---
feature: affected-parallel-test-gate
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [9307, 8231, 9306]
brainstorm: knowledge-base/project/brainstorms/2026-09-30-affected-parallel-test-gate-brainstorm.md
status: draft
created: 2026-09-30
---

# Spec — Affected-only, parallel test gate for Soleur users and the Soleur repo

## Problem Statement

The pre-ship gate over-selects unrelated suites and runs them serially. A reporting session hit 229 suites and >30 min on a contended machine, then stopped the gate and relied on CI. Measured 2026-09-30: a 3-file markdown-only diff selects 306 suites (139 derived, 49 declared, 115 always-on) with no fallback. Separately, the plugin ships no test gate: `work` / `ship` / `review` call the repo-local `scripts/test-all.sh`, so Soleur users' repos get neither affected selection nor parallelism.

## Goals

- G1. Docs-only and knowledge-base-only diffs in the Soleur repo stop selecting broad suite sets; the selected count for a markdown-only diff falls to the always-on floor plus true consumers.
- G2. A plugin-shipped gate script works in any repo: detects the stack, selects affected tests natively, runs them with native parallel workers, and reports `ran X of N, skipped Y`.
- G3. A repo-level override file lets any project declare global paths that force run-all and a custom test command.
- G4. A budget stops the gate cleanly when over time or suite-count, and ship proceeds only when a CI test workflow is detected.
- G5. Unblock #8231's parallel scheduler for the Soleur bash runner once its green-baseline precondition holds.

## Non-Goals

- A custom affected-test engine. Native runner selection only.
- Bundling third-party tools (invoke what the user has installed).
- Any telemetry on test selection.
- Removing CI as the authoritative merge gate.

## Functional Requirements

- FR1. Track 1: identify which `edge:derived` / `edge:declared` edges pull suites for a knowledge-base-only diff; narrow them without dropping a true consumer, and prove it with a before/after `--print-affected-set` count.
- FR2. Track 2: ship a script under `plugins/soleur/` with a stable contract (selected set, reason, fallback reason) and adapters for JS/TS (vitest/jest), Python (pytest, xdist), Go, and nx/turbo.
- FR3. `work`, `ship` and `review` call the script when the repo has no `scripts/test-all.sh`; a repo-local runner remains the override.
- FR4. An undetectable stack, unknown base ref, or empty selection falls back to the project's full test command with a loud "not narrowed" note. Zero selected tests is refused, never green.
- FR5. Output and PR-body wording use "affected-suite gate passed", never "tests verified".
- FR6. Track 3: re-verify #8231's green-baseline precondition and per-suite isolation proof before any parallel bash-suite execution.

## Technical Requirements

- TR1. Fail toward coverage on every uncertainty path.
- TR2. Parallelism comes from the native runner (workers, xdist, `-p`); no `xargs -P` over the bash suite loop until track 3's isolation proof lands.
- TR3. Re-measure contention on the target host; ADR-133's verdict does not transfer between machines.
- TR4. Stay inside the skill description word budget (`SKILL_DESCRIPTION_WORD_BUDGET`); extend `work`/`ship` plus a shared reference rather than adding a skill unless unavoidable.
- TR5. Record the cross-repo decision as an ADR extending ADR-242.

## Sequencing

Three PRs under umbrella #9307: (1) Soleur-repo over-selection fix, (2) plugin-generic gate, (3) #8231 parallel scheduler. Track 3 may need its own brainstorm and must not block 1-2.

## Open Questions

See the brainstorm's Open Questions: the reporter's fallback arm, the edge responsible for docs-only over-selection, budget defaults, override-file schema, cloud-workspace scope, acceptable escape rate, and #8231's precondition status.
