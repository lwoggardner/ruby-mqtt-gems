# frozen_string_literal: true

require_relative 'lib/concurrent_monitor/version'

Gem::Specification.new do |gem|
  gem.name        = 'concurrent_monitor'
  gem.version     = ConcurrentMonitor::VERSION
  gem.authors     = ['Grant Gardner']
  gem.email       = ['grant@lastweekend.com.au']
  gem.summary     = 'An abstract concurrent monitor framework'
  gem.description = 'Simple monitor pattern with a common interface using Thread or Async::Task'
  gem.license     = 'MIT'
  gem.files         = Dir.glob('lib/**/*.rb')
  gem.require_paths = %w[lib]
  gem.required_ruby_version = '>= 3.4'
  gem.metadata['rubygems_mfa_required'] = 'true'
end
