# GitReward — Build Plan Toward Launch

A non-custodial bounty escrow for GitHub issues. Repo maintainers fund their own issues with USDC on Base; when a PR is merged, the platform (acting as oracle + relayer) automatically disburses the bounty to the contributor's pre-linked wallet, minus a small protocol fee. Unmatched bounties refund permissionlessly on a timer. Open-core: permissive contracts, copyleft platform, hosted service for revenue.

---

## 0. Guiding principles

- **The contract can never custody or misdirect principal.** Funds sit in the contract; release is authorized by a signed attestation that names the payout address; refund is permissionless on a timer and needs no key. This is the entire trust pitch — protect it above all features.
- **The signing key is the crown jewel.** In the auto-disburse model the key authorizes *both* "this merged" and "send it here." Its compromise is the one catastrophic failure. Key management is a first-class concern, not an afterthought (see §7).
- **The moat is liveness, discovery, and reputation — not the code.** Since the code is open, the hosted service wins on uptime, the cross-repo bounty directory, and a track record of clean settlements.
- **Don't say "trustless."** Say "non-custodial, one neutral oracle, you only pay gas to fund." One honest claim beats one that invites a takedown.
- **Ship the smallest thing that moves real USDC safely.** Every phase ends with something demonstrable on testnet, then mainnet.

---

## 1. Agreed architecture & flow

### 1.1 Who does what
- **Maintainer = funder = merge authority.** Only repo owners bounty their *own* issues. The person funding is the same person who merges, so "was this merged correctly?" is a fact about their own repo, not a judgment call about a stranger's. This removes all arbitration complexity. (Third-party funding of repos you don't own is explicitly deferred to a possible v2.)
- **Contributor** links a wallet on the platform *before* any payout is possible, then solves issues normally on GitHub.
- **Platform** plays three roles in one backend: the **web app** (humans interact), the **oracle** (turns the GitHub merge-fact into a signed on-chain attestation), and the **relayer** (submits the disbursement transaction and pays its gas).
- **Escrow contract** on Base holds USDC and moves it only two ways: refund to funder, or disburse per a validly-signed attestation.
- **Treasury** (a separate multisig) receives the protocol fee.

### 1.2 End-to-end flow
1. **Maintainer setup (once):** log in with GitHub OAuth; install the GitReward GitHub App on their repo(s). The App grants scoped read (issues), write (comments), and merge webhooks. Backend links GitHub user/org id ↔ installation id.
2. **Contributor setup (once, before claiming):** log in with GitHub OAuth; link a wallet address. Backend stores the GitHub-user → wallet mapping. Without this, a contributor cannot be paid.
3. **Fund (on the web platform):** maintainer picks one of their open issues from a list, enters an amount, and signs a single `fund` transaction in their wallet (USDC via `permit`). Contract holds the USDC, snapshots the fee rate and expiry. Backend posts a bounty comment on the issue via the App.
4. **Work & merge (on GitHub):** contributor opens a PR; maintainer merges it into the designated branch. The merge *is* the authorization.
5. **Auto-disburse (the magic moment):** GitHub fires a merge webhook to the backend. The backend confirms the PR closed the bountied issue on the correct branch, looks up the contributor's linked wallet, signs an EIP-712 attestation naming that wallet, then submits the release transaction and pays the gas. The contract verifies the signature and the bound address, transfers `amount × (1 − fee)` to the contributor and the fee to the treasury. Contributor's wallet is paid with zero action on their part. Backend updates the issue comment to "paid."
6. **Refund (no merge before expiry):** the maintainer calls `refund(bountyId)` themselves, unilaterally, after expiry. No oracle, no fee. Their money returns to them.

### 1.3 Why the recipient address must come from the attestation
At funding time the solver is unknown, so the contract has *no* recipient stored — only funder, amount, fee, expiry, issue ref. The recipient address arrives *inside the signed attestation* at disburse time. This is why the signing key is so powerful (it fills in the payee) and why §7 exists.

---

## 2. Technology stack (decided)

Unified Rails codebase. No React anywhere. The only browser JS is a thin viem island in a Stimulus controller — the same island every stack would have.

| Layer | Choice | Notes |
|---|---|---|
| Platform + oracle + relayer | **Ruby on Rails** (single app) | Most of the system is conventional backend (accounts, OAuth, webhooks, DB, dashboard) — Rails' home turf. |
| UI | **Hotwire / Turbo / Stimulus**, styled with **Tailwind CSS** | Server-rendered; wallet interaction is a small Stimulus controller. Use `tailwindcss-rails` (the standalone-binary gem) so styling needs no Node build step and stays consistent with the no-toolchain, importmap setup. |
| Async disbursement | **Sidekiq / ActiveJob** | Merge webhook enqueues a job: confirm → sign → submit. Never do chain work in the webhook request itself. |
| Browser chain calls | **viem** (in a Stimulus controller) | Connect wallet, sign `permit`, send `fund`. Framework-agnostic; works fine outside React. |
| Server chain calls | **`eth.rb` gem** | Sign EIP-712 attestations, submit disbursement txs, read events. Actively maintained; native `sign_typed_data` (EIP-712) support. |
| JS delivery | **importmaps** (Rails default), viem pinned to a single CDN `/+esm` bundle | Verified working: `bin/importmap pin viem` fails (its downloader doesn't follow viem's relative-import chunks → 404s), but `pin "viem", to: "https://cdn.jsdelivr.net/npm/viem@<ver>/+esm"` inlines the whole dep tree (`@noble`, `abitype`, `ox`) into one file and works in-browser. Keeps the no-build, no-`node_modules` simplicity. Accepts a runtime CDN dependency (fine for v1). esbuild/`vite_rails` is the alternative if vendoring locally is ever wanted. |
| GitHub login | **OmniAuth** | OAuth identity. |
| GitHub App / webhooks / API | **Octokit** | GitHub-maintained Ruby client. |
| Smart contract | **Solidity + Foundry** | Separate `contracts/` directory, permissively licensed. |
| Wallet connect UI | **Hand-rolled connect button for v1** | OnchainKit/RainbowKit/wagmi are React-only and aimed at frontend-heavy dApps — not this server-heavy design. Defer the fancy modal. |

**Cross-language watch point:** the EIP-712 attestation is signed by `eth.rb` (server) and verified by Solidity (contract). Both must agree byte-for-byte on the struct (field names, types, order, domain separator). Keep one canonical definition and derive both sides from it. Use only flat scalar fields (`address`, `uint256`, `bytes32`) — this also sidesteps a known `eth.rb` limitation around arrays in EIP-712.

---

## 3. Phase 1 — Protocol design (freeze before coding)

Everything downstream depends on these. Do not start the oracle or web until the attestation format and contract interface are frozen.

### 3.1 Attestation format (EIP-712)
The signed message the backend produces and the contract verifies. Fields to lock:
- `bountyId` — ties the attestation to a specific funded escrow.
- `recipient` — the contributor wallet to be paid. Bound into the signature so the contract pays exactly this address.
- `prRef` — canonical reference to the merged PR (repo + PR number, or commit SHA), as `bytes32` or an id.
- `feeRateSnapshot` — fee rate captured at funding time.
- `nonce` / `expiry` — replay and staleness protection.

Single canonical definition; Ruby signer and Solidity verifier both derive from it.

### 3.2 Contract interface (escrow)
- `fund(...)` — funder deposits USDC + sets terms + expiry. EIP-2612 `permit` to collapse approve+transfer into one transaction.
- `disburse(attestation, signature)` — submitted by the platform relayer. Verifies the signature came from the trusted oracle key, verifies the bound `recipient`, transfers `amount × (1 − fee)` to recipient and the fee to treasury, emits `Disbursed`. (Note: submitted by the relayer, but the contract trusts the *signature*, not the sender — so the relayer key cannot redirect funds.)
- `refund(bountyId)` — callable by funder after expiry, no oracle involvement, no fee; emits `Refunded`.
- Admin: `setFeeRate(...)` bounded by a hard-coded max (e.g. 10%) the owner cannot exceed; `setTreasury(...)`; `setOracleKey(...)` for rotation (§7); `pause()/unpause()` circuit breaker (§7).
- Views: bounty status, terms, fee snapshot.

### 3.3 Fee model
- Skim-on-release: contributor gets `amount × (1 − feeRate)`, treasury gets `amount × feeRate`, atomically in `disburse`.
- Fee **snapshotted at funding time**, never applied retroactively to locked bounties.
- Start low (target ~2.5–5%, well under the ~20%+ incumbent norm). The hard-coded max-fee cap is a *trust feature* — advertise it.
- Self-hosters set `feeRate = 0` and their own `treasury`.

### 3.4 Threat model (write it down, design against each)
- **Oracle key theft** → can sign false disbursements to attacker addresses, draining all active escrows. THE catastrophic case. Mitigations in §7.
- **Relayer key leak** → only loses gas money; cannot redirect funds (contract trusts the signature, not the sender). Keep it a *separate* key from the oracle signing key.
- **Oracle/platform downtime** → no disbursements happen, but every unmatched bounty self-refunds at expiry. Acceptable; document it.
- **Merge ambiguity** (squash/rebase/force-push/revert/renamed branch) → define precisely what counts as "merged into the correct branch" before writing the listener.
- **Wrong recipient** → because disbursement is automatic, the linked address must be one the *contributor explicitly confirmed*, so a bad address is their assertion, not platform liability.
- **Replay / cross-bounty reuse** → nonce + bountyId binding + expiry.

**Exit criteria:** EIP-712 struct, contract function signatures, events, fee math, and merge-correctness definition all written down and reviewed. Nothing below starts until frozen.

---

## 4. Phase 2 — Smart contract (the trust anchor)

- **Stack:** Solidity + Foundry. **License:** MIT/Apache in `contracts/LICENSE`.
- Implement `fund` / `disburse` / `refund` / admin / views per §3.2.
- Use OpenZeppelin for ECDSA, SafeERC20, reentrancy guard, access control, pausable. Do not hand-roll crypto.
- **Tests are the deliverable:** unit (happy paths), fuzz (amounts, fee math), adversarial (replay, wrong recipient, forged signature, disburse after refund, refund before expiry, fee-cap violation, paused-state behavior, signature malleability).
- Deploy to **Base Sepolia** testnet with test USDC.

**Exit criteria:** full suite green incl. adversarial cases; deployed and exercised on Base Sepolia; per-function gas measured.

---

## 5. Phase 3 — Rails platform (web + oracle + relayer)

- **License:** AGPLv3 for the app.
- **Models (core):** User (maintainer/contributor), Installation (GitHub App link), WalletMapping (GitHub user → wallet), Bounty (issue ref, amount, fee snapshot, expiry, status), Attestation (audit log of what was signed).
- **Auth:** OmniAuth GitHub OAuth for both maintainer and contributor login.
- **GitHub App:** Octokit; install flow, scoped permissions, webhook receiver endpoint for `pull_request.closed` (merged = true).
- **Funding UI:** Hotwire dashboard; issue picker (read via installation token); a Stimulus `wallet_controller.js` using viem to connect wallet, sign `permit`, send `fund`. viem loaded via an importmap CDN `/+esm` pin (no build step).
- **Auto-disburse job (Sidekiq):** on merge webhook → enqueue job → confirm PR satisfies bounty + correct branch → look up contributor wallet → sign EIP-712 attestation (oracle key) → submit `disburse` tx (relayer key, pays gas) → record attestation → update issue comment.
- **Discovery layer (the moat):** cross-repo directory of open bounties, backed by an event-driven read model so it's fast and doesn't hammer RPC.
- **Honest trust/status page:** settled count, total paid, zero-loss track record, plain-English trust model.

**Exit criteria:** end-to-end on testnet — maintainer funds via UI, a real merged PR triggers automatic disbursement to a contributor's linked wallet, with no contributor action.

---

## 6. Phase 4 — Hardening before real money

- **Security audit of the contract.** Non-negotiable before mainnet. Consider extracting `contracts/` into its own audited repo at this point.
- **Testnet beta with the waitlist:** invite the existing signups to run real flows with test USDC. Watch funding UX, merge edge-cases, and the disbursement path.
- **Bug-bounty / responsible disclosure** window before mainnet.
- **Mainnet deploy** with conservative caps (max bounty size, maybe max total locked) initially, raised as confidence grows.

**Exit criteria:** clean audit addressed; beta feedback incorporated; §7 controls live; mainnet contract deployed with caps.

---

## 7. Key management & security (first-class — the make-or-break)

Because auto-disburse means the oracle key authorizes payouts to attacker-chosen addresses if stolen, this is treated as its own workstream, not a footnote.

- **Two separate keys.** Oracle *signing* key (authorizes) vs relayer *gas* key (spends ETH). A leaked relayer key loses only gas; the signing key is the crown jewel. Never the same key.
- **Key in a KMS/HSM, not a file.** The private key should never sit as a plaintext string the app reads. Use a managed KMS (AWS/GCP KMS) so the key never leaves the vault — the backend asks the vault to sign; even a fully compromised server can't exfiltrate the key.
- **Isolate the signer from the public web app.** The webhook receiver can live in the Rails app; the signing call goes to a separate, locked-down path. Popping the website should not equal popping the key.
- **Rotation.** `setOracleKey(...)` on the contract so a suspected-compromised key can be revoked and replaced without redeploying or migrating funds. Rotation control guarded by a multisig.
- **Circuit breaker.** `pause()/unpause()` to halt all disbursement if compromise is suspected. Pause control guarded by a multisig (not the oracle key).
- **Optional disbursement delay/veto window.** Release N hours/minutes after attestation rather than instantly, so a key compromise can't drain everything in one block and anomalies can be caught. Can be tuned (e.g. instant for small bounties, delayed for large). Trades a little "instant magic" for a safety net.
- **Caps while young.** Per-bounty and total-locked caps bound the maximum loss from any compromise during the early period.
- **Hygiene.** Never log/commit/bake the key; scan repos for leaked secrets; pin and audit dependencies (supply-chain risk in the signing process).

**Minimum before mainnet with real funds:** key in KMS, signer isolated, two separate keys, rotation function, emergency pause, conservative caps. Delay window optional but cheap insurance.

---

## 8. Phase 5 — Open-source & business setup (do early, not last)

- **Monorepo, per-directory licensing:** AGPLv3 root; MIT/Apache `contracts/`; `LICENSING.md` explains the split. (Follows the Grafana model — AGPL keeps OSI "open source" status while protecting against a commercial fork-and-host. SSPL/BSL would forfeit the label and risk backlash from the open-source crowd, who are your users.)
- **CLA in place before the first external contribution.** Required if you ever want to dual-license the hosted version. Retrofitting means chasing every past contributor.
- **Self-hoster path:** the fee rate and treasury/oracle addresses are config variables; self-hosters set `feeRate = 0` and point treasury/oracle at their own keys. Provide a clear "deploy your own instance" guide. (A self-hoster is their own oracle — and thus must trust themselves; the neutral hosted oracle is a feature contributors may prefer.)
- **Positioning copy:** "non-custodial," "you only pay gas to fund," "self-refunding," fee compared honestly against the ~20%+ norm, max-fee cap advertised as a trust feature. Never "trustless."

---

## 9. Suggested sequencing

```
Phase 1 (design)         ───────▶ freeze before anything else
Phase 5 (repo/license)   ──┐      set up in parallel with Phase 2
Phase 2 (contract)       ──┴──────▶ Base Sepolia
Phase 7 (key mgmt)       ─────────▶ design alongside contract; controls land before mainnet
Phase 3 (Rails platform) ─────────▶ depends on 1 + 2
Phase 4 (audit/beta)     ─────────▶ gates mainnet
```

The hard, differentiating work is Phase 1 (protocol design), §7 (key management), and Phase 4 (hardening). Phase 3 is mostly conventional Rails plus a thin viem island. Resist starting the UI before the attestation format is frozen.

---

## 10. Risks to keep visible

- **Demand is unproven.** A dozen passive signups is weak signal. Use the Phase 4 testnet beta as the real go/no-go — learn whether maintainers actually fund real bounties before audit spend and mainnet polish.
- **Crypto-only narrows reach** by design. Accept it; target the aligned niche.
- **Auto-disburse concentrates trust in the signing key.** The whole "trust this system" claim rests on §7. This is the price of the magic-moment UX.
- **Single point of liveness.** The self-refund timer is what keeps that safe — it must work flawlessly before mainnet.
- **Fork pressure on the fee.** Mitigated by AGPL + liveness/discovery/reputation as the real moat, never fully eliminated. The hosted value must be real.
- **AI-PR spam attracted by bounties** burdens the maintainer's review queue; escrow doesn't solve it. Contributor reputation/screening is a possible v2.
- **`eth.rb` < viem in ecosystem depth.** Fewer guides when stuck on the server-side crypto. Keep the signing seam small and well-tested.

---

# Appendix A — Phase 1 Frozen Spec

This is the load-bearing artifact. The contract, the Rails oracle, and the Stimulus funding flow all compile against it. Frozen per the decisions in §3 plus the nine finalized choices below. Do not start coding until this is reviewed; do not silently deviate from it — changes here ripple across Solidity and Ruby simultaneously.

## A.1 Finalized decisions (the nine)

1. **Bounty identity & one-shot model.** Contract assigns a sequential `bountyId` at `fund`. The `repo+issue` reference is stored alongside but `bountyId` is canonical. One active bounty per issue for v1; no stacking, no top-ups. Each bounty is one-shot: `Funded → Disbursed` or `Funded → Refunded`, never reused.
2. **No nonce.** The one-shot status + EIP-712 domain separator (chainId + verifying contract) fully cover replay. No separate nonce field.
3. **Merge-correctness rule.** A `pull_request.closed` webhook with `merged == true`, where the PR (a) closed the bountied issue via GitHub closing-keyword linkage and (b) merged into the maintainer-designated target branch (default: repo default branch, chosen at fund time). Covers all three GitHub merge methods. Post-merge reverts are out of scope for v1.
4. **Recipient resolution via PR-open nudge + merge-time authority.** On `pull_request.opened` referencing a bountied issue, the oracle posts a comment: if the author has a linked wallet, "bounty disburses if this PR is merged"; if not, "link a wallet before merge or the bounty refunds to the owner" (and nudge to add the `closes #N` link if missing). This comment is informational only. The authoritative check is at merge time: oracle looks up the author's wallet live. Linked → disburse. Not linked → oracle does nothing; bounty rides to expiry → maintainer refunds. The payee unit is the GitHub PR author (co-authors out of scope for v1).
5. **No early cancellation.** Funds locked until disburse or expiry. No maintainer withdrawal before expiry.
6. **Expiry bounds.** Maintainer sets expiry at fund time. Default 90 days; minimum 7 days.
7. **Instant disbursement.** No delay/veto window in v1. Key-hardening (KMS, signer isolation, rotation, pause, delay) deferred to v2. The one v1 baseline: the oracle key lives in Rails encrypted credentials, never committed to git, never a plaintext env var.
8. **USDC on Base only.** Single token for v1.
9. **Fee.** On-chain `feeRate` state variable, snapshotted into each bounty at fund time, used at disburse. Start 3%. Hard-coded `MAX_FEE = 10%` the owner cannot exceed. Self-hosters call `setFeeRate(0)` on their own deployment. UI reads the live rate from the contract view so display and enforcement never diverge.

## A.2 The contract owns the fee; the platform does not

The fee is enforced on-chain, not in the Rails app. The contract stores `feeRate`, snapshots it at `fund`, and computes the split at `disburse`. A platform env var cannot be the source of truth — if it were, the split would not be enforceable on-chain and the non-custodial guarantee would break. The Rails app only *reads* the rate from the contract for display.

## A.3 EIP-712 attestation (the cross-language contract)

Minimal: two fields. This is the exact statement the oracle signs and the contract verifies. The Ruby signer (`eth.rb`) and the Solidity verifier MUST derive from this identical definition.

**Domain**
```
EIP712Domain {
  string  name              = "GitReward"
  string  version           = "1"
  uint256 chainId           = <Base chain id>      // 8453 mainnet, 84532 Sepolia
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

That is the complete signed message. The fee is already on-chain (snapshotted), `prRef` lives only in the off-chain audit log, and replay is covered by one-shot status + the domain. The signature authorizes exactly one statement: "pay `recipient` for `bountyId`."

**Ruby side (`eth.rb`), illustrative shape:**
```ruby
typed_data = {
  types: {
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
  },
  primaryType: "Disbursement",
  domain: { name: "GitReward", version: "1", chainId: CHAIN_ID, verifyingContract: ESCROW_ADDR },
  message: { bountyId: id, recipient: wallet }
}
signature = oracle_key.sign_typed_data(typed_data)
```

**Solidity side, illustrative shape:**
```solidity
bytes32 constant DISBURSEMENT_TYPEHASH =
    keccak256("Disbursement(uint256 bountyId,address recipient)");

function _hashDisbursement(uint256 bountyId, address recipient) internal view returns (bytes32) {
    bytes32 structHash = keccak256(abi.encode(DISBURSEMENT_TYPEHASH, bountyId, recipient));
    return _hashTypedDataV4(structHash); // OZ EIP712: domain-separates with name/version/chainId/address
}
```

Only flat scalar fields (`uint256`, `address`) — no arrays, sidestepping the known `eth.rb` EIP-712 array limitation.

## A.4 Contract interface

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
// (bountyId, recipient); requires status == Funded; sets Disbursed; transfers
// amount*(1-fee) to recipient and amount*fee to treasury. Emits Disbursed.
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
function setFeeRate(uint16 newFeeBps) external;   // require newFeeBps <= MAX_FEE
function setTreasury(address newTreasury) external;
function setOracleKey(address newOracleSigner) external; // rotation hook (v2 use)

// --- Views ---
function getBounty(uint256 bountyId) external view returns (Bounty memory);
function feeRate() external view returns (uint16);   // current bps, for UI display
function MAX_FEE() external view returns (uint16);    // constant, 1000 = 10%

// --- Events ---
event Funded(uint256 indexed bountyId, address indexed funder, uint256 amount, uint16 feeSnapshot, uint64 expiry, bytes32 issueRef);
event Disbursed(uint256 indexed bountyId, address indexed recipient, uint256 paidToRecipient, uint256 paidToTreasury);
event Refunded(uint256 indexed bountyId, address indexed funder, uint256 amount);
```

Invariants to enforce and test:
- `disburse` and `refund` each require `status == Funded`; both flip status before any transfer (checks-effects-interactions; reentrancy guard).
- `refund` requires `block.timestamp >= expiry`.
- `disburse` has no expiry check — a valid signature can disburse at any time while `Funded` (the oracle simply won't sign past the point it's appropriate).
- `setFeeRate` reverts if `newFeeBps > MAX_FEE`.
- Fee math uses the bounty's `feeSnapshot`, never the live `feeRate`.
- `feeSnapshot` is basis points (300 = 3%); `MAX_FEE` constant = 1000.

## A.5 Oracle (Rails) responsibilities

- `pull_request.opened` webhook → parse closing-keyword link → if it maps to a `Funded` bounty, post the nudge comment based on the author's wallet-link status.
- `pull_request.closed` (merged) webhook → enqueue Sidekiq job → verify merge-correctness (A.1 #3) → look up PR author's linked wallet → if linked, sign the `Disbursement` attestation and submit `disburse` (relayer pays gas) → record the attestation + `prRef` in the audit log → update the issue comment to "paid." If not linked, do nothing (bounty rides to expiry).
- Two separate keys conceptually even in v1: the **oracle signing key** (signs attestations) and the **relayer key** (holds ETH, submits txs). Same process is acceptable in v1, but keep them as distinct keys so a relayer-key leak is not a signing-key leak.

## A.6 State machine (authoritative)

```
                 fund()
   [None] ───────────────────▶ [Funded]
                                  │
              disburse()          │          refund()  (at/after expiry)
   recipient linked at merge      │          maintainer-initiated
        ┌─────────────────────────┴─────────────────────────┐
        ▼                                                     ▼
   [Disbursed]                                           [Refunded]
   (terminal)                                            (terminal)
```

The contract has no "merged" or "awaiting wallet" state. "Merged but recipient not linked" is represented by the bounty remaining `Funded` until expiry, then refunded.

## A.7 Phase 1 exit criteria (updated)

- This appendix reviewed and agreed (done when signed off).
- The EIP-712 definition reproduced identically in a Ruby fixture and a Solidity test, with a round-trip test: `eth.rb` signs, the Solidity verifier (via Foundry) recovers the expected oracle address. This single cross-language test is the most important gate in Phase 1 — it proves the byte-for-byte agreement that everything depends on.
- Merge-correctness rule expressed as concrete webhook-handling pseudocode.

---

# Appendix B — Phase 2 Resolutions & Launch Posture

Decisions settled when moving from Phase 1 (frozen spec) into Phase 2 (build). These refine, not replace, Appendix A.

## B.1 USDC permit — confirmed native on Base

Native USDC on Base supports EIP-2612 `permit` directly (Circle's USDC 2.0+). No Permit2 needed; Permit2 is only a fallback for tokens lacking native permit. The `fund` signature in A.4 stands as drafted with permit parameters.

**Two distinct EIP-712 domains in this system — do not conflate:**
- **USDC's permit domain:** `name "USDC"`, `version "2"`, the USDC token address as `verifyingContract`. The *funder* signs against this to authorize the escrow to pull their tokens.
- **GitReward's disbursement domain:** `name "GitReward"`, `version "1"`, the escrow contract as `verifyingContract`. The *oracle* signs against this to authorize a payout.
Different names, different version strings ("2" vs "1"), different contracts. Mixing them up is a likely bug source.

**USDC addresses:**
- Base Sepolia (test): `0x036CbD53842c5426634e7929541eC2318f3dCF7e` (domain chainId 84532, version "2").
- Base mainnet: native USDC — verify the current address from Circle's docs before mainnet. Use **native USDC, not bridged USDbC** (USDbC is a different, non-Circle token; do not use it).

## B.2 Finalized small decisions

- **Fee math:** integer arithmetic in basis points. Fee rounds down (`amount * feeBps / 10000`); recipient gets the remainder so the contract never over-pays or strands dust.
- **Minimum bounty:** 5 USDC, enforced with a `require` in `fund`.
- **Owner/admin (v1):** a single EOA (externally-owned account — a normal one-key wallet). The admin functions (`setFeeRate`, `setTreasury`, `setOracleKey`) are owner-gated. Moving owner to a **multisig** (a smart-contract wallet requiring M-of-N keys to act, e.g. Safe) is a deferred v2 hardening step.
- **Chain IDs:** Base Sepolia 84532 (test), Base mainnet 8453 (launch) — baked into the GitReward EIP-712 domain.

## B.3 Caps & key hardening — DEFERRED to v2 (risk accepted deliberately)

The following are intentionally **not** in v1, with the unbounded-loss risk consciously accepted by the project owner:
- No on-chain `maxBounty` cap.
- No on-chain `totalLocked` cap.
- No KMS / signer isolation (oracle key in Rails encrypted credentials only — never committed to git, never a plaintext env var; that single baseline IS kept in v1).
- No oracle-key rotation use, no emergency pause, no disbursement delay/veto window.
- Single-EOA owner (no multisig).

**Accepted consequence, in writing so it is not mistaken for an oversight:** with auto-disburse, an unhardened signing key, and no on-chain cap, a leaked oracle key allows a thief to disburse *every active Funded bounty at once* to an attacker address. The maximum loss is unbounded (= total USDC locked at the moment of compromise), it is other people's funds, and it is irreversible on an immutable contract. This was chosen knowingly to keep v1 minimal for an unproven project.

## B.4 Launch posture: testnet beta first, then mainnet — no hardening at launch

1. **Testnet beta (Base Sepolia, fake USDC):** run the full flow with the waitlist. Gate to mainnet = "the flow works and people actually fund bounties." This gate is about *functionality and demand only*.
2. **Mainnet launch (real USDC):** flip once the beta looks solid. **The B.3 items stay deferred — mainnet launches with NO v2 hardening.** No caps, no multisig, no key isolation/rotation/pause. The only security baseline present at launch is the oracle key living in Rails encrypted credentials (never in git, never plaintext env). Hardening is a genuine later-someday, not a pre-mainnet requirement.

**Important caveat (eyes-open):** the testnet beta de-risks *functionality* (does it work, is there demand) but does **NOT** de-risk *key-theft exposure*. That risk goes from zero to unbounded the instant mainnet + real USDC is live, independent of how clean the beta was. A successful beta does not imply mainnet is safe — the two are independent. The "everything looks okay" gate validates the product, not the security posture. Mainnet ships with the B.3 unbounded-loss risk fully in force and accepted.

---

# Appendix C — Database Schema (Rails)

## C.1 Source-of-truth principle

**On-chain is the source of truth for money state; the DB is a synced read-cache.** Money facts (bounty status, amount, fee, who got paid) live on-chain by design — that is the non-custodial thesis. The DB mirrors them by indexing contract events (`Funded`, `Disbursed`, `Refunded`) so Rails can render fast without hitting the chain per request. If DB and chain ever disagree, **the chain wins**, and the DB is rebuildable by replaying events from the contract.

**Off-chain data (GitHub identities, wallet mappings, issue/PR refs, oracle audit log) is DB-owned outright** — the chain knows nothing about it.

So each table is either a *mirror* of chain state or an *owner* of off-chain state. Noted per table below.

## C.2 Identity model

One `users` table. "Maintainer" and "contributor" are behaviors, not types — the same person can fund bounties and claim them. No role column needed unless/until roles gate features; behavior is inferred from relationships (do they have installations? do they have a wallet? have they authored paid PRs?).

## C.3 Tables

### users  — (owner: off-chain)
The human, identified by their GitHub account.
- `id` (pk)
- `github_user_id` (bigint, unique, not null) — GitHub's stable numeric id (never the username, which can change)
- `github_login` (string) — current username, for display; may change
- `github_avatar_url` (string, nullable)
- `email` (string, nullable) — from OAuth scope if granted
- `oauth_token` (encrypted) — for acting as the user via OAuth where needed
- timestamps
- index on `github_user_id`

### wallet_links  — (owner: off-chain)
A user's linked payout wallet. Separate table (not a column on users) so history/rotation is possible and so "has a wallet" is an explicit, auditable fact — the linchpin of auto-disburse.
- `id` (pk)
- `user_id` (fk → users, not null)
- `address` (string, not null) — checksummed EVM address
- `verified_at` (datetime, nullable) — if you later prove wallet ownership via a signature
- `active` (boolean, default true) — one active wallet per user at a time (enforce in app or partial unique index)
- timestamps
- index on `user_id`; index on `address`
- NOTE: the address used at disburse is whatever is `active` at merge time (A.1 #4). This table is that lookup.

### installations  — (owner: off-chain)
A GitHub App installation on a user's/org's repos. Links GitHub identity ↔ App permissions, and is how the oracle is authorized to read issues, comment, and receive merge webhooks.
- `id` (pk)
- `github_installation_id` (bigint, unique, not null) — from the App install callback
- `account_type` (enum: user, organization)
- `account_github_id` (bigint, not null) — the user or org the install belongs to
- `installed_by_user_id` (fk → users, nullable) — who clicked install, if known (install and OAuth can happen independently)
- `suspended_at` (datetime, nullable) — GitHub can suspend installs
- timestamps
- index on `github_installation_id`

### repositories  — (owner: off-chain)
Repos covered by an installation. Needed so the funding UI can list a maintainer's repos/issues and so the webhook handler can map an incoming event to an installation.
- `id` (pk)
- `installation_id` (fk → installations, not null)
- `github_repo_id` (bigint, unique, not null)
- `full_name` (string, not null) — "owner/repo"
- `default_branch` (string) — default target branch for bounties
- timestamps
- index on `github_repo_id`; index on `installation_id`

### bounties  — (MIRROR of chain + owner of off-chain refs)
The central table. Holds a cached copy of on-chain state PLUS the off-chain GitHub references the chain doesn't know.
On-chain mirror fields (authoritative on chain; synced from events):
- `chain_bounty_id` (bigint, unique, nullable until confirmed) — the contract's sequential `bountyId`
- `status` (enum: pending, funded, disbursed, refunded) — `pending` = local, fund tx not yet confirmed; the rest mirror chain `Status`
- `amount` (bigint) — USDC base units (6 decimals); store integer base units, not dollars
- `fee_bps_snapshot` (integer) — basis points captured on-chain at fund
- `expiry` (datetime)
- `funder_address` (string) — from the Funded event
- `recipient_address` (string, nullable) — set when Disbursed
Off-chain owned fields:
- `funder_user_id` (fk → users, not null) — who funded, by our identity
- `repository_id` (fk → repositories, not null)
- `github_issue_number` (integer, not null)
- `github_issue_node_id` (string) — stable GitHub id for the issue
- `target_branch` (string, not null) — chosen at fund time (A.1 #3)
- `issue_ref` (string/bytes32) — the value passed as `issueRef` on-chain, for audit correlation
Sync/tx metadata:
- `fund_tx_hash` (string, nullable)
- `disburse_tx_hash` (string, nullable)
- `refund_tx_hash` (string, nullable)
- timestamps
- Constraint: one active (funded/pending) bounty per (repository_id, github_issue_number) — enforces A.1 #1 "one active bounty per issue."
- indexes: `chain_bounty_id`, `status`, (`repository_id`, `github_issue_number`), `funder_user_id`

### attestations  — (owner: off-chain audit log)
Record of every Disbursement the oracle signed. Off-chain; the on-chain proof is the `disburse` tx, but this is the human-readable audit trail (incl. `prRef`, which deliberately is NOT on-chain).
- `id` (pk)
- `bounty_id` (fk → bounties, not null)
- `recipient_address` (string, not null) — what was signed
- `pr_ref` (string, not null) — repo + PR number / merge commit; audit only
- `pr_author_github_id` (bigint, not null)
- `signature` (text, not null) — the EIP-712 signature produced
- `signed_at` (datetime, not null)
- `submitted_tx_hash` (string, nullable) — the disburse tx that carried it
- timestamps
- index on `bounty_id`
- Idempotency: unique on `bounty_id` (one disbursement attestation per bounty — never sign twice).

### chain_sync_state  — (owner: indexer bookkeeping)
Single-row (or per-contract) table tracking how far the event indexer has processed, so the DB cache knows its own freshness and can resume.
- `id` (pk)
- `contract_address` (string, not null)
- `last_synced_block` (bigint, not null)
- `updated_at`

### pull_request_events  — (owner: off-chain, optional but useful)
Lightweight log of PR-open / PR-merge webhooks tied to bounties, so the PR-open nudge (A.1 #4) and merge handling are traceable and idempotent (don't double-comment, don't double-process a redelivered webhook).
- `id` (pk)
- `bounty_id` (fk → bounties, nullable) — null if PR didn't map to a bounty
- `github_pr_node_id` (string, not null)
- `pr_number` (integer)
- `author_github_id` (bigint)
- `action` (enum: opened, closed_merged, closed_unmerged)
- `processed_at` (datetime, nullable)
- `github_delivery_id` (string, unique) — webhook delivery id, for idempotency
- timestamps

## C.4 Relationships (summary)

- `User` has_many `wallet_links`, `installations` (via installed_by), funds many `bounties`.
- `Installation` has_many `repositories`.
- `Repository` has_many `bounties`.
- `Bounty` belongs_to `funder (User)` and `repository`; has_one `attestation`; has_many `pull_request_events`.
- `Attestation` belongs_to `bounty`.

## C.5 Schema-level notes

- **Money as integer base units everywhere** (USDC 6-decimals → store `5_000_000` for 5 USDC). Never floats. Mirrors the contract's integer math (B.2).
- **GitHub numeric ids over usernames** for all identity joins — usernames change, ids don't.
- **The `pending` bounty status** covers the gap between "user submitted the fund tx" and "indexer saw the `Funded` event." The UI shows it as pending; it becomes `funded` only when the event confirms. This is the seam where DB-as-cache meets chain-as-truth.
- **Rebuildability:** given the contract address and a fresh DB, replaying `Funded/Disbursed/Refunded` events fully reconstructs the on-chain mirror fields. Only the off-chain-owned data (identities, wallet links, audit log) is irreplaceable — back that up; the mirror is disposable.
