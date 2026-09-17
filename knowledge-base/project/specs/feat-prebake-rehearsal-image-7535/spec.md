---
feature: prebake-rehearsal-image
issue: 7535
branch: feat-one-shot-7535-rehearsal-apt-misattribution
phase1_branch: feat-prebake-rehearsal-image-7535
phase1_pr: 7540
phase1_merge: 910f237f0
date: 2026-08-13
updated: 2026-09-17
lane: cross-domain
brand_survival_threshold: none
brainstorm: knowledge-base/project/brainstorms/2026-08-13-prebake-rehearsal-image-brainstorm.md
plan: knowledge-base/project/plans/2026-08-13-test-remove-rehearsal-apt-dependency-plan.md
follow_up: 7544
status: phase2-retargeted
---

# Spec — stop the rehearsal's apt failures reading as emitter findings (#7535)

> **Revised 2026-08-13 after plan review.** The original spec scoped a locally-built fixture image
> replacing all eight container spins, plus guards. A seven-agent panel measured the value case
> and it did not survive. The image is **cut**; the surviving scope is below. The feature slug and
> this directory name still say "prebake" — that is historical, not a live goal, and the directory
> is deliberately not renamed (see the plan's artifact-location note).

> **Retargeted 2026-09-17.** Phase 1 shipped. Two of Phase 2's four named sites were shipped by a
> sibling PR while Phase 2 was blocked, so the remaining scope is **two sites, not four**. Every
> line number this spec used to carry has shifted; all anchors are now by content.

## Problem Statement

`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (3630 lines on `main`) runs eight
container spins per invocation, and `apt-get` invocations across them install tools from an
external mirror.

The defect is **not** cost. It is **diagnostic ambiguity**: when a mirror starves a container, the
arm fails in a way indistinguishable from a substantive finding. #7501's title records exactly this
— *"the rehearsal's R3/R4 arms fail nondeterministically with empty captures, and read as a
substantive emitter finding."* One transient failure produced #7501, #7535, #7544, PR #7507, a
brainstorm and a plan.

**The residual instance, measured 2026-09-17.** At the T17-MUTATION site the enclosing `|| true`
discards the container's rc entirely and the sole assertion is `[ -s capture.log ]`, so a starved
apt yields an empty capture and the suite reports *"T17 MUTATION: removing the rc guard did NOT
make a healthy run emit — the check is vacuous"*. An apt/network failure is thereby misattributed
as a **mutation-battery vacuity finding** — the same defect class one arm over.

## Predecessor state — do not reimplement

| Predecessor | State | Owns on `main` |
|---|---|---|
| PR #7507 | MERGED `dfcf7bd26` (2026-08-13) | `fixture_fail()` (defined **inside** the `R4DRV` heredoc), `Acquire::Retries=3`, a 3-attempt install loop, post-install `command -v` checks, the `GIT_DATA_REHEARSAL_INJECT` harness — all at **R4** |
| PR #7510 | MERGED `45ea9f7e9` (2026-08-19) | The **`run_case`** split and the **T5-mutation** split. **Do not re-split.** |
| Phase 1 (#7540) | MERGED `910f237f0` (2026-08-13) | The redundant `e2fsprogs` install deleted (9 -> 7 apt invocations at that time) plus a NOFEATURES guard fix in R1(a)/(b) |

## Goals

- **G1 — SHIPPED.** Delete the redundant `e2fsprogs` install, which installed an already-present
  package at `Priority: required`.
- **G2** — Make the two remaining uncovered apt cycles name themselves, so a starved fixture is
  never read as a finding about the emitter or about the mutation battery.

## Non-Goals

- **NG1** — A pre-baked fixture image in any form, published or local. Measured: the repo is
  PUBLIC on standard runners so the saving is **$0**, and Infra Validation is never the critical
  path so it is **0 operator-visible seconds**. It would also introduce a T5 vacuous-green (a
  fixture whose `curl` cannot complete TLS satisfies every T5 assertion with `sha256sum -c` never
  evaluated) and convert eight independent failures into one correlated one.
- **NG2** — `FIXTURE_IMG`/`FIXTURE_PACKAGES` chokepoints and the three guards that depended on
  them. Cut with the image.
- **NG3** — Publishing to GHCR or zot.
- **NG4** — `--network none` at any site.
- **NG5** — Digest-pinning `ubuntu:24.04` beyond the existing `UBUNTU_BASE` pin (#7544).
- **NG6** — Changing the assertion floor from `-lt` to `-ne`.
- **NG7** — Retry/backoff outside the R4 site #7507 owns.
- **NG8** — Re-splitting or re-wording `run_case` / T5-mutation (#7510's work), or adding
  cause-level naming to `run_case`'s verdict.
- **NG9** — Reclassifying T17 starvation into an `arm_skip`. That is reclassification, not naming.
- **NG10** — Any other suite in `infra-validation.yml`; any assertion's meaning.

## Functional Requirements

- **FR1 — SHIPPED.** Delete the redundant `apt-get update` / `apt-get install -y -qq e2fsprogs`
  and the dead `export DEBIAN_FRONTEND=noninteractive` that became unreachable with them.
- **FR2 — SHIPPED.** Replace them with a comment recording why, including that this narrows R1's
  `e2fsprogs` source from mirror-current to image-current — a behaviour change, not a no-op.
- **FR3** — At the **T17-MUTATION** site (anchor: `# MUTATION: remove the rc guard and prove
  T17's assertion can FAIL`): split the `apt-get update … && apt-get install …` AND-OR list into
  two statements, capture the container rc through the removed `|| true`, name each apt statement
  with a distinct fixed literal, and make the verdict three-way so the vacuity message is emitted
  only when the arm is genuinely vacuous.
- **FR4** — At the **`_s1_run`** site (anchor: the `S1DRV` heredoc's
  `apt-get install -y -qq openssh-server`): name each apt statement with a distinct fixed literal
  while **preserving the measured rc**, so the arm keeps declining honestly. **Naming only — no
  restructuring.**
- **FR5** — Assert at the T17 site that the rc-guard mutation actually landed, so a `sed` that
  matched nothing cannot be reported as vacuity. (FR5 is the second leg of FR3's property; see the
  plan's D3 cut criterion if a reviewer scopes it out.)
- **FR6** — Amend ADR-188 to record the image as CUT rather than DEFERRED-and-preferred, carrying
  the replacement re-evaluation trigger and the `[ ! -d /run/sshd ]` revival guard.

## Technical Requirements

- **TR1 — SATISFIED.** FR1/FR2 shipped independently of #7507 (`e2fsprogs` appeared 0 times in
  its diff).
- **TR2 — SATISFIED.** FR3/FR4 were blocked on #7507; it merged as `dfcf7bd26`.
- **TR3** — **`fixture_fail` must NOT be used at `_s1_run`.** It is defined inside the `R4DRV`
  heredoc and it `exit 2`s. rc 2 is not in `_S1_ENV_RCS='100 125'`, so `_s1_classify` routes it to
  `harness-defect`; counted across the five `_s1_run` call sites' `case` arms that is **11 hard
  FAILs** on a transient mirror blip — the false-FAIL #7291 and ADR-188 removed. Use the
  `FIXTURE-APT:` literal + a preserved rc instead. "Reuse `fixture_fail`" means reuse the idiom
  and the marker convention, not the function, which is out of scope at both target sites.
- **TR4** — Preserve the measured rc at `_s1_run` (`_rc=$?; …; exit "$_rc"`); do **not** pin
  `exit 100`, which would launder a non-apt-class rc into the environment allowlist.
- **TR5** — Do **not** move `echo "S1_FIXTURE_OK"` above apt: the file's own comment states this
  converts every apt failure into a hard fixture-defect FAIL.
- **TR6** — No new `_skip` call site. `_skip` exits 0 off-CI, so routing a failed provisioning
  step through it would silently green a broken run on a laptop.
- **TR7** — No new command substitution. `scripts/lint-shell-capture-exit.baseline.txt` carries 7
  grandfathered findings for this file and may only **shrink**.
- **TR8** — No new `arm_skip` call site, and `_SKIP_CEILING` unchanged.
  `[ "$_SKIP_CALL_SITES" -eq 3 ]` and the `_PROBE_NAMED == _SKIP_CALL_SITES` roster identity
  (which sums only `T5 `- and `S1 `-prefixed sites) would both red otherwise, and
  `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` reads the same roster.
- **TR9** — **The assertion floor is `-lt 92`** (raised 77 -> 92 by #8043 F11), not `-lt 44`. If
  FR5 adds an assertion, add a **new** `# RAISED 92 -> <measured>` stanza and **do not touch** the
  frozen 19-era baseline list (`B1: 1, B2: 1, D1: 2, T5: 4 + 1 mutation, T17: 2 + 1 mutation,
  S1: 3 + 4 mutation`), which the file marks explicitly as *"not a running total"*. Re-derive the
  number from a **measured** run, never by incrementing.
- **TR10** — `set -e` does **not** fire on a failing non-final member of an AND-OR list. Measured:
  `bash -c 'set -e; sh -c "exit 100" && true; echo reached'` prints `reached` (rc 0);
  `bash -c 'set -e; true && sh -c "exit 100"'` exits 100. The comment at the T17 site must name
  this mechanism explicitly, because the one-liner form *looks* safe under `set -e`.
- **TR11** — Keep `>/dev/null 2>&1` on every apt statement and make every new message a **fixed
  literal**. Behind an authenticated apt proxy, apt's error text embeds `user:pass@host` and the
  skip reason tails that capture on a green run.
- **TR12** — Fault-injection tokens must be **namespaced** (`t17-apt-update`, `s1-apt-install`, …)
  because one `GIT_DATA_REHEARSAL_INJECT` variable is read by more than one driver; a shared token
  would silently starve a different arm than the row intends.
- **TR13** — Read the execution marker with `grep -qx "$_T5_MARKER"`, never `grep -q` and never a
  replicated literal. bash echoes the offending source line on an error, which satisfies a bare
  `grep -q`.
- **TR14** — Every acceptance criterion must disclose its evidence provenance (`[local docker]` or
  `[CI run <id>]`). A docker-less green is not evidence: `_skip` exits 0 off-CI and
  `run-registered-suites.sh` prints `PASS` for a docker-less skip. Docker is currently
  **unavailable on the authoring box** (socket `root:docker` 0660, empty `docker` group, no
  podman).
- **TR15** — Do not describe `git-data-birth-fs-fingerprint.txt:57` as a version pin. Its `:56`
  marks that block `CONTEXT FOR FAILURE MESSAGES ONLY — not asserted`; R1 asserts feature sets.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — no production code path.
Indirect risk is a rehearsal arm that stops discriminating.

**If this leaks:** not applicable — no data surface, credential or network egress added. The one
confidentiality property (apt stderr suppression) is preserved rather than introduced.

**Brand-survival threshold:** `none`.
**threshold: none, reason:** test-fixture-only change with no production code path, no data
surface and no credential; the diff adds error messages, one assertion, and an ADR amendment.

Diverges from the brainstorm's `single-user incident`, deliberately: that framing reasoned from
the suite's importance rather than the change's blast radius. Under the reduced scope no arm can
be made vacuous — the change removes two ways an arm can lie. The cut scope could have been, and
warranted the higher threshold.

## Acceptance Criteria

See the plan's `## Acceptance Criteria` — Phase 1's AC1-AC7 are **frozen as a historical record**
at `910f237f0` and must not be re-asserted against today's `main` (AC1's count moved 7 -> 15 when
#7507 added named apt strings). Phase 2's AC8-AC26 are the live set, and each carries an
evidence-provenance tag per TR14. The plan's `## Guard Contract` holds the two mutation matrices
AC10 and AC11 verify.

## Issue disposition

PR body uses **`Closes #7535`** — in the body, never the title. Phase 2 completes the residual
scope. Phase 1 correctly used `Refs`. The issue is already retitled and already carries the
image-cut measurements as a comment (Phase 1 task 1.10).
