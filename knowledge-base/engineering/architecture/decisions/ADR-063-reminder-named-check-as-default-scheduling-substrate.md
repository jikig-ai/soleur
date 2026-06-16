# ADR-063: Reminder-primitive `named-check` as the default lightweight scheduling substrate (+ scoped close capability)

- **Status:** Accepted
- **Date:** 2026-06-16
- **Deciders:** Jean (operator), security-sentinel + architecture-strategist (deepen-plan review)
- **Relates to:** ADR-046 (Inngest oneshot self-arm / registered-only), ADR-033 (cron runtime invariants), `inngest-oneshot-and-reminder-patterns.md`, #5417 (first consumer)

## Context

Scheduling a one-time, fire-time-secret task (e.g. "in 72h, check whether the
Sentry 'Server startup' rate dropped to ≤1/day, then close the issue") had two
unappealing paths:

1. **`soleur:schedule` GHA-cron** — but a GHA runner has **no Doppler/prd access**,
   so the Sentry-token fetch fails at fire time; the `new-scheduled-cron-prefer-inngest`
   hook also blocks the YAML write. Wrong substrate for secret work.
2. **A bespoke Inngest oneshot** (ADR-046) — correct substrate (fire-time prd env)
   but **heavyweight**: a new `oneshot-*.ts` + a `server/index.ts` boot-arm + a
   deploy, *per task*. Disproportionate for a 3-day, one-off verification.

The reminder primitive (`event-scheduled-reminder.ts`, `POST /api/internal/schedule-reminder`)
already existed as a registered-only, zero-deploy-to-arm, fire-time-secret
substrate — but its only registered check was a trivial demonstrator, so authors
still reached for GHA or a bespoke oneshot.

## Decision

1. **Make the reminder primitive's `named-check` registry the default lightweight
   substrate** by adding ONE reusable, parametric check — `sentry-issue-rate`
   (events/day of a tagged Sentry issue over a window, PASS iff ≤ threshold). The
   per-task cost drops from "new oneshot + deploy" to **a single zero-deploy POST**
   for any future "did Sentry issue X drop below N/day?" verification. New *kinds*
   of check still cost one reviewed registry entry + deploy; instances of an
   existing check cost nothing. This stays within ADR-046/ADR-033's **registered-only**
   model — we did NOT build an arbitrary-script/task-spec executor (explicitly
   rejected as a credential-leak vector).

2. **Add a scoped close capability (v1 → v1.1).** A check may set `close: boolean`
   on its result; the handler then closes **`action.report_to_issue`** only. The
   close target is structurally the action's own report issue — a check can never
   name an arbitrary issue to close. This is *why* the boundary moved (v1 was
   comment-only): the boolean shape makes the scope-violation unrepresentable, so
   the capability is added with zero new attack surface (no runtime guard needed).

3. **Route to it structurally.** `soleur:schedule`'s `create` gains a Step 0
   execution-substrate gate that sends fire-time-secret / server-side scheduled
   work to this primitive (or a oneshot) instead of GHA-cron. Inngest becomes the
   structural default; the `new-scheduled-cron-prefer-inngest` hook is the backstop.

## Consequences

**Positive.** Future scheduled verifications are cheap (one POST) and run with
full prd env. The substrate-routing gate stops the "generate GHA → get blocked →
recover" loop and prevents the silent "fires but can't auth" failure of GHA-cron
for secret work. The first consumer (#5417's AC12) becomes a documented one-line
arm.

**Negative / accepted.** The reminder endpoint's blast radius widens slightly: an
`INNGEST_MANUAL_TRIGGER_SECRET` holder can now schedule a close of the *check's
own report issue* (in addition to a comment / a registered check). This is the
same operator-held trust boundary as `trigger-cron`, the close is scoped to
`report_to_issue`, and fail-closed semantics (`info`, no close on any inability
to verify) bound the downside. `SENTRY_ISSUE_RW_TOKEN` (issue-scoped) is read at
fire time; it lives only in the Authorization header (never in error/body —
token-non-leak test-asserted). Adding a NEW check kind remains a code-reviewed
deploy — deliberately, to preserve registered-only.

**Security review.** `security-sentinel` ran at review (close-capability +
Sentry-read surface): strict `tag` regex + `..`-guard + URL-encoding (no query
injection), `window_hours ∈ [1,168]` (no spurious-pass via huge window),
token-non-leak, fail-closed on every error path.
