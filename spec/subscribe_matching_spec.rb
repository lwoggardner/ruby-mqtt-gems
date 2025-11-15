# frozen_string_literal: true

require_relative 'spec_helper'
require 'mqtt/v3'
require 'mqtt/v5'

module MQTT
  module SubscribeMatchingSpec
    def self.included(spec)
      spec.class_eval do
        describe 'topic matching' do
          let(:sub) { subscribe_class.new(packet_identifier: 1, topic_filters: ['test/topic', 'foo/#', 'bar/+/baz']) }

          it 'matches exact topic' do
            _(sub.match_topic?('test/topic')).must_equal(true)
          end

          it 'matches wildcard #' do
            _(sub.match_topic?('foo/bar/baz')).must_equal(true)
            _(sub.match_topic?('foo/x')).must_equal(true)
            _(sub.match_topic?('foo/a/b/c/d')).must_equal(true)
          end

          it 'matches wildcard +' do
            _(sub.match_topic?('bar/x/baz')).must_equal(true)
            _(sub.match_topic?('bar/anything/baz')).must_equal(true)
          end

          it 'does not match different topic' do
            _(sub.match_topic?('other/topic')).must_equal(false)
            _(sub.match_topic?('bar/x/y/baz')).must_equal(false)
          end

          it 'matches publish packet' do
            pub = publish_class.new(topic_name: 'test/topic', payload: 'data', qos: 0)
            _(sub.match?(pub)).must_equal(true)
          end

          it 'does not match non-matching publish packet' do
            pub = publish_class.new(topic_name: 'other/topic', payload: 'data', qos: 0)
            _(sub.match?(pub)).must_equal(false)
          end

          it 'matches with === operator' do
            _(sub === 'test/topic').must_equal(true)
            _(sub === 'foo/bar').must_equal(true)
            _(sub === 'other').must_equal(false)
          end

          it 'matches any filter in multiple filters' do
            _(sub.match_topic?('test/topic')).must_equal(true)
            _(sub.match_topic?('foo/anything')).must_equal(true)
            _(sub.match_topic?('bar/mid/baz')).must_equal(true)
          end

          it 'does not match when no filter matches' do
            _(sub.match_topic?('test/other')).must_equal(false)
            _(sub.match_topic?('bar/baz')).must_equal(false)
            _(sub.match_topic?('baz/x/bar')).must_equal(false)
          end
        end

        describe 'wildcard edge cases' do
          it 'matches # at root level' do
            sub = subscribe_class.new(packet_identifier: 1, topic_filters: ['#'])
            _(sub.match_topic?('anything')).must_equal(true)
            _(sub.match_topic?('a/b/c')).must_equal(true)
          end

          it 'matches + in multiple positions' do
            sub = subscribe_class.new(packet_identifier: 1, topic_filters: ['+/+/+'])
            _(sub.match_topic?('a/b/c')).must_equal(true)
            _(sub.match_topic?('x/y/z')).must_equal(true)
            _(sub.match_topic?('a/b')).must_equal(false)
            _(sub.match_topic?('a/b/c/d')).must_equal(false)
          end

          it 'matches mixed wildcards' do
            sub = subscribe_class.new(packet_identifier: 1, topic_filters: ['sensor/+/#'])
            _(sub.match_topic?('sensor/temp/room1')).must_equal(true)
            _(sub.match_topic?('sensor/temp/room1/value')).must_equal(true)
            _(sub.match_topic?('sensor/humidity')).must_equal(true)
            _(sub.match_topic?('device/temp')).must_equal(false)
          end

          it 'does not match + across slashes' do
            sub = subscribe_class.new(packet_identifier: 1, topic_filters: ['a/+/c'])
            _(sub.match_topic?('a/b/c')).must_equal(true)
            _(sub.match_topic?('a/b/x/c')).must_equal(false)
          end
        end
      end
    end
  end
end

MQTT::SpecHelper.protocol_version_spec(MQTT::SubscribeMatchingSpec)
