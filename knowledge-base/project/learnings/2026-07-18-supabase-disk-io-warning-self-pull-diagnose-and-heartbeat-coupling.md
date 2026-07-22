---
title: Supabase Disk-IO warning → self-pull diagnosis, and a heartbeat backoff is a coupled contract
date: 2026-07-18
category: performance-issues
module: apps/web-platform/server (concurrency), supabase/migrations
tags: [supabase, disk-io, wal, write-amplification, heartbeat, rls, concurrency-slot]
issue: null
pr: null
---

## Problem

An operator forwarded a Supabase "Disk IO Budget depleting" email for the prod project. The reflex
is to either upgrade the compute tier (money) or start guessing at slow queries. Both are wrong until
you know whether the pressure is **read IO** (missing index / seq scan) or **write IO** (WAL +
checkpoints) — the fixes are disjoint.

## Solution

**1. Self-pull the signal, never eyeball a dashboard (`hr-no-dashboard-eyeball-pull-data-yourself`).**
The project already had the tooling: `disk_io_pressure_signal()` RPC (migrations 095/114) callable over
PostgREST with the Doppler-held service-role key, plus the Management API `/database/query` and
`/advisors/performance`. The signal `cache_hit_pct=100 · max_wal_pct=15` immediately localized it to
**diffuse write IO** (not reads, not one runaway statement). That single pull turned an open-ended
"the DB is slow" into a scoped write-amplification fix and made the operator's optimize-vs-upgrade
decision concrete (they kept the Micro tier).

**2. Three disjoint write-IO levers, in ascending risk:** drop unused secondary indexes (pure
write-amplification, safest); wrap `auth.uid()` in hot RLS policies as `(select auth.uid())` (a
CPU/InitPlan win, NOT WAL — frame it honestly); back off periodic heartbeat cadences (the actual WAL
lever, highest risk). Verify the index-drop down file codepoint-exact against **live**
`pg_indexes.indexdef`, and source RLS wraps from **live `pg_policies`** (policies get redefined after
their original migration — a stale source silently drops a cross-tenant conjunct).

## Key Insight

**A heartbeat-interval backoff is a coupled contract, and the durable fix is structural de-duplication,
not a drift-guard.** Doubling a heartbeat interval (30s→60s) to halve its WAL is only safe if EVERY
matching staleness/reaper threshold rises in lockstep — and those thresholds are almost always
duplicated across layers (multiple TS consumers + several SQL objects). The historical failure mode is
sibling-threshold drift silently false-reaping a live session. Collapsing the duplicated TS thresholds
into **one exported symbol** (`SLOT_STALENESS_THRESHOLD_SECONDS`) makes drift structurally impossible
for the TS side; the SQL side (which must replicate the literal) is then tied back by a single
grep-based drift-guard + a behavioural invariant test on the live symbols. "De-dupe > assert-equal."

**Corollary — a liveness-based reap must gate on agent-loop liveness, not socket focus.** Raising a
staleness threshold widens a cap-hit self-lockout window; the immediate-reclaim mitigation is to reap
slots with no *live loop* on this instance. But "no focused socket" ≠ "no live loop" — a user's socket
tracks one focused conversation while background loops persist across crashes in separate registries.
Gate the reap on the loop registries (cc + legacy), never on socket focus, or you kill the live loop
the whole change was meant to protect (ADR-124, CTO ruling).

## Session Errors

- **AC2 `CONCURRENTLY`-in-comment false-match.** Migration 132's explanatory comments contained the
  literal `CONCURRENTLY`, tripping the AC's `grep -c CONCURRENTLY == 0`. Recovery: reword comments to
  drop the bare token. **Prevention:** already `cq-assert-anchor-not-bare-token` — a "must not contain
  X" assertion collides with documenting X in a comment; reword the comment, don't loosen the grep.
- **Full-suite exit gate caught 10 failures the touched-file loop missed.** Adding two exports to a
  shared module broke 6 test files that wholesale-mock it (accessing an undefined mocked binding
  throws). Recovery: re-export the new consts in every wholesale mock. **Prevention:** already
  documented (wholesale-mock-drops-named-exports); the lesson is that the Phase-2 full-suite exit gate
  is what surfaces it — do not skip it. Working as designed.
- **tsc ×2 on a `vi.fn(() => false)` mock taking a 1-arg `mockImplementation` (TS2345).** Recovery:
  type the mock's param non-optional. **Prevention:** already documented (vitest-zero-arg-mock); give a
  controllable mock its real arg signature up front.
- **Edit "string not found" ×2** from slightly-off remembered comment text. One-off. **Prevention:**
  re-read the exact bytes before an Edit on prose you didn't just write.
