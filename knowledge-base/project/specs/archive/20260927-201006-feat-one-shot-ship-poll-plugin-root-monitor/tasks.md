---
title: "Tasks: fix(ship): Phase 7 poll loses the plugin root when its fence is run from disk under Monitor"
plan: knowledge-base/project/plans/2026-09-27-fix-ship-phase7-poll-plugin-root-under-monitor-plan.md
branch: feat-one-shot-ship-poll-plugin-root-monitor
lane: cross-domain
---

# Tasks

## 1. Setup

- [x] 1.1 Record the baseline. `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` should print `392 pass, 0 fail`.
- [x] 1.2 Record `wc -c plugins/soleur/skills/ship/SKILL.md` (should be 271034; the ceiling is 274000).

## 2. RED: fixture rows (`plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`)

Place every new row after scenario 13c (`EVIL_ROOT` is defined there) and after the mirror-parity loop.

- [x] 2.1 Build a spaced root: `SPACED_PARENT=$(mktemp -d)` and `SPACED_ROOT="$SPACED_PARENT/plugin root"`, a copy of `$PLUGIN_COPY`. Register it in `_TMP_OWNED` and call `assert_fixture_dir`. Hard-fail unless `[[ -d "$EVIL_ROOT" ]]`.
- [x] 2.2 Build `SUBST_BLOCK` and `SUBST_MIRROR` by replacing the token with `$SPACED_ROOT` as a literal, using bash `${line//"$tok"/"$SPACED_ROOT"}` with no `sed` or `perl`. Register both in `_TMP_OWNED`.
  - [x] 2.2.1 Check that the replacement landed, counting occurrences (`grep -oF … | wc -l`):
    - the token count after is 0;
    - the root count equals the token count before, and is at least 1;
    - the rewritten `SYNC_ROOT="$(set +u; printf '%s' "<SPACED_ROOT>")"` line is present.
- [x] 2.3 Create a fresh `mktemp` mocks file from `${SYNC_MOCKS}`, because scenario 9 deletes its own. Use forbid set `SUCCESS_FORBID|\[ship\.phase7\.precondition\]|does not name soleur`.
- [x] 2.4 Add row `17b-delivered-decoy`, with `SCEN_ROOT="$EVIL_ROOT"`, on both blocks (`run_scenario` fifth argument). Match the per-block success line: `auto-sync 1 pushed` for ship and `auto-sync 1/6 pushed` for the mirror.
- [x] 2.5 Add row `17c-delivered-unset`, with `SCEN_ROOT=unset`, on both blocks and with the same expectations.
- [x] 2.6 Add prose pins after the parity loop. For each SKILL.md, run `grep -qF` with two single-quoted fragments:
  - `` the root for this session is `${CLAUDE_PLUGIN_ROOT}` ``
  - `` export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>` using that path ``
- [x] 2.7 Run the suite. Expect the pins to be RED and 17b and 17c to be GREEN, since the existing binding is already correct. Record this in the PR body as proof of the diagnosis.

## 3. GREEN: skill prose (the fences stay byte-identical)

- [x] 3.1 In `ship/SKILL.md` Phase 7, add the "plugin root is fixed only in delivered text" notice. It goes after the `**Claude — Monitor tool loop**` line and before the fence. Use the exact text from the plan's Phase 2.
- [x] 3.2 In `merge-pr/SKILL.md` §5.2, append the pointer sentence to the `**Mirror invariant:**` paragraph.
- [x] 3.3 Check the new text against the W1/W1b/W2/W3 constraints. Do not spell out a checkout path. Keep the net ship growth at or below 800 bytes.

## 4. Verify

- [x] 4.1 Rerun the fixture suite: all green. Set `MIN_VERDICTS` to the **exact** new total, and add 17b, 17c and the pins to the scenario list in the header comment.
- [x] 4.2 Run Guard Contract mutations M1–M7 and harness edits H1–H2. Each should go RED while its named control stays GREEN; scenario 13c is the negative control. Revert each with `git checkout -- <file>`, never `git stash`. Put the results table in the PR body.
- [x] 4.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`
- [x] 4.4 `python3 scripts/lint-skill-body-budget.py --base origin/main`
- [x] 4.5 `bash scripts/plugin-root-anchor-debt.sh` should print `anchor-debt-files=0`.
- [x] 4.6 `bun test plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/components.test.ts`
- [x] 4.7 Confirm that both extracted fences are byte-identical to `origin/main`.
- [x] 4.8 Run `npx markdownlint-cli2` on both edited SKILL.md files.

## 5. Ship notes

- [x] 5.1 If the rename-guard false alarm (#9028) fires, rebuild the branch as one linear commit on `origin/main` with an identical tree. Never apply the override label.
- [x] 5.2 Keep to one PR. The guardrails.sh filing-gate matcher is a separate follow-up.
