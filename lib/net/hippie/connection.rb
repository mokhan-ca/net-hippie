# frozen_string_literal: true

module Net
  module Hippie
    # Persistent HTTP connection with automatic reconnection.
    class Connection
      RETRYABLE_ERRORS = [EOFError, Errno::ECONNABORTED, Errno::ECONNRESET, Errno::EPIPE, IOError].freeze

      def initialize(scheme, host, port, ipaddr, options = {})
        @mutex = Mutex.new
        @created_at = Time.now
        @http = build_http(scheme, host, port, ipaddr, options)
      end

      def run(request, &block)
        @mutex.synchronize do
          ensure_started
          execute(request, &block)
        end
      end

      def stale?(ttl)
        (Time.now - @created_at) > ttl
      end

      def close
        @mutex.synchronize { @http.finish if @http.started? }
      rescue IOError
        nil
      end

      def build_url_for(path)
        return path if path.start_with?('http')

        "#{@http.use_ssl? ? 'https' : 'http'}://#{@http.address}#{path}"
      end

      private

      def build_http(scheme, host, port, ipaddr, options)
        Net::HTTP.new(host, port).tap do |http|
          configure_timeouts(http, options)
          configure_ssl(http, scheme, options)
          configure_tls_client(http, options)
          http.ipaddr = ipaddr if ipaddr
        end
      end

      def configure_timeouts(http, options)
        http.open_timeout = options.fetch(:open_timeout, 10)
        http.read_timeout = options.fetch(:read_timeout, 10)
        http.write_timeout = options.fetch(:write_timeout, 10)
        http.keep_alive_timeout = options.fetch(:keep_alive_timeout, 30)
        http.max_retries = options.fetch(:max_retries, 1)
        http.continue_timeout = options[:continue_timeout] if options[:continue_timeout]
        http.ignore_eof = options.fetch(:ignore_eof, true)
      end

      def configure_ssl(http, scheme, options)
        http.use_ssl = scheme == 'https'
        return unless http.use_ssl?

        http.min_version = options.fetch(:min_version, :TLS1_2)
        http.verify_mode = options.fetch(:verify_mode, Net::Hippie.verify_mode)
        http.set_debug_output(options[:logger]) if options[:logger]
      end

      def configure_tls_client(http, options)
        http.cert = options[:tls_cert] if options[:tls_cert]
        http.key = options[:tls_key] if options[:tls_key]
      end

      def ensure_started
        @http.start unless @http.started?
      end

      def execute(request, retried: false, &block)
        block ? @http.request(request, &block) : @http.request(request)
      rescue *RETRYABLE_ERRORS
        raise if retried

        @http.finish if @http.started?
        @http.start
        execute(request, retried: true, &block)
      end
    end
  end
end
