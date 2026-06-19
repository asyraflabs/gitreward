# GitReward escrow — contract specification

The frozen, load-bearing spec for `GitRewardEscrow.sol`. The Solidity contract,
the Rails oracle (`eth.rb` signer), and the funding flow all compile against this
definition — it is the cross-language contract between them. The **deployed
contract is the source of truth**; this document describes its as-built behaviour.

## Model

- **One-shot bounties.** `fund` assigns a sequential `bountyId`; the `repo+issue`
  reference is stored alongside but `bountyId` is canonical. One active bounty per
  issue. Each bounty moves `Funded → Disbursed` or `Funded → Refunded`, never back,
  never reused.
- **Replay protection without a nonce.** The one-shot status plus the EIP-712
  domain separator (`chainId` + verifying contract) fully cover replay.
- **The contract owns the fee.** `feeRate` is on-chain state, snapshotted into each
  bounty at `fund` and applied at `disburse`. The platform only *reads* it for
  display, so the displayed rate and the enforced rate can never diverge. Start 3%,
  hard-capped at `MAX_FEE = 10%` (1000 bps) the owner cannot exceed. Self-hosters
  call `setFeeRate(0)`.
- **No early cancellation.** Funds are locked until disburse or expiry; no
  maintainer withdrawal before expiry.
- **USDC on Base only** (6 decimals), funded via EIP-2612 `permit` in a single tx.

## EIP-712 attestation (the cross-language contract)

The exact statement the oracle signs and the contract verifies. The Ruby signer
and the Solidity verifier MUST derive from this identical definition.

**Domain**
```
EIP712Domain {
  string  name              = "GitReward"
  string  version           = "1"
  uint256 chainId           = <Base chain id>   // 8453 mainnet, 84532 Sepolia
  address verifyingContract = <deployed escrow address>
}
```

**Typed struct**
```
Disbursement {
  uint256 bountyId
  address recipient
}
```

That is the complete signed message. The fee is already on-chain (snapshotted),
the PR reference lives only in the off-chain audit log, and replay is covered by
the one-shot status + domain. The signature authorizes exactly one statement:
"pay `recipient` for `bountyId`." Only flat scalar fields (`uint256`, `address`) —
no arrays.

```solidity
bytes32 constant DISBURSEMENT_TYPEHASH =
    keccak256("Disbursement(uint256 bountyId,address recipient)");
```

## Interface

```solidity
// Status lifecycle: None -> Funded -> (Disbursed | Refunded). One-shot.
enum Status { None, Funded, Disbursed, Refunded }

struct Bounty {
    address funder;
    uint256 amount;       // USDC, 6 decimals
    uint16  feeSnapshot;  // basis points, captured at fund time (e.g. 300 = 3%)
    uint64  expiry;       // unix seconds; refundable at/after this
    Status  status;
}

// --- Core ---

// Funder deposits USDC via EIP-2612 permit (single tx). Reads current feeRate,
// snapshots it, assigns sequential bountyId, sets status = Funded. Emits Funded.
function fund(
    uint256 amount,
    uint64  expiry,
    bytes32 issueRef,        // off-chain repo+issue reference, stored for audit
    uint256 permitValue,
    uint256 permitDeadline,
    uint8   permitV, bytes32 permitR, bytes32 permitS
) external returns (uint256 bountyId);

// Submitted by the platform relayer. Verifies the oracle signature over
// (bountyId, recipient); requires status == Funded AND block.timestamp < expiry;
// sets Disbursed; transfers amount*(1-fee) to recipient and amount*fee to
// treasury. Emits Disbursed.
// NOTE: the contract trusts the SIGNATURE, not msg.sender — a leaked relayer
// key cannot redirect funds.
function disburse(
    uint256 bountyId,
    address recipient,
    bytes calldata oracleSignature
) external;

// Callable by funder at/after expiry. Requires status == Funded. Sets Refunded;
// returns full amount (no fee). No oracle involvement. Emits Refunded.
function refund(uint256 bountyId) external;

// --- Admin (owner; later a multisig) ---
function setFeeRate(uint16 newFeeBps) external;          // require newFeeBps <= MAX_FEE
function setTreasury(address newTreasury) external;
function setOracleKey(address newOracleSigner) external; // rotation hook

// --- Views ---
function getBounty(uint256 bountyId) external view returns (Bounty memory);
function feeRate() external view returns (uint16);   // current bps, for UI display
function MAX_FEE() external view returns (uint16);   // constant, 1000 = 10%

// --- Events ---
event Funded(uint256 indexed bountyId, address indexed funder, uint256 amount, uint16 feeSnapshot, uint64 expiry, bytes32 issueRef);
event Disbursed(uint256 indexed bountyId, address indexed recipient, uint256 paidToRecipient, uint256 paidToTreasury);
event Refunded(uint256 indexed bountyId, address indexed funder, uint256 amount);
```

## Expiry gate

`disburse` and `refund` partition cleanly at the expiry boundary:

- `disburse` requires `status == Funded` **and** `block.timestamp < expiry`.
- `refund` requires `status == Funded` **and** `block.timestamp >= expiry`.

This bounds the blast radius of an oracle-key compromise: a leaked key can only
redirect a bounty within `[fund, expiry)` — **past-expiry bounties are
refundable by the funder only, and theft-proof.** The trade-off is that a
disburse transaction mined at or after expiry reverts; the platform pre-checks
expiry and the oracle will not sign that close to the deadline, so funds are
never lost (they become refund-only to the maintainer).

## State machine

```
                 fund()
   [None] ───────────────────▶ [Funded]
                                  │
            disburse()            │            refund()  (at/after expiry)
   recipient linked at merge,     │            funder-initiated
   before expiry                  │
        ┌─────────────────────────┴─────────────────────────┐
        ▼                                                     ▼
   [Disbursed]                                           [Refunded]
   (terminal)                                            (terminal)
```

The contract has no "merged" or "awaiting wallet" state. "Merged but recipient
not linked" is represented by the bounty remaining `Funded` until expiry, then
refunded.

## Invariants

- A bounty's status only moves forward: `Funded → Disbursed` or
  `Funded → Refunded`, never back, never reused.
- `disburse` / `refund` flip status **before** any transfer
  (checks-effects-interactions) and are `nonReentrant`.
- Fee = `amount * feeSnapshot / 10000` (floors); the recipient gets the remainder
  ⇒ `paidToRecipient + paidToTreasury == amount` — no dust stranded, never overpaid.
- Fee math always uses the bounty's `feeSnapshot`, never the live `feeRate`.
- `setFeeRate` reverts if `newFeeBps > MAX_FEE` (= 1000 bps).
- Minimums: `MIN_BOUNTY = 5 USDC`, `MIN_DURATION = 7 days`.

For the security posture, threat model, and audit analysis, see
[`../AUDIT.md`](../AUDIT.md). For how a merged PR maps to a disbursement, see
[`merge-correctness.md`](merge-correctness.md).
