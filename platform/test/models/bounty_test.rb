require "test_helper"

class BountyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(github_user_id: 1, github_login: "maint")
    inst = Installation.create!(github_installation_id: 1, account_type: "user", account_github_id: 1)
    @repo = inst.repositories.create!(github_repo_id: 1, full_name: "acme/widgets", default_branch: "main")
  end

  def build_bounty(**attrs)
    @repo.bounties.build({
      funder_user: @user, github_issue_number: 7, target_branch: "main",
      amount: 100_000_000, fee_bps_snapshot: 300, status: "funded"
    }.merge(attrs))
  end

  test "money helpers use integer base units and floor the fee like Solidity" do
    b = build_bounty(amount: 100_000_000, fee_bps_snapshot: 300)
    assert_equal 100.0, b.amount_usdc
    assert_equal 3_000_000, b.fee_base_units          # 3% of 100 USDC
    assert_equal 97_000_000, b.payout_base_units      # remainder, no dust stranded
  end

  test "fee rounds down and recipient gets the remainder" do
    b = build_bounty(amount: 5_000_001, fee_bps_snapshot: 300) # 5.000001 USDC
    assert_equal 150_000, b.fee_base_units            # floor(5_000_001 * 300 / 10000)
    assert_equal 4_850_001, b.payout_base_units
    assert_equal b.amount, b.fee_base_units + b.payout_base_units
  end

  test "usdc_to_base_units converts dollars to 6-decimal integer units" do
    assert_equal 5_000_000, Bounty.usdc_to_base_units(5)
    assert_equal 12_340_000, Bounty.usdc_to_base_units("12.34")
  end

  test "rejects amounts below the 5 USDC minimum" do
    b = build_bounty(amount: 4_999_999)
    assert_not b.valid?
    assert b.errors[:amount].present?
  end

  test "enforces one active bounty per issue" do
    build_bounty.save!
    dup = build_bounty
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end

  test "issue_ref_for is deterministic keccak of repo#issue" do
    ref = Bounty.issue_ref_for("acme/widgets", 7)
    assert_match(/\A0x[0-9a-f]{64}\z/, ref)
    assert_equal ref, Bounty.issue_ref_for("acme/widgets", 7)
  end
end
