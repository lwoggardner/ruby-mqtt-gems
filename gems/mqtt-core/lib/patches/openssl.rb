# frozen_string_literal: true

require 'openssl'

if Gem::Version.new(OpenSSL::VERSION) < Gem::Version.new('3.3.0')
  module OpenSSL
    module SSL
      # Socket patches
      class SSLSocket
        # https://github.com/ruby/openssl/pull/771
        unless method_defined?(:readbyte)
          def readbyte
            getbyte or raise EOFError
          end
        end
      end
    end
  end
end
