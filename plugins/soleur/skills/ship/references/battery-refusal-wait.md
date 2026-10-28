# Refused local battery: bounded wait, then "CI is the gate" (P4d)

Loaded from `soleur:ship` Phase 4 when the detached local battery is **REFUSED** (rc=4, nothing ran) because a sibling worktree already runs a full-gate battery. The script is [battery-refusal-wait.sh](../scripts/battery-refusal-wait.sh); its header carries the contract, this file carries the recipe and the record.

Scope: only the sibling-run refusal (`refusing a full-gate run ... N sibling full-gate run(s) already in flight`) is waitable. Every other rc=4 (selection refusals, a gutted index, `SOLEUR_SUBAGENT=1`, a toolchain fault) keeps stop-and-fix; the script answers `NOT_WAITABLE` (exit 11) for them. The monitor-lock rc=4 of `monitor-pr-checks.sh` is a different exit and is not handled here. Two forms of contention exist and each is already bounded: an `--affected` run that degrades to full, or `--full`, is **refused** (rc=4, this file); a plain `--affected` run is exempt from the refusal and queues on the lock, where `affected-tests.sh` rc 6 is the budget deferral that already means "CI authoritative".

## Recipe (one Monitor script)

Launch first: a refusal exits within seconds, so there is no up-front capacity loop. Arm the Monitor with `persistent: true` (the default 5-minute timeout is shorter than the 30-minute budget). If the Monitor you have rejects `persistent`, arm it at its maximum timeout and, when it expires without a verdict, re-arm a tail-only script that reuses the same `$d` (the recipe prints `BATTERY_DIR=<d>` first; `$LOG`, `$RCF` and `$STATE` are `log`, `rc` and `state` inside it) (the detached battery keeps running and `$STATE` carries the budget); never re-run the recipe from its first line, which starts a new episode and a second battery. Run it from the repository root.

```bash
d="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"; LOG="$d/log"; RCF="$d/rc"; STATE="$d/state"; : > "$STATE"; echo "BATTERY_DIR=$d"
FULL=""; [ "${FULL_BATTERY:-}" = true ] && FULL=--full
launch() { rm -f "$RCF"; setsid nohup bash -c 'bash "$1" $4 > "$2" 2>&1; echo $? > "$3"' _ "${CLAUDE_PLUGIN_ROOT}/scripts/affected-tests.sh" "$LOG" "$RCF" "$FULL" >/dev/null 2>&1 & }
relaunches=0
while :; do
  again=0; launch
  until [ -s "$RCF" ]; do sleep 30; done
  [ "$(cat "$RCF")" = 4 ] || { echo "BATTERY DONE rc=$(cat "$RCF") log=$LOG"; break; }
  bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/battery-refusal-wait.sh" --log "$LOG" --state "$STATE" ${FULL:+--full}; wait_rc=$?
  case "$wait_rc" in
    10) echo "RELAUNCH: capacity idle"; again=1 ;;
    42) echo "CONTINUE_CI_IS_THE_GATE: budget elapsed, local battery not executed" ;;
    12) echo "QUEUE_IN_LOCK: the local run is the sole gate; use the queue-in-lock command in SKILL.md" ;;
    *)  echo "STOP: wait_rc=$wait_rc, read the log: $LOG" ;;
  esac
  [ "$again" = 1 ] || break
  relaunches=$((relaunches + 1))
  [ "$relaunches" -le 3 ] || { echo "STOP: capacity reads idle but the runner keeps refusing (after $((relaunches - 1)) relaunches)"; break; }
done
```

The launch is the pinned dispatch of SKILL.md Phase 4 (`affected-tests.sh`, plus `--full` under `FULL_BATTERY`), never a bare `test-all.sh`. `wait_rc` is the script's status, never `rc`: the battery's `rc` and the wait's status are different facts. **Only 42 continues.** A stray 1 (`set -u` abort), 127 (script not found) or 130 (interrupt) lands in the `*` arm and stops; the suite executes this recipe against stubs for every arm. `WAITING` lines arrive about once a minute and are progress only: take no action on them. Exit 42 is shared with `battery-owed.sh` SKIPPABLE on purpose (same caller action, independent contracts).

## The record (exit 42 only)

Print the verdict line in the transcript (the script already does: `BATTERY_REFUSAL_WAIT verdict=CI_IS_THE_GATE waited_s=<n> ...`) and add exactly this line to the PR body's Test plan, with `<n>` from `waited_s`:

```text
Local battery refused (sibling contention); waited <n>s; CI "test" is the authoritative gate; local run NOT executed.
```

The line states what did not happen. It never says the tests passed, and it is not evidence for the diff: CI's required `test` context is the gate, and a red there is fixed like any red.

## Where CI is not the gate

The `apps/web-platform/infra/` tree has no required CI check (#6480), so a diff touching it (or `.github/workflows/apply-web-platform-infra.yml`, an empty or unresolvable diff, or any git failure resolving it) never gets 42: after the budget the script answers 12 and the local run is queued inside the lock. The same holds for an explicit `--full`, and for a log carrying `AFFECTED_FALLBACK reason=force-all` (the operator's whole-battery lever).

## Known limits

- Idle is read from `--capacity`, which still counts a stale orphan past `TC_RUNTIME_CEILING_S` and low `/tmp`, while the refusal counts fresh siblings only. After the fresh sibling drains, an orphan can hold capacity non-idle and the wait runs to the budget; the loss is bounded and ends in CI or the lock queue. A stale orphan is itself an operator-visible fault.
- The wait can overshoot `--budget-s` by one capacity probe (`--probe-timeout-s`, default 30).
- A capacity reading anywhere in the budget counts (a transient probe failure on the last poll does not turn a long wait into a stop). A `--capacity` that is never readable is only discovered after the whole budget.
- If no rc file ever appears the wrapper was reaped (no rc file means a harness reap, SKILL.md): stop the Monitor and read `$LOG`. `$d` lives under `TMPDIR` and is not removed.
- Run from the repository root with an absolute `TMPDIR`: the script refuses a relative state path.

## See also

- [affected-gate-contract.md](./affected-gate-contract.md): the rc contract of the affected gate (rc 4 = refused, rc 6 = budget deferral).
- When substituting hand-picked suites for a refused gate instead, derive them from the diff's new vocabulary, not its file names: `knowledge-base/project/learnings/2026-09-11-the-shard-i-substituted-for-a-refused-gate-was-the-one-that-was-red.md`.
