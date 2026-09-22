# Tasks — feat-one-shot-8500-admin-merge-ready-script

Plan: `knowledge-base/project/plans/2026-09-22-feat-admin-merge-ready-script-plan.md` (Closes #8500)

## Phase 1 — Setup and tests first (RED)

- [ ] 1.1 Capture the read-only real-shape base fixture: a recently merged PR's head, all required checks green. Save `rules/branches/main` and paginated `check-runs?filter=all`, trimmed with `jq`, to `plugins/soleur/test/fixtures/admin-merge-ready/`, plus a provenance README (PR, SHA, date, ruleset IDs).
- [ ] 1.2 Write `plugins/soleur/scripts/admin-merge-ready.test.sh`:
  - [ ] 1.2.1 A strict PATH `gh` stub that dispatches on the full argv and exits 64 on anything else.
  - [ ] 1.2.2 Guard 1 rows R1, R3–R20 and H1–H4, all derived from the base by `jq` edits.
  - [ ] 1.2.3 An instrument self-test and a check that the number of cases run equals the declared count.
  - [ ] 1.2.4 `ADMIN_MERGE_READY_SLEEP=true` for the `--wait` rows.
- [ ] 1.3 Confirm RED: the suite FATALs on the missing SUT, and every row fails against an empty SUT.
- [ ] 1.4 Write `plugins/soleur/test/admin-merge-ready-wiring.test.sh` (Guard 2):
  - [ ] 1.4.1 Derive the population of `gh pr merge`+`--admin` lines and assert the same-line `--match-head-commit` rule, with a floor of 3 matching lines.
  - [ ] 1.4.2 Fixed-position assertions:
    - the inline block is absent;
    - the reference's merge fence runs the script before `gh pr merge`;
    - the `schedule:212` sentence is absent;
    - ship, merge-pr, one-shot and drain-prs each reference the script.
  - [ ] 1.4.3 W1–W6 run the real lint against a temp copy of the tree; include the W-H1 must-PASS line.
- [ ] 1.5 Confirm the wiring lint is RED on the current tree.

## Phase 2 — Core implementation (GREEN)

- [ ] 2.1 Implement `plugins/soleur/scripts/admin-merge-ready.sh` (mode 755):
  - [ ] 2.1.1 `--help`; argument validation (exit 2); `gh`/`jq` preconditions (exit 3).
  - [ ] 2.1.2 PR state/head/base check (verdict `stale`, exit 1).
  - [ ] 2.1.3 Required set via `gh api --paginate --slurp` on `rules/branches/<@uri base>`: rc-checked temp file, union over all rules. Empty set → exit 3; unpinned entry → exit 3.
  - [ ] 2.1.4 Check runs via `--paginate --slurp`, rc-checked, flattened.
  - [ ] 2.1.5 Single `jq` classifier driven by the required set: latest by `id` per (name, app.id); GREEN is success, skipped or neutral.
  - [ ] 2.1.6 Per-context lines plus the final marker line; exit codes 0, 1, 2 and 3.
  - [ ] 2.1.7 `--wait` with `--timeout`: 60s polls through the `ADMIN_MERGE_READY_SLEEP` seam; emit on change plus a heartbeat every 5 polls. Re-check the head on every poll. FAILED is terminal. Budget spent → `timeout`.
  - [ ] 2.1.8 Header comment: rationale, known limits, exit table, and the GitHub docs URL for skipped/neutral.
- [ ] 2.2 Make the Guard 1 suite pass. Apply the R2 mutation by hand once, confirm it reds R1, revert, and record the result for the PR body.
- [ ] 2.3 Run a live read-only smoke against this PR's head, plain and with `--wait --timeout 120`, and save both outputs for the PR body. Never run `gh pr merge`.

## Phase 3 — Wiring

- [ ] 3.1 In `settle-then-admin-merge.md`:
  - [ ] 3.1.1 Replace the step 2 inline block with the `--wait` call and the exit/verdict actions.
  - [ ] 3.1.2 Merge steps 4 and 5 into the fixed merge block.
- [ ] 3.2 Rewrite the `behind_exhausted` echo byte-identically in `ship/SKILL.md:2384` and `merge-pr/SKILL.md:484`.
- [ ] 3.3 Add the pointer sentence at `ship/SKILL.md` ~:2414 and `merge-pr/SKILL.md` ~:519.
- [ ] 3.4 Add one clause to `one-shot/SKILL.md:352`.
- [ ] 3.5 Add a new, separate bullet in the `drain-prs/SKILL.md` Sharp edges. No line may carry both `gh pr merge` and `--admin`.
- [ ] 3.6 Rewrite `schedule/SKILL.md:212`.
- [ ] 3.7 Append the pointer to the message at `monitor-pr-checks.sh:237`.
- [ ] 3.8 Re-run:
  - the new suites;
  - `monitor-pr-checks.test.sh`;
  - `ship-phase-7-poll-fixtures.test.sh`;
  - markdownlint on the edited files;
  - shellcheck on the new scripts.

## Phase 4 — Ship

- [ ] 4.1 If #8537 is MERGED, merge `origin/main`, keep #8537's "It fails closed" sentence verbatim, and re-run the Phase 3 suites.
- [ ] 4.2 File the PreToolUse-hook follow-up issue (see `decision-challenges.md` item 1) and link it in the PR body.
- [ ] 4.3 In the post-mortem's Action Items, change the #8500 row from `open` to `fixed by #<PR>`.
