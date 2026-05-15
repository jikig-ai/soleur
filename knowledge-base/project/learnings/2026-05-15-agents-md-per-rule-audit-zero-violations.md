---
date: 2026-05-15
category: best-practices
issue: "#3834"
related: [3833, 3837, 3839, 3808, 3681]
tags: [agents-md, per-rule-cap, audit, byte-budget]
---

# Learning: AGENTS sidecar per-rule cap audit — zero violations (2026-05-15)

## Audit command

The canonical per-rule body cap audit (cap = 600 B per `scripts/lint-agents-rule-budget.py`):

```bash
awk '/^- / { if (length($0) > 600) print FILENAME ":" NR ": " length($0) " B" }' \
  AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
```

Run at the start of issue #3834 (after #3808 trimmed `hr-no-dashboard-eyeball-pull-data-yourself` from 1,150 B → 488 B and #3839 added one rule):

```text
# (zero output — no per-rule violations)
```

## Finding

All 77 rule bodies across the three sidecars (`AGENTS.core.md`, `AGENTS.docs.md`, `AGENTS.rest.md`) are at or under the 600 B per-rule cap. Issue #3834's literal close-criterion was already satisfied at plan time.

## Top rule per sidecar

| Sidecar | Longest rule | Bytes | Headroom |
|---|---|---|---|
| `AGENTS.core.md` | `hr-menu-option-ack-not-prod-write-auth` (line 26) | 582 | 18 B |
| `AGENTS.docs.md` | `cq-agents-md-why-single-line` (line 6) | 586 | 14 B |
| `AGENTS.rest.md` | `wg-use-closes-n-in-pr-body-not-title-to` (line 18) | 571 | 29 B |

## Monitor

`hr-menu-option-ack-not-prod-write-auth` (582 B, 18 B headroom from cap) is compliance-tier — its Why documents the per-command-ack incident shape (#2618) and the non-interactive exec gap (#2880). Off-limits for Why-trim regardless of byte impact. Monitor at 600 B — if any future operator-facing edit pushes it over the cap, the path is to migrate context to a learning file or skill body, NOT to trim the compliance-tier Why.

## Cross-axis state at audit time

While per-rule cap was clean, **`B_ALWAYS` was in REJECT state at 22,499 B** (cap = 22,000 B). PR #3839 (merged ~30 min before this audit) added `hr-autonomous-loop-skill-api-budget-disclosure` (+439 B) and the post-#3837 headroom was insufficient to absorb it. PR #3839 explicitly scoped-out the resulting REJECT as a "pre-existing condition." Issue #3834's PR bundles the audit codification with a B_ALWAYS shrink to clear the REJECT — both deliverables operate on the same `scripts/lint-agents-rule-budget.py` output.

## Re-evaluation criteria

The per-rule cap audit must be re-run when:

1. Any rule's `**Why:**` tail is widened (the modal Why-tail trim path leaves room for re-expansion).
2. A new rule is added — verify the new body line is < 600 B before commit.
3. The B_ALWAYS shrink path requires aggressive Why-trim — if a Why-trim takes a rule from 480 B → 540 B by adding canonical text from a deeper learning file, the cap is approached.

The compound skill's Phase 1.5 Step 8 surfaces these in the standard `[ADVISORY]` line — but a dedicated audit pass like this one is the artifact future planners read to know the cap was last verified clean.

## Related

- Lineage: #3681 → #3808 → #3837 → #3839 → #3834 (this audit + B_ALWAYS shrink).
- Plan: `knowledge-base/project/plans/2026-05-15-chore-agents-core-md-rule-cap-audit-plan.md`.
- Brainstorm (structural shrink, deferred): `knowledge-base/project/brainstorms/2026-04-23-agents-md-budget-revisit-brainstorm.md` — Approach D (discoverability litmus + retired-rule-ids allowlist).
