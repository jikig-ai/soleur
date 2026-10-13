---
feature: ci-eval-harness-backstop
lane: single-domain
brand_survival_threshold: single-user incident
status: draft
issue: 5703
date: 2026-06-29
branch: feat-ci-eval-harness-backstop
pr: 5721
brainstorm: knowledge-base/project/brainstorms/2026-06-29-ci-eval-harness-backstop-brainstorm.md
---

# Spec: CI backstop for gated classifier-skill edits

## Problem Statement

The v1 validation gate (#5702/#5701) wires eval-harness verification into `compound`,
covering only compound-authored edits to a gated classifier block. The deterministic
projection-freshness round-trip (`extract-block.test.sh`) already runs on **every PR**
via `ci.yml:375` → `scripts/test-all.sh:186` (which globs
`plugins/soleur/skills/*/test/*.test.sh`), so a manual edit that forgets to regenerate
the projection already fails CI.

The residual bypass is **registry drift**: nothing enforces that the set of
`eval-gate:block:<id>:start` markers in source files matches the `block_id` entries in
`gated-skills.json`, and the round-trip test's target list is **hardcoded**
(`for target in go-routing ticket-triage`). Adding or renaming a gated classifier
without wiring its registry entry leaves its projection/eval coverage silently
unchecked — the exact "edit bypasses the gate" class #5703 exists to close.

## Goals

- Enforce bidirectional parity between `eval-gate:block` markers and
  `gated-skills.json` as a deterministic, no-API CI check.
- Make `extract-block.test.sh` registry-driven so new registry entries auto-extend
  round-trip coverage.
- Reuse the existing `scripts` test shard — no new workflow, no API spend in CI, no
  branch-protection change.

## Non-Goals

- **No API-spending eval in CI** (operator decision this session). The semantic
  corpus-regression eval stays a manual/opt-in local run.
- **No new dedicated workflow** (`eval-harness-gate.yml`) — the existing per-PR
  `scripts` shard already enforces the round-trip; a named workflow would be cosmetic.
- **No changes to `eval-gate.cjs` runtime gate semantics** or to compound wiring.
- **No branch-protection / required-check API mutation.**

## Functional Requirements

- **FR1 — Registry-completeness test (new).** Add a deterministic `*.test.sh` under
  `plugins/soleur/skills/eval-harness/test/` asserting: (a) every registry entry's
  `block_start_marker`/`block_end_marker` is present in its named `source_file`; (b)
  every `eval-gate:block:<id>:start` marker found across source files (excluding the
  eval-harness skill's own `SKILL.md`/`README.md` prose) has a matching `block_id` in
  `gated-skills.json`. Fail-closed (non-zero exit) with a remediation message naming the
  fix (`add the block to gated-skills.json` / `run gen-skill-prompt.cjs --all`).
- **FR2 — Registry-driven round-trip.** Refactor `test/extract-block.test.sh` to derive
  its target loop and projected-prompt paths from `gated-skills.json` (`block_id` +
  `projected_prompt_path`) instead of the hardcoded `for target in go-routing
  ticket-triage` and inline ternary. Coverage must remain ≥ current (both existing
  targets still tested).
- **FR3 — Free discovery.** Both tests must be discovered and run by the existing
  `scripts/test-all.sh` `scripts`-shard glob; no `ci.yml` edit required.

## Technical Requirements

- **TR1 — No new runtime deps.** Use stock bash + node (`gated-skills.json` parsed via
  `node -e`/existing harness helpers), consistent with the other `eval-harness/test/*.test.sh`.
- **TR2 — Deterministic, no live LLM / no API**, per `cq-test-fixtures-synthesized-only`
  and the harness test conventions (SKILL.md "Tests" section).
- **TR3 — Marker-scan exclusion** correctly omits files that document the marker syntax
  (`eval-harness/SKILL.md`, `eval-harness/README.md`) to avoid false positives.
- **TR4 — CI quality gate.** New behavior covered by the test itself (the test *is* the
  feature); add a failing-case assertion (synthetic drift) per `cq-write-failing-tests-before`.

## Acceptance Criteria

- AC1: With the registry and markers in sync (current state), both tests pass under
  `bash scripts/test-all.sh scripts`.
- AC2: Removing a `gated-skills.json` entry while leaving its source marker → FR1 test
  fails with the remediation message.
- AC3: Adding a `eval-gate:block:foo:start` marker to a source file with no registry
  entry → FR1 test fails.
- AC4: The refactored `extract-block.test.sh` still fails on a stale projection (existing
  round-trip behavior preserved) and now covers any registry target without code edits.
