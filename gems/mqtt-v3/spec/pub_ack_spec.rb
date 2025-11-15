# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/v3/packet/pub_ack'

describe 'MQTT::V3::Packet::PubAck' do
  let(:packet_class) { MQTT::V3::Packet::PubAck }

  it 'serialises PUBACK' do
    # https://www.emqx.com/en/blog/mqtt-5-0-control-packets-02-publish-puback
    data = { packet_identifier: 25_674 }
    packet = packet_class.new(**data)
    _(packet.packet_identifier).must_equal(25_674)
    _(packet.success?).must_equal(true)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    # Note the trailing 00 here is strictly not required by the spec.
    #                P_ LN PK_ID
    _(s).must_equal('40 02 64 4a'.b)
  end
end
