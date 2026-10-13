---
title: "fix(test-all): --print-affected-set spins at 100% CPU forever when its worktree is deleted mid-run"
type: fix
date: 2026-09-24
slug: fix-test-all-print-affected-set-deleted-worktree
branch: feat-one-shot-8761-print-affected-set-spin
issue: 8761
closes: 8761
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(test-all): --print-affected-set spins at 100% CPU forever when its worktree is deleted mid-run

## Overview

On 2026-09-24 two `scripts/test-all.sh` invocations — one direct (`--print-affected-set`, parented by a Claude Code Bash call) and one spawned by `scripts/lint-orphan-test-suites.sh` (`--affected --print-affected-set`) — each burned ~97% CPU for 4.5–5 hours after their shared worktree was removed mid-run. `/proc/<pid>/cwd` showed `(deleted)`, state stayed `R`, neither had children, and both had to be killed by hand. The calling agent's Bash call never returned.

The enumerate path must fail fast with a clear error and a non-zero exit when its checkout disappears mid-run, and must carry a hard wall-clock ceiling so no loop in this path — known or future — can spin unbounded again.

## Problem Statement / Motivation

`--print-affected-set` sets `_PRINT_AFFECTED=1` and `_ENUMERATE=1` in `scripts/test-all.sh`'s flag-parse loop, then walks every registration emitting `AFFECTED_CLASS` receipts, terminating at the `_ENUMERATE == 1` early-exit before the epilogue. Two measured gaps make a deleted checkout dangerous on this path:

1. **No liveness check anywhere on the path.** `git`-derived state (`git diff`, `git ls-files --others`) fails into `_diff_names` via `2>/dev/null || true`, every `[[ -e ]]`/`[[ -f ]]` probe in `_affected_derive` goes false, and the walk simply produces a *truncated but successful* output — measured today: deleting the worktree mid-walk produced **267 receipts and `exit 0`** vs 301 on an intact tree. That is a silent under-coverage shape in addition to the spin class the issue reports.
2. **No wall-clock bound.** The `TC_RUNTIME_CEILING_S` check lives inside `run_suite` *after* the `_ENUMERATE == 1` early-return, so the print/enumerate walk is structurally unreachable by the existing ceiling — a spin here is unbounded by construction.

## Research Insights

### Premise Validation

- `gh issue view 8761`: **OPEN**, `type/bug`, `priority/p2-medium`. Cited sibling `gh issue view 8621` ("Converge the two affected-test selectors"): **OPEN**, explicitly out of scope — no plan content depends on it.
- Cited files exist at HEAD: `scripts/test-all.sh` (4,736 lines), `scripts/lint-orphan-test-suites.sh` (spawns `bash "$RUNNER" --affected --print-affected-set` in its classification-receipts block), `scripts/lib/test-affected-paths.sh` (declarations index, no loops).
- Proposed mechanism vs ADR corpus: grepped `knowledge-base/engineering/architecture/decisions/` for `watchdog|timeout|worktree` — no ADR rejects a script-level guard or deadline; ADR-133's bounded-wait family (`_tc_queue_wait`, `_acquire_lock_impl`'s `flock -w`) is the consistent precedent — every wait in this codebase carries a budget except this path.
- **Probe semantics measured live on this host** (deleted-cwd fixture): `[[ -e . ]]`, `[[ -d . ]]`, and `stat .` all return **TRUE** on a deleted-but-open cwd (fd-relative stat resolves the retained inode) — the intuitive `[[ -e . ]]`/`[[ -e "$REPO_ROOT/.git" ]]`-adjacent probe cannot detect the failure. What does detect it: `[[ -d "$PWD" ]]` (FALSE), `pwd -P` (fails), `git rev-parse --show-toplevel` (fails `fatal: Unable to read current working directory`). The probe MUST be path-based.

### Reproduction attempt (hang-site hunt — the issue's explicit ask)

Ran the issue's repro shape 15 times on this HEAD (real `git worktree add` + `--print-affected-set`, with and without `bash -x`, deletion via both `git worktree remove --force` and `rm -rf`, at offsets 0.1s/0.3s/0.5s/0.8s/1.2s/1.5s/2s/3s/5s/8s/10s/15s/20s/40s/70s):

- Deletion before lib sourcing (~0.1s) → `exit 2` on the `repo-write-boundary.sh` missing-lib check — the fail-fast shape working by accident of placement.
- Every later deletion → the walk completes on the dead tree, `exit 0`, truncated receipts.
- **No arm produced the spin.** Static census of the enumerate path confirms why: every loop is bounded — `while read` variants are EOF-bound, `_affected_resolve_vars` is capped at `_iter < 12`, the source-closure BFS is capped at `_depth < 8`, `_tc_alloc_lock` is a counted 50-try retry, `_tc_queue_wait`/`_tc_wait_heartbeat` carry budgets (and are unreached: enumerate mode sets `SOLEUR_DISABLE_SESSION_STATE=1` before `tc_acquire`). The incident ran on the deleted `feat-8486-human-presence-guard` worktree's tree, which is gone; the merge-base diff of `scripts/test-all.sh` shows no loop-shape changes since.

**Consequence for design:** the literal spin site is not identified — see Research Reconciliation. The fix is therefore structural: a fail-fast contract (deleted checkout → non-zero, fast, named error) plus a wall-clock ceiling that bounds *any* loop in this path, so the unidentified site — and any future one — is covered without being located. The regression suite pins the contract, which is violated measurably today (the silent-truncated `exit 0`).

### Property List (mechanism-minimality restatement)

- P1: a run whose checkout is deleted — before or during the walk — exits non-zero, fast, with a named error; it must never emit a truncated receipt set under `exit 0`.
- P2: the enumerate path terminates within a declared wall-clock bound no matter where control flow is stuck, including inside a single loop iteration.
- P3: the contract is regression-pinned so a reintroduction reds.

### Cut List

- Mechanism "caller-side `timeout` in lint-orphan-test-suites.sh" — buys P2 only for that one caller; the direct-invocation case (the Claude Code Bash call that wedged) stays uncovered. Cut — covered by the in-script watchdog instead. lint-orphan already surfaces a non-zero `aff_set_rc` loudly, so no caller change is needed.
- Mechanism "hoist `TC_RUNTIME_CEILING_S` into enumerate" — its check is per-registration, so it cannot interrupt a spin inside one iteration, and its semantic is "stop starting suites" (decline), not "die". The *pattern* (deadline arithmetic on `SECONDS`) is reused; the mechanism itself is not shared. Not cut, just correctly scoped.
- Existing `_CEILING_S` / bare-repo guard / `_RWB_LIB` presence check — verified to not cover this path (enumerate early-returns before the ceiling; the bare-repo probe fails *open* under a deleted cwd — `git rev-parse --is-bare-repository` fails, `grep -q true` is false, run proceeds).

### Learnings applied

- `2026-09-23-a-packed-string-searched-by-glob-is-a-quadratic-map.md` — bash 3.2 constraint confirmed (no assoc arrays; the check added is a single `[[ ]]` test, no map).
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — the Guard Contract below writes the mutation matrix before the guard, including a row that drives the guard's own dispatch red (a `return` in place of `exit` is swallowed by the `||` call sites).
- `2026-09-18-a-plan-prescribed-probe-must-be-portable-to-the-hosts-it-ships-to.md` — `timeout` is absent on stock macOS; the watchdog is pure-bash (`sleep` + `kill` + `SECONDS`), matching `_tc_queue_wait`'s existing portability precedent.
- `2026-05-12-task-subagent-prompt-text-only.md` — planning ran with sequential fallback (no Task fan-out); disclosed below.

### Network-outage gate (Phase 1.4)

Trigger token `timeout` matched (the proposed watchdog ceiling). Evaluated against the checklist: this plan has no SSH/network-connectivity surface — the failure is a local CPU spin, no L3–L7 hypotheses apply. Gate recorded as fired-and-not-applicable; no checklist entries carried into Hypotheses.

### Functional overlap / community discovery (Phases 1.5, 1.5b)

Pure-bash repo-internal runner fix; no uncovered stack signatures apply, and no community artifact provides a "deleted-cwd liveness guard for a bash test runner" — the check is two builtins and a subshell. Nothing to install.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Measured at HEAD | Plan response |
|---|---|---|
| "One of the `while` loops over git-derived state never ends" | Every loop on the enumerate path is bounded (census above); 15-arm repro never spun | Treat hang site as **unidentified**: fix the *contract* (fail-fast + ceiling) rather than a specific loop; regression test pins the contract |
| "check `[[ -d \"$PWD\" ]]`" | Correct probe — measured; `[[ -e . ]]`/`stat .` stay TRUE on deleted cwd | Prescribe `[[ -d "$PWD" ]]` (or `pwd -P`) verbatim; a mutation row pins the wrong-probe substitution |
| "a hard `timeout` on the path" | `timeout(1)` is absent on stock macOS; repo precedent is a bash subshell budget (`_tc_queue_wait`) | Prescribe a pure-bash watchdog subshell + per-chokepoint `SECONDS` deadline, not `exec timeout` |
| "it should never spin" | Today it silently *truncates* (267/301 receipts, `exit 0`) under mid-walk deletion — a second defect the issue didn't name | The in-chokepoint check converts both shapes to the same loud non-zero |

## Hypotheses

| # | Hypothesis for the 4.5h R-state no-children spin | Status |
|---|---|---|
| H1 | A `while`/`for` loop in the enumerate path iterates forever on empty git output | **Not supported on HEAD** — loop census shows every construct bounded; repro never spun |
| H2 | Spin inside bash's own script-reader or a `$( )` child | **Unknown** — cannot be ruled out or confirmed; incident tree is gone |
| H3 | The incident-era worktree carried different code (uncommitted/older) | **Plausible, unverifiable** — merge-base diff shows no loop-shape changes since the era |

Per the sharp-edge on hypothesis honesty, no hypothesis reads CONFIRMED — the deciding datum (the deleted tree's exact code) is unavailable. The plan fixes the class: P1+P2 hold regardless of which loop it was.

## Proposed Solution

Three mechanisms, each buying a distinct property, all in `scripts/test-all.sh` plus test arms in `scripts/test-all-affected.test.sh`:

1. **Up-front checkout guard** (P1, pre-run). Immediately after the bare-repo guard block (so a bare root keeps its own precise message), refuse unless the checkout is usable: `git rev-parse --show-toplevel >/dev/null 2>&1` AND `[[ -d "$PWD" ]]`. On failure print `ERROR: working tree missing (deleted worktree?)` to stderr **and** stdout (operator-protection signal → stdout per constitution; the receipt stream is prefix-keyed so a non-record line is contract-tolerated), `exit 4` — the runner's existing "refused, nothing ran" code.
2. **Per-registration liveness + deadline check** (P1 mid-run + P2 coarse). At the top of `_shard_selects` — the single chokepoint every registration passes through (`run_suite` and `skip_suite` both call it first; verified only two call sites) — after its existing arg-count refusal and before the ordinal increment:
   - `[[ -d "$PWD" ]] || { <error>; exit 4; }` — must be `exit`, never `return 1`: the call sites are `_shard_selects "$label" || return 0`, so a return is swallowed as "not selected".
   - enumerate-scoped deadline: `(( _ENUMERATE == 1 && SECONDS > _ENUM_DEADLINE_S )) && { <error>; exit 4; }` — `SECONDS`, not `EPOCHSECONDS` (bash 3.2, per `_tc_queue_wait`'s own precedent). Execution mode is untouched beyond the shared liveness check, which is correct there too (a deleted cwd poisons an executing battery identically).
3. **Enumerate watchdog subshell** (P2 hard bound). Armed once after flag parse/validation when `_ENUMERATE == 1`: a background `( sleep "$_ENUM_DEADLINE_S"; printf 'ERROR: ...\n' >&2; kill -TERM "$_ENUM_TOP_PID"; sleep 5; kill -KILL "$_ENUM_TOP_PID" ) &`. Disarmed in the `_ENUMERATE == 1` terminal block before `trap - EXIT` (`kill` the watchdog pid; self-terminating otherwise — a leaked `sleep` dies inside the deadline). This bounds *any* spin — including one inside a single iteration that check 2 cannot reach.
4. **In-loop re-check** (issue's ask 2, belt): first statement inside `_affected_derive`'s closure `while` loop — same `[[ -d "$PWD" ]]` die.

`_ENUM_DEADLINE_S` default **300** with env override (`SOLEUR_ENUM_DEADLINE_S`, `=~ ^[0-9]+$`-validated else default — the `_tc_ticket_sweep` sanitization precedent). Basis: full print walk measured ~35s clean / >120s loaded on this host (`timeout 120 bash scripts/test-all.sh --print-affected-set` was killed mid-walk; repro runs completed in ~35s); 300s is ≥2.5x the worst observed and the deadline is a safety bound, not a performance assertion. Small values (5s) let the test exercise the watchdog arm.

## Technical Considerations

- **Why `_shard_selects` and not `run_suite`/`skip_suite`:** it is the structural chokepoint — exactly two call sites, both under `|| return 0`, one invocation per registration in every mode (enumerate, execute, sharded). A check placed there needs no per-callsite upkeep; a second chokepoint added later would be a totality violation the shard machinery already forbids.
- **Bash 3.2 portability:** `SECONDS`, `kill`, `wait`, `[[ -d ]]`, `( ) &` — all 3.2-safe. No `EPOCHSECONDS`/`EPOCHREALTIME`/`declare -A`/`mapfile`/`timeout(1)`.
- **stdout emission of the error line** is safe for every receipt consumer: `lint-orphan-test-suites.sh` selects `AFFECTED_CLASS` rows by `awk -F'\t' '$1=="AFFECTED_CLASS"'`, `battery-tag-authorship`/`shard-totality` select `SUITE_COMMAND*` by prefix — the record contract already documents that consumers must prefix-select. Implementer must grep for any consumer doing a whole-stream equality assert before shipping (none found in this pass, but verify at work time).
- **`exit` vs `return` in `_shard_selects`** is the load-bearing detail — `return 1` reads as "not selected for this leg" at both call sites.
- **`$PWD` semantics:** bash maintains `$PWD` as the path used to arrive; a symlinked worktree path stays `[[ -d ]]`-true while alive — no false positive. `pwd -P` is the stronger alternative (detects a recreated same-path dir too); either is acceptable, pick one and pin it in a comment.
- **Watchdog subshell pid:** capture `_ENUM_TOP_PID=$$` in the parent before spawning (in a `( )` subshell `$$` already equals the top pid, but the explicit capture is clearer and survives review).
- **NFR impacts:** none — dev-tooling script; adds one stat + one background `sleep` per enumerate invocation.

## User-Brand Impact

- **If this lands broken, the user experiences:** a local/CI test-runner process that wedges CPU-indefinitely or reports `exit 0` over a truncated affected-set — wasted host CPU and silently-thin gate coverage on the operator's own tooling; no end-user surface is touched.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — no data, credentials, or network surface involved; worst case is wasted CPU time and a stalled agent session.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what:            "Enumerate run terminates: non-zero exit with 'working tree missing' on a deleted checkout, or exit 0 with the full receipt set on a healthy one"
  cadence:         "per-run"
  alert_target:    "the invoking agent session / shell (tool result), and lint-orphan-test-suites.sh's existing 'exited N' ERROR"
  configured_in:   "scripts/test-all.sh — _shard_selects liveness arm + _ENUMERATE watchdog arm"

error_reporting:
  destination:     "stderr + stdout of the runner process (surfaced by the calling tool's captured output)"
  fail_loud:       "ERROR: working tree missing (deleted worktree?) / ERROR: enumerate deadline exceeded — plus exit 4; lint-orphan amplifies via its aff_set_rc != 0 arm"

failure_modes:
  - mode:          "worktree deleted before launch"
    detection:     "up-front guard exits 4 with the named error"
    alert_route:   "stderr+stdout to the invoking session"
  - mode:          "worktree deleted mid-walk"
    detection:     "_shard_selects liveness check at the next registration"
    alert_route:   "stderr+stdout to the invoking session"
  - mode:          "genuine spin inside one loop iteration (the un-located incident site class)"
    detection:     "watchdog subshell TERM/KILL at the deadline"
    alert_route:   "stderr error line printed by the watchdog before killing"

logs:
  where:           "the invoking session's captured stderr/stdout; TEST_TIMING_LOG unchanged"
  retention:       "session transcript"

discoverability_test:
  command:         "grep -n 'working tree missing' scripts/test-all.sh"
  expected_output: "working tree missing"
```

## Guard Contract

### Guard 1 — deleted-checkout fail-fast

**Property.** When the runner's cwd path no longer resolves, any run — enumerate or executing — exits non-zero with `ERROR: working tree missing (deleted worktree?)` within one registration step of the deletion; it never completes `exit 0` over a truncated receipt set.

**Assembly.** The property quantifies over every registration dispatch and every pre-registration phase. The check sites are: (a) the up-front guard after the bare-repo guard (covers pre-run deletion); (b) the top of `_shard_selects` — the single chokepoint `run_suite` (registration dispatch) and `skip_suite` (counted decline) both funnel through per registration; (c) `_affected_derive`'s closure while-loop (the one multi-iteration site inside a single registration's classify). The assembly is the chokepoint's structure, not today's registration list: any registration added later passes through `_shard_selects` by the existing totality discipline, and a second dispatch function would be a shard-totality violation independent of this guard.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `_shard_selects` liveness arm → delete the fixture worktree mid-walk | RED (today's measured behavior: `exit 0`, truncated receipts) |
| 2 | Substitute the probe with `[[ -e . ]]` or `[[ -d . ]]` (fd-relative — stays TRUE on a deleted cwd, measured) | RED — both deletion arms must fail |
| 3 | Change the arm's `exit 4` to `return 1` — the `||` call sites swallow it as non-selection | RED — the mid-walk arm completes green |
| 4 | Delete the worktree *between* two registrations (after N good dispatches) rather than before the walk | still caught at registration N+1 — second-member-after-compliant-first row |
| 5 | Harness: arm that asserts `exit 0` after mid-walk deletion (vacuous-pass flip) | RED — proves the arm isn't a tautology |
| 6 | Must-PASS: intact fixture worktree, and a symlinked-path variant | run completes `exit 0` with the full receipt count — no false positive on a live tree |

### Guard 2 — enumerate wall-clock watchdog

**Property.** Every `_ENUMERATE == 1` invocation terminates within `_ENUM_DEADLINE_S` (default 300, `SOLEUR_ENUM_DEADLINE_S` overridable) even if control flow never advances — including a pure-compute spin inside one loop iteration — and prints the deadline error before dying.

**Assembly.** The watchdog subshell armed once after flag-parse/validation for the `_ENUMERATE == 1` mode family (`--enumerate`, `--enumerate-commands`, `--print-affected-set`, `--affected --print-affected-set`), plus the per-registration `SECONDS` deadline check in `_shard_selects` as the graceful first line; disarm at the single enumerate terminator before `trap - EXIT`. If a second enumerate exit is ever added, the disarm must move with it — there is exactly one today (the `[shard] enumerate complete` block).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Splice `while :; do :; done` into the sandbox runner's registration walk; run with a small `SOLEUR_ENUM_DEADLINE_S` | RED if the run outlives the test's outer bound — the watchdog must kill it |
| 2 | Remove the watchdog arm entirely | the spliced-spin arm hangs to the outer timeout → RED |
| 3 | Feed a non-numeric `SOLEUR_ENUM_DEADLINE_S` | must not abort the run under `set -u`/arith — normalized to default, run completes |
| 4 | Harness: assert the watchdog does NOT fire on a healthy run (rc 0, full receipts, no deadline line) | PASS — must-PASS input differing from the mutation arms |
| 5 | Harness: run under a deadline smaller than any real walk takes with no wedge | non-zero with the deadline error — proves the kill path end-to-end, not just the code's presence |

## Acceptance Criteria

- [ ] AC1 — `bash scripts/test-all.sh --print-affected-set` in a worktree deleted mid-run exits non-zero within 45s of the deletion and emits the literal `working tree missing` (stderr and stdout).
- [ ] AC2 — The same holds launched in an already-deleted cwd: non-zero within ~5s.
- [ ] AC3 — The coverage applies to the whole enumerate family: `--enumerate`, `--enumerate-commands`, `--affected --print-affected-set` (at least one additional flag spelling exercised by an arm).
- [ ] AC4 — A sandboxed runner spliced to spin forever in its walk is killed by the watchdog within `SOLEUR_ENUM_DEADLINE_S` + grace, printing the deadline error — the mutation-matrix row, not a hypothetical.
- [ ] AC5 — Healthy-path regression: intact worktree run exits 0 and emits every registration's `AFFECTED_CLASS` receipt (count parity with today's baseline — derive the count programmatically in the arm, do not hardcode), including when the cwd is a symlinked path.
- [ ] AC6 — `lint-orphan-test-suites.sh`'s consumer contract holds: a non-zero `--print-affected-set` surfaces as its existing `ERROR: 'bash scripts/test-all.sh --affected --print-affected-set' exited N` arm, and the stray `ERROR:` stdout line breaks no receipt consumer (verify no whole-stream equality assert exists).
- [ ] AC7 — Execution-mode behavior unchanged except the shared liveness check: the affected/enumerate/runner suites stay green (`test-all-affected`, `test-all-enumerate-toolchain`, `test-all-group-affected`, `test-all-killed-classification`, `test-all-capacity-signal`, `test-all-runtime-ceiling`, `test-all-infra-coverage-notice`, `test-all-webplat-gate`, plus `lint-orphan-test-suites.sh` itself).
- [ ] AC8 — `SECONDS`-based deadline and pure-bash watchdog only: no `timeout(1)`/`gtimeout`/`EPOCHSECONDS`/`declare -A`/`mapfile` added to the runner.
- [ ] AC9 — Diff scope: `scripts/test-all.sh`, `scripts/test-all-affected.test.sh`, and this PR's planning artifacts only.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — dev-tooling/test-runner change. Mechanical UI-surface override evaluated: `## Files to Edit`/`Create` contain no UI-surface paths → Product gate is NONE.

## Test Scenarios

- Given a `git init`'d fixture repo containing the runner copy + required libs and a `git worktree add`'d subdirectory, when `--print-affected-set` runs inside the subdir and the subdir is `rm -rf`'d mid-walk, then the run exits non-zero within the bound and prints `working tree missing`. (Guard 1, rows 1-4)
- Given a cwd deleted before launch, when the run starts, then the up-front guard exits 4 fast with the named error. (Guard 1, row 1's pre-run sibling)
- Given a sandbox runner spliced with an infinite loop in its walk and `SOLEUR_ENUM_DEADLINE_S=5`, when the run is launched, then it dies within ~15s having printed the deadline error. (Guard 2, rows 1-2)
- Given an intact fixture worktree (including via a symlinked path), when `--print-affected-set` runs, then it exits 0 with full receipts and no deadline/guard line. (both must-PASS rows)
- Given `lint-orphan-test-suites.sh` driving `--affected --print-affected-set` on a worktree deleted mid-run, when the child exits non-zero, then the linter reports its existing `exited N` ERROR rather than hanging.

## Success Metrics

- The issue's repro sketch (`git worktree add` → run → `git worktree remove` mid-run) produces a fast non-zero exit with a named error instead of a hang.
- Zero registration-mode regressions: the full `scripts/test-all*.test.sh` family and `lint-orphan-test-suites.sh` stay green.
- The enumerate walk's normal cost is unchanged (~one extra `[[ -d ]]` stat per registration).

## Dependencies & Risks

- **The literal spin site is unidentified** (see Hypotheses). Mitigation: the fix targets the contract, not a site — ceiling + fail-fast hold for any loop; the regression test reds on today's *measured* defect (silent truncated `exit 0`) even without reproducing the spin. If implementation reproduces the hang during diagnosis, the identified site additionally gets an inline comment.
- **A consumer doing whole-stream receipt equality** would break on the new stdout `ERROR:` line — verify by grep at work time; the record contract says prefix-select, but verify.
- **`exit` inside `_shard_selects`** terminates the whole runner — intended; the trapless `exit` also skips the watchdog disarm, which is harmless (the `sleep` self-terminates at deadline, its `kill` hits a dead pid).
- **Deadline too tight under extreme load:** 300s is ~2.5x the worst measured walk (>120s loaded); the knob is `SOLEUR_ENUM_DEADLINE_S`-overridable. The deadline is a safety bound, not an SLO.
- **macOS bash 3.2:** all constructs used are 3.2-safe (`SECONDS`, `kill`, `( ) &`, `[[ -d ]]`) — matching the lib's own precedent comments.

## Open Code-Review Overlap

- `#8659` (33 suites replace test-helpers' composed EXIT trap) — **acknowledge**: touches `plugins/soleur/test/test-helpers.sh` trap composition, disjoint from the enumerate chokepoint; a new arm in `test-all-affected.test.sh` uses the suite's own cleanup trap convention, not the shared helper. No fold-in.
- `#7942` (two mutation batteries named `*.mutation.sh` run in no gate) — **acknowledge**: naming/registration concern only; this plan adds an arm to an already-registered suite, so it neither helps nor worsens that issue.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| `exec timeout -k` self re-exec for `--print-affected-set` | Rejected — `timeout(1)` is absent on stock macOS (sharp-edge precedent), carries no error message of its own (rc 124 only), and adds re-exec argv plumbing plus an armed-flag recursion edge |
| Caller-side `timeout` at `lint-orphan-test-suites.sh`'s spawn | Rejected — covers that one caller only; the direct-invocation case (the wedged Claude Code Bash call) stays open. Its existing `aff_set_rc != 0` arm already amplifies the new non-zero exit |
| Only the up-front guard (issue's ask 1 alone) | Rejected — measured today: mid-walk deletion still completes `exit 0` on a truncated receipt set |
| Hoist `TC_RUNTIME_CEILING_S`'s check into enumerate mode | Rejected as insufficient alone — per-registration granularity cannot interrupt an intra-iteration spin; its decline semantic (skip remaining suites, exit 3) is also the wrong verdict for a deleted checkout. The `SECONDS`-deadline *pattern* is reused |
| Wait for #8621 (selector convergence) | Rejected — orthogonal; both selectors share the `_shard_selects`/enumerate machinery this plan hardens |

## Non-Goals / Out of Scope

- Converging the two affected selectors — tracked as #8621, deliberately not co-located.
- Changing execution-mode ceiling semantics (`TC_RUNTIME_CEILING_S` decline behavior untouched).
- Edits to `lint-orphan-test-suites.sh` (its consumer arm already does the right thing on non-zero).
- Deleted-checkout resilience for arbitrary other scripts — this plan scopes to `test-all.sh`'s enumerate path; the shared `_shard_selects` check incidentally protects the executing modes too.

## Files to Edit

- `scripts/test-all.sh` — up-front guard after the bare-repo guard; watchdog arm after flag validation; liveness + enumerate deadline check at the top of `_shard_selects`; `[[ -d "$PWD" ]]` re-check inside `_affected_derive`'s closure loop; watchdog disarm in the `_ENUMERATE == 1` terminal block.
- `scripts/test-all-affected.test.sh` — new arms: mid-walk deletion, pre-deletion start, watchdog splice-mutation, symlinked/intact must-pass. Reuse the suite's `build_sandbox`/`run_arm`/`pass`/`fail` machinery; fixture is a `git init`'d TESTROOT repo (`cq-test-fixtures-synthesized-only`).

## Files to Create

None. (The regression coverage lands as arms inside the already-registered `scripts/test-all-affected` suite — a new test file would additionally need a `run_suite` registration plus an `AFFECTED_*_PATHS` declaration in `scripts/lib/test-affected-paths.sh` or it would red lint-orphan's unclassified check; the in-suite arm avoids both.)

Pipeline artifacts this PR also writes (for diff-scope completeness): this plan file and `knowledge-base/project/specs/feat-one-shot-8761-print-affected-set-spin/tasks.md`.

## Sharp Edges

- The probe for a deleted cwd must be path-based: `[[ -e . ]]`/`[[ -d . ]]`/`stat .` all return TRUE on a deleted-but-open cwd (fd-relative stat) — measured on this host. Prescribe `[[ -d "$PWD" ]]` or `pwd -P` verbatim.
- `return` vs `exit` in `_shard_selects`: both call sites use `|| return 0`, so a return is swallowed as non-selection — the arm must `exit`.
- Watchdog must be pure bash (`sleep`+`kill`); `timeout(1)` is absent on stock macOS (repo precedent: `.claude/hooks/memory-backstop.sh`'s timeout→gtimeout→bare pattern; simpler to not need it).
- `discoverability_test.command` contains no shell metacharacters (`|; & < > $` backtick) per preflight Check 10's byte-level reject.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 — filled above.
- Hypothesis honesty: no hypothesis reads CONFIRMED while the deciding datum (the incident tree's exact code) is unavailable — H1–H3 carry their true status.
- The diff-scope AC includes the pipeline artifacts (plan file + tasks.md), not only the product files.

## Review & Consult Provenance

- Fan-out shape: sequential-fallback — this plan ran inside a pipeline subagent with no Task tool; the research/review passes the skill prescribes as parallel agents were executed inline by the planner. `Reviewed-Coverage: sequential-fallback` — no independent review ran at plan time; `soleur:review` is the review gate.
- Scoped advisor consult (Phase 4.5): not spawned (no Task tool); the riskiest phase is Phase 1's `_shard_selects`/`exit` interaction, covered by Guard-1 mutation row 3.
- External research: skipped — bash-internal fix with strong local precedent (contention-lib bounded-wait family).

## References & Research

- Issue: #8761 (open) — the incident; #8621 (open) — selector convergence, out of scope.
- `scripts/test-all.sh` — flag-parse loop, `_shard_selects`, `_affected_derive`, `_affected_emit_receipt`, diff-collection block, `_ENUMERATE` terminal block.
- `scripts/lib/test-contention.sh` — `_tc_queue_wait`/`_tc_wait_heartbeat` bounded-wait precedent (`SECONDS`, budget exits).
- `scripts/lib/test-affected-paths.sh` — declarations index (no changes needed; no new suite registered).
- `scripts/test-all-affected.test.sh` — host suite for the new arms (`build_sandbox`, `run_arm`, `pass`/`fail`, `assert_fixture_dir`).
- `scripts/lint-orphan-test-suites.sh` — the second consumer; its `aff_set_rc != 0` arm already surfaces a non-zero print run.

**External research:** skipped — bash-internal runner fix; the governing constraints are this repo's own conventions (bash 3.2 safety, receipt prefix-keying, bounded-wait precedent in `scripts/lib/test-contention.sh`), all verified locally.
