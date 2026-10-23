# ADR-293: Property-based testing is a sanctioned third test class

- Status: adopting (soak is the suites living in CI selection)
- Date: 2026-10-19
- Issue: #10398 (epic #10397 child 1)

## Context

Every test in the repo was example-based: each asserts one hand-picked point
of an input domain. Two hand-rolled generated-input suites existed
(`mulberry32` deterministic fuzz in
`test/server/inngest/cron-community-publication.test.ts`, `test/rls-fuzz/`
authz fuzz) but neither shrinks counterexamples, neither uses declarative
arbitraries, and neither is a repeatable pattern other suites can adopt — the
epic audit (#10397) measured this as a gap against the agentic-verification
practice of letting a generator hunt for the "must never happen" violation.

## Decision

Property-based testing is a sanctioned third test class, alongside example
tests and mutation batteries, with one library per arm:

- **Vitest arm:** `fast-check` (npm 4.x, zero dependencies, devDependency-only
  in `apps/web-platform`). Suites are `test/<area>/<subject>.property.test.ts`
  files in the existing `unit` project — no config change; `vitest related`
  narrows them on SUT import-graph diffs. Each file carries ≥1
  negative-control `it` (`fc.assert(prop(false))` must throw) so a suite that
  can only pass is caught, and found counterexamples become permanent `it()`
  regression fixtures labelled `// regression fixture: fast-check seed <seed>
  path <path>` — never `{ seed }` params in committed code.
- **Shell arm:** `scripts/lib/property-harness.sh` (sourced lib:
  `prop_init`/`prop_iter`/`prop_rand`/`prop_pick`/`prop_fail`/`prop_pass`,
  `PROP_SEED` replay, `PROP_RUNS` budget) + `scripts/lib/property-harness.md`
  pattern doc. Reference suite `scripts/lib/legal-normalise-property.test.sh`.
  `.test.sh` property suites live under `SUITE_GLOBS` directories
  (`scripts/lib/`, `.claude/hooks/`, `plugins/soleur/test/`) — placement is
  registration.

The convention doc (generator-over-token-alphabet enumerating every SUT
transform, shell property shapes, seed replay, counterexample triage) lives in
`property-harness.md`; `apps/web-platform/test/README.md` and
`.claude/hooks/README.md` carry pointers.

## Alternatives considered

- **Example-only status quo** — rejected: the audit's finding stands; the
  oracle class (generation + shrinking) is the point, not more examples.
- **Per-suite hand-rolled PRNG** — rejected for TS (duplicates arbitraries +
  shrinking poorly); adopted deliberately on the shell side where a sourced
  repo lib cannot take an npm dep.
- **Install `@trailofbits/skills/property-based-testing` community plugin** —
  deferred: adoption of a plugin is orthogonal scope; the catalog informed
  the property taxonomy only.
- **CI/registration edits** — rejected: `ci-pr-selection.sh`/`test-all.sh`
  carry no per-suite knowledge; glob placement + `source`-closure edge
  derivation wire the suites with zero runner edits.

## First yield

The `repo-url` property suite found a real defect on first run:
`normalizeRepoUrl("foo .git")` returned `"foo "` — a suffix strip exposed
trailing whitespace, breaking the documented idempotence contract. Fixed by
re-trimming after the strips (`lib/repo-url.ts` step 5); the shrunk
counterexamples are pinned as regression fixtures. The same shape exists in
the SQL twin (`031_normalize_repo_url.sql`). Migration 031 is immutable once
applied, so the corrected chain and a stored-row re-normalization shipped as
`163_renormalize_repo_url.sql` (#10633), with a strict `verify/163` sentinel and
a Postgres-generated golden table behind the parity test; the TS↔SQL parity
boundary still only covers URL-clean inputs.
