---
title: "Tasks — restore content-generator Cloud scheduled task"
plan: knowledge-base/project/plans/2026-04-21-ops-restore-content-generator-cloud-task-plan.md
issue: 2742
branch: feat-one-shot-restore-content-generator-cloud-task
---

# Tasks

## Phase 0 — Precondition checks (no writes)

- [ ] 0.1 Confirm runbook exists at `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`
- [ ] 0.2 Confirm Doppler `prd_scheduled` config + `cloud-scheduled-tasks` token:
  `doppler configs tokens --project soleur --config prd_scheduled`
- [ ] 0.3 Snapshot `scheduled-content-generator` label corpus as pre-restore
  baseline:
  `gh issue list --label scheduled-content-generator --state all --limit 30 --json number,title,createdAt,state > /tmp/content-gen-baseline.json`

## Phase 1 — Playwright bootstrap (browser, no writes)

- [ ] 1.1 `mcp__playwright__browser_navigate` to `https://claude.ai/code`
- [ ] 1.2 On auth wall: keep browser open, message founder with the URL, wait
  for login confirmation (per `hr-when-playwright-mcp-hits-an-auth-wall`)
- [ ] 1.3 Navigate to `soleur-scheduled` environment
- [ ] 1.4 `browser_take_screenshot` of the task list; save path for #2714
  comment attachment

## Phase 2 — H1: task paused / deleted / orphaned  [MOST LIKELY]

- [ ] 2.1 Locate Content Generator row; record status (active / paused /
  missing)
- [ ] 2.2 Record schedule: expected `Tuesday + Thursday 10:00 UTC`
- [ ] 2.3 Act per diagnosis:
  - if paused → un-pause (click); screenshot post-state
  - if deleted → re-create from canonical prompt, reconciling against
    2026-04-03 frontmatter-instruction learning
  - if orphaned → re-auth Cloud session, re-save task
- [ ] 2.4 If H1 confirmed + fixed: jump to Phase 6

## Phase 3 — H2: prompt fails before audit-issue step

- [ ] 3.1 Open Content Generator run history; screenshot last ~20 rows
- [ ] 3.2 For any run between 2026-04-02 and 2026-04-21: open detail,
  capture first error line
- [ ] 3.3 Classify: zero invocations → not H2; early error → H2
- [ ] 3.4 If H2 confirmed: patch prompt so every abort path creates audit
  issue before exit (mirror
  `.github/workflows/scheduled-content-generator.yml` lines 82-84, 92-94,
  110-111, 117-118). Save. Dry-run. Jump to Phase 6.

## Phase 4 — H3: Doppler token rotated or revoked  [DESTRUCTIVE GATE]

- [ ] 4.1 Compare Doppler `prd_scheduled` tokens output against Cloud task
  env var (redact in screenshots)
- [ ] 4.2 **Before rotating:** display exact `doppler configs tokens create
  ... --plain` + `revoke ...` commands; wait for explicit per-command
  go-ahead (per `hr-menu-option-ack-not-prod-write-auth`)
- [ ] 4.3 If confirmed and ack received:
  - create rotated token in Doppler (never echo value)
  - paste into Cloud task env var via UI
  - revoke old token
  - dry-run task → jump to Phase 6

## Phase 5 — H4 (concurrency) + H5 (queue format)

- [ ] 5.1 H4 verify: inspect run history for "skipped" / "suppressed" rows,
  or a stuck "running" invocation dated in the silence window
- [ ] 5.2 H4 act: cancel stuck invocation, re-queue → Phase 6
- [ ] 5.3 H5 verify: `git show e4320d55:knowledge-base/marketing/seo-refresh-queue.md | head -100`;
  `git diff e4320d55~..e4320d55 -- knowledge-base/marketing/seo-refresh-queue.md`
- [ ] 5.4 H5 act: if queue format broke the STEP 1 parser, carve into a
  separate PR per plan §Scope. Re-run task. → Phase 6

## Phase 6 — Dry-run + verify

- [ ] 6.1 In Cloud UI: "Run now" on Content Generator; screenshot
- [ ] 6.2 Poll `gh issue list --label scheduled-content-generator
  --state open` until a new `[Scheduled] Content Generator - 2026-04-21`
  issue appears (beyond the pre-existing #2692)
- [ ] 6.3 Verify auto-opened PR has correct distribution-file frontmatter:
  `publish_date: 2026-04-21`, `status: scheduled`, `channels: discord, x,
  bluesky, linkedin-company`
- [ ] 6.4 Verify `npx @11ty/eleventy` passes inside the PR (read CI check
  via `gh pr checks <N>`)

## Phase 7 — Close the loop

- [ ] 7.1 Fill §Comment Template from plan §Comment Template; save to
  `/tmp/2714-diagnosis-comment.md`
- [ ] 7.2 `gh issue comment 2714 --body-file /tmp/2714-diagnosis-comment.md`
- [ ] 7.3 `mcp__playwright__browser_close` (per
  `cq-after-completing-a-playwright-task-call`)
- [ ] 7.4 Check off #2742 acceptance criteria; optionally
  `gh issue close 2742 --comment "Restored per #2714 comment."`
- [ ] 7.5 Leave #2743 open — next-fire verification is time-gated
  (Tue 2026-04-22 10:00 UTC earliest)

## Acceptance Criteria

### Pre-merge / pre-close (agent before #2742 closes)

- [ ] Phase 0 baseline captured
- [ ] Playwright session reached `claude.ai/code` successfully
- [ ] All H1-H5 verified or ruled out with 1-line rationale each
- [ ] Exactly one H* marked CONFIRMED
- [ ] §Comment Template posted on #2714
- [ ] Playwright `browser_close` called

### Post-close (time-gated, on #2743)

- [ ] Next scheduled Tue/Thu 10:00 UTC fire produces `[Scheduled]
  Content Generator - <date>` within 4 hours
- [ ] Watchdog does NOT open a new `cloud-task-silence` issue on next
  daily run
