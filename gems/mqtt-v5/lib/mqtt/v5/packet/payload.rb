# frozen_string_literal: true

module MQTT
  module V5
    module Packet
      # Common methods for PUBLISH and CONNECT (will) payload handling.
      module Payload
        # @api private
        # Sets :payload_format_indicator and :content_type properties for outgoing packets
        # based on the supplied payload's encoding.
        # The payload is **not** validated against the encoding or content_type
        #
        # **Binary** - does nothing.
        #
        #   Use `.b` when sending the payload to avoid this automation, leaving any :payload_format_indicator
        #   or :content_type properties untouched.
        #
        # **UTF-8**
        #
        #   :payload_format_indicator to set to 1, leaves :content_type untouched.
        #
        # **Other encodings**
        #
        #   :payload_format_indicator is removed (defaults to 0)
        #
        #   :content_type...
        #   * where not provided is set to `text/plain; charset=#{encoding.name.downcase}`
        #   * provided without 'charset' has charset appended
        #   * otherwise is left as is
        #
        # @return [void]
        def apply_payload_encoding(properties, encoding)
          return if encoding == Encoding::ASCII_8BIT

          if encoding == Encoding::UTF_8
            properties[:payload_format_indicator] = 1
          else
            properties.delete(:payload_format_indicator)

            user_ct = properties.fetch(:content_type, '') || ''
            unless user_ct.include?('charset')
              user_ct = 'text/plain' if user_ct.empty?
              properties[:content_type] = "#{user_ct}; charset=#{encoding.name.downcase}"
            end
          end
        end

        # Match charset= in a content_type
        CHARSET_PATTERN = /charset=\s*"?([^";\s]+)"?/i

        # @api private
        # Uses payload_format_indicator and content_type to force the encoding for the payload string on an incoming
        # Packet. The payload is **not** validated against the discovered encoding.
        #
        # * Where payload_format_indicator is set to 1, the encoding is forced to **UTF-8**
        # * If the content_type includes a 'charset' expression, then it is used to find and force the encoding
        # * Otherwise, or if an encoding is not found, the payload remains **Binary**
        #
        # @note the payload is frozen after deserialization. To use a different encoding, first convert to binary -
        #   `payload.b.force_encoding(new_encoding)`
        # @return [void]
        def force_payload_encoding(payload, payload_format_indicator, content_type)
          return payload.force_encoding(Encoding::UTF_8) if payload_format_indicator == 1

          return unless content_type&.include?('charset=')

          if (match = CHARSET_PATTERN.match(content_type))
            begin
              payload.force_encoding(Encoding.find(match[1]))
            rescue StandardError
              nil
            end
          end
        end
      end
    end
  end
end
