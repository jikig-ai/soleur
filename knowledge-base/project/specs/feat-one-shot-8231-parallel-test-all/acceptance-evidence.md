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
| `scripts/battery-tag-authorship.test.sh` › the `--enumerate-commands` root-set guard | rc **and** count |
| `plugins/soleur/test/scripts-shard-totality.test.sh` › `enumerate_leg()` | count only |
| `scripts/lint-orphan-test-suites.sh` › the `--print-suite-globs` derivation | rc **and** count — sibling stream, same prologue window |

> **Superseded 2026-09-17 (review).** An earlier revision of this table listed
> `plugins/soleur/test/fullsuite-merge-gate.test.ts:173-176` as a third consumer of the record
> stream. **It is not a consumer at all.** Verified: it imports only `bun:test`, `fs` and `path`
> and spawns no process; `--enumerate` appears in it once, as a member of `QUERY_FLAGS`, a list
> of flags to *exclude* when deciding whether a prescribed invocation runs the battery, and the
> `toBeGreaterThan(0)` counts fenced invocation lines in `ship/SKILL.md`. A zero-record
> enumerate stream could not have reddened it and never can. Two review seats found this
> independently. The claim came from the plan and was propagated without being measured — the
> exact class the rest of this document polices. The count of consumers was wrong; the fix's
> justification stands on `battery-tag-authorship` alone, which was measured exit 1 → exit 0.

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
`bash scripts/lint-orphan-test-suites.sh` → `0 orphaned`, exit 0. The covered-count tracks `main` (460 when measured, 461 after the next merge), so re-run it rather than quoting it.

### 0.1.3 Consumer fail-closed audit

Confirmed by reading each consumer, table above.

`scripts-shard-totality.test.sh` is count-only, and the REASON matters because an earlier
revision of this file got it wrong. It is **not** "the pipe eats the rc": that file sets
`pipefail`, so the runner's rc survives the pipe intact —

```
$ bash -c 'set -uo pipefail; f(){ bash -c "echo x; exit 1" | grep "^x" | cut -f1 >/dev/null; }; f; echo "fn_rc=$?"'
fn_rc=1
```

The rc is discarded at the CALL SITE: `enumerate_leg` is invoked as a bare statement whose `$?`
is never read, and `set -e` is deliberately off (the file's own comment says so). The conclusion
is unchanged; the superseded mechanism is recorded because it would have misled anyone trying to
fix it by adding `pipefail` — which is already there.

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

## Phase 0.4 / 0.4a — serial baseline and the Amdahl GATE

**Run.** `TEST_TIMING_LOG` set, detached via `setsid nohup`, working tree confirmed clean at launch
(a gate only describes the tree it was launched against). Started `2026-09-17T12:10:09Z`, finished
`12:56:37Z` — **2,788 s (46m28s)** wall clock.

Terminal marker present, `killed=0`, rc=1.

```
=== 408/435 suites passed ===
```

### 0.4a GATE — computed over the post-decline population

```
$ awk -F'\t' '$3 ~ /^skip=/ {declined++; next}
              {n++; t+=$2; if($2>m){m=$2; ml=$1}}
              END{printf "total=%d longest=%d (%s) ratio=%.2f\n", t, m, ml, t/m}' timing.tsv
```

**The row set must be reconciled against the registration set first.** An earlier revision of
this section did not do that and published three wrong numbers:

```
$ bash scripts/test-all.sh --enumerate all | awk -F'\t' '/^SUITE_REGISTRATION/{print $2}' | sort -u > /tmp/reg
$ awk -F'\t' '{print $1}' baseline-timing.tsv | sort -u | comm -13 /tmp/reg -
slowfixture   after1   after2   infrarunner   __run_boundary_start__   __run_boundary_end__
```

The timing log carried **441** distinct labels against **435** registrations. The extras are
`test-all-runtime-ceiling.test.sh`'s sandbox fixtures — its nested runners inherited the exported
`TEST_TIMING_LOG` and appended into the baseline — plus the runner's own boundary markers. (This
suite's own `run_enumerate` clears `TEST_TIMING_LOG` for precisely this reason; the hazard was
known while writing the suite and not applied when reading the baseline.)

Reconciled over the registered population only:

| Quantity | Value |
|---|---|
| registered, timed | **429** |
| registered, declined | **6** |
| **conservation** | **429 + 6 = 435 = the registration count** ✅ |
| `total_suite_ms` | **2,703,460** (45.1 min) |
| `longest_suite_ms` | **434,912** (7.2 min) — `scripts/battery-tag-authorship-mutations` |
| **ratio** | **6.22×** |
| Gate (`>= 2.0×`) | **PASS — proceed** |

> **Superseded 2026-09-17 (review).** The earlier figures were `502 rows`, `14 declined`,
> `total 2,731,532` and `ratio 6.28×`. They included 52 boundary markers and 29 fixture rows
> (28,072 ms of nested-runner time). The gate's verdict is unchanged and the decision does not
> turn on it, but the number the plan gates on was off by 1.0%.
>
> The old sanity check was also **invalid reasoning**, not merely a weaker check: it argued that
> "a significant double-count would push the sum ABOVE wall clock, and it does not". A nested
> fixture's time is *contained inside* its parent suite's elapsed time, so a contained
> double-count inflates the sum without ever approaching wall clock. It returned a false
> all-clear on contamination that was present. The conservation line above is the check that
> catches it, and it is one command.

**Against the plan's estimate.** The plan projected ~3.2× on the assumption that the longest
relevant suite is ~14.3 min. Measured, the longest is **7.2 min**, so the ceiling is roughly twice
what the plan assumed. The prize is larger than the plan's own pessimistic case, not smaller.

### The baseline's other result: the local gate was UNRUNNABLE on this host

This is not a side note; it changes what the 27 non-passing suites mean.

The Version Check on `origin/main` is a plain top-level `if` — it is **not** inside any
`_ENUMERATE` conditional. Under `set -euo pipefail`, `actual=$(bun --version)` therefore aborted
**every** invocation on this host, not only `--enumerate`. Verified by extracting main's block and
running it against the live broken shim: neither `REACHED comparison` nor `SURVIVED` is reached.

So there is no "these suites used to pass here" baseline to regress against. They were never
**reached**. The Phase 0.1 fix did not break them; it stopped the runner dying above them.

### Failure triage — 20 pre-existing failures, plus one that was mine

The run log is not committed, so 78 — the `mise ERROR` occurrence count — is the one figure here a reader cannot re-derive from the repo. The falsifiable form of the same claim: `bun --version` exits non-zero on this host, so every bun-dependent suite fails.

| Class | Example | Cause |
|---|---|---|
| bun/toolchain | `scripts/frontmatter-strip-parity` (3/12, the `parity(ts)` arms) | bun non-functional on this host |
| host-specific | `scripts/lib/scratch-root.test.sh` — `HOME fallback` and `containment` both got `/home/jean/.cache/soleur/tmp` | pre-existing, host paths |
| other pre-existing | `plugins/soleur/test/git-tripwire.test.sh` — Guard 3, 16 assertions | pre-existing, not bun-shaped |

This branch's own suite is green inside the battery:
`[ok] scripts/test-all-enumerate-toolchain (12452ms)`, 20 passed / 0 failed.

`#8112 "CI: main branch tests failing"` is already open and is the existing home for main-red work.

### CORRECTION to the triage above — one of the 21 was MINE, not pre-existing

The triage table lists `plugins/soleur/test/fixture-relative-assert.test.sh` as pre-existing. That
was **wrong**, and the error is the exact class `work/SKILL.md` names: a repo-global ratchet counts
a property across the whole tree and references no file in the diff, so no file-selected suite set
can surface it and the baseline's red simply gets swept into "pre-existing".

Measured directly instead of assumed — `git worktree add --detach origin/main` and run it there:

| Tree | Result |
|---|---|
| `origin/main` | **62 passed, 0 failed, exit 0** |
| this branch (before the fix) | 60 passed, **2 failed**, exit 1 |

The two rows were mine: `scripts/test-all-enumerate-toolchain.test.sh:155` and `:169`,
`cat > "$dir/bun"` inside the two fixture-builder functions, where `$dir` arrives as a parameter
and so is not provably absolute *at the writing window* even though `TESTROOT` was guarded where it
was bound.

A second ratchet then reddened on the repair itself. `fixture-dir-operand-assert.test.sh` asserts
every tracked copy of `assert_fixture_dir` is BYTE-IDENTICAL to the canonical one in
`plugins/soleur/test/test-helpers.sh`; my copy had "improved" the empty-operand message to mention
`rm -rf`, and that one-line difference is definition drift. `origin/main`: 71/0 exit 0. Restored to
byte-identical.

That second failure also falsifies a claim I had written into the code comment and the commit
message — that no importable canonical form exists and 32 files re-derive the helper as "a real
propagation weakness". There **is** a canonical home *and* a ratchet enforcing equality against it.
The comment has been corrected; the superseded claim is recorded here rather than silently dropped.

**Corrected counts:** 20 pre-existing failures, not 21. One (`fixture-relative-assert`) was this
branch's regression and is fixed. `fixture-dir-operand-assert` never appeared in the baseline at
all — it was introduced and resolved after the baseline ran.

Post-fix, all of these are green on this branch:

```
fixture-relative-assert       62 passed, 0 failed   exit 0
fixture-dir-operand-assert    71 passed, 0 failed   exit 0
guard-vacuity-floor           23 passed, 0 failed   exit 0
test-all-enumerate-toolchain  20 passed, 0 failed   exit 0
lint-orphan-test-suites                             exit 0
lint-shell-capture-exit       0 new findings
```

### Consequence for Phase 1 and Phase 4 — a methodology blocker the plan did not anticipate

Phase 1 diagnoses #7376 by repetition and attribution, and Phase 4's correctness gate is fault
injection. Both assume a baseline in which a RED suite is a signal. With 20 suites already red for
environment reasons, "interference reddened this suite" and "this suite was already red" are not
distinguishable by the plan's stated method, and the bun-class failures are **non-deterministic in
population** (they depend on which suites reach a bun call).

The plan assumed a green tree and does not say what to do here. Resolving this is a precondition
for Phase 1, not a step inside it.

---

## Registration +1: what it does and does not move

`--enumerate all` goes 434 → 435. No literal count assertion exists anywhere (`git grep` for
`434`/`435` across `scripts/`, `plugins/soleur/test/`, `.github/` returns only unrelated SHAs and
run ids), and the derived consumers absorb it: `scripts-shard-totality`'s `REF_N` is derived at
runtime, `battery-tag-authorship`'s `MIN_ROOTS`/`MIN_CLOSURE` are `>=` floors that move up, and
`guard-vacuity-floor`'s firing count goes 42 → 43 against a `>=` floor.

**But "nothing pins the total" was a claim about COUNTS, and it missed ORDINALS.**
`scripts/test-all.sh` › `_shard_selects` round-robins on `(_shard_ordinal - 1) % _SHARD_N`, where
the ordinal is *static source order*. Inserting a registration shifts the ordinal of every later
scripts-group suite, so leg assignment under `SCRIPTS_SHARD=k/3` changes for most of them.
Nothing fails — totality is structural, and the shard-totality guard derives rather than
restates — but `ci.yml` says in terms that any change to the registered suite set invalidates its
simulated K table, and this branch does not re-simulate it. Recorded rather than fixed: the
table's own prose is already stale against the live count independently of this change.

## Ship gate adjudication — the Incident-PIR signal gate fires, and no PIR is owed

Recorded because the gate is mandatory and fail-toward-PIR, so a dismissal has to be auditable.

`scripts/ship-incident-pir-gate.sh --pr 8241` returns **`INCIDENT-SIGNAL: yes`, exit 0**. It
requires a conjunction — a past-tense outage token AND a production token — and both are
satisfied by this PR's corpus. Neither is a production event.

**The outage conjunct is one token: `post-mortem`, at plan line 110.** It is a bibliographic
citation. The sentence is "the test-pipeline `decision-challenges.md` and the 2026-08-11
post-mortem's plan/spec have been **archived** since they were written", followed by the archive
paths to read them at. The gate's own header names this exact shape as a known false positive:
"A `post-mortem` reference to a LOCAL test-runner retrospective then demanded a PIR for an event
that never happened."

**The production conjunct is 20 standalone `live` tokens plus one `production`.** Measured:

| Token | Count | What it actually says |
|---|---|---|
| `live` (bounded both sides) | 20 | "a live defect", "the LIVE worktree", "read dir" — test-runner vocabulary |
| `production` | 1 | the heading `### Phase 0 — Preconditions (no production edit)` — asserting the opposite |
| `reproduction` | 4 | matched as `production`; see the gate defect below |

So the sole literal `production` in the corpus is a heading declaring that this phase makes no
production edit, and the gate read it as a production context.

**Verdict: no PIR.** There was no production event to report. The defect was a local-host-only
abort in a test runner: CI never saw it (it installs a RUNNABLE bun via `setup-bun`, so the
version read succeeds there — see the correction below; an earlier revision of this line gave the
opposite mechanism), nothing was deployed, nothing user-facing changed, and no release was
blocked. `scripts/ship-pir-action-items-gate.sh --branch`
returns exit 3 (no PIR in the diff), which is consistent.

### A gate defect found while adjudicating — verified, not load-bearing here, NOT fixed in this PR

`PROD_RE` guards `prod(uction)?` on the **right** only: `prod(uction)?([^a-zA-Z]|$)`. The header
documents that fix and the measured false-hit set it removed (`producer`, `produced`, `product`,
`reproduced`). It has no **left** boundary, and `reproduction` is the one inflection where taking
the optional `(uction)` group lands the right guard on a real word end:

| Word | Verdict |
|---|---|
| `producer` / `produced` / `product` / `reproduced` / `reproductions` | reject (the documented fix works) |
| `reproduction` | **MATCH** |

Four of this plan's five `production`-class hits are `reproduction`. This is the same
substring class the right-boundary fix existed to close, surviving that fix.

**It is recorded rather than fixed, and it does not change the verdict above.** Removing it
leaves the production conjunct satisfied anyway, via the 20 standalone `live` tokens — measured
both ways. Fixing it means editing a mandatory safety gate at ship time, after a six-seat review
that never saw that file, on a PR whose scope is two `test-all` files; and the gate's primary
pinning suite is `plugins/soleur/test/ship-incident-pir-gate.test.ts`, which runs under `bun` and
therefore **cannot be run on this host** — the very defect this PR fixes is why. Shipping a
one-line change to a safety gate with its main suite unrun is a worse trade than carrying the
finding.

## CORRECTION — "CI omits `setup-bun`" is false, and I inherited it from a stale code comment

> **Superseded 2026-09-17 (#8241):** every earlier statement in this document, in the PR body, in
> the learning and in `scripts/test-all.sh`'s Version Check comment that CI never saw this defect
> *because `test-scripts` omits `setup-bun`*. The conclusion holds. The mechanism was backwards.

Measured on `.github/workflows/ci.yml` at this commit:

| Probe | Result |
|---|---|
| `setup-bun` step in the `test-scripts` job | **present** — `oven-sh/setup-bun@3d26778…` |
| the job's test step name | `Run scripts-side tests (bash + python3 + bun)` |
| `git log -S'setup-bun' -- .github/workflows/ci.yml` | added by #7566 (2026-08-17), earlier by #6325 and #3672 |

So CI is bun-**bearing**. The correct mechanism is the opposite of the one published: CI installs a
bun that RUNS, `bun --version` succeeds, and the Version Check passes normally. The defect requires
a bun that resolves and cannot run — a version-manager shim — which is a developer-host shape. The
defect is still local-host-only; the reason is not the one stated.

**Where it came from, which is the part worth keeping.** I did not invent this. `scripts/test-all.sh`
already carried, on `main`, the comment *"TEST_GROUP=scripts in CI omits setup-bun by design"* —
directly above the block I was editing. It was true when written and went false when `setup-bun`
landed. I read it, believed it, and propagated it into three new artifacts and the PR body without
running the one-line probe that falsifies it.

`ci.yml` had already corrected its **own** copy of this same claim, in place and with the receipt:
*"`setup-bun` IS required (#7332). This comment previously asserted 'No `bun` in the scripts
group'."* The sweep that fixed the workflow's copy never reached the runner's copy, so the stale
sentence survived in exactly the file whose reader would most rely on it. This is the repo's
documented propagation-failure shape: the finding is not the stale comment, it is that a correction
was applied to the instance and not to the class.

All four sites are corrected in this change: the `test-all.sh` comment (pre-existing on `main`),
this document, the learning, and the PR body.

## Status

| Task | State |
|---|---|
| 0.1.1 / 0.1.2 / 0.1.3 | Done — committed |
| 0.2.1 | Done — `wait -n -p` exact; one plan claim corrected |
| 0.3.1 | Done — taskset/MemoryMax usable, AllowedCPUs inert; plan conditional resolved |
| 0.4.1 / 0.4.2 | Done — 46m28s serial baseline, timing log committed |
| **0.4a GATE** | **PASS at 6.22×** over the reconciled registered population (floor 2.0×) |
| 0.5.1 / 0.5.2 GATE | Not started — needs a `tc_acquire` caller log, not instrumented by the timing-only baseline |
| Phase 1 onward | **Precondition met 2026-09-18 (PR #8270) on 5.1 evidence.** All nine suites green alone, 0 skipped arms. AC12(b) NOT claimed — the 5.2 battery was refused (rc 4) twice for sibling contention; see the 2026-09-18 section. |

## Green-baseline precondition — measured 2026-09-18 (PR #8270, post-review)

### Host facts

| Fact | Value |
|---|---|
| OS / kernel | Linux 7.2.5-3-omarchy, 16 cores |
| Node | 26 (`vitest` 4.1.0) |
| bash | 5.3 (the `${a[@]+…}` guard targets bash 3.2, verified separately from source) |
| gitleaks | **8.24.2, runnable** — via a mise shim that now resolves |
| lefthook | not on PATH; `.git/hooks/pre-commit` reaches it via a hardcoded `/tmp` fallback |
| absent | `shellcheck`, `/usr/bin/time`, `bc` |

### 5.1 — each suite alone, re-derived AFTER the rebase and AFTER the review fixes

All nine exit 0, **with zero skipped arms**. Both facts matter: the skip contract
is exercised and the arms it protects actually ran.

| Suite | rc | Result |
|---|---|---|
| `.claude/hooks/guardrails.test.sh` | 0 | 127 pass / 0 fail |
| `.claude/hooks/git-commit-secret-scan.test.sh` | 0 | 18 pass / 0 fail / 0 skipped |
| `scripts/lint-legal-scope-block-placement.test.sh` | 0 | 71 pass / 0 fail |
| `scripts/lib/scratch-root.test.sh` | 0 | all pass |
| `plugins/soleur/test/gitleaks-rules.test.sh` | 0 | 44/44, 0 skipped |
| `plugins/soleur/test/gitleaks-merge-commit.test.sh` | 0 | 27/27, 0 skipped |
| `plugins/soleur/test/notice-frontmatter.test.sh` | 0 | all executed pass (2 skipped, unrelated to gitleaks) |
| `plugins/soleur/skills/code-to-prd/test/code-to-prd.test.sh` | 0 | 43 pass / 0 fail / 0 skipped |
| `apps/web-platform/infra/registry-userdata-budget.test.sh` | 0 | 16 checks / 0 failed |

Plus `apps/web-platform` `kb-share-preview.test.ts` on Node 26: 25/25 (FR3/#8261).

**Supersedes an earlier record of "20 declared skipped arms."** That measurement
was taken when gitleaks was not runnable on this host. It is now pinned at 8.24.2,
so every arm executes and the skip list is empty. Recording the stale figure would
have asserted coverage this run did not have — in the direction that reads as
*less* coverage, which is why it was worth re-deriving rather than transcribing.

The ADR-188 contract was verified in BOTH directions for all three skip-arm suites:
with a PATH lacking gitleaks they skip and exit 0 locally, and under `CI=true` the
same absence exits 1 naming the arms.

### 5.2 — full serial battery: REFUSED (rc 4), twice

| Attempt | Outcome |
|---|---|
| 1 (12:20Z) | `rc=4` — `CAPACITY_CONTENDED reason=sibling_runs measured_runs=1`; sibling worktree `feat-one-shot-7960-phase-b-delivery-field` running 870s |
| 2 (10:54Z, queued behind attempt 1's sibling) | `rc=4` — the sibling started a NEW full-gate run 6s earlier; this session's own suite sweep was also in flight |

A third attempt is queued behind a 60-second all-quiet requirement (90m cap). The
refusal is the runner working as designed (#7553), not a failure of this change.

Per plan §5.2 this is the sanctioned outcome: *"If the run is refused (rc 4), wait
at most 2 h, then record the refusal and ship on 5.1 alone."* **AC12(b) is
therefore NOT claimed.** AC12(a) is claimed, on the table above.

The host was never quiet during this session because a sibling worktree ran
back-to-back full gates throughout — which is itself evidence for #8231's premise
that serial full-gate runs are the contended resource.

### Repo-global ratchets (the blind spot a file-selected run cannot see)

Re-run after the review fixes, all clean: `guard-vacuity-floor` 23/0,
`lint-orphan-test-suites` 465 covered / 0 orphaned, `lint-guard-contract` rc 0,
`lint-window-closure-assertion` rc 0, `lint-shell-capture-exit` 0 new findings
(one NEW finding introduced by a review fix was fixed at source, not re-baselined).

`shellcheck` is **not installed on this host** — that instrument did not pass, it
did not run.
