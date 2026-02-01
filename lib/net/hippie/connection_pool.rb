# frozen_string_literal: true

module Net
  module Hippie
    # Thread-safe connection pool with LRU eviction.
    class ConnectionPool
      def initialize(max_size: 100, dns_ttl: 300)
        @max_size = max_size
        @dns_ttl = dns_ttl
        @connections = {}
        @monitor = Monitor.new
      end

      def checkout(key, &block)
        reuse(key) || create(key, &block)
      end

      def close_all
        @monitor.synchronize do
          @connections.each_value(&:close)
          @connections.clear
        end
      end

      private

      def reuse(key)
        @monitor.synchronize do
          return nil unless @connections.key?(key)

          conn = @connections.delete(key)
          return @connections[key] = conn unless conn.stale?(@dns_ttl)

          conn.close
          nil
        end
      end

      def create(key)
        conn = yield
        @monitor.synchronize do
          existing = reuse(key)
          if existing
            conn.close
            return existing
          end
          evict_lru if @connections.size >= @max_size
          @connections[key] = conn
        end
      end

      def evict_lru
        key, conn = @connections.first
        conn.close
        @connections.delete(key)
      end
    end
  end
end
