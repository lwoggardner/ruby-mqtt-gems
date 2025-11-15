# frozen_string_literal: true
require_relative 'spec_helper'
require_relative '../lib/mqtt/v5/packets'

describe 'MQTT 5.0 Specification' do
  describe '1.5 Data Representation' do
    it 'MQTT-1.5.4-1: The character data in a UTF-8 Encoded String MUST be well-formed UTF-8' do
      valid_utf8 = 'Valid UTF-8 string'
      invalid_utf8 = "\xED\xA0\x80\xED\xB0\x80"
      expect(invalid_utf8.valid_encoding?).must_equal(false)

      sio = StringIO.new.binmode
      MQTT::Core::Type::UTF8String.write(valid_utf8, sio)
      sio.rewind
      expect(MQTT::Core::Type::UTF8String.read(sio)).must_equal valid_utf8

      expect(-> { MQTT::Core::Type::UTF8String.from(invalid_utf8) }).must_raise EncodingError

      sio = StringIO.new.binmode
      MQTT::Core::Type::UTF8String.write(invalid_utf8, sio)
      sio.rewind
      expect(-> { MQTT::Core::Type::UTF8String.read(sio) }).must_raise EncodingError
    end

    it 'MQTT-1.5.4-2: A UTF-8 Encoded String MUST NOT include an encoding of the null character U+0000.' do
      invalid_utf8_string = "Hello,\u0000世界!"
      expect { MQTT::Core::Type::UTF8String.from(invalid_utf8_string) }.must_raise(EncodingError)
    end

    it 'MQTT-1.5.4-3: A UTF-8 encoded sequence 0xEF 0xBB 0xBF is always interpreted as U+FEFF' do
      string_with_bom = "\xEF\xBB\xBFHello, World!"
      encoded_string = MQTT::Core::Type::UTF8String.from(string_with_bom)
      expect(encoded_string).wont_equal('Hello, World!')
      expect(encoded_string.bytes.length).must_equal(16)
    end

    it 'MQTT-1.5.5-1: The encoded value MUST use the minimum number of bytes necessary to represent the value.' do
      tests = {
        1 => 0...127,
        2 => 128...16_383,
        3 => 16_384...2_097_151,
        4 => 2_097_152...268_435_455
      }
      tests.each do |bytesize, range|
        [range.first, range.last, rand(range)].each do |value|
          sio = StringIO.new.binmode
          MQTT::Core::Type::VarInt.write(value, sio)
          expect(sio.size).must_equal(bytesize)
        end
      end
    end

    it 'MQTT-1.5.7-1: Both strings MUST comply with the requirements for UTF-8 Encoded Strings.' do
      MQTT::Core::Type::UTF8String.stub(:from, 'x') do
        expect(MQTT::Core::Type::UTF8StringPair.from(%w[hello world])).must_equal(%w[x x])
      end

      sio = StringIO.new.binmode
      MQTT::Core::Type::UTF8StringPair.write(%w[hello world], sio)
      sio.rewind
      MQTT::Core::Type::UTF8String.stub(:read, 'x') do
        expect(MQTT::Core::Type::UTF8StringPair.read(sio)).must_equal(%w[x x])
      end
    end

    describe 'MQTT-2.1.3-1' do
      {
        connect: 0b0000,
        connack: 0b0000,
        puback: 0b0000,
        pubrec: 0b0000,
        pubrel: 0b0010,
        pubcomp: 0b0000,
        subscribe: 0b0010,
        suback: 0b0000,
        unsubscribe: 0b0010,
        unsuback: 0b0000,
        pingreq: 0b0000,
        pingresp: 0b0000,
        disconnect: 0b0000,
        auth: 0b0000
      }.each do |packet_name, reserved_value|
        it "Reserved flag for #{packet_name.upcase} MUST be #{format('%04b', reserved_value)}" do
          packet = MQTT::V5::Packet.build_packet(packet_name)

          sio = StringIO.new.binmode
          packet.serialize(sio)
          sio.rewind
          header_byte = sio.readbyte
          expect(header_byte & 0b000_1111).must_equal(reserved_value)

          sio.ungetbyte(header_byte + 1)
          expect(-> { MQTT::V5::Packet.deserialize(sio) }).must_raise MQTT::Error
        end
      end
    end
  end
end
