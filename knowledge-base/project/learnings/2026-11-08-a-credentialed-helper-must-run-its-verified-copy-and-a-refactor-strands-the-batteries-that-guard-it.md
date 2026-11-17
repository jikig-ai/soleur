# Learning: run the verified copy, not the path you verified — and a refactor strands the guards around it

## Problem

`soleur:cve-exposure` (#12006) runs a Better Stack reader under the operator's injected Doppler credentials. Round 1 of review made the helper compare the checkout's reader against upstream main before running it. Round 2 found the check was still a time-of-check/time-of-use gap: the helper verified one file and then executed the path in the (attacker-controllable) checkout. Fixing that rewrote `verify_reader`, which in turn silently stranded four guards that had been written against the old shape:

- the mutation battery anchored on the old `verify_reader` text (every H1–H5 row became "anchor missing" and would have asserted-out instead of reporting);
- the suite's stub reader located its fixture directory relative to its own path, which is now a scratch copy;
- `guard-vacuity-floor.test.sh` could no longer construct a mutant for the suite's floor, because deleting a "duplicate" `SELFTEST_PASSES=1` separated it from the `REAL=` line the mutator keys on;
- a `LIMIT 5` pin was satisfied by `LIMIT 50` (substring match), so a mutant widening the image-scan read survived.

## Solution

- Download each reader file into the helper's private scratch directory, compare, then execute the scratch copy. Nothing on the checkout path runs after the comparison.
- Give the stub its fixture directory through an env var, assert the executed reader path is not under the checkout, make the curl shim reject any argv that lacks the hardened flag prefix and any poisoned `CURL_*` / `SSL_*` environment.
- Pin SQL fragments with their trailing token (`LIMIT 5 FORMAT`), and restore the floor block's adjacent `SELFTEST_PASSES=1` / `REAL=` shape.
- Make the mutation driver report `ANCHOR-MISSING` instead of asserting, so a refactor shows as a visible gap rather than a crash.

## Key Insight

A verification that returns a boolean and a run that re-resolves the path are two different operations; the property is "what ran is what was checked". And any change to a function that other guards anchor on is a change to those guards: re-drive the mutation battery and the repo-global ratchets after the refactor, not after the next review.

## Session Errors

1. **A shared-repo `git fetch --depth=1` experiment left the common repository shallow.** Recovery: removed `.git/shallow`, verified `--is-shallow-repository false`. **Prevention:** never run depth-limited fetches in a worktree of the shared clone; use a raw-file download or a throwaway clone.
2. **A chained command hid a failing vitest (`plugin-root-anchoring`) and the commit went through.** Recovery: fixed in the next commit. **Prevention:** read each suite's own exit code (`echo "RC=$?"` right after it); a trailing command is not the verdict (see `work` SKILL.md "wrapper that reports a gate is itself a guard").
3. **Hook blocks: `gh issue create` without a literal `--body-file`/label, `pgrep -f`, and a stray `git stash list`.** Recovery: re-issued compliant calls. **Prevention:** compose Bash calls from the allowed forms; never include `git stash` subcommands, even read-only.
4. **jq bugs: `select(.h | length > 0 and …)` precedence, `$` matching before a newline (Oniguruma), a negative "minutes ago" producing a future date, a comment apostrophe inside a single-quoted program.** Recovery: parenthesised, switched to `\A…\z`, added a skew helper. **Prevention:** anchor jq regexes with `\A`/`\z` and fixture the trailing-newline and future-timestamp inputs.
5. **Removing a "duplicate" `SELFTEST_PASSES=1` made `guard-vacuity-floor.test.sh` red (floor mutant not constructible).** Recovery: restored the adjacent shape. **Prevention:** after editing any floor block, run `scripts/guard-vacuity-floor.test.sh` (it is repo-global and no file-selected suite references it).
6. **The mutation driver asserted on missing anchors after a refactor, and a `LIMIT 5` pin was satisfied by `LIMIT 50`.** Recovery: lenient driver, pin with trailing token. **Prevention:** `cq-assert-anchor-not-bare-token`; after a refactor re-drive the battery against the current tree before reporting survivors.
7. **A test restored the emptied upstream fixture into the checkout copy.** Recovery: keep a pristine copy before truncating. **Prevention:** a test that mutates a fixture also saves the original it will restore from.
8. **Armed a second Monitor on the same file.** Recovery: `TaskStop`. **Prevention:** one watch per target; check the supersede hint before re-arming.

## Tags

category: integration-issues
module: plugins/soleur/skills/cve-exposure
