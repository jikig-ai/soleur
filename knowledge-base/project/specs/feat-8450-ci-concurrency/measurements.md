# Measurements — CI concurrency ceiling (#8450)

Canonical before/after record. The PR body links here; do not duplicate numbers
in the body.

## Timestamp-semantics pin (precondition for the probe)

Measured 2026-09-21 against live API data; this falsifies the plan's original
run-level metric and the reviewers' job-level conflation concern alike:

- `run_started_at == created_at` on every one of 30 recent runs sampled —
  run-level `created_at → run_started_at` measures registration only and is
  **vacuous** as a queue-wait metric. Do not use it.
- `job.created_at` is stamped when the job becomes runnable — for a
  `needs:`-gated job it equals the upstream job's `completed_at`
  (`deploy.created_at == migrate.completed_at` on run 35555748979). Therefore
  `job.started_at − job.created_at` is **pure runner-acquisition wait**; no
  upstream-compute conflation.
- While a job is `status=queued`, the API pre-populates `started_at` equal to
  `created_at` — the field is only meaningful on completed/in_progress jobs.
  Sample finished jobs only.

**Probe metric (corrected):** per-job `started_at − created_at` on the
deploy-arm jobs (`migrate`, `deploy`) of `web-platform-release.yml` runs
filtered `--event workflow_run` (excludes the push-arm release-only runs).

## Baseline (pre-change, 2026-09-21)

### Queued snapshot ~08:32 UTC

`gh api repos/jikig-ai/soleur/actions/runs?status=queued&per_page=100`:
~30+ runs queued, oldest created 08:01 UTC (~30 min at sample). Single PR heads
dispatch ~18 runs each (PRs #8453/#8454/#8474 batches visible).

### Saturated-window queue waits (job `started_at − created_at`)

CI run 35570460536 (created 06:54, succeeded 08:26):

| job | queued wait |
|---|---|
| detect-changes | 45.7 min |
| test (required aggregator) | 25.0 min |
| critical-css-gate | 26.4 min |

### Deploy-arm (`web-platform-release.yml`, `--event workflow_run`)

8 recent successful runs — job-level queue waits for `migrate`/`deploy`/
`live-verify` were 0–4 s except one `migrate` at 49 s. The deploy arm registers
and runs in quiet windows today; the tail lands on the *critical path to merge*
(CI jobs above), and on deploy arms dispatched during saturated windows
(the 30–75 min issue-reported baseline).

## Anchor audit (C.3) — safe-set ∩ app-affecting-set = ∅

The e2e allowlist is `knowledge-base/**` + root-level `*.md`. Audited
2026-09-21 against the e2e suite's actual inputs (`npx playwright test` in
`apps/web-platform`, `testDir: ./e2e`, mock-Supabase + Next.js server on
ports 3099/3100):

- `knowledge-base/**`: **no coupling.** Only e2e reference is
  `nav-states-shell.e2e.ts`'s *synthetic* fixture — a mocked directory node
  literally named `knowledge-base`, not a filesystem read. No `fs` read of the
  real tree anywhere in `e2e/` (only `global-setup.ts` writing its own
  storage-state JSON). The Next.js app does not serve kb content.
- Root `*.md` (`AGENTS.md`, `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `cla-smoke-test.md`, `feature-request-*.md`):
  **no coupling.** Agent-instruction and repo-docs files; nothing in the
  app build (`next build` inputs: `apps/web-platform/**`, `package*.json`,
  `bunfig.toml`, `tsconfig*`, `next.config*`) or the playwright suite reads
  them. CI lint gates (`markdown-lint`, `adr-ordinals`) DO read them — those
  jobs are ungated and unaffected.
- Explicitly NOT allowlisted and recorded: `docs/**` (only `docs/legal/**`,
  app-coupled via pinned SHA-256s in `legal-doc-shas.ts`), `apps/**`,
  `supabase`-adjacent SQL under `apps/web-platform/infra/**`, `infra/**`,
  `scripts/**`, `plugins/**`, `.github/**`, `.claude*/**`, `docs/`,
  `eleventy.config.js`, `package*.json`, `bunfig.toml`, `test/`, `tests/`,
  `spike/`, `todos/`, `bin/`, `LICENSES/` — every one of these runs e2e.
- Accepted residual gap: a future PR could add a NEW root-level `*.md` file
  that the app starts reading (e.g. a build-time embed). Mitigation: the
  allowlist is name-based, not content-based — Guard 1's anchor assertion
  plus this recorded enumeration are the contract; any such coupling would
  require also teaching e2e to consume the file, a change that itself
  touches `apps/**` and therefore runs e2e on its own diff.

## Probe verdict correction (D.1, measured against the sweeper's contract)

The plan pinned `SKIP-DECLARED → exit 0` for a non-`team` `plan.name`.
`scripts/sweep-followthroughs.sh` maps exit 0 to PASS + **auto-close** of the
tracked issue — so a premature-directive or silent-upgrade-failure path would
have closed #8450 without a single measurement. The probe prints
`SKIP-DECLARED` but exits **2** (sweeper verdict "NOT YET": comment, leave
open, retry next sweep). Exit 2 also covers the unarmed-clock and
insufficient-runs (<5 in-window) verdicts. Guard 2
(`actions-queue-tail-8450.test.sh`, 8 rows) pins the corrected polarity.

## Post-upgrade (pending)

`UPGRADE_NOT_BEFORE`: **TBD** — set to the `gh api orgs/jikig-ai --jq
.plan.name` == `team` verification timestamp (operator-upgrade-steps.md Step 2).

Soak probe: `scripts/followthroughs/actions-queue-tail-8450.sh` — pass =
≥5 deploy-arm runs postdating `UPGRADE_NOT_BEFORE` with p95 queue wait < 15 min.
