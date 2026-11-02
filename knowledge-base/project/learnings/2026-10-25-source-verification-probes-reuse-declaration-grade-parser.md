# Source-verification probes must route through the repo's declaration-grade HCL parser, not a hand-rolled scanner

**Date:** 2026-10-25 · **Context:** PR #11069 (#11068) — `plugins/soleur/scripts/inngest-alerts-push-probe.ts`

A discoverability probe that greps a `.tf` resource block for an attribute is false-PASS-shaped
by default: `push = true` inside a comment, a heredoc body, a nested `lifecycle {}`/`locals {}`
block, or a quoted string all satisfy a regex over the raw block. Three review seats converged
on the same fix: export the shared parser internals (`codeView`, `resourceBlocks`,
`topLevelAttributes` from `plugins/soleur/lib/heartbeat-live-reconcile.ts`) and assert on the
TOP-LEVEL attribute only.

Companion pins that proved load-bearing: a test arm that only checks "revert → missing" does
not pin TARGETS breadth or decoy refusal — mutate a *different* target AND plant nested/heredoc
decoys in the same synthesized root. The `expect(body).not.toBe(before)` land-guard keeps the
mutation honest.
