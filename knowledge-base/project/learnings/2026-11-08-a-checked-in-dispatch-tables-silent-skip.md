---
title: A checked-in dispatch table's non-matching value silently skips a member on every leg
date: 2026-11-08
tags: [ci, fail-closed, dispatch-table, oracle-lane, review-finding]
issue: "#12393"
---

# A non-empty non-matching dispatch value reads as "not mine" — and skips on EVERY consumer

## What happened

PR #12410 matrix-ized `oracle-index-check` into K=5 legs. The run block looked up each
manifest member's assigned leg in a checked-in TSV and compared it to `ORACLE_LEG`:

```bash
assigned="$(awk ... '{print $2; exit}' "$legs")"
if [ -z "$assigned" ]; then ... exit 1; fi      # unassigned member: fail closed
if [ "$assigned" != "$ORACLE_LEG" ]; then
  continue                                     # "not my leg" — skip
fi
```

The empty check catches an *absent* row. It does not catch a *malformed* value: a legs-file
row `member<TAB>bogus`, `member<TAB>1/5 ` (trailing space), or `member<TAB>9/9` (well-formed
but foreign K) is non-empty, never equals any `ORACLE_LEG`, and the member silently runs on
**zero** legs while all five report green. A `ran==0` vacuous-leg check only saves the leg
that ends up empty — a member whose bogus assignment merely thins a leg is invisible.

Three of five review seats found this independently (security P2, architecture P3,
test-design P3). A sentinel arm (`LEG-BAD-VALUE`/`LEG-OUT-OF-MATRIX`) already existed to
catch it pre-merge — but the runtime arm it backstopped was one layer away and itself had
no mutant proving it fired.

## The rule

When a loop dispatches on a looked-up value, the skip predicate must distinguish
"valid value belonging elsewhere" from "value that fails the grammar". Validate the looked-up
value's shape (and, where the grammar is parameterized, its parameter — `n == K`) before the
`!=` compare, or fold the grammar into the compare's error arm. An emptiness check is not a
shape check.

Companion diagnostic class from the same diff: `_leg_k="${VAR%/*}"` under `set -u` aborts on
the unset case *before* the crafted `::error` — extract from `${VAR:-}` first, or the
diagnostic is dead code for the case it names. And a `[ -lt ]`/`[ -gt ]` numeric test fed by
a field whose emptiness was hidden by string concatenation (`"${k}${n}"`) no-ops silently —
check each field separately.

## Detection that worked

A test asserting only `rc != 0` cannot discriminate "dedicated `::error` arm" from
"downstream backstop red". Deleting the whole validator block still left every arm `rc != 0`.
The fix was a **reason pin** per arm (`check_contains ... "unset or malformed"`) plus a
sweep over the malformed-input matrix (`""`, `15`, `1/5/2`, `0/5`, `5/0`, `/5`, `5/`, `x/y`,
`1/5 `). The repo's own mutate()-doctrine ("MUTATION DID NOT LAND") applies equally to
fixture arms: a land-check (`grep -qF` on the mutated copy) keeps a must-PASS row from
passing vacuously when its awk transform stops matching.

## Related

- `scripts/ci-oracle-lane.test.sh` `check_legs()` + sandbox arms (the implementation).
- `decision-challenges.md` T1–T4 (the CTO rulings the seats received as settled decisions).
- knowledge-base/project/specs/feat-one-shot-12393-oracle-lane-bound/session-state.md
  §Review Disposition.
