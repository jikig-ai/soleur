---
title: Fail-closed fixes must sweep every writer AND every producer of the value, not the call site under review
date: 2026-10-06
category: workflow-patterns
tags: [workflow-patterns, fail-closed, sentinels, code-review, cost-writer, mutation-sweep]
---

# Learning: a fail-closed fix at one call site leaves the same defect alive on sibling writers and upstream coerces

## Problem

The #9648 plan review found `MODEL_PRICING[model] ?? {zeros}` bills $0 into the WORM
`audit_byok_use` ledger. The B-0 fix made the caller pass `Number.NaN` and taught
`persistTurnCostAwaitable` to refuse the ledger row — correct, complete-looking, green
on a fresh test suite. The PR's own review panel (five independent lenses: security,
user-impact, test-design, pattern-recognition, code-quality) then all found the same
P1: the sibling writer `persistTurnCost` kept the exact fail-open (and on the
*delegation* path books $0 against the grantor's ledger), and the upstream producers
(`msg.total_cost_usd ?? 0` in agent-runner and soleur-go-runner) destroyed the
sentinel before any writer could see it.

## Solution

When the defect class is "value X silently coerced to a safe default at a trust
boundary," the fix surface is a graph, not a site:

1. **Enumerate every writer** of the sink (here: `persistTurnCost` AND
   `persistTurnCostAwaitable` AND the delegation RPC arm inside the sync writer —
   three paths, not two).
2. **Enumerate every producer** of the value upstream (`?? 0`/`?? {zeros}`/`Number.isFinite`
   coerces — grep for the coercing expression, not the symbol). Producers that squash
   the sentinel upstream make the downstream guard unreachable even after it lands.
3. **Give the sentinel a documented contract** on the shared input type
   (`TurnCostInput.totalCostUsd` JSDoc), or the next caller can't discover it.
4. **Test both ends**: writer tests pin "NaN → no ledger row + Sentry op tag +
   `capture_status:"unpriced"`"; a producer-side test pins the sentinel actually
   reaches NaN (`resolveTurnCostUsd` extracted + unit-tested for exactly this).
5. **Check the observability convention exists**: `cost_usd: null` + a real
   `capture_status` member beat `"ok" + 0` — "genuinely free" and "couldn't price"
   must not share a marker shape.

## Evidence

PR #9684 — 10-reviewer panel, 5 lenses independently reported the same asymmetric-fix
P1; the fix-up commit closed it on all three write paths + both producers.

## Prevention

When fixing a fail-open/coercion defect, grep the whole value path — producers
(`??`, `Number.isFinite`, `|| 0` defaults) and every writer — before writing the
first test. A "latent today" reachability argument is not a reason to skip a path:
the arm exists precisely for the next caller.
