# frozen_string_literal: true

require 'base64'
require 'json'
require 'logger'
require 'monitor'
require 'net/http'
require 'openssl'
require 'resolv'
require 'timeout'

require 'net/hippie/client'
require 'net/hippie/connection'
require 'net/hippie/connection_pool'
require 'net/hippie/content_type_mapper'
require 'net/hippie/version'

module Net
  # High-performance HTTP client with connection pooling and DNS caching.
  module Hippie
    CONNECTION_ERRORS = [
      EOFError,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::EINVAL,
      Errno::EPIPE,
      Errno::ECONNABORTED,
      Errno::ETIMEDOUT,
      IOError,
      Net::OpenTimeout,
      Net::ProtocolError,
      Net::ReadTimeout,
      Net::WriteTimeout,
      OpenSSL::OpenSSLError,
      OpenSSL::SSL::SSLError,
      SocketError,
      Timeout::Error
    ].freeze

    BASIC_PREFIX = 'Basic '
    BEARER_PREFIX = 'Bearer '

    class << self
      attr_writer :logger, :verify_mode

      def logger
        @logger ||= Logger.new(nil)
      end

      def verify_mode
        @verify_mode ||= OpenSSL::SSL::VERIFY_PEER
      end

      def basic_auth(username, password)
        BASIC_PREFIX + ::Base64.strict_encode64("#{username}:#{password}")
      end

      def bearer_auth(token)
        BEARER_PREFIX + token
      end

      def default_client
        @default_client ||= Client.new(follow_redirects: 3, logger: logger)
      end

      def reset_default_client!
        @default_client = nil
      end

      %i[get post put patch delete head options].each do |method|
        define_method(method) do |*args, **kwargs, &block|
          default_client.with_retry(retries: 3) { |c| c.public_send(method, *args, **kwargs, &block) }
        end
      end

      def resolve(hostname, timeout: 5)
        Timeout.timeout(timeout) do
          addresses = Resolv.getaddresses(hostname)
          addresses.find { |a| a.match?(/^\d+\.\d+\.\d+\.\d+$/) } || addresses.first
        end
      end
    end
  end
end
