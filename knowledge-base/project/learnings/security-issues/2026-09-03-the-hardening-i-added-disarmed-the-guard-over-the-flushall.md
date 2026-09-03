---
module: inngest-cutover-flip
date: 2026-09-03
problem_type: security_issue
component: infra_systemd_unit
symptoms:
  - "A Doppler secret NAME was arbitrary command execution as root at the next 30s poll"
  - "ProtectSystem=strict + ReadWritePaths made mountpoint -q pass for an unmounted volume"
  - "Three test suites reported a green exit code with every assertion silenced by one line"
  - "A committed rollout probe could never PASS and its failure arm could never FAIL"
root_cause: guard_narrower_than_property
severity: critical
tags: [doppler, systemd, seam-guard, bind-mount, anti-vacuity, mutation-testing, measurement]
synced_to: [review, work, qa]
---

# The hardening I added disarmed the guard over the FLUSHALL

## Problem

`inngest-cutover-flip.service` runs as root under a bare `doppler run --config prd`, which injects
the whole `soleur-inngest/prd` config into the process environment. The flip script reads its
fixture seams straight from that environment and **executes** several of them
(`CUTOVER_REDIS_CLI_CMD`, `CUTOVER_SYSTEMCTL_CMD`, `CUTOVER_FLAG_SET_CMD`, `CUTOVER_LOGGER_CMD`,
`CUTOVER_CURL_CMD`). Every one is a legal Doppler secret name.

So **write access to the Doppler config was arbitrary command execution as root** on the dedicated
inngest host, at the next 30-second timer fire, inside the same unit that performs an irreversible
Redis `FLUSHALL`. The trust boundary was reasoned about as "root on the host"; it was in fact
"write access to a secrets config".

Measured against live Doppler: the bare form injected 10 names including `INNGEST_POSTGRES_URI`,
the production DSN.

## Solution

Two halves, closing different holes:

1. **The unit bounds what is injected at all** — `--only-secrets INNGEST_CUTOVER_FLIP
   --only-secrets INNGEST_REDIS_PASSWORD --no-exit-on-missing-only-secrets`. Measured: 10 names → 2.
   This is the only half that reaches `BASH_ENV`, `PATH`, `LD_PRELOAD` and `IFS`, which bash honours
   without the script ever naming them, because it filters **before** exec.
2. **The script gates its seams on argv** — honoured only under `--fixture-seams`, which a config
   writer cannot supply because argv is not the environment.

The fail-open flag is deliberate: `INNGEST_CUTOVER_FLIP` is legitimately absent on a pre-arm host,
and measured, `doppler run` exits 1 on a listed-but-absent name — which would stop the 30-second
poll dead.

## Key Insight

**The hardening I added to protect the unit disarmed the guard over its irreversible operation.**

`ProtectSystem=strict` expresses a writable hole in a read-only tree the only way it can: by
**bind-mounting each `ReadWritePaths=` entry onto itself**. And `mountpoint(1)` answers from
`/proc/self/mountinfo` (verified by strace, util-linux 2.41.3). So adding `ReadWritePaths=/mnt/data`
made `mountpoint -q /mnt/data` return **true for a volume that never mounted** — which is precisely
the state the FSM's pre-`FLUSHALL` durability gate exists to detect, since cloud-init mounts with
`|| true` under fstab `nofail`.

The failure was silent and fail-*unsafe*: gate passes → `FLUSHALL` runs → the anti-double-flush
latch is written to the ephemeral root disk **looking durable** → the next host replace erases it →
a later re-arm flushes a live production queue. That is the exact catastrophe the latch exists to
prevent, reopened *through* the guard rather than around it.

The fix is a device-vs-parent `st_dev` comparison — the test `mountpoint` itself used before it
moved to mountinfo. A bind mount preserves `st_dev`, so the predicate is immune to it while still
answering the real question.

```bash
is_real_mount() {
  local p="$1" d pd
  d="$(stat -c %d "$p" 2>/dev/null)" || return 1
  pd="$(stat -c %d "$p/.." 2>/dev/null)" || return 1
  [[ -n "$d" && -n "$pd" && "$d" != "$pd" ]]
}
```

**The generalisable half: on a fix PR, review the new VERIFICATION before the new code.** A fix is
written holding the defect in mind, so its tests inherit that framing. Of ~60 findings from a
ten-agent panel, almost every merge-blocking one lived in the tests, guards or prose — not in the
fix:

- **All three suites reported their assertion floor THROUGH the `fail()` helper the floor
  backstops.** One dropped increment silenced every assertion *and* the floor together, at exit 0.
  Measured: the flip suite printed `116 passed, 0 failed` with eleven real FAIL lines nothing
  counted; Guard 2 self-consistently reported `20/20 passed` with ten rows failing, because its
  denominator is `PASS+FAIL`. The asymmetry is exact — neutering `pass()` was always caught, since
  the floor sums PASS. The fix already existed 200 lines away in a sibling suite.
- **A committed probe grepped a string its own rows never carry.** `emit_state` emits bare JSON
  whose identity lives in the syslog tag, so the probe could never PASS and its flush assertion
  could never FAIL — and its test stub ignored `--grep`, so it certified that 19/19 green. *A fake
  that answers regardless of the request cannot observe the request being wrong.*
- **Two extractors read raw source**, so a comment naming a seam satisfied the completeness
  tripwire — the exact defect the tripwire exists to prevent.
- **A widening admits a region no existing fixture covers.** Every fixture was written against the
  narrower predicate, so the guard passes through the entire regression.

## Prevention

- For any sandboxing directive, ask **what it changes about the namespace the guarded code
  observes** — not just what it protects. `ReadWritePaths` is a *mount*, and anything predicated on
  mounts is now lying.
- Never route an anti-vacuity floor through the helper it backstops. Use `printf` + `exit`, and add
  an instrument self-test that drives `pass()`/`fail()` once each and refuses to continue unless
  both counters moved.
- A stub must **apply** the parameter under test. If the fake answers regardless of the request, it
  cannot see the request being wrong, and every row is scored through an oracle blind to that class.
- Comment-strip before any extraction that feeds a completeness assertion — the moment a task
  requires both "assert X" and "document X", they collide.
- For every causal or universal claim added in prose, name the falsifying command and run it. Six
  claims here were false, each refuted in seconds.

## Session Errors

- **Claimed "neither half is sufficient alone" in four places.** The unit's environment has exactly
  two sources, and the non-Doppler one is a fixed `printf` of Terraform values — so `--only-secrets`
  *is* sufficient against the stated threat. **Recovery:** corrected all four, with the real
  justification (the gate is the backstop for a bound that is silently lost or narrowed).
  **Prevention:** check a sufficiency claim by enumerating the channels, not by reasoning about the
  mechanism.
- **Claimed a doppler `Warning:` "rides journald to Better Stack" as the fail-open's mitigation.**
  The unit set no `SyslogIdentifier`, so journald tagged it `doppler` — a tag no Vector source
  admits. **Recovery:** added the identifier (already allowlisted) and corrected the claim.
  **Prevention:** a mitigation that names a channel must be traced to that channel's allowlist.
- **Five line-number citations stale by exactly 86** — the gate's own length, written pre-insertion.
  **Recovery:** replaced with content anchors. **Prevention:** `cq-cite-content-anchor-not-line-number`.
- **A bare-token grep for `--no-fallback` matched my own explanatory comment.**
  **Recovery:** reworded the comment to drop the literal and anchored the check on the ExecStart
  construct. **Prevention:** treat every absence-check whose literal also appears in prose as guilty.
- **Read `VERIFY_RC=0` from `head` rather than `systemd-analyze`.** **Recovery:** captured rc
  explicitly with no pipe. **Prevention:** never read `$?` through a pipeline.
- **`PROBE_OUT` assigned inside a command substitution.** Command substitution runs in a subshell,
  so every message assertion compared against an empty string while the exit-code assertions kept
  passing. **Recovery:** routed the output through a file. **Prevention:** a function called as
  `x=$(fn)` loses every effect except stdout.
- **A `sed` mutation injected 0 lines and I nearly read the resulting `rc=0` as evidence.**
  **Recovery:** asserted the mutation landed before believing any verdict. **Prevention:** a
  mutation that does not land reports the baseline, which is indistinguishable from a pass.
- **Raising `ACK_CARDINALITY` broke two mutation rows carrying the transcribed literal — one inside
  the mutation itself, so it silently no-opped.** **Recovery:** both derive it now. **Prevention:**
  a transcribed literal in a mutation row is the replicated-literal class one level up.
- **Widening a seam predicate admitted a false member** (`DETAIL_SRC`, a path that is read, never
  executed). **Recovery:** excluded `$` from the assignment prefix. **Prevention:** after any
  widening, ask what it now accepts that it did not, and which fixture lives there.
- **`ALT_ROOT` allocated with a bare `mktemp` and cleaned only on the happy path.** **Recovery:**
  one owning EXIT trap. **Prevention:** caught by `lint-trap-tempfile-ownership.py` — run the
  deterministic lints per guard-shaped commit, not once at session start.
- **The `scripts` shard returned rc=4 — refused, nothing measured** (a sibling full-gate run was in
  flight). **Recovery:** ran targeted suites instead. **Prevention:** rc=4 is neither pass nor fail.
- **Better Stack returned 503 "under maintenance"**, blocking the Phase 0 liveness read.
  **Recovery:** the Doppler read carried through it, as the plan anticipated. **Prevention:** an
  empty telemetry query is not evidence of absence.
- **Forwarded from the plan phase:** the GitHub MCP server failed to connect (worked around with
  `gh`); a heredoc was denied for containing a Doppler secret-set literal; `lint-guard-contract.py`
  required matrices as tables, not numbered lists; `lint-infra-no-human-steps.py` rejected prose
  pairing a human actor with an infra imperative. **Prevention:** all four are one-off shape fixes.

## Plan claims falsified at QA

- **Scenario 19's negative control does not exist.** It claimed a unit whose `ReadWritePaths` names
  a missing directory fails `systemd-analyze verify`. Measured: **rc=0, empty output** — verify
  validates directive syntax, not path existence. The Risks table had cited it as the mitigation for
  the sharpest hazard in the change.
- **"`git-data-gc` injects roughly 129 secrets into the host that holds every connected user's
  source code"** — uncited, and wrong in the present tense. `prd_git_data` is not among the 13 live
  `soleur` configs, and the expense ledger records that host as never having existed. It injects
  nothing today; the live members of that set are the three web-host units, which inverts the
  sequencing the plan recommended.

## Tags

category: security-issues
module: inngest-cutover-flip
