---
title: "fix: campaign-calendar max-turns starvation + overdue-issue dedup"
type: fix
date: 2026-04-28
issue: 2896
branch: feat-one-shot-2896-campaign-calendar-watchdog
classification: ops-remediation
---

# fix: campaign-calendar max-turns starvation + overdue-issue dedup

## Enhancement Summary

**Deepened on:** 2026-04-28
**Sections enhanced:** Risks (R2), H5 (action pin), Phase 2 (STEP 2.5 issue-number capture), Acceptance Criteria, Implementation Sketch (new).
**Research sources used:**

- Live `gh api repos/anthropics/claude-code-action/releases` (verified pin currency).
- Live `gh issue create --help` (verified flag surface — `--json` is NOT supported on create).
- Live `gh issue list --label scheduled-campaign-calendar --state all` (verified watchdog query behavior with closed heartbeat issues).
- Institutional learnings: `2026-04-21-cloud-task-silence-watchdog-pattern.md` (set -euo pipefail + numeric-guard pattern), `2026-03-20-claude-code-action-max-turns-budget.md` (peer ratio table), `2026-04-03-content-cadence-gap-cloud-task-migration.md` (overdue detection origin).
- AGENTS.md cross-checks: `cq-claude-code-action-pin-freshness`, `cq-docs-cli-verification`, `hr-in-github-actions-run-blocks-never-use`, `cq-ci-steps-polling-json-endpoints-under`, `cq-ops-remediation-uses-ref-not-closes-for-post-merge-fixes` (referenced from `wg-use-closes-n-in-pr-body-not-title-to`).

### Key Improvements

1. **R2 fixed — `gh issue create --json` does NOT exist.** Verified via
   `gh issue create --help` on gh v2.91.0. The actual stdout is the
   issue URL. The plan now prescribes `URL=$(gh issue create ...) && N=$(echo "$URL" | awk -F/ '{print $NF}')` to capture the
   issue number deterministically.
2. **H5 closed — pin is borderline-fresh.** `v1.0.101` was published
   2026-04-18 (10 days old at plan time); current tip is `v1.0.108`
   published 2026-04-28. Per `cq-claude-code-action-pin-freshness`,
   <3-week pins are fresh. Bumping is OPTIONAL but recommended:
   v1.0.102 bumped `oven-sh/setup-bun` to v2.2.0 (Node 24), which
   addresses the Node 20 deprecation warning the 2026-04-27 run already
   logged. No max-turns/model/thinking-block changes between 101→108.
3. **Heartbeat issue-creation is verified safe under the watchdog query.**
   `gh issue list --label scheduled-campaign-calendar --state all
   --limit 5 --json createdAt` returns closed issues (verified live —
   #1098 in the CLOSED state surfaces in the corpus). The STEP 2.5
   close-on-create heartbeat IS visible to the watchdog as the most
   recent `createdAt`.
4. **Implementation Sketch added (new section)** — copy-paste-ready bash
   snippets for STEP 2 dedup loop and STEP 2.5 heartbeat, with explicit
   `set -euo pipefail` discipline per the cloud-task-silence-watchdog
   learning (#2716 pre-merge catch — non-numeric guard before integer
   comparison; not directly applicable here, but the discipline of
   running snippets through `bash -n` and `shellcheck` before commit IS).
5. **STEP 2.5 race-free issue-close** — `gh issue close` accepts an
   issue URL directly (verified in gh manual), so the URL captured from
   `gh issue create` can be passed straight to `gh issue close` without
   a list-search round-trip. Eliminates R2's eventual-consistency race.

### New Considerations Discovered

- **Node 20 deprecation warning** logged in the 2026-04-27 failure run
  (`actions/checkout@34e114876b...` and `oven-sh/setup-bun@3d267786b...`).
  Bumping the action pin to v1.0.102+ would not fix this for `actions/checkout`
  (that's pinned by us, not by the action), but it would for the
  action's internal setup-bun. Out of scope for this PR but worth
  filing as a follow-up.
- **Watchdog-issue auto-close is non-atomic.** After the patched
  workflow runs and produces the heartbeat audit issue, the watchdog
  fires next at 09:30 UTC daily — it does NOT trigger immediately on
  the audit issue's creation. So #2896's auto-close happens within
  24h of the patched workflow's first successful schedule fire (next
  scheduled fire is 2026-05-04 16:00 UTC), or sooner if an operator
  manually dispatches the heartbeat workflow.
- **The `--milestone "Post-MVP / Later"` argument requires the
  milestone to exist.** Verified that milestone exists at GitHub
  (referenced in #2896 itself). No new pre-flight needed.
- **`gh issue close` accepts URL.** The verified behavior eliminates
  one round-trip per closed-on-create heartbeat. Important for turn
  thrift on the new 40-turn budget.

## Overview

Issue #2896 is a watchdog alert: the `campaign-calendar` task (label
`scheduled-campaign-calendar`) had not produced an audit issue in 11 days as of
2026-04-25. The watchdog (`.github/workflows/scheduled-cloud-task-heartbeat.yml`)
fired correctly. The task itself is a GHA-scheduled workflow
(`.github/workflows/scheduled-campaign-calendar.yml`), not a Claude Code Cloud
task — so the runbook's H1/H2/H3/H6 hypotheses (Cloud-specific) do not apply.

Two co-located faults explain the silence:

1. **Primary — turn-budget starvation.** `scheduled-campaign-calendar.yml`
   sets `--max-turns 20`, the lowest of any scheduled workflow in the repo
   (peers range 30–80). With ~10 turns of plugin-load overhead +
   STEP1 (calendar regen) + STEP2 (overdue scan & one-issue-per-overdue file)
   + STEP3 (strategy review date) + STEP4 (PR persist), the prompt can complete
   only when the overdue corpus is small. On 2026-04-27, a manual dispatch
   needed to file 3 overdue issues (#2968 #2969 #2970) and hit
   `Reached maximum number of turns (20)` mid-STEP4 — no PR was created, no
   strategy date update persisted. The 2026-04-20 schedule-fire used 21 turns
   (over the limit by 1, but the SDK reports 1+limit so the run was at the wall);
   that run filed zero new audit issues despite #2146 still being open and the
   overdue file 04-brand-guide-creation still outstanding.

2. **Secondary — no dedup of already-open overdue issues.** STEP2 of the
   prompt instructs the agent to "create a GitHub issue" for every overdue file
   without checking for an existing open issue with the same title. Issue #2968
   (2026-04-27) is an exact-title duplicate of #2146 (2026-04-13). Every
   successful run that finds N still-open overdue items burns N turns AND
   pollutes the issue tracker with duplicates. This compounds (1): the more
   overdue items linger unaddressed, the more turns each successful run burns,
   the more likely the next run starves.

The runbook's auto-close branch will close #2896 itself on the next
heartbeat cycle (2026-04-28 09:30 UTC) because three fresh
`scheduled-campaign-calendar` audit issues already exist (#2968 #2969 #2970,
all 2026-04-27) — `days_since` will be 1, well under the 10-day threshold.
This plan still ships the workflow fix so the next outage is not
self-inflicted.

## Research Reconciliation — Spec vs. Codebase

| Issue/runbook claim | Reality | Plan response |
|---|---|---|
| Issue body links the cloud-scheduled-tasks runbook | Runbook H1/H2/H3/H6 are Cloud-specific. campaign-calendar is GHA-scheduled (cron `0 16 * * 1` in `scheduled-campaign-calendar.yml` line 16). | Diagnosis lives outside the runbook. This plan documents the GHA-side failure mode and proposes a runbook addendum (§H7 — GHA max-turns starvation). |
| Last audit issue: 2026-04-13 | True for the moment the watchdog filed at 2026-04-25 09:30 UTC. As of 2026-04-28, three fresh audit issues exist from the manual 2026-04-27 dispatch (#2968 #2969 #2970). | The watchdog will auto-close #2896 on its next fire (2026-04-28 09:30 UTC) regardless of this PR. Verify auto-close in Acceptance Criteria; if it does not fire, manually close with the comment template below. |
| "Reference workflow: `.github/workflows/scheduled-cloud-task-heartbeat.yml`" | The watchdog itself functions correctly — it fired exactly when expected. | Do not modify the watchdog. The fix is in the supervised workflow and its prompt. |
| Watchdog threshold for campaign-calendar = 10 days (Mon weekly cadence) | Verified in `scheduled-cloud-task-heartbeat.yml` TASKS array line 78. | Threshold stays at 10 — sufficient slack for the once-weekly schedule. |
| 2026-04-20 schedule-fire was a "success" (GHA conclusion) | True. But `num_turns: 21` shows the prompt completed at the wall. The run filed zero overdue audit issues despite #2146 still open and brand-guide-creation still overdue — STEP2 silently no-op'd because the agent's pattern was to skip when an existing-open identical issue was visible to it (implicit dedup, not in-prompt dedup). | This is the **secondary** fault: turn-thrift via implicit skip masked the silent-publishing-gap signal that the watchdog's label-cadence query measures. After the fix, STEP2 explicitly looks up open issues and either reuses or skips with a recorded marker. |
| Tracking issue cited in runbook = #2714 | #2714 is the content-generator silence (Cloud) — closed. campaign-calendar's silence is a separate incident (GHA-side, different root cause). | This plan is the tracking-of-record for #2896; #2714 is referenced for context only. |

## Hypotheses

Ordered most to least likely, with explicit verification done at plan time
(not deferred to implementation).

### H1 — `--max-turns 20` is too tight given plugin overhead [PRIMARY — VERIFIED]

The 2026-03-20 max-turns-budget learning gives the formula
`Required turns = plugin overhead (~10) + task tool calls + error/retry buffer (~5)`.
For campaign-calendar, the prompt has four phases:

- STEP1 invokes `/soleur:campaign-calendar` (1 internal skill call, but the
  skill itself globs ~20 files, reads each, classifies, writes the calendar —
  per `campaign-calendar/SKILL.md` Phase 1–3, this is ≥ 5 turns of
  read/write tool calls).
- STEP2 globs `distribution-content/*.md`, reads each, parses frontmatter,
  filters overdue, and creates N issues — N tool calls for `gh issue create`
  alone. As of 2026-04-28, the overdue set is 3 files (brand-guide,
  agents-that-use-apis, service-automation-hn-show), so STEP2 alone is
  3 issue-create turns + ~5 read/glob turns.
- STEP3 reads `content-strategy.md`, edits frontmatter, writes — 2 turns.
- STEP4 runs the PR-persist bash block — 1 turn (single `Bash` invocation,
  not split).

Plugin overhead (load AGENTS.md, constitution, brand guide, etc.) is ~10 turns.
Total: ~10 + 6 + 8 + 2 + 1 = **27 turns minimum** for a 3-overdue corpus.
With `--max-turns 20`, the budget is exhausted mid-STEP3 in the worst case.

**Verify (done at plan time):**

- `grep -E 'max-turns' .github/workflows/scheduled-*.yml` — confirmed
  campaign-calendar at 20 is the lowest. Peers: bug-fixer 55,
  community-monitor 50, content-generator 50, daily-triage 80, growth-audit 70,
  ux-audit 60, competitive-analysis 45, growth-execution 40, seo-aeo-audit 40,
  roadmap-review 40, ship-merge 40, follow-through 30.
- 2026-04-27 run log: `Reached maximum number of turns (20)`
  (`gh run view 25009556821`).
- 2026-04-20 run log: `num_turns: 21` (over the wall by 1; the SDK reports
  initial-prompt + 20 actions). Three pre-existing overdue files but only
  one filed; pattern matches "implicit dedup by skip" — see H2.

**Fix (H1):** Raise `--max-turns` to 40. Pair with `timeout-minutes` raise
to keep ratio ≥ 0.75 min/turn per `2026-03-20-claude-code-action-max-turns-budget.md`.
Current: `timeout-minutes: 15` → 0.75 ratio; new `timeout-minutes: 30` → 0.75
ratio. (15/40 = 0.375, below the floor; 30/40 = 0.75, on the median.)

### H2 — STEP2 has no explicit dedup; agent improvises with skip-or-duplicate [SECONDARY — VERIFIED]

The 2026-04-13 run filed #2146 (overdue: brand-guide). The 2026-04-20 run
saw the same overdue file but filed zero issues. The 2026-04-27 run filed
issue #2968 — an exact-title duplicate of the still-open #2146.

The prompt does not instruct the agent how to handle "an open issue with
this title already exists." Three failure modes observed:

- **Mode A (2026-04-20):** agent skips, no record of the skip → silence
  signal masquerades as "nothing was overdue."
- **Mode B (2026-04-27):** agent re-creates → tracker pollution + extra turns
  consumed → contributes to (H1) starvation.
- **Mode C (theoretical):** agent edits the open issue → would be silent and
  invisible to the watchdog if it preserves `createdAt`. (Not observed; GitHub
  doesn't allow editing `createdAt` anyway.)

**Verify (done at plan time):**

- `gh issue list --label scheduled-campaign-calendar --state open` returns
  #2146 and #2968 with identical titles — duplicate-confirmed.
- 2026-04-20 run log scan (`gh run view 24679688331 --log | grep -i overdue`)
  shows STEP2 prompt was reached but no `gh issue create` invocations land
  in the log — Mode A confirmed for that run.

**Fix (H2):** Rewrite STEP2 to require an explicit dedup guard. For each
overdue file, the agent must run `gh issue list --search '"<exact title>" in:title' --label scheduled-campaign-calendar --state open --json number` first. If the result is non-empty, **comment** on the existing issue with a heartbeat note (`Re-detected on YYYY-MM-DD; still overdue.`) and **do not** create a new issue. If empty, create. This makes the watchdog's label-cadence query honest: every successful run produces at least one timestamped artifact (a comment or a new issue), so the heartbeat sees recent activity and does not flag silence.

The heartbeat reads the most recent issue by `createdAt`, not comments —
so a comment-only signal would not actually reset the silence clock. Two
options to address that:

- **Option 2a:** When all overdue items already have open issues, file a
  single low-noise audit issue per run titled
  `[Scheduled] Campaign Calendar - <YYYY-MM-DD> (no new overdue items)`,
  closed-on-create, with the `scheduled-campaign-calendar` label.
- **Option 2b:** Change the watchdog to also count comments on
  `scheduled-campaign-calendar`-labeled issues as a heartbeat signal.

**Selected: 2a.** Self-contained — no edit to the watchdog, no risk of
breaking the dedup contract for other tasks. The closed-on-create heartbeat
is a novel pattern in this repo (verified via grep across
`.github/workflows/scheduled-*.yml`); modeled on the watchdog's own
exact-title dedup contract from `scheduled-cloud-task-heartbeat.yml`.

### H3 — Schedule did fire but the runner ran a stale revision of the workflow

If a recent commit pushed a YAML-syntax-invalid version of
`scheduled-campaign-calendar.yml`, the schedule would fire but immediately
fail-to-load. **Refuted:** every recent run has `event: schedule` with a
non-error startup; the failure is mid-execution, not workflow-load.

### H4 — Anthropic API outage / rate-limit on the Mon 16:00 UTC slot

If the API was down on 2026-04-13 → 2026-04-20 → 2026-04-27 Mondays at
16:00 UTC, the workflow would fail at the `anthropic-preflight` step.
**Refuted:** preflight passed on 2026-04-20 and 2026-04-27 (run logs show
`needs.preflight.outputs.ok == 'true'`); the failure is in
`refresh-calendar`'s claude-code-action invocation.

### H5 — Workflow's `claude-code-action` SHA pin is too old [VERIFIED FRESH]

Pin: `ab8b1e6471c519c585ba17e8ecaccc9d83043541` (v1.0.101). Per AGENTS.md
`cq-claude-code-action-pin-freshness`, pins should be within ~3 weeks of
release tip.

**Verified live (2026-04-28):**

```bash
$ gh api repos/anthropics/claude-code-action/releases --jq '.[0:5] | .[] | "\(.tag_name) \(.published_at)"'
v1.0.108 2026-04-28T00:32:51Z
v1       2025-08-26T17:01:10Z
v1.0.107 2026-04-25T01:56:23Z
v1.0.106 2026-04-25T00:16:01Z
v1.0.105 2026-04-23T23:25:20Z

$ gh api repos/anthropics/claude-code-action/releases/tags/v1.0.101 --jq '.published_at'
2026-04-18T01:39:19Z
```

v1.0.101 is 10 days old; current tip is v1.0.108. Pin is fresh by the
3-week rule. **Refuted as a cause of the silence.**

**Optional bump (low-risk, not blocking):** v1.0.102 bumped `oven-sh/setup-bun`
to v2.2.0 (Node.js 24), which proactively addresses the Node 20
deprecation warning the 2026-04-27 run logged. v1.0.103–v1.0.108 changelogs
contain no max-turns/model/thinking-block changes (the kinds of breaks
that cq-claude-code-action-pin-freshness exists to catch). If bumping in
this PR, target `v1.0.108` and add to the PR body: "Pin bump justified
by Node 20 deprecation; no behavior changes per release notes." If not
bumping, file a follow-up issue for the Node 20 deprecation track.

**Decision:** defer the bump to a separate PR. Scope this PR strictly to
the silence root cause; a pin bump opens a different review surface
(action behavior under Node 24 has not been verified in this repo's
workflow corpus).

## Open Code-Review Overlap

`gh issue list --label code-review --state open --search '"scheduled-campaign-calendar.yml"'`
and `'"scheduled-cloud-task-heartbeat"'` both returned **zero** matches at
plan time (2026-04-28). No open scope-outs touch the files this plan modifies.

None.

## Files to Edit

- `.github/workflows/scheduled-campaign-calendar.yml`
  - Bump `claude_args --max-turns` from 20 → 40.
  - Bump `refresh-calendar.timeout-minutes` from 15 → 30.
  - Rewrite STEP2 of the prompt to require dedup before issue-create.
  - Append STEP 2.5: when no new overdue issues were created, file a
    `[Scheduled] Campaign Calendar - <YYYY-MM-DD> (no new overdue items)`
    audit issue, immediately close it.
  - (Conditional H5) Bump `anthropics/claude-code-action` pin if > 3 weeks old.
- `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`
  - Add §H7 — GHA-scheduled-task max-turns starvation, with verification
    (`grep -E 'max-turns' .github/workflows/scheduled-*.yml`),
    fix template (raise turns + timeout-minutes proportionally per the
    2026-03-20 ratio table), and reference to this plan.
- `knowledge-base/marketing/distribution-content/04-brand-guide-creation.md`
  - **Operator action, not in-PR.** Either reschedule `publish_date` to a
    near-future Tue/Thu slot, or change `status` to `cancelled` and clear
    `publish_date`. Listed here so the fix-the-recurring-overdue work item
    is visible. Track via existing #2146/#2968 — close the duplicate #2968
    in favor of #2146.
- (Optional, post-merge) Close #2968 as duplicate of #2146 with a comment
  pointing to this PR's STEP2 dedup fix.

## Files to Create

None. (Spec lives in `knowledge-base/project/specs/feat-one-shot-2896-campaign-calendar-watchdog/`
and `tasks.md` is generated by Save Tasks step, not this section.)

## Implementation Phases

### Phase 1 — Workflow turn-budget fix (H1)

1. Edit `.github/workflows/scheduled-campaign-calendar.yml`:
   - Line 49: `timeout-minutes: 15` → `timeout-minutes: 30`.
   - Line 70: `--max-turns 20` → `--max-turns 40`.
2. Verify ratio: 30/40 = 0.75 — matches median per the
   2026-03-20-claude-code-action-max-turns-budget.md table; safe.
3. Verify pin freshness (H5):
   `gh api repos/anthropics/claude-code-action/releases --jq '.[0:3] | .[] | "\(.tag_name) \(.published_at)"'`.
   If `v1.0.101 (ab8b1e64...)` is > 3 weeks old at plan-time, bump to current
   tip in the same edit per `cq-claude-code-action-pin-freshness`. If
   within 3 weeks, leave alone — out of scope for this PR.

### Phase 2 — Prompt STEP2 dedup rewrite (H2)

Replace the existing STEP 2 block (lines 79–87) with the following structure
(actual prose preserved in implementation):

```text
STEP 2 — Flag overdue distribution content (with dedup):
Scan all files in knowledge-base/marketing/distribution-content/ for items
where:
- status is "scheduled" AND publish_date is in the past (before today)
- status is "draft" AND publish_date is non-empty and in the past

For each overdue item, before creating an issue:
1. Compute the canonical title:
   "[Content] Overdue: <title> (was scheduled for <publish_date>)"
2. Search for an existing open issue with that exact title:
   gh issue list \
     --label scheduled-campaign-calendar \
     --state open \
     --search '"<canonical title>" in:title' \
     --json number,title --jq '.[] | select(.title == "<canonical title>") | .number'
3. If a match is found, comment on it:
   gh issue comment <N> --body "Re-detected on $(date -u +%Y-%m-%d); still
   overdue. Heartbeat from campaign-calendar workflow run."
   Do NOT create a new issue.
4. If no match, create a new issue (existing template, unchanged).

Track the count of (a) new issues created, (b) comments added,
(c) overdue items still pending. Print all three at the end of STEP 2 for
visibility.

STEP 2.5 — Heartbeat audit issue (always runs):
If STEP 2 created zero new issues (all overdue items deduped against open
issues, OR no overdue items found), create and immediately close a
heartbeat audit issue so the watchdog's label-cadence query sees recent
activity. Capture the new issue's URL from gh issue create stdout
(deterministic; no list-search needed):
  TITLE="[Scheduled] Campaign Calendar - $(date -u +%Y-%m-%d) (heartbeat)"
  URL=$(gh issue create \
    --title "$TITLE" \
    --label "scheduled-campaign-calendar" \
    --milestone "Post-MVP / Later" \
    --body "No new overdue items detected this run. Tracking heartbeat.")
  gh issue close "$URL" --comment "Auto-closed: heartbeat record only."
If STEP 2 created at least one new issue, skip STEP 2.5 — the new issue is
itself the heartbeat signal.
```

The STEP 2.5 close-on-create pattern keeps the watchdog's label-based
heartbeat query truthful (`gh issue list --label scheduled-campaign-calendar
--state all --limit 5` returns the heartbeat as the most-recent createdAt)
without leaving a clutter of open issues. State `all` is what the watchdog
queries (line 99 of `scheduled-cloud-task-heartbeat.yml`), so closed
heartbeats count.

### Phase 3 — Runbook addendum (H7)

Append to `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`,
after the existing §H6 (Sub-agent auth inheritance):

```markdown
### H7 — GHA-scheduled-task max-turns starvation

GHA-scheduled tasks (campaign-calendar, competitive-analysis, roadmap-review,
growth-execution, seo-aeo-audit, daily-triage) invoke the
`anthropics/claude-code-action` with a `--max-turns` budget. If the budget
is too tight for the task's plugin overhead (~10 turns) + task work
(per-step turn estimate) + error buffer (~5 turns), the agent reaches max
turns mid-STEP and the GHA workflow exits with a `failure` conclusion. The
audit-issue step is typically the LAST step (PR persist), so a starved run
produces zero artifacts → silent gap → watchdog flags after threshold.

**Signature:**
- GHA run conclusion: `failure`
- Run log contains: `Reached maximum number of turns (N)`
- Latest audit issue (label-based query) is older than threshold

**Verify:** `grep -E '--max-turns' .github/workflows/scheduled-*.yml`,
read each row, compute against the 2026-03-20 ratio table.

**Fix:** Raise `--max-turns` to peer median (40), and raise
`timeout-minutes` proportionally (≥ 0.75 min/turn). See
`knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md`.

**Reference incident:** #2896 — campaign-calendar at `--max-turns 20` failed
on 2026-04-27 with 3 overdue items to file. Fix in PR (TBD post-merge).
```

### Phase 4 — Auto-close watchdog issue + close duplicate

After Phase 1–3 merge, verify and clean up:

1. **Watchdog auto-close.** The heartbeat workflow runs daily 09:30 UTC.
   Either it has already auto-closed #2896 (because #2968/#2969/#2970 from
   2026-04-27 reset the cadence clock to 1 day), or it has not. Check
   with `gh issue view 2896 --json state`:
   - If `CLOSED`, no action.
   - If `OPEN` and `days_since` < 10, manually trigger
     `gh workflow run scheduled-cloud-task-heartbeat.yml` and re-check after
     run completes.
   - If `OPEN` and `days_since` ≥ 10, the watchdog is broken — file a
     separate issue and investigate (out of scope for this PR).
2. **Close #2968 as duplicate.** `gh issue close 2968 --comment "Duplicate
   of #2146 — same overdue content file. Both filed because the
   campaign-calendar workflow STEP 2 had no dedup guard prior to PR <N>.
   Tracking via #2146."` Do not auto-link `Closes #2896` from this PR's
   body — see "Acceptance Criteria § Pre-merge / Post-merge" split below.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `.github/workflows/scheduled-campaign-calendar.yml` line 49 changed
  to `timeout-minutes: 30`.
- [x] Same file line 70 changed to `--max-turns 40`.
- [x] STEP 2 of the prompt body now requires the dedup guard described in
  Phase 2; STEP 2.5 (heartbeat audit issue when no new issues filed) is
  appended.
- [x] `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`
  has §H7 addendum.
- [ ] PR body uses `Ref #2896` (NOT `Closes #2896`) per
  `cq-ops-remediation-uses-ref-not-closes-for-post-merge-fixes`.
  The watchdog itself closes #2896 when audit issues land within
  threshold; #2896 is not the implementation-tracking issue, it is the
  alert. Closing it from the PR body would close it before the post-merge
  verify-and-dispatch step ran.
- [ ] H5 disposition recorded in PR body: pin v1.0.101 verified fresh
  (10 days old at deepen-time, well under the 3-week rule). No bump
  in this PR. Follow-up issue for Node 20 deprecation tracking is
  optional.
- [ ] `peer-ratio` table sanity check is in the PR body: a one-line
  citation of the 2026-03-20 budget learning showing the new (30, 40)
  pair lands at 0.75 min/turn.
- [ ] `compound` skill invoked before the commit per
  `wg-before-every-commit-run-compound-skill`.

### Post-merge (operator)

- [ ] Watchdog auto-close of #2896: verify with
  `gh issue view 2896 --json state`. If still OPEN, manually run
  `gh workflow run scheduled-cloud-task-heartbeat.yml` once and re-verify.
- [ ] Manual smoke-test of the patched workflow:
  `gh workflow run scheduled-campaign-calendar.yml`. Poll
  `gh run view <id> --json status,conclusion`. Expected outcome:
  - `conclusion: success`
  - Run log contains `num_turns: <N>` where N ≤ 35 (headroom retained).
  - At least one labeled audit issue exists with `createdAt` after the
    run start. (Either a new overdue issue, a comment on an existing
    overdue issue + a closed heartbeat issue, or a closed heartbeat
    issue alone.)
- [ ] Duplicate cleanup: `gh issue close 2968 --comment <duplicate-of-2146>`.
- [ ] Operator addresses #2146 directly:
  - Reschedule `04-brand-guide-creation.md` `publish_date` to a near-Tue/Thu,
    OR change status to `cancelled` and clear `publish_date`. Update via
    a follow-up commit (not this PR — content-decision, not workflow-fix).
- [ ] Watchdog confirmation: on the next Monday 16:00 UTC fire
  (2026-05-04), verify the workflow runs to completion AND a
  scheduled-campaign-calendar-labeled audit issue is created within 10
  minutes of run end.

## Test Scenarios

This is an infra-only fix; tests are operational verifications, not unit/
integration tests.

### TS1 — Smoke-test the prompt under the expanded budget

After Phase 1+2 merge, manually dispatch
`gh workflow run scheduled-campaign-calendar.yml`. Expected: workflow
completes with `success`. Run log includes `num_turns: <N>` with
N ≤ 35. STEP 2 logs show either dedup-comment events on #2146 (or its
successor) or new-issue creation. STEP 2.5 either fires (closed heartbeat
issue created) or is skipped (with a log line confirming why).

### TS2 — Force the dedup path

To exercise the dedup guard, ensure at least one open
`scheduled-campaign-calendar`-labeled overdue issue exists at dispatch
time (e.g., reopen #2146 if needed). Verify the patched STEP 2 lands a
comment on it instead of creating a new copy.

### TS3 — Force the no-overdue path

If the operator clears all overdue items first (rescheduling all
`*-distribution-content/` files with past `publish_date`), the patched
STEP 2 should produce zero new issues, STEP 2.5 should fire and create+close
a heartbeat issue. The watchdog should NOT flag silence on the next
heartbeat run.

### TS4 — Watchdog auto-close

Verify #2896 auto-closes via the watchdog within one heartbeat-cron cycle
of three fresh `scheduled-campaign-calendar` audit issues existing
(#2968/#2969/#2970, all 2026-04-27 — the cadence resets to 1 day). If
the auto-close does not fire, that is a separate watchdog bug — file a
new issue and link.

## Risks

- **R1:** Raising `--max-turns` to 40 increases the worst-case workflow
  cost and runtime. **Mitigation:** the timeout-minutes pair (30) caps
  wall time. Cost ceiling per run: ~3x previous (per-turn cost is roughly
  constant; 40/20 = 2x turn ceiling, but real runs typically use
  num_turns ≪ max_turns; observed 21 → expect ~25 in steady state). Acceptable.
- **R2:** STEP 2.5's "create then close" pattern depends on
  `gh issue create` returning quickly enough that `gh issue list` finds
  it. GitHub's eventual consistency means this can race.
  **Mitigation (verified at deepen-time):** `gh issue create` outputs
  the new issue's URL on stdout — the URL itself is the deterministic
  return channel. `gh issue close` accepts a URL directly. The pattern
  is:

  ```bash
  URL=$(gh issue create --title "$TITLE" --label "scheduled-campaign-calendar" \
    --milestone "Post-MVP / Later" --body "$BODY")
  gh issue close "$URL" --comment "Auto-closed: heartbeat record only."
  ```

  `gh issue create --json` is NOT supported (verified 2026-04-28 via
  `gh issue create --help` on gh 2.91.0); the URL-on-stdout
  contract is the documented capture mechanism. Per
  `cq-docs-cli-verification`, this snippet has been verified against
  the installed gh version on the developer machine; the action runner
  uses the same flag surface. **STEP 2.5 prose in Phase 2 has been
  rewritten to use the URL-capture form.**
- **R3:** The dedup guard introduces a `gh issue list --search` per overdue
  item. With ~5 overdue items, this is 5 API calls + 1 per gh issue
  comment ≈ 10 turns extra. The 40-turn budget covers this, but if the
  overdue corpus grows to >10 the budget tightens. **Mitigation:** STEP 2
  prompt should batch the `gh issue list` calls into one query
  (`--search "label:scheduled-campaign-calendar in:title"`) and parse the
  JSON locally. Document as an optimization note in the prompt; not
  blocking for this PR.
- **R4:** Bumping the action pin (H5) is conditional on stale-check; if
  the pin must be bumped and the new version has breaking changes
  (e.g., changed argument shape for `--max-turns`), the PR could
  introduce a fresh failure mode. **Mitigation:** read the release notes
  before bumping. If anything in the release notes touches max-turns,
  thinking blocks, or model defaults, defer the bump to a separate PR.
- **R5:** The watchdog might NOT auto-close #2896 if its
  most-recent-issue lookup returns one of the heartbeat issues with a
  closed status — but we already verified the watchdog uses
  `--state all` (line 99) so closed audit issues count. Verified safe.
- **R6:** This plan does not address the campaign-calendar skill itself
  (`plugins/soleur/skills/campaign-calendar/SKILL.md`). If the skill's
  STEP1 work is itself near max-turn-budget on the new ceiling, the fix
  buys headroom but doesn't structurally solve the budget growth as the
  distribution corpus grows. **Mitigation:** monitor `num_turns` in
  successive runs over the next 4 weeks; if the trend is upward toward
  35+, file a follow-up issue to refactor the skill into multi-step
  pipeline (separate workflow per step) per the patterns in
  `scheduled-content-generator.yml`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change
(GitHub Actions workflow + ops runbook addendum). The fix does not touch
user-facing pages, copy, brand assets, infrastructure provisioning, billing,
data modeling, or product surface area. CTO domain is implicitly covered by
the AGENTS.md rules cited in this plan; no leader spawn required.

## Operational Notes

- Per `wg-when-a-pr-includes-database-migrations` does not apply (no DB
  migration).
- Per `wg-after-merging-a-pr-that-adds-or-modifies` (workflow modification):
  the post-merge `gh workflow run scheduled-campaign-calendar.yml` smoke-test
  in Acceptance Criteria § Post-merge satisfies this gate.
- Per `cq-workflow-pattern-duplication-bug-propagation`: this PR does NOT
  duplicate a job pattern from a sibling workflow; it edits one workflow's
  prompt and budget. No cross-workflow propagation needed.
- Per `cq-docs-cli-verification`: the STEP 2/2.5 prose uses
  `gh issue list --search '"<title>" in:title'`,
  `gh issue create --label ... --milestone ...`, `gh issue comment <N>`,
  and `gh issue close <N>`. All four are documented in
  `gh issue --help` and have shipped in prior workflows in this repo
  (e.g., `scheduled-cloud-task-heartbeat.yml` uses all four). No
  fabrication risk.
- Per `hr-in-github-actions-run-blocks-never-use`: the new STEP 2.5 bash
  block uses `{ echo ...; } > "$BODY_FILE"` for the multi-line body
  (matching the heartbeat workflow's Build failure email body pattern).
  No column-0 heredoc terminators.

## Implementation Sketch

Concrete bash for the prompt rewrite, ready for copy-paste into
`scheduled-campaign-calendar.yml`'s `prompt:` field. All snippets verified
against `gh 2.91.0` (developer machine) and match the action runner's
shipped gh version.

### STEP 2 — overdue scan with dedup

```bash
# Pre-compute today (UTC) for date comparisons
TODAY=$(date -u +%Y-%m-%d)

# Counters for the run summary
NEW=0
DEDUP=0
OVERDUE=0

# Scan distribution-content/*.md
for f in knowledge-base/marketing/distribution-content/*.md; do
  # Extract frontmatter via awk (between first two --- markers)
  fm=$(awk '/^---$/{c++; next} c==1' "$f")
  status=$(printf '%s\n' "$fm" | awk -F': ' '/^status:/{print $2; exit}')
  publish_date=$(printf '%s\n' "$fm" | awk -F': ' '/^publish_date:/{print $2; exit}')
  title=$(printf '%s\n' "$fm" | awk -F': ' '/^title:/{print $2; exit}' | sed 's/^"//;s/"$//')

  # Skip if not overdue
  [[ -z "$publish_date" ]] && continue
  [[ "$publish_date" > "$TODAY" || "$publish_date" == "$TODAY" ]] && continue
  case "$status" in
    scheduled|draft) ;;
    *) continue ;;
  esac

  OVERDUE=$((OVERDUE + 1))
  CANONICAL_TITLE="[Content] Overdue: ${title} (was scheduled for ${publish_date})"

  # Dedup: search for an existing OPEN issue with the same canonical title
  existing=$(gh issue list \
    --label scheduled-campaign-calendar \
    --state open \
    --search "\"${CANONICAL_TITLE}\" in:title" \
    --json number,title \
    --jq ".[] | select(.title == \"${CANONICAL_TITLE}\") | .number" \
    | head -1)

  if [[ -n "$existing" ]]; then
    gh issue comment "$existing" \
      --body "Re-detected on ${TODAY}; still overdue. Heartbeat from campaign-calendar workflow run."
    DEDUP=$((DEDUP + 1))
  else
    gh issue create \
      --title "$CANONICAL_TITLE" \
      --label "action-required,scheduled-campaign-calendar" \
      --milestone "Post-MVP / Later" \
      --body "**File:** \`${f}\`

This content item has \`status: ${status}\` but its \`publish_date\` (${publish_date}) is in the past.

**Action required:** Reschedule to the next available Tue/Thu slot or update status to reflect current state.

If this content is no longer planned, update \`status\` to \`cancelled\` or remove the \`publish_date\` field.

---
*Auto-generated by the campaign calendar CI workflow on ${TODAY}.*"
    NEW=$((NEW + 1))
  fi
done

echo "STEP 2 summary: ${OVERDUE} overdue items found, ${NEW} new issues created, ${DEDUP} existing issues commented on."
```

### STEP 2.5 — heartbeat issue when no new issues

```bash
if [[ "$NEW" -eq 0 ]]; then
  TITLE="[Scheduled] Campaign Calendar - ${TODAY} (heartbeat)"
  if [[ "$OVERDUE" -gt 0 ]]; then
    BODY="No new overdue items this run (${DEDUP} existing items deduped). Heartbeat issue to keep cadence-watchdog happy."
  else
    BODY="No overdue items detected. Heartbeat issue to keep cadence-watchdog happy."
  fi
  URL=$(gh issue create \
    --title "$TITLE" \
    --label "scheduled-campaign-calendar" \
    --milestone "Post-MVP / Later" \
    --body "$BODY")
  gh issue close "$URL" --comment "Auto-closed: heartbeat record only."
  echo "STEP 2.5: heartbeat issue created and closed: $URL"
else
  echo "STEP 2.5: skipped (${NEW} new issues are themselves the heartbeat signal)."
fi
```

**Notes:**

- Quoting around `$CANONICAL_TITLE` in the search and jq filter is
  load-bearing — content titles can contain colons and parentheses. The
  `.title == "..."` exact-match filter inside jq guards against
  GitHub-search's fuzzy-match behavior (which can return near-matches).
- `awk '/^---$/{c++; next} c==1'` parses YAML frontmatter without
  requiring a yaml-parser dep on the runner. Caveat: this is a
  poor-man's parser — it does NOT handle multi-line values or escaped
  delimiters. Distribution-content frontmatter has been simple
  (one-line key:value) for the entire history of the corpus; if that
  changes, swap to `yq`.
- `[[ "$publish_date" > "$TODAY" ]]` works for ISO-8601 YYYY-MM-DD
  dates because they sort lexicographically. Caveat: only valid for
  fixed-width ISO dates — fails for `2026-3-1` style. Distribution-
  content files all use the YYYY-MM-DD form per
  `plugins/soleur/skills/campaign-calendar/SKILL.md` Phase 1 spec.
- The bash here lives inside the `claude_args.prompt:` YAML literal
  block. Per `hr-in-github-actions-run-blocks-never-use`, no column-0
  heredoc terminators are used; multi-line strings are concatenated
  with `\n` inside double-quoted body args, which is valid YAML.

### Pre-merge verification commands

Before pushing, run:

```bash
# 1. Render the workflow YAML and validate it parses
yq eval '.jobs.refresh-calendar.steps[2].with.claude_args' .github/workflows/scheduled-campaign-calendar.yml

# 2. Confirm timeout-minutes ratio
yq eval '.jobs.refresh-calendar."timeout-minutes"' .github/workflows/scheduled-campaign-calendar.yml
# Expect: 30 (paired with --max-turns 40, ratio = 0.75)

# 3. Confirm no other workflow inadvertently affected
git diff --stat .github/workflows/
```

## Test Implementation Sketch

For TS1/TS2/TS3, the post-merge operator can run:

```bash
# TS1: smoke-test
RUN_ID=$(gh workflow run scheduled-campaign-calendar.yml --json | jq -r '.id // ""')
# (--json is not yet supported on `workflow run`; capture run id via
# subsequent `gh run list`):
gh workflow run scheduled-campaign-calendar.yml
sleep 30
RUN_ID=$(gh run list --workflow=scheduled-campaign-calendar.yml --limit 1 --json databaseId --jq '.[0].databaseId')

# Poll until conclusion
while true; do
  STATUS=$(gh run view "$RUN_ID" --json status,conclusion --jq '"\(.status) \(.conclusion)"')
  echo "$STATUS"
  [[ "$STATUS" == completed* ]] && break
  sleep 30
done

# Check num_turns in run log
gh run view "$RUN_ID" --log | grep -E '"num_turns"' | head -1
# Expect: "num_turns": <N> with N <= 35

# Verify a labeled audit issue exists with createdAt after run start
gh issue list --label scheduled-campaign-calendar --state all --limit 3 \
  --json createdAt,state,title,number
# Expect: top entry is from the last few minutes, either a new overdue
# issue or a closed heartbeat issue.
```

## References

- Issue: #2896
- Watchdog workflow: `.github/workflows/scheduled-cloud-task-heartbeat.yml`
- Supervised workflow: `.github/workflows/scheduled-campaign-calendar.yml`
- Runbook: `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`
  (will gain §H7 in this PR)
- Foundational learning: `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`
- Budget formula: `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md`
- Skill: `plugins/soleur/skills/campaign-calendar/SKILL.md`
- Sister silence incident (Cloud-side, closed): #2714 + plan
  `2026-04-21-fix-scheduled-content-generator-cloud-task-silence-plan.md`
- Duplicate cleanup target: #2968 (duplicate of #2146)

## Out of Scope / Non-Goals

- **Out of scope:** rescheduling/cancelling the actual overdue distribution
  files. That is a content-strategy decision the operator owns; it is
  tracked separately via #2146 (and via #2969 + #2970 for the two newer
  overdue items). This PR fixes the workflow that surfaces those items;
  it does not re-prioritize them.
- **Out of scope:** bumping `--max-turns` on the other 9 scheduled
  workflows. Their current budgets are healthy per the 2026-03-20 table.
  If a future incident shows a peer is also starved, fix per H7 with a
  scoped PR.
- **Non-goal:** preventing a future watchdog false-positive from a
  long-running schedule pause (e.g., during an Anthropic outage). The
  watchdog is intentionally simple and chatty by design; we accept ~1
  false-positive issue per quarter as the price of catching real
  silences within 1 cadence cycle.
- **Non-goal:** restructuring the campaign-calendar workflow into separate
  jobs (calendar-regen, overdue-scan, strategy-update, persist). That
  would require a real architecture change. The 40-turn budget gives 2x
  headroom; revisit only if num_turns trends upward.
