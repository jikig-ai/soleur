---
title: "`git tag --merged` fails open two ways, and an equality guard over two copies covers only the slice it compares"
date: 2026-09-27
category: integration-issues
module: inngest-bootstrap-pin-bump
tags: [git, ci, drift-guard, mutation-testing, adr-232]
issue: 8782
pr: 9049
---

# Learning: `git tag --merged` fails open, and a byte-equality guard covers only its slice

## Problem

#8782 moved the ADR-232 pin writer (`.github/scripts/bump-inngest-bootstrap-pin.sh`) and
its checker (AC6 in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`) from
"semver-max over every `vinngest-v*` tag" to "semver-max over tags merged into `HEAD`". The
plan and the self-run 13-mutant battery were green. A 10-seat review then found three gaps,
each one a property the guards named but did not enforce:

1. **`git tag --merged` fails OPEN in two different ways, and both exit 0.**
   - On a **shallow** checkout it silently drops every tag below the graft.
   - On an **unreadable** history (a missing mid-history object) it prints `error: Could not
     read <sha>` on **stderr** only, and still lists the tags *above* the break. The result is a
     *truncated* set, not an empty one.

   The plan's ADR text said "a corrupt walk returns an empty set". That holds only when no tag
   sits above the break.
2. **The byte-equality guard over the two selector blocks covered only the 3 lines it
   sliced.** How the checker *used* the value was unpinned:
   - an `export LATEST_TAG=…` or `[[ … ]] && LATEST_TAG=…` reassignment after the selector
     survived (the assignment count only saw lines that *start* with `LATEST_TAG=`);
   - so did `|| true` appended inside the assert's eval string (the wiring check was a
     substring grep).

   Both mutants were 448/0 green.
3. **"Off main" is a point-in-time verdict.** The build refuses a tag when it is pushed, but
   the bump and AC6 re-judge reachability on every run. If the tag's PR later lands through a
   merge-commit or rebase merge (the repository allows both), a refused, image-less tag becomes
   the merged max. The runbook's new "delete it anyway, for hygiene" was therefore unsafe
   advice. The crane-failure deferral then ended green `skipped` for backfills whose target had
   published long ago, and its text could say "delete the tag" about the pinned tag itself.

## Solution

- **Writer:** refuse a shallow checkout *and* any stderr from a pre-walk
  (`walk_err=$(git tag --merged HEAD --list 'vinngest-v*' 2>&1 >/dev/null)`) before
  resolution. The selector itself keeps `2>/dev/null` so it stays identical to AC6.
- **Writer:** read `PIN_TAG` as the max over *both* files. Defer only when the target is newer
  than the signed tag and not already pinned. Every other registry failure is an error. Never
  tell anyone to delete a merged tag.
- **Checker:** add AC6's own shallow-or-truncated arm (CI FAIL, local SKIP). It reads the walk's stderr
  like the writer's `walk_err`; the ship-gate advisor caught that the first version mirrored only the
  shallow half. Pin every write of
  `LATEST_TAG` (exactly one), each pin assert as a whole line under `assert "`, and both CI
  fail-arms as literal `"false"`. Give the dedicated-host drift message the same
  "do NOT bump down" branch.
- **Suite:** add rows B7b (no tags), B7c (the truncated set above a missing object), B22
  (dedicated-host pin above), B23/B24 (the deferral narrowed), and one B21 member per regex
  constraint (`v2x0x0`, `vx-v9.9.9`, `v.9.9`: each sorts above v1.1.40 under its mutant).
- **Docs:** make deleting an off-main tag **required**, and record the point-in-time verdict
  and a version-allocation rule (a new version must sort above *every* tag) in ADR-232.

All 17 review-driven mutants were killed. The suite went from 448 to 483 assertions.

## Key Insight

- **A fail-open primitive is a set of failure modes, not one.** For any git or CLI read whose
  rc stays 0 on damage, enumerate what it returns for: nothing reachable, a partial walk, and a
  cut-off history. Refuse on the evidence each mode leaves (here, stderr), never on emptiness
  alone.
- **An equality guard between two copies proves the copies match and nothing about what each
  consumer does with the value.** Pin the consumer's writes and reads separately, at
  whole-statement granularity.
- **A verdict-helper self-test must use a HERMETIC bad state and an EXACT expected delta.** My
  first version asserted `FAIL moved >= 3` over whatever state the last fixture left behind.
  That fixture's pins also failed, which padded the count, so neutering `assert_result` still
  cleared the threshold. With two hermetic states (verdict checks failing, then side-effect
  checks failing) and `==` deltas, all five neuters were killed.

## Session Errors

1. **The first `draft-pr` push was remote-rejected (`failed`).** Recovery: a plain retry. **Prevention:** none needed. It was transient; retry once before investigating.
2. **A heredoc wrote into the scratchpad directory before it existed.** Recovery: used the Write tool. **Prevention:** create scratch paths with the Write tool, or `mkdir -p` in the same command.
3. **AC1's literal grep returned 2.** The writer's header comment repeated the selector literal. Recovery: reworded the comment. **Prevention:** after writing code that an AC greps for, run the AC's literal command before ticking it (`cq-assert-anchor-not-bare-token`).
4. **In my own mutation battery, M2 "survived".** The first-occurrence replace landed on the header comment. Recovery: anchored the mutation on the code line (`TARGET=$(git -C …`). **Prevention:** require the replaced string to appear exactly once *and* to sit on the construct under test, not merely once in the file.
5. **A Python batch edit hit a triple-quote collision and aborted before writing.** `bash -n` then passed on the unchanged file. Recovery: re-applied using `'''` delimiters. **Prevention:** after a scripted edit, check `git status --short <file>` or grep for the new anchor. A green syntax check says nothing about whether the edit landed.
6. **My first verdict-helper self-test was non-hermetic (`>=N` over ambient fixture state), and a neutered helper survived it.** Recovery: hermetic states with exact deltas. **Prevention:** this learning; not routed into `review/SKILL.md`, which sits 4 bytes under its lint-skill-body-budget ceiling. Its existing "one control per verdict-owning helper" bullet covers the principle.
7. **I wrote "every bump for another tag fails at `resolve`".** The deferral change in the same round had made that false: those bumps defer. Recovery: corrected the runbook and ADR. **Prevention:** after changing a branch's behaviour, grep the prose that describes that branch before committing.
8. **My ADR edit wrapped the AC7 literal across a line, which broke the AC's grep.** Recovery: unwrapped it. **Prevention:** re-run every doc AC after editing its target, not only after the first pass.
9. **Planning subagent (forwarded):** a hook blocked a scratch `rm -rf`, and `gh pr view --json merged` used an invalid field. Recovery: a new scratch directory, and `mergedAt`. **Prevention:** use unique scratch directories, and check `gh <cmd> --json` fields via `--help`.
10. **A background grep inside the git-history seat timed out.** Recovery: it used `git grep` instead. **Prevention:** none needed. It was internal to the agent.
11. **My shellcheck baseline covered only 2 of the 3 files, which made "21 vs 0" look like a regression.** Recovery: inspected the 21 hits, and all were pre-existing SC2034s. **Prevention:** compare baselines over the identical file set.
12. **My grep pattern made AC6 look silent.** Recovery: read the block with `sed`. **Prevention:** give every search a known positive before trusting its silence.
13. **A YAML equality check against `origin/main` reported DIFFERS because main had moved (#8873).** Recovery: compared against the merge-base. **Prevention:** compare a branch's own change against `git merge-base origin/main HEAD`, never against the moving tip.

## Tags
category: integration-issues
module: inngest-bootstrap-pin-bump
