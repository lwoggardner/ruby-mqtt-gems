# frozen_string_literal: true

require_relative '../../errors'

module MQTT
  module Core
    class Client
      # Implements retry strategy with configurable backoff and jitter
      class RetryStrategy
        include Logger

        # @return [Integer] maximum number of retry attempts (default 0 = retry forever)
        attr_reader :max_attempts

        # @return [Float] initial interval in seconds to wait before retrying (default 1.0)
        attr_reader :base_interval

        # @return [Float] multiplier for exponential backoff (default 1.5)
        attr_reader :backoff

        # @return [Float] maximum interval in seconds (default 300)
        attr_reader :max_interval

        # @return [Float] percentage of random jitter to add to retry intervals, 0-100 (default 25.0)
        attr_reader :jitter

        def initialize(max_attempts: 0, base_interval: 1.0, backoff: 1.5, max_interval: 300, jitter: 25.0)
          @max_attempts = max_attempts.to_i
          @base_interval = base_interval.to_f
          @backoff = backoff.to_f
          @max_interval = max_interval.to_f
          @jitter = jitter.to_f
        end

        # This is the retry strategy interface. Caller will retry on completion of this method
        # if it does not raise an exception.
        # @param [Integer] retry_count
        # @param [Proc] raiser
        # @raise [StandardError] the error raised by raiser if retry count has exceeded max attempts
        # @return [Integer] slept duration in seconds
        def retry!(retry_count, &raiser)
          raiser.call
        rescue Error::Retriable, *RETRIABLE_NETWORK_ERRORS => e
          raise e if max_attempts.positive? && retry_count >= max_attempts

          log.error(e)
          duration = calculate_retry_duration(retry_count)
          log.warn { "Retry attempt #{retry_count} in #{duration.round(2)}s" }
          sleep(duration)
        end

        private

        # Calculate the retry duration with exponential backoff and jitter
        def calculate_retry_duration(retry_count)
          base_duration = [base_interval * (backoff**retry_count), max_interval].min
          max_jitter_amount = (base_duration * jitter / 100.0)
          base_duration + rand(-max_jitter_amount..max_jitter_amount)
        end
      end
    end
  end
end
