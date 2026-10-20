# Property-based testing

A reference for the `property` oracle class in `RED(unit|integration|e2e|property)`
task titles. `property` names the oracle — how the test decides pass/fail — not a
pyramid layer; the test file still lives at a layer (`unit` is the usual home,
and `*.property.test.ts` classifies there by path).

## When to reach for it

Reach for `property` when the behavior is a contract that must hold for every
input, not a list of cases you can enumerate:

- **Round-trips** — `decode(encode(x)) == x` for all x (serializers, codecs,
  normalizers; escape/unescape pairs only where the transform is truly
  invertible). Through a lossy serializer (JSON `-0`/`NaN`/`undefined`),
  compare `decode(encode(x))` against the canonical form `canonicalize(x)` —
  never `x` itself, never the round-trip expression (a self-oracular RHS
  passes a constantly-wrong codec).
- **Invariants under mutation** — `sort` is idempotent and a permutation of its
  input; `retry` never exceeds the cap; a reducer keeps a conserved quantity.
- **Metamorphic relations** — output is monotone in a parameter; appending an
  element to the input can only add results, never remove one.
- **Two implementations** — a fast path and a reference path must agree
  (differential/property testing); a new SQL function and its TS twin.
- **Parser/validator boundaries** — every input is either accepted with a valid
  shape or rejected; never silently mangled.

Stay with `unit`/`integration`/`e2e` examples when the interesting behavior is a
small number of named cases, a UI flow, or a contract that only holds at a
boundary (auth gating, 404 shape) — property tests shine where the input
alphabet is too large to enumerate.

## The workflow

1. **Start with a pure function.** Property tests want deterministic,
   side-effect-free cores. If the behavior is tangled in I/O, extract the pure
   part first (the TDD gate's RED-first discipline applies unchanged).
2. **Say the property in plain English first.** "Every normalized URL re-parses
   to the same host" before `fc.property(...)`. If you cannot state it in one
   sentence, you do not have a property yet — you have a fuzzy unit test.
3. **Pick the property's strength.** Weakest: output is well-formed (shape,
   bounds, non-crash). Middle: an invariant relates input to output
   (monotonicity, conservation, idempotence). Strongest: an oracle — a second,
   obviously-correct implementation, or round-trip through an inverse.
4. **Generate the input alphabet, not examples.** The generator describes the
   whole space (including empties, unicode, deep nesting, adversarial lengths);
   the library explores it. Write the generator as carefully as the assertion —
   a generator that only produces benign inputs tests nothing.
5. **Add a negative control.** Run the property against a deliberately broken
   implementation (mutant) once at write time and confirm it fails. A property
   that survives a mutant is a vacuous assertion, same class as a green test
   that never exercised the branch.

## Counterexample lifecycle

When a property test fails, the library reports a counterexample and typically
**shrinks** it — minimizes the failing input until it is as small as possible.
That minimized case is the real find.

- **Triage the shrunk case, not the original.** The original random input is
  noise; the shrunk one isolates the trigger.
- **Pin the minimized case as a permanent named regression test.** The
  regression suite (ordinary `unit` example test) replays it deterministically
  every run; the property run guards the rest of the space.
- **Never pin seeds.** The seed is an accident of one run; the regression
  fixture is a deliberate, named, reviewed input. `// regression fixture:` —
  one line, says what broke.
- **If the shrinker loops or the minimal case is still large**, the generator's
  alphabet is too wide — narrow it (the bug is usually in a small corner).

## Language → tool map

| Language | Library | Entry point |
|---|---|---|
| TypeScript / JavaScript | [fast-check](https://fast-check.dev/) (v4 verified 2026-10-20) | `fc.assert(fc.property(arb, fn))` |
| Python | [Hypothesis](https://hypothesis.works/) (v6 verified 2026-10-20) | `@given(st.<strategy>)` |
| Rust | [proptest](https://crates.io/crates/proptest) (v1.12 verified 2026-10-20) | `proptest! { #[test] fn t(x in strategy) { … } }` |
| JVM | jqwik (unverified) | `@Property` |
| Haskell | QuickCheck (unverified) | `quickCheck prop` |
| .NET | FsCheck (unverified) | `Check.Quick` |

### Minimal fast-check example (TypeScript)

```ts
import fc from "fast-check";

// property: normalize is idempotent — applying it twice changes nothing more.
fc.assert(
  fc.property(fc.webUrl(), (url) => {
    const once = normalizeUrl(url);
    return normalizeUrl(once) === once;
  }),
);
```

### Minimal Hypothesis example (Python)

```python
from collections import Counter
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_sort_is_permutation(xs):
    s = sorted(xs)
    assert Counter(s) == Counter(xs)                    # same multiset — a permutation
    assert sorted(s) == s                               # idempotent
    assert all(a <= b for a, b in zip(s, s[1:]))        # actually ordered
```

(Hypothesis also supports `@settings` for run counts and `st.data()` for
interactive draws — see the tool docs; keep examples like the above pinned to
verified symbols.)

## House conventions

This monorepo's own machinery for property tests lives in
`apps/web-platform/test/README.md` (suite conventions, `*.property.test.*`
naming) and `scripts/lib/property-harness.md` (the repo-side harness shipped for
its own guard corpus — ADR-293). Those paths are this repo's internals; a plugin
install does not carry them. In user repos, the common convention is
`*.property.test.*` files beside the layer suites and
`// regression fixture: <seed-note>` comments on pinned counterexamples.
