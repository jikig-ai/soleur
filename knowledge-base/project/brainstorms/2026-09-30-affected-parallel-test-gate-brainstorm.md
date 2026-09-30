---
title: Generic affected-test + parallel gate (plugin users and the Soleur repo)
date: 2026-09-30
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: stop running unrelated suites, run in parallel — for Soleur users too

## What We're Building

A parallel session reported its pre-ship gate "ran serially on a contended machine and over-selected 229 mostly unrelated suites" (>30 min; the relevant vitest projects had already passed; the operator stopped it and let CI be the authoritative gate). Three tracked deliverables, in order:

1. **Soleur-repo over-selection fix.** Remove the false-positive `test` substring edge, move knowledge-base-only readers out of the always-on set into declared subtree edges, and make the selection observable (a receipt that shows what the current diff selects, not just classes). [Reframed during planning; the original "docs-only diffs pull ~190 suites" reading was a misread receipt.]
2. **Plugin-generic gate.** A plugin-shipped, stack-detecting script that `work` / `ship` / `review` call in any repo: native affected selection + native parallel workers, a repo-level override file, a budget that defers to CI, and a printed "ran X of N, skipped Y" report.
3. **Unblock #8231** (parallel scheduler for the Soleur bash runner), gated on its green-baseline precondition.

## Verified Findings (premise probe)

- **Already shipped:** ADR-242 (accepted 2026-09-18, amended 2026-09-29) makes local `scripts/test-all.sh` default to `--affected` = diff-derived suites + `ALWAYS_ON_SUITES` ratchets, falling back to FULL on `runner-changed` / `undecidable-diff` / `index-missing` / `force-all`. So "avoid unrelated suites" is not greenfield for the Soleur repo.
- **Measured on this branch (2026-09-30), corrected during planning:** `bash scripts/test-all.sh --print-affected-set` prints each registration's CLASS (`edge:derived` / `edge:declared` / `always_on`), NOT what the diff selects — `_affected_emit_receipt` (`scripts/test-all.sh:2477-2481`) never reads `_diff_names`; the diff is applied later by the pre-pass (`:2814-2819`, `_diff_touches`). An earlier version of this bullet read the receipt as a selection ("306 selected") and was wrong. Measured selection for a knowledge-base-only diff: **145 `always_on` (always selected) plus ~5 edge suites**, all 5 via one false-positive edge: the bare `test` token from `bun test <file>` becomes a substring edge (`_affected_derive` catch-all `:2328-2333`, matched by `_diff_touches` `:2015`) that hits any diff path containing "test". 18 suites with slow edge walks were unmeasured. The `ALWAYS_ON_SUITES` array has 145 entries (one research agent's "547" was a wrong count).
- **Local execution is serial by design.** `test-all.sh` has no local parallelism flags. In-script `xargs -P` was rejected in the #3672 brainstorm (module-level `process.env.WORKSPACES_ROOT`, repo-root `_site/` rebuild races, port collisions). #8322's spec reframed parallelism to CI/`--full`; #8231 is open, `priority/p3-low`, blocked on a green-baseline precondition (its Phase 0 measured a ~3.2x ceiling). ADR-133's advisory lock serializes sibling worktrees but proceeds on timeout.
- **The plugin ships no test gate.** `work` / `ship` / `review` / `grok-pre-push-gate.sh` all call the repo-local `scripts/test-all.sh`. Soleur users' repos have no equivalent, and no `--changed` / `--related` / `--findRelatedTests` guidance exists under `plugins/soleur`. No prior art for project-agnostic selection.

## Key Decisions

| Decision | Choice |
|---|---|
| Scope | Plugin-generic gate **and** Soleur-repo tuning |
| Parallelism | Native runner workers for users' repos (vitest/jest, pytest `-n auto`, go). For the Soleur bash runner: **unblock #8231** (operator override of the prior "CI only" reframe — see Risks) |
| Stacks, day one | Detect-anything + repo override file: JS/TS, Python, Go, nx/turbo adapters, plus an override file (global-paths that force run-all, custom command) |
| Over-budget behavior | Wall-clock / suite-count budget. Past it, stop cleanly, report "ran X of N, skipped Y", and let ship proceed only if a CI test workflow is detected. With no CI, run the scoped set to completion |
| Sequencing | Three tracked PRs, 1 -> 2 -> 3, under one umbrella issue |
| Wording | Gate output and PR bodies say "affected-suite gate passed", never "tests verified" (CLO) |
| Delivery form | A shipped script with a testable contract (selected set, reason, fallback reason), not skill prose (CTO) |
| Productize candidate | The plugin-generic gate script itself (recurs every ship in every user repo) |

## User-Brand Impact

- **Artifact:** the pre-ship test gate (`work` / `ship` / `review` phases) and the new plugin-shipped affected-test script.
- **Vector:** a false-narrow selection reports green while a broken change ships, or the gate silently reports success on an undetected stack / empty selection.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

Serial by default confirmed; recommends a shipped stack-detecting script (contract: selected set + reason + fallback reason) over skill prose, native-runner parallelism rather than a custom scheduler, a "global paths -> run all" override, and refusing vacuous zero-selection. Fail-toward-coverage risks: import-graph selectors miss config/fixtures/codegen/cross-package edges; undetectable stack or base ref must fall back to the full run, never to zero tests. Recommends an ADR extending ADR-242 across the repo boundary.

### Product (CPO)

New product surface, not tuning, for plugin users. Recommended option A (posture only) now and B (gate contract + adapters) later; the operator chose the fuller scope. Success metrics: over-selection ratio, wall time under contention, escapes to CI (guardrail). CI-as-authoritative should be conditional on a detected CI test workflow, since many solo founders have none. File as Phase 4 issue; no roadmap row until a second tester reports the friction.

### Legal (CLO)

No legal implications on telemetry, third-party licensing (invoking user-installed tools is fine; bundling needs a license check) or data. Only point: honest labeling — "affected-suite gate passed", not "tests verified" — and keep "CI remains the authoritative merge gate".

## Risks / Tensions

- **Overrides a recorded decision.** Unblocking #8231 reverses the "parallel is CI-only" reframe in the #8322 spec and the #3672 sharp edges. Its green-baseline precondition and per-suite isolation proof must be re-satisfied; track 3 may need its own brainstorm and should not block tracks 1-2.
- **A narrow gate that passes but ships a break** costs more trust than a slow gate. Every path fails toward coverage and prints what it skipped.
- **Skill description budget** is capped (`SKILL_DESCRIPTION_WORD_BUDGET`); prefer extending `work`/`ship` plus a shared reference over a new skill.
- **ADR-133 caveat:** the tmpfs-contention verdict was measured on one workstation and does not transfer to other hosts; re-measure for any new parallelism.

## Open Questions

- Which fallback arm fired in the reporter's 229-suite session (its `AFFECTED_FALLBACK` / `AFFECTED_SCOPE` lines are the deciding evidence)? On this branch no fallback fired.
- [Resolved in planning] The edge question: no KB-consumer edge over-selects; the observed selection was the always-on floor (145) plus the `test` substring edge (5). The reporter's 229 is still unexplained (their diff is unknown).
- Budget defaults (seconds / suite count) and the override file's name and schema.
- Whether cloud workspaces (which clone the user's repo) are in scope alongside the self-hosted CLI plugin.
- Acceptable escape rate to CI per 100 ships, and a measured baseline from a non-Soleur repo (none exists).
- Track 3: does #8231's green-baseline precondition hold today?

## Session Errors

- A research agent reported `ALWAYS_ON_SUITES` = 547 entries; re-derived as 145 (`awk` over the array and `source` + `${#ALWAYS_ON_SUITES[@]}` agree).
- I read `--print-affected-set` receipts (class per registration) as the diff's selection and told the operator "306 selected". Corrected in planning from a research agent's harness plus a direct read of `test-all.sh:2477-2481` and `:2814-2819`: selection for a KB-only diff is ~150. Prevention: before quoting a tool's output as a measurement, confirm what the output describes (class vs. selection) by reading the code that produces it.
