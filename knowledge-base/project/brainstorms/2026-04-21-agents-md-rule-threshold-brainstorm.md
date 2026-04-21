---
title: AGENTS.md rule threshold — hybrid raise + activate prune pipeline
date: 2026-04-21
issue: 2686
related: [2683, 2213, 2573]
branch: feat-agents-rule-threshold
status: decided
---

# AGENTS.md rule threshold — hybrid raise + activate prune pipeline

## Context

`AGENTS.md` holds **106 rules** (via `grep -c '^- '`) as of 2026-04-21 — 6 over the 100-rule warn threshold defined in `cq-agents-md-why-single-line` (compound step 8). Byte size is 36,566 (3,434 under the 40,000-byte cap); longest rule is 582 bytes (18 under the 600-byte per-rule cap). The warn is already firing on main and will fire every compound run.

Issue #2686 was filed by the review phase of PR #2683, which added the single load-bearing rule `hr-ssh-diagnosis-verify-firewall` (rule 106). The threshold breach pre-dates PR #2683 — the rule count was already at 105 before it merged.

**Relevant infrastructure already on main:**

- `scripts/rule-metrics-aggregate.sh` — weekly aggregator (Sunday 00:00 UTC) parses AGENTS.md + `.claude/.rule-incidents.jsonl` into `knowledge-base/project/rule-metrics.json`. Added in PR #2213; refined in PR #2573.
- `scripts/rule-prune.sh` — files GitHub issues milestoned to "Post-MVP / Later" for rules with zero hits over a configurable week window (default 8). Surfaces candidates; does NOT edit AGENTS.md.
- `.github/workflows/rule-metrics-aggregate.yml` — scheduled workflow.

Section distribution of the 106 rules: 43 `cq` (code quality), 27 `hr` (hard rules), 25 `wg` (workflow gates), 6 `rf` (review & feedback), 3 `cm` (communication), 2 `pdr` (passive domain routing).

## What We're Building

A single PR that does three things under Option C:

1. **Raise the threshold** in `cq-agents-md-why-single-line` from 100 → 115 (with a documented rationale tying the new value to empirical growth and `cq-rule-ids-are-immutable`).
2. **Verify/activate the prune pipeline** — confirm the scheduled `rule-metrics-aggregate.yml` workflow has run at least once against current main, `rule-metrics.json` is being committed, and `scripts/rule-prune.sh --dry-run` surfaces candidates without erroring. File follow-up issues only if gaps exist.
3. **Migrate 3–5 already-skill-enforced `cq` rules** whose enforcement lives entirely in a skill or hook (e.g., rules tagged `[skill-enforced: ...]` or `[hook-enforced: ...]` whose runtime behavior is the load-bearing part) into the target skill/hook's own instruction surface, replacing the AGENTS.md entry with a one-line pointer or deprecation marker per `cq-rule-ids-are-immutable`.

Net effect: rule count drops by 3–5 to ~101–103, threshold rises to 115, compound step 8 warnings stop firing, and the prune pipeline takes over as the long-term mechanism.

## Why This Approach

- **Option B alone (raise to 120)** is a bandaid: it removes the noise but doesn't engage the mechanism that actually keeps rules accountable. It also risks threshold creep — if 100 wasn't load-bearing, 120 likely isn't either.
- **Option A alone (prune under 100)** ignores that all 106 rules cite a PR or incident. Blanket pruning without runtime evidence risks re-creating rules the next time the incident recurs. The prune pipeline exists specifically to provide that evidence, but it hasn't been exercised yet.
- **Option C (hybrid)** is the only approach that both removes the immediate noise AND exercises the existing automation. Raising to 115 (not 120) keeps pressure visible; the migration pass proves the skill-enforcement pattern works; activating the prune pipeline makes the count self-regulating.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Threshold new value | 115 (not 120) | Preserves pressure; 5-rule cushion above current 106 is a deliberate budget, not a blank check. |
| Scope of skill migration | 3–5 rules, single PR | Avoids judgment-heavy per-rule consolidation; proves the pattern so future reductions are cheaper. |
| Immutability handling | Deprecation note + replacement pointer | Per `cq-rule-ids-are-immutable`; rule IDs never silently disappear. |
| Pruning cadence | Use existing weekly aggregator + rule-prune | No new cron; verify existing pipeline is actually firing. |
| Rule-ID selection criteria for migration | Rules with `[skill-enforced: ...]` or `[hook-enforced: ...]` annotations where the AGENTS.md text adds no semantic value beyond the annotation | Safest class — behavior already lives in the skill/hook. |
| Constitution migration | Out of scope | `knowledge-base/project/constitution.md` has its own threshold (300) and is on-demand, not always-loaded. |

## Implementation Notes

- Keep rule-ID immutability: rule IDs of migrated rules must remain grep-able in AGENTS.md (as a short deprecation pointer) OR fully deleted with a learning-file breadcrumb documenting ID reuse-is-banned.
- The threshold edit is mechanical; the rationale edit must cite #2683, #2686, and the empirical byte/rule trajectory.
- Verify the weekly aggregator has committed at least one `rule-metrics.json` to main before shipping. If it hasn't, file a follow-up issue (don't block this PR on it).

## Non-Goals

- Migrating constitution.md rules or changing its threshold.
- Running a full audit of all 43 `cq` rules for migrateability.
- Auto-pruning rules without human review (prune pipeline is deliberately issue-filing, not AGENTS.md-editing).
- Changing the byte cap (40,000) or per-rule cap (600). Both have headroom.
- Bulk compression of existing `**Why:**` annotations (PR #2544 already did a compression pass).

## Open Questions

- **Which 3–5 cq rules to migrate in this PR?** Resolution: the planning skill enumerates candidates; user reviews the list before implementation. Defer the selection to `/soleur:plan`.
- **Has the weekly aggregator actually run against main?** Resolution: `gh run list --workflow rule-metrics-aggregate.yml --limit 5` during implementation. If zero runs, file a follow-up issue.

## Domain Assessments

**Assessed:** Engineering (CTO-adjacent — process/tooling, not product).

Engineering-only decision. No marketing, legal, operations, product, sales, finance, or support implications. No user-facing change. No architecture change. No infra change. The rule governs how agents (Claude + developers) read the repo — a tooling/process knob. No domain leaders were formally spawned because the issue is narrow (single-rule threshold + auxiliary skill-migration pass) and the infrastructure (aggregator, prune script) pre-dates this decision.

## References

- Issue: #2686
- Surfacing PR: #2683 (added rule 106, `hr-ssh-diagnosis-verify-firewall`)
- Threshold rule: `cq-agents-md-why-single-line` in `AGENTS.md`
- Immutability rule: `cq-rule-ids-are-immutable` in `AGENTS.md`
- Aggregator: `scripts/rule-metrics-aggregate.sh` (PR #2213)
- Prune surface: `scripts/rule-prune.sh`
- Weekly workflow: `.github/workflows/rule-metrics-aggregate.yml`
- Prior compression pass: PR #2544 (`chore(agents-md): compress Why narratives + add byte-budget guard`)
