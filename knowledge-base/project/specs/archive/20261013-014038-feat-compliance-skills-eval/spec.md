---
title: gdpr-gate skill spec
date: 2026-05-09
status: draft
brand_survival_threshold: single-user incident
adr_required: true
---

# Feature: `gdpr-gate` skill

## Problem Statement

Soleur's compliance posture is mature at the document layer (`legal-audit`, `legal-generate`, 9 active legal docs, vendor DPAs verified) but absent at the code layer. When `/soleur:plan` and `/soleur:work` design schemas, migrations, auth flows, forms, API routes, and PII-touching code, there is no inline pre-generation gate that catches regulated-data design gaps before code is written. Existing scattered guardrails (secret-scan hook on fixtures, Sentry payload scrubbing, regex scrubber invariants) are post-hoc; they catch leaks after the design is committed. For an EU-deployed product with `single-user incident` brand-survival threshold, this gap is unacceptable.

`gosprinto/compliance-skills/pii-detector` (MIT, 2026-05-06) addresses the *idea* but is US-only, embeds vendor-marketing surface in agent output, and ships via per-machine `claude skills add` rather than the plugin model. The brainstorm rejected direct integration; this spec is for a Soleur-native replacement that lifts 5 clean files from Sprinto under MIT attribution and rewrites the regulatory frame around GDPR.

## Goals

- Catch GDPR/UK GDPR/CCPA/HIPAA regulated-data design gaps **before** code is generated, not after.
- Operate as a read-only auditor of the canonical `/soleur:plan` template — never inject competing checklists.
- Stay advisory-only with mandatory disclaimer at top of every gate output; never claim legal sign-off.
- Escalate Critical findings (Art. 9 data, missing lawful basis, Art. 30 trigger) to `compliance-posture.md` Active Items + GitHub issue via operator-acknowledged write.
- Distribute as a Soleur plugin skill (`plugins/soleur/skills/gdpr-gate/`) — same versioning, no per-machine install.
- Save 3-5 days of catalogue-writing engineering time by lifting language-neutral grep+fix catalogues from Sprinto under MIT attribution.

## Non-Goals

- Direct integration of `gosprinto/compliance-skills` as a vendored dependency — rejected by all four leaders.
- Forking the upstream repo — rejected (recurring scrub debt; CLO/CMO blocked).
- Pure-keyword auto-trigger — rejected (Soleur plan templates over-match on "user table"/"session sync"/etc.).
- BIPA, COPPA, FERPA, GLBA, Swiss FADP, AI Act, DSA coverage in v1 — defer to demand-pull.
- Repo-scan mode in v1 — credential-leak risk through scanning `.env`/fixtures; defer to v2 with explicit allowlist.
- `auth-sessions`, `frontend`, `testing-seeding`, `legal-consent` as separate v1 layers — fold relevant checks into the 3 MVP layers; full layer files defer to v2.
- Auto-writing to `compliance-posture.md` — operator-acknowledged only, to preserve human accountability for legal claims.
- Streaming gate on every Edit tool call — batch only (one pass at `/work` Phase 2 exit, one at `/plan` Phase 2.6).
- Gate injecting its own checklist into the plan template — gate is read-only.

## Functional Requirements

### FR1: Plan-phase invocation

`gdpr-gate` is invoked by `/soleur:plan` **Phase 2.7** (between User-Brand Impact at Phase 2.6 and SpecFlow at Phase 3 — preserves existing skill-enforced rule-tag invariants per Research Reconciliation gap #10). Input: the plan document + the FR/TR sections being authored. Output: advisory findings inline in the conversation, formatted as Critical/Important/Suggestion (matching `/review` and `/preflight` voice — no ⚡/🔴/🟡/🟢 emoji branding).

### FR2: Work-phase invocation

`gdpr-gate` is invoked at `/soleur:work` **Phase 2 exit (single pass after all per-task RED/GREEN/REFACTOR loops complete, before Phase 2.5)**. Single pass per phase per ADR-026 TR3 — token budget ≤4k per invocation. AND via lefthook pre-commit on the canonical regex path-array (single source of truth in `plugins/soleur/skills/gdpr-gate/SKILL.md` §"Path globs (canonical)"). Earlier-draft globs `forms/**` and `**/*.prisma` were dropped (zero matches in this repo per Research Reconciliation gaps #4-5); `*auth*` was tightened to bounded paths. Hook layer is regex-only (zero LLM cost) and only triggers the skill invocation.

### FR3: Mandatory disclaimer

Every gate output MUST start with:

> **This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

No pass/fail verdict is ever emitted. Output is labeled "advisory findings."

### FR4: Five mandatory v1 GDPR checks

1. **Lawful basis required** on every new PII field (consent / contract / legitimate interest / vital interest / public task / legal obligation — Art. 6).
2. **Retention period declared** (Art. 5(e)).
3. **DSAR-deletability flagged** with cascade path traceable (Art. 17).
4. **Cross-border transfer flagged** when schema lands in non-EU vendor (Stripe, Cloudflare currently — DPF + SCCs already verified per `compliance-posture.md`; new vendors require fresh check).
5. **Special-category Art. 9 detector** (health, biometric, genetic, racial/ethnic origin, political opinion, religious belief, trade union membership, sex life, sexual orientation) — on hit, gate **blocks** and routes to `clo` agent.

### FR5: Critical-finding escalation

When a Critical finding fires (Art. 9 data, missing lawful basis, or new processing activity that triggers Art. 30 RoPA entry), the gate prompts the operator to:
1. File a GitHub issue (label: `compliance/critical`).
2. Add a row to `compliance-posture.md` Active Items in the same commit.
3. Acknowledge in `/ship` Phase 5.5 conditional gate.

Auto-write is rejected — operator must run the prompted commands. Mirrors `legal-audit`'s "never-write-to-files" rule for OSS repos.

### FR6: Layer coverage v1

Three layers active in v1:
- `data-in-transit` (PII-in-URL-params, hardcoded HTTP, webhook sig verification, PII headers, request-log middleware, HSTS — 6 checks lifted from Sprinto + Chapter V cross-border check).
- `data-lifecycle` (hard-delete, cascade-delete, anonymization with Sweeney 87% re-id nuance, retention jobs, encrypted backups — 6 checks lifted; DL-04 rewritten for Art. 20 + CCPA).
- `api-layer` (full-object responses, IDOR, GraphQL introspection, unscoped bulk, PII in errors, rate-limiting, CORS — 7 checks lifted verbatim).

`auth-sessions`, `frontend`, `testing-seeding`, `legal-consent` content folds into the 3 active layers where overlap exists; full layer files defer to v2.

### FR7: Conversation-only output by default

Findings are displayed inline; never written to repo files. Exception: Critical findings trigger the FR5 escalation prompt for operator-acknowledged writes.

## Technical Requirements

### TR1: Architecture — read-only auditor of canonical plan template

Gate MUST NOT inject its own required-controls checklist into the `/plan` template. Single source of truth for required controls is the canonical `/plan` template. Gate reads + flags drift. This avoids the gate-vs-template collision flagged by CTO at brainstorm time.

### TR2: Distribution — plugin-native

Lives in `plugins/soleur/skills/gdpr-gate/`. Versioned with the plugin via `plugin.json`; no `claude skills add` per-machine install. SKILL.md kept ≤500 lines via `references/` directory for layer files (load-on-demand pattern matching existing `plugins/soleur/skills/review/` and `plugins/soleur/skills/brainstorm/references/`).

### TR3: Token budget — batch, not stream

≤4k tokens per gate invocation. Single Haiku call against (diff + plan excerpt). One pass per phase (work Phase 2 exit, plan Phase 2.6). No per-Edit streaming — would add 3-8k tokens/edit and reverse the work-skill optimizations from PR #3492.

### TR4: Trigger mix

Three layers, no pure-keyword:
1. **Explicit invocation** during `/plan` Phase 2.6 and `/work` Phase 2 exit (deterministic, auditable).
2. **Hook-enforced diff detection** on path globs (FR2). Tag in AGENTS.md: `[hook-enforced: gdpr-gate.sh]`.
3. **brainstorm-domain-config routing** so a CPO/CTO leader pulls the gate when a user message contains regulated-data signal.

### TR5: MIT attribution

Add `plugins/soleur/skills/gdpr-gate/NOTICE` listing each lifted file with upstream commit SHA from `gosprinto/compliance-skills`. Each lifted file gets header: `<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->`. Vendor surface (Sprinto logo, utm links, "powered by" footers) MUST NOT appear in any lifted file. Verified scrub list: only `pii-detector/README.md` and `pii-detector/modes/repo-scan.md` (footer) require scrubbing — other 13 files are clean.

### TR6: ADR required

`/soleur:architecture create "PII gate as plan/work-phase skill with diff hook"` MUST be created before implementation. Cross-cuts plan, work, preflight, and AGENTS.md rule surface. ADR records the read-only-auditor decision (TR1), the trigger mix (TR4), and the rejection of the streaming/per-Edit alternative (TR3).

### TR7: USER_BRAND_CRITICAL handling

`brand_survival_threshold: single-user incident` is set in this spec's frontmatter. Plan skill's Phase 2.6 carries this forward; `user-impact-reviewer` agent runs at review time per `hr-weigh-every-decision-against-target-user-impact`. Three named vectors documented in brainstorm doc `## User-Brand Impact` table.

### TR8: Telemetry

Emit `gdpr-gate fired` incident telemetry on Critical findings only (not every fire) — avoids log noise. Hook into `.claude/hooks/lib/incidents.sh`. Telemetry rule ID: `cq-gdpr-gate-critical-finding` (created at implementation time, not now).

### TR9: Open questions to resolve at plan time

- Q1: Does `gdpr-gate` run in `/soleur:preflight` as Check 7?
- Q2: Telemetry on every fire or Critical only? (TR8 leans Critical; revisit.)
- Q3: Version-pin policy on lifted Sprinto files — re-vendor on upstream change, or fork-permanently?
- Q4: UK GDPR — separate disclaimer language, or fold into "GDPR + UK GDPR"?

## Acceptance Criteria

- [ ] ADR created via `/soleur:architecture create` before any implementation work.
- [ ] `plugins/soleur/skills/gdpr-gate/SKILL.md` exists, ≤500 lines, written from scratch in Soleur voice.
- [ ] `plugins/soleur/skills/gdpr-gate/NOTICE` lists 5 lifted files with upstream commit SHAs.
- [ ] `plugins/soleur/skills/gdpr-gate/references/` contains 3 active-layer files (`api-layer.md`, `data-in-transit.md`, `data-lifecycle.md`) + `fields.md` + `leakage-vectors.md` + `non-negotiables.md` (rewritten) + `legal-consent.md` (rewritten, EU-first).
- [ ] Each lifted file carries `<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->` header.
- [ ] No file in `plugins/soleur/skills/gdpr-gate/` contains `sprinto.com`, `utm_source=Claude`, Sprinto logo URL, or "Built by Sprinto" attribution outside of NOTICE.
- [ ] `/soleur:plan` Phase 2.6 invokes the gate; integration test verifies invocation.
- [ ] `/soleur:work` Phase 2 exit invokes the gate; lefthook hook configured for path globs.
- [ ] Mandatory disclaimer appears at top of every gate output (asserted in skill test).
- [ ] 5 mandatory v1 GDPR checks (FR4) implemented; integration test for each.
- [ ] Critical-finding escalation flow (FR5) prompts operator; never auto-writes.
- [ ] AGENTS.md updated with `[hook-enforced: gdpr-gate.sh]` tag for the diff hook + advisory rule pointing to this skill.
- [ ] Token budget ≤4k per invocation verified by sample Haiku run.
- [ ] CMO blog post draft "Why we built our own PII gate instead of bundling Sprinto's" filed as separate issue (distribution opportunity, not blocking ship).
