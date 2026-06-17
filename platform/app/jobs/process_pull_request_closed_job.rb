# The merge handler (A.5 / docs/merge-correctness.md). On a merged PR that closes
# a funded bounty into the correct branch, with a linked author wallet: sign and
# submit the disbursement. Otherwise record and stand down (the bounty rides to
# expiry, where the maintainer refunds). All chain work happens here, off the
# webhook request, and is idempotent on the delivery id + the attestation index.
class ProcessPullRequestClosedJob < ApplicationJob
  queue_as :default

  def perform(payload, delivery_id)
    return if PullRequestEvent.exists?(github_delivery_id: delivery_id) # redelivery-safe

    resolver = Github::PullRequestResolver.new(payload)
    pr = resolver.pr
    merged = pr["merged"] == true

    result = merged ? resolver.resolve : nil
    bounty = result&.bounty

    event = PullRequestEvent.create!(
      bounty: bounty,
      github_pr_node_id: resolver.pr_node_id,
      pr_number: pr["number"],
      author_github_id: resolver.author_github_id,
      action: merged ? :closed_merged : :closed_unmerged,
      github_delivery_id: delivery_id,
      processed_at: Time.current
    )

    return unless merged          # abandoned PR never pays
    return unless bounty          # closed no funded bounty
    return unless bounty.funded?  # already disbursed/refunded

    # --- Merge-correctness (A.1 #3): merged into the designated branch? ---
    if resolver.base_ref != bounty.target_branch
      Rails.logger.info("Bounty #{bounty.id}: PR merged into #{resolver.base_ref}, not #{bounty.target_branch}; standing down")
      return
    end

    # The contract refuses to disburse at/after expiry (past-expiry bounties are
    # refund-only). Don't submit a doomed, gas-wasting tx — let it ride to refund.
    if bounty.expiry && !bounty.expiry.future?
      Rails.logger.info("Bounty #{bounty.id}: merged but past expiry (#{bounty.expiry}); refund-only, standing down")
      comment(resolver, bounty, expired_body(bounty))
      return
    end

    # --- Recipient resolution (A.1 #4): authoritative live wallet lookup ---
    author = User.find_by(github_user_id: resolver.author_github_id)
    wallet = author&.active_wallet
    unless wallet
      comment(resolver, bounty, no_wallet_body(bounty))
      return # bounty rides to expiry
    end

    disburse!(resolver, bounty, wallet, pr)
  end

  private

  def disburse!(resolver, bounty, wallet, pr)
    pr_ref = "#{bounty.repository.full_name}#PR#{pr['number']}@#{pr['merge_commit_sha']}"
    Disbursement::Processor.new(
      bounty,
      recipient_address: wallet.address,
      pr_ref: pr_ref,
      pr_author_github_id: resolver.author_github_id
    ).call

    comment(resolver, bounty, paid_body(bounty, wallet))
  rescue Disbursement::Processor::AlreadyProcessed
    Rails.logger.info("Bounty #{bounty.id} already disbursed; skipping")
  end

  def comment(resolver, bounty, body)
    Github::RepoClient.new(resolver.installation_id)
                      .post_comment(bounty.repository.full_name, bounty.github_issue_number, body)
  rescue StandardError => e
    Rails.logger.error("Comment failed for bounty #{bounty.id}: #{e.message}")
  end

  def paid_body(bounty, wallet)
    "✅ **GitReward:** bounty paid. **#{bounty.payout_base_units.to_d / Bounty::USDC_UNIT} USDC** " \
      "(after a #{bounty.fee_bps_snapshot / 100.0}% fee) was disbursed to `#{wallet.address}`. " \
      "Thanks for the contribution!"
  end

  def no_wallet_body(bounty)
    "⚠️ **GitReward:** this PR merged and closed a bountied issue, but the author has " \
      "**no linked wallet**, so the **#{bounty.amount_usdc} USDC** bounty could not be paid. " \
      "It will refund to the maintainer after expiry (#{bounty.expiry&.to_date})."
  end

  def expired_body(bounty)
    "⚠️ **GitReward:** this PR merged, but the **#{bounty.amount_usdc} USDC** bounty " \
      "**expired on #{bounty.expiry&.to_date}** and can no longer be disbursed — past-expiry " \
      "bounties are refund-only. The maintainer can refund it; re-fund the issue to pay this work."
  end
end
