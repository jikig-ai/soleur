# Learning: a command-text scanner needs a tokeniser, and every rewrite needs a corpus diff against its predecessor

## Problem

Stage S8 of `tests/scripts/test-argv-bearer-sweep.sh` (PR #10525, umbrella #9757) guards "no registry login carries a
password on argv". The first version was a regex plus heuristics (host-token counting, a redirection lookbehind, a
neutral flag-variable clause). It passed 15 rows and a 12-seat panel then found a long tail of evasions: a second
invocation on the same line, a `$(...)` password, a host-less login, GitHub Actions `${{ }}` expressions, `&>`, valued
options, `bash -lc` payloads. Rewriting it as a tokeniser closed those, and the first round of fixes then **regressed
recall against the regex version** (logins inside quoted payloads, backtick spans) and added false positives (backtick
inline code in markdown, `<file` read as a doc placeholder, a spaced `<two words>` placeholder turning into a redirection
that swallowed a real `-p`).

## Solution

- Tokenise (quote-, `$(..)`-, backtick-, `${{..}}`-aware) instead of regex-matching the line. Operators end an
  invocation; redirections are skipped with their target; a quoted string is prose unless the context says a shell runs it
  (`-c` cluster after a shell word, `eval`, YAML `run:`, `ssh`, exec-style calls).
- Judge "bad" on any password option regardless of host count; count a "site" only for the one-host shape.
- Keep a corpus of adversarial lines (the review seats' cases) and run old and new scanners over it; every line the old
  one caught and the new one misses is a regression until named as a blind spot.
- Put each construct BEFORE the password option in evasion rows, so a mis-tokenised tail loses it; assert record counts
  (not just "bad") for same-line rows.

## Key Insight

A scanner over command text is a parser problem; heuristics on top of a regex fail silently in both directions. And a
rewrite is a new instrument: diff it against its predecessor on a shared corpus before trusting its green, because the
rows written for the new version are shaped by what the new version already does.

## Session Errors

1. **Plan-quoted floor counts were stale** (11 sites/6 files vs 12/7; sweep floor 823 vs 825 measured). Recovery:
   re-measured at work time. **Prevention:** already covered by the work skill's plan-quoted-number rule.
2. **Scanner fix regressed recall vs the old scanner and added false positives.** Recovery: corpus run + a verification
   seat. **Prevention:** this learning (corpus diff against the predecessor for every scanner rewrite).
3. **xtrace test row failed under an ambient `DOPPLER_TOKEN`:** the xtrace lint forced the name into the refusal guard
   because the file referenced it (in `unset`), while the test's `env -u` list was shorter. **Prevention:** when a row
   exercises a refusal keyed on credential names, derive the `env -u` list from the guard's own list.
4. **A suite moved to background by the Bash timeout hung ~50 min** (inherited stdin). Recovery: killed, relaunched
   detached with `</dev/null` and an rc file. **Prevention:** already in the work skill; launch long suites detached.
5. **Hook/tool friction:** a safety check refused `rm -rf "$d/…"` inside a heredoc (rewritten as `${d:?}`), a hook refused
   `ps | awk` self-matching, an f-string brace error in a generated edit, a header replace that did not match (the
   assert aborted before any write). One-off.
6. **`/tmp` was swept on a session restart** and a gate log was lost. Recovery: `/var/tmp`. **Prevention:** already covered.

## Tags
category: best-practices
module: tests/scripts/test-argv-bearer-sweep.sh
