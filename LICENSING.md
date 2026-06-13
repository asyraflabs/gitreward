# Licensing

GitReward is **open-core** with per-directory licensing. This follows the
Grafana model: a copyleft license on the hosted platform protects against a
commercial fork-and-host, while a permissive license on the contracts lets
anyone deploy, audit, and build on the trust anchor freely.

| Path         | License            | Why                                                        |
|--------------|--------------------|------------------------------------------------------------|
| `/` (root)   | **AGPL-3.0**       | The Rails platform (web + oracle + relayer). AGPL keeps OSI "open source" status while requiring anyone who runs a modified hosted copy to publish their changes. |
| `/contracts` | **MIT**            | The escrow contract is the trust anchor. It must be maximally inspectable, forkable, and self-hostable — permissive licensing serves that. |

The full texts are in [`/LICENSE`](./LICENSE) (AGPL-3.0) and
[`/contracts/LICENSE`](./contracts/LICENSE) (MIT).

## Why not SSPL / BSL?

SSPL and the Business Source License would forfeit the OSI "open source" label
and risk backlash from the open-source community — who are precisely our users.
AGPL keeps the label, protects the hosted business, and is well understood.

## Self-hosting

The contracts are MIT, so you may deploy your own GitRewardEscrow. Self-hosters
set their own `treasury` and `oracle` addresses and call `setFeeRate(0)` to run
fee-free. See the deploy guide (forthcoming) for the full instance setup.

A self-hoster is their own oracle — and thus must trust themselves. The neutral
hosted oracle is a feature contributors may prefer.

## Contributing

A CLA is required before the first external contribution is merged, so the
hosted version can be dual-licensed if needed. See `CONTRIBUTING.md`
(forthcoming).
