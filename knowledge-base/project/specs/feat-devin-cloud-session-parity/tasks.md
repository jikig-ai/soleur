# feat-devin-cloud-session-parity — tasks

Plan: `knowledge-base/project/plans/2026-09-14-feat-devin-cloud-session-parity-plan.md` · Issue: #8159 · PR: #8155

## Phase 0 — Empirical cloud probe (operator-gated, FR9)

- [x] `cloud-probe.md` scaffolded with pre-probe credential-determination table, Art. 30 slot, DPIA-screening section, and the full 15-item checklist; deferral tracked by #8172.
- [x] Record the pre-probe credential determination BEFORE the session: whose Devin account, billing entity, reachable API keys. Jikigai-limb positive → escalate to CLO first (D10 pre-emptive). — Done 2026-09-15: operator confirmed all limbs personal (Jean Deruelle personal account, personal billing, no Jikigai-issued keys). D10 not engaged.
- [x] Record Art. 30 determination: PA-37 entry or written out-of-scope note; one-paragraph DPIA-screening note in `cloud-probe.md`. — Written out-of-scope determination + DPIA-screening paragraph recorded (no personal data processed).
- [x] Run one `/handoff` or web-app cloud session on this repo (operator-credentialed test scope, no personal data, non-identifying signals only). — TWO arms ran 2026-09-15: `devin cloud drs` sandbox `devin-b9cf2c02cc8f49debdbc49ed72cdf2b5` AND a user-facing web-app session `4c574cf0fa594527bb3f9650c05b74a7` (checkout `main` `cdee39de1`, results landed via PR #8196 absorbed onto this branch). Remaining arms on #8172: feature-branch session, CLI `/handoff`.
- [x] `cloud-probe.md` records, each with evidence: Q1 repo-level hooks per-event (SessionStart + PostToolUse/Stop markers); `ask_user_question` behavior in unattended sessions (auto-approve / stall / distinguishable-unanswered — freezes FR4 mechanism); per-hook per-matcher binding (`Bash` vs `exec`); repo-level `requiredPlugins` install + unknown-key tolerance; `/handoff` `.devin/` sync; `run_subagent` artifact output; `DEVIN*` env incl. exec-shell + session-id var; `.claude/settings.json`; `PostCompaction`; plugin command-hook execution + `hook_source`. — All 15 items recorded across both arms; the load-bearing findings agree (no-hook environment, no `ask_user_question`, `DEVIN_DIR` only marker). Divergence reconciled: `run_subagent` substrate exists in web-app arm, absent in sandbox; `requiredPlugins` repo-level placement confirmed by plugins overview §Inheritance level 3 (session's contrary doc-finding corrected).
- [x] Finalize FR4 mechanism, FR5 scope, matrix rows, Art. 30 wording from measured data. — FR4 frozen on hard-defer/blocking `message_user` (stalls, never auto-approves); FR5 confirmed maximal (zero hook dispatch, both arms); matrix rows updated to measured; Art. 30 wording measured-accurate. `cloud-detect.sh` env gate widened to include `DEVIN_DIR`; `"Bash"`-vs-`exec` matcher defect in `hooks.json` found and fixed (ported from #8196); `.claude/settings.json` `"Bash"` matcher class recorded as follow-up (per-hook review needed).

## Phase 1 — Detection + sentinel + requiredPlugins (FR1, FR6)

- [x] `devin-session-start.sh`: unconditional content-bearing sentinel write `{host, ts, hook_source}` → `.devin/soleur-local-session`; git-root resolution + `mkdir -p`; `|| true`-guarded after the `additionalContext` emit. Repo-sourced writes never mask an existing plugin-sourced sentinel (dual-registration ordering).
- [x] `plugins/soleur/scripts/cloud-detect.sh`: the ONE classifier — `local` (sentinel + host match + `hook_source=plugin`) or `not-local:<reason>`; single `hostname` source; no `jq` dependency; fail closed.
- [x] `plugins/soleur/test/devin-cloud-mode.test.ts`: `local` arm + every `not-local` reason + never-value + dual-registration ordering arms.
- [x] `.devin/config.json`: `"requiredPlugins": ["jikig-ai/soleur#plugins/soleur"]` + unknown-key tolerance verified (`jq` parses; `devin doctor --json` ok).
- [x] `bun test plugins/soleur/test/` green (2731 pass, 0 fail).

## Phase 2 — Contract surfaces + one wiring pass (FR2, FR3, FR4, TR2, TR3)

- [x] `devin/INSTRUCTIONS.md` §Cloud Mode: canonical contract (banner disclosure + fallback degrade path + ack posture + absent-guardrail disclosure) — loaded via the go shim on routed sessions.
- [x] `plugins/soleur/AGENTS.md`: cloud-mode rules section (`[id:]` convention).
- [x] `plugins/soleur/scripts/cloud-banner.sh`: per-invocation emit, delegates to `cloud-detect.sh`.
- [x] Grep-derive union set: spawn-sites ∪ secrets/prod ∪ directly-invocable pipeline skills — 59 skills derived (compound, code-to-prd, frontend-design, product-roadmap, spec-templates, work, preflight, one-shot, brainstorm, plan, schedule, community, pencil-setup, rclone all present).
- [x] One composite `<!-- soleur-cloud-mode:start/end -->` pointer block per union-set SKILL.md (59/59 applied).
- [x] `emit-review-trailer.sh`: `sequential-fallback` enum widen at all four enum sites; flag in deliverables + PR trailers; xtrace refusal guard added (baseline entry removed).
- [x] `ship` gate: `sequential-fallback` coverage on `single-user incident` plans = blocking (Phase 1.5 Step 2; interactive AskUserQuestion / headless abort; superseding `full` trailer lifts the block).

## Phase 3 — Skill-internal guardrails (FR5)

- [x] `plugins/soleur/scripts/precommit-guard.sh`: self-contained commit-on-main check, exec'd by work/ship/one-shot; no vendored lib, no DONE-marker arm; `git -C`/`cd`-chain/cwd target resolution.
- [x] `.claude/hooks/guardrails.sh`: commit-on-main block delegates to `precommit-guard.sh` (inline check retained as unreachable-plugin fallback).
- [x] Verified in a repo lacking `.claude/` (bare tmp repo, all six arms). Enumerate unrestored guards for the matrix — deferred to Phase 4 (probe-informed).

## Phase 4 — Capability matrix + upstream requests (FR7, FR10)

- [x] `devin/INSTRUCTIONS.md` §Cloud Mode: capability matrix (per-event hook granularity incl. `Bash`/`exec` matcher-binding caveat, subagents local-only, MCP, repo hooks recorded as undocumented pending #8172), unrestored-guard enumeration, upstream request register (#8160).
- [x] README + `plugins/soleur/README.md` matrix pointers.

## Phase 5 — Legal disclosures (FR8, TR6)

- [x] Floor landed: DPD §2.1/§2.1(c)/§3.1(a) scoped to plugin-local; §2.1c names the provider-operated session + fifth table row; privacy-policy §§3/4.1/4.2/8/10 scoped + third-exception paragraph; gdpr-policy all seven scope paragraphs + §8.1 variant extended, §2.1/§7.1 predicates scoped. `Last Updated` lines untouched on all three docs (#7465 drift freeze) — additive "Corrected September 14, 2026 (#8159)" paragraphs per the #7786 convention.
- [ ] CLO decides the ceiling: corpus-wide three-configuration taxonomy vs floor-only.
- [x] Art. 30 register: scope-test bracket appended (provider-operated out of scope on both limbs; plugin-hook TOM absence on third-party machines recorded; D10 in-scope prohibition stated). Per-entry probe-informed wording deferred to #8172.
- [x] `compliance-posture.md` Completed-Work row + D10 prohibition recorded; TC_VERSION tier question flagged to CLO in the row; T&C deliberately untouched. Named Cognition vendor entry remains probe-conditional (no DPA — 2026-09-13 attestation).
- [x] Eleventy mirrors in lockstep (identical edits both surfaces); `legal-doc-shas.ts` repinned ×3; `legal-doc-consistency.test.ts` + `legal-doc-shas-guard.test.ts` 43/43, `check-tc-document-sha.sh` clean, drift ratchet within baseline. CLO sign-off pending (SC5).

## Phase 6 — ADR + C4 + verification session

- [x] ADR-219 (provisional — re-derive vs `origin/*` before merge): "Soleur Cloud Mode — sentinel-based surface detection and honest-degradation contract."
- [x] `model.c4`/`views.c4`: `devin` external system + edges; `c4-count-parity` green.
- [x] Spec notes: FR1 "sibling lib" reading; NG5 revision for `PostCompaction` (probe-conditional).
- [ ] Second post-implementation cloud session verifies SC1/SC3/SC4; file follow-up issues for post-merge ACs (issue not auto-closed).
- [x] markdownlint clean on all touched `.md` (incl. 6 legal files + KB legal records); guard-contract lint passed at plan time.
