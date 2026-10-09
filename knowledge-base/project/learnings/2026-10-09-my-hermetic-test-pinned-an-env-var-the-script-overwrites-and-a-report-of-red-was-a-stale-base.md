# Learning: the "hostile CURL_BIN" I injected was overwritten before any row ran, and the "red on main" report was a stale base

## Problem

PR #9823 (follow-up to #9785) had two jobs: record the Gate 0 verdicts for #9790, and make `learning-retrieval-bench.sh --self-test` green. The brief said
the self-test was `51/1` on `origin/main` ("Stage 2 union-of-paraphrases lost target").

1. **The red was a stale base, not a current defect.** The `51/1` reproduces only on a copy of the script from before #9753 (the #8394 reader change against a
   mock curl that printed no block type). Current `main` was `177/0`. Fixing "the failure" would have meant inventing one.
2. **The real defects were caller-environment leaks**, found by probing rather than reading: `NO_PARAPHRASE=1` gave 173/4, an exported `ANTHROPIC_API_KEY`
   let the Stage 2 rows reach the real curl, an inherited `GIT_DIR` made the run exit 128, and a `TMPDIR` containing a quote, dollar sign or backtick broke
   six rows because generated curl stubs interpolated paths unquoted (that last one also reproduced on `origin/main`).
3. **My first CI wrapper asserted a vacuous thing.** It passed a recording stub as `CURL_BIN` and asserted "no call reached it". `self_test()` overwrites
   `CURL_BIN` with its own fail-closed stub, so nothing could ever reach the recorder: the check could not fail. Three review seats found it independently.
4. **The contract test for the new Sentry alert derived emit sites with a literal-only regex** (double quotes, `.ts` only, nearest preceding `feature:` within
   400 chars). A third emitter written with single quotes, a constant, `.tsx`, or reversed key order stayed green.

## Solution

- Measure the baseline on the actual tree before accepting a "red on main" brief; keep the stale-base finding in the PR body and file no tracker for a
  non-defect.
- Make `--self-test` reset every input it reads (`NO_PARAPHRASE`, `ANTHROPIC_API_KEY`, `CURL_BIN`, the `GIT_*` prefix by `compgen -e`), `%q`-quote every path
  written into a generated stub, and add an in-script row that fails if any row invoked the fail-closed default.
- The wrapper runs the real script once under `env -i` with every hostile value set at once, judges the exit code, the summary line, an independent
  assertion floor, and pins named rows (including the in-script leak row). The recorder is documented as a second layer with a positive control.
- The contract test finds the enclosing object literal of each `op`, accepts any quote style and `.ts/.tsx/.mts`, skips test files, requires the op token to
  appear only at literal sites, and requires every `noTextBlockExtra` caller file to hold an emit site.

## Key Insight

Before asserting "X cannot leak", find what overwrites X. A test environment variable only proves anything if the code path under test READS it after the
script's own setup; otherwise the assertion is true by construction. The fix is to pin the guard that sits where the leak would land (here the in-script row),
and to mutation-test each pin against a pristine copy: the `%q` in the fail-closed stub survived because only a real leak exercises it, which is the honest
limit of that guard and is stated rather than hidden.

A derived set is only as wide as its extractor: when a test claims "derived, not hard-coded", enumerate the syntactic shapes a new member can take (quote
style, constant, extension, key order) and add one mutant per shape.

## Session Errors

1. **Wrapper recorder claim was vacuous** (`self_test()` overwrites `CURL_BIN`). Recovery: reworded as a second layer, pinned the in-script row by name.
   **Prevention:** when a test injects an environment override, grep the script for the assignment that follows it and name the guard that sits after it.
2. **Hostile `GIT_DIR` made the self-test exit 128.** Recovery: scrub the `GIT_*` prefix for `--self-test`. **Prevention:** probe every env input the script
   reads, not a hand-listed set; strip by prefix.
3. **Unquoted paths in generated stubs broke under an adversarial `TMPDIR`** (also on `origin/main`). Recovery: `%q`. **Prevention:** any path interpolated into
   generated shell goes through `printf '%q'`.
4. **Brief reported a failure that does not exist on current main.** Recovery: reproduced on a pre-#9753 copy. **Prevention:** re-measure a reported red on the
   current tree before planning work around it.
5. **Wrapper `MIN_CASES` was set wrong twice** (10 vs 9 checks, then 13 vs 10), because the instrument self-test resets the counters. Recovery: count from a
   real run. **Prevention:** derive the floor from a passing run, not from counting `check` lines.
6. **Write failed on a stale read** after the file changed. Recovery: re-read, rewrite. **Prevention:** none beyond hr-always-read-a-file-before-editing-it.
7. **Hook denials**: `git stash list`, `pgrep -f`, foreground `sleep`. Recovery: used `git show`, Monitor. **Prevention:** already hook-enforced.
8. **Filing gate refused an issue sized for an inline fix** (decision challenges). Recovery: dissents live in the PR body. **Prevention:** already gated.
9. **Terraform 1.9.8 vs `use_lockfile`.** Recovery: scratch-copy plan. **Prevention:** none (local tool version).
10. **`git add apps/web-platform/test` from inside `apps/web-platform`** resolved to `apps/apps/...`. Recovery: re-ran from the worktree root. **Prevention:** run
    git from the worktree root; cwd persists between Bash calls after a `cd`.
11. **Contract extractor was literal-only** (found by review). Recovery: object-literal scan plus the token-count and caller invariants. **Prevention:** one
    mutant per syntactic shape when a test claims a derived set.

12. **A routed one-paragraph bullet pushed `plugins/soleur/skills/work/SKILL.md` 986 bytes over its lifecycle ceiling**, red on the required `rule-body-lint` check. Recovery: reverted the bullet; the insight lives here. **Prevention:** before routing a bullet into a lifecycle SKILL.md, run `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`; `work/SKILL.md` has almost no headroom.

## Tags
category: workflow-issues
module: scripts/learning-retrieval-bench, apps/web-platform/infra/sentry
