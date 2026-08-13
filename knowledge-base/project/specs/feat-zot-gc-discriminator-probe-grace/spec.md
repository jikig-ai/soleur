---
feature: zot-gc-discriminator-probe-grace
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [7456, 7455, 7341]
plan: knowledge-base/project/plans/2026-08-12-feat-zot-gc-attribution-discriminator-plan.md
brainstorm: knowledge-base/project/brainstorms/2026-08-12-zot-gc-discriminator-probe-grace-brainstorm.md
status: revised
created: 2026-08-12
revised: 2026-08-13
---

# Spec — Registry log-channel follow-ups

**[Revised 2026-08-13 after a five-agent plan-review panel.]** The original spec described a
standalone gc-attribution probe with a per-repo stall verdict. The panel established that design was
uninvokable and that its verdict had three independent false-positive paths; see the plan's
`## Plan Review Findings`. This spec now describes what is actually being built.

## Problem Statement

The registry zot container-log channel went live 2026-08-12 20:58Z (probe PASS). That unblocked
#7456 item (b) — make the *next* store-growth cycle attributable. Delivery also exposed three
defects in the surrounding probes:

1. The `delivered_but_silent` arm emits *"THIS IS THE STATE THAT MEANS ACT, NOT WAIT"* against a
   host that has simply never run its first `4-59/5` shipper tick. Observed: false escalate at
   20:56:32Z, unassisted PASS at 20:58:45Z.
2. The `not_delivered` arm still instructs the operator to wait for step-6 of the "open zot-pin
   ordered path" (#7287) — closed 2026-08-12T20:39Z, with the host already replaced.
3. `run_query()` swallows `betterstack-query.sh` rc=3, the likeliest first-run failure.

Separately, #7341's `FAIL)` arm names two growth hypotheses and no tool, so a firing detector leaves
the operator with nothing to run.

## Goals

- G1 — When the disk-fill detector fires, the operator receives an attribution **lead** in the same
  comment, without that lead being able to affect the verdict.
- G2 — The delivery probe stops escalating during the structurally expected pre-first-tick window,
  without weakening the genuine escalation.
- G3 — The probe's operator-facing text describes reality after the 2026-08-12 host replace.

## Non-Goals

- NG1 — Rate-cap retune (#7456 item c): needs measured volume; a successor issue carries the trigger.
- NG2 — Root-filesystem LUKS (#7456 item a): dated 2027-02-11, neither trigger fired.
- NG3 — Flipping ADR-184 `adopting → accepted`: that is #7455's deliverable, and this PR must not
  touch that ADR's frontmatter or `## Status flip condition`.
- NG4 — A standalone attribution probe, a new test suite, a shared parse helper, or a new CI
  vehicle. Each was cut by the panel.
- NG5 — Closing #7456. This PR uses `Refs`, since items (a) and (c) remain.

## Functional Requirements

- **FR1** — `zot-fill-rate-7341.sh`'s `FAIL)` arm prints an attribution lead: gc starts, completions,
  repositories with unmatched starts, `PatchBlobUpload` count, and the `SOLEUR_ZOT_LOG_DROPPED`
  count for the same window.
- **FR2** — The lead is **informational**. It runs after the verdict is decided and cannot change
  the exit code under any input, including query failure, hang, or garbage.
- **FR3** — The drop count is printed **alongside** any unmatched start, because shipper-side row
  loss is byte-indistinguishable from a stall. The lead names a confound rather than asserting a
  cause.
- **FR4** — Row matching anchors on `SOLEUR_ZOT_LOG shipper=zot-log-shipper host=<host>` **including
  the trailing space**, and extracts from the parsed `message` field — never the whole line — so a
  header-borne `executing gc` cannot inject a repository.
- **FR5** — The `delivered_but_silent` arm softens its ACT-NOT-WAIT framing when
  `log_shipper_last_ok_age_s` is the **literal** `-1`. No new verdict name, no exit-code change, no
  clock read.
- **FR6** — Softening keys on the literal `-1`, never on absence: C3b's `control_row_predelivery`
  fixture carries no `log_shipper_*` fields and must keep asserting `delivered_but_silent`.
- **FR7** — The `not_delivered` arm and the file header no longer reference an "open" ordered path
  or step-6; they describe the delivered state and the remaining first-tick wait.
- **FR8** — `run_query()` surfaces `betterstack-query.sh` rc=3, bounded to 600 bytes.

## Technical Requirements

- **TR1** — No new files. Tests extend `tests/scripts/test-zot-log-channel-probe.sh` (497 lines,
  registered at `scripts/test-all.sh:1053`) and `scripts/followthroughs/zot-fill-rate-7341.test.sh`
  (registered at `:849`). `scripts/test-all.sh:1042` states *"ONLY this fixture suite belongs in
  this file."*
- **TR2** — Failing cases are written before the edits (`cq-write-failing-tests-before`).
- **TR3** — Assertion floors raised in both suites to match the added cases; an unraised floor makes
  the additions invisible to the anti-vacuity gate.
- **TR4** — All probe output reaching a public issue comment is bounded.
- **TR5** — No change to `apps/web-platform/infra/cloud-init-registry.yml`. Any edit there costs a
  destructive replace of the fleet's sole image-pull path.
- **TR6** — ADR-184 edits are confined to `## Consequences`; frontmatter `status:` and
  `## Status flip condition` stay byte-identical to `origin/main` (#7455 concurrency guard).

## Measured Facts (basis for FR1/FR4)

Queried live 2026-08-12, not derived from config:

| Class | Carries repository? |
|---|---|
| `executing gc of orphaned blobs for /var/lib/zot/<owner>/<repo>` | yes |
| `gc successfully completed for /var/lib/zot/<owner>/<repo>` | yes |
| `garbage collected blobs` | **no — bare** |
| `PatchBlobUpload` | 0 rows in 3h |

The shipped payload is **comma-separated `key:value` with unescaped colons inside values** —
`sanitize()` (`cloud-init-registry.yml:839`) strips only `"` and `\`. It is not JSON and it is not
safely split on `:`.

## Acceptance Criteria

See the plan's `## Acceptance Criteria` (AC1–AC14). Summary: the lead cannot change any exit code;
the drop count is printed beside unmatched starts; a header-borne `executing gc` injects no
repository; C3b is preserved; the stale arm is corrected; rc=3 is surfaced bounded; no new test file
or registration; both suites green with raised floors; ADR-184's flip-condition section untouched.

## Deferred

- (a) root-fs LUKS — 2027-02-11 or on either recorded trigger.
- (c) rate-cap retune — successor issue carries the drop-count query and a date.
- Standing detection after #7341 closes — successor issue.
- Two false `zotRegistry` claims in `model.c4` — successor issue (whole-file-count ACs make that
  file's edits regression-prone).
