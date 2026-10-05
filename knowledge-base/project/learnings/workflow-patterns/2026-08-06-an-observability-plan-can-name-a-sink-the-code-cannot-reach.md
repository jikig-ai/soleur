---
date: 2026-08-06
issue: "#7332"
pr: 7336
category: workflow-patterns
tags: [observability, plan-preconditions, consent, layer-citation, cto-routing]
---

# An observability plan can name a sink the code cannot reach

## What the plan specified

`## Observability` declared a `SOLEUR_KB_SYNC_PRODUCERS` liveness marker with
`alert_target: Better Stack (SOLEUR_* marker stream)` and a `discoverability_test`
that queried it via `betterstack-query.sh`. The plan flagged it honestly as
unproven and made verification a Phase 0 blocker — which is the only reason this
was caught before implementation rather than after.

## What measurement showed

The ingest path **exists and is fully citable**:

```
in-sandbox Bash stdout (SOLEUR_* line)
  → apps/web-platform/server/git-lock-marker-telemetry.ts   PostToolUse(Bash) hook, MARKER_RE allowlist
  → registered at agent-runner-query-options.ts             createGitLockMarkerHook
  → log.warn / log.error (pino, level ≥ 40)
  → container stdout → Docker journald driver
  → infra/vector.toml [sources.app_container_journald] → [transforms.app_container_warn_filter]
  → [sinks.betterstack] → scripts/betterstack-query.sh --grep
```

And it is **unreachable from this PR**, for two independent reasons:

1. `MARKER_RE` is an **exact-sentinel allowlist**, not a prefix match. A new
   sentinel is dropped at the extractor.
2. The hook is registered **only on the hosted path**. `.claude/settings.json`
   registers PostToolUse matchers for `Write|Edit`, `Task`,
   `mcp__pencil__open_document`, `Skill` — **no `Bash`**. The self-hosted CLI, the
   only surface this PR ships a producer for, is unmirrored by construction.

The second reason is the one that matters, and it is not a gap to be closed: a
*customer's* machine has no route to *Soleur's* Better Stack, and building one
would ship repository-derived metadata to a Soleur vendor — a data-controller
event requiring consent this PR has no mandate for.

## Why the obvious fix was wrong

"Widen `MARKER_RE`" is a one-line change and it fails three ways. It adds a
**permanently-dead allowlist entry** on a surface no producer runs on — the exact
anti-pattern `vector.toml` already documents for `inngest-boot-phone-home` ("a dead
line in an allowlist that is read as an inventory of live channels"). It does not
help the CLI half at all. And it edits a module whose `WEDGE_RE` pages real git
wedges, from inside a plugin-scoped PR.

## The structural gap underneath

`observability-coverage-reviewer` enumerated **six layers, all server/host-side**.
Its Step-2 matcher accepts a citation only if it contains one of `sentry-correlation`,
`pino`, `vector`, `host_metrics`, `release`, `Sentry monitor`, `inngest-heartbeat`,
`webhook response`, `workflow run log`, `::error::`.

So for any `plugins/`-only feature — code that runs on a customer's machine —
**writing an honest layer citation was impossible**, and `hr-observability-layer-citation`
was unsatisfiable by construction. Any such plan takes a P1 for a gap it cannot
close. That is a capability gap in the reviewer, not a defect in the plan.

Added **layer 7 (`cli-stdout-artifact`)**: the synchronous stdout marker *plus* a
deterministic artifact committed to the customer's own repository, because stdout
alone does not survive the session. Accepted only when the producers are
plugin-side, and only when a durable artifact accompanies the marker.

Adding the layer also **falsified three existing clauses** that had to be swept in
the same edit: a "five observability layers" count, "not a **seventh** observability
layer" describing the read-path CLIs, and "The six layers above are all
server/host-side". This is the dangling-clause class — deleting or adding a member
of an enumeration silently re-points every clause that quantified over it.

## Rules

1. **A plan's `alert_target` is a claim to verify, not a fact.** Trace the whole
   chain to the sink before writing code against it. The chain here was six hops and
   broke at hop one.
2. **"The ingest path exists" and "my code can reach it" are different claims.**
   An allowlist-gated extractor and a surface-specific hook registration each break
   the second while leaving the first true.
3. **Consent is a stricter boundary than reachability, and it binds first.** If
   the fix would route customer-derived data to a vendor, the absence of a path is
   a feature.
4. **When the reviewer's own vocabulary cannot express an honest answer, fix the
   vocabulary.** Do not write the nearest-fitting false citation.
5. **Route the fork, do not guess.** The substrate choice (widen the allowlist vs.
   redefine the signal) is an architecture decision with material trade-offs; it
   went to the `cto` agent, which rejected the one-line fix on grounds — dead
   allowlist entry, consent — that were not obvious from the plan.

## What "resolved" looks like

The signal became greppable with no network, no credentials, and no SSH:

```bash
grep -n 'SOLEUR_KB_SYNC_PRODUCERS' knowledge-base/project/kb-coverage.md
```

with a drift guard asserting the stdout marker and the artifact's marker line carry
a **byte-identical field set** (otherwise the discoverability test silently starts
verifying something other than what the run reported), and a negative assertion that
the marker carries **counts only** — keeping the consent claim true in code rather
than only in an ADR.

See also
[[2026-08-06-my-gate-would-have-fired-on-every-input-and-no-unit-test-could-see-it]].
