# Learning: bare-substring fence markers over-slurp, and a missing `.test.` infix hides a RED fixture from CI

## Problem

While documenting the settle-then-admin-merge escape hatch at ship Phase 7 (#4790), the
`ship-phase-7-poll-fixtures.sh` fixture was discovered **already RED on `origin/main`** —
not introduced by this change. Two independent defects:

1. **Extractor over-slurp.** The fixture's `extract_block` awk anchored on the *bare
   substring* `/phase-7-poll-block:start/` and `/phase-7-poll-block:end/`. ship/SKILL.md
   carries a **prose** line (`# ... <!-- phase-7-poll-block:start/end --> markers ...`)
   that contains the literal token `phase-7-poll-block:start`. The `:start` rule (runs
   first, ends in `next`) matched that prose line, re-set `in_block=1`, and — with no
   `:end` after it — slurped to EOF (549 lines incl. prose that breaks `bash -n`).
2. **Orphan from CI.** The fixture filename lacked the `.test.` infix, so
   `scripts/test-all.sh`'s `plugins/soleur/test/*.test.sh` discovery glob never matched
   it. It appeared in ZERO workflow / `run_suite` entries — which is exactly why the RED
   went undetected indefinitely.

## Solution

1. Anchor the awk on the **full HTML-comment fence form** `/<!-- phase-7-poll-block:start -->/`
   and `/<!-- phase-7-poll-block:end -->/` (the prose `start/end` token is NOT a substring
   of `start -->`). Add `next` to the `:end` rule for start/end symmetry. This alone turned
   the fixture GREEN (13 pass / 0 fail) against the *unmodified* blocks — proving the harness
   fix is isolated from the content change.
2. `git mv` the fixture to `…-fixtures.test.sh` so the glob discovers it, and sweep the three
   SKILL.md path references + the fixture's own header comment.

## Key Insight

- **A fixture that extracts a fenced block by bare-substring marker will over-slurp the
  moment that marker token also appears in prose** (a "do not edit / see the markers"
  comment is the classic trigger). Anchor on the *full* fence syntax (`<!-- … -->`), never
  the inner token. Cheapest tripwire: assert the extracted block ends with its real
  terminator (here: `grep -c '\*\*If merged'` returns 0).
- **A test file without the project's discovery infix (`.test.`) is invisible to the
  glob-based runner — its RED is silent forever.** When a fixture's whole job is to guard a
  mirrored/critical block, verify it's actually discovered (`for f in <glob>; do …`), not
  just that it passes when run by hand.

## Session Errors

1. **`git commit` blocked by the unpushed-commits gate.** A Phase-1 checkpoint commit was
   left unpushed; the next `git commit` (content change) was denied with "1 local commit(s)
   not pushed … Run `git push` before queuing auto-merge." — Recovery: `git push` the
   checkpoint first, then re-commit. — **Prevention:** in a multi-commit pipeline, push each
   checkpoint commit immediately after creating it (the gate fires on the *next* mutating
   git op, not only at merge).
2. **Edit on a `git mv`-renamed file failed** with "File has not been read yet" even though
   the pre-rename path had been read. — Recovery: `Read` the new path, then `Edit`. —
   **Prevention:** after any `git mv`, treat the destination path as unread — `Read` it
   before the first `Edit`.

## Tags
category: test-failures
module: plugins/soleur/test, plugins/soleur/skills/ship
