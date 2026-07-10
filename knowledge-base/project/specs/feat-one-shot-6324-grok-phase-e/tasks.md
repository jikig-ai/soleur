# Tasks: Phase E — 68 agents discoverable in grok inspect (#6324)

> **Count note:** 67 load-bearing agents per `discoverAgents()`; 68th on-disk file is `agents/operations/references/service-deep-links.md` (excluded).

## Phase 0 — Spike & plugin enablement

- [ ] 0.1 Run baseline `grok inspect` from worktree root; capture disabled-state + agent count in session notes
- [ ] 0.2 Spike which compat surface Grok loads (`.grok/agents/soleur/*.md` vs manifest-only vs extra plugin path)
- [ ] 0.3 Fix `.grok/config.toml` / symlink so inspect shows soleur plugin enabled (non-disabled)
- [ ] 0.4 Document `[subagents] enabled = true` requirement in grok-onboarding.md (user config)

## Phase 1 — Agent registry

- [ ] 1.1 Add `plugins/soleur/lib/agent-registry.ts` (`pathToAgentId`, `discoverAgentEntries`)
- [ ] 1.2 Add `plugins/soleur/test/agent-registry.test.ts` (count, uniqueness, nested ID samples, references exclusion)
- [ ] 1.3 Refactor `harness.ts` to use registry for ID derivation (single source of truth)

## Phase 2 — Compat sync + artifacts

- [ ] 2.1 Add `plugins/soleur/scripts/sync-grok-agent-compat.ts` (`--check`, `--verbose`)
- [ ] 2.2 Generate and commit `.claude-plugin/agents.manifest.json`
- [ ] 2.3 Generate and commit `.grok/agents/soleur/` compat stubs (thin defer-to-source)
- [ ] 2.4 Update CONTRIBUTING.md with sync-after-agent-add workflow

## Phase 3 — Docs & discoverability tests

- [ ] 3.1 Update `knowledge-base/engineering/grok-onboarding.md` (remove Phase E caveat; add inspect + spawn examples)
- [ ] 3.2 Add `plugins/soleur/test/grok-agent-discoverability.test.ts` (local grok inspect gate; skip when grok absent)
- [ ] 3.3 Export `EXPECTED_SOLEUR_AGENT_COUNT` / manifest path constant for Phase F (#6325)
- [ ] 3.4 Manual verify: `grok inspect` count ±0 vs manifest; trial spawn_subagent for one review agent

## Phase 4 — Ship

- [ ] 4.1 `cd plugins/soleur && bun test test/agent-registry.test.ts test/harness.test.ts test/grok-agent-discoverability.test.ts`
- [ ] 4.2 Commit plan + tasks + implementation; PR body references #6324, epic #6320