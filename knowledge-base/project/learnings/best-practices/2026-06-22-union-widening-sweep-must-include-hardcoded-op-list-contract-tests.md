# Learning: union-widening sweep must include hardcoded op-list contract tests, not just type-level switches

## Problem

PR #5628 widened the `RepoResolverDivergenceOp` union in
`apps/web-platform/server/repo-resolver-divergence.ts` with a new member
(`reprovision-non-member-claim-reset`). During `/work` I ran the
`cq-union-widening-grep-three-patterns` sweep and confirmed no exhaustive
`switch` / `Record<Op, …>` / `Op[]` consumer would break or under-handle the new
member — `tsc` was clean and the suite was green.

Multi-agent review (`pattern-recognition-specialist`) then caught a **P2** the
sweep missed: `apps/web-platform/test/sentry-repo-resolver-divergence-alert-op-contract.test.ts`
holds a **hardcoded** `OPS = [...]` array — a cross-artifact contract test whose
whole job is to assert every union member is covered by the feature-scoped Sentry
alert. Because the list is a hand-maintained literal (not derived from the union),
adding a union member does NOT fail it — the new op was simply unchecked, a silent
false-green. Worsened by a substring trap: the existing `non-member-claim-reset`
is a substring of the new `reprovision-non-member-claim-reset`, so a bare
`emitter.toContain(op)` could not even distinguish them.

## Solution

Fixed inline during review: added the new op to `OPS`, switched the membership
assertion to the **quoted** literal (`emitter.toContain('"' + op + '"')`) so a
substring can't satisfy a sibling op, and added a distinct-member guard case.

## Key Insight

The type-level union-widening sweep (`switch` / `Record` / `Op[]`) is necessary
but **not sufficient**. A union member can also be enumerated in a **hand-maintained
literal list** inside a contract/parity test — and those are invisible to `tsc`
and pass green on a stale list. When widening any string-literal union that has a
cross-artifact contract test, extend the sweep:

1. `git grep -n '<one-existing-member>' <test-dir>` to find hardcoded enumerations
   of the union's members (op-contract tests, parity tests, alert-coverage tests).
2. Update each literal list in the same commit.
3. Prefer **quoted-literal** assertions (`toContain('"' + member + '"')`) whenever
   one union member is a substring of another, so the assertion is member-distinct.

This is the test-literal companion to `cq-union-widening-grep-three-patterns`.

## Session Errors

- **Union-widening sweep missed a hardcoded op-list contract test** — Recovery:
  fixed inline during review (added op to `OPS`, quoted-literal assertions,
  distinct-member guard). Prevention: the union-widening sweep must `git grep` an
  existing member across the test dir to find hand-maintained enumerations, not
  only type-level switch/Record consumers. (recurring)
- **`Edit` "String to replace not found"** on `repo-resolver-divergence.ts` —
  Recovery: retried with a shorter unique anchor (em-dash/indentation in the
  original block didn't match). Prevention: anchor Edits on a short unique
  substring rather than a multi-line block containing em-dashes/special chars.
  (one-off)
- **`semgrep`/`tsc` exit code read empty via `PIPESTATUS`** after a `| tail`
  pipe — Recovery: re-ran with explicit `> log 2>&1; echo "EXIT=$?"`. Prevention:
  for load-bearing pass/fail, capture rc on its own line, don't read it through a
  pipe tail. (one-off; already covered by the work-skill `EXIT=$rc` guidance)

## Tags
category: best-practices
module: apps/web-platform/server (tagged-event op unions)
