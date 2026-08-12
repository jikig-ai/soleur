---
feature: zot-gc-discriminator-probe-grace
lane: cross-domain
brand_survival_threshold: single-user incident
closes: 7456
refs: [7455, 7341, 7440]
brainstorm: knowledge-base/project/brainstorms/2026-08-12-zot-gc-discriminator-probe-grace-brainstorm.md
status: draft
created: 2026-08-12
---

# Spec — Growth-attribution discriminator + delivery-probe first-tick grace

## Problem Statement

The registry zot container-log channel went live on 2026-08-12 at 20:58Z (probe PASS,
`envelope=20 control=7 gc_start=1 gc_done=1 gc_blobs=1 patch_upload=0 dropped_rows=1`). That
unblocks the growth-attribution work #7456 tracks as item (b), which until now could not be built or
validated against zero rows.

Delivery also exposed a defect in the delivery probe itself. The shipper is a `4-59/5` cron
one-shot, so a freshly replaced host has no shipper state until its first tick. The probe's
escalation branch keys only on `boot_marker` present (72h window) plus zero envelope rows in a 30m
window, with **no first-tick grace** — so it emits `delivered_but_silent` ("THIS IS THE STATE THAT
MEANS ACT, NOT WAIT") against a host that is simply too young. Observed directly: false escalate at
20:56:32, unassisted PASS at 20:58:45.

Separately, #7456's opening line cites ADR-179 for the shipper. ADR-179 is
`bare-plugin-root-anchor-for-customer-facing-executables`; the shipper ADR is ADR-184.

## Goals

- G1 — Make the *next* registry disk-growth cycle attributable from telemetry.
- G2 — Stop the delivery probe from emitting an escalate-immediately verdict during the structurally
  expected pre-first-tick window.
- G3 — Leave (c) decidable later on honest data, with the boot-burst confound recorded.

## Non-Goals

- NG1 — Retuning the 5,000/day cap. Needs measured volume and another provisioning event.
- NG2 — Root-filesystem LUKS (item (a)); exception runs to 2027-02-11, neither trigger fired.
- NG3 — Flipping ADR-184 `adopting → accepted`; that is #7455's deliverable.
- NG4 — Any further `registry-host-replace` dispatch.
- NG5 — Recovering #7341's original attribution target; the recut emptied the store
  (`pcent` 100 → 8, 08-04 → 08-10) before it was explained. Forward-looking only.

## Functional Requirements

- **FR1** — A new follow-through probe computes the gc start/complete ratio from the shipped
  envelope rows: denominator `executing gc`; completion evidence `gc successfully completed` and
  `garbage collected blobs`; independent orphan evidence `PatchBlobUpload`.
- **FR2** — The probe's observation window spans **several gc periods** (gc is hourly; window ≥ 6h)
  and keeps the **archive arm** on. A window shorter than the gc period makes any start near the
  window edge appear completion-less, manufacturing the stall signal the probe exists to detect.
- **FR3** — Start→completion pairing has explicit **boundary handling**: a start whose completion
  would fall outside the window must not count as a stall.
- **FR4** — Row matching uses the **positive**, host-isolated envelope prefix
  `SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry`. The negative form is forbidden
  (ADR-184 rejects it as fail-open).
- **FR5** — Greps carry **no quote and no colon** (ClickHouse stores `raw` double-encoded); all
  judgements are made on the decoded object.
- **FR6** — Exit contract mirrors the sibling probe: `0` PASS, `2` TRANSIENT with a distinct
  `reason=` per arm, `1` reserved for a genuine regression. `${VAR:?msg}` is banned.
- **FR7** — `zot-log-channel-7440.sh` gains a verdict `reason=awaiting_first_tick`, distinct from
  `delivered_but_silent` and still exit `2`, when delivery evidence is present but the shipper has
  provably never completed a tick within the grace window.
- **FR8** — The grace window is derived from the shipper's real cadence (`4-59/5`, 5-minute tick),
  not a magic constant, and the derivation is stated in the source.
- **FR9** — #7456's ADR-179 citation is corrected to ADR-184.

## Technical Requirements

- **TR1** — Tests are synthesized fixtures with **measured shapes**
  (`cq-test-fixtures-synthesized-only`), following `apps/web-platform/infra/zot-log-shipper.test.sh`
  (961 lines, wired into `.github/workflows/infra-validation.yml`).
- **TR2** — Fixture coverage must include the two confounds this spec exists to prevent: a
  window-boundary start (must **not** read as a stall) and a boot-burst drop (must **not** read as
  cap pressure).
- **TR3** — The first-tick grace must not weaken the genuine `delivered_but_silent` arm: a host past
  the grace window with zero envelope rows must still escalate.
- **TR4** — No change to `cloud-init-registry.yml`. Any edit there costs a provisioning event on the
  fleet's sole image-pull path.
- **TR5** — Reuse the existing decode/query helpers rather than forking them; do **not** copy
  `--no-archive` from the delivery probe (opposite window class).

## Acceptance Criteria

- **AC1** — Against synthesized fixtures, the discriminator reports a stalled gc (start without
  completion) and a healthy gc (paired) with distinct verdicts.
- **AC2** — A start within one gc period of the window edge does not report as a stall.
- **AC3** — Replaying the observed 20:56 state through the patched delivery probe yields
  `awaiting_first_tick`, not `delivered_but_silent`.
- **AC4** — Replaying a post-grace silent host still yields `delivered_but_silent`.
- **AC5** — `bash scripts/followthroughs/zot-log-channel-7440.sh` against live production still
  returns PASS (channel is live as of 20:58Z 2026-08-12).
- **AC6** — CI green, including `infra-validation.yml` and the followthrough `${VAR:?}` ban lint.

## Deferred

- (a) root-fs LUKS — re-evaluate 2027-02-11 or on either recorded trigger.
- (c) rate-cap retune — dated soak re-check; criterion unchanged ("sustained ordinary-row loss"),
  with the boot-burst confound now documented so the first post-replace number is not misread.
