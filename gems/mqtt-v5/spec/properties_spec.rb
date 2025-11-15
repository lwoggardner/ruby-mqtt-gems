# frozen_string_literal: true
require_relative 'spec_helper'
require_relative '../lib/mqtt/v5/packets'

describe 'MQTT 5.0 Properties Compliance' do
  it 'MQTT-2.2.2-1: Zero property length must be indicated correctly' do
    packet = MQTT::V5::Packet::PingReq.new
    io = StringIO.new
    packet.serialize(io)
    io.rewind
    io.readbyte
    length = MQTT::Core::Type::VarInt.read(io)
    _(length).must_equal(0)
  end

  it 'MQTT-3.3.2-19: Content Type MUST be UTF-8 Encoded String' do
    _(-> { MQTT::V5::Packet::Publish.new(topic_name: 'test', qos: 0, content_type: "type\u0000") }).must_raise EncodingError
  end
end
