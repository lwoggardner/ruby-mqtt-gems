# frozen_string_literal: true

require_relative 'spec_helper'
require 'mqtt/v5'

module MQTT
  module V5
    describe Client::MessageRouter do
      class MockMonitor
        def new_monitor = self
        def synchronize = yield
      end

      let(:monitor) { MockMonitor.new }
      let(:router) { Client::MessageRouter.new(monitor:) }
      let(:subscription_ids) { Client::MessageRouter::SubscriptionIds.new }
      let(:connack) { Packet::Connack.new(session_present: false, subscription_identifiers_available: true) }

      before do
        router.subscription_ids = subscription_ids
        router.connected!(connack)
      end

      def make_sub
        Core::Client::Subscription.new(handler: nil, client: nil)
      end

      describe 'subscription identifier routing' do
        it 'routes PUBLISH with subscription_identifiers to correct subscription' do
          subscribe = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/topic'],
                                            subscription_identifier: 5)
          sub = make_sub

          router.register(subscription: sub, subscribe:)

          publish = Packet::Publish.new(topic_name: 'test/topic', payload: 'test', subscription_identifiers: [5])
          _(router.route(publish)).must_include sub
        end

        it 'routes PUBLISH with multiple subscription_identifiers' do
          subscribe1 = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/#'],
                                             subscription_identifier: 5)
          subscribe2 = Packet::Subscribe.new(packet_identifier: 2, topic_filters: ['test/topic'],
                                             subscription_identifier: 10)

          sub1 = make_sub
          sub2 = make_sub

          router.register(subscription: sub1, subscribe: subscribe1)
          router.register(subscription: sub2, subscribe: subscribe2)

          publish = Packet::Publish.new(topic_name: 'test/topic', payload: 'test', subscription_identifiers: [5, 10])
          subs = router.route(publish)
          _(subs).must_include sub1
          _(subs).must_include sub2
        end

        it 'falls back to trie matching when subscription has no identifier' do
          subscribe = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/#'])
          sub = make_sub

          router.register(subscription: sub, subscribe:)

          publish = Packet::Publish.new(topic_name: 'test/topic', payload: 'test')
          _(router.route(publish)).must_include sub
        end

        it 'cleans up identifier on deregister' do
          subscribe = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/topic'],
                                            subscription_identifier: 5)
          sub = make_sub

          router.register(subscription: sub, subscribe:)

          publish = Packet::Publish.new(topic_name: 'test/topic', payload: 'test', subscription_identifiers: [5])
          _(router.route(publish)).must_include sub

          router.deregister(subscription: sub)
          _(router.route(publish)).wont_include sub
        end

        it 'routes via both id and trie for non-strict mode' do
          # Sub with id
          sub_id = make_sub
          router.register(subscription: sub_id,
                          subscribe: Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/topic'],
                                                           subscription_identifier: 5))

          # Sub without id (goes to trie)
          sub_trie = make_sub
          router.register(subscription: sub_trie,
                          subscribe: Packet::Subscribe.new(packet_identifier: 2, topic_filters: ['test/#']))

          # Publish with id — non-strict should find both
          publish = Packet::Publish.new(topic_name: 'test/topic', payload: 'test', subscription_identifiers: [5])
          subs = router.route(publish)
          _(subs).must_include sub_id
          _(subs).must_include sub_trie
        end

        it 'rejects duplicate identifier' do
          subscribe1 = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/topic'],
                                             subscription_identifier: 5)
          subscribe2 = Packet::Subscribe.new(packet_identifier: 2, topic_filters: ['other/topic'],
                                             subscription_identifier: 5)

          router.register(subscription: make_sub, subscribe: subscribe1)
          _ { router.register(subscription: make_sub, subscribe: subscribe2) }.must_raise MQTT::Error
        end

        it 'handles broker not supporting identifiers' do
          connack_no_ids = Packet::Connack.new(session_present: false, subscription_identifiers_available: false)
          router.connected!(connack_no_ids)

          subscribe = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/#'])
          sub = make_sub
          router.register(subscription: sub, subscribe:)

          publish = Packet::Publish.new(topic_name: 'test/topic', payload: 'test')
          _(router.route(publish)).must_include sub
        end

        it 'handles exact topic match with identifier' do
          subscribe = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/topic'],
                                            subscription_identifier: 5)
          sub = make_sub
          router.register(subscription: sub, subscribe:)

          publish = Packet::Publish.new(topic_name: 'test/topic', payload: 'test', subscription_identifiers: [5])
          _(router.route(publish)).must_include sub
        end

        it 'handles wildcard filter with identifier' do
          subscribe = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/+/topic'],
                                            subscription_identifier: 5)
          sub = make_sub
          router.register(subscription: sub, subscribe:)

          publish = Packet::Publish.new(topic_name: 'test/foo/topic', payload: 'test', subscription_identifiers: [5])
          _(router.route(publish)).must_include sub
        end

        it 'handles duplicate filter with different identifiers and releases both' do
          subscribe1 = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['test/topic'],
                                             subscription_identifier: 5)
          subscribe2 = Packet::Subscribe.new(packet_identifier: 2, topic_filters: ['test/topic'],
                                             subscription_identifier: 10)

          sub1 = make_sub
          sub2 = make_sub
          router.register(subscription: sub1, subscribe: subscribe1)
          router.register(subscription: sub2, subscribe: subscribe2)

          publish = Packet::Publish.new(topic_name: 'test/topic', payload: 'test', subscription_identifiers: [5, 10])
          subs = router.route(publish)
          _(subs).must_include sub1
          _(subs).must_include sub2

          # Deregister both — must release BOTH ids
          router.deregister(subscription: sub1)
          router.deregister(subscription: sub2)

          # Both ids are free — can be reused without "already in use" error
          sub3 = make_sub
          router.register(subscription: sub3,
                          subscribe: Packet::Subscribe.new(packet_identifier: 3,
                                                           topic_filters: ['a'], subscription_identifier: 5))
          router.register(subscription: sub3,
                          subscribe: Packet::Subscribe.new(packet_identifier: 4,
                                                           topic_filters: ['b'], subscription_identifier: 10))
        end

        it 'releases all ids when subscription has multiple ids' do
          sub = make_sub
          subscribe1 = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['topic/a'],
                                             subscription_identifier: 5)
          subscribe2 = Packet::Subscribe.new(packet_identifier: 2, topic_filters: ['topic/b'],
                                             subscription_identifier: 10)
          router.register(subscription: sub, subscribe: subscribe1)
          router.register(subscription: sub, subscribe: subscribe2)

          # Deregister all — both ids should be released
          router.deregister(subscription: sub)

          # Both ids are now free — can be reused without error
          sub2 = make_sub
          router.register(subscription: sub2,
                          subscribe: Packet::Subscribe.new(packet_identifier: 3,
                                                           topic_filters: ['x'], subscription_identifier: 5))
          router.register(subscription: sub2,
                          subscribe: Packet::Subscribe.new(packet_identifier: 4,
                                                           topic_filters: ['y'], subscription_identifier: 10))
        end

        it 'partial deregister releases only affected id' do
          sub = make_sub
          subscribe1 = Packet::Subscribe.new(packet_identifier: 1, topic_filters: ['topic/a'],
                                             subscription_identifier: 5)
          subscribe2 = Packet::Subscribe.new(packet_identifier: 2, topic_filters: ['topic/b'],
                                             subscription_identifier: 10)
          router.register(subscription: sub, subscribe: subscribe1)
          router.register(subscription: sub, subscribe: subscribe2)

          # Partial deregister — only topic/a
          router.deregister('topic/a', subscription: sub)

          # id 5 released, id 10 still active
          publish_b = Packet::Publish.new(topic_name: 'topic/b', payload: 'test', subscription_identifiers: [10])
          _(router.route(publish_b)).must_include sub

          publish_a = Packet::Publish.new(topic_name: 'topic/a', payload: 'test', subscription_identifiers: [5])
          _(router.route(publish_a)).wont_include sub

          # id 5 is free — can be reused
          sub2 = make_sub
          router.register(subscription: sub2,
                          subscribe: Packet::Subscribe.new(packet_identifier: 3,
                                                           topic_filters: ['x'], subscription_identifier: 5))

          # id 10 still locked
          _ { router.register(subscription: sub2, subscribe: Packet::Subscribe.new(packet_identifier: 4, topic_filters: ['y'], subscription_identifier: 10)) }
            .must_raise MQTT::Error
        end

        it 'does not route to unmatched filters sharing the same id' do
          sub1 = make_sub
          # id=5 covers home/# and stats/#
          router.register(subscription: sub1,
                          subscribe: Packet::Subscribe.new(packet_identifier: 1,
                                                           topic_filters: %w[home/# stats/#],
                                                           subscription_identifier: 5))
          # sub2 only on stats/#, re-subscribed with id=10
          sub2 = make_sub
          router.register(subscription: sub2,
                          subscribe: Packet::Subscribe.new(packet_identifier: 2,
                                                           topic_filters: ['stats/#'],
                                                           subscription_identifier: 10))

          # Message for home/temp with id=5 — should route to sub1 only (via home/#)
          # stats/# doesn't match home/temp, so sub2 should NOT receive it
          publish = Packet::Publish.new(topic_name: 'home/temp', payload: 'test', subscription_identifiers: [5])
          result = router.route(publish)
          _(result).must_include sub1
          _(result).wont_include sub2
        end

        it 'flushes stale id mappings after message confirms current id' do
          sub1 = make_sub
          router.register(subscription: sub1,
                          subscribe: Packet::Subscribe.new(packet_identifier: 1,
                                                           topic_filters: ['stats/#'],
                                                           subscription_identifier: 5))
          # Re-subscribe same filter with new id
          sub2 = make_sub
          router.register(subscription: sub2,
                          subscribe: Packet::Subscribe.new(packet_identifier: 2,
                                                           topic_filters: ['stats/#'],
                                                           subscription_identifier: 10))

          # Message with new id confirms transition — flushes old id=5 from stats/#
          router.route(Packet::Publish.new(topic_name: 'stats/cpu', payload: 'x', subscription_identifiers: [10]))

          # id 5 should now be free (no remaining filters)
          sub3 = make_sub
          router.register(subscription: sub3,
                          subscribe: Packet::Subscribe.new(packet_identifier: 3,
                                                           topic_filters: ['other'], subscription_identifier: 5))
        end
      end
    end
  end
end
