# frozen_string_literal: true

require_relative 'spec_helper'
require 'mqtt/v3'
require 'mqtt/v5'

module MQTT
  module SubscribeMatchingSpec
    def self.included(spec)
      spec.class_eval do
        describe 'topic matching' do
          let(:filters) { ['test/topic', 'foo/#', 'bar/+/baz'] }

          it 'matches exact topic' do
            _(Core::Client::Subscription::Filters.match_topic?('test/topic', filters)).must_equal(true)
          end

          it 'matches wildcard #' do
            _(Core::Client::Subscription::Filters.match_topic?('foo/bar/baz', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('foo/x', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('foo/a/b/c/d', filters)).must_equal(true)
          end

          it 'matches wildcard +' do
            _(Core::Client::Subscription::Filters.match_topic?('bar/x/baz', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('bar/anything/baz', filters)).must_equal(true)
          end

          it 'does not match different topic' do
            _(Core::Client::Subscription::Filters.match_topic?('other/topic', filters)).must_equal(false)
            _(Core::Client::Subscription::Filters.match_topic?('bar/x/y/baz', filters)).must_equal(false)
          end

          it 'matches any filter in multiple filters' do
            _(Core::Client::Subscription::Filters.match_topic?('test/topic', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('foo/anything', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('bar/mid/baz', filters)).must_equal(true)
          end

          it 'does not match when no filter matches' do
            _(Core::Client::Subscription::Filters.match_topic?('test/other', filters)).must_equal(false)
            _(Core::Client::Subscription::Filters.match_topic?('bar/baz', filters)).must_equal(false)
            _(Core::Client::Subscription::Filters.match_topic?('baz/x/bar', filters)).must_equal(false)
          end
        end

        describe 'wildcard edge cases' do
          it 'matches # at root level' do
            filters = ['#']
            _(Core::Client::Subscription::Filters.match_topic?('anything', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('a/b/c', filters)).must_equal(true)
          end

          it 'matches + in multiple positions' do
            filters = ['+/+/+']
            _(Core::Client::Subscription::Filters.match_topic?('a/b/c', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('x/y/z', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('a/b', filters)).must_equal(false)
            _(Core::Client::Subscription::Filters.match_topic?('a/b/c/d', filters)).must_equal(false)
          end

          it 'matches mixed wildcards' do
            filters = ['sensor/+/#']
            _(Core::Client::Subscription::Filters.match_topic?('sensor/temp/room1', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('sensor/temp/room1/value', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('sensor/humidity', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('device/temp', filters)).must_equal(false)
          end

          it 'does not match + across slashes' do
            filters = ['a/+/c']
            _(Core::Client::Subscription::Filters.match_topic?('a/b/c', filters)).must_equal(true)
            _(Core::Client::Subscription::Filters.match_topic?('a/b/x/c', filters)).must_equal(false)
          end
        end
      end
    end
  end
end

MQTT::SpecHelper.protocol_version_spec(MQTT::SubscribeMatchingSpec)
