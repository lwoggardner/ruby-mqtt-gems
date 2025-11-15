# frozen_string_literal: true
require_relative 'spec_helper'
require_relative '../lib/mqtt/v5/packet/connect'

describe 'MQTT::V5::Packet::Connect' do
  let(:packet_class) { MQTT::V5::Packet::Connect }

  data = {
    empty: {},
    will: { will_topic: 'the/will/topic9', will_payload: '0my last will and testament' },
    auth: { username: 'user', password: 'XXXX' },
    flags: { clean_start: true },
    properties: { maximum_packet_size: 4000, user_properties: { key: 'value', 'key2' => 'value2' } }
  }
  data[:all] = data.values.inject({}) { |h, v| h.merge!(v) }

  data.each do |name, data|
    it "serialises with #{name} data" do
      packet = packet_class.new(**data)
      io = StringIO.new
      packet.serialize(io)
      s = io.string
      io = StringIO.new(s)
      MQTT::V5::Packet.deserialize(io)
    end
  end

  it 'serialises as expected2' do
    data = { clean_start: true }
    packet = packet_class.new(**data)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(packet.will_flag).must_equal(false)
    _(packet.will_qos).must_equal(0)
    _(packet.keep_alive).must_equal(60)
    _(packet.username).must_be_nil
    _(packet.password).must_be_nil
    #                PK LN VAR(4) M  Q  T  T PV CF KP_AL 0P CL-ID
    _(s).must_equal('10 0d 00 04 4d 51 54 54 05 02 00 3c 00 00 00'.b)
  end

  it 'serialises as expected' do
    # https://www.emqx.com/en/blog/mqtt-5-0-control-packets-01-connect-connack
    # mqttx conn --hostname broker.emqx.io --mqtt-version 5 \
    #   --session-expiry-interval 300 --keepalive 60 --username admin --password public
    data = {
      clean_start: true, session_expiry_interval: 300, keep_alive: 60,
      client_id: 'mqttx_0c668d0d',
      username: 'admin', password: 'public'
    }
    packet = packet_class.new(**data)
    _(packet.session_expiry_interval).must_equal(300)
    _(packet.keep_alive).must_equal(60)
    _(packet.username).must_equal('admin')
    _(packet.password).must_equal('public')
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('10 2f 00 04 4d 51 54 54 05 c2 00 3c 05 11 00 00 01 2c 00 0e 6d 71 74 74 78 5f 30 63 36 36 38 64 30 64 00 05 61 64 6d 69 6e 00 06 70 75 62 6c 69 63'.b)
  end

  describe 'MQTT 5.0 Compliance' do
    it 'MQTT-3.1.3-4: ClientID MUST be UTF-8 Encoded String' do
      _(-> { packet_class.new(client_id: "client\u0000id") }).must_raise EncodingError
    end

    it 'MQTT-3.1.3-11: Will Topic MUST be UTF-8 Encoded String' do
      _(-> { packet_class.new(will_topic: "will\u0000topic", will_payload: 'test') }).must_raise EncodingError
    end

    it 'MQTT-3.1.3-12: User Name MUST be UTF-8 Encoded String' do
      _(-> { packet_class.new(username: "user\u0000name") }).must_raise EncodingError
    end

    it 'MQTT-3.1.2-9: Will Topic and Will Payload MUST be present if Will Flag is set' do
      _(-> { packet_class.new(will_topic: nil, will_payload: 'payload') }).must_raise ArgumentError
      packet_class.new(will_topic: 'topic', will_payload: nil) # empty payload is valid
    end

    it 'MQTT-3.1.2-11: Will QoS MUST be 0 if Will Flag is not set' do
      _(-> { packet_class.new(will_qos: 1) }).must_raise ArgumentError
    end

    it 'MQTT-3.1.2-12: Will QoS MUST be 0, 1, or 2' do
      _(-> { packet_class.new(will_topic: 'topic', will_payload: 'test', will_qos: 3) }).must_raise ArgumentError
    end

    it 'MQTT-3.1.2-13: Will Retain MUST be 0 if Will Flag is not set' do
      _(-> { packet_class.new(will_retain: true) }).must_raise ArgumentError
    end

    it 'MQTT-4.7.1-1: Will Topic MUST NOT contain wildcard characters' do
      _(-> { packet_class.new(will_topic: 'will/#', will_payload: 'test') }).must_raise ArgumentError
      _(-> { packet_class.new(will_topic: 'will/+/topic', will_payload: 'test') }).must_raise ArgumentError
    end

    it 'MQTT-4.7.3-1: Will Topic MUST be at least one character' do
      _(-> { packet_class.new(will_topic: '', will_payload: 'test') }).must_raise ArgumentError
    end
  end
end
