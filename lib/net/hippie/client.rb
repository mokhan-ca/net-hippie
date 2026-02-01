# frozen_string_literal: true

require 'net/hippie/dns_cache'
require 'net/hippie/tls_parser'

module Net
  module Hippie
    # HTTP client with connection pooling, DNS caching, and retry logic.
    class Client
      include TlsParser

      DEFAULT_HEADERS = {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        'User-Agent' => "net/hippie #{VERSION}"
      }.freeze

      JITTER = Random.new.freeze

      attr_reader :mapper, :logger, :follow_redirects

      def initialize(options = {})
        @options = options
        @mapper = options.fetch(:mapper, ContentTypeMapper.new)
        @logger = options.fetch(:logger, Net::Hippie.logger)
        @follow_redirects = options.fetch(:follow_redirects, 0)
        @default_headers = options.fetch(:headers, DEFAULT_HEADERS).freeze
        configure_pool(options)
        configure_tls(options)
      end

      %i[get post put patch delete].each do |method|
        define_method(method) do |uri, headers: {}, body: {}, stream: false, &block|
          run(uri, Net::HTTP.const_get(method.capitalize), headers, body, stream, &block)
        end
      end

      %i[head options].each do |method|
        define_method(method) do |uri, headers: {}, &block|
          run(uri, Net::HTTP.const_get(method.capitalize), headers, {}, false, &block)
        end
      end

      def execute(uri, request, limit: follow_redirects, stream: false, &block)
        conn = connection_for(uri)
        return conn.run(request) { |res| res.read_body(&block) } if stream && block

        return execute_with_block(conn, request, &block) if block

        response = conn.run(request)
        limit.positive? && response.is_a?(Net::HTTPRedirection) ? follow_redirect(uri, response, limit) : response
      end

      def with_retry(retries: 3)
        retries = [retries.to_i, 0].max
        0.upto(retries) do |attempt|
          return yield self
        rescue *CONNECTION_ERRORS => error
          raise if attempt == retries

          sleep_with_backoff(attempt, retries, error)
        end
      end

      def close_all
        @pool.close_all
        @dns_cache.clear
      end

      private

      def configure_pool(options)
        @dns_ttl = options.fetch(:dns_ttl, 300)
        @dns_cache = DnsCache.new(
          timeout: options.fetch(:dns_timeout, 5), ttl: @dns_ttl, logger: @logger
        )
        @pool = ConnectionPool.new(max_size: options.fetch(:max_connections, 100), dns_ttl: @dns_ttl)
      end

      def configure_tls(options)
        @tls_cert = parse_cert(options[:certificate])
        @tls_key = parse_key(options[:key], options[:passphrase])
        @continue_timeout = options[:continue_timeout]
        @ignore_eof = options.fetch(:ignore_eof, true)
      end

      def run(uri, method, headers, body, stream, &block)
        uri = URI.parse(uri.to_s) unless uri.is_a?(URI::Generic)
        execute(uri, build_request(method, uri, headers, body), stream: stream, &block)
      end

      def build_request(type, uri, headers, body)
        merged = headers.empty? ? @default_headers : @default_headers.merge(headers)
        path = uri.respond_to?(:request_uri) ? uri.request_uri : uri.path
        type.new(path, merged).tap { |req| req.body = @mapper.map_from(merged, body) unless body.empty? }
      end

      def execute_with_block(conn, request, &block)
        block.arity == 2 ? yield(request, conn.run(request)) : conn.run(request, &block)
      end

      def connection_for(uri)
        uri = URI.parse(uri.to_s) unless uri.is_a?(URI::Generic)
        key = [uri.scheme, uri.host, uri.port]
        @pool.checkout(key) { Connection.new(uri.scheme, uri.host, uri.port, @dns_cache.resolve(uri.host), conn_opts) }
      end

      def sleep_with_backoff(attempt, max_retries, error)
        delay = ((2**attempt) * 0.1) + JITTER.rand(0.05)
        logger&.warn("[Hippie] #{error.class}: #{error.message} | Retry #{attempt + 1}/#{max_retries}")
        sleep delay
      end

      def conn_opts
        @options.merge(
          tls_cert: @tls_cert, tls_key: @tls_key,
          continue_timeout: @continue_timeout, ignore_eof: @ignore_eof
        )
      end

      def follow_redirect(original_uri, response, limit)
        redirect_uri = original_uri.merge(response['location'])
        execute(redirect_uri, build_request(Net::HTTP::Get, redirect_uri, {}, {}), limit: limit - 1)
      end
    end
  end
end
