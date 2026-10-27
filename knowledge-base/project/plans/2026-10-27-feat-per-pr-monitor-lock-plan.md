---
title: "feat: per-PR monitor lock so there is one pr-checks monitor per PR (P4c of #10924)"
date: 2026-10-27
slug: per-pr-monitor-lock
branch: feat-one-shot-10924-p4c-monitor-lock
issue: 10924
type: feat
priority: p3
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: single-domain
---

# feat: per-PR monitor lock so there is one pr-checks monitor per PR (P4c of #10924)

## Overview

Add a process-level, per-PR exclusion to the canonical PR check/merge poll loop,
`plugins/soleur/scripts/monitor-pr-checks.sh`, so a second monitor armed on the same
repo + PR is refused loudly (one terminal line, rc 4, before any `gh` call) instead of
being layered beside the first. Slice P4c of #10924, under umbrella #9757. PR body uses
`Ref #9757` and `Ref #10924` only; #10924 stays open and its P4c checkbox is ticked after
the merge. P4d and #10932 are separate PRs and are not planned here.

The CTO's directional ruling ("per-PR monitor lock, one monitor per purpose") was made
without reading code. After reading, the ruling holds but the shape changes: a session-scoped,
report-only layer already exists (`.claude/hooks/monitor-supersede-guard.sh`), so P4c is the
missing HARD, harness-independent layer, not a first duplicate-monitor control. Re-scope
ruled by the CTO agent (decision-challenges.md F6). The plan was then reviewed by the
plan-review panel (simplicity, DHH, Kieran, CTO devex) and a sharp-edges pass; their outcomes
are decisions F8-F13 and are already folded in below.

## Enhancement Summary

**Deepened on:** 2026-10-27
**Agents / passes used:** repo + learnings research (plan phase); CTO fork rulings and CTO devex review; plan-review
panel (simplicity per mechanism, DHH, Kieran); a full sharp-edges catalogue pass; deepen-plan halt gates 4.6-4.13 run
mechanically; live verification of every cited PR, issue, learning path and rule id.

### Key Improvements

1. `sleep & wait` plus INT/TERM traps removed after measurement: with only an EXIT trap, bash releases within ~1 s of
   TERM; a TERM trap is what defers release (F12).
2. `lstart` pinned to `TZ=UTC LC_ALL=C` (measured: it follows the caller's TZ), `+`-joined lock names (no `__`
   collision), refusal wording branched on session ownership, and a bounded release-race grace (F10, F11).
3. Surface cut by ~25%: no selfcheck flag, no `purpose` dimension, no CODEOWNERS rows, no hand-run mutation rows;
   the discoverability probe is one `bash -c` line over the lib (F13).

### New Considerations Discovered

- Re-acquire by the SAME pid (what mutation row 2 produces on poll 2) must be an idempotent rc 0, not a self-refusal.
- How the Monitor tool signals a stopped watch is unverified; the refusal therefore leads with `kill <pid>`.
- Residual list (macOS `ps`, PID namespaces, divergent `XDG_RUNTIME_DIR`, clock-step `lstart`, SIGPIPE) is in Sharp Edges.

### Deepen-plan gate results

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | present, threshold `none`, no sensitive path in Files lists (all under `plugins/soleur/`) - pass |
| 4.7 Observability | section present, all 5 fields non-empty; `discoverability_test.command` first token `bash` accepted by `probe-verb-gate.sh` (exit 0), no `ssh`, finishes well inside 15 s (one acquire + release in a temp dir), `expected_output` is a literal - pass. The probe cannot run until the lib exists; Phase 5.3 runs it |
| 4.8 PAT-shaped variable | zero hits - pass |
| 4.9 UI wireframe | no UI-surface file - skipped |
| 4.10 Encryption posture | no `.tf`/migration/cloud-init/compose file, no persistent store or connection - skipped |
| 4.11 Guard Contract | `scripts/lint-guard-contract.py` green; assembly names a chokepoint (`acquire_or_exit`), the exit funnel (`_cleanup`) and the three liveness predicates, not today's members; matrix rows are derived from the design (row 10 is the measured TERM-trap hazard) - pass |
| 4.12 Scope Check | one unfenced section, three subsections, every ask mapped, every `inferred` row justified - pass |
| 4.13 Task design | no new autonomous-task surface - skipped |
| 4.55 Downtime | no serving surface changes - skipped |
| Citations | #11124, #11164, #10873 MERGED; #9757, #10924, #11286 OPEN; all seven cited learning files exist; rule ids `hr-observability-as-plan-quality-gate`, `hr-weigh-every-decision-against-target-user-impact`, `cq-write-failing-tests-before`, `hr-monitor-not-run-in-background-for-polling`, `hr-dispatch-async-must-arm-watch` active in AGENTS.md - pass |

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 10924`: OPEN; P4a (#11124) and P4b (#11164) merged; P4c and P4d unchecked. Premise holds.
- Umbrella #9757 OPEN. Draft PR #11286 is this branch's PR. Collision pre-check: only #11286 names #10924;
  the foreign hits are unrelated `test-all.sh` processes in other worktrees.
- Cited artifact `plugins/soleur/scripts/monitor-pr-checks.sh` exists on `origin/main`; no open PR edits it.
- Mechanism vs ADR corpus: no ADR decides a monitor lock. ADR-270 and ADR-276 reference the script only for
  its queue and ci-head-verdict reads. Nothing rejected.
- Stale-premise finding (changes the shape, not the target): a duplicate-monitor control already exists at
  the hook layer (see Reconciliation). The plan is the hard layer.

### Property List and Cut List (Phase 0.6b)

Properties (one observable outcome each):

1. A second `monitor-pr-checks.sh` armed on the same repo + PR does not poll; it prints one terminal
   line naming the holder and exits with a code no caller reads as success.
2. A refused monitor makes zero `gh` calls.
3. A holder that died (SIGKILL, crash, pid reuse, zombie) never blocks a new monitor.
4. A holder that is stopped (TERM) or finishes releases the lock promptly, including while it sleeps between
   polls, so "stop the old monitor, then arm the new one" works.
5. Monitors on different PRs or different repos do not block each other.
6. When the lock cannot be established (no writable dir, no `ps`, no derivable repo) the monitor still
   runs and says so loudly; a bypass is never silent.

Cut List (mechanism -> property -> what already covers it):

- Deny in `monitor-supersede-guard.sh` -> property 1 -> CUT: report-only by design; absent on Codex/Grok/Devin.
- flock(1) -> property 1 -> CUT: absent on stock macOS; the symlink lock buys the same atomicity.
- Wait-for-holder / take-over / attach -> property 1 -> CUT (F1): refusing loses nothing.
- Lock-age ceiling for a live-but-wedged holder -> property 3 -> CUT (F8): bounded by `--max-polls`; `kill <pid>` named.
- `sleep & wait`, `SLEEP_PID`, INT/TERM traps -> property 4 -> CUT (F12): the EXIT trap alone releases within ~1 s of TERM.
- `--lock-selfcheck` flag and function -> discoverability -> CUT (F13): a one-line `bash -c` over the lib plus the runtime UNAVAILABLE line.
- `purpose` argument and key dimension -> property 5 -> CUT (F9): one adopter; `pr-checks` stays a constant name prefix.
- CODEOWNERS rows for the new files -> ownership -> CUT (F13): `* @deruelle` already owns every path.
- Hook edit pointing at the lock -> discoverability -> CUT (F6): `harness.ts` prose already links the layers.
- Hand-run mutation rows with PR-body proof -> guard strength -> CUT (F13): every row is automated or a plain assertion.
- Adopting the lock in `sync-pr-behind.sh` standalone loop, ship Phase 7 poll, `triage-prs.sh` -> OUT OF SCOPE (F9).

### Research Reconciliation - Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "Add a per-PR monitor lock" as if no control exists | `.claude/hooks/monitor-supersede-guard.sh` (+ `monitor-arm-recorder.sh`, `lib/monitor-sig.sh`) already REPORTS a re-arm on a target the same session still watches. Session-scoped, Claude-Code-only, blind to a second session or a differently-shaped command | Keep the hook unchanged; add the script-level lock as the hard layer (F6) |
| "one monitor per purpose" (plural purposes) | `monitor-pr-checks.sh` is the only script a `Monitor` watch arms for PR checks; the `sync-pr-behind.sh` standalone loop and `triage-prs.sh` also poll and are deliberately NOT adopted (F9) | Lock key = repo + PR under the constant `pr-checks` prefix |
| CTO: "I did not read their code" | Script runs `set -uo pipefail` (no `-e`), has ONE `trap 'rm -f "$ERRTMP"' EXIT`, exits 0/1/2/3 | Fold release into that single trap; add rc 4 |
| A TERM handler is needed for prompt release | Measured: with ONLY an EXIT trap bash dies at once on TERM and runs it (+1 s). `trap 'exit 143' TERM` defers it to the end of a foreground sleep (+6 s of a 6 s sleep) | No TERM/INT trap (F12); a test pins the ~1 s release so nobody adds one |
| rc 4 is free | `sync-pr-behind.sh` uses 4 for `kind=gh`; different script. See the caller table below | rc 4 = already watched |

### Caller and reference sweep (`git grep -n 'monitor-pr-checks' -- ':!knowledge-base'`)

| Hit | Reads the exit code? | Disposition |
|---|---|---|
| `plugins/soleur/lib/harness.ts` (`pollInstructions("claude")`, the `Monitor({command: "bash plugins/soleur/scripts/monitor-pr-checks.sh <PR>"` line) | arms it | EDIT: rc 4 prose, ownership-branched (one canonical place) |
| `plugins/soleur/skills/drain-prs/SKILL.md` (paragraph starting `Arming returns at ENQUEUE`) | arms one per enqueued PR | EDIT: one sentence - rc 4 = already watched, keep the PR in the set awaiting merge, never "done" (a re-run drain re-arms all of them) |
| `plugins/soleur/skills/ship/references/ready-run-wait.md`, `merge-queue-dequeue.md`, `queue-mode.md` | name the script, no exit-code semantics | no change |
| `plugins/soleur/test/ci-head-verdict.test.sh` (reader census `L1.census-sees-the-known-readers`) | greps for the name | no change (the census counts the script file, unchanged) |
| `plugins/soleur/scripts/sync-pr-behind.sh` comments | names the script | no change |
| `.github/CODEOWNERS` row for the script | n/a | no change (catch-all `*` already owns the new files) |
| `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` | suite label | no change (new suite is registered by glob; unknown labels fall back to the default weight) |
| ADR-270 / ADR-276 | prose | no change |

### Local research (repo)

- Script anchors: arg parse and validation block, `ERRTMP` + the `trap 'rm -f "$ERRTMP"' EXIT` line (the model for
  "refuse to start rather than degrade", rc 3), `in_queue`/`ci_verdict` helpers resolve siblings via
  `cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P`, the poll loop, the final `sleep "$INTERVAL"`.
- `plugins/soleur/test/monitor-pr-checks.test.sh`: anti-vacuity floor is the `_ran` assertion count (69), not an arm
  count; CI-measured 245 s because it sleeps at the 10 s interval floor. Registered by glob (`SUITE_GLOBS`
  `plugins/soleur/test/*.test.sh`); a new suite needs no manifest edit. `scripts/lint-orphan-test-suites.sh` and
  `plugins/soleur/test/scripts-shard-totality.test.sh` check registration.
- Portability: `emit-decision.sh` ("stock macOS ... No flock, timeout, jq ... bash 3.2-safe"); `session-state.sh`
  hard-requires flock (Linux-only consumer, not reusable).
- No census requires a new `plugins/soleur/scripts/lib/*.sh` file to be listed.

### Institutional learnings applied

- `2026-09-21-every-gate-this-pr-added-failed-open-on-the-input-it-could-not-measure.md`: fail-open ONLY for "cannot
  establish a lock", fail-closed on a positively live holder; assert each refusal by its exact rendered text.
- `2026-05-12-cross-session-lock-lease-bash-primitives.md`: identify a holder by pid + start time (SE2); a trap does not
  fire while bash is blocked on a foreground child (SE4) - true only when a TERM TRAP is installed (F12).
- `2026-09-19-cleanup-on-failure-is-a-property-of-the-window-not-the-arms.md`: install the trap BEFORE the first write.
- `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`: never `pgrep -f` for a live monitor.
- `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`: prove the acquire is dispatched
  and CAN fail (rows 1-2).
- `best-practices/2026-07-14-extracting-nonzero-returning-helper-into-command-sub-aborts-under-set-e.md`: read the
  lib's non-zero returns through `if`/`||`.
- `2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md`: a mutant is killed only
  by the targeted assertion failing, never by a crash.

### Verification of CLI tokens

- `ps -o stat= -o lstart= -p <pid>` run locally on procps-ng 4.0.7: one line, `lstart` is five space-separated fields
  (`Ss   Tue Oct 27 10:18:25 2026`); an absent pid prints nothing and exits 1; `ps -p N -o pid=` is right-aligned with
  leading spaces. MEASURED: `lstart` follows the caller's `TZ` (`TZ=UTC` -> `09:27:08`, `TZ=Asia/Tokyo` -> `18:27:08`),
  so every read pins `TZ=UTC LC_ALL=C`. `ln -s <target> <link>` is atomic, fails EEXIST on an existing link even when
  dangling, and fails ENOENT on an empty target; `readlink <link>` prints the target. BSD/macOS `ps` documents the same
  `lstart` and `stat` keywords but was NOT run here: the fail-open arm and the one-line probe are the mitigation.
- Stub shapes for the suite are captured from those outputs (leading-space pid, five-field `lstart`, empty + rc 1 for an
  absent pid, `Z`/`Z+` for a zombie).
- Not verified here: how the Monitor tool stops a watch (which process gets which signal). The refusal text therefore
  leads with `kill <pid>`, and the residual (a holder alive after a wrapper-only kill blocks a re-arm for up to the poll
  budget, 2 h at defaults) is recorded under Sharp Edges.

## Open Code-Review Overlap

Queried open `code-review` issues against every file in Files to Edit / Create. No hit on the final file list
(#3321, CODEOWNERS coverage for a KB subtree, matched only the dropped CODEOWNERS edit). None.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a per-PR monitor lock so there is one monitor per purpose" [issue #10924 P4c] | Phases 1-3, `lib/monitor-lock.sh`, `monitor-pr-checks.sh` | mapped |
| 2 | "starting from plugins/soleur/scripts/monitor-pr-checks.sh. Read the script (and its callers/tests) first" [brief] | Research Insights; Phase 2; caller sweep + Phase 4 | mapped |
| 3 | "the CTO's ruling was directional, so re-scope after reading if needed" [brief] | Research Reconciliation; decision-challenges.md F6 | mapped |
| 4 | "PR body uses `Ref #9757` and `Ref #10924` only, never a closing keyword" [brief] | Phase 6 | mapped |
| 5 | "Merge with `gh pr merge <N> --squash --auto` through the merge queue, never --admin" [brief] | Phase 6 | mapped |
| 6 | "Do not read or print secrets; do not run doppler or any live credentialed probe" [brief] | Test design (stubbed `gh`/`ps`, no network); no Doppler step | mapped |
| 7 | "Keep apps/** and scripts/registry-restore-from-ghcr.sh unchanged" [brief] | Files lists touch neither; AC diff-scope check | mapped |
| 8 | "Do not close #10924 (tick the P4c checkbox in its body after the merge)" [brief] | Phase 6 post-merge step | mapped |
| 9 | "If the PR edits .github/workflows/apply-web-platform-infra.yml, ask the operator and wait" [brief] | Files lists include no workflow; Phase 6 re-checks `git diff --name-only` | mapped |
| 10 | "Do not touch the apply-workflow annotations (umbrella item 2)" [brief] | no workflow edits | mapped |
| 11 | "Do NOT plan those here" (P4d and #10932) [brief] | Non-goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/scripts/lib/monitor-lock.sh` (new) | "Add a per-PR monitor lock" | asked |
| `plugins/soleur/scripts/monitor-pr-checks.sh` edits | "starting from plugins/soleur/scripts/monitor-pr-checks.sh" | asked |
| `plugins/soleur/test/monitor-lock.test.sh` (new) | "Read the script (and its callers/tests) first" | inferred - justification: cq-write-failing-tests-before; kept out of `monitor-pr-checks.test.sh`, which costs 245 s of CI because it sleeps at the interval floor |
| `monitor-pr-checks.test.sh` lock-dir isolation export | "Read the script (and its callers/tests) first" | inferred - justification: the existing suite runs the real script for PR 7778 and must not touch a developer's real lock directory |
| `plugins/soleur/lib/harness.ts` and `drain-prs/SKILL.md` rc-4 lines | "Read the script (and its callers/tests) first" | inferred - justification: CTO constraint 5; a caller that reads rc 4 as failure re-arms in a loop and recreates the duplicate-monitor problem |
| bounded release-race grace (F10), TZ pin, ownership-branched refusal text (F11) | "so there is one monitor per purpose" | inferred - justification: CTO devex review; without them a legitimate "stop, then re-arm" or a resumed session leaves the PR unwatched, which defeats the lock's purpose |

### Split Assessment

- Subsystems touched: 1 - `plugins/soleur/`
- Planned files: 6 (2 create, 4 edit) | Estimated changed lines: ~330
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Proposed Solution

### Design (all forks ruled; see decision-challenges.md F1-F13)

**Lock** = a symlink `"$LOCKDIR/pr-checks+<owner>+<repo>+<pr>.lock"` whose TARGET is the holder record
`<pid>|<lstart>|<epoch>` (`lstart` = `TZ=UTC LC_ALL=C ps -o lstart= -p <pid>` with whitespace runs collapsed to `_`;
`epoch` from `date +%s`, never `printf %(%s)T`, which is bash 4.2+). `ln -s` is atomic create-or-fail AND atomic
record, so there is no mid-write window (the Emacs lockfile idiom) and no flock. The name joins parts with `+`,
which the `--repo` grammar excludes, so `a__b/c` and `a/b__c` cannot collide.

- **LOCKDIR** = `${SOLEUR_MONITOR_LOCK_DIR:-${XDG_RUNTIME_DIR:-/tmp}/soleur-monitor-locks-$(id -u)}`, mode 0700,
  must be a directory, owned by us, not a symlink, writable. Fallback is the literal `/tmp`, never `$TMPDIR`.
- **Key** = repo + PR. Repo = `--repo` lowercased, else the cwd's `git config --get remote.origin.url` normalised to
  lowercase `owner/repo` (strip any `user:token@`, scheme, host, trailing `/` and `.git`); must match
  `^[a-z0-9][a-z0-9._-]*/[a-z0-9._-]+$` else the lock is skipped fail-open with the loud line (a non-github host or
  garbage URL included). Never keyed on a bare PR number.
- **Live holder** = pid numeric AND `ps -p <pid> -o pid=` non-empty (NOT `kill -0`: EPERM reads another user's live
  process as dead) AND `ps -o stat=` not `Z*` AND recorded `lstart` equals the current one (pid reuse; if the recorded
  `lstart` is empty the comparison is skipped).
- **Acquire** `monitor_lock_acquire <owner/repo> <pr>`: `ln -s`; on EEXIST read the link: a holder whose pid is this
  process's own `$$` is already ours -> rc 0 (idempotent; this is what the reorder mutant produces on poll 2); a malformed value, or a
  holder that is not live, is stale -> remove it only if `readlink` still equals the stale value, then `ln -s` ONCE more
  (still failing -> rc 2 `contended`); a path that is not a symlink (file, directory) -> rc 2; a LIVE holder -> up to
  2 more tries at `${SOLEUR_MONITOR_LOCK_GRACE_S:-1}` s spacing (F10), then rc 1 with `ML_HOLDER_PID` and `ML_HOLDER_AGE`.
  Returns 0 acquired, 1 held by a live other process, 2 not established (`ML_STATE` = `disabled`|`unavailable`,
  `ML_WHY`). The residual race is two contenders both passing the compare after a SIGKILL; it degrades to a duplicate
  monitor (today's behaviour), never a false refusal.
- **Release** `monitor_lock_release`: remove the link only if `readlink` still equals our recorded value; returns early
  when nothing was recorded; idempotent; never branches on `$?`.
- The lib is sourced under `set -u` and must be `set -u` safe; it changes no shell option. Bash 3.2-safe: no flock,
  `timeout`, associative arrays, `${x,,}`, `printf %(%s)T`.

**Script wiring** (`monitor-pr-checks.sh`), in this order: arg parse -> validation (rc 3) -> `ERRTMP` -> source the
lib (absent -> loud UNAVAILABLE line, define `monitor_lock_release(){ :; }`) -> ONE `_cleanup` (`monitor_lock_release`
first, then `rm -f "$ERRTMP"`) installed as the EXIT trap, replacing the old inline trap; NO INT/TERM trap (F12) ->
`acquire_or_exit` (a function so the reorder mutant is one line) -> the loop. Refused: print the DUPLICATE line and
`exit 4` before any `gh` call. Not established: print the loud line and continue. `--help` and usage errors exit before
the lock is touched. The repo arg is read as `${REPO_ARG[1]:-}` (the existing `"${REPO_ARG[@]}"` is unsafe under `-u`
on bash < 4.4). Acquire/release run in the main shell, never inside `$(...)` (a subshell does not run the parent's EXIT
trap, and the lock would be released the moment the substitution ended).

**Operator-visible lines** (stdout, so the Monitor tool delivers them; asserted verbatim):

- Refused (rc 4): `DUPLICATE MONITOR — PR #<N> is already watched by pid <P> (armed <S>s ago, repo <owner/repo>). This watch exits without polling. If this session armed that monitor, read its output; if not (a resumed or other session), stop it with: kill <P> — then arm this watch once. SOLEUR_MONITOR_LOCK=off bypasses the lock only if the lock mechanism itself misbehaves.` Contains none of `MERGED`, `GREEN`, `CLOSED`, `SETTLED`, `TIMEOUT`, `QUEUE`, `KILLED`, `UNMERGED`.
- Not established: `monitor-lock: UNAVAILABLE (<why>) - running without exclusion`
- Bypass: `monitor-lock: DISABLED (SOLEUR_MONITOR_LOCK=off) - running without exclusion`

Exit-code table (header, `--help` Usage block, and the exit-code sentence): 0 merged / all-green settle, 1 red or
closed terminal, 2 timeout, 3 usage or refuse-to-start, **4 already watched by another live monitor (the PR is being
watched; do not treat it as a PR failure and do not re-arm blindly)**.

**Stop-signal behaviour (measured, F12):** TERM -> bash dies at once, EXIT trap releases (~1 s); HUP -> trap runs
(`$?` inside is 0, which is why release never branches on it); SIGKILL -> no trap, covered by liveness; SIGINT is
ignored by a backgrounded non-interactive bash so it is not tested; a reader that closed stdout (SIGPIPE) kills the
script only at its next write, so the lock can outlive a vanished reader by up to `--heartbeat-every` x `--interval`
(10 min at defaults) - a documented residual covered by the `kill <P>` hint.

## Implementation Phases

### Phase 0 - RED first (cq-write-failing-tests-before)

Write `plugins/soleur/test/monitor-lock.test.sh` and the `monitor-pr-checks.test.sh` isolation edit; run them against
the unmodified script and confirm RED for the right reasons (the lib does not exist; no rc 4).

### Phase 1 - `plugins/soleur/scripts/lib/monitor-lock.sh`

Functions: `_ml_dir`, `_ml_key`, `_ml_ident <pid>` (prints `stat|lstart_`), `_ml_alive <pid> <lstart>`,
`monitor_lock_acquire`, `monitor_lock_release`. Header states the portability contract and the Emacs-style idiom.

### Phase 2 - wire `monitor-pr-checks.sh`

As in "Script wiring". Update the header comment, the Usage block (so `--help` shows rc 4 and `SOLEUR_MONITOR_LOCK`)
and the exit-code sentence.

### Phase 3 - tests (GREEN) and the one-line probe

`monitor-lock.test.sh`: see Test Scenarios and the Guard Contract. `monitor-pr-checks.test.sh`: export
`SOLEUR_MONITOR_LOCK_DIR="$STUB/locks"` near the top so no existing arm touches a real directory; its floor stays
(still prints `floor 69` with n >= 69).

### Phase 4 - callers

- `plugins/soleur/lib/harness.ts` `pollInstructions("claude")`: add the lock prose in ONE place after the
  supersede-guard paragraph (the other surfaces point to it): the script holds a per-PR lock; rc 4 / a `DUPLICATE
  MONITOR` line means a live watch already exists - if this session armed it read its output, otherwise `kill <pid>` it
  and arm once; `TaskStop` the old monitor first still applies. `harness.test.ts` asserts only `Monitor tool`.
- `plugins/soleur/skills/drain-prs/SKILL.md`: one sentence in the `Arming returns at ENQUEUE` paragraph.

### Phase 5 - verification (local, bounded)

`bash plugins/soleur/test/monitor-lock.test.sh`; the isolation-edited `monitor-pr-checks.test.sh` (long: run detached
per the bounded-output rule); `cd plugins/soleur && bun test test/harness.test.ts` (root `bun test` is not the repo's
test entry); `bash plugins/soleur/test/c4-count-parity.test.sh`; `bash scripts/lint-orphan-test-suites.sh` once the
files are tracked; `python3 scripts/lint-trap-tempfile-ownership.py` (the new suite uses `mktemp -d`: its owning
`trap` goes BEFORE `source test-helpers.sh`); `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`;
`python3 scripts/lint-guard-contract.py` on this plan; markdownlint on the plan and `tasks.md`.

### Phase 6 - ship

`soleur:ship`; PR body `Ref #9757` / `Ref #10924` only with a `## Changelog` section and `semver:patch`;
`gh pr merge <N> --squash --auto` (merge queue, never `--admin`); `git diff --name-only origin/main...HEAD` must not
list `.github/workflows/apply-web-platform-infra.yml` (if it ever does: stop and ask the operator before ready/merge).

## Files to Edit

- `plugins/soleur/scripts/monitor-pr-checks.sh` - lock wiring, single `_cleanup`, `acquire_or_exit`, header/Usage
- `plugins/soleur/test/monitor-pr-checks.test.sh` - export `SOLEUR_MONITOR_LOCK_DIR` isolation
- `plugins/soleur/lib/harness.ts` - claude `pollInstructions` rc-4 prose
- `plugins/soleur/skills/drain-prs/SKILL.md` - one sentence on rc 4

## Files to Create

- `plugins/soleur/scripts/lib/monitor-lock.sh`
- `plugins/soleur/test/monitor-lock.test.sh`
- `knowledge-base/project/specs/feat-one-shot-10924-p4c-monitor-lock/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10924-p4c-monitor-lock/decision-challenges.md` (written during planning)

Glob check: `git ls-files plugins/soleur/scripts plugins/soleur/test/monitor-pr-checks.test.sh plugins/soleur/skills/drain-prs/SKILL.md plugins/soleur/lib/harness.ts` resolve; the two creates are new paths in existing directories.

## Architecture Decision (ADR/C4)

No ADR and no C4 change. Test applied: would an engineer reading the ADRs and C4 be misled after this ships? No.
The lock is a machine-local, ephemeral file inside one script; ADR-270 and ADR-276 mention the script only for its
queue and ci-head-verdict reads, which are unchanged. C4 checked by reading `model.c4` (1032 lines), `views.c4`,
`spec.c4`: external human actors - none added; external systems/vendors - none (no new API); containers/data stores -
none (a `/run/user` symlink is not a modeled store); actor-surface access relationships - none change; the model has
no per-script or per-monitor elements. The derived cardinality gate (`plugins/soleur/test/c4-count-parity.test.sh`) is
run in Phase 5 as backing evidence; this PR adds no workflow, monitor slug or heartbeat, so no count moves.

## Guard Contract

### Guard 1 - per-PR monitor lock (duplicate-monitor refusal)

**Property.** At most one live `pr-checks` monitor holds the lock for a given (repo, PR); a second one exits rc 4
before any `gh` call, and a holder that is dead, zombie, reused-pid or released never blocks a new monitor.

**Assembly.** Entry side: ONE chokepoint - `acquire_or_exit` in `monitor-pr-checks.sh`, called once between
"validation + trap installed" and the first `gh` call; `--help` and usage errors exit before it, so no second entry path
exists. Exit side: every way the process ends after acquire - terminal verdicts (`exit 0/1/2`) and TERM/HUP (default
disposition, EXIT trap runs) - flows through the ONE `_cleanup`; SIGKILL and host loss bypass it and are covered by the
liveness predicate, not by cleanup; a vanished stdout reader (SIGPIPE) is the documented residual. Key dimensions
(two, both must discriminate): repo (both `--repo` and origin-derived spellings, case-folded) and PR number. Liveness
predicates (three, each independently load-bearing): pid exists via `ps -p`, not zombie, `lstart` equal under a pinned
`TZ=UTC`. Fail-open arms (three): `SOLEUR_MONITOR_LOCK=off`, lock dir / `ps` / lib unavailable or contended, repo key
underivable - each prints its loud line and none exits 4. Blocking-wait side: with no TERM trap installed, no foreground
child (`sleep`, `gh`, `jq`) can defer the release.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `acquire_or_exit` call (the guard's own dispatch: a suite green with no acquire dispatched is vacuous) | RED: the second-monitor arm sees rc != 4 and the `gh` stub log is non-empty |
| 2 | Move the `acquire_or_exit` call to after the first poll's `gh pr checks` line (REORDER, not delete: a delete reds any suite, a move reds only one that observes inside the window) | RED: the refusal arm asserts the `gh` stub log is empty |
| 3 | Key drops the PR number; the arm runs three monitors (PR 1, then PR 2, then PR 1 again) so a second member follows a compliant first | RED: PR 2 is refused although only PR 1 is held |
| 4 | Key drops the repo | RED: the same PR number in `a/x` and `b/y` must both acquire |
| 5 | Liveness drops the `lstart` comparison | RED: a record with a LIVE pid and a wrong `lstart` must be reclaimed |
| 6 | Liveness drops the zombie (`Z*`) test | RED: a stubbed `ps` reporting `Z` for the holder must be reclaimed |
| 7 | `_ml_ident` drops the `TZ=UTC` pin | RED: a holder recorded under `TZ=UTC` and read under `TZ=Asia/Tokyo` must still be refused |
| 8 | Release removes the link unconditionally | RED: release after another process re-took the lock must not delete the other's link |
| 9 | `_cleanup` stops calling `monitor_lock_release` | RED: after a normal MERGED exit the link path must not exist (`[ ! -L ]`; a leaked link names a dead pid and would just be reclaimed, so the second-run-acquires check alone cannot see this) |
| 10 | Add `trap 'exit 143' TERM` to the script (the deferral hazard) | RED: TERM sent mid-sleep must remove the link within 4 s at `--interval 10` (mutant holds ~9 s) |

Mutants 1-10 are all automated as `sed` edits on a COPIED tree (`$STUB/tree/{monitor-pr-checks.sh,lib/monitor-lock.sh}`,
so the copy sources its own lib and does not silently take the lib-absent path). Each mutant asserts the `sed` changed
the file (non-empty diff) and counts as killed only when its targeted assertion reports FAIL, never when the run
crashes; the suite asserts `killed -eq 10`. Mutants signal nothing outside the scratch tree: the only signalled pid is
the one parsed from the link target in the scratch lock dir. No `pkill`, no `pgrep -f`.

Assertions without a mutant (a mutation would be redundant with the assertion): rc is exactly 4 and never 0/1; the
refusal text equals the specified line and a token-absence check (`[ "$(grep -c -e MERGED -e GREEN -e CLOSED -e
SETTLED -e TIMEOUT -e QUEUE -e KILLED -e UNMERGED <<<"$line")" = 0 ]` with a control that the same grep counts 1 on a
line containing `MERGED`; no `! grep -q`); an unwritable dir runs and prints UNAVAILABLE; `--help` lists rc 4 (header,
Usage and exit-code sentence cannot drift apart); a live holder owned by another user (pid 1, with its real `lstart`
recorded) stays refused - skipped with a loud, non-counted line when the suite runs as root, because `kill -0 1`
succeeds as root and the arm would prove nothing.

**Harness rows:**

- Suite edit that MUST drive it RED: lower or delete one `ok` arm and the numeric floor trips; neuter `ok()`/`no()` and
  the ADR-193 INSTRUMENT self-test trips (same construction as `monitor-pr-checks.test.sh`). `FLOOR` is the assertion
  count measured at first GREEN and bumped whenever an arm is added.
- Must-PASS inputs that are NOT the canonical (each differs in a way the contract permits): (a) `ACME/Widgets` vs
  `acme/widgets` DO conflict (case-folded); (b) every origin URL form maps to the same key - `git@github.com:Acme/Widgets.git`,
  `https://github.com/Acme/Widgets`, `https://github.com/Acme/Widgets.git/`, `ssh://git@github.com/Acme/Widgets.git`,
  `https://x-access-token:<redacted>@github.com/Acme/Widgets.git` (the credential must not reach the lock name), and a
  monitor armed with `--repo acme/widgets` is refused by one derived from origin; (c) a malformed link value, a dead pid,
  and a regular-file stand-in for "empty" (`ln -s '' x` is impossible: ENOENT) are reclaimed (rc 0), a directory at the
  lock path is rc 2 `unavailable`; (d) `a__b/c` and `a/b__c` do not collide.
- Garbage inputs that must FAIL OPEN with the UNAVAILABLE line, not refuse: a non-github host, an empty or garbage
  origin URL, no `ps` on PATH, an absent lib.

**Anchor.** No stored value is compared to the thing it protects. The holder record is validated against the live
process table at acquire time, which no commit can edit; the in-repo values (fixtures) only exercise that comparison.
A weakening therefore needs an edit to a predicate itself, which rows 5-8 catch; every path is owned by the `*`
catch-all CODEOWNERS row.

## User-Brand Impact

- **If this lands broken, the user experiences:** a developer's CI watch exits "DUPLICATE MONITOR" when no other
  monitor exists (false refusal) and their PR sits unwatched until they notice, or two monitors run (today's behaviour).
- **If this leaks, the user's workflow is exposed via:** nothing - the lock holds only a pid, a process start time
  and an epoch in a 0700 per-user directory; no secret, token, PR content or credential is read, written or logged
  (the origin-URL normaliser strips any `user:token@` before the value reaches a name).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** developer-tooling hygiene on one script, no customer data path and no
  hosted runtime; the worst failure is a missed watch that the loud refusal line makes visible, not an incident.

Touches no sensitive path per preflight Check 6 (no auth, credentials, data, payments, migrations), so no
scope-out line is required.

## Observability

Layer 7 (`cli-stdout-artifact`): this script executes on the developer's / customer's own machine under the
Monitor tool; the signal is the tool-result stdout read in-session, and the durable artifact is the lock symlink
(`readlink` shows holder pid, start time, epoch). There is deliberately no Soleur-side sink.

```yaml
liveness_signal:
  what: "every poll / change / heartbeat line already emitted by monitor-pr-checks.sh; a refused monitor emits one terminal DUPLICATE MONITOR line instead of going silent"
  cadence: "per state change plus every --heartbeat-every polls (default 5); refusal is a single immediate line"
  alert_target: "the invoking session's Monitor tool-result stdout (layer 7); no pager - developer tooling"
  configured_in: "plugins/soleur/scripts/monitor-pr-checks.sh (acquire_or_exit after validation) and plugins/soleur/scripts/lib/monitor-lock.sh"
error_reporting:
  destination: "stdout of the monitor (layer 7); no Sentry by design - a customer-side plugin must not phone home"
  fail_loud: "DUPLICATE MONITOR line + rc 4 on a live holder; 'monitor-lock: UNAVAILABLE (<why>) - running without exclusion' when the lock cannot be established; 'monitor-lock: DISABLED (SOLEUR_MONITOR_LOCK=off)' on bypass"
failure_modes:
  - mode: "false refusal: stale link read as live (pid reuse, zombie, TZ drift)"
    detection: "suite fixtures for lstart-mismatch, zombie and TZ drift; at runtime the refusal line names the holder pid and age so a wrong refusal is checkable with ps -p <pid>"
    alert_route: "layer 7 stdout; kill <pid> named in the line"
  - mode: "lock silently not enforced (ps lacks lstart on this OS, dir unwritable, repo underivable)"
    detection: "monitor-lock: UNAVAILABLE line at the start of the watch; the one-line probe prints nothing and exits non-zero when ps/ln/readlink do not support the lock"
    alert_route: "layer 7 stdout"
  - mode: "stopped holder keeps the lock while sleeping between polls (a TERM trap added later)"
    detection: "suite arm: TERM mid-sleep removes the link within 4 s (mutation row 10)"
    alert_route: "CI red on monitor-lock.test.sh"
logs:
  where: "monitor stdout in the Monitor tool result; lock state in the symlink under the lock dir"
  retention: "the session transcript; the symlink is removed on release and is stale-reclaimed after a hard kill"
discoverability_test:
  command: bash -c 'export SOLEUR_MONITOR_LOCK_DIR="$(mktemp -d)"; . plugins/soleur/scripts/lib/monitor-lock.sh && monitor_lock_acquire acme/widgets 1 && monitor_lock_release && echo SOLEUR_MONITOR_LOCK_OK'
  expected_output: SOLEUR_MONITOR_LOCK_OK
```

The probe exercises `ps`, `ln -s` and `readlink` on the current machine in a private temp dir; it does not validate
the real lock directory (that is the runtime UNAVAILABLE line's job, and the sandbox that runs the probe may not
expose `XDG_RUNTIME_DIR`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] A second `monitor-pr-checks.sh <PR>` for the same repo + PR while a live holder exists prints one line starting `DUPLICATE MONITOR` and exits exactly 4; the `gh` stub log (which records every argv, including calls made by child scripts) is empty.
- [ ] The refusal line contains the holder pid, an age in seconds, `kill <pid>` and `SOLEUR_MONITOR_LOCK=off`, and none of `MERGED|GREEN|CLOSED|SETTLED|TIMEOUT|QUEUE|KILLED|UNMERGED`.
- [ ] Different PR and different repo (`--repo a/x` vs `b/y`, same number) do not conflict; `ACME/Widgets` vs `acme/widgets` and `--repo` vs origin-derived spellings do; `a__b/c` and `a/b__c` do not.
- [ ] A holder record with a dead pid, a live pid with a wrong `lstart`, a zombie `stat`, a malformed value, or a regular-file stand-in is reclaimed and the new monitor runs; a directory at the lock path is rc 2.
- [ ] A live holder read under a different `TZ` than it was recorded under is still refused.
- [ ] A live holder owned by another user (pid 1) stays refused (non-root runs; loud non-counted skip as root).
- [ ] A normal terminal exit (rc 0/1/2) and a TERM sent mid-sleep (`--interval 10`) remove the link (`[ ! -L ]`) within 4 s; release never deletes a link that is not ours; TERM then an immediate second monitor acquires (F10 grace).
- [ ] Unwritable lock dir, missing `ps`, absent lib, underivable or non-github repo, and `SOLEUR_MONITOR_LOCK=off` each run the monitor and print their exact loud line; none exits 4.
- [ ] Usage errors (rc 3) and `--help` never create a lock link; `--help` output lists rc 4.
- [ ] The existing `monitor-pr-checks.test.sh` passes with the isolation export and still prints `anti-vacuity floor: <n> assertions ran (floor 69)` with n >= 69.
- [ ] `monitor-lock.test.sh` has the INSTRUMENT self-test, a numeric `FLOOR` (measured at first GREEN), and `killed -eq 10`.
- [ ] The probe command in `## Observability` prints `SOLEUR_MONITOR_LOCK_OK` and exits 0 here.
- [ ] `harness.ts` (claude `pollInstructions`) and the `drain-prs/SKILL.md` ENQUEUE paragraph say rc 4 = a live watch exists (ownership-branched; keep the PR in the awaiting-merge set).
- [ ] `git diff --name-only origin/main...HEAD` lists none of `apps/**`, `scripts/registry-restore-from-ghcr.sh`, `.github/workflows/**`, `.claude/hooks/**`, `.github/CODEOWNERS`.
- [ ] Phase 5 lints pass (orphan-suites, trap-tempfile-ownership, technical-ruling-gate, guard-contract, c4-count-parity, harness tests).
- [ ] PR body has `Ref #9757` and `Ref #10924`, no closing keyword; merged via `gh pr merge <N> --squash --auto`.

### Post-merge

- [ ] P4c box ticked in the #10924 body (`gh issue edit 10924 --body-file` changing only that box; automatable); #10924 and #9757 remain open.

## Test Scenarios

Layer labels: `unit` = sources the lib; `integration` = runs the real script with stubbed `gh` and `ps`. No `e2e`, no network, no credentials.

- (unit) Given an empty lock dir, `monitor_lock_acquire acme/widgets 7` -> rc 0 and one symlink `pr-checks+acme+widgets+7.lock` whose target parses as `<pid>|<lstart>|<epoch>` with `<pid>` = `$$`.
- (unit) Given that lock held by a live child, a second process acquires the same key -> rc 1 after the grace with `ML_HOLDER_PID` set (`SOLEUR_MONITOR_LOCK_GRACE_S=0` in all but the grace arm); other PR / other repo -> rc 0.
- (unit) Holder values - dead pid / live pid wrong `lstart` / stubbed-`ps` zombie / `garbage` / regular file - each reclaimed (rc 0); directory at the path -> rc 2; reclaim lost twice -> rc 2 `contended`.
- (unit) Acquiring a key this same process already holds is an idempotent rc 0.
- (unit) Release when the link names someone else -> link survives; own link -> removed; twice -> no-op; nothing acquired -> early return.
- (unit) Lock dir that is a read-only directory (non-root only), a symlink to a directory, or a regular file -> rc 2 `unavailable` with a reason; `SOLEUR_MONITOR_LOCK=off` -> rc 2 `disabled`.
- (unit) Origin-URL forms and `--repo` spellings -> identical key; non-github host / garbage -> rc 2 `unavailable`.
- (integration) Held lock + logging `gh` stub -> script rc 4, exact refusal line, empty `gh` log.
- (integration) Script backgrounded (`--interval 10 --max-polls 3`, link polled into existence, pid parsed from the link target), TERM sent -> link gone within 4 s; then an immediate second script run acquires.
- (integration) Normal `MERGED|CLEAN|false` stub run -> rc 0 and no link left.
- (integration) No `--repo`, cwd without an origin remote -> UNAVAILABLE line and the monitor still polls (rc from the stub scenario, not 4).
- (integration) `-h`, `abc`, `--interval 5 7778` -> rc 0/3/3 and no link ever appears.
- (mutation) Rows 1-10 of the Guard Contract.

## Domain Review

**Domains relevant:** Engineering (CTO consulted for the forks and for the devex review of the finished plan).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** All forks ruled and persisted in `decision-challenges.md` (F1-F13). The devex review added the bounded
release-race grace (F10), ownership-branched refusal wording (F11), a corrected F8 rationale, the F2 separator/TZ
refinements, and the residuals under Sharp Edges. Plan-review panel outcomes (simplicity, DHH, Kieran) are F12-F13.

No Product/UX surface (no `components/**`, `app/**` file), no regulated data (GDPR gate not triggered: no schema, auth,
API route, `.sql`, no LLM/external API on session data, no new distribution surface), no infrastructure (no Terraform,
secret, vendor, service), no new autonomous-task surface (no workflow, Inngest function, cron or daemon), no persistent
store or network connection (encryption-posture gate skipped).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one declares `none` with a reason.
- Never overwrite the existing `trap 'rm -f "$ERRTMP"' EXIT`; fold it into the one `_cleanup` or the lock leaks on every exit. Never add a TERM/INT trap (a trapped TERM is deferred by a foreground child; mutation row 10).
- `$(...)` subshells do not run the parent's EXIT trap: keep acquire/release in the main shell.
- Record `$$`, never `BASHPID`; under `timeout 90 bash "$SUT"` the recorded pid is the script's own bash.
- The existing suite sleeps at the 10 s floor (245 s in CI): all new tests live in the new fast suite.
- A refusal line is an event the Monitor tool delivers; keep it on stdout and keep verdict tokens out of it.
- The dir check (owned, not a symlink, writable) is what stops a pre-created hostile `/tmp` path from becoming the lock root.
- Residuals, each degrading to a duplicate monitor or a hint-recoverable refusal, never a silent false refusal: macOS BSD `ps` not run here; a holder in another PID namespace reads as dead; two sessions resolving different `XDG_RUNTIME_DIR` never see each other; a clock step can shift `lstart` (reclaim -> duplicate); two contenders racing after a SIGKILL can both win; a vanished stdout reader leaves the lock until its next write (<= 10 min at defaults); how the Monitor tool signals a stopped watch is unverified, so a wrapper-only kill would keep the lock for up to the poll budget (2 h at defaults) - the refusal leads with `kill <pid>`.
- `ln -s '' x` fails ENOENT: the "empty value" fixture is a regular file, not a symlink.
- As root, `kill -0 1` and `[ -w ]` on a `chmod 500` dir both succeed: gate the pid-1 and read-only-dir arms on non-root with a loud, non-counted skip.
- Content anchors, not line numbers, in this plan and in the PR (the lines shift with every edit).

## Non-goals

- P4d (bounded wait on rc=4 battery refusal) and #10932: separate PRs, not planned here.
- Adopting the lock in other pollers (`sync-pr-behind.sh` loop, ship Phase 7 poll, `triage-prs.sh`).
- Any change to `monitor-supersede-guard.sh`, `monitor-arm-recorder.sh`, `lib/monitor-sig.sh`.
- Any workflow edit, including `.github/workflows/apply-web-platform-infra.yml` and the apply-workflow annotations (umbrella item 2).
- Killing or taking over a live holder; a lock-age ceiling; waiting indefinitely for a holder; a `purpose` dimension.
