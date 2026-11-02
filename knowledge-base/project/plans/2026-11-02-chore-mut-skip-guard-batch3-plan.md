---
title: "chore: family remainder batch-3 — canonical-equality + seam-check + mutation-battery hardening across the 6 remaining MUT_SKIP-idiom alert guards"
date: 2026-11-02
slug: chore-mut-skip-guard-batch3
branch: feat-one-shot-11720-mut-skip-batch3
issue: 11720
lane: cross-domain
type: chore
---

## Overview

Batch-3 (final batch) of the #11720 family remainder: port the **shipped** guard-hardening convention — canonical-equality heredoc compare, `res_block()`/`param()` exactly-once block-scoped pins, `PRESENCE_ROWS`/`MUT_ROWS` named floors in the constructible pure-assignment window, `_red_verdict`/`mutate_red`/`mutate_green`/`mutate_floor_red`, decoy/comment-extraction mutation rows, and **workflow seam checks** — to the six remaining `MUT_SKIP`-idiom alert-guard suites under `apps/web-platform/test/infra/`, and promote all six in `scripts/guard-vacuity-floor.test.sh` (`PROMOTED_FILES` at the live :1096 site + `MIN_FIRING_SUITES` 65→71).

This batch: `bwrap-probe-rollback-alert.test.sh`, `faithful-canary-sandbox-alert.test.sh`, `ghcr-blocked-alert.test.sh`, `inngest-step-524-alert.test.sh`, `sandbox-alerts.test.sh`, `web-nic-guard-unpinned-url-alert.test.sh`. `registry-clientip-not-rfc1918-alert.test.sh` stays descoped (already carries a stricter gen-3 harness-marker model — a donor port would be a downgrade; verify-only). `inngest-cutover-flip-silent-alert.test.sh` is out of scope (a new file, absent from the issue's remainder list).

## Problem Statement / Motivation

The six suites still carry the pre-#11601 idiom documented in #11720 — measured per-file on this branch (2026-11-02):

- **Phantom heredoc spans hide every floor.** Each of the six files contains literal `<<-SQL` text inside scanned lines (awk extractor patterns, python mutation strings, shell-string needles, one `printf` fixture format). `guard-vacuity-floor.test.sh`'s `heredoc_lines_of` opens a `SQL`-tagged span at the first occurrence that never closes (no bare `SQL` terminator line exists in any of the six) — every floor `if` below it is invisible to `floor_lines_of`. **All six suites are currently not floor-bearing** — they appear in neither the covered population (387) nor the deferred ledger (47). The port's `<<[-]SQL` / `<<\x2dSQL` evasions are not optional polish; they are what makes the floors exist at all for the meta-guard.
- **Non-constructible floor tails.** All six use the donor's `[ -n "${MUT_SKIP:-}" ] && _floor=…` (or `[ -z … ] &&`) rebind — a non-assignment inside the window stops `build_mutant`'s backward slice → CONSTRUCTION, never FIRES. All six also write floor/ledger `if`s as one-line `if …; fi` with `exit 2` — unslicable (no standalone `fi`) and wrong exit class (floor trips must exit 1, verdict-class, for `mutate_floor_red` to grade rc=1).
- **Magic-literal and slack floors.** `inngest-step-524` carries `_floor=74` / `_floor=50` literals (50 presence + 24 mutation, hand-counted); `bwrap` carries `_floor=$((PRESENCE_ROWS + 21))` with `21` un-named; `ghcr`/`web-nic` name it `MUT_ROWS_EXPECTED` instead of `MUT_ROWS`.
- **Pre-convention battery grading.** Five files grade via inline `case "$want:$rc"` inside a 5-arg `mutate()`; `inngest-step-524` already uses `mutate_red` naming + rc=1-only grading but rows carry **no expected-FAIL fragment** (the "RED for the WRONG reason" class is uncovered) and S1/C1 controls are hand-rolled. None has `_red_verdict`, `mutate_green`, `mutate_floor_red`, or the `want=wrong` scorer control.
- **No seam checks.** None of the six asserts `MUT_SKIP` / `<PREFIX>_GUARD_*` literals absent from `infra-validation.yml` executable text. `ghcr` and `web-nic` already have `IV` axes + step-anchored registration pins; `bwrap`, `fcsb`, `inngest-524`, `sandbox` have no `IV` axis at all — the suite could be muted by an `env:` line and nothing would red.
- **Presence needles satisfiable by dead text.** All six pin via `sql_has`/`line_in`/`top_in`/`blk_in` needle greps over `LOCAL_SQL`/`SQL_N`/`ALERT`/`EXPL` — a `/* */`- or `#`-wrapped decoy copy satisfies the needle while the live body is gutted. None does canonical-equality compare or `res_block()`/`param()` exactly-once pins.

## Proposed Solution

Per file, apply the convention as it shipped in the batch-2 ports (donor-of-record: `egress-gw-alert.test.sh`; gen-2 origin `inngest-luks-key-probe-alert.test.sh`; batch-1 `inngest-luks-wrong-volume-alert.test.sh`):

1. **Phantom-span eviction FIRST.** Sweep every literal `<<-` in the file: `<<[-]SQL` in awk patterns / grep needles / comments, `<<\x2dSQL` inside python strings (renders `<<-SQL` at runtime — the egress-gw `PRELUDE` shape), and for shell-string needles / `printf` format text either compose the literal at runtime (`<<-${Z:-}SQL`, `<<$(printf %s -)SQL`) or move the fixture write into the python `MUT_PROG` heredoc where `\x2d` works. Verify zero remaining opener-regex matches before the floor work — otherwise the ported floor is born invisible.
2. **Canonical-equality compare** — keep each file's `LOCAL_SQL`/`SQL_N` (or `SQL_1`) extraction, add a `*_CANON` constant built from **derived** literals (never re-pinned literals), whitespace-normalized compare byte-for-byte. `sql_local()`/`res_block()`/`param()` ported from egress-gw :105-128 (with the `<<[-]SQL` opener already evaded). `param()` ERE covers the entire value line (the ternary-prefix trap); the documented residual gap (same-attr/different-value decoy) stays documented.
3. **`res_block()`/`param()` exactly-once pins + unanchored opener counts** — `name = <<[-]SQL` openers AND resource-block headers both census-counted; a decoy opener counts and reds.
4. **Constructible floor tail** — the six-line pure-assignment window, verbatim shape per egress-gw :624-636:

```bash
PRESENCE_ROWS=NN
MUT_ROWS=MM
_eff=${MUT_SKIP:+0}
_eff=${_eff:-$MUT_ROWS}
_floor=$((PRESENCE_ROWS + _eff))
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then
  printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2
  exit 1
fi
```

Every line inside the window is a pure assignment — no `[ -n ]` rebind, no comment, no `$(…)` rebind of a counter. Floor trip and ledger trip exit **1** (verdict-class); instrument failures stay exit **2**; each file's "instrument failures exit 2" comment is rewritten to say so. Constants sit ADJACENT to the floor block at column 0 (the `mutate_floor_red` sed anchor is `^PRESENCE_ROWS=[0-9]+$`).
5. **Battery ported to `_red_verdict`/`mutate_red`/`mutate_green`/`mutate_floor_red`** — scratch-copy mutation into `MUT_DIR`, pristine-child control (all six already carry it — keep), `env "P_GUARD_${which}=$copy"` indirection where the file lacks it (inngest-524's explicit per-axis arms → indirection), inner log captured to `$olog` (inngest-524's `>/dev/null` → olog), per-row expected-FAIL fragments (inngest-524's fragment-less signature gains the `$4` tag arg), rc discrimination via `_red_verdict` (rc=1 → red/wrong by fragment, rc=0 → survived, else unresolved), `want=wrong` scorer control row, `mutate_green` must-PASS rows (TF-scoped), `mutate_floor_red` on `^PRESENCE_ROWS=[0-9]+$`.
6. **Decoy/comment-extraction class rows** — decoy heredoc with gutted live body, `/* */`-wrapped decoy blocks, commented pinned lines, inline tautology, `$$` escapes — each row driven RED by `mutate_red` with its own fragment.
7. **Workflow seam checks (the shipped replacement for the issue's "env -u" wording)** — `IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"` comment-stripped view; assert `MUT_SKIP` and the suite's own `*_GUARD_*` literals absent; assert the suite's own `run: bash …` line registered exactly once (ghcr/web-nic keep their stronger step-anchored wiring pins — ADD the literal-absence check; bwrap/fcsb/inngest-524/sandbox gain the whole block including a new `<PREFIX>_GUARD_IV` axis and `IV)` dispatch arm); IV mutation rows prove the seam red (env: insertion, GUARD literal, dropped run line). **No `env -u` run lines are added** — literal `env -u` self-reds `registry-clientip`'s `suite-seam-in-workflow` pin (:479) and the byte-exact run-line pins in `web-nic`/`ghcr`.
8. **Meta-guard promotion of ALL SIX ported files (uniform — the batch-2 ruling extended)** — each ported floor verified FIRES-classified, then: (a) a `PROMOTED_FILES` regex entry at the LIVE site (`scripts/guard-vacuity-floor.test.sh:1096` — the LAST of four assignments; :798/:811/:819 are stale snapshots; dots escaped), (b) the grounds comment paragraph every sibling entry carries, (c) `MIN_FIRING_SUITES` 65→71 per the hand-ratchet comment convention naming each addition.

## Technical Considerations

- **Deviation from issue wording, recorded (unchanged from batch-2):** the issue prescribes "`env -u MUT_SKIP -u <axes>` on each file's run line". The shipped convention is the strictly-stronger per-suite seam check (covers step `env:`/`shell:`/`working-directory:`/job-env redirects). This plan ports the shipped convention; the issue's words are superseded. Batch-2's PR merged 2026-11-02 with zero `env -u` — run lines stay plain `run: bash …`.
- **`mutate_green` is TF-only in the references** — keep green rows TF-scoped unless a helper is deliberately widened.
- **Floor constants are two write sites** — `mutate_floor_red`'s sed anchor must track the declaration; grep every occurrence of the constant literal after each bump (2026-10-31 postmortem).
- **inngest-524's presence count is discovery-coupled** — the suite discovers explorations per section and refuses <3; its `74 = 50+24` accounting assumes the current 2-discovered shape. The ported `PRESENCE_ROWS` pins the CURRENT real count; a future alert that grows the section is exactly the drift the floor exists to red (same ratchet semantics as siblings — raise both constants in the edit that adds the row). The `<3 discovered` refusal stays a separate pin.
- **Serial CI runtime** — measured on this branch: bwrap 4.5s, fcsb 7.1s, ghcr 15.9s, inngest-524 3.3s, sandbox 30.0s, web-nic 2.8s (~64s total today). New decoy/seam/floor rows add a few seconds each (est. +30-60s). `deploy-script-tests-fixed` runs serially under `timeout-minutes: 15` (`infra-validation.yml:854`); measure the leg on-branch; bump only if approaching ~12 min (precedent `:692`/`:705`).
- **`assert_fixture_dir` parity** — all six blocks are byte-identical to egress-gw's today (md5-verified); keep them byte-identical or the P1b parity suite reds.
- **No registry changes for suite discovery** — named steps in `infra-validation.yml`; `lint-orphan-test-suites` unaffected (no renames). `apps/web-platform/infra/lib/mutation-scorer.sh` NOT adopted (registry obligation, zero convention gain).
- **Shared SUT baseline** — all six pin `betterstack-logs-alerts.tf` + `apply-web-platform-infra.yml` (plus per-file emitters: `ci-deploy.sh`, `cloud-init-registry.yml`, `vector.toml`, `cc-dispatcher.ts`, `sandbox-startup-classifier.ts`, `web-private-nic-guard.sh`, runbooks). An in-flight `.tf` PR can invalidate canons mid-batch — re-probe at Phase-7 sync (#11653 precedent).
- **Merge-queue landmines carried forward** — `enqueuePullRequest` rejects until the required `test` check-run is CREATED on the head; KB artifacts archived inside the PR (`archive-kb.sh`); queued branches reject pushes; no backticks/`$$` in mutation labels; no `| grep -q` pipelines (grep-q-pipe-guard); doppler-config-inventory.txt staleness is main-owned (never bump in this PR — currently fresh, stamped 2026-11-02).

## Research Insights

**Premise Validation (Phase 0.6):** #11720 OPEN (title: "chore: family remainder — canonical-equality + decoy/mute-knob hardening + env -u pins across the remaining MUT_SKIP-idiom alert guards"; the issue deliberately stays open across batches). All six target files exist; both batch-1 donors + all four batch-2 files exist on this worktree's base; `scripts/guard-vacuity-floor.test.sh` exists (live `PROMOTED_FILES=` at :1096 — NOT :1089, batch-2's four additions moved it; `MIN_FIRING_SUITES=65` at :1426). `grep -l MUT_SKIP` census = 14 files = 6 batch-3 + 4 batch-2 + 2 batch-1 + registry-clientip (descoped) + inngest-cutover-flip-silent (out of scope). `env -u` never landed on `infra-validation.yml` — run lines are plain `run: bash` at :934/:941/:948/:976/:989/:1001. Collision-precheck: PR #11885 is THIS branch's own WIP placeholder (no collision); two `test-all.sh` processes in the unrelated `feat-prod-readiness-gap-analysis` worktree (informational). Stale premise reconciled: the issue's "env -u" wording predates the shipped seam-check convention (batch-2 ruling).

**Property List (Phase 0.6b):** (a) a presence needle cannot be satisfied by dead text; (b) the mutation battery cannot be halved or redirected by an env axis; (c) each guard's own dispatch is proven non-vacuous (constructible floor + instrument control); (d) CI-level muting is barred structurally, not by convention; (e) each ported floor is VISIBLE to the meta-guard (no phantom heredoc span) — a batch-3 addition since all six are phantom-hidden today. **Cut List:** shared `test/infra/lib/` helper (cut by the issue + both prior plans); `mutation-scorer.sh` adoption; `env -u` run lines (superseded, self-reds sibling pins); registry-clientip rewrite (gen-3 downgrade); inngest-cutover-flip-silent (not in remainder).

**Key learnings applied (batch-2 compound-learnings, verbatim load-bearing):** phantom `<<-` spans hide floors (evasion: `<<[-]SQL` awk/grep/comments, `<<\x2dSQL` python); `build_mutant` needs standalone column-0 `fi`; the `[ -n ] &&` floor rebind is unconstructible (use the `_eff=${MUT_SKIP:+0}` pure-assignment window); backticks/`$$` in mutation labels execute shell; `PRESENCE_ROWS`/`MUT_ROWS` are real call-site counts recomputed after edits; `param()` counts value-matching lines not attr occurrences (documented residual gap); emitter-rename mutations grade FATAL-2 not RED; floor trips exit 1 / instruments exit 2.

**Relevant files:** donor-of-record `apps/web-platform/test/infra/egress-gw-alert.test.sh` (batch-2 shipped: `sql_local`/`res_block`/`param` :105-128, `IV_CODE` seam :347-363, `_red_verdict`/`mutate_red`/`mutate_green`/`mutate_floor_red` :408-485, constructible floor :624-641, `<<\x2dSQL` PRELUDE :389-404); meta-guard `scripts/guard-vacuity-floor.test.sh` (heredoc_lines_of :127-146, floor_lines_of :187-211, COVERED_DIRS :244, DEFERRED_DIRS :257, PROMOTED_FILES live site :1096 + stale :798/:811/:819, membership pin ~:1404, MIN_FIRING_SUITES :1426); workflow `.github/workflows/infra-validation.yml` (six run lines :934-1001, `deploy-script-tests-fixed` timeout :854); batch-2 archive `knowledge-base/project/specs/archive/20261102-113422-feat-one-shot-11720-mut-skip-remainder/` + plan `knowledge-base/project/plans/archive/20261102-113422-2026-11-02-chore-mut-skip-guard-remainder-plan.md` (authoritative port contract this plan extends).

**Measured meta-guard baseline (this branch, 2026-11-02):** `repo-wide floor-bearing 434`, `covered 387`, `deferred 47` (`fires 31`, `construct 16`, `nofire 0`), `fires 370`, `construct 17`, `MIN_FIRING_SUITES=65`, 25/25 green. All six batch-3 files are in NONE of these populations (phantom-hidden → not floor-bearing).

**Suite runtimes measured (this branch):** bwrap 4.5s / fcsb 7.1s / ghcr 15.9s / inngest-524 3.3s / sandbox 30.0s / web-nic 2.8s.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — a vacuous alert-guard suite is a false-green CI signal; user impact is indirect (a silently-weakened drift alert on the ops fleet).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure — test files only, synthesized fixtures, no credentials or user data in scope.
- **Brand-survival threshold:** none
- threshold: none, reason: diff is confined to `apps/web-platform/test/infra/` guard suites, the meta-guard `PROMOTED_FILES`/`MIN_FIRING_SUITES` ledger, and at most a `timeout-minutes` bump in `infra-validation.yml` — no production code, auth, data, payment, or user-owned resource surface.

## Observability

```yaml
liveness_signal:    # the six ported suites run as named serial steps in deploy-script-tests-fixed on every infra-touching PR; cadence per-push; alert_target = the required "test" aggregator leg; configured_in .github/workflows/infra-validation.yml
error_reporting:    # suite [FAIL] lines + non-zero exit → red named step → fail-closed deploy-script-tests-done aggregator (infra-validation.yml:~1345-1414); fail_loud = yes
failure_modes:      # [{mode: vacuous port (assertion count below floor), detection: per-suite _floor + ledger conservation + mutate_floor_red, alert_route: red step}, {mode: floor invisible to meta-guard (phantom heredoc span), detection: PROMOTED_FILES membership pin reports not-floor-bearing, alert_route: red meta-guard suite}, {mode: floor drift across files, detection: guard-vacuity-floor n_deferred/PROMOTED_FILES ledger, alert_route: red meta-guard suite}, {mode: CI-level muting via env axis, detection: per-suite workflow seam-check row, alert_route: red suite step}, {mode: serial-leg timeout, detection: aggregator cancelled-classifier names the timeout shape, alert_route: red leg}]
logs:               # stdout in the infra-validation job log on GitHub Actions; GH retention default
discoverability_test:
  command:          bash -c 'grep -cE "^PRESENCE_ROWS=[0-9]+" apps/web-platform/test/infra/ghcr-blocked-alert.test.sh'
  expected_output:  "1"
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Port the canonical-equality SQL compare + `res_block()`/`param()` exactly-once block-scoped pins + `VAR_BLOCK`-style opener counts + `PRESENCE_ROWS`/`MUT_ROWS` constants + `_red_verdict`/`mutate_green`/`mutate_floor_red` (each port needs its own mutation-matrix rebaseline)." [issue #11720] | Phases 1–4 per-file ports; FR-1 | mapped (6 of 6 remaining this batch) |
| 2 | "Add the comment/decoy extraction class rows: decoy heredoc with gutted live body, `/* */`-wrapped decoy blocks, commented pinned lines, inline tautology, `$$` escapes." [issue #11720] | Per-file mutation batteries; FR-2 | mapped |
| 3 | "`env -u MUT_SKIP -u <suite's own *_GUARD_* axes>` on each file's `infra-validation.yml` run line (verify the override names against each suite's header)." [issue #11720] | Workflow seam-check rows inside each ported suite; FR-3 | mapped — mechanism superseded by shipped seam-check convention (deviation recorded; batch-2 ruling) |
| 4 | "Promote each ported file: add it to PROMOTED_FILES in scripts/guard-vacuity-floor.test.sh and ratchet MIN_FIRING_SUITES (+6 expected → 71, but measure …)" [batch-3 args] | Phase 5 meta-guard promotion; FR-4 | mapped |
| 5 | "`apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh`" [issue #11720 remainder list] | — | descoped — gen-3 harness-marker model already stricter (AC5 verify-only) |
| 6 | "`inngest-cutover-flip-silent-alert.test.sh` … NOT in batch-3 scope" [batch-3 args] | — | excluded — new file, not in the issue's remainder list |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| FR-1 per-file convention port | "Port the canonical-equality SQL compare + `res_block()`/`param()` exactly-once block-scoped pins" | asked |
| FR-2 decoy/comment-extraction rows | "Add the comment/decoy extraction class rows" | asked |
| FR-3 workflow seam-check rows | "`env -u MUT_SKIP -u <suite's own *_GUARD_* axes>` on each file's `infra-validation.yml` run line" — property behind the words: CI-level muting barred | asked (mechanism superseded — batch-2 ruling) |
| FR-4 six-file PROMOTED_FILES + ratchet | "add it to PROMOTED_FILES in scripts/guard-vacuity-floor.test.sh and ratchet MIN_FIRING_SUITES (+6 expected → 71, but measure)" | asked |
| Phantom-span `<<-` evasion sweep | "a literal `<<-TAG` ANYWHERE in scanned test text … opens a span … Evade: `<<[-]SQL` … `<<\x2dSQL`" | asked (args landmine list — made a first-class step because all six measured phantom-hidden) |
| Exit-class normalization (floor trips exit 1) | "each port needs its own mutation-matrix rebaseline" + `_red_verdict` (rc=1-only grading requires floor trips at verdict class) | inferred — required for `mutate_floor_red` to grade RED; batch-2 precedent |
| `<PREFIX>_GUARD_IV` axes for the four files lacking IV | "the suite's own `*_GUARD_*` axes" — seam check needs an IV axis to be mutation-pinnable | inferred — batch-2 precedent (REGSTORE_IV etc. added there) |
| On-branch runtime measurement + conditional `timeout-minutes` bump | — | inferred — added rows extend a serial leg under a 15-min ceiling; repo precedent `:692`/`:705` |
| `## Operator Holds` section | — | inferred — go.md Step 1.5 enforcement contract carries the epic's standing holds into the branch's plan file |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform` (test/infra), `scripts`
- Planned files: 7 | Estimated changed lines: ~2,000
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — estimated lines exceed 800; the split boundary IS the batch boundary (6 files this PR; #11720 closes when this merges). Advisory satisfied: this plan already IS the issue-guided split ("batching ≥2 per PR is fine when the .tf blocks are disjoint" — the six pin disjoint resource names: bwrap_probe_rollback / faithful_canary_sandbox_broken / ghcr_hostsfile_deny_lost / inngest_step_524 + claude_cost_daily_burn / agent_sandbox_bash_denial / web_nic_guard_unpinned_url). Proceed as single PR for the 6-file batch.

## Guard Contract

### Guard 1 — Per-suite canonical-equality + block-scoped pins (6 ported files)

**Property.** A dead-text copy (comment-, heredoc-, or `/* */`-wrapped) of any pinned literal can never satisfy the guard, and every pinned attribute is bound exactly once inside its resource block — weakening the alert definition in `betterstack-logs-alerts.tf`, `apply-web-platform-infra.yml`, or a per-file emitter (`ci-deploy.sh`, `cloud-init-registry.yml`, `vector.toml`, `cc-dispatcher.ts`, `sandbox-startup-classifier.ts`, `web-private-nic-guard.sh`) always turns the suite red.

**Assembly.** The `logtail_exploration`/`logtail_exploration_alert` resource blocks + `*_sql` locals each suite pins in `apps/web-platform/infra/betterstack-logs-alerts.tf`, its `-target=` legs in `apply-web-platform-infra.yml`, its emitter files, its own `run:` step text in `infra-validation.yml`, and the suite's own mutation battery. Chokepoints: `res_block()`/`param()` (block-scoped, exactly-once), the canon compare (whole extracted heredoc, whitespace-stripped), the per-suite opener census, and the per-suite `*_GUARD_*` env-axis set.

**Mutation matrix.**

| # | Edit (design-level) | Expected |
|---|---|---|
| 1 | Gut the live SQL body inside the `name = <<-SQL … SQL` block in the suite's target `.tf` local, leaving the declaration line | RED — canon compare fails |
| 2 | Add a `/* */`- or `#`-wrapped decoy copy of the pinned heredoc elsewhere in the `.tf` | RED — unanchored opener/param count exceeds 1 |
| 3 | Add a second `logtail_exploration_alert` resource carrying the suite's marker after a compliant first | RED — census/param cardinality |
| 4 | Weaken one `param()`-pinned attribute value inside the block | RED — param count drops to 0 |
| 5 | Delete the suite's mutation-row block from the suite itself (harness edit) | RED — `MUT_ROWS`/`_floor` accounting |
| 6 | Bump the suite's `PRESENCE_ROWS`/`MUT_ROWS` constant by 1 without adding a row (`mutate_floor_red`) | RED — floor fails on the real run |
| 7 | Instrument-failure disguised as caught mutation (suite exits 2 on unbound var) | SURVIVED-not-RED — rc≠1 cannot be credited; row reports wrong/unresolved |
| 8 | Reintroduce a literal `<<-` anywhere in the suite's scanned text (phantom span) | RED — PROMOTED_FILES membership pin reports not-floor-bearing |
| 9 | must-PASS: a legit `.tf` edit that changes the alert body AND the canon constant in the same PR | GREEN — canon moved with the thing it protects |

**Anchor.** The canon constant is derived from the same file it protects — a weakening that moves both in one diff is caught only by row 9's explicit must-PASS shape plus review; `PRESENCE_ROWS`/`MUT_ROWS` are two-write-site constants (declaration + `mutate_floor_red` sed anchor) — grep every occurrence after each bump.

### Guard 2 — Workflow seam checks (per ported suite)

**Property.** No `MUT_SKIP` or `<PREFIX>_GUARD_*` literal reaches `infra-validation.yml`'s executable text — CI can never mute or redirect a ported suite's battery.

**Assembly.** The `deploy-script-tests-fixed` job's executable surface in `.github/workflows/infra-validation.yml` (run lines, step `env:`/`shell:`/`working-directory:` keys, job env). Chokepoint: each ported suite's own seam-check row reading the workflow's comment-stripped code view (`IV_CODE`).

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Add `MUT_SKIP=1` to the suite's step `env:` in the workflow | RED — seam row |
| 2 | Add a `<PREFIX>_GUARD_*` literal to any run line in the job | RED — seam row |
| 3 | Guard's own seam-check row deleted from the suite (dispatch) | RED — `MUT_ROWS`/floor accounting drops |
| 4 | must-PASS: a comment line (`#`-whole-line) mentioning `MUT_SKIP` in the workflow | GREEN — comment-stripped view |

**Anchor.** The seam set is enumerated from each suite's own `*_GUARD_*` declarations — not a hand-typed list (the finite-list staleness learning).

### Guard 3 — six-file meta-guard promotion (uniform registration)

**Property.** Every ported file whose floor scores FIRES is registered in `PROMOTED_FILES` at the live write site — a silent floor deletion in any ported suite reds the membership pin.

**Assembly.** `scripts/guard-vacuity-floor.test.sh`'s LAST `PROMOTED_FILES=` assignment (:1096), its `MIN_FIRING_SUITES` ratchet (:1426), and the zero-slack membership pin (each entry must be floor-bearing + covered + FIRES).

**Mutation matrix.**

| # | Edit | Expected |
|---|---|---|
| 1 | Add a ported file to a stale `PROMOTED_FILES` site (:798/:811/:819) instead of :1096 | RED — file stays invisible to the membership pin (no-op detection: the entry must land in the live regex) |
| 2 | Register a ported file whose floor is CONSTRUCTION-classified (non-assignment in the window) or phantom-hidden (`<<-` literal in scanned text) | RED — membership pin reports `floor-does-not-fire` / not-floor-bearing |
| 3 | Delete or weaken a promoted suite's floor after registration | RED — `no-longer-floor-bearing` / `floor-does-not-fire` |
| 4 | must-PASS: six constructible floors + six live-site entries + `MIN_FIRING_SUITES` 65→71 | GREEN — counters move exactly as AC4 declares |

**Anchor.** The meta-guard ledger is the independently-checked registry — the diff edits both the suites and the ledger; the ledger's own suite certifies consistency.

## Domain Review

**Domains relevant:** Engineering, Operations — assessment carried forward from batch-2 (identical change class, wider file set); ran sequentially inline this session (Devin depth-1: subagents cannot spawn subagents — `Reviewed-Coverage: sequential-fallback`).

### Engineering (domain sweep — batch-2 CTO assessment carried forward)

**Status:** reviewed (sequential-fallback)
**Assessment:** Convention confirmed in-tree; adopt seam-check rows not `env -u` (literal `env -u` self-reds sibling pins); registry-clientip already gen-3 — verify-only; normalize instrument failures to `exit 2`, floor trips to `exit 1`; re-derive `PRESENCE_ROWS`/`MUT_ROWS` after the rename/port; measure serial CI leg. Batch-3 additions measured this session: all six floors phantom-hidden (evasion is load-bearing, not polish); four files need a new `IV` axis + `IV)` dispatch arm; inngest-524 is a middle-generation port (mutate_red exists but lacks fragments/expect grading).

### Operations (fail-closed second leader — batch-2 COO assessment carried forward)

**Status:** reviewed (sequential-fallback)
**Assessment:** Zero cost/procurement/vendor surface; suites are named serial steps under `timeout-minutes: 15` on GH-hosted runners, path-filtered to infra PRs; watch item — measure the leg on-branch, bump timeout if it approaches the ceiling (precedent `:692`); parity-pin obligation on byte-identical `assert_fixture_dir` helper blocks (md5-verified identical across all seven files today); census constants deliberately red future additions with instructive messages.

## Product/UX Gate

Not applicable — no user-facing surface; no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit. Mechanical override did not fire.

## Open Code-Review Overlap

- `#8735` (infra-validation notify-main-failure misses cancelled jobs) — **Acknowledge:** separate concern (notification path), orthogonal to seam-check/floor work. Remains open.
- `#7942` (two `*.mutation.sh` batteries in plugins/soleur/test run in no gate) — **Acknowledge:** different directory and battery shape; not in scope.
- No open code-review issues touch the six suite files, `scripts/guard-vacuity-floor.test.sh`, or `infra-validation.yml`.

## Files to Edit

- `apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh` — full port (phantom-evade 5 `<<-` sites; canon compare + `res_block`/`param`; `_floor=$((P+21))`/`&&`-rebind → named constants + constructible window; floor/ledger `exit 2`→`exit 1` + multi-line `if`; `mutate`→`mutate_red`/`mutate_green`/`mutate_floor_red` + `_red_verdict`; add `BWRAP_GUARD_IV` + `IV)` arm + seam check; decoy rows)
- `apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh` — full port (same shape + `SELF` axis preserved; `MIN_ASSERTIONS` one-line `if` → constructible window; add `FCSB_GUARD_IV`; existing `RED:2`→rc1 floor-red normalization folds into `_red_verdict` semantics)
- `apps/web-platform/test/infra/ghcr-blocked-alert.test.sh` — full port (phantom-evade 7 `<<-` sites; `MUT_ROWS_EXPECTED`→`MUT_ROWS` normalization keeping the `MUT_ROWS_RUN` conservation ledger; `IV` axis + registration pin already present — ADD the `GHCR_GUARD_`/`MUT_SKIP` literal-absence seam check + IV mutation rows)
- `apps/web-platform/test/infra/inngest-step-524-alert.test.sh` — deepest port (partial-gen: `mutate_red` exists WITHOUT expect-fragment arg → add `_red_verdict` + per-row fragments; explicit per-axis env arms + `>/dev/null` → `env "SPEND_GUARD_${which}=$copy"` indirection + `$olog`; `_floor=74`/`_floor=50` literals → named constants + constructible window; add `SPEND_GUARD_IV`; S1/C1 hand-rolled controls fold into `mutate_green`/`want=`-class or stay deliberate; H524/HBURN shell needles + s1.tf `printf` fixture need non-literal `<<-` composition)
- `apps/web-platform/test/infra/sandbox-alerts.test.sh` — full port (DISP/CLS server-TS emitter axes; add `SANDBOX_ALERTS_GUARD_IV`; canon + block pins; floor conversion; longest suite at 30s — added rows keep it under scrutiny for the serial-leg measure)
- `apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh` — full port (`MUT_ROWS_EXPECTED`→`MUT_ROWS`; `IV` present — ADD literal-absence seam + IV mutation rows; EM/RB/LQ axes preserved)
- `scripts/guard-vacuity-floor.test.sh` — `PROMOTED_FILES` entries for all six ported files at the live :1096 site (escaped dots) + grounds comments + `MIN_FIRING_SUITES` 65→71
- (conditional) `.github/workflows/infra-validation.yml` — `timeout-minutes` bump on `deploy-script-tests-fixed` (:854) ONLY if the measured leg approaches the 15-min ceiling; decided by the Phase-6 measurement, not pre-authorized

## Files to Create

- (none)

## Implementation Phases

1. **Phase 1 — bwrap-probe-rollback + faithful-canary-sandbox** (near-identical skeletons: same axis set {TF,WF,CI,RB}, same LOCAL_SQL/SQL_N/ALERT/EXPL/MAIN_PLAN extraction). Phantom-evasion sweep first; canon + block pins; constructible floor + exit-class conversion; battery port; `BWRAP_GUARD_IV`/`FCSB_GUARD_IV` + `IV)` arm + seam check; decoy rows; run each green + `MUT_SKIP=1` inner + `mutate_floor_red` grades RED.
2. **Phase 2 — ghcr-blocked + web-nic-guard-unpinned-url** (IV already present — no new axis; normalize `MUT_ROWS_EXPECTED`→`MUT_ROWS`; add literal-absence seam + IV mutation rows; phantom evasions at 7 + 3 sites).
3. **Phase 3 — inngest-step-524** (partial-generation port: keep `mutate_red` name, add fragment/expect arg + `_red_verdict`; env indirection + olog; literal floors → named constants; `SPEND_GUARD_IV`; discovery-coupled presence accounting per Technical Considerations; python-checker canon path differs — canon over the python-extracted SQL, not a `LOCAL_SQL` awk port by rote).
4. **Phase 4 — sandbox-alerts** (DISP/CLS server-TS surface — canon/block pins over `.tf` plus emitter pins over the two `.ts` files; 30s runtime is the serial-leg watch item).
5. **Phase 5 — meta-guard promotion.** `bash scripts/guard-vacuity-floor.test.sh` green; all six ported floors verified FIRES; six `PROMOTED_FILES` entries at the live :1096 site + grounds comments; `MIN_FIRING_SUITES` 65→71.
6. **Phase 6 — rebaseline + measure.** All six suites + `MUT_SKIP=1` inner runs green; registry-clientip byte-identical; affected-suites + meta-guard green; measure `deploy-script-tests-fixed` leg; conditional timeout bump; `lint-shell-capture-exit` baseline check; grep for residual literal `<<-` in all six files (must be zero outside the meta-guard's own evaded forms).

## Acceptance Criteria

- [ ] AC1: All six ported suites exit 0 green on the pristine tree and carry `PRESENCE_ROWS`/`MUT_ROWS` named constants whose `_floor=$((PRESENCE_ROWS + _eff))` equals the suite's real assertion count (verified by `mutate_floor_red` going red on +1).
- [ ] AC2: Each ported suite's mutation battery contains decoy/comment-extraction rows (decoy heredoc with gutted live body, `/* */`-wrapped decoy block, commented pinned line, inline tautology, `$$` escapes) each driven RED by `mutate_red` with a named expected-FAIL fragment, plus `mutate_green` must-PASS row(s) and a `want=wrong` scorer control.
- [ ] AC3: Each ported suite asserts `MUT_SKIP` and its own `*_GUARD_*` literals absent from `infra-validation.yml` executable text (seam-check row over `IV_CODE`), pins its own `run: bash …` registration, and carries IV mutation rows that prove the seam red; no `env -u` appears in the workflow; all six run lines remain plain `run: bash …`.
- [ ] AC4: All six ported floors classify FIRES and all six files are registered at the LIVE `PROMOTED_FILES` site (`scripts/guard-vacuity-floor.test.sh:1096`) with grounds comments + `MIN_FIRING_SUITES` 65→71. `bash scripts/guard-vacuity-floor.test.sh` exits 0 and its printed counters are diffed against the measured pre-port baseline (this branch, 2026-11-02): `covered 387`, `deferred 47` (`fires 31`, `construct 16`), `fires 370`, `construct 17`. Expected post-port movement: `covered` 387→393, `fires` 370→376, `deferred` 47→47 (all six phantom-hidden today → never in the ledger; promotion moves each into covered in the same diff). Any other movement is a finding.
- [ ] AC5: `registry-clientip-not-rfc1918-alert.test.sh` and `inngest-cutover-flip-silent-alert.test.sh` are byte-identical to pre-batch (`git diff` empty on both).
- [ ] AC6: The `deploy-script-tests-fixed` leg is measured on-branch and `timeout-minutes` is bumped only if the measurement approaches the 15-min ceiling.
- [ ] AC7: `assert_fixture_dir` blocks in ported files remain byte-identical to the canonical copy (P1b parity suite green).
- [ ] AC8: Every ported suite's floor tail is the constructible pure-assignment window (no non-assignment inside it) — verified by the meta-guard reporting each file FIRES, not CONSTRUCTION or invisible.
- [ ] AC9: Each ported suite's floor/ledger trip exits 1 and each instrument failure exits 2 — `mutate_floor_red` rows grade RED (not UNRESOLVED) on a +1 bump.
- [ ] AC10: No literal `<<-` opener-regex match remains in any of the six files' scanned text — verified by zero matches for the meta-guard's opener pattern `<<-?[[:space:]]*['"]?[A-Za-z_]` outside real heredocs that close at their own bare terminator (`<<PY`, `<<'ROWS'`).
- [ ] AC11: inngest-524's discovery refusal (<3 explorations) still fires; its S1/C1 controls (or their `mutate_green`/equivalent successors) still green/FATAL as designed.
- [ ] AC12: `mutate_green` rows are TF-scoped unless the helper is deliberately widened; a `want=wrong` negative-control row exists per battery.

## Test Scenarios

- `bash apps/web-platform/test/infra/<each-of-six>.test.sh` → `=== N/N … passed, 0 failed ===`-shaped tail, rc 0
- `MUT_SKIP=1 bash <each suite>` → rc 0 (instrument control)
- `bash scripts/guard-vacuity-floor.test.sh` → rc 0, counters per AC4, all six PROMOTED entries score FIRES
- Negative: hand-introduce a `MUT_SKIP` literal into `infra-validation.yml` → each ported suite's seam row reds (verified by the suite's own IV mutation row, not a manual run)
- Negative: reintroduce `<<-SQL` literally into a ported suite → meta-guard reports it not-floor-bearing → membership pin reds (AC10/Guard-3 row 2)

## Operator Holds

Delegation: <https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901> (valid to 2026-11-20 per the batch-2 recorded evaluation; no delegated act due this batch)

- Hold: the deferred carrier batch (#8525 + #8013 + the RestartSec=300 half of #8080 + advisory #10290) waits for the next vinngest-v* bake / host-replace window
- Hold: #8839 (stuck-on-Working spawn backstop) waits for the Sentry spawn-agent dead-letter evidence and the 35-day lifecycle check
- Hold: Operator-reserved: #9943 — the owner's decision on a new Better Stack read credential in the cutover dispatch
- Hold: Operator-reserved: op=backup dispatch
- Hold: Operator-reserved: DOPPLER_TOKEN_INFRA_PRIVILEGED seed

## Non-Goals

- `registry-clientip-not-rfc1918` rewrite — already gen-3 (AC5 verify-only)
- `inngest-cutover-flip-silent-alert` port — new file outside the issue's remainder list (AC5 verify-only)
- Shared `test/infra/lib/` helper — cut (see Cut List)
- `mutation-scorer.sh` adoption — registry obligation without convention gain
- Any production code, `.tf` resource change, or workflow behavioral change (except the conditional timeout bump)

## Sharp Edges

- A plan whose `## User-Brand Impact` section omits the threshold fails deepen-plan Phase 4.6 — filled above.
- Floor constants are two write sites: after every `PRESENCE_ROWS`/`MUT_ROWS` bump, grep every occurrence of the literal.
- Mutation anchors must not match inside the suite's own header comments (the commented-`paused`-line decoy class); count occurrences the way the matcher counts them.
- `env -u` must not be written literally anywhere in shipped text — the issue's wording is stale; sibling seam pins red on it.
- A literal `<<-TAG` in ANY scanned line (awk pattern, python string, shell needle, printf format, comment) opens a phantom heredoc span — this batch's whole premise. Re-grep after every edit; the evasion must survive the mutation programs' own text too (mutations that INJECT `<<-SQL` into a fixture express it as `<<\x2dSQL` inside the python string).
- `| grep -q` pipelines trip `.claude/hooks/grep-q-pipe-guard` — use `[ "$(producer | grep -cF lit)" -eq 1 ]` or `<<<`/here-string forms (batch-2 hit this twice on `| grep -qx`).
- Shared `.tf` baseline race: an in-flight `betterstack-logs-alerts.tf` PR invalidates canons mid-batch — re-probe at Phase-7 sync (#11653 precedent).
- Backticks or `$$` inside `mutate_red "…"` labels execute shell — the shipped convention writes labels like `the count = 0 mute knob` in plain text (no backticks).
- `build_mutant` slices backward to the first non-assignment: keep the floor window pure assignments, keep any `if…fi` OUT of it, and keep `fi` standalone at column 0.
- Merge queue: `gh pr merge` refuses; GraphQL `enqueuePullRequest` rejects until the required `test` check-run exists on the head; KB artifacts archived inside the PR via `archive-kb.sh`; queued branches reject pushes.
- `doppler-config-inventory.txt` staleness >90d fails test-scripts P16 — it is fresh today (stamped 2026-11-02); if a stale stamp recurs during this pipeline, main owns the bump — do NOT stamp it in this feature PR.
- Devin subagent depth-1: every fan-out in this plan runs sequentially inline; `Reviewed-Coverage: sequential-fallback` discloses wherever a deliverable claims panel/fan-out coverage.

## Port Contract — per-file obligations (plan-time measured)

Shared obligations (all six files), consolidated from the batch-2 shipped convention + this branch's measurements:

- **Phantom sweep first.** Zero literal `<<-`-opener matches in scanned text before floor work; context-correct evasion per site (`<<[-]SQL` awk/grep/comment, `<<\x2dSQL` python string, runtime-composed or `\055`-octal for shell/`printf` text).
- Floor tail is the CONSTRUCTIBLE six-line window (verbatim egress-gw :624-636 shape); constants ADJACENT at column 0; `MUT_ROWS` recomputed from the ported file's own `mutate_*` call-site count (`grep -cE '^\s+mutate_(red|green|floor_red) "'`), `PRESENCE_ROWS` from its `ok()`/`no()` presence-site count — never today's literals.
- Floor/ledger trips exit 1; instrument failures exit 2; the file's "exit 2" convention comment is rewritten where a floor trip would grade UNRESOLVED.
- Battery carries: pristine-child control (all six have it — keep), `want=wrong` scorer control, `_red_verdict` with `$olog` capture, `[note] MUT_SKIP active` loud line (egress-gw :638 shape), per-row expected-FAIL fragments.
- Seam scope per file: `IV_CODE` comment-stripped view; assert `MUT_SKIP` + the suite's OWN axis literals absent; registration pin on the suite's own run line; IV mutation rows prove env: insertion / GUARD literal / dropped run line all red.
- Unanchored opener counts cover BOTH `name = <<[-]SQL` openers AND resource-block headers.
- `mutate_green` TF-scoped; `mutate_floor_red` on `^PRESENCE_ROWS=[0-9]+$`.
- `assert_fixture_dir` stays byte-identical (P1b parity).

Per-file notes:

- **bwrap-probe-rollback** (439 lines, 46 assertions today: P=25 + 21 mut): axes `{TF,WF,CI,RB}` → add `BWRAP_GUARD_IV`; `env "BWRAP_GUARD_${which}=$copy"` indirection already present; `<<-` evasion at :74 (awk), :279/:360/:362/:424 (python); floor `_floor=$((P+21))` → `MUT_ROWS` named constant.
- **faithful-canary-sandbox** (468 lines, 47 assertions: P=37 + M=10): axes `{TF,WF,CI,RB}` + `SELF` (mutates a copy of the suite itself — keep the axis; SELF rows are harness rows); add `FCSB_GUARD_IV`; `MIN_ASSERTIONS` naming → convention `_floor`/`_ran`; the :390 `RED:2`→rc1 floor-trip normalization folds into `_red_verdict`+exit-1 floor semantics; `<<-` at :75 (awk), :372 (python).
- **ghcr-blocked** (708 lines, 78 assertions: P=38 + M_E=40): axes `{TF,WF,CI,CR,RB,IV}` — IV present with step-anchored registration pin (:309-323) — keep it and ADD the literal-absence seam row + IV mutation rows; `MUT_ROWS_EXPECTED`→`MUT_ROWS` while keeping the stronger `MUT_ROWS_RUN` conservation ledger + its `exit 2`; `<<-` at :90 (awk), :420/:501/:503/:549/:557/:564 (python), :679 (harness python); `MUT_PROG` env-passed python (the safer injection form — keep).
- **inngest-step-524** (424 lines, 74 assertions = 50P + 24M per its own comment): axes `{TF,WF,VEC}` → add `SPEND_GUARD_IV`; `mutate_red` exists without fragment arg → signature gains `$4` expect + `$5` want; explicit `SPEND_GUARD_TF=` arms → `env "SPEND_GUARD_${which}=$copy"` indirection; `>/dev/null` → `$olog`; `_floor=74`/`_floor=50` → `PRESENCE_ROWS`/`MUT_ROWS` + constructible window; H524/HBURN (:337) shell needles + s1.tf printf (:398) compose `<<-` at runtime; discovery-coupled presence count pinned to current real count (the <3-discovery refusal stays its own pin); keep the python-based checker shape — canon compares over the python-extracted section, not an awk `LOCAL_SQL` rote-port; `<<-` at :126 (python regex), :337 (shell), :398 (printf).
- **sandbox-alerts** (500 lines, 56 assertions: P=34 + M=22): axes `{TF,WF,DISP,CLS}` → add `SANDBOX_ALERTS_GUARD_IV`; DISP=`server/cc-dispatcher.ts` + CLS=`server/sandbox-startup-classifier.ts` are non-.tf emitters — canon/block pins apply to the `.tf` surface; `.ts` pins stay param-shaped whole-line assertions (no HCL blocks there); `eval_row` python evaluator preserved; `<<-` at :77 (awk), :364/:480/:482/:486 (python); 30s runtime — serial-leg watch.
- **web-nic-guard-unpinned-url** (378 lines, 37 assertions: P=29 + M_E=8): axes `{TF,WF,EM,RB,LQ,IV}` — IV + step-anchored pin present (:239-255); add literal-absence seam + IV rows; `MUT_ROWS_EXPECTED`→`MUT_ROWS` keeping `MUT_ROWS_RUN` ledger; `<<-` at :84 (awk), :296/:362 (python); `MUT_PROG` form kept.

## Port Contract — sequential-fallback disclosure

This plan ran with `Reviewed-Coverage: sequential-fallback` — Devin depth-1 (subagents cannot spawn subagents): the Phase-1 research fan-out, domain-leader sweep, spec-flow pass, advisor consult, and plan-review panel all ran as single-process inline analysis by the orchestrator against the batch-2 shipped artifacts, not as independent seats. The per-file facts above are MEASURED on this branch (greps, timings, meta-guard run), which is the evidence class the panels were there to produce; the coverage claim is narrower by construction and is disclosed wherever the pipeline's ship gate asks for it.

## Enhancement Summary

plan run 2026-11-02 (orchestrator-level, Devin depth-1 sequential-fallback).

### Gate results

- 0.6 Premise validation: PASS (issue OPEN; all cited files exist; env -u stale wording reconciled)
- 0.6b Mechanism minimality: PASS (property list + 5-item cut list emitted)
- 0.7 Skeleton checkpoint: written before research consolidation
- 1.4 Network-outage check: no trigger patterns — skipped
- 1.5 Community discovery: no new stacks — skipped
- 1.5b Functional overlap: batch-2 archive is the same change class — convention reused, not reinvented
- 1.6 External research: skipped — strong local context (shipped convention + measured landmines)
- 1.7.5 Code-review overlap: #8735 + #7942 acknowledged, no touches on planned files
- 1.8 Skill-description budget: no SKILL.md description edits — skipped
- 2.5 Domain review: Engineering + Operations carried forward (sequential-fallback); Product/UX mechanical override did not fire
- 2.6 User-Brand Impact: threshold none + scope-out bullet
- 2.7 GDPR: no regulated-data surface, no (a)-(d) triggers — skipped
- 2.8 IaC routing: no new infrastructure — skipped
- 2.9 Observability: emitted (5-field schema)
- 2.9.3 Task-design: no new autonomous task — skipped
- 2.10 ADR: no architectural decision — skipped
- 2.11 Encryption: no new store/connection — skipped
- 2.12 Guard Contract: 3 guards, matrices ≥3 rows, dispatch + second-member + must-PASS rows present
