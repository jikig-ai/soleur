---
title: "fix(infra): serialize cross-pipeline web-1 swaps (release deploy vs operator recreate/warm-standby) via a shared job-level concurrency group"
date: 2026-07-05
type: fix
issues: ["#6060"]
branch: feat-one-shot-6060-web2-recreate-hardening
lane: cross-domain
brand_survival_threshold: aggregate pattern
adr: ["ADR-068 (amend — cross-pipeline web-1-swap serialization)"]
---

# fix(infra): serialize cross-pipeline web-1 swaps + re-triage the two GA-scoped deferred items

🔧 **What this ships (issue #6060 item (c)).** The frequent push-release `deploy` job
(`web-platform-release.yml`, concurrency group `deploy-web-platform`, `:447`) and the rare
operator-dispatched `web_2_recreate` / `warm_standby` jobs (`apply-web-platform-infra.yml`,
workflow-level group `terraform-apply-web-platform-host`, `:115`) **each fan out a web-1
container swap** (both POST `/hooks/deploy`, which `ci-deploy.sh` fans out to peers after
swapping web-1) but are **NOT serialized against each other** — different concurrency
groups. So a release landing inside a recreate's widened in-flight window issues its own
independent web-1 swap concurrent with the recreate's re-POST swap — an **uncounted
concurrent web-1 swap** on the sole live prod origin (`app.soleur.ai`). This is FINDING 1
from #6051's review.

**The verified concrete harm (spec-flow trace, not hypothetical).** `/hooks/deploy` returns
202 immediately and `ci-deploy.sh` runs detached, serialized by `flock -n`. If the recreate's
detached swap wins the `flock`, the release's detached swap writes
`exit_code=1 reason=lock_contention` — and the release's `Verify deploy script completion`
step (`web-platform-release.yml:619-646`) has **NO case for `exit_code=1`**, so it falls to
`*)` → **the routine push-release deploy fails RED**. Second, the recreate re-POSTs web-1 at
its *existing* (possibly older) tag, risking a **tag-downgrade** of the sole live origin below
the just-shipped release tag (today only ms-window-race-guarded). The transient single-probe
`521` (deferred item (a)) is the *third*, smallest harm. Serializing the swaps closes all
three at the GitHub scheduler.

**Fix (verified best design at plan-time via Fable advisor consult + architecture-strategist
plan-review):** add a **single shared job-level concurrency group** (`web-1-swap`,
`cancel-in-progress: false`) to the **four jobs that actually swap web-1**:
1. the release `deploy` job (`web-platform-release.yml`),
2. the `web_2_recreate` job (`apply-web-platform-infra.yml`),
3. the `warm_standby` job (`apply-web-platform-infra.yml`), and
4. **the `apply` job in `apply-deploy-pipeline-fix.yml`** (`:177`) — it POSTs
   `command: deploy web-platform …` at `:607` and swaps web-1 (architecture-strategist P1: my
   v1 "three jobs" premise was incomplete; #3-#4 are ALREADY serialized against each other via
   the shared workflow-level `terraform-apply-web-platform-host` group, but the release deploy
   is NOT — leaving the exact release-vs-pipeline-fix concurrent-swap this plan claims to close).

Job-level concurrency **coexists** with the existing workflow-level
`terraform-apply-web-platform-host` group (verified — independent scopes), so the R2 state
serializer is untouched. This makes "only one web-1 swap in flight at a time across ALL swap
sources" an **atomic scheduler mutex** (no check-then-act TOCTOU), **bidirectional** (blocks
release-during-recreate AND recreate-during-release), and **queue-not-fail** (a release waits
then runs — never hard-failed / stranded ahead of prod). Zero custom polling script, zero new
API permission, zero new test seam.

**Correctness depends on the lock-hold-duration invariant (architecture-strategist P2):** all
four members POST `/hooks/deploy` then **poll deploy-status to a terminal state**, so each GHA
job stays open across the multi-minute on-host detached swap — the mutex is held for the whole
swap, not just the 202 POST. A future edit making any member fire-and-forget would release the
mutex in seconds while the swap ran on, silently restoring the overlap. The ADR amendment
records this invariant explicitly.

📋 **What this DEFERS (issue #6060 items (a) and (b)) — re-triaged inline, not silently.**
Both are architecturally out-of-lane for a bounded p3 hardening PR and each already has a
named future owner; see `## Deferred / Out of Scope`. In brief:
- **(a) truly-zero-downtime web-1 swap / web-2-only fan-out path** — the zero-downtime half
  needs a local reverse-proxy in front of web-1:80 (the *same* owner-side relay ADR-068 is
  already building for GA); the web-2-only-path half needs web-2 to run its own cloudflared
  connector + a new CF tunnel ingress + a new CF Access token (an ADR-worthy new off-host
  trust boundary). Neither is a hardening tweak.
- **(b) private-net web-2 post-accept health probe** — ADR-068 **explicitly** makes the
  on-host `/internal/readyz` pre-pool gate the deferred GA-cutover orchestrator's job; the
  GA warm-standby plan already reasoned this through and deferred it there.

## Enhancement Summary

**Deepened on:** 2026-07-05
**Research agents:** 3 Explore agents (traced all 3 deferred surfaces — graceful-swap/web-2-only
path, web-2 health probe, merge-freeze concurrency), spec-flow-analyzer, architecture-strategist,
code-simplicity-reviewer, + a Fable scoped-advisor consult. Mechanical halt gates: User-Brand
Impact (4.6 ✓), Observability (4.7 ✓ 5-field), PAT-shaped (4.8 ✓ none), UI-wireframe (4.9 ✓
no UI surface), Downtime & Cutover (4.55 ✓ no offline op introduced), network-outage (4.5 —
Hypotheses provides L3→L7 disposition; not a connectivity outage). Citations verified live
(#6060 OPEN, #6051/#6040/#5966 CLOSED, #3220 OPEN; all cited rule IDs active).

### Key improvements (all applied)
1. **Design pivot (Fable consult):** replaced the first-draft runs-API **polling gate** with a
   **job-level shared concurrency group** — atomic (no TOCTOU), bidirectional, queue-not-fail,
   zero custom code. Dissolves ~9 of spec-flow's polling-gate gaps by construction.
2. **P1 completeness fix (architecture-strategist):** the premise was "three swap jobs" — there
   are **four**. `apply-deploy-pipeline-fix.yml`'s `apply` job also POSTs `deploy web-platform`
   and swaps web-1; it is serialized against recreate/warm_standby (shared workflow-level group)
   but NOT against the release deploy. Added as the 4th `web-1-swap` member; guard is a 4-member
   allow-list.
3. **P2 lock-hold invariant (architecture-strategist):** serialization is only correct because
   every member POSTs-then-polls-to-terminal (holds the job across the on-host swap); recorded
   in the ADR + a Sharp Edge so a future fire-and-forget edit can't silently restore the overlap.
4. **Verified concrete harm (spec-flow):** the primary harm is not the transient 521 but a
   `lock_contention` **RED release** (the Verify step has no `exit_code=1` case) + web-1
   tag-downgrade — leading the Overview now.
5. **Threshold + YAGNI (code-simplicity):** downgraded `single-user incident` → `aggregate
   pattern` (the change is risk-reducing; no single-user-incident failure mode is reachable);
   cut the LARP AC10 and the internals-coupling apply-body grep; the allow-list guard resolves
   the arch(catch-dropped)/simplicity(don't-block-future-add) tension.

### New considerations discovered
- The **inngest** deploy workflows share the on-host `flock` (so an inngest deploy CAN
  `lock_contention`-RED a release) — recorded as a **named accepted residual** with a promote
  trigger, not silently ignored.
- G10 residual: a queued release widens the migrate-applied-but-not-deployed window (accepted
  under expand/contract discipline; do NOT gate `migrate` on `web-1-swap`).
- Coexistence of job-level + workflow-level `concurrency` **confirmed** against the GitHub
  workflow-syntax reference (no in-repo precedent existed) — R2 serialization is preserved.

## Overview

Two-line-of-effort PR, but the second is documentation-only:

1. **Serialize web-1 swaps across pipelines (the code change).** Put the release `deploy`
   job and the `web_2_recreate` + `warm_standby` jobs into one shared job-level
   `concurrency` group so GitHub's scheduler guarantees at most one web-1 swap runs at a
   time. Add a CI drift-guard test asserting all four member jobs carry the identical shared group
   literal (a rename or a dropped copy fails CI). Amend ADR-068 to record the invariant.

2. **Re-triage (a) and (b) with sharpened tracking (the docs change).** Update #6060: check
   off item (c); rewrite items (a) and (b) with their verified future owner + concrete
   re-evaluation criteria so they are individually actionable and not left as a vague
   tracker. `Ref #6060` (NOT `Closes` — (a)/(b) remain open).

**Design decision (advisor-confirmed).** The obvious alternative — a runs-API polling gate
job in the release workflow — was the plan's first draft and was **rejected** at the Fable
scoped consult (Phase 4.5): a polling gate is check-then-act (TOCTOU: a recreate dispatched
between the gate passing and the deploy POST slips through), one-directional (does nothing
when a recreate is dispatched mid-release-swap), must be defined wait-not-fail or it strands
a release undeployed ahead of prod, and carries a custom script + unit-test + `actions:read`
permission to maintain. The job-level shared concurrency group dissolves all four for free.
The other rejected alternative — reusing the whole `terraform-apply-web-platform-host` group
— is over-broad (it would serialize every routine push-release behind every routine infra
`apply`, which does NOT swap web-1). Scoping the shared group to **only the four
swap-performing jobs** (the routine `apply` push/manual-rerun job is excluded — verified it does
not POST `/hooks/deploy`) avoids that.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6060 / premise) | Codebase reality (verified) | Plan response |
|---|---|---|
| Release deploy and recreate/warm-standby are not serialized | Confirmed: release `deploy` group `deploy-web-platform` (`web-platform-release.yml:447`); recreate/warm-standby inherit workflow-level `terraform-apply-web-platform-host` (`apply-web-platform-infra.yml:115`) — disjoint groups | Add a shared job-level `web-1-swap` group to all four swap sites |
| There are exactly FOUR web-1-swap sites (all POST `command: deploy web-platform` to `/hooks/deploy`) | Confirmed: (1) release `deploy` (`web-platform-release.yml:572`); (2) `web_2_recreate` (`apply-web-platform-infra.yml`, `OP_CONTEXT=recreate`, `:912`) + (3) `warm_standby` (`:820/:838`) both via `deploy-status-fanout-verify.sh`; (4) `apply-deploy-pipeline-fix.yml` `apply` job POSTs at `:607` (`command: deploy web-platform …`). `ci-deploy.sh` swaps web-1 on each (`:1346-1389`) then `fan_out_to_peers` (`:1442-1451`) | Serialize ALL FOUR in `web-1-swap` (arch P1 — v1 missed site 4) |
| Sites 2/3/4 are already mutually serialized; the release deploy is the gap | Confirmed: `web_2_recreate`/`warm_standby` (workflow-level `terraform-apply-web-platform-host`, `apply-web-platform-infra.yml:115`) AND `apply-deploy-pipeline-fix.yml` `apply` (same workflow-level group, `:138`) share the R2 serializer → only one of these 3 runs at a time. The release `deploy` (`deploy-web-platform`) is in NONE of them | `web-1-swap` adds the release deploy to the mutex (the missing edge) |
| The routine `apply` (push/manual-rerun) job in apply-web-platform-infra.yml also swaps web-1 | **False** — that `apply` job (`:162-635`) runs terraform but contains NO `/hooks/deploy` POST (grep-verified) → does not swap web-1 | Do NOT add it to `web-1-swap` (keeps routine releases un-blocked by routine infra applies) |
| The inngest deploy workflows swap web-1 | **False (different container)** — `restart-inngest-server.yml:47` (`restart inngest`) + `deploy-inngest-image.yml:54` (`deploy inngest …`) POST the SAME `/hooks/deploy` but swap the **inngest** container, not web-1's app container. They DO contend for the same on-host `flock`/deploy-state slot (so an inngest deploy CAN lock_contention-RED a concurrent web-1 release) | Excluded from `web-1-swap` (web-1-swap semantics); the flock-contention is a **named accepted residual** (see Deferred) — re-eval if an inngest-caused release RED is observed |
| A job can only be in the workflow-level group | **False for our need** — GitHub Actions allows `concurrency` at BOTH workflow level AND job level; they are independent scopes and coexist. `web_2_recreate`/`warm_standby` keep the workflow-level R2 serializer AND gain a job-level `web-1-swap` group | Phase 0 verifies coexistence via `actionlint` + GitHub docs before relying on it (Sharp Edge) |
| A shared concurrency group is "over-broad" (plan v1 objection) | True only if reusing the whole terraform group; **false** for a job-scoped group covering only the 4 swap jobs | Adopt the job-scoped group (Fable consult) |
| `reason==ok` proves web-2 health (item b premise) | **False** — `reason==ok` proves web-2 ACCEPTED the fan-out (HTTP 202 + `:9000` bound), not its canary/readyz health; web-2 health is private-net-only (`ci-deploy.sh:1442-1459`; off-host runner is private-net-deny) | Item (b) deferred to the GA orchestrator's on-host readyz gate (ADR-068) |
| Item (a)'s transient 521 is unbounded | **False** — #6051 already bounds recreate amplification to ≤2 web-1 swaps (`DEGRADED_RETRY_MAX=1`); BetterStack pages on a *sustained* (not transient) 521 | Item (a)'s residual is a rare transient single-probe 521 → genuinely p3, deferred |

## User-Brand Impact

**If this lands broken, the user experiences:** a concurrency-group mis-wire has two failure
shapes. (1) *False-serialize / over-serialize* (e.g., the group accidentally includes the
routine `apply` job, or the group string diverges so a swap is NOT actually serialized):
worst case a routine prod release is delayed behind an unrelated infra apply (deploys new
code later — existing prod keeps serving, no data/exposure impact), OR the intended
serialization silently does not happen and the pre-existing concurrent-swap 521 window
persists (a *no-op*, not a regression). (2) *A hard-fail instead of a queue* (if a future
edit reintroduced a fail-closed gate): a release could be left merged-to-main-but-undeployed
with no auto-reconcile until the next push — the trap the queue-not-fail design exists to
avoid. web-1 is the sole live serving origin, so any change on the deploy path is weighed at
this threshold.

**If this leaks, the user's workflow is exposed via:** N/A — no user data, secrets, or PII
are read/written; the change is GitHub Actions concurrency metadata + an ADR amendment. No
new credential, endpoint, or trust boundary is introduced (unlike deferred item (a)'s
web-2-only path, which is why (a) is out of scope).

**Brand-survival threshold:** aggregate pattern — the change lives on the web-1
release-to-prod deploy path (web-1 = sole live origin), but no *single-user incident* failure
mode is reachable by it: a mis-wire is either a **no-op** (serialization silently does not
happen → the *pre-existing* concurrent-swap hazard persists, not a new one) or a **loud CI
failure** (the drift-guard RED-flags a dropped/diverged copy). The only single-user-incident
shape — a hard-fail that strands a release undeployed ahead of prod — is *not reachable* by
this change (it queues, never hard-fails; that shape would require a FUTURE edit
reintroducing a gate). The residual user-facing risk it touches (the transient single-probe
521 from a concurrent swap) is aggregate/probabilistic, and this change *reduces* it. Threshold
downgraded from `single-user incident` at plan-review (code-simplicity challenge) — the change
strictly reduces concurrent-swap risk and adds no new exposure. Load-bearing mitigations kept:
(i) the shared group is **job-scoped to the 4 swap jobs only** (routine releases are not
blocked by routine infra applies), (ii) `cancel-in-progress: false` so an in-progress swap is
never killed mid-flight (a killed `ci-deploy.sh` mid-`docker run` would itself widen a 521
window) and `web_2_recreate`'s terraform apply is never cancelled mid-apply, (iii) the design
**queues, never hard-fails**.

## Design Detail

### The shared job-level concurrency group

Add to **each** of the four web-1-swap-performing jobs an identical job-level block:

```yaml
concurrency:
  group: web-1-swap
  cancel-in-progress: false
```

- **Release `deploy`** (`web-platform-release.yml:446-448`): this job **already** has a
  job-level `concurrency: { group: deploy-web-platform }`. A job may carry only ONE
  `concurrency` block, so this is a **rename** `deploy-web-platform` → `web-1-swap` (the
  release-vs-release serialization it provided is preserved — two releases still share the
  group). Sweep the one companion comment at `:439` ("Holds the deploy-web-platform lock").
  `deploy-web-platform` is referenced NOWHERE else (grep-verified: only `:439` + `:447`).
  *(Diff-minimal alternative, code-simplicity note: instead of the rename, reuse the existing
  name `deploy-web-platform` as the shared group and have the other three jobs adopt IT —
  zero edits to the release workflow, no comment sweep, no AC4 stale-ref grep. Rejected as the
  default only because `deploy-web-platform` is a misleading name on a terraform-recreate job;
  `/work` + reviewers may pick it if diff-minimality outweighs naming clarity.)*
- **`web_2_recreate`** (`apply-web-platform-infra.yml:~876`), **`warm_standby`** (`:~647`),
  and **`apply-deploy-pipeline-fix.yml`'s `apply` job** (`:177`): these currently have NO
  job-level `concurrency` (they inherit their respective workflow-level
  `terraform-apply-web-platform-host` R2 serializer). ADD the job-level `web-1-swap` block to
  each. The workflow-level R2 group is UNCHANGED and still applies to each whole apply run.

**Why this is correct + deadlock-free (4-member analysis).** Sites 2/3/4 all share the
workflow-level `terraform-apply-web-platform-host` R2 group (across `apply-web-platform-infra.yml`
and `apply-deploy-pipeline-fix.yml`), so **at most one of {recreate, warm_standby,
pipeline-fix-apply} runs at a time**. That one contends for `web-1-swap` against at most the
release `deploy` (which holds ONLY `web-1-swap` and needs nothing else). So `web-1-swap` has ≤2
live contenders and the release always makes progress → no hold-and-wait cycle, no deadlock.
Bidirectional: whichever swap is dispatched first holds the mutex; the other queues. Routine
infra `apply` (push/manual-rerun) is NOT in `web-1-swap`, so routine releases are unaffected by
routine infra applies.

**Lock-hold-duration invariant (load-bearing, architecture-strategist P2).** The mutex only
serializes the *actual* swaps because every member **POSTs `/hooks/deploy` then polls
deploy-status to a terminal state** — the GHA job (and thus `web-1-swap`) is held across the
multi-minute on-host detached swap, not just the 202 POST. All four members do this today. A
future edit making any member fire-and-forget would release the mutex in seconds while the swap
ran on, silently restoring the overlap while the drift-guard stays green. The ADR amendment
records this invariant; the guard optionally asserts each member has a completion-poll step.

**Latest-wins / cancelled-queued semantics (advisor caveat, documented).** GitHub keeps at
most one *pending* run per concurrency group; a queued release superseded by a newer release
of a later SHA is cancelled (latest-wins). For push deploys this is correct — the newer SHA
supersedes the stale queued one and deploys `main`'s latest, so nothing is stranded.
`cancel-in-progress: false` guarantees an **in-progress** swap (release OR recreate) is never
cancelled. AC-covered + documented in `## Downtime & Cutover`.

### Drift-guard test

A concurrency literal replicated across four jobs in three files is exactly the shape the repo's parity
guards protect (cf. `web-hosts-fanout-parity.test.sh`, and the `head -1` un-guard lesson
`2026-07-05-extracted-specialized-shared-script-not-clean-swap-and-parity-blind-spots.md`).
Add an **allow-list** guard (a `.test.sh` or an assertion in an existing infra/workflow test)
— an explicit named-member list resolves the tension between "catch a dropped member" (arch)
and "don't block a deliberate future addition" (simplicity): a future PR that enrolls a new
swap site updates the allow-list as a visible, intentional edit. The guard:
- defines the expected 4 members by `(workflow-file, job-name)`: `web-platform-release.yml`→
  `deploy`; `apply-web-platform-infra.yml`→`web_2_recreate`,`warm_standby`;
  `apply-deploy-pipeline-fix.yml`→`apply`;
- asserts each named member carries job-level `concurrency.group == web-1-swap` with
  `cancel-in-progress: false`;
- asserts the **total** number of `web-1-swap` group occurrences across the repo's workflows
  **equals the allow-list length (4)** — so a silently-dropped member OR an accidental/unlisted
  new member both fail loud (NOT `head -1`, NOT a bare `>= N`);
- asserts the workflow-level `terraform-apply-web-platform-host` literal still present in both
  `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` (R2-serialization
  preserved, AC1);
- (optional, P2) asserts each member job has a deploy-status completion-poll step (guards the
  lock-hold-duration invariant against a future fire-and-forget edit).

Prefer extending an existing infra/workflow test over a brand-new file if one already parses
these workflows; otherwise a new `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`
registered in `infra-validation.yml` (mirror the `run: bash apps/web-platform/infra/<name>.test.sh`
registration pattern at `infra-validation.yml:154`).

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (coexistence + R2-preservation verified BEFORE relying on it):** the
  load-bearing claim — job-level `concurrency` coexists with workflow-level `concurrency`,
  independent scopes — is **confirmed** (GitHub workflow-syntax reference, verified
  2026-07-05: *"concurrency can be defined at both levels in the same workflow; they operate
  independently — workflow-level concurrency governs the entire workflow run, while job-level
  governs only that individual job's execution"*;
  `https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions`).
  Phase 0 re-confirms via `actionlint` accepting the edited `apply-web-platform-infra.yml`
  (which then carries BOTH scopes). **The real safety property to assert:** adding the
  job-level `web-1-swap` group to `web_2_recreate`/`warm_standby` MUST NOT drop them from the
  workflow-level `terraform-apply-web-platform-host` R2 serializer — per the cited reference
  the workflow-level group governs the whole apply run regardless of any job-level group, so
  R2 serialization is preserved; the drift-guard test (AC2) additionally asserts the
  workflow-level group literal is still present and unchanged.
- [x] **AC2 (four members share the group — allow-list guard):** the drift-guard test asserts
  the 4 named members — `deploy` (`web-platform-release.yml`), `web_2_recreate` + `warm_standby`
  (`apply-web-platform-infra.yml`), `apply` (`apply-deploy-pipeline-fix.yml`) — each carry
  job-level `concurrency.group == web-1-swap` with `cancel-in-progress: false`, AND the total
  count of `web-1-swap` occurrences across the workflows **== 4** (allow-list length) so a
  dropped member OR an unlisted new member both fail loud (not `head -1`, not `>= 4`). It also
  asserts the workflow-level `terraform-apply-web-platform-host` literal is still present in BOTH
  `apply-web-platform-infra.yml` AND `apply-deploy-pipeline-fix.yml` (R2 preserved, AC1). The
  routine `apply` job (apply-web-platform-infra.yml) is not a named member, so the `== 4`
  count fails if it (or any other job) is accidentally enrolled.
- [x] **AC4 (release-vs-release preserved):** the rename preserves release deploy
  serialization — `web-1-swap` is the group two concurrent release `deploy` runs share
  (asserted by the test reading the single release-deploy group literal), and no stale
  `deploy-web-platform` reference remains (`grep -rn 'deploy-web-platform' .github/ apps/
  plugins/ scripts/` returns 0).
- [x] **AC5 (workflow lint):** `actionlint .github/workflows/web-platform-release.yml
  .github/workflows/apply-web-platform-infra.yml` clean; any embedded `run:` snippet
  syntax-checked via `bash -c '<snippet>'` (never `bash -n` on the YAML). For the composite
  action caveat: do NOT actionlint `.github/actions/*/action.yml`.
- [x] **AC6 (script/test lint):** `shellcheck` clean on any new `.test.sh` (match sibling
  `apps/web-platform/infra/*.test.sh` conventions).
- [x] **AC7 (test registered):** if a new `.test.sh` is added, it is registered in
  `.github/workflows/infra-validation.yml` next to the sibling infra `.test.sh` steps
  (`:154`).
- [x] **AC8 (ADR amended):** ADR-068 carries a short amendment documenting the cross-pipeline
  web-1-swap serialization invariant: one shared job-level `web-1-swap` group across the **4**
  swap-performing jobs (release `deploy`; `web_2_recreate`; `warm_standby`;
  `apply-deploy-pipeline-fix.yml` `apply`); workflow-level R2 serializer unchanged;
  `cancel-in-progress: false` rationale; the **lock-hold-duration invariant** (members must
  poll-to-terminal); the inngest-flock accepted residual. `Ref #6060`. **Amend**, not a new
  ADR (no decision reversed).
- [x] **AC9 (deferred re-triage recorded):** the PR body (via `ship`) and a #6060 update
  record: item (c) done; items (a) and (b) re-triaged with owner + re-eval criteria (see
  `## Deferred`). PR body uses `Ref #6060`, NOT `Closes` (a/b remain open).

### Post-merge (operator / automated)

None — the mechanical serialization is fully proven pre-merge by AC2 (the runtime queue-wait
on the `web-1-swap` group is confirmable in the Actions UI at the next recreate/release
overlap, but that is confirmation, not a gate; a v1 "AC10" restating it was cut at plan-review
as non-gating). No prod-write verification step is safe or needed.

## Test Strategy

Pure workflow-metadata change → the test surface is a static drift-guard over the two
workflow YAMLs (no network, no runtime). Follow the existing `apps/web-platform/infra/*.test.sh`
convention (plain bash, `pass/fail` counters, registered in `infra-validation.yml`) — do NOT
introduce bats. Parse the `concurrency.group` under each named job with an all-members
extractor (per-job, count-asserted), never `head -1`/`grep -m1`. No fixtures needed (the
assertions read the real workflow files). Verify `actionlint` is installed
(`command -v actionlint`) before prescribing it; it is already used across the repo's
workflow tests.

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions run queue state on the shared `web-1-swap` concurrency group — any of the 4 swap jobs (release deploy / web_2_recreate / warm_standby / pipeline-fix apply) shows 'waiting' when another web-1 swap is in flight; the drift-guard test result in infra-validation.yml gates the 4-member invariant at CI time"
  cadence: "on every push-release deploy + every operator recreate/warm-standby dispatch + every pipeline-fix apply (CI drift-guard on every PR touching the workflows)"
  alert_target: "GitHub Actions run status + job-summary; BetterStack apex/origin probe independently pages on a SUSTAINED (not transient) app.soleur.ai 521 (model.c4 origin absence detector) — the residual transient-521 backstop"
  configured_in: ".github/workflows/web-platform-release.yml (deploy job concurrency); .github/workflows/apply-web-platform-infra.yml (web_2_recreate + warm_standby); .github/workflows/apply-deploy-pipeline-fix.yml (apply); the new drift-guard .test.sh registered in infra-validation.yml"
error_reporting:
  destination: "CI: the drift-guard test FAILs loud in infra-validation.yml if the 3-copy shared-group invariant is violated (rename/drop/divergence). Runtime: GitHub Actions run status; a mis-serialized concurrent swap would surface as a transient 521 on the BetterStack apex probe."
  fail_loud: "true — the drift-guard is a hard CI gate (exit non-zero); no green-on-missing-copy (min-copies==3 assertion)"
failure_modes:
  - mode: "a future edit renames one member's group, drops a copy, or makes a member fire-and-forget → serialization silently lost"
    detection: "drift-guard asserts all 4 named members share the `web-1-swap` literal AND total count==4 (allow-list, not head -1); optional completion-poll-step assertion guards the lock-hold-duration invariant"
    alert_route: "CI RED on the PR (infra-validation.yml)"
  - mode: "the routine `apply` job is accidentally added to `web-1-swap` → routine releases over-serialized behind routine infra applies"
    detection: "drift-guard negative assertion: `apply` job MUST NOT be a `web-1-swap` member"
    alert_route: "CI RED on the PR"
  - mode: "concurrent web-1 swap still occurs (serialization no-op) despite the change"
    detection: "AC2 proves the mechanism pre-merge; at runtime a genuine concurrent swap would show a transient 521 on the BetterStack apex probe (a SUSTAINED 521 pages)"
    alert_route: "BetterStack apex heartbeat"
  - mode: "in-progress swap killed mid-flight (would widen a 521 window)"
    detection: "cancel-in-progress: false on the shared group — asserted by the drift-guard test; an in-progress run is never superseded"
    alert_route: "CI RED if cancel-in-progress != false on any copy"
logs:
  where: "GitHub Actions run logs + $GITHUB_STEP_SUMMARY (queue-wait visible in the run's timeline); infra-validation.yml test output"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh
  expected_output: "0 failed"
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-068** (multi-host workspaces / deploy fan-out): add an amendment recording the
**cross-pipeline web-1-swap serialization invariant** — the **four** jobs that POST
`command: deploy web-platform` to `/hooks/deploy` and thereby swap web-1 (release `deploy`;
`web_2_recreate`; `warm_standby`; `apply-deploy-pipeline-fix.yml`'s `apply`) share one
job-level `web-1-swap` concurrency group (`cancel-in-progress: false`) so at most one web-1
container swap runs at a time across ALL pipelines, while the workflow-level
`terraform-apply-web-platform-host` R2 state serializer is preserved unchanged (independent
scope). The amendment MUST state the **lock-hold-duration invariant**: correctness requires
each member to hold its GHA job open until deploy-status reaches a terminal state (POST-then-
poll-to-completion) — a fire-and-forget member would release the mutex before the swap
finishes. It also records the **accepted residual**: the inngest deploy workflows
(`restart-inngest-server.yml`, `deploy-inngest-image.yml`) share the same on-host `flock` but
swap a different container and are out of `web-1-swap` scope. This closes the FINDING-1
cross-pipeline concurrent-swap gap from #6051's review. Amend (no decision reversed);
`Ref #6060`. Keep it to a short paragraph (code-simplicity note) — not a re-derivation of the
plan.

### C4 views
**No C4 impact** — MUST be re-confirmed at /work by reading all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` (the
completeness mandate, not a keyword grep). Enumeration to confirm already-modeled with no new
element/relationship: **operator dispatch** (existing actor), **Hetzner web hosts**
(web-1/web-2, `model.c4`), **GHCR** (existing edge), **BetterStack origin absence detector**
(existing). No new external human actor, external system, data store, or access relationship
— the change is CI-scheduler serialization metadata over already-modeled internal control
edges (release→web-1 deploy webhook; apply→recreate→fan-out). A "no C4 impact" line at /work
MUST cite this enumeration after the full three-file read.

### Sequencing
Single atomic PR — the concurrency-group edits, the drift-guard test, and the ADR amendment
land together.

## Hypotheses (network/timing)

Not an SSH/firewall connectivity outage — no L3→L7 firewall diagnosis applies (per
`hr-ssh-diagnosis-verify-firewall`, stated explicitly because the feature text mentions
`521`). The `521` this hardening relates to is a web-1 container-swap gracefulness window
(deferred item (a)), NOT a firewall/egress/connectivity failure: the root cause is that two
pipelines can each trigger a web-1 `docker stop`/`docker run` swap concurrently
(`ci-deploy.sh:1346-1389`), and the fix serializes them at the GitHub Actions scheduler. No
firewall allow-list or egress-IP verification is required.

## Downtime & Cutover

**Offline-inducing operation:** none introduced. The change adds a scheduler mutex; it does
NOT alter `ci-deploy.sh`'s swap or add/remove any web-1 swap. Its only effect is to *reduce*
the chance of two web-1 swaps overlapping. `cancel-in-progress: false` guarantees no
in-progress swap is killed mid-flight (which would itself widen a 521 window).

**Queue semantics (documented, advisor caveat).** A push-release `deploy` that queues behind
an in-flight recreate waits (up to the recreate job's `timeout-minutes: 45` ceiling) then
runs — it is never hard-failed. A queued release superseded by a newer release of a later SHA
is cancelled by GitHub (latest-wins, at-most-one-pending-per-group); this is correct for push
deploys (the newer SHA covers the stale one — nothing is stranded ahead of prod). The
recreate is an operator-gated GA-prep dispatch, so a release queuing behind it for minutes is
expected and acceptable — that is the entire point of the serialization.

**Bidirectional by construction (spec-flow G9 resolved).** Because the shared group is a
scheduler mutex, it also serializes the *reverse* direction — an operator recreate dispatched
while a release deploy holds `web-1-swap` queues behind it — for free. A one-directional
polling gate (the rejected v1) would have left this direction unguarded; the concurrency
group needs no second gate and carries no mutual-deadlock risk (a single symmetric mutex, not
two gates waiting on each other).

**`flock` remains the on-host backstop (defense-in-depth, not primary).** `ci-deploy.sh`'s
`flock -n` still serializes any swap that somehow overlaps on-host; after this change the
GitHub scheduler mutex is the **atomic primary** serializer (it prevents the overlap from ever
being dispatched), and `flock` is belt-and-suspenders. Neither is removed.

**Accepted residual — migrate-applied-but-not-yet-deployed window widens (spec-flow G10).**
The `migrate` job gates on `await-ci`, NOT on `web-1-swap`. So when a release `deploy` queues
behind an in-flight recreate, that release's migrations have already applied while the cutover
waits — widening the existing expand/contract residual (`web-platform-release.yml:239-242`) by
up to the recreate's ~45-min ceiling. This is **accepted**, not fixed: migrations are
backward-compatible with the currently-deployed code by expand/contract discipline, so a
delayed cutover is safe. Do NOT add `web-1-swap` to `migrate`'s `needs:` — that would hold the
`migrate-web-platform` lock for the freeze duration (strictly worse). Documented here so a
future reader does not mistake the widened window for a regression.

## Domain Review

**Domains relevant:** none (infrastructure / CI-tooling change).

No cross-domain (product/marketing/sales/finance/legal/support) implications — the change is
GitHub Actions concurrency metadata + an ADR amendment. No UI surface (Files-to-Edit are
`.github/workflows/*.yml`, an ADR, a `.test.sh`), so the mechanical UI-surface override does
not fire and the Product/UX Gate is NONE. Plan-review that ran at plan time:
architecture-strategist + code-simplicity-reviewer + spec-flow-analyzer (+ a Fable scoped
advisor consult) — findings applied below. (Threshold is `aggregate pattern`, so no CPO
sign-off gate; the review depth was retained because the change touches the sole-live-origin
deploy path.)

## Infrastructure (IaC)

No new infrastructure — the change edits already-provisioned CI workflows + an ADR + a test.
It adds NO Terraform resource, secret, vendor, or persistent runtime process. (Deferred item
(a)'s web-2-only path WOULD need new IaC/vendor — CF tunnel ingress + Access token — which is
one reason (a) is out of scope.) IaC gate: skip.

## GDPR / Compliance

No regulated-data surface touched (no schema, migration, auth flow, API route, `.sql`; no LLM
processing of operator data; no new distribution surface). GDPR gate: skip.

## Files to Edit

- `.github/workflows/web-platform-release.yml` — rename the `deploy` job's job-level
  `concurrency.group` `deploy-web-platform` → `web-1-swap` (`:447`); update the companion
  comment (`:439`). Keep `cancel-in-progress: false`.
- `.github/workflows/apply-web-platform-infra.yml` — add a job-level
  `concurrency: { group: web-1-swap, cancel-in-progress: false }` to the `web_2_recreate`
  job (`~:876`) and the `warm_standby` job (`~:647`). Do NOT touch the workflow-level
  `terraform-apply-web-platform-host` group (`:115`). Do NOT add the routine `apply` job.
- `.github/workflows/apply-deploy-pipeline-fix.yml` — add the same job-level
  `concurrency: { group: web-1-swap, cancel-in-progress: false }` to its `apply` job (`:177`,
  the 4th web-1-swap site, POSTs `/hooks/deploy` at `:607`). Do NOT touch its workflow-level
  `terraform-apply-web-platform-host` group (`:138`).
- `.github/workflows/infra-validation.yml` — register the new drift-guard `.test.sh` (if a
  new file is added) next to the sibling infra `.test.sh` steps (`:154`).
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
  — amendment (AC8).

## Files to Create

- `apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` — network-free all-members
  drift-guard (AC2/AC3/AC4): 3 identical `web-1-swap` copies (count==3, not `head -1`),
  `cancel-in-progress: false` each, `apply` job excluded, no stale `deploy-web-platform`.
  (If an existing infra/workflow test already parses these YAMLs, extend it instead and drop
  this file — prefer the smaller diff.)

## Open Code-Review Overlap

One open code-review issue touches an edited file: **#3220** (`ci: postmerge verification of
trigger-bearing migrations in prd — review #3217`) references `web-platform-release.yml`.
**Disposition: Acknowledge** — #3220 concerns the migrate/verify-migrations jobs
(trigger-bearing DB migrations), a different concern from the `deploy` job's concurrency
group; this PR does not touch the migration jobs. #3220 remains open. (Re-run the two-stage
`gh --json … > f.json; jq --arg path …` check at /work after the final Files list is frozen.)

## Deferred / Out of Scope (with tracking on #6060)

Both remaining #6060 items are inline-triaged (per `wg-defer-only-after-inline-triage`) and
kept on the open #6060 tracker with sharpened re-eval criteria. #6060 stays OPEN after this
PR; the PR checks off item (c) only.

- **(a) truly-zero-downtime web-1 re-swap OR web-2-only fan-out path.** *Verified out-of-lane.*
  The zero-downtime half requires a **local reverse-proxy in front of web-1:80** to flip
  old→new container atomically (today the swap is `docker stop` then `docker run` on the same
  name/port — no overlap is structurally possible, `ci-deploy.sh:1346-1389`); that reverse
  proxy IS the **owner-side relay** (`SOLEUR_PROXY_BIND`) ADR-068 is already building for GA.
  The web-2-only-path half requires web-2 to run its own **cloudflared connector** + a new CF
  tunnel ingress hostname + a new CF **Access token/policy** (a new off-host credential/trust
  boundary — ADR-worthy; the tunnel is currently a single connector serving web-1 only,
  `tunnel.tf`). **Re-eval criteria (record on #6060):** revisit when the GA owner-side relay
  lands (fold the graceful swap into it), OR if BetterStack begins pinning a *sustained*
  (not transient single-probe) 521 to a recreate window. Until then the residual is a rare
  transient single-probe 521, already bounded by #6051's ≤2-swap cap — genuinely p3.
- **(b) private-net web-2 post-accept health probe for GA cutover.** *Verified
  GA-orchestrator-scoped.* `reason==ok` is accept-only (HTTP 202 + `:9000` bound), not web-2's
  own canary/readyz health, which is private-net-only and unreachable off-host. ADR-068
  **explicitly** makes the on-host `/internal/readyz` pre-pool gate (writable+populated, N≥2
  consecutive, loopback-gated) the **deferred GA-cutover orchestrator's** job, and the GA
  warm-standby plan (`2026-07-04-feat-autonomous-multihost-ga-warm-standby-and-gate-plan.md`)
  already reasoned this through and deferred it there. No existing mechanism carries web-2's
  health off-host; building one needs web-1→web-2 private-net peer-aggregation into
  deploy-status OR an on-host docker-exec verifier — both belong to the GA cutover PR.
  **Re-eval criteria (record on #6060):** this item is satisfied by the GA-cutover
  orchestrator's readyz pre-pool gate; re-point #6060 item (b) at that orchestrator work and
  close it when the orchestrator lands (do not build a separate probe here).
- **Named accepted residual — inngest deploys share the on-host `flock` (arch-review P1
  corollary).** `restart-inngest-server.yml` + `deploy-inngest-image.yml` POST the same
  `/hooks/deploy` and contend for `ci-deploy.sh`'s `flock`/deploy-state slot, so an inngest
  deploy overlapping a web-1 release can still cause a `lock_contention` RED on the release —
  the same harm class this plan reduces for web-1-vs-web-1 swaps. Left OUT of `web-1-swap`
  (different container; broadening the group to all `/hooks/deploy` POSTs is a larger
  decision). **Owner/trigger:** promote `web-1-swap` to cover the inngest deploy jobs (or
  rename to a `hooks-deploy` mutex) IF an inngest-caused release RED is observed in CI.
- **7-step setup byte-triplication → composite action** (`apply`/`warm_standby`/`web_2_recreate`).
  Named in #6060 "Also noted"; out of scope (DRY refactor, not hardening). Opportunistic; no
  separate issue (a comment on #6060).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, is `TBD`/placeholder, or omits the
  threshold FAILs `deepen-plan` Phase 4.6. This section is filled.
- **Job-level + workflow-level concurrency coexistence is the load-bearing runtime-shape
  claim** (per the "grep the installed runtime shape" sharp-edge family). Phase 0 MUST verify
  it (`actionlint` accepts a workflow carrying BOTH; pin a GitHub-docs citation) BEFORE
  relying on it — do not assert from memory. **Fallback if unsupported:** option (ii) — reuse
  `deploy-web-platform` as the shared group NAME (have `web_2_recreate`/`warm_standby` adopt
  job-level `concurrency.group: deploy-web-platform`), leaving release's group unchanged; the
  release workflow is then untouched and only 2 job-level blocks are added. Functionally
  identical; only naming differs.
- **`cancel-in-progress: false` is load-bearing, not cosmetic.** With `true`, a newer
  release could cancel an in-progress recreate's fan-out swap (killing `ci-deploy.sh`
  mid-`docker run` widens a 521 window) or cancel a mid-apply `terraform apply` (R2 state
  risk). The drift-guard asserts `false` on every copy.
- **Do NOT add the routine `apply` job to `web-1-swap`.** It runs terraform but does not POST
  `/hooks/deploy` (does not swap web-1); adding it would serialize every routine push-release
  behind every routine infra apply (the over-broad trap). The AC2 allow-list guard (total count == 4, named members only) fails if the routine `apply` job — or any unlisted job — is enrolled.
- **Allow-list drift guard, not `head -1`.** The group literal is replicated across 4 jobs in
  3 files; assert each NAMED member + total-count==4 (allow-list, so a deliberate future
  member is a visible allow-list edit while a dropped/stray copy fails loud) — the `head -1`
  un-guard lesson from `2026-07-05-extracted-specialized-shared-script-not-clean-swap-and-parity-blind-spots.md`.
- **Lock-hold-duration is the silent-regression trap (arch P2).** The mutex only serializes
  real swaps because every member POSTs `/hooks/deploy` then POLLS deploy-status to terminal
  (job held across the on-host swap). A future edit making any member fire-and-forget releases
  the mutex in seconds while the swap runs on — overlap silently restored, drift-guard still
  green. The ADR records the invariant; optionally the guard asserts each member has a
  completion-poll step.
- **Four web-1-swap sites, not three (arch P1).** `apply-deploy-pipeline-fix.yml`'s `apply`
  job is the easily-missed 4th site (POSTs `command: deploy web-platform` at `:607`). It is
  already serialized against recreate/warm_standby via the shared workflow-level R2 group but
  NOT against the release deploy — enumerate all four when touching this.
- **`Ref #6060`, not `Closes`.** Items (a) and (b) remain open on #6060; auto-closing at
  merge would false-resolve them (extends `wg-use-closes-n-in-pr-body-not-title-to`).
- Re-run the code-review overlap two-stage `gh --json`/`jq --arg` check at /work after the
  Files list is frozen (never single-stage `gh --jq --arg`).
