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

    # The webhook `sender` is the GitHub user who performed the install/change.
    # If they've signed in (so we have a User), link the installation to them —
    # this is what makes the dashboard show their repos. Works for org installs
    # too, where the account isn't a person but the sender is.
    installer = User.find_by(github_user_id: payload.dig("sender", "id"))
    Github::InstallationSync.call(installation_id.to_i, installed_by: installer)
  rescue StandardError => e
    Rails.logger.error("SyncInstallationJob failed: #{e.class}: #{e.message}")
    raise
  end
end
