---
feature: prebake-rehearsal-image
issue: 7535
branch: feat-prebake-rehearsal-image-7535
pr: 7540
date: 2026-08-13
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-08-13-prebake-rehearsal-image-brainstorm.md
follow_up: 7544
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

Two corrections to #7535's framing shape the work:

**The motivating cost does not transfer to CI.** #7535 extrapolates from a **local** 107.99 s
measurement. GitHub-hosted runners use an Azure apt mirror; the entire rehearsal step measures
**110–119 s (n=6 green runs)**. The defect being removed is primarily the **mirror dependency
and its flake surface**, not a large wall-clock cost.

**One of the six sites installs a package that is already present.** `ubuntu:24.04` ships
`e2fsprogs 1.47.0-2.4~exp1ubuntu4.1` — the exact version `git-data-birth-fs-fingerprint.txt:57`
pins. `:872-873` is a no-op apt cycle, removable today with no image and no dependency on
#7507.

## Goals

- **G1 — Delete the `e2fsprogs` site (`:872-873`).** Free; independent of everything below.
- G2 — Collapse the remaining per-container apt cycles into one image build per run.
- G3 — Remove the external-mirror dependency, so a mirror outage cannot present as a rehearsal
  assertion failure.
- G4 — Introduce **no** durable published artifact: no registry, no signing, no pin cadence.
- G5 — Preserve exactly what each arm proves today; no assertion may become vacuous.

## Non-Goals

- NG1 — Publishing the image to GHCR or zot. Buys ~10 s/run over a local build; breaks fork PRs
  (which receive no secrets); creates a trust anchor for T5, the poisoned-artifact assertion.
  `deploy-script-tests` has neither a zot bridge nor a GHCR login today, so either path adds a
  new outage surface to a per-PR job.
- NG2 — Converting any site to `--network none`. T5's second recorded rationale (`:532-537`)
  survives pre-baking: real network is what makes T5 faithful.
- NG3 — Modifying #7501's retry logic. Separate PR (#7507).
- NG4 — Digest-pinning `ubuntu:24.04`. **Now understood as contraindicated for R1**, which is
  calibrated *against* drift: `fingerprint.txt:21-22,84-85` records that ≥1.47.1 emits
  `orphan_file`/`metadata_csum_seed` and 1.47.0 does not, so R1(a) currently detects the
  upstream bump. Pinning would remove that detector, leaving only the non-gating `R1-EXPIRY`
  (`:1007-1010`). Tracked with the counter-argument at #7544.
- NG5 — Any other suite in `infra-validation.yml`, or a shared base image for other test files.
- NG6 — Changing any assertion. This is a fixture-cost change only; the `total < 44` floor
  (`:1448`) is unchanged because removing apt changes no assertion count.

## Functional Requirements

- **FR1** — Delete the `apt-get update`/`install e2fsprogs` pair at `:872-873`. Add a one-line
  comment recording that `ubuntu:24.04` ships the pinned version, so a future reader does not
  "restore" it.
- **FR2** — An inline `Dockerfile` builds `FROM ubuntu:24.04` and installs the packages the
  **target cloud image** provides but Docker's minimal base strips.
- **FR3** — The image is built once per run and all remaining spins use the local tag.
- **FR4** — The harness fails loudly if the image is absent. It must never fall back to
  `ubuntu:24.04`, which would silently re-acquire the dependency this change removes.
- **FR5** — Rewrite the networking note at `:532-537` to state the post-change truth: tools now
  arrive via the image, and T5 still requires real network for tarball faithfulness. Re-anchor
  it to reason (2) only, so no future reader reads "no apt" as "now hermetic".

## Technical Requirements

- **TR1 (blocking, do first)** — Measure the apt share of the 114 s step before implementing
  FR2–FR4. The ~50–80 s estimate is a decomposition inferred from the step total, not a
  measurement. If apt is materially below ~50 s, stop and re-decide. **FR1 is exempt** — it is
  free regardless.
- **TR2 — Define the image as the target's package set, not the fixture's apt lines.**
  `cloud-init-git-data.yml:11-16` lists only `git, util-linux, cryptsetup, curl` under
  `packages:`; `python3`, `openssh-server` and `e2fsprogs` are absent because the Hetzner
  Ubuntu 24.04 **server** image already ships them (S1's own comment at `:659-662` confirms ssh
  is preinstalled and socket-activated). The fixture's apt only restores what Docker's minimal
  base stripped, so removing it moves the fixture **toward** the target. Building to "whatever
  the six apt lines happen to name" would instead create a third environment that is neither.
  Commit a package manifest and assert equality.
- **TR3 — Assert `! test -e /run/sshd` in the image.** Docker layers persist build-time `/run`
  writes; the real host boots a fresh tmpfs `/run`. That is S1's load-bearing precondition — its
  mutation (`:768-775`) depends on `sshd -t` failing with `Missing privilege separation
  directory`. **Probe status: half-measured.** A *runtime* install was confirmed not to leak
  `/run/sshd` (postinst never creates it; `sshd -t` → rc=255). The *build-time* case was **not**
  measured — the probe build was killed at 900 s — so "a layer cannot snapshot a directory the
  postinst never makes" is an inference. Measure it in CI at implementation time; do not treat
  the assertion as optional on the strength of the runtime result alone.
- **TR4 — Add the image to `_skip`'s preconditions (`:32-44`).** That guard today covers docker,
  the docker daemon, terraform and python3. A missing image must produce one named provisioning
  error, not eight arbitrary arm failures. Note `_skip` **fails** under `CI=true` by design.
- **TR5 — Follow the in-test build precedent, not a workflow step.**
  `apps/web-platform/scripts/sandbox-canary-regression.test.sh:162-168` builds an inline
  Dockerfile with `docker build -q`, guarded by `docker image inspect`. Keeping the build inside
  the test avoids coordinating a workflow step and keeps the suite runnable locally.
- **TR6** — If the build is instead placed in the workflow, it carries its own `timeout-minutes`
  per the convention at `infra-validation.yml:474-476`, and `deploy-script-tests`' budget must be
  re-derived. That budget is **`timeout-minutes: 14`** (`:515`) — the header comment's ladder
  ("8 (was 12, was 8, was 5)") has drifted from the actual value and should be corrected if
  touched.
- **TR7 — Mutation check.** Deliberately break the image and confirm T5, T17, S1, R1 and R4 each
  still **fail**. Guards the vacuous-green class where a fixture change makes a test pass without
  exercising its mechanism.
- **TR8** — Land only after PR #7507 merges, then rebase. Applies to FR2–FR5; FR1 is independent.

## User-Brand Impact

**Artifact:** the git-data runcmd rehearsal fixture — the runtime gate proving the git-data boot
chain aborts correctly on a bad payload.

**Vector:** the rehearsal is the only gate in the git-data suite that catches failures invisible
to static checks; the Phase-0 W0 probe passed every static check and would still have booted
dark. A fixture change that makes any arm pass without exercising its mechanism converts this
gate into a rubber stamp, allowing a git-data boot regression — customer repo data at rest — to
ship believing it was rehearsed. T5 specifically defends against executing a tampered download
as root.

**Threshold:** single-user incident.

## Acceptance Criteria

- AC1 — Zero `apt-get` invocations remain in the rehearsal's container payloads.
- AC2 — The rehearsal step's measured wall time is below its current 110–119 s band, verified
  across ≥3 green CI runs — not a local measurement, which is the error this cycle corrected.
- AC3 — All existing arms pass, and TR7's mutation check confirms each still fails when the
  image is broken.
- AC4 — No new file under `.github/workflows/` publishes an image; no cosign, crane, GHCR or zot
  step is added.
- AC5 — The suite still runs on a fork PR with no secrets available.
- AC6 — `git-data-render-strip-parity.test.sh` still passes — it reads this file to assert the
  anchored strip extractor (`:42`, `:196`).
- AC7 — R1 still detects an upstream `e2fsprogs` bump, or the detector it loses is replaced by an
  explicit `mke2fs -V` assertion (#7544).
