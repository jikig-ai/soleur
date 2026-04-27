# Tasks: feat-one-shot-2907

**Plan:** [2026-04-27-fix-cla-allowlist-claude-bot-format-plan.md](../../plans/2026-04-27-fix-cla-allowlist-claude-bot-format-plan.md)
**Issue:** #2907
**Branch:** `feat-one-shot-2907`
**Type:** `fix(ci)` / `semver:patch`

## Phase 1 — Edit allowlist (pre-merge)

- [ ] 1.1 Re-read `.github/workflows/cla.yml` (Edit tool requires a fresh read after any compaction).
- [ ] 1.2 Apply the one-line edit on line 34: replace bare `claude` with `claude[bot]`. Keep `app/claude` (defense-in-depth).
- [ ] 1.3 Verify YAML still parses: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/cla.yml'))"` exits 0.
- [ ] 1.4 Confirm no other files changed: `git status --short` shows only `M .github/workflows/cla.yml`.

## Phase 2 — Ship (PR)

- [ ] 2.1 Run `skill: soleur:compound` to capture any planning learnings.
- [ ] 2.2 Run `skill: soleur:ship` with PR body containing `Closes #2907` and the body text from the plan's "PR Body Reminder" section.
- [ ] 2.3 Apply `semver:patch` label.
- [ ] 2.4 Wait for PR checks (CI + cla-check on the PR itself — runs against the `main` workflow file, so this PR's cla-check runs the **old** allowlist; it should still pass because the commit is authored by `deruelle`).
- [ ] 2.5 After approval, queue auto-merge: `gh pr merge <N> --squash --auto`.
- [ ] 2.6 Poll `gh pr view <N> --json state --jq .state` until `MERGED`.

## Phase 3 — Post-merge validation (operator)

- [ ] 3.1 Run `cleanup-merged` per AGENTS.md.
- [ ] 3.2 Within 48h of merge: identify the next `claude[bot]`-authored PR via `gh pr list --author 'app/claude' --state open --limit 5` (or look at the daily community-digest cron output around 07:00 UTC).
- [ ] 3.3 Confirm `gh pr checks <bot-pr-N>` reports `cla-check: pass` without commit-authorship rewriting.
- [ ] 3.4 If the gate still fails: capture the failing commit's resolved committer login from the contributor-assistant action's run log, file a follow-up issue, and update the allowlist accordingly.

## Notes

- Pre-merge automated tests are not applicable for YAML-edit-only PRs (consistent with `2026-03-19-chore-cla-ruleset-integration-id-plan.md` and `2026-03-20-chore-standardize-claude-code-action-sha-plan.md`).
- `pull_request_target` runs the workflow from the **base branch**, not the PR branch, so the fix cannot be exercised on this PR — only on the next post-merge bot-authored PR.
