# A.1 #4 (PR-open nudge): when a PR referencing a funded bounty is opened, post
# an informational comment based on the author's wallet-link status. Purely
# informational — the authoritative check happens at merge time.
class ProcessPullRequestOpenedJob < ApplicationJob
  queue_as :default

  def perform(payload, delivery_id)
    return if PullRequestEvent.exists?(github_delivery_id: delivery_id) # idempotency

    resolver = Github::PullRequestResolver.new(payload)
    result = resolver.resolve

    event = PullRequestEvent.create!(
      bounty: result&.bounty,
      github_pr_node_id: resolver.pr_node_id,
      pr_number: resolver.pr["number"],
      author_github_id: resolver.author_github_id,
      action: :opened,
      github_delivery_id: delivery_id,
      processed_at: Time.current
    )

    bounty = result&.bounty
    return unless bounty # no funded bounty closed by this PR

    author = User.find_by(github_user_id: resolver.author_github_id)
    client = Github::RepoClient.new(resolver.installation_id)
    body = nudge_body(bounty, author)
    client.post_comment(bounty.repository.full_name, bounty.github_issue_number, body)
    event.update!(processed_at: Time.current)
  end

  private

  def nudge_body(bounty, author)
    amount = bounty.amount_usdc
    if author&.wallet_linked?
      "💰 **GitReward:** a bounty of **#{amount} USDC** will disburse automatically " \
        "to @#{author.github_login}'s linked wallet if this PR is merged into " \
        "`#{bounty.target_branch}`."
    else
      "💰 **GitReward:** this issue has a **#{amount} USDC** bounty. " \
        "⚠️ The PR author has **no linked wallet** — link one at GitReward before " \
        "this is merged, or the bounty refunds to the maintainer at expiry. " \
        "Also make sure the PR says `closes ##{bounty.github_issue_number}`."
    end
  end
end
