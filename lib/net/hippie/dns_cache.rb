# frozen_string_literal: true

module Net
  module Hippie
    # Thread-safe DNS resolution cache with TTL.
    class DnsCache
      def initialize(timeout: 5, ttl: 300, logger: nil)
        @timeout = timeout
        @ttl = ttl
        @logger = logger
        @cache = {}
        @monitor = Monitor.new
      end

      def resolve(hostname)
        cached = get(hostname)
        return cached if cached

        ip = Net::Hippie.resolve(hostname, timeout: @timeout)
        set(hostname, ip)
        ip
      rescue Timeout::Error, Resolv::ResolvError => error
        @logger&.warn("[Hippie] DNS resolution failed for #{hostname}: #{error.message}")
        nil
      end

      def clear
        @monitor.synchronize { @cache.clear }
      end

      private

      def get(hostname)
        @monitor.synchronize do
          entry = @cache[hostname]
          entry[:ip] if entry && (Time.now - entry[:time]) < @ttl
        end
      end

      def set(hostname, ip_addr)
        @monitor.synchronize { @cache[hostname] = { ip: ip_addr, time: Time.now } }
      end
    end
  end
end
