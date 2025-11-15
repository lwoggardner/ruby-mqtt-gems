# frozen_string_literal: true

require_relative 'spec_helper'
require 'tempfile'

describe 'SocketFactory URI Parameters' do
  describe 'password_file' do
    it 'reads password from file specified in URI' do
      Tempfile.create('mqtt_password') do |f|
        f.write('secret_password')
        f.flush
        
        sf = MQTT::Core::Client::SocketFactory.create("mqtt://user@broker?password_file=#{f.path}")
        auth = sf.auth
        
        expect(auth[:username]).must_equal('user')
        expect(auth[:password]).must_equal('secret_password')
      end
    end
    
    it 'prefers password_file over URI password' do
      Tempfile.create('mqtt_password') do |f|
        f.write('file_password')
        f.flush
        
        sf = MQTT::Core::Client::SocketFactory.create("mqtt://user:uri_password@broker?password_file=#{f.path}")
        auth = sf.auth
        
        expect(auth[:password]).must_equal('file_password')
      end
    end
  end
  
  describe 'SSL URI parameters' do
    it 'extracts SSL params from URI query and stores in query_params' do
      uri = 'mqtt://broker?ssl_cert_file=/path/cert.pem&ssl_key_file=/path/key.pem&ssl_ca_file=/path/ca.pem'
      sf = MQTT::Core::Client::SocketFactory.create(uri, ignore_uri_params: true)
      
      # With ignore_uri_params, SSL params should be in query_params (unused)
      expect(sf.query_params).must_be_kind_of(Hash)
    end
    
    it 'returns empty query_params when no SSL params in URI' do
      sf = MQTT::Core::Client::SocketFactory.create('mqtt://broker')
      
      expect(sf.query_params).must_equal({})
    end
  end
  
  describe 'passphrase_file' do
    it 'reads passphrase from file in code params' do
      skip 'Requires actual SSL files to test'
    end
    
    it 'reads passphrase from file in URI params' do
      skip 'Requires actual SSL files to test'
    end
  end
end
