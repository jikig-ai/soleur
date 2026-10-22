# `mktemp` "equivalences" can defang the observable, and gawk's RSTART dies under `gsub`

Date: 2026-10-20 · PR #10658 / issue #7376 · `Reviewed-Coverage: sequential-fallback`

## What happened

Review of the #7376 tmpdir-namespacing guard found four traps in one small diff,
each a documented class recurring inside the fix for that class:

1. **`mktemp -u` → `mktemp` is NOT semantics-preserving when the file's absence
   is the observable.** `verify-tunnel-ingress-origin-infradir.test.sh` used
   `MARKER="$(mktemp -u)"`; the stub's `touch "$MARKER"` created it, and
   `[[ ! -e "$MARKER" ]]` was the "stub never ran" arm. Switching to `mktemp`
   pre-created the file, making the `-e` arm dead — a check that cannot fail.
   The plan's own justification ("touch on an existing file is identical
   observable behaviour") was false: `touch` creates-or-updates; `-e` observes
   creation. Fix: `MARKER="$STUB_DIR/marker"` — unpredictable name, unclaimed
   path, existence restored as the stub-hit observable.

2. **In gawk, `sub`/`gsub` CLOBBER `RSTART`/`RLENGTH`, so a `/re/ { }` rule that
   runs after a `gsub`-using rule reads stale match coordinates.** An
   unconditional `{ lt = $0; gsub(...) }` rule placed before a
   `/<<-?.../ { substr($0, RSTART-1,1) ... }` rule silently zeroed the
   coordinates — the tag extracted empty, every `<<'TAG'` opened a swallow
   window terminating only on a BLANK line, and ~6 lines of one real suite were
   already invisible to the sweep. Fix: call `match($0, /re/)` inside the
   action (which sets the coordinates) instead of relying on the pattern's
   match, or keep all `sub`/`gsub` calls after the reads that need them.

3. **A heredoc prefilter that accepts UNQUOTED `<<TAG` swallows real code.**
   Unquoted heredoc bodies undergo `$(...)` expansion in the parent shell —
   `$(mktemp -u)` inside `cat <<EOF` executes. Only quoted tags (`<<'T'` /
   `<<"T"`) carry literal bodies. And tags can contain `-`/`.`: a class of
   `[A-Za-z0-9_.-]*`, plus comment lines must never open a window (a `#`-comment
   naming `<<'TAG'` is prose, not an opener).

4. **A skip-the-next-argument table must still READ the skipped arg.**
   `mktemp -p /tmp` (TMPDIR-ignoring absolute scratch path) evaded a sweep that
   blind-skipped `-p`'s argument. Check the consumed arg for the banned shape;
   only then skip.

Companion traps, same session: an env-readable program-path variable
(`TMPNS_AWK_PROG=/dev/null` made the whole sweep green over zero scanned lines —
the env-readable-flag vacuity class); `${var/"$span"/}` is a PATTERN
substitution, so a quoted span containing `*`/`?`/`[` erases through a later
`$(mktemp -u)` (use the `%%"$span"*` + `#*"$span"` literal-removal idiom); a
trailing-comment `code # mktemp -u` line false-flags unless `#` is cut at a
word boundary AFTER quote-stripping but AFTER the exemption-marker check; and
`[[ -f ]] || continue` silently drops unreadable corpus members (emit a MISSING
row and assert its count is zero).

## Rule

When a fix replaces an "unsafe" primitive with a "safe" one, name the observable
the original construction produced and assert the replacement produces it too —
creation-vs-existence, expanded-vs-literal, skipped-vs-unread are the three axes
that bite. And in awk, treat `RSTART`/`RLENGTH` as owned by the LAST `sub`/`gsub`
or `match()` call: read them only immediately after the call that set them.
