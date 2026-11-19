# ADR-142: Declarative Required-Artifact Completion Floors Per Pipeline Phase

## Status

Accepted

## Context

Soleur's pipeline advancement relies on prose continuation gates (`## Work Phase Complete`), subagent narrative summaries (`## Session Summary`), and a terminal `<promise>DONE</promise>` marker. When an agent hallucinates completion or skips an artifact, the omission propagates downstream unnoticed (issue #12527, parent epic #12533).

## Decision

Introduce a declarative completion-floor system:

1. **TypeScript SSoT** (`plugins/soleur/lib/completion-floors.ts`): `FLOORS: Record<Phase, ArtifactCheck[]>` mapping phases (`plan`, `work`, `review`, `qa`, `ship`, `postmerge`) to verifiable required-artifact checks, plus `checkFloor(phase, ctx)`.
2. **Portable verifier** (`plugins/soleur/scripts/completion-floor.sh`): deterministic bash CLI, `--phase <p> [--root <path>]`, emits `SOLEUR_FLOOR_GATE phase=<p> status=pass|fail missing=<list>`, exit 0/1/2. No Node/TS runtime dependency.
3. **Continuation gate integration** in `one-shot/SKILL.md`, `work/SKILL.md`, `ship/SKILL.md`.
4. **Bounded self-healing retry**: exactly one retry on missing artifact, then fail-closed halt emitting `SOLEUR_FLOOR_HALT`.

Verification inspects filesystem/git truth, never agent self-attestation (ADR-324). Script failure fails closed.

## Clean-Room Provenance

Provenance: Independent clean-room re-implementation of declarative artifact completion floors.
Zero source code, AST schemas, prompts, or tests read, inspected, or copied from hmuhlestein/HephaestusNG (AGPL-3.0).
No AGPL notice applies.
