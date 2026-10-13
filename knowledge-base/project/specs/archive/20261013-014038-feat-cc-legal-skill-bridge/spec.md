---
name: clo-founder-threshold-detection
status: ready-for-plan
lane: cross-domain
brand_survival_threshold: single-user incident
related-brainstorm: knowledge-base/project/brainstorms/2026-05-15-claude-for-legal-evaluation-brainstorm.md
related-issues: "#3785 (parent), #3786 (deferred bridge re-evaluation)"
---

# clo + legal-audit founder-threshold detection (no claude-for-legal integration)

> **Branch-name note:** the worktree is `feat-cc-legal-skill-bridge` for historical reasons (the brainstorm investigated a bridge to `anthropics/claude-for-legal`). The leader triad (CPO + CMO + CLO + CTO) converged on **no integration**. The actual deliverable is a CLO upgrade, captured here.

## Problem Statement

Today, when a Soleur user (founder) hits a legal need that exceeds founder-grade compliance helping (vendor MSA review, DSAR request, AI vendor terms onboarding, OSS license classification, breach notice triage), `clo` orchestrates internal agents (`legal-document-generator`, `legal-compliance-auditor`) but does not recognize the threshold or recommend a downstream specialist tool. The founder gets either: (a) a Soleur-native draft that's appropriate for founder-grade work but inadequate for the actual need, or (b) silence.

Anthropic's `claude-for-legal` plugin marketplace (12 lawyer-targeted plugins, 80+ agents) is one possible downstream specialist, alongside e.g. `gosprinto/compliance-skills` (already lifted into `gdpr-gate`) and other peer SaaS-legal tools. The brainstorm rejected direct integration (audience mismatch, brand-confusion risk, Apache-2.0 lift overhead) but identified value in **threshold detection + vendor-neutral recommendations**.

## Goals

1. `clo` agent recognizes 4-5 well-defined founder thresholds and emits a Soleur-native triage output that names the threshold + recommends 1-2 downstream tools (vendor-neutral).
2. `legal-audit` skill flags audit findings that cross the threshold with the same recommendation pattern.
3. New `knowledge-base/legal/recommended-tools.md` lists vendor-neutral downstream options including `claude-for-legal`, `gosprinto/compliance-skills`, and at least one peer SaaS-legal tool.
4. Existing disclaimer/gate patterns (`plugins/soleur/agents/legal/legal-document-generator.md:22`, `plugins/soleur/skills/gdpr-gate/SKILL.md:10`) carried forward verbatim — no new disclaimer drift.

## Non-Goals

- **Not** importing/delegating/lifting any code from `anthropics/claude-for-legal`. (Brainstorm rationale: audience mismatch + Apache-2.0 NOTICE/drift overhead exceeds value.)
- **Not** producing `/soleur:legal-*` commands that wrap upstream plugins. (CMO: brand-confusion risk; CTO: hardcoded `~/.claude/plugins/config/...` profile-path silent failures.)
- **Not** amending Soleur ToS for legal-tooling-bridge UPL coverage. (Unnecessary under no-bridge path; defer until/unless a bridge is actually built.)
- **Not** adding Anthropic as a sub-processor row in `data-protection-disclosure.md` for this scope. (No founder data flows through claude-for-legal under this path.)
- **Not** building an Apache-2.0 NOTICE generator skill or an upstream-drift cron. (Capability gaps deferred — only triggered by lift path.)
- **Not** privileging Anthropic over other downstream specialists in the recommendations page.

## Functional Requirements

- **FR1 — Threshold catalog.** `clo` agent encodes 4-5 founder thresholds, each with: (a) trigger description, (b) Soleur-native triage output template, (c) 1-2 recommended downstream tools with brief rationale per recommendation. Final list TBD with the user (Open Question 1 from brainstorm).
- **FR2 — `legal-audit` integration.** When `legal-audit` produces a finding that exceeds founder-grade scope (severity = HIGH OR finding category in threshold catalog), the inline output appends a "When to escalate" block referencing the relevant `recommended-tools.md` row.
- **FR3 — `recommended-tools.md`.** New file at `knowledge-base/legal/recommended-tools.md`. Vendor-neutral structure: one section per threshold, listing 2-3 specialist tools per threshold with name, license, install/use hint, and one-line "best for". claude-for-legal listed alongside gosprinto/compliance-skills and ≥1 peer.
- **FR4 — Disclaimer carry-forward.** All triage outputs use the existing top-and-bottom DRAFT disclaimer pattern (`legal-document-generator.md:22`). No new disclaimer text invented.
- **FR5 — Re-evaluation hooks.** Brainstorm verdict referenced in `clo.md` (similar to how `2026-03-10-claude-marketplace-evaluation-brainstorm.md` is cited elsewhere) so a future agent re-asking the bridge question reads the rationale before re-spawning leaders. Brainstorm `## Open Questions` re-evaluation criteria captured in a comment.

## Technical Requirements

- **TR1 — No new skills.** Implementation extends existing `clo` agent + `legal-audit` skill; adds one knowledge-base doc. No new entries in `plugins/soleur/skills/`. Avoids triggering `hr-new-skills-agents-or-user-facing` review surface.
- **TR2 — AGENTS.md compliance.** Changes to `clo.md` stay within token budget (`plugins/soleur/AGENTS.md` lines 108-112: cumulative agent descriptions under ~2,500 words). Agent frontmatter unchanged.
- **TR3 — Brand-survival enforcement.** `brand_survival_threshold: single-user incident` carried into the plan via `## Domain Review (carry-forward)` per Phase 2.6 plan-skill template. `user-impact-reviewer` agent fires at PR review (per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`).
- **TR4 — GDPR-gate fires via brand-survival trigger; no Critical findings expected.** [Updated 2026-05-15 from "No GDPR-gate trigger" — corrected by plan spec-flow review.] This change adds documentation + threshold rules with no schema/migration/auth/API surface, BUT `hr-gdpr-gate-on-regulated-data-surfaces` trigger (b) fires unconditionally when `brand_survival_threshold = single-user incident`. Plan Phase 6 invokes the gate; expected outcome is PASS with no Critical findings (no regulated-data surface). If Critical findings emerge, follow gate procedure (operator-acknowledged write to `compliance-posture.md` + `compliance/critical`-labeled issue).
- **TR5 — Vendor-neutrality test.** `recommended-tools.md` must list ≥ 2 vendors per threshold (claude-for-legal cannot be the sole recommendation for any threshold). Lefthook check optional; manual review at PR is sufficient.

## Open Questions (carried from brainstorm)

1. Final 4-5 founder thresholds (need user input — last-90-day founder experience).
2. Specific peer SaaS-legal tools to list alongside claude-for-legal + gosprinto.
3. Re-evaluation cadence for the bridge decision (current proposal: ALL of click-through > N/month for ≥ 60 days, founder-explicit-request signal, CPO demand confirmation).

## Domain Review (carry-forward)

Triad sign-off captured in brainstorm `## Domain Assessments`:

- **CLO:** No new UPL/malpractice surface under no-bridge path; existing disclaimers sufficient. Approved.
- **CPO:** Honors PIVOT verdict (validate demand first). Approved.
- **CMO:** On-brand; docs-only marketing surface; no counsel-review gate. Approved.
- **CTO:** Lowest-risk; no capability gaps triggered; reuse existing patterns. Approved.

`user-impact-reviewer` agent must fire at PR review per `hr-weigh-every-decision-against-target-user-impact` (single-user-incident threshold).
