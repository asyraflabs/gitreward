# Appendix C.3 — pull_request_events (owner: off-chain). Lightweight log of
# PR-open / PR-merge webhooks tied to bounties, so the PR-open nudge (A.1 #4) and
# merge handling are traceable and idempotent (no double-comment, no double-process
# of a redelivered webhook).
class CreatePullRequestEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_request_events do |t|
      t.references :bounty, foreign_key: true          # nullable: PR may not map to a bounty
      t.string   :github_pr_node_id, null: false
      t.integer  :pr_number
      t.bigint   :author_github_id
      t.string   :action, null: false                  # opened|closed_merged|closed_unmerged
      t.datetime :processed_at
      t.string   :github_delivery_id, null: false      # webhook delivery id, for idempotency

      t.timestamps
    end
    add_index :pull_request_events, :github_delivery_id, unique: true
  end
end
