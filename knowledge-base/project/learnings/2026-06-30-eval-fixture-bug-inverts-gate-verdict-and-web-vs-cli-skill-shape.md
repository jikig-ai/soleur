---
title: An eval-harness fixture bug can INVERT a gate verdict; and the web Concierge emits BARE skill names while the CLI emits FQN
date: 2026-06-30
tags: [eval-harness, gate-verdict, fixture-bug, phase-surface-hint, web-vs-cli, skill-tool, tool_input, model-disaggregation]
category: best-practices
issue: 5772
prs: [5792, 5794]
---

# An eval-harness fixture bug can invert a gate verdict; web Skill shape ≠ CLI Skill shape

Two reusable lessons surfaced shipping #5772 (web parity for the L3 phase-surface hint).

## 1. Before trusting an eval's headline delta, look for a fixture bug AND disaggregate by model

`/soleur:go 5772` was gated on #5768's eval evidence ("does the CLI phase hint
measurably reduce wrong-tool selection?"). The first run of the shipped
`eval-harness` `tool-selection` target reported a **+13pt pooled win that
INVERTED on the frontier models** (Opus/Sonnet −20pts, Haiku +80pts) — which
would have killed the web port (the web Concierge runs Sonnet).

That verdict was an **artifact of two fixture bugs**, not a real signal:

- **Enum/prompt vocabulary mismatch.** The skill-arm prompt foregrounded real
  skills (`plan-review`, `test-fix-loop`, …) that were **absent from the closed
  answer enum**, so a model picking a legitimately-foregrounded skill was
  double-penalized (wrong + non-enum gate fail). One task scored 0 by construction.
- **Pooled delta hid a per-model split.** The headline "+13pts" was entirely a
  Haiku rescue (baseline 0.0 → 0.8) driven by the enum bug; it said nothing about
  the model the web actually runs.

After fixing the fixtures (18-token vocab parity + 5→15-task corpus, PR #5792)
the verdict **flipped**: Sonnet +6.7pts (the model web runs), Opus ~neutral.

**Rule:** an eval that gates a build decision is itself code that can be wrong.
Before acting on a headline delta: (a) check the GATE-assert failure count and
*what* failed (non-enum output ≠ wrong-skill — a vocab mismatch inflates the
apparent uplift); (b) **disaggregate by model** — a pooled win is often one
model's catastrophe, and the model that matters is the one the target surface
runs, not the pool. The fixture-hardening was the highest-leverage work in the
whole issue; the "adverse" first verdict would have wrongly deferred a real win.

## 2. The web Concierge emits BARE skill names (`work`); the CLI emits FQN (`soleur:work`)

The CLI phase-surface hook (`.claude/hooks/phase-surface-hint.sh`) keys its map
on **FQN** skill names because the CLI Skill tool reports `tool_input.skill =
"soleur:work"`. The naive JS port reused the FQN-keyed map directly.

But the web Concierge's own production sticky-workflow detection
(`soleur-go-runner.ts:559` `KNOWN_WORKFLOWS`, the system prompt, and the web test
fixtures) all use **bare** names (`work`, `brainstorm`) with no prefix-stripping —
i.e. on the web path `tool_input.skill` is **bare**. An FQN-keyed lookup would
have **missed every real web call → silent no-op → the feature ships dead**, and
synthetic-FQN unit tests would not have caught it (they fed `"soleur:work"`).

**Rule:** when porting a hook/parser/gate from one runtime (CLI) to another
(web SDK) that reads the *same* model-controlled field, **verify the actual
runtime value shape on the TARGET surface** — grep the target's own consumers of
that field, don't assume parity with the source. Fix here: normalize bare→FQN at
lookup (`skill.includes(":") ? skill : "soleur:" + skill`) and make the **bare
shape the primary test case**. Caught by spec-flow-analyzer at plan-review (a P0
that survived two prior review passes because they reasoned about the CLI shape).

## Bonus: a `.c4` source edit needs the compiled `model.likec4.json` regenerated

Editing `knowledge-base/engineering/architecture/diagrams/model.c4` without running
`scripts/regenerate-c4-model.sh` leaves the compiled `model.likec4.json` stale;
`c4-model-freshness.test.sh` (test-scripts CI shard, not the web vitest shard)
byte-compares them and fails. The web-side `c4-render`/`c4-code-syntax` tests pass
regardless — so a green local web run is NOT proof the C4 change is CI-clean.
Caught by architecture-strategist at PR review.
