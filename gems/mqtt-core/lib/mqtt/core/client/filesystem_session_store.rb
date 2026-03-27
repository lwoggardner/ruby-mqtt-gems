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
      #
      # Persists outbound QoS 1/2 packets for retry across process restarts.
      # QoS2 inbound deduplication state (packet ids awaiting PUBREL) is also persisted.
      class FilesystemSessionStore < Qos2SessionStore
        attr_reader :client_dir, :base_dir, :session_expiry_file
        attr_accessor :disconnect_expiry_interval

        # @param [String] base_dir the base directory to store session files in
        # @param [String|nil] client_id
        #   empty string is not permitted, but nil can be used to force the generation of a random id.
        # @param [Integer|nil] expiry_interval
        #   zero is not permitted, but nil represents never expire (server may negotiate a lower value)
        def initialize(client_id:, expiry_interval:, base_dir: Dir.mktmpdir('mqtt'))
          @base_dir = Pathname.new(base_dir)
          @client_dir = (@base_dir + client_id)
          @disconnect_expiry_interval = nil # Default: don't change expiry on disconnect
          super(client_id:, expiry_interval:)

          @session_expiry_file = (@base_dir + "#{client_id}.expiry")
          log.info { "client_dir: #{@client_dir}, clean?: #{clean?}" }
        end

        def restart_clone
          self.class.new(base_dir:, client_id:, expiry_interval:)
        end

        def clean?
          !client_dir.exist?
        end

        def connected!
          pkt_dir.mkpath

          # record the previous session expiry duration so we can check it on a future restart
          session_expiry_file.open('w') { |f| f.write(expiry_interval.to_s) }
        end

        def disconnected!
          session_expiry_file.utime(nil, nil) # now
        end

        def expired?
          return false unless session_expiry_file.exist?

          # choose the most recent of...
          #   * the pkt directory modification time (updated each time a packet file is added or removed),
          #   * the session_expiry_file modification time (updated on disconnect)
          # A hard crash without a clean disconnect will potentially expire a session earlier than the server
          Time.now - [pkt_dir, session_expiry_file].select(&:exist?).map(&:mtime).max > session_expiry_file.read.to_i
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

        # QoS2 inbound deduplication — recover pending packet ids from filenames
        def qos2_recover
          pkt_dir.glob('qos2_*.pending').map { |f| f.basename.to_s[/qos2_([0-9a-f]+)\.pending/, 1].to_i(16) }
        end

        # Mark a QoS2 packet id as pending (received, awaiting PUBREL)
        def qos2_pending(id)
          FileUtils.touch(qos2_pending_file(id))
        end

        # Release a QoS2 packet id (called before sending PUBCOMP)
        def qos2_release(id)
          qos2_pending_file(id).delete
        rescue Errno::ENOENT
          # already released
        end

        private

        def pkt_dir
          @client_dir / 'pkt'
        end

        def qos2_pending_file(id)
          @client_dir + format('pkt/qos2_%04x.pending', id)
        end
      end
    end
  end
end
