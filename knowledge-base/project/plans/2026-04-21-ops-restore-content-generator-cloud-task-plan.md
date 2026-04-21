---
title: "ops: diagnose + restore content-generator Cloud scheduled task (H1-H5)"
type: ops
date: 2026-04-21
issue: 2742
parent_issue: 2714
related_issues: [2716, 2743]
branch: feat-one-shot-restore-content-generator-cloud-task
worktree: .worktrees/feat-one-shot-restore-content-generator-cloud-task
---

# Diagnose + restore content-generator Cloud scheduled task

## Enhancement Summary

**Deepened on:** 2026-04-21
**Sections enhanced:** Hypotheses (H1-H5 verification detail), Execution Order
(Playwright MCP specifics, handoff protocol), Risks (session-cookie expiry,
rate-limit backoff), new "Comment Template" prescription, new "Playwright MCP
Contract" section, new "Operator Safety Gates" section.

**Research sources used:**

- Runbook: `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`
  (authoritative H1-H5 source).
- Learning: `knowledge-base/project/learnings/2026-04-21-cloud-task-silence-watchdog-pattern.md`
  (strict-mode arithmetic pitfall; audit-label contract).
- Learning: `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`
  (frontmatter instruction drop in #1095 Cloud migration).
- Learning: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
  (silent empty-env on rotated `prd_scheduled` token).
- Learning: `knowledge-base/project/learnings/2026-03-13-browser-tasks-require-playwright-not-manual-labels.md`
  (Playwright MCP covers ~95% of browser tasks; only CAPTCHA + OAuth consent
  are genuinely manual).
- Learning: `knowledge-base/project/learnings/2026-03-09-x-provisioning-playwright-automation.md`
  (semi-automated provisioning pattern: automate mechanical steps, pause for
  credentials, resume).
- AGENTS.md rules: `hr-exhaust-all-automated-options-before`,
  `hr-when-playwright-mcp-hits-an-auth-wall`,
  `hr-menu-option-ack-not-prod-write-auth`,
  `cq-doppler-service-tokens-are-per-config`,
  `cq-after-completing-a-playwright-task-call`,
  `wg-when-a-feature-creates-external`.

### Key Improvements

1. **Playwright MCP Contract explicit.** The auth handoff is one specific
   gate (login form at `login.anthropic.com` or equivalent OAuth consent);
   everything else (task list render, status inspection, run-log screenshots,
   "Run now" click, env var paste) is automated. No step is labeled "manual"
   without first attempting Playwright automation — per learning 2026-03-13.
2. **Comment Template pre-filled.** Rather than "post a comment summarizing
   the diagnosis," the plan now includes the exact markdown structure with
   placeholder anchors. Reduces post-diagnosis decision fatigue.
3. **Operator Safety Gates consolidated.** All destructive prod writes (H3
   Doppler rotation + Cloud task re-save) route through a single explicit
   ack gate modeled on `hr-menu-option-ack-not-prod-write-auth` — no
   `--yes`/`--force`/`-auto-approve` permitted.
4. **H-sequence termination rule made explicit.** "Stop at first CONFIRMED
   hypothesis" is now a loud rule; each H* section ends with an explicit
   jump-to-Phase-6 trigger. Prevents the false-ruling-out anti-pattern the
   plan's §Risks called out.
5. **Screenshot hygiene documented.** Redaction contract for env-var screens
   and Doppler-token comparison screens — never post raw token values in
   #2714 comment attachments.
6. **Post-restore verification depth increased.** Phase 6 now checks the
   auto-opened PR's distribution-file frontmatter against the three
   required fields (`publish_date`, `status`, `channels`) — the exact
   regression vector called out in the 2026-04-03 cadence-gap learning.

### New Considerations Discovered

- **Race with the next scheduled Tuesday fire.** If the diagnosis + restore
  completes within ~24 hours, the Tue 2026-04-22 10:00 UTC fire serves as
  natural-cadence verification. If the session runs past 10:00 UTC Tuesday,
  the "Run now" dry-run in Phase 6 is NOT a substitute for schedule
  verification — the watchdog specifically gates on the scheduled surface,
  not the manual-dispatch surface. Plan §Dependencies now calls this out.
- **Rate-limit backoff on `claude.ai/code`.** Cloud Max plan imposes
  concurrent-invocation limits. If Phase 6 "Run now" is triggered while
  another peer task is mid-invocation, the request may queue or silently
  drop. Wait for the task-list UI to show the Content Generator row as
  "idle" before the dry-run click.
- **Dry-run creates a real PR that auto-merges.** The pipeline routes
  through `gh pr merge --squash --auto`, so the dry-run will land in main
  within minutes. This is intentional (it matches real-schedule behavior)
  but means the founder should scan the generated article PR title/body
  before stepping away. If the generated article is obviously malformed,
  immediately `gh pr close <N>` before auto-merge fires.
- **Session-state.md co-location.** The prior ship iteration (PR #2716)
  created `knowledge-base/project/specs/feat-one-shot-2714-scheduled-content-generator/session-state.md`
  under a DIFFERENT spec directory. This plan's tasks.md lives under
  `feat-one-shot-restore-content-generator-cloud-task/` — the two are
  siblings, not the same spec. No merge conflict expected.

## Overview

Operator follow-through from PR #2716. The content-generator Cloud scheduled task
(execution surface: `claude.ai/code` → `soleur-scheduled` environment) silently
stopped firing between **2026-03-31** (last audit issue #1348) and **2026-04-21**
(manual dispatch #2692 restored the pipeline end-to-end but NOT the schedule).
This plan executes the H1-H5 diagnosis checklist from
`knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`, restores the
scheduled task in the Cloud UI, and records the confirmed hypothesis as a
comment on the original tracking issue #2714.

This is an **operator + browser-automation** plan. Zero repo code changes are
expected unless H2 (prompt-level bug) or H5 (queue-format bug) is the confirmed
cause — both of those would carve off into their own PRs after diagnosis.

## Scope

**In scope:**

1. Run the H1-H5 diagnosis checklist in order, each with its cheap verification
   step (runbook §Diagnosis Checklist).
2. Apply the hypothesis-specific restore action (runbook §Restore Procedure).
3. Manual dry-run to confirm the restored task produces a labeled audit issue.
4. Record diagnosis + restore evidence as a comment on #2714.
5. Attempt all browser interactions via Playwright MCP first
   (`hr-exhaust-all-automated-options-before`,
    `hr-when-playwright-mcp-hits-an-auth-wall`).

**Out of scope (explicitly deferred):**

- **Verification of next scheduled fire** — tracked by #2743 (Tue 2026-04-22
  10:00 UTC or Thu 2026-04-24 10:00 UTC). Time-gated; not actionable today.
- **Watchdog workflow behavior** — already shipped in #2716 and will
  auto-open a `cloud-task-silence` issue on 2026-04-25 if the task remains
  silent; `close-orphans` job will auto-close once the next audit issue lands.
- **Repo changes for H2 or H5** — if diagnosis lands on either, record the
  finding on #2714 and open a separate fix-PR per the runbook's "Apply the
  hypothesis-specific fix" step. Do not bundle into this ops follow-through.
- **Migration away from Cloud tasks** — not needed; all peer Cloud tasks
  continue firing.

## Research Reconciliation — Spec vs. Codebase

| Claim (from #2714 / #2742) | Reality | Plan response |
|---|---|---|
| "Silence between 2026-03-31 and 2026-04-21" | `gh issue list --label scheduled-content-generator` shows last auto-issue #1348 on 2026-03-31; #2692 on 2026-04-21 is a manual `workflow_dispatch`, so the scheduled-surface silence window is exactly `2026-04-02 → 2026-04-21` (two missed Tuesdays, three missed Thursdays = 5 missed fires). | Accurate. Use 2026-04-02 as the silence-window start in the #2714 comment. |
| "Follow runbook §H1-H5" | Runbook exists at `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` (merged in #2716). Each H* has explicit verify + restore steps. | Execute in order; stop at first confirmed hypothesis. |
| "Restore at claude.ai/code in soleur-scheduled" | The Claude Code Cloud UI is the only surface exposing task status/pause/run-logs. No REST API alternative known. | Playwright MCP is the automation path; runtime credential prompt at login per `hr-when-playwright-mcp-hits-an-auth-wall`. |
| "Playwright MCP for claude.ai/code login" | `claude.ai/code` requires authenticated Anthropic session. No headless credential path in Doppler (`doppler secrets --project soleur --config prd` does not carry anthropic.com session cookies). | Plan hands off to the founder for the single login step, browser stays open, session resumes per rule. |
| Doppler `prd_scheduled` token rotation date | `doppler configs tokens --project soleur --config prd_scheduled` shows `cloud-scheduled-tasks` token created 2026-03-24T23:00:34Z. No rotation since. | H3 confirmed **low-probability** pre-diagnosis but still require the `Verify` check per runbook. |
| `seo-refresh-queue.md` edit during silence window | `git log --since=2026-03-31 --until=2026-04-10 -- knowledge-base/marketing/seo-refresh-queue.md` shows commit `aac10749` on 2026-03-31 (`auto-generate Soleur vs. Paperclip`) and `e4320d55` on 2026-04-01 (`biweekly keyword optimization`). One post-silence-start edit is a valid H5 candidate. | Include the 2026-04-01 diff as explicit verification input when H5 is reached. |

## Hypotheses (runbook checklist, ordered by prior probability)

### H1 — Cloud task paused, deleted, or orphaned  [MOST LIKELY — P~0.55]

**Prior evidence:** Peer Cloud tasks (community-monitor daily, growth-audit
weekly, campaign-calendar weekly) all continued firing during the silence
window. A per-task fault (paused in UI / deleted during cleanup / session
expired) matches the observed isolation.

**Verify:**

1. Navigate Playwright MCP to `https://claude.ai/code`.
2. If auth-walled, keep the browser open and prompt the founder to log in
   (per `hr-when-playwright-mcp-hits-an-auth-wall`).
3. Open the `soleur-scheduled` environment.
4. List tasks. Screenshot the list.
5. Locate the Content Generator task. Record: exists? schedule = `Tue + Thu
   10:00 UTC`? status = `active`?

**Restore (H1):**

- If **paused:** click un-pause. Screenshot post-state.
- If **deleted:** re-create from the canonical prompt. The Cloud-task prompt
  lives (for reference) in the same structure as
  `.github/workflows/scheduled-content-generator.yml` lines 61-164. Reconcile
  against the 2026-04-03 learning: **frontmatter instruction
  (`publish_date: <today>`, `status: scheduled`, `channels: ...`) MUST be
  present** — this was the line dropped in the original #1095 migration.
- If **orphaned** (session expired, task greyed-out or flagged): re-auth Cloud
  session, re-save the task. Screenshot post-state.

### H2 — Task runs but fails fast before the audit-issue step  [P~0.20]

**Prior evidence:** Absence of any `FAILED` or `FAIL Citations:` issue under
the `scheduled-content-generator` label during the silence window is mild
negative evidence, but the runbook flags this as the second most likely
scenario because early-exit paths in the prompt (plugin marketplace load
failure, missing doppler CLI, network timeout to `github.com`) abort before
the issue-creation `gh issue create` call.

**Verify (only if H1 ruled out):**

1. In the `soleur-scheduled` task UI, open the Content Generator task's run
   history. Screenshot the last ~20 run rows (look specifically for
   invocations between 2026-04-02 and 2026-04-21).
2. For any run in that window: open the run detail, screenshot the first
   non-empty error line.
3. Classify: (a) zero invocations in the window → NOT H2 (go to H3);
   (b) invocations present with early errors → H2 confirmed, capture the
   error class.

**Restore (H2):**

- Patch the Cloud task prompt so every abort path still creates a labeled
  audit issue BEFORE `exit`. Model on
  `.github/workflows/scheduled-content-generator.yml` lines 82-84, 92-94,
  110-111, 117-118 (each abort path pre-files an issue).
- Save prompt. Dry-run. Verify new audit issue appears.
- This WOULD be a repo-touching change only if we want to keep the GHA YAML
  in sync — defer that to a separate PR per §Scope.

### H3 — Doppler `prd_scheduled` service token rotated or revoked  [P~0.10]

**Prior evidence:** Token creation 2026-03-24T23:00:34Z, no visible rotation.
But the Cloud task's `eval $(doppler secrets download ...)` pattern silently
exports an empty env on auth failure (see
`cq-doppler-service-tokens-are-per-config` and
`knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`),
so a silent rotation cannot be ruled out from metadata alone.

**Verify (only if H1 + H2 ruled out):**

1. Run: `doppler configs tokens --project soleur --config prd_scheduled`.
   Confirm the existing `cloud-scheduled-tasks` token is **not revoked**
   (non-empty `ACCESS` column).
2. In the Cloud task env UI (`soleur-scheduled` → Content Generator → env
   vars), compare the token currently set to the one Doppler lists. Redact
   in screenshots — token value is `prd_scheduled`-scoped and must not be
   exposed in the #2714 comment.
3. If mismatch confirmed: H3 confirmed.

**Restore (H3):**

- Rotate token: `doppler configs tokens create --project soleur --config
  prd_scheduled --name "cloud-scheduled-tasks-rotated-$(date -u +%Y%m%d)"
  --plain`. Capture the new value into a `read -s` shell buffer — never echo.
  Note: this is a destructive prod-touching write; surface the exact command
  and wait for explicit per-command go-ahead per
  `hr-menu-option-ack-not-prod-write-auth`.
- Update the Cloud task env var via the UI (paste, do not log).
- Revoke the old token: `doppler configs tokens revoke --project soleur
  --config prd_scheduled <old-token-slug>`.
- Dry-run the task.

### H4 — Concurrency deadlock / rate-limit suppression  [P~0.10]

**Prior evidence:** Migration plan called this out as TR3 ("Rate limit
monitoring must be established"); never implemented. A single hung
invocation can stick the schedule indefinitely on the current Cloud Max
plan.

**Verify (only if H1 + H2 + H3 ruled out):**

1. In the task UI, run history should show explicit "skipped" or
   "suppressed" rows if concurrency was the cause. Screenshot.
2. Check the task detail for a stuck "running" invocation dated in the
   silence window.

**Restore (H4):**

- Cancel the stuck invocation(s) via UI.
- Re-queue with a manual "Run now".
- Record in the #2714 comment that this recurred and recommend filing a
  tracking issue to revisit the Max-plan ceiling case (runbook §H4 already
  calls this out; no new issue needed unless this recurs post-restore).

### H5 — Prompt parses a file whose format changed  [P~0.05]

**Prior evidence:** One in-window queue edit (`e4320d55`, 2026-04-01,
`biweekly keyword optimization`). STEP 1 of the prompt reads
`seo-refresh-queue.md` — a malformed row or a pattern the prompt's parsing
does not tolerate could loop the task on parse error. Lower-prior because
H4's rate-limit backstop would typically suppress repeat failures after
~3 stuck runs, not silent-NO-OP.

**Verify (only if H1 + H2 + H3 + H4 ruled out):**

1. `git show e4320d55:knowledge-base/marketing/seo-refresh-queue.md | head -100`.
2. Diff against the current queue:
   `git diff e4320d55~..e4320d55 -- knowledge-base/marketing/seo-refresh-queue.md`.
3. Check each row touched for: (a) `generated_date` annotation presence,
   (b) table-column count consistency, (c) priority annotation format.

**Restore (H5):**

- Fix the offending row format in a separate PR (carve off per §Scope).
- Re-run the task.

## Restore Procedure (generalized, from runbook)

Execute AFTER one of H1-H5 is confirmed:

1. **Apply the hypothesis-specific fix** above.
2. **Manual dry-run:** in the Cloud UI, click "Run now" on the Content
   Generator task (or `gh workflow run scheduled-content-generator.yml`
   as a secondary verification — both code paths should exercise the
   full pipeline; the GHA wrapper still exists per PR #1095 TR5).
3. **Verify success signals:**
   - [ ] New `[Scheduled] Content Generator - <today>` issue created with
         label `scheduled-content-generator`.
   - [ ] A new PR matches `feat(content): auto-generate article ...`.
   - [ ] The distribution file frontmatter has `publish_date: <today>`,
         `status: scheduled`, `channels: discord, x, bluesky,
         linkedin-company`.
   - [ ] `npx @11ty/eleventy` builds pass inside the generated PR.
4. **Record on #2714:** post a comment with the structure defined in
   §Comment Template below.
5. **Close the loop:** #2714 is already closed, comment does not reopen.
   #2742 auto-closes on acceptance-criteria check-off. #2743 remains open
   awaiting the next scheduled fire.

## Comment Template for #2714

Use this exact structure when posting:

```markdown
## Diagnosis — 2026-04-21

**Silence window:** 2026-04-02 → 2026-04-21 (5 scheduled fires missed).

**Confirmed hypothesis:** H{N} — {short name from runbook}

### Evidence

- Verify step output: {screenshot reference or command output}
- Prior-probability rank: {pre-diagnosis P} → confirmed via {which verify
  step}

### Restore action taken

{one paragraph: what was changed, where, whether Doppler was touched,
whether the Cloud task definition was re-created or un-paused}

### Verification

- Manual dry-run at {UTC timestamp}: produced audit issue #{N}, PR #{N}.
- Distribution file frontmatter confirmed: publish_date / status /
  channels all populated.
- Eleventy build: pass.

### Follow-up

- #2743 (verify next Tue/Thu fire) — remains open; next fire window
  {Tue 2026-04-22 10:00 UTC | Thu 2026-04-24 10:00 UTC}.
- Watchdog (`scheduled-cloud-task-heartbeat`) next runs daily 09:30 UTC
  — will auto-close any open `cloud-task-silence` issue once the next
  labeled audit issue lands within 4-day threshold.

### Learning

{Optional: link to any new learning file if the diagnosis surfaced a
novel failure mode not covered by the existing runbook/learnings.}
```

## Execution Order (single session)

**Phase 0 — Precondition checks** (no external-write actions):

1. Confirm runbook is loaded: `stat knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`.
2. Confirm `prd_scheduled` Doppler config exists: `doppler configs --project
   soleur | grep prd_scheduled`.
3. Snapshot the current `scheduled-content-generator` label corpus:
   `gh issue list --label scheduled-content-generator --state all --limit 30
   --json number,title,createdAt,state > /tmp/content-gen-baseline.json`.
   This is the pre-restore baseline — the post-restore delta confirms the
   dry-run produced a new labeled issue.

**Phase 1 — Playwright MCP bootstrap** (browser, no writes):

1. `mcp__playwright__browser_navigate` to `https://claude.ai/code`.
2. If auth-walled: call `browser_snapshot`, message the founder with the
   current URL, wait for login confirmation, then resume.
3. `browser_click` into `soleur-scheduled` environment.
4. `browser_take_screenshot` of task list. Attach to #2714 comment.

**Phase 2 — H1 verify + restore** (conditional write):

1. Inspect Content Generator row status.
2. Act per §H1 Restore.
3. If H1 confirmed and fixed → skip to Phase 6.

**Phase 3 — H2 verify + restore** (conditional write):

1. Open run history, inspect errors.
2. Act per §H2 Restore (prompt patch in UI).
3. If H2 confirmed and fixed → skip to Phase 6.

**Phase 4 — H3 verify + restore** (destructive prod write — `hr-menu-option-ack-not-prod-write-auth`):

1. Compare Doppler + Cloud env var.
2. **Before rotating:** display the exact `doppler configs tokens create
   ... --plain` and `doppler configs tokens revoke ...` commands; wait for
   explicit per-command go-ahead from founder.
3. Act per §H3 Restore.
4. If H3 confirmed and fixed → skip to Phase 6.

**Phase 5 — H4 + H5 verify + restore** (conditional):

1. H4: inspect concurrency history. Act per §H4.
2. H5: diff queue file. Act per §H5 (carves off into a separate PR if
   confirmed).

**Phase 6 — Dry-run + verify** (prod-touching but non-destructive):

1. "Run now" in Cloud UI. Screenshot.
2. Wait ~5 minutes. Poll `gh issue list --label scheduled-content-generator
   --state open` for a new `[Scheduled] Content Generator - 2026-04-21`
   issue (beyond #2692 which is from this morning's manual dispatch).
3. If a new PR was auto-opened, verify its distribution-file frontmatter
   and Eleventy build pass.

**Phase 7 — Close the loop:**

1. Post the §Comment Template on #2714 (`gh issue comment 2714 --body-file
   <path>`).
2. Call `mcp__playwright__browser_close` per `cq-after-completing-a-playwright-task-call`.
3. Check off #2742 acceptance criteria; optional auto-close via `gh issue
   close 2742 --comment "Restored per #2714 comment."`.

## Playwright MCP Contract

**Which MCP tools to use (in order of preference):**

| Operation | MCP tool |
|---|---|
| First navigation | `mcp__playwright__browser_navigate` |
| Structural inspection | `mcp__playwright__browser_snapshot` |
| Visual evidence | `mcp__playwright__browser_take_screenshot` |
| Click task rows / buttons | `mcp__playwright__browser_click` |
| Paste token into env var field | `mcp__playwright__browser_type` |
| Fill form (multi-field) | `mcp__playwright__browser_fill_form` |
| Network tracing (if stuck) | `mcp__playwright__browser_network_requests` |
| Console errors (if stuck) | `mcp__playwright__browser_console_messages` |
| Session cleanup | `mcp__playwright__browser_close` |

Per `cq-playwright-mcp-uses-isolated-mode-mcp`, the MCP server runs in
`--isolated` mode. If a singleton-lock error surfaces, kill lingering Chrome
processes (`pkill -f chromium`) and retry — do NOT disable `--isolated`.

**Auth-wall protocol (per `hr-when-playwright-mcp-hits-an-auth-wall`):**

1. Call `browser_navigate` to `https://claude.ai/code`.
2. If the response is a login page: call `browser_snapshot` to confirm the
   current URL and form fields.
3. Leave the browser tab open. Post a concise message to the founder:

   ```
   Playwright is at <URL>. Please complete the login in the open browser
   tab. I will resume navigation once you signal "logged in" or I detect
   the post-login URL.
   ```

4. Wait for founder confirmation. Do NOT close the browser. Do NOT navigate
   elsewhere. The session cookie acquired by the founder is the load-bearing
   credential for every subsequent step.
5. On resumption, re-snapshot to confirm authenticated URL, then proceed.

**Redaction hygiene:**

- Before any `browser_take_screenshot` of the Cloud task env-var editor or
  the Doppler terminal window: either (a) crop/mask the token value region,
  or (b) do NOT attach that screenshot to the #2714 comment. Token values
  are `prd_scheduled`-scoped secrets.
- Describe what was observed in prose; do not quote the token.

**Operator-interaction automation scope (per 2026-03-13 learning):**

Playwright MCP automates ~95% of browser tasks. Genuinely manual steps in
this plan reduce to ONE: the initial auth login. Everything else (env var
paste, task list navigation, task-detail inspection, Run-now click,
screenshot capture) is agent-driven. No task in `tasks.md` is labeled
"manual — browser" unless founder interaction is required AT THE EXACT
PAGE (CAPTCHA, OAuth consent screen, login credentials).

## Operator Safety Gates

All destructive prod writes route through the gate protocol from
`hr-menu-option-ack-not-prod-write-auth`. A menu-option ack (e.g., "proceed"
in AskUserQuestion) is NOT authorization for these commands.

**Destructive write inventory (all gated):**

1. **Cloud task re-save** (H1 restore if deleted, H2 restore if prompt
   patched). Surface the exact Cloud-UI action sequence AND the prompt text
   being saved; wait for per-action go-ahead before each save click.

2. **Doppler token rotation** (H3 restore). The exact command sequence:

   ```bash
   # Step 1: create new token (prints the token value — capture via read -s)
   doppler configs tokens create \
     --project soleur \
     --config prd_scheduled \
     --name "cloud-scheduled-tasks-rotated-$(date -u +%Y%m%d)" \
     --plain

   # Step 2: paste into Cloud task env var (Playwright browser_type,
   # NEVER echo the token to logs)

   # Step 3: revoke old token (destructive)
   doppler configs tokens revoke \
     --project soleur \
     --config prd_scheduled \
     <old-token-slug>
   ```

   Each step displayed BEFORE execution. Wait for per-command ack.
   Never chain with `&&`. Never pass `--yes` to `revoke`.

3. **Dry-run "Run now"** (Phase 6). Triggers an auto-merging PR. Show the
   expected pipeline steps (audit issue → article PR → auto-merge) BEFORE
   the click. If the founder declines, skip to Phase 7 without verification
   — the next scheduled fire (Tue 2026-04-22 10:00 UTC) acts as natural
   verification, tracked on #2743.

**What is NOT gated (agent-autonomous):**

- Read-only inspection: `gh issue list`, `doppler configs tokens --project
  ... --config ...` (metadata only), task-list screenshots, run-log
  screenshots, `git diff` / `git log` of `seo-refresh-queue.md`.
- Navigation and UI clicks that do NOT trigger prod-state changes (task
  detail page, run history view).
- Posting the #2714 comment (read-only record of findings; not a
  destructive write).

## Test Scenarios (acceptance)

### Pre-merge (agent, before closing #2742)

- [ ] Phase 0 baseline captured to `/tmp/content-gen-baseline.json`.
- [ ] Playwright MCP landed at `claude.ai/code` successfully (with founder
      handoff for login if walled).
- [ ] All of H1-H5 either verified or formally ruled out with a 1-line note
      per hypothesis.
- [ ] Exactly one H*marked CONFIRMED; restore action taken matches the
      runbook prescription for that H*.
- [ ] §Comment Template filled and posted on #2714.
- [ ] Playwright browser closed.

### Post-restore (time-gated, tracked separately on #2743)

- [ ] Next scheduled Tuesday OR Thursday 10:00 UTC fires and produces a
      `[Scheduled] Content Generator - <date>` issue within 4 hours.
- [ ] `scheduled-cloud-task-heartbeat` does NOT open a new
      `cloud-task-silence` issue on its next daily run (09:30 UTC).

### Negative / regression guards

- [ ] The pre-existing `cloudflare-service-token-rotation.md` runbook is not
      modified by this plan (belongs to a different domain).
- [ ] No repo changes are committed unless H2 or H5 is confirmed; even then
      those changes are carved into a separate PR per §Scope.
- [ ] Destructive Doppler token writes (H3) were NOT executed without
      explicit per-command operator ack.

## Open Code-Review Overlap

None. This is an ops follow-through; no code-review issues currently
reference the operator-execution path files.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is pure operator runbook
execution. Engineering is the only implicit domain (runbook lives under
`knowledge-base/engineering/ops/runbooks/`) and the runbook itself is the
subject-matter authority.

## Risks

- **Playwright session cookies expire mid-session.** Mitigation: keep the
  browser tab open per `hr-when-playwright-mcp-hits-an-auth-wall`; if the
  session drops between H1 and Phase 6, re-auth with founder and resume.
- **H3 Doppler rotation is a prod-scoped destructive write.** Mitigation:
  explicit per-command ack gate in Phase 4 step 2. Never pass `--yes` to
  the revoke step.
- **Dry-run creates a real article PR.** Mitigation: the pipeline already
  routes through `gh pr merge --auto` with a PR title in the
  `feat(content):` namespace — the auto-merge path has been exercised
  multiple times (e.g., PR #2693). Add a post-dry-run visual check on the
  PR body; abort if the article content is obviously malformed.
- **Race with the next scheduled fire (Tue 2026-04-22 10:00 UTC).** If the
  dry-run + restore completes within ~24h, the Tue fire acts as
  natural-cadence verification. If it completes after 10:00 UTC Tuesday, a
  second dry-run may be needed to confirm the schedule (not just "Run now")
  picks up correctly. Mitigation: document the timing in the §Comment
  Template.
- **False-ruling-out H2/H3 by stopping at H1.** If H1 verification reveals
  the task is `active` but the silence window still has zero invocations,
  do NOT treat H1 as "confirmed no-op" — that is already H4 / H2 territory.
  The runbook's explicit verify-then-act pattern is load-bearing here.

## Dependencies

- **Runbook:** `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`
  (merged in #2716).
- **Watchdog workflow:** `.github/workflows/scheduled-cloud-task-heartbeat.yml`
  (merged in #2716).
- **Parent issue:** #2714 (closed; comment does not reopen).
- **Tracking issue:** #2742 (this plan's target; auto-closes on acceptance).
- **Follow-up issue:** #2743 (verify next scheduled fire, time-gated).
- **Operator creds:** an authenticated `claude.ai/code` session (founder
  provides via Playwright MCP handoff).
- **Doppler CLI:** `doppler` v3+ on operator machine (already installed).

## Non-Goals

- Not reverting the GHA → Cloud migration from PR #1095.
- Not extending the runbook (already comprehensive per #2716 merge).
- Not adding a second Cloud task definition (3-task Max plan cap).
- Not changing watchdog thresholds (4 days is deliberate per runbook
  §Threshold Derivation).
- Not automating Cloud-task auth (no known headless path for
  `claude.ai/code`).

## References

- Runbook: `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`
- Source PR: #2716 (watchdog + runbook shipped)
- Parent PR: #1095 (GHA → Cloud migration)
- Prior incident learning: `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`
- Doppler scope learning: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
- Related plan (infra — not this one): `knowledge-base/project/plans/2026-04-21-fix-scheduled-content-generator-cloud-task-silence-plan.md`
- Follow-up issue: #2743
- AGENTS.md rules cited: `hr-exhaust-all-automated-options-before`,
  `hr-when-playwright-mcp-hits-an-auth-wall`,
  `hr-menu-option-ack-not-prod-write-auth`,
  `cq-doppler-service-tokens-are-per-config`,
  `cq-after-completing-a-playwright-task-call`,
  `wg-when-a-feature-creates-external`.
