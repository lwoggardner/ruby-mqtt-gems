# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/core/client/socket_factory'
require 'openssl'

HOST = 'test.mosquitto.org'

describe MQTT::Core::Client::SocketFactory do
  let(:io_args) { [] }
  let(:connect_timeout) { 43 }
  let(:mock_ssl_context) do
    mock = Minitest::Mock.new
    def mock.tap(&block)
      block.call(self)
    end
    mock
  end
  let(:socket_factory) { MQTT::Core::Client::SocketFactory.create(*io_args) }

  def ssl_fixture(path)
    File.join(File.expand_path('../../../spec/fixture/ssl', __dir__), path)
  end

  [
    { args: ["mqtt://#{HOST}"], uri: URI::MQTT, scheme: 'mqtt', host: HOST, port: 1883, auth: {} },
    { args: [HOST], uri: URI::MQTT, scheme: 'mqtt', host: HOST, port: 1883, auth: {} },
    { args: [HOST, 2000], uri: URI::MQTT, scheme: 'mqtt', host: HOST, port: 2000, auth: {} },
    { args: ["mqtts://#{HOST}"], uri: URI::MQTTS, scheme: 'mqtts', host: HOST, port: 8883, auth: {} },
    { args: ["mqtts://#{HOST}:2883"], uri: URI::MQTTS, scheme: 'mqtts', host: HOST, port: 2883, auth: {} },
  ].kw_each do |args:, uri:, scheme:, host:, port:, auth:|
    it "parses #{args.join(', ').tr('.', "\u00b7")}" do
      io_args.push(*args)
      _(socket_factory.uri).must_be_instance_of(uri)
      _(socket_factory.uri.scheme).must_equal(scheme)
      _(socket_factory.uri.host).must_equal(host)
      _(socket_factory.uri.port).must_equal(port)
      _(socket_factory.auth).must_equal(auth)
    end
  end

  it 'raises invalid URI error for non MQTT input' do
    _(-> { MQTT::Core::Client::SocketFactory.create('https://example.com') }).must_raise(URI::InvalidURIError)
  end

  def assert_new_io(&assertions)
    socket_factory.uri.stub(:to_io, assertions) do
      _(socket_factory.new_io).must_equal(true)
    end
  end

  it 'accepts local bind address and port in addition to target host and port' do
    io_args.push(HOST, 2000, '127.0.0.1', 1234)
    assert_new_io do |local_host, local_port, **opts|
      _(local_host).must_equal('127.0.0.1')
      _(local_port).must_equal(1234)
    end
  end

  it 'accepts local bind address and port in addition to target URI' do
    io_args.push('mqtt://test.mosquitto.org:2000', '127.0.0.1', 1234)
    assert_new_io do |local_host, local_port, **opts|
      _(local_host).must_equal('127.0.0.1')
      _(local_port).must_equal(1234)
    end
  end

  describe 'ssl context' do
    it 'builds an SSL context for mqtts scheme' do
      io_args.push('mqtts://localhost')
      assert_new_io do |ssl_context:, **opts|
        _(ssl_context).must_be_instance_of OpenSSL::SSL::SSLContext
        _(ssl_context.verify_mode).must_equal(OpenSSL::SSL::VERIFY_PEER)
      end
    end

    it 'builds SSL context from an SSL version symbol' do
      io_args.push('mqtts://localhost')
      sf = MQTT::Core::Client::SocketFactory.create(*io_args, ssl_min_version: :TLS1_2)
      sf.uri.stub(:to_io, ->(*args, ssl_context:, **opts) {
        _(ssl_context).must_be_instance_of OpenSSL::SSL::SSLContext
        true
      }) do
        _(sf.new_io).must_equal(true)
      end
    end

    it 'builds SSL context from a Hash containing client key information' do
      ssl_args = {
        ssl_ca_file: ssl_fixture('mosquitto.org.crt'),
        ssl_cert_file: ssl_fixture('client.crt'),
        ssl_key_file: ssl_fixture('client.key')
      }
      sf = MQTT::Core::Client::SocketFactory.create('test.mosquitto.org', 2345, **ssl_args)
      _(sf.uri.scheme).must_equal('mqtts')
      _(sf.uri.host).must_equal('test.mosquitto.org')
      _(sf.uri.port).must_equal(2345)
      sf.uri.stub(:to_io, ->(*args, ssl_context:, **opts) {
        _(ssl_context).must_be_instance_of OpenSSL::SSL::SSLContext
        true
      }) do
        _(sf.new_io).must_equal(true)
      end
    end

    it 'raises if SSL context parameters are invalid' do
      _(->{ MQTT::Core::Client::SocketFactory.create('mqtts://localhost', ssl_ssk_xxx: 32) }).must_raise
    end

    it 'accepts an SSL context as a direct input' do
      my_ssl_context = OpenSSL::SSL::SSLContext.new
      sf = MQTT::Core::Client::SocketFactory.create('mqtt.test.example.org', ssl_context: my_ssl_context)
      _(sf.uri.scheme).must_equal('mqtts')
      sf.uri.stub(:to_io, ->(*args, ssl_context:, **opts) {
        _(ssl_context).must_be_same_as(my_ssl_context)
        true
      }) do
        _(sf.new_io).must_equal(true)
      end
    end
  end

  describe '#auth' do
    it 'parses username and password from URI' do
      io_args.push('mqtt://me:secret@test.mosquitto.org')
      _(socket_factory.auth).must_equal({ username: 'me', password: 'secret' })
    end

    it 'parses username only from URI' do
      io_args.push('mqtt://you@test.mosquitto.org')
      _(socket_factory.auth).must_equal({ username: 'you'})
    end

    it 'handles URL encoded credentials' do
      io_args.push('mqtt://you%40example.com:sec%3Aret@test.mosquitto.org')
      _(socket_factory.auth).must_equal({ username: 'you@example.com', password: 'sec:ret' })
    end
  end

  describe '#sanitized_uri' do
    it 'masks password' do
      io_args.push('mqtt://user:secret@test.mosquitto.org')
      _(socket_factory.sanitized_uri.password).must_equal('********')
      _(socket_factory.sanitized_uri.user).must_equal('user')
    end

    it 'removes query parameters' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?password_file=/secret&keep_alive=60&passphrase_file=/key', ignore_uri_params: true)
      _(sf.sanitized_uri.query).must_be_nil
    end

    it 'preserves host and port' do
      io_args.push('mqtt://user:pass@broker:1234?param=value')
      sanitized = socket_factory.sanitized_uri
      _(sanitized.host).must_equal('broker')
      _(sanitized.port).must_equal(1234)
      _(sanitized.password).must_equal('********')
      _(sanitized.query).must_be_nil
    end
  end

  describe 'MQTT_SERVER environment variable' do
    before do
      ENV['MQTT_SERVER'] = 'mqtt://env.mosquitto.org'
    end

    after do
      ENV.delete('MQTT_SERVER')
    end

    it 'uses ENV["MQTT_SERVER"] when no URI is provided' do
      _(socket_factory.uri.host).must_equal('env.mosquitto.org')
    end

    it 'prefers explicit URI over environment variable' do
      io_args.push('mqtts://x.example.net')
      _(socket_factory.uri.host).must_equal('x.example.net')
    end
  end

  describe 'connect_timeout from URI' do
    it 'extracts connect_timeout from URI query parameters' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?connect_timeout=15')
      _(sf.io_opts[:connect_timeout]).must_equal(15.0)
    end

    it 'URI parameter overrides explicit connect_timeout' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?connect_timeout=15', connect_timeout: 30)
      _(sf.io_opts[:connect_timeout]).must_equal(15.0)
    end

    it 'explicit parameter used when ignore_uri_params is true' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?connect_timeout=15', connect_timeout: 30, ignore_uri_params: true)
      _(sf.io_opts[:connect_timeout]).must_equal(30.0)
    end
  end

  describe 'tcp_nodelay option' do
    it 'defaults to nil (handled by uri.rb)' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker')
      _(sf.io_opts[:tcp_nodelay]).must_be_nil
    end

    it 'accepts boolean false' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker', tcp_nodelay: false)
      _(sf.io_opts[:tcp_nodelay]).must_equal(false)
    end

    it 'coerces string "false" to false' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?tcp_nodelay=false')
      _(sf.io_opts[:tcp_nodelay]).must_equal(false)
    end

    it 'coerces string "true" to true' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?tcp_nodelay=true')
      _(sf.io_opts[:tcp_nodelay]).must_equal(true)
    end

    it 'coerces string "0" to false' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?tcp_nodelay=0')
      _(sf.io_opts[:tcp_nodelay]).must_equal(false)
    end

    it 'coerces string "1" to true' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?tcp_nodelay=1')
      _(sf.io_opts[:tcp_nodelay]).must_equal(true)
    end
  end
end

