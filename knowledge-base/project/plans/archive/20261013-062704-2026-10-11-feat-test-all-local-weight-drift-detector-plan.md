---
title: "test-all: local weight-drift detector — warn when a suite's local actual exceeds committed weight by >2x"
type: feat
date: 2026-10-11
slug: feat-test-all-local-weight-drift-detector
branch: feat-one-shot-9814-local-weight-drift
issue: 9814
closes: 9814
lane: cross-domain
requires_cpo_signoff: true
---

# test-all: local weight-drift detector — warn when a suite's local actual exceeds committed weight by >2x

## Enhancement Summary

**Deepened on:** 2026-10-11 (sequential-fallback — no Task/subagent spawn on
this harness; every lane ran in-process and none claims independent review)
**Sections enhanced:** Technical Approach (glob manifest read), Files to Edit
(`glob:` edge kind), Implementation Phases (suite ratchet constraints),
Quality Gates (QG-5 manifest-readers sweep), Success Metrics (verify form),
Architecture Decision (ADR amendment shape corrected), Observability
(discoverability probe dir-scoped), Risks (two rows added).

### Key Improvements

1. Manifest read widened from two literals to `suite-durations*.tsv` — a
   future third manifest joins the comparison instead of mis-reporting
   `unmeasured` (`2026-10-06` SE3).
2. The `AFFECTED_*_PATHS` block uses the `glob:` edge kind from #9813 — the
   declaration now says what the walker reads (`2026-10-10` doctrine).
3. ADR-242 amendment corrected to the dated `## Amendment —` convention (the
   ADR is single-Decision, not ordinal).
4. `discoverability_test.command` dir-scoped — the file-scoped form would
   have failed Check 10's suite-shape reject at ship.
5. New suite carries the three always-on-ratchet constraints
   (owning `trap`, absolute fixture root, per-arm env scrub) that only the
   affected gate exercises (`2026-10-05`).

### New Considerations Discovered

- `WEIGHT_DRIFT` lines print post-marker, so a monitor that exits on the
  `=== N/N ===` marker never sees them — accepted; the marker must stay last
  (#6750 class) and the lines live in run output + the durable TSV.
- QG-5 added: every suite that reads the durations/shard manifests is
  enumerated and run (`git grep -lE` recipe), because a regen can break a
  computed value no literal grep sees (`2026-10-03` SE9).

## Overview

`scripts/test-all.sh` already records per-suite elapsed milliseconds to
`TEST_TIMING_LOG` when that variable is set, and `scripts/suite-durations.tsv`
already carries committed CI weights per suite — but nothing compares a local
run's actual timings against the committed rows. Because local wall-clock
diverges ~2–3x per suite from CI weights, a suite that drifts far past its
committed row locally (the measured case: `lint-shell-trace-credential-refusal`
at 185s local vs 8.5s committed during #9763) is only caught by hand.

This plan adds a warn-only post-run check: for local `--affected` runs, default
`TEST_TIMING_LOG` to a per-run path beside the durable suite logs so the timing
data exists without explicit setup, then compare each ran suite's local
elapsed ms against its committed row and print
`WEIGHT_DRIFT <label> committed=<ms> local=<ms>` when the local actual exceeds
2x committed AND exceeds the 10s fast cap. Suites missing a committed row
report `committed=unmeasured` instead of being silently skipped. The check
never changes the exit code or suite selection — it is an agent-and-operator-
facing signal, not a gate.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement

The #9763 fast-tier ratchet budgets `ALWAYS_ON_SUITES` against committed CI
weights — deliberately: a wall-clock budget would flake, a committed-weight
budget cannot (`scripts/test-all-fast-tier-budget.test.sh` header). But the
inverse question — *does this local run's reality still resemble the committed
rows?* — has no answer anywhere in the run's output. `TEST_TIMING_LOG` exists
and is wired end-to-end, yet it is set only by `ci.yml` shard legs and by the
runner's own test harnesses; a local `--affected` run produces no timing log
unless the caller knows to export it. The one instrument that would have
caught the 185s-vs-8.5s drift was present, unpriced, and off by default.

## Proposed Solution

Three wired-together pieces, all inside `scripts/`:

1. **`scripts/lib/test-weight-drift.sh`** (new) — a `weight_drift_report
   <timing-log> <durations...>` function. Loads every committed durations
   manifest passed to it into a label→ms map (preserving field-3 class), walks
   the timing log in order, and emits the WEIGHT_DRIFT line set to **stdout and
   stderr** (dual-emit operator-protection convention, `test-all.sh:686`).
   Implemented as one `LC_ALL=C awk -F'\t'` pass — the same idiom
   `_aff_full_cost_min` already uses on these manifests (`test-all.sh:3610`) —
   so it is bash-3.2-safe on macOS hosts where `declare -A` is unavailable.
   Always returns 0.

2. **A `TEST_TIMING_LOG` default arm in `scripts/test-all.sh`** — after
   `_durable_log_dir` is computed (~line 4272) and before the first
   registration: when `TEST_TIMING_LOG` is unset AND `CI` is unset AND the run
   is affected-shaped (`TEST_GROUP == affected` OR `_AFFECTED == 1` — the two
   selectors are deliberately disjoint, `test-all.sh:420`), `mkdir -p` +
   writability-probe `$_durable_log_dir`, then set in-shell (never export —
   `TEST_TIMING_LOG="$_durable_log_dir/suite-timings.tsv"`. The probe is
   load-bearing: `run_suite` appends with `>>` under `set -e`, so an
   unwritable target aborts the run mid-suite — the arm must degrade to
   "no timing log", never to "dead runner".

3. **An epilogue emit in `scripts/test-all.sh`** — in the post-marker NOTE
   region (after `=== N/N suites passed ===`, with the infra/ceiling
   notices): when `CI` is unset, `TEST_TIMING_LOG` names a readable file, and
   `weight_drift_report` is defined, call it `|| true` over
   `"$_scriptdir"/suite-durations*.tsv` — the GLOB, not two literals
   (deepen finding from `2026-10-06-one-self-inclusion-claim...`: absence in
   one file is not absence; a future third manifest is picked up rather than
   silently mis-reporting `unmeasured`). `$_scriptdir` is resolved via
   `dirname "${BASH_SOURCE[0]}"` like `_aff_full_cost_min` — never
   cwd-relative, since the runner can be invoked from any directory. A
   caller-set `TEST_TIMING_LOG` on any local run shape also reaches the
   comparator — the emit gate is on the variable, not the mode.

### Line grammar

```text
WEIGHT_DRIFT <label> committed=<ms> local=<ms>            # local > 2*committed AND local > 10000
WEIGHT_DRIFT <label> committed=<ms> basis=floor local=<ms>  # same, anchor row class != measured
WEIGHT_DRIFT <label> committed=unmeasured local=<ms>      # no row in either durations manifest
WEIGHT_DRIFT_UNAVAILABLE rows=<n> reason=elapsed-zero     # ran rows exist but every elapsed_ms is 0
WEIGHT_DRIFT_LOG <path>                                   # trailer, emitted when >=1 WEIGHT_DRIFT line fired
```

A row "ran" iff field 3 does not start `skip=` AND elapsed > 0. FAIL, KILLED
and TRIPWIRE rows still count as ran — they consumed wall-clock. Rows that are
comments (`^#`) or short (`NF < 2`, a torn write from a killed run) are skipped
— same `awk` guard idiom as `_aff_full_cost_min`. Manifest args are
`-f`-checked per file before `awk` reads them; with zero readable manifests
every ran row reports `unmeasured` (visible, never silently skipped — the
issue's own contract). When any WEIGHT_DRIFT line emitted, one trailer line
names the timing-log path so the warning is inspectable rather than a dead
end.

`WEIGHT_DRIFT_FLOOR_MS=10000` is a value-pinned constant mirroring
`LOCAL_FAST_CAP_MS` in `test-all-fast-tier-budget.test.sh` — pin the value,
exercise the predicate, per learning rule 4 of
`2026-10-09-committed-ci-weights-are-not-local-costs.md`.

## Technical Approach

### Architecture

The comparator is a pure function of two files — no runner state, no git, no
network — so the suite can drive it against synthetic fixtures exactly like
`check_tier` in `test-all-fast-tier-budget.test.sh`. The runner touches it at
exactly two points (the default arm and the epilogue call), keeping the change
surface small inside a 7000-line file.

### Implementation Phases

- **Phase 1 — lib + suite (RED first).** Write
  `scripts/test-all-weight-drift.test.sh` with fixture arms for every
  predicate term and row class (RED against a stub/absent lib), then
  `scripts/lib/test-weight-drift.sh` to GREEN. The suite's own shell obeys
  three repo ratchets visible only to always-on/affected suites
  (`2026-10-05` learning): every `mktemp` operand sits under one owning
  `trap ... EXIT` (`lint-trap-tempfile-ownership` rule c); the fixture root
  is a provably-absolute `mktemp -d` path (`fixture-relative-assert`); and
  sandboxed runner arms scrub the env per arm (`env -u TEST_GROUP`, never
  inherit `TEST_TIMING_LOG`/`CI` — the env-leak class that reddens suites
  only under an exported `TEST_GROUP=affected`).
- **Phase 2 — runner wiring.** Source the lib opportunistically beside the
  scratch-root include (~line 496), add the default arm after
  `_durable_log_dir` (~line 4272), add the epilogue call after the
  `=== N/N suites passed ===` marker, and register
  `run_suite "scripts/test-all-weight-drift" bash scripts/test-all-weight-drift.test.sh`
  beside the fast-tier-budget registration (~line 5184).
- **Phase 3 — classification + regen.** Add
  `"scripts/test-all-weight-drift"` to `ALWAYS_ON_SUITES` and an
  `AFFECTED_SCRIPTS_TEST_ALL_WEIGHT_DRIFT_PATHS` block in
  `scripts/lib/test-affected-paths.sh`, then run
  `python3 scripts/regenerate-shard-manifest.py --incremental --write` so the
  new always-on label gets a `floor` durations row and a shard-legs row
  (hand-editing generated tables is refused by ADR-240 convention; flags
  verified against `--help` 2026-10-11 — `--incremental` is a dry-run unless
  `--write` is passed).
- **Phase 4 — ADR-242 amendment.** Append a dated `## Amendment — 2026-10-11
  (#9814)` section (the ADR's own convention — it is a single-Decision ADR
  amended by dated sections, not an ordinal decision list), recording the
  decision below and its rejected alternatives.

## Files to Edit

- `scripts/test-all.sh` — lib source (~:497), `TEST_TIMING_LOG` default arm
  (after `_durable_log_dir`, ~:4275), epilogue emit (post-marker NOTE region,
  ~:6935), one `run_suite` registration (~:5184).
- `scripts/lib/test-affected-paths.sh` — `ALWAYS_ON_SUITES` entry +
  `AFFECTED_SCRIPTS_TEST_ALL_WEIGHT_DRIFT_PATHS` = { the suite file, the lib,
  `scripts/test-all.sh`, `glob:scripts/*.tsv` (the `glob:`
  edge kind from #9813/PR #9945 — the walker reads the glob, so the edge says
  the glob, not today's two literals),
  `scripts/lib/test-affected-paths.sh` (self-inclusion convention) }.
- `scripts/suite-durations.tsv` — regenerated floor row via
  `--incremental --write` (never hand-edited).
- `scripts/suite-shard-legs.tsv` — regenerated leg assignment via the same
  command.
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
  — new decision + alternatives (Phase 2.10 deliverable).

## Files to Create

- `scripts/lib/test-weight-drift.sh` — the comparator.
- `scripts/test-all-weight-drift.test.sh` — the always-on suite.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Extend `test-all-fast-tier-budget` to compare local actuals | That suite's own contract is "a wall-clock budget would flake; a committed-weight budget cannot" — feeding it local actuals rebuilds the flake it exists to remove. Different property: it pins committed weights, this measures local reality. |
| Reuse `_suite_budget_ms` (the `[budget]` declared-budget notice, test-all.sh:1820) | Compares against a per-suite DECLARED budget, not committed CI weights; a suite with no declared budget is invisible — the same unaccountability class this issue closes. |
| Fail the run on drift | Rejected by the issue itself and by its data: a contended host inflates every ratio (7.6x and 6.0x measured on the 2026-10-09 spot-check), so a gate flakes every local run on a loaded machine. |
| Opt-in only (no default; require `TEST_TIMING_LOG=...`) | An opt-in instrument is invisible by default — the exact shape that let the 185s suite slip through #9763 unnoticed. The default arm is the ask's point: a local run "currently pays nothing for it". |
| Local-median baseline file instead of committed rows | Needs a local timing corpus that does not exist; committed rows are the only baseline, and they are what the ratchet is charged against, so drift-from-committed is the meaningful signal. |
| Comparator inside `scripts/lib/test-contention.sh` epilogue | Contention reporting is tmpfs-pressure attribution, a different axis; a dedicated lib keeps the predicate fixture-drivable like `check_tier`. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a local `test-all.sh
  --affected` run that either dies mid-suite (a `TEST_TIMING_LOG` default
  pointing at an unwritable path turns a `>>` append into a `set -e` abort) or
  silently emits nothing — the fast-feedback gate in the daily dev loop is
  degraded or dead on the default path.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  data surface — the artifact is a per-suite millisecond table on local disk;
  the exposure is *workflow*: a broken default arm makes the fast-feedback
  gate itself unavailable, pushing callers to bypass testing.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** no end user is touched, but the
  diff touches the runner's every-local-run path — a defect in the default arm
  is an availability incident for the caller class this repo serves, the
  same class the #9813 plan rated `single-user incident` for a coverage gate.

*Scope-out override:* n/a — threshold is not `none`.

CPO sign-off required at plan time before `soleur:work` begins — invoke the
CPO domain leader or confirm prior coverage;
`soleur:engineering:review:user-impact-reviewer` is invoked at review time
(review skill conditional-agent block).

## Observability

```yaml
liveness_signal:
  what: WEIGHT_DRIFT / committed=unmeasured / WEIGHT_DRIFT_UNAVAILABLE lines in the post-marker block of a local --affected run
  cadence: per local --affected run (and any local run with TEST_TIMING_LOG set)
  alert_target: none — local dev tooling; the line is visible in run output and greppable by the invoking agent
  configured_in: scripts/lib/test-weight-drift.sh (emit) + scripts/test-all.sh (epilogue call site)
error_reporting:
  destination: stdout AND stderr of the invoking run (operator-protection dual-emit, test-all.sh:686)
  fail_loud: WEIGHT_DRIFT_UNAVAILABLE rows=<n> reason=elapsed-zero when ran rows exist but every elapsed is 0 — the check measured nothing, and says so rather than reading as clean
failure_modes:
  - mode: default arm silently never fires (condition wrong, probe inverted)
    detection: suite wiring arm asserts the timing-log path exists and the epilogue produced output on a sandboxed affected run
    alert_route: scripts/test-all-weight-drift suite RED
  - mode: default arm targets an unwritable path; run_suite's `>>` aborts the run under set -e
    detection: read-only-dir arm asserts the run still completes (probe declines to default) and rc is unchanged
    alert_route: suite RED on the diff that removed the probe
  - mode: predicate regresses (2x weakened, floor dropped, skip= rows counted)
    detection: fixture arms drive each term of the predicate and each row class
    alert_route: suite RED at the mutating diff
  - mode: contended host inflates all ratios — expected noise
    detection: none by design; warn-only posture is the mitigation, and the 2x AND >10s conjunction keeps sub-cap drift invisible
    alert_route: caller reads the lines in context
logs:
  where: run stdout/stderr; the timing TSV at $_durable_log_dir/suite-timings.tsv under ${SOLEUR_SCRATCH_BASE:-/var/tmp}/soleur-test-all-logs/<run-dir>/
  retention: run log is console lifetime; the TSV rides the #9117 age-reap on the durable log dir
discoverability_test:
  # dir-scoped on purpose: the file-scoped form `scripts/lib/test-weight-drift.sh`
  # trips Check 10's suite-shape detector (`/test-` inside a filename reads as a
  # test suite). `rg` over the lib dir prints the marker's emit site post-landing.
  command: rg -n WEIGHT_DRIFT scripts/lib
  expected_output: WEIGHT_DRIFT
```

## Encryption Posture

```yaml
# No persistent store and no new cross-component connection. The timing TSV is a
# per-run scratch artifact under the caller's own /var/tmp — the same class as
# the per-suite tee'd logs the runner already writes, deleted with the run dir by
# the #9117 age-reap. Not a store in the Phase 2.11 sense.
at_rest: []
in_transit: []
```

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
with a dated `## Amendment — 2026-10-11 (#9814)` section (the ADR's own
convention — a single Decision followed by dated Amendments, latest
`#9813` 2026-10-10; no ordinal to verify): **"a local run reports local-vs-
committed weight drift as an advisory line, never a gate."** Record: the
TEST_TIMING_LOG default arm for local affected runs, the >2x-committed AND
>10s predicate, the `unmeasured` reporting contract, the dual-emit convention,
and the deliberate non-failing posture. Alternatives table gains: gating on
drift (rejected — contended-host flake), opt-in-only (rejected — invisible by
default), local-median baseline (rejected — no local corpus).

### C4 views

No C4 impact. Checked against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External human actors** — none new. The model's actors (`founder`,
  `emailSender`, `publicReader`, `supportUser`, `betaContact`, `contributor`)
  are unchanged; a test-runner advisory line creates no actor.
- **External systems / vendors** — none (no new service, webhook, or store).
- **Containers / data-stores** — none; the local gate is below modeled
  granularity (no `test-all` element exists in `model.c4`; the only "timing"
  hits are unrelated volume/probe descriptions).
- **Actor↔surface access relationships** — unchanged.

### Sequencing

True at merge — a single `status: accepted` amendment, no adopting window.

## Guard Contract

### Guard 1 — `weight_drift_report` comparator

**Property.** For every ran row in the timing log (field 3 not `skip=*`,
elapsed > 0), the report emits exactly one `WEIGHT_DRIFT` line iff
`local > 2*committed AND local > WEIGHT_DRIFT_FLOOR_MS`, exactly one
`committed=unmeasured` line iff the label has no row in either durations
manifest, and nothing otherwise — and the report never exits non-zero.

**Assembly.** One chokepoint: `weight_drift_report` in
`scripts/lib/test-weight-drift.sh`, called once from the test-all.sh epilogue
with inputs = this run's `TEST_TIMING_LOG` plus
`scripts/suite-durations{,-heavy}.tsv`. The identity set is the timing log's
row population; the join key is the `run_suite` label (= manifest field 1 —
verified `scripts/test-all-fast-tier-budget` appears in both).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `>` on the 2x term weakened to `>=` | RED — a 2.0x-exact fixture must NOT emit |
| 2 | `> WEIGHT_DRIFT_FLOOR_MS` term dropped | RED — a 3x/9s fixture must NOT emit |
| 3 | Comparator returns after the first drifted row | RED — a two-drifted-row fixture must emit two lines (stops-at-first is itself the defect) |
| 4 | `skip=*` rows classified as ran | RED — a declined-suite fixture must emit nothing |
| 5 | Missing-row (unmeasured) branch deleted | RED — a ran-but-rowless fixture must emit `committed=unmeasured`, not silence |
| 6 | FAIL/KILLED/TRIPWIRE rows filtered out | RED — a failed-and-drifted fixture must still emit |
| 7 | stdout emit dropped (stderr-only) | RED — the stdout-capture arm must see the line (harness-facing contract) |
| 8 | Must-PASS: a within-tolerance log (local < 2x on every row) | PASS — zero WEIGHT_DRIFT lines, rc 0 |
| 9 | Must-PASS: non-canonical row class — a `floor` anchor row | PASS — emits with `basis=floor`, not dropped or mis-keyed |

**Anchor.** The committed manifests are derived data regenerated by
`regenerate-shard-manifest.py` from CI artifacts — a hand-edit to
`suite-durations.tsv` weakens every comparison silently. The anchor is
protected by convention (generated-not-edited, ADR-240) and the
shard-manifest lint pins table shape; the residual is accepted for a warn-only
signal and recorded in Risks.

### Guard 2 — local timing-data path (default arm + epilogue call)

**Property.** A local affected run (`CI` unset, `TEST_TIMING_LOG` unset)
leaves a writable timing log that the epilogue comparator reads — and when the
path cannot be made writable, the run still completes with no drift block and
an unchanged exit code.

**Assembly.** Three sites in `scripts/test-all.sh`: the default arm (after
`_durable_log_dir`, before registrations — the single `TEST_TIMING_LOG`
assignment), `run_suite`'s `>> "${TEST_TIMING_LOG:-/dev/null}"` appends (the
sink the arm feeds), and the epilogue call site (the only comparator
invocation). The check's dispatch is the conjunction `-z CI && -n
TEST_TIMING_LOG && -f file && declare -F weight_drift_report`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Default arm deleted | RED — sandboxed affected run produces no timing log; the wiring arm asserting log-existence fails |
| 2 | Writability probe removed while the target is a read-only dir | RED — run must still complete green; a removed probe lets `>>` abort the run |
| 3 | Epilogue call site deleted | RED — timing log exists, zero WEIGHT_DRIFT lines; the emit arm fails |
| 4 | `-z ${CI:-}` dropped from the default arm (auto-defaults on CI) | RED — CI-arm fixture asserts no auto-default |
| 5 | `-z ${TEST_TIMING_LOG:-}` dropped (clobbers the caller-set path) | RED — caller-set path must win |
| 6 | Must-PASS: caller-set TEST_TIMING_LOG on a local `--full` run | PASS — comparator still emits (advisory on explicit opt-in) |
| 7 | Must-PASS: `--enumerate` run (no rows written) | PASS — empty/absent log emits nothing, exits clean |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "compare each selected suite's elapsed ms against its `suite-durations.tsv` row and print a `WEIGHT_DRIFT` line when local > 2x committed AND > the 10s fast cap" | FR-2 / `scripts/lib/test-weight-drift.sh` / epilogue emit | mapped |
| 2 | "default it on for local `--affected` runs to a scratch path, since a default local run currently pays nothing for it" | FR-1 / `TEST_TIMING_LOG` default arm in `scripts/test-all.sh` | mapped |
| 3 | "Deliberately non-failing — a contended host inflates every ratio; the signal is for the operator/agent reading the run, not a gate" | NFR-1 / `|| true` epilogue call + return-0 lib | mapped |
| 4 | "Suites missing a row report as `unmeasured` (already a budget-lint red only for the pinned allowlist — this stays informational)" | FR-3 / `committed=unmeasured` line | mapped |
| 5 | "Never changes exit code or selection." | NFR-1, NFR-2 / AC-4 | mapped |
| 6 | "A local `--affected` run emits `WEIGHT_DRIFT <label> committed=<ms> local=<ms>` warnings, or nothing when all within tolerance." | FR-2 / Acceptance Tests | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `scripts/lib/test-weight-drift.sh` | asks 1, 3, 4 | asked |
| `scripts/test-all.sh` default arm | "default it on for local `--affected` runs to a scratch path" | asked |
| `scripts/test-all.sh` epilogue emit | asks 1, 5 | asked |
| `scripts/test-all-weight-drift.test.sh` | — | inferred — justification: house fixture-arm convention (learnings rule 5: a predicate never driven red is untested) and the Guard Contract matrix must be exercised by a suite |
| `scripts/lib/test-affected-paths.sh` edits | — | inferred — justification: the orphan census reds any registration not classified ALWAYS_ON or edge-declared; the suite must be in `ALWAYS_ON_SUITES` |
| `scripts/suite-durations.tsv` + `suite-shard-legs.tsv` regen | — | inferred — justification: `test-all-fast-tier-budget` reds on an always-on label with no weight row; ADR-240 mandates `--incremental --write`, never a hand-edit |
| ADR-242 amendment | — | inferred — justification: plan Phase 2.10 makes the warn-only design decision a deliverable of this plan, not a deferred issue |
| `WEIGHT_DRIFT_UNAVAILABLE` line | — | inferred — justification: anti-vacuity; a bash-3.2 host produces all-zero elapsed and must not read as "within tolerance" |
| `suite-durations*.tsv` glob read | — | inferred — justification: correctness; heavy-group labels would falsely report `unmeasured` against the light table alone, and absence-in-one-file is not absence (deepen: `2026-10-06` SE3) |
| `basis=floor` annotation | — | inferred — justification: 3 `floor`-class rows exist; a floor-anchored drift line must name its weaker anchor |

### Split Assessment

- Subsystems touched: 1 — `scripts/` (plus the ADR file under `knowledge-base/`)
- Planned files: 7 | Estimated changed lines: ~480
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Functional Requirements

- [x] FR-1: a local `--affected` run (`CI` unset, `TEST_TIMING_LOG` unset) writes per-suite timings to a per-run file under `$_durable_log_dir` without explicit setup.
- [x] FR-2: when `TEST_TIMING_LOG` is set on a local run, each ran suite with `local > 2*committed AND local > 10000` emits exactly `WEIGHT_DRIFT <label> committed=<ms> local=<ms>` — on stdout and stderr.
- [x] FR-3: a ran suite with no row in any `scripts/suite-durations*.tsv` manifest emits `WEIGHT_DRIFT <label> committed=unmeasured local=<ms>` — never silently skipped.
- [x] FR-4: `skip=*`, KILLED/FAIL/TRIPWIRE handling per the grammar above (declines silent, ran-but-failed still compared).
- [x] FR-5: ran rows present but every elapsed_ms = 0 emits `WEIGHT_DRIFT_UNAVAILABLE rows=<n> reason=elapsed-zero` once.

### Non-Functional Requirements

- [x] NFR-1: exit code unchanged — a run emitting WEIGHT_DRIFT lines exits with the same rc as an identical run without them; the check can never set the code.
- [x] NFR-2: selection unchanged — affected selection, declines, the breakdown line and the `=== N/N suites passed ===` marker are byte-identical to a run without the feature.
- [x] NFR-3: no cost when unarmed — a run without `TEST_TIMING_LOG` (CI, `--full` local, caller-unset non-affected) pays nothing beyond one `[[ -n ]]` test.
- [x] NFR-4: bash-3.2 host safe — the comparator uses `awk`, no `declare -A` or bash-4 builtins; an EPOCHREALTIME-less host reports `WEIGHT_DRIFT_UNAVAILABLE`, not silence.
- [x] NFR-5: the default arm never arms on CI (`CI` set) and never overrides a caller-set `TEST_TIMING_LOG`.

### Quality Gates

- [x] QG-1: `scripts/test-all-weight-drift` is registered and in `ALWAYS_ON_SUITES` with its `AFFECTED_*_PATHS` block; `lint-orphan-test-suites` census green.
- [x] QG-2: `scripts/suite-durations.tsv` carries a `floor` row for the new label via `--incremental --write`; `test-all-fast-tier-budget` green with the allowlist unchanged (still 2 members).
- [x] QG-3: `python3 scripts/lint-guard-contract.py` green against this plan's Guard Contract.
- [x] QG-4: the new suite's mutation arms drive each predicate term and each wiring site red, and the must-PASS rows stay green.
- [ ] QG-5: manifest-readers sweep — `git grep -lE 'regenerate-shard-manifest|suite-shard-legs|suite-durations' -- plugins/soleur/test scripts tests` enumerated and every hit's suite run (per `2026-10-03` Session Error 9: a regen-derived value a suite computes from can break where a literal grep can't see it).

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a timing log row `scripts/x \t 30000` and a committed row `scripts/x \t 5000`, when `weight_drift_report` runs, then it emits `WEIGHT_DRIFT scripts/x committed=5000 local=30000` on stdout and stderr (unit layer — the lib is a pure file function).
- Given committed=5000 and local=10001 but ratio < 2x, then nothing emits (floor alone is not drift).
- Given committed=4000 and local=8100 (>2x but <10s), then nothing emits.
- Given committed=5000 and local=10000 (exactly 2x), then nothing emits — `>` is strict.
- Given a ran row for a label absent from both manifests, then `WEIGHT_DRIFT <label> committed=unmeasured local=<ms>` emits.
- Given a `floor`-class anchor row, then the line carries `basis=floor`.
- Given `skip=affected` / `skip=runtime-ceiling` rows, then nothing emits for them.
- Given a sandboxed affected run where a stub suite exceeds 2x committed (test-all-group-affected.test.sh fixture pattern), then stdout contains the WEIGHT_DRIFT line AND rc is the no-drift rc AND the `=== N/N passed ===` marker is intact. (integration layer)

### Regression Tests

- Caller-set `TEST_TIMING_LOG` on a local `--full` run → comparator still emits (the emit gate is on the variable).
- `CI=1` sandboxed run → no auto-default of `TEST_TIMING_LOG`.
- Read-only `_durable_log_dir` → default arm declines to set the variable; run completes green; no timing log.
- All-zero elapsed log → `WEIGHT_DRIFT_UNAVAILABLE` once, not per-row.

### Edge Cases

- bash 3.2 host (EPOCHREALTIME absent) → the unavailable arm above.
- Heavy-group label running locally → resolves via `suite-durations-heavy.tsv`, not `unmeasured` (the glob covers it; a fixture row proves the light+heavy join).
- `tmp_delta` trailing field rows → parsed by first three fields only.
- Duplicate label rows (defensive) → last row wins; documented in the lib.

## Success Metrics

A replay of the #9763 incident shape — an always-on suite at ~20x its
committed weight locally — emits a `WEIGHT_DRIFT` line in the run output.
Run-verification form: `bash scripts/test-all.sh --affected > /tmp/run.log
2>&1; rc=$?` — never `... | tail`, which discards the runner's rc under a
non-pipefail harness (`2026-05-18` tail-masking learning).
without anyone checking timings by hand; a quiet run on an idle machine emits
nothing.

## Dependencies & Prerequisites

None external. Ordering inside the PR: lib + suite land together (Phase 1);
runner wiring (Phase 2) before classification (Phase 3); regen after
registration or the new label is absent from the enumerate census. A diff
touching `scripts/test-all.sh` degrades local `--affected` to the full battery
(runner-changed fallback) while this PR is open — expected, and incidentally
the slowest local runs this feature exists to warn about.

## Risk Analysis & Mitigation

| Risk | Likelihood | Mitigation |
|---|---|---|
| Default arm sets an unwritable `TEST_TIMING_LOG`; `run_suite`'s `>>` aborts the run under `set -e` | Medium | `mkdir -p` + `[[ -w && -O ]]` probe before assigning; probe failure → variable stays unset; suite arm pins the read-only-dir case. MID-RUN RESIDUAL (review): the probe validates at arm time only — a dir deleted/ENOSPC mid-run still aborts the run at the next `>>` (same class as the caller-set exposure; bounded by the 14-day reap window and per-run leaf, documented not retrofitted because `|| true` on appends would silently drop audit rows) |
| Comparator error mid-epilogue corrupts the summary path | Low | Called `|| true` after the `=== N/N passed ===` marker, inside `declare -F` + `-f` guards; pure file reads, no writes |
| Contended host floods the block with WEIGHT_DRIFT lines | Expected | Warn-only by design; the 2x AND >10s conjunction; issue's own data says direction holds under inflation |
| Manifest regenerated dropping a label → stale `unmeasured` | Low | `unmeasured` is informational, exactly the visible-not-silent posture the issue asks for |
| Label join mismatch (registration label ≠ manifest key) | Low | Verified: manifest field 1 is the `run_suite` label (`scripts/test-all-fast-tier-budget` appears verbatim in both) |
| macOS bash 3.2 → all-zero elapsed → vacuous signal | Medium on that host | `WEIGHT_DRIFT_UNAVAILABLE` names the vacuity instead of reading as clean |
| New always-on label without a weight row → `test-all-fast-tier-budget` RED | Certain if skipped | `--incremental --write` regen is a Phase-3 step, pinned by QG-2 |
| Caller-set `TEST_TIMING_LOG` to an unwritable path aborts the run (`>>` under `set -e`) | Pre-existing — unchanged by this plan | The NEW default arm is the only exposure added; it is probe-guarded. Widening the probe to the caller-set case is out of scope — a caller who exports a bad path asked for it |
| Timing log truncated mid-row (watchdog kill mid-write) | Low | `NF < 2` rows skipped in the comparator |
| Warning fatigue: the issue-set 2x predicate sits at the bottom of the measured ~2-3x local-vs-CI divergence band | Expected | Warn-only advisory; `basis=floor` names weak anchors; operators read lines in context (Observability failure-mode 4 accepts this) |
| The suite flags itself `basis=floor` on contended hosts until the first measured regen | Expected | Floor rows are honest placeholders; the line names its weak basis. CI measured weight expected ~3.5-6s (sibling-calibrated vs test-all-group-affected's 3200ms) — if >10s the fast-tier lint forces the ADR-262 demotion decision by design |
| Permanent `committed=unmeasured` classes (bun/webplat/infra legs carry no row in either scripts manifest) | Certain | Visible-not-silent contract is deliberate; a `basis=unpriced-leg` annotation is the recorded follow-up if readers start ignoring the block |

## Research Insights

**Sequential-fallback disclosure:** this environment has no Task/subagent
spawn; every research lane (`repo-research-analyst`, `learnings-researcher`,
community/functional discovery, ADR corpus, code-review overlap) ran
sequentially in-process by direct read and grep.

**Premise Validation (Phase 0.6).** Issue #9814 is OPEN with no closing PR.
Cited refs verified: #9763 CLOSED as stated; PR #9945 MERGED 2026-10-11
(extension-aware glob); #9969 OPEN and correctly out of scope;
`scripts/suite-durations.tsv` present (604 rows, 595 `measured` + 3 `floor`);
`TEST_TIMING_LOG` plumbing exists in `scripts/test-all.sh` (writes at :1635,
:1670, :1697, :1829, :1844, :1855, :1858, :1899) and is set only by
`ci.yml:1467/:1555` and test harnesses — never defaulted locally;
`knowledge-base/project/learnings/2026-10-09-committed-ci-weights-are-not-local-costs.md`
exists and corroborates every claim. ADR corpus checked for the proposed
mechanism (ADR-240 shard manifest, ADR-242 local gate): no rejected
alternative covers a local-vs-committed advisory; ADR-240 decision 6
mandates `--incremental` regen for new labels. Proposed-mechanism check on
"local affected run": `_AFFECTED == 1` covers the flag AND the no-flag local
default (`test-all.sh:420-424`); `TEST_GROUP=affected` is a *distinct
selector* the `_AFFECTED` gate deliberately does not arm — the default arm
must cover both.

**Property List (Phase 0.6b).** (1) A local run surfaces per-suite
local-vs-committed drift as agent-readable WEIGHT_DRIFT lines. (2) A
default local affected run pays nothing extra to obtain the timing data.
(3) The signal is warn-only — exit code and selection unchanged. (4)
Missing-row suites report `unmeasured` — absence is visible, not silent.
**Cut List:** nothing cut — both mechanisms named in the ask buy uncovered
properties (TEST_TIMING_LOG plumbing exists but no local default; the
committed-weight budget exists but never reads local actuals;
`_suite_budget_ms` exists but compares declared budgets, not committed
weights). **Value measurement (0.6c):** not a cost-saving claim — the
justification is the measured miss in the issue (185s vs 8.5s), already
quantified there and in the learnings file.

**Relevant files.**
`scripts/test-all.sh` (run_suite timing writes :1635–:1899; `_durable_log_dir`
:4272; `_AFFECTED` resolution :414–424; dual-emit precedent :686; epilogue
NOTE region :6930–:6990; registration example :5184);
`scripts/suite-durations.tsv` + `scripts/suite-durations-heavy.tsv` (label \t
ms \t class; field 1 = run_suite label — verified);
`scripts/test-all-fast-tier-budget.test.sh` (`check_tier`, LOCAL_FAST_CAP_MS=10000,
KNOWN_UNMEASURED_ALWAYS_ON 2-member pinned set);
`scripts/lib/test-affected-paths.sh` (ALWAYS_ON_SUITES :106+, edge-array
conventions :1–105);
`scripts/regenerate-shard-manifest.py` (`--incremental --write` adds floor
rows + leg rows for new labels);
`scripts/test-all-group-affected.test.sh` (sandboxed-runner fixture pattern,
:270–:296).

**Learnings applied.**
`2026-10-09-committed-ci-weights-are-not-local-costs.md` (all five rules —
budget against the paying machine; unmeasured = unaccountable; pin the value,
exercise the predicate; fixture arms for cap predicates); the constitution's
operator-protection-signal → stdout rule, realized here as the
`test-all.sh:686` dual-emit precedent; `set -euo pipefail` append-abort
hazard on the default arm.

**Conventions captured.** Registration = `run_suite "<label>" <cmd>` +
`ALWAYS_ON_SUITES` + `AFFECTED_*_PATHS`; new-suite weight row comes only from
`--incremental --write` (ADR-240: generated, never hand-edited); suite
self-tests carry inline mutation arms; `[budget]`/NOTES precedent for
caller-facing advisories.

**Research Reconciliation — Spec vs. Codebase.** All issue claims verified
against the tree; none stale. The one precision adjustment: "selected suite"
in the ask maps to *ran* rows — `skip=` rows are written to the timing log at
0ms and are correctly invisible; and "suite-durations.tsv row" must include
`suite-durations-heavy.tsv` or three labels mis-report `unmeasured`.

**Deepen pass (2026-10-11, sequential-fallback).** Mechanical halts 4.6/4.7/
4.8/4.9/4.10/4.11/4.12 all pass — `lint-guard-contract.py` green (2 entries),
Scope Check fence-count 1 with compliant rows, PAT sweep clean,
Observability 5-field valid. One gate-adjacent fix landed: the
discoverability probe was dir-scoped because the file-scoped form trips
Check 10's suite-shape detector (`/test-` inside the filename). Learnings
consumed and folded: `2026-10-06` SE3 (absence-in-one-file is not absence →
manifest read is `suite-durations*.tsv`, and the edge declares `glob:` kind);
`2026-10-03` SE9 (manifest-readers sweep added as QG-5); `2026-10-05` (the
new suite obeys lint-trap-tempfile-ownership (c), fixture-relative-assert,
and per-arm env scrub); `2026-10-10` (edge declares what the walker reads);
`2026-05-18` (verification uses redirect+`$?`, never `| tail`). Citation
census: all 7 referenced issues/PRs re-verified live; `cq-ac-must-not-depend-on-concurrent-sessions` confirmed migrated-active. Verify-the-negative pass:
`TEST_TIMING_LOG` setter census confirms only `ci.yml` + harnesses; zero
`===`-shaped lines exist after the `:6949` marker; zero suites pin the live
registration count, so the added `run_suite` is safe.

**Plan Review (inline sequential-fallback).** The 5-agent panel lenses
(DHH/simplicity, Kieran/correctness, architecture/blast-radius, spec-flow,
CTO/devex — activated by `single-user incident` + tooling Files) were applied
in-process since no Task spawn exists; no independent review ran and none is
claimed. Findings folded, all Mechanical: torn/short timing rows skipped
(`NF < 2`); durations paths resolved via `BASH_SOURCE` dir not cwd;
caller-set-unwritable-path residual recorded in Risks; sandbox-mutation
safety and edge-consumer notes added to Sharp Edges. Standing check
`cq-ac-must-not-depend-on-concurrent-sessions`: clean — every AC is
deterministic over synthetic fixtures or the sandboxed runner; the
idle-machine line lives in Success Metrics, not an AC. No Taste or
User-Challenge findings to persist.

## Domain Review

**Domains relevant:** Engineering only — internal test-gate machinery; no
user-facing surface (mechanical UI-surface override checked: Files to
Create/Edit contain no `*.tsx`, `page.tsx`, `components/**`, `*.njk`, or
glob-superset match).

### Engineering

**Status:** reviewed (inline — subagent spawn unavailable in this
environment)

**Assessment:** dev-experience instrumentation on Soleur's own local gate.
The binding doctrines are fail-toward-coverage (ADR-242) and
warn-not-gate (the issue's explicit posture); the hazard is concentrated in
the default arm's write-target probe and in keeping the emit strictly
post-marker. No architectural novelty — a consumer of two existing data
paths (TEST_TIMING_LOG rows, committed durations manifests).

### Product/UX Gate

**Tier:** none — no user-facing surface; the mechanical override did not
fire.

## Open Code-Review Overlap

- `#8659` (33 suites replace test-helpers' composed EXIT trap): **acknowledge**
  — the new suite follows the sibling `trap cleanup EXIT` shape and does not
  source `test-helpers.sh`, so the defect class does not apply; noted so the
  implementer does not copy the wrong pattern.
- `#7942` (mutation batteries named `*.mutation.sh` run in no gate):
  **acknowledge** — the new suite is a registered `*.test.sh`, not a stray
  battery.
- `#8800` (census sandbox shares inodes/symlinks with live repo):
  **acknowledge** — this suite's fixtures are synthetic TSVs in mktemp dirs;
  the sandboxed-runner arms use the established `build_sandbox` shape, which
  that issue's remediation covers separately.

## Sharp Edges

- A `WEIGHT_DRIFT` line that only reaches stderr is invisible to the invoking
  agent's stdout capture — dual-emit is load-bearing, not stylistic.
- The default arm's writability probe is the difference between "no signal"
  and "dead runner": `>>` under `set -e` aborts on an unwritable target.
- `TEST_GROUP=affected` and `_AFFECTED == 1` are disjoint selectors by design;
  gating the default on only one leaves half the local affected runs without
  timing data.
- `skip=*` rows exist in the same file with `0` elapsed — a comparator that
  doesn't filter field 3 floods the report with declines.
- The `=== N/N suites passed ===` marker must remain the last `===`-shaped
  line; the emit site goes in the post-marker NOTE region, never before it.
- The default arm survives the splice window in EVERY runner-SUT sandbox
  copy (it sits above tc_acquire): sibling suites must scrub with
  `TEST_TIMING_LOG=/dev/null` — the documented opt-out — or the arm creates
  `suite-timings.tsv` inside their durable-dir assertions (this reddened
  test-all-orphan-log-retention until scrubbed; review P1).
- "Nested runners don't emit WEIGHT_DRIFT" holds by directory layout, not
  contract: a fixture copying the full scripts/lib/ tree gains the emit
  (and per-stub `committed=unmeasured` lines) — copy only named libs.
- A diff touching `scripts/test-all.sh` self-selects the full battery
  (runner-changed): while this PR is open, local runs pay full cost — the
  plan's own development is a live exercise of the signal.
- The `AFFECTED_*_PATHS` entries are consumed by the affected classifier in
  `test-all.sh` and by the `lint-orphan-test-suites` census — they matter for
  FUTURE diffs touching the new files, not for this PR (runner-changed already
  degrades it to full).
- The wiring mutation arms edit a scratch COPY of the runner via the
  `build_sandbox` pattern (`test-all-group-affected.test.sh:270`) executed in
  a fixture dir — the mutations are textual predicate/call-site edits only;
  no `kill`/`pkill`/`$PPID`/`rm -r` block is ever flipped.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6 — filled above.

## References

- Issue: #9814 (this work)
- Parent sequence: #9763 (closed — fast-tier ratchet), PR #9945 (merged —
  extension-aware affected-glob), #9969 (open — under-cover siblings, out of
  scope)
- Learning: `knowledge-base/project/learnings/2026-10-09-committed-ci-weights-are-not-local-costs.md`
- ADRs: ADR-240 (shard manifest / durations derivation), ADR-242 (local gate
  defaults — amendment target), ADR-262 (edge-selection shape)
- Sibling plan: `knowledge-base/project/plans/2026-10-10-chore-extension-aware-affected-edges-plan.md`
