# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/core/client/message_router'

module MQTT
  module Core
    class Client
      describe MessageRouter::Trie do
        let(:trie) { MessageRouter::Trie.new }

      describe '#add' do
        it 'adds a simple topic filter' do
          trie.add('sensor/temp')
          _(trie.empty?).must_equal false
        end

        it 'adds filters with single-level wildcards' do
          trie.add('sensor/+/temp')
          _(trie.match('sensor/123/temp')).must_include 'sensor/+/temp'
        end

        it 'adds filters with multi-level wildcards' do
          trie.add('sensor/#')
          _(trie.match('sensor/123/temp')).must_include 'sensor/#'
        end
      end

      describe '#match' do
        it 'matches exact topic filters' do
          trie.add('sensor/temp')
          _(trie.match('sensor/temp')).must_equal ['sensor/temp']
        end

        it 'does not match different topics' do
          trie.add('sensor/temp')
          _(trie.match('sensor/humidity')).must_be_empty
        end

        it 'matches single-level wildcard +' do
          trie.add('sensor/+/temp')
          _(trie.match('sensor/123/temp')).must_include 'sensor/+/temp'
          _(trie.match('sensor/456/temp')).must_include 'sensor/+/temp'
        end

        it 'does not match + across multiple levels' do
          trie.add('sensor/+/temp')
          _(trie.match('sensor/123/456/temp')).wont_include 'sensor/+/temp'
        end

        it 'matches multi-level wildcard # at end' do
          trie.add('sensor/#')
          _(trie.match('sensor/temp')).must_include 'sensor/#'
          _(trie.match('sensor/123/temp')).must_include 'sensor/#'
          _(trie.match('sensor/123/456/temp')).must_include 'sensor/#'
        end

        it 'does not match # before the filter position' do
          trie.add('sensor/#')
          _(trie.match('other/temp')).wont_include 'sensor/#'
        end

        it 'matches multiple overlapping filters' do
          trie.add('sensor/+/temp')
          trie.add('sensor/#')
          trie.add('sensor/123/temp')

          matches = trie.match('sensor/123/temp')
          _(matches).must_include 'sensor/+/temp'
          _(matches).must_include 'sensor/#'
          _(matches).must_include 'sensor/123/temp'
        end

        it 'handles complex wildcard patterns' do
          trie.add('+/+/temp')
          trie.add('sensor/+/#')
          trie.add('#')

          matches = trie.match('sensor/123/temp')
          _(matches).must_include '+/+/temp'
          _(matches).must_include 'sensor/+/#'
          _(matches).must_include '#'
        end

        it 'returns empty array when no matches' do
          trie.add('sensor/temp')
          _(trie.match('other/humidity')).must_be_empty
        end
      end

      describe '#remove' do
        it 'removes a topic filter' do
          trie.add('sensor/temp')
          trie.remove('sensor/temp')
          _(trie.match('sensor/temp')).must_be_empty
        end

        it 'removes wildcard filters' do
          trie.add('sensor/+/temp')
          trie.remove('sensor/+/temp')
          _(trie.match('sensor/123/temp')).must_be_empty
        end

        it 'keeps other filters when removing one' do
          trie.add('sensor/+/temp')
          trie.add('sensor/#')
          trie.remove('sensor/+/temp')

          _(trie.match('sensor/123/temp')).must_equal ['sensor/#']
        end

        it 'handles removing non-existent filter' do
          trie.add('sensor/temp')
          trie.remove('other/temp')
          _(trie.match('sensor/temp')).must_equal ['sensor/temp']
        end

        it 'cleans up empty nodes' do
          trie.add('sensor/temp')
          trie.remove('sensor/temp')
          _(trie.empty?).must_equal true
        end

        it 'handles re-adding same filter (idempotent)' do
          trie.add('sensor/temp')
          trie.add('sensor/temp')
          
          # Should still match once
          matches = trie.match('sensor/temp')
          _(matches).must_equal ['sensor/temp']
          
          # Remove once should remove it
          trie.remove('sensor/temp')
          _(trie.match('sensor/temp')).must_be_empty
        end
      end

      describe 'MQTT spec compliance' do
        it 'handles topic levels correctly' do
          trie.add('sport/tennis/player1')
          trie.add('sport/tennis/+')
          trie.add('sport/+')
          trie.add('+/+')
          trie.add('#')

          # Exact match
          matches = trie.match('sport/tennis/player1')
          _(matches).must_include 'sport/tennis/player1'
          _(matches).must_include 'sport/tennis/+'
          _(matches).must_include '#'
          _(matches.size).must_equal 3

          # Different player
          matches = trie.match('sport/tennis/player2')
          _(matches).must_include 'sport/tennis/+'
          _(matches).must_include '#'
          _(matches).wont_include 'sport/tennis/player1'
        end

        it 'handles # wildcard at different positions' do
          trie.add('sport/#')
          trie.add('sport/tennis/#')

          matches = trie.match('sport/tennis/player1')
          _(matches).must_include 'sport/#'
          _(matches).must_include 'sport/tennis/#'
        end

        it 'handles empty topic levels' do
          trie.add('sensor//temp')
          _(trie.match('sensor//temp')).must_include 'sensor//temp'
          _(trie.match('sensor/123/temp')).wont_include 'sensor//temp'
        end
      end
    end
  end
  end
end
