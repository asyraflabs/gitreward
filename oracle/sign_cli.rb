# frozen_string_literal: true

require_relative "attestation"

# Thin CLI used by Foundry's FFI for a LIVE round-trip test: the Solidity test
# deploys the real escrow, reads its actual domain (chainId + address), and asks
# this script to sign — proving the deployed contract accepts an eth.rb signature
# end-to-end. Prints ONLY the 0x-prefixed signature so vm.ffi can decode it.
#
#   ruby oracle/sign_cli.rb <chainId> <verifyingContract> <bountyId> <recipient>
#
# Uses the same fixed test oracle key as the fixture (anvil account #0).
ORACLE_PRIVATE_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

chain_id, verifying_contract, bounty_id, recipient = ARGV

print GitReward::Attestation.sign(
  private_key: ORACLE_PRIVATE_KEY,
  chain_id: chain_id,
  verifying_contract: verifying_contract,
  bounty_id: bounty_id,
  recipient: recipient
)
