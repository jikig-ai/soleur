---
module: KB Concierge / Type System
date: 2026-05-07
problem_type: integration_issue
component: tooling
symptoms:
  - "Compile-time `_AssertPartitionTotal` rail using `typeof <Set> extends ReadonlySet<infer T> ? T : never` compiled clean with members missing from either set"
  - "Adding a new union member without partition coverage produced a vacuously-true assignment instead of a build failure"
  - "Tests passed; the bug was caught only via independent multi-agent review (architecture-strategist + pattern-recognition-specialist) running their own TS probes"
root_cause: type_widening
resolution_type: code_fix
severity: high
tags: [typescript, exhaustiveness-rail, infer-T, as-const-satisfies, multi-agent-review, partition-types, compile-time-guarantee]
synced_to: []
---

# Learning: Type-level partition rails must derive from `as const satisfies` literal tuples — `infer T` on a typed `Set` collapses to a tautology

## Problem

PR #3405 introduced a compile-time partition rail to lock the soft/hard partition over `PdfExtractErrorClass`:

```ts
const PDF_SOFT_FAILURE_CLASSES: ReadonlySet<PdfExtractErrorClass> = new Set<
  PdfExtractErrorClass
>([
  "oversized_buffer",
  "corrupted",
  "parse_error",
  "lazy_import_failed",
  "read_failed",
]);

const PDF_HARD_FAILURE_CLASSES: ReadonlySet<PdfExtractErrorClass> = new Set<
  PdfExtractErrorClass
>(["encrypted", "empty_text"]);

type _PartitionMembers =
  | (typeof PDF_SOFT_FAILURE_CLASSES extends ReadonlySet<infer T> ? T : never)
  | (typeof PDF_HARD_FAILURE_CLASSES extends ReadonlySet<infer T> ? T : never);
type _AssertPartitionTotal = PdfExtractErrorClass extends _PartitionMembers
  ? _PartitionMembers extends PdfExtractErrorClass
    ? true
    : never
  : never;
const _partitionExhaustive: _AssertPartitionTotal = true;
```

Plan claim: "if `PdfExtractErrorClass` widens, the assertion fails until the new member lands in exactly one of the two sets above."

**The claim was false.** The rail was vacuously true. Adding `"new_class"` to `PdfExtractErrorClass` and forgetting to add it to either Set would compile cleanly. Removing `"encrypted"` from `PDF_HARD_FAILURE_CLASSES` would compile cleanly. The "compile-time guarantee" was nonexistent.

## Investigation

The bug was invisible to:
- `tsc --noEmit` (clean)
- The vitest suite (all targeted tests passed)
- The runtime `for (const cls of SOFT_CLASSES)` test loop (loops over hand-maintained tuples that themselves duplicated the runtime sets — a member missing from BOTH the runtime sets AND the test tuples is silently absent from any assertion)

It was caught only by multi-agent review running independent TS probes. Two reviewers (architecture-strategist, pattern-recognition-specialist) — running concurrently in different agent contexts — both built a TS probe with deliberately incomplete sets and reproduced the no-error result. Their convergent finding made the bug actionable.

## Root Cause

`infer T` on `typeof <variable>` resolves against the variable's *declared* type, not the value passed to its constructor. When the Set was annotated:

```ts
const PDF_SOFT_FAILURE_CLASSES: ReadonlySet<PdfExtractErrorClass> = new Set<...>([...])
```

`typeof PDF_SOFT_FAILURE_CLASSES` resolved to `ReadonlySet<PdfExtractErrorClass>`. Therefore `infer T` yielded `PdfExtractErrorClass` itself — the FULL union, not the literal members of the constructor argument array. `_PartitionMembers` collapsed to `PdfExtractErrorClass | PdfExtractErrorClass = PdfExtractErrorClass`, and the bidirectional rail reduced to:

```ts
PdfExtractErrorClass extends PdfExtractErrorClass
  ? PdfExtractErrorClass extends PdfExtractErrorClass
    ? true
    : never
  : never
// ≡ true (always)
```

The plan's Sharp Edge actually warned about this — but **got the warning backwards**:

> "If the `Set` is constructed without an explicit `ReadonlySet<PdfExtractErrorClass>` annotation, TypeScript widens the element type to `string` and the rail collapses."

The plan author thought the annotation was *needed* to prevent rail collapse. In fact, the annotation is what *causes* the collapse — without it, the array literal would give literal types (`Set<"oversized_buffer" | ...>`), and the rail would work. With the annotation, `infer T` reads from the annotation, not the array.

## Solution

Drive `_PartitionMembers` off `as const satisfies readonly <Union>[]` literal tuples — never from `infer T` on a typed collection:

```ts
export const PDF_SOFT_FAILURE_LITERALS = [
  "oversized_buffer",
  "corrupted",
  "parse_error",
  "lazy_import_failed",
  "read_failed",
] as const satisfies readonly PdfExtractErrorClass[];

export const PDF_HARD_FAILURE_LITERALS = [
  "encrypted",
  "empty_text",
] as const satisfies readonly PdfExtractErrorClass[];

const PDF_SOFT_FAILURE_CLASSES: ReadonlySet<PdfExtractErrorClass> = new Set(
  PDF_SOFT_FAILURE_LITERALS,
);

type _PartitionMembers =
  | (typeof PDF_SOFT_FAILURE_LITERALS)[number]
  | (typeof PDF_HARD_FAILURE_LITERALS)[number];
type _AssertPartitionTotal = PdfExtractErrorClass extends _PartitionMembers
  ? _PartitionMembers extends PdfExtractErrorClass
    ? true
    : never
  : never;
const _partitionExhaustive: _AssertPartitionTotal = true;
```

The shape closes a **dual gap**:

1. **Member added to union, missing from tuples** — `PdfExtractErrorClass extends _PartitionMembers` becomes false. Build fails at the rail.
2. **Typo in tuple, not a union member** — `as const satisfies readonly PdfExtractErrorClass[]` rejects the typo at literal-declaration time. Build fails at the satisfies clause.

Test-time mirror in `read-tool-pdf-capability.test.ts` now imports `PDF_SOFT_FAILURE_LITERALS` and `PDF_HARD_FAILURE_LITERALS` from the runtime — single source of truth across rail + predicate + test loop.

## Key Insight

**`typeof <variable>` reads the variable's declared type, not the constructor argument's literal type.** Any compile-time guarantee that pivots on `infer T` from a typed collection is at risk of resolving to the annotation rather than the contents.

The safer pattern: declare the source-of-truth as `as const` literal tuples, then derive both runtime collections AND type-level rails from them. The `satisfies` clause adds a second layer (typo detection) that the bidirectional rail alone cannot catch.

This is a sibling of [discriminated-union widening (`cq-union-widening-grep-three-patterns`)](2026-04-18-discriminated-union-widening-if-ladders-and-config-map-parity.md): both are TypeScript exhaustiveness gotchas where the compile-time guarantee is weaker than the prose claims, and both are reliably caught by multi-agent review running independent probes.

## Prevention

- When constructing a partition rail, never write `typeof <typedSet> extends ReadonlySet<infer T> ? T : never`. Always derive `_PartitionMembers` from `(typeof <constLiteralTuple>)[number]`.
- Pair the `as const` tuple with `satisfies readonly <Union>[]` so a typo in the tuple fails at declaration.
- For verification, write a TS probe with deliberately-incomplete tuples and confirm `tsc --noEmit` errors with `Type 'true' is not assignable to type 'never'`. If it compiles, the rail is broken.
- When a plan claims a compile-time guarantee, multi-agent review must independently probe the claim — do not trust the prose. The exact failure shape (silent compile-clean) means the bug is invisible to test runs and tsc on the working codebase.
- Export the literal tuples from the runtime module so test files iterate them directly. Hand-maintained test-side duplicates of the partition produce a one-way lock (rail catches, but tests vacuously pass on a missing class).

## Tags

category: type-system
module: KB Concierge prompt builder

## Session Errors

- **Tautological partition rail (P1, pr-introduced)** — the original `_AssertPartitionTotal` rail on `infer T` from a typed `Set` was vacuously true (`Union extends Union ? true : never`). Caught only by multi-agent review with independent TS probes. **Recovery:** rewrote rail to derive `_PartitionMembers` from `as const satisfies readonly PdfExtractErrorClass[]` literal tuples; exported tuples + imported in test partition mirror. **Prevention:** when introducing a compile-time exhaustiveness rail, run a TS probe with deliberately incomplete sets and confirm `tsc` rejects the `_partitionExhaustive` assignment. Pattern: `as const satisfies readonly <Union>[]` for source tuples, then `(typeof <tuple>)[number]` for rail derivation. Never rely on `infer T` from a typed collection.

- **`expectNoCascade` test pin scope mismatch** — flipping soft-class assertions from `buildPdfUnreadableDirective` (which doesn't name the cascade binaries) to `buildPdfGatedDirective` (which contains the binary names by design in its defensive "Do NOT call X" exclusion list) broke the `Set#has` cascade pin on every soft-route test. **Recovery:** dropped `expectNoCascade` from soft-route tests; the regex-based "does NOT install software" test (`/\b(install|run)\s+apt-get\b/`) remains the appropriate cascade-enabling pin because it distinguishes defensive from enabling context. **Prevention:** when a directive contains binary names in a defensive context, cascade-enabling pins must use enabling-shape matchers (regex on imperative verbs) rather than substring presence on the binary names.

- **Agent contention on `read_failed` placement** — data-integrity P2 + git-history P3 argued that `read_failed` is FS-side and SDK Read against the same path will repeat the error (move to hard); user-impact-reviewer (plan-mandated for `single-user incident` threshold, CPO-relevant) explicitly rejected the move because the user's filmed reproduction (#3376) was a path-shape mismatch SDK Read would resolve. Applied the move first, then reverted. **Recovery:** restored to soft, documented asymmetric-cost rationale (best-case recovery vs worst-case extra roundtrip with tool-error paraphrase) in code comment. **Prevention:** when a plan declares a brand-survival threshold (e.g., `single-user incident`), the plan-mandated reviewer's verdict supersedes other agents' findings on user-facing routing decisions. Apply changes only after that reviewer's CONCUR/DISSENT is in.

- **GraphQL rate limit transient hit** — `gh pr view` returned "API rate limit already exceeded" at review-skill start. The graphql endpoint has a separate quota from REST; the per-resource `rate_limit` endpoint showed the reset had already passed. **Recovery:** retried after rate-limit-resource check. **Prevention:** before assuming a hard rate limit, query `gh api rate_limit --jq .resources` and use the per-resource reset epoch.

- **Bash CWD doesn't persist across calls in a worktree pipeline** — `git add ...` from the bare repo root path returned `pathspec did not match`. **Recovery:** prefixed every git/test/build command with `cd <worktree-abs-path> && <cmd>`. **Prevention:** already covered by AGENTS.md `cm-when-running-test/lint/budget-commands-from-inside-worktree-pipeline`. No new rule.

## See also

- [`2026-04-18-discriminated-union-widening-if-ladders-and-config-map-parity.md`](2026-04-18-discriminated-union-widening-if-ladders-and-config-map-parity.md) — sibling TypeScript exhaustiveness gotcha on if-ladders vs switches; same pattern of "audit prose claims a guarantee that the type system doesn't actually enforce."
- [`best-practices/2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md`](best-practices/2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md) — multi-agent review reliably catches feature-wiring bugs that tests + tsc miss; this incident extends the catalogue with "tautological compile-time rails."
