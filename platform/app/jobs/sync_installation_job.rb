# Keeps Installation/Repository rows in sync when GitHub sends installation
# events (install, repos added/removed, suspended). Idempotent upsert.
class SyncInstallationJob < ApplicationJob
  queue_as :default

  def perform(payload)
    installation_id = payload.dig("installation", "id")
    return if installation_id.blank?

    if payload["action"] == "deleted"
      Installation.find_by(github_installation_id: installation_id)&.destroy
      return
    end

    Github::InstallationSync.call(installation_id.to_i)
  rescue StandardError => e
    Rails.logger.error("SyncInstallationJob failed: #{e.class}: #{e.message}")
    raise
  end
end
