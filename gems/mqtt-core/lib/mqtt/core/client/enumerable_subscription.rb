# frozen_string_literal: true

require_relative 'subscription'

module MQTT
  module Core
    class Client
      # Enumerable subscription supporting iteration over received messages
      #
      # Method variants
      #
      #   - methods with aliases suffixed `messages` yield deconstructed topic, payload, and attributes
      #   - methods suffixed with `packets` yield raw `PUBLISH` packets
      #   - methods prefixed with `async` perform enumeration in a new thread
      #   - methods suffixed with bang `!` ensure {#unsubscribe}
      #   - methods prefixed with `lazy` return lazy enumerators for advanced chaining
      #
      class EnumerableSubscription < Subscription
        include Enumerable

        # @!visibility private
        def put(packet)
          handler.enqueue(packet)
        end

        # @!macro [new] yield_messages
        #   @yield [topic, payload, **attributes]
        #   @yieldparam [String] topic the message topic.
        #   @yieldparam [String] payload the message payload.
        #   @yieldparam [Hash<Symbol>] attributes additional `PUBLISH` packet attributes.
        #   @yieldreturn [$0]

        # @!macro [new] yield_packets
        #   @yield [packet]
        #   @yieldparam [Packet] packet a `PUBLISH` packet.
        #   @yieldreturn [$0]

        # @!macro [new] enum_return
        #   @return [void] when block given
        #   @return [Enumerator] an enumerator when no block given.

        # @!macro [new] lazy_enum_return
        #   @return [void] when block given
        #   @return [Enumerator::Lazy] a lazy enumerator when no block given.

        # @!macro [new] async_return
        #   @return [self, ConcurrentMonitor::Task]
        #     a pair containing self and the task that is iterating over the messages.

        # @!macro [new] qos_note
        #   @note QoS 1/2 packets are marked as completely handled in the session store when the given block completes.
        #     If no block is given, completion is marked *before* the packet is returned.

        # Get one packet, blocking until available
        #
        # @!macro qos_note
        # @!macro yield_packets(Object)
        # @return [Packet] a `PUBLISH` packet when no block given
        # @return [Object] the block result when block given
        # @return [nil] when unsubscribed or disconnected
        def get_packet(&)
          handle(handler.dequeue, &)
        end

        # Get one message, blocking until available
        #
        # @!macro qos_note
        # @!macro yield_messages(Object)
        # @return [String, String, Hash<Symbol>] topic, payload, and attributes when no block given
        # @return [Object] the block result when block given
        # @return [nil] when unsubscribed or disconnected
        def get(&)
          get_packet { |pkt| pkt.deconstruct_message(&) }
        end
        alias get_message get

        # Read one packet, blocking until available, for use in loops
        # @!macro yield_packets(Object)
        # @return [Packet] a `PUBLISH` packet when no block given
        # @return [Object] the block result when block given
        # @raise [StopIteration] when unsubscribed or disconnected
        def read_packet(&)
          get_packet do |packet|
            raise StopIteration unless packet

            block_given? ? yield(packet) : packet
          end
        end

        # Read one message, blocking until available, for use in loops
        # @!macro yield_messages(Object)
        # @return [String, String, Hash<Symbol>] topic, payload, and attributes when no block given
        # @return [Object] the block result when block given
        # @raise [StopIteration] when unsubscribed or disconnected
        def read(&)
          read_packet { |pkt| pkt.deconstruct_message(&) }
        end
        alias read_message read

        # Enumerate packets
        # @!macro yield_packets(void)
        # @!macro enum_return
        def each_packet(&)
          return enum_for(__method__) unless block_given?

          loop { read_packet(&) }
        end

        # Enumerate packets, ensuring {#unsubscribe}
        # @!macro yield_packets(void)
        # @!macro enum_return
        def each_packet!(&) = enum_for!(__method__, &)

        # Enumerate messages
        # @!macro yield_messages(void)
        # @!macro enum_return
        def each
          return enum_for(__method__) unless block_given?

          each_packet { |pkt| yield(*pkt.deconstruct_message) }
        end

        alias each_message each

        # Enumerate messages, ensuring {#unsubscribe}
        # @!macro yield_messages(void)
        # @!macro enum_return
        def each!(&) = enum_for!(__method__, &)
        alias each_message! each!

        # Return a lazy enumerator for advanced chaining
        # @return [Enumerator::Lazy<String, String, Hash>] lazy enumerator yielding [topic, payload, **attributes]
        # @example
        #   sub.lazy.select { |t, p| p.size > 100 }.map { |t, p| JSON.parse(p) }.take(5)
        def lazy
          each.lazy
        end
        alias lazy_messages lazy

        # Return a lazy enumerator ensuring {#unsubscribe}
        # @return [Enumerator::Lazy<String, String, Hash>] lazy enumerator yielding [topic, payload, **attributes]
        # @example
        #   sub.lazy!.select { |t, p| p.size > 100 }.map { |t, p| JSON.parse(p) }.take(5)
        def lazy!
          each!.lazy
        end
        alias lazy_messages! lazy!

        # Return a lazy packet enumerator for advanced chaining
        # @return [Enumerator::Lazy<Packet>] lazy enumerator yielding PUBLISH packets
        def lazy_packets
          each_packet.lazy
        end

        # Return a lazy packet enumerator with auto-unsubscribe
        # @return [Enumerator::Lazy<Packet>] lazy enumerator yielding PUBLISH packets
        def lazy_packets!
          each_packet!.lazy
        end

        # Enumerate messages in a new thread
        # @overload async(&)
        # @!macro yield_messages(void)
        # @!macro async_return
        # @see each
        def async(method = :each, &)
          raise ArgumentError, 'block is required for async enumeration' unless block_given?

          [self, client.async("sub.#{method}") { send(method, &) }]
        end
        alias async_messages async

        # Enumerate messages in a new thread, ensuring {#unsubscribe}
        # @!macro yield_messages(void)
        # @!macro async_return
        # @see each!
        def async!(&) = async(:each!, &)
        alias async_messages! async!

        # Enumerate packets in a new thread
        # @!macro yield_packets(void)
        # @!macro async_return
        # @see each_packet
        def async_packets(&) = async(:each_packet, &)

        # Enumerate packets in a new thread, ensuring {#unsubscribe}
        # @!macro yield_packets(void)
        # @!macro async_return
        # @see each_packet!
        def async_packets!(&) = async(:each_packet!, &)

        # Delegates Enumerable methods ending in `!` to {#each!}, ensuring {#unsubscribe}
        #
        # @note Methods that require consuming the entire enumerable (e.g., `map`, `select`)
        #   will block indefinitely on an infinite subscription stream unless combined with
        #   limiting methods like `take` or terminated by a `break` condition.
        #
        # @example
        #   sub.take!(5)             # => Array of 5 messages, then unsubscribes
        #   sub.first!               # => First message, then unsubscribes
        #   sub.find! { |t, p| ... } # => Matching message, then unsubscribes
        def method_missing(method, *, &)
          if method.end_with?('!') && Enumerable.public_instance_methods.include?(method[..-2].to_sym)
            each!.public_send(method[..-2], *, &)
          else
            super
          end
        end

        private

        def respond_to_missing?(method, include_private = false)
          (method.end_with?('!') && Enumerable.public_instance_methods.include?(method[..-2].to_sym)) || super
        end

        def enum_for!(method, &)
          return enum_for(method) unless block_given?

          with! { send(method[..-2], &) }
        end
      end
    end
  end
end
