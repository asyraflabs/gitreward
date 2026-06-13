class InstallationsController < ApplicationController
  before_action :require_login

  # Send the maintainer to GitHub to install the App on their repos.
  def new
    slug = Rails.application.credentials.dig(:github, :app_slug)
    if slug.blank? || slug.include?("REPLACE")
      redirect_to dashboard_path, alert: "GitHub App is not configured yet." and return
    end
    redirect_to "https://github.com/apps/#{slug}/installations/new", allow_other_host: true
  end

  # GitHub redirects back here after install with ?installation_id=...&setup_action=...
  def callback
    installation_id = params[:installation_id]
    if installation_id.blank?
      redirect_to dashboard_path, alert: "Install was cancelled." and return
    end

    Github::InstallationSync.call(installation_id.to_i, installed_by: current_user)
    redirect_to dashboard_path, notice: "GitHub App installed. Your repos are ready to fund."
  rescue StandardError => e
    Rails.logger.error("Install sync failed: #{e.class}: #{e.message}")
    redirect_to dashboard_path, alert: "Couldn't sync the installation. Try again."
  end
end
