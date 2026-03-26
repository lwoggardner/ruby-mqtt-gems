# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/mqtt/core/range_allocator'

module MQTT
  describe RangeSet do
    let(:rs) { RangeSet.new(1..10) }

    describe '#initialize' do
      it 'accepts an initial range' do
        rs = RangeSet.new(1..10)
        _(rs.next).must_equal 1
      end
    end

    describe '#next' do
      it 'returns nil when exhausted' do
        rs = RangeSet.new(1..3)
        _(rs.next).must_equal 1
        _(rs.next).must_equal 2
        _(rs.next).must_equal 3
        _(rs.next).must_be_nil
      end

      it 'returns sequential values' do
        first = rs.next
        second = rs.next
        third = rs.next
        
        _(first).must_equal 1
        _(second).must_equal 2
        _(third).must_equal 3
      end
    end

    describe '#free' do
      it 'returns values to the pool' do
        rs = RangeSet.new(1..5)
        
        id1 = rs.next
        id2 = rs.next
        id3 = rs.next
        
        rs.free(id2)
        
        # Next allocation should reuse freed ID
        _(rs.next).must_equal 2
      end

      it 'merges contiguous ranges' do
        rs = RangeSet.new(1..10)
        
        # Allocate first 5
        5.times { rs.next }
        
        # Free them back in order
        rs.free(1)
        rs.free(2)
        rs.free(3)
        
        # Should merge into single range
        _(rs.next).must_equal 1
        _(rs.next).must_equal 2
        _(rs.next).must_equal 3
      end
    end

    describe '#reset' do
      it 'restores full range' do
        rs = RangeSet.new(1..5)
        
        rs.next
        rs.next
        rs.next
        
        rs.reset
        
        _(rs.next).must_equal 1
        _(rs.next).must_equal 2
      end
    end

    describe 'subscription identifier pool usage' do
      it 'allocates unique identifiers' do
        pool = RangeSet.new(1..10)

        ids = 5.times.map { pool.next }
        
        _(ids.uniq.size).must_equal 5
        ids.each { |id| _((1..10).cover?(id)).must_equal true }
      end

      it 'reuses freed identifiers' do
        pool = RangeSet.new(1..10)

        id1 = pool.next
        id2 = pool.next
        id3 = pool.next

        pool.free(id2)

        # Should reuse freed ID
        more_ids = 10.times.map { pool.next }.compact
        _(more_ids).must_include id2
      end

      it 'handles exhaustion gracefully' do
        pool = RangeSet.new(1..3)

        pool.next
        pool.next
        pool.next
        _(pool.next).must_be_nil

        pool.free(2)
        _(pool.next).must_equal 2
        _(pool.next).must_be_nil
      end

      it 'handles large ranges efficiently' do
        pool = RangeSet.new(1..268_435_455)

        id1 = pool.next
        id2 = pool.next
        _((1..268_435_455).cover?(id1)).must_equal true
        _((1..268_435_455).cover?(id2)).must_equal true
        _(id1).wont_equal id2

        pool.free(id1)
        pool.free(100)
        pool.free(1000)

        id3 = pool.next
        _((1..268_435_455).cover?(id3)).must_equal true
      end
    end
  end
end
