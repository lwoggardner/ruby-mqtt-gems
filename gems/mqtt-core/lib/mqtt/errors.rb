# frozen_string_literal: true

require 'socket'

module MQTT
  # Super-class for other MQTT related exceptions
  class Error < StandardError
    # included in protocol specific errors that are retriable
    module Retriable
    end
  end

  # Raised if there is a problem with data received from a remote host
  class ProtocolError < Error; end

  # Raised when trying to perform a function but no connection is available
  class ConnectionError < Error; end

  # Raised in the disconnect handler when the client expects a session, but the broker does not have one.
  class SessionNotPresent < Error; end

  # Raised in the disconnect handler when the client session has expired before it can reconnect to the broker.
  class SessionExpired < Error; end

  # Base timeout error can be used from application scenarios (eg request/response)
  class TimeoutError < Error; end

  # A ResponseError will be raised from packet acknowledgements
  class ResponseError < Error; end

  RETRIABLE_NETWORK_ERRORS = [
    Errno::ECONNABORTED,   # Connection aborted
    Errno::ECONNRESET,     # Connection reset
    Errno::EHOSTUNREACH,   # No route to host
    Errno::ENETUNREACH,    # Network unreachable
    Errno::EPIPE,          # Broken pipe
    Errno::ETIMEDOUT,      # Connection timed out
    Errno::EINVAL,         # Invalid argument (Windows-specific)
    SocketError,           # DNS and basic socket errors
    IOError                # Generic IO errors (including IO::TimeoutError)
  ].freeze
end
