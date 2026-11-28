# Tasks: fix(ship) merge-poll stderr isolation, absent required check, locked arm form vs kb-archive gate

Plan: `knowledge-base/project/plans/2026-11-28-fix-ship-poll-stderr-missing-check-kb-gate-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-ship-poll-stderr-missing-check-kb-gate/decision-challenges.md`

## Phase 1: Setup and RED tests (commit tests before fixes)

- [ ] 1.1 Create `plugins/soleur/test/fixtures/gh-pr-view-hint.txt`: the real 8-line gh 2.106.0 hint block with synthesized PR number 4387.
- [ ] 1.2 Measure the ship ceiling: `python3 scripts/lint-skill-body-budget.py --base origin/main`. Record the headroom (69 B at plan time).
- [ ] 1.3 `plugins/soleur/test/pr-merge-poll.test.ts`:
  - [ ] 1.3.1 `parsePrPollRead` cases: hint on stderr leaves the state unchanged; a merged stream on stdout returns null; rc 1 + hint + `gh: HTTP 502` → `fetch-error: gh: HTTP 502`; rc 1 + hint only → `fetch-error: rc=1`; rc 0 + valid stdout + hint and a warning on stderr → the state; rc 0 + empty stdout → null. Export `GH_ERR_LINE_MAX`.
  - [ ] 1.3.2 Iterate the `Harness` union for the stdout-only sentence in `behindSyncInstructions` and in `pollInstructions` (except `cursor`, which returns the behind-sync stop unchanged) with the embedded behind-sync text removed.
  - [ ] 1.3.3 Guard 2 scan: git ls-files, non-test files, backslash-continuation joiner, quote- and paren-depth matcher, shrink-only exclusion list, floor of at least 10 files, mutation rows 1–5, harness rows H-a/H-b. RED must report exactly the 10 known sites.
- [ ] 1.4 `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`: rows H1, H1f, H2, H3, H4, H4b and H6 on `:ship` and `:merge-pr`, plus the `WANTH` pin. H1/H1f use the RROOT chosen-body required-set stub. H1–H3 assert every state line matches `^[0-9:]{8} \[[0-9]+/90\] PR 4387 (OPEN|MERGED|CLOSED|fetch-error:)` and no line contains `PR 4387 hint:` (today's output prefixes the hint, so a bare `^hint:` check would pass on the broken code). H6 fails only the `GH_ERR` mktemp call.
- [ ] 1.5 `.claude/hooks/ship-kb-archive-gate.test.sh`: Guard 1 rows from T83 on.
  - [ ] 1.5.1 Parse the site list from `arm-check-sites.test.sh` (`SITES`, `LINK_ONLY`, `CANON`). Extract every span containing both `gh pr merge` and `--match-head-commit`, substitute placeholders, and assert per-site span counts (fail loudly when one is empty).
  - [ ] 1.5.2 RED reason rows: the ship block's reason is `more than one gh pr merge invocation`, and the admin hatch's is `names no 40-hex sha`.
  - [ ] 1.5.3 Mutation rows 1–13 (row 13: the composite arm-check-plus-lock one-call form) and harness rows H-a–H-d. Row 2/3 inputs must not nest a `gh pr merge`, so they reach the new rules.
- [ ] 1.6 `plugins/soleur/test/sync-pr-behind.test.sh`: standalone hint row (right branch, hint on stderr, no exit 12).
- [ ] 1.7 `.claude/hooks/ship-operator-step-gate.test.sh`: hint row (flag-only merge, a parked PR other than the current one, allowed).
- [ ] 1.7b Apply the plan's "Test-harness requirements" 1–8: `assert_deny_why`, the per-block redirect count, H3 on Q8's shape plus the stub-order row, stdout-only state-line checks with a non-zero line floor, the H6 `rm` shim and file-backed mktemp counter, the sync `MERGED CLEAN` row, the operator-gate no-PR row, and Guard 2 prefix-skipping with counted exclusions (rows 6–7).
- [ ] 1.8 Commit the RED tests and confirm each fails for the stated reason.

## Phase 2: Core Implementation

- [ ] 2.1 Defect 1, fence (ship Phase 7) and mirror (merge-pr §5.2):
  - [ ] 2.1.1 `SYNC_SNAP=""; GH_ERR=""`, then one `trap 'rm -f "$SYNC_SNAP" ${GH_ERR:+"$GH_ERR"}' EXIT`; remove the conditional trap from the precondition chain.
  - [ ] 2.1.2 `GH_ERR="$(mktemp 2>/dev/null)" || GH_ERR=""`. Both state reads use `2>"${GH_ERR:-/dev/null}"` and `|| s="fetch-error: $(gh_err_line $?)"`.
  - [ ] 2.1.3 Fence-local `gh_err_line`: first non-empty line not starting with `hint:` or whitespace, cut with `${e:0:200}`, else `rc=<rc>`. It must be errexit-safe.
  - [ ] 2.1.4 Update the fixture's mirror-parity tokens (combined trap, redirect, `gh_err_line`).
- [ ] 2.2 `plugins/soleur/scripts/sync-pr-behind.sh`: the 3 standalone reads go stdout-only with `errf`; add one shared `gh_err_line` for every stderr echo (including `queue_state_read` and `qw_snapshot`); drop the 3 stale `2>&1` comments (and reword the test-file one); `queue_wait_eval`'s echo uses `gh_err_line` too. Re-anchor G6-1…G6-8 and move the `lsa`–`lsh` junk.
- [ ] 2.3 `.claude/hooks/ship-operator-step-gate.sh`: stdout-only current-branch read, a function-local stderr file removed on every return path, and no second EXIT trap.
- [ ] 2.4 `gh run view` poll snippets (ship post-merge, `schedule/SKILL.md`): the same stderr-file form. Move ship's "Why this pattern" paragraph, rewritten, into `ship/references/monitor-hygiene.md` with a relative pointer.
- [ ] 2.5 `plugins/soleur/lib/pr-merge-poll.ts`: `parsePrPollRead({rc, stdout, stderr})` (spec-only doc comment) and the stdout-only sentence in every `behindSyncInstructions` arm. Add the same sentence to `plugins/soleur/lib/harness.ts` `pollInstructions`.
- [ ] 2.6 Defect 2: run the fixture. H1, H1f, H2, H3, H4, H4b and H6 must go GREEN with no change to the required-set arm's predicates.
- [ ] 2.7 Defect 3, `.claude/hooks/ship-kb-archive-gate.sh`:
  - [ ] 2.7.1 Rule (i): a bare PR number `^[0-9]{1,9}$` beside one `--match-head-commit`. A literal 40-hex means census by sha; one double-quoted simple expansion means census by PR number. Read the operand with a new raw extractor over `$CMD` (residues stop at `$`), applied to every invocation.
  - [ ] 2.7.2 Rule (ii), in place of the multi-invocation deny and ahead of the proven-foreign exit: multiple invocations only when the raw residues, the stripped residues and the raw `--match-head-commit` operands are all byte-identical.
  - [ ] 2.7.3 Residuals paragraph: the restrict-only argument, the quoted-operand catch, the census-vs-`H` window, the admin hatch.
- [ ] 2.8 `plugins/soleur/skills/ship/references/merge-queue-dequeue.md` step 3: `gh pr merge <pr-number>`. Re-run `arm-check-sites.test.sh`.

## Phase 3: Testing and close-out

- [ ] 3.1 Run `ship-phase-7-poll-fixtures.test.sh`, `sync-pr-behind.test.sh`, `ship-kb-archive-gate.test.sh`, `ship-operator-step-gate.test.sh`, `arm-check-sites.test.sh`, `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/harness.test.ts`, `python3 scripts/lint-trap-tempfile-ownership.py`, and `python3 scripts/lint-skill-body-budget.py --base origin/main` (ship at least 50 B under ceiling). CI is the gate.
- [ ] 3.2 Learning: `knowledge-base/project/learnings/workflow-issues/2026-11-28-a-cli-hint-on-stderr-switched-off-every-open-arm-of-the-merge-poll.md` (all three defects, the interlock, the before/after gate table, the incident timeline, `## Session Errors`). Add a dated follow-up line to the 2026-11-25 learning's §3.
- [ ] 3.3 PR #13112 body: `Closes #12697`, `Closes #12963`, `Ref #13115`, `Ref #13017`, and a `## Changelog` section (semver:patch).
- [ ] 3.4 Before arming, pipe the documented arm block through `post-dispatch-watch-gate.sh`, `guardrails.sh` and `background-poll-prefer-monitor.sh` as PreToolUse input and confirm each allows it.
- [ ] 3.5 Arm this PR with the measured-accepted flag-only locked form after the arm check. Sync BEHIND by hand if the installed poll does not.
