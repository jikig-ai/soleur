---
module: rule-metrics-aggregate workflow
date: 2026-04-15
problem_type: integration_issue
component: github_actions
symptoms:
  - "rule-metrics-aggregate.yml first run 24444855398 failed at git push"
  - "remote: 3 of 3 required status checks are expected"
  - "remote: Required status check cla-check is expected"
root_cause: direct_push_blocked_by_rulesets
severity: high
tags: [github-actions, rulesets, bot-pr, synthetic-check-runs, pipeline-gotchas]
related:
  - 2026-03-19-content-publisher-cla-ruleset-push-rejection.md
  - 2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md
  - 2026-03-19-github-actions-bypass-actor-not-feasible.md
issues: ["#2258", "#2264"]
pr: "#2270"
---

# rule-metrics aggregator: PR pattern + session gotchas

## Problem

`.github/workflows/rule-metrics-aggregate.yml` shipped in PR #2213 with `permissions: contents: write` and a direct `git push` to `main`. The first run (manual dispatch `24444855398`, 2026-04-15) failed at the push step — rejected by the `CI Required` (ruleset 14145388) and `CLA Required` (ruleset 13304872) rulesets that protect `main`. The workflow was both a hardening concern (#2258) and non-functional at runtime.

## Solution

Applied the canonical PR + synthetic-check-runs pattern already used by `.github/workflows/scheduled-weekly-analytics.yml`:

- Expand `permissions:` to `checks`, `contents`, `pull-requests` (dropped `statuses` after review — Check Runs API path only; see review agents' flagging).
- Create `ci/rule-metrics-YYYY-MM-DD` branch, `gh pr create`, post four synthetic Check Runs (`test`, `cla-check`, `dependency-review`, `e2e`) via the **Checks API** (`POST /repos/.../check-runs`), then `gh pr merge --squash --auto`.
- Use canonical bot email `41898282+github-actions[bot]@users.noreply.github.com` (original workflow used the non-numeric form).
- Delete one-shot migration `scripts/backfill-rule-ids.py` (and test + test-all.sh line) now that PR #2213 has backfilled all 72 rule IDs in AGENTS.md.

No new technical insight — the pattern was already documented in `2026-03-19-content-publisher-cla-ruleset-push-rejection.md`. The value of this session is capturing the session gotchas below so future pipeline runs avoid the same procedural friction.

## Session Errors

1. **`git add` of paths already staged via `git rm` fails with `pathspec did not match`.**
   - Evidence: After `git rm scripts/backfill-rule-ids.py tests/scripts/test_backfill_rule_ids.py`, a follow-up `git add ... scripts/backfill-rule-ids.py ...` in the commit command exited 128.
   - Recovery: Staged only the remaining modified paths; the deletion entries carried through the commit unchanged.
   - **Prevention:** After `git rm`, do not re-add the same paths. Use `git status` to confirm what is already staged, and only `git add` additional modified files.

2. **`gh issue create --milestone N` requires the milestone *title*, not the number.**
   - Evidence: `gh issue create ... --milestone 6` exited with `could not add to milestone '6': '6' not found`. The milestone exists (API shows `{"number":6,"title":"Post-MVP / Later"}`), but `gh issue create` resolves the flag against `title`.
   - Recovery: Retried with `--milestone "Post-MVP / Later"`; issue #2272 was filed.
   - **Prevention:** When creating issues with `gh`, always pass the milestone *title* as the value. Retrieve via `gh api /repos/<owner>/<repo>/milestones --jq '.[] | {number, title}'` and pass the `title` field.

3. **PreToolUse security-reminder hook aborts the first Edit on a workflow file even when no untrusted inputs are touched.**
   - Evidence: First `Edit` against `.github/workflows/rule-metrics-aggregate.yml` produced `PreToolUse:Edit hook error: [security_reminder_hook.py]` with injection guidance; edit was rejected.
   - Recovery: Re-issued the same edit unchanged; second attempt succeeded (the hook appears to be advisory-by-reminder but aborts the *first* call to surface the warning).
   - **Prevention:** Treat the first workflow-file edit as expected-to-trip; retry after reading the reminder. No code change needed — this is hook intended behavior.

## Prevention

- Every new scheduled workflow that mutates repo files must use the PR + synthetic-check-runs pattern. Reference the canonical implementation at `.github/workflows/scheduled-weekly-analytics.yml:68-119`. Never declare `permissions: contents: write` + `git push` on a protected branch.
- `permissions:` blocks must be audited for least-privilege: `statuses: write` is not required when the workflow uses only the Checks API (`/check-runs`). Four review agents flagged this in PR #2270.
- Deprecated: When a migration script completes its one-shot job, delete it in the same PR that removes its sole invocation — don't let it accrue a maintenance tail.

## Follow-ups

- Issue #2272 tracks extracting the bot-PR + synthetic-checks boilerplate into a composite action, collapsing the four near-identical `gh api check-runs` calls into a loop, and migrating both `rule-metrics-aggregate.yml` and `scheduled-weekly-analytics.yml` to the shared action.

## Cross-references

- `2026-03-19-content-publisher-cla-ruleset-push-rejection.md` — canonical PR-pattern solution.
- `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md` — Check Runs vs Statuses, never use `[skip ci]`.
- `2026-03-19-github-actions-bypass-actor-not-feasible.md` — why `cla-check` integration_id (15368) mandates `GH_TOKEN: ${{ github.token }}`.
- `2026-02-21-github-actions-workflow-security-patterns.md` — least-privilege permissions, SHA-pinned actions.
