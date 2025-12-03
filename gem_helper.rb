# frozen_string_literal: true

# Helper for version management and gem releases
# Used by Rakefile and gemspecs, not included in released gems
class GemHelper
  class << self
    def git_ref(env: ENV)
      ref = env.fetch('GIT_REF') do
        `git symbolic-ref HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null`.strip
      rescue StandardError
        nil
      end

      return [ref, nil] unless ref

      if ref.start_with?('refs/heads/')
        [ref.delete_prefix('refs/heads/'), :branch]
      elsif ref.start_with?('refs/tags/')
        [ref.delete_prefix('refs/tags/'), :tag]
      elsif ref.match?(/^v?\d+\.\d+\.\d+/)
        [ref, :tag]
      else
        [ref, :unknown]
      end
    end

    def gem_version(version:, main_branch: 'main', env: ENV)
      ref_name, ref_type = git_ref(env: env)

      gem_version = case ref_type
                    when :branch
                      ref_name == main_branch ? version : "#{version}.#{ref_name.tr('/_-', '.')}"
                    when :tag
                      ref_name.start_with?('v') ? ref_name[1..] : ref_name
                    else
                      suffix = ref_name&.empty? ? 'unknown' : (ref_name || 'unknown')
                      "#{version}.pre.#{suffix}"
                    end

      [gem_version, ref_name, ref_type]
    end

    def current_branch
      `git symbolic-ref --short HEAD 2>/dev/null`.strip
    end

    def working_directory_clean?
      system('git diff-index --quiet HEAD --')
    end

    def tag_exists?(tag)
      system("git rev-parse #{tag} >/dev/null 2>&1")
    end

    def read_version(file)
      File.read(file).match(/VERSION = ['"](.+)['"]/)[1]
    end

    def verify_versions_match(*files)
      versions = files.map { |f| read_version(f) }
      return versions.first if versions.uniq.size == 1

      raise "Version mismatch: #{files.zip(versions).map { |f, v| "#{f}=#{v}" }.join(', ')}"
    end

    def create_tag(version:, main_branch:, prerelease: false)
      branch = current_branch
      raise 'Working directory has uncommitted changes' unless working_directory_clean?

      if prerelease
        raise "Use release tag from main branch (currently on: #{branch})" if branch == main_branch

        branch_suffix = branch.tr('/_-', '.')
        tag = "v#{version}.#{branch_suffix}"
        message = "Pre-release #{tag}"
      else
        raise "Release tags must be from main branch (currently on: #{branch})" unless branch == main_branch

        tag = "v#{version}"
        message = "Release #{tag}"
      end

      raise "Tag #{tag} already exists" if tag_exists?(tag)

      system("git tag -a #{tag} -m '#{message}'") || raise('Failed to create tag')
      tag
    end
  end
end
