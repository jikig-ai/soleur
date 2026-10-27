# #8764 — Inngest step-boundary harness sweep + census lint

Issue: #8764 (follow-up deferred by #8726). Defect class: #8717/#8726 — an error that
crosses `step.run`'s boundary reaches the handler catch as the SDK's rebuilt
`StepError` (name `"Error"`, no custom class/fields), so handler catches routing on
`instanceof`/`.name`/`.status` misroute in production while passing in-process mocks.

## Migration census (honest, not the issue's "~38")

41 suites define a local `makeStep`/`makeRetryingStep`; others use inline fakes.
Set (a) — handler-under-test catches around `step.run(` → migrate:

**Migrated & green** (runLikeInngest, real serializeError→StepError):
- cron-review-reminder, cron-terraform-drift, cron-dev-migration-drift,
  cron-domain-model-drift, cron-main-health-monitor,
  cron-actions-queue-health-dispatch, cron-supabase-watchdog-dispatch,
  cron-supabase-advisor-scan, cron-inngest-config-drift (9 dispatch suites)
- sla-issue-process, cron-anthropic-cost-report, agent-on-spawn-lifecycle,
  cron-kb-template-health, cron-weekly-release-digest, cron-community-monitor-dedup

**Migrated earlier (#8726)**: the 10 original suites incl. cron-github-app-drift-guard.

**Remaining in set (a)** — larger suites needing per-test boundary review
(memo seeding, attempt plumbing, ordering); enumerated for the follow-up:
- cron-community-monitor-heartbeat, cron-merge-queue-stall-dispatch,
  cron-content-vendor-drift-revendor, cron-stale-deferred-scope-outs,
  cron-bug-fixer, cron-gh-pages-cert-reissue, cron-cohort-dedup,
  cron-compound-promote-{create,draft,patterns}-handler,
  agent-on-spawn-requested-leader-loop (partial boundary coverage exists in
  several; the remaining makeStep paths are what need conversion).

Set (b) — never exercise the catch boundary → intentionally not migrated
(handler has no `try{step.run}catch`, or mocks model a different contract;
their verdicts do not depend on boundary error identity — the census lint now
keeps the corpus from growing new cases).

## Harness additions

`step.sleep` + `step.sendEvent` settle via the same memoize-and-end-invocation
path; `sentEvents` records each DELIVERED event once (a wrapped `sendEvent`
over-counts — the handler re-calls it on every replay).

## Census lint

`scripts/lint-inngest-step-boundary.py` walks
`apps/web-platform/server/inngest/functions/*.ts`, strips comments, brace-matches
try/catch, and flags: (A) a catch whose own try contains `step.run(` reading
`<p> instanceof <Class>` / `<p>.name ===` / `<p>.status` on its catch param —
always a violation; (B) a catch inside a `step.run` callback reading error
identity — legal (live error) but requires registration in
`STEP_INTERNAL_ALLOWLIST` (cost-report, credit-probe, cert-reissue per the
issue, plus drift-guard + compound-promote whose #8726 rework put the checks
inside steps). `instanceof Error` is exempt — StepError extends Error, so the
check cannot misroute. Self-test: `lint-inngest-step-boundary.test.sh`
(bad fixture red, allowlist green, step-internal green).
Registered: `run_suite` ×2 in test-all.sh; `AFFECTED_SCRIPTS_LINT_INNGEST_STEP_BOUNDARY_{LIVE,UNIT}_PATHS`.

## Assertion changes worth noting

- cron-anthropic-cost-report: harness pinned a real defect — daily marker +
  key-missing warn emitted at handler scope after a step, so every replay
  re-emitted; moved inside `step.run("key-missing-report")` / `("daily-marker")`.
- cron-community-monitor-dedup: fail-closed upsert-read test seeds a third
  fault — a persistent outage must survive the step retry, not just one call.

## Guard Contract

### Guard 1 — `lint-inngest-step-boundary` unit battery + live corpus run

**Property.** The census cannot silently vacuate: `lint-inngest-step-boundary.test.sh`
proves a known-bad fixture exits 1, the named allowlist exempts only step-internal
catches, `instanceof Error` is exempt, a no-`step.run` catch is not flagged, and the
live corpus run exits 0 — so a regression either reds the fixtures (verdict broken)
or the live run (corpus drifted past the allowlist).

**Assembly.** Two chokepoints: `scripts/lint-inngest-step-boundary.py` (the verdict,
scope `apps/web-platform/server/inngest/functions/*.ts`) and
`scripts/lint-inngest-step-boundary.test.sh` (the fixture battery). Registered via
`run_suite` rows `scripts/lint-inngest-step-boundary-{unit,live}` in `test-all.sh`
and `AFFECTED_SCRIPTS_LINT_INNGEST_STEP_BOUNDARY_{LIVE,UNIT}_PATHS` edges in
`scripts/lib/test-affected-paths.sh` so the corpus, the lint, or the index all
select it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `instanceof` identity hit from `identity_hits` | RED — "boundary instanceof flagged" goes green on a bad fixture |
| 2 | Allowlist every basename (or match by step-internal presence alone) | RED — "step-internal unlisted flagged" goes green |
| 3 | Flag any catch containing a try, not just a try containing `step.run(` | RED — "catch without step.run not flagged" goes red |
| 4 | Remove the bare-`Error` RHS exemption | RED — "instanceof Error exempt" goes red |
| 5 | Drop the AFFECTED_LIVE edge for `server/inngest/functions/` | RED — corpus-affecting diffs stop selecting the live suite; the affected-index test catches the missing edge |
