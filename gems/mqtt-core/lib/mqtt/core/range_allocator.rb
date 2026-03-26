# frozen_string_literal: true

module MQTT
  # Interface for allocating identifiers from a range
  module RangeAllocator
    # @see .parse_range
    RANGE_REGEX = /\A(\d*)\.{2}(\d*)\z/

    # @return [Range] the initial range from which identifiers are allocated
    attr_reader :range

    # @param range [Range] the initial range from which identifiers are allocated
    # @param within [Range|nil] optional range to validate against
    def initialize(range, within: nil)
      @range = allocation_range(range, within:)
      reset
    end

    # @!method next
    #  @abstract
    #  @return [Integer] the next id to allocate
    #  @return [nil] if there were no more ids available to allocate

    # @!method free(id)
    #  @abstract
    #  Return an identifier to the pool
    #
    #  @param id [Integer]
    #  @return [void]

    # @!method reset
    #  @abstract
    #  Reset allocation, so the whole initial range is available
    #  @return [void]

    def validate!(within:)
      valid_range!(@range, within:)
    end

    module_function

    # @param [String] range (matching {RANGE_REGEX})
    # @return [Range]
    def parse_range(range)
      match = RANGE_REGEX.match(range)
      raise ArgumentError, 'Expecting range "\d*..\d*"' unless match

      Range.new(match[1] == '' ? nil : match[1], match[2] == '' ? nil : match[2])
    end

    # Build a range for allocation of identifiers
    # @param range [String|Range]
    # @param within [Range] defines the bounds for the input range
    # @return [Range]
    def allocation_range(range, within: nil)
      range = parse_range(range) if range.is_a?(String)
      raise TypeError unless range.is_a?(Range)

      return range unless within

      range = within.begin..range.end unless range.begin
      range = range.begin..within.end unless range.end

      valid_range!(range, within:)
    end

    def valid_range!(range, within:)
      raise ArgumentError, "range(#{range}) must be within #{within}" unless within.cover?(range)

      range
    end
  end

  # A {RangeAllocator} that never re-uses ids. It simply increments a counter until the ids run out..
  # - next: O(1)
  # - free: not applicable
  class SimpleRange
    include RangeAllocator

    # @return [Integer] the next integer from the range
    # @return [nil] if we've reached the end of the range
    def next
      return nil if @next >= @range.end

      @next += 1
    end

    # This implementation is a no-op. Returned ids are never reused.
    def free(id)
      # no-op
    end

    # Reset allocation, so the whole initial range is available
    # @return [void]
    def reset
      @next = @range.begin - 1
    end
  end

  # A {RangeAllocator} that efficiently stores the set of available integers by compressing contiguous sequences into
  # ranges.
  # - next: O(1)
  # - free: O(logN) search, possible O(N) array re-allocation
  class RangeSet
    include RangeAllocator

    # Reset allocation, so the whole initial range is available
    # @return [void]
    def reset
      @ranges = [@range]
    end

    # optimized code
    # rubocop:disable Metrics, Style

    # Remove and return the lowest available identifier from the range
    #
    # Balance of predictable sequential allocation, and memory use
    # @return [Integer] the next id to allocate
    # @return [nil] if there are no more ids left to allocate
    def next
      return nil if @ranges.empty?

      range = @ranges.first
      value = range.begin

      if range.begin == range.end
        @ranges.shift
      else
        @ranges[0] = ((range.begin + 1)..range.end)
      end

      value
    end

    # Return an identifier to the pool
    #
    # This implementation uses a binary search to find where to insert the id, and attempts to merge it with the
    # available range on its left or right.
    # @param id [Integer]
    # @return [void]
    def free(id)
      raise RangeError unless range.cover?(id)

      # Binary search for insertion point
      idx = @ranges.bsearch_index { |r| r.begin > id } || @ranges.size

      # The id is already in the set
      return if idx > 0 && @ranges[idx - 1].end >= id

      # Try to merge with previous range
      if idx > 0 && @ranges[idx - 1].end + 1 == id
        @ranges[idx - 1] = (@ranges[idx - 1].begin..id)
        if @ranges[idx].begin == @ranges[idx - 1].end + 1
          @ranges[idx - 1] = (@ranges[idx - 1].begin..@ranges[idx].end)
          @ranges.delete_at(idx)
        end
        # Try to merge with next range
      elsif idx < @ranges.size && @ranges[idx].begin - 1 == id
        @ranges[idx] = (id..@ranges[idx].end)
      else
        # Insert new single-element range
        @ranges.insert(idx, id..id)
      end
    end

    # rubocop:enable Metrics,Style

    # @!visibility private
    def inspect
      "#<#{self.class} ranges=#{@ranges.inspect}>"
    end
  end
end
