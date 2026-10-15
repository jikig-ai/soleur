# Learning: a diagnostic helper copied a field the repo forbids, and three of my own tests could not fail

## Problem

PR #10378 added `describeDbError(error, status, statusText)` so a failed Supabase read in the DSAR export
says what the HTTP layer said (a nightly run failed with `workspace_engine_settings read failed: Project
not specified` and the status, which postgrest-js keeps on the result object and not on `error`, had been
discarded at all 42 read sites). The first version passed its own tests and still had:

1. **A forbidden field.** It appended `hint`. The repo's rule (`sqlStateFromError` in
   `lib/postgres-errors.ts`; the comments in `server/observability.ts`) is that `details` AND `hint` can
   embed row values, and this text reaches logs on a regulated surface. I had excluded only `details`.
2. **Unpinned wiring.** The helper had a thorough unit suite and one site was driven end to end, so 41 of
   42 sites could be reverted to a bare `${error.message}` with every test green.
3. **A comment stripper that swallowed code.** The new source-assertion test stripped block comments
   before line comments, so a `/*` inside a `// ...<userId>/*` path-glob comment opened a "block comment"
   that ran for ~70 lines (imports included).
4. **Tests that could not fail on the defect they guard.** The input-bound timing test used 3 MB of `x`
   with a 100 ms ceiling: the unbounded cost of that payload is ~50 ms, under the ceiling. The
   "all whitespace reads as empty" test passes with no bound at all, since the whitespace collapses
   anyway. Two seats also could not reproduce the "~170 ms per MB" figure written into a comment.
5. **Substring checks.** `declText.includes("status")` is true of `statusText`, so dropping `status` from a
   destructure left the guard green (and `status` then resolves to a global).

## Solution

- Choose the emitted field set from the repo's own convention (grep the sanitizer/observability code for
  the field names), not from what the vendor type offers. Keep only `message`, the HTTP status, and a
  `code` that matches a closed shape (`^(?:[0-9A-Z]{5}|PGRST[0-9]{3})$`).
- Pin a helper-to-call-site wire with a SOURCE assertion over the function: comment-stripped by a
  scanner (string/template aware), anchored on the template literal that builds the message, with the
  exact site count found two ways (the message wording AND the helper call count), so rewording a site
  cannot drop it out of both. Prove it red by mutation: revert one site, swap two arguments, reword one.
- Assert the comment stripper itself: the whole file survives (first import and last function present)
  and a `/*` inside a `//` comment opens nothing.
- For a bound on work, pick a payload whose UNGUARDED cost you measured above the ceiling
  (`"a ".repeat(1_500_000)`: ~430 ms unbounded, ~0.1 ms bounded), and add a structural case that cannot
  pass without the bound (`" ".repeat(2000) + "tail"` must read as no message). Delete the guard and
  watch both go red.
- Match identifiers by token (`\bstatus\b(?!\s*:)`, `\bstatus:\s*<name>\b`), never by substring.

## Key Insight

A fix that is verified only by tests the same author wrote proves the tests agree with the fix, not that
they would catch its absence. For every guard, delete the guard and run the test; for every number in a
comment or a ceiling, re-run the measurement on the payload the test uses. And when a PR adds a field to
a log line on a regulated surface, the question is "which fields does this repo already forbid", answered
by grep, before the first draft.

## Session Errors

1. **PR text said "appeared once in 12 recorded runs"** (13 executed the suite) — Recovery: corrected to
   13 — Prevention: re-derive any count in PR prose from the run list before writing it.
2. **First helper emitted `hint`** — Recovery: dropped, code shape-validated — Prevention: grep
   `lib/postgres-errors.ts` and `server/observability.ts` for the forbidden-field comments before
   choosing emitted fields (this learning).
3. **First fixtures used status 200 with a non-JSON body** (postgrest-js sends non-2xx there) — Recovery:
   502 "Bad Gateway" — Prevention: read the client library's code path for the condition being modelled.
4. **`resolves.toBeDefined()` and substring `rejects.toThrow("...")`** (test-design) — Recovery: result
   list assertion and anchored regexes — Prevention: assert the value, not existence; anchor message regexes.
5. **Comment stripper swallowed ~70 lines; two vacuous bound tests; substring `status` check; unreproduced
   `~170 ms/MB` comment figure** — Recovery: scanner, discriminating payloads, token-boundary regexes,
   figure replaced by one re-measured — Prevention: mutation-check every new assertion and re-run every
   cited measurement (this learning).
6. **A `U+2028` escape in a test comment became the raw character through the Write tool** — Recovery:
   replaced, `grep -nP` clean — Prevention: already covered by
   `2026-05-28-unicode-separator-escapes-need-charcode-construction.md`; build separators with
   `String.fromCharCode` and grep for raw ones.
7. **Semgrep segfaulted (-11) without `ulimit -s unlimited`, leaving a void scan** — Recovery: re-ran with
   the limit lifted — Prevention: treat a signalled exit as "scan did not run"; already noted in
   recent learnings.

## Tags
category: test-failures
module: apps/web-platform/server/dsar-export
