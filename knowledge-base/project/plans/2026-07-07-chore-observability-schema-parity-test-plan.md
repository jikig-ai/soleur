---
title: "Observability-block schema parity test"
type: chore
issue: 4133
branch: feat-one-shot-4133-observability-schema-parity
lane: cross-domain
brand_survival_threshold: none
created: 2026-07-07
---

# chore: Observability-block schema parity test (#4133)

> Note: No `spec.md` exists for this branch — `lane:` defaulted to `cross-domain` (TR2 fail-closed) per plan skill Save-Tasks rule.

## Overview

The `## Observability` block schema — 5 top-level fields (`liveness_signal`, `error_reporting`, `failure_modes`, `logs`, `discoverability_test`) — introduced by PR #4123 (Ref #4116) is replicated verbatim across **4 surfaces** with no compile-time or commit-time guard. Phase 4.7 of `deepen-plan` enforces the schema at *plan-authoring runtime* (against a plan file), but nothing guards the **canonical schema definitions themselves** against drifting apart. A rename or field add/remove in any single surface silently desyncs the gate from its own template.

This plan adds a single self-contained `bun:test` drift-guard — `plugins/soleur/test/observability-schema-parity.test.ts` — that treats `plan/SKILL.md §2.9` as canonical and asserts the other surfaces agree. It is a pure test addition: no production code, no infra, no schema change.

### The 4 surfaces (verified 2026-07-07)

| # | Surface | Location | How the schema appears |
|---|---------|----------|------------------------|
| 1 (canonical) | `plugins/soleur/skills/plan/SKILL.md` §2.9 | fenced ```yaml block, lines 476–482 | 5 top-level keys, inline `#` comments |
| 2 | `plugins/soleur/skills/plan/references/plan-issue-templates.md` | 3 `## Observability` yaml blocks (MINIMAL @36, MORE @164, A LOT @305) | 5 top-level keys **+ nested sub-fields** per block |
| 3 | `plugins/soleur/skills/deepen-plan/SKILL.md` §4.7 Step 3 | prose, lines 449 & 453 | 5 backticked field names `` `liveness_signal` `` … |
| 4 | `AGENTS.core.md` `hr-observability-as-plan-quality-gate` | rule line 48 | **does NOT enumerate names** — states `(5 fields)` + `WITHOUT SSH` invariant |

### Key design nuance — surface 4 does not name the fields

`AGENTS.core.md` deliberately says `` `## Observability` block (5 fields) `` without listing the 5 names (the always-loaded rule budget is byte-capped; enumerating names there would bloat it). Therefore the parity test **cannot** assert "each name appears in AGENTS.core.md." Instead it asserts the **count claim** `(N fields)` where `N === canonical.length`, plus presence of the `discoverability_test` / no-SSH invariant. This is the one place the issue's literal step-2 ("assert each name appears in the other 3 surfaces") must be adapted — recorded here so it is a deliberate decision, not an oversight.

## Research Reconciliation — Issue body vs. Codebase

| Issue-body claim | Reality | Plan response |
|---|---|---|
| "Assert each name appears in the other 3 surfaces" | Surface 4 (`AGENTS.core.md`) does not enumerate field names by design | Assert `(5 fields)` count parity + no-SSH invariant on surface 4; assert full name-set parity only on surfaces 2 & 3 |
| "3 templates" in `plan-issue-templates.md` | Confirmed 3 `## Observability` yaml blocks (MINIMAL/MORE/A LOT), each carrying all 5 top-level keys incl. `logs` | Block-walk all `## Observability` yaml blocks; assert exactly 3 found + each set-equals canonical |
| Test may be `.ts` or `.sh` | `bun test plugins/soleur/` (test-all.sh:196) auto-discovers `*.test.ts` recursively — no test-all.sh edit needed | Use `.test.ts` with `bun:test` (matches repo convention, e.g. `terraform-target-parity.test.ts`) |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — a false-passing or false-failing CI check on the Soleur plugin's own test suite. Worst case is a noisy red check on unrelated PRs (false positive) or continued undetected schema drift (false negative).
**If this leaks, the user's data is exposed via:** N/A — the test reads only in-repo documentation files, touches no user data, secrets, or external services.
**Brand-survival threshold:** none — internal developer-tooling drift guard; touches no production surface and no `single-user incident` sensitive path (only `plugins/soleur/test/`). Reason: pure test addition over committed docs.

## Implementation Phases

### Phase 1 — Write the failing-first parity test

Create `plugins/soleur/test/observability-schema-parity.test.ts`:

```ts
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const read = (p: string) => readFileSync(resolve(REPO_ROOT, p), "utf8");

// Extract top-level YAML keys (column-0 `key:`) from a fenced ```yaml block body.
function topLevelKeys(blockBody: string): string[] {
  return blockBody
    .split("\n")
    .map((l) => l.match(/^([a-z_]+):/)?.[1])   // column 0 → sub-fields (indented) excluded
    .filter((k): k is string => Boolean(k));
}

// Return the bodies of every ```yaml fenced block that sits under a `## Observability` heading.
function observabilityYamlBlocks(md: string): string[] { /* see Phase 1 notes */ }
```

Assertions (one `test()` per surface):

1. **Canonical** (`plan/SKILL.md`): extract the yaml block after `**Required schema (verbatim`; `CANONICAL = topLevelKeys(block)`. Assert `CANONICAL.length === 5` and `new Set(CANONICAL)` equals the literal expected set (sanity anchor so a 6th field added *only* to canonical is caught). Export `CANONICAL` for reuse.
2. **`plan-issue-templates.md`**: block-walk every `## Observability` yaml block. Assert **exactly 3** blocks found (catches a dropped/added template). For each block, assert `topLevelKeys(block)` set-equals `CANONICAL`.
3. **`deepen-plan/SKILL.md` §4.7**: for every line that enumerates the fields (`For each of the 5 required top-level fields (…)` and the empty-key line), extract all `` `([a-z_]+)` `` tokens; assert the extracted set (filtered to the canonical namespace) set-equals `CANONICAL`. Assert the literal count word `5` in "the 5 required top-level fields" equals `CANONICAL.length`.
4. **`AGENTS.core.md`**: locate the `hr-observability-as-plan-quality-gate` rule line. Assert it contains `(${CANONICAL.length} fields)` (count parity), `discoverability_test`, and a WITHOUT-SSH invariant token (`WITHOUT SSH`). Names are intentionally not asserted here (see design nuance).

### Phase 2 — Prove the guard bites (RED evidence)

Temporarily rename `logs` → `log_output` in ONE surface (e.g. MORE template block) locally, run the test, confirm it FAILS with a message naming the offending surface; revert. Capture the failing output in the PR body. This satisfies AC "test fails when any of the 5 field names is renamed in any single surface." Also spot-check: rename in canonical only → templates/deepen-plan mismatch → fail.

### Phase 3 — Run green + full suite

`cd <repo-root> && bun test plugins/soleur/test/observability-schema-parity.test.ts` → green. Then confirm auto-discovery: `bun test plugins/soleur/` picks it up (no `test-all.sh` edit required).

## Files to Edit

- **Create** `plugins/soleur/test/observability-schema-parity.test.ts` — the parity guard.
- No other file changes. (`scripts/test-all.sh:196` already runs `bun test plugins/soleur/` recursively → auto-discovers the new `.test.ts`.)

## Files to Create

- `plugins/soleur/test/observability-schema-parity.test.ts`

## Open Code-Review Overlap

None. (Checked open `code-review` issues touching `plugins/soleur/test/` schema surfaces at plan time; #4133 is itself the only tracker for this surface.)

## Observability

Skip — this plan's only Files-to-Edit is a new test file under `plugins/soleur/test/`, which is NOT in the Phase 2.9 trigger set (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`) and introduces no infrastructure surface. Pure test addition over committed docs → Observability gate skips silently.

## Architecture Decision (ADR/C4)

None. No ownership/tenancy boundary, substrate, resolver/trust boundary, or ADR reversal. A drift-guard test over existing documentation makes no architectural decision — a competent engineer reading the existing ADR/C4 corpus is not misled by this change. Skip.

## Domain Review

**Domains relevant:** none

No cross-domain implications — internal engineering/tooling change (a test-suite drift guard). No UI-surface file in Files-to-Create/Edit; Product/UX gate does not fire.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/test/observability-schema-parity.test.ts` exists and passes: `bun test plugins/soleur/test/observability-schema-parity.test.ts` exits 0.
- [ ] Canonical extraction yields exactly 5 fields `{liveness_signal, error_reporting, failure_modes, logs, discoverability_test}` from `plan/SKILL.md §2.9`.
- [ ] Template block-walk finds exactly 3 `## Observability` yaml blocks in `plan-issue-templates.md`, each top-level-key set equal to canonical.
- [ ] `deepen-plan §4.7` field enumeration set-equals canonical.
- [ ] `AGENTS.core.md` rule line asserts `(5 fields)` count parity + `discoverability_test` + WITHOUT-SSH invariant.
- [ ] RED evidence captured in PR body: renaming any one field name in any single surface makes the test fail with a message identifying the surface.
- [ ] `bun test plugins/soleur/` auto-discovers and runs the new test (no `scripts/test-all.sh` edit).

## Test Scenarios

- Rename `logs` → `log_output` in MORE template only → FAIL (template set ≠ canonical).
- Rename `logs` → `log_output` in canonical `plan/SKILL.md` only → FAIL (canonical set ≠ templates & deepen-plan).
- Change `(5 fields)` → `(6 fields)` in `AGENTS.core.md` → FAIL (count parity, `6 !== canonical.length`).
- Drop one of the 3 template blocks → FAIL (block count `!== 3`).
- Consistent rename across ALL surfaces → PASS (a coordinated rename is not drift — correct behavior).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6. This plan's section is filled (threshold: none, with reason).
- **Block-walk, not hardcoded blocks:** the template surface must be extracted by walking every `## Observability` yaml block (asserting the count), not by hardcoding 3 line-ranges — otherwise a re-ordered or added template silently escapes the guard (drift-guard-must-directory-walk pattern).
- **Surface 4 is count-parity only:** do NOT try to assert the 5 names against `AGENTS.core.md` — they are intentionally absent there (rule-budget byte cap). Asserting names would false-fail a correct file.
- **Absence/count grep trap:** the `AGENTS.core.md` assertion derives `(${CANONICAL.length} fields)` from canonical length, not a hardcoded `5` — so it stays correct if the schema legitimately grows.
