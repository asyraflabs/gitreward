# frozen_string_literal: true

require "json"
require_relative "attestation"

# Generates the committed cross-language fixture consumed by
# contracts/test/EIP712RoundTrip.t.sol. Run:
#
#   ruby oracle/generate_fixture.rb
#
# The fixture pins a known oracle key, domain, and message so the Solidity test
# can recover the expected signer from an eth.rb-produced signature WITHOUT
# needing Ruby at test time. This is the Phase 1 byte-for-byte agreement gate.
#
# Fixed inputs (deterministic):
#   - oracle key: anvil default account #0 (a well-known test key, never used for funds)
#   - chainId 84532 (Base Sepolia)
#   - verifyingContract a fixed sentinel address
#   - bountyId 1, recipient a fixed sentinel address
ORACLE_PRIVATE_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
CHAIN_ID = 84_532
VERIFYING_CONTRACT = "0x000000000000000000000000000000000000C0DE"
BOUNTY_ID = 1
RECIPIENT = "0x000000000000000000000000000000000000bEEF"

fixture = {
  description: "EIP-712 Disbursement attestation signed by eth.rb. " \
               "Solidity must recover `expectedSigner` from `signature` over this digest.",
  domain: {
    name: GitReward::Attestation::DOMAIN_NAME,
    version: GitReward::Attestation::DOMAIN_VERSION,
    chainId: CHAIN_ID,
    verifyingContract: VERIFYING_CONTRACT
  },
  message: {
    bountyId: BOUNTY_ID,
    recipient: RECIPIENT
  },
  expectedSigner: GitReward::Attestation.signer_address(ORACLE_PRIVATE_KEY),
  digest: GitReward::Attestation.digest(
    chain_id: CHAIN_ID, verifying_contract: VERIFYING_CONTRACT,
    bounty_id: BOUNTY_ID, recipient: RECIPIENT
  ),
  signature: GitReward::Attestation.sign(
    private_key: ORACLE_PRIVATE_KEY, chain_id: CHAIN_ID,
    verifying_contract: VERIFYING_CONTRACT, bounty_id: BOUNTY_ID, recipient: RECIPIENT
  )
}

out = File.expand_path("../contracts/test/fixtures/disbursement_fixture.json", __dir__)
File.write(out, "#{JSON.pretty_generate(fixture)}\n")
puts "Wrote #{out}"
puts JSON.pretty_generate(fixture)
