---
module: scripts/lib
date: 2026-10-20
problem_type: test_failure
component: testing_framework
symptoms:
  - "residue oracle extracted only `s|` sed rules (31/39); the 8 `s/` rules were invisible to the property they belonged to"
  - "`if grep -qE \"$p\"` reads rc>=2 (invalid pattern) as residue-free — an uncompilable extracted LHS would join the oracle as a permanent no-op"
  - "on bash 3.2 a `x=$(prop_pick ...)` command substitution reads the SAME $RANDOM stream position the parent had at fork — every loop iteration returns the identical value"
root_cause: logic_error
resolution_type: test_fix
severity: medium
tags: [property-based-testing, oracle, generated-input, bash-3-2, random-seed, fail-open]
synced_to: [review]
---

# Learning: a generated-input oracle's coverage is bounded by its extraction window — delimiter classes, pattern validity, and the bash-3.2 $RANDOM subshell all fail toward a smaller effective domain

## Problem

Two independent mechanisms in PR #10624's shell property arm (`scripts/lib/property-harness.sh` + reference suite `legal-normalise-property.test.sh`) had the same failure shape: **the instrument silently covered less than its name claimed**, and every failure direction read as green.

### 1. Residue-oracle extraction window (review P2, two seats)

The suite's residue property asserts `collapse()`'s output contains none of its LHS patterns — with the LHS set *extracted from the SUT's sed body at run time* so a new rewrite rule joins the oracle automatically. The first extractor read only `s|LHS|...` delimiters: `legal-normalise.sh` has 39 sed rules, 8 written `s/LHS/.../` — **a whole syntactic class invisible to the oracle**. A rule added in `s/` form would never join the residue check, and the suite would stay green.

Same commit, second channel: `if grep -qE "$p"` treats `grep`'s rc≥2 (invalid ERE) identically to no-match. An extracted LHS that doesn't compile as ERE becomes a permanent oracle no-op — the residue it was supposed to catch reads as residue-free forever.

### 2. bash-3.2 `$RANDOM` does not advance across a command substitution (design-time catch)

`x=$(prop_pick ...)` forks a subshell. On bash ≥5 the draw still advances the parent's `$RANDOM` stream; on **bash 3.2 (macOS default — the portability floor for `scripts/lib/`)** the subshell reads the *same* stream position the parent had at fork, so every loop iteration draws the identical value: the generator degenerates to a one-case suite that always passes — and `PROP_PASS` prints `runs=100` beside it.

## Solution

All in `legal-normalise-property.test.sh` / `property-harness.sh` (review commits `1c09971565`, `7b752879a4`):

```bash
# 1. Extract BOTH delimiters + conservation count against the rule census.
RULE_COUNT="$(awk '/^collapse\(\)/,/^}/' "$SUT" | grep -cE '^ +s[|/]')"
mapfile -t LHS_PATTERNS < <(
  awk '/^collapse\(\)/,/^}/' "$SUT" \
    | sed -nE 's/^ +s\|([^|]*)\|.*/\1/p; s/^ +s\/([^/]*)\/.*/\1/p'
)
(( ${#LHS_PATTERNS[@]} == RULE_COUNT && RULE_COUNT > 0 )) || fail "..."

# 2. Compile-check every extracted pattern — rc>=2 fails the suite, not "no match".
for p in "${LHS_PATTERNS[@]}"; do
  if grep -qE "$p" </dev/null; then rc=0; else rc=$?; fi
  (( rc > 1 )) && fail "extracted LHS pattern is not a valid ERE: $p"
done
```

```bash
# 3. Outvar API instead of echo-return: printf -v runs in-process on both
#    bash 3.2 and 5.x — no subshell, no stream-position divergence.
prop_rand() { local _n="$1" _out="$2"; ...; printf -v "$_out" '%s' "$draw"; }
prop_pick() { local _out="$1"; shift; ...; printf -v "$_out" '%s' "$pick"; }
```

The `property-harness.sh` header documents the rule permanently ("WHY NO ECHO-FORM"), and `prop_init` rejects `PROP_RUNS<1` so a zero budget can't emit a vacuous `PROP_PASS` (P3 sibling fix — the anti-vacuity floor itself was vacuous at zero).

## Key Insight

**An oracle extracted from SUT syntax is only as wide as its extractor's grammar.** Three independent walls, each fail-open:

1. *Form coverage* — the extractor must read every syntactic form the SUT allows (both `s|` and `s/`), not just the dominant one. A census (`grep -cE` over the same region) converted to an equality check turns "missed a form" into a loud failure.
2. *Validity* — an extracted pattern that doesn't compile reads as "no residue" under every `if grep -q` idiom, because grep folds rc≥2 into the same branch as no-match. Compile-check each member up front.
3. *Generation* — on bash 3.2, `$RANDOM` inside `$()` sees the parent's pre-fork stream position, so the "random" sequence is constant. This is the third fail-open class in one file: the *generator* can silently cover less domain than the loop count claims.

The meta-shape is `2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once`: a property named over set S whose oracle samples a subset. What's new here is the subset can be **empty-by-construction** (uncompilable pattern) or **one element repeated N times** (frozen PRNG) — both smaller than any cardinality check alone would suspect, which is why the harness asserts the census count *and* seeds deterministically *and* never lets the outvar cross a subshell boundary.

## Prevention

1. **Generated-input oracles: extraction = shapes × census × validity.** Enumerate every syntactic form the SUT permits, count the producer's rules independently, and compile-check each extracted member. Any one missing leg is a fail-open hole.
2. **`grep -qE "$var"` under `if`/`&&` is a two-outcome reader of a three-outcome tool.** Always capture `rc=$?` and branch on `>1` for extracted/dynamic patterns.
3. **bash ≤3.2 portability floor: outvar APIs for anything consuming `$RANDOM`.** `printf -v outvar` in-process; never `x=$(fn)` when `fn` draws. Also applies to any hidden stream state (incremented counters, rotated arrays).
4. **Instrument self-test before trusting green.** The suite drives `prop_fail` in a captured subshell and asserts the `PROP_FAIL` marker + non-zero rc before the first real case — a failure channel proven to fire.
5. **Anti-vacuity floors need their own floor.** `PROP_RUNS=0` produced a vacuous green until `prop_init` rejected `<1`; every "must have run N times" assertion needs the N≥1 gate beside it.

## Session Errors

1. **Residue oracle LHS extractor matched only `s|` delimiters (31/39 rules)** — `s/` rules invisible to the residue property (review P2: pattern-recognition-specialist, test-design-reviewer). Recovery: both-delimiter extraction + conservation count, `1c09971565`. **Prevention:** Prevention #1 — forms × census × validity.
2. **`grep -qE` read rc≥2 (invalid pattern) as residue-free** — fail-open channel in the same oracle (review P2). Recovery: upfront ERE compile-check, same commit. **Prevention:** Prevention #2.
3. **ALPHABET hand-copied while the header claimed "auto-join" for the generator side** — claim/machinery drift (review P2). Recovery: header corrected to say the oracle auto-joins but the alphabet is hand-maintained. **Prevention:** a claim of automatic coverage needs the mechanism named in the same sentence — "extracted" and "enumerated" are different contracts.
4. **`fails` counter not bumped on `prop_fail`** — summary printed `failed: 0` beside PROP_FAIL lines (folded into the P2 round). **Prevention:** the counter pair is one instrument; audit both halves when the failure channel changes.
5. **shellcheck SC2154 `doc` unassigned via outvar indirection** — `printf -v` writes are invisible to shellcheck's flow analysis. Recovery: `doc` initialized before the call (folded fix). **Prevention:** declare/initialize outvars before the `prop_*` call so the linter sees a defined name.
6. **`PROP_RUNS=0` vacuous green** (review P3) — Recovery: `prop_init` range-check, `567e13effe`. **Prevention:** Prevention #5.
7. **`prop_pass` takes an explicit runs arg a caller could misreport** — wontfix'd (convention passes `$PROP_ITER` at call site; API churn for hypothetical misuse). Recorded for next-time context.
8. **Plan phase (forwarded): Devin harness has no Task/Skill tools** — all prescribed fan-out (research agents, SpecFlow, advisor consult, plan-review panel, CTO rulings) ran sequentially in-process with `Reviewed-Coverage: sequential-fallback` disclosure. Already covered by the existing sequential-fallback machinery and `2026-10-06-review-seats-rate-limited-at-spawn-inline-fallback`; no new rule needed.

## References

- PR #10624 (draft); `scripts/lib/property-harness.sh` + `scripts/lib/property-harness.md`; `scripts/lib/legal-normalise-property.test.sh`
- Review dedup ledger: `knowledge-base/project/specs/archive/20261020-034022-feat-one-shot-10398-property-based-testing/session-state.md`
- Sibling class: `knowledge-base/project/learnings/2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md`; `knowledge-base/project/learnings/2026-06-11-cross-file-drift-guards-extract-every-operand-by-shape.md` (extract by shape, exactly-one count, integer-validate)
- Routed insight appended to `plugins/soleur/skills/review/SKILL.md` §Sharp Edges (generated-input oracle checklist)
