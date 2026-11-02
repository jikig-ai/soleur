# Tasks: LUKS runbook Better Stack write-scope verified

Plan: knowledge-base/project/plans/2026-11-02-docs-luks-runbook-betterstack-write-scope-verified-plan.md
Issue ref: #11869 | PR: #11926 (draft, reuse)

## Phase 1 - Edit

- 1.1 Read `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` section 5 (anchor on the text `The write token's scope for this endpoint is UNVERIFIED`).
- 1.2 Replace the span through `has not been exercised from this repo.` with the verified-on-2026-11-02 note (HTTP 200 on incident `1045365287`, not one of the two named in the paragraph; `resolved_at` 2026-11-02T22:32:29Z; evidence: the "Manual resolve done" comment on #11869, 22:32 UTC; plus the one-line "verified scope is not authorization" sentence).
- 1.3 Leave the 401/403 stop rule, the resolve script block and every other runbook byte unchanged.

## Phase 2 - Verify

- 2.1 Run the plan's AC1-AC5 checks; each must pass. The paragraph is hard-wrapped, so AC2 and AC3 grep a newline-flattened copy (`tr '\n' ' ' < file | tr -s ' '`) and AC3 compares PR head with `git show origin/main:<runbook>`; AC1 greps the single-line anchors `UNVERIFIED**` and `has not been exercised from this repo`.
- 2.2 Run markdownlint on the runbook and `bash scripts/pre-push-ratchet-lane.sh`.

## Phase 3 - Ship

- 3.1 Commit (separate `git add` and `git commit -F <file>` calls), push, mark PR #11926 ready with `Ref #11869`.
- 3.2 After merge, read the file by merge SHA and confirm AC1-AC3 from a detached `origin/main` worktree (postmerge).
