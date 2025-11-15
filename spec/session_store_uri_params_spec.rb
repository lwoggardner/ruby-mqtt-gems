# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../gems/mqtt-core/lib/mqtt/core/client/session_store'

describe 'SessionStore URI Parameters' do
  describe 'SessionStore.extract_uri_params' do
    it 'extracts client_id and expiry_interval' do
      query_params = { 'client_id' => 'device123', 'expiry_interval' => '3600', 'other' => 'ignored' }
      params = MQTT::Core::Client::SessionStore.extract_uri_params(query_params)
      
      expect(params[:client_id]).must_equal('device123')
      expect(params[:expiry_interval]).must_equal(3600)
      expect(params.key?(:other)).must_equal(false)
    end
    
    it 'converts expiry_interval to integer' do
      query_params = { 'expiry_interval' => '7200' }
      params = MQTT::Core::Client::SessionStore.extract_uri_params(query_params)
      
      expect(params[:expiry_interval]).must_be_kind_of(Integer)
      expect(params[:expiry_interval]).must_equal(7200)
    end
    
    it 'returns empty hash when no relevant params' do
      query_params = { 'keep_alive' => '60', 'other' => 'value' }
      params = MQTT::Core::Client::SessionStore.extract_uri_params(query_params)
      
      expect(params).must_equal({})
    end
    
    it 'handles partial params' do
      query_params = { 'client_id' => 'test' }
      params = MQTT::Core::Client::SessionStore.extract_uri_params(query_params)
      
      expect(params).must_equal({ client_id: 'test' })
    end
  end
end
