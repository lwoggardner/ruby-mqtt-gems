# frozen_string_literal: true

require 'mqtt/core/client'
require_relative '../topic_alias'

module MQTT
  module V5
    class Client < MQTT::Core::Client
      # Client protocol for MQTT 5.0
      class Connection < MQTT::Core::Client::Connection # rubocop:disable Metrics/ClassLength
        def initialize(**)
          super
          @qos_send_condition = new_condition
        end

        def publish(qos: 0, topic_alias: true, **publish, &)
          decrement_send_quota if qos.positive?
          topic_alias = topic_alias.positive? if topic_alias.is_a?(Integer)
          publish[:assign_alias] = topic_alias
          begin
            session.publish(qos:, **publish, &)
          rescue StandardError
            increment_send_quota if qos.positive?
            raise
          end
        end

        def send_packet(packet)
          topic_aliases&.handle_outgoing(packet) if packet&.packet_name == :publish
          super
        end

        def disconnect(exception = nil, **disconnect)
          if exception
            disconnect.merge!({ reason_code: 0x04, reason_string: "#{exception.class.name}: #{exception.message}" })
          end

          super(**disconnect)
        end

        def reauthenticate(**auth, &)
          raise ProtocolError, 'Not connected with extended auth' unless @auth

          # reauthenticate sets authentication_method/data in auth data
          send_packet(auth_packet(reason_code: 0x19, **@auth.reauthenticate(**auth)), &)
        end

        private

        def_delegators :session, :clean_start, :session_expiry_interval, :max_packet_id, :stored_packet?, :session_store
        def_delegators :client, :topic_aliases, :auth_ack

        def connect_packet(**connect)
          super.tap do |p|
            @qos_receive_quota = p.receive_maximum || max_packet_id
            topic_aliases&.clear_incoming!(p)
          end
        end

        def connect_data(**connect)
          super.tap { |data| data.merge!(setup_authentication(**connect)) }
        end

        def setup_authentication(authentication_method: nil, **connect)
          return {} unless authentication_method

          @auth = Authenticator.factory(authentication_method)
          @auth.start(authentication_method:, **connect)
        end

        def complete_connection(received_packet)
          super(complete_authentication(received_packet))
        end

        def complete_authentication(packet)
          while packet&.packet_name == :auth
            raise ProtocolError, 'Unexpected auth packet' unless @auth

            packet.continue!

            send_packet(auth_packet(**@auth.continue(**packet.properties.dup)))
            packet = receive_packet
          end
          packet
        end

        def handle_connack(packet)
          super
          @auth&.success(**packet.properties)
          @qos_send_quota = packet.receive_maximum || max_packet_id
          topic_aliases&.clear_outgoing!(packet)
          self.keep_alive = [@keep_alive, packet.server_keep_alive || @keep_alive].min if packet.server_keep_alive
          log.debug { "Connected: Keep alive: #{@keep_alive}, Send quota: #{@qos_send_quota}" }
          true
        rescue BadAuthenticationMethod, NotAuthorized => e
          @auth&.failed(reason_code: e.code, **packet.properties)
          raise
        end

        def handle_auth(packet)
          raise ProtocolError, 'Unexpected auth packet' unless @auth

          case packet.reason_code
          when 0x18 # continue
            push_packet(auth_packet(**@auth.continue(**packet.properties.dup)))
          when 0x00 # success - we only see this on reauthenticate, otherwise it comes in connack
            @auth.success(**packet.properties)
            auth_ack(packet)
          else
            raise UnknownReasonCode, packet.reason_code, 'Unknown reason code for auth packet'
          end
        end

        def auth_packet(reason_code: 0x18, **data)
          # always a continuation from the client
          build_packet(:auth, reason_code:, **data)
        end

        def handle_publish(packet)
          topic_aliases&.handle_incoming(packet)
          decrement_receive_quota if packet.qos.positive?

          super
        rescue ReceiveMaximumExceeded, TopicAliasInvalid => e
          push_packet(disconnect_packet(reason_code: e.reason_code))
        end

        def handle_puback(packet)
          increment_send_quota if stored_packet?(packet.id)
          super
        end

        def handle_pubrec(packet)
          increment_send_quota if packet.failed? && stored_packet?(packet.id)
          super
        end

        def handle_pubcomp(packet)
          increment_send_quota if stored_packet?(packet.id)
          super
        end

        def handle_disconnect(packet)
          super
        rescue NotAuthorized => e
          @auth&.failed(reason_code: e.code, **packet.properties)
        rescue ServerMoved, UseAnotherServer
          handle_server_redirect(packet)
          raise
        end

        # @!visibility private
        def handle_server_redirect(packet)
          # moved temporarily,  moved permanently
          # Followed by a UTF-8 Encoded String which can be used by the Client to identify another Server to use.
          # It is a Protocol Error to include the Server Reference more than once.
          # The Server sends DISCONNECT including a Server Reference and Reason Code 0x9C (Use another server) or 0x9D
          # (Server moved) as described in section 4.13.
          socket_factory.redirect(packet.server_redirect) if socket_factory.respond_to?(:redirect)
        end

        def decrement_receive_quota
          synchronize do
            raise RecieveMaximumExceeded if @qos_receive_quota.zero?

            @qos_receive_quota -= 1
          end
        end

        def increment_receive_quota
          synchronize do
            @qos_receive_quota += 1
          end
        end

        def decrement_send_quota
          synchronize do
            @qos_send_condition.wait_until { @qos_send_quota.positive? }
            @qos_send_quota -= 1
          end
        end

        def increment_send_quota
          synchronize do
            @qos_send_quota += 1
            @qos_send_condition.signal
          end
        end
      end
    end
  end
end
