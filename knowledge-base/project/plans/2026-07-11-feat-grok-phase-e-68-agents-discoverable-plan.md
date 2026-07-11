---
title: "feat(grok): Phase E — 68 agents discoverable in grok inspect"
type: feat
date: 2026-07-11
lane: cross-domain
related_issues: ["#6320", "#6324", "#6325"]
---

# feat(grok): Phase E — 68 agents discoverable in grok inspect

## Enhancement Summary

**Deepened on:** 2026-07-11  
**Sections enhanced:** Overview, Proposed Solution, Acceptance Criteria, Risks, Observability  
**Research agents used:** Live `grok inspect`, `feature-dev` plugin structure comparison, Grok settings/docs fetch, `discoverAgents()` probe, issue state verification (`gh issue view`)

### Key Improvements

1. **Root cause pinned:** Grok lists flat `feature-dev` agents (`agents/*.md`) but zero nested `soleur:*` agents — compat stubs + manifest required; not a harness.ts bug.
2. **Count reconciled:** 67 load-bearing agents (`discoverAgents()`); 68th file is `agents/operations/references/service-deep-links.md` (excluded by loader filter).
3. **Enablement gap:** Inspect shows `soleur (project, disabled)` despite `enabled = ["soleur"]` — Phase 0 must fix before counting agents.
4. **Phase F boundary:** CI contract test explicitly deferred to #6325; this phase exports manifest + `EXPECTED_SOLEUR_AGENT_COUNT` constant.
5. **Subagents config:** `[subagents] enabled` belongs in user `~/.grok/config.toml` (project scope cannot set it per xAI docs).

### New Considerations Discovered

- `GROK_SUBAGENTS=1` or user `[subagents] enabled = true` is prerequisite for `spawn_subagent` at runtime (already noted in `harness.ts:160`).
- Thin compat stubs must defer to `${GROK_PLUGIN_ROOT}/agents/...` to avoid 67-way body duplication drift (AC7).
- Post-edit self-audit: no stale `tenant_cost_window` / dropped symbols in plan (N/A).

**Epic:** #6320 Grok Build fidelity — /go routes to Soleur workflows without improvisation

**Parent sequencing:** Phases A–C (#6321–#6323) are **closed**. Phase D (#6316 / ADR-110) is separate. **This issue is Phase E.** Phase F (#6325) adds CI contract tests on top of this deliverable — do not duplicate Phase F CI work here.

## Overview

`grok inspect` today lists **zero** Soleur domain agents in the `Agents` section and reports `soleur (project, disabled) … 1 agents` under `Plugins`, while Claude Code discovers **67** load-bearing agents recursively under `plugins/soleur/agents/**` (68 `.md` files on disk; `discoverAgents()` excludes `references/`). Workflows (`/review`, `/plan`, `/deepen-plan`, `/go`) spawn qualified IDs like `soleur:engineering:review:security-sentinel`, but Grok `spawn_subagent` cannot target them until they appear in inspect.

This plan ships an **agent registry + Grok compat layer** so every recursive agent file is registered with the same qualified IDs Claude uses, `grok inspect` agent count matches the registry (±0), and `spawn_subagent` can target domain agents.

### Research Insights

**Best Practices:**
- Treat agent discovery as a **registration surface** separate from authoring — same class as `SKILL_CATEGORIES` drift (`2026-02-19-growth-strategist` learning). Automate with `--check` generator.
- Phase 0 **loader spike** before bulk moves (pattern from `2026-02-12-plugin-loader-agent-vs-skill-recursion.md`).
- Canonical source remains `plugins/soleur/agents/**`; `.grok/agents/` is generated compat only (mirror Phase C `.grok/plugins` symlink precedent).

**Implementation Details:**
- Qualified ID algorithm (verified against 67 agents):
  ```typescript
  // agents/engineering/review/security-sentinel.md
  // → soleur:engineering:review:security-sentinel
  const rel = path.replace(/^agents\//, "").replace(/\.md$/, "");
  return "soleur:" + rel.split("/").join(":");
  ```
- `feature-dev` reference layout (flat, all visible in inspect):
  ```text
  ~/.grok/marketplace-cache/.../feature-dev/agents/code-reviewer.md
  → inspect: feature-dev:code-reviewer
  ```
- Excluded from registry: `plugins/soleur/agents/operations/references/service-deep-links.md` (references dir).

**Edge Cases:**
- New agent without `bun run scripts/sync-grok-agent-compat.ts` → inspect regression; `--check` fails in CI (Phase F).
- Plugin `disabled` in inspect → zero agents even with stubs; AC3 blocks ship.
- `grok` absent in CI → discoverability test skips locally; Phase F adds runner image with grok CLI.

**References:**
- <https://docs.x.ai/build/features/skills-plugins-marketplaces> — plugin agent discovery paths
- <https://docs.x.ai/build/settings/reference> — `[subagents]`, `[plugins] enabled`, compat scanners
- `knowledge-base/project/learnings/2026-02-12-plugin-loader-agent-vs-skill-recursion.md`

## Premise Validation (plan Phase 0.6)

| Cited artifact | Live check | Result |
|----------------|------------|--------|
| #6324 (target) | `gh issue view 6324` | `OPEN`, no merged closer |
| #6320 (epic) | `gh issue view 6320` | `CLOSED` (tracking epic; children remain valid) |
| #6325 (Phase F) | `gh issue view 6325` | `OPEN` — CI scope deferred to Phase F |
| Phases A–C | `gh issue view 6321/6322/6323` | All `CLOSED` — prerequisites met |
| `plugins/soleur/lib/harness.ts` | present on branch | `spawnAgent` → `spawn_subagent` for Grok |
| `plugins/soleur/agents/**` | `find … \| wc -l` | 68 `.md` files; `discoverAgents()` → **67** |
| `grok inspect` baseline | run from worktree root | `Agents` section: **0** `plugin: soleur` rows; `Plugins`: `soleur (project, disabled) … 1 agents` |
| Nested-agent hypothesis | compare `feature-dev` (flat `agents/*.md`, 3 agents visible) vs Soleur (nested `agents/<domain>/<fn>/*.md`, 0 visible) | Grok plugin agent scan likely **non-recursive or not registering nested paths** — compat layer required |
| Branch safety | `git branch --show-current` | `feat-one-shot-6324-grok-phase-e` (not main) |

**Premise Validation note:** All cited premises hold. Problem is confirmed live: inspect shows ~1 agent metadata vs 67 discoverable under Claude semantics. Plan shape is *build compat layer*, not *fix a single broken agent file*.

## Research Reconciliation — Spec vs. Codebase

| Issue/spec claim | Codebase reality | Plan response |
|------------------|------------------|---------------|
| "68 agents" | 68 `.md` on disk; **67** in `discoverAgents()` (excludes `agents/**/references/`) | Registry uses `discoverAgents()` as canonical; AC targets **67** with explicit carve-out for `references/` |
| "Agent manifest / compat scan fixes" | No manifest exists; no compat stubs | Add `agent-registry.ts` + `sync-grok-agent-compat` script + committed manifest/stubs |
| `spawn_subagent` for `soleur:engineering:review:*` | `harness.ts` emits correct IDs; agents not in inspect | Register agents so inspect + spawn surface align |
| Plugin enabled in `.grok/config.toml` | `enabled = ["soleur"]` set but inspect shows **disabled** | Phase 0 diagnoses enablement; fix config/symlink/path precedence |
| Phase F CI | Not implemented | Out of scope; export constants for Phase F consumer |

## User-Brand Impact

**If this lands broken, the user experiences:** Under Grok, `/go` or `/review` routes spawn `spawn_subagent` for `soleur:engineering:review:security-sentinel` (etc.) but the agent is missing — workflows fall back to improvisation or fail silently, losing multi-agent review fidelity in every Grok session.

**If this leaks, the user's workflow is exposed via:** Misrouted subagent prompts (wrong or generic agent handles security/legal review) — not a data/payment leak.

**Brand-survival threshold:** `none` — plugin harness/discoverability only; no prod user data, billing, or sensitive paths.

## Observability

```yaml
liveness_signal:
  what: "agent-registry unit tests + optional local grok inspect agent-count assertion"
  cadence: "on PR touching plugins/soleur/agents/**, lib/agent-registry.ts, scripts/sync-grok-agent-compat*, .grok/**"
  alert_target: "CI test failure (plugins/soleur bun test); operator manual inspect before Grok sessions"
  configured_in: "plugins/soleur/test/agent-registry.test.ts; plugins/soleur/test/grok-agent-discoverability.test.ts"

error_reporting:
  destination: "bun test stderr + non-zero exit; sync script stderr on manifest drift"
  fail_loud: "test failure when registry count ≠ discoverAgents(); sync script exits non-zero on write drift in CI mode"

failure_modes:
  - mode: "New nested agent added without re-running compat sync — inspect count regresses"
    detection: "agent-registry.test.ts count parity; grok-agent-discoverability.test.ts (local-only) compares inspect count to manifest"
    alert_route: "PR author runs `bun run scripts/sync-grok-agent-compat.ts --check`; Phase F CI will hard-gate"
  - mode: "Plugin remains disabled in inspect — zero agents despite manifest"
    detection: "discoverability_test command parses `Plugins` line for `soleur` not `disabled`"
    alert_route: "manual grok inspect before ship; documented in grok-onboarding.md"
  - mode: "Qualified ID drift between harness.ts and registry"
    detection: "agent-registry.test.ts asserts `pathToAgentId` samples match harness `normalizeAgentName` contract"
    alert_route: "unit test failure"

logs:
  where: "bun test stdout; sync script stdout when run with --verbose"
  retention: "per-run (CI/GitHub Actions logs)"

discoverability_test:
  command: "cd plugins/soleur && bun test test/agent-registry.test.ts 2>&1 | tail -5 && cd ../.. && grok inspect 2>&1 | rg 'soleur.*agents|Agents \\(' | head -20"
  expected_output: "agent-registry tests pass (0 fail); inspect shows soleur plugin enabled and agent count ≥ 67 (or soleur-qualified rows in Agents section)"
```

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (local analysis)

**Assessment:** Pure plugin harness/discoverability. No data model, UI, or infra. Aligns with epic layers 5–6. Precedent: Phase B `harness.ts` adapter; Phase C routing contract. Low blast radius if compat stubs are generated, not hand-duplicated.

### Product/UX Gate

**Tier:** NONE — no UI-surface files; orchestration/plugin change only.

## Open Code-Review Overlap

None.

## Proposed Solution

### Root cause (empirical)

1. **Nested layout:** Soleur agents live at `agents/<domain>/<function>/<name>.md` (30+ at depth ≥3). Reference plugin `feature-dev` uses flat `agents/<name>.md` and all three appear in `grok inspect`. Grok's plugin agent scanner does not surface Soleur's nested files in the `Agents` list.
2. **Enablement:** Project plugin reports `disabled` in inspect despite `enabled = ["soleur"]` in `.grok/config.toml` — must fix so compat artifacts load.
3. **ID contract:** Claude qualifies nested paths as `soleur:<path-segments-colon-separated>`. Grok `spawn_subagent` must accept the same strings once registered.

### Architecture

```text
plugins/soleur/agents/**/**/*.md  (source of truth, unchanged)
        │
        ▼
lib/agent-registry.ts  ← discoverAgents() + pathToAgentId()
        │
        ▼
scripts/sync-grok-agent-compat.ts  (deterministic generator)
        │
        ├── .claude-plugin/agents.manifest.json  (qualified id → path, for inspect/CI)
        └── .grok/agents/soleur/<qualified-id>.md  (thin compat stubs OR symlinks — format validated in Phase 0 spike)
        │
        ▼
grok inspect  → 67 soleur agents listed, spawn_subagent targets work
```

**Thin stub shape (default):** frontmatter with `name` matching qualified ID + `description`/`model` copied from source; body is a single line: `Read and follow the instructions in ${GROK_PLUGIN_ROOT}/agents/<relative-path>.` — avoids duplicating 67 agent bodies.

### Phase 0 — Spike & enablement (blocking)

1. Run `grok inspect` and document exact failure modes (disabled plugin, agent count, sample missing IDs like `soleur:engineering:review:security-sentinel`).
2. Test which compat surface Grok loads:
   - (a) `.grok/agents/soleur/*.md` project agents
   - (b) extra `[plugins] paths` entry
   - (c) manifest-only without stubs
3. Fix plugin **enabled** state until inspect shows `soleur (project, enabled)` (or equivalent non-disabled).
4. Ensure subagents enabled: document `[subagents] enabled = true` in `knowledge-base/engineering/grok-onboarding.md` (user `~/.grok/config.toml`; project config cannot set `[subagents]` per docs).

### Phase 1 — Agent registry module

- Add `plugins/soleur/lib/agent-registry.ts`:
  - `pathToAgentId(relativePath: string): string` — `agents/engineering/review/security-sentinel.md` → `soleur:engineering:review:security-sentinel`
  - `discoverAgentEntries(): { id, path, name, description, model }[]`
  - Reuse `discoverAgents()` / `parseComponent()` from `test/helpers.ts` (extract shared import or duplicate minimally to avoid test-only import in prod — prefer moving discovery helpers to `lib/` if needed).
- Add `plugins/soleur/test/agent-registry.test.ts`:
  - Count === `discoverAgents().length`
  - All IDs unique
  - Sample nested ID matches `harness.ts` `normalizeAgentName` behavior
  - Excludes `references/`

### Phase 2 — Compat sync script + artifacts

- Add `plugins/soleur/scripts/sync-grok-agent-compat.ts`:
  - Writes `.claude-plugin/agents.manifest.json` (sorted, schema-versioned)
  - Writes compat stubs under `.grok/agents/soleur/` (or winning path from Phase 0 spike)
  - Flags: `--check` (CI/Phase F), `--verbose`
- Wire into `plugins/soleur/package.json` or document in README as pre-commit step for agent edits.
- Commit generated artifacts (deterministic; no timestamps in JSON).

### Phase 3 — Harness + docs alignment

- Update `plugins/soleur/lib/harness.ts` to import `pathToAgentId` from registry (single source of truth for ID derivation).
- Update `knowledge-base/engineering/grok-onboarding.md`:
  - Post-Phase E inspect expectation: 67 agents
  - `spawn_subagent` example with `soleur:engineering:review:security-sentinel`
  - `[subagents] enabled = true` requirement
- Update `CONTRIBUTING.md` Grok section: run sync script after adding agents.
- Update `plugins/soleur/commands/help.md` if agent spawn guidance needed.

### Phase 4 — Tests & manual verification

- Add `plugins/soleur/test/grok-agent-discoverability.test.ts`:
  - **Local gate:** if `grok` on PATH, parse inspect output; assert soleur agent count ≥ manifest length
  - **CI-safe:** skip with message when `grok` absent (Phase F adds required CI)
- Run `bun test` for harness + agent-registry + discoverability.
- Manual: `grok inspect | rg soleur` and trial `spawn_subagent` for one review agent from `/review` skill path.

## Files to Edit

- `plugins/soleur/lib/harness.ts` — delegate ID derivation to registry
- `plugins/soleur/test/helpers.ts` — optional: extract shared discovery to `lib/` (if needed)
- `knowledge-base/engineering/grok-onboarding.md` — inspect + spawn docs
- `CONTRIBUTING.md` — compat sync workflow
- `plugins/soleur/commands/help.md` — optional spawn example
- `.grok/config.toml` — enablement/path fixes from Phase 0

## Files to Create

- `plugins/soleur/lib/agent-registry.ts`
- `plugins/soleur/scripts/sync-grok-agent-compat.ts`
- `plugins/soleur/.claude-plugin/agents.manifest.json` (generated)
- `.grok/agents/soleur/*.md` (generated compat stubs — count = 67)
- `plugins/soleur/test/agent-registry.test.ts`
- `plugins/soleur/test/grok-agent-discoverability.test.ts`

## Out of Scope (Phase F — #6325)

- Required CI check that fails on inspect regression
- Golden-path `/go` → `/one-shot` eval under Grok harness fixture
- Changing agent prompt bodies or domain directory layout
- Flattening `agents/` tree (would break Claude path-qualified IDs)

## Acceptance Criteria

- [ ] **AC1 (registry parity):** `cd plugins/soleur && bun test test/agent-registry.test.ts` passes; `discoverAgentEntries().length === discoverAgents().length` (67 at time of writing).
- [ ] **AC2 (manifest):** `.claude-plugin/agents.manifest.json` exists, lists every registry entry with `id`, `path`, `name`, `description`, `model`; `bun run scripts/sync-grok-agent-compat.ts --check` exits 0.
- [ ] **AC3 (inspect count):** From repo/worktree root, `grok inspect 2>&1` shows soleur plugin **enabled** and agent count matching manifest length (±0). Verification snippet:
  ```bash
  grok inspect 2>&1 | rg 'soleur'
  # Expect: non-disabled soleur plugin line with agents count = 67
  ```
- [ ] **AC4 (qualified IDs):** Inspect `Agents` section includes nested examples, e.g. `soleur:engineering:review:security-sentinel` (or `plugin: soleur` row for that id — exact format documented in Phase 0 spike).
- [ ] **AC5 (spawn contract):** `harness.ts` `spawnAgent('engineering:review:security-sentinel', …)` under `GROK_SUBAGENTS=1` emits `spawn_subagent` with agent `soleur:engineering:review:security-sentinel`; `bun test test/harness.test.ts` passes.
- [ ] **AC6 (docs):** `grok-onboarding.md` updated — no "fewer agents until Phase E" caveat; adds sync-script + subagents enable steps.
- [ ] **AC7 (no duplication):** `git grep -l 'You are an elite Application Security' .grok/agents/` returns 0 files (stubs defer to source, not copy bodies).
- [ ] **AC8 (Phase F handoff):** Export `EXPECTED_SOLEUR_AGENT_COUNT` (or manifest path) constant for Phase F CI test — document in plan/tasks, no CI wiring in this PR.

## Test Scenarios

- Given a new agent at `agents/engineering/review/new-reviewer.md`, when `sync-grok-agent-compat.ts` runs, then manifest and compat stubs include `soleur:engineering:review:new-reviewer`.
- Given `grok` on PATH, when `grok-agent-discoverability.test.ts` runs, then inspect soleur agent count ≥ manifest length.
- Given `GROK_SUBAGENTS` unset, when `spawnAgent` called, then instruction still names correct agent id (enablement note present).
- Given `references/` agent files, when registry runs, then they are excluded from manifest.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Grok compat surface unknown | Phase 0 spike before bulk stub generation |
| Manifest drift on agent add | `--check` mode + CONTRIBUTING.md + Phase F CI |
| Duplicate agent bodies in stubs | Thin defer-to-source stub pattern; AC7 grep |
| Plugin disabled regression | AC3 inspect line; config.toml fix |
| Count 67 vs 68 marketing drift | Document: 67 load-bearing; `stats.js` counts all `.md` including `operations/references/service-deep-links.md` |
| Grok CLI version drift | Pin minimum grok version in onboarding when inspect format changes; Phase F CI pins |

### Precedent-Diff Gate (pattern-bound compat stubs)

No in-repo precedent for Grok agent compat stubs. Pattern is **novel** — reviewers should scrutinize stub frontmatter shape and inspect output format. Closest precedent: eval-harness projection scripts (`extract-block.cjs` / `gated-skills.json`) — generated artifacts with `--check`, canonical source elsewhere.

**Verify-the-negative pass:** Plan claims harness already maps `spawn_subagent` for Grok — confirmed `plugins/soleur/lib/harness.ts:152-162` (`tool: "spawn_subagent"`, `agent: agentId`). No contradiction.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty will fail `deepen-plan` Phase 4.6 — filled above.
- Do not edit `plugin.json` version sentinel (`0.0.0-dev`).
- Sources of truth remain under `plugins/soleur/`; `.grok/agents/` stubs are generated compat — edit agents in `plugins/soleur/agents/`, then re-run sync.
- Phase F (#6325) owns CI — do not add required `grok inspect` CI check in this PR.

## References

- #6320 epic, #6324 (this issue), #6325 (CI follow-up)
- `knowledge-base/engineering/grok-onboarding.md`
- `plugins/soleur/lib/harness.ts`
- `plugins/soleur/test/helpers.ts` (`discoverAgents`)
- Learning: `knowledge-base/project/learnings/2026-02-12-plugin-loader-agent-vs-skill-recursion.md`
- Learning: `knowledge-base/project/learnings/workflow-patterns/2026-07-11-grok-fidelity-self-referential-go-under-grok.md`
- Prior plan: `knowledge-base/project/plans/2026-07-11-feat-grok-phase-c-go-md-eval-harness-plan.md`