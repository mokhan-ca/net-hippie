# frozen_string_literal: true

module Net
  module Hippie
    # Parses TLS certificates and keys from various formats.
    module TlsParser
      def parse_cert(cert)
        return cert if cert.is_a?(OpenSSL::X509::Certificate) || cert.nil?

        OpenSSL::X509::Certificate.new(cert)
      end

      def parse_key(key, passphrase)
        return key if key.is_a?(OpenSSL::PKey::PKey) || key.nil?

        passphrase ? OpenSSL::PKey::RSA.new(key, passphrase) : OpenSSL::PKey::RSA.new(key)
      end
    end
  end
end
