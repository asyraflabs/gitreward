# Rate limiting / abuse protection (Rack::Attack runs at the Rack layer, before
# the app, so blocked requests are cheap). Counters live in Rails.cache —
# solid_cache in production (shared across Puma workers), memory in dev.
# Tune limits up if they ever clip legitimate traffic.
class Rack::Attack
  Rack::Attack.cache.store = Rails.cache

  ### Allowlist ###
  # Never throttle local traffic (dev, health checks from the host/proxy).
  safelist("allow-localhost") { |req| ["127.0.0.1", "::1"].include?(req.ip) }

  ### Throttles ###

  # General backstop: any IP, excluding static assets and the health check.
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?("/assets", "/up")
  end

  # Public, unauthenticated webhook entry. HMAC rejects forgeries, but a flood
  # still costs work + can churn the job queue. Generous so GitHub's normal
  # delivery bursts aren't clipped.
  throttle("webhooks/ip", limit: 120, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/webhooks/github"
  end

  # OAuth start — abuse / loop protection.
  throttle("logins/ip", limit: 15, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/auth/github"
  end

  # Authenticated mutations (fund/refund/wallet) — guards against row/tx spam.
  throttle("writes/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.post? || req.patch? || req.put? || req.delete?
  end

  ### Response for throttled requests ###
  self.throttled_responder = lambda do |req|
    period = (req.env["rack.attack.match_data"] || {})[:period].to_i
    headers = { "Content-Type" => "text/plain", "Retry-After" => period.to_s }
    [429, headers, ["Too many requests — slow down and retry shortly.\n"]]
  end
end
