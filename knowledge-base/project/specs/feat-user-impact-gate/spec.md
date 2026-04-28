---
title: Target-User-Impact Workflow Gate
feature: feat-user-impact-gate
date: 2026-04-24
issue: 2888
triggered_by: 2887
branch: feat-user-impact-gate
pr: 2889
status: specified
owner: CPO
brainstorm: knowledge-base/project/brainstorms/2026-04-24-target-user-impact-gate-brainstorm.md
---

# Spec: Target-User-Impact Workflow Gate

## Problem Statement

Every workflow decision that touches credentials, auth, data persistence, payments, or user-owned resources is currently weighed on technical/convenience axes (is the mechanism wired correctly? is the secret fetched at the right time?). No workflow step asks *"what is the worst thing the target user experiences if this fails, silently or loudly?"*

This is the root cause of incident #2887 — the `dev` and `prd` Doppler configs for the `soleur` project both hold connection strings that point to the **same Supabase project**. Every dev read, write, migration, backfill, or schema change executes against the single shared database that prod users depend on. The setup shipped months ago; the existing `cq-doppler-service-tokens-are-per-config` rule protected the token scoping but never asked what a real user's data breach would cost the brand.

Per the discovery framing: *"if one Soleur user is exposed or has such a security breach, the impact to the brand will be such that we will lose all business."*

## Goals

1. **Force user-framing at the earliest decision point** (brainstorm Phase 0) before domain routing fires. The question must be presented to the user even when the request seems purely technical.
2. **Require a `## User-Brand Impact` section on every plan**, with a three-level `brand-survival threshold` (`none` | `single-user incident` | `aggregate pattern`).
3. **Halt `deepen-plan`** when the section is missing (hard gate, not a warning).
4. **Spawn a dedicated `user-impact-reviewer` agent** during review when the plan marks threshold = `single-user incident`.
5. **Block ship via preflight** when the diff touches sensitive paths AND the `## User-Brand Impact` section is missing (or threshold=`none` with demonstrable sensitive-path contact and no scope-out justification).
6. **Codify the gate in AGENTS.md** so every session sees it on every turn.
7. **Validate with an in-session smoke scenario**: author a synthetic plan targeting `apps/web-platform/server/session-sync.ts` omitting the section, run through `/soleur:plan` → `/soleur:review` → `/soleur:ship`, capture evidence each gate fires, remove the synthetic plan before merge.

## Non-Goals

- CI workflow enforcement (parse PR body + diff, fail merge without section). **Deferred** to follow-up issue — tracked separately. This PR is skill-markdown-only.
- Retiring `cq-doppler-service-tokens-are-per-config`. That rule stays; the new gate is complementary.
- Adding `security-sentinel` as a brainstorm Phase 0.5 domain leader. It remains a review-time agent only.
- Automated generic-boilerplate detection (e.g., rejecting "users experience a bug" as the section content). The new `user-impact-reviewer` agent handles this at review time via its prompt contract.
- Extending the gate to external plugins or consumers outside this repo.

## Functional Requirements

**FR1 — Brainstorm Phase 0 mandatory question.** Before Phase 0.5 domain routing, present the user (via AskUserQuestion) with: *"If this decision ships as designed, what is the worst outcome the target user experiences? If it silently fails, what do they see? If it leaks, what data of theirs is exposed?"* Parse the answer for trigger keywords (`data loss`, `trust breach`, `credential exposure`, `billing surprise`, `user data`, `credentials`, `payment`, `auth`). If any match, tag the session as `user-brand-critical` and spawn **CPO + CLO + CTO** in parallel before other specialists run.

**FR2 — Plan mandatory section.** Every plan output by `/soleur:plan` must include a `## User-Brand Impact` section containing three lines:
- `If this lands broken, the user experiences: [...]`
- `If this leaks, the user's [data / workflow / money] is exposed via: [...]`
- `Brand-survival threshold: none | single-user incident | aggregate pattern`

When threshold is `single-user incident`, the plan MUST be signed off by CPO before `/work` begins (same gate shape as the existing Product/UX Gate).

**FR3 — deepen-plan halts on missing section.** `skill: soleur:deepen-plan` greps its target plan for `## User-Brand Impact`. If absent, exits with a clear error referencing the plan skill template line number. Hard gate.

**FR4 — `user-impact-reviewer` agent.** New file at `plugins/soleur/agents/engineering/review/user-impact-reviewer.md`. Single job: enumerate every way the change can hurt a user and require each explicitly mitigated or scope-outed. Prompt contract requires naming (a) a specific user-facing artifact (email, workspace, API key, conversation, message, billing event) and (b) a specific exposure vector (cross-tenant read, credential leak, data loss, double-charge, silent drop). Rejects generic boilerplate ("users experience a bug").

**FR5 — Review conditional spawn.** `skill: soleur:review` spawns `user-impact-reviewer` when the plan's threshold = `single-user incident`. Invocation lives in the `<conditional_agents>` block of `plugins/soleur/skills/review/SKILL.md`.

**FR6 — Preflight Check N.** `skill: soleur:preflight` adds a new check: "Brand-Survival Self-Review." Fails when:
- Diff touches any path matching: `apps/web-platform/server/**`, `apps/web-platform/supabase/**`, `apps/web-platform/lib/{stripe,auth,byok}*`, `infra/**`, `**/doppler*.{yml,yaml,sh}`, `.github/workflows/*doppler*.yml`
- AND the PR body is missing `## User-Brand Impact` OR the section is empty OR threshold is `none` without an inline scope-out note of the form `threshold: none, reason: <why this touched path is not user-impacting>`.

Interactive mode prompts the user to fill in the section. Headless mode aborts with the rule reference.

**FR7 — AGENTS.md hard rule.** Append a new Hard Rule (ID: `hr-weigh-every-decision-against-target-user-impact` pending lint-rule-ids.py assignment). Under the 600-byte cap per `cq-agents-md-why-single-line`. References issue #2888 + #2887 in `**Why:**` line.

**FR8 — Smoke scenario evidence.** Create `knowledge-base/project/specs/feat-user-impact-gate/smoke-evidence.md` containing command output + screenshots from running the synthetic plan through all three gates. Synthetic plan file is deleted before merge; evidence file stays.

## Technical Requirements

**TR1 — Phase numbering.** Use the quarter-step decimal convention (already used for Phase 0.25, 0.5, 3.5). The new brainstorm Phase 0 question inserts *before* Phase 0.25 Roadmap Freshness Check — call it `Phase 0.1 User-Impact Framing` or integrate into Phase 0. TBD during plan.

**TR2 — domain-config table row (or decision to skip).** Issue §1 implies escalation "before any other specialist runs." Options: (a) add a virtual `user-brand-critical` tag processed in Phase 0.5 processing instructions, OR (b) add a domain-config row for each of CPO/CLO/CTO already existing — we just bump their priority. Chosen direction: (a), since CPO/CLO/CTO are already domain leaders; we just need the tag to reorder their invocation. Implementation detail resolved during plan.

**TR3 — Preflight glob list implementation.** Mirror the pattern of the existing migration/security/lockfile checks in `plugins/soleur/skills/preflight/SKILL.md` (lines 44-192). Use `git diff --name-only` piped to `grep` with the glob list. Override detection via `grep -E '^threshold:\s*none,\s*reason:'` inside the PR body's `## User-Brand Impact` section.

**TR4 — Review skill conditional_agents block.** Add a new `<conditional_agent>` entry to `plugins/soleur/skills/review/SKILL.md` line 102 region. Trigger: plan text contains `Brand-survival threshold: single-user incident`. Action: spawn `user-impact-reviewer`.

**TR5 — AGENTS.md budget tracking.** Current size ~36,878 bytes. Target: rule ≤ 400 bytes so post-add size lands ~37.3k (past warn, under critical). The rule itself must be tight enough to leave headroom.

**TR6 — Rule ID assignment.** Run `python3 scripts/lint-rule-ids.py` after adding the rule to verify ID format and immutability. Confirm the `retired-rule-ids.txt` manifest does not already claim the proposed ID.

**TR7 — deepen-plan grep contract.** Add new Phase (number TBD — mirror `hr-ssh-diagnosis-verify-firewall`'s Phase 4.5). Grep: `grep -q '^## User-Brand Impact' <plan-file>`. Exit with `plugin path reference + line number of the plan skill template` on miss.

## Out-of-Scope Files (do not edit)

- `.github/workflows/*` — CI enforcement is deferred.
- `scripts/lint-rule-ids.py` — run only, no edits.
- `apps/web-platform/**` — no production code changes; this is workflow-only.
- Any `knowledge-base/marketing/**`, `knowledge-base/sales/**`, `knowledge-base/finance/**` — unrelated domains.

## Files to Touch

| File | Change |
|---|---|
| `plugins/soleur/skills/brainstorm/SKILL.md` | Add Phase 0.1 mandatory user-impact question (before Phase 0.25). Parse answer for trigger keywords. Tag session `user-brand-critical`. |
| `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` | Document the `user-brand-critical` tag and its CPO + CLO + CTO escalation. No new domain row. |
| `plugins/soleur/skills/plan/SKILL.md` | Add mandatory `## User-Brand Impact` section to plan template. Document 3-level threshold. Document CPO sign-off gate on `single-user incident`. |
| `plugins/soleur/skills/deepen-plan/SKILL.md` | Add new Phase that halts if `## User-Brand Impact` missing. |
| `plugins/soleur/skills/review/SKILL.md` | Add `user-impact-reviewer` conditional-agent entry. Trigger on `Brand-survival threshold: single-user incident`. |
| `plugins/soleur/skills/preflight/SKILL.md` | Add Check N: "Brand-Survival Self-Review." Glob list + override detection. Interactive/headless branching. |
| `plugins/soleur/agents/engineering/review/user-impact-reviewer.md` | **NEW.** Agent definition with prompt contract requiring user-facing artifact + exposure vector. |
| `AGENTS.md` | Append new `hr-*` rule under 600-byte cap. Reference #2888 + #2887 in `**Why:**`. |
| `scripts/retired-rule-ids.txt` | No edit — new rule, not retiring any. |
| `knowledge-base/project/specs/feat-user-impact-gate/smoke-evidence.md` | **NEW.** Evidence from running synthetic plan through plan → review → preflight. Captured post-implementation. |

## Acceptance Criteria

- [ ] Brainstorm Phase 0.1 question fires and captures a user-impact answer before domain routing.
- [ ] Trigger-keyword match in answer escalates to CPO + CLO + CTO before other specialists.
- [ ] Every plan output by `/soleur:plan` includes a `## User-Brand Impact` section.
- [ ] `/soleur:deepen-plan` halts with a clear error when the section is missing.
- [ ] `/soleur:review` spawns `user-impact-reviewer` when threshold = `single-user incident`.
- [ ] `/soleur:preflight` Check N blocks ship when sensitive-path diff lacks the section or a valid scope-out.
- [ ] AGENTS.md contains the new `hr-*` rule; `python3 scripts/lint-rule-ids.py` passes.
- [ ] Smoke scenario executed end-to-end; `smoke-evidence.md` contains proof each gate fires.
- [ ] `user-impact-reviewer.md` agent exists and its prompt contract requires specific user-facing artifact + exposure vector.
- [ ] All 5 existing sub-task checkboxes on #2888 are checked.

## Risks

| Risk | Mitigation |
|---|---|
| Checkbox / cargo-cult drift — sections filled with generic "users experience a bug" | `user-impact-reviewer` agent rejects generic fills; prompt contract requires specific artifact + vector. Monitor via quarterly grep of `## User-Brand Impact` sections. |
| False-positive preflight blocks (e.g., a README edit inside `apps/web-platform/**` flags) | Inline scope-out note: `threshold: none, reason: <why>`. Low-cost override. |
| AGENTS.md crosses warn threshold post-ship | Accept warn; next compound nags. Deferral issue exists for rule-retirement audit. |
| Humans merging via GitHub UI bypass preflight | Known gap. Deferral issue #N for CI workflow enforcement closes this. |
| CPO becomes bottleneck on `single-user incident` sign-off | Revisit if more than 2 PRs/week get labeled; promote security-sentinel as co-signer. |

## Dependencies

- Depends on existing worktree + PR #2889.
- Depends on existing `user-impact-reviewer` agent being created as part of this PR (no external dependency).
- No new secrets / infra / Doppler config changes required.

## Success Metrics (post-ship)

- Within 4 weeks of ship: at least 1 plan is sent back by the gate with threshold mislabeled or section missing.
- Within 8 weeks: observe the threshold-label distribution. Healthy signal: ≥20% of sensitive-path PRs carry `single-user incident`. Red flag: 100% `none`.
- Within 12 weeks: audit for generic-boilerplate — grep sections for "users experience a bug" / "error state" / boilerplate patterns. Target: 0.

## Next Step

`skill: soleur:plan` to decompose into tasks.
