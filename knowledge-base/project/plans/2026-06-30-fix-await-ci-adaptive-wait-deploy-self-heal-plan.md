---
date: 2026-06-30
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5795
branch: feat-one-shot-5795-await-ci-contention-self-heal
title: "fix(release): adaptive CI-signal wait for prod deploy gate (await-ci races CI-under-contention)"
---

# Plan: Adaptive CI-signal wait for the prod deploy gate (issue #5795)

> No spec.md exists for this branch (one-shot pipeline, no brainstorm) — `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Overview

The `await-ci` job in `web-platform-release.yml` gates the prod `deploy` job on CI's `test`
aggregator check-run for the pushed SHA. It polls a **fixed** 900s window
(`MAX_ATTEMPTS=90 × INTERVAL_S=10`, `web-platform-release.yml:62-63`) and fail-closes the
deploy if `test` has not concluded `success` by then.

**Root cause (verified against `ci.yml:418`):** the `test` aggregator is a synthetic job with
`needs: [test-webplat, test-bun, test-scripts]` and `if: always()`. GitHub does **not** create
the `test` check-run until those three shards reach a terminal state. Under runner contention
the shards sit `queued`, so `repos/<repo>/commits/<sha>/check-runs` returns **no** check-run
named `test` — `await-ci` logs `status=missing` for the entire 900s (exactly the
2026-06-30 incident log), times out, and the deploy is skipped. The "next release self-heals"
recovery breaks because each consecutive squash-merge loses the **same** race, so no release in
the busy window ever reaches `deploy`; prod stalled ~2.5h on `badacd118`. Manual recovery was
`gh run rerun --failed` after CI-on-main went green.

**The fix is to wait on the real CI signal, adaptively.** `await-ci` already queries
`actions/workflows/ci.yml/runs?head_sha=$SHA` (today only for `total_count` in the fast-fail
path, `web-platform-release.yml:98`). The ci.yml **workflow-run** object is created at trigger
time (`status=queued`) even while the shards — and therefore the `test` check-run — do not yet
exist. So we replace the fixed-900s "missing ⇒ time out" assumption with: **keep waiting as
long as the ci.yml run for this SHA is alive (`status != completed`)**; exit `success` only on
`test` `conclusion=success`; fail-closed the instant the ci.yml run concludes without
`test=success`, or no run registers after the grace, or a raised hard ceiling is hit. Then raise
the job's `timeout-minutes` (currently 20, `web-platform-release.yml:55`) above the new ceiling.

**Scope of the fix (honest framing — load-bearing).** Adaptive-wait **restores per-release
self-heal for the observed case**: each release now waits for *its own* CI signal and deploys
its own SHA once green, with no dependence on a later release and no manual `rerun`. It does
**not** make deploy structurally self-healing for the case where CI legitimately runs *longer
than the ceiling* — any single-shot `needs: await-ci` fail-closed gate has a cliff at whatever
ceiling you pick; adaptive **widens and defers** that cliff (≈15m → ≈60m, only when CI is
provably still alive) rather than removing it. Removing the cliff entirely requires deploying
off a `workflow_run: completed` event (issue #5795 option 3) — a topology change deferred to a
tracking issue (see Deferred Scope). This plan ships the minimal robust fix first, per the
`single-user incident` brand threshold.

Two adjacent risks the longer wait **amplifies** are pulled into scope because shipping the
longer ceiling without them would create new silent-regression windows (CTO advisory):

- **Migrate ordering (Phase B).** `migrate` is `needs: release` only (`web-platform-release.yml:110`)
  — it is NOT gated on `await-ci`, so migrations apply to the prod DB even while the deploy is
  gated. A longer adaptive wait widens the window in which prod runs OLD app code against a NEW
  schema (and applies migrations for a SHA whose CI may yet fail-closed). Gate `migrate` on
  `await-ci` so migrations only apply for a CI-green SHA.
- **Out-of-order / superseded deploy (Phase C).** Longer waits make more releases' `deploy` jobs
  overlap on the `deploy-web-platform` concurrency lock (`cancel-in-progress: false`,
  `web-platform-release.yml:310-311`), which serializes but does not guarantee newest-wins. An
  older release's deploy can run *after* a newer one, rolling prod back to an older build — and
  the `build_sha == github.sha` health gate (`web-platform-release.yml:549`) verifies the
  *older* build deployed and passes **silently**. Add a conservative superseded-SHA guard.

## Premise Validation

- Issue **#5795** OPEN; cited references resolve: **#5786** CLOSED, **PR #5787** exists, **#5752**
  MERGED (distinct: admin-bypass skip, not contention). No stale premise.
- Cited mechanism verified in code (not paraphrased): `await-ci` job + fixed `MAX_ATTEMPTS/INTERVAL_S`
  loop (`web-platform-release.yml:48-107`); `test` aggregator `needs:[…shards]` + `if: always()`
  (`ci.yml:418-436`) confirms the check-run is absent until shards finish — the exact
  `status=missing` mechanism in the incident log.
- ADR-corpus grep for the mechanism: the original gate (#5052 / PR #5051,
  `2026-06-08-feat-cd-deploy-ci-gate-and-build-cache-plan.md`) shipped with **no ADR**; the
  *deploy* poll-ceiling changes WERE recorded as ADR-068 because raising a ceiling introduced a
  named trade-off. Adaptive await-ci introduces a structurally identical named trade-off →
  warrants an ADR (see Architecture Decision section). Not a rejected-alternative collision.

## Research Reconciliation — Issue claim vs. Codebase

| Issue / candidate-fix claim | Codebase reality (verified 2026-06-30) | Plan response |
|---|---|---|
| "raise/adapt the await-ci timeout" (option 1) | Bare raise makes every genuinely-red-CI release burn the full new ceiling before deploy skips. | Reject bare option 1. Adopt **adaptive**: a raised ceiling is only safe *because* fail-closed fires the instant the ci.yml run concludes non-success. |
| "auto-retry the gate: re-dispatch once CI test terminal" (option 2) | `gh run rerun --failed` re-POSTs to `/hooks/deploy`; if the prior deploy is in-flight it collides with `ci-deploy.sh`'s `flock -n` (learning `2026-04-17-align-ci-poll-windows…`). The `Pre-rerun lock probe` (`web-platform-release.yml:312`) exists precisely to guard this. | Adaptive-wait **subsumes** option 2's intent (wait for the real CI signal) without a re-dispatch and without the flock collision. |
| "trigger deploy off `workflow_run: completed`" (option 3) | Most robust — no fixed ceiling, no held runner — but a topology change: `workflow_run` runs the default-branch workflow version, fires on every ci.yml completion (needs `head_branch==main && conclusion==success && head_sha` filtering), and loses the current `max(build,CI)` parallelism unless build/deploy are restructured. `workflow_dispatch` does not populate `github.event.workflow_run.*` (learning `2026-03-05-…gh-cli-pitfalls`). | **Defer** to a tracking issue. Option 3 is the path to true >ceiling self-heal AND structurally fixes Phase B/C; not required to fix the incident. |
| `test` is the gate signal | `test` is the required-context name on branch-protection ruleset 14145388 and the synthetic aggregator's required name (`ci.yml:396-418`). Do NOT rename. | Keep polling the `test` check-run for the success/fail verdict; use the ci.yml **run** status only for the adaptive "is CI still alive" liveness. |
| Merge-queue interaction | Repo adopted `merge_group` (commit b29e331c3); CI runs on ephemeral `gh-readonly-queue/main/*` refs, then ci.yml re-runs on the `push:[main]` merged SHA (`ci.yml` push-trigger, unconditional). | `await-ci` polls `github.sha` (the merged main SHA), whose own ci.yml run exists — no change needed, but encode `event=="push"` run filtering (Phase A edge case). |

## User-Brand Impact

**If this lands broken, the user experiences:** a stale production app — prod frozen on an old
build (missing the merged fix/feature they were told shipped), the exact 2.5h-stall symptom of
#5795; **or**, if the gate regresses to fail-**open**, untested/broken code reaching prod (a
semantically-broken `main` that compiles and returns health 200s but is logically broken).

**If this leaks, the user's workflow is exposed via:** N/A — no data surface; this is a CD-gate
timing change. The exposure axis here is *availability/correctness of the deployed build*, not
data confidentiality.

**Brand-survival threshold:** single-user incident. (Carried forward from the original gate,
which shipped at this threshold: `2026-06-08-feat-cd-deploy-ci-gate-and-build-cache-plan.md`
frontmatter `brand_survival_threshold: single-user incident`.) A single broken deploy — silent
rollback or fail-open — is a user-visible product incident. → `requires_cpo_signoff: true`;
`user-impact-reviewer` runs at review-time.

## Hypotheses

The `timeout` substring in the issue triggers the Network-Outage Hypothesis gate (plan Phase 1.4).
The four L3→L7 layers are **N/A here** and the root cause is established, not hypothesised:

| Layer | Verified? | Finding |
|---|---|---|
| L3 firewall allow-list | N/A | No affected host. CI runs on GitHub-hosted runners; the gate calls the GitHub REST API, not a Hetzner host. No `hcloud firewall` surface. |
| L3 DNS / routing | N/A | No hostname resolution involved; `api.github.com` reachability was never in question (the API returned data; it returned `status=missing` *correctly* because the check-run did not yet exist). |
| L7 TLS / proxy | N/A | No HTTPS endpoint under test; not a Cloudflare/CDN path. |
| L7 service layer | **Root cause** | GitHub **runner-queue contention** delayed the `test` aggregator's shards; the synthetic `test` check-run is not created until shards finish, so `await-ci` saw `missing` for the full fixed 900s. This is a queueing-latency/timeout-sizing bug, NOT a connectivity outage. The `hr-ssh-diagnosis-verify-firewall` hard rule (SSH/firewall-first ordering) therefore does not apply — no SSH/firewall hypothesis is being proposed. |

## Implementation Phases

### Phase A — Adaptive CI-signal wait (the core fix) — `web-platform-release.yml` `await-ci` step

Rewrite the poll loop. **Preserve** the existing fail-closed posture, the cancelled-shadow
check-run selector (`select(.conclusion!="cancelled")|sort_by(.started_at)|last`,
`web-platform-release.yml:83`), and the 60s grace + zero-run fast-fail
(`web-platform-release.yml:97-102`). Changes:

1. **Top of every iteration: read the `test` check-run verdict FIRST.** If
   `status=completed && conclusion=success` → `exit 0`. If `status=completed && conclusion != success`
   → fail-closed `exit 1` (log the conclusion). This makes `test=failure`-while-CI-still-running
   fail fast instead of waiting out the ceiling. (spec-flow P1 "happy-path ordering".)
2. **Replace the fixed-window timeout with ci.yml-run liveness.** When `test` is `missing`/queued/
   `in_progress`, query `actions/workflows/ci.yml/runs?head_sha=$SHA&event=push&per_page=20`,
   select the run with max `created_at` (do NOT blind-index `[0]`), read `.status` + `.conclusion`:
   - **`status != completed`** (covers `queued`, `in_progress`, `waiting`, `requested`, `pending`
     — use a **blocklist** `!= completed`, NEVER an allowlist of two states; spec-flow **P0**):
     keep waiting (subject to the hard ceiling).
   - **`status == completed`** with the `test` check-run not yet `success`: enter a **bounded
     post-completion reconciliation grace** (re-poll the `test` check-run `RECONCILE_ATTEMPTS`
     times, e.g. 6×10s) to absorb run-completion→check-run eventual-consistency lag. Proceed only
     on observed `test=success`; fail-closed only after the grace expires with `test` still
     absent/non-success (covers ci `cancelled`/`timed_out`/`skipped`/`action_required`). spec-flow
     **P0** "green build blocked by check-run lag" + **P1** "completed/action_required emit
     operator-actionable message".
3. **Keep the 60s grace + `total_count==0` zero-run fast-fail**, but only act on a **successful**
   API response — a transient `gh api` 5xx/secondary-rate-limit/network error must `continue`
   (retry), never be parsed as `total_count==0` and never abort the job under `set -e` (mirror the
   existing check-runs retry guard at `web-platform-release.yml:77-80`). spec-flow **P1** API-error
   conflation; guard `jq '.workflow_runs[0]'` `null` by branching on array length / `total_count`
   first. spec-flow **P2**.
4. **Stale re-run reconciliation:** ignore a `test` check-run older than the selected run's
   `run_started_at` (API re-runs reuse the `workflow_run` id with a new `run_attempt`, so the run
   object does not distinguish attempts — only the check-run timestamp does). spec-flow **P1**.
5. **Raise the ceiling + the job timeout together** (Sharp Edge: never raise an attempt budget
   without raising `timeout-minutes`). Propose `MAX_ATTEMPTS=300`, `INTERVAL_S=10` → 3000s = 50m
   hard ceiling **bounded by ci.yml-run liveness** (we only approach it while CI is provably
   `!= completed`); set the job `timeout-minutes` ≥ ceiling + one `INTERVAL_S` + API-retry budget
   (propose `55`). The in-bash ceiling branch MUST win the race against `timeout-minutes` so its
   diagnostic `::error::` always emits (spec-flow P0/config — a bare GitHub job-kill reproduces the
   "silent skip, no signal" symptom). **/work MUST measure the realistic worst-case** before
   freezing 300/55: pull recent CI-under-contention durations
   (`gh run list --workflow=ci.yml --branch main --limit 50 --json createdAt,updatedAt,conclusion`)
   and size the ceiling to exceed observed p100 with margin (learning
   `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`). The 50m figure is the
   plan's starting estimate, not a frozen constant.

### Phase B — Gate `migrate` on `await-ci` — `web-platform-release.yml` `migrate` job

Add `await-ci` to `migrate`'s `needs` and require its success (mirroring `deploy`'s existing
push-vs-dispatch tolerance at `web-platform-release.yml:299-301`), so migrations only apply for a
CI-green SHA and never run ahead of a fail-closed gate:

- `needs: [release, await-ci]` (was `needs: release`, `web-platform-release.yml:110`).
- `if:` AND-in: `(needs.await-ci.result == 'success' || (github.event_name == 'workflow_dispatch'
  && needs.await-ci.result == 'skipped'))` — preserving the existing `version != ''` and
  `skip_deploy` clauses. On `workflow_dispatch`, `await-ci` is skipped (`if: github.event_name ==
  'push'`, `web-platform-release.yml:49`) and tolerated, exactly as `deploy` already does.
- Net time-to-prod is unchanged: `deploy` already waits on `await-ci`, so moving `migrate` to run
  *after* CI-green (instead of in parallel with the build) adds no critical-path latency while
  removing the old-code-vs-new-schema and migrate-for-a-red-SHA windows. Document the trade-off
  (loses `migrate || build` parallelism; gains correctness) in the job comment.

### Phase C — Superseded-SHA guard in `deploy` (conservative) — `web-platform-release.yml` `deploy` job

Before the deploy POST, add a read-only guard step that fail-closes-to-skip **only when a
strictly-newer release SHA exists** on `main`, so an older release whose `deploy` won the
concurrency lock late does not roll prod back:

- Compute the latest released SHA: `git rev-list -1 $(git describe --tags --match 'web-v*'
  --abbrev=0 origin/main)` or, more directly, compare `github.sha` against `git rev-parse
  origin/main`. If `github.sha` is an **ancestor of** `origin/main` AND `origin/main != github.sha`
  (a newer `apps/web-platform/**` release exists), **skip the POST** with a `::warning::`
  ("release `<sha>` superseded by `<newer>` — newer release deploys; skipping to avoid rollback").
- Conservatism requirement: the guard must skip **only** on a proven strictly-newer release; any
  ambiguity (tag-read failure, equal SHA) → proceed (do NOT introduce a new silent-skip class —
  the very symptom #5795 is about). Guard is GET/`git`-only, no prod write.
- **Descope valve:** if plan-review judges Phase C blast-radius too high for this PR, move it to the
  option-3 tracking issue (option 3 carries the authoritative SHA on the event and fixes
  out-of-order structurally). Record the decision in the PR body. Phase A + B are the non-negotiable
  core; Phase C is should-have.

### Phase D — ADR + (no) C4 — see Architecture Decision section. In-scope deliverable.

### Phase E — Observability — see Observability section. Elapsed annotations + contention `::warning::`.

## Files to Edit

- `.github/workflows/web-platform-release.yml` — Phase A (`await-ci` step rewrite + `timeout-minutes`),
  Phase B (`migrate` `needs`/`if`), Phase C (`deploy` superseded-SHA guard step), Phase E
  (elapsed-time log annotations + cross-old-900s `::warning::`).
- `knowledge-base/engineering/architecture/decisions/ADR-072-adaptive-ci-signal-wait-for-deploy-gate.md`
  — **new** (verify next-free ordinal at write time; highest current is ADR-071 and the corpus has
  duplicate ordinals, so `git ls-files | grep ADR-072` before naming). See Architecture Decision.

## Files to Create

- The ADR file above (via `/soleur:architecture`).
- No new workflow, script, or test-runner files. (Verification is via existing `actionlint` +
  extracted-snippet `bash -c` per Test Scenarios; no new test framework — none is installed for
  workflow YAML.)

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (Phase A — adaptive liveness):** in the `await-ci` step, the "missing/queued/in_progress"
  branch reads `actions/workflows/ci.yml/runs?head_sha=$SHA` and treats `status != completed` as
  keep-waiting. Verify: `grep -n 'workflow_runs' .github/workflows/web-platform-release.yml`
  returns ≥1 hit inside the `await-ci` step, AND the status comparison is a `!= "completed"`
  blocklist form (grep for `!= "completed"` / `!= completed`), NOT an allowlist of `queued|in_progress`.
- **AC2 (Phase A — happy path first):** the `test` `conclusion=success → exit 0` and
  `conclusion != success → exit 1` checks are evaluated at the **top** of each loop iteration
  (before the ci-run-liveness branch). Verify by reading the step: the success/fail `exit` lines
  precede the `workflow_runs` query in the loop body.
- **AC3 (Phase A — reconciliation grace):** a bounded post-completion re-poll exists for the
  "ci.yml run completed but `test` check-run not yet success" race (a named `RECONCILE_ATTEMPTS`
  env/loop). Verify: `grep -nE 'RECONCILE|reconcil' .github/workflows/web-platform-release.yml`
  returns a hit.
- **AC4 (Phase A — fail-closed preserved):** the only `exit 0` in the step is guarded by
  `conclusion == "success"`. Verify: every `exit 0` line in the `await-ci` step is within a
  `conclusion`=`success` branch (read the step; there must be exactly one `exit 0`).
- **AC5 (Phase A — ceiling < timeout):** the job `timeout-minutes` (minutes) strictly exceeds
  `MAX_ATTEMPTS × INTERVAL_S` (seconds) ÷ 60 plus one interval. Verify arithmetic from the
  literal env values in the step + the job `timeout-minutes` line.
- **AC6 (Phase A — API-error not a false zero-run):** the `total_count==0` fast-fail only fires on
  a successful API response; a failed `gh api` call `continue`s. Verify by reading the step: the
  runs-query has an `if ! resp=$(gh api …)` retry guard analogous to the check-runs guard.
- **AC7 (Phase B — migrate gated on await-ci):** `migrate.needs` contains `await-ci` and
  `migrate.if` requires `await-ci` success-or-(dispatch∧skipped). Verify:
  `awk '/^  migrate:/{f=1} f&&/needs:/{print; exit}' .github/workflows/web-platform-release.yml`
  shows `await-ci`, and the `if:` contains `needs.await-ci.result == 'success'`.
- **AC8 (Phase B — dispatch tolerance):** `workflow_dispatch` still reaches `migrate`
  (await-ci skipped is tolerated) — the `if:` mirrors the `deploy` job's existing
  `(github.event_name == 'workflow_dispatch' && needs.await-ci.result == 'skipped')` clause.
- **AC9 (Phase C — superseded guard, if not descoped):** the `deploy` job has a read-only step
  that skips the POST only when `origin/main` has a strictly-newer `apps/web-platform/**` release
  SHA; on any ambiguity it proceeds. Verify by reading the step (or: PR body records Phase C
  descoped to the option-3 issue).
- **AC10 (Phase E — observability):** each `await-ci` poll log line includes an elapsed-seconds
  field, and a `::warning::` is emitted when elapsed crosses the prior 900s threshold (contention
  made visible). Verify: `grep -nE 'elapsed|::warning::' .github/workflows/web-platform-release.yml`
  returns hits in the `await-ci` step.
- **AC11 (Phase D — ADR):** `ADR-072-*.md` (or next-free ordinal) exists with `## Decision`,
  `## Alternatives Considered` (listing options 1/2/3 with why-not), and `## Consequences` naming
  the held-runner trade-off + the deferred option-3 + the migrate-gating decision. Verify:
  `test -f` the file and `grep -c '^## ' <file>` ≥ 3.
- **AC12 (YAML + shell validity):** `actionlint .github/workflows/web-platform-release.yml` passes,
  and the extracted `await-ci` `run:` body passes `bash -n` via `bash -c "$(…extracted…)"` (do NOT
  run `bash -n` on the `.yml` file directly — it parses YAML as bash). See Sharp Edges.
- **AC13 (Open Code-Review Overlap):** #3220 (postmerge trigger verification) is acknowledged as
  out-of-scope and remains open (different concern — post-apply verification, not gate timing).

### Post-merge (operator / automated)

- **AC14 (Ref not Closes):** PR body uses `Closes #5795` (this IS a code change that fully fixes
  the bug at merge — not an ops-remediation; `Closes` is correct here).
- **AC15 (deferred-scope tracking issue):** a tracking issue for option 3 (`workflow_run: completed`
  deploy trigger) exists, labeled `domain/engineering` + `type/chore` + `priority/p3-low`, with
  re-evaluation criteria (see Deferred Scope). Verify: `gh issue view <n>` after creation.
- **AC16 (live self-heal verification — read-only):** after the next real CI-under-contention
  squash-merge, `gh run view <release-run-id> --job await-ci` shows `await-ci` *waited past 900s
  and then succeeded* (deploy proceeded) rather than timing out — confirming the adaptive wait. No
  synthetic prod writes; read-only `gh` observation only.

## Open Code-Review Overlap

1 open scope-out touches this file: **#3220** (postmerge verification that trigger-bearing
migrations land in prd). **Disposition: Acknowledge** — different concern (post-apply catalog
verification vs. gate timing). Phase B changes *when* `migrate` runs, not whether its results are
verified, so there is no conflict and no fold-in. #3220 remains open.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Adaptive-wait is the right call now (strictly better than option 1; subsumes
option 2) and is a ~15-line bash change to an existing job. Strongest objection (real, not
disqualifying): the wait holds one idle GitHub-hosted runner up to the ceiling, adding one unit of
the very contention it waits on — this is exactly what option 3 eliminates and is the reason
option 3 stays the documented long-term target; not disqualifying because it is a single idle slot
(not a build) and the observed pool is not repo-saturated. Two amplified risks pulled into scope:
**migrate ordering (HIGH)** → Phase B gates `migrate` on `await-ci`; **out-of-order/superseded
deploy (MED-HIGH)**, where the `build_sha==github.sha` health check silently passes on the older
build → Phase C guard. Wrong-run selection (LOW-MED) mitigated by `event==push` + max-`created_at`
selection. CTO recommends a lightweight ADR (ADR-068 precedent: a raised ceiling with a named
trade-off was recorded) and option-3 as a deferred tracking issue. Edge cases folded into Phase A
ACs (blocklist not allowlist; reconciliation grace; API-retry; ceiling<timeout).

### Product/UX Gate

Skipped — **Product NONE.** Files-to-Edit are `.github/workflows/web-platform-release.yml` + an
ADR `.md`; no UI-surface path (no `components/**`, `app/**/page.tsx`, etc.) per the mechanical
UI-surface override. This is CD-orchestration tooling, not a user-facing surface.

**Brainstorm-recommended specialists:** none (no brainstorm; one-shot pipeline).

## Architecture Decision (ADR/C4)

This plan changes a fail-closed deploy-gate **timing semantic** (fixed window → adaptive on the
real CI signal) and introduces a named trade-off (held-runner contention; >ceiling cliff deferred).
Per `wg-architecture-decision-is-a-plan-deliverable` and the ADR-068 precedent (a raised deploy
ceiling with a named trade-off was recorded as an ADR), this warrants an ADR — a future maintainer
would otherwise "optimize" the ceiling back down. The ADR write is an in-scope task of THIS plan,
not a follow-up.

### ADR

- **Create `ADR-072` "Adaptive CI-signal wait for prod deploy gate"** via `/soleur:architecture`
  (verify next-free ordinal at write time — highest current is ADR-071 and the corpus contains
  duplicate ordinals; `git ls-files | grep -i ADR-072` before naming). `## Decision`: wait on
  ci.yml-run liveness + `test` conclusion, fail-closed, raised adaptive ceiling. `## Alternatives
  Considered`: option 1 (bare raise — unsafe), option 2 (auto-retry — flock collision), option 3
  (`workflow_run` — deferred, the true >ceiling self-heal). `## Consequences`: held-runner
  trade-off; migrate-gating; out-of-order guard; the residual >ceiling cliff and its deferral.

### C4 views

**No C4 impact.** Verified against all three model files (`model.c4`, `views.c4`, `spec.c4`):
the actors/systems involved are already modeled — `github` system ("Source control, CI/CD … and
releases", `model.c4:200-203`, `#external`) and the `engine -> github "Git operations and CI"`
edge (`model.c4:240`); the deploy-serving edge is `cloudflare -> webapp "Tunnel, DNS, CDN"`
(`model.c4:241`). Enumerated for this change: (a) external human actors — none (no
correspondent/reviewer/recipient changes); (b) external systems/vendors — GitHub CI/CD (already
modeled), no new vendor; (c) containers/data-stores — none touched (the prod DB `migrate` edge is
unchanged in topology; only its *ordering* relative to await-ci changes, which is not a C4-level
relationship); (d) actor↔surface access relationships — unchanged. A poll-loop timeout semantic is
an internal implementation detail below C4 element granularity. → `### C4 views: none` is supported
by the enumeration above; no `.c4` edit, no view-include change.

### Sequencing

The decision is true on merge (no soak-gated later slice). ADR status `accepted` at write.

## Observability

The #5795 recovery was "silent + manual" — making contention visible IS part of the fix. This is
a workflow-file change (not under `apps/*/server|src|infra` or `plugins/*/scripts`), so the
Phase-2.9 schema is provided as good practice; the discoverability test is `gh`-based, never SSH.

```yaml
liveness_signal:
  what: "await-ci job conclusion per release run; emits an elapsed-seconds field on every poll line and a ::warning:: when elapsed crosses the prior 900s threshold (CI-under-contention made visible)"
  cadence: "per push to main touching apps/web-platform/**"
  alert_target: "GitHub Actions run UI + the existing CI Slack/Sentry notification on a failed release run; a fail-closed await-ci already surfaces as a red required job"
  configured_in: ".github/workflows/web-platform-release.yml (await-ci step)"
error_reporting:
  destination: "GitHub Actions ::error:: annotations on the await-ci step (fail-closed paths) + the workflow's existing failure notification"
  fail_loud: true   # every fail-closed path emits a distinct ::error:: with the terminal conclusion / reason; no bare job-kill (ceiling < timeout-minutes guarantees the diagnostic emits)
failure_modes:
  - mode: "CI under contention slower than the adaptive ceiling"
    detection: "await-ci ::error:: 'Timed out after <ceiling>s while ci.yml run still in_progress'"
    alert_route: "red await-ci job on the release run → existing release-failure notification"
  - mode: "CI concluded non-success (test failure / cancelled / timed_out)"
    detection: "await-ci ::error:: with the terminal conclusion logged"
    alert_route: "red await-ci job"
  - mode: "no ci.yml run for the SHA after grace (CI skipped/never triggered)"
    detection: "await-ci ::error:: 'No ci.yml run for <sha> after grace'"
    alert_route: "red await-ci job"
  - mode: "deploy superseded by a newer release (Phase C)"
    detection: "deploy ::warning:: 'release <sha> superseded by <newer>; skipping to avoid rollback'"
    alert_route: "step-summary warning on the older release run"
logs:
  where: "GitHub Actions run logs for web-platform-release.yml (await-ci + deploy steps)"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: "gh run view <release-run-id> --job await-ci   # shows elapsed-annotated polls + the contention ::warning:: / fail-closed ::error::"
  expected_output: "On a contention-delayed-but-recovered release: poll lines past 900s elapsed, then 'CI test passed … deploy may proceed.' On a true ceiling timeout: the ::error:: line with the reason. NO ssh."
```

## Risks & Mitigations

- **Adaptive widens but does not remove the cliff (spec-flow P1).** CI legitimately > ceiling →
  fail-closed → deploy deferred; sustained contention beyond the ceiling re-creates the original
  race class at 50m instead of 15m. *Mitigation:* ceiling sized to observed p100+margin (Phase A
  step 5 measurement); true structural self-heal deferred to option-3 issue (AC15). Framed plainly
  in Overview — this is a deferral, not a silent gap.
- **Held-runner contention (CTO §1).** await-ci holds one idle runner up to the ceiling under the
  same contention it waits on. *Mitigation:* single idle slot, not a build; option 3 removes it
  entirely (deferred). Accepted + documented in the ADR `## Consequences`.
- **Out-of-order / silent rollback (CTO §2, MED-HIGH).** Amplified by longer waits. *Mitigation:*
  Phase C superseded-SHA guard (conservative, GET-only); option 3 fixes structurally. If Phase C
  is descoped, the risk is named in the PR body + the option-3 issue.
- **Migrate runs ahead of a fail-closed gate (CTO §2, HIGH).** *Mitigation:* Phase B gates migrate
  on await-ci; no net critical-path cost.
- **Wrong ci.yml run picked for a SHA (CTO §2, LOW-MED).** *Mitigation:* filter `event==push`,
  select max `created_at`; squash-merge mints a fresh SHA so multiplicity is low.
- **Bash edge cases silently fail-open/closed (spec-flow).** *Mitigation:* blocklist `!= completed`
  (P0), reconciliation grace (P0), top-of-loop `test` verdict (P1), API-retry (P1),
  null-array guard (P2), stale-check-run timestamp reconciliation (P1) — all folded into Phase A
  ACs and the Test Scenarios.

## Test Scenarios

Workflow logic is bash; no test framework is installed for workflow YAML, so verification is
static + extracted-snippet execution (do not introduce bats/pytest):

1. `actionlint .github/workflows/web-platform-release.yml` — YAML + job-graph valid.
2. Extract the `await-ci` `run:` body and run `bash -n` on it via `bash -c "$(extracted)"` (NOT on
   the `.yml`); optionally `shellcheck` the extracted snippet.
3. **Dry-run the loop logic** against synthesized API fixtures (jq over hand-written JSON, no live
   API): assert the branch decisions for each spec-flow case — `status=queued`→wait;
   `status=waiting`→wait (blocklist); `test completed/success`→exit 0; `test completed/failure`
   while run `in_progress`→exit 1 (top-of-loop); run `completed` + `test` missing→grace then
   fail-closed; run `completed/success` + `test` lagging→grace then exit 0; `gh api` error→retry
   not zero-run; empty `workflow_runs` array→guarded.
4. Arithmetic assertion: `timeout-minutes*60 > MAX_ATTEMPTS*INTERVAL_S + INTERVAL_S`.

## Deferred / Optional Scope

- **Option 3 — deploy off `workflow_run: completed` on ci.yml (tracking issue, AC15).** The true
  structural fix for >ceiling self-heal: no fixed ceiling, no held runner, and it carries the
  authoritative SHA on the event (fixing Phase B/C structurally if migrate/deploy are re-homed
  under the trigger). Deferred because it is a topology change against a `single-user incident`
  threshold; ship the minimal robust fix first. **Re-evaluation criteria:** revisit if a real
  CI-under-contention event exceeds the adaptive ceiling post-merge, or when CI shard count/runtime
  grows enough that the ceiling needs another bump. Milestone: Post-MVP / Later (#6).
- **Phase C descope valve** (if plan-review pulls it): fold the superseded-SHA guard requirement
  into the option-3 issue.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled
  (threshold `single-user incident`, concrete artifact + N/A-with-reason exposure axis).
- **`bash -n` on a `.yml` file parses the YAML header as bash and fails spuriously** — always
  extract the `run:` snippet and `bash -c` it. `actionlint` validates the workflow; do NOT
  `actionlint` a composite-action file (this is a workflow, so actionlint is correct here).
- **`await-ci` status handling must use a blocklist (`!= completed`), not an allowlist** of
  `queued|in_progress` — GitHub run `status` also includes `waiting`/`requested`/`pending`; an
  allowlist dead-ends on those (spec-flow P0).
- **The reconciliation grace is load-bearing for green builds:** without it, the first iteration
  after ci flips to `completed/success` can see the `test` check-run not-yet-surfaced and
  instant-fail-close a healthy build (spec-flow P0). It is a *bounded* re-poll, not an unbounded
  wait.
- **ADR ordinal collision:** the corpus has duplicate ordinals (two ADR-033, two ADR-068); `git
  ls-files | grep -i ADR-072` before naming and bump if taken.
- **Verify the ceiling against live CI durations at /work time**, do not freeze 300/55 from this
  plan's estimate (learning `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`).

## Relevant Learnings

- `knowledge-base/project/learnings/best-practices/2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md`
  — exact pattern: under contention CI sits queued, await-ci times out, deploy skips; poll the
  workflow RUN, not the missing check-run.
- `knowledge-base/project/learnings/2026-06-08-ci-gate-fail-open-traps-skip-token-grep-and-buildkit-cache-mode.md`
  — fail-closed discipline; only `exit 0` guarded by `conclusion==success`; verify run never
  registered via `total_count==0`.
- `knowledge-base/project/learnings/best-practices/2026-04-17-align-ci-poll-windows-with-adjacent-steps.md`
  — `MAX_ATTEMPTS×INTERVAL_S` ceiling alignment; `gh run rerun --failed` × in-flight `flock -n`
  collision (argues against option 2's re-dispatch).
- `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`
  — re-measure ceilings against real durations; elapsed-time annotation to catch ceiling drift.
- `knowledge-base/project/learnings/best-practices/2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md`
  — merge-queue synthetic refs; filter `event==push` when selecting the run for `head_sha`.
- ADR-068 (`…-graceful-cron-drain-before-container-swap.md`) — precedent for recording a
  raised-ceiling named trade-off as an ADR.
