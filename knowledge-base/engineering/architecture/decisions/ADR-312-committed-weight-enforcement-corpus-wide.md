---
adr: 312
title: Committed-weight enforcement is corpus-wide; duration weight enters the tree only through a gated generator
status: active
date: 2026-10-31
issue: 11662
---

# ADR-312: Committed-weight enforcement is corpus-wide; duration weight enters the tree only through a gated generator

## Context

`scripts/test-all.sh` regressed to ~3 h wall-clock (704 registrations, ~121 min
serial committed weight, 2026-10-30) with no gate on duration weight entering
the tree: `regenerate-shard-manifest.py` refused only shape errors, and the
committed-weight caps covered only `ALWAYS_ON_SUITES` (ADR-242's fast-tier
budget). This ADR extends ADR-242's weight-cap precedent corpus-wide and gives
ADR-240's generator-owns-the-ledger model a refusal path.

## Decision

Four committed-weight guards, all value-pinned and never wall-clock (a
wall-clock budget flakes; a committed-weight budget cannot):

1. **G1 — regen drift gate** (`regenerate-shard-manifest.py`): `--write` refuses
   (exit 2) when any `src=measured` row grows >1.5× AND >10 s, or total measured
   weight grows >10% vs the merge-base blob. `--allow-growth` is the recorded
   escape — stamped `# growth-acked=<digest>` scoped to the acked violation set.
   Count growth is reported, never gated; floor rows are excluded from the
   per-suite comparison but count toward total growth.
2. **G2 — corpus weight budget** (`test-all-corpus-weight-budget.test.sh`):
   every committed weight ≤ 600 s or exempted in
   `suite-weight-exemptions.tsv` (`label<TAB>cap_ms<TAB>reason`, `#NNN`
   required, cap ≤ ~1.3× weight, minimal ledger, stale-key parity). Unmeasured
   registrations red — unmeasured is not exempt.
3. **G3 — always-on ledger + non-live ceiling** (`always-on-ledger.test.sh`):
   two-directional keys-parity against `always-on-justifications.tsv`, plus
   `count(ALWAYS_ON \ live_named) ≤ NON_LIVE_CAP=95`. Distinct from f1's
   pin-vs-list band (`_MIN_ALWAYS_ON_DECLARED`, `count-5 ≤ floor ≤ count`):
   f1 catches the pinned floor rotting; the cap catches organic accretion.
   Escape = cap ack-edit, never a floor bump.
4. **G4 — dead-registration census** (`lint-orphan-test-suites.sh` surface 7):
   every `SUITE_COMMAND`'s resolved argv target must exist — env-prefix
   stripping, `python3 -m` module→path, interpreter-class directory operands
   allowed, unknown argv0 reds. Covers the test-all stream and the infra
   runner's `--enumerate` paths.

## Consequences

- Duration weight can only regrow through the sanctioned regeneration flow
  with an explicit ack (per-suite factor, total pct) or a reviewed ledger
  edit (per-suite cap). Hand-edited weights remain an accepted v1 hole —
  G1 rate-limits the sanctioned flow, G2's absolute cap is the level guard.
- No absolute total-corpus cap in v1: legitimate suite accretion is
  intentionally unbounded (R10).
- bun/webplat registrations carry no duration table — out of scope v1.
- Legal-control suites (FR5) are exempt from census removal/demotion.
