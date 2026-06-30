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

## Enhancement Summary

**Deepened on:** 2026-06-30 (6 parallel agents: architecture-strategist, code-simplicity-reviewer,
kieran-rails-reviewer, security-sentinel, observability-coverage-reviewer, GitHub-REST-API
verification; plus prior plan-phase research: repo (self), learnings-researcher, CTO, spec-flow).

### Key improvements applied
1. **Phase C (superseded-SHA guard) REJECTED and deferred** — three reviewers showed it false-skips
   nearly every deploy (`origin/main` advances on every merge), needs a checkout the `deploy` job
   lacks, and reddens the run via step-level `exit 0`; out-of-order is folded into the option-3 issue.
2. **Phase B P0 fix:** `migrate.if` MUST lead with `always() &&` — else a workflow_dispatch-skipped
   `await-ci` auto-skips migrate and ships new code on an un-migrated schema.
3. **Fail-open invariant pinned (AC4):** the ci.yml run `.conclusion` NEVER authorizes `exit 0`;
   only the `test` check-run `conclusion==success` may.
4. **Observability honesty:** the cited "release-failure notification" does not exist; fail-closed
   is pull-only AND the release job sends a *misleading* "released!" — added an in-scope
   `notify-gated` push signal.
5. **AC discipline:** AC10 false-green fixed (file-wide grep matched other jobs → step-scoped +
   distinct token); AC5 worst-case includes reconciliation grace; AC7 adds the `if:`/`always()` greps.
6. **Simplification:** cut the stale-attempt timestamp-reconciliation branch (YAGNI for a fresh-SHA
   incident; existing `sort_by(.started_at)|last` selector retained).

### New considerations discovered
- GitHub run-status enum confirmed (`queued|in_progress|completed|waiting|requested|pending`) →
  `!= completed` blocklist validated; `per_page=1` + `event=push` + `head_sha` filtering confirmed.
- The check-run-timing root cause is undocumented in the REST API → grounded empirically in the
  #5795 incident log; /work to confirm against a live contended run.

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

Two adjacent risks the longer wait **amplifies** are weighed below (deepen-plan multi-agent
review). One is pulled into scope (Phase B); the other is deferred with the risk named.

- **Migrate ordering (Phase B — in scope).** `migrate` is `needs: release` only
  (`web-platform-release.yml:110`) — NOT gated on `await-ci`, so migrations apply to the prod DB
  even while the deploy is gated. A longer adaptive wait widens the window in which prod runs OLD
  app code against a NEW schema (and applies migrations for a SHA whose CI may yet fail-closed).
  Gate `migrate` on `await-ci` (with a leading `always() &&` — see Phase B; without it a
  `workflow_dispatch`-skipped `await-ci` auto-skips migrate and ships new code on an un-migrated
  schema) so migrations only apply for a CI-green SHA.
- **Out-of-order / superseded deploy (DEFERRED to the option-3 issue).** Longer waits make more
  releases' `deploy` jobs overlap on the `deploy-web-platform` concurrency lock
  (`cancel-in-progress: false`, `web-platform-release.yml:310-311`), which serializes but does not
  guarantee newest-wins; an older release's deploy can run *after* a newer one, rolling prod back,
  and the `build_sha == github.sha` health gate (`web-platform-release.yml:549`) verifies the
  *older* build and passes silently. **A guard was considered (a "Phase C") and rejected by
  deepen-plan review** — three independent reviewers (architecture, security, simplicity) showed it
  would (a) false-skip nearly every deploy because `origin/main` advances on every merge, not just
  `apps/web-platform/**`, (b) require a new `actions/checkout` + `fetch-depth: 0` + tag fetch (the
  `deploy` job checks out nothing today), and (c) reintroduce a *new* silent-skip class — the exact
  symptom #5795 is about. Net: it is the wrong tool. The risk is **pre-existing** (the
  `cancel-in-progress: false` non-newest-wins property exists today); the longer wait only widens
  the window. It is fixed *structurally* by option 3 (`workflow_run: completed` carries the
  authoritative SHA), so it is folded into the option-3 tracking issue (Deferred Scope) and named
  in the PR body. Expand/contract migration discipline (Phase B + forward-compatible schemas)
  bounds the blast radius in the interim.

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
   `in_progress`, query `actions/workflows/ci.yml/runs?head_sha=$SHA&event=push&per_page=1`
   (the API returns most-recent-first; `event=push` + `head_sha` filter together — both confirmed
   against the GitHub REST docs), read `.workflow_runs[0].status`:
   - **`status != completed`** (covers `queued`, `in_progress`, `waiting`, `requested`, `pending`
     — the full run-status enum per GitHub REST docs; use a **blocklist** `!= "completed"`, NEVER
     an allowlist of two states, or `waiting`/`requested`/`pending` dead-end; spec-flow **P0**):
     keep waiting (subject to the hard ceiling).
   - **`status == completed`** with the `test` check-run not yet `success`: re-poll the `test`
     check-run a **bounded** few more iterations (a small `RECONCILE_ATTEMPTS`, e.g. 6×10s,
     consumed as ordinary loop iterations — NOT a new unbounded inner loop) to absorb
     run-completion→check-run eventual-consistency lag. Proceed ONLY on a re-observed
     `test=success` from `commits/$SHA/check-runs`; fail-closed once the bounded grace expires with
     `test` still absent/non-success (covers ci `cancelled`/`timed_out`/`skipped`/`action_required`,
     emitting an operator-actionable `::error::` with the terminal conclusion). spec-flow **P0**
     "green build blocked by check-run lag" — without this a healthy build can instant-fail-close.
3. **Keep the 60s grace + `total_count==0` zero-run fast-fail**, but only act on a **successful**
   API response — a transient `gh api` 5xx/secondary-rate-limit/network error must `continue`
   (retry), never be parsed as `total_count==0` and never abort under `set -e` (the current
   `web-platform-release.yml:98` does `|| echo "0"`, which conflates an API failure with a true
   zero-run → a false fail-closed; tighten it to retry, mirroring the check-runs retry guard at
   `web-platform-release.yml:77-80`). Guard `jq '.workflow_runs[0]'` `null` by branching on
   `total_count`/array length first. spec-flow **P1/P2**.
4. **Run selection.** Squash-merge mints a fresh SHA, so a single push-run matches `head_sha`;
   `per_page=1` over the most-recent-first ordering returns it. (The `gh run rerun` re-run race —
   same `run_id`, incremented `run_attempt` — is NOT the incident path; the **existing**
   cancelled-shadow check-run selector `select(.conclusion!="cancelled")|sort_by(.started_at)|last`
   at `web-platform-release.yml:83` is RETAINED and already prefers the newest check-run. A
   dedicated stale-attempt timestamp-reconciliation branch was considered and **cut** as YAGNI for
   this incident — it belongs with option 3, which removes the polling entirely.)
5. **Raise the ceiling + the job timeout together** (Sharp Edge: never raise an attempt budget
   without raising `timeout-minutes`). Propose `MAX_ATTEMPTS=300`, `INTERVAL_S=10` → 3000s = 50m
   hard ceiling **bounded by ci.yml-run liveness** (we only approach it while CI is provably
   `!= completed`); set the job `timeout-minutes` ≥ `(MAX_ATTEMPTS + RECONCILE_ATTEMPTS) × INTERVAL_S`
   ÷ 60 + margin (propose `55`: 3060s worst-case < 3300s). The in-bash ceiling branch MUST win the
   race against `timeout-minutes` so its diagnostic `::error::` always emits (a bare GitHub job-kill
   reproduces the "silent skip, no signal" symptom). **Add an inline YAML comment at the ceiling
   constants** stating "adaptive ceiling — do NOT lower without re-reading ADR-072; bounded by CI
   liveness, not fixed latency" (the load-bearing anti-regression note; the ADR is the rationale,
   the comment is what a future maintainer actually sees). **/work MUST measure the realistic
   worst-case** before freezing 300/55: pull recent CI-under-contention durations
   (`gh run list --workflow=ci.yml --branch main --limit 50 --json createdAt,updatedAt,conclusion`)
   and size the ceiling to exceed observed p100 with margin (learning
   `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`). The 50m figure is the
   plan's starting estimate, not a frozen constant.

> **Root-cause grounding (check-run timing).** The load-bearing assumption — a synthetic
> aggregator job's check-run is not created until its `needs:` shards finish — is **not documented
> in the GitHub REST API reference** (verified). It is grounded **empirically** in the #5795
> incident log: `await-ci` logged `status=missing` for the full 900s while the ci.yml run *existed*
> (it did NOT hit the `total_count==0` fast-fail), which is only possible if the `test` check-run
> was absent while the run was live. /work SHOULD additionally confirm against one real
> contended run (`gh api repos/<repo>/commits/<sha>/check-runs` during a queued window) before
> finalizing.

### Phase B — Gate `migrate` on `await-ci` — `web-platform-release.yml` `migrate` job

Add `await-ci` to `migrate`'s `needs` and require its success, so migrations only apply for a
CI-green SHA and never run ahead of a fail-closed gate:

- `needs: [release, await-ci]` (was `needs: release`, `web-platform-release.yml:110`).
- `if:` **MUST lead with `always() &&`** (mirroring the `deploy` job at `web-platform-release.yml:293`):
  `always() && needs.release.outputs.version != '' && (needs.await-ci.result == 'success' ||
  (github.event_name == 'workflow_dispatch' && needs.await-ci.result == 'skipped')) &&
  (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)`.
  **Why `always()` is load-bearing (deepen-plan architecture P0):** GitHub Actions skips a job when
  any `needs` dependency is *skipped*, BEFORE the `if` expression is evaluated — unless the `if`
  leads with `always()`. On `workflow_dispatch`, `await-ci` is skipped (`if: github.event_name ==
  'push'`, `web-platform-release.yml:49`); without `always()`, `migrate` would auto-skip, the
  dispatch-tolerance clause would never run, `deploy` (which tolerates `migrate==skipped`) would
  still ship, and the operator escape hatch would deploy NEW app code against an UN-migrated schema
  — the more dangerous ordering. With `always()`, the tolerance clause actually evaluates.
- **No fail-open is introduced** (verify at /work): on a `push` with a fail-closed `await-ci`,
  `migrate.if` → false → `migrate` is `skipped`; `deploy` stays blocked because its own `if`
  independently requires `needs.await-ci.result == 'success'` (`web-platform-release.yml:298-299`)
  and merely tolerates `migrate==skipped`. So gating migrate cannot let untested code deploy.
- **Trade-off (corrected — deepen-plan P2):** this serializes `migrate` *after* `await-ci` (today
  it runs concurrently with the wait, both firing off `release`), so in the contention case this PR
  targets, `deploy` start ≈ `await-ci + migrate_runtime` instead of `max(await-ci, migrate)`.
  `migrate` is short (transactional DDL) so the tail cost is small, and the correctness gain
  (no migrate-for-a-red-SHA, no new-schema-ahead-of-old-code on push) is worth it. Document this in
  the job comment — do NOT claim "no net cost."
- **Residual window (named, not closed):** Phase B closes the *red-CI* slice only. A `migrate` that
  applies without a following `deploy` can still occur for a `verify-doppler-secrets` failure
  (`web-platform-release.yml:297`), leaving NEW schema with OLD prod code. This is acceptable under
  standard expand/contract forward-migration discipline (forward-compatible schemas) — state it
  plainly rather than implying Phase B removes the window entirely.

### Phase C — Superseded-SHA guard — REJECTED by deepen-plan review; deferred to the option-3 issue

A conservative "skip the deploy POST when a strictly-newer release SHA exists" guard was designed
and **rejected** by three independent deepen-plan reviewers. Recorded here so /work does NOT
re-introduce it:

- **architecture:** keying on `git rev-parse origin/main` false-skips nearly every deploy —
  `origin/main` advances on every merge (docs/plugins/other apps), but the release workflow only
  triggers on `apps/web-platform/**`; by deploy time an unrelated commit has almost always landed,
  so the guard would skip valid deploys (reproducing the #5795 silent-skip). Keying on the newest
  `web-v*` tag is closer but still non-trivial. Also: a bash `exit 0` in a guard step ends only that
  step, so the two Verify-deploy steps would still poll for the old version → version mismatch →
  RED run + burned ceiling.
- **security + architecture:** the `deploy` job performs **no `actions/checkout`** today (it is
  entirely `curl`/`gh`-API based), so any `git` ancestry/tag logic needs a new checkout with
  `fetch-depth: 0` + tag fetch; without it `origin/main` equals the shallow ref and the guard is a
  **permanent silent no-op** — protective-looking code that never fires.
- **simplicity:** the out-of-order risk is **pre-existing** (today's `cancel-in-progress: false`
  already doesn't guarantee newest-wins); the longer wait only widens the window. Net-new
  deploy-critical-path logic to marginally narrow a pre-existing risk is a poor trade, especially
  one that can itself silent-skip.

→ Folded into the **option-3 tracking issue** (Deferred Scope): `workflow_run: completed` carries
the authoritative SHA on the event and fixes out-of-order *structurally*. Named in the PR body.

### Phase D — ADR + (no) C4 — see Architecture Decision section. In-scope deliverable.

### Phase E — Observability + fail-closed notification — see Observability section. Elapsed
annotations + contention `::warning::` + a `notify-gated` push signal (converts the pull-only
fail-closed signal into an operator-visible notification — fixes the "silent" half of #5795).

## Files to Edit

- `.github/workflows/web-platform-release.yml` — Phase A (`await-ci` step rewrite + raised
  `MAX_ATTEMPTS`/`timeout-minutes` + inline anti-regression comment), Phase B (`migrate` `needs`/`if`
  with leading `always()`), Phase E (elapsed-time log annotations in the `await-ci` step + a new
  `notify-gated` job that fires on `await-ci` fail-closed). NOT the `deploy` job (Phase C rejected).
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
  consumed as ordinary loop iterations). Verify: `grep -nE 'RECONCILE|reconcil'
  .github/workflows/web-platform-release.yml` returns a hit (name-only proxy; the *behavior* —
  re-poll then exit only on observed `test=success` — is covered by Test Scenario 3's dry-run).
- **AC4 (Phase A — fail-closed preserved; the load-bearing fail-open invariant):** **every** `exit 0`
  in the `await-ci` step is guarded by the `test` check-run `conclusion == "success"`, AND the
  ci.yml workflow-**run** `.conclusion` is **never** used to authorize `exit 0` (the run object is
  liveness-only; a `run.conclusion==success → exit 0` shortcut would fail-OPEN on a mis-selected
  run or a green run whose `test` aggregation was non-success). Verify by reading the step: enumerate
  every `exit 0` and confirm each is inside a `test … conclusion==success` branch; grep the step for
  any `exit 0` reached from a `.workflow_runs[…].conclusion` read (must be none). (Replaces the
  earlier "exactly one exit 0" count — the two-exit design (top-of-loop + grace) is correct; the
  invariant is the guard predicate, not the count. deepen-plan kieran P1 + security.)
- **AC5 (Phase A — ceiling < timeout, incl. grace):** `timeout-minutes × 60 >
  (MAX_ATTEMPTS + RECONCILE_ATTEMPTS) × INTERVAL_S + INTERVAL_S`, AND there is no unbounded inner
  retry loop (API-error retry consumes a main-loop attempt via `continue`, not an inner `while`).
  Verify arithmetic from the literal env values + the job `timeout-minutes`; read the step to
  confirm no inner unbounded retry. (deepen-plan kieran P1.)
- **AC6 (Phase A — API-error not a false zero-run):** the `total_count==0` fast-fail only fires on
  a successful API response; a failed `gh api` call `continue`s (replacing the current
  `|| echo "0"` at `web-platform-release.yml:98`). Verify: the runs-query has an
  `if ! resp=$(gh api …)` retry guard analogous to the check-runs guard at lines 77-80.
- **AC7 (Phase B — migrate gated on await-ci, with `always()`):** `migrate.needs` contains
  `await-ci`; `migrate.if` **leads with `always() &&`** AND contains
  `needs.await-ci.result == 'success'` AND the dispatch-tolerance clause. Verify (inline `needs`
  form is prescribed at Files-to-Edit):
  `awk '/^  migrate:/{f=1} f&&/needs:/{print; exit}'` shows `await-ci`;
  `awk '/^  migrate:/{f=1} f&&/if:/{print; exit}'` (or read the block) shows a leading `always()`;
  `grep -F "needs.await-ci.result == 'success'" .github/workflows/web-platform-release.yml` returns
  a hit in the migrate block. (awk confirmed non-self-matching — two independent rules, `^  migrate:`
  anchor excludes `verify-migrations:`/`migrate-*`.)
- **AC8 (Phase B — no fail-open chain, explicit):** on a `push` fail-closed `await-ci`, `migrate`
  resolves to `skipped` and `deploy` stays blocked via its OWN `needs.await-ci.result == 'success'`
  requirement (`web-platform-release.yml:298-299`) while tolerating `migrate==skipped` — so gating
  migrate introduces no path where untested code deploys. On `workflow_dispatch`, `await-ci` skipped
  is tolerated and `migrate` runs (the `always()`-evaluated dispatch clause). Verify by tracing both
  branches against the deploy `if`.
- **AC9 (out-of-order risk — deferred, not guarded):** Phase C is rejected; the PR body NAMES the
  pre-existing out-of-order/superseded-deploy risk and references the option-3 tracking issue
  (AC15) as its structural fix. Verify: PR body contains the named risk + issue link; no
  superseded-guard step was added to `deploy`.
- **AC10 (Phase E — observability, step-scoped not file-wide):** the `await-ci` step emits an
  elapsed-seconds field per poll line and a `::warning::` when elapsed crosses the prior 900s
  threshold. **Verify against the EXTRACTED `await-ci` step body** (the same awk-extract AC12 uses
  for `bash -n`), NOT a file-wide grep — the file already contains `elapsed=`/`::warning::` in the
  `deploy` and `live-verify` jobs, so a whole-file grep is false-green (deepen-plan kieran P0). Use a
  NEW distinct token (e.g. `elapsed_s=` and a literal `past 900s` string) absent elsewhere, and
  assert it appears within the extracted `await-ci` body.
- **AC10b (Phase E — fail-closed notification):** a `notify-gated` job fires on `await-ci`
  fail-closed (`if: always() && needs.await-ci.result == 'failure'`) and posts an operator-visible
  "deploy gated — CI not green for `<sha>`, prod NOT updated" message via the existing notification
  channel. Verify: the job exists with that `if:` and references the notification secret/webhook.
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
(not a build) and the observed pool is not repo-saturated. Two amplified risks were weighed:
**migrate ordering (HIGH)** → Phase B gates `migrate` on `await-ci` (architecture review added the
load-bearing `always() &&` fix — a skipped-need otherwise auto-skips migrate and ships new code on
an un-migrated schema); **out-of-order/superseded deploy (MED-HIGH)** → a guard was designed and
**rejected** by the deepen-plan panel (false-skips nearly every deploy; no checkout in the deploy
job; step-level `exit 0` reddens the run) and **deferred to the option-3 issue**, which fixes it
structurally. Wrong-run selection (LOW-MED) mitigated by `event==push` + `per_page=1`. CTO
recommends a lightweight ADR (ADR-068 precedent: a raised ceiling with a named trade-off was
recorded) and option-3 as a deferred tracking issue. Edge cases folded into Phase A ACs (blocklist
not allowlist; bounded reconciliation grace; API-retry-not-false-zero-run; ceiling+grace<timeout).
Observability review surfaced that fail-closed is pull-only today and the release job sends a
misleading "released!" → Phase E adds a `notify-gated` push signal.

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
  (`workflow_run` — deferred, the true >ceiling self-heal). `## Consequences` MUST record the
  load-bearing invariants deepen-plan surfaced (else a future maintainer silently reintroduces
  them): (i) `migrate.if` leads with `always() &&`; (ii) the ci.yml run `.conclusion` NEVER
  authorizes `exit 0` (only `test` check-run `conclusion==success`); (iii) held-runner trade-off;
  (iv) corrected serialize-migrate-after-await-ci tail cost; (v) out-of-order + held-runner +
  >ceiling cliff all deferred to option-3 (no Phase-C guard); (vi) fail-closed is pull-only without
  the `notify-gated` job; (vii) the inline ceiling-constant anti-regression comment.

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

**Correction from deepen-plan review:** the original draft cited "the existing CI Slack/Sentry
notification on a failed release run" — that notification **does not exist**. `web-platform-release.yml`
has no `if: failure()`/`workflow_run` notifier; the only Sentry emit is in `live-verify`
(`web-platform-release.yml:598`), gated on `needs.deploy.result == 'success'`, so on EVERY
fail-closed path deploy is skipped → live-verify is skipped → no Sentry event. Worse, the `release`
job's "v0.X.Y released!" Slack/email (`reusable-release.yml:639,657`) fires on release-job success
**independent of** `await-ci`, so a fail-closed gate sends a *misleading* "released!" while prod is
frozen. Therefore Phase E adds a real **`notify-gated`** push signal; absent that, fail-closed is
pull-only (red job + annotation).

```yaml
liveness_signal:
  what: "await-ci job conclusion per release run; the step emits an elapsed-seconds field (new distinct token, e.g. elapsed_s=) on every poll line and a ::warning:: when elapsed crosses the prior 900s threshold (CI-under-contention made visible); a notify-gated job emits a push notification on fail-closed"
  cadence: "per push to main touching apps/web-platform/**"
  alert_target: "PUSH: notify-gated job posts to the existing notification channel on await-ci fail-closed. PULL: GitHub Actions run UI — fail-closed await-ci is a red required job + ::error:: annotation"
  configured_in: ".github/workflows/web-platform-release.yml (await-ci step + notify-gated job)"
error_reporting:
  destination: "GitHub Actions ::error:: annotations on the await-ci step (every fail-closed path) + the notify-gated push notification"
  fail_loud: true   # every fail-closed path emits a distinct ::error:: with the terminal reason; no bare job-kill (AC5 ceiling < timeout-minutes guarantees the diagnostic emits); notify-gated converts pull-only → push
failure_modes:
  - mode: "CI under contention slower than the adaptive ceiling"
    detection: "await-ci ::error:: 'Timed out after <ceiling>s while ci.yml run still in_progress'"
    alert_route: "red await-ci job + notify-gated push ('deploy gated — prod NOT updated')"
  - mode: "CI concluded non-success (test failure / cancelled / timed_out)"
    detection: "await-ci ::error:: with the terminal conclusion logged"
    alert_route: "red await-ci job + notify-gated push"
  - mode: "no ci.yml run for the SHA after grace (CI skipped/never triggered)"
    detection: "await-ci ::error:: 'No ci.yml run for <sha> after grace'"
    alert_route: "red await-ci job + notify-gated push"
  - mode: "misleading 'released!' announcement on a gated deploy (PRE-EXISTING, surfaced here)"
    detection: "release job posts 'v0.X.Y released!' while await-ci fail-closed and deploy is skipped"
    alert_route: "notify-gated push provides the compensating 'gated — not live' signal; fully gating the announcement on deploy-success is deferred (touches shared reusable-release.yml) — see Risks"
logs:
  where: "GitHub Actions run logs for web-platform-release.yml (await-ci step + notify-gated job)"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: gh api repos/jikig-ai/soleur/actions/workflows/web-platform-release.yml --jq .state
  expected_output: active
  # Pre-merge runnable probe (no ssh, deterministic): confirms the release workflow under change is
  # registered + active so its await-ci/notify-gated observability surface exists. The richer
  # post-merge observation — `gh run view <release-run-id>` showing await-ci elapsed-annotated polls
  # past 900s + contention ::warning:: / fail-closed ::error:: + the notify-gated job result — is the
  # read-only live self-heal verification (AC16), run against the next real CI-under-contention release.
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
- **Out-of-order / silent rollback (CTO §2, MED-HIGH).** Pre-existing (`cancel-in-progress: false`
  is not newest-wins today); amplified by longer waits. *Mitigation:* a superseded-SHA guard was
  designed and **rejected** by deepen-plan review (false-skips nearly every deploy; no checkout in
  the deploy job; reddens the run) — see Phase C. Risk is **named in the PR body** and **folded into
  the option-3 issue**, which fixes it structurally (authoritative SHA on the event). Expand/contract
  migration discipline bounds the interim blast radius.
- **Misleading "released!" on a gated deploy (deepen-plan observability).** The `release` job's
  Slack/email (`reusable-release.yml:639,657`) fires on release-job success independent of
  `await-ci`, so a fail-closed gate sends "v0.X.Y released!" while prod is frozen — worse than dark.
  *Mitigation:* Phase E `notify-gated` job posts a compensating "deploy gated — not live" push.
  Fully gating the announcement on deploy-success touches shared `reusable-release.yml` (all
  components) and is deferred to the option-3 issue / a follow-up.
- **Migrate runs ahead of a fail-closed gate (CTO §2, HIGH).** *Mitigation:* Phase B gates migrate
  on await-ci **with a leading `always() &&`** (without it, a workflow_dispatch-skipped await-ci
  auto-skips migrate and ships new code on an un-migrated schema — architecture P0). Small tail-cost
  (serializes migrate after await-ci); residual `verify-doppler-secrets`-failure window bounded by
  expand/contract discipline.
- **Check-run-timing root cause not in REST docs.** *Mitigation:* grounded empirically in the
  #5795 incident log (`status=missing` for 900s while the ci.yml run existed); /work confirms
  against one real contended run before finalizing.
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
  structural fix; the option-3 issue's scope explicitly INCLUDES three things this PR defers:
  (a) >ceiling self-heal — no fixed ceiling; (b) the held-runner cost — no runner held during the
  wait; (c) the **out-of-order/superseded-deploy** fix — the `workflow_run` event carries the
  authoritative SHA, so migrate/deploy re-homed under it deploy the right SHA in order (subsuming
  the rejected Phase C guard); and (d) consider fully gating the "released!" announcement on
  deploy-success. Deferred because it is a topology change against a `single-user incident`
  threshold; ship the minimal robust fix first. **Re-evaluation criteria:** revisit if a real
  CI-under-contention event exceeds the adaptive ceiling post-merge, if an out-of-order deploy is
  observed, or when CI shard count/runtime grows enough that the ceiling needs another bump.
  Milestone: Post-MVP / Later (#6).

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
- **A file-wide grep AC over a multi-job workflow is false-green.** `web-platform-release.yml`
  already contains `elapsed=`/`::error::`/`::warning::` in the `deploy` and `live-verify` jobs, so a
  whole-file `grep` for those passes even if the `await-ci` step never gets them. Scope AC greps to
  the extracted step body, or assert a NEW distinct token (`elapsed_s=`, `past 900s`) absent
  elsewhere. (deepen-plan kieran P0.)
- **`migrate.if` without a leading `always() &&` ships new code on an un-migrated schema.** A
  `needs:` dep that is *skipped* (await-ci on workflow_dispatch) auto-skips the job BEFORE `if`
  evaluates, unless `if` leads with `always()`. Mirror the `deploy` job. (deepen-plan architecture P0.)
- **A bash `exit 0` in a guard step ends only that step.** A "skip the deploy" guard built as
  `exit 0` leaves later steps in the job running — they'd poll for the old version and redden the
  run. (One of three reasons Phase C was rejected.)
- **The ci.yml run `.conclusion` must NEVER authorize `exit 0`** — it is liveness-only; only the
  re-observed `test` check-run `conclusion==success` authorizes deploy, or a mis-selected/green-run
  fails OPEN. (deepen-plan security.)
- **Verify the ceiling against live CI durations at /work time**, do not freeze 300/55 from this
  plan's estimate (learning `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`).
- **A file-wide grep AC over a multi-job workflow is false-green.** `web-platform-release.yml`
  already contains `elapsed=`/`::warning::` in the `deploy` + `live-verify` jobs, so AC10's check
  MUST extract the `await-ci` step body first (or assert a NEW distinct token) — a whole-file grep
  passes even if the await-ci annotations are never written (deepen-plan kieran P0).
- **A `needs:`-gating change needs `always()` in the `if`.** Adding `await-ci` to `migrate.needs`
  WITHOUT leading `migrate.if` with `always() &&` makes a skipped `await-ci` (workflow_dispatch)
  auto-skip migrate before the tolerance clause runs → deploy ships new code on an un-migrated
  schema. Mirror the `deploy` job's `always() &&` prefix.
- **A bash `exit 0` in a guard step ends only that step.** A would-be deploy guard that "skips the
  POST" leaves the later Verify-deploy steps running → they poll for the wrong version → RED run +
  burned ceiling. Gate the POST AND the verify steps on one output, or model the guard as a `needs`
  job. (Part of why Phase C was rejected.)
- **The ci.yml workflow-RUN `.conclusion` is liveness-only — never an `exit 0` authorizer.** Only
  the `test` check-run `conclusion==success` may authorize deploy; a `run.conclusion==success` shortcut
  fails-OPEN on a mis-selected run or a green run with a non-success `test` aggregation.

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
