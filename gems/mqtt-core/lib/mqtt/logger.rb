# frozen_string_literal: true

# Sugar for logging
require 'logger'
require 'delegate'

module MQTT
  # The MQTT Logger
  module Logger
    # @!visibility private
    # Adds classname info as progname to each log message
    class InstanceLogger < SimpleDelegator
      def initialize(obj)
        @obj = obj
        super(Logger.log)
      end

      %i[debug info warn error fatal].each do |lvl|
        lvl_check = :"#{lvl}?"
        lvl_const = ::Logger.const_get(lvl.upcase)
        define_method(lvl) do |message = nil, &block|
          next unless __get_obj__.public_send(lvl_check)

          add(lvl_const, message, &block)
        end
      end

      def add(severity, message = nil, &block)
        if block
          __get_obj__.add(severity, nil, @obj.log_name) { convert_message(block.call) }
        else
          __get_obj__.add(severity, convert_message(message), @obj.log_name)
        end
      end

      private

      def __get_obj__
        Logger.log
      end

      def convert_message(msg)
        case msg
        when Exception
          ["#{msg.class.name}: #{msg.message}", *(__get_obj__.debug? ? msg.backtrace : [])].join("\n")
        else
          msg
        end
      end
    end

    class << self
      # @!visibility private
      def configure(file: nil, shift_age: nil, shift_size: nil, level: nil)
        shift_age = Integer(shift_age) if shift_age
        shift_size = Integer(shift_size) if shift_size

        device = [file, shift_age, shift_size].compact
        if device.any?
          send(:log=, *device, level: (level || defined?(@log) ? @log.level : ::Logger::INFO))
        elsif level
          log.level = level
        end
      end

      # @!visibility private
      # Set the log device
      def log=(*device, level: defined?(@log) ? @log.level : ::Logger::INFO)
        @log = ::Logger.new(*device, level:)
      end

      # @!visibility private
      # The actual logger
      # @return [::Logger]
      # @example
      #   MQTT::Logger.log.warn! # set level to WARN
      def log
        @log ||= send(:log=, $stdout).tap { $stdout.sync = true }
      end
    end

    # @!visibility private
    def log
      @log ||= InstanceLogger.new(self)
    end

    # @!visibility private
    def log_name
      self.class.name
    end
  end
end
