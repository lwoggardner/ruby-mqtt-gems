# frozen_string_literal: true

require_relative 'shape'

module MQTT
  module Core
    module Type
      # Class representing an MQTT SubType (defined for structured lists)
      class SubType
        include Shape

        class << self
          # @!attribute [r] fields
          #   @return [Array] fields injected by List
          attr_reader :fields

          def read(io)
            new(io)
          end

          def write(value, io)
            value.serialize(io)
          end

          # TODO: if we had a subtype that was not within a list
          #       then we'd probably list the fields and pull top level content from the data
          def from(value, **)
            new(**value)
          end
        end
      end
    end
  end
end
