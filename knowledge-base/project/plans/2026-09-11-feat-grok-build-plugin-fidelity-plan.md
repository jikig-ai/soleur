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

Make Soleur's Grok Build plugin path match the current Claude Code lifecycle without regressing Claude. Grok has no nested Skill/slash tool: after `/go` classifies, the parent Reads the next SKILL.md **in-process**. That Read **is** the invoke. The adapter (`harness.ts` + `workflowFidelityInstructions("grok")` + `go.md` Step 2.1) must say so — today they still forbid Read. Dual-voice is a short harness block plus handoff-site `invokeSkill()` citations, not a full-body rewrite. Plugin-root prefers `GROK_PLUGIN_ROOT` then `CLAUDE_PLUGIN_ROOT` with **no** CWD default. Hook aliases are exact-name duplicates. Docs/legal after eval. Web ACP and GPU stay parked.

CPO sign-off at plan time: granted 2026-09-11 under Track 1 / eval-then-docs / no Phase 4 promotion. `user-impact-reviewer` runs at PR review.

## Plan Review Revisions (2026-09-11)

Panel: DHH, code-simplicity, architecture-strategist, spec-flow, CPO, CMO, UX, CTO. **Kieran 402** (not run). Mechanical findings auto-applied below. Taste / User-Challenge listed at the end of this section for the operator gate.

**Mechanical (applied):**

1. Honest Grok invoke lives in `harness.ts` `invokeSkill()` + `workflowFidelityInstructions("grok")` + `go.md` Step 2.1 + existing anti-bypass headers (brainstorm/plan/one-shot/work). Grok: Read `skills/<name>/SKILL.md` in-process and run it to completion. Forbidden is **selective** execution, not the Read. Claude keeps “do not Read SKILL.md; use the Skill tool.”
2. Dual-voice = 8–12 line harness block citing `invokeSkill()` / `routingInstructions()`, plus **handoff/pipeline-detection sites**. Do not twin every `skill: soleur:` sentence in 1k-line bodies.
3. Guard 1 pins `harness.ts` or `invokeSkill()` **and** an in-process-Read sentence on the Grok branch. A header that mentions `harness.ts` while Phase 4 still says only `skill: soleur:review` must go **red**. Slash-token OR is forbidden (review/work already contain `/ship` and would pass). Do not add `incident` as a locked member.
4. Plugin-root: `ROOT="${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"` with **no** `:-./plugins/soleur` (ADR-179 / #7442 / `test-sync-producer-reachability.sh` T0b). Empty → keep `probe-unreachable`. Do not add `:-` to `sync.md`. Local Grok fail copy is not Concierge “Settings → Repository.”
5. Hook aliases: **duplicate matcher objects** with exact Grok tool names (`run_terminal_command`, `ask_user_question`, `spawn_subagent`, and measured Write/Edit names). Do not OR into Claude regex until matcher grammar is measured. Write/Edit aliases are in-scope (ADR-089), not a `/work` spike. Skill/Monitor: no fake matcher. Distinct markers: `reason=no-tool` vs `reason=untrusted-session`.
6. Cut: optional `harness.test.ts` on grok-fidelity-gate; research-agent `cheap` call sites; AUP extra xAI flow-down as a required AC; `SOLEUR_HOOK_SKIP` as a new SessionStart hook (onboarding sentence is enough for no-tool).
7. C4: if `grokBuild` is added, it is a **local harness** loading `plugin` via `.grok/config.toml`, **not** a child of Cloud CLI Engine `platform.engine`. No `api`/`hetzner` edges. (Whether C4 ships in this PR is coupled to ADR-110 — User-Challenge below.)
8. Live CLI (this host, `grok --help`): **no `--trust` flag**. `--always-approve` and `--no-subagents` exist. Do **not** freeze `grok --trust` into legal copy. `/work` must confirm which token arms Soleur PreToolUse (`/hooks-trust` vs Claude-compat `.claude/settings.json`) before Phase 5/6.

**Taste / User-Challenge (resolved 2026-09-11):** operator chose **keep ADR-110, park legal**. Phase 3 + C4 local `grokBuild` stay in this PR. Phase 6 legal lockstep is deferred until `/work` confirms a live trust token (this `grok --help` has no `--trust`). Do not freeze `grok --trust` into T&C.

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
- Fake Monitor matcher for a tool Grok does not have → documented skip.
- CWD/`:-./plugins/soleur` plugin-root default → ADR-179 single-user incident (#7442).
- Regex-OR matcher strings (`Bash|run_terminal_command`) until Grok matcher grammar is measured.
- `grok --trust` in legal copy until `/work` confirms a live CLI token (`grok --help` on this host has no `--trust`).
- Optional `harness.test.ts` enrollment; research-agent `cheap` call sites; AUP extra xAI link as an AC.

**Phase 1 fan-out.** Brainstorm already ran CPO/CLO/CTO/COO/CMO/CCO/CFO + repo-research + learnings. Plan-time repo-research and learnings-researcher **failed 402** (Grok Build usage balance exhausted). Findings below are from that brainstorm plus orchestrator greps on this worktree. Do not treat the 402 as “no remaining gaps.”

**External research.** Skipped — local adapter, eval, and ADR-110 spec already exist.

**Community discovery / functional overlap.** Not re-spawned (402). Stack is already Soleur plugin + `harness.ts`; this plan completes shipped Phase A–F, it does not import a new community skill.

### Dual-voice pattern (copy this)

`plugins/soleur/lib/harness.ts` `invokeSkill()` / `routingInstructions()`. Skills that already dual-voice: `commands/go.md`, `skills/brainstorm/SKILL.md`, `skills/one-shot/SKILL.md`, `skills/ship/SKILL.md`, `skills/plan/SKILL.md` (anti-bypass header). Claude branch keeps **Skill tool** `soleur:<skill>` and **forbids** reading SKILL.md as a substitute. Grok branch: **Read** `plugins/soleur/skills/<name>/SKILL.md` in-process and execute it to completion — that Read is the invoke. Do not write “invoke `/name` as a nested tool_use” or “do not Read SKILL.md” on the Grok branch.

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

One sequenced spec (#8064). Fix the adapter first (`harness.ts` + fidelity instructions + go.md Step 2.1) so Grok’s sanctioned next action is in-process Read. Dual-voice headers + handoff sites. Plugin-root env fallback with no CWD default. Exact-name hook aliases. Docs after eval. ADR-110 and legal lockstep stay in the plan pending the operator User-Challenge (DHH cut vs CPO/architecture keep).

## Technical Approach

### Architecture

Keep one plugin. `detectHarness()` already splits Claude vs Grok. The **invoke contract** is `harness.ts` + `workflow-fidelity.ts`, not SKILL.md folklore. Skills cite `invokeSkill()`. Session-start: `ROOT="${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"` with no CWD default. Model pins go through `resolveModelTier()` **if** Phase 3 stays in this PR.

Do not add a Grok Skill-tool shim. Do not edit `apps/web-platform/server/agent-runner.ts`.

### Implementation Phases

#### Phase 1 — Adapter contract + dual-voice + eval (FR1–FR3)

- Change `invokeSkill()` Grok `instruction` and `workflowFidelityInstructions("grok")`: Read `plugins/soleur/skills/<name>/SKILL.md` in this process and run it to completion. Forbidden = selective execution, not the Read.
- `go.md` Step 2.1: same. Claude branch unchanged.
- Anti-bypass headers on brainstorm/plan/one-shot/work: Grok REQUIRED line must not forbid in-process Read.
- Dual-voice Skill-tool-only **handoff sites** (8–12 line harness block + Phase 4 / drain / review pipeline-detection). Do not twin every `skill: soleur:` sentence.
- Pipeline-detection inventory: review, work Phase 4, qa, compound, ship, one-shot child steps, plan exit — match `skill: soleur:X` **or** `/X` **or** `slash_command`.
- Guard 1: locked set includes `deepen-plan`. Fail unless file cites `harness.ts` or `invokeSkill()` **and** Grok branch has an in-process-Read sentence. Header-only dual-voice on work Phase 4 must-RED. Cases live in existing `workflow-fidelity.test.ts` (already in grok-fidelity-gate).
- Sharp edge in `go.md`: if the operator typed `/soleur:go`, say Grok’s entry is `/go`.
- **Success:** fidelity gate green; stripping the in-process-Read sentence from `review/SKILL.md` reds Guard 1; Claude golden-path Skill-tool case stays green.

#### Phase 2 — Plugin-root (FR5)

- `go.md` Step 0.0/0 only: `ROOT="${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"`. Empty → keep `plugin-root-unverified`. Identity = plugin.json name soleur.
- Do not add `:-./plugins/soleur`. Do not add `:-` to `sync.md`. Do not change `hooks.json` until interpolation is measured.
- Fail copy when Grok env is set: local checkout / `grok inspect` should list soleur — not Concierge Settings → Repository.
- **Success:** both env vars unset still emits `plugin-root-unverified`. `GROK_PLUGIN_ROOT` pointing at `plugins/soleur` is ready.

#### Phase 3 — ADR-110 (FR4)

**In this PR** (operator 2026-09-11).

- `harness-model-map.ts` + tests. Reuse `detectHarness()` from `harness.ts` (not `GROK_SESSION`).
- `workflow-model-pins.test.ts` allowlist → `cheap`/`standard`; resolve in the seven `*.workflow.js` `agent()` helpers already enumerated.
- plan Step 4.5 / ship Phase 5.5 use `advisor` via resolver.
- ADR-110 Status → Accepted. Fixture maps only; live SKUs at `/work`.
- Do not pass `cheap` at research-agent call sites in this PR.

#### Phase 4 — Hook aliases (FR6)

Duplicate matcher **objects** (exact Grok names). Do not write `Bash|run_terminal_command` as one string.

| Claude matcher | Grok exact name | Action |
|----------------|-----------------|--------|
| `Bash` | `run_terminal_command` | Duplicate object |
| `AskUserQuestion` | `ask_user_question` | Duplicate object |
| `Task` | `spawn_subagent` | Duplicate object |
| `Write` / `Edit` | `search_replace` / `write` (this session) | Duplicate — in-scope ADR-089 |
| `Skill` | none | Keep Claude; skip `reason=no-tool` |
| `Monitor` | none | Keep Claude; drain-prs Grok = AwaitShell |

Untrusted session: `reason=untrusted-session` + one user line naming the **live** trust token. This host’s `grok --help` has no `--trust`.

**Success:** settings.json still has `"matcher": "Skill"` and `"matcher": "Monitor"` and exact `ask_user_question` / `spawn_subagent` strings.

#### Phase 5 — Docs after eval (FR7–FR8)

Only after Phases 1–2 tests are green (Phase 3 if kept):

- Refresh `grok-onboarding.md` with **live** tokens from `/work` (`grok --help` this session: no `--trust`; `--no-subagents` exists; subagents are user-config). In-process Read contract. Training-opt-in refusal. Slash-collision FAQ (`/help` `/plan` `/review`). Fail-loud: hooks armed? spawn available?
- Getting-started: four-row table (go/sync/help/next-skill) on the **existing** page in `#self-hosted` **after** the Claude install block and **before** the Existing/Starting-fresh callouts. Do not edit hero, waitlist CTA, or AEO definition. No new layout/CSS. No `.pen`. Forbidden: `full Grok support`, `zero configuration`, `out of the box`, Grok “two commands”. Caption: “Claude Code: `/soleur:go`. Grok Build: `/go`.” Dual-voice the existing `/soleur:go` callouts, workflow “Skill tool” sentence, and the `/soleur:go` FAQ + FAQPage JSON-LD in the **same** file (otherwise the table fights the rest of the page). Bump `last_updated`.
- Same four-row table in root `README.md` and `plugins/soleur/README.md`.
- Do not launch (no “Grok support” changelog/social).
- Do not freeze a trust CLI token into public copy until `/work` confirms it.

#### Phase 6 — Legal (FR9) — PARKED

Deferred from this PR until a live Grok trust/hooks token is confirmed. Residual: five canonical legal docs plus cookie-policy and disclaimer still say “Claude Code plugin.” Do not claim legal is harness-neutral. Follow-up: document in-place here (net-issue-flow hook blocked a dedicated issue). Re-open when the live Grok trust token is confirmed.

## Files to Edit

- `plugins/soleur/lib/harness.ts` (Grok `invokeSkill` instruction)
- `plugins/soleur/lib/workflow-fidelity.ts` (`workflowFidelityInstructions("grok")`)
- `plugins/soleur/test/workflow-fidelity.test.ts`
- `plugins/soleur/skills/brainstorm/SKILL.md` (Grok anti-bypass: allow in-process Read)
- `plugins/soleur/skills/plan/SKILL.md` (same; advisor spawn only if Phase 3 kept)
- `plugins/soleur/skills/one-shot/SKILL.md` (same)
- `plugins/soleur/skills/review/SKILL.md`
- `plugins/soleur/skills/qa/SKILL.md`
- `plugins/soleur/skills/compound/SKILL.md`
- `plugins/soleur/skills/drain-labeled-backlog/SKILL.md`
- `plugins/soleur/skills/drain-prs/SKILL.md`
- `plugins/soleur/skills/work/SKILL.md`
- `plugins/soleur/commands/go.md` (Step 2.1 + Step 0.0 + `/soleur:go` recovery copy)
- `.claude/settings.json`
- `knowledge-base/engineering/grok-onboarding.md`
- `plugins/soleur/docs/pages/getting-started.njk`
- `README.md`
- `plugins/soleur/README.md`

Phase 3 only (if ADR-110 stays): `harness-model-map.ts` (create), `harness-model-map.test.ts` (create), `workflow-model-pins.test.ts`, seven `*.workflow.js` pin files already listed in tasks.md, ADR-110 status, C4 `grokBuild` as a local harness (not under `platform.engine`), `skills/ship/SKILL.md` advisor spawn.

Phase 6 only (if legal stays): five `docs/legal/*.md` + Eleventy mirrors + `legal-doc-shas.ts`. No cookie/disclaimer unless CLO expands.

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
- **If this leaks, the user's workflow / repo content is exposed via:** inlined pipeline (skip review/ship), untrusted session (hooks never armed), or xAI CLI training opt-in on a non-personal repo
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

**Property.** Every locked pipeline/handoff SKILL.md cites `harness.ts` or `invokeSkill()` and its Grok branch contains an in-process-Read sentence. Header-only dual-voice with Skill-tool-only handoff sites is not enough.

**Assembly.** One test in `plugins/soleur/test/workflow-fidelity.test.ts` iterates `PIPELINE_SKILLS ∪ HANDOFF_SKILLS ∪ IMPLEMENTATION_TAIL ∪ {plan, postmerge, deepen-plan}` and reads `plugins/soleur/skills/<name>/SKILL.md` (go from `plugins/soleur/commands/go.md`). Invoked from `grok-fidelity-gate.sh` bun argv. No second inventory.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the in-process-Read sentence from `skills/review/SKILL.md`, leave `skill: soleur:compound` | RED |
| 2 | Change the test to iterate an empty list and still exit 0 | RED (vacuous dispatch) |
| 3 | Add `skills/qa/SKILL.md` to the locked set (already in union) without an in-process-Read sentence | RED (second member) |
| 4 | Harness: comment out the `expect` that fails, leave the file walk | RED |
| 5 | Must-PASS: a file with harness block + in-process-Read + Claude Skill-tool example (brainstorm after Phase 1 header fix) | PASS |
| 6 | Header mentions `harness.ts` but work Phase 4 handoff sites remain Skill-tool-only | RED |

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
- **External system:** Claude Code is `platform.engine.claude`. **Grok Build CLI is not modeled.** If C4 ships in this PR, add `grokBuild` as a **local harness** that loads `plugin` via `.grok/config.toml` — **not** a child of Cloud CLI Engine `platform.engine` (that parent inherits Hetzner + `api → claude`).
- **Relationships:** `founder -> grokBuild` (`/go`); `grokBuild -> plugin`. Do **not** edge Concierge/web to grokBuild (#6547). Do not inherit `hetzner`/`api` edges.
- **Views:** add `grokBuild` only to views that should show the local plugin CLI, not every view that includes `platform.engine.claude`.
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
- [ ] AC5: `go.md` Step 0.0 uses `GROK_PLUGIN_ROOT` then `CLAUDE_PLUGIN_ROOT` with **no** `:-` CWD default; identity check still requires plugin.json name soleur; empty root still emits `plugin-root-unverified`.
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

1. Plan-time `repo-research-analyst` and `learnings-researcher` returned **402**. Orchestrator grepped the worktree instead.
2. Plan-review **Kieran 402**. Other eight panel seats completed; mechanical findings applied 2026-09-11. Kieran correctness pass is still missing — `/work` should treat unverified CLI/AC wording as suspect.
3. Live `grok --help` (this host) has **no `--trust`**. July onboarding and this plan’s first draft froze a token the binary does not accept.

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
