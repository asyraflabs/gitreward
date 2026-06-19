<div align="center">

<img src="platform/public/icon.png" alt="GitReward" width="76" />

# GitReward

**Bounties for GitHub issues that pay themselves.**

Fund an issue in USDC. When the PR merges, the contributor gets paid
automatically — no claim, no invoice, no middleman.

![platform: AGPL-3.0](https://img.shields.io/badge/platform-AGPL--3.0-2563eb)
![contracts: MIT](https://img.shields.io/badge/contracts-MIT-16a34a)
![built on Base](https://img.shields.io/badge/built%20on-Base-0052FF)
![Solidity 0.8.28](https://img.shields.io/badge/Solidity-0.8.28-363636)
![Rails 8](https://img.shields.io/badge/Rails-8-CC0000)

</div>

---

GitReward is a **non-custodial bounty escrow** for GitHub issues. Maintainers fund
their own issues with USDC on [Base](https://base.org); when a merged pull request
closes a funded issue, the bounty is disbursed automatically to the contributor's
pre-linked wallet, minus a small protocol fee. Unmatched bounties refund
permissionlessly to the funder after expiry.

The money lives in an open-source escrow contract — not in anyone's bank account.

## How it works

1. **Post a bounty.** Pick one of your open issues and fund it with USDC. The funds
   lock in the escrow contract on Base; you only pay gas.
2. **Solve & merge.** A contributor opens a PR that closes the issue. Merging it
   into your target branch *is* the authorization — nothing else to click.
3. **Get paid.** The bounty disburses automatically to the contributor's linked
   wallet, minus the fee. Unmatched bounties refund to the funder after expiry.

## Trust & custody

GitReward is **non-custodial with one neutral oracle** — an honest, smaller claim
than "trustless," and the one we actually stand behind:

- **Funds sit in an open-source contract on Base**, not with us. We can't spend
  them and we can't block a refund.
- **The only power the platform holds** is signing an EIP-712 attestation that says
  "pay this contributor for this bounty" when a PR is merged. The contract verifies
  the *signature*, not the sender — so a leaked relayer key cannot redirect funds,
  and the oracle can only pay the address the contributor themselves linked.
- **The refund path is permissionless.** Every unmatched bounty is refundable by
  its funder after expiry, with no fee and nothing for us to approve — so no one can
  strand your money, even if the platform disappears.
- **The fee is enforced on-chain** and hard-capped at 10% in the contract; the owner
  cannot exceed it. Self-hosters set it to zero.

See [`docs/contract-spec.md`](docs/contract-spec.md) for the exact escrow interface
and EIP-712 definition, and [`AUDIT.md`](AUDIT.md) for the security posture.

## Repository layout

| Path | What | License |
|------|------|---------|
| [`contracts/`](contracts) | Solidity escrow (Foundry) — the trust anchor | MIT |
| [`platform/`](platform) | Rails platform: web + oracle + relayer | AGPL-3.0 |
| [`oracle/`](oracle) | Canonical EIP-712 signer, shared by app + contract tests | AGPL-3.0 |
| [`docs/`](docs) | Contract spec, merge-correctness rule, self-hosting guide | — |
| [`AUDIT.md`](AUDIT.md) | Security review — contract **and** platform | — |

GitReward is **open-core**: the contracts are MIT so anyone can verify and reuse
the trust anchor; the platform is AGPL-3.0. See [`LICENSING.md`](LICENSING.md) for
the full split.

## Quick start — contracts

```bash
cd contracts
forge build
forge test
```

The escrow holds USDC and moves it exactly two ways: **refund** to the funder
(permissionless, after expiry) or **disburse** against a validly-signed EIP-712
attestation from the oracle key. See [`contracts/README.md`](contracts/README.md).

## Quick start — platform

```bash
cd platform
bin/rails db:prepare      # one-time: app DB + Solid Queue tables
bin/rails server          # web: receives webhooks, enqueues jobs
bin/jobs                  # worker: disbursement + recurring chain indexer
```

Defaults to a local Anvil node; point it at a real network with `CHAIN_NETWORK` +
env. See [`platform/README.md`](platform/README.md) for the full local/testnet
runbook, and [`docs/self-hosting.md`](docs/self-hosting.md) to deploy your own
fee-free instance.

## Security

GitReward handles money, so its security posture is documented openly in
[`AUDIT.md`](AUDIT.md) — including the trust model and the static-analysis
results. If you find a vulnerability, please report it privately rather than 
opening a public issue.

## Contributing

Contributions are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). Because
GitReward is dual-licensed, all contributors sign a lightweight
[Contributor License Agreement](CLA.md) (handled automatically on your first PR).

## License

Open-core: **contracts MIT, platform AGPL-3.0.** See [`LICENSE`](LICENSE),
[`contracts/LICENSE`](contracts/LICENSE), and [`LICENSING.md`](LICENSING.md).
