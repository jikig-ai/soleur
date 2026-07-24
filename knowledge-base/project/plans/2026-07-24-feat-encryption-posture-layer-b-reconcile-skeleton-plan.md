---
title: "feat(encryption-posture): Layer B live-reconcile — disarmed measure-then-arm skeleton"
date: 2026-07-24
issue: 6902
type: feat
lane: cross-domain
brand_survival_threshold: aggregate pattern
adr: ADR-141 (provisional ordinal — re-verify next-free against origin/main at ship)
status: draft
---

# feat(encryption-posture): Layer B live-reconcile — disarmed measure-then-arm skeleton (#6902)

## Enhancement Summary

**Deepened on:** 2026-07-24
**Research agents used:** architecture-strategist (scope-verdict pressure-test), spec-flow-analyzer
(reconcile-arm completeness), code-simplicity-reviewer (YAGNI), Explore/sonnet (verify-the-negative
grep pass).

### Key Improvements (from the architecture-strategist deepen pass, applied)

1. **Set-equality reconcile, not a bare count** — a `count >= N` gate false-greens when the one
   available row flips `available → unavailable` (1→0, still below threshold, still green). Gate now
   compares the declared-available SET to a pinned baseline; a member leaving is drift → non-green.
2. **Ride the existing `scheduled-terraform-drift.yml` as a job** — rejected the issue's prescribed
   new `cron-encryption-posture-reconcile.ts` + new workflow (ADR-033 single-substrate violation;
   `heartbeat-live-reconcile` is the precedent). The #1 anti-rework change.
3. **Deferred the dedicated Sentry cron-monitor** — the parity guard is workflow-step-granular, and a
   `failure_issue_threshold=1` monitor on a disarmed near-no-op is a false-MISSED-page generator.
   Failures surface via ops-email instead; the dedicated monitor lands with the armed reconcile.

### New Considerations Discovered

- The issue's `--report --json` collapses to `--json` (the `--json` short-circuit ignores `--report`).
- The one `available` row is host-probe-backed (luks-monitor.sh), NOT runner-reconcilable — so even
  the 1 measurable volume gives the runner no independent signal; the honest positive work is guarding
  the ledger's coverage CLAIM from regression, not re-probing the volume.
- #6896 (provider attestation) is CLOSED yet those rows correctly stay `unavailable` forever — the arm
  threshold must be phrased over *runner-reconcilable* rows, never "all available."

## Overview

Issue #6902 asks for **Layer B**: live reconciliation of `scripts/encryption-posture-ledger.json`
against actual provider/host state, as the runtime companion to the merged **Layer A** design-time
mechanical check (#6885 / ADR-140). The issue itself flags a load-bearing caveat: Layer B
substantially **overlaps two existing detectors** and can measure only **1 of 6** guest-LUKS volumes.

This plan ran the **measure-then-scope** mandate before committing to a design. The measurement is
decisive and is documented in the Coverage Measurement section below. The honest verdict:

> **Building the full *armed* Layer B reconcile now is BOTH premature AND duplicative.** Scope this
> increment to a **disarmed measure-then-arm skeleton** (mirroring the #6901 measure-then-arm DEFER
> pattern merged 2026-07-24) that measures coverage, cannot cry-wolf, and **arms nothing** until the
> prerequisite per-volume emitters (#6894 / #6895 / #6897) land. **DEFER** the armed per-row live
> reconcile to a Layer B tracking issue gated on those emitters.

The skeleton is not zero: it establishes the count-gate substrate, the single-parser shell-out
contract, the Sentry cron-monitor liveness plane, and the coverage ledger — so that when the
emitters land, arming Layer B is a one-line threshold flip, not a from-scratch build.

## Coverage Measurement (the load-bearing MEASURE step)

Measured against `scripts/encryption-posture-ledger.json` at HEAD (2026-07-24):

| live_verification | count | stores |
| --- | --- | --- |
| `available` | **1** | `hcloud_volume.workspaces_luks` |
| `unavailable:*` | **13** | the other 13 stores |
| **total** | **14** | |

The 6 `hcloud_volume` (guest-LUKS) stores specifically — confirming the issue's "1 of 6":

| volume | mechanism | live_verification | prerequisite |
| --- | --- | --- | --- |
| `hcloud_volume.workspaces_luks` | luks | **available** | — (covered by luks-monitor.sh) |
| `hcloud_volume.git_data_luks` | luks | unavailable | #6897 |
| `hcloud_volume.workspaces` (plain) | plaintext-exception | unavailable | #6897 |
| `hcloud_volume.git_data` (plain) | plaintext-exception | unavailable | #6897 |
| `hcloud_volume.inngest_redis` | plaintext-exception | unavailable | #6894 |
| `hcloud_volume.registry` | plaintext-exception | unavailable | #6895 |

**Why only 1 is measurable, and why even that 1 is not *runner*-reconcilable:**

- The Hetzner API is **blind to guest-side LUKS** (it sees a block volume, not whether the guest
  opened a `crypto_LUKS` mapper over it), and **SSH to the hosts is forbidden**. So a CI-runner
  reconcile has no independent live signal for guest-LUKS state.
- `workspaces_luks` is `available` **because a HOST probe exists** —
  `apps/web-platform/infra/luks-monitor.sh`, the daily at-rest probe that verifies mount→mapper,
  `cryptsetup status`, `blkid` = `crypto_LUKS`, the Doppler escrow re-test, and the header UUID, then
  pushes a Better Stack heartbeat and emits a discriminating Sentry event on drift. **The
  runner cannot reproduce that signal** — it can only observe the host probe's own liveness
  (heartbeat/Sentry), which the existing `scheduled-terraform-drift.yml` heartbeat-live-reconcile job
  already covers.
- Provider-managed stores (R2, Supabase, Doppler, Better Stack) are **structurally never**
  runner-live-reconcilable — you cannot probe Cloudflare's disk encryption from CI. #6896 (their
  attestation formalization) is CLOSED, yet those rows correctly stay `unavailable` forever.

**Overlap with the two existing detectors (characterized from source):**

1. `apps/web-platform/infra/luks-monitor.sh` — the DAILY host probe **already deeply verifies the one
   measurable volume** (workspaces_luks). A Layer B reconcile of that volume duplicates it and adds no
   independent signal.
2. `.github/workflows/scheduled-terraform-drift.yml` — already `on: workflow_dispatch:`-only,
   Inngest-dispatched (ADR-033) via `cron-terraform-drift.ts`, checks in to a Sentry cron-monitor,
   AND already carries a `heartbeat-live-reconcile` job (live-state read → manifest reconcile →
   find-or-update-by-title issue). It also runs `terraform plan` drift detection on
   `apps/web-platform/infra`, which already catches new/changed volumes (store-inventory drift).

**Net:** the only measurable volume is already covered; store-inventory drift is already covered; the
substrate the issue prescribes already exists. There is **no non-duplicative, non-cry-wolf slice of
per-row live reconciliation the runner can perform today.**

## Research Reconciliation — Spec (issue #6902) vs. Codebase

| Issue claim / prescription | Reality (verified) | Plan response |
| --- | --- | --- |
| "shells out to `python3 scripts/lint-encryption-posture.py --report --json`" | `--json` **short-circuits and ignores `--report`** (`main()`: the `if args.json:` block returns before `run_sweep(..., report=...)`). `--json` is the documented "single-parser contract Layer B shells out to" (docstring line 28). `--json` mode **already exists** — not part of scope to add. | Skeleton shells out to **`--json` alone**. Drop `--report` (inert). |
| "a `cron-encryption-posture-reconcile.ts` owns the schedule and workflow_dispatch-es an `on: workflow_dispatch:`-only workflow" | `scheduled-terraform-drift.yml` already provides this exact shape and already carries a live-reconcile job (`heartbeat-live-reconcile`) riding the existing `cron-terraform-drift.ts` dispatch with "no new schedule/Inngest function". | **Ride the existing workflow as a new job** (mirror heartbeat-live-reconcile). **No new Inngest fn, no new workflow** — more aligned with ADR-033 single-substrate + YAGNI. (Surfaced to architecture-strategist; see Domain Review.) |
| "can only measure 1 of 6 volumes (workspaces_luks)" | **Confirmed exactly.** 1 of 6 volumes; 1 of 14 total stores. | Verdict rests on this. |
| "positive-work floor counts only `live_verification:available` rows" | Correct and load-bearing: counting only available rows means the floor **cannot cry-wolf** about the 13 it structurally cannot see. | Adopted verbatim as the count-gate input. |
| "ADR-117 measure-then-arm count-gate" | ADR-117 (`ADR-117-executable-heartbeat-arming.md`) exists; #6901 (CLOSED) applied the same measure-then-arm pattern to Layer A. | Adopted: skeleton is DISARMED below an arm threshold. |
| "Sentry cron-monitor plane (NOT Better Stack) so `sentry-monitor-iac-parity.test.ts` covers it" | `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` is a one-way (code→IaC) guard; it legitimately tolerates GHA-fired monitors (scheduled-terraform-drift) with no Inngest slug. `sentry/cron-monitors.tf` is auto-applied by `apply-sentry-infra.yml`. | Skeleton checks in to a **Sentry cron-monitor** from the GHA job (liveness of the gate itself, independent of arm state). |
| "Deferred from merged audit #6885 — do not re-do it" | #6885 MERGED. | No audit work re-done. |

## Scope Decision

**In scope (the disarmed skeleton):**

1. **ADR-141** recording the measure-then-scope verdict (see Architecture Decision section).
2. A **reconcile probe** (`plugins/soleur/scripts/reconcile-encryption-posture.ts`, mirroring
   `reconcile-live-heartbeats.ts`) that shells out to `python3 scripts/lint-encryption-posture.py
   --json` and performs a **coverage-claim SET-EQUALITY reconcile** (architecture-strategist's
   load-bearing correction — a bare count false-greens, see Sharp Edges). It computes
   `ACTUAL_AVAILABLE` = the set of store addresses whose `at_rest.live_verification == "available"`,
   and compares it to a **pinned committed baseline** `EXPECTED_AVAILABLE = {"hcloud_volume.workspaces_luks"}`:
   - **equal** → `SOLEUR_ENCRYPTION_POSTURE_RECONCILE_DISARMED measured=<N> baseline=<M>` + **exit 0**
     (green; the disarmed steady state).
   - **shrank** (a row LEFT the available set — the coverage-claim regression the runner CAN see, and
     the one thing nothing else guards) → `...RECONCILE_REGRESSION removed=<addrs>` + `::error::` +
     **exit non-zero** (pages via the workflow's ops-email path).
   - **grew** (an emitter landed → a new row became `available`) → `...RECONCILE_ARM_READY added=<addrs>`
     + **exit 0** (good news, not a page; surfaced in the log + the deferred Layer B tracking issue).
   - **incomparable overlap** (the set BOTH adds AND removes members vs baseline — a member left *and*
     a new one appeared) → route to **REGRESSION** (a baseline member leaving is drift regardless of
     what else appeared; never let a simultaneous add mask a removal into `ARM_READY`).
   The four arms are exhaustive over set-comparison (equal / strict-subset / strict-superset /
   incomparable), and the reconcile normalizes any abnormal exit (crash/OOM 137 / SIGSEGV 139 /
   timeout 124 from the `lint-encryption-posture.py --json` shell-out) to the **error path** — a crash
   must never exit 0 before the verdict line (mirror `reconcile-live-heartbeats.ts` rc-normalization).
   The workflow asserts the mandatory verdict line is **PRESENT** (positive control), so a silently
   skipped reconcile fails rather than reads green.
   This is genuine, non-duplicative positive work — it guards the ledger's `live_verification` field
   against silent regression — while structurally **cannot cry-wolf** about the 13 `unavailable` rows
   (they are never in either set). It files **no** issues in the disarmed path.
3. A new **job in `scheduled-terraform-drift.yml`** (`encryption-posture-reconcile`) riding the
   existing Inngest dispatch (mirror `heartbeat-live-reconcile`: **no new Inngest fn, no new
   schedule, no new workflow** — the #1 anti-rework / ADR-033 single-substrate correction). Hard
   failures (regression, schema-invalid, abnormal crash) surface via `::error::` + an
   `./.github/actions/notify-ops-email` step (the same non-SSH alert path the drift job already uses)
   + a failed job.
4. Tests: the reconcile script's set-equality reconcile (equal/shrank/grew arms) driven by
   **synthesized** ledger fixtures (`cq-test-fixtures-synthesized-only`); the disarmed-exit-0 and
   regression-exit-non-zero behavior; the `--json` (not `--report --json`) shell-out contract.

**Explicitly DEFERRED from the skeleton (architecture-strategist corrections — flagged as
User-Challenges to the issue's literal prescription in `decision-challenges.md`):**

- **The dedicated `sentry_cron_monitor` + `cron-monitors.tf` edit + `sentry-monitor-iac-parity.test.ts`
  coverage.** The issue prescribed "Sentry cron-monitor plane so `sentry-monitor-iac-parity.test.ts`
  covers it," but the parity guard is **workflow-step-granular** (it requires a `sentry_cron_monitor`
  only for a workflow carrying a `monitor-slug:` heartbeat step) — a job riding the existing workflow
  triggers no parity requirement. A NEW dedicated `failure_issue_threshold=1` cron-monitor on a
  twice-daily near-no-op is a **false-MISSED-page generator** (the parity test's own comment warns a
  crontab monitor "pages MISSED forever"). The dedicated monitor lands **with the armed reconcile**,
  when there is a real drift-SLO to protect. This increment's failures are still observable (ops-email
  + failed job). **Operator may override** (see `decision-challenges.md`).
- **The new `cron-encryption-posture-reconcile.ts` Inngest fn + new `workflow_dispatch` workflow.**
  Superseded by the ride-existing-job decision above (ADR-033 single-substrate).

**Deferred (the armed reconcile) — DEFER to a new Layer B tracking issue, gated on emitters:**

- Per-row live reconciliation that cross-checks each `available` row against an independent live
  signal and files find-or-update-by-title mismatch issues. This is unbuildable non-duplicatively
  until per-volume host posture emitters exist for the other volumes:
  - **#6894** — inngest_redis emitter (OPEN)
  - **#6895** — registry emitter (OPEN)
  - **#6897** — git-data / session-store / plaintext-volume host posture (OPEN)
  - Provider-managed rows remain structurally out of runner reach (documented in the ADR).
- The arm flip is a threshold change in the reconcile script once ≥ a defensible count of
  runner-reconcilable-AND-non-duplicative rows exist.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly — Layer B is a
detective control on encryption posture, disarmed in this increment. A broken skeleton is no worse
than the status quo: `luks-monitor.sh` still covers the one live volume, and Layer A still gates the
ledger at design time. The realistic failure is an *internal* false-green (the gate silently never
runs) — mitigated by the Sentry cron-monitor liveness check-in and the mandatory disarmed-marker
verdict line.

**If this leaks, the user's data is exposed via:** N/A — the reconcile is read-only, reads the
committed ledger + `lint-encryption-posture.py --json` (hermetic, no network, no secrets), and emits
only integer counts + store addresses (no user data crosses any boundary).

**Brand-survival threshold:** `aggregate pattern` — a dark encryption-posture reconcile does not
itself cause a single-user incident; it is a second-order detective control whose absence is an
aggregate-risk regression, not a per-user breach. (The thing it eventually monitors — at-rest
encryption of sole-copy user volumes — is single-user-incident class, but this disarmed skeleton
neither performs nor gates that protection.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `reconcile-encryption-posture.ts` shells out to `python3 scripts/lint-encryption-posture.py --json` (NOT `--report --json`) and parses the emitted ledger. Assert the shell-out command literal contains `--json` and does NOT contain `--report`.
- [ ] **AC2** The reconcile derives `ACTUAL_AVAILABLE` = the SET of store addresses whose `at_rest.live_verification == "available"`. On a synthesized fixture with 1 available + 13 unavailable rows, `ACTUAL_AVAILABLE == {"hcloud_volume.workspaces_luks"}` (fixture synthesized, not a copy of the live ledger — `cq-test-fixtures-synthesized-only`).
- [ ] **AC3** Set-equality reconcile — **equal** arm: `ACTUAL_AVAILABLE == EXPECTED_AVAILABLE` → emits `SOLEUR_ENCRYPTION_POSTURE_RECONCILE_DISARMED measured=<N> baseline=<M>` and **exits 0**; files no issue, calls no GitHub API (assert no `gh`/network in this path).
- [ ] **AC4** Set-equality reconcile — **shrank** arm (regression): a fixture whose available set is missing a baseline member → emits `...RECONCILE_REGRESSION removed=<addr>`, an `::error::` annotation, and **exits non-zero**. (This is the false-green the bare-count design would swallow.)
- [ ] **AC5** Set-equality reconcile — **grew** arm (arm-ready): a fixture whose available set is a strict superset of the baseline → emits `...RECONCILE_ARM_READY added=<addr>` and **exits 0** (good news, not a page).
- [ ] **AC6** Structurally-cannot-cry-wolf: a fixture with 13 `unavailable` rows and the 1 baseline `available` row reconciles as **equal** (green) — the 13 unavailable rows are in neither set and never affect the verdict.
- [ ] **AC6b** Incomparable-overlap arm: a fixture whose available set both **removes** a baseline member AND **adds** a new one routes to **REGRESSION** (exit non-zero), NOT `ARM_READY` — a removal is never masked by a simultaneous add.
- [ ] **AC6c** Crash-safety: a stubbed `lint-encryption-posture.py --json` that exits abnormally (non-0/1/2 — e.g. 137) drives the reconcile to the **error path** (non-zero exit), never a silent green before the verdict line. And the workflow step asserts the verdict marker line is PRESENT (positive control).
- [ ] **AC7** The `encryption-posture-reconcile` job exists in `.github/workflows/scheduled-terraform-drift.yml`, has **no** `schedule:`/`on:` of its own (rides the workflow's existing `workflow_dispatch` Inngest dispatch), adds **no** `monitor-slug:` heartbeat step (dedicated Sentry monitor deferred), and routes a hard failure through an `./.github/actions/notify-ops-email` step (mirroring the drift job).
- [ ] **AC8** `sentry-monitor-iac-parity.test.ts` still PASSES with **no** new monitor added (the new job adds no `monitor-slug:` step, so the guard requires nothing new — assert green, no edit needed).
- [ ] **AC9** ADR-141 exists at `knowledge-base/engineering/architecture/decisions/ADR-141-*.md` (ordinal re-verified against `origin/main` at ship per the ADR-Ordinal Collision Gate), status `adopting`, recording: the DISARMED verdict, the host-probe-vs-runner-reconcile distinction, the ride-existing-workflow (ADR-033) decision + its cadence-coupling acceptance, the set-equality gate design, and the arm sequencing behind #6894/#6895/#6897. Any AC/plan reference to the ordinal is swept if it renumbers.
- [ ] **AC10** `python3 scripts/lint-encryption-posture.py --repo-sweep` still PASSES (this PR adds NO `.tf` store/resource — assert Layer A is unaffected).
- [ ] **AC11** Typecheck (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`) + the repo test runner green for all new/edited test files (paths satisfy the runner's discovery globs — verify the glob at /work).

### Deferred (tracking issue, not this PR)

- [ ] The armed per-row live reconcile + find-or-update-by-title mismatch filing + the dedicated `sentry_cron_monitor` + `sentry-monitor-iac-parity.test.ts` coverage — all tracked in the new Layer B tracking issue, gated on #6894 / #6895 / #6897.

## Observability

```yaml
liveness_signal:
  what: "encryption-posture-reconcile job verdict line (the mandatory DISARMED/REGRESSION/ARM_READY marker)"
  cadence: "twice-daily (rides scheduled-terraform-drift.yml's existing Inngest dispatch, 06:00/18:00 UTC)"
  alert_target: "ops-email (./.github/actions/notify-ops-email) on a hard failure + the failed GHA job; the workflow-level scheduled-terraform-drift Sentry monitor already pages if the whole workflow stops dispatching. Dedicated encryption-posture Sentry cron-monitor DEFERRED with the armed reconcile (see decision-challenges.md)."
  configured_in: "the encryption-posture-reconcile job in .github/workflows/scheduled-terraform-drift.yml"
error_reporting:
  destination: "::error:: annotation + notify-ops-email step on rc != 0 (regression / schema-invalid / abnormal crash)"
  fail_loud: "an abnormal rc (crash/OOM/timeout) is normalized to the error path (mirror heartbeat-live-reconcile's rc-normalization), never silently green"
failure_modes:
  - mode: "reconcile script crashes / lint-encryption-posture.py --json fails schema-validation"
    detection: "non-zero rc normalized to the error path"
    alert_route: "::error:: + ops email + failed job"
  - mode: "coverage-claim regression (a baseline row leaves the available set — the false-green class)"
    detection: "RECONCILE_REGRESSION marker + non-zero exit"
    alert_route: "::error:: + ops email"
  - mode: "the job silently never runs (workflow stops dispatching — the dark-gate class)"
    detection: "the workflow-level scheduled-terraform-drift Sentry cron-monitor missed-check-in"
    alert_route: "Sentry cron-monitor issue (existing, workflow-level)"
logs:
  where: "GitHub Actions run log (job output) + the SOLEUR_ENCRYPTION_POSTURE_RECONCILE_* markers"
  retention: "GHA default (90 days)"
discoverability_test:
  command: "gh workflow run scheduled-terraform-drift.yml   # then read the encryption-posture-reconcile job log for the verdict marker"
  expected_output: "SOLEUR_ENCRYPTION_POSTURE_RECONCILE_DISARMED measured=1 baseline=1"
```

## Encryption Posture

**No new persistent store, no new cross-component connection, and — after the architecture-strategist
correction — no `.tf`/`.sql`/cloud-init/compose change at all** (the dedicated `sentry_cron_monitor`
is deferred with the armed reconcile). The Phase 2.11 detection set does not fire. The reconcile job
is read-only: it reads the committed ledger + `lint-encryption-posture.py --json` hermetically (no
network, no secrets, no writes) and emits only integer counts + store addresses. The encryption
posture of the stores this feature *observes* is unchanged and already ledgered.

## Infrastructure (IaC)

**No IaC in this increment.** The plan now introduces no server, service, cron resource, secret, DNS
record, cert, or firewall rule. The reconcile is a **job added to an already-provisioned workflow**
(`scheduled-terraform-drift.yml`) riding its existing Inngest dispatch — no new schedule, no new
Inngest fn, no `.tf`. The Phase 2.8 IaC-routing gate does not fire.

The dedicated `sentry_cron_monitor` (which WOULD be IaC in `apps/web-platform/infra/sentry/
cron-monitors.tf`, auto-applied by `apply-sentry-infra.yml`) is **deferred to the armed reconcile**
per the architecture-strategist verdict (a paging monitor on a near-no-op disarmed probe is a
false-MISSED-page generator). It will carry its own `## Infrastructure (IaC)` section when armed.

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-141** (provisional ordinal — re-verify next-free against `origin/main` at ship; last on
  main is ADR-140): *"Layer B encryption-posture reconcile is disarmed until per-volume host emitters
  make coverage runner-reconcilable."* `## Decision`: ship the measure-then-arm skeleton disarmed as a
  **coverage-claim set-equality reconcile** (not a bare count) riding the **existing
  scheduled-terraform-drift.yml as a job** (no new Inngest fn / schedule / workflow — ADR-033
  single-substrate); arm only when the set of runner-reconcilable-AND-non-duplicative
  `live_verification:available` rows grows past the pinned baseline. `## Alternatives Considered`:
  (a) full armed reconcile now — rejected as premature (1/14) + duplicative (luks-monitor.sh +
  terraform-drift already cover the measurable surface); (b) reconcile only workspaces_luks — rejected
  because the runner has no independent live signal for it (host-probe-backed); (c) a new
  `cron-encryption-posture-reconcile.ts` + new `workflow_dispatch` workflow (the issue's prescription)
  — rejected as an ADR-033-violating second substrate when `heartbeat-live-reconcile` proves the
  job-in-existing-workflow shape; (d) a dedicated Sentry cron-monitor for the disarmed probe —
  deferred (false-MISSED-page generator on a near-no-op; the parity guard is workflow-step-granular so
  it is not required). `## Context` records: the **host-probe-vs-runner-reconcile distinction** (the
  load-bearing conceptual boundary — mirrors ADR-123 "self-report, no self-converge" and ADR-126
  "cron liveness must assert the consumed artifact"), the **cadence-coupling** to terraform-drift
  (accepted, not accidental), the **set-equality gate** (a bare count false-greens on a shrink), and
  the emitter sequencing (#6894/#6895/#6897; provider-managed rows structurally out of runner reach
  forever). `status: adopting` (the armed state is true only after the emitters land). Written via
  `/soleur:architecture`. Extends ADR-140 (Layer A) and ADR-117 (measure-then-arm); ADR-033 lineage
  for the substrate decision.

### C4 views — no C4 impact (enumeration cited)

Enumeration against all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`), per the C4
completeness mandate (checked against external actors / systems / stores / access-relationships, not
a bare feature-noun grep):

- **External human actors:** none new (no correspondent/reviewer/recipient — an internal CI job).
- **External systems:** Sentry (modeled `model.c4:294` + `github -> sentry` edge `:511`) and GitHub
  CI (`model.c4:232`) — **both already modeled**. No new system.
- **Containers / data stores:** the ledger is a committed repo file, not a C4 container; the volumes
  it observes are already modeled (`model.c4:182-220`, with their encryption-posture exceptions). No
  new store.
- **Access relationships:** none change. Because the dedicated Sentry monitor is **deferred**, the
  `github -> sentry` edge's monitor counts (`:511`, "50 cron monitors, 7 check in from here") are
  **not** falsified this increment — no new monitor is added. (When the armed reconcile lands its
  dedicated monitor, THAT plan updates the count.)

**Conclusion: no `.c4` edit in this increment.** No new element, no new edge, no `views.c4` include
change, no falsified description.

### Sequencing

The ADR is authored now describing the target (armed) state with `status: adopting`; the arm flip is
deferred to the tracking issue. Not postponed to its own ADR.

## Domain Review

**Domains relevant:** Engineering (infra/observability) — assessed via architecture-strategist
(pressure-testing the DEFER verdict; see Session note). No Product/UX surface (no file under
`components/**`, `app/**/page.tsx`, or any UI-surface glob) → Product Gate = **NONE**. No
Finance/Legal/Sales/Marketing/Support implications (an internal CI detective-control skeleton).

### Engineering (infra/observability)

**Status:** reviewed (architecture-strategist pressure-test of the scope verdict; folded into Scope
Decision + Sharp Edges).
**Assessment:** the DEFER verdict, the ride-existing-workflow vs new-Inngest-fn choice, and the
disarmed-monitor-now vs defer-monitor question are the material trade-offs; deepen-plan carries the
final refinement.

## Sharp Edges

- **The `## User-Brand Impact` section must stay filled** — a plan whose section is empty/`TBD`/
  missing-threshold fails `deepen-plan` Phase 4.6.
- **`--json` ignores `--report`.** Do not restore `--report` in the shell-out "to be safe" — it is
  inert and its presence would falsely imply the parity table is consumed. `--json` is the sole Layer
  B contract.
- **Set-equality, NOT a bare `count >= N` threshold (architecture-strategist load-bearing edge).**
  A `count >= N` gate false-greens on the exact regression it should catch: if `workspaces_luks` —
  the one measurable row — silently flips `available → unavailable`, the count drops 1→0, which is
  *still below the arm threshold*, *still exit 0, still green*, rendering the disappearance of the
  only live signal invisible. Anchor the gate to the ledger's declared-available **SET** vs a pinned
  committed baseline: a row LEAVING the set is drift → non-green even while total stays "below
  arming." Encode the "available-only" set selection as a named predicate with a test that a
  13-unavailable/1-available fixture reconciles as equal (green) and a fixture missing the baseline
  member exits non-zero.
- **Disarmed ≠ dead, and disarmed rots silently.** A disarmed probe emitting "measured, below
  threshold, exit 0" will decay into "permanently forgotten." Bind it to the Layer B tracking issue
  and record the arming trigger (#6894/#6895/#6897 landing → the `grew` arm fires `ARM_READY` → flip
  to equality-against-the-grown-set) in ADR-141 so "disarmed" is a decision with an owner, not a
  no-op that rots. The `grew` arm is the built-in reminder: when an emitter lands, the reconcile
  itself announces `ARM_READY`.
- **The arm threshold must be phrased over *runner-reconcilable* rows, never "all available."**
  Provider-managed rows (R2/Supabase/Doppler/Better Stack) are structurally `unavailable` forever
  (#6896 CLOSED and they still, correctly, read `unavailable`), so an "arm when all rows are
  available" condition would never fire. Phrase the arm over the specific host-emitter-backed rows the
  emitters unblock.
- **Do not smuggle a design-time check into Layer B.** Ledger-store-inventory vs Terraform-declared
  inventory is runner-doable but is a **Layer A** (design-time mechanical) concern — if that gap is
  uncovered, file it against Layer A (#6885 / lint-encryption-posture.py), do not put it in the
  "live" Layer B reconcile (layering violation, per architecture-strategist).
- **Provider-managed rows never become runner-reconcilable** — do not let a future "arm when all rows
  are available" threshold be written, because those rows are structurally `unavailable` forever
  (#6896 closed and they still, correctly, read `unavailable`). The arm threshold must be phrased over
  *runner-reconcilable* rows, not *available* rows, or it will never fire.
- **ADR ordinal is provisional.** A sibling PR can claim ADR-141; re-verify next-free against
  `origin/main` at ship and sweep the plan/tasks/AC if renumbered.

## Deferral Tracking

- **File a Layer B tracking issue** (milestone from `roadmap.md`) for the deferred armed reconcile:
  what (per-row live reconcile + mismatch filing), why deferred (1/14 measurable; overlap), re-eval
  criteria (arm when runner-reconcilable coverage crosses the threshold), blockers (#6894/#6895/#6897).
- The prerequisite emitters already have tracking issues (#6894/#6895/#6897 OPEN) — the Layer B
  tracking issue references them as blockers; no new emitter issues are filed by this plan.

## Files to Create

- `plugins/soleur/scripts/reconcile-encryption-posture.ts` — the disarmed reconcile probe (mirrors
  `reconcile-live-heartbeats.ts`).
- `knowledge-base/engineering/architecture/decisions/ADR-141-*.md` — via `/soleur:architecture`.
- Test file(s) for the reconcile count-gate / floor / disarmed-exit (path chosen to satisfy the
  repo test runner's discovery globs — verify against the runner config at /work).

## Files to Edit

- `.github/workflows/scheduled-terraform-drift.yml` — add the `encryption-posture-reconcile` job
  (rides the existing dispatch; `::error::` + `notify-ops-email` on hard failure; no `monitor-slug:`).

**Deliberately NOT edited this increment (deferred with the armed reconcile):**
`apps/web-platform/infra/sentry/cron-monitors.tf`, `sentry-monitor-iac-parity.test.ts` (asserted
green unchanged), and `model.c4` (no monitor added → no count change). See the DEFERRED subsection
and `decision-challenges.md`.

## Open Code-Review Overlap

None (no open `code-review`-labelled issues were found touching these files during planning; re-run
the overlap query at /work if the backlog changed).

## Decision Challenges (headless — for `ship` to render + file as `action-required`)

Two architecture-strategist findings changed the issue's *stated* prescription; recorded to
`knowledge-base/project/specs/feat-one-shot-6902-encryption-posture-layer-b-reconcile/decision-challenges.md`
for operator visibility (the operator may override):

1. **Sentry cron-monitor deferred** — the issue said "use the Sentry cron-monitor plane so
   `sentry-monitor-iac-parity.test.ts` covers it"; the plan defers the dedicated monitor to the armed
   reconcile (false-MISSED-page risk on a disarmed probe; the parity guard is workflow-step-granular
   so nothing is required). Failures still surface via ops-email + failed job.
2. **No new Inngest fn / workflow** — the issue said build `cron-encryption-posture-reconcile.ts` +
   a new `workflow_dispatch` workflow; the plan rides the existing `scheduled-terraform-drift.yml` as
   a job (ADR-033 single-substrate; `heartbeat-live-reconcile` precedent).
