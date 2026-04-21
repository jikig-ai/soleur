---
name: Cloud Routines sub-agent auth inheritance (H6)
description: Claude Code Cloud Routines that invoke /soleur:* sub-skills silently fail to produce PRs/issues — sub-agent sessions lose GitHub MCP + Doppler auth
category: integration-issues
module: cloud-routines
issue: 2742
parent_issue: 2714
related_issues: [2716, 2743, 2744, 1095, 2050]
related_learnings:
  - 2026-04-03-content-cadence-gap-cloud-task-migration.md
  - 2026-04-21-cloud-task-silence-watchdog-pattern.md
  - 2026-03-13-browser-tasks-require-playwright-not-manual-labels.md
pr: 2744
date: 2026-04-21
---

# Learning: Cloud Routines sub-agent auth inheritance (H6)

## Problem

Content Generator Cloud Routine (twice-weekly Tue/Thu 10:00 UTC) reported "Success" for Apr 2, 7, 9 runs and "Failed" for Apr 14, 16 runs in the Claude Code Routines UI — but **zero PRs and zero labeled audit issues were produced on any of those dates** (`gh pr list` + `gh issue list` scoped to the window both returned `[]`). The `scheduled-content-generator` label corpus was silent from 2026-03-31 (#1348) → 2026-04-21. Watchdog from #2716 detected the silence correctly; the #2742 follow-through triggered this diagnosis.

The runbook at `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` (shipped in #2716) defined hypotheses H1-H5 — all five were ruled out.

## Investigation

**H1 — task paused/deleted/orphaned:** Cloud UI showed routine Active, correct cron `0 10 * * 2,4`, next run populated. RULED OUT.

**H2 — task runs but fails fast before audit step:** Runs history showed invocations in the window; but SUCCESS runs produced zero artifacts, not just FAIL runs. Not classical H2.

**H3 — Doppler token rotated/revoked:** `doppler configs tokens --project soleur --config prd_scheduled` showed the `cloud-scheduled-tasks` service token from 2026-03-24 with read access and no rotation. RULED OUT from metadata alone (no need to compare in-UI token value).

**H4 — concurrency deadlock:** No stuck "running" rows in Cloud run history. RULED OUT.

**H5 — queue file format changed:** `git diff` of the one in-window queue edit (`e4320d55`) showed a valid row structure. RULED OUT.

**Breakthrough:** opened the Apr 9 SUCCESS session (session_0124vCyKFcvhPZX6viNkepNd) in the Claude Code UI. Model output at the end of the session stated verbatim:

> "Doppler returned Forbidden for all configs, GitHub MCP tools unavailable in this session, gh CLI unauthenticated, git proxy handles only git operations (not API). The branch is pushed at <https://github.com/jikig-ai/soleur/pull/new/ci/content-gen-2026-04-09-101841> — PR creation requires manual action or a session with GitHub credentials."

So the session:

- DID clone the repo (git proxy, auto-authenticated)
- DID generate the article file + distribution file (Anthropic-native tools, no auth needed)
- DID commit and push a branch (git proxy)
- DID NOT create the PR (`gh pr create` unauthenticated)
- DID NOT create the audit issue (`gh issue create` unauthenticated)
- DID NOT auto-merge (`gh pr merge` unauthenticated)

Cloud Routines UI marked it "Success" anyway because the MCP session terminated cleanly. Peer routine Daily Issue Triage on the same repo/project runs `gh issue list`/`gh issue view`/`gh issue edit` **directly from the top-level prompt** and succeeds every day, confirming that `gh` auth IS available in routine sessions.

Difference: Content Generator's prompt invokes `/soleur:content-writer --headless` and `/soleur:social-distribute --headless`. These sub-skills spawn **sub-agents** with their own sessions. The GitHub MCP auth context is NOT inherited into those sub-agent sessions. By the time control returns to the top-level prompt and reaches STEP 6 / MANDATORY FINAL STEP, `gh` and GitHub MCP are both unauthenticated.

## Root Cause

**Sub-agent auth inheritance boundary:** Claude Code Cloud Routine sessions provision GitHub MCP tools + git proxy auth at the **top level only**. Sub-agents spawned via `/soleur:*` skill invocations run in isolated sessions that do NOT inherit these integrations. Any `gh` / GitHub MCP / Doppler call made after a sub-agent returns operates in an unauthenticated context.

This is a **detection-surface mismatch failure mode**: the Cloud UI's binary SUCCESS/FAIL is based on MCP loop termination, not on whether the routine produced its intended side effects. A routine can burn compute every scheduled fire, spend Anthropic tokens, generate content files locally, push branches, and still report "Success" while producing zero GitHub-visible output.

## Solution

**Option B (chosen): revert to GHA scheduling.** Mirrors Growth Audit's rollback #2050, which documented the same failure mode 8 days earlier in Jean's own commit message:

> *"Cloud Remote Trigger cannot load Soleur plugin skills, causing silent failures since 2026-03-25. Moving back to GHA where claude-code-action has full plugin support."*

PR #2744 diff (minimal):

```diff
 on:
-  # MIGRATED TO CLOUD SCHEDULED TASK — 2026-03-25 (PR #1095).
-  # Silence detection: .github/workflows/scheduled-cloud-task-heartbeat.yml (#2714).
-  # Diagnosis/restore runbook: knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md
-  # Uncomment schedule to revert to GHA execution.
-  # schedule:
-  #   - cron: '0 10 * * 2,4'  # Tuesday + Thursday 10:00 UTC
+  schedule:
+    - cron: '0 10 * * 2,4'  # Tuesday + Thursday 10:00 UTC
   workflow_dispatch:
```

Operator actions (outside repo):

1. Paused the Cloud Routine via `claude.ai/code/routines/<id>` toggle.
2. Renamed to `Content Generator (DISABLED — migrated back to GHA)` to match Growth Audit's precedent. Kept the routine for historical reference; un-pausing it will NOT restore the broken behavior because the GHA cron now owns the schedule.
3. Verified post-merge with `gh workflow run scheduled-content-generator.yml` — produced labeled audit issue + article PR.

## Key Insight

**Two overlapping blind spots produce Cloud Routine silent output drop:**

1. **UI telemetry reports SUCCESS for any cleanly-terminated MCP session**, regardless of whether the side effects the prompt required actually happened.
2. **`/soleur:*` sub-skill invocations inside Cloud Routine prompts run in sub-agent sessions that do NOT inherit GitHub MCP / Doppler auth.**

If *either* blind spot is closed, the silence becomes visible. Today, the only defensive mechanism is the heartbeat watchdog on the *output* surface (labeled audit issues) from #2716. A content-generator that runs every Tue/Thu 10 UTC but produces no GitHub artifacts is invisible to Cloud UI — only to the output-surface watchdog.

**Default rule: any Cloud Routine whose prompt invokes `/soleur:*` skills should run under GHA (`claude-code-action`), not Cloud Routines.** GHA has first-class plugin + `GITHUB_TOKEN` support; Cloud Routines do not.

## Related

- #1095 — Original Cloud migration of 3 scheduled workflows (2026-03-25). All 3 (growth-audit, content-generator, community-monitor) exhibited this failure mode; growth-audit was reverted in #2050, content-generator in this PR, community-monitor is Paused with no restore yet.
- #2050 — Growth Audit rollback (2026-04-13). Pre-documented this exact failure mode in its commit message 8 days before this session — the insight was in git history but not in AGENTS.md or constitution.md.
- #2716 — Watchdog + runbook infrastructure. Runbook's H1-H5 reflected the pre-rebrand "Scheduled Tasks" model and missed the sub-agent boundary entirely.
- #2742 — This follow-through issue; auto-closed via PR #2744.
- #2743 — Time-gated verification (Thu 2026-04-23 10:00 UTC natural cron fire).

## Session Errors

Errors encountered during this one-shot session. Each includes **Recovery** and **Prevention**:

1. **Playwright click on notification "Not Now" dialog (ref=e696) timed out** — modal overlay intercepted pointer events. **Recovery:** re-snapshotted to get fresh refs, clicked "Don't ask me again" instead. **Prevention:** when `browser_click` errors with `intercepts pointer events`, always re-snapshot before retrying — ref may have changed or a competing modal may be on top.

2. **Switch toggle `browser_click(ref=e228)` timed out** — underlying `input[role=switch]` was `sr-only` (visually hidden, screen-reader-only); visible DOM was a styled wrapper `div`. **Recovery:** used `browser_evaluate` to call `.click()` on `input.closest('label')`. **Prevention:** for routine state toggles (Enable/Active), prefer `browser_evaluate` clicking the visible label over `browser_click` on the sr-only input.

3. **PreToolUse `security_reminder_hook.py` emitted an error-shaped warning on first workflow YAML edit** — output looked like a hard block, but retrying the identical edit succeeded. **Recovery:** retried identical `Edit` call. **Prevention:** security-reminder hooks warn, they don't block. Treat "PreToolUse:Edit hook error" output on `.github/workflows/*.yml` as informational; retry once before assuming failure. Proposed follow-up: hook should exit 0 with `stdout` warning rather than error-shaped output.

4. **Runbook H1-H5 did not match the actual root cause** (H6 sub-agent auth inheritance was novel). **Recovery:** diagnosed independently by opening the Cloud session transcript and reading the model's own end-of-session output. **Prevention:** runbook should add H6 as the **first** hypothesis for any Cloud Routine whose prompt invokes `/soleur:*` sub-skills. Filed separately as follow-up.

5. **Plan Non-Goals hard-banned the correct fix** — "Not reverting the GHA → Cloud migration from PR #1095" was listed as a Non-Goal, but diagnosis showed reverting WAS the right call. Founder override required. **Recovery:** surfaced the conflict, founder waived. **Prevention:** plan templates should treat Non-Goals as "soft — waive if diagnosis reveals otherwise" rather than hard bans. Specifically for operational runbook-execution plans where the diagnosis may surface a different fault model than the plan anticipated.

6. **Modal scroll targeted wrong DOM container** — scrolled `[role=dialog]` then `document` before discovering `.fixed.z-modal` was the scrollable wrapper. **Recovery:** scrolled `.fixed.z-modal` directly. **Prevention:** for Claude Code modal dialogs, `.fixed.z-modal` is the scrollable ancestor. Add to Playwright MCP Contract in future ops plans.

7. **React render race on `dialog.querySelector('input[type="text"]')`** — returned null on first call, then 1ms later `querySelectorAll('input')` found the same input with value "Content Generator". **Recovery:** use `querySelectorAll` and filter client-side. **Prevention:** for React dialogs that just opened, avoid type-specific initial queries; use `querySelectorAll` + filter to absorb render jitter.

8. **Forwarded from session-state.md (plan phase):** "Authored a new operator-execution plan distinct from the shipped infra plan" — two sibling plans for the same outcome space (infra plan for watchdog, ops plan for operator execution). **Prevention:** plan skill should detect same-issue plan siblings under `knowledge-base/project/plans/` and prompt for consolidation or explicit separation reason.

## Tags

category: integration-issues
module: cloud-routines
component: claude-code-routines
severity: high
failure-mode: silent-output-drop
scope: cloud-max-scheduling
