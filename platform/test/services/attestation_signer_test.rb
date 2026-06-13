require "test_helper"

# Guards the Phase 1 cross-language invariant from inside the app: the canonical
# signer the oracle uses must reproduce the committed fixture that the Solidity
# verifier accepts. If this drifts, disbursements would be rejected on-chain.
class AttestationSignerTest < ActiveSupport::TestCase
  FIXTURE = JSON.parse(
    File.read(Rails.root.join("..", "contracts", "test", "fixtures", "disbursement_fixture.json"))
  )
  ORACLE_PK = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

  test "in-app signer reproduces the committed cross-language fixture byte-for-byte" do
    args = {
      chain_id: FIXTURE.dig("domain", "chainId"),
      verifying_contract: FIXTURE.dig("domain", "verifyingContract"),
      bounty_id: FIXTURE.dig("message", "bountyId"),
      recipient: FIXTURE.dig("message", "recipient")
    }

    assert_equal FIXTURE["digest"], GitReward::Attestation.digest(**args)
    assert_equal FIXTURE["signature"], GitReward::Attestation.sign(private_key: ORACLE_PK, **args)
    assert_equal FIXTURE["expectedSigner"], GitReward::Attestation.signer_address(ORACLE_PK)
    # NOTE: end-to-end delegation through Chain::AttestationSigner + the deployed
    # contract is exercised by the anvil round-trip (see platform/README dev flow)
    # and the contract's EIP712RoundTrip Foundry test.
  end
end
