# frozen_string_literal: true

module MQTT
  # @!visibility private
  module Options
    private

    # rubocop:disable Metrics

    # Optimized slice and replace exact keys, delete_if a single prefix or regex.
    # @param opts [Hash]
    # @param keys [Array<Symbol>]
    # @param prefix [String] slices entries from opts whose keys start with this prefix
    # @param pattern [Regex] slices entries from opts whose keys match this pattern
    # @yield [k,v] transform values (with key)
    def slice_opts!(opts, *keys, prefix: nil, pattern: nil)
      s = opts.slice(*keys)
      opts.replace(opts.except(*keys)) if keys.any?

      if prefix
        opts.delete_if do |k, v|
          next false unless k.start_with?(prefix)

          s[k.to_s.delete_prefix(prefix).to_sym] = v
          true
        end
      end
      if pattern
        opts.delete_if do |k, v|
          next false unless (m = pattern.match(k))

          s[m[1].to_sym] = v
          true
        end
      end

      return s unless block_given?

      s.each { |k, v| s[k] = yield(k, v) }
    end

    # rubocop:enable Metrics

    def coerce_boolean(_key = nil, value = nil, **opts)
      _key, value = opts.first if opts.size == 1
      return value if [true, false, nil].include?(value)
      return false if value.to_s.match?(/^(false|f|no|n|0)$/i)

      !!value
    end

    def coerce_integer(key = nil, value = nil, **opts)
      key, value = opts.first if opts.size == 1
      coerce(key, value, type: :Integer)
    end

    def coerce_float(key, value)
      coerce(key, value, type: :Float)
    end

    # @!visibility private
    def coerce(key, value, type: :Integer)
      return value unless value

      case type
      when :Integer
        Integer(value)
      when :Float
        Float(value)
      end
    rescue ArgumentError => e
      raise ArgumentError, "#{key}: #{e.message}"
    end

    #  @param value [Class, Proc, Object] a Class to create the instance,  a Proc to create the instance,
    #   or an already constructed instance use_subscription_identifiers
    def construct(value, *, **)
      return value.call(*, **) if value.respond_to?(:call)
      return value.new(*, **) if value.is_a?(Class)

      value
    end
  end
end
