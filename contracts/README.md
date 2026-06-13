# GitRewardEscrow (contracts)

The trust anchor: a non-custodial USDC bounty escrow for GitHub issues, on Base.
MIT-licensed (see [`LICENSE`](./LICENSE)) so anyone can audit, fork, and
self-deploy. Built to the frozen spec in [Appendix A of the build
plan](../gitreward-build-plan.md).

**The contract can never custody or misdirect principal.** Funds move exactly
two ways:
- **refund** to the funder — permissionless, after expiry, no fee, no oracle;
- **disburse** per a valid EIP-712 attestation from the oracle key — the
  contract trusts the **signature**, not `msg.sender`, so a leaked relayer key
  cannot redirect funds.

## Quick start

```bash
forge build
forge test                 # 37 tests: unit, fuzz, adversarial, EIP-712 round-trip
forge test --gas-report
```

The live cross-language round-trip (real contract verifies an `eth.rb`
signature) is opt-in because it shells out to Ruby:

```bash
RUN_LIVE_EIP712=true forge test --match-test test_liveContract --ffi
```

## Interface (A.4)

```solidity
function fund(uint256 amount, uint64 expiry, bytes32 issueRef,
              uint256 permitValue, uint256 permitDeadline,
              uint8 permitV, bytes32 permitR, bytes32 permitS)
    external returns (uint256 bountyId);

function disburse(uint256 bountyId, address recipient, bytes calldata oracleSignature) external;
function refund(uint256 bountyId) external;

// admin (owner-gated)
function setFeeRate(uint16 newFeeBps) external;   // reverts if > MAX_FEE
function setTreasury(address newTreasury) external;
function setOracleKey(address newOracleSigner) external;

// views
function getBounty(uint256 bountyId) external view returns (Bounty memory);
function feeRate() external view returns (uint16);
function MAX_FEE() external view returns (uint16);    // 1000 = 10%
function MIN_BOUNTY() external view returns (uint256); // 5_000_000 (5 USDC)
function domainSeparator() external view returns (bytes32);
```

Status lifecycle is one-shot: `None → Funded → (Disbursed | Refunded)`.

### Key invariants (enforced + tested)

- `disburse`/`refund` require `status == Funded`; both flip status before any
  transfer (checks-effects-interactions + `nonReentrant`).
- `refund` requires `block.timestamp >= expiry`, callable only by the funder.
- `disburse` has no expiry check — a valid signature pays any time while `Funded`.
- Fee uses the bounty's `feeSnapshot`, never the live `feeRate`; fee rounds
  down, recipient gets the remainder (no dust stranded, never overpays).
- `setFeeRate` reverts above `MAX_FEE`; `MIN_BOUNTY` = 5 USDC; min duration 7 days.
- Signature malleability and forged/replayed signatures are rejected (OZ ECDSA +
  one-shot status).

## EIP-712 attestation (A.3) — the cross-language contract

The oracle signs, the contract verifies, and `eth.rb` must agree byte-for-byte.

```
Domain:  EIP712Domain { name "GitReward", version "1", chainId, verifyingContract }
Struct:  Disbursement { uint256 bountyId, address recipient }
Typehash: keccak256("Disbursement(uint256 bountyId,address recipient)")
```

The Ruby signer lives in [`../oracle/attestation.rb`](../oracle/attestation.rb);
the committed fixture in `test/fixtures/disbursement_fixture.json` is produced by
`ruby oracle/generate_fixture.rb` and verified by `EIP712RoundTrip.t.sol`.

> Do not conflate this with **USDC's permit domain** (`name "USDC"`,
> `version "2"`, the USDC token as `verifyingContract`), which the *funder* signs
> to authorize the pull. Different name, version, and contract (B.1).

## USDC addresses (B.1)

| Network      | chainId | USDC                                         |
|--------------|---------|----------------------------------------------|
| Base Sepolia | 84532   | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| Base mainnet | 8453    | native USDC — verify from Circle before mainnet; **not** bridged USDbC |

## Deploy

Set env, then run [`script/Deploy.s.sol`](./script/Deploy.s.sol):

```bash
export USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e   # Base Sepolia
export TREASURY=0x...        # fee recipient
export ORACLE_SIGNER=0x...   # public address of the oracle signing key
export OWNER=0x...           # admin EOA (v1)
export FEE_BPS=300           # 3%

forge script script/Deploy.s.sol --rpc-url "$BASE_SEPOLIA_RPC" \
  --private-key "$DEPLOYER_PK" --broadcast --verify
```

Self-hosters: deploy your own, point `TREASURY`/`ORACLE_SIGNER` at your keys, and
call `setFeeRate(0)` to run fee-free.

## v2 hardening (deliberately deferred — see build plan B.3)

No on-chain caps, no KMS/signer isolation, no key rotation use, no pause, no
disbursement delay, single-EOA owner. The `setOracleKey` rotation hook exists but
is unused in v1. Accepted consequence: a leaked oracle key can disburse every
active `Funded` bounty at once. This is consciously accepted for an unproven v1.
