---
title: "feat: Grok Build plugin fidelity after Claude Code progress on main"
type: feat
date: 2026-09-11
slug: feat-grok-build-plugin-fidelity
branch: feat-grok-build-claude-parity
issue: 8064
closes: 8064
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: Grok Build plugin fidelity after Claude Code progress on main

## Overview

Make Soleur's Grok Build plugin path match the current Claude Code lifecycle without regressing Claude. Grok has no nested Skill/slash tool: after `/go` classifies, the parent Reads the next SKILL.md in-process through `harness.ts`. Dual-voice pipeline skills, implement ADR-110, additive hook aliases, plugin-root substitution, then public docs and legal harness-neutral copy after the golden-path eval is green. Web ACP and GPU dogfood stay parked.

CPO sign-off at plan time: brainstorm CPO recommended Track 1 only (Approach A); operator confirmed. `user-impact-reviewer` runs at PR review.

## Research Insights

**Premise Validation.** `#8064` OPEN (this work). `#6320` CLOSED (do not reopen). `#6316` CLOSED after docs-only PR `#6317`; `plugins/soleur/lib/harness-model-map.ts` is absent on this worktree (`ls` → no such file) so the “ADR-110 shipped” premise is stale — this plan implements PR2. `#6547` `#6546` `#7882` OPEN and parked. `harness.ts` and `workflow-fidelity.ts` exist. Live `/go` on 2026-09-11 classified to brainstorm then Read SKILL.md.

**Property List.**

1. After `/go` classifies, the parent follows the next registered skill without Skill-tool-only prose.
2. Claude Skill-tool invocation still works and eval stays green.
3. Semantic model tiers resolve to a non-empty spawn value under both harnesses.
4. Session-start plugin probes work when Grok does not set `CLAUDE_PLUGIN_ROOT`.
5. Safety hooks that can fire on Grok-named tools do fire; tools Grok does not have are documented skips, not silent offs.
6. After eval is green, public getting-started/README and legal plugin copy are not Claude-exclusive.

**Cut List.**

- Nested slash as a real tool_use → no xAI primitive; honest contract is in-process Read.
- Rebuild grok inspect CI → `grok-fidelity-gate.sh` already runs inspect + golden-path.
- Web ACP / `agent-runner.ts` → `#6547` parked.
- GEX44 Robot IaC / GPU order → `#6546`/`#7882` parked.
- Port `claude-code-action` CI → ADR-110 out of scope.
- Fake Monitor matcher for a tool Grok does not have → documented skip + `SOLEUR_*` marker.

**Phase 1 fan-out.** Brainstorm already ran CPO/CLO/CTO/COO/CMO/CCO/CFO + repo-research + learnings. Plan-time repo-research and learnings-researcher **failed 402** (Grok Build usage balance exhausted). Findings below are from that brainstorm plus orchestrator greps on this worktree. Do not treat the 402 as “no remaining gaps.”

**External research.** Skipped — local adapter, eval, and ADR-110 spec already exist.

**Community discovery / functional overlap.** Not re-spawned (402). Stack is already Soleur plugin + `harness.ts`; this plan completes shipped Phase A–F, it does not import a new community skill.

### Dual-voice pattern (copy this)

`plugins/soleur/lib/harness.ts` `invokeSkill()` / `routingInstructions()`. Skills that already dual-voice: `commands/go.md`, `skills/brainstorm/SKILL.md`, `skills/one-shot/SKILL.md`, `skills/ship/SKILL.md`, `skills/plan/SKILL.md` (anti-bypass header). Claude branch keeps **Skill tool** `soleur:<skill>`. Grok branch says slash `/<skill>` meaning **Read that SKILL.md in-process**.

Skill-tool-only (or Claude-qualified only) call sites to dual-voice, re-derived this session:

| File | Evidence |
|------|----------|
| `skills/review/SKILL.md` | `skill: soleur:compound` / `skill: soleur:ship`; pipeline detection keys on `skill: soleur:work` |
| `skills/qa/SKILL.md` | usage `skill: soleur:qa` |
| `skills/compound/SKILL.md` | usage block `skill: soleur:compound` |
| `skills/drain-labeled-backlog/SKILL.md` | `Use the Skill tool: skill: soleur:one-shot` |
| `skills/drain-prs/SKILL.md` | `/soleur:review` + Monitor tool, no AwaitShell |
| `skills/work/SKILL.md` | Phase 4 still `skill: soleur:review` … `ship` despite Grok anti-bypass header |

### Eval surface today

`plugins/soleur/scripts/grok-fidelity-gate.sh` runs: agent-budget lint, `sync-grok-agent-compat.ts --check`, `bun test test/grok-inspect-contract.test.ts test/go-routing-golden-path.test.ts test/workflow-fidelity.test.ts test/pr-merge-poll.test.ts`. `harness.test.ts` and `grok-agent-discoverability.test.ts` ride `test-bun`, not this gate.

`workflow-fidelity.test.ts` asserts sentinels and `invokeSkill` under `grokTestEnv()`. It does **not** fail a pipeline SKILL.md that only says “Use the Skill tool.”

### Plugin-root

`commands/go.md` Step 0.0/0 and `commands/sync.md` key `${CLAUDE_PLUGIN_ROOT}`. `plugins/soleur/hooks/hooks.json` commands are `${CLAUDE_PLUGIN_ROOT}/hooks/…`. Grok stubs use `${GROK_PLUGIN_ROOT}` in `agent-registry.ts`. Detection order in `detectHarness`: `CLAUDECODE` then `GROK_HOME`/`GROK_AGENT`/`GROK_DEFAULT_MODEL`/`GROK_SUBAGENTS`.

### Hooks

`.claude/settings.json` matchers include `Skill`, `Monitor`, `Monitor|TaskStop`, `AskUserQuestion`, `Task`, plus many `Bash`. Grok tool names in this session: `run_terminal_command`, `ask_user_question`, `spawn_subagent`. No Skill tool. No Monitor tool.

### ADR-110

`knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md` Status **Proposed**. Spec `knowledge-base/project/specs/feat-harness-model-map/spec.md` PR2: `harness-model-map.ts`, tests, workflow `agent()` wrapper, `workflow-model-pins.test.ts` still allowlists `"sonnet"`/`"haiku"` only.

### Docs / legal

- Getting-started: `plugins/soleur/docs/pages/getting-started.njk` (`last_updated: 2026-06-01`) teaches `claude plugin …` and `/soleur:go`.
- Canonical legal: `docs/legal/{terms-and-conditions,privacy-policy,data-protection-disclosure,gdpr-policy,acceptable-use-policy}.md` — “Claude Code plugin.”
- Eleventy mirrors: `plugins/soleur/docs/pages/legal/*.md`.
- 3-way lockstep: also `apps/web-platform/lib/legal/legal-doc-shas.ts` (`2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md`).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|------------|---------|---------------|
| Dual-voice all pipeline skills | 5 of the locked list are still Skill-tool-only; go/brainstorm/one-shot/ship already dual-voice | Edit the 5 + work Phase 4; do not rewrite go.md invoke table except plugin-root |
| `harness-model-map.ts` | File absent; #6316 closed as docs | Implement ADR-110 PR2 in this plan |
| Hook matcher ports | Skill/Monitor/AskUserQuestion/Task never fire on Grok | Alias only names that exist; Monitor/Skill are documented skips |
| Nested slash invoke | No Grok tool | Honest contract in every dual-voice header |
| Public docs after eval | getting-started is Claude-only today | Sequence: eval green on same stack before njk/README/legal |

## Problem Statement

Epic #6320 closed claiming Skill→slash parity. Grok still has no nested Skill tool. A live `/go` session classified correctly then Read SKILL.md. Claude Code skill/hook/ship work since 2026-07-10 has no Grok counterpart. Public getting-started and legal copy still define Soleur as a Claude Code plugin. That is a single-user incident: wrong commands, skipped hooks, or inlined pipeline.

## Proposed Solution

One sequenced spec (#8064). Dual-voice via existing `harness.ts`. Implement ADR-110. Additive hook aliases. Plugin-root fallback. Public docs and legal lockstep only after `grok-fidelity` asserts Skill-tool-only pipeline files fail.

## Technical Approach

### Architecture

Keep one plugin. `detectHarness()` already splits Claude vs Grok. Skills must call `invokeSkill()` language, not hardcode Skill tool. Model pins go through `resolveModelTier()`. Session-start bash uses a single `PLUGIN_ROOT` expansion: `GROK_PLUGIN_ROOT` → `CLAUDE_PLUGIN_ROOT` → `./plugins/soleur`.

Do not add a Grok Skill-tool shim. Do not edit `apps/web-platform/server/agent-runner.ts`.

### Implementation Phases

#### Phase 1 — Dual-voice + eval (FR1–FR3)

- Add a `workflow-fidelity` (or sibling) test that, for each name in `PIPELINE_SKILLS` ∪ `HANDOFF_SKILLS` ∪ `IMPLEMENTATION_TAIL` ∪ `{plan,postmerge}`, reads `skills/<name>/SKILL.md` (or `commands/go.md` for go) and fails if the file contains `Skill tool` / `skill: soleur:` **and** contains neither `harness.ts` nor a Grok slash branch (`/plan`, `slash_command`, `invokeSkill`).
- Dual-voice the Skill-tool-only files listed above. Preserve Claude Skill-tool wording in the Claude branch.
- Pipeline-detection strings in review/work that key only on `skill: soleur:work` must also match `/work` and `slash_command` so Grok in-process runs still count as pipeline mode.
- Enroll the new test in `grok-fidelity-gate.sh`. Optionally enroll `harness.test.ts` in the same bun test line (cheap).
- **Success:** `bash plugins/soleur/scripts/grok-fidelity-gate.sh` green; a one-line revert of the review dual-voice header turns the new test red.

#### Phase 2 — Plugin-root (FR5)

- Introduce a documented expansion used by `go.md` Step 0.0/0, `sync.md` probes, and `hooks/hooks.json` if Grok interpolates it: `PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}}"`.
- Identity check stays “plugin.json name is soleur”, not path shape (#7474).
- **Success:** with `CLAUDECODE` unset and `GROK_HOME` set, the Step 0.0 probe is not `source=probe-unreachable reason=plugin-root-unverified` when `./plugins/soleur/.claude-plugin/plugin.json` exists.

#### Phase 3 — ADR-110 (FR4)

- Add `plugins/soleur/lib/harness-model-map.ts` and `plugins/soleur/test/harness-model-map.test.ts` per `feat-harness-model-map/spec.md`.
- Migrate `workflow-model-pins.test.ts` allowlist `sonnet`/`haiku` → `standard`/`cheap`; resolve in each `*.workflow.js` `agent()` helper before spawn.
- Research agents: pass `cheap` at call site until spawn APIs accept frontmatter `model: cheap`.
- `plan` Step 4.5 / `ship` Phase 5.5 use `advisor` via resolver, not raw `fable`.
- Flip ADR-110 to **Accepted**.
- Live Grok model id strings: confirm at `/work` against current xAI docs (`https://docs.x.ai/build/…`) — do not freeze a guessed SKU in this plan. Tests use fixture maps.
- **Success:** `resolveModelTier("cheap"|"standard"|"strong"|"advisor", "claude"|"grok")` returns non-empty; Claude pins still behave as haiku/sonnet/opus/fable in the Claude fixture.

#### Phase 4 — Hook aliases (FR6)

Additive matchers in `.claude/settings.json` (and plugin `hooks.json` if Grok loads it):

| Claude matcher | Grok alias | Action |
|----------------|------------|--------|
| `Bash` | `run_terminal_command` | Add `Bash\|run_terminal_command` (Grok already maps Bash→run_terminal_cmd per onboarding; verify live, do not drop `Bash`) |
| `AskUserQuestion` | `ask_user_question` | Add both |
| `Task` | `spawn_subagent` | Add both |
| `Write`/`Edit` | keep; confirm Grok edit tool names (`search_replace` / `write`) and alias if PreToolUse does not fire |
| `Skill` | none | Grok has no Skill tool. Keep Claude matcher. Document skip; emit `SOLEUR_HOOK_SKIP harness=grok matcher=Skill reason=no-tool` from a SessionStart note in grok-onboarding, not a fake matcher |
| `Monitor` / `TaskStop` | none | Grok poll path is Shell/AwaitShell (`pollInstructions("grok")`). Document skip. drain-prs dual-voice must tell Grok to use AwaitShell, not Monitor |

**Success:** a Grok `ask_user_question` PreToolUse hits the same hook command as Claude `AskUserQuestion`. Claude matchers still present (grep `Skill` and `Monitor` unchanged as tokens).

#### Phase 5 — Docs after eval (FR7–FR8)

Only after Phases 1–3 tests are green on this branch:

- Refresh `knowledge-base/engineering/grok-onboarding.md` (date this change): `/go` not `/soleur:go`; `grok --trust`; user-config `[subagents]`; filename-stem spawn; in-process SKILL.md contract; refuse xAI CLI “improve the product and model” for non-personal repos.
- Getting-started: two-column command table on the **existing** page (`getting-started.njk`) — not a new layout. Allowed: “Same plugin. Claude Code: `/soleur:go`. Grok Build: `/go`.” Forbidden: “full Grok support”, “zero configuration”.
- Root `README.md` + `plugins/soleur/README.md` same table.
- CLI tokens verified this session: `/go` (this run), `grok --trust` and `grok inspect` cited from `knowledge-base/engineering/grok-onboarding.md` (2026-07-10) and xAI docs `https://docs.x.ai/build/overview`. Re-verify `--help` at `/work` if the binary is on PATH.

#### Phase 6 — Legal harness-neutral plugin copy (FR9)

3-way lockstep in the same PR (`2026-05-29-legal-doc-triple-lockstep…`):

- Canonical `docs/legal/{terms-and-conditions,privacy-policy,data-protection-disclosure,gdpr-policy,acceptable-use-policy}.md`
- Eleventy `plugins/soleur/docs/pages/legal/<same>.md` (hero + body Last Updated)
- `apps/web-platform/lib/legal/legal-doc-shas.ts`

Replace exclusive “Claude Code plugin” with harness-neutral plugin language (“Claude Code or Grok Build plugin”). Document `grok --trust` as a confidentiality TOM. **Do not** add xAI as a customer sub-processor or Third-Party Services path.

AUP § Anthropic flow-down: add a Grok/xAI AUP link for Grok runtime users; keep Anthropic for Claude. Still not a processor row.

## Files to Edit

- `plugins/soleur/lib/workflow-fidelity.ts` (test helper export if needed)
- `plugins/soleur/test/workflow-fidelity.test.ts`
- `plugins/soleur/scripts/grok-fidelity-gate.sh`
- `plugins/soleur/skills/review/SKILL.md`
- `plugins/soleur/skills/qa/SKILL.md`
- `plugins/soleur/skills/compound/SKILL.md`
- `plugins/soleur/skills/drain-labeled-backlog/SKILL.md`
- `plugins/soleur/skills/drain-prs/SKILL.md`
- `plugins/soleur/skills/work/SKILL.md`
- `plugins/soleur/commands/go.md`
- `plugins/soleur/commands/sync.md`
- `plugins/soleur/hooks/hooks.json`
- `.claude/settings.json`
- `plugins/soleur/test/workflow-model-pins.test.ts`
- `plugins/soleur/skills/plan/SKILL.md` (advisor spawn via resolver)
- `plugins/soleur/skills/ship/SKILL.md` (advisor spawn via resolver)
- workflow `*.workflow.js` under `plugins/soleur/skills/` that pin `sonnet`/`haiku` (enumerate at `/work` via `git grep -l "sonnet\|haiku" -- 'plugins/soleur/**/*.workflow.js'`)
- `knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/views.c4` (views that include `platform.engine.claude` at views.c4 lines containing that token)
- `knowledge-base/engineering/grok-onboarding.md`
- `plugins/soleur/docs/pages/getting-started.njk`
- `README.md`
- `plugins/soleur/README.md`
- `docs/legal/terms-and-conditions.md`
- `docs/legal/privacy-policy.md`
- `docs/legal/data-protection-disclosure.md`
- `docs/legal/gdpr-policy.md`
- `docs/legal/acceptable-use-policy.md`
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md`
- `plugins/soleur/docs/pages/legal/privacy-policy.md`
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`
- `apps/web-platform/lib/legal/legal-doc-shas.ts`

## Files to Create

- `plugins/soleur/lib/harness-model-map.ts`
- `plugins/soleur/test/harness-model-map.test.ts`

## Alternative Approaches Considered

| Approach | Verdict |
|----------|---------|
| User types each next `/skill` | Rejected — autonomy loss; operator chose in-process Read |
| `spawn_subagent` owns each stage | Rejected — different UX, still no Skill return |
| Wait for xAI nested invoke | Rejected — leaves the live `/go` failure |
| Docs/legal first | Rejected — operator chose eval-then-docs |
| Equal umbrella of ACP + GPU | Rejected — operator chose Track 1 only |

## User-Brand Impact

- **If this lands broken, the user experiences:** `/go` in Grok Build, public getting-started `/soleur:go`, or PreToolUse hooks that never arm
- **If this leaks, the user's workflow / repo content is exposed via:** inlined pipeline (skip review/ship), untrusted session (`grok --trust` skipped), or xAI CLI training opt-in on a non-personal repo
- **Brand-survival threshold:** `single-user incident`

Carry-forward from brainstorm Phase 0.1. Artifact = Soleur plugin workflows under Grok Build.

## Observability

Touches `plugins/soleur/scripts/` and hooks — Phase 2.9 applies.

```yaml
liveness_signal:
  what: required GitHub check grok-fidelity (grok-fidelity-gate.sh)
  cadence: every PR touching plugins/soleur
  alert_target: PR check failure (merge blocked)
  configured_in: .github/workflows/ci.yml job grok-fidelity
error_reporting:
  destination: CI logs on the grok-fidelity job; stdout SOLEUR_HOOK_SKIP / SOLEUR_GIT_REPO_DIAG
  fail_loud: grok-fidelity-gate.sh exits non-zero; probe prints source=probe-unreachable
failure_modes:
  - mode: pipeline SKILL.md regresses to Skill-tool-only
    detection: new workflow-fidelity file-content assertion
    alert_route: grok-fidelity required check
  - mode: Grok session takes plugin-root fallback
    detection: SOLEUR_GIT_REPO_DIAG source=probe-unreachable in session transcript
    alert_route: existing Better Stack mirror of SOLEUR_* (server-side hook)
  - mode: Grok AskUserQuestion hook silent-off
    detection: matcher alias missing; PreToolUse does not run
    alert_route: grok-fidelity unit test on settings.json matcher strings
logs:
  where: GitHub Actions grok-fidelity job logs; local bun test output
  retention: GitHub Actions default for the repo
discoverability_test:
  command: bash plugins/soleur/scripts/grok-fidelity-gate.sh
  expected_output: bun tests pass and script exits 0
```

No soak-gated close criterion — no follow-through enrollment.

## Guard Contract

### Guard 1 — pipeline skills are not Skill-tool-only

**Property.** Every locked pipeline/handoff SKILL.md that mentions Skill-tool invocation also mentions the Grok harness adapter or a Grok slash branch.

**Assembly.** The chokepoint is one test in `plugins/soleur/test/workflow-fidelity.test.ts` that iterates `PIPELINE_SKILLS ∪ HANDOFF_SKILLS ∪ IMPLEMENTATION_TAIL ∪ {plan, postmerge}` and reads each skill file from `plugins/soleur/skills/<name>/SKILL.md` (go from `plugins/soleur/commands/go.md`). The test is invoked from `plugins/soleur/scripts/grok-fidelity-gate.sh` (the bun test argv). No second inventory.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the Grok/`harness.ts` sentences from `skills/review/SKILL.md`, leave `skill: soleur:compound` | RED |
| 2 | Change the test to iterate an empty list (dispatch 0 files) while still exiting 0 | RED (vacuous dispatch) |
| 3 | Add `skills/incident/SKILL.md` to the locked set in the test without dual-voicing that file | RED (second member after a compliant first) |
| 4 | Harness: comment out the `expect` that fails on Skill-tool-only, leave the file walk | RED |
| 5 | Must-PASS: `skills/brainstorm/SKILL.md` as it exists (already dual-voice) | PASS |

Write the matrix in the test file as named cases before implementing the walker.

### Guard 2 — Claude Skill/Monitor matchers remain

**Property.** `.claude/settings.json` still contains matcher tokens `Skill` and `Monitor` after alias edits.

**Assembly.** One test (same `workflow-fidelity.test.ts` or `harness.test.ts`) reads `.claude/settings.json` and asserts those substrings. Chokepoint: that JSON file’s `hooks.PreToolUse` array.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `"matcher": "Skill"` object | RED |
| 2 | Test greps a file that is not settings.json and reports 0 matchers yet exits 0 | RED |
| 3 | Add a second PreToolUse file (plugin hooks.json) to the locked set and drop Skill there if it currently has none — if hooks.json has no Skill matcher, do not add this row; instead mutate settings.json by renaming `Skill` to `skill` (case) | RED |
| 4 | Harness: assertion uses `toContain("S")` only | RED |
| 5 | Must-PASS: current settings.json with additive `AskUserQuestion\|ask_user_question` | PASS |

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Operations, Marketing, Support, Finance

Carry-forward from brainstorm `## Domain Assessments` (no fresh leader spawn; 402).

### Engineering

**Status:** reviewed
**Assessment:** Nested invoke does not exist; inspect CI ≠ pipeline fidelity. Implement ADR-110. Alias only real Grok tool names. Do not start ACP or fake GEX as hcloud.

### Legal

**Status:** reviewed
**Assessment:** Plugin fidelity is disclosure + Art. 32 TOM (`grok --trust`), not a new processor. No xAI customer sub-processor row. Live xAI CLI training opt-in must be in onboarding. Lockstep legal copy.

### Operations

**Status:** reviewed
**Assessment:** Track 1 ≈ $0 vendor. `GROK_SUBAGENTS=1` is user config. No new expense row.

### Marketing

**Status:** reviewed
**Assessment:** Allowed after eval: “Same plugin. Claude: `/soleur:go`. Grok: `/go`.” Forbidden: “full Grok support”, echoing xAI “zero configuration.”

### Support

**Status:** reviewed
**Assessment:** Public getting-started is Claude-only; Discord already has a Grok contributor. Slash collisions (`/review`, `/plan`) need a FAQ line in onboarding.

### Finance

**Status:** reviewed
**Assessment:** No budget hold for Track 1.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted for copy-on-existing-page (getting-started table). Mechanical glob `*.njk` matches `getting-started.njk`; brainstorm excluded “pure copy / no new layout.” If `/work` creates a new Eleventy layout or page, stop and run the BLOCKING wireframe path (`wg-ui-feature-requires-pen-wireframe`).
**Agents invoked:** none (402; CPO already signed Track 1 at brainstorm)
**Skipped specialists:** spec-flow-analyzer, ux-design-lead, copywriter (no new UI layout; copy table only)
**Pencil available:** N/A (no new UI surface)

**Brainstorm-recommended specialists:** spec-flow-analyzer for `/go` handoff without Skill tool — covered by Guard 1 + dual-voice; not a Pencil surface.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-110** in this plan: Status Proposed → Accepted when `harness-model-map.ts` and pin migration land. Do not pick a new ordinal. Sweep `knowledge-base/project/{plans,specs}/feat-grok-build-claude-parity/` and `feat-harness-model-map/` if any leftover “Proposed” claims remain.

### C4 views

Read `model.c4`, `views.c4`, `spec.c4`.

- **External human actor:** founder already modeled.
- **External system:** Claude Code is `platform.engine.claude` (container “Agent Runtime”). **Grok Build CLI is not modeled.** Add a sibling container `grokBuild` (or softwareSystem) “Grok Build harness” under the same engine parent: loads the same `plugin` via `.grok/config.toml`, not Concierge `agent-runner`.
- **Relationships:** `founder -> grokBuild` (`grok --trust`, `/go`); `grokBuild -> plugin` (skills/agents/hooks). Do **not** edge Concierge/web to grokBuild (that is #6547).
- **Views:** `views.c4` includes `platform.engine.claude` in at least two views (lines 34 and 62). Add `platform.engine.grokBuild` to those same `include` lists so it renders.
- **Cardinalities:** no new cron/monitor; run `apps/web-platform/test/c4-count-parity.test.sh` after the model edit (expected: still green if no count prose changed).
- After edit: `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing

ADR-110 becomes true in Phase 3 of this PR, not a follow-up issue.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (65 issues) contained none of: `plugins/soleur/lib/harness.ts`, `workflow-fidelity.ts`, `commands/go.md`, `skills/review/SKILL.md`, `getting-started.njk`, `docs/legal/terms-and-conditions.md`, `.claude/settings.json`.

## GDPR / Compliance

Phase 2.7 trigger **(b)** brand-survival `single-user incident` fired. Canonical regex (schemas/auth/API) does not. CLO brainstorm: no new processor; disclosure + TOM only.

Live `/gdpr-gate` skill was **not** re-invoked (Grok 402). Carry-forward CLO actions that remain in this plan: harness-neutral legal copy; `grok --trust` TOM; onboarding training-opt-in warning. **Out of this plan:** `data-processing-agreements/xai.md`, Art. 30 xAI PA, customer ACP.

## Acceptance Criteria

### Functional

- [ ] AC1: For each locked skill file in Guard 1’s assembly, `bun test plugins/soleur/test/workflow-fidelity.test.ts` fails if Grok/harness sentences are removed and Skill-tool sentences remain.
- [ ] AC2: `dispatchGoRoute("fix", …, claudeTestEnv())` still uses Skill tool `soleur:one-shot` (`go-routing-golden-path.test.ts` existing Claude case stays green).
- [ ] AC3: `plugins/soleur/lib/harness-model-map.ts` exists; `resolveModelTier` returns non-empty for `cheap|standard|strong|advisor` × `claude|grok` fixtures; ADR-110 Status line is `Accepted`.
- [ ] AC4: `git grep -n 'sonnet\|haiku' -- plugins/soleur/test/workflow-model-pins.test.ts` no longer treats those as the only pinnable workflow tiers (allowlist is semantic `cheap`/`standard`).
- [ ] AC5: `go.md` Step 0.0 uses a fallback that includes `./plugins/soleur` when `CLAUDE_PLUGIN_ROOT` is unset; identity check still requires plugin.json name soleur.
- [ ] AC6: `.claude/settings.json` contains `ask_user_question` and `spawn_subagent` as matcher tokens **and** still contains `"matcher": "Skill"` and `"matcher": "Monitor"`.
- [ ] AC7: `getting-started.njk` contains `/go` and `/soleur:go` in the same section; does not contain the substring `full Grok support` or `zero configuration`.
- [ ] AC8: `docs/legal/terms-and-conditions.md` no longer defines Soleur exclusively as “a Claude Code plugin” (must mention Grok Build); Eleventy mirror date matches; `legal-doc-shas.ts` updated. `git grep -n 'xAI' -- docs/legal/` does not add a sub-processor / Third-Party Services customer-path row.

### Quality gates

- [ ] AC9: `bash plugins/soleur/scripts/grok-fidelity-gate.sh` exits 0 on this branch.
- [ ] AC10: Guard 1 mutation 1 (strip Grok sentences from review SKILL.md in a throwaway copy) is encoded as a test that would fail — not a manual checklist.

## Test Scenarios

- Given a pipeline SKILL.md with only `skill: soleur:compound`, when the fidelity test runs, then it fails.
- Given brainstorm SKILL.md as on main (dual-voice), when the same test runs, then it passes.
- Given Claude env `CLAUDECODE=1`, when `invokeSkill("plan")` runs, then command is `soleur:plan` not `/plan`.
- Given Grok env `GROK_HOME=1` and no `CLAUDECODE`, when `invokeSkill("plan")` runs, then command is `/plan`.
- Given ADR-110 Claude fixture, when tier `cheap` resolves, then value is `haiku`.
- Given settings.json after Phase 4, when grepping matcher Skill, then count ≥ 1.

No browser QA for the getting-started table beyond Eleventy build if `/work` touches `.njk` (existing `deploy-docs` screenshot gate applies if critical CSS changes — this table should not).

## Success Metrics

- grok-fidelity required check green
- No Claude Skill-tool eval regression
- Public `/go` vs `/soleur:go` table exists only on a commit where AC1 is green

## Dependencies & Risks

- xAI live model IDs for the Grok fixture map — confirm at `/work`, do not guess in this plan
- Grok matcher string for Write/Edit may differ (`search_replace`); verify with a one-line Grok session or docs before aliasing
- Legal 3-way lockstep can fail CI if shas/mirrors/dates drift
- Plan-review panel was not run (402). `/work` must not start until the operator runs `/plan-review` or accepts that residual. See Session Errors.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|------|------------|
| Dual-voice rewrite drops Claude Skill tool | AC2 + Guard 2 |
| Fake Monitor matcher | Cut List — documented skip |
| Docs before eval | Phase 5 gated on Phase 1–3 |
| Legal over-claims xAI processor | AC8 forbids xAI sub-processor row |

## Documentation Plan

Onboarding, getting-started, READMEs, legal lockstep, ADR-110 Accepted, C4 grokBuild container — all in this PR after eval.

## Session Errors

1. Plan-time `repo-research-analyst` and `learnings-researcher` returned **402 Payment Required: Grok Build usage balance exhausted**. Orchestrator grepped the worktree instead. Re-run those agents under Claude or a funded Grok session if this plan is challenged.
2. `plan-review` panel not executed for the same 402. At `single-user incident` the skill wants DHH + Kieran + simplicity + architecture-strategist + spec-flow. **Operator: run `/plan-review` on this file before `/work`, or explicitly skip.**

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6. This section is filled.
- Do not `git add` the whole `knowledge-base/project/plans/` directory at commit — add this file only.
- `AskUserQuestion` in skills should say: Claude `AskUserQuestion` tool; Grok `ask_user_question` tool (this session’s tool name).
- drain-prs Monitor-only polling: Grok uses AwaitShell per `pollInstructions("grok")`.

## References & Research

- Spec: `knowledge-base/project/specs/feat-grok-build-claude-parity/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-09-11-grok-build-claude-parity-brainstorm.md`
- ADR-110, spec `feat-harness-model-map`
- `plugins/soleur/lib/harness.ts`, `workflow-fidelity.ts`
- Learnings: `2026-07-11-grok-go-routes-one-shot-but-inlines-pipeline.md`, `2026-07-17-grok-spawn-subagent-filename-stem-not-colon-name.md`, `2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md`
- Issues: #8064 (this), #6320 CLOSED, #6316 CLOSED docs-only, #6547/#6546/#7882 parked
- Draft PR: #8061
