#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'

require 'rake'
require 'rake/clean'
require 'fileutils'

require 'bundler/audit/task'
Bundler::Audit::Task.new

require 'bundler/gem_helper'

require 'rubocop/rake_task'
RuboCop::RakeTask.new

require 'yard'

require 'rake/testtask'

# YARD documentation for all gems
CLOBBER.include('doc')

desc 'Generate YARD documentation for all gems'
YARD::Rake::YardocTask.new do |t|
  t.options = ['--fail-on-warning']
end

desc 'Run YARD server for live documentation'
task :yard_server do
  sh 'bundle exec yard server --reload'
end

# Get all gem directories
def gem_directories
  Dir.glob('./gems/*').select { |f| File.directory?(f) }
end

namespace :gems do
  gem_directories.each do |gem_dir|
    gem_name = File.basename(gem_dir)

    namespace gem_name.to_sym do
      RuboCop::RakeTask.new do |task|
        task.patterns = ["#{gem_dir}/lib/**/*.rb"]
      end

      Rake::TestTask.new(:test) do |t|
        t.libs << "#{gem_dir}/lib"
        t.libs << "#{gem_dir}/spec"
        t.test_files = FileList["#{gem_dir}/spec/**/*_spec.rb"]
        t.warning = false
      end

      Bundler::GemHelper.new(gem_dir).install

      desc "Generate YARD documentation for #{gem_name}"
      YARD::Rake::YardocTask.new(:yard) do |t|
        t.files = ["#{gem_dir}/lib/**/*.rb"]
        t.options = ['--no-private', '--markup', 'markdown']
      end

      task default: %i[rubocop test yard]
    end

    CLEAN.include("#{gem_dir}/pkg")
  end

  desc 'Build all gems'
  task :build do
    gem_directories.each do |gem_dir|
      gem_name = File.basename(gem_dir)
      Rake::Task["gems:#{gem_name}:build"].invoke
    end
  end

  desc 'Release all gems'
  task :release do
    gem_directories.each do |gem_dir|
      gem_name = File.basename(gem_dir)
      Rake::Task["gems:#{gem_name}:release"].invoke
    end
  end
end

# Broker management tasks
namespace :broker do
  desc 'Start mosquitto broker in Docker (stable profile)'
  task :start do
    profile = ENV['BROKER_PROFILE'] || 'stable'
    sh "docker compose --profile #{profile} up -d"
    puts 'Waiting for broker to be ready...'

    # Check docker container status
    sh "docker compose --profile #{profile} ps"

    # Wait up to 10 seconds for broker to be accessible
    10.times do |i|
      if system('nc -z localhost 1883 2>/dev/null')
        puts "Mosquitto broker (#{profile}) started on localhost:1883"
        break
      end
      sleep 1
      if i == 9
        sh "docker compose --profile #{profile} logs"
        abort 'Broker failed to start after 10 seconds'
      end
    end
  end

  desc 'Stop mosquitto broker'
  task :stop do
    sh 'docker compose --profile stable --profile testing down'
    puts 'Mosquitto broker stopped'
  end

  desc 'Start stable mosquitto broker'
  task :start_stable do
    ENV['BROKER_PROFILE'] = 'stable'
    Rake::Task['broker:start'].invoke
  end

  desc 'Start testing mosquitto broker'
  task :start_testing do
    ENV['BROKER_PROFILE'] = 'testing'
    Rake::Task['broker:start'].invoke
  end

  desc 'Check if broker is running'
  task :status do
    system('docker compose ps mosquitto')
  end

  desc 'View broker logs'
  task :logs do
    sh 'docker compose logs -f mosquitto'
  end
end

namespace :test do
  desc 'Run tests with broker (starts broker, runs tests, stops broker)'
  task :with_broker do
    Rake::Task['broker:start'].invoke
    Rake::Task['test:all'].invoke
  ensure
    Rake::Task['broker:stop'].invoke
  end

  desc 'Use spec reporter (use with another test task)'
  task :use_spec_reporter do
    ENV['MINITEST_REPORTER'] = 'SpecReporter'
  end

  desc 'Disable test parallelization (use with another test task)'
  task :sequential do
    ENV['MINITEST_SEQUENTIAL'] = '1'
  end

  # Task to run all tests (top-level + all gems) with aggregate reporting
  desc 'Run all tests (project root and all gems)'
  Rake::TestTask.new(:all) do |t|
    t.libs << 'lib'
    t.libs << 'spec'
    gem_directories.each do |gem_dir|
      t.libs << "#{gem_dir}/lib"
      t.libs << "#{gem_dir}/spec"
    end
    t.test_files = FileList['spec/**/*_spec.rb'].exclude('spec/stashed/**/*') +
                   gem_directories.flat_map { |gem_dir| FileList["#{gem_dir}/spec/**/*_spec.rb"] }
    t.warning = false
  end

  desc 'Run tests from the project root only'
  Rake::TestTask.new(:root_only) do |t|
    t.libs << 'lib'
    t.libs << 'spec'
    t.test_files = FileList['spec/**/*_spec.rb'].exclude('spec/stashed/**/*')
    t.warning = false
  end
end

desc 'Run all tests'
task test: ['test:all']

# For now ConcurrentMonitor version is aligned with MQTT version
VERSION_FILES = %w[
  gems/mqtt-core/lib/mqtt/version.rb
  gems/concurrent_monitor/lib/concurrent_monitor/version.rb
  gems/json_rpc_kit/lib/json_rpc_kit/version.rb
].freeze

namespace :version do
  desc 'Show current versions'
  task :show do
    require_relative 'gem_helper'

    VERSION_FILES.each do |file|
      version = GemHelper.read_version(file)
      puts "#{file}: #{version}"
    end

    branch = GemHelper.current_branch
    puts "\nBranch: #{branch}"
  end

  desc 'Create release tag (main branch only, verifies versions match)'
  task :tag do
    require_relative 'gem_helper'
    GemHelper.create_and_display_tag(version_files: VERSION_FILES, main_branch: 'main', prerelease: false)
  end

  desc 'Create pre-release tag from current branch (optional suffix: rake version:tag_prerelease[rc1])'
  task :tag_prerelease, [:suffix] do |_t, args|
    require_relative 'gem_helper'
    GemHelper.create_and_display_tag(version_files: VERSION_FILES, main_branch: 'main', prerelease: true,
                                     suffix: args[:suffix])
  end

  desc 'Bump minor version for both gems'
  task :bump_minor do
    VERSION_FILES.each do |file|
      content = File.read(file)
      content.sub!(/VERSION = ['"](\d+)\.(\d+)\.(\d+)['"]/) do
        "VERSION = '#{Regexp.last_match(1)}.#{Regexp.last_match(2).to_i + 1}.0'"
      end
      File.write(file, content)

      new_version = content.match(/VERSION = ['"](.+)['"]/)[1]
      puts "Updated #{file} to #{new_version}"
    end

    puts "\nNext steps:"
    puts '  bundle install  # Update Gemfile.lock'
    puts "  git commit -am 'Bump version to <version>'"
  end
end

task default: %i[rubocop yard test:use_spec_reporter test:with_broker]
