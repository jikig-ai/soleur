---
date: 2026-05-15
topic: brainstorm Phase 1.1 — walk migration history (not just grep) before designing a fix for a domain-with-schema issue
related:
  - 2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md
  - 2026-05-11-brainstorm-grep-approach-hook-before-spawning-leaders.md
  - 2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md
issue: 3205
pr: 3853
---

# Brainstorm Phase 1.1 — walk migration history for shipped remediation when the issue's named gap touches DB schema

## Context

Issue #3205 was filed P1-high / deferred-scope-out / CPO-routed: "server-side T&C consent enforcement on OAuth signup path." The body asserted a client-side-only T&C gate (PR #3199) left a server-side hole, and proposed 3 open architectural decisions: where to store consent (table vs column), backfill policy, `/accept-terms` interaction.

The existing prior-art-grep learnings (cited above) would have caught a single-symbol-already-on-main case. They did not catch this one cleanly because the cited symbol (`tcAccepted` React state) was the *client* surface — the issue's whole point was that the server side was missing. Naive grep on `tcAccepted` confirms the client state exists; it does not refute the issue's premise.

What actually refuted the premise was walking the migration directory: `005_add_tc_accepted_at.sql` → `006_restrict_tc_accepted_at_update.sql` → `007_remove_tc_accepted_metadata_trust.sql` → `007_remediate_fabricated_tc_accepted_at.sql` → `008_add_tc_accepted_version.sql`. The presence of a **`*_remediate_fabricated_*` migration** plus a paired **`*_remove_*_trust` migration** is a strong tell that the team already lived through the issue's failure mode and shipped a 4-layer defense (callback gate, middleware gate, WS handshake gate, GRANT lockdown).

## What to do

When a brainstorm input cites a gap in a domain with persistent state (DB schema, file-system, config), expand the Phase 1.1 grep into a **migration / schema walk** before spawning domain leaders:

1. List every migration touching the cited symbol family: `find <migrations-dir> -name "*<symbol>*.sql"` or `grep -l "<symbol_root>" <migrations-dir>/*.sql`.
2. Scan filenames for **`remediate`**, **`remediation`**, **`fix`**, **`backfill`**, **`null_out`**, **`remove_*_trust`** — these are tells that an incident was already addressed.
3. Read the prose comments at the TOP of any remediation migration. They are forensic notes (PR refs, GDPR articles, "Bug:" preamble). Quote them when reframing the brainstorm.
4. Pair the migration walk with a grep for any **route handler** + **middleware** + **adjacent transport handler** (WebSocket, GraphQL, gRPC) that consumes the symbol. The team often closes ONE surface and leaves an adjacent one open; the brainstorm's value is finding the missed surface, not redesigning the closed ones.

When the migration walk reveals shipped defense, pivot the brainstorm framing in the Phase 0.5 leader prompts from "design the fix" to "audit residual GDPR Art. 7 / OWASP / domain-specific demonstrability gaps in the shipped implementation." The triad assessment is much more productive on the residual lens.

## Why

For #3205 specifically, the pivot took ~10 minutes of pre-leader investigation and saved spawning a triad against a stale premise (which would have produced an internally-coherent recommendation to design a system that already exists). The triad on the residual lens produced 6 genuinely new findings (R1–R6 in PR #3853 spec) including 3 single-user-incident-class gaps the issue body never mentioned (middleware fail-open, WS mid-session no recheck, CI guardrail).

Generalizing: an issue filed at P1 with a "Proposed Fix" section of architectural options is often a snapshot from one point in time. If the cited domain has schema, a `ls migrations/` walk is the cheapest possible staleness check.

## When NOT to apply

If the brainstorm input is the FIRST capture of a green-field problem (no prior PRs, no migration history, no `*_remediate_*` artifacts), skip this step. The signal it provides is only useful when there is history to inspect.
