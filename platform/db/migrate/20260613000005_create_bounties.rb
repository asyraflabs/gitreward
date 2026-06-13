# Appendix C.3 — bounties (MIRROR of chain + owner of off-chain refs). Central
# table: cached on-chain state PLUS the GitHub references the chain doesn't know.
# Chain is source of truth (C.1); these mirror fields are rebuildable from events.
class CreateBounties < ActiveRecord::Migration[8.1]
  def change
    create_table :bounties do |t|
      # --- on-chain mirror (authoritative on chain; synced from events) ---
      t.bigint   :chain_bounty_id                     # contract's sequential bountyId; null until confirmed
      t.string   :status, null: false, default: "pending" # pending|funded|disbursed|refunded
      t.bigint   :amount                              # USDC base units (6 decimals); integer, never floats
      t.integer  :fee_bps_snapshot                    # basis points captured on-chain at fund
      t.datetime :expiry
      t.string   :funder_address                      # from Funded event
      t.string   :recipient_address                   # set when Disbursed

      # --- off-chain owned ---
      t.references :funder_user, null: false, foreign_key: { to_table: :users }
      t.references :repository, null: false, foreign_key: true
      t.integer :github_issue_number, null: false
      t.string  :github_issue_node_id                 # stable GitHub id for the issue
      t.string  :target_branch, null: false           # chosen at fund time (A.1 #3)
      t.string  :issue_ref                            # value passed as issueRef on-chain (audit correlation)

      # --- sync/tx metadata ---
      t.string :fund_tx_hash
      t.string :disburse_tx_hash
      t.string :refund_tx_hash

      t.timestamps
    end

    add_index :bounties, :chain_bounty_id, unique: true
    add_index :bounties, :status
    add_index :bounties, %i[repository_id github_issue_number]
    # One active (pending/funded) bounty per issue (A.1 #1 / C.3).
    add_index :bounties, %i[repository_id github_issue_number],
              unique: true, where: "status IN ('pending','funded')",
              name: "index_one_active_bounty_per_issue"
  end
end
