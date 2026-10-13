# Tasks — feat-one-shot-10094-slot-trigger-lease-legs

Plan: `knowledge-base/project/plans/2026-10-13-fix-slot-trigger-lease-nightly-legs-closeout-plan.md`
Issue: #10094 (closes) · fold-ins: #3373, #3221 · umbrella: #9993 (stays open)

## 1. Final verification

- [ ] 1.1 Run `gh run list --workflow=scheduled-integration-suites.yml --limit 5
  --json databaseId,conclusion,createdAt,event,headSha`; identify the latest
  `schedule`-event run post-#10001.
- [ ] 1.2 Run
  `gh api repos/jikig-ai/soleur/actions/runs/<run-id>/jobs -q '.jobs[0].steps[]
  | select(.name | test("SLOT_TRIGGER|WORKTREE_LEASE")) | "\(.conclusion)\t\(.name)"'`;
  both lines must read `success`. (AC1)
- [ ] 1.3 Optional corroboration (skip if no `doppler` dev access): run the
  `pg_proc.prosrc` probe from plan Phase 1 step 2; expect two rows with
  `has_240s = t`.
- [ ] 1.4 Honest-exit check: if either leg reads `failure` on a `schedule`-event
  run post-#10001, do NOT proceed to §2 — comment the run link + failing step on
  #10094 and stop.

## 2. #10094 closeout

- [ ] 2.1 Post the root-cause comment on #10094 (drift table + run-SHA
  explanation + green-run evidence list).
- [ ] 2.2 `gh issue close 10094 --comment "<evidence pointer>"`; verify
  `gh issue view 10094 --json state` returns `CLOSED`. (AC2)

## 3. Tracker hygiene

- [ ] 3.1 Comment on #9993: slot-trigger + worktree-lease legs verified green
  under #10094 scope; tracker remains open for remaining legs. Verify #9993
  still `OPEN`. (AC3)
- [ ] 3.2 `gh issue close 3373 --comment "<evidence>"` citing
  `scheduled-integration-suites.yml:262` + nightly run; verify `CLOSED`. (AC4)
- [ ] 3.3 `gh issue close 3221 --comment "<evidence>"` citing the nightly
  env-gated legs + `scripts/lint-integration-env-gates.sh`; verify `CLOSED`.
  (AC4)

## 4. PR hygiene

- [ ] 4.1 Confirm `git diff --quiet origin/main...HEAD -- apps/ plugins/
  .github/ scripts/` exits 0 (no code changes). (AC5)
- [ ] 4.2 Ensure PR body carries `Closes #10094` and notes the #3373/#3221
  fold-ins.
