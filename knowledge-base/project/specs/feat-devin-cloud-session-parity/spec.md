---
title: "Devin Cloud Session Parity — Soleur Cloud Mode"
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-14-devin-cloud-session-parity-brainstorm.md
issue: 8159
created: 2026-09-14
---

# Spec: Devin Cloud Session Parity ("Soleur Cloud Mode")

## Problem Statement

Devin plugins load in cloud sessions (skills + plugin `AGENTS.md` rules + MCP servers + repo-level `requiredPlugins`), but **plugin subagents and plugin hooks do not** — both are documented as local-only (CLI/Desktop). Soleur depends on both surfaces: 66 agent definitions fan out across review/plan/brainstorm/work/one-shot/agent-native-audit, and hooks carry session-rules injection (`AGENTS.rules.md` corpus), the credential guard, `guardrails.sh`, and the `<promise>DONE</promise>` stop-gate. Today a `/soleur:*` pipeline run in a cloud session silently produces weaker output than a local one — an undisclosed-degradation failure this repo classifies as its worst shape.

## Goals

- **G1.** A cloud session is *detected* (sentinel-based, never env-sniffed) and every pipeline-skill entry emits a capability banner naming absent surfaces.
- **G2.** Every fan-out skill degrades to sequential role execution with explicit disclosure — generalizing the shipped contract in `devin/INSTRUCTIONS.md` (work Tier-C / review Gate-2a templates).
- **G3.** Prod/Doppler-touching skills (~15) require an explicit cloud acknowledgement (`ask_user_question`) before mutating or reading secrets on a Cognition-managed VM.
- **G4.** Cloud-critical context is carried on surfaces that load in cloud: plugin `AGENTS.md` + skill preambles; skill-internal equivalents for the hook backstops that cannot be restored.
- **G5.** Users get an honest capability matrix (`devin/INSTRUCTIONS.md` + README pointer) and the legal disclosures CLO requires (DPD §2.1, Privacy §5.1, GDPR §2.2 scope rows; Art. 30 §(g) TOM entries rescoped "local sessions").
- **G6.** The platform unknowns are resolved empirically in a real cloud session and the results recorded (Open Questions Q1–Q4 in the brainstorm).

## Non-Goals

- **NG1.** No true parity attempt — platform absences (subagents, plugin hooks) are Cognition's to close; upstream feature requests are documentation, not scope.
- **NG2.** No Jikigai-credentialed cloud session carrying user personal data — prohibited until Cognition is a contracted processor (Art. 28(3)+SCCs). Enforced as a documented prohibition + skill warnings, not code.
- **NG3.** No changes to the Claude/Codex/Grok harness paths.
- **NG4.** No version-key addition to any manifest (ADR-182 / #7471 invariant).
- **NG5.** No restructuring of `hooks.json` contents — hooks stay as-is; the work is what happens *without* them.

## Functional Requirements

- **FR1. Cloud detection.** Add `detectCloudSession()` to `plugins/soleur/lib/harness.ts` (or a sibling lib): returns true when a Devin harness is detected AND the local-session sentinel written by `devin-session-start.sh` is absent. Sentinel lives under `.devin/` (or `$DEVIN_HOME`); `devin-session-start.sh` writes it on SessionStart. Feature-detect only — no invented env markers.
- **FR2. Capability banner.** Pipeline skills (`go`→ routed skills, `one-shot`, `work`, `plan`, `review`, `brainstorm`, `deepen-plan`, `drain-*`) emit a one-time-per-session banner when `detectCloudSession()` is true, naming: subagents absent, SessionStart hooks absent, other plugin hooks absent, sequential-fallback active. Banner text lives in one shared include/script, not duplicated prose.
- **FR3. Sequential fallback generalization.** Every SKILL.md that spawns subagents gains an explicit degrade path: attempt `run_subagent`; on plugin-agent unavailability, execute the role definition sequentially inline and disclose "executed sequentially — independent-review parity reduced" in the deliverable and PR trailer.
- **FR4. Cloud-ack gate.** The ~15 prod/Doppler skills (deploy, flag-create/set-role/delete/list, user-set-role, provision-{doppler,cloudflare,github,hetzner}, trigger-cron, admin-ip-refresh, cf-token-scope, ship, qa, postmerge, incident, reproduce-bug, ux-audit, test-browser, operator-digest) get a shared cloud-ack block: when cloud-detected, `ask_user_question` confirms "running on a Cognition VM with credential guards absent — proceed?" before any secret read or prod mutation.
- **FR5. Skill-internal gate backstops.** Extract the commit-on-main block and the DONE-marker check into a skill-invoked script (`scripts/precommit-guard.sh` or equivalent) that `work`/`ship`/`one-shot` exec directly — enforcement must not depend on PreToolUse/Stop hook execution.
- **FR6. `requiredPlugins`.** Add `"requiredPlugins": ["jikig-ai/soleur#plugins/soleur"]` to repo `.devin/config.json`.
- **FR7. Capability matrix + docs.** `devin/INSTRUCTIONS.md` gains a cloud-vs-local surface matrix (skills / AGENTS.md rules / MCP / subagents / hooks / repo hooks), the sequential-fallback contract extended to hooks, and MCP-auth-via-web-app note. README Devin section links it.
- **FR8. Legal disclosures.** DPD §2.1, Privacy §5.1, GDPR §2.2 gain a scope row for "plugin executing on a user-credentialed third-party VM"; Art. 30 register §(g) TOM entries for PreToolUse guards are rescoped "local sessions"; Eleventy doc mirrors updated in lockstep.
- **FR9. Empirical verification.** Run one `/handoff` or web-app cloud session on this repo; record in `knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md`: whether repo-level hooks fire, whether `run_subagent` accepts prompt-delivered roles via built-in profiles, what env/session signals distinguish cloud, whether `.claude/settings.json` hooks load. Specs FR1–FR8 implement against the *documented* absence; the probe either confirms or upgrades scope.
- **FR10. Upstream requests.** File/document Cognition feature requests for cloud subagents + cloud plugin hooks inside the capability matrix (tracked, not blocking).

## Technical Requirements

- **TR1.** Detection and the banner/ack helpers live in `plugins/soleur/lib/` + `scripts/`; SKILL.md files source them — no per-skill divergence in detection logic.
- **TR2.** All SKILL.md edits preserve existing rule IDs; new rules added to AGENTS.md follow the `[id: <prefix>-<slug>]` convention and pass the tier gate.
- **TR3.** The sequential-fallback path must never claim independent review occurred when it did not (existing contract verbatim).
- **TR4.** Changes pass `npx markdownlint-cli2` on touched `.md` files and `bun test plugins/soleur/test/` (add `devin-cloud-mode.test.ts` covering detection + banner emit).
- **TR5.** No secrets in cloud-path code; the cloud-ack gate reads no credential values itself.
- **TR6.** Legal doc edits follow the three-doc lockstep convention (DPD/Privacy/GDPR + SHA repins + Eleventy mirrors) per the CLO attestation pattern.
- **TR7.** The cloud probe must not carry user personal data and uses only operator-credentialed test scope (per CLO prohibition).

## Out of Scope (Future Work)

- Upstream platform support for cloud subagents/hooks (vendor-owned; documented as FR10 requests).
- Re-enabling Jikigai-credentialed cloud sessions for user-personal-data workflows (blocked on Cognition processor contract; re-evaluation trigger = executed DPA/SCCs).
- Devin Desktop-specific parity notes (inherits the same local-session treatment; no dedicated work).

## Success Criteria

- **SC1.** A cloud `/soleur:go` run on this repo emits the capability banner and completes a pipeline stage with disclosed sequential fallback — verified in the FR9 probe session.
- **SC2.** `grep -c "cloud" plugins/soleur/devin/INSTRUCTIONS.md` shows the matrix; every spawn-site SKILL.md contains the fallback block (grep-verified, not sampled).
- **SC3.** A prod-mutating skill invoked in cloud halts at the ack gate when unanswered.
- **SC4.** `devin plugins info soleur` + a fresh cloud session on a repo lacking personal-manifest sync loads skills via `requiredPlugins`.
- **SC5.** CLO signs off on the three-doc disclosure update and the Art. 30 rescoping (register limbs documented).

## Implementation Notes (recorded 2026-09-14, post-plan-review)

- **FR1 landed in `plugins/soleur/scripts/cloud-detect.sh`, not `lib/harness.ts`.** Plan-review found `harness.ts` functions are only consumed by tests — the bash script is the sole runtime detector, so the "sibling lib" reading of FR1 resolves to `scripts/`. The sentinel also gained `hook_source` (a repo-level SessionStart firing on a cloud VM would otherwise write a matching-host sentinel → false-local) and the classifier is tri-state fail-closed (`local` / `not-local:<reason>`).
- **NG5 narrowed by the doc correction:** plugin `command` hooks are now documented cloud-capable for every event except `SessionStart`/`SessionEnd`, so `hooks.json` still needs no restructuring — but `PostCompaction` (documented cloud-capable, unused today) is a probe-conditional follow-up, tracked under #8172.
