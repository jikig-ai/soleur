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

The pre-ship gate over-selects unrelated suites and runs them serially. A reporting session hit 229 suites and >30 min on a contended machine, then stopped the gate and relied on CI. Measured 2026-09-30 (corrected in planning): a knowledge-base-only diff selects ~150 suites — the 145-entry `ALWAYS_ON_SUITES` floor plus ~5 edge suites pulled by a false-positive `test` substring edge. (`--print-affected-set` prints classes, not the diff's selection.) The reporter's 229 is unexplained; their diff is unknown. Separately, the plugin ships no test gate: `work` / `ship` / `review` call the repo-local `scripts/test-all.sh`, so Soleur users' repos get neither affected selection nor parallelism.

## Goals

- G1. Docs-only and knowledge-base-only diffs in the Soleur repo select only true consumers: the false-positive `test` edge is removed, KB-only readers move from the always-on set to declared subtree edges, and a print mode shows what the CURRENT diff selects.
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

- FR1. Track 1: remove the bare-command-word edge (`test`) that `_affected_derive` adds for `bun test <file>`; move KB-only always-on readers to declared subtree edges; add a diff-aware print mode; prove no true consumer is dropped with a property test (every suite reading a real repo KB path is always-on or carries a covering KB edge).
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

## Planning Decisions (2026-09-30)

- Adapters: all four (JS/TS, Python, Go, nx/turbo) per the operator's direction, over the review panel's advice to ship fewer; Go uses a reverse-dependency closure.
- Refusal policy: rc 4 only when tests exist but cannot be run; a repo with no test files gets rc 7 and ship proceeds with a disclosed note.
- Cloud (Devin) handling is in PR 2 scope (identity-based root resolution, bounded shallow deepen, toolchain check).
- PR 3 (#8231) stays in the umbrella behind a go/no-go measurement; PR 2 is independent of PR 1.
- Exit contract: 0 pass / 1 failed / 4 refused / 6 budget deferred to CI / 7 no suite detected. The override file is a committed repo-root `.soleur-test-gate.json`.
