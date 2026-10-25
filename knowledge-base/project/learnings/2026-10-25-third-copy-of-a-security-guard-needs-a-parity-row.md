---
title: A third copy of a security guard is comment-identical until a parity row binds it
date: 2026-10-25
category: engineering
tags: [code-review, credential-hygiene, xtrace-refusal, test-design, inngest]
issue: '#10363'
pr: '#11097'
type: learning
---

# A third copy of a security guard is comment-identical until a parity row binds it

## Problem

Porting the #10637 xtrace-refusal / resolve-after-refusal mechanism to a third
probe (`inngest-consumer-probe.sh`) produced a byte-identical `_key_ok` copy whose
safety comment cited the sibling suites' hostile-key and locale rows. Four
independent review seats (pattern-recognition, architecture, code-quality,
test-design) converged on the same P2: the byte-identity claim was
comment-asserted and test-unenforced — the one existing parity row bound only
nic-guard↔zot — and the new suite's hostile-key rows were all lowercase-led, so
the `${!name}` body clause (`*[!A-Z0-9_]*`, the clause that stops array-subscript
and command-substitution injection through an env-file-supplied variable name)
had no discriminating row. Deleting the clause left every suite green while
turning `KEY=A[$(cmd)]` into executed code.

## Fix

- Body-clause key table in the F6 block (`A[$(touch plant)]`, `A[0]`, `A=B`,
  `A.B`, `A/B`) — upper-case-led so the rows die in the body clause, not the lead.
- A three-way `_key_ok` byte-parity assert (this copy vs both siblings) — pins
  `local LC_ALL=C` and every future drift.
- Ported the remaining security-axis template rows that a "lean port" had
  dropped: not-exported envdump + `export URL` mutant (the `unset URL` rationale),
  every-`Exec*` dollar-free sweep, unset-named-var input cell, and a
  guard-removed `sh -x` leak control on the rendered heartbeat bodies.

## Lessons

1. **When a port's justification is "byte-identical to sibling X", the identity
   needs a test row, not a comment.** The repo's own doctrine names this: pinning
   two of three copies while the third's comment claims all three is worse than
   no pin (inngest-cutover-flip.test.sh, the third-GQL-query precedent).
2. **A "lean port" of a test template must not drop rows on the injection axis.**
   Every dropped F6 row (body-clause table, envdump, ALLEXEC) was on the hostile
   key/env axis — the half of the guard that is a security boundary rather than
   a config guard. The canary/ZTOK rows were correctly dropped (inapplicable);
   the hostile rows were not optional.
3. **Review-seat convergence is a reliable signal for real defects.** Four
   seats with different lenses independently named the same uncovered clause;
   one (test-design) confirmed it as a surviving mutant before the report.
4. **Adjacent same-class residuals belong in a filed issue, not a PR
   expansion.** security-sentinel found two pre-existing `bash -c` ExecStarts
   (inngest-redis `--requirepass`, rendered inngest-server signing-key export)
   that the bound test's `[{][!]` spelling can't see — filed as #11103 rather
   than widening the PR's contract.
5. **Trace-armed launch coverage that matters:** `SHELLOPTS=xtrace`,
   `BASH_ENV=...set -x`, `bash -x`, `sh -x` (bash AND dash — the rendered body
   runs under dash). A hostile `PS4` still expands per-trace-line before any
   script can run, but requires env-write (≈ credential access) — documented
   residual, not fixable below the interpreter.
