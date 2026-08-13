---
feature: prebake-rehearsal-image
issue: 7535
branch: feat-prebake-rehearsal-image-7535
pr: 7540
date: 2026-08-13
lane: cross-domain
brand_survival_threshold: none
brainstorm: knowledge-base/project/brainstorms/2026-08-13-prebake-rehearsal-image-brainstorm.md
plan: knowledge-base/project/plans/2026-08-13-test-remove-rehearsal-apt-dependency-plan.md
follow_up: 7544
status: revised
---

# Spec — stop the rehearsal's apt failures reading as emitter findings (#7535)

> **Revised 2026-08-13 after plan review.** The original spec scoped a locally-built fixture image
> replacing all eight container spins, plus guards. A seven-agent panel measured the value case
> and it did not survive. The image is **cut**; the surviving scope is below. The feature slug and
> branch name still say "prebake" — that is historical, not a live goal.

## Problem Statement

`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` runs eight container spins per
invocation, and nine `apt-get` invocations across them install tools from an external mirror.

The defect is **not** cost. It is **diagnostic ambiguity**: when a mirror starves a container, the
arm fails in a way indistinguishable from a substantive finding about the emitter. #7501's title
records exactly this — *"the rehearsal's R3/R4 arms fail nondeterministically with empty captures,
and read as a substantive emitter finding."* One transient failure produced #7501, #7535, #7544,
PR #7507, a brainstorm and a plan.

A secondary defect: one of the nine invocations installs a package the base image already ships.

## Goals

- **G1** — Delete the redundant `e2fsprogs` install (`:872-873`), which installs an
  already-present package at `Priority: required`.
- **G2** — Make every remaining apt failure name itself, so a starved fixture is never read as an
  emitter finding.

## Non-Goals

- **NG1** — A pre-baked fixture image in any form, published or local. Measured: the repo is
  PUBLIC on standard runners so the saving is **$0**, and Infra Validation is never the critical
  path so it is **0 operator-visible seconds**. It would also introduce a T5 vacuous-green (a
  fixture whose `curl` cannot complete TLS satisfies every T5 assertion with `sha256sum -c` never
  evaluated) and convert eight independent failures into one correlated one.
- **NG2** — `FIXTURE_IMG`/`FIXTURE_PACKAGES` chokepoints and the three guards that depended on
  them. Cut with the image.
- **NG3** — Publishing to GHCR or zot.
- **NG4** — `--network none` at any site — T5's second recorded rationale (`:532-537`) is
  independent of how tools arrive.
- **NG5** — Digest-pinning `ubuntu:24.04` (#7544).
- **NG6** — Changing the assertion floor from `-lt` to equality.
- **NG7** — Retry/backoff outside the R4 site #7507 owns.
- **NG8** — Any other suite in `infra-validation.yml`; any assertion's meaning.

## Functional Requirements

- **FR1** — Delete `apt-get update` / `apt-get install -y -qq e2fsprogs` at `:872-873` and the
  dead `export DEBIAN_FRONTEND=noninteractive` at `:871`.
- **FR2** — Replace them with a comment recording why, including that this narrows R1's
  `e2fsprogs` source from mirror-current to image-current — a behaviour change, not a no-op.
- **FR3** — After #7507 merges, rc-check every remaining `apt-get update`/`install` and route
  failure to #7507's `fixture_fail` with a message naming the site and the cause.

## Technical Requirements

- **TR1** — FR1 ships independently. Verified conflict-free: `e2fsprogs` appears 0 times in
  #7507's diff, whose hunks are at `44-51, 402-409, 1089-1104, 1130-1148, 1149-1156, 1159-1166,
  1445-1453`.
- **TR2** — FR3 is blocked on #7507 merging, and reuses its `fixture_fail` helper rather than
  introducing a parallel idiom.
- **TR3** — No new `_skip` call site. `_skip` exits 0 off-CI (`:37-38`), so routing a failed
  provisioning step through it would silently green a broken run on a laptop — the exact failure
  its own B5 comment (`:25-31`) exists to prevent.
- **TR4** — No new command substitution. `scripts/lint-shell-capture-exit.baseline.txt` carries 7
  grandfathered findings for this file and may only shrink.
- **TR5** — Do not describe `git-data-birth-fs-fingerprint.txt:57` as a version pin. Line 56 marks
  that block `CONTEXT FOR FAILURE MESSAGES ONLY — not asserted`; R1 asserts feature sets (`:82-86`).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — no production code path.
Indirect risk is a rehearsal arm that stops discriminating.

**If this leaks:** not applicable — no data surface, credential or network egress added.

**Brand-survival threshold:** `none`.
**threshold: none, reason:** test-fixture-only change with no production code path, no data
surface and no credential; the diff deletes a redundant install and adds error messages.

Diverges from the brainstorm's `single-user incident`, deliberately: that framing reasoned from
the suite's importance rather than the change's blast radius. Under the reduced scope no arm can
be made vacuous. The cut scope could have been, and warranted the higher threshold.

## Acceptance Criteria

See the plan's `## Acceptance Criteria` (AC1–AC12) — Phase 1 and Phase 2 sets are stated
separately there, because Phase 1 merges alone.

## Issue disposition

PR body uses **`Refs #7535`, not `Closes`**. The issue is titled "remove the … apt dependency";
this work reduces and names it. #7535 stays OPEN, retitled to residual scope, with the
measurements posted as a comment.
