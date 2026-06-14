module Bounties
  # Posts the "this issue has a bounty" comment on the GitHub issue once funding
  # is confirmed on-chain (build plan §1.2 step 3). Triggered when the indexer
  # flips a bounty pending -> funded, so the announcement reflects real escrowed
  # funds, not an unconfirmed local row.
  module Announcer
    module_function

    def announce_funded(bounty)
      installation_id = bounty.repository.installation.github_installation_id
      Github::RepoClient.new(installation_id)
                        .post_comment(bounty.repository.full_name, bounty.github_issue_number, body(bounty))
    rescue StandardError => e
      Rails.logger.error("Bounty announce failed for ##{bounty.id}: #{e.class}: #{e.message}")
    end

    def body(bounty)
      <<~MD.strip
        💰 **GitReward bounty: #{bounty.amount_usdc} USDC**

        This issue is funded. Open a PR that closes it (e.g. `closes ##{bounty.github_issue_number}`)
        and get it merged into `#{bounty.target_branch}` — the bounty disburses automatically to your
        linked wallet, minus a #{bounty.fee_bps_snapshot / 100.0}% fee. No claim step.

        Make sure you've linked a payout wallet first, or the bounty refunds to the maintainer after
        #{bounty.expiry&.to_date}. Non-custodial: funds sit in an open-source escrow on Base.
      MD
    end
  end
end
