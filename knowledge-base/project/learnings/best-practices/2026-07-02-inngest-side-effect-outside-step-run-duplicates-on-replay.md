---
title: A user-facing side-effect in an Inngest handler body (outside step.run) duplicates on replay and can be dropped un-awaited
date: 2026-07-02
category: best-practices
tags: [inngest, notifications, idempotency, step-run, replay, review-caught]
issue: 5767
pr: 5881
severity: P1
---

## Problem

feat-l5-runaway-guard added a cost-breaker **notification** to `persistFailure`
in `agent-on-spawn-requested.ts` (a durable Inngest leader-loop handler,
`retries: 3`). The first implementation fired it as a raw fire-and-forget
side-effect in the handler body, immediately before the terminal
`step.run("persist-failure")`:

```ts
if (args.notify && COST_BREAKER_NOTIFY_REASONS.has(reason)) {
  void notifyOfflineUser(args.founderId, { type: "cost_breaker_tripped", ... }); // ← BUG
}
await step.run("persist-failure", async () => { /* action_sends UPDATE */ });
```

tsc, the full unit suite (11.6k tests), and the handler's own notify test all
passed green. Three independent review agents (architecture-strategist,
code-quality-analyst, user-impact-reviewer) converged on **two** defects the
tests could not see:

1. **Duplicate sends on replay/retry.** Inngest re-executes the *entire handler
   body* on every replay, returning memoized `step.run` results instantly but
   **re-running all non-step code**. When a *later* step (`persist-failure`)
   throws a transient error, Inngest retries the function (up to `retries`),
   and the un-memoized `void notifyOfflineUser(...)` re-fires each pass — up to
   4 duplicate "you hit your spending cap" pages to the founder.
2. **Un-awaited drop.** As a floating `void` promise, the in-flight push/email
   HTTP call can be torn down when the isolate suspends at the next `step.run`
   boundary before it resolves → the notification silently never sends, and the
   whole "notify on halt" guarantee fails.

A third, adjacent defect: the notification's send-failure had **no Sentry
mirror** (the existing `mirrorStatutoryNotifyFailure` only covered statutory
email-triage), so a dropped page was also invisible — the plan's Observability
block *claimed* `op=notify-cost-breaker` coverage that did not exist
(`cq-silent-fallback-must-mirror-to-sentry` violation).

## Solution

Wrap any user-facing / non-idempotent side-effect in the handler body in its
**own memoized `step.run`**, and add an explicit Sentry mirror on send failure:

```ts
const notify = args.notify;
if (notify && isCostBreakerReason(reason)) {
  await step.run("notify-cost-breaker", () =>
    notifyOfflineUser(args.founderId, { type: "cost_breaker_tripped", reason, ... }),
  );
}
```

- `step.run` memoizes the result → Inngest fires it **exactly once** across all
  replays/retries.
- `await` makes it durable — it completes before the next step boundary.
- `notifyOfflineUser` never throws (it swallows + Sentry-mirrors its own
  failures), so the step always succeeds and can never mask the terminal write.
- Ordering is preserved: the `notify-cost-breaker` step runs before
  `persist-failure`, so "notify before the terminal UPDATE" (AC3) still holds.

## Key Insight

**"Single call site" ≠ "fires once" in a replayed function.** The Sentry-mirror
before it (`reportSilentFallback`) is safe to duplicate because it's
idempotent; a founder-facing spending-alert email is not — the two must not
share an ordering/placement rationale. In Inngest (and any replay/retry
execution model — Temporal, Step Functions, durable workflows), the rule is:
**every non-idempotent side-effect belongs inside its own `step.run`.** A raw
call in the handler body is a duplicate-and/or-drop bug that unit tests (which
don't model replay) will pass.

Companion insight: a notification keyed on a persistent **state** ("account is
still paused", `run_paused`) rather than the **transition** into that state
re-pages on every subsequent event — a storm from the guard itself. This is the
notification-layer instance of the [[2026-07-02-set-only-state-flag-is-a-cosmetic-guard-and-surface-conflation]]
transition-vs-state conflation. Fix: notify on the state-*setting* trip only
(`byok_cap_exceeded`), and let the in-product surface (the Today card + Resume)
carry every subsequent blocked attempt.

## Prevention

- **Review-spawn prompt:** when a PR adds a side-effect (notify, webhook POST,
  external write) inside an Inngest/durable-workflow handler, ask "is this in a
  `step.run`? is it idempotent under replay? is it awaited?" — surfaced by
  architecture + code-quality + user-impact converging here.
- **Grep gate:** `git grep -nE 'void (notify|send|post|dispatch)' apps/web-platform/server/inngest/` — a `void`-ed dispatch in an Inngest function body is the smell.
- The plan's `## Observability` claims are preconditions to verify against code,
  not facts — the `op=notify-cost-breaker` Sentry claim was aspirational until
  the mirror was actually wired.

## Session Errors

- **Misleading background-bash "exit 0"** — the backgrounded full-suite task
  notification reported exit 0 while the redirected log held `EXIT=1` (a real
  `TC_BUMP_METADATA.substantiveChange` shape failure). **Recovery:** grepped the
  log for the vitest summary line. **Prevention:** never trust a background
  task's "completed (exit 0)"; always grep the redirected log for the runner's
  own `Tests N failed` summary (already a hard rule — reinforced).
- **Over-broad source-sentinel false-positive** — a new `from("users")` pause
  read tripped `installation-id-source-of-truth.test.ts`'s blanket
  `from(["']users["'])` ban, whose documented intent was the *install-credential*
  read only. **Recovery:** narrowed the assertion to
  `from("users")…github_installation_id`. **Prevention:** a source-sentinel that
  bans a broad construct (`from("<table>")`) to protect a *narrow* intent
  (don't read column X) must anchor on the intent (`…X`), not the construct —
  else the next legitimate unrelated read of that table false-fails.
- **Metadata banner-shape gate** — `substantiveChange: "§3a.5 BYOK…"` failed
  `accept-terms-copy-regression`'s `/^[§A-Z][^.]{9,}$/` because "3a.5" contains a
  period. **Recovery:** reworded period-free. **Prevention:** `TC_BUMP_METADATA`
  labels must be period-free (the banner template supplies the period).
- **RED test-fixture gaps** (missing `mockFrom` for the `last_used_at` update;
  regex not tolerant of HTML-entity-escaped apostrophes) — **one-off**, fixed at
  RED time.
