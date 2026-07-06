---
date: 2026-07-05
category: test-failures
module: plugins/soleur/skills/incident
issue: 5987
tags: [golden-parity, test-baseline, merge-time-timebomb, git-show-main]
---

# Learning: a golden-parity test's "old engine" baseline must be a FROZEN fixture, never `git show main:<the-file-being-replaced>`

## Problem

PR #5987 replaced the pure-bash `redact-sentinel.sh` grep scanner with a Python
`redact-engine.py` behind a thin shim. To prove the ERE→`re` port didn't narrow any
class (AC3 golden parity) and that the old engine genuinely *missed* the new
confusable/invisible-split evasions (Test 5a), the test acquired the "old engine" via:

```bash
git -C "$REPO_ROOT" show main:plugins/soleur/skills/incident/scripts/redact-sentinel.sh > "$OLD_ENGINE"
```

This passed **43/43 on the branch** — because `main` still carried the pre-#5987
self-contained bash scanner. The trap: **the file being fetched from `main` is the same
file this PR replaces.** The moment the PR merges, `git show main:redact-sentinel.sh`
returns the *new shim*, which `exec`s `redact-engine.py` from `$OLD_ENGINE`'s directory
(a temp dir with no sibling engine) → python3 exits 2 → Test 5a expects 0 → **the suite
reddens on the next contributor's PR**, on an otherwise-clean tree. Test 9 degraded to
vacuous at the same time (old engine errors → empty hit-set → `comm` trivially passes).
The `|| cp "$SENTINEL"` fallback did not save it — post-merge `git show` *succeeds*, so
the fallback never fires, and the copied shim still lacks its engine sibling.

Caught by `code-quality-analyst` at multi-agent review (P1), not by the green branch run.

## Solution

Freeze the pre-change engine into a committed fixture and point the baseline at it:

```bash
git show main:plugins/soleur/skills/incident/scripts/redact-sentinel.sh \
  > plugins/soleur/skills/incident/test/fixtures/legacy-bash-scanner.sh
# test:
OLD_ENGINE="${SCRIPT_DIR}/fixtures/legacy-bash-scanner.sh"
```

The frozen copy is self-contained (pure bash, no python dependency) and **stable across
merges** — it is a golden reference, not a live view of a mutating file.

## Key Insight

A parity/regression test that references the *current* state of the artifact it is
replacing is a **merge-time time-bomb**: green on the branch, red on `main` for whoever
touches the file next. The same class as
[[2026-06-12-hook-test-passes-on-worktree-fails-on-main-cwd]] — a test whose outcome
depends on repo state that changes at merge. Any "compare new vs old implementation"
test must pin `old` to a frozen committed fixture. Also: byte-collation matters —
`comm` needs `LC_ALL=C sort` on both inputs or it silently treats locale-sorted input
as unsorted and its diff is undefined (the parity guard runs blind).

## Session Errors

- **Parity baseline pinned to `git show main:<replaced-file>`** — Recovery: froze the
  legacy scanner into `test/fixtures/legacy-bash-scanner.sh`. **Prevention:** when a PR
  replaces an engine/module and keeps the old one as a parity baseline, commit a frozen
  copy under `test/fixtures/`; never `git show main:` the file under replacement.
- **Golden-parity `comm` ran on locale-sorted input** ("not in sorted order", diff
  undefined) — Recovery: `LC_ALL=C sort` + `LC_ALL=C comm`. **Prevention:** always pin
  `LC_ALL=C` for `sort`+`comm` set-diff assertions.
- **`PATH=<stripped> bash "$X"` exited 127** (parent couldn't find `bash` under the
  stripped PATH) — Recovery: invoke `bash` by absolute path (`command -v bash`), only the
  child inherits the stripped PATH. **Prevention:** when testing a no-<tool>-on-PATH
  fail-closed path, strip PATH only for the child and call the interpreter absolutely.
- **Literal invisibles pasted into a test generator** (ZWSP/soft-hyphen/U+2028) — AC6
  caught it. Recovery: build via `chr(0x…)`. **Prevention:** `cq-regex-unicode-separators-escape-only`
  + the AC6 grep gate already enforce this; keep generating invisibles from ordinals.
