# Brainstorm: Devin Cloud Session Parity ("Soleur Cloud Mode")

**Date:** 2026-09-14
**Trigger:** Operator question — "Does our Soleur Devin plugin actually support running sessions on Devin Cloud remotely instead of the CLI here?"
**Worktree:** `.worktrees/feat-devin-cloud-session-parity` | **Branch:** `feat-devin-cloud-session-parity` | **Draft PR:** #8155
**Lane:** cross-domain (auto — USER_BRAND_CRITICAL=true per #5175)

## Verified Platform Facts (docs.devin.ai, 2026-09-14)

| Plugin surface | Cloud session | Source |
|---|---|---|
| Skills (`/soleur:*`) | Loads | `extensibility/plugins/overview` — "Plugins work across Devin cloud sessions, the Devin CLI, and Devin Desktop" |
| Plugin `AGENTS.md` / `rules/` | Loads (always-on / triggered rules) | same page |
| MCP servers | Works; auth via **web-app connection**, not `devin mcp login` | same page |
| Repo `.devin/config.json` `requiredPlugins` | Honored "from each cloned repository" | same page, Inheritance §3 |
| Plugin subagents (`agents/**/*.md`) | **Absent** — "local Devin agents only — the CLI and Devin Desktop — not in cloud Devin sessions" | same page |
| Plugin hooks (`hooks.json` at plugin root) | **Absent** — registers "in local Devin sessions (the CLI and Devin Desktop)"; fail-open everywhere | same page |
| Repo-level hooks (`.devin/hooks.v1.json`, `.devin/config.json` hooks key, `.claude/settings.json`) | **Undocumented** — pivotal open question (see Open Questions) | hooks docs are CLI-scoped |

Soleur inventory affected (repo-research): **66 agent definitions** (fan-out used by review/plan/brainstorm/work/deepen-plan/one-shot/agent-native-audit); **6 plugin hooks** in `hooks/hooks.json` (SessionStart ×3 incl. `devin-session-start.sh` = the entire Devin tool-mapping contract; PreToolUse credential guard; Stop ×3 incl. `<promise>DONE</promise>` completion gate + unkept-promise guard); **4 repo-level hooks** in `.devin/config.json` (session-rules-loader = the whole AGENTS.rules.md corpus, guardrails.sh). ~40 skills touch Doppler/prod surfaces.

## What We're Building

**"Soleur Cloud Mode"** — make the plugin behave correctly and *honestly* inside Devin Cloud sessions: detect the cloud environment, disclose which enforcement surfaces are absent, degrade agent fan-out to the shipped sequential contract, gate secrets/prod-touching skills behind an explicit acknowledgement, and document the capability matrix for users — including the legal disclosures CLO flagged.

The product promise (CPO): **workflow-complete, gate-disclosed — never capability-equivalent.** No cloud run may produce silently weaker output than a local one.

## Why This Approach

Approach A (plugin-carried) chosen over B (verify-first repo config) and C (docs + upstream request). Skills and `AGENTS.md` are the only surfaces guaranteed to load in cloud — enforcement must live where it can actually run. B's verification step folds into A as an implementation task; C leaves degradation undisclosed-in-band and timelines vendor-owned.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Scope = operator self-use **and** documented support for plugin users | User answered: "Also documented for users" → legal doc updates in scope |
| D2 | Posture = honest degradation ("Soleur Cloud Mode"), not parity attempt or docs-only | True parity impossible (no platform subagents/hooks to restore); docs-only leaves silent degradation — our own worst failure shape |
| D3 | Detection = sentinel, not env sniffing | No documented cloud marker exists; `devin-session-start.sh` writes a sentinel in local sessions — `DEVIN` set + sentinel absent ⇒ hookless cloud. CTO rec; feature-detect never sniff |
| D4 | Capability banner + degradation ledger in deliverables/PR trailers | CPO rec — undisclosed degradation is a protocol violation equivalent to a forged DONE |
| D5 | Sequential agent fallback generalized to every fan-out skill | Contract already shipped (`devin/INSTRUCTIONS.md`, work Tier-C, review Gate-2a templates); verify if `run_subagent` accepts arbitrary prompts via built-in profiles in cloud |
| D6 | Cloud-ack gate (`ask_user_question`) on prod/Doppler skills (~15: deploy, flag-*, provision-*, trigger-cron, admin-ip-refresh, user-set-role, ship/qa/postmerge Doppler reads, incident, ux-audit/test-browser w/ real creds) | CLO rec — credential guards absent in the least-attended runtime |
| D7 | Move cloud-critical context into plugin `AGENTS.md` + skill preambles | AGENTS.md loads in cloud; SessionStart injection doesn't. Extend the `devin/skills/go` self-load pattern to pipeline skills |
| D8 | `requiredPlugins: ["jikig-ai/soleur#plugins/soleur"]` in repo `.devin/config.json` | Quick win — honored in cloud "from each cloned repository"; zero risk locally |
| D9 | Legal disclosures (DPD §2.1, Privacy §5.1, GDPR §2.2): add "plugin on user-credentialed third-party VM" scope row; Art. 30 §(g) TOM entries scoped "local sessions" | CLO — documenting cloud use fires the 2026-09-13 attestation's re-evaluation trigger |
| D10 | PROHIBITED until Cognition is a contracted Jikigai processor (Art. 28(3)+SCCs): any Jikigai-credentialed cloud session carrying user personal data | CLO register limbs 2+3 both fire |
| D11 | Deferred: upstream feature requests to Cognition (cloud subagents, cloud plugin hooks) | Platform limits are not ours to close; docs matrix states them |

## Open Questions

- **Q1 (pivotal):** Do repo-level hooks (`.devin/config.json` hooks key, `.devin/hooks.v1.json`, `.claude/settings.json`) fire in cloud sessions? Undocumented. Verify empirically via a `/handoff` test session early in implementation — if yes, repo-shipped config restores partial structural parity for this repo.
- **Q2:** Does `run_subagent` in cloud accept arbitrary prompt-delivered role definitions via built-in profiles (subagent_explore/general)? If yes, sequential→parallel role execution may still be possible.
- **Q3:** Does a stable cloud-session signal exist beyond sentinel inference (env, `session_id` shape, hooks payload)? Probe in the same test session.
- **Q4:** Does `.claude/settings.json` hook loading (`read_config_from.claude`, default on) apply in cloud? Repo-research claims the ~35 `.claude/settings.json` hooks are already absent in local Devin CLI — needs verification, contradicts CLI docs.

## User-Brand Impact

- **Artifact:** Soleur plugin behavior inside Devin Cloud sessions
- **Vector:** an operator trusts a cloud-run `/soleur:one-shot` or review pipeline whose agent roster and hook gates silently didn't fire — unreviewed work ships under a "Soleur ran it" assumption; or prod secrets are pulled onto a Cognition VM with credential guards absent
- **Threshold:** `single-user incident`

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** "Workflow-complete, gate-disclosed." Sequential fallback + prose-only DONE contract acceptable with disclosure; guardrails-off is warn-and-confirm; undisclosed degradation = protocol violation. Recommends capability banner, degradation ledger, AGENTS.md carry, `requiredPlugins` quick win.

### Legal (CLO)

**Summary:** PERMITTED-WITH-GUARDRAILS + one prohibition (D10). Documenting cloud use fires the re-evaluation trigger from the 2026-09-13 attestation — three-doc disclosure update + Art. 30 TOM rescoping required. No BUSL change; never market cloud parity as protection parity.

### Engineering (CTO)

**Summary:** Real absences are SessionStart hooks + subagents (verified). Architecture: requiredPlugins → sentinel detection → AGENTS.md/skill-preamble carry → generalized sequential fallback → skill-internal gates → cloud-ack gate. Effort: hours→days→days→days→docs.

## Capability Gaps

- **No hook-fallback contract.** Subagent fallback is shipped (`devin/INSTRUCTIONS.md:83-85`); nothing equivalent exists for hooks — cloud silently loses rules corpus, credential guard, DONE-gate. Evidence: `plugins/soleur/hooks/hooks.json` (6 hooks), `.devin/config.json` (4 hooks), grep of SKILL.md for hook-absence fallback text = zero hits.
- **No cloud-vs-local detection.** `plugins/soleur/lib/harness.ts:80-115` `detectHarness()` returns `"devin"` for both surfaces; zero `DEVIN_CLOUD`-class markers consumed repo-wide.
- **Skill-internal enforcement for absent backstops.** `<promise>DONE</promise>` is skill-internal at one-shot Step 8 but its *backstop* is `stop-hook.sh`; block-commit-on-main lives only in `guardrails.sh`. Need skill-invoked equivalents (precommit-guard exec'd directly by work/ship).
