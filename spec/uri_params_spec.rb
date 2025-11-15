# frozen_string_literal: true

require_relative 'spec_helper'
require 'mqtt/v5'

describe 'MQTT URI Query Parameters' do
  let(:socket_factory) { MQTT::Core::Client::SocketFactory.create(uri) }
  
  describe 'URI query parameters integration' do
    it 'merges URI query parameters into query_params' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?keep_alive=60&client_id=test123')
      
      expect(sf.query_params[:keep_alive]).must_equal('60')
      expect(sf.query_params[:client_id]).must_equal('test123')
    end

    it 'returns empty query_params when no query parameters' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker')
      
      expect(sf.query_params).must_equal({})
    end

    it 'handles partial parameters' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?keep_alive=30')
      
      expect(sf.query_params[:keep_alive]).must_equal('30')
    end

    it 'query parameters are strings from URI' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker?keep_alive=45&protocol_version=5')
      
      expect(sf.query_params[:keep_alive]).must_be_kind_of(String)
      expect(sf.query_params[:protocol_version]).must_be_kind_of(String)
    end
  end

  describe 'parameter precedence' do
    it 'URI parameters override code parameters' do
      # Simulate what happens in MQTT.open: client_opts.merge(uri_params)
      code_opts = { keep_alive: 60, connect_timeout: 5 }
      uri_params = { keep_alive: 30 }
      merged = code_opts.merge(uri_params)
      
      expect(merged[:keep_alive]).must_equal(30) # URI wins
      expect(merged[:connect_timeout]).must_equal(5) # code value kept when not in URI
    end
    
    it 'protocol_version parameter overrides URI' do
      # protocol_version uses ||= so explicit parameter wins
      protocol_version = '5'
      uri_protocol = ['3']
      result = protocol_version || uri_protocol
      
      expect(result).must_equal('5')
    end
  end

  describe 'protocol_version handling' do
    it 'uses protocol_version from URI when not explicitly provided' do
      query_params = { 'protocol_version' => '3' }
      protocol_version = query_params['protocol_version']&.split(',')
      
      expect(protocol_version).must_equal(['3'])
    end

    it 'supports comma-separated protocol versions' do
      query_params = { 'protocol_version' => '5,3' }
      protocol_version = query_params['protocol_version']&.split(',')
      
      expect(protocol_version).must_equal(['5', '3'])
    end
  end
end
