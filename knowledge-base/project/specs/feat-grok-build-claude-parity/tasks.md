# Tasks: feat-grok-build-claude-parity

Lane: `cross-domain`. Closes #8064.

## Phase 1: Adapter + dual-voice + eval

- [x] 1.1 `harness.ts` `invokeSkill()` Grok instruction + `workflowFidelityInstructions("grok")`: in-process Read **is** the invoke
- [x] 1.2 `go.md` Step 2.1 same; `/soleur:go` recovery one-liner; Grok fail copy is not Concierge
- [x] 1.3 Anti-bypass headers on brainstorm/plan/one-shot/work: do not forbid Grok Read
- [x] 1.4 Guard 1: `harness.ts`/`invokeSkill()` + in-process-Read sentence; header-only dual-voice must-RED; include `deepen-plan`
- [x] 1.5 Handoff-site dual-voice: review, qa, compound, drain-labeled-backlog, drain-prs (AwaitShell), work Phase 4
- [x] 1.6 Pipeline-detection matches `skill: soleur:X` or `/X` or `slash_command`
- [ ] 1.7 `bash plugins/soleur/scripts/grok-fidelity-gate.sh` exits 0

## Phase 2: Plugin-root

- [ ] 2.1 `go.md` Step 0.0/0: `ROOT="${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"` — no `:-` CWD default, no `sync.md` `:-`
- [ ] 2.2 Empty root still emits `plugin-root-unverified`

## Phase 3: ADR-110 (in this PR)

- [ ] 3.1 Create `plugins/soleur/lib/harness-model-map.ts` + `test/harness-model-map.test.ts` (reuse `detectHarness()`)
- [ ] 3.2 Confirm Grok fixture model ids against live xAI docs (do not guess in the plan)
- [ ] 3.3 Update `workflow-model-pins.test.ts` allowlist to `cheap`/`standard`
- [ ] 3.4 Resolve tiers in `agent()` of:
  - `skills/deepen-plan/workflows/deepen-plan.workflow.js`
  - `skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js`
  - `skills/plan-review/workflows/plan-review.workflow.js`
  - `skills/resolve-parallel/workflows/resolve-parallel.workflow.js`
  - `skills/resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js`
  - `skills/resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js`
  - `skills/review/workflows/review.workflow.js`
- [ ] 3.5 `plan` Step 4.5 and `ship` Phase 5.5 spawn `advisor` via resolver
- [ ] 3.6 ADR-110 Status → Accepted
- [ ] 3.7 C4: `grokBuild` as a **local** harness (not under Cloud CLI Engine); run c4 syntax/render + `c4-count-parity.test.sh`

## Phase 4: Hook aliases

- [ ] 4.1 Duplicate matcher objects with exact Grok names (`run_terminal_command`, `ask_user_question`, `spawn_subagent`, `search_replace`/`write`) — no regex-OR
- [ ] 4.2 No fake Skill or Monitor matchers; skip `reason=no-tool` vs `reason=untrusted-session`
- [ ] 4.3 Guard 2: Skill and Monitor tokens still present

## Phase 5: Docs (after Phases 1–2 green)

- [ ] 5.1 Refresh `grok-onboarding.md` from **live** `grok --help` (no `--trust` on this host)
- [ ] 5.2 Four-row table on existing getting-started `#self-hosted` after install, before callouts; dual-voice callouts + Skill-tool sentence + FAQ/JSON-LD; no hero/AEO edit
- [ ] 5.3 Same table in `README.md` and `plugins/soleur/README.md`
- [ ] 5.4 Confirm trust token (`/hooks-trust` vs Claude-compat settings) before any public TOM sentence

## Phase 6: Legal lockstep — PARKED (follow-up issue)

- [ ] 6.1 Canonical `docs/legal/{terms-and-conditions,privacy-policy,data-protection-disclosure,gdpr-policy,acceptable-use-policy}.md` harness-neutral plugin copy
- [ ] 6.2 Eleventy mirrors `plugins/soleur/docs/pages/legal/<same>.md` (hero + body dates)
- [ ] 6.3 Update `apps/web-platform/lib/legal/legal-doc-shas.ts`
- [ ] 6.4 No xAI customer sub-processor row (`git grep xAI docs/legal/` has no new processor table)

## Phase 7: Testing

- [ ] 7.1 Guard 1 mutations (including vacuous dispatch) encoded as tests
- [ ] 7.2 `bash plugins/soleur/scripts/grok-fidelity-gate.sh`
- [ ] 7.3 Claude golden-path case still green
