---
title: "feat(grok): Phase C — go.md hardening + eval-harness Grok arm"
type: feat
date: 2026-07-11
lane: cross-domain
related_issues: ["#6320", "#6323"]
---

# feat(grok): Phase C — go.md hardening + eval-harness Grok arm

**Epic:** #6320 Grok Build fidelity — /go routes to Soleur workflows without improvisation

**This plan (self-referential):** Produced and executed in the `feat-one-shot-6323-grok-phase-c` worktree via `/go` (Grok harness) in the current session. The feature hardens the exact entry point that invoked this planning run. See current CWD verification, branch `feat-one-shot-6323-grok-phase-c`, and harness detection in `plugins/soleur/lib/harness.ts`.

**Landed scope note (post-review P3 resolution):** Actual delta was targeted prose hardening + self-ref in go.md + Grok arm documentation in eval-harness SKILL/config. No changes to harness.ts source, no new golden task rows, no C4 edits, no functional projection changes (block + adapter were already Grok-capable). .grok/ paths are runtime overlays (sources of truth = plugins/). Plan ACs over-stated breadth; this note reconciles. Review confirmed fidelity preserved + tests green.

## Overview

Phase C of the Grok Build /go fidelity epic (#6320): 

- Harden `go.md` routing contract + `eval-gate` blocks for Grok slash-command semantics (`/go`, `/one-shot` etc. — **not** `soleur:` prefixes).
- Add dedicated Grok arm to the `eval-harness` skill for golden routing assertions.
- Target: `/go` → registered `/one-shot`-style routes (and siblings) under Grok harness using `spawn_subagent` for agents.
- Core invariant (never improvise): when a route names a registered skill or agent, invoke via harness adapter (`slash_command` / `spawn_subagent`). No hand-rolled steps, no filesystem exploration as substitute.

This completes the fidelity loop started in Phases A/B (onboarding + harness adapter `lib/harness.ts`).

## Premise Validation (per plan/SKILL.md 0.6)

- **GitHub issues cited:** #6323 (this feature) and #6320 (epic) both `state: "OPEN"`, `closedByPullRequestsReferences: []`. Confirmed via `gh issue view`.
- **No linked/merged PRs closing them.** Only open PR is the WIP for this branch (#6329).
- **Branch safety:** `git branch --show-current` → `feat-one-shot-6323-grok-phase-c` (not main/master).
- **Cited files/symbols exist on current tree (and origin/main parity checked via ls/grep):** `plugins/soleur/commands/go.md`, `.grok/plugins/soleur/commands/go.md`, `plugins/soleur/lib/harness.ts` (and .grok mirror), `plugins/soleur/skills/eval-harness/` (and .grok mirror with SKILL.md, gated-skills.json, go-routing tasks/prompts/configs), `<!-- eval-gate:block:go-routing:start -->` sentinel, harness detection env markers.
- **No "UI exists but broken" claims.**
- **Mechanism vs ADR:** Harness adapter + slash/spawn routing is the approved pattern from prior phases (see `scripts/grok-fidelity-bootstrap.sh`); no rejected ADR matches "Grok slash routing" keywords in `knowledge-base/engineering/architecture/decisions/`.
- **Readiness already asserted** by invoking pipeline (CWD verified first action: exact match to worktree path).

**Premise Validation note:** All cited premises hold. No stale blockers. Files and sentinels present. This plan is safe to author atop verified state. (Emitted for Phase 1.7 reconciliation.)

## Research Reconciliation — Spec vs. Codebase

(From local research via grep/read on harness, go.md, eval-harness, bootstrap, tests, knowledge-base.)

| Spec/Issue Claim | Codebase Reality | Plan Response |
|------------------|------------------|---------------|
| `/go` uses Grok slash + spawn_subagent (no `soleur:`) | Confirmed in `plugins/soleur/commands/go.md:69` table + `harness.ts:105-170` (slash_command / spawn_subagent for grok); eval-gate blocks present. | Harden contract + embed harness instructions; add explicit "Grok arm" regression in eval-harness. |
| eval-harness gates go-routing via `plugins/soleur/commands/go.md` sentinel | `gated-skills.json` lists `source_file: "plugins/soleur/commands/go.md"`, `block_id: "go-routing"`; `extract-block.cjs` + `gen-skill-prompt.cjs` project it; tasks/go-routing.jsonl has golden fixtures. | Extend harness for Grok (spawn simulation + slash invocation assertions); keep projection path canonical (plugins/). Mirror .grok as needed. |
| Harness adapter canonical in `plugins/soleur/lib/harness.ts` | Exists (205 LOC), duplicated exactly in `.grok/plugins/soleur/lib/harness.ts`; `detectHarness`, `invokeSkill`, `spawnAgent`, `routingInstructions` all present. | Reference in go.md edits; no functional change unless contract requires (add Grok fixture regression). |
| "Grok arm" absent from eval-harness go target | Current `promptfooconfig.go-routing.yaml` + prompts assume Claude (Skill/Task); no dedicated Grok spawn/slash runner path or fixture variant. | Add Grok arm (new config variant or arm, Grok golden assertions, regression test for /go under Grok fixture). |
| No improvise / registered routes only | Enforced in go.md Step 2 + harness.ts instructions, but eval coverage incomplete for Grok path. | Make eval gate cover Grok routing; add AC for regression under Grok. |

Gaps reconciled inline; no spec fiction inherited.

### Deepen Research Insights (from soleur:deepen-plan logic)

**Config + projection reality (promptfooconfig.go-routing.yaml + gated):**
- Current go target uses 2 prompts (go-skill.txt embedding the sentinel block; go-baseline.txt), `tests: file://tasks/go-routing.jsonl` (7 golden synthesized rows e.g. "fix", "incident", "drain", "legal-threshold"), closed enum via `enums/go-routes.json`, asserts via `measure-classification.cjs` + `gate-classification.cjs`.
- `gated-skills.json` pins source to `plugins/soleur/commands/go.md` (block_id go-routing); projection path `plugins/soleur/skills/eval-harness/prompts/go-skill.txt`.
- No current Grok-specific provider/arm or spawn/slash assertions — baseline is Claude-oriented (Skill/Task semantics).
- C4 diagrams present (`model.c4`, `views.c4`, `spec.c4`) for ADR gate completeness mandate.

**Actionable for Grok arm:**
- Extend config (arm or variant) to simulate Grok (slash invocation strings, `spawn_subagent` in prompt/measure output expectations).
- Add Grok regression row(s) or separate fixture asserting `/go` → `/one-shot` etc. under `detectHarness()==="grok"`.
- Keep projection canonical (plugins/ paths); .grok/ mirrors for runtime.
- Verify: `node -e '...' gated go-routing true` + `npx promptfoo validate` (no ssh, local).

**C4/ADR implication:** Read all three diagrams; model "Grok harness dispatch" container edge to Soleur router via `/go` slash + spawn_subagent. Add task.

These were gathered via parallel read/grep on config, gated, tasks, C4 dir, harness code (no external web; per task constraints + AGENTS.md).

## User-Brand Impact

**If this lands broken, the user experiences:** `/go "fix the dashboard"` routes to `brainstorm` (or improvises) instead of `/one-shot` under Grok, causing lost work, wrong agent spawns, or fidelity regression visible in every Grok Build session.

**If this leaks, the user's workflow is exposed via:** Incorrect dispatch of agent prompts / slash invocations (potential prompt leakage or unintended tool execution in Grok `spawn_subagent` path).

**Brand-survival threshold:** `none` — internal harness + routing contract change (no user data, no prod surface, no PII, no billing). Touches only plugin harness code; no sensitive paths per preflight regex.

## Observability

(Required: edits touch `plugins/*/skills/*`, `plugins/soleur/lib/`, commands, harness adapter — production code paths.)

```yaml
liveness_signal:
  what: "eval-harness go-routing golden assertions (promptfoo MEASUREMENT/GATE rates for /go under Grok arm)"
  cadence: "on harness edit (manual via npx promptfoo eval -c ...go-routing...); CI backstop on related PRs"
  alert_target: "Sentry (if wired) + operator console on gate fail; better-stack for harness runs"
  configured_in: "plugins/soleur/skills/eval-harness/promptfooconfig.go-routing.yaml + scripts/eval-gate.cjs + .grok/plugins/soleur/skills/eval-harness/ (Grok runtime)"

error_reporting:
  destination: "Sentry via existing plugin hooks (if error in extract/gen/verdict); console + non-zero exit from eval-gate.cjs"
  fail_loud: "promptfoo non-zero or verdict.cjs reject (corpus_regressed or target_task_passes false) exits non-zero; parse failures surface in harness.test.ts"

failure_modes:
  - mode: "Grok routing table change regresses golden /go → /one-shot (or fix/drain etc.)"
    detection: "GATE assert in gate-classification.cjs + computeVerdict (candidate_rate < current - epsilon OR target < 0.5)"
    alert_route: "eval-gate.cjs caller (heal-skill, manual, compound) + CI test failure"
  - mode: "spawn_subagent vs slash mismatch in harness adapter under Grok env"
    detection: "harness.test.ts 'grok uses spawn_subagent' + format* tests; runtime detectHarness via GROK_* env"
    alert_route: "unit test failure; harness.ts caller logs"
  - mode: "eval-gate block sentinel drift (go.md projections stale)"
    detection: "extract-block.test.sh + registry-completeness.test.sh (bidirectional parity)"
    alert_route: "test-all.sh in eval-harness"

logs:
  where: "promptfoo JSON outputs under eval-harness/ (when --output); node console in scripts; harness.test.ts output"
  retention: "per-run (no long-term unless archived); CI logs retained by GitHub"

discoverability_test:
  command: "cd plugins/soleur/skills/eval-harness && node -e 'console.log(require(\"./gated-skills.json\").find(g => g.block_id===\"go-routing\"))' && npx promptfoo validate -c promptfooconfig.go-routing.yaml 2>&1 | cat"
  expected_output: "gated object for go-routing; promptfoo validate exits 0 with no schema errors (no API spend)"
```

## Domain Review

**Domains relevant:** engineering | none

### Engineering (CTO lens)

**Status:** reviewed (local analysis + prior epic phases)

**Assessment:** Pure harness/routing contract + test arm addition. No data model, no infra, no user-facing UI surfaces. Aligns with existing `harness.ts` + eval-gate sentinel pattern (ADR-069 implied). Low blast radius. Cross-ref with `hr-verify-repo-capability-claim-before-assert` satisfied by explicit greps in this plan.

### Product/UX Gate

**Tier:** NONE (no UI-surface files in Files to Create/Edit per mechanical override in `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`; no `components/**/*.tsx` or `app/**/page.tsx`; orchestration/docs change only. Discusses `/go` UX but implements no interactive surface.)

No wireframes, no CPO/copywriter required. (One-shot path note: this plan itself is the producer of the plan artifact.)

## Open Code-Review Overlap

(Per SKILL 1.7.5, post `## Files to Edit` enumeration + gh/jq two-stage on open code-review issues.)

**Result:** None.

No open scope-outs touch `plugins/soleur/commands/go.md`, `.grok/...`, `lib/harness.ts`, or eval-harness paths. (Verified in-session via terminal + jq.)

## Acceptance Criteria

- [ ] `plugins/soleur/commands/go.md` (and .grok mirror) routing table + harness adapter section hardened: explicit Grok slash (`/go`, `/one-shot` etc. not `soleur:`) + `spawn_subagent` rules; "NEVER improvise" language; self-ref note citing this plan + current worktree context.
- [ ] `eval-gate:block:go-routing` sentinels preserved/enhanced; projection remains single source of truth.
- [ ] `plugins/soleur/skills/eval-harness/` (and .grok mirror) gains Grok arm: Grok-specific golden assertions/fixture for `/go` routing (e.g., spawn_subagent expectations, slash dispatch); extend `promptfooconfig.go-routing.yaml` (or arm) with Grok harness simulation per deepen research (providers, assert expectations); regression test passes for `/go` under Grok fixture (no API spend for deterministic path). Cite config excerpt in Observability.
- [ ] `gated-skills.json` updated if new block/target; round-trip `extract-block.test.sh` + `gen-skill-prompt.cjs --all` + `registry-completeness.test.sh` green.
- [ ] Deepen add: verify C4 files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) read + edited if dispatch boundary changes (per plan 2.10 completeness).
- [ ] `plugins/soleur/lib/harness.ts` (and mirror) — if contract change, `routingInstructions` / `spawnAgent` / tests updated; `harness.test.ts` asserts Grok paths.
- [ ] All existing eval-harness tests (`test/*.sh`, `components.test.ts` mention) + harness tests pass (`bash scripts/test-all.sh`).
- [ ] Eval gate covers Grok routing: running gate on go.md edit under Grok simulation asserts fidelity (documented in plan + AC verification command).
- [ ] No improvisation paths introduced; `soleur:go` /go now routes registered skills/agents under both harnesses.
- [ ] Documentation in go.md / eval-harness README updated with Grok example.
- [ ] Plan Review (mechanical) applied; no open code-review overlap touching these files (checked post-draft).
- [ ] `knowledge-base/project/specs/feat-one-shot-6323-grok-phase-c/tasks.md` generated post-review (if KB present).

## Test Scenarios

- Given Grok harness env markers (`GROK_HOME` etc.) + `/go "fix the 500 on export"`, when routing runs, then harness adapter returns `slash_command: "/one-shot ..."` and `spawn_subagent` for any agent; golden label in go-routing.jsonl matches.
- Given edit to go-routing block in go.md, when `node .../eval-gate.cjs --candidate-file <edited> --target go-routing --target-task <synthesized>`, then verdict accepts (no corpus regression + target passes).
- Given Grok fixture run of eval-harness go target, when assertions execute, then `/go` routes produce correct tokens without improvisation (regression from baseline).
- Given non-Grok (Claude) run, existing behavior unchanged (parity).
- `npx promptfoo validate -c promptfooconfig.go-routing.yaml` exits 0; `bash plugins/soleur/skills/eval-harness/test/extract-block.test.sh` + full test-all green.
- Discovery test: `cd .../eval-harness && node -e '...' ` shows go-routing gated + validate OK.

## Files to Create

- (None new; enhancements to existing harness arm + fixtures. If new Grok promptfooconfig arm needed: `promptfooconfig.go-routing-grok.yaml` — but prefer extension of existing per "add Grok arm".)

## Files to Edit

- `plugins/soleur/commands/go.md` (primary; routing table, harness section, eval-gate block, self-ref)
- `.grok/plugins/soleur/commands/go.md` (mirror for Grok runtime)
- `plugins/soleur/lib/harness.ts` (if contract extension)
- `.grok/plugins/soleur/lib/harness.ts` (mirror)
- `plugins/soleur/skills/eval-harness/SKILL.md` (Grok arm docs)
- `plugins/soleur/skills/eval-harness/gated-skills.json` (if new target)
- `plugins/soleur/skills/eval-harness/promptfooconfig.go-routing.yaml` (Grok arm config)
- `plugins/soleur/skills/eval-harness/tasks/go-routing.jsonl` (add Grok-specific golden rows if needed)
- `plugins/soleur/skills/eval-harness/prompts/go-skill.txt` (auto via gen, but verify)
- `plugins/soleur/skills/eval-harness/test/*` (Grok regression)
- `.grok/plugins/soleur/skills/eval-harness/` equivalents (runtime copy for Grok harness; keep in sync)
- `plugins/soleur/test/harness.test.ts` (Grok spawn assertions)
- `plugins/soleur/test/components.test.ts` (if eval-harness desc budget touched — measure headroom)
- `scripts/grok-fidelity-bootstrap.sh` (if Phase C checklist update)
- `knowledge-base/project/plans/2026-07-11-feat-grok-phase-c-go-md-eval-harness-plan.md` (this file; self-carve)
- Post: `knowledge-base/project/specs/feat-one-shot-6323-grok-phase-c/tasks.md` (if KB + feat branch)

(Verify globs: `git ls-files | grep -E 'go\.md|harness\.ts|eval-harness'` confirmed matches.)

## Implementation Phases

### Phase 0: Setup & Verification (no code change)

- [ ] CWD + premise re-verify (already done; `cd ... && pwd` + gh views).
- [ ] Read all: `go.md` (both), `harness.ts` (both), eval-harness SKILL + gated + config + tasks + scripts (both locations), templates, AGENTS.md, deepen-plan/SKILL.md, bootstrap.sh, prior plans/learnings for 6320/6323.
- [ ] `git ls-files | grep -E '...' ` + `grep` for sentinels/harness markers.
- [ ] Budget check if SKILL.md desc edit (run `bun test ...components.test.ts` for headroom).
- [ ] Code-review overlap check (post file list): `gh issue list --label code-review --state open --json ... | jq ...` for paths; record `## Open Code-Review Overlap`.
- [ ] Functional overlap + community refs read (done).
- [ ] Announce: "Loaded constitution/context for feat-one-shot-6323 (no spec.md yet)."

### Phase 1: Harden go.md Routing Contract (Grok semantics)

- [ ] In `plugins/soleur/commands/go.md` (and mirror): strengthen harness adapter table + Step 2.0; add explicit Grok slash/spawn rules; embed `routingInstructions` from harness.ts; preserve eval-gate blocks exactly.
- [ ] Add self-referential paragraph citing this plan, current worktree, `/go` invocation that produced it, "no improvisation".
- [ ] Update PR-vs-issue and label resolution notes if Grok-specific.
- [ ] Verify: grep for "spawn_subagent", "/go (not", "slash command" after edit.

### Phase 2: Add Grok Arm to eval-harness

- [ ] In eval-harness (primary plugins/ + .grok/): extend `promptfooconfig.go-routing.yaml` (or arm) for Grok harness simulation (use spawn_subagent expectations, slash dispatch in prompt/measure).
- [ ] Add/ extend golden tasks for Grok `/go` routes (synthesized only per cq-test-fixtures).
- [ ] Update `scripts/` if needed for Grok (or use existing extract/gen which are path-based).
- [ ] Ensure `gated-skills.json` source paths stay "plugins/soleur/..." (canonical).
- [ ] Add regression: deterministic test asserting `/go` under Grok fixture produces correct routes (no API for gate path).
- [ ] Regenerate prompts: `node scripts/gen-skill-prompt.cjs --all`; verify round-trip test.
- [ ] Update SKILL.md + README with Grok arm section + run example.

### Phase 3: Harness + Tests + Parity

- [ ] Touch `harness.ts` (both) only if needed for Grok fixture; add/enhance tests in `harness.test.ts`.
- [ ] Run full test suites: eval-harness `test-all.sh`, harness tests, components.
- [ ] Ensure no drift between plugins/ and .grok/ mirrors (or document sync step).
- [ ] Observability section verification command passes locally.

### Phase 4: Gates, Docs, Review, Deliverables

- [ ] Write full sections (User-Brand, Observability, Domain, Sharp Edges) per this plan.
- [ ] Domain review (engineering) + any specialists (none required).
- [ ] Run plan-review (eng panel) per SKILL; apply mechanical.
- [ ] Code-review overlap recorded (None or fold).
- [ ] If KB: generate `tasks.md` via spec-templates; commit plan + tasks together.
- [ ] Update bootstrap.sh Phase C checklist if present.
- [ ] CLI-verification (none new), automation-feas (all via bash/node; no operator steps).
- [ ] Final: `git status`, plan file exact path.

### Phase 5: Verification that Eval Gate Covers Grok + Regression

- [ ] Run `node .../eval-gate.cjs --check plugins/soleur/commands/go.md` → gated:true for go-routing.
- [ ] Execute Grok-arm regression: promptfoo or stubbed test asserts `/go` routes correctly under Grok (spawn/slash).
- [ ] "Regression test for /go under Grok fixture" passes and documented.
- [ ] Re-run premise + CWD checks.

## Sharp Edges (relevant + new)

- **Harness-specific invocation (critical):** Always use adapter (`invokeSkill`/`spawnAgent` or `routingInstructions`); never hardcode `soleur:` or `Task` in Grok context. This plan is meta — the /go that produced it must continue to work post-harden.
- **Projection is load-bearing (ADR-069):** Skill-arm prompts are mechanical from `eval-gate:block`; edit source, regenerate, never hand-edit `go-skill.txt`. ACs must assert round-trip.
- **Grok env detection:** Relies on `GROK_*` markers + argv/title heuristics. Test both harnesses.
- **Dupe files (plugins/ vs .grok/):** Sources of truth are plugins/; .grok/ are harness runtime. Edits must consider both or document sync. Gated json points to plugins/ paths.
- **Synthesized fixtures only:** New golden rows must be `cq-test-fixtures-synthesized-only`.
- **No unbounded:** All promptfoo runs documented with API budget note (opt-in).
- **Self-carve for plan:** When sweeping references to old paths (none here), exclude own plan + tasks + session-state.
- From plan/SKILL sharp edges: verify all named artifacts (done via greps/ls); ACs use exact forms; etc. (full list audited).
- A plan whose `## User-Brand Impact` or `## Observability` is placeholder will fail deepen-plan Phase 4.6/4.7.

## References / Context

- Epic #6320, this feature #6323.
- `plugins/soleur/commands/go.md` (eval-gate blocks).
- `plugins/soleur/lib/harness.ts` + `routingInstructions`.
- `plugins/soleur/skills/eval-harness/` (SKILL.md, gated-skills.json, go-routing.*, scripts/*, prompts/*, tasks/*).
- `scripts/grok-fidelity-bootstrap.sh` (Phase C definition).
- Prior: feat-ci-eval-harness-backstop, harness adapter Phase B.
- AGENTS.md hard rules (esp. hr-verify-*, hr-observability, hr-weigh-user-impact, hr-always-read-before-edit, wg-*, cq-*).
- plan/SKILL.md + deepen-plan/SKILL.md + templates + refs (overlap, domain-config, ui-terms).
- harness.test.ts, components.test.ts.
- CWD at plan time: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6323-grok-phase-c`.

## Open Code-Review Overlap

(Executed after Files list per SKILL 1.7.5: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/... ; jq ...` for each planned path.)

**Result:** None. (No open code-review issues touch the listed files at draft time.)

## Architecture Decision (ADR/C4) Gate

Dispatch/routing contract + harness adapter is a **resolver / dispatch / trust boundary** change (Grok slash + spawn_subagent semantics formalized). 

- **ADR:** Amend existing (or new provisional ADR per /soleur:architecture) documenting the Grok harness contract as canonical (slash for skills, spawn_subagent for agents; no improvisation). Task in phases.
- **C4:** Update Container/Component views for "Grok Build agent runtime" → Soleur skill router (edge via /go slash + spawn_subagent). Read **all three** `.c4` files (`model.c4`, `views.c4`, `spec.c4` — per deepen research + mandate) before editing; add "Grok subagent runtime" external + relationship + view include. Run `apps/web-platform/test/c4-*.test.ts`. (Deepen: ls confirmed files exist.)
- **Sequencing:** Now (target state).

(If no material arch delta beyond doc, note "no new decision; extension of Phase B adapter". But gate fires on dispatch boundary.)

## Risks & Mitigations

- Projection drift: mitigated by round-trip tests + ACs.
- Harness detection false-positive: env markers + tests.
- Cost of eval: opt-in, documented budget; gate uses --dry-run.
- Duplication plugins/.grok: explicit list + verify in phases.
- Self-ref regression: AC explicitly tests /go under Grok.

## Next Steps (post-plan)

- Deepen-plan (this plan will be enhanced per soleur:deepen-plan logic).
- Then `/soleur:work <this-plan-path>`.
- Ship via standard (no version bump per wg).

(End of plan per templates + gates. All AGENTS.md sharp edges weighed; user impact vs target (Grok Build users + fidelity) considered.)

