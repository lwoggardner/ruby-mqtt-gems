# frozen_string_literal: true

module JsonRpcKit
  # Handles transformation, filtering, and merging of transport options
  #
  # ## Transport options
  #
  #  A typical transport will provide wrappers for {Endpoint} or {Service} that configures what arbitrary options
  #  may be relevant for the transport. e.g. HTTP headers, MQTT Quality of Service etc...
  #
  #  The transport can provide a {#prefix} to distinguish its options from other transports, a {#filter} to select
  #  which option keys it accepts,  and a {#merge} proc to describe how options from multiple sources should be
  #  combined.
  #
  #  The toolkit will then ensure that the transport only receives valid options.
  #
  # ## User space options
  #
  #  Users of {Endpoint}, and {Service} will send and receive options with the {#prefix},
  #  and errors will be raised if invalid options are used.
  #
  #  In cases where an {Endpoint} or {Service} may be used with code supporting multiple transports,
  #  users can also provide a means to {#ignore} certain options so they are not seen by the transport but do not raise
  #  errors.
  class TransportOptions
    # rubocop:disable Style/RescueModifier

    # Default {#merge} proc
    # - Hashes and Sets are merged
    # - Arrays are concatenated and deduplicated
    # - Other values are replaced
    DEFAULT_MERGE = proc do |_key, old, new|
      case old
      when Hash, Set
        old.merge(new) rescue new
      when Array
        (old + Array(new)).uniq rescue nil
      else
        new
      end
    end
    # rubocop:enable Style/RescueModifier

    # Options managed by JsonRpcKit
    RESERVED_OPTIONS = %i[async timeout converter].freeze

    class << self
      # @!visibility private
      # Create a TransportOptions from opts hash, extracting and removing prefix/filter/merge
      # @param opts [Hash] options hash to extract from (mutated - config keys removed)
      # @return [TransportOptions] new instance
      def create_from_opts(opts)
        config = opts.delete(:options_config)
        return config if config

        config_opts = opts.slice(:prefix, :filter, :merge, :ignore)
        opts.replace(opts.except(:prefix, :filter, :merge, :ignore))
        new(**config_opts)
      end
    end

    # @return [String, nil] an optional prefix so user space can distinguish options from different transports
    attr_reader :prefix

    # Permitted transport space option keys
    #
    # @return [Array<Symbol>] list for 'Hash#slice'
    # @return [Proc] 'Hash#filter |key, value|' block
    # @return [nil] allow all options, transport is responsible for handling unsupported options
    attr_reader :filter

    # @return [Proc] 'Hash#merge block: |key, old, new|' for combining options (in transport space)
    # @return [nil] where a transport does not support any options at all
    attr_reader :merge

    # @return [Proc] (Hash#reject block |key,value|) to ignore options (user space keys)
    # @return [Array<String>] list of prefixes to ignore
    # @return [nil] do not ignore any options
    attr_reader :ignore

    # @!visibility private
    def initialize(prefix: nil, filter: nil, ignore: nil, merge: DEFAULT_MERGE)
      raise ArgumentError, "merge(#{merge.class}): must be Proc or nil" unless merge.nil? || merge.respond_to?(:call)

      @merge = merge
      @prefix = prefix
      # no merge proc means the transport does not support any options
      raise ArgumentError, 'filter: not relevant without merge:' if !merge && filter

      @filter = build_filter(merge ? filter : [])
      @ignore = build_ignore(ignore)
    end

    # @!visibility private
    # Add prefix to option keys
    # @param opts [Hash] transport space options
    # @return [Hash] user_space options
    def to_user_space(opts)
      opts.transform_keys { |k| prefix_key(k) }
    end

    # @!visibility private
    # Remove prefix from option keys
    # @param opts [Hash] user space options
    # @return [Hash] transport space options
    def to_transport_space(opts)
      return opts unless prefix

      opts.transform_keys { |k| de_prefix_key(k) }
    end

    # @!visibility private
    # Filter option keys to only those relevant for the transport
    #
    # removes explicitly ignored options then applies the filter
    #
    # @param opts [Hash] options to filter (user space)
    # @return [Hash] filtered options (user space)
    # @raise [ArgumentError] if opts contains unsupported options
    def filter_opts(opts)
      # Silently discard ignored options, but never ignore RESERVED_OPTIONS. Note ignore is uer_space keys!!
      opts = opts.reject { |k, v| !RESERVED_OPTIONS.include?(k) && ignore.call(k, v) } if ignore
      return opts unless filter
      return filter_list(opts) if filter.is_a?(Array)

      opts.filter { |k, v| RESERVED_OPTIONS.include?(k) || filter.call(de_prefix_key(k), v) }
    end

    # @!visibility private
    # @param list [Array<Hash>] list of option hashes to merge (user space)
    # @return [Hash] merged and filtered options (transport space)
    def reduce_to_transport_space(*list)
      # called: only for a Service response_options
      # called: <not implemented> for Endpoint::Batch to reduce per-request request-options
      # Both cases - list is user space (prefixed and should have been filtered), result is transport space.

      to_transport_space(list.reduce({}) { |old, new| merge_opts(old, new) })
    end

    # @!visibility private
    # @param old_hash [Hash] user space, filtered
    # @param new_hash [Hash] user space, unfiltered
    # @param filtered [Boolean] set true if new_hash has already been filtered.
    # @return [Hash] the merged, user space, result
    def merge_opts(old_hash, new_hash, filtered: false)
      new_hash = filter_opts(new_hash) unless filtered
      old_hash.merge(new_hash) { |key, old_val, new_val| merge_key(key, old_val, new_val) }
    end

    private

    # Call merge proc with key transformation (removes prefix from key before calling)
    # @param key [Symbol] key to merge (user_space)
    # @param old [Object] old value
    # @param new [Object] new value
    # @return [Object] merged value
    def merge_key(key, old, new)
      return new if RESERVED_OPTIONS.include?(key)
      return nil unless merge

      merge.call(de_prefix_key(key), old, new)
    end

    def prefix_key(key)
      key = key.to_sym
      return key unless prefix
      return key if RESERVED_OPTIONS.include?(key)

      :"#{prefix}#{key}"
    end

    # @param key [Symbol] user space key
    # @return [Symbol] transport space key
    def de_prefix_key(key)
      key = key.to_sym
      return key unless prefix
      return key if RESERVED_OPTIONS.include?(key)

      key.start_with?(prefix) ? key.to_s[prefix.length..].to_sym : key
    end

    def build_filter(filter)
      case filter
      when nil
        filter
      when Symbol, String
        [prefix_key(filter)]
      when Array
        filter.map { |k| prefix_key(k) }
      else
        raise ArgumentError, "filter(#{filter.class}): must be Array<Symbol> or Proc" unless filter.respond_to?(:call)

        filter
      end
    end

    # user space perpective!!
    def build_ignore(ignore)
      case ignore
      when String
        ->(k, _v) { k.start_with?(ignore) }
      when Array
        ->(k, _v) { ignore.any? { k.to_s.start_with?(it) } }
      when nil
        nil
      else
        raise ArgumentError, "ignore:(#{ignore.class}) must be Array, Proc, or nil" unless ignore.respond_to?(:call)

        ignore
      end
    end

    def filter_list(opts)
      invalid_opts = opts.except(*filter, *RESERVED_OPTIONS)
      raise ArgumentError, "Unsupported options: #{invalid_opts.keys}" unless invalid_opts.empty?

      opts
    end
  end
end
