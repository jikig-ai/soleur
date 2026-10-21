---
title: "A guidance doc teaching anti-vacuity shipped a tautological example, a second-order vacuity, and a self-oracular oracle"
date: 2026-10-21
category: best-practices
module: plugins/soleur/skills/work
tags: [property-based-testing, anti-vacuity, oracle-design, review-findings, guidance-docs]
issue: 10400
pr: 10718
---

# Learning: shipped examples are graded like code — check them against trivial implementations and self-oracles

## Problem

PR #10718 (issue #10400) added `plugins/soleur/skills/work/references/property-testing.md`, a
reference teaching when and how to write property-based tests — including an anti-vacuity
obligation section. Its own Hypothesis example shipped vacuous:

```python
@given(st.lists(st.integers()))
def test_sort_is_permutation(xs):
    assert sorted(xs) == list(xs) or sorted(xs) != list(xs) or sorted(sorted(xs)) == sorted(xs)
```

That is `P ∨ ¬P ∨ Q` — a tautology that cannot fail for ANY implementation of `sorted`.
Three review seats (security-sentinel, pattern-recognition, agent-native) converged on it as
the panel's one real P1.

The fix commit (eaab20329e) replaced it with `Counter(sorted(xs)) == Counter(xs)` (permutation)
plus `sorted(sorted(xs)) == sorted(xs)` (idempotence). The fix-round's security seat then found
the **second-order** vacuity: the identity function satisfies BOTH properties, so the pair
still admits a trivially wrong `sorted` — the example needed `all(a <= b …)` ordering too
(c51e00febd). Vacuity is not discharged by removing the tautology; it is discharged only when
no trivial implementation survives.

Two adjacent defects shipped in the same file:

- **A self-oracular canonical oracle (P2).** The round-trip bullet told readers to compare
  `decode(encode(x))` against `decode(encode(canonicalize(x)))` — the RHS runs the same codec
  under test, so a constantly-wrong codec shifts both sides identically and passes. The fix:
  compare `decode(encode(x))` against `canonicalize(x)` — never `x` itself (lossy serializer),
  never the round-trip expression.
- **Unverified tool-map rows.** jqwik/QuickCheck/FsCheck rows cited APIs nobody had checked;
  they now carry `(unverified)` markers. Rows verified 2026-10-20 name the check date.

## Solution

All fixes landed inline during the panel + fix-round (commits eaab20329e, 5de5299cfa,
c51e00febd, 26c72453c9): the sort example asserts permutation + idempotence + ordering, the
round-trip guidance compares against `canonicalize(x)` directly, unverified tool rows are
labelled, and the scope of the round-trip shape was narrowed to truly invertible transforms.

## Key Insight

An example in a guidance document is not prose — review grades it as executable code that
teaches. An example that demonstrates the defect the document warns against (a tautological
"property", an oracle derived from the system under test) is worse than no example: it is
read as endorsement. For every shipped test/example, run three checks:

1. **Tautology** — can the assertion fail at all? (`P ∨ ¬P` never can.)
2. **Trivial implementation** — does a no-op / identity / constant implementation pass every
   assert? If yes, the assert set under-constrains the SUT.
3. **Self-oracle** — is the expected value computed by the same machinery under test? Then a
   systematic error shifts both sides and the suite stays green.

## Session Errors

**crates.io API returned 403 without a User-Agent header**

- **Recovery:** retried the crates.io version probe with a UA header; proptest 1.12.0 verified.
- **Prevention:** crates.io requires a `User-Agent` on API calls — send one on first request.

**deepen-plan §4.7 pure-docs exemption does not cover `plugins/*/skills/*.md`**

- **Recovery:** plan carried the full `## Observability` block; gate passed.
- **Prevention:** none needed — the boundary is deliberate (skill definitions are executable
  instructions, not docs). Recognise a `plugins/soleur/skills/**` docs-shaped change as
  gate-bearing at plan time, not as an exemption miss.

## Related

- `knowledge-base/project/learnings/best-practices/2026-10-20-fastcheck-v4-substitutions-and-json-canonical-oracle.md`
  — sibling learning on canonical JSON oracles (same oracle class, app-suite side).
- `plugins/soleur/skills/review/references/generated-input-oracle-surfaces.md` — the review
  checklist surface these findings land beside.
