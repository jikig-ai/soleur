---
module: web-platform
date: 2026-10-20
problem_type: best_practice
component: testing_framework
symptoms:
  - "fc.jsonObject() / fc.stringOf() cited in fast-check docs are not in the installed 4.10.2 API surface"
  - "A JSON round-trip property comparing against the raw generated value fails on -0: JSON.stringify(-0) === \"0\" but vitest toEqual distinguishes -0 from 0"
root_cause: wrong_api
resolution_type: tooling_addition
severity: low
tags: [fast-check, property-based-testing, json, arbitraries, vitest]
---

# Learning: fast-check v4 substitutions — fc.dictionary+fc.jsonValue for JSON objects, fc.string({unit}) for biased alphabets, and canonicalize JSON oracles before comparing

## Problem

Writing the PR #10624 vitest property suites required two API substitutions and one oracle correction against `fast-check@4.10.2` (`apps/web-platform` devDependency):

1. **`fc.jsonObject()` is not in the v4 surface** (docs/plans cite it, it does not exist in the installed package). The substitute for "arbitrary JSON-compatible object" is:

   ```ts
   const messageArb = fc.dictionary(fc.string(), fc.jsonValue());
   ```

   `fc.jsonValue()` generates nested objects/arrays/scalars while staying strictly JSON-serializable; `fc.dictionary` wraps it in a top-level object. The combination covers `jsonObject`'s domain exactly.

2. **`fc.stringOf()` does not exist** — to bias a string generator toward a forbidden-character alphabet (e.g. log-sanitize's strip class C0/DEL/U+2028/U+2029), the v4 form is the `unit` arbitrary option:

   ```ts
   fc.string({
     unit: fc.constantFrom("\x00", "\x1f", "\x7f", "\u2028", "\u2029", "a", "Z", "9", " ", "\n", "ok"),
   })
   ```

   Each `unit` is a building block the string is assembled from, so the interesting domain is dense instead of one codepoint per few-thousand chars.

3. **A JSON round-trip oracle is the canonical JSON form, not the raw generated value.** `fc.jsonValue()` can emit `-0`; `JSON.stringify(-0)` is `"0"`, so `decode(encode(m))` legitimately returns `0` where `m` held `-0` — and vitest `toEqual`/`Object.is` semantics distinguish `-0` from `0`. The same applies to `NaN`/`undefined`, which JSON cannot represent. Correct oracle:

   ```ts
   const canonical = (m: unknown): unknown => JSON.parse(JSON.stringify(m));
   expect(decodeCodexJsonlLine(encodeCodexJsonl(m))).toEqual(canonical(m));
   ```

   The property then asserts "decode(encode(m)) reproduces the canonical JSON form of m" — the wire contract — rather than object identity with the generator's reference value.

## Solution

All three landed in `apps/web-platform/test/{lib,server}/*.property.test.ts` (commits `04650ffd43`, `27d21ce3f6`, `d5d7a6f7dd`). Each suite also carries a **negative-control `it`** — `fc.assert(fc.property(arb, () => false))` must throw — so a suite that can only pass is caught (anti-vacuity, ADR-293).

## Key Insight

- **Pin the API surface against the installed package, not the docs.** Plan phase verified `npm view fast-check` → 4.10.2 and the cited API list; `jsonObject`/`stringOf` still slipped through because they appear in fast-check's own docs and in plan prose. `Object.keys(fc).filter(...)` on the installed version is the five-second check.
- **`toEqual` semantics decide whether an oracle needs canonicalization.** Any property whose round-trip passes through a lossy serializer (JSON, URL-encoding, locale collation) must compare against `deserialize(serialize(x))`'s fixed point — `JSON.parse(JSON.stringify(x))` for JSON — not against `x`.
- **Bias generators at the boundary the SUT cares about.** `unit:`/`constantFrom` for forbidden characters; `tuple(fc.webUrl(), suffixArb).map(([u,s]) => u+s)` for URL+suffix composition; `tuple(constantFrom(" ", "\t", "\n"), urlishArb).map(...)` for padding. Composed arbitraries are how a flat generator finds intersection defects like the repo-url re-trim.

## Session Errors

1. **`decodeCodexJsonlStream` was fed `string[]` instead of an `AsyncIterable`** in the first draft of the codex suite — type-check red, fixed in `d5d7a6f7dd`. **Prevention:** the SUT's stream seam consumes `AsyncIterable`; a `[...]` literal is the example-test instinct — wrap chunks in an async generator when the consumer is async.

## References

- ADR-293 (`knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md`)
- `apps/web-platform/test/README.md` §"Property-based tests"; `scripts/lib/property-harness.md` (shell-arm sibling)
- fast-check docs: https://fast-check.dev/ (`fc.dictionary`, `fc.jsonValue`, `fc.string({unit})`, `{seed, path, numRuns}`)
