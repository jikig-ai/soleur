---
date: 2026-05-12
class: session-error
component: web-platform/infra
related_pr: "#3704"
---

# PGID inheritance and bash TERM-trap defer on foreground commands

## Setting

Implementing #3704's "wall-clock cap on ci-deploy.sh + SIGTERM/INT trap" per a plan whose deepen-pass prescribed `set -m + kill -TERM 0` as the canonical "kill me and everything I spawned" pattern. Two empirical findings at /work + /review invalidated parts of the plan's reasoning.

## SE1 — `set -m` does NOT move bash itself out of the parent's PGID

**Claim in plan v1 (deepen-pass):** "Adding `set -m` makes the script a process-group leader, and `kill -TERM 0` in the trap signals the entire foreground PGID."

**Empirical reality (parent.sh/child.sh repro):**

```bash
# parent.sh — runs from a non-interactive shell, NOT set -m
bash /tmp/child.sh &
# child.sh
set -m
echo "child pid=$$ pgid=$(ps -o pgid= $$ | tr -d ' ')"
```

Output: child `pid=3570999 pgid=3570995` (PARENT's PID). `set -m` enables job control for FUTURE foreground/background commands inside bash — it does NOT call `setpgid(0, 0)` on bash itself. Subsequent foreground/background children DO get new PGIDs (verified: a backgrounded `sleep 30 &` shows `pid=3565723 pgid=3565723`), but bash inherits whatever PGID its parent gave it.

**Production implication:** ci-deploy.sh is fork-exec'd by adnanh/webhook (which itself runs as `webhook.service`). `webhook` does not call `setpgid` before fork-exec — the child bash inherits webhook.service's PGID. `kill -TERM 0` from inside ci-deploy.sh's trap would therefore TERM `webhook` itself and cascade-restart-noise it. systemd `Restart=on-failure` would mask this, but the operator would lose `/hooks/deploy-status` for the restart window and any in-flight HMAC-validated requests.

**Verification at second-level:** ran `bash parent.sh` with a TERM trap in child that calls `kill -TERM 0`. Parent died ("Terminated", rc=143) within 1s of the child receiving SIGTERM. Confirmed PGID propagation.

**Shipped fix:** `pkill -TERM -P $$` in the trap (PPID-based). Reaches only direct children of bash, never the parent. Safe regardless of who fork-execs ci-deploy.sh.

## SE2 — Bash defers TERM trap dispatch during foreground commands

**Claim in plan v1:** the TERM trap will fire "in the very next poll" when the wrapper's `timeout` sends SIGTERM at 900s, producing a terminal `exit_code=124 reason=timeout` state.

**Empirical reality (test design pivot):** bash's signal-handling docs state: "If bash is waiting for a command to complete and receives a signal for which a trap has been set, the trap will not be executed until the command completes." Verified directly:

```bash
trap 'echo TRAP at $(date +%s); exit 124' TERM
echo "starting fg sleep at $(date +%s)"
sleep 30
```

Sending SIGTERM at t=0s: the trap fired at t=30s (after `sleep` returned), not at t=0s. Same behavior for `docker pull` blocked on a network syscall in production.

**Production implication:** the trap is BEST-EFFORT observability. For hung-foreground hangs (`docker pull` blocked indefinitely — the actual #3704 failure surface), bash is wedged in `waitpid()` and the trap doesn't dispatch. The wrapper's `--kill-after=20s` SIGKILL fires at t=920s; bash dies on SIGKILL (no trap can run); state stays at `running`. The workflow's Pre-rerun lock probe at the next deploy sees `elapsed > 900s` and degrades-permissive past the stale state. The wrapper is the load-bearing safety net; the trap covers the subset of hangs where bash IS dispatchable (between commands, in `wait $!`, in shell logic).

**Shipped test design:** ci-deploy.test.sh's SIGTERM coverage has two parts because the production trap is not directly exercisable end-to-end:
- **Static check** — greps ci-deploy.sh for the canonical trap pattern.
- **Isolated repro** — heredoc'd minimal script using `sleep & wait $!` (the `wait` builtin is interruptible immediately) so the trap CAN fire and the contract (state file + exit code + no orphans) is verified.

## Pattern for future shell-trap work

When wrapping a long-running shell script with a wall-clock cap that delivers SIGTERM:

1. Default to **`pkill -TERM -P $$`** in the trap (PPID-based, never escalates to parent).
2. Reserve `kill -TERM 0` (PGID-based) for cases where the script is **explicitly its own session leader** — e.g., started via `setsid` or `daemon(3)`. Verify with `ps -o pgid= $$` at script start.
3. Clear the trap **before** sending kill: `trap - TERM INT` first, then `pkill`. Prevents a queued second-signal (from `--kill-after` grace) re-entering the handler mid-write.
4. Treat the trap as best-effort. For correctness, the load-bearing primitive is the wrapper's SIGKILL fallback (`--kill-after=Ns`) — bash dying releases any FD-held locks regardless of trap dispatch.
5. Test the trap in an isolated repro that uses `sleep & wait $!` to bypass bash's foreground-defer; document the gap between repro coverage and prod coverage.

## SE3 — uutils `timeout` rc=125 vs GNU rc=124 on SIGTERM-by-timeout

**Setting:** Dev box on Ubuntu 25.04+ (questing) where `/usr/bin/timeout` is the rust uutils variant from `coreutils-from-uutils`, not GNU coreutils. The wrapper-test's behavioral assertion `timeout --signal=TERM --kill-after=20s 1s sleep 60` expects exit code 124 (GNU's convention for "TERM-by-timeout"). uutils sends the signal correctly but exits 125 ("timeout itself failed"), masking the contract test.

**Recovery:** Detect via `timeout --version | grep -qi uutils`. If detected, fall back to `/usr/bin/gnutimeout` (provided by Ubuntu's `gnu-coreutils` package). If neither is available, SKIP the behavioral test with an explicit log line.

**Prevention pattern:** When verifying CLI primitive behavior in tests, detect coreutils flavor up-front:

```bash
pick_timeout() {
  if timeout --version 2>&1 | head -1 | grep -qi uutils; then
    command -v gnutimeout || echo SKIP
  else
    echo timeout
  fi
}
```

Production (Ubuntu 24.04 LTS noble) ships GNU coreutils so the wrapper's bare `timeout` invocation is correct; this is a test-harness-only concern.

## SE4 — Cross-tool regex gotchas in the parity test

Two papercuts during the wrapper/workflow 900s parity test:

**SE4a:** `grep -oE '--kill-after=[0-9]+s [0-9]+s /usr/local/bin/ci-deploy\.sh'` failed with `grep: unrecognized option '--kill-after=…'`. grep parses leading `--` as flag-stop or unknown flag. Fix: `grep -oE -- '--kill-after=…'` (POSIX argument separator) or `grep -oE -e '--kill-after=…'`.

**SE4b:** First extraction attempt `grep -oE '[0-9]+s '` matched both `20s` (from `--kill-after=20s`) and `900s` — `head -1` then picked the wrong one. Fix: anchor on position-bearing context (`grep -oE ' [0-9]+s /'` to pick the digit between `--kill-after=20s ` and `/usr/local/bin/`).

**Prevention pattern:** Multi-token regex extraction must pin positional context, not just shape. When two tokens of identical shape coexist in one line, anchor the extraction on the literal text that disambiguates them (space-before-and-slash-after, not just `\d+s`).
