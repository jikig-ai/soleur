---
title: "feat: read the required set from the ship Phase 7 inline poll (inline half of #11544)"
date: 2026-11-09
slug: ship-phase7-required-set-read
branch: feat-one-shot-11544-ship-phase7-required-set
issue: 11544
closes: 11544
refs: 9927
type: feature
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-11-09
**Halt gates run (4.6-4.13):** User-Brand Impact (pass, threshold `none` with reason), Observability (pass; `expected_output` changed to the single literal `REQUIRED-SET` so Check 10's tokenizer can match it), PAT-shaped variable sweep (no hit), UI wireframe (not a UI plan), Encryption Posture (no store or connection), Guard Contract (`lint-guard-contract.py` green, 2 guards), Scope Check (one unfenced section, no unmapped ask), Task Design (no new autonomous surface).
**Review panel before deepening:** DHH, Kieran, code-simplicity (plan-review) and two CTO rulings; then a verify-the-negative sweep and a test-design trace.

### Key Improvements
1. Green-dwell semantics (CTO re-ruling, decision-challenges row 5): the 10 ticks count only ticks on which every gate holds, sampled on the existing every-5th-tick cadence, so a PR still waiting on running required checks cannot get a false `absent` read. First read lands at tick 14, not 10.
2. Fence simplified: no `rs_due`, no `RS_OK`, no tag-pin row, no extra knob; the redundant `rs_qs` clause on the increment line (an equivalent mutant) was removed and the sample gate carries the armed / not-queued decision.
3. Hand-traced predicted ticks corrected (F3 reads at 14 and 27, not 29); mutation matrix now pins the per-tick-sampling cost through the verdict stub's call count and every mutant has a named RED row.
4. The monitor-dedupe deferral is documented in place after the filing gate refused an issue (CTO option A), not filed.

### New Considerations Discovered
- A fresh `--queue-state` read at fire time would consume the seen-queued marker and could swallow the dequeue stop; sampling is deliberate (Cut List 9).
- The merge-pr mirror lacks the canonical required-check scan comment; its insertion anchor is the code, not the comment.
- Fixture traps: `SCEN_ROOT` is global, absence must be asserted through `MERGED CLEAN` / call counts (the heartbeat skips most tick labels), and a root-owned `chmod` cannot make a directory unwritable.

## Overview

The monitor half of #11544 merged as ce34675bf8: `monitor-pr-checks.sh` now reads the required-context set (`ci-head-verdict.sh required`) when its checks are green but the PR stays BLOCKED. The inline poll loop in `soleur:ship` Phase 7, and its derived mirror in `soleur:merge-pr` section 5.2, still ends such a PR by heartbeating until the 90-minute cap, which is the silent-forever case the read exists to close.

This plan gives that loop the same read, dispatched to one new script (`plugins/soleur/scripts/required-set-report.sh`) so the two fences only dispatch, as they already do for `sync-pr-behind.sh`. The PR body says `Closes #11544` and `Ref #9927`, never `Closes #9927`.

Spec lane note: the branch has no `spec.md`, so `lane:` is the fail-closed default `cross-domain` (TR2).

## Research Insights

### Premise Validation (Phase 0.6, run 2026-11-09 against origin/main at af764001ee)

- #11544 is OPEN (milestone Post-MVP / Later, labels type/chore, domain/engineering, priority/p2-medium); #9927 is OPEN and is only referenced. PR #12476 (this branch) is the only open change naming #11544; `collision-precheck.sh 11544` reported the three foreign `test-all.sh` processes of an unrelated worktree, none on these files.
- The monitor half is on `origin/main`: `read_required_set`, `_req_degraded`, `REQ_DWELL_S` (600) and `REQ_TIMEOUT_S` (120) are all present in `plugins/soleur/scripts/monitor-pr-checks.sh`. The brief's description of it holds.
- Open PRs touching this plan's shared files: #12462, #12438 and #7390 append rows to the two suite registries (`scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`). None touches either fence, the fixture suite, `ready-run-wait.md` or `.claude/hooks/lib/context-sanitize.test.sh`.
- ADR corpus: no ADR rejects dispatching a fence step to a script; the pattern is ADR-179 (root identity) plus the `sync-pr-behind.sh` precedent (#8383). No ADR/C4 impact (see Architecture note below).
- Stale-claim sweep (own capability claim, `hr-verify-repo-capability-claim-before-assert`): the sentence "does not perform this read yet" appears in THREE places, not the one the brief names: `ready-run-wait.md` (end of the "The monitor performs this read for you" paragraph), the header of `monitor-pr-checks.sh` ("The inline poll loop in ship Phase 7 does not perform this read yet") and the header of `ci-head-verdict.sh` ("the inline poll loop in ship Phase 7 (#11544) still does not"). Only comments change in the two scripts; see Cut List item 7.

### Property List (Phase 0.6b)

1. A PR that the inline poll sees OPEN and BLOCKED with auto-merge armed, not queued and a `full-decided` verdict for 10 consecutive ticks (a green dwell, so a PR still waiting on running checks is not read early) gets the required-context set read, printed on the Monitor stream, at most 3 times per poll and 10 ticks apart.
2. The read cannot alter the poll's other behaviour: it pushes nothing, syncs nothing, re-arms nothing, and never executes a RECOVERY line.
3. A marker of `absent` or `failed` ends the poll with the hints visible; `complete`, `pending`, `error` and "no marker" keep it polling.
4. The marker is the only thing read (never an exit code), and a missing marker is `error`.
5. The parsing and sanitising of the resolver's output live in exactly one new, directly unit-testable place; the two fences contain dispatch only.
6. Ship and the merge-pr mirror behave identically on every row.
7. The read is bounded: at most `timeout -k 5 120` (125 s) per read, 3 reads per poll.

### Cut List (Phase 0.6b)

| # | Mechanism considered | Property it would buy | Disposition |
|---|---|---|---|
| 1 | Inline the marker parse in both fences | 5 | CUT (CTO ruling): a third and fourth copy of ~40 lines of parser; the script is the one place. |
| 2 | A temp file (and a second EXIT trap) in the fence for the read's stdout | 2, leak-freedom | CUT: the fence already owns one `trap ... EXIT` for the sync snapshot and a second `trap` would replace it (parity token `trap 'rm -f "$SYNC_SNAP"' EXIT` is pinned). The script owns the temp files; the fence streams the script's stdout through a process substitution (same construct as the existing `mapfile -t REQUIRED_CHECKS < <(...)`). |
| 3 | A new `gh pr view autoMergeRequest` call per tick for "armed" | 1 | CUT: the every-5th-tick `--queue-state` line already carries `<queued\|not_queued\|dequeued> <state> <armed\|disarmed>`, with `armed` queue-gated (#11789). The fence reuses that last read. |
| 4 | The verdict read inside the script | 1 | CUT (CTO ruling): the script takes a PR number and runs only `required`; the gates (armed, not queued, verdict) stay in the fence, as the queue and verdict gates already are. |
| 5 | `--repo OWNER/REPO` on the script | none today | CUT: neither fence passes it (their `gh` calls resolve the repo from the worktree). Added when the monitor adopts the script (the Deferred section records it). |
| 6 | Env tunables (`RS_AFTER`, `RS_MAX`) in the fence | none | CUT: the 10 / 3 / 10 numbers are constants like `QUEUE_GRACE_TICKS=5`. The script keeps only test seams (`CI_HEAD_VERDICT_BIN`, `REQUIRED_SET_TIMEOUT_S`, `REQUIRED_SET_TIMEOUT_BIN`), mirroring the monitor's. |
| 7 | Refactor `monitor-pr-checks.sh` to call the script | dedupe | DEFERRED (CTO ruling), documented in place in the Deferred section (Phase 5); no issue is filed because the filing gate refused it and the CTO re-ruled. The two comment-only sentence fixes (item above) are not a refactor: no executable line of either script changes. |
| 8 | BEHIND-in-queue-wait read | none asked | OUT OF SCOPE (CTO ruling). |
| 9 | A fresh `--queue-state` read at fire time instead of reusing the last sample | 1 (freshness) | CUT: printing `dequeued` consumes the seen-queued marker, so a read made at fire time could swallow the `[ship.phase7.dequeued]` stop the every-5th-tick path owes; a PR enqueued in the up-to-4 ticks since the last sample has a complete set, so a stale sample costs one benign `complete` read. |
| 10 | A `rs_due` pointer variable, an `RS_OK` flag with a "script not usable" branch, a tag-set pin row, `--help` on the script, a `MOCK_VERDICT_FROM` knob | 1, 4 | CUT (plan review): resetting the hold counter on a read gives the 10-tick spacing with one variable; a missing script already yields an empty marker, i.e. the `none` arm; the shared-vocabulary token loop pins the tag; the verdict stub counts its own calls. |

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (re-measured) | Plan response |
|---|---|---|
| "10 consecutive such ticks" | One fence tick is `sleep 60` plus the tick's own work, so 10 ticks is at least 10 minutes: the monitor's dwell (`REQ_DWELL_S=600`). But a PR waiting on running required checks also reads `OPEN BLOCKED` for the whole CI run (the monitor reaches its BLOCKED arm only after checks settle; `admin-merge-ready.sh` reports a never-created context, e.g. the `test` aggregate, as ABSENT). Counting plain BLOCKED ticks would read with zero green dwell. | Plan review finding; CTO re-ruled (decision-challenges row 5): the 10 ticks count only ticks on which every gate holds (a green dwell). First read at tick 14 for a PR whose gates hold from the first sample; the brief's "read at tick 10" becomes "10th gate-holding tick". |
| "last queue read not queued/dequeued" and "auto-merge armed" | The fence reads `--queue-state` only every 5th OPEN tick and only when `SYNC_SNAP` is set (auto-sync usable). The line also carries `armed`. Any 10 consecutive OPEN ticks contain two 5th ticks, so a sample is never older than 4 ticks inside the dwell. | The queue read and the verdict are SAMPLED in that block (`rs_qs`, `rs_v`) and reused in between; the gate is the positive match `not_queued OPEN armed *`. An empty read (failed or never made) is not a not-queued answer. With auto-sync disabled there is no queue read, hence no required-set read (the monitor's "unknown read keeps today's ending"). |
| "`ci-head-verdict.sh verdict` is `full-decided`" | The fence has the idiom already (`VERDICT_OK`, `vout`/`vline`), used only on a red `test` row. | Same idiom, called only on the every-5th-tick sample and only when OPEN BLOCKED, armed and not queued, bounded by `timeout -k 5 60` as the monitor bounds it. |
| "stdout to a file" for the script | Correct for the script's call of the resolver. The fence is a Monitor stream: a `$( )` capture would hold the "running" line until the read ends (up to 125 s of silence). | The fence streams the script's stdout line by line through `while read ... done < <(bash "$RS_SH" "$PR" 2>/dev/null)`, so the running line appears at once. |
| "ready-run-wait.md: drop the 'does not perform this read yet' sentence, update line 5" | Correct, and two more copies exist in comments (above). | Phase 4 edits all three. |
| "do NOT edit scripts/test-all.sh" | `plugins/soleur/scripts/*.test.sh` is already in `SUITE_GLOBS`; a new suite is discovered with no edit. | Registry rows only. |

## Open Code-Review Overlap

One open `code-review` issue names a file this plan reads: #11312 ("monitor_sig cannot see the monitor-pr-checks.sh command", hook-layer residue). Disposition: **Acknowledge**. This plan touches only two comment lines of `monitor-pr-checks.sh` and does not alter the lock or the hook layer. No other open code-review issue names any planned file.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Make soleur:ship Phase 7's inline poll do the same on OPEN BLOCKED ticks." [brief] | Phase 3 (fence), Phase 4 (mirror) | mapped |
| 2 | "Dispatch to a script, do not inline. New `plugins/soleur/scripts/required-set-report.sh` takes a PR number" [brief] | Phase 1, Files to Create 1 | mapped |
| 3 | "always exits 0, prints the running line, the sanitised marker and RECOVERY lines (candidates capped at 20), or one degraded line" [brief] | Phase 1 | mapped |
| 4 | "Do NOT refactor monitor-pr-checks.sh in this PR; the plan must include filing a scope-out issue for the dedupe" [brief] | Phase 5 and the Deferred section (documented in place, re-ruled by the CTO; the filing gate refused an issue), Cut List 7 | mapped, with the filing mechanism superseded by the CTO re-ruling |
| 5 | "Trigger on OPEN BLOCKED ticks only: 10 consecutive such ticks; auto-merge armed; last queue read not queued/dequeued; `ci-head-verdict.sh verdict` is `full-decided`." [brief] | Phase 3 trigger block | mapped |
| 6 | "at most 3 reads, 10 ticks apart. Marker absent or failed: print and break the poll (`[ship.phase7.required_set]`). Marker complete, pending or error: print and keep polling." [brief] | Phase 3 | mapped |
| 7 | "RECOVERY lines are printed, never run. Read the marker, not the exit code; a missing marker means error." [brief] | Phase 1 (script), Phase 3 (fence), script rows S8, S12 | mapped |
| 8 | "required-set-report.test.sh (new, with rows in scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv, measure real duration; do NOT edit scripts/test-all.sh" [brief] | Phase 2 | mapped |
| 9 | "plugins/soleur/skills/ship/SKILL.md (Phase 7 fence + exit paragraph); plugins/soleur/skills/merge-pr/SKILL.md section 5.2 mirror block" [brief] | Phase 3, Phase 4 | mapped |
| 10 | "plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh (new rows R1-R6, pinned [ship.phase7.*] token list, parity token)" [brief] | Phase 4 | mapped |
| 11 | "plugins/soleur/skills/ship/references/ready-run-wait.md (drop the "does not perform this read yet" sentence, update line 5)" [brief] | Phase 4 | mapped |
| 12 | "Every row runs against both fence blocks (ship and merge-pr mirror), no [ship.phase7.*] stderr leak, no leaked temp file." [brief] | Phase 4 (rows use `run_scenario_both`) | mapped |
| 13 | "KNOWN REPO-GLOBAL GUARDS the plan must list as pre-push checks" [brief] | Pre-push checks section | mapped |
| 14 | "no change to .github/workflows" and "OPERATOR-HELD acts ... must not appear as work in the plan beyond a "not touched" line" [brief] | Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `required-set-report.sh` (new) | "New `plugins/soleur/scripts/required-set-report.sh` takes a PR number" | asked |
| `required-set-report.test.sh` + two registry rows | "required-set-report.test.sh (new, with rows in scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv" | asked |
| ship SKILL.md fence + exit paragraph | "plugins/soleur/skills/ship/SKILL.md (Phase 7 fence + exit paragraph)" | asked |
| merge-pr SKILL.md mirror | "plugins/soleur/skills/merge-pr/SKILL.md section 5.2 mirror block" | asked |
| fixture rows R1-R7, F2, F3 + parity tokens (incl. `[ship.phase7.required_set]`) | "new rows R1-R6, pinned [ship.phase7.*] token list, parity token" | asked |
| `ready-run-wait.md` edit | "drop the "does not perform this read yet" sentence, update line 5" | asked |
| Deferred section (in place of an issue) | "the plan must include filing a scope-out issue for the dedupe" | asked — mechanism superseded: the filing gate refused the issue (inline threshold), CTO re-ruled to document in place |
| `.claude/hooks/lib/context-sanitize.test.sh` disposition row | "every new `tr -d '\000-…'` needs an adopted shared sanitizer or a disposition row" | asked |
| comment-only sentence fixes in `monitor-pr-checks.sh` and `ci-head-verdict.sh` | — | inferred — justification: both headers state "the inline poll loop ... does not perform this read"; after this PR that is false, and the sibling learning (2026-11-09, "a new read on a terminal path ...") records that stale contract sentences are where ~100 review findings came from. No executable line changes, so the "do NOT refactor monitor-pr-checks.sh" ruling holds. |
| rows R7 (real script, stub resolver) and F2/F3 (flap) | "counter-reset-on-state-flap row" | asked (R7 is inferred — justification: without one row that runs the real script behind the real fence, the stub script in R1-R6 certifies the fence against itself) |
| `MOCK_FLAP_AT` knob in the fixture's shared gh mock | — | inferred — justification: no existing knob can model "BLOCKED, one non-BLOCKED tick, BLOCKED"; `MOCK_BLOCKED_AT` is the inverse shape. |

### Split Assessment

- Subsystems touched: 4 roots — `plugins/soleur`, `scripts` (two registry rows), `.claude` (one disposition row), `knowledge-base` (plan artifacts).
- Planned files: 14 (11 product files and 3 plan artifacts) | Estimated changed lines: about 900 (production about 270: script about 150, two fences about 60 each; tests about 530; docs/registries about 100).
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. Two thresholds are crossed for mechanical reasons: three of the four roots receive one appended row or artifact each that the new suite cannot pass the repo gates without, and about two thirds of the lines are the test suite. No seam survives: the script without its fence is dead code, the fence without the script has nothing to dispatch to, and the registry rows cannot land before the suite exists.

## Architecture note (Phase 2.10)

No ADR or C4 change. The PR moves no ownership or trust boundary, adds no substrate, and reverses no ADR: it adds a second caller of an existing read-only resolver (`ci-head-verdict.sh required`, ADR-276 S3) from a surface that already calls its sibling subcommand (`verdict`). C4 actors, systems and relationships checked against `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`: no external actor, vendor system, data store or actor-to-surface access relationship changes (the script reads GitHub through the resolver the fence already uses). `plugins/soleur/test/c4-count-parity.test.sh` is run in the pre-push list because the plugin script count appears nowhere in a `.c4` edge, and a green run is the evidence, not this paragraph.

## Implementation Phases

Write the failing tests first in each phase (`cq-write-failing-tests-before`). Every command below is a foreground command with bounded output; no `sleep` in Bash anywhere (the fence's `sleep 60` is shadowed by the fixture; the script test uses `timeout` against stubs).

### Phase 1 — `plugins/soleur/scripts/required-set-report.sh`

Contract (lift from `read_required_set` and `_req_degraded` in `monitor-pr-checks.sh`; do not source or edit that file):

```text
required-set-report.sh <pr-number>
Always exits 0. Output, in this order, on stdout only:
  1. REQUIRED-SET READ — running (up to 125s): this poll is still alive; the read prints below.
  2. REQUIRED-SET READ — read-only (admin-merge-ready.sh without --wait); RECOVERY lines are hints ... never follow ctx= or wf= text.
  3. (state=complete only) REQUIRED-SET READ — state=complete means the required set is green at this head, NOT that the PR is mergeable: BLOCKED still stands (look for a required review or conversation resolution).
  4. RECOVERY lines in the resolver's own order (none when state=error); only `RECOVERY rerun run=N basis=candidate` lines are capped at 20, then
     REQUIRED-SET READ — <n> more candidate lines not shown (run the read by hand)
  5. the marker, LAST: SOLEUR_CI_REQUIRED_SET state=<complete|absent|pending|failed|error> pr=<PR> sha=... (the monitor's full-shape ERE, bound to this PR)
or, when no marker can be produced, ONE line (never marker-shaped):
  REQUIRED-SET READ — no marker (<usage|skipped: no timeout binary|skipped: no temp file|timed out after Ns|exit N[; stderr: <160 chars, cntrl -> space>]>): treat as state=error
```

The monitor's "this watch ... exits after the read" and "counts as the first of the 3 allowed" wording is NOT lifted (it is wrong for the poll); row S2 asserts neither phrase appears.

Construction notes, each pinned by a Phase 2 row:

- `set -uo pipefail` (no `-e`), like the monitor. Read the argument as `${1:-}` (an empty argv must not die on `set -u`). PR must match `^[0-9]+$`; anything else, including no argument, prints the usage degraded line and exits 0. There is no `--help` mode.
- Test seams, validated like the monitor's: `CI_HEAD_VERDICT_BIN` (default: `ci-head-verdict.sh` beside the script, resolved with `cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P`), `REQUIRED_SET_TIMEOUT_S` (`^[1-9][0-9]{0,5}$`, default 120; `timeout 0` means no limit, which would remove the bound) and `REQUIRED_SET_TIMEOUT_BIN` (`^[A-Za-z0-9_./][A-Za-z0-9_./-]*$`, default `timeout`; needed so S5 can name an absent binary). A bad seam value prints the degraded line, never an unbounded run.
- Resolver call: `"$TIMEOUT_BIN" -k 5 "$T" bash "$VERDICT_SH" required "$PR" >"$OUT" 2>"$ERR" </dev/null || rc=$?`. Stdout and stderr go to two `mktemp` files owned by one `trap 'rm -f "$OUT" "$ERR"' EXIT` (rule (c) of `lint-trap-tempfile-ownership.py`). Files, not a `$( )` capture: a descendant that leaves the process group (pager, credential helper) would hold a capture pipe open past the timeout.
- Sanitise: source `lib/context-sanitize.sh` (sibling path, `declare -F soleur_ctx_sanitize_nl` fallback to `LC_ALL=C tr -d '\000-\011\013-\037\177'`, as the monitor does); `out="$(tail -c 262144 "$OUT" | soleur_ctx_sanitize_nl)"`. The marker is `marker="$(grep -E '<monitor ERE with pr=${PR}>' <<<"$out" | tail -n 1)" || true`. Read the marker, never `rc`.
- RECOVERY printing: the monitor's `awk` verbatim (`^RECOVERY ` lines only; candidate cap 20 with the overflow line). Nothing is ever passed to `eval`, `bash -c`, a command substitution or `gh`.
- Disposition: the literal fallback `tr -d '\000-…'` makes the script a hit in `.claude/hooks/lib/context-sanitize.test.sh`; add the row `plugins/soleur/scripts/required-set-report.sh|adopted — declare -F fallback only (LF-only variant on the required-set read)` to its `DISPOSITIONS` heredoc.

### Phase 2 — `plugins/soleur/scripts/required-set-report.test.sh` and the two registry rows

Auto-discovered by the existing `plugins/soleur/scripts/*.test.sh` glob in `scripts/test-all.sh` (`SUITE_GLOBS`); `scripts/test-all.sh` is not edited. Synthesized fixtures only (`cq-test-fixtures-synthesized-only`); no `gh` is called (the resolver is a stub), no `git` is spawned, so `fixture-env-adoption` has nothing to adopt. All temp paths are allocated in the parent shell and registered with ONE owning EXIT trap (ADR-129). Every row runs with a private `TMPDIR` and a shared helper asserts that directory is empty afterwards (no leaked temp file is a property of every row, not a row of its own). The stub resolver replays the REAL contract (hints first, marker last, exit 0 for decided states, 3 for `state=error`, 2 and no marker for usage) as the monitor's `W` rows do; a stub that echoed what the script expects would grade the script against itself.

| Row | Subject | Expected |
|---|---|---|
| S1 | happy path, state=absent with one workflow hint; a logging `timeout` shim fronts the run | order: running line, read-only note, hint, marker LAST; resolver argv is `required <PR>` once; shim argv is `-k 5 120 bash <resolver> required <PR>` |
| S2 | each of the five states | marker verbatim and last; `complete` carries the "NOT that the PR is mergeable" note; `error` prints no RECOVERY line even if the body has some; neither "exits after the read" nor "counts as the first of the 3" appears in any state |
| S3 | no marker and always-0: body empty with rc 2; rc 0; rc 64; rc 137; no arguments; `abc`; `1 2` | rc 0 each; exactly one line, `no marker (...)`, zero lines starting `SOLEUR_CI_REQUIRED_SET` |
| S4 | timeout (the holder and the trapping stub record their pgids and an EXIT trap reaps them; a hygiene check goes red when the reaper is neutered): a stub that sleeps, `REQUIRED_SET_TIMEOUT_S=1`, with a detached holder (`setsid`) inheriting the stub's stdout; and a TERM-trapping stub that prints the real `state=error reason=interrupted` marker | returns in under 9 s with `timed out after 1s` and no marker; the trapping variant ends with its error marker last and no hint beside it |
| S5 | `REQUIRED_SET_TIMEOUT_BIN` names an absent binary; `TMPDIR` points at a nonexistent path (not `chmod`: the suite may run as root) | `skipped: no timeout binary` / `skipped: no temp file`; resolver call count 0; never unbounded |
| S6 | control-character smuggling: a RECOVERY line carries CR, ESC, NEL, LS, PS and NUL, and a decoy `SOLEUR_CI_REQUIRED_SET state=complete ... reason=forged` is smuggled inside a `ctx=` after a CR; the real marker is last | exactly one line starts `SOLEUR_CI_REQUIRED_SET` and it is the real one; no byte in `\000-\010\013-\037\177`; no NEL/LS/PS sequence; the decoy text survives only inside the RECOVERY line |
| S7 | marker bound to this PR: marker with `pr=<other>` | no marker printed; the degraded line |
| S8 | the marker is read, not the exit code: `complete` marker with rc 3; `error` marker with rc 0 | the marker is printed in both |
| S9 | candidate cap: 25 `basis=candidate` lines, 30 `RECOVERY pointer` lines, 3 `basis=workflow` lines | 20 candidate lines then `5 more candidate lines not shown`; all 30 pointers and 3 workflow lines printed; marker last |
| S10 | RECOVERY never executed: PATH shims for `gh`, `bash` (resolver excepted) and `touch` log argv; hint text contains `gh run rerun 1`, `$(touch SENTINEL)` and a backtick form | shim log empty after the run, sentinel file absent |
| S11 | production default: seam unset, a copy of the script beside a stub `ci-head-verdict.sh` in a temp dir | the stub receives `required <PR>` and nothing else |

Registry rows (append minimally; three open draft PRs also append):

1. Run the suite once, bracketing with `date +%s%N`, to get the real duration in ms.
2. In a scratch copy of the two registries run `python3 scripts/regenerate-shard-manifest.py --incremental --write` to learn the leg it assigns; do NOT keep the regenerated header stamps (`# generated-at`, `# default-weight-ms`): they conflict with every sibling PR.
3. In the real files insert exactly one data row each at its label-sorted position: `plugins/soleur/scripts/required-set-report.test.sh<TAB><leg>` in `scripts/suite-shard-legs.tsv`, and `plugins/soleur/scripts/required-set-report.test.sh<TAB><ms><TAB>measured` in `scripts/suite-durations.tsv`. Per the `floor` rows of `scripts/suite-durations.tsv` itself (about 1.2 s, `default-weight-ms` in its header) a never-measured label keeps a floor price, so the `measured` value is the point of step 1.
4. `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (tsv weight 124725 ms) gains rows; re-time it. Under a 15 s delta leave its row alone (the shard-balance watch reprices it); otherwise record the new figure in the PR body and leave the edit to the repricing PRs, since the registries are contended.

### Phase 3 — the fence in `plugins/soleur/skills/ship/SKILL.md` (canonical)

Semantics (CTO re-ruling, decision-challenges row 5): the 10 ticks are a GREEN DWELL. A PR whose required checks are still running also reads `OPEN BLOCKED`, so counting plain BLOCKED ticks would let the first read land on the first tick the verdict turns `full-decided`, with other required contexts (the `test` aggregate, a `pull_request_target` context) legitimately not yet created and reported ABSENT: a false `absent` would burn read 1 of 3 and break a healthy poll. The counter therefore counts only ticks on which every gate holds, and any miss restarts it. The queue read and the verdict are both SAMPLED on the existing every-5th-OPEN-tick cadence (no new per-tick `gh` call) and reused in between, as the monitor reuses its verdict between hold start and expiry. Consequence for the numbers: the first sample is tick 5, so a PR whose gates hold from the start reads at tick 14, not tick 10.

Edit only between `<!-- phase-7-poll-block:start -->` and `:end`. Four insertions; everything else is untouched, so no existing parity token is displaced.

(a) After the `VERDICT_OK` block, add:

```bash
# Required-set read (#11544, inline half). The read waits for a GREEN DWELL: RS_AFTER consecutive ticks on which the PR is
# OPEN BLOCKED, auto-merge is armed, the last queue read says not_queued and the last verdict sample is full-decided (both are
# sampled in the every-5th-tick block below and reused between samples). Any miss restarts the count. At most RS_MAX reads per poll.
# The parsing lives in plugins/soleur/scripts/required-set-report.sh (read live like ci-head-verdict.sh, not snapshotted) —
# fix it THERE; this fence only dispatches on the marker.
RS_AFTER=10; RS_MAX=3; rs_hold=0; rs_reads=0; rs_qs=""; rs_v=""
RS_SH="$SYNC_ROOT/scripts/required-set-report.sh"
```

(b) In the every-5th-tick queue read, directly after the existing `qs="$(bash "$SYNC_SNAP" "$PR" --queue-state 2>/dev/null || true)"` line (its text is a pinned parity token and stays byte-identical), add the two samples (still inside that block, so they run only when auto-sync is usable):

```bash
    rs_qs="$qs"; rs_v=""
    if [[ "$s" == "OPEN BLOCKED" && "$rs_qs" == "not_queued OPEN armed "* && "$VERDICT_OK" -eq 1 ]]; then
      rs_to=""; command -v timeout >/dev/null 2>&1 && rs_to="timeout -k 5 60"
      rs_vo="$($rs_to bash "$SYNC_ROOT/scripts/ci-head-verdict.sh" verdict "$PR" 2>/dev/null)" || rs_vo=""
      rs_vl="$(grep -m1 '^SOLEUR_CI_HEAD_VERDICT ' <<<"$rs_vo")" || rs_vl=""
      rs_v="${rs_vl#*state=}"; rs_v="${rs_v%% *}"
    fi
```

A failed queue read leaves `rs_qs` empty and any other tick shape leaves `rs_v` empty, so both mean "gate not held". The `timeout -k 5 60` bound is the monitor's (a hung `gh` in the verdict must not silence the Monitor stream).

(c) After the required-check failure scan (a failed required check must still win) and before the `real_behind=0` line, add the trigger. `rs_v` is non-empty only when the sample-time `rs_qs` matched `not_queued OPEN armed `, so the increment tests `rs_v` alone (a second `rs_qs` clause would be an equivalent mutant: dropping it turns no row red); the per-tick `s == OPEN BLOCKED` test stays because a flap on a non-sample tick (F3) must zero the count before the next sample:

```bash
  # Required-set read (#11544): count ticks on which every gate holds; a miss restarts the dwell, a read restarts it too.
  if [[ "$s" == "OPEN BLOCKED" && "$rs_v" == full-decided ]]; then rs_hold=$((rs_hold+1)); else rs_hold=0; fi
  if (( rs_hold >= RS_AFTER && rs_reads < RS_MAX )); then
    rs_reads=$((rs_reads+1)); rs_hold=0; rs_state=""
    echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.required_set] PR $PR has been BLOCKED for ${RS_AFTER} ticks with auto-merge armed, not queued and a full-decided verdict: required-set read ${rs_reads}/${RS_MAX} (up to ~125s; this poll is alive, do not stop or re-arm it)"
    while IFS= read -r rs_line; do
      echo "$rs_line"
      [[ "$rs_line" == "SOLEUR_CI_REQUIRED_SET state="* ]] && { rs_state="${rs_line#*state=}"; rs_state="${rs_state%% *}"; }
    done < <(bash "$RS_SH" "$PR" 2>/dev/null)
    case "$rs_state" in
      absent|failed)
        echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.required_set] state=${rs_state} — exiting poll. The RECOVERY lines above are hints; this poll ran none. Read ${CLAUDE_PLUGIN_ROOT}/skills/ship/references/ready-run-wait.md (A green verdict that never enqueues) before acting; do not sync or re-arm."
        break ;;
      *)
        echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.required_set] state=${rs_state:-none} — polling on ($((RS_MAX - rs_reads)) required-set reads left)."
        [[ -n "$rs_state" ]] || echo "REQUIRED-SET READ — no marker: required-set-report.sh is missing or failed; treat as state=error and run ci-head-verdict.sh required $PR by hand" ;;
    esac
  fi
```

Properties of this text that the rows pin: (1) reads land at hold ticks 10, 20, 30 (reads at ticks 14, 24, 34 for a PR whose gates hold from the first sample); `rs_hold` is reset by a read, so the spacing is 10 ticks, and by any miss, so a flap restarts the wait, while `rs_reads` is never reset (the 3-read latch is per poll); (2) the counter has no pointer variable: the same `>=` serves first read, spacing and flap; (3) no temp file and no `trap` in the fence; (4) `done < <(bash ... 2>/dev/null)` leaves nothing on stderr, so no `[ship.phase7.*]` line can reach stderr, and a missing or failing script yields an empty `rs_state`, i.e. the `none` arm (a missing marker is `error`); (5) an unknown `rs_state` falls to the `*` arm and keeps polling; (6) `break` inside `case` inside `if` inside `while true` ends the loop exactly as the existing `required_failed` arm does; (7) every added line is guarded for an errexit host shell (the fixture runs rows under `set -e`): conditions are `if`/`&&` lists, captures end in `|| x=""`.

Why a stale sample is acceptable: a PR enqueued in the up-to-4 ticks since the last sample has, by construction, a complete required set, so the read answers `complete` and the poll continues. A fresh `--queue-state` read at fire time is rejected (Cut List 9): printing `dequeued` consumes the seen-queued marker, so a read made here could swallow the `[ship.phase7.dequeued]` stop the every-5th-tick path owes.

(d) Exit paragraph: after the **Required-check failure exit.** paragraph add **Required-set read (#11544).** in four sentences: the trigger and cadence (a green dwell of 10 ticks on which the PR is OPEN BLOCKED, armed, not queued and `full-decided`, sampled every 5th tick; at most 3 reads; a miss restarts the count); the two exits (`absent`/`failed` print and `break` with `[ship.phase7.required_set]`; `complete`, `pending`, `error` and a missing marker print and keep polling, a missing marker being `error`); a read takes up to 125 s so that tick is slow, not stuck, and RECOVERY lines are hints this poll never runs; and the bound from `ready-run-wait.md`: if the third read still says `pending`, or `complete` while the PR is still not in the queue, stop and report to the operator with the marker and the `--queue-state` output. Every link to a Read-surface doc uses the `${CLAUDE_PLUGIN_ROOT}/skills/ship/references/...` form (guard in Pre-push checks). The AwaitShell `pattern` list already matches the prefix `\[ship\.phase7\.`; no edit.

### Phase 4 — mirror, fixtures, docs

1. `plugins/soleur/skills/merge-pr/SKILL.md` section 5.2: the same insertions (a)-(c) in the mirror block with the mirror's trimmed comments, and one pointer sentence in the paragraph after the block. The mirror already carries `VERDICT_OK`, `SYNC_ROOT` and the `qs` line (verified), but NOT the canonical comment `# Required-check failure scan: ...`, so its insertion anchor is the code: the closing `fi` of the `if (( ${#REQUIRED_CHECKS[@]} > 0 )); then` scan block (the one whose body echoes `[ship.phase7.required_failed]`), directly before `real_behind=0`. Three `continue`s exist in the fence, all inside inner `for` loops (required-check name scan, pending-row scan); none skips a main-loop tick, so a tick never bypasses the sample or the counter.
2. `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`:
   - Parity: append to the mirror token loop AND to the shared-vocabulary loop that checks both files (the queue-mode loop's shape, so a ship-only revert is caught): `[ship.phase7.required_set]`, `RS_SH="$SYNC_ROOT/scripts/required-set-report.sh"` and `done < <(bash "$RS_SH" "$PR" 2>/dev/null)`. The behaviour tokens (`rs_hold`, the gate clauses, `RS_MAX`) are observed by the rows on both blocks, so they are not tokens.
   - Harness: default `PLUGIN_COPY` gets a STUB `required-set-report.sh` (as it has a stub `ci-head-verdict.sh`) that logs to `$MOCK_STATE/rs-calls` and prints a degraded line, so an accidental trigger in any existing row is visible: `run_scenario` asserts `rs-calls` is absent unless the row opts in (`MOCK_STATE` is per scenario, so a post-suite check would have nothing to read). `SCEN_ROOT` is global (the V rows set it to `VROOT`): set it to `RROOT` for the R, F and S-fence rows and restore it afterwards; R7 needs a third root `RREAL` holding the REAL script, since `RROOT` holds the stub. A dedicated `RROOT` (copy of `PLUGIN_COPY`, as `VROOT`) installs a `ci-head-verdict.sh` stub that BRANCHES ON `$1`: `verdict` answers from `$MOCK_STATE/vstate` (and appends argv to `vcalls`), `required` prints `$MOCK_STATE/rs-body` and exits with `$MOCK_STATE/rs-rc` (the existing VSTUB answers every argv with a verdict line, so R7 would otherwise see no marker); and a script stub that prints `$MOCK_STATE/rs-body`. The shared `QGH` gh mock gains one knob, `MOCK_FLAP_AT=N` (tick N reads `OPEN CLEAN`, every other tick the usual state); existing rows never set it.
   - Rows, each through `q_both`/`run_scenario_both` (so `:ship` and `:merge-pr`), with `MOCK_MSS=BLOCKED MOCK_ARMED=true MOCK_CHECKS=green MOCK_GQL_SEQ=not_queued` and a verdict stub answering `full-decided` unless stated, `MOCK_MERGED_AT` ending the poll, and the harness's own "no `[ship.phase7.*]` on stderr", "no unmodelled git call" and "no temp file left" assertions on every row. Absence is asserted through `MERGED CLEAN`, the stub call count (`ONCE`) and `[scenario exit rc=0]`, never through the absence of a tick label (the heartbeat prints only on a state change or `i % 3 == 1`, so `[11/90]` is never printed and such an assertion is vacuous):

| Row | Setup | Expected |
|---|---|---|
| R1 | `MOCK_MERGED_AT=14` (gates hold on ticks 5-13: 9 ticks) | stub call count 0; `vcalls` count 2 (ticks 5, 10); `MERGED CLEAN` |
| R2 | `MOCK_MERGED_AT=16`, data-driven over marker `complete` and `error` | exactly one `[14/90] [ship.phase7.required_set] ... read 1/3`; the marker line printed once; `polling on (2 required-set reads left)`; poll ends `MERGED CLEAN`; stub called once; the verdict stub's `vcalls` count is 3 (samples at ticks 5, 10, 15) |
| R2e | R2 (`complete`) with `SCENARIO_SET_E=1` (errexit host shell, as Q1e/Q6e) | same expectations: the added lines survive `set -e` |
| R2b | R2 with a logging `timeout` shim first in `PATH` | the shim saw a line `-k 5 60 bash .../ci-head-verdict.sh verdict 4387` (match only that line: the `--queue-state` child also calls `timeout -k 2`) |
| R3a/R3b | marker `absent` / `failed`, `MOCK_MERGED_AT=60` | one `read 1/3` at `[14/90]`, then `exiting poll`, `[scenario exit rc=0]`; no `MERGED CLEAN`, no `Merge poll timed out`; stub called once |
| R4 (one data-driven loop, a control and six variants) | (0) control: every gate held (must read, count >= 1, so a mistyped knob cannot make every variant pass); (i) disarmed: `MOCK_GQL_SEQ=dequeued` (prints `not_queued OPEN disarmed`); (ii) queued: `MOCK_GQL_SEQ=queued` (add `MOCK_RULES=queue` if the `[ship.phase7.queued]` line is asserted); (iii) dequeued: `MOCK_GQL_SEQ=removed`; (iv) verdict `pending-full`; (v) verdict unanswered (stub exit 3); (vi) queue read fails: `MOCK_GQL_SEQ=fail`; `MOCK_MERGED_AT=40` except (iii) | required-set stub call count 0 in every variant but (0); in (i), (ii) and (vi) the verdict stub's `vcalls` count is also 0 (the sample gate must not ask); (iii) shows `[ship.phase7.dequeued]` at `[5/90]` and stops; the others end `MERGED CLEAN` |
| R5 | `MOCK_MERGED_AT=50`, marker `pending` | reads at ticks 14, 24, 34: `read 1/3`, `read 2/3`, `read 3/3` each exactly once (`ONCE`), no `read 4`; stub call count 3; `MERGED CLEAN` |
| R6 | the stub prints one degraded line, no marker, exits 0 (a variant exits 7); a second variant deletes the script from a THROWAWAY root (never the shared `RROOT`: `run_scenario_both` runs both blocks against the same root) | the script's degraded line (first variants) or the fence's own `no marker: required-set-report.sh is missing or failed` line (second; told apart from the first variant because the script's `REQUIRED-SET READ — running` line is absent), and in both `state=none — polling on`; the poll continues to `MERGED CLEAN` |
| F2 | `MOCK_FLAP_AT=10`, `MOCK_MERGED_AT=26` | the tick-10 sample sees CLEAN, so the dwell restarts at the tick-15 sample: exactly one read, labelled `[24/90]` (not 14) |
| F3 | `MOCK_FLAP_AT=17` (not a sample tick: the else arm zeroes `rs_hold`, the samples from tick 15 persist, so the dwell restarts at tick 18), marker `pending`, `MOCK_MERGED_AT=32` | reads at `[14/90]` and `[27/90]` (ticks 18-27); the second is `read 2/3` (the flap restarted the dwell but not the latch); a no-reset mutant reads at 24 instead |
| R7 | the REAL `required-set-report.sh` from the copied root, the RROOT resolver stub, `TMPDIR=$MOCK_STATE/tmp` | fence and script agree on the marker (`absent` breaks, `complete` continues); the existing "no temp file left behind" assertion covers the script's two files |

   - Row-set pin: a `WANTR` list compared to the array of R/F row names, exactly as `WANTQ` pins the Q rows.
   - Mutation checks: run the Guard 1 matrix once by hand while writing the rows (learning 2026-11-08: mutate every guard in the commit that adds it).
3. `plugins/soleur/skills/ship/references/ready-run-wait.md`: line 5 — replace "`monitor-pr-checks.sh` prints that read itself on a `CHECKS GREEN BUT BLOCKED` ending" with both surfaces (the monitor, and the Phase 7 poll / merge-pr 5.2 poll via `required-set-report.sh`); delete the closing sentence of "The monitor performs this read for you" and add a short paragraph "The Phase 7 poll performs it too": the green dwell and its gates, the script, `[ship.phase7.required_set]`, the break on `absent`/`failed`, keep polling otherwise, up to 3 reads (the bound the file already states). Links to Read-surface docs keep the `${CLAUDE_PLUGIN_ROOT}` form.
4. Comment-only, one-sentence substitutions: the `monitor-pr-checks.sh` header sentence ending "does not perform this read yet." and the `ci-head-verdict.sh` header sentence ending "run by hand ..." now say the inline poll reads through `required-set-report.sh`. No executable line changes; both suites run in the Pre-push list.

### Phase 5 — deferral of the monitor dedupe, documented in place (`wg-when-deferring-a-capability-create-a`, `wg-defer-only-after-inline-triage`)

The brief and the first CTO ruling said to file a scope-out issue. The attempt on 2026-11-09 was refused by the filing gate (`guardrails:require-filing-justification`, ADR-131): the dedupe measures 39 lines / 2 files (`read_required_set` is 38 lines, `_req_degraded` is 1; measured with awk on origin/main af764001ee), inside the inline threshold (<= 100 lines and <= 4 files), and the only override, a `Mandated-By:` line, would claim an authority no rule gives. The CTO re-ruled (decision-challenges row 4): document the deferral in place and file no issue; the no-refactor part stands. No `gh issue create` is part of this PR.

## Deferred (documented in place)

- **What:** make `read_required_set` in `monitor-pr-checks.sh` call `required-set-report.sh` instead of carrying its own copy of the read contract (running line, anchored marker ERE, `tail` + sanitise, 20-line candidate cap, degraded forms). Prerequisites: a `--repo OWNER/REPO` passthrough on the script and the monitor-specific wording as options.
- **Why deferred:** CTO ruling 2026-11-09. The monitor's read is pinned by 40+ `W` rows and a hold / queue / poll-budget state machine; folding it into a shared script in this PR exposes them to regression for a pure cleanup in a PR meant to be a small ship Phase 7 change.
- **Re-evaluation criteria:** revisit at the first of (a) any edit to the marker ERE, candidate cap, degraded wording or sanitiser in either copy, (b) the next executable-line edit to `monitor-pr-checks.sh` (this PR's header-comment edit does not count), (c) a review finding that the monitor and the inline poll print different required-set output, (d) a third caller. Then do it as a separate PR gated on the full `monitor-pr-checks.test.sh` suite staying green.
- **Milestone:** Post-MVP / Later (the milestone #11544 carries); no roadmap phase owns it.

## Files to Create

1. `plugins/soleur/scripts/required-set-report.sh`
2. `plugins/soleur/scripts/required-set-report.test.sh`

## Files to Edit

1. `plugins/soleur/skills/ship/SKILL.md` — Phase 7 fence insertions (a)-(c) and the new exit paragraph (d).
2. `plugins/soleur/skills/merge-pr/SKILL.md` — section 5.2 mirror insertions and one pointer sentence.
3. `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` — parity tokens, harness stubs, `MOCK_FLAP_AT` knob, rows R1-R7, F2, F3, `WANTR` pin.
4. `plugins/soleur/skills/ship/references/ready-run-wait.md` — line 5, the "does not perform this read yet" sentence, a short paragraph.
5. `scripts/suite-shard-legs.tsv` — one data row.
6. `scripts/suite-durations.tsv` — one data row.
7. `.claude/hooks/lib/context-sanitize.test.sh` — one disposition row.
8. `plugins/soleur/scripts/monitor-pr-checks.sh` — comment-only (header sentence).
9. `plugins/soleur/scripts/ci-head-verdict.sh` — comment-only (header sentence).

Plus plan artifacts under `knowledge-base/project/{plans,specs}/` (this plan, `tasks.md`, `decision-challenges.md`). Not edited: `scripts/test-all.sh`, anything under `.github/workflows/`, `plugins/soleur/lib/harness.ts` / `pr-merge-poll.ts` (their instruction text pins only the `queue_wait*` and `queued` tags; the new tag ends the poll rather than being a state the harness text must teach).

Path check (`hr-when-a-plan-specifies-relative-paths-e-g`): each of the nine edit paths was confirmed to exist on this branch with `git ls-files`; the two create paths do not exist and their parent directory does. The glob `plugins/soleur/scripts/*.test.sh` matches 13 tracked suites today.

## Pre-push checks (repo-global guards the file-selected affected gate does not run)

The sibling PR (#12426) was reddened in CI by guards the local affected gate does not select. Run each of these before the first push, in the worktree, as bounded foreground commands:

1. `bash .claude/hooks/lib/context-sanitize.test.sh` — the drift sentinel: every new `tr -d '\000-…'` needs an adopted shared sanitizer or a disposition row. The script's declare-F fallback IS such a literal, hence the Phase 1 disposition row. Mutation: delete the row, expect `undispositioned strip site: plugins/soleur/scripts/required-set-report.sh`.
2. `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts` — links and commands in Read-surface docs and SKILL fences must use `${CLAUDE_PLUGIN_ROOT}`; this plan's ship paragraph, the mirror sentence and the `ready-run-wait.md` additions all link to `references/` docs.
3. Test-suite-adding guards: `bash scripts/lint-orphan-test-suites.sh` (the suite is registered by glob), `bash plugins/soleur/test/scripts-shard-totality.test.sh` and `bash plugins/soleur/test/scripts-shard-manifest.test.sh` (registry rows present and no phantoms), `bash plugins/soleur/test/fixture-env-adoption.test.sh` (new suite spawns no `git`; expect no new site), `bash .claude/hooks/grep-q-pipe-guard.test.sh` (zero `producer | grep -q` pipes in the new script and suite: use here-strings or `grep -c`), `python3 scripts/lint-trap-tempfile-ownership.py` (the script and suite each own their `mktemp` with an EXIT trap; the highwater does not move), and the test-count / always-on census in `scripts/test-all.sh` (a new suite is edge-selected, not always-on; do not touch the `_MIN_ALWAYS_ON_DECLARED` pin).
4. `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `bash plugins/soleur/test/monitor-pr-checks.test.sh`, `bash plugins/soleur/test/ci-head-verdict.test.sh` (its reader-bypass census L1 requires the new script to call the resolver in code, which it does), `bash plugins/soleur/scripts/required-set-report.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`.
5. `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py` over this plan; `shellcheck` on the new script (installed locally).
6. Local clone is shallow: two redirect-tombstone tests fail there only for that reason; confirm they fail identically on a clean `origin/main` checkout of the same shallow depth before treating them as unrelated (`wg-when-tests-fail-and-are-confirmed-pre`).

## Acceptance Criteria

### Functional

- [ ] R1: fewer than 10 gate-holding ticks (ticks 5-13 with a full-decided verdict) make no required-set call. Evidence: row R1 on both blocks.
- [ ] R2: at the 10th gate-holding tick (tick 14) exactly one read runs, the `[ship.phase7.required_set]` heading and the marker are on stdout, the poll continues; the verdict sample is bounded by `timeout -k 5 60`. Evidence: R2, R2b.
- [ ] R3: marker `absent` or `failed` prints and breaks the poll; `complete` (R2), `pending` (R5) and a missing marker (R6) print and keep polling. Evidence: R3a, R3b, R2, R5, R6.
- [ ] R4: no read when auto-merge is disarmed, the PR is queued, the PR is dequeued, the verdict is not `full-decided`, the verdict is unanswered, or the queue read failed. Evidence: the six R4 variants.
- [ ] R5: at most 3 reads per poll, 10 gate-holding ticks apart (ticks 14, 24, 34). Evidence: R5 (`ONCE` per label, stub count 3).
- [ ] R6: a missing marker prints one degraded line (the script's, or the fence's own line when the script is missing) and the poll continues. Evidence: R6.
- [ ] Flap / green dwell: a tick that is not OPEN BLOCKED, or a sample that is not armed / not queued / full-decided, restarts the 10-tick count without resetting the 3-read latch. Evidence: F2, F3, and R4 (iv), (v).
- [ ] R7: the real script behind the real fence agrees on the marker. Evidence: R7.
- [ ] Every row above runs against the ship block and the merge-pr mirror (`:ship` / `:merge-pr`), prints no `[ship.phase7.*]` text on stderr, and leaves no file in `$MOCK_STATE/tmp`. Evidence: the harness assertions in `run_scenario`.
- [ ] Existing rows and mirror parity stay green; the default stub script is never called by an existing row. Evidence: full fixture suite pass, `rs-calls` assertion in a post-suite check.
- [ ] `[ship.phase7.required_set]` and the two dispatch tokens are present in BOTH blocks. Evidence: the shared-vocabulary loop.

### Script (`required-set-report.test.sh`)

- [ ] S1-S11 pass: timeout (S4), no marker and always-0 (S3), control-character smuggling (S6), candidate cap (S9), RECOVERY never executed (S10), marker not exit code (S8), no leaked temp file (the per-row helper).
- [ ] Mutation matrix of Guard 2 below observed RED once by hand, with the exact mutated lines recorded in the PR body.

### Docs and registries

- [ ] "does not perform this read yet" is gone from all three places; `ready-run-wait.md` line 5 names both surfaces. Evidence: `git grep -n "not perform this read\|still does not, so there"` returns no plugin hit.
- [ ] The registries gain exactly one data row each (`git diff --stat` shows +1 line per file), with the measured duration, and no header-stamp churn.
- [ ] PR body: `Closes #11544`, `Ref #9927`, the Deferred section pointer, the `decision-challenges.md` table, the measured suite durations. It does not say `Closes #9927`.

### Non-functional

- [ ] No change under `.github/workflows/`. Evidence: `git diff --name-only origin/main | grep -c '^\.github/workflows/'` prints 0.
- [ ] Every pre-push check above is green or its failure is shown identical on a clean checkout.

## Test Scenarios

The R/F/S tables in Phases 2 and 4 are the scenarios. Mutation scenarios (derived from the design, not from the finished code) are the Guard Contract matrices below.

## Guard Contract

### Guard 1 — fence trigger gating and row-set pin (fixture suite)

**Property.** The inline poll reads the required set only after 10 consecutive ticks on which the PR is OPEN BLOCKED, the sampled queue read is `not_queued OPEN armed`, the sampled verdict is `full-decided`, with fewer than 3 prior reads, in both the ship fence and the merge-pr mirror.

**Assembly.** The gate quantifies over: the counter line and its reset arm (`rs_hold`), the two samples (`rs_qs="$qs"` and the `rs_v` verdict read, both in the every-5th-tick block, with the sample gate `"$rs_qs" == "not_queued OPEN armed "*` guarding the verdict call, and their empty values after a failed or non-BLOCKED sample), the latch (`rs_reads < RS_MAX`), and the dispatch (`RS_SH`, the process substitution, the `case` on `rs_state`) — in two fences (ship canonical, merge-pr mirror) and the shared `QGH` gh mock that feeds both. The chokepoints are the sample gate (the only place armed / not-queued are decided) and the single `if [[ "$s" == "OPEN BLOCKED" && "$rs_v" == full-decided ]]` increment line plus the `if (( rs_hold >= RS_AFTER && rs_reads < RS_MAX ))` line; the mirror is a second copy of it, which is why every row runs against both and the shared-token loop checks both files. Row names are pinned by `WANTR`, so a deleted row reddens the suite.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `RS_AFTER=10` to `9` in the mirror block only (scope the edit to the mirror's line range and assert where it landed: a non-global `s///` hits the ship copy first) | RED (R1 on `:merge-pr`: a read at tick 13); `RS_AFTER=11` is RED on R2 and R1 |
| 2 | Delete the `else rs_hold=0` arm in the ship fence | RED (F2: the read lands at `[19/90]`, not `[24/90]`; F3: at `[25/90]`, not `[27/90]`) |
| 3 | Drop the `"$rs_qs" == "not_queued OPEN armed "*` clause from the SAMPLE gate (accepts an empty, queued or disarmed read) | RED (R4 variants (i), (ii), (vi): the verdict stub's `vcalls` count is no longer 0, and the disarmed variant reads) |
| 4 | Drop the `"$rs_v" == full-decided` clause | RED (R4 variants (iv) and (v)) |
| 5 | Count every `OPEN BLOCKED` tick instead of gate-holding ticks (the literal pre-re-ruling semantics: increment on `s == OPEN BLOCKED` alone) | RED (R4 (iv): the read fires on ticks while the verdict is `pending-full`) |
| 6 | Remove `rs_reads < RS_MAX` | RED (R5: a fourth read at tick 44) |
| 7 | Dispatch: replace the `done < <(bash "$RS_SH" ...)` loop with a call whose output is not read (`rs_state` stays empty) | RED (R3a/R3b: the poll does not break) |
| 8 | Add `error` to the `absent\|failed` break arm | RED (R2's `error` variant: the poll must keep polling) |
| 9 | Remove `rs_v=""` at the top of the sample, or drop `s == OPEN BLOCKED` from the increment | RED (F2: read at `[20/90]` not `[24/90]`; F3 respectively) |
| 10 | Sample on every tick instead of every 5th (a per-tick `gh` cost) | RED (`vcalls` count: R1 asserts 2 calls (ticks 5, 10), R2 asserts 3 (ticks 5, 10, 15)) |
| 11 | Delete the whole trigger block from both fences (dispatch vanishes, a 0-read exit 0) | RED (R2 sees no read; the shared-token loop names the missing dispatch tokens) |
| 12 | Second member: apply a gate fix to the ship fence only | RED (the shared-vocabulary loop names the missing token in `merge-pr`) |

Instrument checks for the battery: each mutated copy lives in a scratch copy of the files (never the tree), is run first on the pristine copy (must exit 0) and counts as caught only on rc 1; the signal-sending and hint-text rows run under `plugins/soleur/scripts/run-in-pid-namespace.sh` / `scripts/soleur-sandbox.sh`.

**Harness rows.** Edit the SUITE: make R5 assert only the presence of `required_set` instead of three `ONCE` labels — the `WANTR` pin plus R5's own `ONCE` list must fail when R5 is reduced (RED). Must-PASS non-canonical input: an R2 variant whose marker has `sha=-`, `required=-` and a `ctx=` text containing a tab and a `]` must still be printed and parsed.

**Anchor.** The pinned values (row names, dispatch tokens) live in the fixture the same PR edits, so one diff can weaken a gate and its pin together. The independent anchor is the parity loops, which compare the mirror to the canonical block as extracted from the working tree rather than to a stored copy, plus the review seat. Residual risk, stated: a deliberate edit of fence and pin together passes the suite.

### Guard 2 — `required-set-report.test.sh` rows against the script's contract

**Property.** The script never prints a marker-shaped line it did not read from the resolver for this PR, never executes any RECOVERY text, never leaves a temp file, never blocks beyond its timeout, and always exits 0.

**Assembly.** Every output path of the script: the running line, the note lines, the awk RECOVERY printer (candidate branch and non-candidate branch), the marker printer, and each of the five degraded branches (usage, no timeout binary, no temp file, timed out, exit N); every file the script allocates (`OUT`, `ERR`); every external command it starts (`timeout`, the `bash` resolver, `tail`, `grep`, `awk`, `head`, `tr`). The chokepoint for output is the single sanitiser pipeline feeding `out`; the chokepoint for allocation is the `trap ... EXIT`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `soleur_ctx_sanitize_nl` from the `out=` pipeline | RED (S6: control bytes and the decoy line survive) |
| 2 | Take the first matching marker (`head -n1`) instead of `tail -n 1`, or print a second marker after the first (second member) | RED (S1/S6: the marker is not unique and last) |
| 3 | Drop `pr=${PR}` from the marker ERE | RED (S7) |
| 4 | Remove the candidate cap `++c > 20`, or cap ALL RECOVERY lines at 20 | RED (S9: 25 candidate lines printed / pointer and workflow lines lost) |
| 5 | Add an `eval "$hint"` or run `gh run rerun` for `basis=workflow` hints | RED (S10: shim log non-empty or sentinel created) |
| 6 | Replace the file redirects by `$( )` capture | RED (S4: the detached holder blocks past the timeout) |
| 7 | Delete `trap ... EXIT` | RED (the per-row empty-`TMPDIR` helper: two files remain) |
| 8 | Make the script exit with the resolver's rc, or decide the state from `rc` instead of the marker | RED (S3: rc 2/64/137; S8: complete+rc3, error+rc0) |

**Harness rows.** Edit the SUITE: point S1 at a no-op script (`exit 0`, prints nothing) — S1's "marker printed LAST" clause must FAIL (anti-vacuity). Must-PASS non-canonical inputs: a marker with `absent=["a","b"]` JSON containing spaces and brackets, a RECOVERY `ctx=` with quotes and `]`, and a 262145-byte body (tail truncation) whose marker is still the last line.

**Anchor.** The marker ERE and the candidate cap are lifted from the monitor; the independent anchor is the monitor's own `W` rows, which stay green and pin the same contract from the other side. Until the dedupe lands, a change to one copy that is not made to the other shows as a divergence only if someone runs both (hence the Deferred section's re-evaluation criteria).

## Observability

The read runs on the operator's or customer's own machine inside a Claude Code session (observability layer 7, `cli-stdout-artifact`, `hr-observability-layer-citation`); there is no server, no Sentry project and no host to log into, and the signal is the Monitor stream the agent reads in-session. No ssh anywhere.

```yaml
liveness_signal:
  what: the "[ship.phase7.required_set] ... required-set read N/3 (up to ~125s; this poll is alive ...)" line printed before each read, then the script's "REQUIRED-SET READ — running" line, the marker, and the closing "[ship.phase7.required_set] state=... — polling on / exiting poll" line
  cadence: at most 3 times per poll, 10 gate-holding ticks apart
  alert_target: the Monitor tool stream the shipping agent is already reading (stdout only; the harness asserts nothing tagged reaches stderr)
  configured_in: plugins/soleur/skills/ship/SKILL.md Phase 7 fence (mirror in plugins/soleur/skills/merge-pr/SKILL.md section 5.2); script plugins/soleur/scripts/required-set-report.sh

error_reporting:
  destination: stdout of the script, streamed by the fence; layer 7 (cli-stdout-artifact). No Sentry: the surface is a customer-executed CLI plugin
  fail_loud: a missing marker prints "REQUIRED-SET READ — no marker (<cause>): treat as state=error" (or the fence's own "no marker: required-set-report.sh is missing or failed" line) and "state=none — polling on"; absent or failed ends the poll with the hints above the exit line

failure_modes:
  - mode: resolver hangs or dies silently (network, pager, credential helper)
    detection: "timed out after 120s" degraded line from the script (S4); the fence is not blocked longer than 125 s per read, and the verdict sample is bounded at 65 s
    alert_route: Monitor stream, layer 7
  - mode: the script is missing or from an older plugin root
    detection: empty marker, so "state=none — polling on" plus the fence's own missing-or-failed line (R6)
    alert_route: Monitor stream, layer 7
  - mode: forged or control-character-laden resolver output
    detection: sanitised and bound to this PR by the script; nothing marker-shaped starts a line except the real marker (S6, S7)
    alert_route: Monitor stream, layer 7
  - mode: gates never hold (disarmed, queued, verdict not full-decided, queue read unknown)
    detection: no read and no line; the existing heartbeat and the `--queue-state` timeout line ("Queue: ...") are the visible state, and R4 pins that the absence is deliberate
    alert_route: Monitor stream, layer 7

logs:
  where: the Monitor tool's output stream for the session; no file is written
  retention: the session transcript

discoverability_test:
  command: bash plugins/soleur/scripts/required-set-report.sh not-a-pr
  expected_output: REQUIRED-SET
```

The command exercises the script's usage path (no network, no resolver) and finishes in milliseconds, well inside the 15-second cap.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The pipeline brief carries the CTO ruling of 2026-11-09, recorded as four rows in `knowledge-base/project/specs/feat-one-shot-11544-ship-phase7-required-set/decision-challenges.md`: dispatch to a script, no monitor refactor in this PR (scope-out issue instead), trigger and exit semantics. This plan implements it and does not reopen it. No other domain is implicated: no UI surface (no file under `components/`, `app/`, no page), no user data, no vendor, no spend, no legal text, no marketing copy, so the Product/UX gate and the GDPR gate do not fire.

No Product/UX Gate: the mechanical UI-surface override scanned `## Files to Create` and `## Files to Edit` and matched no path.

## User-Brand Impact

- **If this lands broken, the user experiences:** a shipping session whose poll either never reads the required set (today's silent 90-minute heartbeat on a PR that can never enqueue, now unchanged) or reads it too eagerly and ends a healthy poll early on a false `absent`; in both cases the cost is a wasted or aborted merge wait inside the user's own Claude Code session, with the Monitor lines showing exactly what happened.
- **If this leaks, the user's workflow is exposed via:** no new channel. The script prints GitHub check names and run ids the session can already read; `ctx=` and `wf=` text is untrusted PR data and is printed, never executed (S12), with control characters stripped (S8).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: the change is read-only, bounded to 3 reads per poll, and cannot push, merge, re-arm or run a hint; the worst failure is a missed or early stop that the stream explains. The path matches a sensitive-path scan only through `plugins/soleur/scripts/`; threshold: none, reason: the script is read-only against GitHub through an existing resolver and executes nothing it prints.

## Non-Goals

- Refactoring `monitor-pr-checks.sh` onto the new script (Deferred section, Phase 5).
- Reading the set on BEHIND-in-queue-wait ticks (CTO ruling).
- Any change under `.github/workflows/` (no agent admin-merge hatch exists for workflow edits).
- Editing `scripts/test-all.sh`; repricing existing suites in the registries.
- Teaching the harness instruction text (`harness.ts`, `pr-merge-poll.ts`) the new tag.
- Operator-held acts of epic #9927 enumerated in the pipeline brief: not touched by this PR and absent from every phase above; any operator note goes on the existing issue #12272 only.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one states `none` with a reason.
- The fence's `done < <(bash "$RS_SH" "$PR" 2>/dev/null)` makes the read's wall time part of one tick (up to 125 s). `MAX_POLL_MIN` counts iterations, not minutes, so the poll's wall clock can exceed 90 minutes by at most 3 x 125 s; the exit paragraph says so, so a slow tick is not mistaken for a hang.
- The dwell is a GREEN dwell (CTO re-ruling). A reviewer who "simplifies" the increment line to `[[ "$s" == "OPEN BLOCKED" ]]` alone restores the false-`absent` window; Guard 1 mutation 5 and R4 (iv) pin it.
- Keep `qs="$(bash "$SYNC_SNAP" "$PR" --queue-state 2>/dev/null || true)"` byte-identical: it is a pinned parity token. The two sampling lines go on their own lines after it.
- No `trap` in the fence: the existing one (`trap 'rm -f "$SYNC_SNAP"' EXIT`) is pinned and a second `trap` replaces it.
- `RS_SH` is read live, like `ci-head-verdict.sh`, not snapshotted like `SYNC_SNAP`; a comment in the fence says so.
- The suite registries are contended by three open draft PRs; insert one row each at the sorted position and never commit a regenerated header.
- Fixture assertions of absence must go through `MERGED CLEAN`, `ONCE` and the stub call count: the heartbeat prints only on a state change or `i % 3 == 1`, so a missing tick label proves nothing.
- `git add` and `git commit` are separate calls; no `git stash`; no process-listing by full command line; no `sleep` in Bash.
