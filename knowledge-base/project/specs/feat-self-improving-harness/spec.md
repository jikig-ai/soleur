---
feature: self-improving-harness
title: Read-only weakness-miner (Self-Harness Layer 2, detection-only)
date: 2026-07-05
issue: 6037
deferred_issues: [6038, 6039]
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-07-05-self-improving-harness-brainstorm.md
---

# Spec: Read-Only Weakness-Miner

## Problem Statement

Soleur implements ~70% of the Self-Harness / HarnessX self-improving-harness loop, but the
**weakness-mining** stage — clustering recurring execution failures into an actionable signal — is
still 100% human. Downstream stages are built and guardrailed (`cron-compound-promote.ts` proposes;
`eval-gate.cjs` + ADR-069 validate). The loop is open at exactly one place. Additionally,
`rule-metrics.json` shows 97 rules with 0 fires over 8 weeks: `.rule-incidents.jsonl` telemetry is
captured but never read by any automation, so rule-fire counts are not a usable weakness signal.

## Goals

- G1. Close the weakness-mining gap with a **read-only** primitive that clusters Soleur's own
  failure signal into a ranked recurring-failure-pattern digest.
- G2. Substrate = session-error learnings corpus + raw `.rule-incidents.jsonl` (NOT rule-fire
  counts, which are all-zero).
- G3. Feed the digest into the *existing* human-gated `/compound` → promote → eval-gate pipeline —
  no new trust boundary, no harness mutation.
- G4. Surface unused-rule / obsolescence candidates as a secondary output (serves #397's deferred
  rule-retirement trigger).

## Non-Goals

- NG1. Auto-proposing or auto-applying any AGENTS.md / skill / harness edit (→ #6038, gated behind
  a new ADR).
- NG2. Any user-facing "workspace got smarter" changelog (→ #6039).
- NG3. HarnessX-style processor-combo search / AEGIS RL evolution (over-engineering at markdown
  scale — CTO).
- NG4. Auto-merge of any proposal. Human triage remains load-bearing.

## Functional Requirements

- FR1. A weekly cron/CI job aggregates the session-error learnings corpus + `.rule-incidents.jsonl`
  into a ranked recurring-failure-pattern digest artifact.
- FR2. Clustering = deterministic aggregation (by touched file/skill + rule-id) **plus exactly one
  bounded classification pass** for theme. No inference loop.
- FR3. Recurrence threshold ≥ 3 similar occurrences (re-confirm against ~3–5 learnings/week volume).
- FR4. Digest includes a secondary section: unused-rule / obsolescence candidates from
  `rule-metrics.json`.
- FR5. Digest explicitly reports whether all-zero rule fires indicate broken emit coverage vs.
  genuinely-unused rules — never treats zero as "healthy."
- FR6. Digest is a committed artifact and is linked from the operator-digest.

## Technical Requirements

- TR1. **Zero mutation surface** — the job writes only its digest artifact; it MUST NOT edit
  AGENTS.md, skills, hooks, or any harness file. (Enforce via target-path scan in the job.)
- TR2. Weekly cadence, no hot-path write (no WAL cost). Prefer a sibling script sharing the
  `rule-metrics-aggregate` workflow schedule over a new cron.
- TR3. The single classification pass has a bounded token budget and is skipped/degrades to
  deterministic-only if the budget/API is unavailable (fail-open to raw aggregation).
- TR4. Apply shipped self-modification landmines even though read-only: do not trust any
  LLM-supplied count/hash as a gating value; re-derive gating values in-job; track (don't
  gitignore) any CI-consumed config; "looks gated ≠ is gated" — exercise the operative path in an
  AC, not just registry presence.
- TR5. Observability: the job's failure path must be reachable from the existing CI/observability
  layer without SSH (hr-no-ssh-fallback-in-runbooks).

## Open Questions (carry to plan)

- Digest destination: committed markdown vs. weekly GitHub issue vs. operator-digest section.
- `.rule-incidents.jsonl` all-zero root cause (broken emit vs. genuinely-unused).
- Clustering key precision (error string vs. file/skill vs. rule-id vs. LLM theme).
- Extend `scripts/rule-metrics-aggregate.sh` vs. sibling `weakness-miner` script.

## Architecture Decision

Per `wg-architecture-decision-is-a-plan-deliverable`: this increment reuses ADR-069's validation
boundary and adds no new mutation boundary, so no new ADR is required for A. **#6038 (auto-proposer)
DOES require a new ADR** (`Auto-edit policy for AGENTS.md hard rules`) before build — recorded as a
re-evaluation gate on that issue.
