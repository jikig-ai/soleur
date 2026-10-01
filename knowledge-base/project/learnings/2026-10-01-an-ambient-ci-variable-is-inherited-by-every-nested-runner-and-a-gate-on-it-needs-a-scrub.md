# Learning: gating on an ambient CI variable — nested runners inherit it, and the guard suite needs its own instrument

## Problem

#9323 / ADR-262 path-gates five self-test mutation batteries on `pull_request` runs by keying
`_diff_touches --pr-gated` on `GITHUB_EVENT_NAME == pull_request`. The first CI run of the branch was red
for three causes, none visible from the targeted local runs:

1. **The variable is ambient, so it is inherited.** The coverage-notice, group-affected and runtime-ceiling suites
   re-execute `test-all.sh` under `CI=1` inside a sandbox. In a pull_request job those nested runners inherited
   `GITHUB_EVENT_NAME=pull_request` and took the new PR arm, so an arm asserted as "CI runs everything" saw `[skip]`.
   Locally the variable is unset, so every local run was green.
2. **A suite that relocates the runner must carry the runner's sourced libs.** The new guard suite copied
   `test-all.sh` into a sandbox without `scripts/lib/repo-write-boundary.sh`; `repo-write-boundary.test.sh`
   flagged the relocation.
3. **Two new test files used fixture-relative operands** (12 sites), tripping the `fixture-relative-assert` ratchet.

A fourth class surfaced in review: the guard suite itself was vacuous in ways a green run cannot show (a mutant
"caught" by a crash rather than a verdict, a floor counter that was a constant, a probe that read a red run as PASS).

## Solution

- Scrub `GITHUB_EVENT_NAME=` wherever a suite already scrubs `CI` for a nested runner (three suites).
- Copy every sourced lib explicitly in a sandbox builder; add `assert_fixture_dir` and absolute `$fx/$p` operands.
- Grade a mutant CAUGHT only on a verdict mismatch (a crash is "no verdict"), keep an append-only fail log, and run
  sabotage children that force the suite's own pass and fail paths, so the instrument is proven upstream of every
  assertion. Make the assertion floor a real counter incremented in `pass()`/`fail()`.
- A soak probe must count only `conclusion == success` runs and treat a pending push run as NOT YET (exit 2), never PASS.

## Key Insight

A gate keyed on an environment variable is a gate on every process that inherits it. When adding such a gate, grep
for each suite that already scrubs the sibling variable (`CI`) and extend the scrub in the same edit; "unset locally"
makes the omission invisible until the first real CI run. And a guard suite for a gate must be proven able to go red
for the right reason (verdict, not crash) before its green means anything.

## Session Errors

1. **`GITHUB_EVENT_NAME` leaked into nested sandbox runners** — Recovery: scrubbed in three suites. Prevention: when a change reads an ambient CI variable, grep every suite that scrubs `CI` and scrub the new variable alongside it; reproduce locally with `CI=1 GITHUB_EVENT_NAME=pull_request`.
2. **Guard suite relocated the runner without its sourced lib** — Recovery: explicit `cp` of `repo-write-boundary.sh`. Prevention: a sandbox builder lists every sourced lib; `repo-write-boundary.test.sh` is the existing detector, run it for any suite that copies `test-all.sh`.
3. **Fixture-relative operands in two new test files** — Recovery: `assert_fixture_dir` + absolute operands. Prevention: new suites start from the canonical fixture-dir helper; run the whole-repo ratchets (`fixture-relative-assert`, `guard-vacuity-floor`) before pushing, since a file-selected suite set cannot see them.
4. **Floor counter shape / xtrace guard width** — Recovery: real counter; guard widened to `GH_TOKEN`+`GITHUB_TOKEN`. Prevention: covered by `guard-vacuity-floor` and `lint-shell-trace-credential-refusal`; run them locally.
5. **Lint battery sandbox did not materialise `*_PATHS` arrays** — Recovery: materialise every array, re-declare the tag files. Prevention: a new array declared in the relevance lib is a sandbox-materialisation edit in the same commit.
6. **shard-totality census/anchors broke on an `if` re-indent and `--rows` text** — Recovery: awk filter + anchors updated. Prevention: grep the mutation-anchor file for the runner text you re-indent.
7. **`test-all-affected` sc6 asserted the old selection** — Recovery: assert the machinery edge. Prevention: a selection-semantics change owns the suite asserting the old selection.
8. **Merge conflict with `origin/main` at the end of the `want_scripts` block** — Recovery: kept both. Prevention: register new suites in a stable position or merge `origin/main` before the final push.
9. **Lefthook hooks began running after the merge** (`lint-skill-body-budget` 140 bytes over; `web-platform-typecheck` OOM locally) — Recovery: shortened the skill edit; `LEFTHOOK_EXCLUDE=web-platform-typecheck` for the merge commit only. Prevention: check `wc -c` against the skill body ceiling when editing a SKILL.md.
10. **A gitignored local `knowledge-base/INDEX.md` made `test-affected-kb-consumers` red** (environment artifact, 3 of 4 violations) — Recovery: moved aside to confirm; fixed the one real violation (`knowledge-base/x.md` literal in a probe test). Prevention: re-measure a "known failure" against a clean checkout before attributing it.
11. **`--full` gate refused rc=4 (sibling runs) and the first attempt was edited underneath** — Recovery: targeted suites in a CI-shaped env. Prevention: already covered by one-shot token-discipline rule 8.
12. **Ran `bash <file>.test.ts` in the background by mistake** — Recovery: killed, no effect. Prevention: none needed (one-off).
13. **Review subagents could not write report files (security seat returned text)** — Recovery: read the text result. Prevention: one-off harness behaviour; brief seats to return findings inline.

## Triage

| item | recurring? | disposition |
|---|---|---|
| 1, 2, 3, 4, 5 | recurring | covered by existing detectors; the new part is rule 1's scrub, recorded here |
| 6, 7, 8 | one-off | noted |
| 9, 10, 11 | recurring | already documented in skills/one-shot; no new rule |
| 12, 13 | one-off | noted |

## Tags
category: integration-issues
module: scripts/test-all.sh, ci
