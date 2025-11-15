# frozen_string_literal: true

require 'securerandom'

module MQTT
  module Core
    class Client
      # Client ID Helpers
      module ClientIdGenerator
        # Base method to generate a client id consisting of a prefix and random sequence of alphanumerics
        # @param [String] prefix
        # @param [Integer] length
        def generate_client_id(prefix: 'rb', length: 21)
          "#{prefix}#{SecureRandom.alphanumeric(length)}"
        end
      end
    end
  end
end
