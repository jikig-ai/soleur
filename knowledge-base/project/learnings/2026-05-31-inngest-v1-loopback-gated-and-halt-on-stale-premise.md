# Learning: Inngest `/v1/*` is loopback-gated from the app container; halt one-shot when a just-merged HEAD invalidates the task premise

## Problem

A `/soleur:go` request asked to re-architect the `cron-cloud-task-heartbeat`
watchdog to detect scheduled-task silence via **Inngest run-history** instead of
the presence of a `scheduled-<task>` GitHub issue. The operator (via
AskUserQuestion) explicitly chose "switch to Inngest run-history".

Two traps:

1. **The chosen approach was technically infeasible.** Inngest here is
   self-hosted (`host.docker.internal:8288`, SQLite at `/var/lib/inngest`). Inngest
   gates its **entire `/v1/*` introspection surface to loopback** — from the app
   container `/health` returns 200 but `/v1/functions` (and `/v1/runs`,
   `/v1/events` — same namespace) returns **404**; only the host's
   `127.0.0.1:8288` can read it. So a containerized watchdog can never read
   run-history, exactly the way it can never read the registry.

2. **A commit merged hours earlier had already proven this.** `#4708`
   (HEAD commit `8535bdf1`, "retire watchdog to liveness-only beacon") retired the
   *sibling* `cron-inngest-cron-watchdog.ts` for this exact reason. The one-shot
   pipeline created its worktree from fresh `origin/main`, which surfaced #4708 in
   the base — visible only because the worktree was freshly cut.

## Solution

Halt the one-shot pipeline **before** spawning the planning subagent, surface the
#4708 evidence, and re-ask the operator. The viable fix (operator chose it) was
the minimal one: keep the GitHub-issue-label detection — a valid "did this task
produce its output artifact?" signal — and instead **correct `TASK_INVENTORY`**:

- Remove the 3 non-producers (daily-triage / ux-audit / bug-fixer) that never
  create a `scheduled-<task>` issue, so they false-fired forever via the
  `daysSince === null → silent: true` branch.
- Re-derive every remaining producer's `maxGapDays` from its real cron cadence
  (legal-audit 9→95 was the headline: a 9-day gate on a quarterly cron).

Cron **liveness** for all tasks (including the 3 removed) is covered separately by
per-function Sentry cron monitors (`failure_issue_threshold = 1` in
`cron-monitors.tf`) — verified at review time. The heartbeat answers only the
orthogonal "did it produce output" question.

## Key Insight

- **Self-hosted Inngest `/v1/*` (registry AND run-history) is loopback-gated —
  unreachable from any app-container code.** Never propose a containerized
  function that reads Inngest introspection/run-history; no auth or network change
  fixes it (#4694 tried dropping the auth header; the 404 recurred). Use
  per-function Sentry cron monitors for "did the cron fire" liveness.
- **When a one-shot task proposes a re-architecture, scan the fresh worktree base
  (`git log --oneline -8 <subsystem>` + the HEAD commit body) for recently-merged
  commits touching the same subsystem BEFORE spawning the planning subagent.** A
  commit that merged between request and dispatch can invalidate the whole
  premise; halting pre-plan saves a full plan→work→review→ship cycle and avoids
  producing a confidently-wrong plan. The operator's chosen option is a strong
  signal, not a constraint to honor when fresh evidence contradicts it
  (`cm-challenge-reasoning-instead-of`).

## Session Errors

1. **CWD drift on first RED test run** — ran
   `./node_modules/.bin/vitest run …` after `cd`-ing to the bare-root
   `apps/web-platform` (not the worktree), producing a "Tests no tests" / FAIL that
   looked like a collection error. **Recovery:** re-ran from the worktree-absolute
   path. **Prevention:** always chain `cd <worktree-abs-path> && <cmd>` in a single
   Bash call; the Bash tool does not persist CWD and the bare root holds stale
   synced copies (already documented; reinforced).
2. **Planning subagent transient Edit path-typo** (forwarded from
   session-state.md) — dropped the worktree prefix on one Edit; retried with the
   absolute path and succeeded. **Prevention:** subagents must run the CWD-verify
   first tool call and use worktree-absolute paths (already in the one-shot
   subagent contract).

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
related: "#4708, #2714, #4682"
