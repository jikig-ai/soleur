---
title: "Acceptance evidence — parallelize independent local test-all suites safely (#8231)"
branch: feat-one-shot-8231-parallel-test-all
issue: 8231
plan: knowledge-base/project/plans/2026-09-17-feat-parallel-local-test-all-suites-plan.md
---

# Acceptance evidence

Every figure here is a measurement with the command that produced it beside it, per
`work/SKILL.md` ("publish the COMMAND next to the number, because a prose predicate does not pin a
count"). Where a measurement contradicts the plan, the plan is corrected here and the contradiction
is stated rather than reconciled away.

**Host.** 16 cores, `MemAvailable` 16,943,372 kB, bash `5.3.15(1)-release`, cgroup v2 unified.

---

## Phase 0.1 — `--enumerate` is now toolchain-independent

### 0.1.1 The defect, measured before the fix

```
$ bash scripts/test-all.sh --enumerate all ; echo $?
mise ERROR No version is set for shim: bun
...
1
$ bash scripts/test-all.sh --enumerate all 2>/dev/null | grep -c '^SUITE_REGISTRATION'
0
```

All five groups: `rc=1 registrations=0`.

**Mechanism.** `command -v bun` succeeds because a `mise` shim exists at
`~/.local/share/mise/shims/bun`, but `bun --version` exits non-zero with `No version is set for
shim: bun`. `scripts/test-all.sh` is `set -euo pipefail`, so `actual=$(bun --version)` was an
ABORT, and it sits above every registration emit.

This is not a host curiosity. Three registered consumers fail closed on that stream:

| Consumer | Fails closed on |
|---|---|
| `scripts/battery-tag-authorship.test.sh:224-260` | rc **and** count |
| `plugins/soleur/test/scripts-shard-totality.test.sh:231-238` | count only — it pipes the runner, so rc is the pipe's |
| `plugins/soleur/test/fullsuite-merge-gate.test.ts:173-176` | count (`toBeGreaterThan(0)`) |

`scripts/battery-tag-authorship` measured **exit 1** before the fix and **exit 0** after it. The
consumers are right to fail closed; the producer was wrong to hand them a zero for an environment
reason.

### 0.1.2 The group partition is exact

```
$ for g in scripts bun webplat infra all; do
    n=$(bash scripts/test-all.sh --enumerate "$g" 2>/dev/null | grep -c '^SUITE_REGISTRATION')
    echo "$g=$n"; done
```

| Group | Registrations |
|---|---|
| `scripts` | 422 |
| `bun` | 7 |
| `webplat` | 4 |
| `infra` | 1 |
| **sum** | **434** |
| `all` | **434** |

Partition holds. This independently confirms the plan's Overview figure of 434 registrations.

**Consequence for this work, stated early because it bounds everything downstream:** 422 of 434
registrations (97.2%) are in the `scripts` group. Whatever parallel mode this work ships is
overwhelmingly a statement about that one shard.

After registering `scripts/test-all-enumerate-toolchain`, `all` = **435**.
`bash scripts/lint-orphan-test-suites.sh` → `460 covered, 0 orphaned`, exit 0.

### 0.1.3 Consumer fail-closed audit

Confirmed by reading each consumer, table above. One honest nuance the plan did not record:
`scripts-shard-totality.test.sh` pipes the runner (`bash "$RUNNER" --enumerate scripts | grep …`),
so **rc is lost to the pipe** and only the count guard catches this class there. It is sufficient
for this defect, but it is a count-only guard, not the rc-and-count shape the plan assumed.

---

## Phase 0.2 — `wait -n -p` is available and exact

`BASH_VERSION=5.3.15(1)-release`, so `wait -n -p VAR -- pids…` is supported.

Probe: three children — a clean exit, `exit 7`, and one killed with `SIGTERM` while NOT trapping it.

| Child | rc observed | pid var | Signal-shaped |
|---|---|---|---|
| clean | 0 | set, correct | no |
| `exit 7` | 7 | set, correct | no |
| SIGTERM'd | **143** | set, correct | yes (SIG15) |
| `exec /nonexistent/binary` | **127** | **set** | no |

**Plan claim verified:** a SIGTERM'd child returns 143 through `wait -n -p`. Confirmed literally.

**Plan claim corrected:** plan task 3.3.2 prescribes a collector branch for *"rc 127 with an empty
pid var"*. Measured, rc 127 arrives with the pid variable **set** (`rc=127 pid=2957870`). The
branch is still worth having as a defensive arm, but its stated premise is not what this bash
produces — an `exec` failure in a forked child is a normal child exit, so the pid is known.

A first probe of mine returned **137**, not 143, because the victim carried `trap '' TERM` and was
then `SIGKILL`ed. That was a defect in the probe, not in bash; recorded because the wrong number
was momentarily believed.

Per-child rc arriving with its pid is what lets the collector map index→rc by direct observation
rather than by discipline, which is why #7554's rc-forgery channel cannot arise at this layer.

---

## Phase 0.3 — host capacity constraint mechanisms

The plan's task 0.3.1 says to measure the constrained **view**, not the exit code. Doing so
falsifies the obvious probe:

```
$ systemd-run --user --scope -p AllowedCPUs=0-3 -- nproc
16          # rc=0
$ taskset -c 0-3 nproc
4
$ taskset -c 0-1 nproc
2
```

**`AllowedCPUs=` on a `--user` scope is accepted and silently inert.** The mechanism, read from
the hierarchy rather than inferred:

```
/sys/fs/cgroup/cgroup.subtree_control                    = cpuset cpu io memory hugetlb pids rdma misc dmem
/sys/fs/cgroup/user.slice/cgroup.subtree_control         = cpu memory pids
/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/cgroup.controllers = cpu memory pids
```

`cpuset` is enabled at the root and **not delegated** below `user.slice`, so a user scope cannot
receive one. A probe asserting `rc == 0` would have reported a constraint that does not exist —
the proxy-vs-invariant substitution the plan polices elsewhere, in the plan's own probe.

Reading the scope's own cgroup (via a script FILE — passing an inline `${cg}` to `systemd-run`
lets *systemd* expand it first, which silently redirected two earlier reads to the ROOT cgroup and
returned a confident wrong answer):

| Constraint | Result |
|---|---|
| `-p MemoryMax=512M` | `memory.max=536870912` — **applies exactly** |
| `-p AllowedCPUs=0-3` | `cpuset.cpus.effective` UNREADABLE, `nproc=16` — **does not apply** |

**Plan conditional resolved, in the direction the plan did not assume.** Task 0.3.1 says *"if no
memory constraint is available, record that H2 will terminate UNKNOWN by construction."* A memory
constraint **is** available — `memory` is delegated to the user slice and `MemoryMax` lands. So H2
is testable on this host and must not be written off as UNKNOWN-by-construction.

**Mechanisms to use downstream:**

- CPU constraint → `taskset -c <range>` (measured 4 and 2).
- Memory constraint → `systemd-run --user --scope -p MemoryMax=<N>` (measured exact).
- NOT `AllowedCPUs=` on a user scope.

---

## Phase 0.4 / 0.4a — serial baseline and the Amdahl go/no-go

Pending. See `## Status` below.

## Status

| Task | State |
|---|---|
| 0.1.1 / 0.1.2 / 0.1.3 | Done — committed |
| 0.2.1 | Done — recorded above |
| 0.3.1 | Done — recorded above |
| 0.4.1 / 0.4.2 / 0.4a GATE | Not started — requires an uncontended serial baseline run |
| 0.5.1 / 0.5.2 GATE | Not started |
