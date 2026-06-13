# Off-chain webhook log (C.3): PR-open / PR-merge events tied to bounties, so the
# PR-open nudge (A.1 #4) and merge handling are traceable and idempotent. The
# unique github_delivery_id makes redelivered webhooks no-ops.
class PullRequestEvent < ApplicationRecord
  belongs_to :bounty, optional: true

  enum :action, {
    opened: "opened",
    closed_merged: "closed_merged",
    closed_unmerged: "closed_unmerged"
  }

  validates :github_pr_node_id, presence: true
  validates :github_delivery_id, presence: true, uniqueness: true

  def processed?
    processed_at.present?
  end
end
