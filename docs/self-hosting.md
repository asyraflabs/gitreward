# Deploy your own GitReward instance

GitReward is open-core: the escrow contracts are MIT and the platform is AGPL-3.0
(see [`LICENSING.md`](../LICENSING.md)). You can run the whole thing yourself —
for your own org, fee-free, with your own oracle and treasury. This guide walks
the full deploy.

## What self-hosting means (read this first)

- **You become your own oracle.** The platform signs the EIP-712 attestation that
  authorizes each payout. When you self-host, *you* hold that signing key — so
  you must trust yourself and secure that key. (Contributors who'd rather trust a
  neutral third party may prefer the hosted service; that's a real feature, not a
  knock on self-hosting.)
- **You set the fee.** Deploy with `feeRate = 0` (or call `setFeeRate(0)`) and the
  protocol takes nothing; you point the treasury at your own address.
- **v1 security posture.** There is **no** KMS/HSM, key rotation use, emergency pause, 
  disbursement delay, or multisig owner. A leaked oracle key can disburse every active 
  funded bounty to an attacker. For a single-org deployment you control, this is usually 
  acceptable — but **treat the oracle key as you would a hot wallet that can move all 
  escrowed funds.** Don't put more in escrow than you're comfortable exposing to that key.

## Prerequisites

- [Foundry](https://book.getfoundry.sh) (`forge`, `cast`) for deploying the contract.
- Ruby 3.3+, the platform's bundle (`cd platform && bundle install`).
- A Base RPC endpoint (e.g. `https://mainnet.base.org` / `https://sepolia.base.org`,
  or your own node / Alchemy / Infura URL).
- A deployer wallet with a little ETH on your target chain (deploy costs ~0.00001
  ETH on Base; mainnet a bit more).
- The **USDC address** for your chain (Base Sepolia: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`;
  Base mainnet: verify the current native-USDC address from Circle — **not** bridged USDbC).

## 1. Generate your keys

You need two **distinct** keys (never the same one):

- **Oracle signing key** — authorizes payouts (the crown jewel). Holds no funds.
- **Relayer key** — submits the disburse transaction and pays its gas. A leak of
  this key loses only gas, not funds (the contract trusts the *signature*, not the
  sender).

```bash
cd platform
bin/rails runner 'require "eth"; o=Eth::Key.new; r=Eth::Key.new;
  puts "ORACLE  pk=#{o.private_hex} addr=#{o.address}";
  puts "RELAYER pk=#{r.private_hex} addr=#{r.address}"'
```

Fund the **relayer address** with ETH on your chain. The oracle address needs no
funds — it only signs.

## 2. Deploy the escrow

From `contracts/`, set the deploy parameters and run the script. Use the relayer
key (or any funded key) as the deployer; set `FEE_BPS=0` to run fee-free.

```bash
cd contracts
export USDC_ADDRESS=0x036CbD...        # USDC on your chain
export TREASURY=0xYourTreasury         # who receives fees (irrelevant if FEE_BPS=0)
export ORACLE_SIGNER=0xYourOracleAddr  # the oracle address from step 1
export OWNER=0xYourAdminEOA            # admin (setFeeRate/setTreasury/setOracleKey)
export FEE_BPS=0                       # 0% for self-hosters; max enforced on-chain is 10%

forge script script/Deploy.s.sol \
  --rpc-url "$YOUR_RPC" --private-key "$DEPLOYER_PK" --broadcast --verify
```

Note the **deployed escrow address** and the **deploy block number** (from the
broadcast output / `broadcast/Deploy.s.sol/<chainId>/run-latest.json`). You'll
need both.

## 3. Register your own GitHub App

Create a GitHub App at `https://github.com/settings/apps/new`:

- **Callback URL:** `https://yourhost/auth/github/callback`
- **Setup URL:** `https://yourhost/install/callback` (✅ Redirect on update)
- **Webhook URL:** `https://yourhost/webhooks/github`, **Active**, with a strong
  **secret** (generate one: `ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'`)
- **Repository permissions:** Issues = Read & write; Pull requests = Read-only;
  Metadata = Read-only.
- **Account permissions:** Email addresses = Read-only (optional).
- **Subscribe to events:** Pull request.

Then collect: **App ID**, **Client ID**, a generated **Client secret**, a
generated **private key (.pem)**, and the **slug** (from the App's public URL).

## 4. Configure the platform

### Secrets → encrypted credentials

```bash
cd platform
bin/rails db:encryption:init    # if not already set; add the 3 keys to credentials
EDITOR="your-editor --wait" bin/rails credentials:edit
```

Add (keys are namespaced per network so you can run anvil/testnet/mainnet side by
side):

```yaml
active_record_encryption:
  primary_key: …
  deterministic_key: …
  key_derivation_salt: …

chain:
  base_mainnet:                       # or base_sepolia, etc. — match CHAIN_NETWORK
    oracle_key:  "<oracle private hex, no 0x>"
    relayer_key: "<relayer private hex, no 0x>"

github:
  oauth_client_id: "<Client ID>"
  oauth_client_secret: "<Client secret>"
  app_id: <App ID>
  app_slug: "<your-app-slug>"
  webhook_secret: "<webhook secret>"
  private_key: |
    -----BEGIN RSA PRIVATE KEY-----
    …your App .pem…
    -----END RSA PRIVATE KEY-----
```

### Non-secret network params → env

The platform reads `config/chain.yml`, which is env-overridable. Set these for
your host (the included `.env.<network>` pattern works well — keep it out of git):

```bash
CHAIN_NETWORK=base_mainnet            # the credentials key above must match
CHAIN_ID=8453                         # 8453 mainnet, 84532 sepolia
CHAIN_RPC_URL=<your server RPC>       # may be authenticated/private
PUBLIC_RPC_URL=https://mainnet.base.org   # browser-safe RPC for wallet network-add
USDC_ADDRESS=0x...                    # USDC on your chain
ESCROW_ADDRESS=0x...                  # from step 2
USDC_PERMIT_VERSION=2                 # Circle USDC permit domain version
CHAIN_LABEL="Base"
CHAIN_CONFIRMATIONS=2
CHAIN_START_BLOCK=<deploy block>      # so the indexer doesn't scan from genesis
EXPLORER_URL=https://basescan.org     # for the "verify on-chain" links
```

**`CHAIN_START_BLOCK` matters on a live chain** — set it to the escrow's deploy
block, or a fresh indexer cursor scans from block 0 (millions of blocks). Get the
deploy block from the broadcast file Foundry wrote in step 2 — run this from
`contracts/`, replacing `<chainId>` with `8453` (mainnet) or `84532` (sepolia):

```bash
cast receipt \
  "$(jq -r '.transactions[0].hash' broadcast/Deploy.s.sol/<chainId>/run-latest.json)" \
  blockNumber --rpc-url "$YOUR_RPC"
```

(Or open the escrow contract on the block explorer — its "Contract Creation"
transaction shows the block.)

## 5. Run locally to verify (optional but recommended)

Before deploying, sanity-check the whole config against your chain:

```bash
cd platform
bin/rails db:prepare        # app DB + Solid Queue tables (one time)
# two processes, both carrying the env from step 4:
bin/dev                     # web: OAuth, funding UI, webhooks
bin/jobs                    # worker: disbursement + the recurring indexer
```

The indexer (recurring) syncs `Funded`/`Disbursed`/`Refunded` events into the DB;
the chain is the source of truth and the DB is a rebuildable mirror. In production
you don't run `bin/jobs` separately — see below.

## 6. Deploy the backend to production

The platform is a standard Rails 8 app and ships with **Kamal** (`config/deploy.yml`,
`Dockerfile`, `.kamal/secrets`) — Docker on a server you control. A PaaS
(Render, Fly.io, Heroku) works too; the same env/secret/process notes apply.

**The one thing to understand:** in production the Solid Queue worker runs *inside*
Puma (`SOLID_QUEUE_IN_PUMA: true`, already set in `deploy.yml`), so a **single
container runs both the web server and the jobs** (disbursement + the recurring
indexer). You do **not** run `bin/jobs` separately unless you scale to a dedicated
job machine.

### Kamal path

1. **Provision a server** with Docker and SSH access, and a container registry
   (Docker Hub, GHCR, etc.).
2. **Edit `config/deploy.yml`:** set `service`/`image` to your name, `servers.web`
   to your server's IP/host, `registry` to your registry + username, and `proxy.host`
   to your domain (Kamal's proxy gets you automatic Let's Encrypt TLS).
3. **Secrets — `RAILS_MASTER_KEY` is the critical one.** It decrypts
   `credentials.yml.enc`, which holds your oracle key, relayer key, and GitHub App
   creds. Put it in `.kamal/secrets` (sourced from your env/secret manager, never
   committed). This is the single secret that unlocks everything.
4. **Non-secret chain env → `deploy.yml` `env.clear`:** add `CHAIN_NETWORK`,
   `CHAIN_ID`, `CHAIN_RPC_URL`, `PUBLIC_RPC_URL`, `USDC_ADDRESS`, `ESCROW_ADDRESS`,
   `USDC_PERMIT_VERSION`, `CHAIN_LABEL`, `CHAIN_CONFIRMATIONS`, `CHAIN_START_BLOCK`,
   `EXPLORER_URL` (the values from step 4). The keys themselves stay in credentials.
5. **Database.** Defaults to SQLite on the **persistent volume** already declared in
   `deploy.yml` (`volumes:`) — point it at a mounted, backed-up path. SQLite is fine
   for a single server (primary + queue + cache + cable DBs all live on the volume).
   For multiple web servers, switch to Postgres and split the job role onto its own
   machine instead of `SOLID_QUEUE_IN_PUMA`.
6. **Deploy:** `kamal setup` (first time), then `kamal deploy` for updates. Run the
   one-time DB setup against the release: `kamal app exec 'bin/rails db:prepare'`
   (creates + loads the app, queue, cache, and cable schemas).

### After deploy

- Point your **GitHub App's** Callback / Setup / Webhook URLs at your domain
  (`https://yourhost/auth/github/callback`, `/install/callback`, `/webhooks/github`).
- If you restrict hosts (`config.hosts`) in `production.rb`, add your domain;
  by default Rails doesn't block hosts in production.
- Install your GitHub App on the repos you want to bounty, and do a smoke test:
  fund a small bounty, open + merge a closing PR, confirm the payout.

## Operating notes

- **Protect the oracle key.** It can move all escrowed funds if leaked. Keep it
  only in encrypted credentials (never a plaintext env var, never committed). The
  contract has a `setOracleKey` rotation hook (owner-gated) if you ever need to
  rotate.
- **Keep the relayer funded** with ETH so disbursements can be submitted.
- **AGPL obligation:** if you run a *modified* version of the platform as a network
  service, AGPL-3.0 requires you to offer your users the modified source. The MIT
  contracts have no such requirement.
