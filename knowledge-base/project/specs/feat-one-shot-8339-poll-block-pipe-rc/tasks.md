# Tasks: fix-ship-phase-7-poll-block-pipe-rc (#8339)

Plan: `knowledge-base/project/plans/2026-09-19-fix-ship-phase-7-poll-block-pipe-rc-plan.md`. AC numbers refer to that plan's `## Acceptance Criteria`.

## Phase 1: RED — fixture first (one commit, before any SKILL.md edit; AC1)

- [ ] 1.1 In `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, add `set +o pipefail` as the first statement inside `run_scenario`'s `( … )` subshell; add a 5th parameter `local block="${5:-$BLOCK_FILE}"` and `source "$block"` instead of `source "$BLOCK_FILE"`.
- [ ] 1.2 Make the mirror extraction executable: `extract_block "$MIRROR" | sed 's/<number>/4387/g' > "$MIRROR_FILE"`; add a `bash -n "$MIRROR_FILE"` pass/fail line (AC7). Do NOT touch `extract_block()` or the three-token fingerprint loop (AC8).
- [ ] 1.3 Add the harness self-check row: a mocks file written with a QUOTED heredoc (`<<'EOF'`) whose body is `false | true; echo "harness-pipefail-status=$?"` plus a `gh()` returning `MERGED CLEAN` on tick 1; `run_scenario "0-harness-pipefail-off" … "harness-pipefail-status=0"` (AC4). Drive it RED once by temporarily removing `set +o pipefail`; paste that one-line result into the PR body.
- [ ] 1.4 Add scenario 6 (`git merge origin/main` → CONFLICT lines, `return 1`; `git diff --name-only` → `foo.md`; `git merge --abort` → `MOCK: git merge --abort observed` on STDOUT; `gh pr view` → `OPEN BEHIND`), with the plan's AC2 must/must-not regexes; run it against `"$BLOCK_FILE"` and `"$MIRROR_FILE"` (5th arg on its own terminating line).
- [ ] 1.5 Add scenario 7 (`git merge` → `Merge made by the 'ort' strategy.`, rc 0; `git push` → `error: failed to push some refs to 'origin'`, `return 1`) with AC3's regexes; both blocks.
- [ ] 1.6 Add scenario 8 (`git fetch` → `fatal: unable to access 'origin'`, `return 1`; merge/push succeed) with AC3's scenario-8 regexes; both blocks.
  - [ ] 1.6.1 Mock `git()` dispatches on `"$1 ${2:-}"` with the exact patterns from the plan's Technical Considerations (`"rev-parse "*)`, `"merge origin/main")`, `"merge --abort")`, `"diff --name-only")`, `"fetch origin")`, `"push "|"push")`, `*) return 0`).
- [ ] 1.7 Extend the mirror-parity token loop with `'sync_rc=$?'`, `'git merge --abort'`, `'git push failed after merge'`, `'fetch origin main failed'` (AC5).
- [ ] 1.8 Run `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`; confirm scenarios 6/7/8 are RED on BOTH blocks and the parity tokens fail; quote the summary line in the PR body. Commit (`test(ship): RED fixtures for #8339 …`).

## Phase 2: GREEN — the fix in both fenced blocks

- [ ] 2.1 `plugins/soleur/skills/ship/SKILL.md`: inside the `<!-- phase-7-poll-block:start -->` fence, replace the `if ! git fetch … | tail -2 / elif ! git merge … | tail -5 / elif ! git push … | tail -2 / else` chain with the captured-rc arm from the plan's Proposed Solution (messages verbatim; success echo unchanged; existing re-fetch + MERGED/CLOSED break kept inside the new `else`). Nothing outside the fence; `OUTAGE_RE` / §5.5 untouched (AC8).
- [ ] 2.2 `plugins/soleur/skills/merge-pr/SKILL.md` §5.2: inside the mirror fence, replace the `&&` chain + single `else` with the same captured-rc arm, keeping merge-pr's success echo `auto-sync ${behind_syncs}/${MAX_BEHIND_SYNCS} pushed` and its re-fetch; update the prose sentence "this mirror is not directly tested" to say scenarios 6/7/8 now run against it.
- [ ] 2.3 Run the fixture: expect `0 fail`, ≥ 18 + new rows pass, both blocks `bash -n` clean. Commit (`fix(ship): capture rc before tail in the phase-7 BEHIND sync arm (#8339)`).

## Phase 3: Verification

- [ ] 3.1 AC8 diff-scope check: `git diff -U0 origin/main -- plugins/soleur/skills/ship/SKILL.md | grep '^@@'` hunks inside the fence range; `git diff origin/main -- plugins/soleur/skills/ship/SKILL.md | grep -c OUTAGE_RE` = 0; merge-pr hunks inside its fence + the one prose line; fixture diff has no `in_block` / `for token in 'MAX_BEHIND_SYNCS` lines.
- [ ] 3.2 AC6: `grep -c '"\$MIRROR_FILE"$' plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` ≥ 3.
- [ ] 3.3 AC9: `TEST_GROUP=scripts bash scripts/test-all.sh` green.
- [ ] 3.4 AC10: `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-19-fix-ship-phase-7-poll-block-pipe-rc-plan.md` passes.
- [ ] 3.5 AC11 retroactive run (scratchpad, scrubbed env, real git — recipe in plan §Test Scenarios "Retroactive"): capture the ~10 verdict lines (`merge conflict`, conflicted path, `Manual conflict resolution required on feat`, no `pushed`, `MERGE_HEAD` absent, porcelain empty, remote SHAs unchanged) into the PR body. No file under `specs/` for the transcript; never commit `$tmp`.
- [ ] 3.6 PR body: `Closes #8339`, `Ref #8383`, `## Changelog` (patch), the AC1/AC4 RED lines and the AC11 verdict block; `ship` renders `decision-challenges.md` (DC-1..DC-3) as informational.
