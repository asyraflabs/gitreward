# GitReward

Non-custodial bounty escrow for GitHub issues. Repo maintainers fund their own
issues with USDC on Base; when a PR is merged, the platform (acting as oracle +
relayer) automatically disburses the bounty to the contributor's pre-linked
wallet, minus a small protocol fee. Unmatched bounties refund permissionlessly
on a timer.

**Honest trust model:** non-custodial, one neutral oracle, you only pay gas to
fund. Not "trustless."

## Repository layout

| Path                       | What                                              | License   |
|----------------------------|---------------------------------------------------|-----------|
| [`contracts/`](./contracts)| Solidity escrow (Foundry). The trust anchor.      | MIT       |
| [`platform/`](./platform)  | Rails platform: web + oracle + relayer.           | AGPL-3.0  |
| [`oracle/`](./oracle)      | Canonical EIP-712 signer, shared by app + contract test. | AGPL-3.0 |
| [`docs/`](./docs)          | Merge-correctness webhook spec.                   | —         |
| [`gitreward-build-plan.md`](./gitreward-build-plan.md) | Full build plan. **Appendix A is the frozen spec.** | — |

See [`LICENSING.md`](./LICENSING.md) for the open-core split.

## Status

| Phase | What | State |
|-------|------|-------|
| 1 | Protocol design (frozen spec — Appendix A) | ✅ Frozen; cross-language EIP-712 gate proven |
| 2 | Smart contract + tests | ✅ Built (37 tests: unit/fuzz/adversarial); deployed & exercised on Base Sepolia |
| 3 | Rails platform (web + oracle + relayer) | ✅ Full flow validated end-to-end on Base Sepolia (real testnet USDC) |
| 5 | Open-source & business setup | 🟡 Licensing, CLA, CONTRIBUTING, self-hoster guide done; CLA bot + positioning copy pending |
| 7 | Key management (§7) | 🟡 v1 baseline (keys in encrypted credentials, oracle/relayer split); hardening deferred to v2 (Appendix B.3) |
| 4 | Hardening: audit · testnet beta · mainnet | ⬜ Not started (gates mainnet) |

> Note: the Base Sepolia run was a **solo self-test** (functionality), not the
> Phase 4 **testnet beta** with the waitlist (demand). Per Appendix B.4, that work
> de-risks functionality, not key-theft exposure.

## Contracts — quick start

```bash
cd contracts
forge build
forge test
```

The escrow holds USDC and moves it exactly two ways: **refund** to the funder
(permissionless, after expiry) or **disburse** per a validly-signed EIP-712
attestation from the oracle key. The contract trusts the *signature*, not the
sender — a leaked relayer key cannot redirect funds.

See [`contracts/README.md`](./contracts/README.md) for the contract interface
and the EIP-712 attestation definition.

## Platform — quick start

```bash
cd platform
bin/rails db:prepare      # one-time: app DB + Solid Queue tables
bin/rails server          # web (receives webhooks, enqueues jobs)
bin/jobs                  # worker: disbursement + recurring indexer (separate process)
```

Defaults to local anvil; point at a real network with `CHAIN_NETWORK` + env (see
[`platform/README.md`](./platform/README.md) for the full local/testnet runbook).
