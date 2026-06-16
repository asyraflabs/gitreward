require "test_helper"

# Smoke test: every redesigned authed view renders (200) with real data.
# Catches ERB/helper errors the public-page checks can't reach.
class ViewsRenderTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "12868523",
      info: { nickname: "jimmyasyraf", image: nil, email: "j@example.com" },
      credentials: { token: "gho_test" }
    )
    post "/auth/github"
    follow_redirect! # callback -> sessions#create -> dashboard

    @user = User.find_by!(github_user_id: 12868523)
    inst = Installation.create!(github_installation_id: 1, account_type: "user",
                                account_github_id: 12868523, installed_by_user: @user)
    @repo = inst.repositories.create!(github_repo_id: 1, full_name: "acme/widgets", default_branch: "main")
    @user.wallet_links.create!(address: "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955")
    @bounty = @repo.bounties.create!(
      funder_user: @user, github_issue_number: 7, target_branch: "main", status: "funded",
      amount: 50_000_000, fee_bps_snapshot: 300, expiry: 30.days.from_now,
      chain_bounty_id: 1, fund_tx_hash: "0xabc123"
    )
    # Funded + expired + owned by current user → exercises the refund-button branch.
    @expired = @repo.bounties.create!(
      funder_user: @user, github_issue_number: 8, target_branch: "main", status: "funded",
      amount: 25_000_000, fee_bps_snapshot: 300, expiry: 2.days.ago,
      chain_bounty_id: 2, fund_tx_hash: "0xdef456"
    )
  end

  teardown { OmniAuth.config.test_mode = false }

  test "authed views render without error" do
    {
      "dashboard" => dashboard_path,
      "bounties index" => bounties_path,
      "directory" => directory_path,
      "bounty show" => bounty_path(@bounty),
      "bounty show (expired, refundable)" => bounty_path(@expired),
      "payout wallet" => wallet_path
    }.each do |name, path|
      get path
      assert_response :success, "#{name} (#{path}) failed to render: #{response.status}"
    end
  end

  test "fund view renders" do
    # load_open_issues rescues any GitHub failure to [], and live_fee_bps rescues
    # the unconfigured chain to 300 — so the view renders without external deps.
    get new_bounty_path(repository_id: @repo.id)
    assert_response :success
  end
end
