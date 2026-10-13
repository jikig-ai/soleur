---
date: 2026-06-29
type: feat
feature: skill-eval-gate
lane: single-domain
brand_survival_threshold: none
issue: 5702
pr: 5701
branch: feat-skill-eval-gate
brainstorm: knowledge-base/project/brainstorms/2026-06-29-skill-eval-gate-brainstorm.md
spec: knowledge-base/project/specs/feat-skill-eval-gate/spec.md
revised: 2026-06-29 post-plan-review (block-keyed proposer-agnostic re-scope; see Plan-Review Reconciliation)
---

# Plan: Validation-Gated Classifier-Skill-Edit Acceptance Loop ✨

## Overview

A **block-keyed, proposer-agnostic** verification gate. Each gated classifier skill exposes its
rules as a **delimited block** in the source file (`/go` routing table, ticket-triage rubric). The
eval-harness skill-arm prompt is a **mechanical projection** of that block (extracted, not
hand-copied — this *replaces* the fixture-sync caveat). Any edit that changes a gated block — from
`heal-skill` (primary in-session path), `compound`, or a manual/one-shot edit — must pass a
deterministic before/after eval before it is applied: corpus must not regress AND the targeted case
must pass. Rejected edits are logged to a buffer that the proposer reads before re-proposing.

Borrows SkillOpt's validation-gated acceptance + rejected-edit buffer; skips genetic/Pareto evolution
and autonomous self-editing (NG1–NG3). No new infra, no UI.

## Plan-Review Reconciliation (block-keyed re-scope)

Three plan-reviewers (DHH, Kieran, code-simplicity) surfaced one root flaw and several fixes. Operator
decided the re-scope. Recorded here so /work doesn't re-litigate:

| Finding | Resolution |
|---|---|
| **Kieran P1-1** — skill-arm prompt is a 15-line hand-distilled paraphrase of 84-line `go.md`; "no mechanical link" → gate measures stale prose / a false-accept. | **Mechanical projection.** Wrap classifier rules in `go.md` / `ticket-triage.md` in sentinel markers; `extract-block.cjs` deterministically projects the block into the skill-arm prompt. Kills the fixture-sync caveat. |
| **Kieran P1-3** — `compound` Step 8 appends *commentary bullets*, not classifier-rule edits, so wiring the gate there is theater. | **Proposer-agnostic, block-keyed.** Gate fires on any edit touching a gated block. Primary in-session hook is **heal-skill** (the path that actually edits skill rules); compound Step 8 keeps a hook for the rare block-touching case; #5703 CI backstop is the catch-all for manual/one-shot edits. |
| **Kieran P1-2** — no `--target-task` input but accept rule needs `target_task_passes`. | `eval-gate.cjs --target-task <json\|path>`; evaluate from the arg; append to corpus only on accept (clean baseline). |
| **Kieran P1-4** — verdict+run bundled → AC2 untestable without live API. | Split: thin runner shells `promptfoo --output results.json`; **pure** `computeVerdict()` in `verdict.cjs`. AC2 tests `computeVerdict` against recorded JSON fixtures, zero API. |
| **Kieran P2-1/2-2** — `≥` undefined under `--repeat` noise; `target_task_passes` aggregation unspecified. | Define: aggregate over `model×repeat` samples; `no_regression = candidate_rate ≥ current_rate − ε` (ε = 1 task-equivalent, stated); `target_task_passes = pooled correct-rate ≥ 0.5`. Gate default `--repeat 5`. |
| **Kieran P2-3** — headless auto-apply vs interactive spend gate; gate wastes the baseline arm. | Headless: **skip-gate-and-defer** (log a deferred-verification note; #5703 catches at CI) rather than spend unattended. Gate runs **skill-arm only** (current vs candidate) — baseline arm is irrelevant to the gate. |
| **Kieran P2-4** — C4 id `eval-harness` is invalid (ids are hyphen-free); edge used `evalharness`. | Use `evalharness` consistently (declaration, edge, `views.c4` include). |
| **Kieran P2-5 / DHH+simplicity "buffer is write-only"** — reject path `synced_to` undefined; buffer has no reader. | Buffer **kept** with reader wired: on reject, do NOT stamp `synced_to`; proposer + `/sync` check `.skill-edit-rejections.jsonl` (dedupe key = `source_file` + target-task id) before re-proposing. This is the buffer's consumer — resolves the write-only objection without reversing the brainstorm decision. |
| **DHH+simplicity** — fold `append-target-task.cjs` into the gate. | `eval-gate.cjs --append-on-accept` (TR2 synthesized-only guard preserved). |
| **DHH+simplicity** — `gated-skills.json` for 2 rows. | **Kept** — two consumers (proposer lookup + gate) and #5704 is a near-term grower. |
| **DHH P2** — `single-user incident` + CPO signoff inflated for internal tooling, no user data. | **Downgraded to `none`** (operator decision). Landing broken == today's no-gate status quo; no user data. `requires_cpo_signoff` dropped. |

## Files to Create

- `plugins/soleur/skills/eval-harness/scripts/verdict.cjs` — **pure** `computeVerdict(currentResults, candidateResults, targetTask, {epsilon, aggregation}) → {accept, corpus_regressed, target_task_passes, per_task}`. No I/O, no shell-out. The unit-testable seam (AC2).
- `plugins/soleur/skills/eval-harness/scripts/extract-block.cjs` — deterministic projection: given a source file + block markers, emit the classifier block (used to generate the skill-arm prompt AND to detect "does this edit touch the block?").
- `plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs` — thin orchestrator: `--target`, `--candidate-file <edited-source>`, `--target-task <json|path>`, `--repeat`, `--append-on-accept`, `--check <file>` (lookup-only). Extracts current+candidate blocks → runs promptfoo **skill-arm only** with `--output` → calls `computeVerdict` → prints verdict JSON. Discloses API estimate before spending (TR3). Fail-closed (TR4).
- `plugins/soleur/skills/eval-harness/gated-skills.json` — registry: `{ source_file, block_start_marker, block_end_marker, target, projected_prompt_path }` per gated skill.
- `plugins/soleur/skills/eval-harness/test/verdict.test.cjs` — recorded-promptfoo-JSON fixtures + `computeVerdict` assertions (accept / corpus-regress / target-fail / ε-boundary cases).
- `knowledge-base/engineering/architecture/decisions/ADR-069-validation-gated-classifier-skill-edits.md`.

## Files to Edit

- `plugins/soleur/commands/go.md` — wrap the routing table in `<!-- eval-gate:block:go-routing:start -->` … `:end` markers (no behavior change; the block is now the SSOT the projection reads).
- `plugins/soleur/agents/support/ticket-triage.md` — wrap the P-level rubric in `eval-gate:block:ticket-triage` markers.
- `plugins/soleur/skills/eval-harness/prompts/go-skill.txt` + `triage-skill.txt` — become generated projections of the block (or `file://` the generated file); document that the mechanical link replaces the hand-copy.
- `plugins/soleur/skills/eval-harness/SKILL.md` — document gate mode + block projection; **remove** the "no mechanical link" fixture-sync caveat (now mechanically linked). No `description:` change → budget check N/A.
- `plugins/soleur/skills/eval-harness/README.md` — gate-mode reproduce + projection-regen command.
- `plugins/soleur/skills/heal-skill/SKILL.md` — **primary in-session hook.** In the apply step, if the target edit changes a gated block (`eval-gate.cjs --check`), run the gate; on reject do NOT apply, log to the buffer, and surface the verdict; check the buffer before re-proposing a previously-rejected edit.
- `plugins/soleur/skills/compound-capture/SKILL.md` — Step 8: same gated-block guard for the rare case a routed learning edits a gated block (commentary-bullet edits don't touch the block → `--check` returns not-gated → proceed). On reject: don't stamp `synced_to`.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — add `evalharness = component "eval-harness skill"`; edge `compound -> evalharness` AND `healskill -> evalharness "Gates classifier-block edits"` (if `heal-skill` is modeled; else add it too).
- `knowledge-base/engineering/architecture/diagrams/views.c4` — include `platform.plugin.evalharness`.
- `.gitignore` — add `.claude/.skill-edit-rejections.jsonl`.

## Technical Requirements

- **TR1** — reuse promptfoo configs + `measure-classification.cjs` + `parse-label.cjs`; no measurement fork.
- **TR-PROJECTION** — the skill-arm prompt is a deterministic projection of the source's delimited block (`extract-block.cjs`). "Current" projects from the source on disk; "candidate" projects from the edited source. The fixture-sync caveat is removed because the link is now mechanical. An edit whose diff does not change any gated block → `--check` returns not-gated → proceed (the real ungateable case, per Kieran P3-1).
- **TR-VERDICT** — verdict logic lives in pure `computeVerdict()`; the runner only shells promptfoo and passes results in. No LLM in the verdict (variance lives only in the classifier scores the verdict consumes).
- **TR2** — `--append-on-accept` accepts synthesized fixtures only; reject real-data-shaped input.
- **TR3** — gate discloses API estimate before spending (skill-arm-only ≈ half the full-eval count); honors `--repeat` (gate default 5).
- **TR4** — fail-closed: any gate error → edit NOT applied, error surfaced.
- **TR5** — `accept = (candidate_corpus_rate ≥ current_corpus_rate − ε) && (target_task pooled correct-rate ≥ 0.5)`, ε = one-task-equivalent, aggregation = pooled over model×repeat. Target task evaluated from `--target-task`, appended to corpus only on accept.
- **TR-HEADLESS** — in `HEADLESS_MODE`, proposers skip-gate-and-defer (record a deferred-verification note; #5703 CI backstop catches it) rather than spend unattended.

## Acceptance Criteria

### Pre-merge (PR)
- AC1 — `eval-gate.cjs --check <file>` and `--help`/`--dry-run` run with **no** API call; `--dry-run` prints the API-cost disclosure (skill-arm-only count). Verify: run, paste output.
- AC2 — `verdict.test.cjs` asserts `computeVerdict` against recorded promptfoo JSON: accept (improve+no-regress), reject (corpus regress), reject (target fails), and the ε-boundary case. Zero live API.
- AC3 — `gated-skills.json` lists the two v1 targets; each `source_file` exists (`test -f`) and contains its `block_start_marker`/`block_end_marker`; each `projected_prompt_path` exists.
- AC4 — `extract-block.cjs` projects the `go.md` routing block byte-for-byte into `go-skill.txt` (round-trip test: generated == committed projection).
- AC5 — heal-skill SKILL.md apply step contains the gated-block branch (check → run → reject-don't-apply+log+buffer-read); compound-capture Step 8 has the `--check` guard + "don't stamp synced_to on reject"; both note prose-only / no displacement of the hook-first hierarchy (FR6).
- AC6 — `.gitignore` contains `.claude/.skill-edit-rejections.jsonl`.
- AC7 — ADR-069 exists (Decision + Alternatives-Considered: genetic/Pareto, autonomous optimizer, CI-only-deferred); `model.c4` declares `evalharness` (hyphen-free id) + the edge; `views.c4` includes it; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- AC8 — `npx promptfoo validate config` still passes for both configs after the prompts become projections; new `.cjs` lint/`tsc` clean per repo convention.

### Post-merge (operator)
- None. Gate activates on the next gated-block edit.

## Architecture Decision (ADR/C4)

### ADR
**ADR-069** via `/soleur:architecture`. Decision: classifier-skill rules live in a delimited block
that is the SSOT for both production and the eval projection; edits to that block are validation-gated
(no-regression + target-passes) before applying, proposer-agnostic. **Precondition recorded in the
Decision (per Kieran P3-4):** the gate is only honest while the skill-arm prompt is a mechanical
projection of the block — if the projection link is broken the gate no-ops. Alternatives Considered
(rejected): genetic/Pareto evolution; autonomous unattended optimizer; CI-only gate (deferred #5703).

### C4 views
Read all three `.c4` files. **External actors/systems:** none — internal dev-tooling loop, no human
actor / external vendor / data store enters the model. **Change:** add `evalharness` component;
edges `compound -> evalharness` and `healskill -> evalharness "Gates classifier-block edits"`. Add to
`views.c4` plugin include. Component-view only (no Context/Container change). Validate via the two C4 tests.

### Sequencing
ADR-069 accepted on merge (gate + projection ship together); no soak gate.

## Observability

```yaml
liveness_signal:
  what: eval-gate.cjs verdict JSON to stdout per gated-block edit (synchronous; no daemon)
  cadence: per gated-block edit (event-driven)
  alert_target: in-session operator output (proposer surfaces accept/reject)
  configured_in: heal-skill/SKILL.md apply step + compound-capture/SKILL.md Step 8
error_reporting:
  destination: proposer in-session output + non-zero exit from eval-gate.cjs
  fail_loud: true   # TR4 — edit NOT applied on any gate error
failure_modes:
  - {mode: promptfoo run errors / API key missing, detection: eval-gate.cjs non-zero exit, alert_route: proposer aborts apply + surfaces}
  - {mode: edit does not touch a gated block, detection: extract-block diff empty / --check miss, alert_route: log "not gated" + proceed}
  - {mode: headless invocation, detection: HEADLESS_MODE set, alert_route: skip-gate-and-defer note; #5703 CI catches}
logs:
  where: rejected edits → .claude/.skill-edit-rejections.jsonl (local, gitignored); gate runs → in-session
  retention: local; pruned by operator (v1)
discoverability_test:
  command: "cat .claude/.skill-edit-rejections.jsonl | jq ."
  expected_output: "JSON lines {source_file, target_task_id, reason, verdict, timestamp} — NO ssh"
```

## Domain Review

**Domains relevant:** Engineering (brainstorm carry-forward).

### Engineering
**Status:** reviewed (brainstorm + 3-agent plan-review + plan-time CTO lens)
**Assessment:** Integration of `compound`/`heal-skill` + `eval-harness` via a deterministic verdict
and a delimited-block projection. Plan-review reshaped the trigger from proposer-bound (compound) to
block-keyed proposer-agnostic after Kieran showed the original hook measured the wrong artifact.
Residual risks: projection-link integrity (TR-PROJECTION; ADR records it as a validity precondition),
small-N variance (TR5 ε + pooled aggregation), FR6 hook-first non-displacement.

### Product/UX Gate
Skipped — no UI-surface file (`.md`, `.cjs`, `.json`, `.c4`, `.gitignore`). Product = NONE.

## User-Brand Impact

**If this lands broken, the user experiences:** no worse than today — a gated-block edit is applied
unverified (the current no-gate status quo). The gate only *reduces* misroute risk; it introduces no
new user-facing failure beyond a too-strict gate blocking a good fix (recoverable, in-session).

**If this leaks:** no user data involved — synthesized fixtures only (TR2); buffer is local + gitignored.

**Brand-survival threshold:** none. **Reason:** internal dev-tooling, touches no user data, no
production runtime surface; landing broken is no worse than the current no-gate state. (Operator
decision at plan-review, overriding the brainstorm's initial single-user-incident framing.)

## Risks & Mitigations
- **Projection link silently breaks** → ADR-069 records it as a validity precondition; AC4 round-trip test asserts generated == committed projection; a CI check (folded into #5703) re-asserts it.
- **Small-N variance** → ε tolerance + pooled aggregation + `--repeat 5` (TR5).
- **Headless unattended spend** → skip-gate-and-defer (TR-HEADLESS).
- **GDPR / IaC** → none touched; synthesized fixtures only. Both gates skipped.

## Open Code-Review Overlap
None (checked 63 open code-review issues against all touched paths).

## Deferred (tracking issues)
- #5703 — CI backstop: re-run eval-harness + assert projection-link integrity on PRs touching a gated block (now the proposer-agnostic catch-all for manual/one-shot edits). Pull-forward candidate if in-session hooks prove insufficient.
- #5704 — broader gated-skill catalog.
- NEW (file at plan-end): cross-operator/shared rejected-edit buffer (v1 is local-per-machine).

## Sharp Edges
- The verdict MUST stay in pure `verdict.cjs`, never in a proposer's LLM step — promptfoo's classifier output is LLM-mediated; only the accept/reject computation is deterministic.
- The gate is only honest while the skill-arm prompt is a mechanical projection of the block. If anyone reverts the prompts to hand-copied snapshots, the gate silently no-ops on out-of-block edits (the exact P1-1 failure). AC4 + the #5703 projection-integrity check guard this.
