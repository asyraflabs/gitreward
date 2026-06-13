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
| 1 | Protocol design (frozen spec — Appendix A) | ✅ Frozen |
| 2 | Smart contract + tests on Base Sepolia | 🚧 In progress |
| 3 | Rails platform (web + oracle + relayer) | ✅ Built; validated end-to-end on local anvil |
| 4 | Audit / testnet beta / mainnet | ⬜ Not started |

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
