# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/v3/packet/connack'

describe 'MQTT::V3::Packet::Connack' do
  let(:packet_class) { MQTT::V3::Packet::Connack }

  data = {
    empty: {},
    rc: { return_code: 0x80 }
  }
  data[:all] = data.values.inject({}) { |h, v| h.merge!(v) }

  data.each do |name, data|
    it "serialises with #{name} data" do
      packet = packet_class::Connack.new(**data)
      _(packet.session_present?).must_equal(false)
      _(packet.return_code).must_equal(data[:return_code] || 0)
      io = StringIO.new
      packet.serialize(io)
      s = io.string
      io = StringIO.new(s)
      packet = MQTT::V3::Packet.deserialize(io)
      _(packet.session_present?).must_equal(false)
    end
  end
end
