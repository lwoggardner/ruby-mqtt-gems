# frozen_string_literal: true

require_relative '../../gem_helper'
require_relative '../mqtt-core/lib/mqtt/version'

Gem::Specification.new do |gem|
  gem.name        = 'mqtt-v3'
  gem.version     = GemHelper.gem_version(version: MQTT::VERSION).first
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
