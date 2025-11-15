# frozen_string_literal: true

require_relative 'spec_helper'
require 'mqtt/v5'

# test against test.mosquitto.org or local broker combinations of encrypted/unencrypted, authenticated etc..
describe MQTT::Core::Client::SocketFactory do
  # Set TEST_BROKER env var to switch between local and remote testing
  # TEST_BROKER=test.mosquitto.org bundle exec ruby spec/connection_spec.rb
  # TEST_BROKER=localhost bundle exec ruby spec/connection_spec.rb (default)
  let(:host) { ENV.fetch('TEST_BROKER', 'localhost') }
  let(:io_args) { [] }
  let(:io_opts) { {} }
  let(:socket_factory) { MQTT::Core::Client::SocketFactory.create(*io_args, **io_opts) }
  let(:instrument) { Minitest::Mock.new }
  let(:io) { socket_factory.new_io.tap { @io_used = true } }

  def ssl_fixture(path)
    File.join(File.expand_path('fixture/ssl', __dir__), path)
  end

  def ca_file_for_host
    host == 'test.mosquitto.org' ? ssl_fixture('mosquitto.org.crt') : ssl_fixture('server.crt')
  end

  def expect_connected(instrument: nil)
    MQTT::V5::Client.open(socket_factory, session_store: MQTT::V5::Client.qos0_store) do |client|
      if instrument
        client.on_receive { |pkt| instrument.recv_packet(pkt) if pkt }
        client.on_send { |pkt| instrument.send_packet(pkt) }
      end
      client.connect
      ConcurrentMonitor::TimeoutClock.wait_until(5, delay: 0.2) { client.status == :connected }
      expect(client.status).must_equal(:connected)
      yield client if block_given?
    end

    instrument&.verify
  end

  after do
    io&.close if @io_used
  end

  it 'connects to default port 1883' do
    io_args << "mqtt://#{host}"
    expect(io).must_be_instance_of TCPSocket
    expect(socket_factory.auth).must_be_empty
    expect(io.closed?).must_equal(false)
    expect_connected
  end

  it 'connects via Unix socket' do
    socket_path = File.expand_path('fixture/mosquitto/mqtt.sock', __dir__)
    skip "Unix socket not available at #{socket_path}" unless File.exist?(socket_path)
    io_args << "unix://#{socket_path}"
    expect(io).must_be_instance_of UNIXSocket
    expect(io.closed?).must_equal(false)
    expect_connected
  end

  it 'connects with authentication' do
    io_args << "mqtt://ro:readonly@#{host}:1884"

    instrument.expect(:send_packet, true) do |packet|
      packet.username == 'ro' && packet.password == 'readonly'
    end

    instrument.expect(:send_packet, true, [MQTT::V5::Packet::Disconnect])
    instrument.expect(:recv_packet, true, [MQTT::V5::Packet::Connack])

    expect(socket_factory.auth).must_equal({ username: 'ro', password: 'readonly' })
    expect_connected(instrument:)
  end

  it 'connects with ssl when using mqtts' do
    require 'openssl'
    io_args << "mqtts://#{host}"
    io_opts.merge!(ssl_ca_file: ca_file_for_host)
    # default port 8883 uses custom certificate
    expect(socket_factory.uri.port).must_equal(8883)
    expect(io).must_be_instance_of OpenSSL::SSL::SSLSocket
    expect(io.closed?).must_equal(false)
    expect_connected
  end

  it 'connects with ssl when using mqtts and default CA bundle' do
    skip "Default CA bundle test only works with test.mosquitto.org" unless host == 'test.mosquitto.org'
    io_args << "mqtts://#{host}:8886"
    expect(io).must_be_instance_of OpenSSL::SSL::SSLSocket
    expect(io.closed?).must_equal(false)
    expect_connected
  end

  it 'connects to encrypted socket with client certificate' do
    require 'openssl'
    io_args << "mqtts://#{host}:8884"
    io_opts.merge!(ssl_ca_file: ca_file_for_host, ssl_cert_file: ssl_fixture('client.crt'), ssl_key_file: ssl_fixture('client.key'))
    expect(io).must_be_instance_of OpenSSL::SSL::SSLSocket
    expect(io.closed?).must_equal(false)
    expect(io.context.cert).wont_be_nil
  end

  it 'connects with authentication and tls' do
    skip "Authenticated SSL is not working on test.mosquitto.org:8885" if host == 'test.mosquitto.org'
    io_args << "mqtts://ro:readonly@#{host}:8885"
    io_opts.merge!(ssl_ca_file: ca_file_for_host)

    instrument.expect(:send_packet, true) do |packet|
      packet.username == 'ro' && packet.password == 'readonly'
    end

    instrument.expect(:send_packet, true, [MQTT::V5::Packet::Disconnect])
    instrument.expect(:recv_packet, true, [MQTT::V5::Packet::Connack])

    expect_connected(instrument:)
  end

  it 'raises error if server cert is not in default CA bundle' do
    require 'openssl'
    io_args << "mqtts://#{host}"
    expect(-> { io }).must_raise(OpenSSL::SSL::SSLError)
  end

  it 'raises error if server cert is expired' do
    require 'openssl'
    io_args << "mqtts://#{host}:8887"
    io_opts.merge!(ssl_ca_file: ca_file_for_host)
    expect(-> { io }).must_raise(OpenSSL::SSL::SSLError)
  end
end
