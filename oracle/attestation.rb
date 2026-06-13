# frozen_string_literal: true

require "eth"

# Canonical EIP-712 disbursement attestation, per Appendix A.3 of the build plan.
#
# This is the single source of truth on the Ruby side. The Solidity verifier
# (contracts/src/GitRewardEscrow.sol) MUST derive from the identical definition:
#
#   Domain:  name "GitReward", version "1", chainId, verifyingContract (escrow)
#   Struct:  Disbursement { uint256 bountyId, address recipient }
#
# Only flat scalar fields — no arrays — sidestepping the known eth.rb EIP-712
# array limitation. The signature authorizes exactly one statement:
# "pay `recipient` for `bountyId`".
#
# When this is folded into the Rails app (Phase 3), the oracle signing service
# requires this file and calls .sign with the key from encrypted credentials.
module GitReward
  module Attestation
    DOMAIN_NAME = "GitReward"
    DOMAIN_VERSION = "1"

    # eth.rb requires symbol keys (see Eth::Eip712.enforce_typed_data).
    TYPES = {
      EIP712Domain: [
        { name: "name", type: "string" },
        { name: "version", type: "string" },
        { name: "chainId", type: "uint256" },
        { name: "verifyingContract", type: "address" }
      ],
      Disbursement: [
        { name: "bountyId", type: "uint256" },
        { name: "recipient", type: "address" }
      ]
    }.freeze

    module_function

    # Build the EIP-712 typed-data structure for a disbursement.
    def typed_data(chain_id:, verifying_contract:, bounty_id:, recipient:)
      {
        types: TYPES,
        primaryType: "Disbursement",
        domain: {
          name: DOMAIN_NAME,
          version: DOMAIN_VERSION,
          chainId: Integer(chain_id),
          verifyingContract: verifying_contract
        },
        message: {
          bountyId: Integer(bounty_id),
          recipient: recipient
        }
      }
    end

    # Return the 65-byte signature as a 0x-prefixed hex string. eth.rb encodes
    # v as 27/28, matching OpenZeppelin's ECDSA.recover expectation.
    def sign(private_key:, chain_id:, verifying_contract:, bounty_id:, recipient:)
      key = Eth::Key.new(priv: private_key)
      data = typed_data(
        chain_id: chain_id, verifying_contract: verifying_contract,
        bounty_id: bounty_id, recipient: recipient
      )
      "0x#{key.sign_typed_data(data).sub(/\A0x/, '')}"
    end

    # The EIP-712 digest (the bytes that are signed), as 0x-prefixed hex.
    def digest(chain_id:, verifying_contract:, bounty_id:, recipient:)
      data = typed_data(
        chain_id: chain_id, verifying_contract: verifying_contract,
        bounty_id: bounty_id, recipient: recipient
      )
      "0x#{Eth::Eip712.hash(data).unpack1('H*')}"
    end

    # Address that produced a signature (for verifying our own output).
    def signer_address(private_key)
      Eth::Key.new(priv: private_key).address.to_s
    end
  end
end
