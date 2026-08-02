# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-02-fix-resend-inbound-webhook-500-dispatch-outage-plan.md
- Status: complete

### Errors
None. All mechanical gates passed (4.5 network-outage, 4.55 downtime/cutover, 4.6 user-brand,
4.7 observability, 4.8 PAT-shape, 4.10 encryption posture; 4.9 skipped — no UI surface).
Telemetry emitted for the two gates that fired. Citation, rule-ID, and issue-number checks
clean; verify-the-negative sweep returned 15/15 confirmed.

Scope verification (one-shot post-subagent gate): `git diff origin/main...HEAD --name-only`
after a fresh `git fetch origin main` listed only the plan file and
`knowledge-base/project/specs/feat-one-shot-resend-inbound-webhook-500/tasks.md`. No
out-of-scope source/workflow files were touched — the planning subagent stayed within its
plan-only mandate.

### Decisions
- **Root-caused to infrastructure, not the route.** Every observed 500 is the route's
  ADR-055 transient-dispatch path firing correctly: `inngest.send()` gets
  `ECONNREFUSED 10.0.1.40:8288`, the dedup row is released, 500 is returned so the svix
  retry is honoured. H2/H5/H6 refuted from committed code; H1 near-refuted by the errno;
  H3 refuted and H4 confirmed via the Hetzner API. Onset recovered as
  2026-07-30T15:13:06Z (~27h before the vendor alert), which the plan had recorded as
  UNKNOWN.
- **Durable-claim shape: extend `processed_resend_events`, not a new outbox table**;
  persist-then-200 unconditional, with the reconciler as sole dispatcher. Rejected the
  two-table shape (distributed-transaction hazard) and persist-only-on-failure
  (incident-only recovery code).
- **Retention: delete-on-drain rejected in favour of null-PII-and-keep-tombstone** —
  delete-on-drain would destroy the ADR-037 replay defense. Sweep uses a terminal-state
  allowlist, never an age-only predicate.
- **Observability fix contained to the route** (wrapper `Error` with `cause`), explicitly
  not `server/logger.ts`. Drain alarm is a `sentry_cron_monitor` off the Inngest
  substrate, since an Inngest-fired alarm cannot run during the outage it guards.
- **Probe-first preserved but de-merged** — Phase 0 produces no PR (all reads are
  read-only API calls), time-boxed ≤4h, gating on the first failing hop rather than on a
  single-winner hypothesis.

### Components Invoked
`soleur:plan`, `soleur:deepen-plan`; agents: `repo-research-analyst`, `learnings-researcher`,
`engineering:cto`, `legal:clo`, `product:cpo`, Fable advisor consult (ADR-083),
`data-integrity-guardian`, `observability-coverage-reviewer`, `spec-flow-analyzer`,
verify-the-negative sweep; tooling: `scripts/betterstack-query.sh`, `scripts/sentry-issue.sh`,
Sentry + Resend + Hetzner APIs, `gh`, Doppler.

## Carried into Work Phase
- **Live legal exposure (Phase 1.0, cannot ride behind Phase 2):** statutory mail (DSAR
  Art. 12(3), service of process, regulator contact, or an inbound processor breach
  notice under Art. 33's 72h clock) arriving in the outage window was never escalated by
  PA-27. Phase 2's durable claim prevents recurrence but does not discharge a clock
  already running.
- **Answers to the brief's two questions:** the Resend webhook is still `status: enabled`
  (re-verified 2026-08-02 11:17Z), so no re-enable is required today; the *triage
  delegation* was lost for ≥15 distinct emails, but the *mail* was not — ADR-055's Sieve
  rule is forward-and-keep, so Proton should hold every original. Phase 1.0 verifies the
  keep-copy rather than assuming it.
