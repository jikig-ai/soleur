---
title: The findings live in the hardening, not in the shape it catches
date: 2026-09-27
category: workflow-issues
module: shard-totality guard widening (#9035), mutation-battery drivers, review panel
tags: [census, mutation-testing, regex-derivation, review-economics, want-sig]
pr: 9059
---

# Learning: the findings live in the hardening, not in the shape it catches

## Problem

Issue #9035 asked for a narrow thing: widen the shard-totality guard so a
`rows :` spelling, an `export`-prefixed declaration, a garbage `--rows`
suffix, a lib subdirectory, or a battery under `apps/` cannot evade it. The
design was right on first pass — the nine-seat review panel produced ~62
findings and **every one of them landed in the new machinery, none in the
widenings' stated shape**. A hardening PR's residual risk is its own
hardening, and the concentration was total:

- **Derived-regex arithmetic is a defect surface.** The shared
  `_DECL_READ_RE` composes `_DECL_PREFIX_RE` into a sed substitution with a
  `\N` backref. Widening the prefix from one flag-arg group to an alternation
  added a capture group and silently moved the digit group `\4`→`\5` — every
  per-token read returned empty and the guard reddened itself. The
  intermediate file pattern (`sed` constant → `sed -nE` consumer) has no
  compile step; the only thing that caught it was running the guard.
- **`want_sig` is only binding if it is fail-only.** The signature I first
  picked for the two literal-census rows — `'literal census'` — appears
  verbatim in the arm's PASS line as well as its FAIL line, so `grep -qF`
  was satisfied either way and the binding the convention exists for was
  vacuous. Two independent seats flagged it. The fix was picking a substring
  that only the failure text carries (`'test-all.sh/scripts/lib but'`).
- **Shell rc semantics betray in the small places.** `rc=$?` inside
  `if ! git …; then` reports the *negated* status (0) forever; and
  `grep -c || echo 0` prints `0\n0` on no-match because `grep -c` emits `0`
  AND exits 1. Both shapes looked right at read time and were wrong at run
  time — a pre-existing `0\n0` wrong-arm routing on `origin/main` the diff
  touched anyway.
- **Enumeration plumbing must match its own contract.** Direction-1 got a
  NUL-safe `read -d ''`/`xargs -0` chain and Direction-2 initially got a
  newline-separated list with plain `xargs` — the exact silent-shrink class
  the arms exist to kill, reintroduced by writing the second site faster
  than the first.
- **Prose knocks-on miss the SECOND sweep's corpus.** Two count-carriers
  still read the 27-row/2-leg world (`mutations.sh` header "twenty-seven
  ways", the runbook topology table) — same defect class the sibling PR
  (#9027) had already turned into a learning earlier that day. The grep for
  the noun (`27`, `two`) found them only when aimed repo-wide, not
  diff-wide.

## Solution

All findings were fixed inline (7 P2s + ~25 P3s, no filings needed) because
each sat inside the flip-inline budget and inside the diff's own subsystem.
The durable rules of thumb the session produced:

- When a regex constant is *composed into* a `sed s/…/\N/` substitution,
  count the capture groups after every edit to either half — and let a
  battery row carry the check (the `DECL-PREFIX-READER` GREEN row now pins
  the backref end-to-end).
- A `want_sig` is a discriminant, not a label: pick a substring that appears
  in the target arm's FAIL text and provably nowhere else in the guard's
  output (the PASS line is the usual collision).
- Negated-condition rc capture needs a separate statement
  (`cmd; rc=$?`), never `if ! cmd; then rc=$?`.
- Write enumeration plumbing once and reuse the shape — or keep both loops
  on the same contract by construction (the census predicate, the `-f`
  regular-file gate, and the shebang regex are now one shared constant).
- The second knock-on sweep greps the *subject* (the count, the leg number),
  not the diff's file list — both stale carriers were outside the diff.

## Session Errors

- **`_DECL_READ_RE` backref shift (`\4`→`\5`)** — Recovery: the per-token
  "declares no DECLARED_TOTAL" arm reddened the guard on the clean tree,
  a symptom that read as its own diagnosis. Prevention: compose-and-count —
  derive the backref from the final assembled pattern, and keep a GREEN
  battery row that exercises the reader on a prefixed declaration
  (DECL-PREFIX-READER does exactly that now).
- **Stray `: > decl_census` truncation + no-op `if` left mid-edit** —
  Recovery: caught on self-review of the edited region before commit.
  Prevention: re-read the full hunk after multi-part edits, not just the
  lines each edit touched.
- **`rc=$?` inside `if ! git …`** — Recovery: flagged by the
  pattern/code-quality seats (diagnostics would have printed `rc=0`
  forever). Prevention: `cmd; _rc=$?; if (( _rc != 0 ))` — capture outside
  the conditional.
- **`grep -c || echo 0` double-zero (pre-existing wrong-arm)** — Recovery:
  replaced with an explicit `if [[ -f ]]` / `else _decl_lines=0`.
  Prevention: `grep -c` already prints `0` on no-match; `|| echo` fallbacks
  on *count* output forms duplicate rather than default.
- **Vacuous `want_sig 'literal census'`** — Recovery: re-bound to the
  fail-only substring `test-all.sh/scripts/lib but` on both DIR1 rows.
  Prevention: when writing a sig, grep the guard for the candidate string —
  it must appear only in the fail text; the scorer comment now says so.
- **`tasks.md` ticked as verified one verification leg early** — Recovery:
  the leg subsequently ran green; noted by the history seat as
  convention-tolerated ordering. Prevention: tick after, not during, the
  last verification command.
- **PR went `BEHIND` mid-flight when main moved** — Recovery: merged
  `origin/main` into the housekeeping branch; auto-merge re-armed itself.
  Prevention: none — expected gate behavior, recorded for completeness.

## Prevention

- For shared derived regexes (constant → consumer), treat the consumer's
  capture-group index as part of the constant's contract and pin it with a
  GREEN battery row — the machinery then guards its own arithmetic.
- Adopt the fail-only-substring rule for all future `want_sig` authorship
  (documented in `_score_row_rc`'s header).
- Run the knock-on sweep on the noun, not the diff — `grep -rn '27'`
  found the two stale count-carriers this diff never touched.

## Related

- `knowledge-base/project/learnings/2026-09-26-whitespace-rc-fields-and-guard-population-censuses.md`
  — the sibling mechanism learning this PR hardens further.
- `knowledge-base/project/learnings/2026-09-24-the-alarm-my-plan-relied-on-could-not-page-and-my-census-read-one-spelling.md`
  — the one-spelling census lesson the widening implements.
- `knowledge-base/project/learnings/2026-09-27-knock-on-enumeration-must-cover-prose-carriers.md`
  — the knock-on-enumeration rule this PR re-violated once (runbook + header
  counts) before the panel caught it.
- Issue #9035, PR #9059 (this change); PR #9027 / #8990 (predecessor machinery).
