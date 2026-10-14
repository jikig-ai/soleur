# Decision challenges — feat-one-shot-8102-check10-yaml-quote-escapes

These are decisions taken during planning that depart from what the request asked for, recorded
per ADR-084 so they can be audited outside this session. `ship` renders this file into the PR
body.

---

## DC-1 — The quote decode moves into the parser, not into the SKILL.md bash block

**Date:** 2026-09-25
**Classification:** User-Challenge. The request named the edit site; the plan moves it.
**Plan:** `knowledge-base/project/plans/2026-09-25-fix-check10-yaml-quoted-command-escapes-plan.md`
(§Research Reconciliation, §Proposed Solution)

### What was asked

Decode `\"` / `\\` (double-quoted) and `''` (single-quoted) in the runtime, *"SKILL.md Step 10.4
bash block"*, and in the TypeScript mirror's `stripQuotes`.

### What the plan does instead

- **Runtime.** The decode goes into `parse-form-a.awk`'s inline `command:` rule. The #8149 quote
  strip in the SKILL.md normalize block is **deleted**, not extended. SKILL.md Step 10.4 still
  changes, through prose and that deletion.
- **Mirror.** A new `decodeQuotedScalar()` is added, used only by `parseCommand`'s inline path.
  `stripQuotes` keeps its behaviour.

### Why

1. The normalize block sees the command **after** parsing. At that point it cannot tell a
   YAML-quoted inline scalar (which has escapes) from a single-line block or fold scalar, or from
   a Form B fence, and both of those are literal text. The parser is the one layer that knows.
2. Decoding in both places double-decodes: `command: "'x'"` would run `x` instead of `'x'`.
3. The byte-exact parity harness (P1) executes the awk, so a decode there is covered by the
   existing harness plus new rows. A decode in SKILL.md is visible to P1 only as a "known
   divergence", which is how the original bug shipped green.
4. `stripQuotes` also serves `expected_output` and `credentials_required`, and the runtime for
   neither decodes anything. Changing it would open a new mirror/runtime split on those two
   fields.

Measured cost: 0 of 921 corpus commands reach the deleted SKILL.md strip from anything other than
an inline scalar. The one guard that covers those cases is the Q, O and E fixture rows
`NEG-BLOCK` and `NEG-FOLD`.

### Default if nobody objects

Proceed as planned. To reverse it, move the decode back into the normalize block, and accept
three costs. P1 cannot see a decode there. Block and fold scalars would be decoded as well. And
the mirror/runtime gap on block, fold and Form B paths reopens: the TS mirror never stripped
those, while the SKILL.md strip did (architecture review, deepen).

The deepen pass also found that the old last-character rule mis-handled `"cmd" #"tail"`. The
parser-side scan now decodes exactly YAML's value, which a normalize-block strip cannot do,
because by then it can no longer tell the command from a trailing YAML comment.
