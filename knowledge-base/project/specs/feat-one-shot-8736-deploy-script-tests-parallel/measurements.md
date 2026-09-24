# Measurements — deploy-script-tests shard restructure (Phase 0, frozen 2026-09-24)

Source: `gh api repos/jikig-ai/soleur/actions/{workflows/infra-validation.yml/runs,runs/<id>/jobs}`.
Basis run: 36037220776 (last green main-push before freeze, 2026-09-24T17:51Z).

## Per-run job wall clock (green main-push runs)

| run | job wall | step total | steps |
|---|---|---|---|
| 35951193516 | 1459 s | 1456 s | 165 |
| 35952634647 | 1462 s | 1461 s | 165 |
| 35954771278 | 1304 s | 1301 s | 165 |
| 36031820102 | 1429 s | 1425 s | 168 |
| 36037220776 | 1508 s | 1504 s | 168 |

Median ≈ 1459 s (~24.3 min). The job is a serial chain — wall clock ≈ step total.

## Step classification (run 36037220776)

- Shard pool (`run: bash apps/web-platform/infra/*.test.sh`, non-sudo): **143 steps, 1371 s**
- Fixed-job steps (sudo loopback ×3, terraform validate, fixtures-validate,
  test/infra steps, sandbox-canary, evidence/provenance/lint blocks): **20 steps, 120 s**
- Platform/setup (checkout, setup-terraform, cloud-init/nftables install,
  docker assert): 25 s named + job setup/teardown ~5 s

## Sticky-LPT partition of the shard pool (serial-per-leg bound)

| K | worst leg (suite s) | +60 s measured fixed | projected leg wall |
|---|---|---|---|
| 2 | 686 | 746 s | ~12.4 min |
| 3 | 457 | 517 s | ~8.6 min |
| **4** | **343** | **403 s** | **~6.7 min** |
| 6 | 229 | 289 s | ~4.8 min |
| 8 | 205 | 265 s | ~4.4 min |

Legs balance within ~1 s of each other under LPT — the distribution is
dominated by six heavy suites; the heaviest single suite (205 s,
`infra-config-repush-mutation.test.sh`) is the floor no K beats.

Each leg additionally runs its subset under the runner's `xargs -P` executor
(`min(nproc,6)` → 4 on a GitHub runner), so realized leg times land BELOW
these serial-per-leg projections — projections are the conservative bound.

## Per-leg fixed cost (measured, run 36037220776)

checkout 12 s · setup-terraform 1 s · install cloud-init 9 s · install
nftables 1 s · docker assert 2 s → **25 s** named setup. Adding
job-setup/teardown (~5 s) and the `if: always()` artifact uploads (~10 s),
use **~60 s/leg conservative** (plan's 90 s estimate was pessimistic; either
figure keeps K=4 under target).

Break-even vs ADR-238's objection: K=4 duplicates ~60 s of fixed work ×4 =
4 min aggregate runner time against ~18 min of wall-clock saved per run.

## K decision

**K=4.** Worst leg ~6.7 min measured-bound (7.2 min under the plan's 90 s
fixed assumption) — under the 10-min target with ~30% margin for suite
growth. K=6 saves ~1.9 min wall for +2 min aggregate fixed per run while the
org's 20-concurrent-job budget is the contested resource
(2026-09-21 ci-runner-concurrency brainstorm). Raising K later is a one-line
matrix edit + manifest regen — the absorption property.

## Fixed-job budget

120 s suite time + ~60 s own setup ≈ 3 min — under the leg budget.

## #8744 status at freeze

OPEN; defect sites verified verbatim on `origin/main`:
`git-data-ownership.test.sh:280` and `git-data-cutover-access.test.sh:1770`
both pipe `apt-get update/install` to `/dev/null` with no retry → rc=100
`FIXTURE_APT_FAILED` with no diagnostics. The 14:49–15:49Z red window +
17:05Z recovery matches the issue's transient-mirror hypothesis; root cause
unaddressed.

## Top shard-pool durations (run 36037220776)

| s | suite |
|---|---|
| 205 | infra-config-repush-mutation.test.sh |
| 197 | cloud-init-inngest-zot-pull-mutation.test.sh |
| 189 | git-data-runcmd-rehearsal.test.sh |
| 120 | run-registered-suites.test.sh |
| 93 | web-host-provisioner-parity-mutation.test.sh |
| 70 | git-data-cutover-access.test.sh |
| 58 | ci-deploy.test.sh |
| 38 | git-data-root-key.test.sh |
| 32 | cloud-init-web-zot-seed.test.sh |
| 29 | workspaces-luks-verify-workflow.test.sh |

The three docker-heavy suites the ceiling PR bounded (rehearsal 189 s,
cutover 70 s, ownership 23 s) carry the per-suite override-map entries.

## Shipped structure (verification record)

- `deploy-script-tests` → K=4 matrix (`fail-fast: false`), each leg invokes
  `run-registered-suites.sh` with `SOLEUR_INFRA_SHARD=k/4`. Per-leg
  `timeout-minutes: 15` ≈ 2.2× the measured worst leg (~6.7 min).
- `deploy-script-tests-fixed`: 3 privileged `sudo bash` loopback suites, the
  5 `test/infra` alert guards, 2 terraform validates, fixtures, sandbox-canary,
  sigpipe probe, freshness + provenance guards (provenance last, per #8052).
- `deploy-script-tests-done`: `if: always()` aggregator over both legs'
  results with the #7931 cancelled-vs-superseded discriminator;
  `notify-main-failure` now reads it (#8735).
- Seeded `apps/web-platform/infra/suite-shard-legs.tsv` (143 rows) via
  `regenerate-shard-manifest.py --group infra` from the 5-run step table:
  legs 369–370 s each, 1 s spread.
- Registration gate rewritten to the connection contract (runner step +
  shard wiring + unmasked + fail-fast + privileged-sudo + aggregator
  needs + test/infra coverage); mutation battery 17/17 green.
- Suites' self-registration assertions updated to the runner-connection
  check (apex ×2, zot-inventory, inngest-host-state, git-data-root-key,
  cutover-access, flag-precheck, infra-config-gate, handler-bootstrap,
  tunnel-origin-relative, verify-tunnel-ingress, scan-workflow).
