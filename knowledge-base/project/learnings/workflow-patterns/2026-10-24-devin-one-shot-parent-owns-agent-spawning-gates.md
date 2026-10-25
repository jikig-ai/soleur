---
title: "Devin one-shot: parent owns every gate that needs an agent spawn; phase subagents are the payload boundary"
date: 2026-10-24
category: workflow-patterns
tags: [devin, one-shot, subagent, technical-ruling-gate, sequential-fallback]
---

# Learning: Devin one-shot phase subagents cannot spawn — parent owns agent-needing gates

## Problem

`soleur:one-shot` on Devin CLI ran its plan phase in a `subagent_general` (the SKILL.md is
~52k chars and the pipeline's token-discipline wants a compaction boundary). The subagent hit
two walls the Claude-Code shape assumes away:

1. Devin `run_subagent` does not nest — the subagent could not run plan's research fan-out,
   the Step 4.5 advisor consult, or the plan-review panel. It substituted inline reads and
   recorded every open technical row as `pending - assumed:` in `decision-challenges.md`.
2. `technical-ruling-gate.sh --branch` then FAILed at parent level on those rows — by design,
   that is the sanctioned state when the Agent tool is absent, but the RESOLUTION (a batched
   `soleur:engineering:cto` spawn) can only happen in the parent: the subagent cannot spawn it.

The same constraint shaped work (fact-checker phase inline) and review (7 seats sequential,
`Reviewed-Coverage: sequential-fallback` trailer via `emit-review-trailer.sh`).

## Solution

Treat each one-shot child whose SKILL.md exceeds ~50 KB (work 356 KB, review 476 KB) as a
subagent-run phase, and keep in the parent the pieces that must spawn agents:

- after plan returns: run `technical-ruling-gate.sh --branch`; on `unruled-technical`, spawn
  ONE batched `soleur:engineering:cto` (`subagent_explore` suffices — it returns rulings, the
  parent writes the `Ruled by CTO agent, <date>:` cells), then re-run the gate to PASS.
- work and review run as `subagent_general` with an explicit return contract; review emits the
  `sequential-fallback` trailer from the parent afterwards
  (`emit-review-trailer.sh --mode sequential-fallback --agents-ran N --agents-expected N`).
- every worktree commit from Devin uses `git -C <worktree-abs> commit` — the hook envelope
  omits `.cwd` and bare `git commit` inside `.worktrees/` is false-denied (#8254).

## Key Insight

On Devin, the subagent boundary is a payload boundary, not just a freshness boundary: the
skills are too large to load inline, AND anything inside a subagent that would spawn another
agent must be hoisted to the parent. The `pending - assumed:` placeholder is the load-bearing
hand-off format — it survives the subagent's exit and is exactly what the parent-level gate
consumes.

## Session Errors

1. Planning subagent: nested agent spawns unavailable — fan-outs ran inline; recorded as
   `pending - assumed:` rows. **Prevention:** none needed — the convention worked; parent
   resolved via one batched CTO spawn.
2. Work subagent: fact-checker and Tier-B reviewer phases ran inline. **Prevention:** same
   class as #1 — expected on Devin until nested spawn exists (#8160-class upstream gap).
3. Review ran sequential-fallback; trailer emitted by parent. **Prevention:** same class.
4. `pip3 install pillow` required — env lacked PIL for the OG card. **Prevention:** one-off;
   plan already prescribed the Pillow path.
5. `gh issue create` refused twice by the filing gate (missing `--milestone`, then a
   `User-Impact:` line that did not match an exit shape). **Prevention:** the gate's own
   message names the three exits (`meta/machinery` label, `User-Impact:` + `Fix-Size:` pair,
   `Mandated-By:` line) — read the refusal before retrying; a machinery finding takes the
   `meta/machinery` label.
6. First word-count `awk` included the JSON-LD block (2,220 vs true 1,896). **Prevention:**
   exclude the whole `<script>…</script>` region, not just the tag line.

## Tags

devin, one-shot, subagent, technical-ruling-gate, sequential-fallback
