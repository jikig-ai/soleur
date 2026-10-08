# Learning: a grep-count probe written pre-implementation must count what the fix's own prose adds

Date: 2026-10-07
Branch: feat-one-shot-6940-7632-cutover-followups — PR #9698 / issues #6940, #7632

## Problem

A plan's `discoverability_test.command` runs **post-implementation** (preflight
Check 10 executes `bash -c "$CMD"` and compares stdout to `expected_output`). This
one was written before the code existed:

```yaml
discoverability_test:
  command: grep -c 'triggers { type value }' apps/web-platform/infra/inngest-registry-probe.sh
  expected_output: "1"
```

`grep -c` counts matching **lines**, and the implementation added the pattern in
two places by design: the `FUNCTIONS_GQL_QUERY` line AND the header comment that
documents the new output contract (`{ functions { id slug triggers { type value } } }`).
The probe would have printed `2` at ship time and failed its own discoverability
check — a false-negative on the exact change it was meant to prove.

The same shape appeared twice more in the same session:

- A `grep -qF 'date -u -d "@$(('`-style assertion embedded a raw `"` inside the
  assert's double-quoted `cond` string. The inner quote closed the string early,
  the tail fell out unquoted, and bash reported a parse error 20 lines later at
  an innocent `(` — a quoting bug masquerading as a syntax error in a different
  statement.
- A "the block directly follows X" neighbour pin anchored on the block's `if`
  line, but two assignment statements (`MTR_GATE=…`, `MTR_BODY=…`) sat between
  the echo and the `if` — the previous non-blank line was `MTR_BODY=…`, not the
  echo the pin named.

## Solution

- Anchor discoverability probes on the **code symbol**, not the concept string:
  `grep -c 'FUNCTIONS_GQL_QUERY.*triggers { type value }'` counts the query line
  only — comments, tests, and doc prose that quote the pattern cannot satisfy it.
- In assertion-helper strings (`assert "desc" "cond"`), never let a `"` inside
  `cond` go unescaped — prefer `-F` fixed-string patterns that avoid inner quotes
  entirely, or `\$(`/`\$VAR` escapes. When a parse error names a later line, look
  UP for the first unbalanced quote — bash reports where the cascade breaks, not
  where it starts.
- A "directly follows" pin must name the *first statement* of the block it
  precedes, not the block's control line — or assert against the line
  immediately above (which may be a deliberate assignment pair).

## Key Insight

Probes that grep for a string the change introduces are self-referential: the
fix lands the searched text AND prose describing it. Any `grep -c`-shaped
verification written before the code exists must be re-counted against the
finished diff — comments and test fixtures that legitimately quote the pattern
are invisible when the count is authored.

## Tags

grep-count, discoverability-test, self-referential-assertion, quoting,
neighbour-pin, plan-probe, shell
