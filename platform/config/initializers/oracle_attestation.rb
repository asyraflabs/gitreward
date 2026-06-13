# Load the canonical EIP-712 attestation definition shared with the contract's
# cross-language test (repo-root oracle/attestation.rb). Keeping ONE definition
# is the whole point of the Phase 1 gate — the Ruby signer and Solidity verifier
# must never diverge. This lives outside app/ (not Zeitwerk-managed), so require
# it explicitly here.
require Rails.root.join("..", "oracle", "attestation.rb").to_s
