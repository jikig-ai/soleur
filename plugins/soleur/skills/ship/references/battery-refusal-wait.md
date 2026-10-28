# Refused local battery: bounded wait, then "CI is the gate" (P4d)

Loaded from `soleur:ship` Phase 4 when the detached local battery is **REFUSED** (rc=4, nothing ran) because a sibling worktree already runs a full-gate battery. The script is [battery-refusal-wait.sh](../scripts/battery-refusal-wait.sh); its header carries the contract, this file carries the recipe and the record.

Scope: only the sibling-run refusal (`refusing a full-gate run ... N sibling full-gate run(s) already in flight`) is waitable. Every other rc=4 (selection refusals, a gutted index, `SOLEUR_SUBAGENT=1`, a toolchain fault) keeps stop-and-fix; the script answers `NOT_WAITABLE` (exit 11) for them. The monitor-lock rc=4 of `monitor-pr-checks.sh` is a different exit and is not handled here.

## Recipe (one Monitor script, `persistent: true`)

Launch first: a refusal exits in under a second, so there is no up-front capacity loop. The Monitor tool's default 5-minute timeout is shorter than the 30-minute budget, hence `persistent: true`.

```bash
d="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"; LOG="$d/log"; RCF="$d/rc"; STATE="$d/state"; : > "$STATE"
FULL=""   # set to --full when soleur:ship was invoked with --full
launch() { rm -f "$RCF"; setsid nohup bash -c 'bash scripts/test-all.sh --affected > "$1" 2>&1; echo $? > "$2"' _ "$LOG" "$RCF" >/dev/null 2>&1 & }
while :; do
  again=0; launch
  until [ -s "$RCF" ]; do sleep 30; done
  [ "$(cat "$RCF")" = 4 ] || { echo "BATTERY DONE rc=$(cat "$RCF") log=$LOG"; break; }
  bash plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh --log "$LOG" --state "$STATE" ${FULL:+--full}; wait_rc=$?
  case "$wait_rc" in
    10) echo "RELAUNCH: capacity idle"; again=1 ;;
    42) echo "CONTINUE_CI_IS_THE_GATE: budget elapsed, local battery not executed" ;;
    12) echo "QUEUE_IN_LOCK: the local run is the sole gate; use the queue-in-lock command in SKILL.md" ;;
    *)  echo "STOP: wait_rc=$wait_rc, read the log: $LOG" ;;
  esac
  [ "$again" = 1 ] || break
done
```

`wait_rc` is the script's status, never `rc`: the battery's `rc` and the wait's status are different facts. **Only 42 continues.** A stray 1 (`set -u` abort), 127 (script not found) or 130 (interrupt) lands in the `*` arm and stops; the suite drives that `case` with each status. Under `FULL_BATTERY` (an operator-typed `--full`) the local run was asked for by name, so the script never answers 42 there.

## The record (exit 42 only)

Print the verdict line in the transcript (the script already does: `BATTERY_REFUSAL_WAIT verdict=CI_IS_THE_GATE waited_s=<n> ...`) and add exactly this line to the PR body's Test plan, with `<n>` from `waited_s`:

```text
Local battery refused (sibling contention); waited <n>s; CI "test" is the authoritative gate; local run NOT executed.
```

The line states what did not happen. It never says the tests passed, and it is not evidence for the diff: CI's required `test` context is the gate, and a red there is fixed like any red.

## Where CI is not the gate

`apps/web-platform/infra/` has no required CI check (#6480), so a diff touching it (or `.github/workflows/apply-web-platform-infra.yml`, or any git failure resolving the diff) never gets 42: after the budget the script answers 12 and the local run is queued inside the lock. The same holds for an explicit `--full`.

## See also

- [affected-gate-contract.md](./affected-gate-contract.md): the rc contract of the affected gate (rc 4 = refused).
- When substituting hand-picked suites for a refused gate instead, derive them from the diff's new vocabulary, not its file names: `knowledge-base/project/learnings/2026-09-11-the-shard-i-substituted-for-a-refused-gate-was-the-one-that-was-red.md`.
