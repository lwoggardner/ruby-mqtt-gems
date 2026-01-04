# frozen_string_literal: true

require_relative '../../gem_helper'
require_relative 'lib/json_rpc_kit/version'

Gem::Specification.new do |gem|
  gem.name = 'json_rpc_kit'
  gem.version = GemHelper.gem_version(version: JsonRpcKit::VERSION).first
  gem.authors = ['Grant Gardner']
  gem.email = ['grant@lastweekend.com.au']
  gem.summary = 'JSON-RPC 2.0 client and server toolkit'
  gem.description =
    'A Ruby toolkit for JSON-RPC 2.0 that provides both client, server and transport infrastructure components'
  gem.license = 'MIT'
  gem.files = Dir.glob('lib/**/*.rb')
  gem.require_paths = %w[lib]
  gem.required_ruby_version = '>= 3.4'
  gem.metadata['rubygems_mfa_required'] = 'true'
  gem.add_dependency 'json', '~> 2.0'
end
