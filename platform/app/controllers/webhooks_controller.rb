require "openssl"

# Receives GitHub App webhooks. Verifies the HMAC signature, then dispatches.
# NEVER does chain work in the request — merge handling is enqueued (build plan
# §2). Idempotency is keyed on the delivery id (C.3 / docs/merge-correctness.md).
class WebhooksController < ApplicationController
  skip_forgery_protection

  def github
    payload_body = request.body.read
    unless valid_signature?(payload_body)
      head :unauthorized and return
    end

    event = request.headers["X-GitHub-Event"]
    delivery = request.headers["X-GitHub-Delivery"]
    payload = JSON.parse(payload_body)

    case event
    when "installation", "installation_repositories"
      SyncInstallationJob.perform_later(payload)
    when "pull_request"
      handle_pull_request(payload, delivery)
    end

    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def valid_signature?(body)
    secret = Rails.application.credentials.dig(:github, :webhook_secret)
    return false if secret.blank? || secret.include?("REPLACE")

    sig = request.headers["X-Hub-Signature-256"].to_s
    expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, body)
    ActiveSupport::SecurityUtils.secure_compare(sig, expected)
  end

  def handle_pull_request(payload, delivery)
    case payload["action"]
    when "opened", "reopened"
      ProcessPullRequestOpenedJob.perform_later(payload, delivery)
    when "closed"
      # Enqueue regardless of merged flag; the job records the event and decides.
      ProcessPullRequestClosedJob.perform_later(payload, delivery)
    end
  end
end
