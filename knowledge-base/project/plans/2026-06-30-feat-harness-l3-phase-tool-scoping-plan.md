---
title: "feat(harness): L3 per-phase tool/skill scoping (CLI v1)"
issue: 5768
branch: feat-harness-l3-phase-tool-scoping
pr: 5769
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-30-harness-l3-phase-tool-scoping-brainstorm.md
spec: knowledge-base/project/specs/feat-harness-l3-phase-tool-scoping/spec.md
deferred_followup: 5772
date: 2026-06-30
---

# feat(harness): L3 per-phase tool/skill scoping — CLI v1 ✨

Shrink the agent's *effective* skill/agent surface by workflow phase — **without
removing anything** — in the **CLI/plugin harness**. A single stateless
PostToolUse hook injects a fail-open phase hint after every `Skill` call; an
eval target measures whether it reduces wrong-tool selection. Web parity is
**#5772** (deferred). Not a full per-phase allowlist framework.

## Overview

The issue's premise is **partly already solved** (Research Reconciliation):
MCP schemas are already deferred via ToolSearch; change-class scoping already
ships via `session-rules-loader.sh`. The residual is the **92 always-loaded
skill descriptions** + the **absence of a phase signal**. This plan adds the
phase signal and an additive hint that biases skill/agent selection per phase.

**Mechanism (post-review, corrected):** a **PostToolUse hook on the `Skill`
matcher** (`phase-surface-hint.sh`). PostToolUse hooks CAN emit
`additionalContext` (proven by `pencil-collapse-guard.sh:108-111`; PreToolUse
returns only `permissionDecision`). It fires after **every** `Skill` call —
interactive AND autonomous (`one-shot`) AND inside Task subagents — reads
`tool_input.skill`, derives the phase from a static map, and injects the
phase's surface hint. **Stateless:** no phase-token file, no session_id
plumbing, no sentinel. The skill call *is* the phase signal at the moment it
fires.

**Load-bearing invariant (TR1, two-tier fail-open rule):** deny-by-default is
permitted ONLY on an already-fail-open layer (MCP/ToolSearch). On every other
layer scoping is **additive-hint only**. In v1 *nothing is denied on any tier*,
so the invariant holds trivially; ADR-070 binds the **deferred** `disallowedTools`
implementer (#5772), not just v1. Any classifier ambiguity / unmapped skill →
emit nothing → full surface (mirrors `session-rules-loader.sh:114-126`
multi-class/empty → load-all).

## Research Reconciliation — Spec/Brainstorm vs. Codebase

| Claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Inject the hint via `session-rules-loader.sh` / a `UserPromptSubmit` reader keyed off a phase token | `UserPromptSubmit` **never fires in `one-shot`** (one user prompt, then internal skill-driven phases) → zero hint on the primary autonomous flow (spec-flow review #1). PreToolUse can't inject `additionalContext`; **PostToolUse can** (`pencil-collapse-guard.sh:108-111`). | **Single stateless PostToolUse(`Skill`) hook.** Fires in autonomous + interactive + subagent. Drops the token file, session_id plumbing, and on-change sentinel entirely (dissolves spec-flow #1/#1b/#3/#5, simplicity Q2, architecture P1 flock + `.gitignore`). |
| Web side "scope down a high-confidence never-needed subset" (spec FR3) | `allowedTools` is **auto-approve-only** (sdk.d.ts:858-862); `disallowedTools` is the only restrictor and is **fail-closed** (silent "unknown tool" to a paying user — `2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools`). | Fail-closed → contradicts "fail-open only" → **deferred to #5772**. |
| "Per-phase scoping applies to both harnesses" | Web DOES run the full skill sequence (`/soleur:go` as SDK router, ADR-022; `soleur-go-runner.ts`). But the web SDK sets **`settingSources: []`** (`agent-runner-query-options.ts:155`) → it does NOT load `.claude/` hooks → the CLI PostToolUse hook can't reach it. | **v1 is CLI-only.** Web needs an SDK-native hook registered in `options.hooks` (where PreToolUse sandbox + SubagentStart already live) → **#5772**. |
| ADR via `/soleur:architecture` | Highest existing ADR = **ADR-069**. | New ADR = **ADR-070**. |
| Registry consistency needs a dedicated TS test (ADR-053) | A stale map entry fails **OPEN** (no hint → full surface); a fail-closed CI gate is disproportionate (simplicity Q1). | Fold the consistency check into the **shell test**; ALSO assert every `skill_to_phase` *value* is a key in `phase_to_surface` (spec-flow #6 dangling-phase). |

## User-Brand Impact

**If this lands broken, the user experiences:** a CLI agent that foregrounds the
wrong phase's skills (e.g. suggests `ship` during planning) — degraded routing,
fully recoverable; the hint removes nothing.

**If this leaks, the user's workflow is exposed via:** N/A — no user data, no
credentials, no PII. The phase hint is agent-prompt context only.

**Brand-survival threshold:** single-user incident.

CPO sign-off carried forward from brainstorm Phase 0.1 (the web-vs-paying-user
decision was made with the brand vector explicit; web is now deferred → v1 has
~zero paying-user surface). `user-impact-reviewer` runs at PR review. Threshold
held by: additive-only (nothing removed → zero silent-fail surface) + ambiguity→
full-surface.

## Implementation Phases

### Phase 0 — Empirical probe (mirrors this repo's PermissionDenied probe precedent)

0.1 **Verify PostToolUse(`Skill`) `additionalContext` is actually injected** into the agent's context (the load-bearing assumption). Probe like `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md` did: a stub PostToolUse(`Skill`) hook emitting a sentinel `additionalContext`, confirm it reaches the model. **If it does NOT inject** (SDK/CC version regression), fall back to a `Stop`/`UserPromptSubmit` hybrid and re-scope — do NOT ship a dark mechanism. Record the probe result in the PR body.

### Phase 1 — Registry

1.1 Create `.claude/phase-surface-map.json`: `skill_to_phase` (brainstorm/brainstorm-techniques→`brainstorm`; plan/deepen-plan/plan-review→`plan`; work/atdd-developer/test-fix-loop/resolve-*→`work`; review/qa→`review`; ship/preflight/merge-pr/postmerge→`ship`) + `phase_to_surface` (per phase: `relevant_skills`, `relevant_agents`, `not_live_note`). Any skill not in `skill_to_phase` → no hint (full surface). `one-shot`/`go` deliberately unmapped (they drive sub-skills whose own calls fire the hook).

### Phase 2 — The hook

2.1 Create `.claude/hooks/phase-surface-hint.sh` (PostToolUse). Reads `tool_input.skill` from stdin, looks up phase in `phase-surface-map.json`; if mapped, emits `{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"<≤15-line phase hint>"}}`; if unmapped/missing-map/jq-fail → emit nothing, `exit 0`. Read-only (no lock — the map is static), `set -uo pipefail`, every external call inside a command-sub with `|| fallback`, **`exit 0` on every path** (never block tool dispatch). Mirror `session-rules-loader.sh` ERR-trap discipline (`:196-200`).
2.2 Wire in `.claude/settings.json` under `PostToolUse`, matcher `Skill`.

### Phase 3 — Measurement (thin: ~5 golden tasks)

3.1 Add an opt-in/manual eval-harness `tool-selection` target: `promptfooconfig.tool-selection.yaml` + `prompts/tool-selection-skill.txt` + **≤5** golden tasks under `tasks/tool-selection/` (full-surface arm vs phase-scoped arm). MEASUREMENT records wrong-tool rate; token spend from promptfoo usage. NOT CI-wired (API-budget gate per eval-harness SKILL.md). Document in eval-harness SKILL.md as a manual target. (Deliberately thin — a corpus beyond ~5 tasks is scope-creep against the cheap-win mandate.)

### Phase 4 — ADR-070

4.1 Author ADR-070 ("L3 phase tool scoping — two-tier fail-open rule") via `/soleur:architecture`. Records: additive-hint-over-deny; deny-by-default only on MCP/ToolSearch; `allowedTools` auto-approve-only + `disallowedTools` fail-closed finding; the **`settingSources:[]` web-isolation** reason; the **canonical shared-registry location** decision for the deferred web map reuse (#5772); the deferred `disallowedTools` subset binding. C4: no `.c4` edit (enumeration below).

### Phase 5 — Tests & verification

5.1 `phase-surface-hint.test.sh`: mapped skill → hint emitted with that phase's surface; unmapped skill (`soleur:help`) → empty output, exit 0; missing/corrupt map → empty output, exit 0; **map consistency** (every `skill_to_phase` key resolves to a real SKILL.md; every `skill_to_phase` *value* is a `phase_to_surface` key; 5 core phases present). 5.2 `bash scripts/test-all.sh scripts` (existing glob runs the new `.test.sh`).

## Files to Create

- `.claude/phase-surface-map.json` — registry (skill→phase + phase→surface)
- `.claude/hooks/phase-surface-hint.sh` — PostToolUse(`Skill`) additive-hint injector (stateless)
- `.claude/hooks/phase-surface-hint.test.sh` — hook behavior + map consistency
- `plugins/soleur/skills/eval-harness/promptfooconfig.tool-selection.yaml`
- `plugins/soleur/skills/eval-harness/prompts/tool-selection-skill.txt`
- `plugins/soleur/skills/eval-harness/tasks/tool-selection/*` — ≤5 golden tasks
- `knowledge-base/engineering/architecture/decisions/ADR-070-l3-phase-tool-scoping-two-tier-fail-open.md`

## Files to Edit

- `.claude/settings.json` — wire `phase-surface-hint.sh` as PostToolUse matcher `Skill`
- `plugins/soleur/skills/eval-harness/SKILL.md` — document the manual `tool-selection` target

(No web files, no `skill-invocation-logger.sh`, no `session-rules-loader.sh`, no
`.gitignore` change — the stateless PostToolUse design writes no state files.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC0 PostToolUse(`Skill`) `additionalContext` injection confirmed by the Phase 0 probe (result in PR body); fallback taken + re-scoped if not.
- [ ] AC1 `.claude/phase-surface-map.json` exists; `jq -e '.skill_to_phase["soleur:work"]=="work"'` true.
- [ ] AC2 `phase-surface-hint.test.sh` passes: mapped skill emits a hint naming that phase's surface; `soleur:help` emits nothing (exit 0); missing map emits nothing (exit 0).
- [ ] AC3 Map consistency (in `phase-surface-hint.test.sh`): every `skill_to_phase` key → real SKILL.md; every `skill_to_phase` value → a `phase_to_surface` key; 5 core phases present.
- [ ] AC4 `phase-surface-hint.sh` wired as PostToolUse matcher `Skill` (`jq -e '.hooks.PostToolUse[]|select(.matcher=="Skill")'`).
- [ ] AC5 ADR-070 exists and records the two-tier rule + allowedTools/disallowedTools finding + `settingSources:[]` reason + shared-registry-location decision + deferred-subset binding.
- [ ] AC6 `bash scripts/test-all.sh scripts` green.
- [ ] AC7 Web-parity follow-up #5772 referenced in the PR body.

### Post-merge (operator)

- [ ] AC8 Run the `tool-selection` eval target locally (opt-in/manual, API spend); record full-surface vs phase-scoped wrong-tool rate + token spend in #5768. This is the AC(c) effectiveness evidence. (Automation: not feasible in CI — API-budget gate per eval-harness SKILL.md; operator-run by design.)

## Observability

```yaml
liveness_signal:
  what: phase-surface-hint.sh emits additionalContext on each mapped Skill call (visible in the agent transcript)
  cadence: per Skill invocation (PostToolUse)
  alert_target: none (local dev-harness; no prod surface, no persistent state)
  configured_in: .claude/hooks/phase-surface-hint.sh + .claude/settings.json
error_reporting:
  destination: none needed — stateless, fail-soft, exit-0 on every path; a fault degrades to "no hint" (full surface), the correct posture for an additive hint
  fail_loud: false (intentional — never block tool dispatch)
failure_modes:
  - mode: phase-surface-map.json malformed/missing
    detection: phase-surface-hint.test.sh fails in CI (scripts shard); at runtime → no hint (fail-open)
    alert_route: PR CI red
  - mode: PostToolUse additionalContext stops injecting (SDK/CC regression)
    detection: Phase 0 probe at build time; the eval target (AC8) measures net effect
    alert_route: manual probe + eval run
  - mode: map drifts (dangling phase value / deleted skill)
    detection: AC3 consistency assertions in the shell test
    alert_route: PR CI red
logs:
  where: none persisted (stateless hook); the hint itself appears in the agent transcript
  retention: n/a
discoverability_test:
  command: "printf '{\"tool_input\":{\"skill\":\"soleur:work\"}}' | .claude/hooks/phase-surface-hint.sh   # NO ssh"
  expected_output: "JSON additionalContext naming the work-phase surface; empty for an unmapped skill"
```

## Architecture Decision (ADR/C4)

### ADR
- **Create ADR-070** via `/soleur:architecture`. Decision + alternatives (full framework — rejected: bypass risk; measure-only — rejected: operator wants a shipped change; web `disallowedTools` in v1 — rejected: fail-closed → #5772). MUST record the `settingSources:[]` web-isolation mechanism and the canonical shared-registry location for #5772.

### C4 views
**No `.c4` edit required.** Completeness-mandate enumeration (read `model.c4`, `views.c4`, `spec.c4`):
- **External human actors:** none added.
- **External systems/vendors:** none added (the Anthropic engine `platform.engine.claude` already modeled; no new data flow).
- **Containers / data stores:** none — the stateless hook persists NO state (v1 dropped the token file).
- **Access / ownership relationships:** none changed.
- **Granularity:** `platform.engine.hooks` is a container; individual hooks are NOT modeled as components (neither existing hook appears), so adding `phase-surface-hint.sh` is internal behavior — no element/edge change. `evalharness` already modeled; a manual target changes no edge.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` cross-referenced against the Files-to-Edit set — `.claude/settings.json` + `eval-harness/SKILL.md` — no open scope-out names them.)

## Domain Review

**Domains relevant:** Engineering, Product (carried forward from brainstorm `## Domain Assessments`).

### Engineering
**Status:** reviewed (brainstorm carry-forward + plan-time CTO grounding + 3-agent plan-review: architecture-strategist, code-simplicity, spec-flow).
**Assessment:** Sound, no P0. The PostToolUse single-hook design (post-review) is materially simpler than the v1 token+UserPromptSubmit design AND fixes the autonomous-flow defect. Two-tier rule holds (vacuously in v1 — nothing denied). No capability gaps. Complexity: low-medium.

### Product/UX Gate
**Tier:** none — no UI surface (only `.sh`, `.json`, `.cjs`/`.yaml`/`.txt`, `.md`). Mechanical UI-surface override did not fire.
**Pencil available:** N/A.
**CPO sign-off:** required (single-user threshold); carried forward from brainstorm Phase 0.1. Web deferral (#5772) removes the only paying-user surface from v1.

#### Findings
v1 is additive-only and CLI-only → ~zero paying-user risk. The web silent-unknown-tool risk re-enters only with #5772's `disallowedTools` lever, gated behind TR3 telemetry + eval evidence.

## GDPR / Compliance Gate
Trigger (b) fires by the letter (threshold = single-user incident), but the diff touches **no regulated-data surface** (no schema/migration/auth/API-route/.sql, no new LLM processing of user data). Disposition: **no findings** (consistent with the #5703 internal-tooling precedent).

## Infrastructure (IaC)
N/A — no new infrastructure. Eval target is opt-in/manual, not a cron. Phase 2.8 trigger set not matched.

## Test Scenarios

1. `soleur:work` Skill call → hint emitted naming work-phase surface.
2. Phase transition (`work`→`review` via the next Skill call) → review-phase hint emitted.
3. `soleur:help` (unmapped) → empty output, exit 0 (no spurious hint, full surface).
4. Missing/corrupt `phase-surface-map.json` → empty output, exit 0 (fail-open).
5. Map with a non-existent skill key OR a dangling phase value → `phase-surface-hint.test.sh` fails (consistency gate).
6. (Phase 0) stub PostToolUse(`Skill`) hook → sentinel additionalContext confirmed reaching the model.

## Sharp Edges / Risks

- **PostToolUse-injection assumption is load-bearing** → Phase 0 probe (AC0) verifies it empirically before build, with a fallback. Do not ship dark.
- **One-call freshness:** the hint reflects the skill *just* invoked — correct by construction (the Skill call IS the phase transition). No stale-token class (stateless).
- **Per-call token cost:** the hint (~15 lines) is emitted once per Skill call (= once per phase transition, not per turn) — negligible vs the 92 descriptions it helps the model ignore. Net effect measured by AC8.
- **`requires_cpo_signoff: true`** → exit gate recommends `/soleur:deepen-plan` (single-user threshold; the deepen triad catches substance-level issues plan-review is blind to).
- **Deferred (web parity):** #5772 — SDK-native phase hint + `disallowedTools` subset + TR3 telemetry, gated on AC8 eval evidence. Referenced in PR body (AC7).
- A plan whose `## User-Brand Impact` is empty/`TBD` fails `deepen-plan` Phase 4.6 — filled above.
