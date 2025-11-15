# frozen_string_literal: true

module MQTT
  module QoSReliability
    # Network Failure Controller - Injects network disruptions
    class NetworkController
      def initialize
        @handlers = Hash.new { |h, k| h[k] = [] }
        @retriables = {}
      end

      def clear
        @handlers.clear
        @retriables.clear
      end

      def delay_on_receive(delay, packet_name, **options)
        delay_on(:receive, delay, packet_name, **options)
      end

      def raise_on_receive(packet_name, **options, &raiser)
        raise_on(:receive, packet_name, **options, &raiser)
      end

      def delay_on_send(delay, packet_name, **options)
        delay_on(:send, delay, packet_name, **options)
      end

      def raise_on_send(packet_name, **options, &raiser)
        raise_on(:send, packet_name, **options, &raiser)
      end

      def send(packet)
        call(:send, packet)
      end

      def receive(packet)
        call(:receive, packet)
      end

      def retry_error(delay: 0.1, count: 0, error: EOFError)
        @retriables[error] = { count:, delay: }
      end

      def disconnect(count, &raiser)
        raiser.call
      rescue *@retriables.keys => e
        retriable = @retriables[e.class]

        if count > retriable[:count]
         sleep retriable[:delay]
        end

      end

      private

      def call(direction, packet)
        @handlers[direction].each(&:call)
      end

      def delay_on(direction, delay, packet_name, **options)
        @handlers[direction] << ->(packet) do
          next unless match?(packet, packet_name, **options)
          sleep delay
        end
      end

      def raise_on(direction, packet_name, error: EOFError, **options)
        @handlers[direction] << ->(packet) do
          next unless match?(packet, packet_name, **options)

          raise error, "Network connection lost"
        end
      end

      def match?(packet, packet_name, **options)
        packet&.packet_name == packet_name && options.all? { |k, v| packet.send(k) == v }
      end
    end
  end
end
