# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/v3/packet/publish'

describe 'MQTT::V3::Packet::Publish' do
  let(:packet_class) { MQTT::V3::Packet::Publish }
  it 'serialises PUBLISH' do
    # https://www.emqx.com/en/blog/mqtt-5-0-control-packets-02-publish-puback
    data = {
      qos: 0,
      retain: false,
      topic_name: 'request',
      payload: 'This is a QoS 0 message'
    }
    packet = packet_class.new(**data)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(s).must_equal('30 20 00 07 72 65 71 75 65 73 74 54 68 69 73 20 69 73 20 61 20 51 6f 53 20 30 20 6d 65 73 73 61 67 65'.b)
  end
end
