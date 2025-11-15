# frozen_string_literal: true

module MQTT
  module V5
    class Client < MQTT::Core::Client
      # Enhanced authentication
      # @abstract
      class Authenticator
        class << self
          # @param [String] auth_method
          # @param [Class|Authenticator] authenticator
          def register(auth_method, authenticator)
            @authenticators ||= {}
            @authenticators[auth_method] = authenticator
          end

          #   @param [String<UTF8>|Class|Authenticator] auth_method
          #     * String will lookup a registered authenticator (see #{register} )
          #     * Class will be used to instantiate an Authenticator
          #     * Authenticator (or something that quacks like one) will be used directly
          #   @return [Authenticator]
          #   @raise [Error] if authentication_method is not valid
          def factory(auth_method)
            return nil unless auth_method

            if auth_method.is_a?(String)
              auth_method = @authenticators.fetch do
                raise ProtocolError, "Unknown authentication method #{auth_method}"
              end
            end

            return auth_method.new if auth_method.is_a?(Class)
            return auth_method if %i[start continue success failed].all? { |m| auth_method.respond_to?(m) }

            raise Error, "Invalid Authenticator #{auth_method}"
          end
        end

        # Start authentication
        # @!method start(authentication_method:, authentication_data: nil, **connect_props)
        #   @param [String] authentication_method
        #   @param [String] authentication_data
        #   @param [Hash<Symbol>] connect_props additional properties for connect packet
        #   @return [Hash<Symbol>] properties to merge into the connect data
        #      typically will include :authentication_data
        #      can include other connect packet properties

        # Initiate re-authentication
        # @!method reauthenticate(authentication_method:, authentication_data: nil, **auth_props)
        #   @param [String] authentication_method
        #   @param [String,nil] authentication_data
        #   @param [Hash<Symbol>] auth_props additional properties supplied to reauthenticate
        #   @return [Hash<Symbol>] properties to merge into the auth data
        #      typically will include :authentication_data
        #      can include other auth packet properties
        # @note this need not be implemented if re-authentication is not required

        # Continue authentication
        # @!method continue(authentication_method:, authentication_data: nil, **auth_props)
        #   @param [String] authentication_method
        #   @param [String] authentication_data
        #   @param [Hash<Symbol>] auth_props additional auth properties (from auth packet)
        #   @return [Hash<Symbol>] properties to merge into the auth packet
        #      typically will include :authentication_data
        #      can include other auth packet properties

        # Completion of successful authentication
        # @!method success(authentication_method:, authentication_data: nil, **auth_props)
        #   @param [String] authentication_method
        #   @param [String] authentication_data
        #   @param [Hash<Symbol>] auth_props additional auth properties (from connack or auth completion packet)
        #   @return [void]

        # Notification of failed authentication
        # @!method failed(reason_code:, **properties)
        #   @param [Integer] reason_code
        #   @param [Hash<Symbol>] properties of the failed connack or disconnect packet
        #   @return [void]
        # @note this is not guaranteed to be called
      end
    end
  end
end
