# Off-chain audit log (C.3): record of every Disbursement the oracle signed.
# Unique on bounty_id — the idempotency guard that we never sign twice (A.5).
class Attestation < ApplicationRecord
  belongs_to :bounty

  validates :recipient_address, :pr_ref, :pr_author_github_id, :signature, :signed_at, presence: true
  validates :bounty_id, uniqueness: true
end
