# Merge-correctness & recipient resolution (Phase 1 exit criterion)

Concrete webhook-handling pseudocode for the oracle, implementing the frozen
spec: merge-correctness rule (A.1 #3) and recipient resolution (A.1 #4). This is
the precise definition of "what counts as merged into the correct branch" that
the build plan (§3.4) requires before writing the listener.

This document is the contract the Phase 3 Rails oracle implements. The chain
already enforces the money rules; this defines when the oracle is willing to
**sign**.

---

## Definitions

- **Bountied issue**: a GitHub issue with an on-chain bounty whose mirrored
  status is `Funded`.
- **Closing linkage**: a PR is linked to an issue via a GitHub closing keyword
  (`closes`/`fixes`/`resolves #N`, etc.) such that merging the PR auto-closes
  the issue. We read this from the PR's `closingIssuesReferences` (GraphQL), not
  by regex on the body — GitHub itself resolves the linkage.
- **Target branch**: the branch chosen by the maintainer at fund time and stored
  on the bounty (`bounties.target_branch`). Default: the repo default branch.
- **Payee unit**: the GitHub PR **author** (co-authors out of scope for v1).

---

## A.1 #3 — Merge-correctness rule

A merge authorizes disbursement **iff ALL of the following hold**:

1. The webhook is `pull_request.closed` **and** `payload.pull_request.merged == true`.
   (A `closed` with `merged == false` is an abandoned PR — never pays.)
2. The PR's base branch equals the bounty's `target_branch`
   (`payload.pull_request.base.ref == bounty.target_branch`).
3. The PR closes the bountied issue via closing linkage (the issue id appears in
   the PR's `closingIssuesReferences`).

This covers all three GitHub merge methods (merge commit, squash, rebase)
uniformly, because we trust `merged == true` + the closing linkage rather than
inspecting commit topology. **Post-merge reverts are out of scope for v1.**

---

## A.1 #4 — Recipient resolution

- **PR opened** → informational nudge only (never authorizes anything).
- **Merge time** → authoritative live lookup of the author's active wallet.
  - Linked → sign `Disbursement{bountyId, recipient}` and submit `disburse`.
  - Not linked → **do nothing**. The bounty stays `Funded` and rides to expiry,
    where the maintainer refunds. The contract has no "merged-but-unpaid" state.

---

## Webhook: `pull_request.opened` (and `reopened`, `edited` re-link)

```
on pull_request.opened(payload):
    delivery_id = header["X-GitHub-Delivery"]
    if already_processed(delivery_id): return 200          # idempotency

    installation = lookup_installation(payload.installation.id)
    if installation is None or installation.suspended: return 200

    # Which bountied issues would this PR close, per GitHub's own linkage?
    closing_issues = graphql_closing_issue_refs(payload.pull_request.node_id)
    bounty = first_funded_bounty_for(installation, payload.repository, closing_issues)

    record_pr_event(bounty, payload, action="opened", delivery_id)

    if bounty is None:
        # PR doesn't reference any funded bounty. If it references a bountied
        # issue WITHOUT a closing keyword, nudge to add `closes #N`.
        if references_bountied_issue_without_closing_link(payload):
            comment(payload.pull_request, NUDGE_ADD_CLOSING_LINK)
        return 200

    author_id = payload.pull_request.user.id
    if has_active_wallet(author_id):
        comment(payload.pull_request, "✅ Bounty of {amt} USDC disburses to your "
                "linked wallet automatically if this PR is merged into "
                "`{bounty.target_branch}`.")
    else:
        comment(payload.pull_request, "⚠️ Link a wallet before this is merged or "
                "the {amt} USDC bounty refunds to the maintainer at expiry. "
                "(Also ensure the PR says `closes #{issue}`.)")
    return 200
```

The opened-comment is **informational only** — it reflects wallet status *now*,
but the authoritative check is re-run at merge.

---

## Webhook: `pull_request.closed`

```
on pull_request.closed(payload):
    delivery_id = header["X-GitHub-Delivery"]
    if already_processed(delivery_id): return 200          # redelivery-safe

    if not payload.pull_request.merged:
        record_pr_event(action="closed_unmerged", delivery_id, processed=now)
        return 200                                          # abandoned, never pays

    # Enqueue — NEVER do chain work in the webhook request (build plan §2).
    enqueue(DisburseJob, payload_subset, delivery_id)
    return 200
```

### `DisburseJob` (Sidekiq) — confirm → sign → submit

```
def DisburseJob(payload, delivery_id):
    with idempotency_lock(delivery_id):                     # at-most-once effect
        installation = lookup_installation(payload.installation.id)
        if installation is None or installation.suspended: return

        closing_issues = graphql_closing_issue_refs(payload.pull_request.node_id)
        bounty = first_funded_bounty_for(installation, payload.repository, closing_issues)

        record_pr_event(bounty, payload, action="closed_merged", delivery_id)

        # --- Merge-correctness (A.1 #3) ---
        if bounty is None:                       return       # no funded bounty closed
        if bounty.status != Funded:              return       # already disbursed/refunded
        if payload.pull_request.base.ref != bounty.target_branch: return  # wrong branch

        # --- Recipient resolution (A.1 #4), authoritative live lookup ---
        wallet = active_wallet_for(payload.pull_request.user.id)
        if wallet is None:
            comment(issue, "Merged, but the author has no linked wallet. The "
                           "bounty will refund to the maintainer after expiry.")
            return                                            # bounty rides to expiry

        # --- Idempotent attestation (DB: unique on bounty_id) ---
        if Attestation.exists(bounty_id): return              # never sign twice

        signature = oracle.sign_disbursement(bounty.chain_bounty_id, wallet.address)
        attestation = Attestation.create(
            bounty, recipient=wallet.address, pr_ref=pr_ref(payload),
            pr_author_github_id=payload.pull_request.user.id,
            signature=signature, signed_at=now)

        tx = relayer.submit_disburse(bounty.chain_bounty_id, wallet.address, signature)
        attestation.update(submitted_tx_hash=tx.hash)

        # Status flips to `disbursed` when the indexer sees the Disbursed event
        # (chain is source of truth, C.1). Update the issue comment to "paid"
        # on confirmation.
```

---

## Edge cases & how this rule handles them (build plan §3.4)

| Case | Handling |
|---|---|
| Squash / rebase / merge-commit | All accepted: we trust `merged == true` + closing linkage, not commit topology. |
| Merged into wrong branch | Rejected by check (2): `base.ref != target_branch`. Bounty rides to expiry. |
| PR closed without merge | `merged == false` → never pays. |
| Author has no wallet at merge | Oracle does nothing; bounty refunds at expiry. No on-chain "unpaid" state. |
| Webhook redelivery | `github_delivery_id` unique + `idempotency_lock` + `Attestation` unique on `bounty_id` → at-most-once disbursement. |
| Two PRs close the same issue | First merged PR satisfying the rule disburses; the bounty flips to `Disbursed`, so later merges find `status != Funded` and no-op. |
| Force-push / post-merge revert | Out of scope for v1 (A.1 #3). Disbursement is irreversible on-chain. |
| Wallet changed between open and merge | Merge-time lookup wins (the opened comment was informational). |
```
