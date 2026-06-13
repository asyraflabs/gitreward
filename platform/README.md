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

## Local end-to-end on anvil (no testnet, no real funds)

The dev oracle key is anvil account #0, so it matches `contracts/`'s test setup.

```bash
# 1. Local chain
anvil

# 2. Deploy MockUSDC + escrow and fund one bounty (prints addresses)
cd ../contracts
forge script script/DevDeploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# 3. Run the app pointed at those addresses
cd ../platform
USDC_ADDRESS=0x… ESCROW_ADDRESS=0x… bin/dev
```

`bin/dev` runs the web server, the Tailwind watcher, and Solid Queue (which runs
the recurring `IndexChainEventsJob` that syncs Funded/Disbursed/Refunded into the
DB cache). The chain is the source of truth; the DB is a rebuildable mirror (C.1).

> Jobs use plain ActiveJob on Solid Queue (Rails 8 default, no Redis). Swapping to
> Sidekiq in production is a one-line adapter change (build plan §2).

## Tests

```bash
bin/rails test
```

The cross-language signer invariant (`test/services/attestation_signer_test.rb`)
asserts the in-app signer reproduces the committed fixture the Solidity verifier
accepts. Full chain delegation is covered by the anvil flow above and the
contract's `EIP712RoundTrip` Foundry test.
