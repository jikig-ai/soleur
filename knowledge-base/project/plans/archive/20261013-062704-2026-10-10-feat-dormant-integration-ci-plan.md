---
title: "feat: Wire dormant env-gated integration suites into scheduled CI (#9855 PR 2)"
type: feat
date: 2026-10-10
slug: feat-dormant-integration-ci
branch: feat-one-shot-9855-dormant-integration-ci
issue: 9855
closes: 9855
lane: cross-domain
brand_survival_threshold: none
---

# feat: Wire dormant env-gated integration suites into scheduled CI (#9855 PR 2)

## Overview

Issue #9855's second work item: seven opt-in environment gates guard twelve vitest
integration files, and no value under `.github/` or `scripts/` ever sets them, so
every suite they gate skips on every run while reporting green. This plan adds a
scheduled workflow that sets the gates inside the existing dev-Supabase CI
substrate (Doppler `dev_scheduled` config, `dev-suite-mutex` advisory lock) and
files a tracking issue on failure, plus a sentinel lint that keeps the wiring
honest as new gated suites are added.

*Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).*

## Enhancement Summary

**Deepened on:** 2026-10-10
**Sections enhanced:** Proposed Solution (scheduled-substrate check), Encryption
Posture (skip-form per precedent), Architecture Decision (C4 enumeration)
**Research agents used:** none — subagent spawning unavailable in this pipeline
context; all deepen-plan halt gates and quality checks were executed inline.

### Key Improvements

1. Inngest-vs-GH-Actions substrate decision recorded (ADR-033 gate fired: 57
   `cron-*.ts` exist; GHA justified on repo-scope, no-memoization-benefit, and
   the prd-container credential boundary).
2. `discoverability_test.expected_output` pinned to `uncovered=0` — the sentinel
   summary-line contract is now specified once, in Proposed Solution.
3. C4 "no impact" claim replaced an unsupported assertion with the mandated
   actor/system/container/relationship enumeration.

### Gates Run (deepen-plan, inline)

- 4.4 precedent-diff: PASS (`dev-suite-mutex.sh` reused verbatim; scheduled-work
  check resolved to GHA)
- 4.6 User-Brand Impact: PASS | 4.7 Observability: PASS | 4.8 PAT shapes: none
- 4.9 UI-wireframe: N/A | 4.10 Encryption Posture: skipped-form (precedent)
- 4.11 Guard Contract: `lint-guard-contract.py` rc=0, assembly structural
- 4.12 Scope Check: PASS (all asks mapped; one inferred item justified)
- Plan-review standing check: ACs are deterministic over file state/fixtures —
  the multi-agent review panel could not be spawned here (no Task tool) and is
  noted as an uncovered lane for the pipeline.

## Problem Statement / Motivation

A `describe.skipIf(!process.env.<GATE>)` suite that no CI job un-gates passes
vacuously forever — strictly worse than no test, because the green summary reads
as coverage. The pyramid census (#9855) measured ~40% of the integration layer in
exactly this state. PR 1 (#9890, merged) fixed the marker/demotion half; this PR
is the CI half. The gap cannot fix itself: each new env-gated suite lands dormant
by default, so the fix pairs coverage (the scheduled leg) with a durability guard
(the gate-coverage sentinel).

## Research Insights

**Premise Validation (Phase 0.6).** `gh issue view 9855` → OPEN, no
`closedByPullRequestsReferences`; `gh pr view 9890` → MERGED 2026-10-09 (PR 1);
`gh pr view 9947` → OPEN draft on this branch. All seven gate vars grep-verified
in test sources and absent from `.github/` and `scripts/` — premise holds.
Correction to the issue text: `SUPABASE_DEV_INTEGRATION` gates **6** files, not 5
— the issue undercounts `test/server/conversation-visibility.tenant-isolation.test.ts`,
which is collected by the existing `test/server/` path filter but skips anyway
because that job exports only `TENANT_INTEGRATION_TEST`.

**Property List (Phase 0.6b).**

- P1 — every gate var in the issue's set is exported by a CI workflow, so its suites execute rather than skip.
- P2 — dev-Supabase writes from the new leg serialize against all other dev writers.
- P3 — a suite failure is loud (red run + tracked issue), never silent.
- P4 — no new secrets or credential provisioning; no path to prd credentials.
  (One Terraform resource IS added — the `sentry_cron_monitor` for the dead-man
  arm — a config-plane object the existing Sentry provider applies at merge,
  carrying no secret.)
- P5 — a NEW env-gated suite cannot silently re-create the dormancy class.
- P6 — cost and flake bounded to a scheduled cadence, not per-PR.

**Cut List (Phase 0.6b).**

- Per-PR leg / required-check wiring → buys "pre-merge gating" — CUT. No bounded
  `detect-changes` surface exists for these suites (BYOK crypto, concurrency
  slots, DSAR export, realtime subscriptions share no path glob); a broad trigger
  would burn the #5585 dev-Supabase rate budget and inflate the required-check
  flake surface. Scheduled-only covers P1/P3/P6. Promotion is a follow-up if
  nightly proves the suites stable.
- Extend `tenant-integration.yml` in place → buys P1 as well as a sibling file —
  CUT in favor of a sibling `scheduled-*.yml`. The existing file is a
  required-check contract with merge_group/detect-changes/aggregator arms tuned
  to PR semantics; a cron leg inside it forces every one of those arms to reason
  about a new event kind.
- Dedicated/fresh Supabase project per run (README §"Run behavioral suites
  against a DEDICATED, freshly-migrated Supabase project") → buys "clean-replica
  fidelity" — CUT. The Free-tier quota is 2 projects and both are allocated
  (ADR-023); a third project is new spend plus a Management-API provisioning
  step that `dev_scheduled` deliberately cannot hold (DC-1, #8028), and ADR-061
  already rejected an ephemeral throwaway DB per run as heavyweight. The plan
  adopts shared dev + apply-migrations + mutex — the substrate ~55
  tenant-isolation suites already run on — and records the residual below.
- Copy the drift probes / ledger parity into the new leg → they guard the PR
  *unmerged-apply* path; a cron leg applies merged migrations only, and
  `scheduled-dev-migration-drift.yml` already owns drift. CUT — except the two
  *live-state* preflights (`preflight-schema-vs-ledger.sh`,
  `preflight-worm-cascade-contradiction.sh`), which plan review reinstated:
  equally relevant nightly, and they name the offending relation instead of an
  opaque GoTrue 500.
- Terraform `doppler_secret` for `MU1_FIXTURE_*` → unneeded: live-verified
  `dev_scheduled` already carries `MU1_FIXTURE_REPO_URL`,
  `MU1_FIXTURE_INSTALLATION_ID`, `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, and
  all four Supabase keys (`doppler secrets --only-names -p soleur -c
  dev_scheduled`, 2026-10-10).

**Key file paths.**

- `.github/workflows/tenant-integration.yml` — the dev-Supabase CI substrate this
  plan mirrors (Doppler env assertion, `scripts/dev-suite-mutex.sh` acquire/release,
  `run-migrations.sh --bootstrap=skip`, seed-bot-fixtures).
- `.github/workflows/scheduled-realtime-probe.yml` — the scheduled-leg pattern
  (cron + `workflow_dispatch`, `issues: write`, record-failure → file/comment
  tracking issue, `strip_log_injection`).
- `.github/workflows/rls-authz-fuzz.yml` — covers the rls-fuzz family (the issue's
  other already-covered leg; `RLS_FUZZ_DATABASE_URL`, not env gates).
- `apps/web-platform/test/README.md` — env-flag conventions + the dedicated-project
  guidance this plan consciously deviates from (see Risks).
- `apps/web-platform/vitest.config.ts` — all gated files run under the `unit`
  project (`test/**/*.test.ts`; zero matches in `test/repo-wide-suites.ts`).
- `scripts/lint-orphan-test-suites.sh` + `.test.sh` — the nearest precedent for
  the sentinel (registered via `run_suite` in `scripts/test-all.sh:5157`,
  companion battery sharded `--rows 1-10` / `--rows 11-20` at :5183-5184, lint
  step in ci.yml's `lint-bot-statuses` job ~:345).
- Gate census (`git grep -hoE 'process\.env\.[A-Z0-9_]+ *(===|!==) *"1"' --
  test/ lib/`): `TENANT_INTEGRATION_TEST` (wired), the seven dormant vars, plus
  `RLS_FUZZ_LOCAL`, `SOLEUR_ISOLATION_IN_IMAGE`, `SOLEUR_ISOLATION_TEST_HOST`,
  `ANTHROPIC_ISOLATION_TEST_OK` — the last four are deliberate local/image/host
  opt-in arms, not CI gates (allowlist candidates for the sentinel).

**Relevant learnings/ADRs.** ADR-023 (2-project quota, both allocated); ADR-061
(shared-dev substrate + ephemeral-DB rejection + per-ref-ownership pattern);
#8028 DC-1 (no `SUPABASE_ACCESS_TOKEN` in `dev_scheduled`); #7986/#8048 (repo-wide
concurrency starved the queue — reuse the per-ref key + advisory mutex instead);
`2026-05-06-supabase-default-privileges-defeat-revoke-from-public` (grant-state
assertions can differ on shared dev — the README's "clean replica" concern);
`2026-06-02-drift-guard-bare-path-grep-vacuous` (producer must be a census, not a
directory-scoped grep — the sentinel greps the whole `test/` tree).

**Research Reconciliation — issue vs. codebase.**

| Issue claim | Reality | Plan response |
|---|---|---|
| `SUPABASE_DEV_INTEGRATION` (5 DSAR/cross-tenant files) | 6 files — `server/conversation-visibility.tenant-isolation.test.ts` also gates on it and currently skips inside the `test/server/` run | Wire all six in one vitest invocation |
| "Extend tenant-integration.yml or add a sibling leg" | Sibling scheduled file is cleaner given the required-check arms | `.github/workflows/scheduled-integration-suites.yml` |
| "Requires dev-Supabase secrets via Doppler" | `dev_scheduled` already holds every needed secret incl. `MU1_FIXTURE_*` + `GITHUB_APP_*` | Reuse `DOPPLER_TOKEN_DEV_SCHEDULED`; zero provisioning |

**Open Code-Review Overlap (Phase 1.7.5).** Open `code-review`-labeled issues
searched for every planned path (`tenant-integration.yml`,
`scheduled-dormant-integration`, `mu1.integration.test.ts`, `test/README.md`,
`lint-orphan-test-suites`, `SUPABASE_DEV_INTEGRATION`, `dev-suite-mutex`). One
tangential hit: #8800 (lint-orphan fixture inode sharing) — **acknowledge**:
unrelated file set, no action.

## Proposed Solution

**Scheduled-work substrate check (deepen-plan Phase 4.4 precedent gate).**
ADR-033 prefers Inngest crons — 57 `cron-*.ts` functions exist — but this job
belongs in GitHub Actions on three grounds: (a) the work is purely
git/repo-scoped test execution requiring a fresh checkout, `npm ci`, vitest,
`dev-suite-mutex.sh`, and `run-migrations.sh` — the same shape as
`tenant-integration.yml`, `rls-authz-fuzz.yml`, and `scheduled-realtime-probe.yml`;
(b) `step.run` memoization/replay buys nothing for a vitest run; (c) the
decisive boundary: Inngest functions execute inside the deployed web-platform
container holding **prd** credentials — running dev-scoped service-role writes
from that environment would plumb dev credentials into the prd runtime, the
inverse of the isolation ADR-023 exists to guarantee. The
`new-scheduled-cron-prefer-inngest.sh` PreToolUse hook may flag the new
`scheduled-*.yml` at write time; this paragraph is the recorded justification.

New workflow `.github/workflows/scheduled-integration-suites.yml`. **Line 1
carries the literal `<!-- gate-override: new-scheduled-cron-prefer-inngest -->`
comment** — the `new-scheduled-cron-prefer-inngest.sh` PreToolUse hook DENIES any
new `scheduled-*.yml` containing a `schedule:`/`cron:` token without it (the
ADR-033 justification paragraph above is the companion documentation; the hook
reads the YAML, not the plan — `scheduled-supabase-watchdog.yml:1-11` is the
precedent shape). Header comment then carries `name: "Scheduled: integration
suites"`, the 3-point Inngest-vs-GHA justification, and the
concurrency-eviction edge note below.

`schedule: cron '30 4 * * *'` (04:30 UTC — neighbors surveyed: `apply-inngest-rls`
04:17, `workspaces-luks-verify` 04:41, `kb-drift-walker` 03:00, the congested
probe fleet at 06:00–07:00; Inngest-dispatched `cron-dev-migration-drift` fires
every 6h at HH:15 and does not take the dev-suite mutex — no dev-Supabase
contention) + `workflow_dispatch`. One job, `timeout-minutes: 60` (the repo's
timeout rule: the job ceiling dominates the SUM of step ceilings — ~8min
setup+apply + ~4min max mutex wait + 8×6min suite steps ≈ 60; a step timeout is
a step *failure* the filer reports, so the arithmetic self-tunes), 
`permissions: {contents: read, issues: write}`, `concurrency` declared at JOB
level per the tenant-integration precedent with
`group: dev-supabase-${{ github.ref }}` and `cancel-in-progress: false` (same
per-ref key as tenant-integration; serialized further by the advisory mutex for
cross-ref coverage). **Concurrency-edge comment (required in the file):** on
`schedule` the group resolves to `refs/heads/main` — the same group as
push-to-main `tenant-integration` runs; with `cancel-in-progress: false` and
GitHub's one-pending-per-group limit, the cron arrival can evict a *pending*
main run → `cancelled`. Rare at 04:30 UTC and the shared key is deliberate
(GHA-level serialization the advisory mutex cannot give); the comment names the
edge so nobody "fixes" it later.

Step order, mirroring `tenant-integration.yml`'s heavy job minus its PR-only
guards:

1. checkout (default `fetch-depth` — no PR-diff steps; the precedent's
   `fetch-depth: 2` exists for diff context this job lacks)
2. Setup Bun (`.bun-version`) + Node 22 (`cache: npm`,
   `cache-dependency-path: apps/web-platform/package-lock.json`)
3. `npm ci --ignore-scripts` in `apps/web-platform`
4. Install Doppler CLI via `DopplerHQ/cli-action` pinned to the SAME v4 SHA
   `tenant-integration.yml` uses (`@5351693…` — not the realtime probe's older
   v3 pin)
5. Verify `DOPPLER_TOKEN_DEV_SCHEDULED` non-empty — fail, never silent-skip
   (the gate trap this whole issue exists to close)
6. Assert `dev_scheduled` → `environment=dev` and absent
   `SUPABASE_ACCESS_TOKEN` (verbatim copy of the tenant-integration assertion
   block, incl. `strip_log_injection` on the env name — `hr-dev-prd-distinct-supabase-projects` + #8028 DC-1)
7. `scripts/dev-suite-mutex.sh acquire` under `doppler run -c dev_scheduled`,
   `DEV_SUITE_MUTEX_IDENTITY: di-${{ github.run_id }}-${{ github.ref_name }}`,
   **`DEV_SUITE_MUTEX_HOLD_S: "3900"`** — the script's own invariant
   (`dev-suite-mutex.sh` › header) requires the hold ceiling to EXCEED the job
   timeout; default 1170s was sized for tenant-integration's 15-minute job and
   would release the lock ~40min early under this job's 60-minute ceiling.
8. Seed bot fixtures (soft-fail `::warning::`). Real dependency, not parity
   cargo: merged migrations such as `071_ux_audit_artifacts_bucket.sql`
   reference `auth.users` rows that `bot-fixture.ts` creates
   (`tenant-integration.yml` seed-step comment) — without the seed the apply
   degrades gracefully but defers RLS policy.
9. `preflight-schema-vs-ledger.sh` + `preflight-worm-cascade-contradiction.sh`
   — live-state guards, NOT PR-unmerged-apply artifacts (the earlier draft of
   this plan mischaracterized them): on a poisoned shared-dev they name the
   offending relation instead of surfacing an opaque GoTrue 500 three layers
   deep.
10. `run-migrations.sh --bootstrap=skip` under Doppler, with
    `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` and **without**
    `ALLOW_UNMERGED_DEV_APPLY` — a scheduled main-ref checkout applies merged
    migrations only; the unmerged-apply gate stays armed so a feature-branch
    dispatch refuses in-flight files.
11. Eight suite steps, each `working-directory: apps/web-platform`,
    `timeout-minutes: 6` (a step timeout = step *failure*: `!cancelled()`
    siblings still run and the filer fires — a job-level timeout is
    `cancelled`, which cannot be reported in-band), each
    `if: ${{ !cancelled() }}` (kept for pre-step aborts), each
    `doppler run -p soleur -c dev_scheduled -- env <GATE>=1 \
    npm run test:ci -- <files> --project unit --reporter=verbose`.
    The 8-step split is deliberate (and the honest justification, replacing
    the earlier "starve the evidence" overclaim — a single vitest invocation
    also runs every file): (a) `steps.<id>.outcome` gives the filed issue
    structured per-suite attribution without log-parsing, and (b) process
    isolation — a hard crash in one vitest invocation loses the remaining
    files' results entirely.
    `--project unit` only is correct today (explicit file lists; zero gated
    files in `test/repo-wide-suites.ts` — verified): a future repo-wide gated
    file would fail loudly ("no test files found" → red step → filed issue),
    and the sentinel's file-level arm (below) flags it as uncovered at
    lint time.

    | Step | Gate | Files |
    |---|---|---|
    | `supabase-dev` | `SUPABASE_DEV_INTEGRATION` | `test/beta-crm-dsar.integration.test.ts test/cc-dispatcher-cross-tenant.integration.test.ts test/conversations-rail-cross-tenant.integration.test.ts test/dsar-author-redaction.integration.test.ts test/dsar-export-cross-tenant.integration.test.ts test/server/conversation-visibility.tenant-isolation.test.ts` |
    | `worktree-lease` | `WORKTREE_LEASE_INTEGRATION_TEST` | `test/worktree-write-lease.integration.test.ts` |
    | `acquire-slot` | `ACQUIRE_SLOT_WS_INTEGRATION_TEST` | `test/concurrency-acquire-slot-workspace-id.integration.test.ts` |
    | `byok` | `BYOK_INTEGRATION_TEST` | `test/byok.integration.test.ts` |
    | `slot-trigger` | `SLOT_TRIGGER_INTEGRATION_TEST` | `test/conversation-archive-release-slot.integration.test.ts` |
    | `workspace-binding` | `WORKSPACE_BINDING_INTEGRATION_TEST` | `test/workspace-binding-restart-survival.integration.test.ts` |
    | `mu1` | `MU1_INTEGRATION` | `test/mu1.integration.test.ts` |
    | `departed-member` | `TENANT_INTEGRATION_TEST` | `test/dsar-departed-member.integration.test.ts` |

    The `departed-member` step wires a file-level dormancy found at plan
    review: `test/dsar-departed-member.integration.test.ts:66` gates on
    `TENANT_INTEGRATION_TEST` — a *wired* var — but lives at `test/` root while
    `tenant-integration.yml` collects only `test/server/`; it has never run in
    CI. This is the live instance that motivates the sentinel's file-level arm.

    MU1 AC-2 *will* engage — `dev_scheduled` carries `MU1_FIXTURE_*` +
    `GITHUB_APP_*` — minting a live installation token and cloning the fixture
    repo into a `mkdtemp` root. Intended: it verifies the signup→clone path
    nightly. The partial-set canary in the test file stays useful (fails loudly
    on a half-provisioned config).
12. `scripts/dev-suite-mutex.sh release`, `if: always()` (local-only, no Doppler
    needed — same comment block as tenant-integration; on a job-level cancel
    even this cannot run, which the HOLD_S ceiling covers by auto-expiry).
13. File-or-comment tracking issue on `${{ (failure() || cancelled()) &&
    github.ref == 'refs/heads/main' }}` — a job timeout records `cancelled`,
    never `failure` (repo-measured: `main-health-monitor.yml` header defect A,
    19/30 runs silent until fixed), and the ref gate keeps a feature-branch
    `workflow_dispatch` refusal from filing noise. Pattern from
    `scheduled-realtime-probe.yml`: label `ci/integration-suites`, title
    `[ci/integration-suites] Nightly integration suites failed`, body names the
    failing step(s) via `steps.<id>.outcome` (earliest failure first), run URL,
    UTC timestamp. **Include the stale-issue auto-close arm**
    (`scheduled-realtime-probe.yml` › "Auto-close stale issue (probe green)"):
    on a green main run, close the open tracker — otherwise one transient
    flake leaves a permanently open issue and trains the label to be ignored.
    The probe's email-notify arm is deliberately not copied (issue + heartbeat
    is enough).
14. Sentry check-in, terminal `if: always()` step via
    `./.github/actions/sentry-heartbeat`, `monitor-slug:
    scheduled-integration-suites`, status keyed on job outcome per the
    producer-outcome-first formula in `scheduled-realtime-probe.yml`'s
    heartbeat comment (#7138). This is the dead-man arm for the plan's own
    worst case — a `schedule:` that never fires produces no run and nothing to
    file (GitHub has measured-dropped scheduled runs; `cron-monitors.tf`
    records the 2026-05-26 realtime-probe drop) — a missed check-in pages the
    monitor instead.

New sentinel `scripts/lint-integration-env-gates.sh` (P5): censuses every
`process\.env\.[A-Z0-9_]+ *(===|!==) *"1"` gate under `apps/web-platform/test/`
**and `apps/web-platform/lib/`** (the `unit` project collects
`lib/**/*.test.ts` too — `vitest.config.ts`; a gate planted there would be
dormant *and* sentinel-invisible under a `test/`-only census — the
`lint-orphan-test-suites.sh` header already records the "one directory over"
lesson) via `git grep -hoE` on the tracked tree, and asserts each gate var
passes **both** arms:

- **Var-level wiring (anchored):** the var appears in a *setting position* in
  a `.github/workflows/*.yml` file — `env <VAR>=1` (run-prefix form) or
  `<VAR>: ["']?1` (env-mapping form) — matched on comment-stripped content.
  A bare-token match is vacuous: `tenant-integration.yml:4` today contains
  `# TENANT_INTEGRATION_TEST=1 …` *inside a comment*, so a comment-only
  reference would certify unwired while the suite still skips — the exact
  defect this sentinel exists to kill (cq-assert-anchor-not-bare-token).
- **File-level collection:** for every file containing a gate, the file is
  *collected* by a workflow that wires its var — its app-relative path
  (`test/…` / `lib/…`, prefix `apps/web-platform/` stripped for comparison)
  OR its parent directory at depth ≥ 2 (`test/server/`, trailing slash)
  appears as a whitespace/EOL-bounded token in that workflow. Bounded matching
  is load-bearing: `test/server/` must not satisfy a file whose parent is
  `test/`. A file may instead carry a per-file `collect:` allowlist entry
  (for gates collected via a non-path mechanism).

…or the var/file is listed in the script's allowlist with a non-empty `reason:
#N` — seed entries cite `#9855` (this issue documents why each is exempt).
Zero gates found → error (anti-vacuity, not a pass). Seed allowlist:

| Var | Reason |
|---|---|
| `RLS_FUZZ_LOCAL` | local disposable-Postgres arm only; CI arm runs via `RLS_FUZZ_DATABASE_URL` in `rls-authz-fuzz.yml` (#9855) |
| `SOLEUR_ISOLATION_IN_IMAGE` | in-image arm of `test/sandbox-isolation.test.ts` — runs inside the runtime image, not GitHub CI (#9855) |
| `SOLEUR_ISOLATION_TEST_HOST` | deliberate fail-loud host-capability opt-in; CI must not satisfy it (#9855) |
| `ANTHROPIC_ISOLATION_TEST_OK` | manual opt-in for a host-level destructive arm (#9855) |

The sentinel prints a stable summary line — exactly
`env-gates: found=<N> wired=<W> allowlisted=<A> uncovered=<U>` — with
`uncovered=0` as the success contract (this literal is also the
Observability `discoverability_test.expected_output` below, so it is pinned
here, once). `found` counts gated *files*; a file whose var is wired but whose
path is uncollected counts as uncovered.

Companion battery `scripts/lint-integration-env-gates.test.sh` runs the
mutation matrix over a scratch fixture tree. Fixture mechanism: the sentinel
takes a `SOLEUR_LINT_GATES_ROOT` env override for producer/consumer roots
(`lint-orphan-test-suites.sh`'s `BASH_SOURCE`-derived `REPO_ROOT` does not
port to a fixture — spec, don't improvise).

Registration: `run_suite` lines in `scripts/test-all.sh` for the sentinel and
its companion battery (unconditional — seconds on a scratch tree; interact
with `suite-shard-legs{,-heavy}.tsv` via `scripts/regenerate-shard-manifest.py`
and `scripts-shard-totality.test.sh` `--rows` pinning per the orphan battery's
registration shape), plus one advisory step in ci.yml's
`lint-bot-statuses` job next to `lint-orphan-test-suites.sh` — born-advisory,
same promotion path (`required-checks.txt` + ruleset) the existing lints use.
The dual registration (test-all.sh *and* the ci.yml step, so the sentinel runs
twice per PR) is deliberate, matching `lint-orphan-test-suites.sh`.
"Advisory" names the branch-protection contract only: a red sentinel still
reds the ci.yml run `conclusion`, and its `run_suite` registration lands it in
the `main-health-monitor.yml` sweep (Inngest-dispatched every 6h, files a
`ci/main-broken` P1 on red) — *that* is the post-merge watcher
(`post-merge-monitor.yml` filters `[bot-fix]` commits only and does not see
ordinary merges; an earlier draft of this plan misattributed the alarm).
Intended, because the sentinel is deterministic (pure `git grep` on the
tracked tree, no network), so its red means a real uncovered gate or a
sentinel bug, never a flake worth suppressing.

Docs: `apps/web-platform/test/README.md` gains a "CI wiring" paragraph naming the
new workflow, the eight gates it sets (incl. `TENANT_INTEGRATION_TEST` for the
departed-member file), and the shared-dev caveat — **and the flag table at the
top is completed** (it currently lists only 3 of the 8+ gated suites, already
stale). Also fix the now-false comment at `test/mu1.integration.test.ts:220`
("CI never sets MU1_FIXTURE_*…" — false the night this merges).

## Implementation Phases

**Phase 1 — sentinel first (failing-test-first).** Author
`scripts/lint-integration-env-gates.sh` + companion battery. It MUST go red on
the current tree (7 unwired vars + the departed-member uncollected file) — that
red is the failing-test proof. Wire its `run_suite` registrations but do not
commit a green yet.

**Phase 2 — the workflow.** Author
`.github/workflows/scheduled-integration-suites.yml` per Proposed Solution
(marker line 1, HOLD_S, per-step timeouts, 8 suite steps, filer + auto-close +
heartbeat). The sentinel flips green only once every non-allowlisted gate
appears in a setting position AND every gated file is collected.

**Phase 3 — monitor IaC + CI wiring + docs.** `sentry_cron_monitor` +
unrouted alert entry (same PR as the heartbeat step — parity test enforces it);
advisory lint step in `lint-bot-statuses`; README paragraph + flag-table
completion + mu1 comment fix; shard-manifest regeneration if the battery's
registration requires it.

## Files to Create

- `.github/workflows/scheduled-integration-suites.yml` (~260 lines)
- `scripts/lint-integration-env-gates.sh` (~160 lines)
- `scripts/lint-integration-env-gates.test.sh` (~200 lines)

## Files to Edit

- `scripts/test-all.sh` — two `run_suite` lines beside the
  `lint-orphan-test-suites*` block (~:5157-5188)
- `.github/workflows/ci.yml` — one step in the `lint-bot-statuses` job beside
  "Lint orphan test suites" (~:344)
- `apps/web-platform/test/README.md` — "CI wiring" paragraph + complete the
  stale flag table
- `apps/web-platform/test/mu1.integration.test.ts` — fix the stale
  "CI never sets MU1_FIXTURE_*" comment at :220
- `apps/web-platform/infra/sentry/cron-monitors.tf` — new
  `sentry_cron_monitor` `scheduled-integration-suites`
  (`checkin_margin_minutes = 1440`, the realtime-probe's measured
  false-alarm-free margin for daily GHA crons; `sentry-monitor-iac-parity.test.ts`
  enforces slug parity — resource + workflow step land in the SAME PR, and a
  typo'd slug pages "missed check-in" forever per `cron-monitors.tf`)
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — unrouted entry
  per the two-PR convention (#8630, README §186-199; the routed alert is the
  follow-up)

## User-Brand Impact

- **If this lands broken, the user experiences:** either a nightly `ci/integration-suites`
  issue filing noise a founder must triage (flake arm), or — the worse arm — a
  sentinel/workflow that never runs while looking wired, reproducing the vacuous-green
  defect this plan exists to close.
- **If this leaks, the user's [data / workflow / money] is exposed via:** a
  mis-scoped Doppler token reaching prd — bounded by the same
  `environment=dev` + `SUPABASE_ACCESS_TOKEN`-absence assertions
  `tenant-integration.yml` enforces before any Supabase secret is touched. The
  suites write only synthetic identities (`*@soleur-test.invalid`, UUID-scoped)
  to the dev project.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change adds coverage and cannot
  regress a code path users execute; its worst case is CI noise or continued
  dormancy, both repo-internal.
- `threshold: none, reason: the only credential-handling file is a new scheduled workflow that reads the existing dev-scoped Doppler token; it creates no user-facing surface and writes only synthetic rows to dev.`

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions nightly run 'Scheduled: integration suites' + Sentry cron-monitor check-in (dead-man arm: a never-fired or killed run misses its check-in and pages) + ci/integration-suites tracking issue on failure"
  cadence: "daily 04:30 UTC (cron '30 4 * * *') + workflow_dispatch"
  alert_target: "GitHub issue labeled ci/integration-suites (created/commented/closed) + Sentry cron monitor 'scheduled-integration-suites' (missed check-in)"
  configured_in: ".github/workflows/scheduled-integration-suites.yml (on.schedule + issue-filing + sentry-heartbeat steps) + apps/web-platform/infra/sentry/cron-monitors.tf (sentry_cron_monitor resource)"
error_reporting:
  destination: "the tracking issue + the Actions run log; each suite step's outcome surfaces per-gate attribution"
  fail_loud: "run conclusion failure + ::error:: annotations + issue body naming steps.<id>.outcome"
failure_modes:
  - mode: "Doppler token missing or rotated to non-dev scope"
    detection: "explicit non-empty check + environment=dev assertion, ::error:: before any Supabase access"
    alert_route: "red run + tracking issue"
  - mode: "dev-suite mutex contention / residual drift from a contended sibling"
    detection: "dev-suite-mutex.sh's DEV_SUITE_MUTEX_CONTENDED_PROCEEDING path (deliberately fail-open); suites failing on shared-dev cruft is the signal itself"
    alert_route: "per-suite step outcome in the filed issue"
  - mode: "a new env-gated suite added with no CI wiring (dormancy recurrence)"
    detection: "scripts/lint-integration-env-gates.sh census, run in ci.yml lint-bot-statuses (advisory) and test-all.sh"
    alert_route: "advisory red on the PR + suite registration in test-all"
  - mode: "MU1 AC-2 fires and cannot mint an installation token (fixture creds drift)"
    detection: "the test's own partial-set canary + hard failure"
    alert_route: "mu1 step outcome in the filed issue"
  - mode: "job-level timeout or runner cancellation (records cancelled, never failure)"
    detection: "filer gated on failure() || cancelled(); per-step timeout-minutes keep a single hung suite a step failure, not a job cancel"
    alert_route: "tracking issue (main-ref runs only) + missed Sentry check-in if the job dies before it"
  - mode: "schedule never fires (disabled workflow, on: drift, GitHub dropped run — measured 2026-05-26 on the realtime probe)"
    detection: "sentry-heartbeat terminal if: always() step; missed check-in pages the cron monitor"
    alert_route: "Sentry cron monitor 'scheduled-integration-suites' missed-check-in alert"
logs:
  where: "GitHub Actions run logs, 90-day retention (repo default)"
  retention: "90 days"
discoverability_test:
  command: bash scripts/lint-integration-env-gates.sh
  expected_output: uncovered=0
```

The discoverability command IS the sentinel: the smallest command that prints
the coverage signal this change exists to produce. The `env-gates:` summary
line's exact shape is pinned in Proposed Solution so `expected_output` is a
literal substring, not a description.

## Encryption Posture

Skipped per Phase 2.11: the plan introduces no persistent data store and no
new cross-component or network connection. The leg reuses the
runner→Doppler, runner→dev-Supabase, and runner→api.github.com edges that
`tenant-integration.yml` and `scheduled-realtime-probe.yml` already establish
(TLS with cert verification on, enforced by the hosted clients); MU1 AC-2's
fixture clone is `https://github.com/` (the test itself asserts the scheme).
Files checked: the two `.tf` edits are Sentry-monitor config-plane objects
(no data store, no network edge — the runner→Sentry check-in edge already
exists in 16 workflows); no `supabase/migrations/*.sql`, no
`cloud-init*.yaml`, no `docker-compose*.yaml` in Files to Create/Edit.

## Architecture Decision (ADR/C4)

**No ADR.** No ownership/tenancy move, no new substrate or trust boundary — the
scheduled leg is a third consumer of the already-decided shared-dev CI substrate
(ADR-061 substrate, ADR-023 isolation, `dev-suite-mutex`). The one judgment that
could read as architectural — scheduled-only on shared dev vs. a dedicated
project — is the alternative ADR-061 already weighed and rejected, and is
recorded as a deviation note in `test/README.md` (Files to Edit) with the
dedicated-project revisit trigger.

**No C4 impact — enumerated against the three model files**
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
(a) no new external human actor (the leg acts on synthetic `*@soleur-test.invalid`
identities, not people); (b) no new external system or vendor — dev Supabase,
Doppler, and the GitHub API/App are all already modeled edges; (c) no new
container or data store — the workflow runs on GitHub-hosted runners writing to
the existing dev project; (d) no actor↔surface access relationship changes.
Derived cardinalities (edge prose counts) are not reached by this rubric.

## Guard Contract

### Guard 1 — `scripts/lint-integration-env-gates.sh`

**Property.** Every `process.env.<VAR> ===|!== "1"` integration-test gate in the
tracked `apps/web-platform/test/` + `apps/web-platform/lib/` trees is either
(a) *set* by a `.github/workflows/*.yml` file AND every file carrying it is
*collected* by a workflow that sets it, or (b) allowlisted with a non-empty
reason + issue ref — so no gated suite can report green while never running in
CI, at either the var level or the file level.

**Assembly.** Producer: `git grep -hoE 'process\.env\.[A-Z0-9_]+ *(===|!==) *"1"' -- apps/web-platform/test/ apps/web-platform/lib/` (whole tracked tree — the canonical gate idiom only; non-`"1"` gates like `RLS_FUZZ_DATABASE_URL` presence checks are outside the idiom by design, same scope-boundary discipline as lint-orphan-test-suites' suffix keying; `lib/` is in scope because the `unit` project collects `lib/**/*.test.ts`). Consumer set: every file under `.github/workflows/` — comment-stripped — matching only *setting positions* `env <VAR>=1` or `<VAR>: ["']?1` (a bare-token or comment match does NOT count as wired; `tenant-integration.yml:4` is the live counterexample), plus the script's own allowlist table — the single chokepoint for exemptions, each entry forced to carry `reason: #N`. File-level arm: for each gated file, its app-relative path (`apps/web-platform/` stripped) OR its depth-≥2 parent dir with trailing slash must appear whitespace/EOL-bounded in a workflow that sets the gate; per-file `collect:` allowlist entries cover non-path collection mechanisms. `SOLEUR_LINT_GATES_ROOT` env override redirects producer+consumer roots for the fixture battery.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `TENANT_INTEGRATION_TEST=1` from `tenant-integration.yml` | RED |
| 2 | Repoint the producer grep at a path with no matches (0 gates found) | RED — zero-census is vacuous, not clean |
| 3 | Add `process.env.NEW_GATE === "1"` to an existing test file with no workflow wiring | RED |
| 4 | Add a second unwired gate after a compliant first in one fixture (check must not stop at first member) | RED naming BOTH |
| 5 | Rename the gate var in the test file only (test/workflow spelling drift) | RED |
| 6 | (harness) Delete one mutation row from `lint-integration-env-gates.test.sh` — remaining rows still exercise the sentinel, and the battery itself fails if the sentinel reports "0 checked" | RED on the battery's own anti-vacuity assertion |
| 7 | (must-PASS, non-canonical input) Gate referenced as `FOO: "1"` in `env:` mapping form instead of `env FOO=1` prefix form — both spellings count as wired | PASS |
| 8 | Gate var present only inside a workflow `#` comment (`# FOO=1` — the `tenant-integration.yml:4` shape) | RED |
| 9 | Gate planted in `apps/web-platform/lib/` (collected by `unit`, outside a `test/`-only census) | RED |
| 10 | Gated file whose var IS wired but whose path is collected by no workflow (the `dsar-departed-member` shape — var-level green, file-level dormant) | RED |
| 11 | (must-PASS) Gated file under `test/server/` covered by the `test/server/` dir-filter token in the wiring workflow | PASS |

**Anchor.** The allowlist lives in-repo, so a PR could add a gate AND exempt it
in one diff — the sentinel cannot see motive, only that every exemption carries a
non-empty `reason:` and a `#N` tracking reference that review must ratify (the
same trust shape as `lint-orphan-test-suites.sh` exclusions). The workflow-dir
side is anchored on `git ls-files` under `.github/workflows/`, so the set cannot
be narrowed by editing a manifest.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Wire the orphaned env gates into CI. … The remaining gates — `SUPABASE_DEV_INTEGRATION` (5 DSAR/cross-tenant files), `WORKTREE_LEASE_INTEGRATION_TEST`, `ACQUIRE_SLOT_WS_INTEGRATION_TEST`, `BYOK_INTEGRATION_TEST`, `SLOT_TRIGGER_INTEGRATION_TEST`, `WORKSPACE_BINDING_INTEGRATION_TEST`, `MU1_INTEGRATION` — are set **nowhere** in `.github/` or `scripts/`; those `describe.skip` suites pass vacuously on every run." [issue #9855 PR 2] | Phase 2 / `scheduled-integration-suites.yml` (Files to Create) | mapped |
| 2 | "Extend tenant-integration.yml or add a sibling leg." [issue #9855] | Proposed Solution — sibling `.github/workflows/scheduled-integration-suites.yml` | mapped |
| 3 | "Requires dev-Supabase secrets via Doppler — decide per-suite whether per-PR or scheduled-only (real dev-project writes; cost + flake budget)." [issue #9855] | Proposed Solution preamble + Cut List — scheduled-only, all seven gates, `dev_scheduled` reuse | mapped |
| 4 | "dedicated/fresh project per test/README contract" decision [resume prompt] | Proposed Solution + Cut List + README deviation note | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `.github/workflows/scheduled-integration-suites.yml` | "Extend tenant-integration.yml or add a sibling leg" | asked |
| `scripts/lint-integration-env-gates.sh` + `.test.sh` + test-all.sh + ci.yml registrations | — | inferred — justification: the issue's own defect class is "gates set nowhere in .github/ or scripts/ … pass vacuously"; without a census the next gated suite re-creates it, matching the repo's lint-orphan-test-suites precedent (durability guard for a registration property) |
| `apps/web-platform/test/README.md` paragraph | "dedicated/fresh project per test/README contract" | asked (records the contract deviation the prompt demands be resolved) |

### Split Assessment

- Subsystems touched: 4 — `.github`, `scripts`, `apps/web-platform/test`,
  `apps/web-platform/infra/sentry`
- Planned files: 9 | Estimated changed lines: ~900
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one cohesive feature (the monitor IaC is the
  dead-man arm of the same liveness contract; splitting it would break the
  `sentry-monitor-iac-parity` invariant the PR itself relies on)

## Acceptance Criteria

- [ ] `.github/workflows/scheduled-integration-suites.yml` exists with the literal `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` comment near the top, `schedule:` (`30 4 * * *`) + `workflow_dispatch`, no `pull_request`/`merge_group` triggers, `permissions: {contents: read, issues: write}`, job-level `concurrency.group: dev-supabase-${{ github.ref }}` with `cancel-in-progress: false`, `timeout-minutes: 60`.
- [ ] The workflow asserts `dev_scheduled` resolves `environment=dev` and holds no `SUPABASE_ACCESS_TOKEN` before any Supabase secret is touched (block copied from `tenant-integration.yml` semantics, incl. `strip_log_injection`).
- [ ] `scripts/dev-suite-mutex.sh` acquire precedes all dev-touching steps with `DEV_SUITE_MUTEX_HOLD_S` set > the job timeout (3900) and `release` runs `if: always()`; identity `di-${{ github.run_id }}-${{ github.ref_name }}`.
- [ ] `run-migrations.sh --bootstrap=skip` runs under `doppler run -c dev_scheduled` with `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` and NO `ALLOW_UNMERGED_DEV_APPLY`, preceded by the two live-state preflights.
- [ ] Eight suite steps export the gate vars `=1` over the thirteen files enumerated in Proposed Solution (6 under `SUPABASE_DEV_INTEGRATION` incl. `server/conversation-visibility.tenant-isolation.test.ts`; `test/dsar-departed-member.integration.test.ts` under `TENANT_INTEGRATION_TEST`), each `working-directory: apps/web-platform`, `timeout-minutes: 6`, `if: ${{ !cancelled() }}`, `npm run test:ci -- … --project unit --reporter=verbose` under `doppler run`.
- [ ] A reporting step files-or-comments a `ci/integration-suites`-labeled issue on `${{ (failure() || cancelled()) && github.ref == 'refs/heads/main' }}` naming the failing step outcome(s) and run URL, and a sibling step auto-closes the stale tracker on a green main run (both per `scheduled-realtime-probe.yml` shape).
- [ ] A terminal `if: always()` `sentry-heartbeat` step with `monitor-slug: scheduled-integration-suites` exists, and `apps/web-platform/infra/sentry/cron-monitors.tf` declares the matching `sentry_cron_monitor` (+ unrouted `cron-monitor-alerts.tf` entry) in the same PR — `sentry-monitor-iac-parity.test.ts` green.
- [ ] `scripts/lint-integration-env-gates.sh` exits non-zero listing ≥1 uncovered gate on a tree where a `process.env.X === "1"` gate has no workflow reference; exits non-zero when its own census finds 0 gates; a comment-only workflow mention does NOT satisfy wiring; an uncollected gated file does NOT satisfy coverage; on `origin/main` after this PR it prints `env-gates: found=<N> wired=<W> allowlisted=<A> uncovered=0` and exits 0.
- [ ] `scripts/lint-integration-env-gates.test.sh` implements all Guard Contract mutation rows (incl. rows 8-11) in a scratch fixture tree via `SOLEUR_LINT_GATES_ROOT`; both files registered via `run_suite` in `scripts/test-all.sh`; sentinel step added to ci.yml `lint-bot-statuses` (advisory — NOT added to `scripts/required-checks.txt` or the ruleset); `bash scripts/lint-orphan-test-suites.sh` passes with the new files tracked (registration proven by the census, not assumed).
- [ ] `apps/web-platform/test/README.md` names the new workflow, lists the eight gates it sets, completes the stale flag table, and records the shared-dev substrate decision with the dedicated-project revisit trigger; `test/mu1.integration.test.ts:220`'s stale comment is fixed.
- [ ] Post-merge, one `gh workflow run scheduled-integration-suites.yml` dispatch on `main` reaches the suite steps and files or comments a `ci/integration-suites` issue on any red — verified by `gh run watch` (pipeline post-merge step; no live dev writes are performed inside the planning/implementing session beyond this dispatch).

## Plan-Review Consolidation

Four-seat panel (DHH / Kieran / code-simplicity / CTO-devex) — 4×
APPROVE-WITH-CHANGES. All consolidated findings classified **Mechanical** (one
right answer each: spec-vs-precedent drift, guard vacuity, missing repo-convention
arms) and auto-applied above; **no Taste/User-Challenge findings** — the
scheduled-vs-per-PR, sibling-file, and shared-dev decisions survive intact.
Applied: mutex `HOLD_S` invariant; timeout→`cancelled` filer gap + per-step
timeouts; dead-man heartbeat + monitor IaC; sentinel anchored consumer (comment
false-positive at `tenant-integration.yml:4`), `lib/` producer scope, and
file-level collection arm (live instance: `dsar-departed-member`); auto-close
stale tracker; gate-override marker; `main-health-monitor` (not
`post-merge-monitor`) watcher correction; `reason: #N` seed contract; Doppler v4
pin; `working-directory`/`cancel-in-progress`/job-level-concurrency pins;
live-state preflights; README table + mu1 comment; fetch-depth and
7-vs-8-steps justification corrections. Deliberately not applied (documented):
probe's email-notify arm (issue+heartbeat sufficient); culprit-PR attribution in
the issue body (step-outcome attribution + run URL suffice at nightly cadence).

## Test Scenarios

- `unit` — sentinel companion battery: Given a fixture tree with a `process.env.NEW_GATE === "1"` gate and no workflow reference, when `lint-integration-env-gates.sh` runs, then it exits non-zero naming `NEW_GATE` (rows 1-6 of the Guard Contract matrix).
- `unit` — Given a fixture with gate `FOO` wired as `FOO: "1"` under `env:` in a workflow, when the sentinel runs, then it passes (row 7).
- `unit` — Given a fixture where the producer census finds zero gates, when the sentinel runs, then it exits non-zero reporting the vacuous census (row 2).
- `integration` — workflow_dispatch on `main` post-merge: Given the merged workflow, when dispatched, then the env assertion, mutex acquire, migration apply, and all seven suite steps execute in order and the run outcome is reported (success, or a filed issue).
- `integration` — Given a suite failure mid-run, when a later gate's step is evaluated, then `!cancelled()` still executes it (failure attribution coverage), and the issue-filing step names every failed `steps.<id>.outcome`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/test-infrastructure change with no
user-facing surface, no schema/data, no legal/finance/marketing surface. The
mechanical UI-surface override did not fire (no `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit).

## Risks / Sharp Edges

- **Shared-dev flake.** README prefers a dedicated fresh project for these
  behavioral suites; shared dev accumulates grant/cruft divergence
  (`2026-05-06-supabase-default-privileges-defeat-revoke-from-public`) and GoTrue
  rate limits under mass user create/delete. Mitigations: mutex serialization,
  migration apply before tests, suites' synthetic-UUID scoping +
  `helpers/gotrue-retry.ts`. Revisit trigger: two consecutive nightly filings
  attributable to substrate cruft rather than a real regression → reopen the
  dedicated-project evaluation (cost: paid tier + Management-API custody).
- **First-run unknowns.** The suites have never run in CI; several may fail
  against current dev schema/cruft on first dispatch. That is discovery, not a
  plan defect — the dispatch AC exists to surface it, and per-suite fixes go to
  follow-up issues rather than weakening gates to force green.
- **Gate-idiom scope.** The sentinel covers the `===|!== "1"` idiom only; a gate
  written as `!!process.env.X` or `X == "yes"` escapes it (documented scope
  boundary, same posture as lint-orphan-test-suites' suffix keying).
- **No progress-key / skeleton contract.** Do not add `## Acceptance Criteria`
  placeholders elsewhere; completion is asserted on content.
- **Empty-section trap.** A `## User-Brand Impact` or `## Observability` section
  left with placeholder text fails deepen-plan; both are filled above.
- **Branch dispatch arm.** `workflow_dispatch` from a feature branch applies
  only migrations on `origin/main` (unmerged-apply gate stays armed); the
  tenant-integration leg remains the apply path for in-flight migrations.
- **No live dev-Supabase writes in-session.** The implementing agent does not
  run the gated suites locally; pre-merge verification is static (YAML lint,
  shellcheck, sentinel battery, `git grep` census). Live verification is the
  post-merge dispatch AC.

## Context

- Issue: #9855 (this plan closes it — PR 2 of 2; the "Input to #9771" machinery
  critiques are explicitly routed to #9771, not part of this issue's work items)
- PR 1: #9890 (merged 2026-10-09) — marker backfill + demotions
- Draft PR for this branch: #9947
- Substrate ADRs: ADR-023 (dev/prd project split, 2-project Free quota),
  ADR-061 (shared-dev per-ref gates; ephemeral-DB rejected), #8028 DC-1,
  #5585 (rate-budget + required-check shim), #7986/#8048 (concurrency-key sizing)
- Stale sibling worktree `.worktrees/feat-9855-test-pyramid-cleanup` holds
  unrelated uncommitted salvage — out of scope; no file overlap with this plan.

## References

- `apps/web-platform/test/README.md` — env-flag conventions + dedicated-project guidance
- `knowledge-base/engineering/architecture/decisions/ADR-023-supabase-environment-isolation.md`
- `knowledge-base/engineering/architecture/decisions/ADR-061-per-ref-behavioural-schema-gate-over-shared-dev.md`
- `.github/workflows/tenant-integration.yml`, `scheduled-realtime-probe.yml`, `rls-authz-fuzz.yml`
- `scripts/lint-orphan-test-suites.sh` — sentinel precedent
