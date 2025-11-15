require_relative 'spec_helper'

require 'async/monitor'
require 'thread/monitor'

# Run the same specs against both concurrent_monitor implementations
# @param specs [Module] The spec module to include for each concurrent_monitor implementation

MONITORS = [Async::Monitor, Thread::Monitor].freeze

def self.test_with_monitors(specs, monitors: MONITORS)
  MONITORS.each do |klass|
    describe klass do
      if monitors.include?(klass)
        parallelize_me!

        let(:monitor_class) { klass }
        let(:monitor) { monitor_class.new_monitor }
        include ConcurrentMonitor
        include specs

        before do
          self.monitor = monitor_class.new_monitor
        end
      else
        it "tests #{specs}"
      end
    end
  end
end
