# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/v5/packet/connack'

describe 'MQTT::V5::Packet::Connack' do
  let(:packet_class) { MQTT::V5::Packet::Connack }

  data = {
    empty: {},
    rc: { reason_code: 0x80 }
  }
  data[:all] = data.values.inject({}) { |h, v| h.merge!(v) }

  data.each do |name, data|
    it "serialises with #{name} data" do
      packet = packet_class::Connack.new(**data)
      _(packet.session_present?).must_equal(false)
      _(packet.reason_code).must_equal(data[:reason_code] || 0)
      io = StringIO.new
      packet.serialize(io)
      s = io.string
      io = StringIO.new(s)
      packet = MQTT::V5::Packet.deserialize(io)
      _(packet.session_present?).must_equal(false)
    end
  end
end
