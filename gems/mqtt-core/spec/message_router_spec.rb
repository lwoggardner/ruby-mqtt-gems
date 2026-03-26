# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/core/client/message_router'
require_relative '../lib/mqtt/core/client/subscription'

module MQTT
  module Core
    class Client
      describe MessageRouter do
        class MockMonitor
          def new_monitor = self
          def synchronize = yield
        end

        MockPublish = Struct.new(:topic_name, :payload, :qos, keyword_init: true) do
          def initialize(topic_name:, payload: '', qos: 0) = super
        end

        MockSubscribe = Struct.new(:filters, keyword_init: true) do
          def subscribed_topic_filters(_suback = nil) = filters
        end

        let(:monitor) { MockMonitor.new }
        let(:router) { MessageRouter.new(monitor:) }

        def make_sub
          Subscription.new(client: nil, handler: nil)
        end

        describe '#register and #route' do
          it 'routes exact topic to registered subscription' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: ['test/topic']))

            result = router.route(MockPublish.new(topic_name: 'test/topic'))
            _(result).must_include sub
          end

          it 'does not route unmatched topic' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: ['test/topic']))

            result = router.route(MockPublish.new(topic_name: 'other/topic'))
            _(result).wont_include sub
          end

          it 'routes wildcard # filter via trie' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: ['test/#']))

            result = router.route(MockPublish.new(topic_name: 'test/foo/bar'))
            _(result).must_include sub
          end

          it 'routes wildcard + filter via trie' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: ['test/+/data']))

            result = router.route(MockPublish.new(topic_name: 'test/sensor/data'))
            _(result).must_include sub
          end

          it 'routes to multiple subscriptions on same filter' do
            sub1 = make_sub
            sub2 = make_sub
            subscribe = MockSubscribe.new(filters: ['test/topic'])
            router.register(subscription: sub1, subscribe:)
            router.register(subscription: sub2, subscribe:)

            result = router.route(MockPublish.new(topic_name: 'test/topic'))
            _(result).must_include sub1
            _(result).must_include sub2
          end

          it 'deduplicates when subscription matches via both exact and wildcard' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: ['test/topic']))
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: ['test/#']))

            result = router.route(MockPublish.new(topic_name: 'test/topic'))
            _(result.count(sub)).must_equal 1
          end

          it 'merges filters into subscription topic_filters' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: %w[a b]))

            _(sub.topic_filters).must_include 'a'
            _(sub.topic_filters).must_include 'b'
          end

          it 'returns only new filters' do
            sub = make_sub
            new1 = router.register(subscription: sub, subscribe: MockSubscribe.new(filters: %w[a b]))
            _(new1).must_equal %w[a b]

            new2 = router.register(subscription: sub, subscribe: MockSubscribe.new(filters: %w[b c]))
            _(new2).must_equal ['c']
          end
        end

        describe '#deregister' do
          it 'removes subscription from routing' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: ['test/topic']))
            router.deregister(subscription: sub)

            result = router.route(MockPublish.new(topic_name: 'test/topic'))
            _(result).wont_include sub
          end

          it 'cleans up trie when last subscription for wildcard filter is removed' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: ['test/#']))
            router.deregister(subscription: sub)

            result = router.route(MockPublish.new(topic_name: 'test/foo'))
            _(result).must_be_empty
          end

          it 'returns filters safe to unsubscribe' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: %w[a b]))

            inactive = router.deregister(subscription: sub)
            _(inactive).must_include 'a'
            _(inactive).must_include 'b'
          end

          it 'excludes filters still used by other subscriptions' do
            sub1 = make_sub
            sub2 = make_sub
            router.register(subscription: sub1, subscribe: MockSubscribe.new(filters: ['shared']))
            router.register(subscription: sub2, subscribe: MockSubscribe.new(filters: ['shared']))

            inactive = router.deregister(subscription: sub1)
            _(inactive).wont_include 'shared'

            # sub2 still receives messages
            result = router.route(MockPublish.new(topic_name: 'shared'))
            _(result).must_include sub2
          end

          it 'deregisters only specified filters when given' do
            sub = make_sub
            router.register(subscription: sub, subscribe: MockSubscribe.new(filters: %w[a b]))

            inactive = router.deregister('a', subscription: sub)
            _(inactive).must_equal ['a']

            # 'b' still routes
            _(router.route(MockPublish.new(topic_name: 'b'))).must_include sub
            # 'a' no longer routes
            _(router.route(MockPublish.new(topic_name: 'a'))).wont_include sub
          end
        end

        describe '#clear' do
          it 'returns all subscriptions and resets' do
            sub1 = make_sub
            sub2 = make_sub
            router.register(subscription: sub1, subscribe: MockSubscribe.new(filters: ['a']))
            router.register(subscription: sub2, subscribe: MockSubscribe.new(filters: ['b']))

            all = router.clear
            _(all).must_include sub1
            _(all).must_include sub2

            # After clear, routing returns nothing
            _(router.route(MockPublish.new(topic_name: 'a'))).must_be_empty
          end
        end
      end
    end
  end
end
