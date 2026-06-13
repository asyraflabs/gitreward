# Appendix C.3 — attestations (owner: off-chain audit log). Record of every
# Disbursement the oracle signed. The on-chain proof is the disburse tx; this is
# the human-readable trail incl. pr_ref (deliberately NOT on-chain).
class CreateAttestations < ActiveRecord::Migration[8.1]
  def change
    create_table :attestations do |t|
      # Idempotency: one disbursement attestation per bounty — never sign twice.
      t.references :bounty, null: false, foreign_key: true, index: { unique: true }
      t.string   :recipient_address, null: false      # what was signed
      t.string   :pr_ref, null: false                 # repo + PR number / merge commit; audit only
      t.bigint   :pr_author_github_id, null: false
      t.text     :signature, null: false              # the EIP-712 signature produced
      t.datetime :signed_at, null: false
      t.string   :submitted_tx_hash                   # the disburse tx that carried it

      t.timestamps
    end
  end
end
