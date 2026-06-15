class BountiesController < ApplicationController
  before_action :require_login, except: %i[show]
  before_action :set_bounty, only: :show

  def index
    @bounties = current_user.bounties.order(created_at: :desc).includes(:repository)
  end

  def show
    @issue_title = issue_title_for(@bounty)
  end

  # Funding form: pick one of the maintainer's open issues, set amount + expiry.
  # The actual fund tx is signed in the browser (viem); see wallet_controller.js.
  def new
    @repository = current_user_repositories.find(params[:repository_id])
    @fee_bps = live_fee_bps
    @issues = load_open_issues(@repository)
    @min_usdc = 5
    @default_expiry_days = 90
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Repository not found or not yours."
  end

  # Records a `pending` bounty right after the user submits the fund tx in their
  # wallet. The indexer flips it to `funded` (and fills chain_bounty_id) when it
  # sees the Funded event — chain is the source of truth (C.1 / C.5 pending seam).
  def create
    repository = current_user_repositories.find(params[:repository_id])
    bounty = repository.bounties.build(
      funder_user: current_user,
      status: :pending,
      amount: bounty_params[:amount].to_i,
      fee_bps_snapshot: bounty_params[:fee_bps_snapshot].to_i,
      expiry: Time.at(bounty_params[:expiry].to_i).utc,
      github_issue_number: bounty_params[:github_issue_number].to_i,
      github_issue_node_id: bounty_params[:github_issue_node_id],
      target_branch: bounty_params[:target_branch].presence || repository.default_branch,
      issue_ref: bounty_params[:issue_ref],
      fund_tx_hash: bounty_params[:fund_tx_hash]
    )

    if bounty.save
      render json: { ok: true, redirect: bounty_path(bounty) }, status: :created
    else
      render json: { ok: false, errors: bounty.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { ok: false, errors: ["Repository not found"] }, status: :not_found
  rescue ActiveRecord::RecordNotUnique
    render json: { ok: false, errors: ["This issue already has an active bounty"] }, status: :conflict
  end

  private

  def set_bounty
    @bounty = Bounty.includes(:repository, :attestation).find(params[:id])
  end

  # Live issue title from GitHub (cached). Falls back to nil so the view shows
  # "Issue #N" if the App can't read it.
  def issue_title_for(bounty)
    repo = bounty.repository
    Rails.cache.fetch("issue_title/#{repo.github_repo_id}/#{bounty.github_issue_number}", expires_in: 1.hour) do
      Github::RepoClient.new(repo.installation.github_installation_id)
                        .issue(repo.full_name, bounty.github_issue_number)[:title]
    end
  rescue StandardError => e
    Rails.logger.info("issue_title_for(#{bounty.id}) failed: #{e.message}")
    nil
  end

  def current_user_repositories
    Repository.where(installation_id: current_user.installations.select(:id))
  end

  def bounty_params
    params.require(:bounty).permit(:amount, :fee_bps_snapshot, :expiry, :github_issue_number,
                                   :github_issue_node_id, :target_branch, :issue_ref, :fund_tx_hash)
  end

  # Live fee from the contract so display and on-chain enforcement never diverge
  # (A.2). Falls back to the configured default if the chain is unreachable.
  def live_fee_bps
    Chain::Client.new.fee_rate_bps
  rescue StandardError
    300
  end

  def load_open_issues(repository)
    installation_id = repository.installation.github_installation_id
    Github::RepoClient.new(installation_id).open_issues(repository.full_name).map do |i|
      {
        number: i[:number],
        title: i[:title],
        node_id: i[:node_id],
        issue_ref: Bounty.issue_ref_for(repository.full_name, i[:number]),
        has_active_bounty: repository.bounties.active.exists?(github_issue_number: i[:number])
      }
    end
  rescue StandardError => e
    Rails.logger.warn("Issue list unavailable: #{e.message}")
    []
  end
end
