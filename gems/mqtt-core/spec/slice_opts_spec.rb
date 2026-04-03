# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/mqtt/options'

# Minimal test harness that includes Options
class SliceOptsHarness
  include MQTT::Options
  public :slice_opts!
end

describe 'Options#slice_opts!' do
  let(:harness) { SliceOptsHarness.new }

  describe 'prefix extraction' do
    it 'extracts prefix-matched keys with string values' do
      opts = { session_base_dir: '/tmp', other: 1 }
      result = harness.slice_opts!(opts, prefix: 'session_')
      _(result).must_equal({ base_dir: '/tmp' })
      _(opts).must_equal({ other: 1 })
    end

    it 'preserves nil values when extracting by prefix' do
      opts = { session_expiry_interval: nil, other: 1 }
      result = harness.slice_opts!(opts, prefix: 'session_')
      _(result).must_equal({ expiry_interval: nil })
      _(opts).must_equal({ other: 1 })
    end

    it 'preserves false values when extracting by prefix' do
      opts = { session_clean: false, other: 1 }
      result = harness.slice_opts!(opts, prefix: 'session_')
      _(result).must_equal({ clean: false })
      _(opts).must_equal({ other: 1 })
    end

    it 'removes prefix-matched keys from source hash even when value is nil' do
      opts = { session_expiry_interval: nil, session_base_dir: '/tmp', keep_alive: 60 }
      harness.slice_opts!(opts, prefix: 'session_')
      _(opts).must_equal({ keep_alive: 60 })
    end
  end

  describe 'pattern extraction' do
    it 'preserves nil values when extracting by pattern' do
      opts = { session_expiry_interval: nil, other: 1 }
      result = harness.slice_opts!(opts, pattern: /^session_(.+)/)
      _(result).must_equal({ expiry_interval: nil })
      _(opts).must_equal({ other: 1 })
    end
  end

  describe 'exact key extraction' do
    it 'extracts exact keys normally' do
      opts = { client_id: 'test', session_store: nil, other: 1 }
      result = harness.slice_opts!(opts, :client_id, :session_store)
      _(result).must_equal({ client_id: 'test', session_store: nil })
      _(opts).must_equal({ other: 1 })
    end
  end
end
