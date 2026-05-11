---
title: gdpr-gate skill brainstorm
date: 2026-05-09
status: complete
brand_survival_threshold: single-user incident
related_repo: https://github.com/gosprinto/compliance-skills
---

# Brainstorm: `gdpr-gate` skill (compliance-skills evaluation)

## What We're Building

A Soleur-native plugin skill, **`gdpr-gate`**, that fires inline during `/soleur:plan` and `/soleur:work` to catch regulated-data design gaps **before** code is generated. GDPR-first (Art. 5/6/9/17/20/25/30/32/33/35), with secondary US coverage (CCPA, HIPAA). Output is **advisory-only** with a mandatory disclaimer header — the skill never claims legal sign-off.

The trigger to evaluate this came from `https://github.com/gosprinto/compliance-skills` (Sprinto's `pii-detector` skill, MIT, USA-focus). The brainstorm decided **not to integrate Sprinto's skill directly** but to **lift 5 specific files under MIT attribution** into a Soleur-native skill, rewriting the regulatory frame around GDPR.

## Why This Approach

Across all four leader assessments (CPO, CLO, CTO, CMO) and a deep-dive of Sprinto's repo, the consensus was identical:

- **Vendor as-is fails** — Sprinto is US-only, embeds utm-tagged links into agent output (turning every PII check into a Sprinto impression inside our agent surface), and ships via `claude skills add` (per-machine) rather than the plugin model Soleur uses.
- **Inspiration-only over-corrects** — re-writing 25+ grep+fix catalogues that already exist (notably `data-lifecycle.md` DL-03's Sweeney 87% re-identification check, the `api-layer.md` 7-check IDOR/CORS catalogue, and `auth-sessions.md` JWT+OAuth catalogue) wastes 3-5 days of engineering time.
- **Lift-with-attribution is the highest-leverage middle.** Sprinto's vendor surface is confined to two files (`README.md` + `modes/repo-scan.md` footer); the other 13 files are clean. A `NOTICE` line + 5 file headers covers MIT obligations.

Soleur's existing compliance posture is GDPR-first (EU data residency: Hetzner Finland, Supabase Ireland; DPF/SCCs for US vendors; 9 active legal documents; vendor DPAs verified). Code-level pre-generation guardrails are the missing layer — `legal-audit` and `legal-generate` cover documents; `gdpr-gate` covers code design.

## User-Brand Impact

**Brand-survival threshold:** `single-user incident` (per `hr-weigh-every-decision-against-target-user-impact`).

The framing question — "what is the worst outcome the target user experiences if this fails?" — was answered "all of them": user data exposure, false sense of compliance, and credential leak through compliance tooling. All three are live risks for this skill:

| Vector | Artifact | Threshold | Mitigation in v1 |
|---|---|---|---|
| User data exposure | A field flagged "ok" by the gate that turns out to be Art. 9 special-category data → operator ships GDPR-non-compliant schema → regulator complaint or DSAR failure | single-user incident | Art. 9 special-category detector is one of the 5 mandatory v1 checks; on hit, skill **blocks** and routes to clo agent for human review |
| False sense of compliance | Operator screenshots green "✅ PII Check" output as proof of GDPR compliance for an investor / auditor / customer | single-user incident (brand-survival) | Mandatory disclaimer at **top** of every gate output: "This is not legal review. Findings are heuristic. Consult clo + legal-compliance-auditor before merging." Output labeled "advisory findings" — no pass/fail verdict ever |
| Credential leak through tooling | Repo-scan mode reads schema files / .env / fixtures and includes them in model context that escapes to a non-EU vendor | single-user incident | Repo-scan mode deferred to v2; v1 only inspects diffs/plans the operator pasted; never reads `.env*` or files matching the secret-scan ignore list |

CLO + user-impact-reviewer sign-off required at plan time.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Skill name: `gdpr-gate`** | CMO: turns the EU constraint into the headline; defensible positioning vs. SOC2-shaped competitors; `pii-gate` is generic, `compliance-guard` is enterprise-mush |
| 2 | **Approach B: lift specific files under MIT** | All leaders + deep-dive recommend; saves 3-5 days; vendor surface confined to 2 of 15 files; attribution is `NOTICE` + 5 headers |
| 3 | **Files to lift verbatim with attribution** | `patterns/fields.md`, `rules/leakage-vectors.md`, `layers/api-layer.md`, `layers/auth-sessions.md`, `layers/data-in-transit.md` — language-neutral grep+fix catalogues, zero US-only framing |
| 4 | **Files to lift + EU-extend** | `layers/data-lifecycle.md` (Sweeney insight + add GDPR Art. 17/20), `layers/frontend.md` (add ePrivacy/TTDSG strict-opt-in), `layers/testing-seeding.md` (add Art. 32 pseudonymization) |
| 5 | **Files to write from scratch** | `SKILL.md` (Soleur-voice dispatch), `rules/non-negotiables.md` (GDPR Art. 5/6/9/25/32 first-class), `layers/legal-consent.md` (ePrivacy + Art. 7/13/14/35), `modes/repo-scan.md` (drop Sprinto footer, dual EU/US summary) |
| 6 | **MVP scope: 3 layers, 4 regs, 5 GDPR checks** | CPO + CLO consensus. Layers: data-in-transit, data-lifecycle, api-layer. Regs: GDPR + UK GDPR + CCPA + HIPAA. Checks: lawful basis required, retention period declared, DSAR-deletability, cross-border transfer flagged, Art. 9 special-category detector |
| 7 | **Architecture: plan-skill + work-hook, batch not stream** | CTO. Plan-phase: skill invoked by `/soleur:plan` Phase 2.6 against the plan doc. Work-phase: lefthook + `/work` Phase 2 exit, batch one Haiku pass per gate invocation, ≤4k token budget. No per-Edit streaming |
| 8 | **Gate is read-only auditor of the canonical `/plan` template** | CTO. Gate must NEVER inject its own checklist into the plan — that creates a gate-vs-template collision where two control lists drift. Single source of truth = `/plan` template; gate reads + flags |
| 9 | **Output: advisory-only, conversation-only by default** | CLO. Mirrors `legal-audit`'s "never-write-to-files" rule for OSS repos. Mandatory disclaimer at top of every gate block |
| 10 | **Critical-finding escalation to `compliance-posture.md`** | CLO. Art. 9 data, missing lawful basis, or new processing activity (Art. 30 trigger) → operator-acknowledged write to Active Items table + GitHub issue, enforced via `/ship` Phase 5.5 conditional gate. Auto-write rejected — preserves human accountability |
| 11 | **Distribution: plugin-native, not `claude skills add`** | CTO. Lives in `plugins/soleur/skills/gdpr-gate/`. Layer files in `references/` to keep SKILL.md ≤500 lines and load-on-demand |
| 12 | **ADR required** | CTO. `/soleur:architecture create "PII gate as plan/work-phase skill with diff hook"` cross-cuts plan, work, preflight, AGENTS.md rule surface — needs an ADR before plan implementation |
| 13 | **Trigger mix: explicit invocation + path-globbed hook + brainstorm-domain routing** | CTO. No pure-keyword auto-trigger — Soleur plan templates use language ("user table", "session sync") that over-matches |
| 14 | **CMO content opportunity: "Why we built our own PII gate instead of bundling Sprinto's"** | Distribution moat. EU founder audience on HN + IndieHackers + r/europe |

## Non-Goals (v1)

- BIPA, COPPA, FERPA, GLBA layers — defer to demand-pull
- Swiss FADP — defer to first CH-resident operator
- `auth-sessions`, `frontend`, `testing-seeding`, `legal-consent` layers as separate v1 layers (their checks fold into the 3 MVP layers where overlap exists; full layer files defer to v2)
- Repo-scan mode — defer to v2 (credential-leak risk; v1 only inspects diffs/plans)
- AI Act, DSA — out of scope for v1 (different obligation shape; deserves its own skill)
- Auto-writing to `compliance-posture.md` — operator-acknowledged only

## Open Questions

- **Q1:** Does `gdpr-gate` need to run in `/soleur:preflight` as Check 7, or is `/work` Phase 2 + `/plan` Phase 2.6 sufficient? Defer to plan.
- **Q2:** Should the gate emit incident telemetry on every fire, or only on Critical findings? CTO leans Critical-only to avoid log noise; revisit at plan time.
- **Q3:** What's the version-pin policy on the lifted Sprinto files? If Sprinto pushes a security-relevant update to `api-layer.md`, do we re-vendor or fork-permanently? Plan should decide.
- **Q4:** UK GDPR coverage — is it material enough to call out separately in the disclaimer, or does "GDPR + UK GDPR" suffice? CLO defers to first UK-resident operator review.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

(User-brand-critical lane spawned CPO + CLO + CTO + CMO ahead of others; remaining domains skipped as not relevant for a code-level compliance skill.)

### Product (CPO)

**Summary:** Ship now, scope-down. Inline pre-generation gate is on-thesis for Soleur's agent-native + GDPR-first positioning; slots into roadmap P3 alongside `legal-audit`/`legal-generate`. MVP = 3 layers (data-in-transit, data-lifecycle, api-layer) + 4 regs (GDPR/UK/CCPA/HIPAA). Highest risk is false-sense-of-compliance — non-negotiable disclaimer + advisory-only output + no pass/fail verdict.

### Legal (CLO)

**Summary:** Soleur-native from scratch with selective MIT lifts. Sprinto's US-only frame leaves Art. 5/6/9/17/20/25/30/32/33/35 unaddressed; the embedded utm links risk implicit endorsement and a hidden sub-processor relationship. v1 must cover lawful basis + retention + DSAR + cross-border + Art. 9. Conversation-only output by default; Critical findings route to `compliance-posture.md` Active Items via operator-acknowledged write.

### Engineering (CTO)

**Summary:** Plan-phase skill + work-phase hook, batched not streamed (≤4k tokens/invocation, Haiku). Plugin-native distribution; layer files in `references/`. Gate is read-only auditor of canonical `/plan` template — never injects, to avoid gate-vs-template collision. Recommends `/soleur:architecture create` ADR before implementation since the skill cross-cuts plan/work/preflight/AGENTS.md.

### Marketing (CMO)

**Summary:** Name it `gdpr-gate`, not `pii-gate` — turns the EU constraint into the headline. Vendoring Sprinto would rent operator attention to a competitor inside our product surface; hard pass. Strong content opportunity: blog post "Why we built our own PII gate instead of bundling Sprinto's" + HN/IndieHackers distribution + comparison page. Compliance-as-positioning is a distribution moat we should explicitly own.

## Capability Gaps

None reported by leaders. `skill-creator`, `compound`, `architecture`, brainstorm-domain-config, and lefthook hook infrastructure cover the authoring + enforcement surface needed for this skill.

## Lifted Files Inventory (MIT Attribution Plan)

| Source file (gosprinto/compliance-skills) | Soleur destination | Action | Notes |
|---|---|---|---|
| `pii-detector/patterns/fields.md` (3.8 KB) | `plugins/soleur/skills/gdpr-gate/references/fields.md` | Lift verbatim + attribution header | Add Art. 9 special-category fields (political, religious, union, sexual orientation, genetic) |
| `pii-detector/rules/leakage-vectors.md` (5.9 KB) | `references/leakage-vectors.md` | Lift verbatim + attribution header | Language-neutral; no US-only framing |
| `pii-detector/layers/api-layer.md` (9.1 KB) | `references/layers/api-layer.md` | Lift verbatim + attribution header | 7 checks (AP-01..AP-07) carry over cleanly |
| `pii-detector/layers/auth-sessions.md` (6.8 KB) | `references/layers/auth-sessions.md` | Lift verbatim + attribution header | 7 checks (A-01..A-07); add Art. 32(1)(b) framing in footer |
| `pii-detector/layers/data-in-transit.md` (7.3 KB) | `references/layers/data-in-transit.md` | Lift verbatim + attribution header | Add Chapter V cross-border transfer check |
| `pii-detector/layers/data-lifecycle.md` (9.6 KB) | `references/layers/data-lifecycle.md` | Lift + EU rewrite | Sweeney 87% re-id check is gold; rewrite DL-04 export to GDPR Art. 20 + CCPA |
| `pii-detector/layers/frontend.md` (5.9 KB) | `references/layers/frontend.md` | Lift + EU rewrite | Rewrite F-03 consent-gate to ePrivacy strict-opt-in |
| `pii-detector/layers/testing-seeding.md` (6.1 KB) | `references/layers/testing-seeding.md` | Lift + EU rewrite | Add Art. 32 pseudonymization in non-prod |
| `pii-detector/rules/non-negotiables.md` (3.6 KB) | `references/non-negotiables.md` | Write from scratch | GDPR Art. 5/6/9/25/32 first-class; CCPA + HIPAA secondary |
| `pii-detector/layers/legal-consent.md` (4.0 KB) | `references/layers/legal-consent.md` | Write from scratch | ePrivacy + Art. 7/13/14/35; biggest EU gap in Sprinto's repo |
| `pii-detector/modes/repo-scan.md` (6.6 KB) | (deferred to v2) | Write from scratch when v2 happens | Drop Sprinto footer; dual EU/US summary table |
| `pii-detector/modes/inline.md` (5.8 KB) | `SKILL.md` (folded in) | Inspiration only | "Check before generating" sequencing folds into Soleur skill voice |
| `pii-detector/modes/planning.md` (4.8 KB) | `SKILL.md` (folded in) | Inspiration only | "Weave, don't append" rule is the highest-value design idea — wholesale into our voice |
| `pii-detector/SKILL.md` (5 KB) | `SKILL.md` | Write from scratch | Borrow trigger-phrase + field-name + layer-table shape; rewrite contents for Soleur dispatch |
| `pii-detector/README.md` + root `LICENSE` + root `README.md` | (drop) | — | Vendor surface; replaced by Soleur `NOTICE` |

**Attribution policy:** Add `NOTICE` file in `plugins/soleur/skills/gdpr-gate/` listing each lifted file with upstream commit SHA. Each lifted file gets a header comment: `<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->`.

**Vendor-surface scrub list (verified by deep-dive):** only `pii-detector/README.md` (logo + utm links lines 4/6/14/17/111) and `pii-detector/modes/repo-scan.md` (lines 67-68, 160-165 — Sprinto logo+tagline injected into every audit output). All `layers/`, `rules/`, `patterns/`, `modes/inline.md`, `modes/planning.md`, and `SKILL.md` are clean.
