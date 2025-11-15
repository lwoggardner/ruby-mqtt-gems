# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/v3/packet/connect'

describe 'MQTT::V3::Packet::Connect' do
  let(:packet_class) { MQTT::V3::Packet::Connect }

  data = {
    empty: {},
    will: { will_topic: 'the/will/topic9', will_payload: '0my last will and testament' },
    auth: { username: 'user', password: 'XXXX' },
    flags: { clean_session: true }
  }
  data[:all] = data.values.inject({}) { |h, v| h.merge!(v) }

  data.each do |name, data|
    it "serialises with #{name} data" do
      packet = packet_class.new(**data)
      io = StringIO.new
      packet.serialize(io)
      s = io.string
      io = StringIO.new(s)
      MQTT::V3::Packet.deserialize(io)
    end
  end

  it 'serialises as expected' do
    data = { clean_session: true }
    packet = packet_class.new(**data)
    io = StringIO.new
    packet.serialize(io)
    s = MQTT::Core::Packet.hex(io.string)
    _(packet.will_flag).must_equal(false)
    _(packet.username).must_be_nil
    _(packet.password).must_be_nil
    #                PK LN VAR(4) M  Q  T  T PV CF KP_AL CL-ID
    _(s).must_equal('10 0c 00 04 4d 51 54 54 04 02 00 3c 00 00'.b)
  end
end
