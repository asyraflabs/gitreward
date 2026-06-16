class DashboardController < ApplicationController
  before_action :require_login

  PREVIEW = 6 # dashboard shows a short preview; full lists live on their own pages

  def show
    @wallet = current_user.active_wallet

    repos = current_user.repositories.order(:full_name)
    @repos_count = repos.count
    @repos_preview = repos.limit(PREVIEW)

    bounties = current_user.bounties.order(created_at: :desc).includes(:repository)
    @bounties_count = bounties.count
    @bounties_preview = bounties.limit(PREVIEW)
  end
end
