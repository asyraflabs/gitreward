# GitReward platform (Rails)

The web app + oracle + relayer, in one Rails 8 codebase (build plan §5). AGPL-3.0
(repo root `LICENSE`). Server-rendered Hotwire; the only browser chain code is a
single viem Stimulus island (`app/javascript/controllers/wallet_controller.js`).

## What's here

| Area | Where |
|------|-------|
| Data model (Appendix C) | `app/models/*`, `db/migrate/*` |
| GitHub OAuth login | `config/initializers/omniauth.rb`, `app/controllers/sessions_controller.rb` |
| GitHub App (install, webhooks, issues) | `app/services/github/*`, `app/controllers/webhooks_controller.rb` |
| Chain seam (eth.rb) | `app/services/chain/*` (config, client, signer, indexer) |
| Auto-disburse | `app/jobs/process_pull_request_closed_job.rb` → `app/services/disbursement/processor.rb` |
| Funding UI (viem) | `app/views/bounties/new.html.erb` + `wallet_controller.js` |
| Discovery + trust | `app/controllers/{directory,trust}_controller.rb` |

The EIP-712 signer is the repo-root `oracle/attestation.rb`, loaded via
`config/initializers/oracle_attestation.rb` so the Ruby signer and the Solidity
verifier never diverge (the Phase 1 gate).

## Setup

```bash
bundle install
bin/rails db:prepare
```

Secrets live in Rails encrypted credentials (`bin/rails credentials:edit`):

```yaml
active_record_encryption: { primary_key: …, deterministic_key: …, key_derivation_salt: … }
chain:
  oracle_key:  <hex, no 0x>   # signs attestations — the crown jewel (§7)
  relayer_key: <hex, no 0x>   # pays gas only; MUST be a different key
github:
  oauth_client_id: …          # GitHub OAuth app (login)
  oauth_client_secret: …
  app_id: …                   # GitHub App (repo access + webhooks)
  app_slug: gitreward
  webhook_secret: …
  private_key: |              # GitHub App PEM
    -----BEGIN RSA PRIVATE KEY----- …
```

Network params (non-secret) are in `config/chain.yml`, overridable by env
(`CHAIN_RPC_URL`, `USDC_ADDRESS`, `ESCROW_ADDRESS`, …). Addresses are quoted —
unquoted `0x…` is parsed by YAML as a hex integer.

## Background jobs (Solid Queue)

Development uses **Solid Queue** (DB-backed ActiveJob, no Redis), the same as
production. One-time setup creates the queue database from `db/queue_schema.rb`:

```bash
bin/rails db:prepare
```

Jobs (webhook handling → disbursement, and the recurring `IndexChainEventsJob`
that syncs Funded/Disbursed/Refunded into the DB cache) run **only while
`bin/jobs` is running** — it's a separate process from the web server. Run both:

```bash
bin/rails server -p 3000   # web: receives webhooks, enqueues jobs
bin/jobs                    # worker: processes jobs + recurring indexer (every 15s, see config/recurring.yml)
```

Both processes need the chain env (see below). The chain is the source of truth;
the DB is a rebuildable mirror (C.1). Swapping Solid Queue for Sidekiq in
production is a one-line adapter change (build plan §2).

## Local end-to-end on anvil (no testnet, no real funds)

The dev oracle key is anvil account #0, so it matches `contracts/`'s test setup.

```bash
# 1. Local chain
anvil

# 2. Deploy MockUSDC + escrow and fund one bounty (prints addresses)
cd ../contracts
forge script script/DevDeploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# 3. Run the app pointed at those addresses (web + jobs, two terminals)
cd ../platform
USDC_ADDRESS=0x… ESCROW_ADDRESS=0x… bin/rails server -p 3000
USDC_ADDRESS=0x… ESCROW_ADDRESS=0x… bin/jobs
```

## Pointing at Base Sepolia (or another network)

Set `CHAIN_NETWORK` + the network's params (keys are namespaced per network in
credentials under `chain.<network>`). A convenient pattern is a gitignored env
file sourced into both the web and jobs processes:

```bash
set -a && . ./.env.base_sepolia && set +a && bin/rails server -p 3000
set -a && . ./.env.base_sepolia && set +a && bin/jobs
```

> Indexer note: the recurring job resumes from `chain_sync_state.last_synced_block`.
> On a fresh cursor it would scan from block 0 — infeasible on a live chain — so
> production needs a configurable deploy/start block (TODO).

## Tests

```bash
bin/rails test
```

The cross-language signer invariant (`test/services/attestation_signer_test.rb`)
asserts the in-app signer reproduces the committed fixture the Solidity verifier
accepts. Full chain delegation is covered by the anvil flow above and the
contract's `EIP712RoundTrip` Foundry test.
