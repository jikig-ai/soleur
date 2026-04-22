# Tasks — Verify Growth Audit Rubric Tables (#2802)

**Plan:** `knowledge-base/project/plans/2026-04-22-chore-verify-growth-audit-rubric-tables-2802-plan.md`
**Branch:** `feat-one-shot-2802-verify-growth-audit-rubric-tables`
**Issue:** #2802

## Phase 1 — Run Validator

- [x] 1.1 Resolve the latest AEO audit file: `AUDIT=$(ls -1 knowledge-base/marketing/audits/soleur-ai/*-aeo-audit.md | sort | tail -n 1)` and confirm it is `2026-04-22-aeo-audit.md` ✓ (15018 bytes)
- [x] 1.2 Run the SAP Scorecard grep assertions (Structure/40, Authority/35, Presence/25) — all three must print PASS ✓ `PASS: Structure/40, Authority/35, Presence/25`
- [x] 1.3 Run the 8-component AEO diagnostic count grep — must equal `8/8` ✓ `PASS: 8-component count 8/8`
- [x] 1.4 Capture validator stdout verbatim to a temp file for use in the closing comment ✓
- [x] 1.5 On FAIL → branch to Phase 1b; on PASS → continue to Phase 2 — PASS, branching to Phase 2

## Phase 1b — P1 Follow-Up (only if Phase 1 FAILs)

- [ ] 1b.1 Run `diff -u knowledge-base/marketing/audits/soleur-ai/2026-04-21-aeo-audit.md knowledge-base/marketing/audits/soleur-ai/2026-04-22-aeo-audit.md` to capture delta
- [ ] 1b.2 File P1 issue via `gh issue create --title "P1: scheduled-growth-audit.yml dropped <rubric> table in run 24795319398" --label "priority/p1-high,domain/marketing,type/bug" --milestone "Post-MVP / Later"`
- [ ] 1b.3 Include validator failure output, audit diff, and link to PR #2795 in issue body
- [ ] 1b.4 Close #2802 with `gh issue close 2802 --comment "Pin dropped — see #<new-P1>"`

## Phase 2 — Close #2802 With Evidence

- [x] 2.1 Build closing comment body referencing audit file path, workflow run URL 24795319398, merge PR #2810, and pasting Phase 1 validator output verbatim
- [x] 2.2 Post comment via `gh issue comment 2802 --body-file -` heredoc (avoid multi-line `--body` flag per AGENTS.md `hr-in-github-actions-run-blocks-never-use`)
- [x] 2.3 Run `gh issue close 2802` (deferred to PR body `Closes #2802` at merge; evidence comment posted before close)
- [x] 2.4 Verify `gh issue view 2802 --json state --jq .state` prints `CLOSED` — pending merge of PR #2823

## Phase 3 — Cleanup

- [ ] 3.1 Decide PR path: default is no PR (leave worktree for next cleanup-merged sweep). If `/ship` insists, open a docs-only PR titled `chore: verify #2802 pinned-template follow-through (docs only)` with `Closes #2802` in body.
- [ ] 3.2 Run `/soleur:compound` to capture any learnings (expected to skip gracefully — happy-path verification)
