---
title: AGENTS.md rule retirement — pointer-preservation deprecation pattern
date: 2026-04-21
category: best-practices
tags: [agents-md, rule-governance, migration, lint-rule-ids]
pr: 2754
issue: 2686
---

# AGENTS.md rule retirement — pointer-preservation deprecation pattern

## Context

`AGENTS.md` is loaded on every agent turn via `CLAUDE.md @AGENTS.md`. The file grew to 106 rules / 36,566 bytes by 2026-04-21, crossing the 100-rule warn threshold encoded in compound step 8 (`plugins/soleur/skills/compound/SKILL.md` §8). The threshold rule (`cq-agents-md-why-single-line`) also prescribes the migration escape valve: *"move skill-specific rules to the skills that enforce them."* That escape valve had never been exercised after `lint-rule-ids.py` shipped (PR #2213, 2026-04-14).

This PR (#2754, feat `feat-agents-rule-threshold`) raises the warn threshold from 100 → 115 **and** exercises the migration pattern on 3 rules to establish precedent. This learning captures the pattern, the rejected alternatives, and why the aggregate byte-savings number in the original plan was wrong.

## The Pointer-Preservation Pattern

### Why pointers, not removal

`scripts/lint-rule-ids.py` (L65–80) computes the set of `[id: ...]` tags present in `HEAD:AGENTS.md` and the set present in the staged working copy. Any id in the former but missing from the latter causes a hard fail. This is load-bearing — it enforces `cq-rule-ids-are-immutable`, which says "rewording preserves the ID; removal requires a deprecation note + tracking issue." The hook is stricter than the prose: it rejects removal *even with* a deprecation note, because no allowlist mechanism exists.

Therefore the only hook-compatible migration is: **move the full rule body to the owning skill/hook file, replace the AGENTS.md entry with a one-line pointer that preserves the `[id: ...]` and `[hook-enforced:/skill-enforced: ...]` tags.**

### Convention applied to all three migrations

1. Full rule body → destination file (hook script header comment OR SKILL.md section), prefixed with `Rule source: AGENTS.md — migrated YYYY-MM-DD (PR #NNNN)` so the pattern is self-documenting for future readers.
2. AGENTS.md entry replaced with: lead-in verb/imperative + destination path + preserved `[id: ...]` + preserved enforcement tag. Pointer line stays under 600 bytes (well under the per-rule cap).
3. External call sites (plans, specs, `rule-metrics.json`, hook incident emitters) continue to work because the `[id: ...]` token is still grep-able in AGENTS.md as part of the pointer line.

### The 3 migrated rules (PR #2754)

| ID | New home | Enforcement |
|---|---|---|
| `cq-after-completing-a-playwright-task-call` | `plugins/soleur/hooks/browser-cleanup-hook.sh` header | hook: `browser-cleanup-hook.sh` |
| `cq-before-calling-mcp-pencil-open-document` | `.claude/hooks/pencil-open-guard.sh` header + `plugins/soleur/skills/pencil-setup/SKILL.md` §"Untracked .pen safety" | hook: `pencil-open-guard.sh` |
| `wg-when-a-research-sprint-produces` | `plugins/soleur/skills/work/SKILL.md` §Phase 2.5 | skill: work Phase 2.5 |

## Why the threshold was raised to 115 (not 120, not 110)

Per `2026-04-18-agents-md-byte-budget-and-why-compression.md` and the per-rule-byte precedent (500 → 600 in PR #2544), pick a threshold above the growth tail, not a round number. Rule count at plan time: 106. Monthly growth since the foundational `2026-02-25-lean-agents-md.md` learning has been ~5–8 rules/month, driven by PR-citation pressure (every new rule comes with an incident receipt).

- 120: rejected as a blanket pass that signals "don't worry about growth."
- 110: rejected as too tight — leaves zero headroom once the 3 pointer-migrated rules are counted (pointers preserve count under `lint-rule-ids.py`).
- 115: ~9 rules of headroom (~1.5 months at current rate), aligns with the "modest, not blanket" signal the brainstorm reached. The rule-prune aggregator (PR #2213) is the long-term regulator; the threshold is an early warning, not a hard cap.

## Rejected alternative: the merged-id-tag pattern

The brainstorm and architecture review both considered appending a retiring rule's `[id: ...]` tag to an *adjacent* surviving rule's line (so that the id stays grep-able while the rule body is fully removed, reducing count by 1 per migration). This was rejected on two grounds:

1. **Fights the rule-governance architecture.** The one-rule-per-line convention is enforced implicitly by `grep -c '^- '` counting and by every tool/reader that extracts `[id: ...]` per line. Conflating two rules' tags onto one line breaks the "each line is one obligation" contract that agents rely on.
2. **No review has vetted the convention.** It has zero precedent in the repo and would need its own ADR-style deliberation before being adopted.

The architecturally correct full-body-removal path is to amend `lint-rule-ids.py` to support a **retired-ids allowlist** (e.g., `scripts/retired-rule-ids.txt`). That is filed as follow-up **Issue A** (see PR #2754 body, milestone "Post-MVP / Later").

## The "800 bytes saved" estimate in the plan was wrong

The plan's Technical Considerations section estimated 800–1,200 bytes saved from 3 pointer migrations ("moving ~300–400 byte rule bodies out, replacing with ~80–120 byte pointers"). That estimate contradicts the plan's own per-rule byte-impact table, which predicted:

- Rule 1 (playwright): **neutral** — original was only ~141 bytes; any pointer referencing a destination path exceeds that.
- Rule 2 (pencil): ~220 bytes saved (original ~297 bytes).
- Rule 3 (research): ~40 bytes saved.

True aggregate prediction: ~260 bytes saved, before the +120-byte `**Why:**` annotation on the threshold rule itself. Net: ~140 bytes added, not ~1,000 bytes removed.

Measured outcome on PR #2754 branch: +128 bytes (36,566 → 36,694), rule count flat at 106, longest rule 582 bytes (under the 600 cap). The spec was updated to relax FR4 to "count flat AND neutral-to-slightly-higher bytes" rather than the aspirational `wc -c ≤ baseline − 800`.

**Lesson for future AGENTS.md migration plans:** when a rule's *current* body is shorter than ~200 bytes, pointer-preservation will NOT save bytes on that rule — it may cost bytes. Byte-savings estimates should be per-rule and sum honestly, not aggregated via an optimistic average. The real win of pointer-preservation on small rules is **architectural** (rule bodies live with the enforcement, hook header becomes self-documenting) and **warn-silencing** (count stays under threshold), not byte reduction.

## Downstream reference integrity check

For each migrated ID, run at least:

```bash
rg -n '<id>' .claude/hooks/ tests/ scripts/ knowledge-base/project/rule-metrics.json \
  plans/ specs/ plugins/soleur/ AGENTS.md
```

All hits remain valid because the `[id: ...]` tag is still present in AGENTS.md as part of the pointer. Hook incident emitters in `.claude/hooks/lib/incidents.sh` that use these IDs as telemetry strings continue to work unchanged.

## See also

- `cq-rule-ids-are-immutable` (AGENTS.md) — the immutability contract
- `cq-agents-md-why-single-line` (AGENTS.md) — the threshold rule itself (now 115)
- `plugins/soleur/skills/compound/SKILL.md` step 8 — threshold enforcement
- `scripts/lint-rule-ids.py` — the diff-based immutability hook
- `scripts/lint-agents-compound-sync.sh` — new: guards that AGENTS.md and compound SKILL.md stay in sync on the threshold literal
- PR #2544 — prior per-rule byte cap raise (500 → 600)
- PR #2213, #2573 — aggregator + prune pipeline that regulates growth long-term
- `2026-04-06-rule-audit-budget-baseline-drift.md` — why we capture baseline at plan-execute time, not plan-author time
- `2026-04-18-agents-md-byte-budget-and-why-compression.md` — prior threshold-raise reasoning
- Follow-up Issue #2762 — amend `lint-rule-ids.py` to support retired-ids allowlist (unblocks full-body removal)
