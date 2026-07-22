---
module: web-platform-infra
date: 2026-07-19
problem_type: test_failure
component: shell_script
symptoms:
  - "C1 byte-identity verify aborted with exactly 1 difference on two consecutive real freezes"
  - "icode=>fcst...... path=redis/appendonlydir/appendonly.aof.94.incr.aof"
  - "28/28 green test suite, clean shellcheck, and 191/191 full suite all missed 4 P1s and a P0"
root_cause: incomplete_quiesce_set_and_self_violating_test_harness
severity: critical
tags: [luks, cutover, quiesce, sigpipe, pipefail, canary, readiness, mutation-testing, vacuous-test, fail-open]
issue: 6588
synced_to: [work, review, qa]
---

# The harness broke the rule it enforced, and the canary could not fail

`Ref #6588` / PR #6701. Fixing the /workspaces LUKS cutover freeze after two real
production aborts. Every headline below is a **gate that certified the wrong property**.

## Problem

Two consecutive REAL freezes (runs `29676994044`, `29687729540`) safe-aborted on the C1
byte-identity verify with exactly one difference:

```
SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF count=1 idx=0
  icode=>fcst...... path=redis/appendonlydir/appendonly.aof.94.incr.aof
```

`>fcst......` = checksum + size + mtime differ: a file being appended to during the copy.
`inngest-redis.service` persists its AOF to `/mnt/data/redis` and is a **systemd unit, not a
container**, so `docker stop "$CONTAINER"` never touched it. DP-6 auto-rolled back both times;
no data lost. **The C1 gate was right. The writer was not quiesced.**

## Solution

Quiesce the writer, and — per multi-agent review — six further defects the first fix left or
introduced. See PR #6701 for the diff.

## Key Insight 1 — the invariant a suite enforces on the SUT applies to the harness

The suite exists to forbid `lsof … | grep -q` under `set -o pipefail`: `grep -q` exits on first
match, the producer takes SIGPIPE, the pipeline returns **141**, so `&& die` never fires. It is a
*size-dependent fail-open* — the gate evaporates precisely when there are many stragglers. That is
pinned by `T8` and mutation `M3`.

The harness then used `calls | grep -q` at **12 assertion sites**. On a NEGATIVE assertion
(`if ! …`) 141 fails **OPEN**, so `T11`/`T13`/`T14` and mutations `M1`/`M4` could report green
while the property was violated. Worse — `undef()`, the guard written specifically to stop vacuous
passes, had the same shape, and `HARNESS_UNDEFINED:` is line 1 so the match is *always* early:
`T7`/`T8` passed against a script where the functions **do not exist**.

```bash
# WRONG — 141 under pipefail on an early match; a negative assertion silently passes
if ! calls | grep -qE '^systemctl stop inngest-server'; then ok "never stops it"; fi

# RIGHT — grep the file directly; no pipe, no SIGPIPE, no fail-open
nhas() { ! grep -qE -- "$1" "$CALLS"; }
undef() { [[ "$CASE_OUT" == *"HARNESS_UNDEFINED:"* ]]; }   # bash match, not a pipe
```

**A green run of a suite with this defect is not evidence.** Ask of every harness: *does it obey
the rule it exists to enforce?* Cheapest check — grep the test file for the shape it forbids in
the SUT. See [[2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards]]: this class was
documented **one day** before this session and recurred anyway, in the file whose entire purpose was
to pin it.

## Key Insight 2 — replacing a gate that always fails with one that can never fail is not a fix

The pre-existing canary probed `https://app.soleur.ai/api/health`, which has no route and 307s to
`/login`. Asserting `== 200` on it would have aborted **every otherwise-successful cutover** at the
last gate, after the mount was already repointed. Correct diagnosis.

The fix repointed it to `/health` — which is `res.writeHead(200)` **unconditionally**
(`server/index.ts`, comment: *"Always return 200 for load balancer probes"*), and
`server/readiness.ts` states the invariant explicitly: *"/health stays untouched — physically
enforcing the 'no mount coupling on /health' invariant."* So the replacement is the one endpoint in
the codebase **architecturally guaranteed not to reflect the volume being repointed**. If the mapper
mounts but `$MOUNT/workspaces` is absent, docker auto-creates an empty bind source, the container
serves an empty `/workspaces`, and the cutover reports green with every user's source code missing.

Compounding it: `CANARY_OK=1` was set by the *host* canary and `disarm_dead_man` ran **before**
`app_canary` — so rollback was already suppressed and the backstop already cancelled at the one gate
that proves user-facing health.

**When repointing a health probe, ask what it is COUPLED to, not whether it returns 200.** Prefer
the purpose-built readiness endpoint (`/internal/readyz` asserts `workspaces_writable` +
`workspaces_populated`) over the load-balancer liveness probe. Sibling of
[[2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire]].

## Key Insight 3 — the reported symptom is a LOWER BOUND on the blast radius

Fixing the named writer left `orphan-reaper.timer` — a 6-hourly **root `rm -rf`** over
`/mnt/data/workspaces/*.orphaned-*` with **no** `RequiresMountsFor` — entirely unquiesced. Firing
between the delta rsync and the verify it makes `rsync --delete --dry-run` emit a `*deleting` line:
the **identical** C1 abort signature, on a 6h duty cycle against a ~20 min freeze.

Also missed: a **running** `luks-monitor.service` (stopping a `.timer` does not stop the instance it
already launched — quiesce timers as `<timer> <service>` **pairs**), and the canary container
sharing the same RW bind mount. And G4 was a **single point-in-time sample** ~10 minutes before the
verify it protects, so any writer starting after it was undetected by construction.

**The quiesce set is a property of the MOUNT, not of the units anyone thinks of as "part of the
cutover."** The enumeration is *"what else opens, writes, or deletes under this path?"*

## Key Insight 4 — `lsof` cannot distinguish "clean" from "failed", so prove the probe ran

`lsof` exits **1 both** when it finds nothing and when it errors, writing diagnostics only to
stderr. So `holders="$(lsof +D "$MOUNT" 2>/dev/null || true)"` reads *probe failure* as
*mount is clean* — a typo'd `$MOUNT` or an unstat-able subtree (docker overlay filesystems already
warn on this host) passes the gate blind. Fixed with a **positive control**:

```bash
exec 9>"$probe"                      # hold our own fd under $MOUNT
lsof +D "$MOUNT" >"$lout" 2>"$lerr"; rc=$?
exec 9>&-
[ "$rc" -gt 1 ] && die "the G4 probe itself FAILED (rc=$rc)"
grep -qF -- "$probe" "$lout" || die "lsof did not report our own fd — the probe is BLIND, not clean"
```

Empty output now **proves** the scan reached the mount instead of assuming it. Mirrors
`verify_byte_identity`, which captures stdout/stderr separately and treats a probe error as
fail-closed for the same reason.

## Key Insight 5 — byte-identity is not integrity

`systemctl stop` returns **0 after a SIGKILL** at `TimeoutStopSec`. So a torn AOF tail is
byte-perfectly copied, C1 certifies it, and Redis silently discards the tail at restart under the
default `aof-load-truncated yes` — every reminder armed in the last seconds vanishes with no error.
`systemd` sets `Result=timeout` on the kill, so assert it.

## Key Insight 6 — the unit that fails SAFELY is not the dangerous one

`inngest-redis.service` carries `RequiresMountsFor=/mnt/data`, so on a failed remount systemd
refuses to start it — it fails *safely* into `failed`. `webhook.service` carries **no**
`RequiresMountsFor` (only `ReadWritePaths=/mnt/data`), so it starts **successfully onto the bare
root-disk mountpoint directory** — and it is the CI deploy receiver, so a deploy landing during the
incident writes user data to the root filesystem, shadowed the instant the volume is remounted.
Guard the restore on `mountpoint -q`, never on unit properties.

## Session Errors

1. **IaC write-guard blocked the plan write twice** (forwarded from `session-state.md`) — the
   `<!-- iac-routing-ack -->` comment was placed before the YAML frontmatter; the hook honors it
   only in the body. **Prevention:** put the ack comment in the body, after frontmatter.
2. **Probed the wrong host** (`soleur.com/health`) and reported an SSL error before checking the
   script's actual canary URL. **Prevention:** derive probe URLs from the code under test, never
   from memory.
3. **`shellcheck … | head` then `echo EXIT=$?`** read `head`'s status, not shellcheck's.
   **Prevention:** capture `rc` before piping (`cmd > "$log"; rc=$?`).
4. **Background bash with a trailing `echo` reported "exit code 0" twice while `TESTALL_EXIT=1`.**
   **Prevention:** never end a backgrounded command with `echo`; always grep the log for the
   runner's own summary.
5. **A Monitor tailed a stale log** and reported 190/191 after the fix had already landed.
   **Prevention:** key the monitor to a per-run log path.
6. **T8 was vacuous via E2BIG** — a multi-MB `LSOF_OUT` passed through `env` exceeded the argv
   limit, so the subshell died before the harness precondition ran and "must exit non-zero" passed
   for the wrong reason. **Prevention:** pass large fixtures by file, never by env.
7. **The `lsof` stub's `return 0` swallowed the SIGPIPE** that mutation M3 exists to reproduce.
   **Prevention:** stubs must propagate the producer's status (`return $?`).
8. **AC5's body-grep matched its own comment** explaining the trap. **Prevention:** strip
   `^[[:space:]]*#` before grepping a script body (`cq-assert-anchor-not-bare-token`).
9. **T12 repeated #8** — a bare-token grep matched the comment block just expanded to mention the
   token, while the correct comment-stripping fix sat **8 lines below** in AC5.
   **Prevention:** when a file already contains the fix for a class, grep the whole file for other
   instances of that class before shipping.
10. **The harness committed the SIGPIPE bug the suite forbids** (Key Insight 1).
    **Prevention:** grep the test file for the shape it forbids in the SUT.
11. **Loose `/tmp` mktemp scratch reaped mid-run** → phantom SUT regressions (3 different failing
    sets across 5 runs). **Prevention:** one per-run scratch dir; a missing scratch file is a
    HARNESS error, never evidence.
12. **A 5-line cloud-init comment blew the `user_data` gzip budget** (22620 vs 22450).
    **Prevention:** rationale belongs in the ADR, not baked into every host's `user_data`.
13. **Stop/restore asymmetry** — webhook stopped unconditionally, restored only if present in
    `QUIESCE_UNITS`. **Prevention:** drive stop and restore off one derived list.
14. **Missed writers** — `orphan-reaper`, a running `luks-monitor.service`, the canary container
    (Key Insight 3). **Prevention:** enumerate by mount, not by unit familiarity.
15. **The canary could not fail** (Key Insight 2). **Prevention:** ask what the probe is coupled to.
16. **G4 still fail-open** on `lsof` rc conflation (Key Insight 4). **Prevention:** positive control.
17. **`resume_writers` introduced a root-disk data-loss vector** (Key Insight 6).
    **Prevention:** guard restores on `mountpoint -q`.
18. **The corrected `dry_run` description overclaimed 2 of its 5 COVERS clauses** — a *new*
    misrepresentation inside the fix for a misrepresentation. **Prevention:** verify every clause of
    a correction against the code and assert them (AC9b), not just the headline disclaimer.
19. **Wrong `/health` attribution** — cited `middleware.ts:113`; it is served by the custom server at
    `server/index.ts` before Next routing ever runs. **Prevention:** trace the actual handler.
20. **`disarm_dead_man` ran before `app_canary`** (pre-existing, but these lines were rewritten).
    **Prevention:** the backstop is disarmed LAST, after the gate it backstops.

## Process observation

Eight parallel review agents found **4 P1s and a P0** that a 28/28 green suite, a clean
`shellcheck`, and a 191/191 full suite all missed. **Three were introduced by the fix itself.** The
suite went 28 → 58 assertions with 7 mutation twins as a result. The generalizable point is not
"review is useful" — it is that *every one of those gates certified a property adjacent to the one
that mattered*: the suite certified its own assertions ran, shellcheck certified syntax, the full
suite certified no regression elsewhere. None certified *the freeze is safe*.

## Related

- [[2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards]] — the SIGPIPE class,
  documented one day earlier and recurred here in the file meant to pin it
- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] — a green battery is evidence about
  the mutations, not about the tests
- [[2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire]] — sibling of
  Key Insight 2
- [[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]] —
  the comment-matching class of errors 8/9
- [[2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report]] —
  the routing + self-reporting predecessor for this same cutover
