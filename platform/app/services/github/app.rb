require "jwt"
require "openssl"

module Github
  # App-level GitHub auth: mints the short-lived JWT from the App private key and
  # exchanges it for per-installation access tokens. Installation tokens are what
  # authorize the oracle to read issues, comment, and act on a repo (A.5 / C.3).
  module App
    module_function

    def app_id      = Rails.application.credentials.dig(:github, :app_id)
    def app_slug    = Rails.application.credentials.dig(:github, :app_slug)
    def private_pem = Rails.application.credentials.dig(:github, :private_key)

    def configured?
      app_id.present? && private_pem.present? && !private_pem.include?("REPLACE")
    end

    # A ~10-minute JWT signed with the App's RSA key (GitHub max is 10 min).
    def jwt
      key = OpenSSL::PKey::RSA.new(private_pem)
      now = Time.now.to_i
      payload = { iat: now - 60, exp: now + 9 * 60, iss: app_id.to_s }
      JWT.encode(payload, key, "RS256")
    end

    # Octokit client authenticated as the App itself (for install metadata).
    def app_client
      Octokit::Client.new(bearer_token: jwt)
    end

    # Octokit client scoped to one installation (for repo actions). Tokens last
    # ~1h; we mint per use rather than cache to keep it simple and safe.
    def installation_client(installation_id)
      token = app_client.create_app_installation_access_token(installation_id)[:token]
      Octokit::Client.new(access_token: token)
    end
  end
end
