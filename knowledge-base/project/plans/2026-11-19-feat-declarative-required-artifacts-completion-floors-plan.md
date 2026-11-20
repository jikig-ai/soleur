---
title: "feat: declarative required-artifact completion floors per pipeline phase (#12527)"
date: 2026-11-19
slug: declarative-required-artifacts-completion-floors
branch: feat-12527-pipeline-phase-required-artifacts
issue: 12527
lane: cross-domain
type: feat
priority: P1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Implement a deterministic, declarative completion floor system for Soleur's orchestration pipeline (#12527, parent epic #12533). Pipeline advancement currently relies on prose continuation gates (`## Work Phase Complete`), subagent narrative summaries (`## Session Summary`), and a terminal `<promise>DONE</promise>` marker; when an agent hallucinates completion or skips an artifact, the omission propagates downstream unnoticed.

This plan ships four layers:

1. **TypeScript SSoT** (`plugins/soleur/lib/completion-floors.ts`): a declarative registry mapping pipeline phases (`plan`, `work`, `review`, `qa`, `ship`, `postmerge`) to verifiable required-artifact checks.
2. **Portable verifier** (`plugins/soleur/scripts/completion-floor.sh`): a deterministic shell CLI evaluating artifact presence and structural validity across all seven harnesses.
3. **Continuation gate integration**: machine-enforced pre-advance gates in `one-shot/SKILL.md`, `work/SKILL.md`, and `ship/SKILL.md` replacing hand-rolled checks.
4. **Bounded self-healing retry (1 attempt)**: on a missing artifact, the orchestrator injects an actionable diagnostic prompt naming the missing deliverable, giving the phase one chance to produce it before halting fail-closed.

## Research Insights

**Premise Validation (Phase 0.6).** Issue #12527 OPEN (verified). Parent epic #12533. Draft PR #12808 OPEN on this branch. Brainstorm at `knowledge-base/project/brainstorms/2026-11-16-declarative-required-artifacts-completion-floors-brainstorm.md`. No cited blocker already resolved. No external premises stale.

**Property List (Phase 0.6b).**

1. Pipeline phases cannot advance without their required on-disk artifacts present and structurally valid.
2. The floor definition lives in one place (`completion-floors.ts`) so skill prose, scripts, and tests cannot drift.
3. The verifier runs identically on all seven harnesses (no Claude-only hooks required).
4. A missing artifact produces an actionable diagnostic naming the missing deliverable, with exactly one retry before fail-closed halt.
5. Verification inspects filesystem/git truth, never agent self-attestation (ADR-324).
6. Script failure (exit 1/2/127) fails closed (`unknown fires the gate`).

**Cut List (Phase 0.6b).** None — every proposed mechanism buys a distinct property not already covered by an existing repo mechanism. `technical-ruling-gate.sh` and `pipeline-tally.sh` are close precedents but neither encodes per-phase artifact floors.

**Institutional learnings applied.**
- #3937: subagent summaries are statements of intent, not fact → floors inspect filesystem reality.
- #3827: verify structural anchors (`## Acceptance Criteria`), not fragile headings.
- ADR-324: orchestrator executes deterministic script and reads stdout receipt (`SOLEUR_*`).
- Fail-closed rule: any script failure fails closed.
- #6325/#6320: mechanical floors essential to prevent phase inlining.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Reality on `origin/main` (2026-11-19) | Plan response |
|---|---|---|
| `plugins/soleur/lib/completion-floors.ts` does not yet exist | Confirmed absent (glob) | Create new file |
| `plugins/soleur/scripts/completion-floor.sh` does not yet exist | Confirmed absent (find) | Create new file |
| `one-shot/SKILL.md`, `work/SKILL.md`, `ship/SKILL.md` exist | Confirmed present | Edit to integrate gate |
| `technical-ruling-gate.sh` precedent exists | Confirmed present | Mirror its receipt/exit-code contract |

## Files to Create

- `plugins/soleur/lib/completion-floors.ts` — declarative registry (SSoT) of phase → required artifact checks, plus types and a `checkFloor(phase, ctx)` helper.
- `plugins/soleur/scripts/completion-floor.sh` — portable CLI; args: `--phase <phase> [--root <path>]`; emits `SOLEUR_FLOOR_GATE phase=<p> status=pass|fail missing=<list>`; exit 0 on pass, 1 on fail, 2 on usage/unknown.
- `plugins/soleur/scripts/completion-floor.test.sh` — fixture-based tests mirroring `pipeline-tally.test.sh` conventions.
- `knowledge-base/engineering/architecture/decisions/ADR-329-completion-floors.md` — new ADR (provisional ordinal; re-verify at ship).

## Files to Edit

- `plugins/soleur/skills/one-shot/SKILL.md` — replace hand-rolled continuation checks with `completion-floor.sh --phase` calls at each phase boundary; add bounded self-healing retry (1 attempt) on fail.
- `plugins/soleur/skills/work/SKILL.md` — gate work-phase advance on `--phase work`.
- `plugins/soleur/skills/ship/SKILL.md` — gate ship-phase advance on `--phase ship`.
- `plugins/soleur/test/components.test.ts` — register new script/test if component inventory is enumerated (verify during work).

## Implementation Phases

### Phase 1 — SSoT (`completion-floors.ts`)
Define `Phase = 'plan' | 'work' | 'review' | 'qa' | 'ship' | 'postmerge'`. Define `ArtifactCheck` with `id`, `description`, `predicate: (ctx) => boolean | Promise<boolean>`, `remediation` (actionable prompt text). Define `FLOORS: Record<Phase, ArtifactCheck[]>`. Export `checkFloor(phase, ctx)` returning `{ ok, missing: string[] }`.

Floor definitions (structural anchors, not fragile headings):
- `plan`: plan file exists under `knowledge-base/project/plans/` for branch; contains `## Acceptance Criteria`; `tasks.md` exists; zero out-of-scope edits (git diff stat check).
- `work`: commit count >= 1 on branch since base; clean working tree (`git status --porcelain` empty).
- `review`: open `code-review` issues == 0 (via `gh issue list --label code-review --state open`); attestation trailers present in latest commit.
- `qa`: test scenarios artifact present OR `no-test-scenarios` marker; docs-only changes exempt test diff.
- `ship`: `gh pr view --json state` reports `MERGED`.
- `postmerge`: deploy health probe passes (reuse observability discoverability command).

Predicates must be pure-ish and accept a `ctx` with `root`, `branch`, `baseRef`.

### Phase 2 — Verifier (`completion-floor.sh`)
Portable bash. Parse `--phase`, `--root` (default cwd/git root). Resolve repo root via `git rev-parse --show-toplevel`. For each check in the phase's embedded list (mirror TS definitions; keep in sync via a generated comment header), evaluate. Emit one `SOLEUR_FLOOR_GATE phase=<p> status=pass|fail missing=<comma-list>` line to stdout. Exit codes: 0 pass, 1 fail (missing artifacts), 2 usage/unknown phase. Fail-closed: any internal error → exit 2 with `status=fail`.

The script must not depend on Node/TS runtime (portability across harnesses). Keep check list duplicated but documented as mirror of `completion-floors.ts`; add a drift lint in tests (grep that both files list the same check ids).

### Phase 3 — Continuation gate integration
In `one-shot/SKILL.md`, `work/SKILL.md`, `ship/SKILL.md`: replace prose continuation gates with:
```
bash plugins/soleur/scripts/completion-floor.sh --phase <phase>
```
On non-zero exit, parse `missing=` and inject bounded self-healing retry: re-invoke the phase's producer with a diagnostic prompt naming missing deliverables; on second failure, halt fail-closed with the receipt.

### Phase 4 — Bounded self-healing retry
Implement in skill prose (and a small helper `completion-floor-retry.sh` if needed): exactly one retry; on retry failure emit `SOLEUR_FLOOR_HALT phase=<p> reason=<missing>` and stop. No infinite loops.

### Phase 5 — Tests
`completion-floor.test.sh` with fixtures: pass case, fail case (missing artifact), unknown phase (exit 2), fail-closed on git error. Mirror `pipeline-tally.test.sh` structure.

## Acceptance Criteria

- [ ] `plugins/soleur/lib/completion-floors.ts` exists and exports `FLOORS`, `checkFloor`, `Phase`.
- [ ] `plugins/soleur/scripts/completion-floor.sh` exists, executable, exits 0/1/2 per contract, emits `SOLEUR_FLOOR_GATE` receipt.
- [ ] All six phases (`plan`, `work`, `review`, `qa`, `ship`, `postmerge`) have floor definitions.
- [ ] `completion-floor.sh --phase bogus` exits 2.
- [ ] A missing artifact yields exit 1 and `missing=` lists it.
- [ ] `one-shot/SKILL.md`, `work/SKILL.md`, `ship/SKILL.md` invoke the verifier (grep check).
- [ ] Bounded retry documented: exactly one retry then fail-closed halt.
- [ ] Test script passes.
- [ ] Clean-room attestation trailer present in PR.

## Scope Check

### Ask Mapping

| Ask (quoted) | Mapped item | Status |
|---|---|---|
| "completion-floors.ts SSoT" | `plugins/soleur/lib/completion-floors.ts` (Phase 1) | mapped |
| "completion-floor.sh verifier" | `plugins/soleur/scripts/completion-floor.sh` (Phase 2) | mapped |
| "continuation gate integration" | Edits to `one-shot/SKILL.md`, `work/SKILL.md`, `ship/SKILL.md` (Phase 3) | mapped |
| "bounded self-healing retry" | Phase 4 retry logic | mapped |

### Plan-Item Provenance

| Plan item | Provenance | Justification |
|---|---|---|
| `completion-floors.ts` | asked | core deliverable |
| `completion-floor.sh` | asked | core deliverable |
| `completion-floor.test.sh` | inferred | test coverage for verifier; needed for regression safety |
| ADR-329 | inferred | architecture decision record; standard for new contract |

### Split Assessment

- Files to edit: 4 (3 SKILL.md + components.test.ts)
- Files to create: 4
- Recommendation: single PR (cohesive feature)

## User-Brand Impact

**If this lands broken, the user experiences:** pipeline phases advancing past incomplete work, producing phantom PRs/merges/deployments with no on-disk artifacts.

**If this leaks, the user's data/workflow/money is exposed via:** N/A (local orchestration, no data surface); the risk is false-green completion claims corrupting downstream state.

**Brand-survival threshold:** single-user incident.

## Domain Review

**Domains relevant:** Engineering

### Engineering
**Status:** reviewed
**Assessment:** Script-backed floor gate + TS SSoT; ADR-324 invariant; multi-harness parity; fail-closed. No user-facing legal changes.

## Observability

```yaml
liveness_signal:
  what: completion-floor.sh exit code + SOLEUR_FLOOR_GATE receipt on stderr/stdout
  cadence: per phase boundary
  alert_target: pipeline halt (fail-closed)
  configured_in: plugins/soleur/scripts/completion-floor.sh
error_reporting:
  destination: stdout/stderr receipt
  fail_loud: yes
failure_modes:
  - mode: missing artifact
    detection: SOLEUR_FLOOR_GATE status=fail missing=<list>
    alert_route: orchestrator retry then halt
  - mode: script error
    detection: exit 2
    alert_route: fail-closed halt
logs:
  where: stdout/stderr
  retention: ephemeral
discoverability_test:
  command: bash plugins/soleur/scripts/completion-floor.sh --phase plan
  expected_output: "SOLEUR_FLOOR_GATE"
  credentials_required: none
```

## Guard Contract

### Guard 1 — completion floor gate
**Property.** A pipeline phase cannot advance unless all its declared required artifacts are present and structurally valid on disk.

**Assembly.** `completion-floors.ts` (SSoT definitions) + `completion-floor.sh` (runtime evaluator) + skill continuation gates in `one-shot/SKILL.md`, `work/SKILL.md`, `ship/SKILL.md`. Chokepoint: the script's exit code consumed by the orchestrator.

**Mutation matrix.**

| Mutation | Expected | Notes |
|---|---|---|
| Delete a required artifact (e.g., plan file) | RED (exit 1) | drives guard red on missing |
| Add second artifact after compliant first | still PASS | per-member, not count-only |
| Remove all checks for a phase | RED (lint) | assembly drift caught by test |
| Corrupt structural anchor (`## Acceptance Criteria` → `## Overview`) | RED | structural anchor, not heading presence |
| Invoke with unknown phase | exit 2 | fail-closed usage |
| Force script error (unreadable root) | exit 2 | fail-closed |

**Harness rows.** Test must include at least one must-PASS input differing from canonical (docs-only change exempts test diff) and one must-RED input mutating the guard's own dispatch (script exits 0 while artifacts missing → test fails).

**Anchor.** Floor definitions in TS SSoT; script mirrors. Drift lint asserts check-id sets match between the two files.

## Architecture Decision (ADR/C4)

### ADR
Create ADR (provisional ordinal — re-verify at ship) documenting the declarative completion floor contract, multi-harness portability, and fail-closed disposition.

### C4 views
No new external actors/systems; internal tooling. C4 impact: none beyond existing plugin/tooling container (verified by reading model.c4/views.c4/spec.c4 for "completion"/"floor"/"pipeline" — no new elements required).

## Clean-Room Provenance

Provenance: Independent clean-room re-implementation of declarative artifact completion floors.
Zero source code, AST schemas, prompts, or tests read, inspected, or copied from hmuhlestein/HephaestusNG (AGPL-3.0).
No AGPL notice applies.
