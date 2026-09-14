# feat-devin-cloud-session-parity — tasks

Plan: `knowledge-base/project/plans/2026-09-14-feat-devin-cloud-session-parity-plan.md` · Issue: #8159 · PR: #8155

## Phase 0 — Empirical cloud probe (operator-gated, FR9)

- [ ] Record the pre-probe credential determination BEFORE the session: whose Devin account, billing entity, reachable API keys. Jikigai-limb positive → escalate to CLO first (D10 pre-emptive).
- [ ] Record Art. 30 determination: PA-37 entry or written out-of-scope note; one-paragraph DPIA-screening note in `cloud-probe.md`.
- [ ] Run one `/handoff` or web-app cloud session on this repo (operator-credentialed test scope, no personal data, non-identifying signals only).
- [ ] `cloud-probe.md` records, each with evidence: Q1 repo-level hooks per-event (SessionStart + PostToolUse/Stop markers); `ask_user_question` behavior in unattended sessions (auto-approve / stall / distinguishable-unanswered — freezes FR4 mechanism); per-hook per-matcher binding (`Bash` vs `exec`); repo-level `requiredPlugins` install + unknown-key tolerance; `/handoff` `.devin/` sync; `run_subagent` artifact output; `DEVIN*` env incl. exec-shell + session-id var; `.claude/settings.json`; `PostCompaction`; plugin command-hook execution + `hook_source`.
- [ ] Finalize FR4 mechanism, FR5 scope, matrix rows, Art. 30 wording from measured data.

## Phase 1 — Detection + sentinel + requiredPlugins (FR1, FR6)

- [ ] `devin-session-start.sh`: unconditional content-bearing sentinel write `{host, ts, hook_source}` → `.devin/soleur-local-session`; git-root resolution + `mkdir -p`; `|| true`-guarded after the `additionalContext` emit.
- [ ] `plugins/soleur/scripts/cloud-detect.sh`: the ONE classifier — `local` (sentinel + host match + `hook_source=plugin`) or `not-local:<reason>`; single `hostname` source; no `jq` dependency; fail closed.
- [ ] `plugins/soleur/test/devin-cloud-mode.test.ts`: `local` arm + every `not-local` reason + never-value.
- [ ] `.devin/config.json`: `"requiredPlugins": ["jikig-ai/soleur#plugins/soleur"]` + pre-merge unknown-key tolerance validation.
- [ ] `bun test plugins/soleur/test/` green.

## Phase 2 — Contract surfaces + one wiring pass (FR2, FR3, FR4, TR2, TR3)

- [ ] `devin/INSTRUCTIONS.md` §Cloud Mode: canonical contract (banner disclosure + fallback degrade path + ack posture + absent-guardrail disclosure) — loaded via the go shim on routed sessions.
- [ ] `plugins/soleur/AGENTS.md`: cloud-mode rules section (`[id:]` convention).
- [ ] `plugins/soleur/scripts/cloud-banner.sh`: per-invocation emit, delegates to `cloud-detect.sh`.
- [ ] Grep-derive union set: spawn-sites ∪ secrets/prod ∪ directly-invocable pipeline skills (must include compound, code-to-prd, frontend-design, product-roadmap, spec-templates, work, preflight, one-shot, brainstorm, plan, schedule, community, pencil-setup, rclone; verify gdpr-gate/skill-creator).
- [ ] One composite `<!-- soleur-cloud-mode:start/end -->` pointer block per union-set SKILL.md.
- [ ] `emit-review-trailer.sh`: `sequential-fallback` enum widen; flag in deliverables + PR trailers.
- [ ] `ship` gate: `sequential-fallback` coverage on `single-user incident` plans = blocking.

## Phase 3 — Skill-internal guardrails (FR5)

- [ ] `plugins/soleur/scripts/precommit-guard.sh`: self-contained commit-on-main check (~40 lines), exec'd by work/ship/one-shot; no vendored lib, no DONE-marker arm.
- [ ] `.claude/hooks/guardrails.sh`: commit-on-main block delegates to `precommit-guard.sh`.
- [ ] Verify in a repo lacking `.claude/`; enumerate unrestored guards for the matrix.

## Phase 4 — Capability matrix + upstream requests (FR7, FR10)

- [ ] `devin/INSTRUCTIONS.md`: cloud-vs-local matrix (per-event hook granularity incl. matcher-binding, subagents, MCP, repo hooks per probe), unrestored-guard enumeration, upstream request register (#8160).
- [ ] README + `plugins/soleur/README.md` matrix pointers.

## Phase 5 — Legal disclosures (FR8, TR6)

- [ ] Floor: correct affirmatively-false statements (DPD §3.1(a), §2.1(c)); name the third configuration; DPD §2.1c fifth table row.
- [ ] CLO decides the ceiling: corpus-wide three-configuration taxonomy vs floor-only.
- [ ] Art. 30 per-entry audit amendments; record plugin-hook control absence, probe-informed wording.
- [ ] Probe-conditional named Cognition disclosure; `compliance-posture.md` row + D10 record; TC_VERSION tier question to CLO.
- [ ] Eleventy mirrors; `legal-doc-shas.ts` repins; `legal-doc-consistency.test.ts` + `check-tc-document-sha.sh` green; CLO sign-off.

## Phase 6 — ADR + C4 + verification session

- [ ] ADR (provisional ordinal — re-derive vs `origin/*`, re-verify before merge): "Soleur Cloud Mode — sentinel-based surface detection and honest-degradation contract."
- [ ] `model.c4`/`views.c4`: `devin` external system + `founder→devin`, `devin→platform.plugin` edges; `c4-count-parity` green.
- [ ] Spec notes: FR1 "sibling lib" reading; NG5 revision for `PostCompaction` (probe-conditional).
- [ ] Second post-implementation cloud session verifies SC1/SC3/SC4; file follow-up issues for post-merge ACs (issue not auto-closed).
- [ ] `npx markdownlint-cli2` on touched `.md`; `lint-guard-contract.py` passes.
