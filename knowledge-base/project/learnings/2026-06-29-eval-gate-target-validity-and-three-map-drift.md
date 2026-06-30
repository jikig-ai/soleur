---
title: An eval-harness gate target is only valid if its prose IS the LLM-applied rule; and the additive recipe has three hardcoded maps
date: 2026-06-29
category: best-practices
tags: [eval-harness, classifier-gate, ADR-069, projection-honesty, hardcoded-map-drift, plan-review, dormant-gate]
module: eval-harness
related-issues: [#5704, #5701, #5702]
related-learnings:
  - knowledge-base/project/learnings/2026-06-29-multi-label-classifier-gateable-core-is-its-single-token-output-slice.md
related-plan: knowledge-base/project/plans/2026-06-29-feat-expand-gated-skill-catalog-plan.md
governing-adr: ADR-069-validation-gated-classifier-skill-edits
---

# Learning: eval-harness gate target validity + the three-map drift

Two distinct findings from plan-review of #5704 (expanding the ADR-069 validation gate to new
classifier surfaces). Both were caught by a 3-agent plan-review (spec-flow + kieran + simplicity)
after passing brainstorm-time assessment — i.e. they survived a CTO "best candidate" call and only
fell to grepping the actual installed code.

## Finding 1 — A surface is a valid gate target only if its prose IS the LLM-applied decision rule

The eval-harness gate projects a classifier's **prose block** into an LLM skill-arm prompt and measures
classification accuracy. So a surface is only a valid target if the prose between the sentinels is the
rule the model reasons from. Two failure shapes:

- **Deterministic scanner masquerading as a classifier.** `skill-security-scan` *looks* like a
  3-class classifier (`LOW-RISK | REVIEW | HIGH-RISK`), but `run-scan.sh` computes the verdict with
  `jq` max-severity aggregation over external YAML/regex rule files — no LLM. Its §Verdict semantics
  prose merely *documents* a deterministic pipeline; projecting it hands the model an aggregation
  function with zero detection criteria, measuring the LLM's ability to reconstruct rules it was never
  given. Editing that prose doesn't even change behavior (the rules live in the YAML), so the gate
  guards nothing.
- **Prose that is documentation, not the rule.** Same test: if the behavior is determined by code/
  config the prose only describes, the prose is not gateable.

**Litmus before adopting a gate target:** grep the surface's *executor*. If a script/config computes
the output (`grep -nE "verdict|jq|aggregat" <skill>/scripts/*.sh`), it's deterministic → reject. If
the output is an LLM reasoning from the prose criteria (e.g. brainstorm lane-inference table, incident
Phase 1 threshold criteria, /go routing table), it's valid.

## Finding 2 — The "additive recipe" has THREE hardcoded per-target maps; a miss ships the gate dormant

The README sells adding a target as additive data. It is not. Three hardcoded per-target maps must each
gain an entry, in two different `.cjs` files plus a test:

1. `gen-skill-prompt.cjs` `TARGET_CONFIG` — the per-target render wrapper + `enumPath`.
2. `eval-gate.cjs` `TARGET_RESOURCES` — `{tasks, enumPath}`; **this is the gate itself**.
3. `extract-block.test.sh` round-trip loop — hardcoded `for target in …` + a filename ternary.

The trap: `eval-gate.cjs --check <source>` reports `gated:true` from the **registry alone**, but the
real gate (`--target`) resolves `TARGET_RESOURCES[target]` and `die()`s fail-closed when it's absent.
So omitting map #2 ships a surface that *looks* gated (`--check` green, registry row present, config
validates, round-trip passes) while the gate **dies on first real use** — a dormant gate with every AC
green. The brainstorm/spec "no new code" claim and even the first plan draft both stopped at map #1.

**Fixes that close the class:**
- An AC that exercises the **gate path**, not the measurement path: `node scripts/eval-gate.cjs
  --dry-run --target <t>` (no API) — forces `TARGET_RESOURCES` to exist.
- A **registry-coverage consistency test**: every `gated-skills.json` target ∈ `keys(TARGET_CONFIG)`
  ∩ `keys(TARGET_RESOURCES)`. Makes a missed map fail CI permanently.
- **Data-drive** the round-trip test loop from the registry (`target` + `projected_prompt_path`) so
  map #3 disappears.

## Key Insight

When extending a registry-driven mechanism, the registry is rarely the *only* per-item coupling — grep
for every `const X = { "<existing-item>": ... }` map keyed on the same id across ALL the mechanism's
files (not just the one the README names), and assert membership in each via a consistency test.
A `--check`-style "is it registered?" probe is a proxy; the load-bearing AC must exercise the actual
operative path (here, the gate). And before gating a "classifier," confirm an LLM — not a script —
produces its label.

## Session Errors

1. **`Monitor` invoked without its deferred-tool schema loaded** (`InputValidationError` on a `timeout`
   param). Recovery: background agents auto-notify on completion, so the poll was unnecessary.
   Prevention: don't poll harness-tracked agents; `ToolSearch select:<name>` before calling a deferred tool.

## Tags
category: best-practices
module: eval-harness
