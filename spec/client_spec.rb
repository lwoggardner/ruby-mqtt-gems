# frozen_string_literal: true
require_relative 'spec_helper'

# QoS 2 subscription tests - comprehensive coverage of receive flow

module MQTT
  module ClientIntegrationSpec
    def self.included(spec)
      spec.class_eval do

        it 'starts a connection' do
          with_client do |client|
            _(client).must_be_instance_of(client_class)
            _(client.send(:monitor)).must_be_kind_of(monitor_class)
            _(client.status).must_equal(:configure)
            client.connect
            _(client.status).must_equal(:connected)
            client.disconnect
            wait_until(6) { client.status == :stopped }
            _(client.status).must_equal(:stopped)
          end
        end

        it 'stays alive if nothing is sent' do
          client_class_opts[:keep_alive] = 2
          with_client do |client|
            ping_send = 0
            ping_recv = 0
            client.on_send { |pkt| ping_send += 1 if pkt&.packet_name == :pingreq }
            client.on_receive { |pkt| ping_recv += 1 if pkt&.packet_name == :pingresp }
            expect(client.keep_alive).must_equal(2)
            sleep 5
            expect(client.status).must_equal(:connected)
            expect(ping_recv).must_be :>, 0
            expect(ping_send).must_be :>, 0
          end
        end

        it 'stays alive when publishing only qos0 messages' do
          client_class_opts[:keep_alive] = 2
          with_client do |client|
            ping_send = 0
            ping_recv = 0
            client.on_send { |pkt| ping_send += 1 if pkt&.packet_name == :pingreq }
            client.on_receive { |pkt| ping_recv += 1 if pkt&.packet_name == :pingresp }

            # Publish QoS 0 messages every 1 second for 5 seconds
            6.times do
              client.publish('ruby_mqtt5/test', 'qos0 message')
              sleep 0.5
            end

            # Should have sent PINGREQ despite regular QoS 0 publishing
            expect(client.status).must_equal(:connected)
            expect(ping_send).must_be :>, 0
            expect(ping_recv).must_be :>, 0

          end
        end

        it 'sends qos0 publish' do
          with_client do |client|
            pub = ack = nil
            client.on_publish { |p, a| pub = p; ack = a }
            client.connect
            client.publish('ruby_mqtt5/test', 'hello')
            expect(pub.packet_name).must_equal(:publish)
            expect(pub.qos).must_equal(0)
            expect(ack).must_be_nil
          end
        end

        it 'subscribes and unsubscribes' do
          with_client do |client|
            sub_pkt = ack_pkt = unsub = unsuback = nil
            client.on_subscribe { |s, a| sub_pkt = s; ack_pkt = a }
            client.on_unsubscribe { |u, ua| unsub = u; unsuback = ua }
            client.connect
            
            sub = client.subscribe('ruby_mqtt5/test')
            expect(sub_pkt.packet_name).must_equal(:subscribe)
            expect(ack_pkt.packet_name).must_equal(:suback)
            expect(sub_pkt.success!(ack_pkt)).must_equal({ 'ruby_mqtt5/test' => :success })

            sub.unsubscribe
            expect(unsub.packet_name).must_equal(:unsubscribe)
            expect(unsuback.packet_name).must_equal(:unsuback)
            expect(unsub.success!(unsuback)).must_be_same_as(unsub)
          end
        end

        it 'receives messages' do
          skip "No system topic for #{uri}" unless sys_topic
          with_client do |client|
            topic, = client.subscribe(sys_topic).first
            expect(topic).must_equal(sys_topic)
          end
        end

        it 'receives messages with wildcard subscription' do
          base_topic = "ruby_mqtt5/wildcard_test/#{SecureRandom.hex(4)}"
          
          with_client(session_store: client_class.qos0_store) do |subscriber|
            sub = subscriber.subscribe("#{base_topic}/#")
            
            with_client(session_store: client_class.qos0_store) do |publisher|
              publisher.publish("#{base_topic}/a", "msg_a")
              publisher.publish("#{base_topic}/b", "msg_b")
              publisher.publish("#{base_topic}/c/d", "msg_c_d")
            end
            
            messages = sub.take(3)
            expect(messages.size).must_equal(3)
            topics = messages.map { |t, _| t }
            expect(topics).must_include("#{base_topic}/a")
            expect(topics).must_include("#{base_topic}/b")
            expect(topics).must_include("#{base_topic}/c/d")
          end
        end

        it 'receives messages in FIFO order' do
          topic = 'ruby_mqtt5/fifo_test'
          
          with_client(session_store: client_class.qos0_store) do |subscriber|
            sub = subscriber.subscribe(topic)
            
            with_client(session_store: client_class.qos0_store) do |publisher|
              5.times { |i| publisher.publish(topic, "message_#{i}") }
            end
            
            messages = sub.take(5)
            expect(messages.size).must_equal(5)
            messages.each_with_index do |(_t, payload), i|
              expect(payload).must_equal("message_#{i}")
            end
          end
        end
      end

    end
  end
end

MQTT::SpecHelper.client_spec(MQTT::ClientIntegrationSpec)
