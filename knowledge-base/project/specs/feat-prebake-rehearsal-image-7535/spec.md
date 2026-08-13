---
feature: prebake-rehearsal-image
issue: 7535
branch: feat-prebake-rehearsal-image-7535
pr: 7540
date: 2026-08-13
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-08-13-prebake-rehearsal-image-brainstorm.md
status: draft
depends_on: 7507
---

# Spec — remove the rehearsal containers' apt dependency (#7535)

## Problem Statement

`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` spins eight `ubuntu:24.04`
containers per run (six code sites; `run_case` and `_s1_run` are each called twice). Every
container has a cold apt cache and installs its own packages — `curl python3` at four sites,
`openssh-server` at one, `e2fsprogs` at one. Each apt cycle is a dependency on an external
mirror inside a test whose failures then read as substantive findings about the emitter rather
than as a starved fixture.

The measured cost is smaller than #7535 states. The issue extrapolates from a **local**
107.99 s measurement; the entire CI step measures **110–119 s (n=6)**, because GitHub-hosted
runners use an Azure apt mirror. The defect being removed is therefore primarily the
**mirror dependency and its flake surface**, not a large wall-clock cost.

## Goals

- G1 — Collapse eight per-container apt cycles into one image build per CI run.
- G2 — Remove the external-mirror dependency from all six code sites, so a mirror outage
  cannot present as a rehearsal assertion failure.
- G3 — Introduce **no** durable published artifact: no registry, no signing, no pin cadence.
- G4 — Preserve exactly what each arm proves today; no assertion may become vacuous.

## Non-Goals

- NG1 — Publishing the image to GHCR or zot. Buys ~10 s/run over inline; breaks fork PRs
  (which receive no secrets); creates a trust anchor for T5, the poisoned-artifact assertion.
- NG2 — Converting any site to `--network none`. T5's second recorded rationale (`:532-537`)
  survives pre-baking: real network is what makes T5 faithful. Any `--network none` change for
  R1/S1 is a separate decision.
- NG3 — Modifying #7501's retry logic. Separate PR (#7507).
- NG4 — Digest-pinning `ubuntu:24.04`. Split to its own issue (D6) as an independent
  correctness fix.
- NG5 — Any other suite in `infra-validation.yml`, or a shared base image for other test files.
- NG6 — Changing any assertion. This is a fixture-cost change only.

## Functional Requirements

- **FR1** — A `Dockerfile` beside the test builds `FROM ubuntu:24.04` and installs
  `curl`, `python3`, `openssh-server`, `e2fsprogs` in a single layer.
- **FR2** — `infra-validation.yml`'s `deploy-script-tests` job builds it once, before the
  rehearsal step, tagged locally.
- **FR3** — All eight container spins use the local tag in place of `ubuntu:24.04`.
- **FR4** — The harness fails loudly if the local image is absent. It must never fall back to
  `ubuntu:24.04`, which would silently re-acquire the dependency this change removes (D8).
- **FR5** — The networking note at `git-data-runcmd-rehearsal.test.sh:532-537` is rewritten to
  state the post-change truth: tools now arrive via the image, and T5 still requires real
  network for tarball faithfulness (D9).

## Technical Requirements

- **TR1 (blocking, do first)** — Measure the apt share of the 114 s step before implementing.
  Instrument the eight cycles in one CI run. The entire value case rests on this decomposition,
  which is currently **inferred, not measured**. If apt is materially below ~50 s, stop and
  re-decide — a Dockerfile is not worth a 30 s saving.
- **TR2** — The build step carries its own `timeout-minutes`, per the convention recorded at
  `infra-validation.yml:474-476`: an image-building step must be independently attributable so
  a cold-pull stall names that step rather than cancelling the job elsewhere.
- **TR3** — Re-derive `deploy-script-tests`' `timeout-minutes: 8`. The workflow explicitly
  requires this when steps are added; the budget's comment documents its current composition.
- **TR4** — Mutation check: deliberately break the image and confirm T5, T17, S1, R1 and R4
  each still **fail**. Guards against the vacuous-green class where a fixture change makes a
  test pass without exercising its mechanism.
- **TR5** — Land only after PR #7507 merges, then rebase. #7507 edits this same file and bounds
  the R4 site.
- **TR6** — Follow the existing inline-build precedent in this job
  (`infra-validation.yml:415-419`, the alpine+bubblewrap image); do not invent a new pattern.

## User-Brand Impact

**Artifact:** the git-data runcmd rehearsal fixture — the runtime gate proving the git-data
boot chain aborts correctly on a bad payload.

**Vector:** the rehearsal is the only gate in the git-data suite that catches failures which
are invisible to static checks; the Phase-0 W0 probe passed every static check and would still
have booted dark. A fixture change that makes any arm pass without exercising its mechanism
converts this gate into a rubber stamp, allowing a git-data boot regression — customer repo
data at rest — to ship believing it was rehearsed. T5 specifically defends against executing a
tampered download as root.

**Threshold:** single-user incident.

## Acceptance Criteria

- AC1 — Zero `apt-get` invocations remain in the rehearsal's container payloads.
- AC2 — The rehearsal step's measured wall time is below its current 110–119 s band, verified
  across ≥3 green CI runs (not a local measurement — that is the error this cycle corrected).
- AC3 — All existing rehearsal arms pass, and TR4's mutation check confirms each still fails
  when the image is broken.
- AC4 — No new file under `.github/workflows/` publishes an image; no cosign, crane, GHCR or
  zot step is added.
- AC5 — The suite still runs on a fork PR with no secrets available.
- AC6 — `git-data-render-strip-parity.test.sh` still passes — it reads this file to assert the
  anchored strip extractor (`:42`, `:196`) and must remain green.
