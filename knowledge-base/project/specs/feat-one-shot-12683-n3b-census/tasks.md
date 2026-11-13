# Tasks: feat-one-shot-12683-n3b-census (#12683)

Plan: `knowledge-base/project/plans/2026-11-13-fix-n3b-census-6604-verify-lines-and-token-client-plan.md`

## 1. Setup and red-first evidence

- [ ] 1.1 Record the baseline: the suite prints `=== Results: 286/286 passed, 0 failed ===`.
- [ ] 1.2 Write the R1 and R2 content-anchored edit scripts in the scratchpad. R1 edits one function body with a `#`
      delimiter, R2 is an ENVIRON-fed awk insertion. Each asserts exactly one changed line per file.
- [ ] 1.3 Replay R1 and R2 on two detached worktrees of HEAD, at the same time. Expect 286/286 from both, then remove
      the worktrees (AC1).

## 2. Core implementation

- [ ] 2.1 Phase 1: extract `rb_line_v2`/`rb_line_v3`/`rb_line_v4` and `N3B_V3_URL`, and make `rb_expected` call them.
      Suite 286/286.
- [ ] 2.2 Phase 2: add the H18 rows and helpers.
  - [ ] 2.2.1 Add `_h18_vbld` (modes `built`, `both`, `builder-only`, and the `@@precondition@@` channel) and `_h18_v`.
  - [ ] 2.2.2 Add `n3b_frozen_all`, and rework `_h18_fs <label> <awk> <key> <reason>` to use it.
  - [ ] 2.2.3 Rewrite `_h18_red` as ERE over `D|R|V[234]`.
  - [ ] 2.2.4 Add Guard 1 rows gVr1, gVr2, gVr4, gVr5, gVr6, gVr11, fs-v4-unquoted, fs-v3-id, fs-v2-url, fs-r-unquoted, and
        the hb web1-pin cases.
  - [ ] 2.2.5 Add Guard 2 rows g5r1-g5r6 and g5r8.
  - [ ] 2.2.6 Add harness rows H-d, H-e, H-f and H-g as instrument controls.
  - [ ] 2.2.7 Pass `$_wpin` as `n3b`'s 5th argument at all 6 call sites. Keep the `_n3b=` line and the fs-self control
        on D/R.
  - [ ] 2.2.8 Run the suite. H18 FAIL names the new rows, and the fs-V rows report `(did-not-land)`. Save the line (AC2).
- [ ] 2.3 Phase 3: the fix.
  - [ ] 2.3.1 Add the `N3B_FROZEN_V2/V3/V4` quoted heredocs, and switch the `_n3b=` line and the fs-self control to
        `n3b_frozen_all`.
  - [ ] 2.3.2 In `n3b_frozen_self`, add the `@ID@` placement checks before the `case`, with the `@ID@ placement:`
        message.
  - [ ] 2.3.3 In `n3b_lists`, select the anchor by kind (V3 as a fixed string), and add the `if [[ $k == V* ]]` V `case`
        with `key=url`. Leave the D/R lines untouched, and print ` (no <K> URL end)` for V kinds.
  - [ ] 2.3.4 In `n3b`, extend the `slot:` check to the web1 pin, and add the V2/V3/V4 `n3b_builder` calls.
  - [ ] 2.3.5 In `_h18_bld` `both` mode, add `N3B_FROZEN_V<k>=$(rb_line_v<k> @ID@)`. Give the F4 rows the `_h18_v` suffix.
  - [ ] 2.3.6 Add p5 to `n3b_census`'s `flush()`.
  - [ ] 2.3.7 Add the maintenance comment above `rb_expected`, update the suite comments by content anchor, and update
        the N3b and H18 pass messages.
  - [ ] 2.3.8 Run the suite: 286/286 (AC4, AC7).
- [ ] 2.4 Phase 3c: WIP-commit the fix, then replay R1 and R2 on worktrees of that commit. Both turn N3b red with the
      named tags, and N3 stays `pass:` on R1 (AC5).

## 3. Documents, guards and ship

- [ ] 3.1 Edit items 5 and 6 of the archived 2026-11-11 plan (AC10).
- [ ] 3.2 Run AC3, AC6, AC8 (lint-skill-body-budget, plugin-root-anchoring) and AC9 (grep-q-pipe-guard).
- [ ] 3.3 Check AC11 (diff scope). Never edit either runbook or the encryption-posture ledger.
- [ ] 3.4 Merge only after main's CI is green (AC12), under the standing delegation on #9927 scope item 2.
