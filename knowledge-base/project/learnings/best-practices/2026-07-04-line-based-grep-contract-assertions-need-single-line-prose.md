# Learning: static-contract grep assertions over Markdown prose need the asserted phrase on ONE physical line

## Problem

`operator-digest-skill.test.sh` (an LLM-as-script skill's only mechanically-testable
surface) guards prose contracts with `grep -iqE` assertions, some of which assert a
multi-word **adjacency** (`only.{0,60}active`, `never.{0,40}quieter`,
`suppress.{0,80}(anchor|ambiguous)`). When the GREEN edit added the run-rate prose, the
clause "counting **only** rows whose `status` is `active`" soft-wrapped in the SKILL.md
Markdown so that `only` ended one physical line and `active` began the next. `grep` is
line-oriented (`.` never crosses a newline), so the assertion failed GREEN — 29/30 passed
with the one adjacency assertion red — even though the prose was semantically present and
correct.

## Solution

Keep any phrase an assertion matches by adjacency on a **single physical line** in the
source prose. When authoring the test alongside the prose, pair each `X.{0,N}Y` assertion
with a deliberate no-wrap of the `X … Y` clause. Recovery when it fails: re-flow the
sentence so the two tokens sit on one line (I moved "counting **only** rows whose status
is active" onto one line), not widen the `.{0,N}` window (which would mask a genuinely
missing phrase).

## Key Insight

A GREEN run where the ONLY failures are the multi-word adjacency assertions (`X.{0,N}Y`)
is a **line-wrap** signal, not a "prose missing" signal — because `grep` matches per
physical line while Markdown soft-wraps freely. Distinguish the two before touching the
regex: if `grep -c X` and `grep -c Y` each return ≥1 but `grep 'X.{0,N}Y'` returns 0, the
tokens exist but straddle a line break — fix the prose wrap, never the assertion window.
This is the prose-side companion to the general "grep is line-based" gotcha and applies to
every LLM-as-script contract test.

## Session Errors

- **Line-wrapped adjacency phrase broke a line-based grep assertion** — the `only.{0,60}active`
  assertion failed GREEN because "only" and "active" landed on separate physical lines in
  SKILL.md. Recovery: re-wrapped the clause onto one line. Prevention: when pairing an
  `X.{0,N}Y` adjacency assertion with new prose, keep `X … Y` on one physical line; a
  GREEN-fail on exactly the adjacency assertions means line-wrap, not missing prose.
- **Vacuous contract assertions shipped in RED** — two new assertions (`cadence`,
  `consequence`) matched pre-existing prose (the L3 guardrail / the Register), so they would
  have passed even with the feature reverted. Caught at review (pattern-recognition +
  code-simplicity converged). Recovery: re-anchored to phrases unique to the new prose
  (`shipping cadence`, `stated as a business consequence`). Prevention: when adding a
  presence assertion, diff the pattern against `origin/main`'s SKILL.md — if it already
  matches there, the assertion guards nothing new; anchor to a phrase the feature introduces.
- **Plan Edit staleness after `sed`** — a Read-then-Edit failed because an earlier `sed`
  checkbox update dirtied the plan file between Read and Edit. Recovery: re-read, re-edited.
  One-off (expected staleness). Prevention: re-Read a file after any `sed`/scripted mutation
  before an Edit.
- **Background-exit masking** — a long `test-all.sh` auto-backgrounded and its `EXIT=$rc`
  echo went to the bg output file, not the redirected log. Recovery: verified via the
  runner's own `137/137 suites passed` summary line, not the exit notification. Already
  covered by the existing AGENTS rule / learning on background-exit masking. One-off.

## Tags
category: best-practices
module: operator-digest, static-contract-tests
