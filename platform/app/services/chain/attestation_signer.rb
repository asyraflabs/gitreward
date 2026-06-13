module Chain
  # Produces the EIP-712 disbursement signature the contract verifies, using the
  # oracle key (credentials) over the active network's domain. Delegates the
  # actual struct/domain encoding to the canonical GitReward::Attestation module
  # (repo-root oracle/attestation.rb) so the bytes match the Solidity verifier.
  module AttestationSigner
    module_function

    # Returns { signature:, digest:, signer:, chain_id:, verifying_contract: }.
    def sign(chain_bounty_id:, recipient:)
      raise ArgumentError, "recipient required" if recipient.blank?
      raise "escrow address not configured" unless Chain::Config.escrow_configured?

      args = {
        chain_id: Chain::Config.chain_id,
        verifying_contract: Chain::Config.escrow_address,
        bounty_id: chain_bounty_id,
        recipient: recipient
      }

      {
        signature: GitReward::Attestation.sign(private_key: Chain::Config.oracle_key.private_hex, **args),
        digest: GitReward::Attestation.digest(**args),
        signer: Chain::Config.oracle_signer_address,
        chain_id: args[:chain_id],
        verifying_contract: args[:verifying_contract]
      }
    end
  end
end
