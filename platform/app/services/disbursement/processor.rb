module Disbursement
  # The chain half of the magic moment (A.5): sign the EIP-712 attestation with
  # the oracle key, record it (idempotently — never sign twice), submit the
  # disburse tx via the relayer (which only pays gas), and update the issue
  # comment. Status flips to `disbursed` when the indexer sees the Disbursed
  # event (chain is source of truth, C.1) — we don't set it optimistically here.
  class Processor
    class AlreadyProcessed < StandardError; end

    def initialize(bounty, recipient_address:, pr_ref:, pr_author_github_id:)
      @bounty = bounty
      @recipient = recipient_address
      @pr_ref = pr_ref
      @pr_author_github_id = pr_author_github_id
    end

    def call
      existing = Attestation.find_by(bounty_id: @bounty.id)
      # "Done" means a tx was actually submitted — not merely that we started.
      # A prior attempt that died before submitting (e.g. a gas error) leaves an
      # attestation with no tx_hash, and we retry it here rather than skip.
      raise AlreadyProcessed, "bounty #{@bounty.id} already disbursed" if existing&.submitted_tx_hash.present?

      attestation = existing || create_attestation
      signed = Chain::AttestationSigner.sign(chain_bounty_id: @bounty.chain_bounty_id, recipient: @recipient)
      attestation.update!(signature: signed[:signature], signed_at: Time.current)

      tx_hash = Chain::Client.new.disburse(
        chain_bounty_id: @bounty.chain_bounty_id, recipient: @recipient, signature: signed[:signature]
      )

      attestation.update!(submitted_tx_hash: tx_hash)
      @bounty.update!(recipient_address: @recipient, disburse_tx_hash: tx_hash)
      attestation
    end

    private

    # The unique index on attestations.bounty_id guarantees a single attestation
    # per bounty even under concurrent webhooks; the loser re-finds the winner's.
    def create_attestation
      Attestation.create!(
        bounty: @bounty,
        recipient_address: @recipient,
        pr_ref: @pr_ref,
        pr_author_github_id: @pr_author_github_id,
        signature: "pending",
        signed_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique
      Attestation.find_by!(bounty_id: @bounty.id)
    end
  end
end
