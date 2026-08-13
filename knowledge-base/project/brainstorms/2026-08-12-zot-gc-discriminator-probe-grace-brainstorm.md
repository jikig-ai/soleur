# Growth-attribution discriminator + probe first-tick grace (#7456)

**Date:** 2026-08-12
**Issue:** #7456 (post-delivery follow-ups for the registry zot log shipper)
**Branch:** `feat-zot-gc-discriminator-probe-grace`
**PR:** #7513

## What We're Building

Two items, both unblocked by a delivery event that landed **during this session**:

1. **(b) The growth-attribution discriminator** — a gc start/complete ratio plus `PatchBlobUpload`
   counts, read back out of the warehouse, so the *next* registry disk-growth cycle is
   attributable rather than reconstructed.
2. **A first-tick grace guard on `scripts/followthroughs/zot-log-channel-7440.sh`** — the delivery
   probe currently reports its *escalate-immediately* verdict against a host that is merely too
   young to have run a tick.

Plus a one-line citation correction: #7456's opening line cites **ADR-179**
(`bare-plugin-root-anchor-for-customer-facing-executables`). The shipper ADR is **ADR-184**, which
#7455 cites correctly.

## Why Now — the premise changed mid-session

#7456 and #7455 both state that delivery "rides the step-6 `registry-host-replace` on the ordered
path in **#7287**." That framing was stale before this session started, and then resolved during it:

| Time (UTC, 2026-08-12) | Event |
|---|---|
| 20:39 | **#7287 closed** — COMPLETED, no closing PR. Its closing comment records that the atomic 3-way `registry-luks-recut` replaced the host on 08-10, so *"ordered-path step 6 did not need a separate `registry-host-replace`"* |
| — | #7444 (the shipper) merged 08-12 19:38Z — **two days after** that host was born, so it was committed and inert. The closing comment concedes this: *"It did not make this window."* |
| 20:52 | A parallel session dispatched `registry_host_replace` (run 31639782781) |
| 20:54 | Run **success** |
| 20:56 | Probe: `delivered_but_silent` — the ACT-NOT-WAIT arm |
| **20:58** | Probe: **PASS** — `envelope=20 control=7 gc_start=1 gc_done=1 gc_blobs=1 patch_upload=0 dropped_rows=1` |

The channel is live. ADR-184's flip condition is "the **first PASS**" of that probe, so
`adopting → accepted` is now earned — landed via **#7455**, not here.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | (b) is a **separate follow-through probe**, not an extension of the delivery probe | Window incompatibility — see D2. The delivery probe is deliberately `--no-archive` on a 30m keyhole; its own header warns *"do not copy flags between the days-old and minutes-old cases."* |
| D2 | The discriminator window must span **several gc periods** (≥ 6h, archive arm on) | `gc` runs hourly. A window shorter than the gc period makes any start near the window edge appear completion-less — **the window manufactures the exact stall signal the probe exists to detect.** The ratio must pair start→completion *within* the window with explicit boundary handling |
| D3 | The delivery probe gains an `awaiting_first_tick` verdict distinct from `delivered_but_silent` | Evidenced this session: false escalate at 20:56, unassisted PASS at 20:58. The cron is `4-59/5`, so between host birth and first tick the escalate arm is structurally wrong |
| D4 | (c) rate-cap retune stays **deferred with a dated soak re-check**, criterion unchanged | Its first datapoint (`dropped_rows=1`) is a **boot burst**, not cap pressure — see below. The existing "sustained ordinary-row loss" criterion correctly excludes it |
| D5 | (a) root-fs LUKS unchanged | Exception runs to 2027-02-11; neither re-evaluation trigger has fired |
| D6 | Fixtures synthesized, shapes measured | `cq-test-fixtures-synthesized-only`, and the sibling suite's own warning that *"synthesized fixtures against a wrong shape are exactly why the existing suite could not have caught this"* |

### The `dropped_rows=1` correction

The first observation after delivery showed one dropped row, which reads as immediate cap pressure.
It is not. There are **two independent 17-per-tick caps** — `CAP_PER_INTERVAL` (ordinary) and
`CAP_EXEMPT_PER_INTERVAL` (the four evidence classes) — and the shipper's own comment records that a
boot produces *"30-60 journald entries against a 17/tick ordinary cap."* The observed shape
(~17 ordinary at cap + 3 exempt = 20 shipped, 1 dropped) is textbook boot burst.

Recording this explicitly because the **first** number anyone sees after a replace looks like the
retune trigger and is not — that misreading is the likely failure mode for (c).

## Design Sketch — (b)

- **Denominator:** `executing gc`. **Numerators:** `gc successfully completed`,
  `garbage collected blobs`. **Independent evidence:** `PatchBlobUpload` (orphaned `.uploads/`).
- All four are already **cap-exempt** in the shipper, so they survive the flood that accompanies
  disk growth — the parser is fully specifiable against the shipped envelope format today.
- Envelope anchor is the **positive**, host-isolated prefix
  `SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry`. ADR-184 explicitly rejects the
  negative form as fail-open.
- Encoding: ClickHouse stores `raw` double-encoded, so greps carry **no quote and no colon**, and
  every judgement is made on the decoded object. Same constraint as the delivery probe.
- Exit contract mirrors the sibling: `0` PASS / `2` TRANSIENT (each with a distinct `reason=`) /
  `1` reserved for a genuine regression. `${VAR:?msg}` is banned (lint-enforced).

### Open question carried to `/plan`

Wiring target. #7456 says "wire it to whichever criterion **#7341** ends up carrying" — and #7341 is
still OPEN with its original attribution target unrecoverable (the recut emptied the store,
`pcent` 100 → 8 across 08-04 → 08-10). So the discriminator is **forward-looking only**, and whether
it hosts its own tracker or lands on #7341's criterion is a plan-time decision.

## User-Brand Impact

- **Artifact:** the registry-host growth-attribution discriminator + the `zot-log-channel-7440`
  delivery probe's verdict semantics.
- **Vector:** a probe that reports a false *escalate-immediately* — or a stall ratio that is a
  windowing artifact — trains the operator to discount the one channel that reports on the fleet's
  sole container-image pull path. A discounted alarm on that host is a silent outage of every
  deploy.
- **Threshold:** `single-user incident`.

## Non-Goals

- Firing any further `registry-host-replace` (delivery already verified this session).
- Retuning the 5,000/day cap (needs measured volume; another provisioning event).
- Root-filesystem LUKS (dated to 2027-02-11).
- Flipping ADR-184 `adopting → accepted` — that belongs to **#7455**.

## Session Errors

1. I initially read `dropped_rows=1` as possible cap pressure before checking the producer. The
   two-cap structure and the boot-burst comment refuted it. Corrected above.
2. The `delivered_but_silent` verdict at 20:56 was reported before checking the shipper's cron
   cadence (`4-59/5`). Checking the cadence first would have predicted the false escalate rather
   than discovering it — though the discovery is what evidenced D3.

## Domain Assessments

**Assessed:** Engineering (inline). Marketing, Operations, Product, Legal, Sales, Finance, Support —
not applicable (internal observability on an infra host, no user-facing or regulated surface).

Domain leaders were **not** spawned as sub-agents: this session's operating instructions forbid
Agent-tool invocation unless explicitly requested. The engineering assessment was performed inline
against live telemetry and the ADR/producer sources cited throughout.
