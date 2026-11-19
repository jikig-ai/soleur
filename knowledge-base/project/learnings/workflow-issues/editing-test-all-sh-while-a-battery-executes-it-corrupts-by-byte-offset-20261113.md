---
title: "Editing scripts/test-all.sh while a local battery executes it crashes the run with garbage tokens at an unrelated line — twice in one session"
date: 2026-11-13
category: engineering
tags: [test-all, local-battery, byte-offset, mid-run-edit, corrupted-script]
symptoms: ["`scripts/test-all.sh: line N: <truncated-token>: command not found` (e.g. `ython3`), or `syntax error near unexpected token` at a line that reads perfectly well in the file; both preceded by a commit touching test-all.sh while the battery was in flight"]
module: CI
component: local-test-runner
problem_type: self_inflicted_crash
resolution_type: sequencing_rule
root_cause: bash reads a running script by BYTE OFFSET, not line number — an edit that changes byte lengths before the interpreter's read position shifts every subsequent read, landing it mid-token
severity: low
issue: '#11556'
pr: '#12698'
---

# The crash that looks like a repo bug and is an editing artifact

**Twice in one work session** a local `test-all.sh` battery crashed at the same
spot (~line 7244 / ~line 7331), each time right after a commit that touched
`test-all.sh` while the run was in flight:

- `scripts/test-all.sh: line 7244: ython3: command not found` — a `p` clipped
  off `python3` when the interpreter's stored byte offset landed mid-token.
- `scripts/test-all.sh: line 7331: syntax error near unexpected token '('` —
  same mechanism after a +~270-byte comment insertion earlier in the file.

The file is fine in both cases (`bash -n` clean, `git diff` correct). The crash
is positional: bash executes a seekable script lazily and tracks where it is by
**byte offset into the file as it was first opened**. Any edit that changes the
length of content *ahead of* that offset (insertions or deletions anywhere
earlier in the file) makes the interpreter's next read resume at stale bytes —
duplicating or skipping ~the edit delta, and landing mid-identifier or
mid-string. The failure surface moves with WHERE you edited, not with what the
edit did.

## How to recognize it instantly

The crash line's content never matches the reported token — `line 7244` in the
file was `fi`, not `ython3`; `line 7331`'s `(` token was inside a comment in the
real file. When a suite runner crashes on a token that isn't at the reported
line, check `git log -1 --format=%ct scripts/test-all.sh` against the battery's
start time before investigating the code.

## The rule

**A runner file is frozen while its battery runs.** Sequence every edit to
`scripts/test-all.sh` (and any file a long-running interpreter reads lazily —
the derive libs it sources at exec time are exempt only because they are read
fully up front) either BEFORE launch or AFTER the run ends. This includes the
tempting "tiny comment fix" — the corruption cost here was two ~50-minute full
batteries, more than either battery's remaining runtime.

Corollary for the detached-battery recipe
(`skills/ship/references/battery-refusal-wait.md`): the recipe is a ship-phase
step for a reason — arm it only when the diff is final. A mid-flight review
round that touches the runner turns the battery into evidence about your edit
timing, not your diff.

## What survives the crash

Per-suite verdicts already recorded stay valid (each suite is a fresh process);
a retained suite-log directory (`/var/tmp/soleur-test-all-logs/<worktree>-*`)
keeps what ran. The crash only voids the run's *coverage* claim and the
end-of-run repo-write boundary re-read — which prints exactly that disclaimer.
