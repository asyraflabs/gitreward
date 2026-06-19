# Contributing to GitReward

Thanks for your interest in contributing! This doc covers the essentials.

## Contributor License Agreement (required)

Before your first contribution can be merged, you must agree to the
[Contributor License Agreement](./CLA.md). This keeps the licensing clean and
preserves the open-core model (see [`LICENSING.md`](./LICENSING.md)). You keep
ownership of your work — the CLA only grants the project the licenses it needs.

**Signing is one comment, not paperwork.** On your first pull request, an
automated CLA check posts instructions; reply with the requested phrase and
you're done — your agreement is recorded against your GitHub identity for all
future PRs.

### Wiring the CLA check (maintainer setup — one time)

The repo uses a CLA bot to gate PRs. Two common options:

- **Hosted:** [cla-assistant.io](https://cla-assistant.io) — sign in with GitHub,
  point it at this repo and at [`CLA.md`](./CLA.md). Zero infra.
- **Self-contained GitHub Action:** `contributor-assistant/github-action`, which
  stores signatures as a JSON file in a branch of this repo. Add a workflow like:

  ```yaml
  # .github/workflows/cla.yml
  name: CLA
  on:
    issue_comment: { types: [created] }
    pull_request_target: { types: [opened, synchronize] }
  jobs:
    cla:
      runs-on: ubuntu-latest
      steps:
        - uses: contributor-assistant/github-action@v2
          env:
            GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
            PERSONAL_ACCESS_TOKEN: ${{ secrets.CLA_SIGNATURES_TOKEN }} # repo-scoped PAT to write signatures
          with:
            path-to-document: 'https://github.com/<org>/<repo>/blob/main/CLA.md'
            path-to-signatures: 'signatures/cla.json'
            branch: 'cla-signatures'
            allowlist: 'dependabot[bot]'
  ```

  > Not committed as a live workflow yet — it needs the `CLA_SIGNATURES_TOKEN`
  > secret, and a required-but-misconfigured check would block every PR. Add the
  > secret first, then drop this in.

## Development setup

- **Contracts** (`contracts/`, Solidity + Foundry): see
  [`contracts/README.md`](./contracts/README.md). `forge build && forge test`.
- **Platform** (`platform/`, Rails): see [`platform/README.md`](./platform/README.md).
  `bin/rails db:prepare`, then `bin/rails server` + `bin/jobs`. Defaults to a
  local anvil chain.

## Before you open a PR

- **Tests pass.** `forge test` for contract changes; `bin/rails test` for platform
  changes. Add tests for new behavior.
- **Match the surrounding style.** No new dependencies without discussion.
- **Don't touch the frozen spec.** [`docs/contract-spec.md`](docs/contract-spec.md)
  is the load-bearing EIP-712 / contract-interface contract. Changes there ripple
  across Solidity and Ruby simultaneously — raise an issue first.
- **Keep the trust pitch intact.** The contract must never custody or misdirect
  principal; never describe the system as "trustless."

## Licensing of contributions

By contributing you agree your work is licensed under the license of the
directory it lives in:

- `contracts/` → **MIT**
- everything else (the platform) → **AGPL-3.0**

and, per the CLA, that the project may also offer it under separate commercial
terms for the hosted version.
