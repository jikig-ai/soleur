---
title: "feat(encryption-posture): Layer B live-reconcile — measure-then-scope DEFER + Layer A coverage floor"
date: 2026-07-24
issue: 6902
type: feat
lane: cross-domain
brand_survival_threshold: aggregate pattern
adr: ADR-141 (provisional ordinal — re-verify next-free against origin/main at ship)
status: draft
---

# feat(encryption-posture): Layer B live-reconcile — measure-then-scope DEFER (#6902)

## Enhancement Summary

**Deepened on:** 2026-07-24
**Research agents used:** architecture-strategist (scope-verdict pressure-test), spec-flow-analyzer
(reconcile-arm completeness), code-simplicity-reviewer/YAGNI (the load-bearing correction below),
Explore/sonnet (verify-the-negative grep pass — all 7 factual premises CONFIRMED).

### The load-bearing deepen finding (YAGNI, corroborated by verify-the-negative)

`lint-encryption-posture.py --json` emits the **committed ledger verbatim** and is **hermetic** (no
network, no host, no SSH — `scripts/lint-encryption-posture.py:54, 1006-1012`, confirmed). So the
ledger's `live_verification` field is a **static committed string, not a measured live signal**. Any
runner-side "reconcile" of it against a pinned constant compares **two static committed files** —
which can only change via a reviewed PR that already passes Layer A CI. A twice-daily cron re-reading
two static files emits the identical verdict every run and adds **zero** detection value over a single
PR-time assertion (worse: a bad commit is caught hours later by email instead of blocked at PR time).
This is the plan's own Sharp Edge — *"do not smuggle a design-time check into Layer B; that is a
layering violation"* — and it means **there is no non-duplicative live work a Layer B cron can do
today.**

### Verdict (all three deepen agents converge)

> **Layer B live reconcile is DEFERRED almost entirely** (the #6901 measure-then-arm DEFER pattern).
> The runner has **no live signal** for any store today: the one measurable volume is host-probe-backed
> (luks-monitor.sh), not runner-reconcilable, and `--json` is a static-file read. Ship the **ADR** (the
> durable deliverable), a **small correctly-layered Layer A coverage floor** (PR-time, no cron), and a
> **Layer B tracking issue** gated on the per-volume emitters. Build the actual live reconcile only
> when an emitter gives the runner a real signal.

This supersedes the earlier draft's "disarmed cron skeleton" — the skeleton's only positive work was a
static-file invariant, which is Layer A, not a Layer B cron.

## Overview

Issue #6902 asks for **Layer B**: live reconciliation of `scripts/encryption-posture-ledger.json`
against actual provider/host state, the runtime companion to the merged **Layer A** design-time check
(#6885 / ADR-140). The measure-then-scope mandate required verifying measurable coverage **before**
committing to a design. The measurement (below) plus the runner-reconcilability analysis show a full
Layer B reconcile is premature, duplicative, and — for the one measurable row — impossible from a CI
runner. The honest, defensible increment is the DEFER above.

## Coverage Measurement (the load-bearing MEASURE step)

Measured against `scripts/encryption-posture-ledger.json` at HEAD (2026-07-24):

| live_verification | count | stores |
| --- | --- | --- |
| `available` | **1** | `hcloud_volume.workspaces_luks` |
| `unavailable:*` | **13** | the other 13 stores |
| **total** | **14** | |

The 6 `hcloud_volume` (guest-LUKS) stores — confirming the issue's "1 of 6":

| volume | mechanism | live_verification | prerequisite |
| --- | --- | --- | --- |
| `hcloud_volume.workspaces_luks` | luks | **available** | — (covered by luks-monitor.sh) |
| `hcloud_volume.git_data_luks` | luks | unavailable | #6897 |
| `hcloud_volume.workspaces` (plain) | plaintext-exception | unavailable | #6897 |
| `hcloud_volume.git_data` (plain) | plaintext-exception | unavailable | #6897 |
| `hcloud_volume.inngest_redis` | plaintext-exception | unavailable | #6894 |
| `hcloud_volume.registry` | plaintext-exception | unavailable | #6895 |

**Why there is no runner-side live signal today:**

- The Hetzner API is **blind to guest-side LUKS**; **SSH to the hosts is forbidden**. A CI-runner
  reconcile has no independent signal for guest-LUKS state.
- `workspaces_luks` is `available` **because a HOST probe exists** (`luks-monitor.sh`, daily). The
  runner cannot reproduce that signal — it can only observe the probe's own liveness (Better Stack
  heartbeat / Sentry), which `scheduled-terraform-drift.yml`'s existing `heartbeat-live-reconcile` job
  already covers.
- Provider-managed stores (R2/Supabase/Doppler/Better Stack) are **structurally never**
  runner-live-reconcilable. #6896 (their attestation formalization) is CLOSED, yet those rows correctly
  stay `unavailable` forever — so any arm threshold must be phrased over *runner-reconcilable* rows,
  never "all available."
- `lint-encryption-posture.py --json` emits the **committed ledger** (hermetic) — reading it is a
  design-time operation, not a live measurement.

**Overlap with the two existing detectors (characterized from source):**

1. `apps/web-platform/infra/luks-monitor.sh` — the DAILY host probe already deeply verifies the one
   measurable volume (mount→mapper, `cryptsetup status`, `blkid` crypto_LUKS, Doppler escrow re-test,
   header UUID; Better Stack heartbeat + discriminating Sentry event on drift). A Layer B reconcile of
   that volume duplicates it and adds no independent signal.
2. `.github/workflows/scheduled-terraform-drift.yml` — already `workflow_dispatch`-only,
   Inngest-dispatched (ADR-033) via `cron-terraform-drift.ts`, checks a Sentry cron-monitor, carries a
   `heartbeat-live-reconcile` job (live-vs-manifest, find-or-update-by-title), AND runs `terraform
   plan` drift on `apps/web-platform/infra` (store-inventory drift). Store-inventory-vs-ledger is a
   Layer A concern; store-inventory-vs-live-Hetzner is already this workflow's job.

**Net:** the only measurable volume is host-covered; inventory drift is covered; the `--json` read is
design-time. There is no non-duplicative, non-cry-wolf slice of live reconciliation the runner can do
today.

## Research Reconciliation — Spec (issue #6902) vs. Codebase

| Issue claim / prescription | Reality (verified) | Plan response |
| --- | --- | --- |
| "Inngest-dispatch hybrid: `cron-encryption-posture-reconcile.ts` → new `workflow_dispatch` workflow" | `scheduled-terraform-drift.yml` already IS that shape and carries a live-reconcile job; a new Inngest fn/workflow violates ADR-033 single-substrate. AND — more fundamentally — there is no live signal to reconcile (below). | **Build no cron this increment.** Defer the live reconcile; if/when built, ride the existing job (recorded in ADR-141), not a new substrate. |
| "shells out to `python3 scripts/lint-encryption-posture.py --report --json`" | `--json` short-circuits and **ignores `--report`** (`main()` returns before `run_sweep`); `--json` emits the committed ledger **verbatim, hermetically** (`:54, 1006-1012`). It is a static-file read, not a live probe. | Confirms the "no live signal" finding. The `--report --json` combo is inert; canonical is `--json`. |
| "positive-work floor counts only `live_verification:available` rows" | Correct and useful — but as a **Layer A PR-time** floor over the committed ledger, not a Layer B cron (the field is static). | Adopt as a **Layer A** floor assertion (≥1 available row), the correctly-layered home for the coverage-regression guard. |
| "Sentry cron-monitor plane so `sentry-monitor-iac-parity.test.ts` covers it" | The parity guard is workflow-step-granular; a monitor on a non-existent cron is moot. With no cron built, no monitor is needed. | Deferred with the live reconcile. |
| "measure 1 of 6 volumes (workspaces_luks)" | Confirmed exactly (1/6 volumes, 1/14 stores). | Verdict rests on this. |
| "ADR-117 measure-then-arm; #6901 DEFER pattern" | Both exist; #6901 CLOSED. | Mirrored — near-total DEFER. |
| "Deferred from merged audit #6885 — do not re-do it" | #6885 MERGED. | No audit re-done; the Layer A floor is a NEW mechanical invariant, not a ledger-content edit. |

## Scope Decision

**In scope (the honest, correctly-layered increment):**

1. **ADR-141** — the durable deliverable. Records the measure-then-scope DEFER verdict, the
   **host-probe-vs-runner-reconcile distinction**, why `--json` is design-time (static-file) not live,
   the overlap with luks-monitor.sh + terraform-drift, and the **arm trigger** (the live reconcile is
   buildable only once a per-volume emitter #6894/#6895/#6897 gives the runner a real signal). Written
   via `/soleur:architecture`. Extends ADR-140 (Layer A) and ADR-117 (measure-then-arm); ADR-033
   lineage for the substrate note.
2. **A Layer A positive-work-floor assertion** in `scripts/lint-encryption-posture.py` — extend the
   existing R8 floor (`check_positive_work_floor`) with: **the ledger must retain ≥ 1 store whose
   `at_rest.live_verification == "available"`** (fail-closed if it drops to zero — the ledger silently
   losing ALL measurable coverage is the one regression worth blocking at PR time). This is the
   correctly-layered home for the "coverage-claim regression guard": co-located with the parser (no
   dual-source-of-truth), resolved against the committed ledger at PR time, **no cron**. It is a floor
   (count ≥ 1), NOT an identity pin on `workspaces_luks` — so a legitimate individual regression that
   is honestly re-ledgered does not false-page; only zeroing-out all live coverage does. Plus a
   **synthesized** fixture test (`cq-test-fixtures-synthesized-only`).
3. **File the Layer B tracking issue** for the armed live reconcile, gated on #6894/#6895/#6897.

**Explicitly DEFERRED (with rationale — see `decision-challenges.md` for the issue-prescription
challenges):**

- **The Layer B live-reconcile script + cron job** (`reconcile-encryption-posture.ts` + a
  `scheduled-terraform-drift.yml` job). No live signal exists today; a cron over a static-file read is
  a mis-scoped Layer A check that degrades PR-time blocking to hours-later email. Build it when an
  emitter lands.
- **The dedicated `sentry_cron_monitor` + parity coverage.** Moot with no cron; lands with the armed
  reconcile.
- **The new `cron-encryption-posture-reconcile.ts` Inngest fn + new workflow.** ADR-033
  single-substrate; ride the existing job if/when built.
- **The armed per-row live reconcile + find-or-update-by-title mismatch filing.** The core Layer B
  feature — gated on runner-reachable live signal from the emitters.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The deliverables are an ADR
(docs) and a PR-time Layer A CI assertion. A broken floor assertion would at worst fail CI on this PR
(caught immediately), never reach production, and never touch user data or the serving path. The
status quo (luks-monitor.sh for the live volume, Layer A for the ledger) is unchanged.

**If this leaks, the user's data is exposed via:** N/A — no store, no connection, no secret, no
user-data path is touched. The Layer A assertion reads the committed ledger hermetically.

**Brand-survival threshold:** `aggregate pattern` — a deferred detective control is an aggregate-risk
posture, not a per-user breach. Nothing here performs or gates the at-rest encryption itself.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** ADR-141 exists at `knowledge-base/engineering/architecture/decisions/ADR-141-*.md`
  (ordinal re-verified against a freshly-fetched `origin/main` per the ADR-Ordinal Collision Gate),
  `status: adopting`, recording: the measure-then-scope DEFER verdict; the
  host-probe-vs-runner-reconcile distinction; the `--json`-is-design-time (static-file) analysis; the
  overlap with luks-monitor.sh + terraform-drift; the arm trigger (#6894/#6895/#6897); and the
  ADR-033 substrate note (ride the existing job if/when built). Any plan/AC reference to the ordinal is
  swept if it renumbers.
- [x] **AC2** `scripts/lint-encryption-posture.py` gains a positive-work-floor assertion: with a
  **synthesized** fixture ledger whose stores are ALL `unavailable:*`, `--repo-sweep` FAILS with a
  `FAIL: ... at least one live_verification:available store required ...` line and non-zero exit.
- [x] **AC3** With a synthesized fixture containing ≥ 1 `available` row (and any number of
  `unavailable` rows), the new assertion PASSES — it is a floor (count ≥ 1), not an identity pin, so it
  does not false-fail on individual honest regressions.
- [x] **AC4** The new assertion is **hermetic** (no network / no `gh` / no host read) — it reads only
  the committed ledger via the existing loader, preserving the script's stated hermeticity (`:54`).
- [x] **AC5** `python3 scripts/lint-encryption-posture.py --repo-sweep` PASSES against the **real**
  committed ledger (which has 1 available row) — the assertion does not regress current CI.
- [x] **AC6** The Layer A test battery (`scripts/lint-encryption-posture.test.sh` or the repo's runner
  for it) covers the new floor with the two synthesized fixtures (all-unavailable → FAIL; ≥1 available
  → PASS). Verify the test path/runner at /work.
- [x] **AC7** No `.tf`, no workflow, no cron, no Inngest fn, no `sentry_cron_monitor` is added
  (assert the diff introduces none — this is the near-total DEFER).

### Deferred (Layer B tracking issue, not this PR)

- [ ] The armed per-row live reconcile + find-or-update-by-title mismatch filing + (if built) the ride
  on the existing `scheduled-terraform-drift.yml` job + a dedicated `sentry_cron_monitor` + parity
  coverage — gated on #6894 / #6895 / #6897 giving the runner a real live signal.

## Observability

The in-scope deliverables are an ADR (docs) and a Layer A CI assertion in `scripts/` — **not a
production runtime surface** (no `apps/*/server`, `apps/*/src`, `apps/*/infra`, or `plugins/*/scripts`
path; no new infra). The Phase 2.9 trigger set does not fire. The one observable behavior is a CI
gate:

```yaml
liveness_signal:
  what: "the lint-encryption-posture.py positive-work floor (≥1 available row) runs as part of Layer A CI on every PR"
  cadence: "per-PR (the existing Layer A repo-sweep check, #6901)"
  alert_target: "the PR's failing required check (Layer A repo-sweep) — blocks merge; no runtime paging needed"
  configured_in: "scripts/lint-encryption-posture.py + the Layer A CI check that invokes --repo-sweep"
error_reporting:
  destination: "the assertion's FAIL line on stderr + non-zero exit fails the CI check"
  fail_loud: "fail-closed — a zero-available-row ledger fails the sweep; it cannot pass silently"
failure_modes:
  - mode: "ledger silently drops all live_verification:available rows"
    detection: "the new floor assertion FAILs the repo-sweep"
    alert_route: "the failing Layer A required check on the PR"
logs:
  where: "CI job log for the Layer A repo-sweep step"
  retention: "GHA default (90 days)"
discoverability_test:
  command: "python3 scripts/lint-encryption-posture.py --repo-sweep; echo rc=$?"
  expected_output: "rc=0 on the current ledger (1 available row); a FAIL line + rc=1 on an all-unavailable ledger"
```

## Encryption Posture

**No new persistent store, no new cross-component connection, no `.tf`/`.sql`/cloud-init/compose
change.** The Phase 2.11 detection set does not fire. The Layer A assertion reads the committed ledger
hermetically. The encryption posture of the observed stores is unchanged and already ledgered.

## Infrastructure (IaC)

**No IaC.** No server, service, cron, secret, DNS, cert, or firewall rule is introduced. The Phase 2.8
gate does not fire. (The deferred live reconcile, if built, would ride the already-provisioned
`scheduled-terraform-drift.yml` — recorded in ADR-141 — and only its eventual dedicated Sentry monitor
would be IaC, carried by the tracking issue.)

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-141** (provisional — re-verify next-free against a freshly-fetched `origin/main`; last
  on main is ADR-140): *"Layer B encryption-posture live reconcile is deferred until a per-volume host
  emitter gives the runner a real signal; the interim coverage guard lives in Layer A."* `## Decision`:
  DEFER the live reconcile + cron; add a Layer A positive-work floor (≥1 available row); arm the live
  reconcile only when #6894/#6895/#6897 land a runner-reachable signal, riding the existing
  `scheduled-terraform-drift.yml` job (ADR-033), not a new substrate. `## Alternatives Considered`:
  (a) full armed reconcile now — rejected (1/14; no live signal); (b) disarmed cron skeleton over the
  ledger — rejected (the `--json` read is a static-file/design-time check; a cron adds no detection
  value and violates the Layer A/B boundary — the YAGNI finding); (c) dedicated Sentry monitor for a
  disarmed probe — moot with no cron; (d) new Inngest fn/workflow — ADR-033 violation. `## Context`:
  the host-probe-vs-runner-reconcile distinction (mirrors ADR-123 "self-report, no self-converge" and
  ADR-126 "cron liveness must assert the consumed artifact"); the `--json` hermeticity; the emitter
  sequencing; provider-managed rows structurally out of runner reach forever. `status: adopting`.

### C4 views — no C4 impact (enumeration cited)

Checked against all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`) per the completeness mandate:

- **External human actors:** none new. **External systems:** Sentry (`model.c4:294`), GitHub CI
  (`:232`) — already modeled; nothing new is wired (no cron/monitor added). **Data stores:** the
  ledger is a committed repo file, not a C4 container; observed volumes already modeled (`:182-220`).
  **Access relationships:** none change — with no cron/monitor added, the `github -> sentry` edge
  counts (`:511`) are **not** falsified.

**Conclusion: no `.c4` edit.** (When the deferred reconcile lands its cron + monitor, THAT plan
updates the counts.)

### Sequencing

ADR authored now (`status: adopting`) describing the target (armed) state; the live reconcile itself
is deferred to the tracking issue. Not postponed to a separate ADR.

## Domain Review

**Domains relevant:** Engineering (infra/observability) — reviewed via architecture-strategist,
spec-flow-analyzer, and code-simplicity/YAGNI (the last drove the DEFER). No Product/UX surface
(no `components/**`, `app/**/page.tsx`, or UI glob) → Product Gate **NONE**. No
Finance/Legal/Sales/Marketing/Support implications.

### Engineering (infra/observability)

**Status:** reviewed (three deepen agents; findings folded into the DEFER verdict + Layer A floor).
**Assessment:** the material trade-off — whether Layer B can do non-duplicative live work today — was
resolved decisively by the YAGNI finding that `--json` is a hermetic static-file read; the correctly
layered increment is an ADR + a Layer A floor + a tracking issue.

## Sharp Edges

- **`--json` is a design-time (static-file) read, not a live signal (THE finding).** Any future
  attempt to build a Layer B "reconcile" over `lint-encryption-posture.py --json` is a Layer A check in
  disguise — the field it reads only changes via a reviewed commit. A live reconcile needs a
  runner-reachable signal that does NOT come from the committed ledger (a per-volume host emitter). Do
  not resurrect the cron skeleton until that signal exists.
- **The Layer A floor is a count, not an identity pin.** Assert `≥1 available`, never
  `workspaces_luks ∈ available` — an identity pin duplicates a fact the ledger already asserts
  (dual-source-of-truth) and false-pages on a legitimate honest re-ledgering. The floor pages only when
  ALL live coverage is zeroed, which is genuinely worth blocking.
- **Arm threshold over *runner-reconcilable* rows, never "all available."** Provider-managed rows are
  structurally `unavailable` forever (#6896 CLOSED, rows stay unavailable) — an "arm when all available"
  condition never fires.
- **ADR ordinal is provisional.** `git fetch origin main` and re-derive next-free at ship; sweep the
  plan/tasks/ACs if renumbered.
- **Do not add a cron for a static input.** A twice-daily job re-reading two committed files degrades a
  PR-time block into hours-later email — strictly worse. If a coverage invariant is wanted, it belongs
  at PR time (Layer A), which is where this plan puts it.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-141-*.md` — via `/soleur:architecture`.
- A synthesized-fixture test addition for the new Layer A floor (path per the existing Layer A test
  convention — verify at /work).

## Files to Edit

- `scripts/lint-encryption-posture.py` — extend `check_positive_work_floor` (or add a sibling check)
  with the ≥1-`live_verification:available` floor + its FAIL line.

**Deliberately NOT created/edited (deferred):** `reconcile-encryption-posture.ts`, any
`.github/workflows/*` job, `apps/web-platform/infra/sentry/cron-monitors.tf`,
`sentry-monitor-iac-parity.test.ts`, `model.c4`.

## Open Code-Review Overlap

None (no open `code-review`-labelled issues found touching `scripts/lint-encryption-posture.py` or the
ADR path during planning; re-run the overlap query at /work if the backlog changed).

## Decision Challenges (headless — for `ship` to render + file as `action-required`)

Recorded to
`knowledge-base/project/specs/feat-one-shot-6902-encryption-posture-layer-b-reconcile/decision-challenges.md`.
The plan defers the issue's core prescription (an Inngest-dispatched Sentry-monitored live reconcile
cron) because the deepen analysis proved there is no runner-reachable live signal to reconcile today —
the `--json` read is a hermetic static-file (design-time) operation. Operator may override; the
challenges document the reasoning and the exact conditions (emitters #6894/#6895/#6897) under which the
full reconcile becomes buildable.

## Deferral Tracking

- **File the Layer B tracking issue** (milestone from `roadmap.md`) for the armed live reconcile: what
  (per-row live reconcile + find-or-update-by-title + optional ride on `scheduled-terraform-drift.yml`
  + dedicated Sentry monitor), why deferred (1/14 measurable; no runner-reachable live signal; overlap
  with existing detectors), re-eval criteria (an emitter lands a runner-reachable signal), blockers
  #6894/#6895/#6897.
- Prerequisite emitters already tracked (#6894/#6895/#6897 OPEN) — referenced as blockers, no new
  emitter issues filed.
