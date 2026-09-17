---
feature: prebake-rehearsal-image
issue: 7535
branch: feat-one-shot-7535-rehearsal-apt-misattribution
phase1_branch: feat-prebake-rehearsal-image-7535
phase1_pr: 7540
phase1_merge: 910f237f0
date: 2026-08-13
updated: 2026-09-17
revision: R2-deepened
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
> and it did not survive. The image is **cut**. The feature slug and this directory name still say
> "prebake" — historical, not a live goal, and deliberately not renamed.

> **Retargeted 2026-09-17 (R1).** Two of Phase 2's four named sites were shipped by a sibling PR
> while Phase 2 was blocked, so the remaining scope is **two sites, not four**.

> **Reconciled 2026-09-17 (R2, deepen-plan).** An implementation of Phase 2 landed in the worktree
> during the deepen pass and is **uncommitted** (3630 -> 3717 lines, `+101/-14`, plus a modified
> `scripts/followthroughs/t5-skip-persistence-bound-7510.sh`). R2 adopts its `arm_skip` design and
> withdraws the requirements that forbade it; it also names six things the tree still owes. Every
> line number in R1 has shifted — **all anchors are by content.** See the plan's `Revision R2`.

## Problem Statement

`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` runs eight container spins per
invocation, and `apt-get` invocations across them install tools from an external mirror.

The defect is **not** cost. It is **diagnostic ambiguity**: when a mirror starves a container, the
arm fails in a way indistinguishable from a substantive finding. #7501's title records exactly
this. One transient failure produced #7501, #7535, #7544, PR #7507, a brainstorm and a plan.

**Two residual instances, measured 2026-09-17.**

1. At the T17-MUTATION site the enclosing `|| true` discarded the container rc and the sole
   assertion was `[ -s capture.log ]`, so a starved apt yielded an empty capture and the suite
   reported *"the check is vacuous"* — an apt failure misattributed as a **mutation-battery vacuity
   finding**.
2. **On the tree as built, the same misattribution survives for a different cause.**
   `echo T17M_APT_OK` precedes `bash /work/drive.sh`, and `drive.sh`'s bind guard exits 2 with
   `FIXTURE: capture server never bound :8099`. So a bind failure yields marker-PRESENT + rc 2 +
   empty capture and takes the vacuity branch, whose detail asserts *"apt succeeded and this is a
   genuine vacuity finding"*. A deterministic fixture defect announced as a vacuity finding.

## Predecessor state — do not reimplement

| Predecessor | State | Owns on `main` |
|---|---|---|
| PR #7507 | MERGED `dfcf7bd26` (2026-08-13) | `fixture_fail()` (defined **inside** the `R4DRV` heredoc), `Acquire::Retries=3`, a 3-attempt loop, post-install `command -v` checks, the `GIT_DATA_REHEARSAL_INJECT` harness — all at **R4** |
| PR #7510 | MERGED `45ea9f7e9` (2026-08-19) | The **`run_case`** split and the **T5-mutation** split. **Do not re-split.** |
| Phase 1 (#7540) | MERGED `910f237f0` (2026-08-13) | The redundant `e2fsprogs` install deleted, plus a NOFEATURES guard fix in R1(a)/(b) |

## Goals

- **G1 — SHIPPED.** Delete the redundant `e2fsprogs` install.
- **G2** — Make the two remaining uncovered apt cycles name themselves **per statement**, so a
  starved fixture is never read as a finding about the emitter or the mutation battery.
- **G3 (R2)** — Ensure the vacuity message is emitted only when the arm is genuinely vacuous, and
  that no reword, env var or future edit can turn the arm into a silent green.

## Non-Goals

- **NG1** — A pre-baked fixture image in any form. Measured: PUBLIC repo on standard runners so the
  saving is **$0**; Infra Validation is never the critical path so it is **0 operator-visible
  seconds**; it would introduce a T5 vacuous-green and convert eight independent failures into one
  correlated one.
- **NG2** — `FIXTURE_IMG`/`FIXTURE_PACKAGES` chokepoints and the three guards that depended on them.
- **NG3** — Publishing to GHCR or zot. **NG4** — `--network none` at any site (starves are induced
  by poisoning apt's sources in-driver). **NG5** — Digest-pinning beyond the existing `UBUNTU_BASE`
  pin (#7544). **NG6** — `-lt` -> `-ne` on the floor.
- **NG7** — Retry/backoff outside the R4 site #7507 owns.
- **NG8** — Re-splitting or re-wording `run_case` / T5-mutation (#7510's work); adding cause-level
  naming to `run_case`'s verdict; "fixing" `run_case`'s next-line `local rc=$?`.
- ~~**NG9** — Reclassifying T17 starvation to an `arm_skip`.~~ **WITHDRAWN at R2** — see TR8.
- **NG10** — Modelling Docker Hub in C4. **NG11** — Any other suite in `infra-validation.yml`.
- **NG12 (R2)** — A `workflow_dispatch` input for `GIT_DATA_REHEARSAL_INJECT`. See TR16.
- **NG13 (R2)** — Fixing the roster/ceiling census defect (TR17). Recorded and filed, not fixed.
- **NG14 (R2)** — A new docker-free verdict-ladder harness suite. Declined on registration cost.

## Functional Requirements

- **FR1, FR2 — SHIPPED.** The redundant install and its dead `DEBIAN_FRONTEND` export are gone,
  replaced by a comment recording that the deletion narrows R1's `e2fsprogs` source from
  mirror-current to image-current — a behaviour change, not a no-op.
- **FR3** — At the **T17-MUTATION** site: the AND-OR list is split (**done**), the container rc is
  captured through the removed `|| true` (**done**), and the verdict routes every non-vacuous cause
  away from the vacuity message. **Owed:** a per-statement literal for each apt statement; the sink
  moved out of the `-v "$TMP/out:/out"` bind mount; and two rungs — the `FIXTURE:` bind rung above
  the vacuity branch, and the `rc == 0` not-landed rung.
- **FR4** — At the **`_s1_run`** site: name each apt statement with a distinct fixed literal while
  **preserving the measured rc**, so the arm keeps declining honestly. **Naming only — no
  restructuring.** Naming is **done**; rc preservation is **owed**.
- **FR5 (replaces R1's FR5)** — A mutation that did not land must say so rather than reporting
  vacuity. This is **free from the rc**: `on_err`'s `[ "$rc" -eq 0 ] && exit 0` is the line the
  `sed` removes, so a landed-and-ran mutant exits 1 and a non-landed one exits 0. No `diff`, no
  count, no assertion, no floor move.
- **FR6** — Amend ADR-188: the image is **CUT** (not deferred-and-preferred); the retry
  alternative's now-unsatisfiable reconsideration condition; the stale non-declinable-arm
  enumeration; the Carrier note's roster and the ceiling table; and the preserved
  `[ ! -d /run/sshd ]` revival guard, distinguished from the separately-deferred `/out/setup.log`
  capture.
- **FR7 (R2)** — Pin `_T17M_MARKER` structurally over `"$0"`. Without it a one-sided reword makes
  the marker permanently absent and routes **every** run into `arm_skip` — a silent, permanent
  GREEN decline, strictly worse than the pre-change state.
- **FR8 (R2)** — Retire the superseded *"the deferred pre-baked image (#7535) is owed"* instruction
  from its two **executable** carriers: `scripts/followthroughs/t5-skip-persistence-bound-7510.sh`
  and `.github/workflows/scheduled-rehearsal-skip-monitor.yml`. Amending ADR-188 prose does not buy
  this while a daily monitor keeps emitting it. Keep the probe's counting behaviour unchanged.
- **FR9 (R2)** — An in-suite structural census over `"$0"`: zero AND-OR apt pairs on non-comment
  lines (with an anti-vacuity floor on its own grep) and zero `docker run … || true`.
- **FR10 (R2)** — Refuse fault injection under CI: a non-empty `GIT_DATA_REHEARSAL_INJECT` with
  `CI=true` must `echo … >&2; exit 1` before any arm runs.

## Technical Requirements

- **TR1, TR2 — SATISFIED.** FR1/FR2 shipped independently; FR3/FR4's blocker merged as `dfcf7bd26`.
- **TR3** — **`fixture_fail` must NOT be used at `_s1_run`.** It is defined inside the `R4DRV`
  heredoc and `exit 2`s. rc 2 is not in `_S1_ENV_RCS='100 125'`, so `_s1_classify` returns
  `harness-defect`; across the five `_s1_run` call sites' `case` arms that is **11 hard FAILs** on a
  transient mirror blip — the false-FAIL #7291 and ADR-188 removed. "Reuse `fixture_fail`" means
  reuse the idiom and the `FIXTURE-FAIL:` marker family, not the function, which is out of scope at
  both target sites.
- **TR4** — Preserve the measured rc (`_rc=$?; …; exit "$_rc"`); do **not** pin `exit 100`, which
  launders a non-apt-class rc into the environment allowlist. Place the handlers **inside the
  `<<'S1DRV'` heredoc, immediately after each `apt-get`** — never at `_s1_run`'s `docker run`, where
  `_rc` would be an unlocalised host global and `exit` would end the whole suite.
- **TR5** — Do **not** move `echo "S1_FIXTURE_OK"` above apt, and do **not** add an apt statement
  **below** it: one below makes rung 2 fire and yields the same 11 hard FAILs.
- **TR6** — No new `_skip` call site (it exits 0 off-CI).
- **TR7** — The constraint is the **gate**, not the absence of `$( )`:
  `lint-shell-capture-exit.py --baseline …` must report **zero new capture-then-exit findings** with
  the baseline unmodified (7 entries for this file; may only shrink). *R1 said "no command
  substitution"; the tree adds two and the gate is green — measured `0 new findings, 203 baselined`.*
- **TR8 (rewritten at R2)** — The T17 decline **is** an `arm_skip`, per ADR-188: for a precondition
  nobody owns the honest verdict is a declared skip, and T17-mutation's sibling T5-mutation already
  declines on the identical condition with the identical allowlist and image. The requirement is
  therefore **roster consistency**, not invariance: `grep -cE '^[[:space:]]*arm_skip '` == the
  `-eq N` stanza assertion == `_PROBE_NAMED` (with `_T17_SKIPS` folded in); `_SKIP_CEILING` == the
  sum in its itemised stanza; and `SKIP_MARKERS` carries `SKIP (loud): T17 `. The `arm_skip` must be
  written at line-start so the census can see it.
- **TR9** — The floor is `-lt 92` (raised 77 -> 92 by #8043 F11). FR7 and FR9 add assertions, so a
  **new** `# RAISED 92 -> <measured>` stanza is owed, the frozen 19-era baseline list must **not** be
  touched, and the number must be **re-derived from a measured run** — never incremented. No literal
  raise target appears in this spec or the plan for that reason.
- **TR10** — `set -e` does **not** fire on a failing non-final member of an AND-OR list. Measured:
  `bash -c 'set -e; sh -c "exit 100" && true; echo reached'` prints `reached`; final position exits
  100. The comment at the T17 site must name this mechanism, because the one-liner *looks* safe.
- **TR11** — Keep `>/dev/null 2>&1` on every apt statement and make every new message a **fixed
  literal**: behind an authenticated apt proxy apt's error text embeds `user:pass@host`, and the
  skip reason tails that capture on a GREEN run.
- **TR12** — Injection tokens must be **namespaced** (`t17-apt-update`, …) and compared with
  **exact `=` on a quoted `$INJECT`, mirroring R4** — never a `case` glob, never `=~`. R4 tests
  `[ "$INJECT" = "apt-update" ]`, so a glob form at T17 would let R4's token starve T17.
- **TR13 (R2)** — An injection arm must **poison apt**, not `exit` directly. An arm that exits never
  enters the `|| { … }` handler, so the injected and real observables diverge and the
  rc-preservation mutation row cannot be demonstrated. R4 gets away with a direct exit only because
  its handler *is* `fixture_fail`.
- **TR14 (R2)** — Read markers with `grep -qx`, never `grep -q`, and never a replicated literal.
  Note `_T5_MARKER`'s existing pin covers `drive.noerrexit.sh`, **not** the `drive.noguard.sh` the
  T17 arm mounts — FR7 is what pins the T17 marker.
- **TR15 (R2)** — **No apostrophe** may be added inside the `bash -c '…'` recipe: it is a
  single-quoted host string and one `'` is a whole-file syntax error (measured `bash -n` rc 2). Run
  `bash -n` after every recipe edit.
- **TR16 (R2)** — Do not ship a `workflow_dispatch` input for `GIT_DATA_REHEARSAL_INJECT`. Verified:
  `infra-validation.yml`'s `workflow_dispatch:` has no inputs and the rehearsal step no
  step-level `env:`, so the variable is not injectable from any workflow surface today; a free-form
  string input on a required gate would make FR10's switch operator-reachable with no ack or audit.
- **TR17 (R2)** — Record, do not fix (NG13): the roster guard's
  `grep -cE '^[[:space:]]*arm_skip ' "$0"` returns **4** while the file has **7** executable call
  sites (the three S2 ones are `case`-arm one-liners the line anchor cannot see), so the declarable
  skip budget is **13** against `_SKIP_CEILING=7` (re-derived on `origin/main`) and the roster identity is blind to half the
  roster. R1's NG9 was therefore unenforceable. File it with those measurements.
- **TR18** — Evidence provenance: every AC discloses `[local docker]` or `[CI run <id>]`, **and** the
  quoted terminal line must show `Skipped: 0` — a green CI run is obtainable from a run in which
  every new path declined. A docker-less green is not evidence: `_skip` exits 0 off-CI and
  `run-registered-suites.sh` prints PASS for a docker-less skip. Docker is currently **unavailable**
  on the authoring box (socket `root:docker`, empty `docker` group, no podman).
- **TR19** — Do not describe `git-data-birth-fs-fingerprint.txt:57` as a version pin; `:56` marks
  that block `CONTEXT FOR FAILURE MESSAGES ONLY — not asserted`.

## Files to change

`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`;
`knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`;
`scripts/followthroughs/t5-skip-persistence-bound-7510.sh`;
`.github/workflows/scheduled-rehearsal-skip-monitor.yml`. The last two are new at R2 — R1 said
"No workflow edit", and the probe was already modified in the tree while unlisted.

## User-Brand Impact

**If this lands broken:** nothing directly — no production code path. Indirect risk is a rehearsal
arm that stops discriminating; R2's FR7/FR9/FR10 exist because the adopted `arm_skip` design makes
"stops discriminating" *green* rather than red.

**If this leaks:** not applicable. The one confidentiality property (apt stderr suppression) is
preserved rather than introduced.

**Brand-survival threshold:** `none`.
**threshold: none, reason:** test-fixture-only change with no production code path, no data surface
and no credential; the diff adds error messages, rungs, a pin, a census and a CI refusal.

Diverges from the brainstorm's `single-user incident` deliberately: that framing reasoned from the
suite's importance rather than the change's blast radius.

## Acceptance Criteria

See the plan's `Acceptance Criteria`. Phase 1's set is frozen as a historical record at
`910f237f0`; Phase 2's AC8-AC30 are live, each carrying an evidence-provenance tag per TR18. The
plan's `Guard Contract` holds the two mutation matrices AC10 and AC11 verify.

## Issue disposition

PR body uses **`Closes #7535`** — in the body, never the title. **[Updated 2026-09-17] That close
is carried by PR #8249, not this branch:** implementation was handed to a parallel session's PR and
this one is docs-only, using `Refs`. See the plan's `## Issue disposition`. The issue is already retitled and
already carries the image-cut measurements as a comment (Phase 1 task 1.10).
