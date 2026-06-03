---
title: "fix: cron-community-monitor max-turns exhaustion produces no digest issue"
type: fix
date: 2026-06-03
branch: feat-one-shot-cron-community-monitor-spawn-liveness
lane: cross-domain
status: planned
related_issues: []
related_sentry:
  - eff0bef435664f4d929d2ac3aa3e6a7e  # WEB-PLATFORM-1Z scheduled-output-missing
related_prs:
  - "#4714 output-aware heartbeat"
  - "#4786 stdout-tail capture"
  - "#4468 GHA→Inngest migration"
brand_survival_threshold: aggregate-pattern
---

# fix: cron-community-monitor max-turns exhaustion → no digest issue 🐛

## Enhancement Summary

**Deepened on:** 2026-06-03 (inline — pipeline subagent cannot fan out parallel Task agents; gates + realism passes run inline per the documented platform limitation).
**Sections enhanced:** Overview, Root Cause, Hypotheses, Implementation Phases, Acceptance Criteria, Risks.

### Key Improvements
1. **Prompt-anchor blast radius quantified.** `cron-community-monitor.test.ts` asserts **27 verbatim prompt anchors** (`SUT_SOURCE.toContain(...)`) across two `it.each` blocks. AC5/Phase 2 now enumerate that the budget bump (Phase 1) touches NO anchor, and any Phase 2 prompt edit must avoid the 27 anchored substrings or update the matching anchor in lockstep.
2. **Turn-budget value pinned to the proven comparator** (daily-triage `--max-turns 80`, runs healthily through the SAME `DEFAULT_CLAUDE_SETTINGS`). Timeout-to-turns ratio computed (0.625 min/turn, in the 0.55–1.2 peer band).
3. **AC7 "heartbeat unchanged" verified against source** — `resolveOutputAwareOk(` (1 hit) and `ok: heartbeatOk` (2 hits) confirmed present; the `#4730` test block stays green.
4. **Scheduled-work precedent confirmed** — the cron is already an Inngest function (canonical per ADR-033); no GHA-cron migration needed.

### New Considerations Discovered
- The fix is **demand-side AND supply-side bounded**: raising `--max-turns` (supply) is the confirmed lever; prompt efficiency (demand) is a secondary lever gated empirically by AC9. A unit test cannot prove 80 is enough — only a live 7-platform fire can.
- Reordering the prompt so issue-create lands BEFORE the best-effort PR flow would make the artifact (monitor's success contract) survive a tight budget — but step 5 (Persist via PR) and step 6 (Create Issue) ordering is itself anchored indirectly via `git checkout -b` / `gh pr merge` / `[Scheduled] Community Monitor` anchors. Treat any reorder as anchor-affecting (update tests).

## Overview

The `cron-community-monitor` Inngest function (`soleur-runtime-cron-community-monitor`,
daily `0 8 * * *` UTC) fired on 2026-06-03 08:00, spawned `claude --print`, and the
spawn **exited 1 after exhausting its 50-turn budget** — `stdoutTail: "Error: Reached
max turns (50)\n"` — before reaching its final "create the `[Scheduled] Community
Monitor` GitHub issue" step. Because the issue is the function's success contract, the
output-aware heartbeat (`resolveOutputAwareOk`, PR #4714) correctly turned the Sentry
monitor RED and emitted the `scheduled-output-missing` event with the
`spawn exited non-zero AND created no "scheduled-community-monitor" issue` message.

**The liveness assertion is NOT over-firing — it is doing exactly its job.** The bug is
the spawned agent's **turn budget is too small for the task** (and the prompt spends
turns inefficiently). The community-monitor is a genuine always-create producer: every
run must write a dated digest and file a summary issue (even the no-platform path files
a `- FAILED` issue). So the `artifact-required` heartbeat contract is the right one; the
fix is to make the producer actually finish within budget, not to relax the monitor.

This is a **chronic** failure, not a one-off: the last successful digest was issue #4401
/ PR #4400 on **2026-05-25**. Nine days of zero output (the 2026-05-26/27 gap was the
Inngest-desync missed check-in documented in `2026-05-27-sentry-cron-community-monitor-missed-checkin.md`;
the cron has since resumed firing but now exhausts turns). The output-missing event is
count=1 only because the diagnostic machinery that surfaces it (#4714 output-aware
heartbeat + #4786 stdout-tail capture) is itself recent — before it, turn exhaustion was
a dark silent no-op.

## Root Cause (confirmed from live Sentry evidence)

Sentry event `eff0bef435664f4d929d2ac3aa3e6a7e` (WEB-PLATFORM-1Z), latest-event `extra`:

| field | value | meaning |
| --- | --- | --- |
| `exitCode` | `1` | claude `--print` non-zero exit |
| `spawnOk` | `false` | `exitCode !== 0` |
| `stderrTail` | `""` | no infra fault (no git/auth/network stderr) |
| `stdoutTail` | `"Error: Reached max turns (50)\n"` | **turn exhaustion** — the binding constraint |
| `runStartedAt` | `2026-06-03T08:00:08.046Z` | window start |
| event `dateCreated` | `2026-06-03T08:06:02Z` | **~6 min elapsed** — NOT a wall-clock timeout |

The ~6-minute elapsed time (vs the 50-min `MAX_TURN_DURATION_MS` wall-clock budget)
proves the agent hit the **turn count** ceiling, not the wall-clock ceiling. Raising
`MAX_TURN_DURATION_MS` alone would change nothing.

**Why 50 turns is insufficient.** The community-monitor task is heavier than the
proven-healthy comparator (`cron-daily-triage`, which runs reliably at `--max-turns 80`
and only comments on issues). Per the `2026-03-20-claude-code-action-max-turns-budget`
learning, the digest task must: load plugin context (~10 turns) + detect platforms +
collect from up to 7 platform commands across Discord/X/Bluesky/GitHub/HN + read the
brand guide + write the digest file + run the full git→PR→auto-merge flow + create the
summary issue + run the DEDUP check. The original 2026-03-20 estimate of ~23 task turns
predates the ephemeral-workspace plugin-loading and the expanded 7-command GitHub batch
(activity/contributors/discussions/repo-stats/fetch-interactions + 2 HN calls). 50 turns
no longer leaves error/retry headroom, and the issue-create is the **last** step — so any
overrun drops exactly the artifact the monitor requires.

## Research Reconciliation — Spec vs. Codebase

No spec/brainstorm preceded this plan (direct one-shot → plan path). The task argument
posed two hypotheses; both are resolved against live evidence:

| Premise (from task argument) | Reality (verified) | Plan response |
| --- | --- | --- |
| "spawn failure is the bug to fix" | Confirmed — `Reached max turns (50)`, exitCode 1, no infra fault | Fix the turn budget + prompt efficiency |
| "OR the liveness assertion is over-firing (monitor found nothing to report)" | Refuted — the producer ALWAYS creates an issue (even no-platform → `- FAILED` issue); zero output = real failure | Keep `artifact-required` contract; do NOT relax `resolveOutputAwareOk` |
| Sandbox `allow:[]` + `sandbox.enabled:true` blocks `gh issue create` (the #4689-era prime hypothesis) | Refuted previously by `2026-06-01-output-aware-cron-heartbeat...` (daily-triage produces output through the SAME settings); and here `stderrTail` is empty (a sandbox-denied write would surface) | Out of scope; not the cause |
| `ensure-labels: 3/3 failed` (WEB-PLATFORM-B) is part of this failure | Refuted — that event is tagged `inngest.fn_id=cron-follow-through-monitor`, a SEPARATE cron (the `gh auth login` unauth class in `2026-06-01-inngest-cron-gh-cli-needs-minted-app-token`). Not community-monitor. | Out of scope; note as sibling, do not fold in |
| `scheduled-community-monitor` label missing → create fails | Refuted — `gh label list` shows the label exists (`#0E8A16`) | Out of scope |

## Hypotheses (ranked, with the decisive probe for each)

- **H1 — turn-budget exhaustion (CONFIRMED).** `stdoutTail = "Error: Reached max turns
  (50)"`. Decisive: stdout notice + ~6-min elapsed (not wall-clock). **This is the cause.**
- **H2 — wall-clock timeout.** Refuted: `abortedByTimeout` would be true and ~50 min
  would elapse; only ~6 min did, and no `claude-eval-timeout` event was emitted.
- **H3 — infra fault (git clone / auth / DNS / disk).** Refuted: `stderrTail` empty; no
  `setup-ephemeral-workspace` / `child_process.spawn` / `git clone failed` event near the
  fire. (Per the Sentry-mechanics recipe: an infra fault would surface as a searchable
  project issue tagged `feature=cron-community-monitor` — none exists for this window.)
- **H4 — sandbox/permission denial of `gh`/write.** Refuted (see Reconciliation table).
- **H5 — monitor over-firing on a legitimately-empty run.** Refuted: the producer is
  always-create; an empty run is itself the failure.

## User-Brand Impact

**If this lands broken, the user experiences:** the operator (Soleur founder) loses the
daily community digest issue — no visibility into Discord/GitHub/HN/Bluesky activity,
new stargazers, or external interactions. Compounding: the Sentry monitor pages daily
(false-feeling, but actually-correct RED), training the operator to ignore the monitor.
**If this leaks, the user's data is exposed via:** N/A — no new data surface; the spawn
env allowlist is unchanged and the digest aggregates public/community-platform data only.
**Brand-survival threshold:** aggregate pattern — a single missed digest is a tolerable
internal-ops gap; the brand risk is the *chronic* dark-producer pattern + alert fatigue
across the cron cohort. (No `single-user incident` exposure; no `requires_cpo_signoff`.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `CLAUDE_CODE_FLAGS` in `cron-community-monitor.ts` sets `--max-turns` to the
  new value (proposed **80**, matching the proven-healthy daily-triage budget). Verify:
  `grep -A1 '"--max-turns"' apps/web-platform/server/inngest/functions/cron-community-monitor.ts`
  shows the new literal.
- [ ] AC2 — The header-comment turn-budget rationale (line ~35 `--max-turns 50 (was 40)`)
  is updated to the new value WITH a one-line rationale citing the max-turns learning and
  the daily-triage comparator. (Stale header comments are a documented drift surface.)
- [ ] AC3 — The prompt's data-collection step is restructured to spend fewer turns:
  the GitHub batch (step 2 Batch 2) and the Discord/X/Bluesky batch (Batch 1) each remain
  a single Bash call; the issue-create + DEDUP-check are positioned to survive a tight
  budget. (Decision in Phase 2 below — minimal prompt edit, preserving the verbatim-anchor
  test contract.)
- [ ] AC4 — `MAX_TURN_DURATION_MS` review: confirm 50-min wall-clock is still adequate for
  80 turns (ratio 0.625 min/turn, within the 0.55–1.2 peer band per the max-turns
  learning). Document the ratio in the header comment. If the new turn count would need
  more wall-clock, bump `MAX_TURN_DURATION_MS` in lockstep (the documented silent-failure
  pairing). **Note:** `MAX_TURN_DURATION_MS` is also exported and asserted by
  `cron-community-monitor.test.ts` (`expect(MAX_TURN_DURATION_MS).toBe(50 * 60 * 1000)`) —
  if changed, update that assertion too.
- [ ] AC5 — `cron-community-monitor.test.ts` passes (run the package's actual runner —
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts`).
  The prompt verbatim-anchor assertions (`SUT_SOURCE.toContain(...)`) MUST still pass. There
  are **27 anchored substrings** across two `it.each` blocks (enumerated in Research Insights
  below). The Phase 1 `--max-turns` bump touches NONE of them (no anchor pins the turn value).
  Any Phase 2 prompt edit MUST either avoid all 27 anchored substrings or update the matching
  anchor in lockstep in the same commit.
- [ ] AC6 — `tsc --noEmit` clean for `apps/web-platform`.
- [ ] AC7 — The output-aware heartbeat (`resolveOutputAwareOk`) and the `artifact-required`
  semantics are UNCHANGED. `SUT_SOURCE.not.toContain("ok: spawnResult.ok")` and
  `toContain("resolveOutputAwareOk(")` still hold (the `#4730` test block).

### Post-merge (operator / automated)

- [ ] AC8 — Trigger one live run via `/soleur:trigger-cron` (event
  `cron/community-monitor.manual-trigger`, allowlisted) and confirm it produces a
  `[Scheduled] Community Monitor - <date>` issue labeled `scheduled-community-monitor`
  within the run window. Verify via `gh issue list --label scheduled-community-monitor
  --state open --search 'Community Monitor in:title' --limit 3`. Automation: feasible via
  the trigger-cron skill (POST /api/internal/trigger-cron) + `gh` — bake into ship/work, do
  NOT punt to operator dashboard-watching.
- [ ] AC9 — After the live run, confirm the Sentry monitor `scheduled-community-monitor`
  posted `status=ok` (not error) for that fire. Verify via the documented check-ins API
  (`SENTRY_API_TOKEN`, `/monitors/scheduled-community-monitor/checkins/`). If still RED with
  `Reached max turns (N)` at the new budget, the prompt-efficiency lever (Phase 2) was
  insufficient — re-open with the new stdoutTail evidence.

## Implementation Phases

### Phase 0 — Preconditions (verify against installed code)
- Read `cron-community-monitor.ts` and `cron-community-monitor.test.ts` in full before any
  edit (Read-before-Edit). Enumerate every `SUT_SOURCE.toContain(...)` prompt anchor and
  every constant assertion (`MAX_TURN_DURATION_MS`) so the edit blast radius is known.
- Confirm daily-triage's proven budget (`--max-turns 80`, `MAX_TURN_DURATION_MS 60min`,
  narrowed `Bash(gh ...:*)`) as the comparator basis for the chosen value.

### Phase 1 — Raise the turn budget (the confirmed fix)
- Edit `CLAUDE_CODE_FLAGS` `--max-turns` `50` → `80`.
- Update header comment line ~35 rationale + add the timeout-to-turns ratio line.
- Decide `MAX_TURN_DURATION_MS`: 50 min ÷ 80 turns = 0.625 min/turn (in-band) — likely keep
  50 min and keep the test assertion. If raised, update the test assertion in lockstep.

### Phase 2 — Prompt turn-efficiency (reduce the demand side)
- Minimal edits to `COMMUNITY_MONITOR_PROMPT` to conserve turns WITHOUT breaking
  verbatim-anchor tests: ensure the data-collection batching directives are intact;
  consider reinforcing "create the issue FIRST from collected data, then the PR is
  best-effort" so the artifact (the monitor's success contract) lands before any budget
  overrun. Any prompt-text change MUST be mirrored in the test anchor or confined to
  non-asserted text. (Conservative default: budget bump alone may suffice — AC9 is the
  empirical gate. Keep prompt edits minimal to avoid anchor churn.)

### Phase 3 — Tests
- Run `cron-community-monitor.test.ts` + `tsc --noEmit`. Update anchors/constants only as
  required by Phases 1–2.

### Phase 4 — Live verification (post-merge)
- Per AC8/AC9 via trigger-cron + `gh` + Sentry check-ins API.

## Files to Edit
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — `CLAUDE_CODE_FLAGS`
  `--max-turns` value; header-comment rationale + ratio; possibly `MAX_TURN_DURATION_MS`;
  minimal prompt edits.
- `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` — only IF a changed
  constant (`MAX_TURN_DURATION_MS`) or an asserted prompt anchor is touched.

## Files to Create
- None (pure code/config change against an already-provisioned surface).

## Open Code-Review Overlap
None checked yet — run the Phase 1.7.5 overlap query against `## Files to Edit` at
deepen-plan time. (No open code-review issues are known to touch these two files.)

## Domain Review

**Domains relevant:** Engineering (CTO) — infrastructure/observability tuning.

No UI surface (no `components/**`, `app/**/page.tsx` in Files to Edit) → Product/UX Gate
NONE. No regulated-data surface (GDPR gate skip). The change is a turn-budget + prompt
tuning on an existing cron — Engineering-only.

### Engineering (CTO)
**Status:** reviewed (inline)
**Assessment:** The fix matches the established cohort pattern (daily-triage budget) and
the documented max-turns learning. The key CTO concern — "does this new turn budget mirror
a predicate already proven elsewhere?" — is satisfied: daily-triage runs healthily at 80.
The `artifact-required` heartbeat contract is correctly retained (community-monitor is a
true always-create producer, unlike the best-effort bug-fixer whose contract was relaxed in
#4730). The timeout-to-turns ratio is held in-band (0.625 min/turn).

## Infrastructure (IaC)
Skip — no new infrastructure. The Sentry monitor `scheduled-community-monitor` already
exists in `apps/web-platform/infra/sentry/cron-monitors.tf` (margin 30 / runtime 10) and is
NOT modified by this plan. No new server, secret, vendor, or persistent process.

## Observability

```yaml
liveness_signal:
  what: scheduled-community-monitor Sentry cron monitor (output-aware heartbeat)
  cadence: daily 0 8 * * * UTC
  alert_target: Sentry cron monitor (status=ok|error) → operator email
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (slug scheduled-community-monitor)
error_reporting:
  destination: Sentry via reportSilentFallback (op=scheduled-output-missing) carrying exitCode + stdoutTail + stderrTail
  fail_loud: yes — heartbeat posts status=error and the scheduled-output-missing event fires
failure_modes:
  - mode: turn-budget exhaustion (this bug)
    detection: stdoutTail "Reached max turns (N)" in scheduled-output-missing extra
    alert_route: Sentry monitor RED + scheduled-output-missing event
  - mode: wall-clock timeout
    detection: abortedByTimeout=true + claude-eval-timeout event
    alert_route: Sentry monitor RED + claude-eval-timeout event
  - mode: infra fault (clone/auth/disk)
    detection: stderrTail populated + setup-ephemeral-workspace / child_process.spawn event
    alert_route: early-return status=error heartbeat
logs:
  where: app stdout (pino) → Better Stack via Vector (post #4786); stdout/stderr tails folded into Sentry extra
  retention: Better Stack default + Sentry 90d issue retention
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $SENTRY_API_TOKEN\" \"https://sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-community-monitor/checkins/?per_page=5\" | jq -r '.[] | \"\\(.dateCreated) \\(.status)\"'"
  expected_output: most recent check-in shows status=ok after the post-merge live run (AC9)
```

## Test Scenarios
- Existing unit suite (`cron-community-monitor.test.ts`) — source-shape + anchor + heartbeat
  contract assertions; updated only for touched constants/anchors.
- Live end-to-end (post-merge AC8/AC9) — the binding empirical gate, since turn-budget
  adequacy can only be proven against a real 7-platform fire, not a unit test.

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Relax the `artifact-required` heartbeat to `liveness` (don't require the issue) | Rejected — community-monitor is a true always-create producer; relaxing it re-creates the dark-silent-no-op the #4714 mechanism was built to kill. The monitor is correct. |
| Raise `MAX_TURN_DURATION_MS` (wall-clock) only | Rejected — the failure is turn-count (~6 min elapsed), not wall-clock; this no-ops. |
| Widen `--allowedTools` / sandbox to "unblock gh" | Rejected — refuted hypothesis (empty stderrTail; daily-triage works through the same settings). |
| Bump `--max-turns` to 80 (daily-triage parity) + minimal prompt efficiency | **Chosen** — matches the proven comparator and the documented turn-budget formula; AC9 is the empirical gate. |

## Research Insights

### Precedent-Diff Gate (Phase 4.4)

The scheduled-job precedent is confirmed canonical: `cron-community-monitor.ts` is already an
**Inngest** function (`apps/web-platform/server/inngest/functions/cron-*.ts`), per ADR-033 —
NOT a GHA `scheduled-*.yml` workflow. No migration. The turn-budget pattern has a direct
in-repo precedent:

| | community-monitor (failing) | daily-triage (proven healthy) |
| --- | --- | --- |
| `--max-turns` | 50 → **80 (proposed)** | 80 |
| `MAX_TURN_DURATION_MS` | 50 min | 60 min |
| ratio (min/turn) | 1.0 → **0.625** | 0.75 |
| `--allowedTools` Bash | wholesale `Bash` | narrowed `Bash(gh ...:*)` |
| `DEFAULT_CLAUDE_SETTINGS` | `allow:[]` + `sandbox.enabled:true` | same |
| task weight | heavier (7 platforms + digest + PR + issue) | lighter (comment on issues) |

daily-triage proves 80 turns + the shared sandbox settings reliably produce output. The
community-monitor's heavier task at the smaller 50-turn budget is the gap. Matching daily-
triage's 80 is the precedent-grounded value. (Narrowing `--allowedTools` like daily-triage is
NOT proposed here — it would change the bucket-ii security surface and is out of scope.)

### The 27 prompt anchors (AC5 blast radius)

`apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` asserts these via
`SUT_SOURCE.toContain(...)`. A Phase 2 prompt edit MUST NOT alter any of these substrings
without updating the test in the same commit:

**original-GHA anchors (19):** `You are a community monitoring agent` · `## Instructions` ·
`plugins/soleur/skills/community/scripts/community-router.sh` ·
`ROUTER="plugins/soleur/skills/community/scripts/community-router.sh"` ·
`knowledge-base/support/community/` · `YYYY-MM-DD-digest.md` · `[Scheduled] Community Monitor` ·
`scheduled-community-monitor` · `--milestone "Post-MVP / Later"` · `## Period` ·
`## Activity Summary` · `## Top Contributors` · `Repository Stats` · `Community Interactions` ·
`bash $ROUTER discord` · `bash $ROUTER github activity` · `bash $ROUTER hn mentions` ·
`bash $ROUTER bsky get-metrics`

**safety-guard anchors (8):** `MILESTONE RULE:` · `Do NOT push directly to main` ·
`git checkout -b` · `gh pr merge` · `DEDUP RULE` · `within the last 24 hours` ·
`CLONE DEPTH RULE:` · `post your findings as a comment on the most recent existing issue`

### Verify-the-negative pass (Phase 4.45)

- Plan claims `resolveOutputAwareOk` + `ok: heartbeatOk` are UNCHANGED → confirmed present in
  source (`grep -c "resolveOutputAwareOk("` = 1; `grep -c "ok: heartbeatOk"` = 2). AC7 holds.
- Plan claims the `ensure-labels: 3/3 failed` event is a SEPARATE cron → confirmed: that
  event is tagged `inngest.fn_id=cron-follow-through-monitor` (a different fn). Not folded in.
- Plan claims the `scheduled-community-monitor` label EXISTS → confirmed via `gh label list`
  (`#0E8A16`). The issue-create will not fail on a missing label.

### Live Sentry diagnostic recipe (reusable, no SSH)

```bash
TOK=$(doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain)
# latest event extra (exitCode/stdoutTail/stderrTail) — org-scoped events endpoint works,
# the numeric /issues/<id>/ and project-scoped events/latest both 401 with this token:
curl -s -H "Authorization: Bearer $TOK" \
  "https://sentry.io/api/0/organizations/jikigai-eu/issues/124662213/events/latest/" \
  | jq '[.. | objects | to_entries[] | select(.key|test("exitCode|stdoutTail|stderrTail|spawnOk";"i"))] | unique_by(.key)'
```

This is how the root cause (`stdoutTail: "Error: Reached max turns (50)"`) was pulled.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- The prompt is asserted verbatim by `SUT_SOURCE.toContain(...)` anchors in the test file —
  any prompt edit must update the matching anchor or be confined to non-asserted text.
  Enumerate anchors (Phase 0) before editing.
- `MAX_TURN_DURATION_MS` is exported AND asserted (`toBe(50 * 60 * 1000)`); if changed,
  update the test in the same commit.
- This is the FIRST emission of the `scheduled-output-missing` event for this cron
  (count=1) only because #4714/#4786 are recent — do not read the low count as "rare"; the
  producer has been silent since 2026-05-25.
- Use `Ref #<issue>` not `Closes #<issue>` IF a tracking issue is filed, because the real
  fix-confirmation (AC9 live run) happens post-merge.
