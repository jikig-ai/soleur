---
title: Adaptive CI-signal wait for the prod deploy gate
status: accepted
date: 2026-06-30
---

# ADR-072: Adaptive CI-signal wait for the prod deploy gate

- **Deciders:** Jean (operator), CPO sign-off (single-user-incident threshold), CTO agent (mechanism assessment), deepen-plan review (architecture-strategist, code-simplicity-reviewer, kieran-rails-reviewer, security-sentinel, observability-coverage-reviewer)
- **Relates to:** #5795 (this change), #5052 / PR #5051 (the original `await-ci` CI-gate, shipped with no ADR), ADR-078 (precedent for recording a raised-ceiling named trade-off as an ADR), #5752 (admin-merge deploy-skip — distinct: admin-bypass skipping CI entirely)

## Context

`web-platform-release.yml`'s `await-ci` job gates the prod `deploy` cutover on CI's
synthetic `test` aggregator check-run for the pushed SHA. It polled a **fixed** 900s window
(`MAX_ATTEMPTS=90 × INTERVAL_S=10`) and fail-closed the deploy if `test` had not concluded
`success` by then.

**Root cause (verified against `ci.yml:418`):** the `test` aggregator is a synthetic job with
`needs: [test-webplat, test-bun, test-scripts]` and `if: always()`. GitHub does **not** create
the `test` check-run until those shards reach a terminal state. Under runner contention the
shards sit `queued`, so `repos/<repo>/commits/<sha>/check-runs` returns **no** check-run named
`test` — `await-ci` logged `status=missing` for the entire 900s, timed out, and the deploy was
skipped. The documented "next release self-heals" recovery breaks because each consecutive
squash-merge loses the **same** race, so no release in the busy window ever reaches `deploy`.
On 2026-06-30 prod stalled ~2.5h on `badacd118`; recovery was a manual `gh run rerun --failed`
after CI-on-main went green.

The fix must wait on the **real** CI signal rather than a fixed clock. The brand-survival
threshold is `single-user incident` (a broken or stalled deploy is a user-visible product
incident), so it ships the minimal robust fix and defers the larger topology change.

## Decision

Replace the fixed-window timeout with an **adaptive wait on CI-run liveness**, in the
`await-ci` step:

1. **Top of every loop iteration, read the `test` check-run verdict first.** `conclusion ==
   success` → `exit 0`; `completed && conclusion != success` → fail-closed `exit 1`. This makes
   a genuinely-red CI fail fast instead of waiting out the ceiling.
2. **When `test` is missing/queued/in_progress, gate on ci.yml-run liveness.** Query
   `actions/workflows/ci.yml/runs?head_sha=$SHA&event=push`; keep waiting as long as the run
   `status != "completed"` — a **blocklist** over the full run-status enum
   (`queued|in_progress|waiting|requested|pending`), never an allowlist of two states.
3. **Bounded reconciliation grace.** When the ci.yml run reaches `completed` but the `test`
   check-run has not yet surfaced `success`, re-poll a bounded `RECONCILE_ATTEMPTS` (consumed as
   ordinary loop iterations, not a new unbounded inner loop) to absorb
   run-completed→check-run eventual-consistency lag, proceeding **only** on a re-observed
   `test=success` and fail-closing once the grace is spent.
4. **Raised adaptive ceiling, keyed on wall-clock.** `CEILING_S=3000s` (50m) hard ceiling,
   **bounded by ci.yml-run liveness** (we only approach it while CI is provably alive). The
   in-bash ceiling tests `elapsed >= CEILING_S` (real wall-clock), **not** an attempt count, so
   the diagnostic `::error::` is guaranteed to fire before the job `timeout-minutes` hard-kill
   regardless of per-iteration `gh api` latency (an attempt-count ceiling can be out-raced when
   API latency under contention stretches each iteration past `INTERVAL_S` — #5795 review P3).
   `MAX_ATTEMPTS=300` is the loop's iteration backstop; `timeout-minutes` is raised to 60 (3600s),
   ≥20% headroom over `CEILING_S`. Sized above the observed p100 CI-under-contention duration
   (~28m, measured 2026-06-30 over the last 50 main ci.yml runs).
5. **Migrate gated on await-ci (Phase B).** `migrate.needs` gains `await-ci` and its `if` leads
   with `always() &&` so migrations only apply for a CI-green SHA and never run ahead of a
   fail-closed gate.
6. **Fail-closed notification (Phase E).** A `notify-gated` job posts an operator-visible
   "deploy gated — prod NOT updated" Slack message on `await-ci` fail-closed, converting the
   pull-only red-job signal into a push.

Fail-closed posture is unchanged: the gate still defaults to blocking the deploy on any
unresolved CI state.

## Alternatives Considered

- **Option 1 — bare raise of the fixed timeout.** Rejected: a bare raise makes every
  genuinely-red-CI release burn the full new ceiling before the deploy skips. A raised ceiling
  is only safe *because* the adaptive wait fail-closes the instant the ci.yml run concludes
  non-success.
- **Option 2 — auto-retry: re-dispatch the gate once CI `test` reaches terminal.** Rejected:
  `gh run rerun --failed` re-POSTs to `/hooks/deploy`; if a prior deploy is in-flight it
  collides with `ci-deploy.sh`'s `flock -n` (the `Pre-rerun lock probe` exists precisely to
  guard this). Adaptive-wait subsumes option 2's intent (wait for the real CI signal) without a
  re-dispatch and without the flock collision.
- **Option 3 — deploy off `workflow_run: completed` on ci.yml.** The most robust fix (no fixed
  ceiling, no held runner, authoritative SHA on the event) and the structural fix for the
  out-of-order/superseded-deploy risk — but a topology change: `workflow_run` runs the
  default-branch workflow version, fires on every ci.yml completion (needs
  `head_branch==main && conclusion==success && head_sha` filtering), and loses the current
  `max(build, CI)` parallelism unless build/deploy are restructured. **Deferred** to a tracking
  issue; not required to fix the incident.
- **Superseded-SHA guard ("Phase C") on the deploy job.** Designed and **rejected** by
  deepen-plan review: keying on `git rev-parse origin/main` false-skips nearly every deploy
  (origin/main advances on every merge), the `deploy` job performs no `actions/checkout` so any
  git-ancestry logic is a permanent silent no-op, and a step-level `exit 0` guard leaves later
  Verify-deploy steps polling for the wrong version (RED run). The out-of-order risk is
  pre-existing (`cancel-in-progress: false` is not newest-wins today) and is fixed structurally
  by option 3.

## Consequences

Each release now waits for *its own* CI signal and deploys its own SHA once green, with no
dependence on a later release and no manual `rerun` — per-release self-heal is restored for the
observed contention case. It does **not** make deploy structurally self-healing when CI
legitimately runs *longer than the ceiling*: any single-shot `needs: await-ci` fail-closed gate
has a cliff at whatever ceiling is chosen; adaptive **widens and defers** that cliff (≈15m →
≈50m, only while CI is provably alive) rather than removing it. Removing it entirely is
option 3.

Load-bearing invariants a future maintainer MUST preserve (each silently reintroduces a bug if
dropped):

1. **`migrate.if` leads with `always() &&`.** GitHub skips a job when any `needs` dep is
   *skipped* before the `if` evaluates; without `always()`, a `workflow_dispatch`-skipped
   `await-ci` would auto-skip `migrate`, the dispatch-tolerance clause would never run, and
   `deploy` (which tolerates `migrate==skipped`) would ship NEW app code on an UN-migrated
   schema — the more dangerous ordering.
2. **The ci.yml workflow-RUN `.conclusion` NEVER authorizes `exit 0`** — it is liveness-only;
   only the `test` check-run `conclusion==success` may authorize the deploy. A
   `run.conclusion==success` shortcut would fail-OPEN on a mis-selected run or a green run whose
   `test` aggregation was non-success.
3. **Held-runner trade-off.** `await-ci` holds one idle GitHub-hosted runner up to the ceiling
   under the same contention it waits on — accepted because it is a single idle slot (not a
   build) and the pool is not repo-saturated; option 3 removes it entirely.
4. **Migrate is serialized AFTER await-ci** (it used to run concurrently with the wait), so
   under contention deploy-start ≈ `await-ci + migrate_runtime` instead of
   `max(await-ci, migrate)`. The tail cost is small (short transactional DDL); this is NOT a
   "no net cost" change.
5. **Out-of-order/superseded deploy, the held-runner cost, and the >ceiling cliff are all
   deferred to option 3** (no Phase-C guard was added). A residual `migrate`-without-`deploy`
   window remains on a `verify-doppler-secrets` failure, bounded by expand/contract
   forward-migration discipline.
6. **Fail-closed is pull-only without the `notify-gated` job.** The `release` job posts a
   misleading "released!" Slack/email on release-job success independent of `await-ci`;
   `notify-gated` provides the compensating "gated — not live" push. Fully gating the
   announcement on deploy-success touches the shared `reusable-release.yml` and is deferred.
7. **The in-bash ceiling is keyed on wall-clock `elapsed`, not attempt count, and the inline
   ceiling-constant anti-regression comment is load-bearing.** An attempt-count ceiling
   (`attempt >= MAX_ATTEMPTS`) can be out-raced by `gh api` latency under contention, letting the
   GitHub `timeout-minutes` hard-kill fire first — a bare job-kill with no diagnostic, the exact
   silent-skip symptom #5795 is about (#5795 review P3, two independent reviewers concurred). The
   ceiling therefore tests `elapsed >= CEILING_S`, and `timeout-minutes` carries ≥20% wall-clock
   headroom over `CEILING_S`. The ADR is the rationale; the comment at the `CEILING_S`/
   `MAX_ATTEMPTS`/`timeout-minutes` constants is what a future maintainer actually sees — it
   states the ceiling is wall-clock-bounded by CI liveness, not fixed latency, and must not be
   lowered without re-reading this ADR.

8. **`migrate.if`'s leading `always()` widens its run condition on a failed `release` that still
   emitted a non-empty `version`** (previously `needs: release` without `always()` auto-skipped
   migrate on any release failure). This is fail-safe: on the push path `migrate` is still
   backstopped by `needs.await-ci.result == 'success'`, and `deploy` is independently gated by
   `needs.release.outputs.docker_pushed == 'true'`, so no deploy occurs on an un-built image — the
   only residual is a `migrate`-without-`deploy`, inside the expand/contract window named in
   Consequence #5.

Cross-reference: ADR-078 (raised-ceiling named-trade-off ADR precedent); ADR-011 (the
fail-closed-gate discipline this extends).
