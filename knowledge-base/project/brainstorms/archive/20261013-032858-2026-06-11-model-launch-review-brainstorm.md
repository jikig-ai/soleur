---
date: 2026-06-11
topic: model-launch-review skill
issue: 5100
parent_issue: 3791
branch: feat-model-launch-review
pr: 5157
lane: single-domain
brand_survival_threshold: not-applicable
status: brainstorm-complete
---

# Brainstorm: `model-launch-review` skill — recurring per-model-release audit

## What We're Building

A skill (`/soleur:model-launch-review`) that productizes the **manual model-launch
checklist** previously executed by hand for the #3791 tiering work. Each Anthropic
model release recurs the same five-item checklist:

1. **Model-ID swaps** across plugin reference files (learning `2026-02-22-model-id-update-patterns.md`).
2. **claude-code-action pin sync** so the embedded Agent SDK matches the new model's
   thinking-API shape (rule `cq-claude-code-action-pin-freshness`).
3. **Thinking-API shape changes per tier** (`enabled`/`budget_tokens` → `adaptive`/`output_config.effort`).
4. **Pricing-table refresh** against the authoritative source.
5. **Tier-map re-evaluation** against the Model Selection Policy.

The skill **audits + auto-fixes** the mechanical items and opens a **CI-gated PR**
(never a direct write to main). Detection is wired into an **existing scheduled cron**
that files an issue on drift or a new model release — closing the dormant-trigger gap
that let Fable 5 ship without #3791's "pricing change" trigger ever firing.

## Why This Approach

- **Premise verified live:** #3791 (the tiering issue) closed via PR #5096, merged
  2026-06-10T17:01Z. The re-eval criteria ("next Anthropic model release after the
  tiering PR merges") has condition 1 satisfied; condition 2 (next release) has **not**
  fired yet. Building the harness *now*, in the quiet window while the manual checklist
  is fresh, is ideal timing — not premature.
- **Auto-fix chosen by operator** for speed, with a structural safety net: fixes land
  in a PR gated by CI + a pre-PR compatibility probe, so the #2540 "wrong-edit-breaks-CI"
  failure mode is caught before merge rather than on the next scheduled run.
- **Reuse-existing-cron chosen by operator** to avoid new infra and solve dormancy.
  A drift-family workflow already exists (`kb-drift-walker.yml`, `rule-audit.yml`,
  `scheduled-terraform-drift.yml`) — append the model-drift check there.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Audit + auto-fix → CI-gated PR** (operator choice) | Speed; PR + CI is the safety net against silent green *and* blind auto-edit. |
| 2 | **Coupled-triple invariant**: `(model-ID, claude-code-action pin, thinking-API shape)` bumped as ONE unit per workflow | #2540 — bumping model alone against a stale pin sends a deprecated payload and 400s. |
| 3 | **Mechanical-auto-fix vs. judgment-flag split** | Auto-fix IDs / pins / pricing-table data; **flag** tier-map re-eval (judgment vs. Model Selection Policy) into the PR body for human sign-off — never auto-apply. |
| 4 | **Reuse existing scheduled cron** for detection → files issue → invokes skill | No new infra; solves the dormant-trigger gap (`2026-06-10` learning). |
| 5 | **Pre-PR compatibility probe** | Dry-run a tiny API call with the new model + the pin's SDK thinking shape before opening the PR; scheduled workflows don't run on PR, so CI alone can't catch a 400. |
| 6 | **Pricing source of truth = `claude-api` skill cached model table** | Per `2026-06-10` learning — never model memory. |
| 7 | **Grep is the inventory, not the issue's file list** | `2026-02-22` learning: issue inventories undercount (7 listed → 9 actual). |

## Open Questions

1. **Which existing cron hosts the detection?** Candidates: `kb-drift-walker.yml`
   (daily 03:00 UTC, drift-themed), `rule-audit.yml` (1st/15th), or
   `scheduled-terraform-drift.yml`. Lean `kb-drift-walker` for cadence + theme fit.
2. **How to detect "new model released"?** Poll the Anthropic models endpoint, the
   `anthropics/claude-code-action` releases (`gh api .../releases`), or both. The pin
   freshness check already uses the releases API.
3. **Pre-PR probe in CI** needs an API key + negligible token spend — confirm the
   scheduled-workflow secret scope covers it.
4. **Scope of "thinking-API shape" auto-fix** — is rewriting `claude_args` payload
   shapes across workflows mechanical enough to auto-fix, or flag-only in v1?

## Productize Candidate

N/A — this issue **is** the productization of the recurring model-launch pattern
(Productize Candidate from #3791 brainstorm Key Decision 11, now being built).

## Lane / Domain Note

`LANE=single-domain` (engineering). Domain leaders were **not** spawned: well-scoped
p3-low internal tooling with rich prior art, and the `2026-06-10` learning documents
that CTO/CFO produced false-negative capability claims on this exact topic (asserted
"no per-agent token telemetry" when `agent-token-tee.sh` already existed). The decisions
here are operator-preference (action model, trigger), not domain-expertise, calls.

## User-Brand Impact

Not applicable — internal/CI tooling. Worst case is operator-visible CI breakage
(mitigated by Key Decisions 1, 2, 5) or silent config drift (mitigated by the cron
detection + no-silent-green audit). No Soleur end-user data, credentials, or surfaces
are touched.
