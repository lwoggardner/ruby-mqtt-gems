# frozen_string_literal: true

require_relative 'lib/mqtt/v3/version'

Gem::Specification.new do |gem|
  gem.name        = 'mqtt-v3'
  gem.version     = MQTT::V3::VERSION
  gem.authors     = ['Grant Gardner']
  gem.email       = ['grant@lastweekend.com.au']
  gem.summary     = 'Ruby MQTT 3.1.1'
  gem.description = 'MQTT version 3.1.1 protocol implementation'
  gem.license     = 'MIT'
  gem.files         = Dir.glob('lib/**/*.rb')
  gem.require_paths = %w[lib]
  gem.required_ruby_version = '>= 3.4'
  gem.add_dependency 'mqtt-core'
  gem.metadata['rubygems_mfa_required'] = 'true'
end
