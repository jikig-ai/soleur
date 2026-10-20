---
title: "Decision challenges — feat-one-shot-10398-property-based-testing"
date: 2026-10-19
branch: feat-one-shot-10398-property-based-testing
---

# Decision Challenges

Headless one-shot planning for #10398. Technical items were ruled in-process via the CTO Rule interface (no Agent tool on Devin); operator-class items are persisted for `ship` Phase 6 to render into the PR body and file as `action-required` issues.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Shell property-harness shape: shared sourced lib vs copy-paste idiom vs doc-only | technical | Ruled by CTO agent, 2026-10-19: shared lib `scripts/lib/property-harness.sh` + canonical doc + one reference suite — the `legal-normalise.sh` header records the governing rationale ("a second implementation is a second thing to drift"); a doc-only idiom across ~715 suites re-creates it. Dissent: none — stricter option also wins on drift grounds. |
| Shell property suite placement: `scripts/lib/` vs repo-root `scripts/` vs `.claude/hooks/` | technical | Ruled by CTO agent, 2026-10-19: `scripts/lib/` — `scripts/lib/*.test.sh` is in `SUITE_GLOBS` (test-all.sh:107) so presence is registration; repo-root `scripts/*.test.sh` is deliberately not globbed (test-all.sh:6707 — "runs in zero runners and stays green forever"); a repo-root placement would also force a `test-all.sh` edit, which is on ci-pr-selection's TRIGGER LIST. SUT (`legal-normalise.sh`) sits beside the suite. |
| Vitest suite naming: `*.property.test.ts` infix vs plain `*.test.ts` vs a `test/property/` dir | technical | Ruled by CTO agent, 2026-10-19: `test/<area>/<subject>.property.test.ts` — matches the `unit` include `test/**/*.test.ts` and the test/README.md mirror-the-SUT placement convention; the infix makes the class greppable for ACs and future curation. |
| Seed policy: pinned `seed:` in committed properties vs unseeded + fixture convention | technical | Ruled by CTO agent, 2026-10-19: never pin seeds — coverage variance across runs is the point; fast-check prints seed+path on failure; shrunk counterexamples become permanent `it()`/`case` fixtures (satisfies issue AC "save minimized failing cases"). |
| Property subjects: codex-app-server-jsonl / plan-limits / repo-url (+log-sanitize) | technical | Ruled by CTO agent, 2026-10-19: these four — direct match to the issue's parser/formatter/serialization examples, all pure, all with *strong* properties (round-trip, invariant, idempotence) per the ToB strength ordering; log-sanitize is a bonus fourth covering a sensitive-path-adjacent module at ~30 lines. |
| "CI wiring" interpretation: the issue says `ci-pr-selection.sh` | technical | Ruled by CTO agent, 2026-10-19: no edits to `ci-pr-selection.sh` or `test-all.sh` — verified in `_affected_derive` (test-all.sh:3263-3391) that glob-registered suites derive edges from argv literals + name-stem + source/import closure; wiring is achieved by placement and asserted empirically (AC9/AC15). The issue's AC wording is satisfied structurally, not literally. |
| Install `@trailofbits/skills/property-based-testing` community plugin (found by functional-discovery: covers fast-check conventions + shrunk-counterexample triage) | operator (scope) | pending — NOT installed; plan meets ACs with fast-check + in-repo docs. Ship: file as action-required so the operator can decide whether the plugin adds review-time value (re-evaluation also natural under epic sibling #10400, which ships PBT guidance to plugin users). |
| Extend property coverage to `normalizeRepoUrl`'s SQL mirror (`031_normalize_repo_url.sql`) | technical | Ruled by CTO agent, 2026-10-19: deferred — `repo-url-sql-parity.test.ts` already owns the parity property; SQL-side generation is a separate scope (recorded in plan Future Considerations; epic #10397 siblings may pick it up). |

## Not Yet Specified candidates

- Whether `.test.sh` property suites should eventually enforce per-suite `PROP_PASS`-marker presence via a lint (a "property suite that prints nothing" detector) — premature with one suite; revisit if the pattern gains ≥3 adopters.
