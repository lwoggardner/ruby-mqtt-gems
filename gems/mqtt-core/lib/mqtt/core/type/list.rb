# frozen_string_literal: true

module MQTT
  module Core
    module Type
      # list of type
      class List
        attr_reader :type

        def initialize(type)
          @type = type
        end

        def item_type
          type
        end

        def default_value
          []
        end

        def read(io)
          result = []
          result << type.read(io) until io.eof?
          result.freeze
        end

        def write(value, io)
          value&.each { |v| type.write(v, io) }
        end

        # @return [Array<#type>]
        def from(arr, **)
          arr ||= []
          arr = [arr] unless arr.respond_to?(:map)
          arr.map { |v| type.from(v, **) }.freeze
        end
      end
    end
  end
end
