---
feature: skill-eval-gate
lane: single-domain
brand_survival_threshold: none
plan: knowledge-base/project/plans/2026-06-29-feat-skill-eval-gate-plan.md
---

# Tasks: Validation-Gated Classifier-Skill-Edit Acceptance Loop

## Phase 1 — Foundation: delimited block + mechanical projection
- [ ] 1.1 Wrap the `/go` routing table in `plugins/soleur/commands/go.md` with `<!-- eval-gate:block:go-routing:start -->` … `:end` markers (no behavior change).
- [ ] 1.2 Wrap the P-level rubric in `plugins/soleur/agents/support/ticket-triage.md` with `eval-gate:block:ticket-triage` markers.
- [ ] 1.3 Write `scripts/extract-block.cjs` — deterministic block projection (source + markers → block text).
- [ ] 1.4 Regenerate `prompts/go-skill.txt` + `prompts/triage-skill.txt` as projections of their blocks; document the mechanical link.
- [ ] 1.5 Write `gated-skills.json` registry (source_file, markers, target, projected_prompt_path) for both targets.

## Phase 2 — Verdict engine (pure, testable)
- [ ] 2.1 Write `scripts/verdict.cjs` — pure `computeVerdict(current, candidate, targetTask, {epsilon, aggregation})` (TR-VERDICT, TR5). No I/O.
- [ ] 2.2 Write `test/verdict.test.cjs` with recorded promptfoo JSON fixtures: accept, corpus-regress reject, target-fail reject, ε-boundary (AC2).

## Phase 3 — Gate orchestrator
- [ ] 3.1 Write `scripts/eval-gate.cjs` — `--check`, `--candidate-file`, `--target-task`, `--repeat`, `--append-on-accept`, `--dry-run`. Skill-arm-only promptfoo run with `--output`; calls computeVerdict; prints verdict JSON.
- [ ] 3.2 API-cost disclosure on non-dry runs (TR3); fail-closed non-zero exit (TR4).
- [ ] 3.3 `--append-on-accept` appends a synthesized golden task; reject real-data-shaped input (TR2).

## Phase 4 — Proposer integration
- [ ] 4.1 `heal-skill/SKILL.md` apply step (primary hook): `--check` → run gate → reject = don't apply + log buffer + surface; read buffer before re-proposing (dedupe key source_file+target-task-id). Prose-only / no hook-hierarchy displacement (FR6).
- [ ] 4.2 `compound-capture/SKILL.md` Step 8: `--check` guard for the rare block-touching learning; on reject don't stamp `synced_to`.
- [ ] 4.3 `TR-HEADLESS`: in HEADLESS_MODE, skip-gate-and-defer (log note; #5703 catches).
- [ ] 4.4 Add `.claude/.skill-edit-rejections.jsonl` to `.gitignore`.

## Phase 5 — Docs + architecture
- [ ] 5.1 `eval-harness/SKILL.md`: document gate mode + projection; REMOVE the fixture-sync "no mechanical link" caveat.
- [ ] 5.2 `eval-harness/README.md`: gate-mode reproduce + projection-regen command.
- [ ] 5.3 Create ADR-068 via `/soleur:architecture` (Decision + projection-precondition + Alternatives-Considered).
- [ ] 5.4 `model.c4`: add `evalharness` component + `compound -> evalharness` + `healskill -> evalharness` edges. `views.c4`: include `platform.plugin.evalharness`.

## Phase 6 — Verify
- [ ] 6.1 `verdict.test.cjs` green (AC2); AC4 round-trip (generated projection == committed) passes.
- [ ] 6.2 `npx promptfoo validate config` passes both configs (AC8); new `.cjs` lint/tsc clean.
- [ ] 6.3 `c4-code-syntax.test.ts` + `c4-render.test.ts` pass (AC7).
- [ ] 6.4 `eval-gate.cjs --dry-run` prints skill-arm-only API estimate, no API call (AC1).
- [ ] 6.5 File the cross-operator-buffer deferred issue.
