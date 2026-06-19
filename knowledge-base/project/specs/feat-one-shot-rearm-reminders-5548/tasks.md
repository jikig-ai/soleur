---
title: "Tasks — Re-arm Inngest reminders lost in the #5542 cutover (#5548)"
plan: knowledge-base/project/plans/2026-06-18-fix-rearm-reminders-lost-in-cutover-plan.md
lane: single-domain
issue: 5548
---

# Tasks: Re-arm reminders lost in the #5542 cutover

Derived from `2026-06-18-fix-rearm-reminders-lost-in-cutover-plan.md` (post deepen-plan).
**No production source code changes** — this is an ops-remediation re-arm against an
existing, validated endpoint. Deliverables: reconstructed payloads, in-session re-arm
execution, and a PIR/runbook note.

## Phase 0 — Preconditions (read-only)

- 0.1 Confirm #5417 + #5469 still OPEN and un-fired (no `sentry-issue-rate` comment on
  #5417; no re-eval comment on #5469): `gh issue view 5417 --json comments`,
  `gh issue view 5469 --json comments`. If either was already re-armed/fired since the
  plan was written, scope it out (do not double-arm).
- 0.2 Confirm the cutover quiesce flag is CLEAR (route returns 503 while
  `INNGEST_CUTOVER_QUIESCE` set, `route.ts:45-48,74-79`). Verify a non-503 path (e.g.
  `curl -sS -o /dev/null -w '%{http_code}' https://app.soleur.ai/health` → 200), or
  accept the AC6 503-abort as the guard.
- 0.3 Confirm the durable backend is healthy (`op=inventory` → `functions=56`, NOT
  `__FETCH_FAILED__`) per the #5542 PIR. Arming into a down backend silently re-loses —
  the exact #5548 failure mode.

## Phase 1 — Reconstruct + freeze the two payloads

- 1.1 **5417** — copy the blessed `sentry-issue-rate` payload verbatim from
  `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md:81-84`.
  Set `fire_at:"2026-06-19T09:00:00Z"`. Verify `params.tag:"event_type:server-startup"`
  (COLON form — `TAG_RE` at `sentry-issue-rate.ts:22`; equals form would 400),
  `max_per_day:1`, `window_hours:72` (∈ [24,168]), `close_on_pass:true`,
  `report_to_issue:5417`, `actor:"platform"`. (AC1)
- 1.2 **5469** — build the `issue-comment` body from #5469's re-eval criterion (≥14 days
  `routine_runs` data after the inbound fix). Target `issue:5469`,
  `fire_at:"2026-07-01T09:00:00Z"`, `actor:"platform"`, body ≤ 65000 chars. (AC2)
- 1.3 Note in the #5417 re-arm body that the blessed `sentry-issue-rate` arm is the
  distilled form of #5417's fuller AC12 spec (the OOM-page / AC13 firewall-self-heal
  tail is a separate manual check if still wanted) — ADR-063 + the runbook blessed the
  distillation.

## Phase 2 — Execute the re-arm in-session (NO operator handoff)

- 2.1 Read the secret read-only: `SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)`;
  never echo it; `unset SECRET` after use (mirror `trigger.sh:133-148`).
- 2.2 **Option A (default — direct curl):** POST each frozen payload to
  `https://app.soleur.ai/api/internal/schedule-reminder` with
  `-H "Authorization: Bearer $SECRET"`. Expect HTTP **202**. On **503** ABORT LOUD
  (quiesce still set — do not swallow); **401** = wrong secret; **400** = payload failed
  the allowlist (re-check Phase 1). (AC6, AC7)
- 2.3 **Option B (repeatable — reuse existing executor, NO new script):** feed the two
  payloads as a JSON array to `apps/web-platform/infra/inngest-rearm-reminders.sh` via
  `INNGEST_REARM_STDIN=1` + `SCHEDULE_REMINDER_URL=https://app.soleur.ai/api/internal/schedule-reminder`.
  Do NOT author a new `rearm-5548-*.sh` (duplicates the tested executor).
- 2.4 Idempotency note for the PR body: route sets `id`=reminder_id + `ts`=Date.parse(fire_at)
  (`route.ts:128-133`); re-running the SAME POST within Inngest's ~24h dedup window
  dedups (moot — empty queue). (AC4)

## Phase 3 — Confirm + close

- 3.1 Verify both 202s; if reachable, confirm armed via `op=inventory` (AC8) — else the
  two 202 responses are the acceptance evidence (note inventory as deferred confirmation).
- 3.2 `gh issue close 5548` with a comment: re-armed ids + fire_at + 202 evidence + the
  5432 disposition. (AC9)

## Phase 4 — Document (so the next cutover does not re-lose these)

- 4.1 Append a one-line note under the #5548 row of
  `knowledge-base/engineering/operations/post-mortems/inngest-durable-redis-missing-outage-postmortem.md`:
  re-armed 5417 + 5469 (202×2); 5432 not re-armed (past window, unrecorded body).
- 4.2 (Optional) Add a runbook callout in `inngest-oneshot-and-reminder-patterns.md` §A:
  if inngest is DOWN during a cutover, `op=capture` snapshots nothing — survivors must
  be reconstructed from source automations and re-armed manually (see #5548).

## Phase 5 — Dependabot reminder disposition (AC3)

- 5.1 Do NOT re-arm `rebase-dependabot-5432-otel-2026-06-18` (past 2026-06-18 13:00 fire
  window; body unrecorded; out of the documented #5548 scope per PIR `:42`). Record the
  rationale in the PR body + a one-line #5548 note; offer `@dependabot rebase` directly
  on the #5432 PR if the otel bump is still wanted.
- 5.2 If the operator disagrees, re-arm as `issue-comment {issue:5432, body:"@dependabot rebase"}`
  with a near `fire_at` — accepting the body is reconstructed, not recorded.

## PR + closure shape

- 6.1 PR body uses `Ref #5548`, NOT `Closes #5548` (ops-remediation: actual closure is
  the post-merge `gh issue close 5548` after the 202s). (AC5)
- 6.2 Verify-the-negative + halt-gate results (already passed in deepen-plan) carry into
  the PR body for reviewer continuity.
