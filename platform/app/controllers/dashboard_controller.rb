class DashboardController < ApplicationController
  before_action :require_login

  def show
    @wallet = current_user.active_wallet
    @installations = current_user.installations.includes(:repositories)
    @bounties = current_user.bounties.order(created_at: :desc).limit(20).includes(:repository)
    @app_slug = Rails.application.credentials.dig(:github, :app_slug)
  end
end
