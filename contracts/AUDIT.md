# GitRewardEscrow — audit readiness & scope

This document prepares `GitRewardEscrow.sol` for an independent third-party
security audit (Phase 4, non-negotiable before mainnet). It states the scope, the
trust model, the **deliberately accepted** risks, and the results of the free
pre-audit passes (static analysis + author review). It is **not** a substitute for
a professional audit — author/AI self-review has blind spots; that's the whole
reason an independent audit exists.

## Scope

| | |
|---|---|
| In scope | `src/GitRewardEscrow.sol` (~250 lines) |
| Out of scope | OpenZeppelin libraries (`lib/`), tests, scripts, the off-chain Rails oracle |
| Solidity | 0.8.28 (checked arithmetic) |
| Dependencies | OpenZeppelin: `EIP712`, `ECDSA`, `SafeERC20`, `ReentrancyGuard`, `Ownable`, `IERC20Permit` |
| Token | USDC (6 decimals), set immutably at deploy; single token for v1 |
| Tests | 39 passing — unit, fuzz (512 runs), adversarial; cross-language EIP-712 round-trip (Ruby ↔ Solidity); plus a Foundry invariant suite |
| Deployed | Base Sepolia, exercised end-to-end (fund / disburse / refund) |

## What the contract does

Holds USDC against a GitHub issue and moves it exactly two ways:
- **`disburse(bountyId, recipient, oracleSig)`** — pays `amount·(1−fee)` to
  `recipient` and the fee to `treasury`, only if `oracleSig` is a valid EIP-712
  signature from the configured oracle over `(bountyId, recipient)` **and the
  bounty has not expired** (`block.timestamp < expiry`). Submitted by a relayer,
  but **the contract trusts the signature, not `msg.sender`.**
- **`refund(bountyId)`** — returns the full amount to the funder, callable only by
  the funder at/after expiry, no fee, no oracle.

One-shot lifecycle: `None → Funded → (Disbursed | Refunded)`.

## Trust model (what an attacker would target)

1. **Oracle signing key** — signs disbursement attestations. *If stolen,* an
   attacker can sign `disburse(bountyId, attackerAddress)` for every `Funded`
   bounty **that has not yet expired** and drain them. **This is the catastrophic
   case.** The contract is correct here (it verifies the signature and binds the
   recipient); the risk is key custody, handled off-chain. The theft window per
   bounty is bounded to `[fund, expiry)` — see the expiry-gate note below.
2. **Owner key (single EOA in v1)** — can `setOracleKey` to an attacker key, then
   sign disbursements. So the owner key is *also* fund-critical. It cannot,
   however, withdraw funds directly (no withdraw path) or alter a funded bounty's
   fee snapshot.
3. **Relayer key** — only pays gas. A leak loses gas, not funds (the contract
   trusts the signature, not the sender). Kept distinct from the oracle key.
4. **Replay / cross-bounty / cross-chain** — covered by one-shot status +
   signature binding `bountyId` + EIP-712 domain binding `chainId` and the
   verifying contract.

## Accepted v1 risks (deliberate — see build plan B.3)

These are **chosen**, not oversights, and an auditor should treat them as
in-design:

- **No on-chain caps** (`maxBounty`, `totalLocked`). Maximum loss from a key
  compromise = total USDC locked at that moment. Unbounded by design for v1.
- **No KMS/HSM, no key rotation use, no emergency pause, no disbursement delay.**
  The oracle key lives in the platform's encrypted credentials only.
- **Single-EOA owner** (no multisig).

## Expiry gate on disburse (amends frozen spec A.6)

`disburse` requires `block.timestamp < expiry`; `refund` requires
`block.timestamp >= expiry`. The two paths **partition cleanly at the expiry
boundary** — no overlap, no race. Consequences:

- A compromised oracle key can only redirect a bounty within `[fund, expiry)`.
  **Past-expiry bounties are theft-proof** — refundable by the funder only. This
  bounds the blast radius of the crown-jewel risk without any off-chain machinery.
- **Trade-off:** a PR merged in the final moments before expiry whose `disburse`
  tx mines at/after expiry will revert; the bounty then becomes refund-only and
  the contributor is not auto-paid (funds are not lost — they return to the
  maintainer). The oracle should not sign that close to the deadline; the platform
  pre-checks expiry and won't submit a doomed tx.
- This **amends Appendix A.6** (which originally specified no expiry check). The
  build plan's spec should be updated to match, or a "spec amendment" note added.

## Invariants (enforced; good targets for invariant tests)

- A bounty's status only moves forward: `Funded → Disbursed` or `Funded → Refunded`, never back, never reused.
- `disburse`/`refund` flip status **before** any transfer (checks-effects-interactions) and are `nonReentrant`.
- Fee = `amount * feeSnapshot / 10000` (floors); recipient gets the remainder ⇒ `paidToRecipient + paidToTreasury == amount`, no dust stranded, never overpaid.
- `feeSnapshot` is captured at fund time and never re-read from the live `feeRate`.
- `feeRate ≤ MAX_FEE` (1000 bps) always; `setFeeRate` reverts above it.
- `refund` requires `block.timestamp ≥ expiry` and `msg.sender == funder`.
- `disburse` requires `block.timestamp < expiry`; with refund's `≥ expiry` check
  the two paths partition at the boundary — a bounty is disbursable xor refundable
  at any instant, never both.

## Free pre-audit passes (results)

### Static analysis — Slither 0.11.5

`slither . --filter-paths "lib/|test/|script/"` → **6 results, 0 high, 0 medium.**

| Finding | Disposition |
|---|---|
| `reentrancy-benign` in `fund` (state written after `USDC.permit`) | Non-issue: `nonReentrant` guard; USDC is trusted and non-reentrant; the value-moving `safeTransferFrom` is already post-state-write. Slither classes it benign. |
| `timestamp` comparisons (`fund`, `refund`) | Accepted: expiry is days-scale; validator drift (±seconds) is immaterial. |
| `naming-convention` (`USDC` not mixedCase) | Intentional: `immutable` reference, capitalized like a constant. |
| `unindexed-event-address` (`TreasuryUpdated`, `OracleSignerUpdated`) | Optional nice-to-have: index the addresses for off-chain filtering. The money events (`Funded`/`Disbursed`/`Refunded`) already index the key addresses. |

### Author review

No high/medium issues found. `disburse` correctly verifies the EIP-712 signature
(OZ `ECDSA.recover` rejects malleable/high-s and zero signatures; `oracleSigner`
can never be the zero address), binds the recipient, enforces one-shot status, and
follows CEI with a reentrancy guard. `disburse` is gated strictly before expiry
and `refund` strictly at/after it, so the two paths can never both apply (no
race). `fund` tolerates a front-run permit via try/catch and reverts safely if the
resulting allowance is short. `refund` is funder-only, post-expiry, full-amount,
no fee. The residual risks are the **key custody** items above, not code defects.

> Reminder: these passes catch the easy/known classes and document the design.
> They do **not** replace an independent professional audit before mainnet, which
> is specifically there to find the subtle logic/economic bugs a free tool and the
> author cannot.

### Invariant testing — Foundry

`test/GitRewardEscrowInvariant.t.sol` drives random `fund`/`disburse`/`refund`
sequences (signing real EIP-2612 permits and oracle attestations) and asserts the
conservation invariant **escrow USDC balance == Σ amounts in `Funded` status**.

Result: **512 runs / 256,000 calls / 0 reverts**, invariant held throughout
(~85k calls each of fund/disburse/refund). This catches over/under-payment,
double-spend, stranded dust, and accounting drift across arbitrary sequences.

## Recommended before commissioning the paid audit

- Optionally index the two admin-event address params (`TreasuryUpdated`,
  `OracleSignerUpdated`).
- Hand the auditor this doc + Appendix A of the build plan (the frozen EIP-712 /
  interface spec) + the §3.4 threat model.
