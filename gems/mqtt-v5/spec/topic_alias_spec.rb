# frozen_string_literal: true

require_relative 'spec_helper'

module MQTT
  module V5
    module TopicAliasSpec
      def self.included(base)
        base.class_eval do
          describe 'Topic Aliases Integration' do
            it 'negotiates topic alias limits with broker' do
              with_client(topic_alias_send_maximum: 10) do |client|
                client.connect(topic_alias_maximum: 5)
                
                _(client.topic_aliases.incoming).wont_be_nil
                _(client.topic_aliases.incoming.max).must_equal 5
                _(client.topic_aliases.outgoing).wont_be_nil
              end
            end

            it 'publishes with topic aliases' do
              with_client(topic_alias_send_maximum: 10) do |client|
                sent_packets = []
                client.on_send { |pkt| sent_packets << pkt if pkt.respond_to?(:packet_name) && pkt.packet_name == :publish }
                
                client.connect
                
                topic = 'test/topic/aliases/long/name'
                
                # Publish all messages first
                client.publish(topic, 'message1', topic_alias: true)
                client.publish(topic, 'message2', topic_alias: true)
                client.publish(topic, 'message3', topic_alias: false)
                client.publish(topic, 'message3', topic_alias: false)
                client.publish(topic, 'message4')
                
                # Wait for packets to be sent
                sleep 0.01 until sent_packets.size >= 5
                
                # Verify we captured 4 packets
                _(sent_packets.size).must_equal 5
                
                # First publish with topic_alias: true - should assign alias
                _(sent_packets[0].topic_name).must_equal topic
                _(sent_packets[0].topic_alias).must_be :>, 0
                alias_id = sent_packets[0].topic_alias
                
                # Second publish with topic_alias: true - should reuse alias with empty topic
                _(sent_packets[1].topic_name).must_equal ''
                _(sent_packets[1].topic_alias).must_equal alias_id
                
                # Third publish with topic_alias: false - we don't care whether it uses an alias or not

                # Fourth publish with topic_alias:false - won't be aliased (we evicted it last time)
                _(sent_packets[3].topic_name).must_equal topic
                _(sent_packets[3].topic_alias).must_be_nil

                # Fifth publish with topic_alias not set - default is true, assigns new alias
                _(sent_packets[4].topic_name).must_equal topic
                _(sent_packets[4].topic_alias).must_be :>, 0
              end
            end

            it 'receives messages with topic aliases from broker' do
              topic = 'test/topic/alias/receive/with/very/long/name/to/encourage/broker/aliasing'

              with_client(retry_strategy: false) do |client|
                _(client.topic_aliases).wont_be_nil

                client.connect(topic_alias_maximum: 10)
                _(client.topic_aliases.incoming).wont_be_nil
                _(client.topic_aliases.incoming.max).must_equal 10
                
                sub = client.subscribe(topic)

                with_client(session_store: client.class.qos0_store, topic_alias_send_maximum: 10) do |publisher|
                  sent_packets = []
                  publisher.on_send { |pkt| sent_packets << pkt if pkt.respond_to?(:packet_name) && pkt.packet_name == :publish }
                  
                  publisher.connect
                  5.times { |i| publisher.publish(topic, "test #{i}", topic_alias: true) }
                  
                  sleep 0.01 until sent_packets.size >= 5
                  
                  _(sent_packets[0].topic_name).must_equal topic
                  _(sent_packets[0].topic_alias).must_be :>, 0
                  
                  alias_id = sent_packets[0].topic_alias
                  sent_packets[1..4].each do |pkt|
                    _(pkt.topic_name).must_equal ''
                    _(pkt.topic_alias).must_equal alias_id
                  end
                end

                packets = sub.each_packet.take(5)
                _(packets.size).must_equal 5
                packets.each { |pkt| _(pkt.topic_name).must_equal topic }
                
                # Verify broker sent topic aliases (requires max_topic_alias_broker in mosquitto.conf)
                if packets.any? { |pkt| pkt.topic_alias }
                  _(client.topic_aliases.incoming.size).must_equal 1
                  _(packets[0].topic_alias).must_be :>, 0
                  _(packets[0].orig_topic_name).must_equal topic
                  alias_id = packets[0].topic_alias
                  packets[1..4].each do |pkt|
                    _(pkt.topic_alias).must_equal alias_id
                    _(pkt.orig_topic_name).must_equal ''
                  end
                else
                  skip "Broker not sending topic aliases - requires mosquitto 2.1+ with max_topic_alias_broker"
                end
              end
            end

            it 'handles zero topic alias maximum (disabled)' do
              with_client(topic_alias_send_maximum: 0) do |client|
                client.connect(topic_alias_maximum: 0)
                
                _(client.topic_aliases.incoming).must_be_nil
                _(client.topic_aliases.outgoing).must_be_nil
                
                client.publish('test/topic', 'message')
              end
            end
          end
        end
      end
    end
  end
end

MQTT::SpecHelper.client_spec(MQTT::V5::TopicAliasSpec, protocol_version: 5)
