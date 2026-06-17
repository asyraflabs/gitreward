# GitReward — security audit readiness & scope

Prepares GitReward for independent third-party security review before mainnet
(Phase 4, non-negotiable). It has **two parts** — both matter, and a contract
audit alone does not cover the second:

- **Part 1 — Smart contract** (`GitRewardEscrow.sol`): the on-chain trust anchor.
- **Part 2 — Rails platform**: holds the **oracle signing key** (the crown jewel)
  and ingests untrusted GitHub webhook input.

This records the free pre-audit passes (static analysis + author review) and the
**deliberately accepted** v1 risks. It is **not** a substitute for professional
review — author/AI self-review has blind spots; that's the whole point of an
independent audit.

---

# Part 1 — Smart contract (`GitRewardEscrow.sol`)

## Scope

| | |
|---|---|
| In scope | `contracts/src/GitRewardEscrow.sol` (~250 lines) |
| Out of scope | OpenZeppelin libraries (`contracts/lib/`), tests, scripts |
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

## Free pre-audit passes

### Static analysis — Slither 0.11.5

From `contracts/`: `slither . --filter-paths "lib/|test/|script/"` → **6 results, 0 high, 0 medium.**

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

### Invariant testing — Foundry

`contracts/test/GitRewardEscrowInvariant.t.sol` drives random `fund`/`disburse`/`refund`
sequences (signing real EIP-2612 permits and oracle attestations) and asserts the
conservation invariant **escrow USDC balance == Σ amounts in `Funded` status**.

Result: **512 runs / 256,000 calls / 0 reverts**, invariant held throughout
(~85k calls each of fund/disburse/refund). Catches over/under-payment,
double-spend, stranded dust, and accounting drift across arbitrary sequences.

---

# Part 2 — Rails platform

The contract is the trust anchor, but the platform is the higher-value
*operational* target: it holds the **oracle signing key** and ingests untrusted
GitHub webhook input. A contract audit covers none of this.

## Static analysis — Brakeman 8.0.5

`bin/brakeman` → **0 warnings** after triaging one weak-confidence false positive:

| Finding | Disposition |
|---|---|
| `LinkToHref` XSS — `Bounty#issue_url` in a `link_to` href (`bounties/show`) | **False positive** (recorded in `platform/config/brakeman.ignore`). `issue_url` is server-built `https://github.com/{full_name}/issues/{number}`; `full_name` is GitHub-sourced (`owner/repo`, format-constrained) and `number` is an integer column, so the href is always a well-formed `https://github.com` URL and can never be a `javascript:` scheme. |

## Dependency & secret scanning

- **`bundle audit`** (bundler-audit, ruby-advisory-db, 1,145 advisories) →
  **no vulnerable gems.** Brakeman doesn't check dependency CVEs; this does.
- **`gitleaks`** over the working tree + all git history → **no leaks** (config in
  `.gitleaks.toml`). `master.key` has **never** been committed (0 commits). The
  only raw matches were OpenZeppelin's vendored test fixtures (`contracts/lib/`)
  and the **well-known public anvil/hardhat default keys** used for local dev/tests
  — both allowlisted with documented reasons. No real secret has ever been
  committed; live secrets stay in encrypted credentials (ciphertext) + the
  gitignored `master.key`.

## Author review by risk area

### Secrets — the oracle & relayer keys (crown jewel)
- Stored only in Rails **encrypted credentials**; `master.key` is gitignored.
  Per-network namespacing (`chain.<network>.{oracle,relayer}_key`). Never a
  plaintext env var, never logged, never sent to a view/param.
- Oracle and relayer are **distinct keys** — a relayer leak loses only gas.
- **Accepted v1 risk (§7 / B.3):** no KMS/HSM or signer isolation, so a full
  server compromise reaching `master.key` + `credentials.yml.enc` yields the
  oracle key, which can drain all *non-expired* funded bounties (the expiry gate
  bounds this to `[fund, expiry)` per bounty). **"Popping the website" can equal
  "popping the key" in v1.** Signer isolation is the main deferred v2 hardening;
  operate the host locked-down and keep `RAILS_MASTER_KEY` in a secret manager.

### Webhook authenticity (the untrusted-input boundary)
- `WebhooksController#github` verifies the `X-Hub-Signature-256` HMAC over the
  **raw body** with the App's `webhook_secret`, using
  `ActiveSupport::SecurityUtils.secure_compare` (timing-safe); 401 on
  missing/placeholder secret or mismatch. This is what stops a forged webhook from
  triggering a disbursement.
- `skip_forgery_protection` here is correct — server-to-server API authenticated
  by HMAC, not a browser form.
- **Idempotency:** unique `github_delivery_id` + unique `attestations.bounty_id`
  ⇒ a redelivered/duplicated webhook can't double-disburse.

### Authorization / IDOR
- `fund`/`create` scoped via `current_user_repositories.find` (only your own
  repos); `refund` via `current_user.bounties.find` (and the contract also
  enforces `msg.sender == funder`); `wallet`/dashboard/index pages scoped to
  `current_user`. Bounty `show` is intentionally public (read-only). No
  owner/admin contract functions are exposed through the web app.

### Client-trust boundary on funding
`bounties#create` writes a **`pending`** row from client-supplied values, but this
is **not authoritative**: the chain is the source of truth, and the indexer
overwrites amount/fee/expiry/funder from the on-chain `Funded` event. A forged
payload either never matches a real event (stays `pending`, cosmetic) or is
corrected by the indexer — **no money moves on client input.** The disburse
recipient is the PR author's linked wallet resolved server-side and bound into the
oracle signature; no client input selects it.

### Availability / abuse — rate limiting
**Rack::Attack** (`config/initializers/rack_attack.rb`) throttles by IP, with
counters in `Rails.cache` (solid_cache in prod, shared across Puma workers):
a 300/5min general backstop (assets + `/up` exempt), 120/min on the public
`POST /webhooks/github` flood surface (generous so GitHub delivery bursts aren't
clipped — forgeries are already rejected by HMAC), 15/min on `POST /auth/github`,
and 30/min on authenticated mutations (fund/refund/wallet) to bound row/tx spam.
Throttled requests get a `429` + `Retry-After`. Localhost is safelisted (health
checks). Covered by `test/integration/rack_attack_test.rb`. This is app-layer
hygiene, **not** volumetric DoS protection — that belongs at the edge (a CDN /
the proxy); a small VPS is still trivially floodable at the network layer.

### Other classes (checked, clean)
- **Mass assignment:** strong params (`bounty_params`, `wallet_params`).
- **SQL injection:** ActiveRecord throughout; the indexer uses raw JSON-RPC, not SQL.
- **Open redirect:** the only cross-host redirect is to
  `https://github.com/apps/{slug}/installations/new` (`allow_other_host: true`);
  `slug` is server-controlled (credentials), not user input.
- **CSRF / OAuth:** `omniauth-rails_csrf_protection` guards the OAuth request
  phase; forms carry CSRF tokens; the funding `fetch` sends `X-CSRF-Token`.
- **Sessions:** default encrypted+signed cookie store; `reset_session` on login/logout.
- **Host authorization:** dev allows tunnel hosts; production must set
  `config.hosts` to the real domain.

---

# Recommended before commissioning the paid audit / mainnet

- **Hand the contract auditor** Part 1 + Appendix A of the build plan (frozen
  EIP-712 / interface spec) + the §3.4 threat model.
- **Get the platform reviewed too** (Part 2) — not just the contract; specifically
  the key-custody/operational posture and the webhook→disburse path.
- **Signer isolation** (§7 deferral): move oracle signing behind a KMS/locked-down
  path so a web-app compromise can't exfiltrate the key — the single
  highest-leverage v2 platform hardening.
- **Keep the scanners running, not one-shot:** wire `slither`, `brakeman`,
  `bundle audit`, and `gitleaks` into CI so regressions and newly-disclosed gem
  CVEs are caught on every change; enable **Dependabot** for ongoing gem updates.
  (§7 flags supply-chain risk in the signing process.)
- **Scan the deploy image:** run **Trivy/Grype** on the Docker image at deploy
  time (OS/library CVEs the Ruby-level tools don't see).
- Optionally index the two admin-event address params (`TreasuryUpdated`,
  `OracleSignerUpdated`).
