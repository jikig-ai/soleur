---
title: "Alpha-tester cohort program — onboarding flow v2 + value-prop validation loop"
feature: feat-alpha-tester-value-loop
issue: "#8880"
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
date: 2026-09-25
branch: feat-alpha-tester-value-loop
pr: 8868
brainstorm: knowledge-base/project/brainstorms/2026-09-25-alpha-tester-value-loop-brainstorm.md
related:
  - knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md
  - knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md
  - knowledge-base/product/roadmap.md
  - knowledge-base/project/learnings/technical-debt/2026-09-25-system-one-decision-engine-eval-deferred.md
  - knowledge-base/legal/2026-08-06-alpha-tester-processing-annex.md
  - knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
IaC routing gate reviewed and opted out deliberately pending plan: this change provisions no
new infrastructure. If the Slack tester channel requires workspace provisioning, that is a
vendor workspace, not Terraform-managed host infra; any new vendor/sub-processor decision
routes to CLO at plan time.
-->

# Feature: Alpha-tester cohort program — onboarding flow v2 + value-prop validation loop

## Problem Statement

Soleur's Phase 4 validation protocol (#1439–#1443) is running — tester #1 onboarded 2026-08-06 —
but the loop is incomplete and unmeasured: tester #1's 2-week checkpoint was never filed,
first-session orientation never fires on real (marketplace) installs, the cohort has no
tracking surface, and on self-hosted CLI no activation/retention/agent-mix signal exists at
all. Without measurement machinery the protocol cannot produce its own verdict (CaaS thesis
holds / compounding thesis holds / neither).

## Goals

- Testers 2–10 onboard on the hosted platform through a documented, near-zero-friction flow
  (guided session + guided Anthropic-key setup + Slack channel + setup doc).
- Cohort state is visible in one pull (`soleur:cohort-status`), not scattered across a runbook
  tally, issue comments, and the CRM.
- Checkpoints are armed (schedule-reminder primitive), not remembered.
- Activation/retention/agent-mix are measurable per the existing funnel definition
  (domainCount ≥ 2, span ≥ 14d) scoped to the alpha cohort.
- A durable, field-allowlisted decision log (`.soleur/decisions.jsonl`) captures
  routing/skill/agent decisions on tester and operator machines — serving #1442 metrics, the
  parked System-1 eval corpus (tech-debt enabling action), and decision-quality feedback.
- Tester #1's owed actions are closed and the loop repaired before tester #2.

## Non-Goals

- Opt-in telemetry beacon / any egress from tester machines — deferred (Posture C consent
  stack; re-eval when a checkpoint pull proves insufficient for ≥2 testers or a tester asks
  for live observability).
- The System-1 decision-engine eval itself (Laya/Jev) — parked tech debt; none of its four
  revisit triggers has fired.
- BYOK delegation flag flip — legal-gated on the Side Letter.
- Questionnaire-driven onboarding (#6008), CRM UI editing (#6250), tester-visible CRM (#6171).
- New vendor/sub-processor procurement; in-product UI changes (cohort capture rides the
  existing invite-token flow).

## Functional Requirements

### FR1: Hosted onboarding path (runbook v2)

Update `alpha-tester-onboarding.md` for the hosted surface: guided Anthropic-key setup step,
Slack channel setup, structured #1441 observation template (four protocol prompts as an
`interview_notes` skeleton), and checkpoint arming via `POST /api/internal/schedule-reminder`
(issue-comment action at +14d) replacing the remember-to-file step.

### FR2: Tester-#1 repair

Close tester #1's owed actions: file/run the overdue 2-week checkpoint (aggregate KB-growth
pull + self-reported usage, disclosed as such); execute #7459 terms re-notify (2.5.0 → 2.5.1);
create the beta-CRM contact (platform serving; owner-authenticated RPC path only — never a
scripted bypass); C9 determination re-run per #7348 before tester #2's first session; retro
problem interview flagged post-exposure (never pooled with clean #1440 data).

### FR3: Cohort-status skill

`soleur:cohort-status` — pull-based cohort table: recruit tally + mix floor check, per-tester
stage (from `beta_contacts` via owner RPC where platform allows, else issue-derived), armed vs
overdue checkpoints, quiet signal (`last_contact`/`next_action_date` fields where populated).
Zero personal data — company + repo URL only (git-safe output).

### FR4: Recruitment mechanics

Runbook + recruitment artifacts: non-CC screening question added to the recruitment DM
(repo-scan demoted to corroboration), non-CC seats targeted first (testers #2–4), channel +
framing attribution recorded per tester (CRM fields; company-level in git), waitlist-harvest
wave option documented.

### FR5: Tester-facing setup doc

A canonical hosted-platform setup document the welcome message's `[link to setup instructions]`
can point at — near-zero-friction, no assumed Claude Code fluency.

### FR6: First-session welcome fix

`welcome-hook.sh:16` guard corrected so marketplace-installed projects get the welcome sentinel
(`#5119` class). Detection must not depend on `plugins/soleur` existing in the project tree.

## Technical Requirements

### TR1: Local decision log

`.soleur/decisions.jsonl` on the user's machine — append-only, flock'd, rotated, fail-open
(exit-0), kill-switch env; outside the user's git tree is the default, committable by the
user's own choice only. Field-allowlisted schema (NO-ECHO): `{ts, event, surface, label,
skill, agent_domain, harness, session_id, plugin_sha}` — never intent text, args, file paths,
or repo names. Harness-tagged; capture-rate vs usage-rate divergence disclosed.

### TR2: Dual-write capture

(a) plugin `hooks.json` gains `^(Skill|skill|Task|run_subagent)$` matchers where the harness
supports hooks (Claude Code; Devin-local with lowercase wire names via `HOOK_TOOL_KIND`);
(b) `plugins/soleur/scripts/emit-decision.sh` invoked by skill prose at decision points
(`go.md` route label first — highest-value, cheapest record) covering all four harnesses.
Divergence between the two halves is itself measurable (drop-sentinel precedent).

### TR3: Checkpoint aggregate pull

`plugins/soleur/scripts/alpha-metrics.sh` — tester-run script printing decision-log aggregates
(wc -l, per-skill/per-domain counts, first/last ts, logger-present probe with an
`SOLEUR_*_ABSENT` absence marker for stale installs) plus `git log --stat` KB-growth
instructions. Tester-initiated export only; non-personal aggregates.

### TR4: Cohort tagging + funnel scoping

Cohort attribution via invite-token acceptance recorded server-side (schema decision at plan:
users column vs invite join vs beta_contacts link — gdpr-gate applies, PII boundary unchanged).
`/api/admin/analytics` gains a cohort scope over the existing `computeFunnel`/`computeMetrics`
— no new tracking categories.

### TR5: Privacy/compliance invariants

No personal data in git (company + repo URL only). No new regulated surface: local writes +
tester-initiated aggregates only; any future beacon needs consent + Art. 13 + PA row + docs
lockstep (out of scope). `soleur:gdpr-gate` invoked manually at plan Phase 2.7 and work Phase
2 exit — the canonical regex does not cover `plugins/soleur/` paths. Every #1442 finding
carries the surface caveat (hosted-era vs CLI-era data are not comparable).
