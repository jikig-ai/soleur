---
date: 2026-05-10
issue: 3508
related_pr: 3495
related_issues: [3122, 3494]
category: best-practices
---

# Shared log-rotation primitive: design choices that bit on first draft

## Context

Three append-only JSONL telemetry sinks under `.claude/` accumulated without
bound — `.rule-incidents.jsonl` (#2213), `.skill-invocations.jsonl` (#3122),
`.session-tokens.jsonl` (#3494). Only the first had rotation, and it lived
inside the weekly aggregator (`scripts/rule-metrics-aggregate.sh`), so any
operator who never triggered the cron path accumulated forever.

Issue #3508 specified a shared rotator helper at `.claude/hooks/lib/log-
rotation.sh`. The plan got two design choices wrong on first draft and corrected
them during deepen-plan.

## Lesson 1 — atomic-rename is the WRONG primitive for `O_APPEND` writers

Initial draft: `mv $active → $archive.tmp` inside the rotator's flock, then
`: > $active` to recreate.

What this misses: `flock` advisories are **inode-bound**, not path-bound. All
the writers open by path on every invocation:

```bash
( flock -x 9; printf '%s\n' "$line" >&9 ) 9>>"$file"
```

The interleave that breaks rename:

```
T0: writer A:                  T1: rotator:                T2: writer B:

t1 open fd 9 >> $active
t2                              flock -w 5 -x 9 (acquired)
t3                              mv $active → $archive.tmp
t4                                                          open fd 9 >> $active
                                                            ← creates NEW inode at $active
t5                              : > $active
                                ← rotator's $active is the inode A still points to
                                ← (now under $archive.tmp, no path-side reference)
t6                              flock release
t7                                                          flock -w 5 -x 9 (acquired
                                                            on the new inode created
                                                            by writer B at t4)
t8 flock -w 5 -x 9 (acquired
   on the OLD inode, now
   reachable only via
   $archive.tmp)
```

`mv` is one syscall, but `mv + truncate-create` is two — and the writer can
wedge in between. Two writers, two inodes, two flocks. Torn writes.

**Fix:** copy-then-truncate-in-place. `cat $active >> $archive` then
`: > $active`. The inode never changes; flock semantics hold across the
rotation. This is the pattern at `scripts/rule-metrics-aggregate.sh:291-295`,
load-bearing for the same reason.

## Lesson 2 — exit-code-as-signal trips `set -e` in callers

The rotator runs in a flock subshell:

```bash
( ... flock body ... ) 9>>"$active"
```

Subshell variable assignments don't propagate, so the helper used **exit code
10** to signal "rotated, gzip the archive" to the outer scope:

```bash
if cat "$active" >> "$archive"; then
  : > "$active"
  exit 10   # signal "rotated"
fi
exit 0
```

First test run hung silently — `set -euo pipefail` at the top of the test file
killed the script the moment the subshell exited 10. The subshell call is in
**command position**, so `set -e` triggers on any non-zero. Even our deliberate
non-zero "success" code.

**Fix:** capture via `||`, which is conditional context (set -e exempt):

```bash
local rotated=0
( ... ) 9>>"$active" 2>/dev/null || rotated=$?
```

Lesson generalizes: any "successful but non-zero" exit code from a subshell or
command must be captured in a conditional context. `result=$?` after a bare
command call is set-e territory.

## Lesson 3 — empty file with stale mtime would produce empty .gz archives

Without a `[[ -s "$active" ]]` guard, a 0-byte file with mtime > 30 days
would trigger age-based rotation, producing a 0-byte `.gz`. Informationally
identical to absence, but pollutes the archive directory.

**Fix:** explicit non-empty gate before any threshold check. Cheap and
prevents observed-in-test pollution.

## Lesson 4 — `set -u` interacts with `local var=$?`

`local rotated=$?` always returns the local-builtin's exit code (0), not the
preceding command's exit code. The pattern `local rotated; rotated=$?` works
but is ugly. Cleanest: declare separately, capture via `||`:

```bash
local rotated=0
( ... ) || rotated=$?
```

## Pitfalls observed but NOT hit (worth flagging for future similar work)

- **macOS missing `flock`**: helper exits 0 without writing. Operator gets no
  rotation but no crash.
- **Symlinked `.claude/`**: writers and rotator must canonicalize via
  `cd -P + pwd -P` so they target the same inode. Sibling hooks already do
  this; the rotator doesn't need to (it gets the path from the caller).
- **Subshell variable reassignment**: `archive=...` inside the flock subshell
  is invisible to the outer `gzip` call. Compute the archive path BEFORE
  entering the subshell. Same pitfall as `rule-metrics-aggregate.sh:288`.

## References

- Plan: `knowledge-base/project/plans/2026-05-10-feat-shared-log-rotation-primitive-plan.md`
- Issue: #3508
- Rebased on top of: PR #3495 (merged during /work)
