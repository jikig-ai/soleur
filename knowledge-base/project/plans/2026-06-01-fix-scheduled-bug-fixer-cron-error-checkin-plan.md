---
title: Fix scheduled-bug-fixer Sentry cron monitor error check-in
date: 2026-06-01
type: fix
status: planned
lane: cross-domain
brand_survival_threshold: none
related_issues: []
related_prs: []
related_learnings:
  - knowledge-base/project/learnings/bug-fixes/2026-05-27-sentry-cron-community-monitor-missed-checkin.md
  - knowledge-base/project/learnings/2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md
  - knowledge-base/project/learnings/bug-fixes/2026-05-30-inngest-cron-desync-regression-needs-runtime-self-heal-not-ci-guard.md
---

# 🐛 Fix `scheduled-bug-fixer` Sentry cron monitor error check-in

## Overview

The Sentry cron monitor `scheduled-bug-fixer` (monitor ID
`8f12e8fb-d232-4f53-8f2d-48fc80b81e8e`, incident `5127648`) is reporting an
**error check-in** ("An error check-in was detected"), not a *missed*
check-in. Last successful check-in was `2026-05-30T06:00:24+00:00`; it has
been failing since the `2026-05-31` 06:00 UTC fire and again on `2026-06-01`
08:00 CEST (06:00 UTC).

The monitor is fed by the Inngest cron function
`apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` (cron
`0 6 * * *` UTC), which POSTs `?status=error` to Sentry Crons whenever its
handler resolves with `ok: false`. The function fires daily and runs a
`claude --print -- /soleur:fix-issue <N>` child-process eval inside an
ephemeral cloned workspace.

**Error check-in ≠ missed check-in.** A missed check-in (the
`scheduled-community-monitor` 2026-05-27 class) means the function never
fired — root cause is Inngest server desync (runbook H9). An *error*
check-in means the function **did fire and ran to completion**, then
deliberately posted `status=error`. So this is NOT an H9 desync; the failure
is in the handler's success/failure decision or in the spawned claude-eval.

### The `auth-callback-no-code-burst` linkage — CONFIRMED COINCIDENTAL (red herring)

The alert email names alert rule `auth-callback-no-code-burst`. This is a
**project-wide Sentry _issue alert_** (`sentry_issue_alert.auth_callback_no_code_burst`
in `apps/web-platform/infra/sentry/issue-alerts.tf:79`), an
`EventFrequency`-style rule on auth-callback events with no `code` param. It
is a **completely separate Sentry resource** from the cron monitor; it shares
only the operator notification email channel. The exact same red-herring
pairing is documented for the 2026-05-27 `scheduled-community-monitor`
incident: *"The alert was 'triggered by auth-callback-no-code-burst' — this
was a red herring (coincidental unrelated Sentry issue alert routed to the
same operator email)"* (`2026-05-27-sentry-cron-community-monitor-missed-checkin.md:21`
and runbook `cloud-scheduled-tasks.md:381`). The underlying auth-callback
no-code path (`app/(auth)/callback/route.ts:297` `op: "callback_no_code"`)
is a benign bookmark/stale-link fallback and has **no causal connection** to
the cron monitor. The linkage assertion in the brief is therefore **rejected**:
do not chase the auth callback. The work phase must still confirm by pulling
the actual Sentry **monitor** event (`c05485aca66b4696844fd815e4ec4600`) — see
Phase 1.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (codebase / precedent) | Plan response |
|---|---|---|
| "likely a GitHub Actions cron invoking a Soleur skill, or an Inngest/scheduled function" | It is an **Inngest cron function** (`cron-bug-fixer.ts`, cron `0 6 * * *`). The GHA `scheduled-bug-fixer` workflow was **deleted** in TR9 PR-5 (#4377). | Investigate the Inngest function + claude-eval substrate only. No GHA workflow exists. |
| "auth-callback-no-code-burst suggests the underlying error may be a burst of auth-callback requests with no `code`" | The alert rule is an unrelated project-wide issue alert sharing only the email channel. Direct precedent (2026-05-27) documents this exact pairing as a red herring. | **Reject** the linkage; do not modify the auth callback. Confirm via the monitor event payload in Phase 1. |
| "error check-in" | Distinct from the 2026-05-27 *missed* check-in. The handler posts `status=error` when `ok:false`; `ok` derives from `spawnResult.ok` (claude exit code `=== 0`). | Root cause is a **non-zero claude-eval exit** (or workspace-setup failure / timeout), NOT Inngest desync. Runbook H9 does not apply. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly —
`scheduled-bug-fixer` is an internal autonomous ops cron. The failure cost is
**operator alert fatigue**: a daily false-or-true `status=error` page that, if
mis-triaged, trains the operator to ignore the bug-fixer monitor (and, by
proximity, the whole `scheduled-*` monitor family) — the exact decay the
`scheduled-realtime-probe` margin-widening (#4189) and the watchdog (#4650)
were built to prevent.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no
user data flows through this monitor. The handler already redacts the
installation token from every observability sink
(`cron-bug-fixer.ts` token-redaction sentinel sweep, test group (f)).

**Brand-survival threshold:** none — internal ops monitor; no user-facing
artifact and no data-exposure vector. (threshold: none, reason: internal
autonomous-ops cron monitor with no user-facing surface and no
regulated-data movement.)

## Hypotheses (ranked; Phase 1 confirms with the Sentry event payload)

The handler resolves `ok:false` (→ `status=error`) on exactly these paths.
Each is a candidate root cause; Phase 1 reads the event + `reportSilentFallback`
extras to select.

- **H1 — claude-eval exits non-zero (MOST LIKELY).** `spawnClaudeEval`
  returns `ok: exitCode === 0` (`_cron-claude-eval-substrate.ts:231`). The
  final happy-path heartbeat is `overallOk = spawnResult.ok && !!detectedPr`
  (`cron-bug-fixer.ts:792`), but that line is only reached when `detectedPr`
  is truthy (the `!detectedPr` branch returns earlier at :756 with
  `ok: spawnResult.ok`). So `&& !!detectedPr` is effectively redundant, and
  the **sole error driver in normal operation is `spawnResult.ok === false`**
  — i.e. `claude --print ... -- /soleur:fix-issue N` exited non-zero. claude
  CLI `--print` mode exits non-zero on max-turns exhaustion and several
  terminal agent states; for an autonomous best-effort fixer, "ran 55 turns,
  did not land a single-file fix" is a **normal daily outcome**, not an
  operational error. This is the "Monitor exit-condition tightness" class
  (`2026-05-18-...-monitor-exit-condition-tightness.md`): a healthy signal
  reported as failure. Onset `~2026-05-31` is consistent with the issue
  backlog reaching a state where the selected issue is no longer one-shot
  fixable (the cascade always finds *some* p3/p2/p1 `type/bug` issue, then
  claude can't fix it → non-zero exit → daily page).
- **H2 — claude-eval aborted by the 50-min timeout.** `abortedByTimeout`
  path sets `spawnResult.ok` per exit code after SIGTERM/SIGKILL; a killed
  child exits non-zero → `status=error`. Distinguishable in Phase 1 by the
  `op: "claude-eval-timeout"` `reportSilentFallback` (`cron-bug-fixer.ts:733`)
  and `durationMs ≈ MAX_TURN_DURATION_MS`.
- **H3 — ephemeral workspace setup failure.** `git clone --depth=1` of
  `jikig-ai/soleur` failing (token-mint regression, network, disk) → the
  setup-workspace catch posts `status=error` (`cron-bug-fixer.ts:691`),
  `op: "setup-ephemeral-workspace"`. Onset would correlate with a token /
  GH-App / Hetzner-disk change around 2026-05-30. Note the GitHub-App
  installation-token 401 resilience gap
  (`2026-05-26-inngest-github-installation-token-401-resilience-gap.md`).
- **H4 — manual-trigger override with a bad payload.** `event.data.issue_number`
  non-integer posts `status=error` (`cron-bug-fixer.ts:612`). Ruled out for a
  *daily-recurring* failure (the cron trigger sends no `data`), but Phase 1
  should confirm the failing check-ins are the `0 6 * * *` fire, not a
  fat-fingered manual trigger.
- **H5 (eliminated as the page driver) — H9 Inngest desync.** Would produce a
  *missed* check-in, not an *error* one. The function is firing (error
  check-ins prove the handler ran to a heartbeat). Do not run the H9 restart
  runbook for this incident.

## Root-Cause Decision & Fix Direction

The fix shape depends on which hypothesis Phase 1 confirms:

- **If H1/H2 (claude-eval non-zero / timeout is a _normal_ no-fix outcome):**
  the bug is the **over-tight monitor exit condition**. The correct
  liveness semantic for an autonomous best-effort fixer is *"the cron fired
  and the pipeline ran end-to-end without an _infrastructure_ error"* — NOT
  "claude landed a mergeable PR today." Decouple the Sentry heartbeat
  `ok` from `spawnResult.ok`: a clean end-to-end run (token minted, workspace
  set up, claude spawned and exited, PR-detection ran, teardown ran) is
  `ok:true` regardless of claude's exit code; reserve `status=error` for
  genuine infrastructure failures (token mint, clone, spawn `child.on("error")`,
  timeout-abort). claude's non-zero "no fix today" exit becomes a structured
  `logger.info` + an optional low-urgency telemetry breadcrumb, not a page.
  This mirrors the sibling crons' intent and the `#4682` watchdog redesign
  ("its own check-in proves the scheduler is alive", `cron-monitors.tf:435`).
  **This is the expected outcome and the primary fix.**
- **If H3 (workspace/token infra failure):** that IS a genuine error the
  monitor should page on — keep `status=error`, and the fix is the underlying
  infra failure (token-mint resilience per
  `2026-05-26-inngest-github-installation-token-401-resilience-gap.md`, or
  clone/disk). The monitor is behaving correctly; do not relax it.
- **If H4 (bad manual trigger):** no code fix; the failing check-ins are
  operator-triggered noise. Confirm and close.

The Phase 1 data-pull is therefore **load-bearing**: H1/H2 → relax the exit
condition; H3 → fix the infra and keep the strict condition. Do not assume.

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)

- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bug-fixer.test.ts` is green on `origin/main` (baseline; per `2026-05-27` Session Error 1 — run vitest from `apps/web-platform`, not the monorepo root).
- [ ] Confirm `SpawnResult.ok = exitCode === 0` at `_cron-claude-eval-substrate.ts:231` (already verified at plan time).
- [ ] Confirm the final heartbeat is `overallOk = spawnResult.ok && !!detectedPr` at `cron-bug-fixer.ts:792` and the `!detectedPr` early-return at `:756` is `ok: spawnResult.ok` (already verified at plan time).
- [ ] `grep -n "status=error\|status=ok" apps/web-platform/test/server/inngest/cron-bug-fixer.test.ts` — enumerate every test that asserts the heartbeat status so the Phase 3 changes update them coherently (groups (b), (e), manual-trigger).

### Phase 1 — Confirm root cause from the Sentry event (data-pull, no SSH)

Per `hr-no-dashboard-eyeball-pull-data-yourself`: pull the data, apply a
deterministic verdict rule.

- [ ] Read the failing **monitor** check-in / associated event via the Sentry API (token in Doppler `prd`/`prd_terraform` as `SENTRY_API_TOKEN`):
  ```bash
  # Monitor state + recent check-ins
  curl -s -H "Authorization: Bearer $SENTRY_API_TOKEN" \
    "https://sentry.io/api/0/organizations/$SENTRY_ORG/monitors/scheduled-bug-fixer/checkins/?per_page=20" \
    | jq '.[] | {status, dateCreated, duration}'
  # The cited event payload (extras carry op + durationMs)
  curl -s -H "Authorization: Bearer $SENTRY_API_TOKEN" \
    "https://sentry.io/api/0/projects/$SENTRY_ORG/web-platform/events/c05485aca66b4696844fd815e4ec4600/" \
    | jq '{title, "extra": .context, tags: [.tags[] | {key, value}]}'
  ```
- [ ] **Verdict rule:**
  - A `reportSilentFallback` event with `op: "claude-eval-timeout"` and `durationMs ≈ 3_000_000` → **H2**.
  - A `setup-ephemeral-workspace` / `mint-installation-token` / `child_process.spawn` error event near the failing check-in timestamps → **H3** (genuine infra error).
  - **Absence** of any infra-error `reportSilentFallback` around the failing fires, with check-in `duration` well under 50 min → **H1** (claude exited non-zero with no infra fault; the "no fix today" normal case).
- [ ] Cross-check cron-fire liveness to rule out H9 confusion: the monitor shows *error* check-ins (not gaps), confirming the function fires. Record the selected hypothesis in the PR body.

### Phase 2 — Fix (branch by confirmed hypothesis)

**Phase 2-A — H1/H2 confirmed (primary, expected): relax the exit condition.**

- [ ] In `cron-bug-fixer.ts`, redefine the heartbeat `ok` so a clean
  end-to-end run is healthy regardless of claude's exit code. Concretely:
  - The final heartbeat becomes `ok: true` (the pipeline reached the end:
    token+workspace+spawn+detect+teardown all ran without throwing). Drop the
    `spawnResult.ok && !!detectedPr` conjunction.
  - The `!detectedPr` branch (:756) likewise becomes `ok: true` (a clean run
    that produced no PR is the normal best-effort outcome).
  - Keep `status=error` ONLY on genuine infrastructure faults that already
    have early-return error heartbeats: setup-workspace catch (:691), bad
    manual-trigger payload (:612). These are unchanged.
  - When `spawnResult.ok === false` (claude non-zero) OR
    `spawnResult.abortedByTimeout`, emit a structured `logger.info`/`logger.warn`
    ("bug-fixer claude-eval produced no fix" / "aborted by 50-min budget") and
    a low-urgency Sentry breadcrumb — NOT a `status=error` heartbeat. The
    timeout `reportSilentFallback` at :727 may stay (it's a `warning`-level
    telemetry breadcrumb, not the monitor page) — decide at /work whether a
    chronic-timeout signal is still wanted as a separate, non-paging alert.
  - Update the handler return shape (`ok`) to reflect the new semantic so the
    return value and the heartbeat agree.
- [ ] Update the cron-monitors.tf header prose if any comment claims the
  bug-fixer pages on claude failure (verify; likely no change needed — the
  Terraform resource is unaffected since `status` is computed app-side).

**Phase 2-B — H3 confirmed: fix the infra, keep the strict page.**

- [ ] The monitor is correct; do NOT relax it. Fix the underlying failure:
  installation-token resilience (apply the retry/backoff pattern from
  `2026-05-26-inngest-github-installation-token-401-resilience-gap.md` if the
  fault is a 401/clone-auth race), or surface the clone/disk error. Scope the
  exact fix once Phase 1 names the `op`.

**Phase 2-C — H4 confirmed: no code change.** Document the bad manual trigger
in the PR body; close the incident; add an AC-less note. (Unlikely for a daily
recurrence.)

### Phase 3 — Tests (RED before GREEN, per `cq-write-failing-tests-before`)

For the primary (H1/H2) path:

- [ ] **Rewrite test group (e)**: the existing
  `"claude spawn non-zero exit + no PR detected → ?status=error"`
  (`cron-bug-fixer.test.ts:806`) encodes the OLD (buggy) semantic. Replace
  with `"claude non-zero exit (no fix) → ?status=ok"` — a clean run with a
  non-zero claude exit and no PR is a healthy liveness check-in. This is
  directly testable with the existing harness: `wireSpawn(1)` (the helper at
  `:229` already takes a claude exit code) + no PR wired → assert
  `status=ok`. **Also flip the return-value assertion**: this test's
  `expect(result.ok).toBe(false)` (`:822`) must become `toBe(true)` since the
  handler return `ok` is changed in lockstep with the heartbeat (Phase 2-A).
- [ ] **Add** `"claude timeout-abort → ?status=ok (+ telemetry breadcrumb, no page)"`.
- [ ] **Keep** the genuine-error tests as `status=error`: group (b)
  `"plugin sentinel manifest missing"` (:543/:577) and manual-trigger
  `"rejects non-integer issue_number"` (:879). These are infra/operator
  faults and must still page.
- [ ] **Keep** group (e) happy-path `"?status=ok with scheduled-bug-fixer slug"`
  (:762) and the no-qualifying-issue `status=ok` (:474).
- [ ] Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bug-fixer.test.ts`.

### Phase 4 — Recover the live monitor to healthy

- [ ] After merge + deploy, the **next natural 06:00 UTC fire** posts the new
  `status=ok` and `recovery_threshold = 1` flips the monitor green
  (`cron-monitors.tf:115`). No manual Sentry mutation needed.
- [ ] **Optional faster recovery (automatable, no SSH):** fire a manual
  trigger to post an immediate `ok` check-in via the Inngest event endpoint
  (operator/`gh`-auth path), confirming end-to-end before the next natural fire:
  ```bash
  # via the existing manual-trigger event (no issue_number → cron-equivalent run)
  curl -X POST "http://127.0.0.1:8288/e/<INNGEST_EVENT_KEY>" \
    -H "Content-Type: application/json" \
    -d '{"name":"cron/bug-fixer.manual-trigger","data":{}}'
  ```
  This is on-host; the no-SSH confirmation is to watch the
  `scheduled-bug-fixer` monitor flip to `ok` via the Sentry Crons monitor-list
  API (Phase 1 curl). Prefer waiting for the natural fire unless the operator
  wants immediate green.
- [ ] Close incident `5127648` / any auto-filed `failure_issue_threshold=1`
  GitHub issue once the monitor reports `ok` (use `Ref #N` not `Closes #N` if
  recovery is post-merge per `wg-use-closes-n-in-pr-body-not-title-to` ops
  variant; close via `gh issue close` after the green check-in).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] PR body names the confirmed hypothesis (H1/H2/H3/H4) with the Sentry
  event evidence pulled in Phase 1 (verdict rule output pasted).
- [ ] PR body states the `auth-callback-no-code-burst` linkage was confirmed
  coincidental (red herring), citing the 2026-05-27 precedent — the auth
  callback route is **not** modified by this PR (`git diff --name-only` shows
  no `app/(auth)/callback/route.ts`).
- [ ] (H1/H2 path) `cron-bug-fixer.ts` heartbeat `ok` is decoupled from
  `spawnResult.ok`: a clean end-to-end run with a non-zero claude exit and/or
  no detected PR posts `?status=ok`. `grep -n "status=ok\|status=error" `…
  semantics verified by the rewritten tests.
- [ ] (H1/H2 path) Genuine infra/operator faults still post `?status=error`:
  setup-workspace catch, bad manual-trigger payload, plugin-sentinel-missing.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bug-fixer.test.ts` is green, including the rewritten group (e) tests.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/function-registry-count.test.ts` still green (slug↔monitor parity unaffected).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

### Post-merge (operator/automatable)

- [ ] Next `0 6 * * *` UTC fire (or the optional manual trigger) posts
  `status=ok`; the `scheduled-bug-fixer` Sentry monitor reads `ok` via the
  Crons monitor-list API. Automation: pull via Phase 1 curl; not operator
  eyeballing. (Automation: feasible via Sentry API + Inngest manual-trigger.)
- [ ] Incident `5127648` and any auto-filed monitor-failure GitHub issue
  closed once the monitor is green.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal observability/ops cron
exit-condition fix. No user-facing surface, no schema, no auth/payments/data
movement. (The auth-callback route is explicitly out of scope per the
red-herring finding.)

## Observability

```yaml
liveness_signal:
  what: "scheduled-bug-fixer Sentry cron monitor check-in (status=ok)"
  cadence: "daily 0 6 * * * UTC"
  alert_target: "Sentry cron monitor 8f12e8fb-d232-4f53-8f2d-48fc80b81e8e (failure_issue_threshold=1, recovery_threshold=1)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf:107 + cron-bug-fixer.ts postSentryHeartbeat"
error_reporting:
  destination: "Sentry (reportSilentFallback) for genuine infra faults; structured logger.info/warn for benign no-fix outcomes"
  fail_loud: "infra faults page via status=error; benign no-fix is logged, not paged (the fix's whole point)"
failure_modes:
  - mode: "claude-eval non-zero exit (no fix today) — H1"
    detection: "spawnResult.ok === false with no infra reportSilentFallback"
    alert_route: "logger.info/breadcrumb only — NOT a page (post-fix)"
  - mode: "claude-eval 50-min timeout abort — H2"
    detection: "abortedByTimeout + durationMs ≈ 3_000_000; op=claude-eval-timeout"
    alert_route: "warning-level Sentry breadcrumb (non-paging); monitor stays ok"
  - mode: "workspace clone / token-mint failure — H3"
    detection: "reportSilentFallback op=setup-ephemeral-workspace|mint-installation-token|child_process.spawn"
    alert_route: "status=error → Sentry cron monitor page (kept strict)"
  - mode: "bad manual-trigger payload — H4"
    detection: "reportSilentFallback op=parse-event-data"
    alert_route: "status=error → page (kept strict)"
logs:
  where: "Inngest function logs (stdout/stderr line-streamed, token-redacted) + Sentry events"
  retention: "Sentry default project retention; Inngest run logs per server config"
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $SENTRY_API_TOKEN\" \"https://sentry.io/api/0/organizations/$SENTRY_ORG/monitors/scheduled-bug-fixer/checkins/?per_page=5\" | jq '.[] | {status, dateCreated}'"
  expected_output: "most recent check-in status == \"ok\" after the post-merge fire"
```

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` — (H1/H2) decouple heartbeat `ok` from `spawnResult.ok`; benign no-fix → `status=ok` + structured log; keep infra faults strict. (H3) no change here; fix the infra path.
- `apps/web-platform/test/server/inngest/cron-bug-fixer.test.ts` — rewrite group (e) non-zero-exit test to expect `status=ok`; add timeout-abort `status=ok` test; keep infra-fault `status=error` tests.

## Files to Create

- None. (Learning capture happens via `/soleur:compound` at ship time, directory `knowledge-base/project/learnings/bug-fixes/`, author picks date at write time.)

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` checked at plan time;
no open scope-out names `cron-bug-fixer.ts` or its test. The three open
`scheduled-bug-fixer`-mentioning issues — #2539, #3788, #2914 — are GHA-era
follow-throughs and content-publisher/CLA verifications, not exit-condition
scope-outs.)

## Research Insights (deepen-plan pass, 2026-06-01)

All claims below were verified live against the worktree at deepen time.

**Code-path verification (H1 mechanism — CONFIRMED):**

- `_cron-claude-eval-substrate.ts:231` — `ok: exitCode === 0`. A non-zero
  claude `--print` exit (max-turns exhaustion / no-fix terminal state)
  produces `spawnResult.ok === false`. Confirmed.
- `cron-bug-fixer.ts:756` `!detectedPr` early-return is `ok: spawnResult.ok`;
  `:792` `overallOk = spawnResult.ok && !!detectedPr` is reached only when
  `detectedPr` is truthy → `&& !!detectedPr` is **redundant/dead**, and
  `spawnResult.ok` alone drives the page. Confirmed — the fix target is
  precisely `spawnResult.ok`, not PR detection.
- Genuine infra faults have **independent** early-return error heartbeats:
  setup-workspace catch (`:691`, `op: setup-ephemeral-workspace`), bad
  manual-trigger (`:612`, `op: parse-event-data`), plugin-sentinel-missing
  (surfaces via setup-workspace catch, tested at `:543/:577`). Relaxing the
  *post-spawn* heartbeat to `ok:true` does NOT touch these — H3 infra failures
  still page. Confirmed.

**Test-harness verification (Phase 3 is complete + executable):**

- Full enumeration of heartbeat-status assertions in
  `cron-bug-fixer.test.ts`: `:489` (no-issue → ok, keep), `:577` (sentinel
  missing → error, keep), `:803` (happy path → ok, keep), `:828` (non-zero
  exit + no PR → error, **REWRITE to ok**), `:888` (bad manual trigger →
  error, keep). Phase 3 accounts for **all five** — no missed test pinning the
  old semantic.
- Return-value (`result.ok`) assertions: `:482`, `:566`, `:822`, `:888`. Only
  `:822` (the rewritten group-(e) test) flips `false→true`; the others assert
  genuine-error paths that stay `false`. Captured in the Phase 3 rewrite step.
- `wireSpawn(claudeExitCode)` (`:229`) takes the exit code as its arg → the H1
  scenario (`wireSpawn(1)`, no PR, expect `status=ok`) needs **no new mock
  plumbing**.
- Runner: `apps/web-platform/package.json:15` `"test": "vitest"`;
  `vitest.config.ts:44` node project `include: ["test/**/*.test.ts", ...]`.
  The prescribed path `test/server/inngest/cron-bug-fixer.test.ts` matches the
  glob. The Phase 0/3 run command is correct.

**Sentry Crons recovery semantics (Phase 4 — CONFIRMED behavior):**

- `cron-monitors.tf:107-117` `sentry_cron_monitor.scheduled_bug_fixer` has
  `recovery_threshold = 1`, so a single `?status=ok` check-in flips the
  monitor from error→ok automatically. The heartbeat is a single end-of-job
  POST (no in-progress/duration two-step — `cron-monitors.tf:37-46`), so the
  next natural `0 6 * * *` fire posting `ok` is sufficient; no manual Sentry
  API mutation is needed. The heartbeat URL shape
  (`/api/<project>/cron/<slug>/<key>/?status=<ok|error>`) is at
  `_cron-shared.ts:83`.

**Red-herring linkage (CONFIRMED via direct precedent):**

- `2026-05-27-sentry-cron-community-monitor-missed-checkin.md:21` —
  *"The alert was 'triggered by auth-callback-no-code-burst' — this was a red
  herring (coincidental unrelated Sentry issue alert routed to the same
  operator email)."* Runbook `cloud-scheduled-tasks.md:381` repeats it. That
  incident was a **missed** check-in (H9 Inngest desync,
  `cloud-scheduled-tasks.md:287`); the current incident is an **error**
  check-in (function fires, posts error) — H9 does NOT apply and its restart
  runbook must NOT be run here.

**Sibling-cohort note (scope discipline):** `cron-roadmap-review.ts:277` and
`cron-legal-audit.ts:263` post `ok: spawnResult.ok` (PR-agnostic) — they share
the same latent over-tight semantic (any claude non-zero exit pages) but have
not fired because their claude invocations exit 0 reliably. Per the Sharp Edge
below, fix bug-fixer inline and file a follow-up issue for the cohort rather
than silently widening this PR to all five claude-eval crons.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. (This plan's threshold is `none` with a reason
  bullet — valid.)
- **Do NOT run the H9 Inngest-desync restart runbook for this incident.** H9
  is for *missed* check-ins; this is an *error* check-in (the function is
  firing). Running `gh workflow run restart-inngest-server.yml` would be
  wasted action and masks the real (app-code) root cause.
- **Do NOT touch `app/(auth)/callback/route.ts`.** The
  `auth-callback-no-code-burst` alert is a coincidental email-channel collision
  (documented red herring). Modifying the callback chases the wrong signal.
- The final-branch `overallOk = spawnResult.ok && !!detectedPr` is **dead-code
  tight**: the `!detectedPr` early-return at `:756` means `!!detectedPr` is
  always `true` at `:792`. The true error driver is `spawnResult.ok` alone.
  Verify this with the Sentry event before assuming H1 — if Phase 1 shows an
  infra `op`, the fix is H3 (infra), not the exit-condition relaxation.
- Sibling claude-eval crons (`cron-roadmap-review.ts`, `cron-legal-audit.ts`)
  post `ok: spawnResult.ok` (PR-agnostic) — they also page on claude non-zero
  exit. If H1 is confirmed, consider whether the SAME relaxation should apply
  to them in a follow-up (they have not paged because their `claude` invocations
  more reliably exit 0, but they share the latent over-tight semantic). Scope
  decision at /work: fix bug-fixer inline; file a follow-up issue for the
  cohort if the pattern is systemic. Do NOT silently widen this PR to all five
  crons without explicit scoping.
