# frozen_string_literal: true

require 'pathname'
require 'tmpdir'
require 'tempfile'
require 'fileutils'
require_relative 'qos2_session_store'
module MQTT
  module Core
    class Client
      # A Session Store that holds packets in the filesystem.
      class FilesystemSessionStore < Qos2SessionStore
        attr_reader :client_dir, :base_dir, :session_expiry_file

        # @param [String] base_dir the base directory to store session files in
        # @param [String|nil] client_id
        #   empty string is not permitted, but nil can be used to force the generation of a random id.
        # @param [Integer|nil] expiry_interval
        #   zero is not permitted, but nil represents never expire (server may negotiate a lower value)
        def initialize(client_id:, expiry_interval:, base_dir: Dir.mktmpdir('mqtt'))
          @base_dir = Pathname.new(base_dir)
          @client_dir = (base_dir + client_id)
          super(client_id:, expiry_interval:)

          @session_expiry_file = (base_dir + "#{client_id}.expiry")
          cleanup_tmp
          log.info { "client_dir: #{@client_dir}, clean?: #{clean?}" }
        end

        def restart_clone
          self.class.new(base_dir, client_id:, expiry_interval:)
        end

        def clean?
          !client_dir.exist?
        end

        def connected!
          client_dirs.each(&:mkpath)

          # record the previous session expiry duration so we can check it on a future restart
          session_expiry_file.open('w') { |f| f.write(expiry_interval.to_s) }
        end

        def disconnected!
          session_expiry_file.utime(nil, nil) # now
        end

        def expired?
          return false unless session_expiry_file.exist?

          # choose the most recent of...
          #   * the directory modification times (updated each time a packet file is added or removed),
          #   * the session_expiry_file modification time (updated on disconnect)
          # A hard crash without a clean disconnect will potentially expire a session earlier than the server
          Time.now - (client_dirs + [session_expiry_file]).map(&:mtime).max > session_expiry_file.read.to_i
        end

        def store_packet(packet, replace: false)
          raise KeyError, 'packet id already exists' if !replace && stored_packet?(packet.id)

          packet_file(packet.id).open('wb') { |f| packet.serialize(f) }
        end

        def delete_packet(id)
          packet_file(id).delete
        end

        def stored_packet?(id)
          packet_file(id).exist?
        end

        def retry_packets(&)
          @client_dir.glob('pkt.*').sort_by(&:mtime).map { |f| f.open('r', &) }
        end

        def packet_file(id)
          @client_dir + format('pkt/%04x.mqtt', id)
        end

        # QOS Receive
        # Unique ID is sortable (fixed width timestamp)
        # qos1 live:      `/#{client_id}/qos1/#{unique_id}_#{packet_id}.live` write on PUBLISH, deleted on handled.
        # qos2 live:      `/#{client_id}/qos2/#{unique_id}_#{packet_id}.live` (unhandled, unreleased)
        # qos2 handled:   `/#{client_id}/qos2/#{unique_id}_#{packet_id}.handled` (handled, unreleased)
        # qos2 released:  `/#{client_id}/qos2/#{unique_id}_#{packet_id}.released` (unhandled, released)
        # qos2 replay:    '/#{client_id}/qos2/#{unique_id}_#{packet_id}.replay_[live|handled]

        # TODO: Recover utility
        #    * cleanup_tmp
        #    * qos2/*.live     - rename to .replay_live or .handled
        #    * qos2/*.released - rename to .replay_released or delete

        def store_qos_received(packet, unique_id)
          client_dir + qos_path(packet.qos, packet.id, unique_id).tap do |live_file|
            tmp_file = live_file.sub_ext('live', 'tmp')
            tmp_file.open('wb') { |f| packet.serialize(f) }
            tmp_file.rename(live_file)
          end
        end

        # Release the pending qos2 (return true if we had previously seen it)
        def qos2_release(id)
          qos2_live = find_qos2_file(id)

          if qos2_live&.extname == '.live'
            qos2_live.rename(qos2_live.sub_ext('.live', '.released'))
          else
            qos2_live&.delete
          end

          super
        rescue Errno::ENOENT
          retry
        end

        def qos_handled(packet, unique_id)
          if packet.qos == 1
            qos1_handled(packet, unique_id)
          elsif packet.qos == 2
            qos2_handled(packet, unique_id)
          end
        end

        # Called once at initialize.
        # rubocop:disable Metrics/AbcSize
        def qos2_recover
          # Abort if there are unmarked files to potentially replay
          if (client_dir.glob('qos2/*.live') + client_dir.glob('qos2/*.released')).any?
            raise SessionNotRecoverable, "Unhandled QOS2 messages in #{"#{client_dir}/qos2"}. Run recover utility"
          end

          client_dir.glob('qos2/*.replay_live').each { |q2| q2.rename(q2.sub_ext('.live')) }
          client_dir.glob('qos2/*.replay_released').each { |q2| q2.rename(q2.sub_ext('.released')) }

          client_dir.glob(%w[qos2/*.live qos2/*.handled]).map { |f| f.basename.to_s.split('_').last.to_i(16) }
        end
        # rubocop:enable Metrics/AbcSize

        # Load the unhandled packets with their unique id, only called once per session store
        def qos_unhandled_packets(&)
          client_dir.glob(%w[qos?/*.live qos2/*.released]).sort_by(&:basename)
                    .to_h { |f| [f.open('r', &), f.basename.to_s.split('_').first] }
        end

        private

        def cleanup_tmp
          # Cleanup crashed .tmp files
          client_dir.glob('qos?/*.tmp').each(&:delete)
        end

        # Make directories.
        #   pkt  - packets we are sending, waiting to be acked
        #   qos1 - qos1 packets received, waiting to be handled
        #   qos2 - qos2 packets received, waiting to be released and handled
        def client_dirs
          %w[pkt qos1 qos2].map { |d| client_dir + d }
        end

        def qos2_handled(packet, unique_id)
          live_file = client_dir + qos_path(2, packet.id, unique_id)
          rel_file = client_dir + qos_path(2, packet.id, unique_id, 'released')

          live_file.rename(live_file.sub_ext('.handled')) if live_file.exist?
          rel_file.unlink if rel_file.exist?
        rescue Errno::ENOENT
          retry
        end

        def qos1_handled(packet, unique_id)
          live_file = (client_dir + qos_path(1, packet.id, unique_id))
          live_file.unlink
        rescue Errno::ENOENT
          log.warn { "qos_handled: #{live_file} unexpectedly not exists" }
        end

        # @return [String]
        def qos_path(qos, packet_id, unique_id, ext = 'live')
          format('qos%<qos>i/%<unique_id>s_%<packet_id>05x.%<ext>s', qos:, unique_id:, packet_id:, ext:)
        end

        def find_qos2_file(id)
          # search live and handled separately to avoid race while renaming
          live_files = client_dir.glob(qos_path(2, id, '*', 'live'))
          raise ProtocolError, "QOS(#{id}): more than one packet: #{live_files}" if live_files.size > 1
          return live_files.first if live_files.size == 1

          handled_files = client_dir.glob(qos_path(2, id, '*', 'handled'))
          raise ProtocolError, "QOS(#{id}): more than one packet: #{handled_files}" if handled_files.size > 1

          handled_files.first
        end
      end
    end
  end
end
