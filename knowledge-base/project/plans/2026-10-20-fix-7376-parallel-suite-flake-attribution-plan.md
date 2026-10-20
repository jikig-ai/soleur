---
title: "fix: attribute and close out the -P 4 parallel infra-suite flake (#7376)"
type: fix
date: 2026-10-20
slug: fix-7376-parallel-suite-flake-attribution
branch: feat-one-shot-7376-suite-flake
issue: 7376
closes: 7376
lane: cross-domain
priority: P2
domain: engineering
brand_survival_threshold: none
---

## Overview

Issue #7376 tracks a flaky parallel run of `apps/web-platform/infra/run-registered-suites.sh`
at its default width (`-P min(nproc,6)` = `-P 4` on a 4-core hosted runner). The first arm
(PR #7423) shipped the diagnostic instrument and closed a false green; the follow-up sweep
(#9554) removed the `grep -q` early-exit pipe shape that the flake was later traced to, and
PR #10459 removed the monitor's infra-step `JOBS=1` stopgap so the default-width path is now
under a 12-run soak (`scripts/followthroughs/jobs1-stopgap-7432.sh`). What remains is the
issue's own fix criteria: establish whether residual failures are shared-state collisions or
resource exhaustion, finish the cross-suite shared-state audit, ship per-run namespacing for
the sites that provably collide, and apply the resource arm the evidence supports.

## Research Insights

### Premise Validation (Phase 0.6)

- `#7376` OPEN — premise live; the issue's own Verification section says it stays open
  until its fix criteria are met (soak PASS posts figures as "mitigated, not fixed").
- `#7307`/`#7374` CLOSED, `#7423` MERGED — the diagnostic instrument, accounting
  assertion and per-suite `.log/.meta/.trow` capture all exist on this branch
  (`run-registered-suites.sh:758-1218`). The issue's "observability gap" ask is DONE;
  re-doing it is out of scope.
- `#7432` OPEN — `JOBS=1` stopgap removal; PR #10459 merged 2026-10-19 removing the
  infra-step pin; the tests-step `JOBS: 1` pin stays (`main-health-monitor.yml:365`).
  Soak probe `scripts/followthroughs/jobs1-stopgap-7432.sh` is mid-window.
- `#7554` OPEN — sibling `.meta` forge/erase defect; related, not absorbed.
- `#9554` MERGED — converted the production `| grep -q`/early-exit-reader population
  (166 lines, 82 files) and shipped the derived zero-sweep guard
  (`.claude/hooks/grep-q-pipe-guard.test.sh`, green today: 4,603 files swept, only 6
  file-exact deferral rows — none are executed suites). The executed suite set is at
  ZERO for the mechanism the flake was "mostly" traced to.
- Files verified: `run-registered-suites.sh` (1,218 lines), its `.test.sh` (1,157),
  `scripts/lib/scratch-root.sh` (session scratch root + TMPDIR export, live),
  `scripts/lib/test-contention.sh` (capacity instrumentation + advisory lock, used by
  test-all.sh only — `tc_acquire` is CI-exempt at line ~1307).
- Litmus verified at `skills/work/SKILL.md` ("three runs of an UNCHANGED tree giving
  three DIFFERENT failure sets is a harness defect").
- Suite census re-derived: `bash apps/web-platform/infra/run-registered-suites.sh
  --list` → 187 derived suites (issue body said 92 — stale).

### Mechanism Minimality (Phase 0.6b)

**Property List** (the ask restated as observable properties):

- P1: a residual `-P 4` failure is *attributable* — a reader can say which of
  shared-state vs resource-exhaustion vs real-defect produced it, from evidence, not
  intuition.
- P2: no registered suite shares mutable state a concurrent sibling/invocation can
  collide with (TMPDIR-ignoring writes, `mktemp -u`, fixed docker names, host ports,
  fixed lock/pid paths).
- P3: the namespacing fixes cannot silently regress (a re-added `mktemp -u` or
  hardcoded `/tmp` write in an audited file goes red).
- P4: if resource exhaustion is the residual class, the mitigation is deterministic
  and does not make the flake irreproducible (rejected: width varying per run/host).

**Cut List** (mechanisms the issue or intuition proposes that an existing mechanism
already covers, or that buy no property):

- "Make the runner report why a suite failed" — already shipped by #7423:
  marker-anchored bounded dump + `rc` + `elapsed` + `start_offset` + UNACCOUNTED
  naming + `::error` annotations (`run-registered-suites.sh:861-1152`). CUT.
- "Cap -P by available memory" — CUT as a *mechanism* by CTO ruling (P4 violated:
  auto-derived width varies per run and self-masks the evidence stream; recorded in
  `decision-challenges.md`). The *property* it serves (P4 resource mitigation) is
  covered by `_SUITE_BOUNDS` + the evidence-gated class-serialisation arm.
- Machine-wide run serialization via `tc_acquire` — exists but CI-exempt by design
  and serializes *invocations*, not intra-run width; adopting it buys nothing here.
- A dedicated CI soak workflow — the #7432 probe already runs that experiment; CUT.
- A mandatory local `taskset` n≥20 battery — CUT as an AC (CPU-only bound; a local
  non-reproduction establishes nothing per the prior arm's recorded caveat).

### Evidence ledger (measured this session, 2026-10-20)

- Monitor soak (window start 2026-10-19T18:00Z): run 39298929992 clean; run
  39345015242 ran `with -P 4` and reported `179 passed, 1 failed, 0 unaccounted (of
  180)` — the single RED was `cloud-init-inngest-bootstrap.test.sh` rc=1 in 8 s at
  +30 s, a **deterministic tag-drift failure** (cloud-init pin v1.1.56 vs latest
  merged tag v1.1.57), the allowlisted class the soak probe already names — NOT a
  parallel flake. The #7423 instrument produced the full attribution unaided.
- `deploy-script-tests` leg corpus per `main-health-monitor.yml` comment: 688 legs at
  `-P 4` 2026-09-25→10-16, 75 failures, **none shown parallel-only**.
- Bound-kill class proven at `-P 4` (rc=124 while internally green) and already
  mitigated by `_SUITE_BOUNDS` widening: `web-host-provisioner-parity-mutation` 360→720,
  `workspaces-boot-unlock` 900→1200, `infra-config-repush-mutation`/`zot-pull`→720,
  `run-registered-suites.test.sh`→540 (`run-registered-suites.sh:615-677`).
- Shared-state audit (fresh sweep across the execute set): docker names and image
  tags are all `$$`-scoped (`soleur-plugin-seed-test-$$`, `pu-tierb-$$`,
  `soleur-luks-gate-probe:$$`); the only host port bind is `sshd -p 2222` INSIDE a
  docker netns (`git-data-ownership.test.sh:326`); HOME writes are fixture-scoped
  (`HOME="$d/home"`); terraform work happens in per-run copies. **Live residual
  sites:** `git-data-rung2-rehearsal.test.sh` hardcoded `/tmp/rung2` (lines ~905,
  1106, 2068-2077, 2426 — TMPDIR-ignoring, shared across concurrent invocations);
  `ci-deploy.test.sh:6462` `mktemp -u`; `verify-tunnel-ingress-origin-infradir
  .test.sh:40` `mktemp -u`; `sandbox-masked-proc-docker.test.sh:725,728`
  `/tmp/c4-status.json` (PRIVILEGED — derived, not executed by this runner).

### Applicable learnings

- `2026-08-10-pipe-buf-atomicity-does-not-apply-to-the-file-i-was-redirecting-into.md`
- `2026-10-18-a-bound-sized-from-one-contended-sample-was-1-12x-not-1-35x.md`
  (bound sizing needs ≥1.5x headroom, not a single contended sample)
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  (mutation matrix + must-PASS rows before the guard)
- `2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill...`
- Prior arm's archived spec `specs/archive/20260811-022448-*/{tasks,session-state}.md`
  — hypothesis table, Split Trigger, rejected width derivation, Phase 3/4 leftovers
  this plan completes.

### Related issues/PRs

#7376 (this), #7432 (soak tracker — out of scope), #7554 (`.meta` forge — out of
scope), #7307, #7374, #7423, #7429, #9554, #10459, #9217 (grep-q series umbrella),
#7076 (derivation), #7004 (scratch root), #6789/#7545/#8579 (contention lib).

### Conventions

- Runner must stay single-file-self-contained (ADR-177 §A3): its test suite copies
  the SUT to a pristine file and runs a python single-file mutator — no `source` of
  external libs inside `run-registered-suites.sh`.
- `PASS <path>`/`RED  <path>` byte shape and the summary line are pinned by
  `run-registered-suites.test.sh` T6v and
  `plugins/soleur/test/main-health-monitor-workflow.test.sh` — do not touch.
- New `*.test.sh` under `apps/web-platform/infra/` is auto-registered by presence
  (ADR-252) and must be registered in `infra-validation.yml` per the registration
  gate (`.github/scripts/test/test-infra-suite-registration.sh`).

## Problem Statement

`run-registered-suites.sh` is open-ended under its default `-P 4`: the flake was
real, the observability gap that hid it is closed, and the proximate mechanism
(`producer | grep -q` early-exit under `pipefail`, contention only opening the
scheduling gap) was removed and guarded. The issue remains open because its own
fix criteria are unfinished: nobody has established which of the two remaining
candidate classes — shared-state collisions vs resource exhaustion — can still
produce a non-deterministic RED, and the residual shared-state sites were never
swept. This plan finishes the audit, namespaces the sites that provably race,
pins them against regression, and records the attribution + evidence ledger so
the verdict is written where the next flake investigator looks.

## Hypotheses & Verdicts (carried forward from the prior arm, re-measured)

| ID | Hypothesis | Verdict | Evidence |
|----|-----------|---------|----------|
| H1 | `producer \| grep -q` early-exit under `pipefail` → SIGPIPE/141 or false-miss | **CONFIRMED as the proximate mechanism; FIXED + guarded** | `grep-q-pipe-guard.test.sh` header + FILES_7376 comment ("the three suites whose 2026-10-05 flakes were this same mechanism"); #9554 removed the production population; derived zero-sweep green today |
| H2 | OOM / shim kill (a wrapping `bash -c` dies, no `.meta`) | **UNPROVEN — no occurrence observed** | zero UNACCOUNTED in the soak window; instrument now sees this shape (xargs rc 125 + UNACCOUNTED naming) so any future instance is attributed by construction |
| H3 | Shared-state collision between concurrent suites | **AUDITED — residual set is two `mktemp -u` races + one TMPDIR-ignoring write** | full sweep this session: docker names/tags `$$`-scoped, only host port is inside a netns, HOME fixture-scoped, terraform work in per-run copies; live sites listed in Evidence ledger |
| H4 | CPU/disk contention → suite exceeds its bound (rc=124) | **CONFIRMED class — mitigated by `_SUITE_BOUNDS` widening** | bound-kills recorded in `_SUITE_BOUNDS` comments (`run-registered-suites.sh:615-677`); renders as a named RED, tune per-suite at ≥1.5x worst observed (learning 2026-10-18) |

The issue's own "which is it" is therefore: the recorded flakes were H1
(contentment-opened); the residual shared-state surface is a small audited set
(this plan's Phase 2); resource exhaustion in the OOM sense is unproven and now
self-attributing if it ever fires. Exit-code-first attribution for any future
RED: `rc=124` → H4 (bound/contention); signal-shaped or UNACCOUNTED → H2
(kill/OOM-candidate); marker `FAIL` → real defect or H3.

## Proposed Solution

1. Namespace the three audited sites (per-run-scoped, provable-by-reading — the
   same "ships without a measurement gate" convention the prior arm used for its
   Phase 2).
2. Add a namespacing T-case inside `run-registered-suites.test.sh` asserting zero
   `mktemp -u` / positional-`/tmp` mktemp templates across the derived execute set.
3. Record the attribution table + rejected memory-cap ruling where the next
   investigator reads it: the runner's header comment and one clause in ADR-133.
4. Post the evidence ledger to #7376 at ship time (soak-run ids, leg corpus,
   per-hypothesis verdicts) — the issue's "establish which" deliverable.

Explicitly NOT in scope: `JOBS`/`-P` width changes (no OOM evidence exists;
deterministic class-serialisation is the ruled arm if kill-class evidence ever
lands — `decision-challenges.md`), the `JOBS: 1` pins (#7432 owns them), `.meta`
forge/erase (#7554), workflow edits, new suite files.

## Implementation Phases

### Phase 1 — Namespacing fixes

- `apps/web-platform/infra/verify-tunnel-ingress-origin-infradir.test.sh:40` —
  `MARKER="$(mktemp -u)"` → `MARKER="$(mktemp)"`. The stub `touch`s the marker;
  `touch` on an existing file is the same observable behaviour, and `mktemp`
  creates it atomically — the TOCTOU window closes without changing semantics.
- `apps/web-platform/infra/ci-deploy.test.sh:6462` — `st=$(mktemp -u)` → derive
  the state path from the already-unique `pf` (`st="${pf}.state"`) or an owned
  `mktemp -d` dir; implementer picks whichever reads cleaner in context. The
  property is "name unpredictable and unclaimed", not "name absent".
- `apps/web-platform/infra/inngest-redis-luks.test.sh:176` — `/tmp/.ilt-block.$$`
  → `"${TMPDIR:-/tmp}/.ilt-block.$$"` (keeps `$$` suffix; the `:-/tmp` fallback
  keeps a standalone, non-runner invocation working). `$$` already prevents
  collision; the fix makes it honour the runner's disk-backed session root and
  its cleanup.

### Phase 2 — Namespacing guard (T-case in `run-registered-suites.test.sh`)

- Derive the execute set the same way the runner does (`git ls-tree` glob, or
  invoke `--enumerate`), then `git grep` the set for: (a) `mktemp` with `-u`
  **including the long form `--dry-run` (its `-u` alias — found at SpecFlow)**;
  (b) `mktemp` with a positional `/tmp` template — assert zero hits outside a
  marker convention (`# tmpns-exempt: <reason>` for the one or two legitimate
  demos, if any). The guard prints each exempted file:line with its reason
  token, so exemption growth is a visible diff, not a silent absorb. Vacuity:
  assert the derived set is non-empty AND the pattern family matches a planted
  fixture (fixture dir via `SOLEUR_INFRA_DIR` seam or a synthesized hit line)
  so "0 checked → PASS" is impossible.
- Keep the pattern tight: do NOT attempt a "no bare `/tmp` writes" assertion —
  container-heredoc and workflow-contract `/tmp` uses are legal and numerous
  (audit found ~11 files); a line search cannot see the container boundary.

### Phase 3 — Record

- Runner header: add a short `ATTRIBUTION (#7376)` paragraph beside
  `DIAGNOSTICS ON RED` — the H1–H4 table's verdict lines + the exit-code-first
  rule. Comment-only, no behaviour.
- `knowledge-base/engineering/architecture/decisions/ADR-133-*.md`: append one
  clause — the memory-derived `JOBS` cap is a *rejected* alternative
  (irreproducible width + self-masking evidence); deterministic
  class-serialisation is the evidence-gated arm.
- Ship-time: `gh issue comment 7376` with the evidence ledger (this plan's
  `### Evidence ledger` verbatim, updated with any new soak runs), and note in
  the PR body which criteria are met and which remain observation-gated.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.test.sh` — `mktemp -u` fix (Phase 1)
- `apps/web-platform/infra/verify-tunnel-ingress-origin-infradir.test.sh` —
  `mktemp -u` fix (Phase 1)
- `apps/web-platform/infra/inngest-redis-luks.test.sh` — `/tmp` → `$TMPDIR` (Phase 1)
- `apps/web-platform/infra/run-registered-suites.test.sh` — namespacing T-case (Phase 2)
- `apps/web-platform/infra/run-registered-suites.sh` — header attribution block (Phase 3)
- `knowledge-base/engineering/architecture/decisions/ADR-133-*.md` — one clause (Phase 3)

## Files to Create

None. (The guard is a T-case inside the existing runner suite — no new suite
file, so no `infra-validation.yml` registration is needed.)

## Alternative Approaches Considered

| Option | Verdict |
|--------|---------|
| Memory-derived `JOBS` cap (issue's proposal) | Rejected — CTO ruling 2026-10-20: auto-derived width varies per run/host, makes the flake irreproducible and self-masking; single-file-SUT constraint bars sourcing the existing capacity lib |
| Deterministic class-serialisation of heavy suites | Held as the evidence-gated arm — ships only if kill-class (H2) evidence lands; no such evidence today |
| New standalone namespacing-guard suite | Rejected — a T-case inside `run-registered-suites.test.sh` keeps the audit beside the set it quantifies over and avoids a new registration |
| Bare-`/tmp` write prohibition guard | Rejected — container-heredoc and workflow-contract `/tmp` writes are legal; a line search cannot see the boundary |
| Fix `/tmp/rung2` (workflow contract) | Rejected — the path is `.github/workflows/git-data-rung2-rehearsal.yml`'s contract; the suite's arms already serialize internally; CI jobs are one-per-runner so no collision exists |
| Mandatory local `taskset` n≥20 battery | Rejected — CPU-only bound; a local non-reproduction establishes nothing (prior arm's recorded caveat) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a returning non-deterministic
  CI flake that the monitor files as a wrong-cause P1 (`ci/main-broken`), or a
  namespacing regression that re-opens a cross-suite race no gate reports —
  the operator pays a phantom-debug cycle, not a product-visible failure.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing — the diff touches test fixtures, a guard T-case, and comments; no
  credentials, no user data, no production path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal test-harness hygiene; the
  blast radius is CI signal quality, not a user-facing surface.
- `threshold: none, reason: test-harness namespacing + guard + comments only;
  no user-facing surface, credentials, or regulated data`.

## Observability

```yaml
liveness_signal:
  what: "main-health-monitor infra step runs the full runner at default -P; verdict on the SOLEUR_MAIN_HEALTH annotation + the `=== registered infra suites:` tally line"
  cadence: "~4x/day (scheduled) + workflow_dispatch dry runs"
  alert_target: "P1 `ci/main-broken` issue filed by the monitor"
  configured_in: ".github/workflows/main-health-monitor.yml (infra step); scripts/followthroughs/jobs1-stopgap-7432.sh (12-run soak probe on #7432)"
error_reporting:
  destination: "monitor-filed GitHub issue (P1) + ::error annotations per RED suite"
  fail_loud: "`RED <path>` / `UNACCOUNTED <path>` lines + exit contract (1 / 128+N); retained per-suite log dir path printed on any non-green"
failure_modes:
  - mode: "suite exceeds its per-suite bound under contention (H4)"
    detection: "rc=124 .meta → named `RED <path>` + ::error bound annotation"
    alert_route: "monitor P1 naming the suite"
  - mode: "wrapping shim killed (H2 OOM-candidate)"
    detection: "no .meta → UNACCOUNTED naming + xargs rc 125 reported"
    alert_route: "monitor P1; accounting assertion exits 1"
  - mode: "shared-state collision / real defect (H3/real)"
    detection: "marker-anchored bounded dump of the suite's own FAIL lines"
    alert_route: "monitor P1 + leg artifact log"
logs:
  where: "per-suite `.log/.meta/.trow` under $SOLEUR_SUITE_LOGDIR (retained on non-green); Actions step log + leg artifacts"
  retention: "retained dir until 12h self-reap on the dev box; CI leg artifact retention"
discoverability_test:
  command: bash apps/web-platform/infra/run-registered-suites.sh --list
  expected_output: "registered infra suite"
```

## Guard Contract

### Guard 1 — tmpdir-namespacing T-case (inside `run-registered-suites.test.sh`)

**Property.** No suite in the derived execute set resolves a scratch path by
unpredictable-name guesswork or a TMPDIR-ignoring absolute path: zero `mktemp`
with `-u` and zero `mktemp` with a positional `/tmp` template, outside marker
exemptions.

**Assembly.** The execute set as the runner itself derives it — `git ls-tree -r
--name-only HEAD -- $SOLEUR_INFRA_DIR` filtered to `*.test.sh` minus the
PRIVILEGED_WHY basenames (the same chokepoint every dispatched suite flows
through; a suite added on disk next month is in the population without an edit).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add `st=$(mktemp -u)` to a compliant suite (fixture root) | RED |
| 2 | Add `mktemp -d /tmp/fixed.XXXX` (positional `/tmp` template) to a second suite after a compliant first | RED |
| 3 | Neuter the guard's own dispatch — make the derive/`--enumerate` call return an empty set or corrupt the pattern so it can never match | RED (the vacuity floor: non-empty-set assertion + planted-hit fixture) |
| 4 | Exempt a suite with a bare `mktemp -u` via the `# tmpns-exempt:` marker | must-PASS (marker honoured, non-canonical form tolerated) |
| 5 | A suite using `mktemp -d -p "$TMPDIR"` and a docker-heredoc `/tmp` payload | must-PASS (the shapes the audit proved legal) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Whether the failures are resource exhaustion (memory/CPU/fd/disk under -P 4 on a 4-core box) or genuine shared-state collisions between suites" | Hypotheses & Verdicts table + Phase 3 record + AC4 | mapped |
| 2 | "If shared state: which suites collide, and give each a per-run-scoped namespace" | Phase 1 (three audited sites) + Phase 2 guard | mapped |
| 3 | "If resource exhaustion: cap -P by available memory rather than by core count" | Evidence-gated: no OOM/kill-class evidence exists today (H2 unproven; H4 owned by `_SUITE_BOUNDS`). The memory-cap mechanism is rejected by CTO ruling (decision-challenges.md); deterministic class-serialisation is the ruled arm if evidence lands | mapped — resolved as established-not-triggered |
| 4 | "make the runner report *why* a suite failed" | Already shipped by #7423 (instrument + accounting) — verified live on run 39345015242 | mapped — pre-satisfied, verified not re-done |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 namespacing fixes | "give each a per-run-scoped namespace" | asked |
| Phase 2 guard T-case | — | inferred — justification: a fixed race regressing silently is the rot class this repo's FILES_7376/SWEEP_DEFERRALS convention pins; the audit's result must not be able to rot |
| Phase 3 attribution record (runner header + ADR-133 clause + issue comment) | "What a fix would need to establish" / "establish WHICH it is" | asked |
| No `JOBS`/width change | — | inferred — justification: no kill-class evidence exists; width derivation was rejected by recorded ruling |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 6 | Estimated changed lines: ~120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/test-harness change.
Product/UX mechanical scan of Files to Edit/Create: no `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx` → override did not fire; tier NONE.

## Open Code-Review Overlap

- `#7098` (ci: audit the 56 `run:` bodies whose `set` omits -e…) mentions
  `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`. **Acknowledge** —
  different concern (`set -e` posture of workflow `run:` bodies vs this plan's
  namespacing); the file is not in this plan's Files to Edit. Remains open.
- No other open `code-review` issue body names a planned file. Checked
  2026-10-20 against `gh issue list --label code-review --state open`.

## Acceptance Criteria

- [ ] AC1: the namespacing T-case's zero-hit assertion passes — i.e. zero
  *executed* `mktemp -u` / positional-`/tmp` mktemp sites across the derived
  execute set. (A raw `git grep` absence AC would false-fail:
  `workspaces-luks-g4-mutation.test.sh:939` legitimately carries `mktemp -u`
  inside a string payload inspecting its SUT — the guard's comment/payload
  handling is the correct verifier.)
- [ ] AC2: `inngest-redis-luks.test.sh` contains no bare `/tmp/` write outside
  `$TMPDIR` — `git grep -n '/tmp/' -- apps/web-platform/infra/inngest-redis-luks.test.sh`
  returns only string/payload/context lines, no executed write.
- [ ] AC3: the namespacing T-case inside `run-registered-suites.test.sh` exists,
  is executed by the suite, and each mutation-matrix row (1–5) produces its
  expected verdict — including the vacuity floor row.
- [ ] AC4: `run-registered-suites.sh` carries an attribution block naming the
  four hypothesis verdicts and the exit-code-first rule; `ADR-133-*.md` carries
  the rejected-width clause; an evidence comment was posted to #7376.
- [ ] AC5: `JOBS` computation unchanged (`run-registered-suites.sh:750` still
  `min(nproc,6)`); no workflow file modified; no new suite file created.
- [ ] AC6: `bash apps/web-platform/infra/run-registered-suites.test.sh` green;
  `bash scripts/test-all.sh` green (or the affected-lane equivalent that covers
  all five touched files, per `wg-after-a-pr-merges` conventions).
- [ ] AC7: PR body + issue comment state what was established, per hypothesis,
  including that H2 remains unproven-by-absence and the soak verdict is owned by
  #7432's probe.

## Test Scenarios

- Given the suite `verify-tunnel-ingress-origin-infradir` runs, when its stub
  `doppler` executes, then `touch "$MARKER"` hits a file `mktemp` created —
  marker observed, suite green, no predictable-name window. (`unit`/integration
  within the suite itself)
- Given `ci-deploy.test.sh` runs `assert_zot_dark_is_terminal`, when
  `CI_DEPLOY_STATE` is set, then the path is derived from the `mktemp`-created
  `pf` (unpredictable, unclaimed) and the case still reaches its assertions.
  (`unit`)
- Given a fixture suite dir containing a `mktemp -u` line, when the namespacing
  T-case runs, then it reports the file+line and fails. (`unit`)
- Given a fixture suite dir where the derivation returns zero files or the
  pattern is corrupted, when the T-case runs, then it fails loudly rather than
  passing on "0 checked". (`unit`)
- Given an exempt-marker line and a docker-heredoc `/tmp` payload, when the
  T-case runs, then both stay green. (`unit` — must-PASS control)

## Architecture Decision (ADR/C4)

ADR-133 (`knowledge-base/engineering/architecture/decisions/ADR-133-*.md`) is
amended in this PR — one clause recording that a memory-derived `JOBS` cap is a
rejected alternative for the parallel-runner capacity question (irreproducible
width + self-masking evidence + single-file-SUT constraint) and that
deterministic class-serialisation is the evidence-gated arm. Same single-clause
precedent the prior arm used. No new ADR; no C4 impact (checked: the change
adds no external actor, external system, container, or access relationship —
the runner, suites and monitor are all already modeled).

## Context

- Prior arm: `knowledge-base/project/specs/archive/20260811-022448-*/` (plan
  `plans/archive/20260811-002501-2026-08-10-fix-infra-suite-runner-parallel-flake-plan.md`)
  — its deferred Phase 3/4 work is completed here by audit + evidence rather
  than by a local battery.
- Technical rulings: `knowledge-base/project/specs/feat-one-shot-7376-suite-flake/decision-challenges.md`
  (CTO rulings executed inline — `Reviewed-Coverage: sequential-fallback`; no
  spawn tool on this harness).
- Soak probe (not owned here): `scripts/followthroughs/jobs1-stopgap-7432.sh`.

## References

- Issue: #7376 (OPEN); related: #7432, #7554, #9217, #9554, #10459, #7423, #7429
- Monitor soak runs observed: 39298929992 (clean), 39345015242 (`-P 4`, 179/180,
  1 deterministic tag-drift RED — allowlisted class, instrument attributed it)
