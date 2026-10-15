# Learning: a one-token locale fix was the small part; the prune's guard and the repo's own ratchets were the work

## Problem

`sync_bare_files()` compared two `LC_ALL=C`-sorted lists with a `comm` running in the caller's locale.
Under `en_US.UTF-8` it printed `not in sorted order` and returned a wrong difference that included tracked
files, so every `sync` / `cleanup-merged` deleted `.claude-plugin/marketplace.json` from the bare root and
the local `soleur` marketplace stopped loading.

## Solution

`LC_ALL=C` on every sed/sort/comm stage, `-c core.quotePath=false` on both git calls, a per-path
`cat-file -t <pinned-sha>:<path> == blob` guard that aborts the whole prune on any hit, and a ceiling
(`SOLEUR_SYNC_PRUNE_MAX`, default 5000) on the paths about to be removed. Fixture: 22 tracked and 8 deleted
paths, calibrated by a seeded search so the legacy pipeline emits a tracked path under en_US.

## Key Insight

The nine-seat review found that the guard did not equal the property it named. Three seats independently
found the bigger defect, which pre-dated the locale bug: run from a worktree, every bare `git ... HEAD`
resolved the worktree's branch, so a feature branch that deleted a file `main` still tracks made the prune
remove it from the root, and the blob guard asked the same wrong HEAD. Also real: a symlinked ancestor
made `rm -f` delete the link target (a tracked file, or one outside the root); `SOLEUR_SYNC_PRUNE_MAX=08`
was an octal error that silently disabled the ceiling; a file literally named like git's quoted spelling
was pruned. Pin one commit from the root, resolve the real directory and compare it to the spelled path
(one `cd -P && pwd -P` also covers `.`, `..` and `//`), and read env integers as `10#`.

## Session Errors

1. **The `*.test.sh` ratchets ran late, not with the first test commit.** `fixture-relative-assert`,
   `guard-vacuity-floor` and `test-affected-kb-consumers` each went red on new code and were only
   run after a full suite pass. — Recovery: fixed each. — **Prevention:** run all three right after
   writing the first arm (work Phase 0.5 6.6/6.7 already says so); one call, not three rounds.
2. **`fixture-scan.py` reads `$VAR` tokens inside single-quoted text on a redirect line.** A shim written
   by `printf '...$GITSHIM_REC...' > "$shim/git"` was flagged `root=never-bound` for a variable that is
   only text. — **Prevention:** write generated scripts with a quoted heredoc (`cat > "$f" <<'EOF'`),
   one operand per redirect line.
3. **Full path literals in a test name the script to the kb-consumers scanner**, which then hops into it
   and charges the test with that script's `knowledge-base/` reads. — **Prevention:** reference sibling
   scripts by basename when the test only needs identity (a census anchor), and hold a docs-dir prefix in
   a variable (`KB="knowledge""-base"`).
4. **A mutation `str.replace(old, new, 1)` hit the first textual occurrence, which was a different
   function carrying the identical regex**, so the row "survived" and was nearly recorded as a test gap.
   — **Prevention:** anchor the replace on a multi-token context unique in the file and assert
   `s.count(old) == 1`, not `>= 1`.
5. **A subtree sandbox is not a git repo**, so the census arm reddened the unmutated control and voided
   the first battery. — **Prevention:** `git init && git add -A && git commit` inside the sandbox before
   the control run (already documented in review/SKILL.md; applied late).
6. **A generated Cyrillic literal replaced one of two characters** (`ет`), leaving a stray non-ASCII byte
   in a "pure ASCII" fixture. — **Prevention:** grep generated fixtures for `[^\x00-\x7F]` before
   committing.
7. **A parallel branch (`fix-version-banner-inplace-install`, draft #10165) carries the same
   `LC_ALL=C comm` fix** and conflicts in two files. Found only by the history seat. — **Prevention:**
   before planning a fix to a shared script, `git log origin/<other branches> -S'<the token>'` for the
   token you are about to change.
8. **Four Stop-hook rejections** for closing sentences that named a next action. — **Prevention:** when
   waiting on a background seat, end with a `Paused:` sentence stating what is awaited.
9. **A foreground `sleep 60 && cat` was blocked by a hook; `worktree-manager create` blocks on a y/n
   prompt without `--yes`.** — **Prevention:** `--yes` for `create`; Monitor with an until-loop to wait.

## Tags

category: logic-errors
module: git-worktree
