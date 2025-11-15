# frozen_string_literal: true

module MQTT
  # @!visibility private
  module Options
    private

    # Slice out a set of options, removing them from  the original hash
    # @param [Hash] opts
    # @param [Array<Symbol,Regexp>] keys
    #   - Symbol: exact match
    #   - Regexp: match against key, using first matching group to name the option (eg remove prefix/suffix)
    # @return [Hash]
    def slice_opts!(opts, *keys) # rubocop:disable Metrics/AbcSize
      {}.tap do |slice|
        opts.delete_if do |o, v|
          keys.any? do |k|
            if k.is_a?(Regexp)
              k.match(o).tap { slice[(it[1] || o).to_sym] = v if it }
            else
              (k.to_sym == o).tap { slice[o] = v if it }
            end
          end
        end
        slice.each { |k, v| slice[k] = yield(k, v) } if block_given?
      end
    end

    def coerce_boolean(_key, value)
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
  end
end
