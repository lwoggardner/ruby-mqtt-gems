# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/core/client/uri'

describe 'TCP_NODELAY socket option' do
  it 'enables TCP_NODELAY by default on MQTT TCP sockets' do
    uri = URI::MQTT.new('mqtt', nil, 'localhost', 1883, nil, nil, nil, nil, nil)
    
    socket = uri.to_io
    nodelay = socket.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY).int
    
    _(nodelay).must_equal(1)
  ensure
    socket&.close
  end

  it 'can disable TCP_NODELAY when explicitly set to false' do
    uri = URI::MQTT.new('mqtt', nil, 'localhost', 1883, nil, nil, nil, nil, nil)
    
    socket = uri.to_io(tcp_nodelay: false)
    nodelay = socket.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY).int
    
    _(nodelay).must_equal(0)
  ensure
    socket&.close
  end

  it 'enables TCP_NODELAY by default on MQTTS TCP sockets' do
    skip 'requires SSL setup' unless ENV['TEST_SSL']
    
    uri = URI::MQTTS.new('mqtts', nil, 'localhost', 8883, nil, nil, nil, nil, nil)
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
    
    ssl_socket = uri.to_io(ssl_context: ssl_context)
    tcp_socket = ssl_socket.io
    nodelay = tcp_socket.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY).int
    
    _(nodelay).must_equal(1)
  ensure
    ssl_socket&.close
  end
end
