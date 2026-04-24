---
title: Target-User-Impact Workflow Gate
date: 2026-04-24
status: captured
issue: 2888
triggered_by: 2887
branch: feat-user-impact-gate
pr: 2889
owner: CPO
domains_assessed: [Engineering, Product, Legal]
---

# Brainstorm: Target-User-Impact Workflow Gate

## What We're Building

A new workflow gate that threads through **brainstorm → plan → deepen-plan → review → preflight (ship)** and is reinforced by one AGENTS.md hard rule. Every design, plan, and PR that touches credentials, auth, data persistence, payments, or user-owned resources must answer one concrete question before implementation begins:

> **What is the worst thing the target user experiences if this fails — silently or loudly?**

The gate was triggered by #2887 (dev and prd Doppler configs pointing at the same Supabase project — a single-user data breach that shipped for months because no workflow step ever asked the user-framing question).

## Why This Approach

Existing gates catch technical correctness (`cq-*` rules), silent observability drops (`cq-silent-fallback-must-mirror-to-sentry`), and per-config credential scoping (`cq-doppler-service-tokens-are-per-config`). None of them ask *"is the blast radius on a single user acceptable?"*. #2887 sat exactly inside that blind spot — the existing rule protected the token but not the database the token pointed at.

Research findings that shaped the design:

- **No prior "user-brand" vocabulary exists** in the codebase. "blast radius" appears informally ~20 times. We are introducing new canonical framing.
- **Learnings show the same pattern recurs**: Supabase silent-error-return (`2026-03-20`), env var mis-attribution (`2026-03-20`), terraform drift exit-0 (`2026-03-21`), engineering-scope crowding out user-framing (`2026-03-17`). The gate question "what user sits behind this?" would have surfaced all four.
- **Gate must cover both omission and commission**: "what does the user *see go wrong*?" (loud) AND "what does the user *never notice is wrong*?" (silent). Silent drops are the larger class.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Ship full scope** — all 5 sub-tasks per issue #2888. | Operator preference. Incident-response value of strong framing across the full workflow is high; narrow MVP was an option but rejected in favor of comprehensive coverage. |
| 2 | **Brainstorm Phase 0 question is mandatory and presented via AskUserQuestion** on every brainstorm. | Issue §1 requires the question be presented even when the request seems technical — the whole point is to force the framing. Answers parsed for trigger keywords (data loss, trust breach, credential exposure, billing surprise). |
| 3 | **Escalation set on `user-brand-critical` tag: CPO + CLO + CTO.** Drop COO (domain config is vendor/tooling/expense — mismatched for user-data framing). Drop security-sentinel from brainstorm-phase (it stays review-only via the new `user-impact-reviewer`). | CPO owns product decision quality; CLO owns data-exposure / compliance lens; CTO owns architectural blast radius. Coherent separation: brainstorm-time = strategic framing, review-time = technical security. |
| 4 | **Plan mandatory section `## User-Brand Impact`** with three lines: user-experience-if-broken, data-exposure-vector, brand-survival-threshold (`none` \| `single-user incident` \| `aggregate pattern`). | 3-level threshold per issue spec. Even though pre-beta "aggregate pattern" is mostly empty today, keeping 3 levels reserves vocabulary for when the product scales past ~100 paying users. |
| 5 | **deepen-plan HALTS on missing section.** Hard gate, not a warning. | Matches the shape of existing `hr-ssh-diagnosis-verify-firewall` skill-enforced hook in plan Phase 1.4 / deepen-plan Phase 4.5. Soft warnings get dismissed. |
| 6 | **Review creates a new `user-impact-reviewer` agent** (not a prompt addendum on security-sentinel). Spawned when plan marks threshold = `single-user incident`. | Operator preference for dedicated agent with single job: enumerate every way the change can hurt a user; require each explicitly mitigated or scope-outed. Accepts the 9th review-agent maintenance cost in exchange for separation of concerns. |
| 7 | **Preflight Check N uses broader globs + in-section scope-out**. Trigger paths: `apps/web-platform/server/**`, `apps/web-platform/supabase/**`, `apps/web-platform/lib/{stripe,auth,byok}*`, `infra/**`, `**/doppler*.{yml,yaml,sh}`. Override: a note inside `## User-Brand Impact` of the form `threshold: none, reason: <why this touched path is not user-impacting>`. | Survives file renames/additions. False-positive cost is a one-line justification — cheap. Narrow enumeration rots as the codebase grows. |
| 8 | **AGENTS.md rule added; accept 37.3k bytes (past 37k warn threshold).** Single `hr-*` rule under the 600-byte cap. Points to this issue + #2887 in `**Why:**` line. | One byte of warn-headroom today, 2.6k critical-headroom. Next compound nags, operator decides if a retirement is warranted. #2887 is P0 — ship, don't block on budget cleanup. |
| 9 | **CI workflow enforcement DEFERRED** to a follow-up issue. This PR is skill-markdown only. | Operator preference. Known tradeoff: preflight only fires in agent sessions; humans merging via GitHub UI bypass the gate. The new CI-workflow follow-up issue will close that gap. |
| 10 | **Smoke scenario RUN in-session**, evidence captured in `smoke-evidence.md` in the spec directory. Synthetic plan targets `apps/web-platform/server/session-sync.ts`, removed before merge. | Validates the gate actually fires before it lands. Same principle as `wg-when-a-feature-creates-external-resources` — the black-box probe is the shipping gate. |

## Non-Goals (explicitly excluded)

- **CI workflow enforcement** — deferred to follow-up issue (see Deferrals below).
- **Retiring `cq-doppler-service-tokens-are-per-config`** — that rule stays; this gate is complementary, not a replacement.
- **Adding `security-sentinel` as a brainstorm-Phase-0.5 domain leader** — it remains a review-time agent only.
- **Automating generic-boilerplate detection** in the `## User-Brand Impact` section (CTO's concern about "users experience a bug" cargo-culting). The new `user-impact-reviewer` is expected to reject generic fills at review time; no grep-based linter in this PR.
- **Extending the gate to non-Soleur plugins or external consumers.** Scope is this repo only.

## Deferrals (tracking issues to be opened in Phase 3.6)

1. **CI workflow for user-brand-impact check** — parse PR body + diff, fail when sensitive-path diff exists and `## User-Brand Impact` is missing. Override via `scope-out-user-brand-impact` label + `## Scope-Out Justification` section.
2. **Retire-or-consolidate audit of `cq-deploy-webhook-observability-debug`** and similar specialized debugging rules — surface AGENTS.md headroom.
3. **Review of aggregate threshold collapse** at ~50 paying users (revisit whether 3-level threshold remains right).

## Open Questions

- **Phase 0 question wording exact text** — to be finalized during plan. Current working text: *"If this decision ships as designed, what is the worst outcome the target user experiences? If it silently fails, what do they see? If it leaks, what data of theirs is exposed?"* Two variants per learnings-researcher (loud + silent) may be better than one.
- **user-impact-reviewer prompt contract** — CTO flagged generic-boilerplate risk. Reviewer prompt MUST require naming (a) a specific user-facing artifact (email, workspace, API key, conversation) and (b) a specific exposure vector (cross-tenant read, credential leak, data loss). Otherwise the gate degrades to cargo-cult.
- **deepen-plan exit message** — must point the agent at the exact template block in the plan skill to auto-correct. Error wording to be drafted during implementation.

## Domain Assessments

**Assessed:** Engineering, Product, Legal

(Full assessments spawned in Phase 0.5; see agent telemetry for raw output.)

### Product (CPO)

**Summary:** Diagnosis is right, mechanism is half-right. Recommended narrower MVP shape (preflight-only + CI + rule); operator chose full scope. Checkbox risk remains real — the `user-impact-reviewer` agent is the main mitigation for boilerplate drift. CPO should watch metric: % of `single-user incident` labels that correlate with real scope narrowing vs. copy-paste sections.

### Engineering (CTO)

**Summary:** Markdown prompts are advisory. CI workflow would be the load-bearing enforcement; its deferral is a real gap humans can walk through. Broader glob strategy + in-section override survives codebase growth. AGENTS.md budget is tight but viable at 37.3k. Smoke scenario is runnable in-session, ~30 min.

### Legal (CLO)

**Summary:** Included in the `user-brand-critical` escalation set so data-exposure lens is applied at brainstorm-time framing (not just review-time). This is a net-new touchpoint — CLO was not previously involved in pre-implementation gates for credential/DB/user-data decisions. Clear fit for the #2887 class (data-isolation failure has direct legal implications).

## Capability Gaps

1. **`user-impact-reviewer` agent does not exist.** Will be created in this PR at `plugins/soleur/agents/engineering/review/user-impact-reviewer.md`.
2. **`security-sentinel` is not currently in the brainstorm Phase 0.5 domain config.** Not being added in this PR — remains review-only. Design decision #3 confirmed this is intentional.
3. **No `user-brand` / `brand-survival` vocabulary in codebase.** This PR introduces it. Section headings, threshold label names, and the AGENTS.md rule wording all need to be consistent across the 5 edit points.
