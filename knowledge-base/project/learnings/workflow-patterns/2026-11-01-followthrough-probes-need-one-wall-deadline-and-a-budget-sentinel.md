---
title: "Follow-through probes need ONE wall deadline and a budget sentinel — a phase budget that can be cut must report a cut, never a failure"
date: 2026-11-01
pr: "#11767"
issue: ["#10865", "#9323"]
tags: [followthrough, soak-probe, deadline, sweeper, budget]
---

# Follow-through probes: one wall deadline + a budget sentinel

**Pattern.** A probe running under the sweeper's per-probe `timeout -k 10 $FT_PROBE_TIMEOUT` (300 s, #11215) must
reach its own verdict inside the kill. The model that survives: `END = T0 + BUDGET` (~30 s margin), every phase
(listing, parallel read dispatch, serial facts, baseline reads) gating on `SECONDS - T0`, each API read capped at
`min(60, END - SECONDS - 5)`, and a **sentinel return code (46) meaning "deadline spent → budget cut, never a failed
read"** — a deadline-capped read is indistinguishable from a real 60 s stall (both rc 124) without it.

**Traps the review panel found in the first cut at this:**

- Recompute the per-read cap *inside* the retry loop — a stale cap lets a retried read run ~57 s past END and
  reintroduces the kill.
- Every `gh_get` caller must map the sentinel — the one missed site (`raw_baseline`) turned a deadline cut into
  CANNOT ESTABLISH.
- `TRUNC` is the steady state (units_read ≤ dispatch cap vs hundreds of readable runs); never gate an unconditional
  criterion on `TRUNC == 0` — gate it on the deadline itself, and print `field=unread` rather than a fabricated value.
- `units_read` counting produced rows vs `readable_n` counting listed runs mixes denominators — derive TRUNC from the
  dispatch basis and prove the read set is a true prefix (a mid-dispatch deadline cut can leave an interior hole that
  hides a defect unit).
- Artifact-priced soak accounting needs the artifact budget sized at `MIN_RUNS × (~11 artifacts/run + 1)` — a 60-cap
  evidences ~5 runs and starves the verdict floor by construction; a cap-truncated run is `evidence_absent`, never a
  deflated sum.
- Dedupe priced rows across ALL of a run's artifacts (`!seen[$1]++` in one awk over the collected TSVs) — a `seen`
  array written but never read prices a duplicated skip row twice.

**Why:** #10865 was CANNOT ESTABLISH every sweep (two-epoch ~480 s budget predating the 300 s cap); #9323's whole-run
billable bar conflated suite growth with the lever's effect (~48.5 suite-min realized skip, drift-immune measure).
Both are classes of "the probe's accounting must survive its own supervision boundary."
