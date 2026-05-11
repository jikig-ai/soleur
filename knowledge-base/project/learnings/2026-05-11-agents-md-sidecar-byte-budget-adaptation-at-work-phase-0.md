---
title: "AGENTS.md sidecar split (PR #3496) — byte-budget adaptation at /work Phase 0 for plans that pre-date the split"
date: 2026-05-11
type: learning
issue: "#2720"
pr: "#3559"
tags:
  - agents-md-sidecar
  - byte-budget
  - precondition-staleness
  - work-phase-0
related:
  - knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md
---

# AGENTS.md sidecar split (PR #3496) — byte-budget adaptation at /work Phase 0 for plans that pre-date the split

## Problem

PR #3496 (shipped 2026-05-11) split `AGENTS.md` into four files:

- `AGENTS.md` — pointer index, always-loaded
- `AGENTS.core.md` — cross-cutting rules, always-loaded via SessionStart hook
- `AGENTS.docs.md` — docs-class rules, conditionally loaded
- `AGENTS.rest.md` — code/infra-class rules, conditionally loaded

The byte-budget thresholds for the **always-loaded payload** (`AGENTS.md` + `AGENTS.core.md`) changed in the same PR:

- Old single-file `AGENTS.md` thresholds: `≤37000 bytes` (warn), advisory.
- New `AGENTS.docs.md` `cq-agents-md-why-single-line` thresholds: `≤18000 warn / ≤22000 critical` for the always-loaded payload.

PR #3559's plan (authored 2026-05-11 ~hours before /work began) hardcoded the old `37000` threshold in its Phase 2.2 LLM prompt and used the singular `tier: 'agents-md'` (referring to the pre-split single-file target). At /work Phase 0 the branch was 14 commits behind main; merging in the split was the load-bearing precondition before any Phase 1+ work could proceed.

This is the same class of failure as `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`: a plan-quoted measurement is a precondition to verify at /work start, not a fact to rely on. PR #3501 hit `~186 word headroom` against an actual `15`; PR #3559 hit a `37000 byte` budget against a real `18000 warn / 22000 critical` with the always-loaded payload at `21,949` bytes (51 bytes from critical).

## Solution

The /work Phase 0 sequence that recovers from this class of drift:

1. **Re-measure the precondition.** Re-run any measurement the plan quotes verbatim: `wc -c < AGENTS.md`, `wc -l AGENTS.core.md`, `bun test … | tail`, `gh pr list | wc -l`. If the plan says "current size is N bytes", confirm by running the same command.

2. **Identify what shifted.** For PR #3559 the diff between plan-time and /work-time was 14 main-commits including the AGENTS.md sidecar split. The split changed (a) the file layout (single file → index + 3 sidecars), (b) the byte budget thresholds (37k → 18k/22k), (c) the rule routing semantics (now domain-classed via `[id: ...] → core|docs|rest`).

3. **Patch the plan in place.** For PR #3559 the patches were: (a) Phase 2.2 prompt tier values `'skill'|'agents-md'` → `'skill'|'agents-core'`; (b) byte-cap threshold `37000` → `18000`; (c) explanation of "cross-cutting target" updated to name `AGENTS.core.md` specifically; (d) Sharp Edges entry added documenting the current 21,949-byte payload size and the 51-byte headroom.

4. **Commit the plan revision separately** before Phase 1 begins. Single commit, `Ref #<issue>` only (no `Closes`). The plan IS the spec for the subsequent commits.

## Key Insight

**Plan-quoted measurements are preconditions to verify, not facts.** Plans authored hours-or-days earlier observe a moving target; parallel branches landing in `main` invalidate the measurement. The /work skill's existing rule (`Phase 1, item 1: Plan-quoted numbers are preconditions to verify, not facts`) is the load-bearing defense — apply it on **byte budgets** alongside test pass counts, word headroom, file counts.

**A specific anti-pattern: hardcoded byte thresholds in LLM-bound prompts.** When a plan instructs an LLM to enforce a numeric cap, the cap MUST be either (a) injected at runtime from the script (the driver `wc -c`s and substitutes the number into the prompt), or (b) re-verified at /work Phase 0 against the live file. The PR #3559 plan did neither in v1; v2 adopts approach (a) — `scripts/compound-promote.sh` now computes `ALWAYS_LOADED_NOW` at runtime and injects it into the prompt, AND emits `::compound-promote-byte-budget::<now>:<cap>` as observable telemetry, AND the workflow enforces the cap post-`git apply` with revert-on-overflow.

**The discoverability litmus from `wg-every-session-error-must-produce-either` applies here:** this learning records a clear error (plan precondition drift caught at /work Phase 0). A learning file alone suffices — no AGENTS.md rule needed, because the existing `/work` Phase 1 item already covers the general case ("Plan-quoted numbers are preconditions to verify"). The specific case (AGENTS.md byte threshold under the new sidecar split) is captured here for future plans that touch AGENTS-md tier promotion.

## Sharp Edges

- **AGENTS.docs.md is the new home of `cq-agents-md-why-single-line`.** Plans that grep `AGENTS.md` for this rule's body will not find it post-split. The pointer-index `AGENTS.md` shows `[id: cq-agents-md-why-single-line] → docs-only`; the body lives in `AGENTS.docs.md`. Skills and agents that quote the rule must point at `AGENTS.docs.md`, not the index.

- **The always-loaded payload is currently 21,949 bytes** (PR #3559 merge time). Adding any AGENTS.core.md rule of size > 51 bytes will push past the 22k critical threshold. Operators should retire stale rules via `scripts/retired-rule-ids.txt` before promoting new ones; the compound-promotion-loop's Phase 2.2 prompt enforces this gate at clustering time and the workflow enforces it post-apply.

- **Promotion to AGENTS.core.md is the only AGENTS-md tier eligible for the compound-promotion-loop v1.** Promotion to AGENTS.docs.md or AGENTS.rest.md is deferred to v2 because the LLM cannot reliably tell rest-class from docs-class from a single learning cluster.

## Tags

```text
category: best-practices
module: work, plan, agents-md
issue: #2720
pr: #3559
related-pr: #3496
```
