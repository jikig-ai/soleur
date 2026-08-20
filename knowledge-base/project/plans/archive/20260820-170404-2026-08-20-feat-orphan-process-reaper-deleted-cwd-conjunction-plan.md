---
title: "test-contention: no reaper exists for orphaned suite processes, and the fd-based discriminator is falsified as stated"
date: 2026-08-20
slug: feat-orphan-process-reaper-deleted-cwd-conjunction
branch: feat-one-shot-7537-orphan-process-reaper
issue: 7537
closes: 7537
type: feat
lane: cross-domain
domain: engineering
priority: p2-medium
brand_survival_threshold: none
---

## Overview

Nothing in this repo terminates a *process* that has outlived its work. `scripts/tmpfs-guard.sh`
reclaims files and deliberately skips entries with open file descriptors, which is correct for a live
run and is exactly why an orphaned process survives it. The gap this plan closes is a suite process
whose working directory and executing script have both been unlinked out from under it, which keeps
consuming CPU and tmpfs on a shared box with its output unrecoverable by construction.

The difficulty is the discriminator, not the signal. A detached run and an orphaned one look
identical under `ps`. This plan builds a detector keyed on a narrow conjunction of deleted `/proc`
links, deliberately excluding the two signals that healthy processes on this box demonstrably
produce, and it fails toward leaving a process alive whenever the evidence is incomplete.

## Research Insights

### Premise validation (Phase 0.6)

Every reference the issue cites was re-probed rather than inherited.

| Cited | Probe | Result |
| --- | --- | --- |
| #7537 | `gh issue view 7537 --json state,closedByPullRequestsReferences` | OPEN, no closing PR. Premise holds. |
| #7429 (sibling) | same | CLOSED by PR 7538. Sibling closed; does not touch this scope. |
| #7498 (sibling) | same | OPEN. Independent; no overlap with this plan's files. |
| PR 7538 | `gh pr view 7538` | Shares `scripts/test-all.sh` with the issue body but never touches `scripts/tmpfs-guard.sh`. Citation, not collision — gate cleared in the prior session, not re-litigated here. |
| PR 7641 | `gh pr view 7641` | OPEN, draft, on this branch. Do not open another. |
| `apps/web-platform/infra/orphan-reaper.sh` | read in full | Exists on `main`. A 33-line systemd-timer reaper for stale `.orphaned-*` workspace **directories** on the prod web host, header `"Remove stale .orphaned-* workspace directories"`. Pure NAME collision. This plan's artifact must say **process** in its name and must not be conflated with it. |

ADR corpus grep for the proposed mechanism (not the issue number): `orphan|reaper|/proc/|pkill|SIGKILL` over
`knowledge-base/engineering/architecture/decisions/`. No ADR decides the orphan-process question. The nearest
neighbours are ADR-133 (test-all tmpfs contention, managed resource + advisory lock), ADR-177 / ADR-187
(runner result taxonomy — an unresolved run is not a failed one) and ADR-178 / ADR-179 (shared bash primitives
ship inside the plugin). None of them forecloses this work; ADR-133's first principle — *instrumentation ships
ahead of every fix* — directly shapes it.

### Property list and Cut list (Phase 0.6b — mechanism minimality)

Restating the ask as observable properties, then asking of each whether something already on `main` buys it.
Each answer is a grep of the **authority**, named.

| # | Property (observable outcome) | Already bought? |
| --- | --- | --- |
| P1 | A process whose cwd and executing script are both unlinked is identified. | **No.** `plugins/soleur/scripts/lib/proc.sh` `_proc_owns` explicitly *refuses* this case: `[[ "$cwd" == *' (deleted)' ]] && return 1`, rationale `"no positive proof, no signal"`. The one mechanism that could identify it is the one that structurally excludes it. |
| P2 | The `tmpfs-guard.sh` cron shape (deleted stdout, live cwd, live script) is never identified. | **Free by construction** if stdout/stderr are never consulted. |
| P3 | An `exe`-deleted process (claude self-update) is never identified on that basis. | **Free by construction** if `exe` is never consulted. |
| P4 | Any unreadable `/proc` entry leaves the process alive. | **No**, but it is a coding discipline rather than a mechanism. |
| P5 | The enumerating process never reports or signals itself, an ancestor, or a sibling fork of itself. | **Yes.** `scripts/lib/test-contention.sh` already ships `_tc_stat_field` / `_tc_ppid` / `_tc_pgrp` / `_tc_self_and_ancestors`, and `proc.sh` documents *why* pgid is the exact discriminator (its command-substitution forks share pgid but are not ancestors). Reuse, do not re-derive. |
| P6 | Own-uid only, no sudo. | **Free.** Measured: `readlink /proc/1/cwd` fails for a foreign-uid process, so P4's fail-toward-alive rule already excludes foreign processes. An explicit `stat -c %u` check is kept as a stated boundary rather than an incidental one. |
| P7 | What would be done is visible before it is done. | **Precedent exists.** `proc.sh` `list_runs`/`kill_mine` and `tmpfs-guard.sh`'s `DRY_RUN` both model it, including `proc.sh`'s fail-SAFE parse (`PROC_SH_DRY_RUN=true` must not mean "live"). |
| P8 | Findings reach the operator without SSH and without a dashboard. | **Yes.** `~/.local/state/soleur/tmpfs-guard-alarms.log` + `tmpfs-guard-last-run`, read by `.claude/hooks/session-rules-loader.sh` — the only SessionStart reader of that channel. |
| P9 | The detector runs periodically. | **Yes.** An existing `*/5` user crontab entry already drives `scripts/tmpfs-guard.sh` (recorded in `knowledge-base/project/learnings/2026-03-28-tmpfs-guard-cron-defense-in-depth.md`). Superseded at review: the trigger is now suite launch, so the property is bought by `scripts/test-all.sh` running at all. |
| P10 | A confirmed orphan's CPU is actually reclaimed, and every termination leaves durable evidence that survives the process it killed. | **No.** Added at review: the first nine properties are all about *identification*, which is why the kill-side apparatus had nothing to check itself against and grew unchecked. Naming the reaping property is what let the ledger, the two-strike file, the polls and the exit-code taxonomy be measured against a requirement — and three of the four were then cut. |

**Cut list** — removed here, not researched, not designed:

| Cut mechanism | Property it claimed | What already covers it |
| --- | --- | --- |
| A new `*/5` cron entry for the reaper | P9 (runs periodically) | The existing tmpfs-guard crontab entry. A second entry buys nothing and is a scheduling surface that is not IaC-managed. |
| A third mirror of the `/proc` stat primitives | P5 (self-exclusion) | `scripts/lib/test-contention.sh`. ADR-178 forbids a *plugin-shipped* file sourcing a repo-root library; this artifact is repo-root, so the prohibition does not reach it and a third copy is pure drift surface. |
| A `--verbose`/`--json` output mode | none in the list | Not asked for. Cut. |
| Detection wired into `tc_preamble` | P9 | Refused on measurement, not taste: `_tc_scan_procs` is measured at ~6.6 s and `test-all.sh` states that a second walk is a second **non-atomic** snapshot (its AC10 pins one-walk agreement, M9 is the mutation that breaks it). A detector there taxes every suite launch and re-opens a defect that plan closed. |

### Measurements taken this session (method named, per `hr-no-dashboard-eyeball-pull-data-yourself`)

Reproducing the issue's own probe, on the same box, `2026-08-20`:

```
total_pids=592  own_uid=222
deleted_cwd=0   deleted_exe=0   deleted_stdout_or_stderr=0
CONJUNCTION(cwd AND fd255)=0
```

The command is a `for d in /proc/[0-9]*` walk comparing `stat -c %u "$d"` against `id -u`, then `readlink` on
`cwd`, `exe`, `fd/1`, `fd/2`, `fd/255`, counting the `' (deleted)'` suffix on each. **This is evidence of
specificity in a sample that contains no orphan. It is not evidence of sensitivity, and nothing below may be
read as showing that the detector has ever fired on a real orphan.**

The negative arm is live on the box right now — two healthy processes carrying the exact shape the issue warns
about:

```
pid=1531891 comm=sh   cwd=/home/jean  fd1=/tmp/#172545 (deleted)
pid=1531892 comm=bash cwd=/home/jean  fd1=/tmp/#172545 (deleted)
```

Deleted stdout, **live** cwd. A reaper keyed on stdout kills this class.

Synthesized positive control (`cq-test-fixtures-synthesized-only`) — a bash script launched with its cwd inside
a temp tree, then both the tree and the script unlinked:

```
cwd   = [/tmp/orphanprobe.e2kIgj/work (deleted)]        rc=0
exe   = [/usr/bin/bash]                                  <- NOT deleted
fd255 = [/tmp/orphanprobe.e2kIgj/work/victim.sh (deleted)]
fd1   = [/dev/null]
```

Three facts fall out and each one constrains the design: the kernel appends `' (deleted)'` and `readlink`
still returns **rc 0**, so the return code carries no signal; `exe` is untouched, confirming it is orthogonal
rather than merely noisy; and `fd/255` exists only while bash is still bash — a process that `exec`s away
loses it entirely, which bounds what this detector can ever see.

### The false-positive vector the issue does not name (found by probe, not by reading)

A directory may legally be **named** `work (deleted)`. Measured against a perfectly healthy process sitting in
one:

```
readlink cwd = [/tmp/spoofprobe.nbdq8x/work (deleted)]
naive suffix test says deleted?: YES-FALSE-POSITIVE
inode via magic link   = 137995
inode via literal path = 137995   -> SAME inode: NOT deleted (correctly rescued)
```

and the control, a genuinely deleted cwd:

```
inode via magic link   = 138023
inode via literal path = stat: cannot stat '.../work (deleted)': No such file or directory
                          -> differs/unreadable: DELETED (correct)
```

So the discriminator is: a link is genuinely deleted **iff** `stat -c %i "<verbatim readlink output>"` fails or
returns an inode different from `stat -Lc %i /proc/<pid>/<link>`. A bare suffix match is not sufficient.

Note the polarity, because it is the reason this matters here and not in `proc.sh`: for `proc.sh` a bare suffix
match is fail-**safe** (it refuses to signal), while for a reaper the identical test is fail-**dangerous** (it
flags, and flagging leads to a kill). The same line of code is correct in one file and a defect in the other.

### Institutional learnings that bind this plan

The four guard learnings are inputs, not references. Each contributes a mechanical countermeasure that appears
in Acceptance Criteria below.

- `knowledge-base/project/learnings/2026-08-14-every-defect-was-a-guard-that-could-not-fail-and-no-instrument-found-more-than-two.md`
  — the preceding PR in this area shipped nine guards that could not be driven red. Transferable: a
  consistency check that asserts N implementations *agree* never asserts what they agree *on*; a count floor
  with slack is an attack budget; prefer a SET assertion over a COUNT; and no single instrument found more than
  two defects, so the mutation battery is necessary and not sufficient.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — a guard scored 14/14 while being `diff "$1" "$CANONICAL"`, because every RED fixture was derived from the
  canonical and the only must-PASS fixture *was* the canonical. Transferable: must-PASS fixtures have to differ
  from the canonical in spec-permitted ways. Also: never mutate inside `$( )` — a failed mutation in a subshell
  cannot fail the suite, which left 16 of 18 rows green on a fully broken harness.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — the pre-test question is *"what is the cheapest edit that breaks the property this guard NAMES while leaving
  the guard GREEN?"*. Also: measure the work performed, never the source shape.
- `knowledge-base/project/learnings/2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md`
  — mutation coverage is a property of the **axes** edited, not of the row count: N mutations of one shape are
  one mutation. Pair every "returns empty" assertion with a non-empty positive control.

Supporting:

- `knowledge-base/project/learnings/2026-08-13-the-guard-i-added-created-a-declaration-site-nothing-enforced.md`
  — a report nobody consumes is a declaration site, not a guard. The reporting path must terminate in something
  an actor actually reads.
- `knowledge-base/project/learnings/2026-08-19-the-budget-was-shorter-than-the-thing-it-was-waiting-for.md`
  — a degraded probe must carry a validity flag rather than degrading to `0`, which is indistinguishable from a
  real reading of zero.
- `knowledge-base/project/learnings/2026-03-28-tmpfs-guard-cron-defense-in-depth.md`
  — the three-layer tmpfs defense and the `*/5` schedule this plan reuses instead of adding to.
- `knowledge-base/project/learnings/2026-05-26-chromium-zombie-processes-docker-without-init.md`
  — TERM-then-escalate and the reparenting behaviour that makes an orphan look identical to a deliberate
  detached run under `ps`.

### Codebase anchors (all paths relative to this worktree)

| Path | What it contributes |
| --- | --- |
| `scripts/tmpfs-guard.sh` | The template. `set -euo pipefail`; every seam declared at the top with the note that *"a seam that is documented but unimplemented produces a test that sets it, observes no effect, and passes for the wrong reason"*; `guard_log()` writing to `logger -t tmpfs-guard` or an injected sink; `DRY_RUN` compared against `"1"`; non-blocking `flock -n` on a per-uid lockfile; alarm + heartbeat files under `~/.local/state/soleur/`. |
| `scripts/tmpfs-guard.test.sh` | The test template, and the anti-vacuity idiom: `cases` incremented **at the call site**, never inside `pass()`/`fail()`, so stubbing a verdict helper cannot move the counter with it. Fixtures synthesized under the suite's own `mktemp -d`; a fake `/proc` built from `mkdir` + `ln -sfn`. |
| `plugins/soleur/scripts/lib/proc.sh` | The signalling precedent: argv-**position** matching rather than substring, the wrapper walk, the pgid exclusion, path-free scan→signal channel, `_proc_sanitize` via `tr -c '[:print:]'`, re-verification at the signal site, and counters that separate `killed` / `would_signal` / `failed` / `refused` / `late_refused`. |
| `scripts/lib/test-contention.sh` | `_tc_stat_field` and friends — the `/proc/<pid>/stat` parser that strips through the **last** `') '` because `comm` may contain spaces and close-parens. Reused rather than mirrored. |
| `scripts/test-all.sh` | Registration. `scripts/*.test.sh` is deliberately **not** auto-globbed — *"an unregistered gate never runs"* — so a new suite needs an explicit `run_suite` line. `scripts/lib/*.test.sh` **is** globbed. |
| `scripts/lint-orphan-test-suites.sh` | Fails when a tracked `*.test.sh` is run by no runner. Producer is `git ls-files '*.test.sh'` over the whole repo. |
| `scripts/guard-vacuity-floor.test.sh` | Meta-guard that derives its population by SHAPE and constructs a mutant of every suite's anti-vacuity floor. A new suite's floor enters this population automatically — and is reported LOUDLY if its shape is unrecognised. |
| `scripts/lint-guard-contract.py` | Mechanical reject conditions for the `## Guard Contract` section: `**Property.**` and `**Assembly.**` present and non-placeholder, and `MIN_MUTATION_ROWS = 3` counted in the span following `**Mutation matrix**`. |
| `.claude/hooks/session-rules-loader.sh` | The only SessionStart reader of the tmpfs-guard alarm channel — the surfacing path this plan reuses. |

### Conventions carried in from AGENTS.md

`cq-test-fixtures-synthesized-only` (both arms are fixtures); `cq-write-failing-tests-before`;
`cq-assert-anchor-not-bare-token` (matching by argv position, not substring); `hr-observability-layer-citation`
and `hr-no-ssh-fallback-in-runbooks` (the discoverability probe is local, never SSH);
`hr-verify-repo-capability-claim-before-assert` (every "already exists / does not exist" claim above is a named
grep); `hr-when-in-a-worktree-never-read-from-bare`.

### Related issues and PRs

#7537 (this), #7429 (CLOSED by PR 7538), #7498 (OPEN), #7538 (citation not collision), #6789 and #6991
(tmpfs-guard scratch reaper and its count-shaped leak), #7545 (the lock budget shorter than the hold time),
#7525 (the self-matching `pkill` incident that produced `proc.sh`).

### Research caveat

The repo-research sub-agent returned paths rooted at the **bare** repo rather than this worktree, contrary to
`hr-when-in-a-worktree-never-read-from-bare`, and it also reported that a root-level suite could be registered
"under `scripts/lib/*.test.sh`". Both were corrected against direct measurement in this worktree: the suite
globs in `scripts/test-all.sh` do not include `scripts/*.test.sh`, and registration is an explicit `run_suite`
line. Every path in this section is worktree-relative and was re-verified here.

## Research Reconciliation — issue claims vs. codebase

| Issue claim | Reality measured here | Plan response |
| --- | --- | --- |
| "Detector keyed on deleted `cwd` plus deleted `BASH_SOURCE`/`fd 255`." | Both links do carry `' (deleted)'`, but `readlink` returns **rc 0** for them, and a directory may be literally named `x (deleted)`. A suffix test alone therefore produces false positives. | Keep the conjunction; add an **inode discriminator** as the definition of "deleted". Documented as a first-class check with its own mutation row, not as an implementation detail. |
| "Own-uid only, no sudo." | Own-uid falls out for free: `readlink` on a foreign process's `cwd` fails. | Keep an explicit `stat -c %u` gate anyway, so the boundary is stated rather than incidental — and so removing it is a mutation the suite can catch. |
| "Nothing in the repo reaps this class." | True for processes. But `plugins/soleur/scripts/lib/proc.sh` already enumerates and signals processes with a full safety apparatus, and *deliberately refuses* deleted-cwd. | Do not extend `proc.sh`. Reuse the `/proc` primitives from `scripts/lib/test-contention.sh` and mirror `proc.sh`'s verb split and counter discipline. Record the divergence as an ADR. |
| "The strict four-way conjunction returned zero hits." | Reproduced: 0 of 222 own-uid processes. | Carried forward as **specificity only**. The plan states in three places that no sensitivity evidence exists, and the first shipped posture is deliberately non-destructive. |
| "`scripts/tmpfs-guard.sh` … is file-scoped and explicitly skips entries with open fds." | Confirmed. `_build_inuse_top` marks a path in-use from any process `cwd`, any `fd`, any `map_files` entry, and `/proc/net/unix`. | Unchanged. This plan does not touch that behaviour. The only edit contemplated for that file is an added call site, and an acceptance criterion pins its existing suite green. |

## User-Brand Impact

**If this lands broken, the user experiences:** a running test suite, agent session, or editor process on their
own machine terminated mid-flight by a false positive — the concrete artifact being a `signalled pid=… cwd=…`
line in `~/.local/state/soleur/orphan-process-reaper-alarms.log` naming work that was alive.

**If this leaks, the user's data is exposed via:** no new exposure surface. The tool reads `/proc` for the
invoking uid only, sends no network traffic, and writes only to operator-local state files. Process paths are
sanitized through the `tr -c '[:print:]'` idiom before they reach any log, so a maliciously-named directory
cannot forge or overwrite audit lines in the operator's terminal.

**Brand-survival threshold:** none

- `threshold: none, reason: the change is confined to a developer-box maintenance script with no customer-facing surface, no customer data, no network egress, and no regulated-data path — the blast radius is the founder's own local processes, which is an availability risk to one machine rather than a brand-survival exposure.`

The local blast radius is nonetheless the dominant risk in this plan and is carried in Risks below, not waved
away by the threshold.

## Files to Create

| Path | Purpose |
| --- | --- |
| `scripts/orphan-process-reaper.sh` | The detector and its two verbs. Named for **processes** — see the naming note below. |
| `scripts/orphan-process-reaper.test.sh` | Behavioural arms. Every gate asserted in both directions against a synthesized `/proc`, plus real-process arms. |
| `scripts/orphan-process-reaper-mutation.test.sh` | The mutation battery: each check mutated out individually, each row proved to redden. |
| `test/fixtures/orphan-proc-dangling/` | A committed dangling-symlink procfs fixture. It is the AC30b control arm *and* the target of the `discoverability_test`, so the probe is deterministic, needs no live `/proc`, and reddens on a regression to a suffix test. |
| `knowledge-base/engineering/architecture/decisions/ADR-195-orphan-process-boundary-is-inode-verified-deleted-conjunction.md` | The decision record (ordinal provisional — see the ADR section). |

**Naming, stated so a reviewer cannot conflate the two.** `apps/web-platform/infra/orphan-reaper.sh` already
exists on `main`. It is a 33-line systemd-timer script that removes stale `.orphaned-*` workspace
**directories** on the production web host, and it has nothing to do with processes, with `/proc`, or with this
box. The new artifact carries `process` in its name for that reason, and its header must say so explicitly.

## Files to Edit

| Path | Edit |
| --- | --- |
| `scripts/test-all.sh` | (a) The preamble invocation, `timeout 10 … || true`, alongside the existing contention banners. (b) **Two** explicit `run_suite` lines — behavioural suite and mutation battery — following the idiom already used for `scripts/tmpfs-guard` and `scripts/lint-orphan-test-suites`. `scripts/*.test.sh` is not auto-globbed, so without those lines the suites gate nothing. A third, live `report` registration was considered and cut: it would be a second `/proc` walk per launch and, before exit code `10` was itself cut, would have turned the gate red the first time the detector worked. |
| `plugins/soleur/scripts/lib/proc.sh` | Comment only, at the `[[ "$cwd" == *' (deleted)' ]] && return 1` line in `_proc_owns()`. Records that the bare suffix test is falsifiable by a directory literally named `… (deleted)` — measured, `st_nlink` 2 versus 0 — that its failure direction there is fail-**closed** (a refusal, which that file's header calls the D6 shape), and that `scripts/orphan-process-reaper.sh` asks a different question (`is this inode unlinked`) rather than the same question with opposite polarity. A reciprocal comment goes in the reaper. No behaviour change. |
| `knowledge-base/project/specs/feat-one-shot-7537-orphan-process-reaper/tasks.md` | Task breakdown derived from the phases below. |

`scripts/tmpfs-guard.sh` is **no longer edited**. The first draft added a report-only call to its `main()`;
review measurement (R1a–R1c above) showed the destination erases its own messages and the call site can
suppress the heartbeat. Leaving that file untouched is now the stronger outcome — it also removes any question
about the fd-skip behaviour the issue asked to preserve.

The two deletion predicates for "is this cwd deleted" now diverge deliberately between `proc.sh` (bare suffix,
fail-closed refusal) and the reaper (device-qualified inode, fail-open-to-alive). That divergence is the thing
worth documenting; undocumented, it is a trap for whoever next tries to unify them. No issue is filed for
`proc.sh`'s suffix test: applying `wg-defer-only-after-inline-triage`, there is no concrete trigger (no such
directory has ever been observed) and it is not plausible at this scale in six months, so a tracking issue
would be phantom backlog by this repo's own rule. The in-place comment, plus the reaper's fixture that proves
the falsification, is the record.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 64 open issues; none of their
bodies contains `scripts/tmpfs-guard.sh`, `scripts/test-all.sh`, `scripts/lib/test-contention.sh`,
`plugins/soleur/scripts/lib/proc.sh`, `.claude/hooks/session-rules-loader.sh`, or `orphan-process-reaper`.

## Design

### Review revision R1 — three measured defects in the first draft

This section is retained rather than silently overwritten, because two of the three were defects in the
**issue's own specification**, not in the drafting, and a reviewer needs to see that the change was forced by
measurement.

**R1a — the anchor conjunction identifies the wrapper, not the load.** `fd/255` is bash's script descriptor.
Census on this box: **31 processes carry an `fd/255`, of which 30 are `bash` and one is `dbus-daemon`.**
Nothing else has one. Synthesizing the battery shape — a bash script that spawns a non-bash worker, with cwd
and script unlinked after launch — produced this:

```
pid 2964711  bash     cwd=/tmp/f1probe.si9KOP/work (deleted)  fd255=<none>
pid 2964718  bash     cwd=/tmp/f1probe.si9KOP/work (deleted)  fd255=.../run.sh (deleted)   <- the only match
pid 2964751  python3  cwd=/tmp/f1probe.si9KOP/work (deleted)  fd255=<EMPTY>                <- burns the CPU
                      cwd dev:inode = 50:219246  (identical for all three)
```

The conjunction the issue specifies flags exactly one process — the bash wrapper — and leaves the `python3`
child that is actually holding the cores. The issue is written about reclaiming 62 CPU-minutes; a mutation
battery's CPU lives in its children. No threshold change reaches this, because `fd/255` is structurally absent
on every non-shell process.

The fix preserves the issue's discriminator verbatim and does not add a second detector. The conjunction stays
exactly as specified and becomes the **anchor**. Once an anchor is confirmed, the reap set extends to every
own-uid process whose cwd resolves to the **same deleted `dev:inode` pair** — measured identical across all
three processes above, because children inherit cwd across `fork` and an unlinked directory keeps its inode.
That is exact set membership, not a heuristic, and no process is ever reaped without a confirmed anchor.

**R1b — `%i` alone is not a valid deletion discriminator.** Inode numbers are unique per **device**, not
globally. `/tmp` is tmpfs (`dev 50` above) and a worktree is ext4; a cross-device inode-number collision is
ordinary. Under a bare `%i` comparison a genuinely-deleted cwd can compare equal to a live directory named
`… (deleted)` on another filesystem — reintroducing the false positive the discriminator exists to close, in
the direction that kills. **Superseded by R2a:** the remedy this defect first suggested (`%d:%i` on both sides)
was itself replaced by `st_nlink == 0`, which needs no comparison at all. The defect is recorded because it is
what prompted looking again.

**R1c — the reporting channel this plan first chose erases its own messages.** Verified by reading the code,
not by argument. `scripts/tmpfs-guard.sh` `alarm_clear_if_healthy()` is:

```bash
alarm_clear_if_healthy() {
  [[ -f "$ALARM_FILE" ]] || return 0
  guard_log "alarm cleared — $TMP_ROOT healthy again"
  rm -f "$ALARM_FILE" 2>/dev/null || true
}
```

It removes the **whole file**, and `main()` calls it whenever `/tmp` usage is under the warn threshold with no
count pressure. `/tmp` occupancy is uncorrelated with orphaned processes — the motivating orphan's cwd was
already unlinked, so it occupied no `/tmp` entries at all. A healthy `/tmp` is therefore the *expected* state
when this detector fires, so an orphan report written at T is deleted at T+5min. Compounding it,
`.claude/hooks/session-rules-loader.sh` reads a single hardcoded path with `tail -1` and labels it
`[tmpfs-guard] /tmp alarm, most recent:` — so even inside the window the report is outranked by any tmpfs
alarm and mislabelled as a disk problem. The first draft's objection to report-only was that a report nobody
acts on is a declaration site; this was worse — a report nobody **receives**.

There is a second, independent defect in that placement: `scripts/tmpfs-guard.sh` runs under `set -euo
pipefail`, so a non-zero return from an added call aborts `main()` — and if placed before `heartbeat_write`,
it suppresses the only liveness signal the hook has, taking the tmpfs alarms dark along with the orphan
reports. That file's own comments record this exact incident class.

### The anchor conjunction

A pid is an **anchor** only when every one of these holds. Any one failing, and any error reading any of them,
leaves the process unflagged and alive.

| # | Gate | How |
| --- | --- | --- |
| G1 | Own uid | **`stat -Lc '%u'`** on the `/proc/<pid>` entry equals `id -u`, and the skip is counted in `skipped_foreign_uid`. The `-L` is load-bearing and gets its own assertion: measured, `stat -c '%u'` on a symlink reports the **link's** uid (1001), while `stat -Lc '%u'` reports the target's (0), so the un-dereferenced form silently classifies every foreign process as own-uid. Enforcement is still structurally redundant — `readlink` fails on a foreign process — which is exactly why the counter matters: without a field whose value differs, removing this gate has no observable and M5 is an equivalent mutant. |
| G2 | `cwd` genuinely unlinked | `stat -Lc '%h' /proc/<pid>/cwd` equals `0`. |
| G3 | `fd/255` is an unlinked **regular file at an absolute path** | `stat -Lc '%h'` equals `0`, **and** the `readlink` value is an absolute path ending `' (deleted)'`, **and** the target is a regular file. All three, because `%h == 0` alone is far broader than "the bash script is unlinked": measured on this box, a `memfd_create` file has `nlink 0` and reports as a regular file, so any process holding a memfd on fd 255 satisfies a bare link-count test with no bash, no script and no orphan — and an anchor authorizes a whole reap set. Pipes, unix sockets and eventfds are `nlink 1` and were never the risk. The two added terms are **narrowing** and fail toward alive, so neither re-opens the polarity problem R2a closed: the suffix test is dangerous only as a *sole* term. |
| G4 | Not the scanner | Not self, not an ancestor, not in the scanner's own process group. **Applies to reap-set members too — see below.** |
| G5 | Same mount namespace | `/proc/<pid>/ns/mnt` resolves equal to the scanner's own. A process in a foreign namespace is unadjudicable. |
| G6 | Older than the age floor | From `"$ORPHAN_PROC_ROOT"/<pid>/stat` starttime against **`"$ORPHAN_PROC_ROOT"/uptime`** — never a literal `/proc/uptime`. Against a fixture root, differencing a synthesized starttime from the real box uptime yields meaningless ages, makes AC8's two-direction arm impossible, and makes AC7's unreadable-uptime case unreachable. |

**G-fail — the failure default, stated as a gate because it is one.** Any unreadable `/proc` entry, failed
`stat`, unreadable `/proc/uptime`, or unresolvable namespace link leaves the process unflagged and increments
`unreadable`.

**Never consulted at all:** `exe`, `fd/1`, `fd/2`. Not "never consulted as a positive term" — never consulted.
This is stronger than the issue requires and it is deliberate, because it is what keeps P2 and P3 free *by
construction* rather than by a polarity discipline a later edit can flip.

### Review revision R2 — the discriminator, and the veto that is cut

**R2a — `st_nlink == 0` replaces both the suffix test and the device-qualified double-stat.** Measured on this
box:

```
genuinely deleted cwd                     stat -Lc '%h' /proc/<pid>/cwd    -> 0
                                          stat -Lc '%h' /proc/<pid>/fd/255 -> 0
HEALTHY process in a directory literally
  named "work (deleted)"                  stat -Lc '%h' /proc/<pid>/cwd    -> 2
                                          stat -Lc '%h' /proc/<pid>/fd/255 -> 1
ordinary healthy process (control)        stat -Lc '%h' /proc/$$/cwd       -> 21
```

Link count is the kernel's own answer to "is this inode unlinked". It is one syscall on the magic link, it
never re-resolves the reported path, and it is therefore immune to all three problems the earlier design was
built to work around: the `' (deleted)'` suffix is a string the kernel appends and a directory may legitimately
carry; a `%i` comparison is not unique across devices; and a `%d:%i` comparison needs two stats with a window
between them. All three disappear rather than being defended against.

This supersedes **R1b** (the `%d:%i` correction) — that correction was right about the defect and wrong about
the remedy, and both are recorded because the defect is what motivated looking again.

The property to hold onto, and the one the tests must pin, is *"genuinely unlinked, namespace-independently"*.
`st_nlink` is today's mechanism for it. Acceptance criteria and mutation rows below are written against the
property, so switching mechanism later does not read as weakening a guard.

**R2b — the stdout veto is cut.** An earlier draft carried a gate: *do not flag if `fd/1` resolves to a
still-existing path, a pipe, or a tty*, reasoned as a monotonically-safe negative term. Two reviewers
independently falsified it against this plan's own measurements:

- It **vetoes the plan's own positive control.** The synthesized orphan measured above has `fd1 = /dev/null`,
  a still-existing path. The veto refuses the only fixture in the plan that demonstrates sensitivity at all —
  and refuses the R1a three-process shape too, whose child inherited `>/dev/null`. The "veto applies to the
  anchor only" carve-out existed solely to repair damage the veto itself introduced.
- It **spends the free-by-construction argument.** P2 and P3 are free precisely because stdout and `exe` are
  never read. Once `fd/1` is read anywhere, that stops being a structural property.
- It defended the **only class in the plan with no measurement behind it** — a self-deleting installer still
  writing to live stdout. Every other fixture was probed on this box; that one was asserted.

Cutting it also removes the carve-out, two mutation rows, and four fixtures.

**R2c — a foreign mount namespace is unadjudicable (G5), and the reason is not the one first written.** The
original rationale — "the paths its magic links report do not exist in the scanner's namespace" — stopped being
true at R2a: `stat -L` on a magic link is resolved by the kernel against the target's own dentry and returns
the true `st_nlink` regardless of namespace, and the design no longer re-resolves reported paths at all. Left
as written, the next reader removes G5 as vacuous.

The live reason is stronger: sandboxed processes — `bwrap`, rootless containers, `unshare -m`, all of which
this repo runs own-uid, preflight Check 10 by design — routinely operate with an unlinked or namespace-private
cwd **as normal operation**, and their lifecycle belongs to their supervisor, not to this tool. G5 refuses to
adjudicate rather than guessing, the same posture `proc.sh` takes toward evidence it cannot establish.

A correction to the earlier claim that this axis "cannot be exercised by a synthesized `/proc` at all": it can.
`ns/mnt` is read as a link *string*, so a fixture crafts it to differ from the scanner's own for the negative
arm and to match for every positive one. That claim and M9/AC6 contradicted each other; the fixture wins.

### The reap set

Anchors are what the detector *identifies*; the reap set is what a confirmed anchor *authorizes*.

- A member is an own-uid process that shares the anchor's cwd **`dev:inode` pair** — compared as
  `stat -Lc '%d:%i'` on both sides, never `%i` alone — **and independently satisfies G1, G2, G3's link-count
  term, G4, G5 and G6 on its own links**. Membership restates the gates; it never inherits the anchor's verdict.
- **The device qualifier is load-bearing here even though R2a retired it from the deletedness test.** R2a
  replaced the *is-this-unlinked* comparison with `st_nlink`, which needs no comparison at all — but set
  membership is still an inode-**number** equality test, and R1b's cross-device collision applies to it
  verbatim. Measured: `/tmp` is dev 50 (tmpfs) and a worktree is dev 66307 (ext4), so a bare `%i` match across
  them is ordinary; and tmpfs hands inode numbers from a monotonic counter (three consecutive `mkdir`s
  measured 248902, 248903, 248904), so the number an own-uid process's directory receives is **steerable**.
  Without `%d`, an unrelated process can be walked into a foreign anchor's reap set while both independently
  pass every gate — restating the gates per member does not catch it, because each is genuinely unlinked.
- **G4 on members is load-bearing and its absence was a suicide bug.** An earlier draft applied G4 to anchors
  only. Run this plan's own AC29 scenario against that: `git worktree remove` on a worktree with a suite
  running inside it leaves `test-all.sh`, the reaper it spawned from the preamble, and every suite child
  sharing one unlinked cwd. Without G4 on members, the reap set is the caller's entire process tree — the
  reaper kills its own ancestors. The one concrete in-repo generator the plan names was also the one scenario
  in which it destroys the session that ran it.
- **Structural refusal.** If the scanner's own cwd inode equals a candidate set's inode, the run aborts with
  `valid=0` and reports. The scanner is inside the doomed directory and cannot adjudicate it.
- **Cardinality cap.** If a set exceeds `ORPHAN_REAPER_MAX_SET`, the whole reap is refused and reported,
  counted `refused_cap`. The default is **measured against the motivating incident before being chosen, not
  guessed**: a `git worktree remove` under a running `test-all.sh` produces a suite tree far wider than the 8
  an earlier draft proposed, so that value would have refused precisely the incident AC40 traces end to end —
  putting AC13 and AC40 in direct tension. The cap bars *automatic* action only; the full set is always
  reported, and `reap` takes an explicit override the banner names, so it is a speed bump for a human rather
  than a wall for the tool. It is also a free denial-of-reaping — any own-uid process can `fchdir` into the
  doomed inode enough times to hold a set over the cap — which is a further reason it must not be a hard wall.
- Children are signalled **before** the anchor, so a supervising parent cannot respawn them.
- The set is wider than "descendants" because ancestry is unreliable for orphans, which are reparented. What
  else can share an unlinked cwd inode, enumerated rather than waved at: an interactive shell, editor, pager,
  file watcher or language server that merely `cd`'d there; a deliberate `setsid`/`nohup` detached run in a
  worktree later removed; a process that `fchdir`'d into an inherited directory fd. The first and third are
  covered by G6's age floor only weakly. The second is the Overview's own central difficulty returning at the
  set level, and it is the reason the trigger design below reports the full set and requires an explicit
  `reap` rather than signalling anything automatically.

### Verbs

Mirroring `proc.sh`'s `list_runs` / `kill_mine` split, for the reason that file gives: the dry view is the
thing to reach for first.

- `report` — the default. Walks, classifies, prints one line per anchor and its set, plus a summary. Signals
  nothing.
- `reap` — signals `TERM`, one pid at a time, never to a process group, with no automatic escalation to
  `KILL`. Re-verifies every gate on every member immediately before its signal.

**Exit codes are `0` (walk completed) and `1` (walk structurally invalid), and nothing else.** Findings live on
the summary line, never in the exit code.

An earlier draft added `10` for "candidates found". It is cut, because no caller branches on it and one caller
is actively harmed by it: `scripts/test-all.sh`'s `suite_exit_class()` classifies `0` as `ok`, treats
`rc > 128 && rc <= 192` with a resolvable signal name as `killed`, and falls through to `failed` for everything
else — so `rc=10` classifies as **failed**. Registering a live walk as a suite would have meant that *the first
time the detector ever worked*, the full gate went red, and the cheapest remedy would have been to kill the
process or delete the line. The incentive inverts. Worse, the verdict would depend on what else happened to be
running, which is `cq-ac-must-not-depend-on-concurrent-sessions` reproduced inside the tool.

**Re-verification at the signal site** covers pid recycling *and* inode recycling, which are the same class.
Starttime is captured at scan and re-read before the signal; the member's own `st_nlink` is re-read too, and
the anchor must still be alive and still unlinked. An inode number is pinned only while something holds it, and
`/tmp` is tmpfs with fast churn, so a set membership computed at T0 is not evidence at T1.

**Pid validation is `^[1-9][0-9]*$`, never `^[0-9]+$`, with an explicit refusal of pid 1.** Measured, the
permissive form admits both `0` and `0777`. `kill -TERM 0` signals the **caller's entire process group** — for
an operator running `reap` from their own shell, that is their foreground job. Real `/proc` never produces such
entries, which is exactly why only the seam path can reach them, and the seam path is the one already treated
as dangerous. Every signal is `kill -TERM -- "$pid"`, quoted, validated at the signal site.

**The tool refuses to run as root.** Both verbs abort when `${EUID:-$(id -u)}` is 0. G1 is
`stat -Lc '%u' == id -u`, so under `sudo` "own uid" silently becomes uid 0 and the enforcement-by-accident
(`readlink` failing on a foreign process) evaporates — measured, `readlink /proc/1/cwd` fails as uid 1001 and
succeeds as root. The reap set would become *every root process with an unlinked cwd*, a populated class on a
box mid-`apt` transaction. The banner prints a `reap` command an operator may reflexively prefix with `sudo`
when it "doesn't work", so this is the realistic path. It is its own mutation axis (privilege floor), distinct
from M5's: M5 removes the uid gate, whereas here the gate is **present and passing** in the case that matters.

**The procfs root is checked by identity, not by name.** `stat -fc '%T' "$ORPHAN_PROC_ROOT"` must equal `proc`
(measured: `proc` for `/proc`, `tmpfs` for `/tmp`). A `!= /proc` string comparison refuses harmless aliases
while permitting the one dangerous case it cannot see — a procfs from a foreign **pid** namespace bind-mounted
at `/proc`, whose pids are not pids in the reaper's `kill` namespace. G5 covers `ns/mnt` and nothing covered
`ns/pid`, so a **G7** requires `ns/pid` to equal the scanner's own, and `reap` additionally requires
`$ORPHAN_PROC_ROOT/$$/stat` to exist and match the reaper's own `comm` and starttime. There is also an arm for
the seam being **unset**, which a name check did not cover.

**The injected signal sink is a file path that pids are appended to — never a command name that is executed.**
An env-var-named command inside a shipped script is an arbitrary-execution hook, and the root refusal above
exists precisely because this script can plausibly be invoked under `sudo`.

**The seam is validated non-empty, absolute, and a directory before it is assigned anywhere.**
`scripts/lib/test-contention.sh:39` binds `TC_PROC_ROOT="${TC_PROC_ROOT:-/proc}"` with `:-`, not `-`, so an
**empty-but-set** seam silently reverts the borrowed helpers to the real `/proc` while the reaper's own walk
globs `/[0-9]*` at the filesystem root. That is H4's class one layer lower, failing toward the live machine.

**The `PROC_ROOT` seam must not be able to send a real signal.** The walk is `for d in "$PROC_ROOT"/[0-9]*` and
fixtures are synthesized directories like `4242`. Real pids on this box were measured in the 2.9-million range,
but low pids are live. `reap` therefore refuses outright when `PROC_ROOT != /proc` unless an explicit signal
sink is injected, and that refusal has its own arm. `tmpfs-guard.sh`'s header states the general form of this
trap: a seam that is documented but unimplemented produces a test that passes for the wrong reason.

Dry-run parsing is fail-safe: anything other than an explicit off value means rehearsal, because `proc.sh`
already paid for the alternative (`PROC_SH_DRY_RUN=true` once performed a real kill on a rehearsal request).

### Evidence: journald, written before the signal

Every signal is preceded by a `logger -t orphan-process-reaper` record carrying timestamp, pid, starttime, uid,
sanitized cmdline, both link readings, measured age, anchor-or-member, and the gate verdict that authorized it.
If that write fails, the reap is **refused** rather than performed unrecorded.

It must precede the signal for a specific reason rather than out of general caution: after a successful kill the
`/proc` entry is gone, so the evidence links can never be re-examined by anyone — and the victim class has
unrecoverable output by construction, so this is the only record that a false positive ever happened.

An earlier draft specified a bespoke append-only ledger file *in addition*. Cut: journald is already durable,
already rotated, and already cleared by no health predicate — which is the entire specification the ledger file
was given. A second file with no named reader is the "declaration site nothing enforced" shape.

**Survivors are detected by the next scan, not by polling.** An earlier draft slept through polls at ~T+5 s and
~T+30 s. A process that survives `TERM` is by construction still an anchor at the next `test-all.sh` launch, so
the periodic re-scan is free survivor detection and the plan already has it — while a ≥30 s synchronous sleep
sat on the repo's hottest path.

### Trigger surface

`scripts/test-all.sh`'s preamble runs **`report`**. Nothing invokes `reap` automatically anywhere in this plan.

This resolves a contradiction an earlier draft carried: the trigger section said `report` while AC29 described
a later run signalling. The verb is now pinned in both places.

The contention is paid at suite launch, and that is where an actor — operator or agent — is present and already
reading stderr. The banner joins the ones `scripts/lib/test-contention.sh` already prints and names the exact
`reap` command for the set it found. That is a real actor at a real decision point, which is what the earlier
alarm-file channel was not.

It also means **the first strike is a reader's judgment**, which is strictly stronger than the state file an
earlier draft proposed. That two-strike file is cut: it re-implemented in state what the verb split already
guarantees, it had no specified path, no pruning rule, and no corruption semantics, and — because the preamble
runs *before* `tc_acquire` — concurrent worktrees would each have raced it anyway.

**The exclusion process group is passed in explicitly, not inferred.** `timeout` runs its child in its own
process group, so `_tc_pgrp` at the call site would return `timeout`'s pid rather than the suite's, and the
suite's own command-substitution forks — precisely the class `proc.sh` documents pgid as the discriminator for
— would not be excluded. The ancestor walk rescues the common case but not a reparented sibling fork. The
caller therefore sets `ORPHAN_REAPER_EXCLUDE_PGID` (or invokes `timeout --foreground`), and an arm on the
preamble path asserts the computed exclusion pgid equals the caller's. The behavioural suite structurally
cannot see this — it pins `TC_SELF_PID` against a synthesized procfs, so the pgid computed *at the real call
site* is never observed. That is H4's blind spot inverted: a call site that changes what self-exclusion means.

Isolation at the call site is `timeout 10 bash scripts/orphan-process-reaper.sh report || true`. The `|| true`
covers exit status; the `timeout` covers the failure modes it does not — an unresponsive NFS/FUSE/autofs mount
puts `readlink`/`stat` in uninterruptible sleep, and a command that never returns is never rescued by `|| true`.

The reaper takes its **own** non-blocking `flock` and never calls `tc_acquire`: that lock serialises whole
suites with a 3600 s budget, and a preamble probe must not queue behind one.

**Precedent diff (Phase 4.4).** `scripts/tmpfs-guard.sh` already ships the canonical form for exactly this
situation — a periodic own-uid maintenance script that must not overlap itself — and the reaper adopts it
rather than inventing a variant. Two details in it are hard-won and are the reason for the diff:

| | tmpfs-guard precedent | This plan, v1 | Adopted |
| --- | --- | --- | --- |
| Contention | logs `another … run is in flight — skipping`, then `exit 0` | "exits 0 **silently**" | The precedent. A silent skip is indistinguishable from "ran and found nothing", which is the exact confusion the `valid`/`scanned` counters exist to prevent. |
| Lockfile uncreatable | runs **unserialised** and says so | unspecified | The precedent, including its prohibition: never fall back to `exec 9>/dev/null`. That locks the `/dev/null` inode, which is shared with every process on the box, so an unrelated flocker blocks this run indefinitely and it then reports "another run is in flight", which is false. |
| Opt-out seam | `TMPFS_GUARD_NO_FLOCK` | unspecified | A matching `ORPHAN_REAPER_NO_FLOCK`, so the suite can exercise both arms. |

**Scheduled-work precedent (Phase 4.4).** The repo carries 53 Inngest cron functions under
`apps/web-platform/server/inngest/functions/cron-*`, and ADR-033 makes Inngest the canonical path for
scheduled work. It does not apply here, and the reason is worth stating so a reviewer does not read the
omission as an oversight: this tool is not scheduled work at all. It runs inside `scripts/test-all.sh` on the
developer's own box, needs no app context, no app secrets and no Sentry integration, and reads a `/proc` that
exists only on that machine. An Inngest function runs server-side on a different host entirely and could not
see the processes in question.

The cost objection that ruled out `tc_preamble` does not transfer. That objection was measured against
`_tc_scan_procs` (~6.6 s, reading `cmdline` for 592 pids). This walk **pre-filters on `fd/255` existence
first** — 31 pids box-wide as measured — and only then stats. The one-walk/one-snapshot invariant that plan
established also does not bind: it binds because two walks made an *agreement* claim about one quantity, and
this walk has a different predicate, different output, and asserts no agreement with `tc_preamble`. There is
exactly one invocation, because the separate live `report` registration is cut for the reason given above.

Two placements were considered and rejected on evidence: `scripts/tmpfs-guard.sh` `main()` (R1c — the channel
erases itself, and an errexit abort there can suppress the heartbeat), and the SessionStart hook (that file's
own stated constraint, *"a healthy machine must not tax every session's context"* — the hook reads state, it
does not generate it).

## Implementation Phases

Ordered so that every contract lands before its consumer. The suite is written before the detector, per
`cq-write-failing-tests-before` — and, more pointedly, because a mutation matrix derived from finished code
tests the code that exists rather than the property.

### Fixture strategy — measured, because the obvious one is silently wrong

The gates test `stat -Lc '%h'` on a `/proc` magic link. A synthesized `/proc` built the obvious way cannot
express the positive condition, and fails in the direction that looks like success. Measured:

```
A  fake symlink -> a nonexistent path ("/tmp/gone (deleted)")
     stat -Lc '%h'  ->  stat: cannot stat ... (rc 1)      NOT 0
B  fake symlink -> a live directory
     stat -Lc '%h'  ->  2                                  correct for a negative arm
C  fake symlink -> /proc/<pid>/fd/N, where N is an OPEN BUT UNLINKED file
     stat -Lc '%h'  ->  0                                  correct for a positive arm
```

Case A is the fixture anyone would write first, and under this plan's own G-fail rule a failed `stat` counts as
`unreadable` and the process is **not flagged**. So a suite built on dangling symlinks would report every
positive arm as passing while the detector never actually classified anything — a test that passes for the
wrong reason, which is the exact class `tmpfs-guard.sh`'s header warns about for unimplemented seams.

Therefore:

- **Anchor-positive arms use case C or a real process.** Either a real bash process whose cwd and script are
  genuinely unlinked (as the plan's own probes did), or a synthesized `/proc` whose link points at a
  `/proc/<pid>/fd/N` handle held open on an unlinked file. Case C is preferred where it works, because it is
  deterministic and needs no process lifecycle in the suite.
- **Negative and structural arms may use case B** — live targets, real nlink values — which covers
  self-exclusion, the glob guard, counters, ordering, the cardinality cap, and the `… (deleted)`-named
  directory.
- **Arms that need real process lifecycle** — signal delivery, starttime re-read, pid recycling, the
  end-to-end trace — use real helper processes. The mount- and pid-namespace gates are **not** in this
  category: both are read as link strings and are craftable in a fixture.

Per-arm realism, stated so an implementer does not have to infer it:

| Arm class | Fixture |
| --- | --- |
| Every anchor-positive (AC1, AC2, aged AC8, AC40) and the whole reap set | Real victim, or case-C handle |
| `… (deleted)`-named spoof; cross-device collision; memfd on `fd/255` | Case B / crafted, live targets |
| Unreadable, vanishing pid, missing `fd/255`, non-numeric starttime | Pure-synth |
| Mount namespace, pid namespace, foreign uid | Crafted link strings / `ln -sfn /proc/1` |
| Signal delivery, starttime re-read, pid recycling, AC40 | Real processes |

The suite asserts this discipline directly: a control arm builds a case-A fixture and requires it to classify
as `unreadable`, **not** as an anchor. Without that control, a later refactor back to dangling symlinks would
turn every positive arm green-but-vacuous with nothing to notice.

### Phase 1 — the mutation matrix and the failing suite (RED)

Write `scripts/orphan-process-reaper.test.sh` against a `/proc` synthesized under the suite's own `mktemp -d`,
in the `tmpfs-guard.test.sh` idiom (`mkdir -p "$FAKE_PROC/4242"; ln -sfn … "$FAKE_PROC/4242/cwd"`). Every gate
asserted in both directions. `cases` incremented at the call site; `pass()` / `fail()` never move it. The
accounting-conservation check and an absolute assertion floor at the bottom. Suite must fail — the script does
not exist yet.

### Phase 2 — the detector

`scripts/orphan-process-reaper.sh`: seams declared at the top and each one actually read; `set -euo pipefail`;
`_orphan_is_unlinked <pid> <link>` implementing the `st_nlink` test **once**; `_orphan_classify` as the single
classification chokepoint; one walk over `"$ORPHAN_PROC_ROOT"/[0-9]*`, pre-filtered on `fd/255` existence,
feeding both verbs.

**The seam is named `ORPHAN_PROC_ROOT`, not `PROC_ROOT`.** A bare `PROC_ROOT` is already bound by
`scripts/tmpfs-guard.sh`, and `proc.sh` records in its own header that it namespace-prefixed `PROC_SH_ROOT` for
exactly that reason. This script also sources a library carrying `TC_PROC_ROOT`, so a bare name would be the
third name for one concept inside one process — in the very place the Assembly below says copies drift apart.

**Every glob iteration is guarded.** `for d in "$ORPHAN_PROC_ROOT"/[0-9]*; do [[ -d "$d" && ! -L "$d" ]] || continue`. The `! -L` term is not decoration: measured, `[[ -d ]]` is **true** for a symlink-to-directory, and every downstream read is `stat -L`, which follows it silently — real `/proc` has no numeric symlink entries, but a fixture root or an operator-supplied root does. Bash
without `nullglob` iterates a non-matching pattern **once, literally** — measured — and `nullglob` is set in
none of the three sibling libraries. Without the guard a walk over an empty procfs reports `scanned=1`.

**Capture discipline is explicit at every `readlink` and `stat` site, and this is a P0 rather than a style
note.** Measured under `set -euo pipefail`:

```
v=$(stat -Lc '%h' /proc/999999/cwd 2>/dev/null)   -> aborts, rc=1
v=$(readlink /proc/self/fd/255 2>/dev/null)       -> aborts, rc=1
v=$(... ) || v=""                                 -> reached, rc=0
```

Both failures are *ordinary* outcomes of this walk: a pid exits between the glob and the readlink, and 561 of
592 processes have no `fd/255` at all. Under errexit the walk would die at the first one, non-deterministically.
There is no mechanical backstop either — `scripts/lint-shell-capture-exit.py`'s `NONZERO_IS_AN_ANSWER` set
covers `grep`/`rg`/`diff`/`cmp`/`pgrep`/`pidof`/`test` and does **not** include `readlink` or `stat`, so the
registered live linter cannot see this class. Every capture carries an explicit `|| rc=$?` with a decided
meaning, and an acceptance criterion pins it.

**Borrowed primitives, and the validation they require.** Sources `scripts/lib/test-contention.sh` for
`_tc_self_and_ancestors`, `_tc_pgrp` and `_tc_starttime_ticks`. Four binding conditions:

- **Set `TC_PROC_ROOT` and `TC_SELF_PID` from this script's own seams *before* sourcing.** These — not
  `TC_TMPDIR` — are the seams that govern the borrowed helpers: `_tc_self_and_ancestors()` reads both as
  globals. An earlier draft pinned `TC_TMPDIR`, which only feeds `tc_tmp_entry_count` / `tc_used_bytes` /
  `tc_avail_mb`, none of which this script calls. `scripts/test-all.sh` exports `TC_TMPDIR` and neither of the
  other two, so a suite pinning only the reaper's own procfs seam would leave self-exclusion reading the
  **real** `/proc` — making AC8 and its mutation row assert nothing, and letting a synthetic pid collide with
  a live one.
- **Validate every returned value against `^[0-9]+$` before use.** `_tc_stat_field` returns **exit 0 with
  empty output** on an unreadable stat file — measured. Empty is then arithmetic zero even under `set -u`, so
  `(( (now - "") > 600 ))` *passes* the age floor: G6 fails **open**, in the gate whose entire job is to spare
  fresh processes. The same emptiness makes starttime-based identity vacuous, since empty-at-scan equals
  empty-at-signal. A non-numeric reading is `unreadable`, never a verdict. `_tc_scan_procs` already applies
  exactly this discipline at its own call sites (`[[ "$self_pgrp" =~ ^[0-9]+$ ]] || self_pgrp=""`).
- **Only those three private readers.** No public `tc_*` verb: `tc_acquire` locks and `tc_preamble` performs
  the 6.6 s walk.
- **A `declare -F` assertion for all three names immediately after sourcing**, in both script and suite. They
  are underscore-private, so an upstream rename silently empties the exclusion set — and errexit does not
  rescue it, because `local x=$(_tc_pgrp …)` masks the substitution's status behind `local`'s own return of 0.

Signatures, stated because the plan previously assumed them: `_tc_pgrp` and `_tc_starttime_ticks` take a
**path to a stat file**, not a pid; `_tc_self_and_ancestors` takes no argument and returns a space-delimited
string with a trailing space.

Phase 1 goes green.

### Phase 3 — reap set, verbs, evidence

The cwd-inode reap-set expansion, with G2/G4/G5/G6 restated per member, the scanner-inside-the-doomed-inode
structural refusal, and the cardinality cap. `report` and `reap` with exit codes `0`/`1`. Re-verification of
starttime **and** `st_nlink` at the signal site. Children signalled before the anchor. The `PROC_ROOT != /proc`
refusal on `reap` unless a signal sink is injected. The reaper's own non-blocking `flock`, exiting 0 on
contention. The journald record written before every signal, refusing the reap if the write fails.

The counter line prints on **every** invocation with `anchors`, `set_members`, `would_signal`, `signalled`,
`failed`, `refused`, `late_refused`, `refused_cap`, `skipped_same_pgroup`, `skipped_foreign_ns`, `unreadable`,
`scanned`, `valid` and `mode` as separate fields.

`unreadable` is load-bearing and not decoration: the fail-toward-alive rule silently drops candidates, and
without a count of those drops there is no evidence distinguishing "no orphans" from "the conjunction is
unsatisfiable in production".

### Phase 4 — the mutation battery

`scripts/orphan-process-reaper-mutation.test.sh`. Each row copies the detector to a temp path, applies one
edit, runs the behavioural suite against the mutant, and asserts it **fails**. Two structural requirements,
both learned the hard way and both non-negotiable:

- The mutation is never applied inside `$( )`. A `jq`/`sed` failure inside a command substitution cannot fail
  the suite, which is how a fully broken harness once left 16 of 18 rows green.
- Every row first asserts the mutant **differs** from the original. A row whose edit matched nothing is
  vacuous and must be reported as such, not counted as a pass.

### Phase 5 — registration and wiring

Two `run_suite` lines in `scripts/test-all.sh`, each carrying the same explanatory comment shape its
neighbours use, plus the `timeout 10 … || true` preamble invocation alongside the existing contention banners.
The comment-only note in `plugins/soleur/scripts/lib/proc.sh` and its reciprocal in the reaper. Confirm
`scripts/lint-orphan-test-suites.sh` passes.

**Measure the mutation battery's wall-clock before registering it.** It runs the behavioural suite once per
row against a synthesized `/proc`, on a box this plan itself describes as contention-bound and for which a
`--capacity` gate shipped in 5cf9761a4. A battery that doubles the scripts shard is a cost the plan should
know before it lands, not after.

### Phase 6 — the decision record

Write the ADR, re-deriving its ordinal against freshly-fetched refs immediately before merge.

## Guard Contract

### Guard 1 — the orphan conjunction detector

**Property.** No process is signalled unless a confirmed **anchor** exists — own-uid, `cwd` and `fd/255` both
genuinely unlinked, same mount namespace, not the scanner or an ancestor or same-process-group, older than the
age floor — and the process is either that anchor or a set member that independently satisfies those same gates
on its own links; and no reading error, empty borrowed-primitive value, or ambiguity anywhere in that
determination can produce a signal.

Stated as *genuinely unlinked*, not as `st_nlink == 0`. The link-count test is today's mechanism for the
property; writing the mechanism into the property would make a future improvement read as weakening a guard.

**Assembly.** The chokepoint is `_orphan_classify` in `scripts/orphan-process-reaper.sh`: one guarded walk
(`for d in "$ORPHAN_PROC_ROOT"/[0-9]*; do [[ -d "$d" ]] || continue`) emits pids, every pid passes through that
single function, and both verbs consume that one walk's classified output without re-deriving a verdict. The
structural claim — not a list of today's members — is *one walk, one classifier, one unlinked-predicate, two
consumers, and one gate set applied to anchors and members alike*.

Four things follow, and they are what the matrix tests. A second classification site (a verb testing a link
itself, a "quick pre-filter" that decides rather than narrows) makes the guard narrower than the property. The
unlinked test must exist in exactly one place, `_orphan_is_unlinked` — and this repo already carries a second,
deliberately divergent predicate in `proc.sh`, so the drift is not hypothetical. The reap set must derive from
a confirmed anchor rather than compute its own predicate, since a set on its own predicate is a second detector
wearing the first one's authority. And the gate set must quantify over **members**, not just anchors: an
earlier draft applied the self-exclusion gate to anchors only, which made the plan's own AC29 scenario reap the
caller's entire process tree.

The membership that matters is the set of *sites that can reach a signal*, and the suite asserts that set has
one element rather than asserting which links are checked today.

**Mutation matrix.** Each row edits a different **axis** — several edits of one shape are one mutation.

| # | Mutation | Axis | Must redden because |
| --- | --- | --- | --- |
| M1 | Drop the `fd/255` conjunct; classify on `cwd` alone | conjunction arity | The deleted-cwd-only fixture becomes an anchor, and the conjunction the issue specifies is gone. |
| M2 | Replace the link-count test with a `*' (deleted)'` suffix match | unlinked semantics | The spoof fixture is flagged. **Its construction is not the obvious one and the row is vacuous without it:** flagging needs the conjunction, so the fixture must carry the suffix on *both* links — a real directory `work (deleted)` containing a real script named `victim.sh (deleted)`. With a normally-named script the suffix mutant fails G3, never flags, and M2 never reddens. |
| M3 | Add `exe` to the conjunction | signal selection (narrowing) | Its witness is the **canonical positive**, not the self-update fixture. Adding a conjunct can only narrow, and the self-update fixture (deleted `exe`, live `cwd`) already fails G2 both before and after — an equivalent mutant against that witness. The canonical orphan's `exe` is `/usr/bin/bash` and not deleted (measured), so the added conjunct stops it flagging. |
| M4 | Add `fd/1` as a **veto** (the polarity an implementer would actually write) | signal selection (veto) | Its witness is also the **canonical positive**, whose `fd/1` is `/dev/null` — a live path — so the veto suppresses it. The polarity must be pinned: as a *conjunct* the row reddens the same way, but against the tmpfs-guard cron witness the row is vacuous either way, because that fixture already fails G2 in the baseline. |
| M5 | Remove the own-uid gate | ownership | A foreign-uid fixture reaches classification instead of being refused. |
| M6 | Remove self/ancestor/pgid exclusion **from anchors** | self-exclusion | The scanner's own pid appears among anchors. |
| M7 | Remove self/ancestor/pgid exclusion **from set members** | self-exclusion, member scope | The AC29 fixture — scanner and its ancestors sharing the doomed inode — puts the caller's own tree in the reap set. Separate axis from M6: an earlier draft passed M6 and still contained the suicide bug. |
| M8 | Remove the scanner-inside-the-doomed-inode structural refusal | structural refusal | The fixture where the scanner's own cwd inode equals the candidate set's proceeds instead of aborting with `valid=0`. |
| M9 | Remove the mount-namespace gate | adjudicability | The foreign-namespace fixture, whose magic links resolve nowhere in the scanner's namespace, is flagged as fully orphaned. |
| M10 | Remove the age floor | recency | The two-second-old orphan fixture is flagged. |
| M11 | Accept a non-numeric `_tc_starttime_ticks` reading instead of counting it `unreadable` | borrowed-primitive validation | The unreadable-stat fixture yields an empty value, arithmetic-zero, and *passes* the age floor — the measured fail-open. |
| M12 | Invert the error default: an unreadable link counts as unlinked | fail direction | Witness pinned to **`fd/255` present, `cwd` stat fails**. A wholly-unreadable `/proc/<pid>` is rejected by the `fd/255` existence pre-filter *before* classification, so the mutant never sees it and the row would be an equivalent mutant against that fixture. |
| M13 | Drop the `[[ -d "$d" ]] || continue` glob guard, then point the walk at a pattern matching nothing | **the guard's own dispatch** | Bash iterates the literal pattern once, so the walk reports `scanned=1` over an empty procfs. This is the row an earlier draft got wrong: it asserted `scanned=0` and was therefore an equivalent mutant — the exact class the cited learnings say to hunt. |
| M14 | Make `_orphan_classify` return after its first candidate | **second member after a compliant first** | The two-orphan fixture yields one anchor; a checker that stops at the first member is an instance of the class this contract exists to catch. |
| M15 | Restrict the reap set to the anchor alone | reap-set reach | The measured three-process fixture signals one pid and the `python3` child that burns the cores survives — the R1a defect restored. |
| M16 | Derive the reap set from its own predicate instead of from a confirmed anchor | reap-set derivation | An anchorless fixture — a process in an unlinked cwd with no anchor anywhere — is signalled. |
| M17 | Let membership inherit the anchor's verdict instead of restating the gates | member predicate | Witness re-specified: a process that **shares the anchor's `dev:inode` but fails G5 (foreign namespace) or G6 (younger than the floor)** joins the set. The original witness — a live directory occupying the anchor's *released* inode — cannot exist: measured, while the anchor holds its unlinked cwd the inode is not free, and a fresh `mkdir` gets the next number (247498 held vs 247517 fresh). Recycling across a scan→signal window is M20's axis, so the original wording was also a second spelling of M20. |
| M18 | Remove the cardinality cap | blast-radius bound | The wide-set fixture (a removed worktree with many own-uid processes inside it) proceeds to signal instead of refusing and reporting. |
| M19 | Signal the anchor before its children | ordering | The supervising-parent fixture respawns a child after the anchor dies. |
| M20 | Remove starttime and `st_nlink` re-verification at the signal site | recycling | The fixture whose pid is recycled between scan and signal is signalled, and the `late_refused` arm reddens. |
| M21 | Let `reap` run with `ORPHAN_PROC_ROOT` pointed at a fixture and no injected signal sink | seam safety | The fixture directory named for a **live** pid receives a real `TERM`. A seam that is documented but unimplemented produces a test that passes for the wrong reason. |
| M22 | Remove the journald record entirely | evidence presence | The kill-then-inspect fixture leaves no record; after a successful kill the `/proc` entry is gone and the evidence is unrecoverable. |
| M23 | Let a failed evidence write proceed to the signal | evidence | The unwritable-logger fixture signals unrecorded. |
| M24 | Capture a `readlink`/`stat` without deciding its non-zero meaning | errexit discipline | The fixture containing a pid that vanishes mid-walk aborts the run, non-deterministically, instead of counting `unreadable`. |
| M25 | Drop the `unreadable` counter from the summary line | reportability | The fixture with three unreadable `/proc` entries reports the same summary as a clean walk, so a silent drop is indistinguishable from a real zero. |
| M26 | Delete the `declare -F` assertion **only** (helper left intact) | assertion presence | The assertion's own absence must redden; compounding it with a stub made M26's observable identical to M6's, so it was not independent evidence. |
| M27 | Write the journald record **after** the signal instead of before | evidence ordering | The kill-then-inspect fixture records a pid whose `/proc` entry is already gone, so the link readings are unrecoverable. Split from M22 because an `or` row is un-auditable — one branch may be equivalent and the battery cannot tell which ran. |
| M28 | Stub a borrowed `_tc_*` helper away with the assertion intact | borrowed-primitive drift | The `declare -F` assertion must be what fails, loudly, rather than the exclusion set silently emptying. |
| M29 | Remove the root refusal | privilege floor | The run-as-root fixture proceeds, and G1 **passes** because `id -u` is 0 — the gate is present and green in exactly the case that matters, which is why M5 does not cover this. |
| M30 | Drop `%d` from the set-membership comparison, leaving bare `%i` | set-membership identity | The cross-device fixture — an unrelated process on ext4 whose cwd inode *number* equals a tmpfs anchor's — joins the reap set while independently passing every gate. Distinct from M15/M16/M17, none of which touch device qualification. |
| M31 | Remove G3's regular-file and absolute-path terms, leaving bare `%h == 0` | predicate breadth | The memfd fixture — a process holding a `memfd_create` file on fd 255 with an unlinked cwd, no bash and no script — becomes an anchor and authorizes a reap set. |
| M32 | Relax pid validation to `^[0-9]+$` | operand validation | The fixture entry named `0` reaches the signal site, where `kill -TERM 0` would signal the caller's whole process group. |
| M33 | Replace the procfs identity check with a `!= /proc` name check, or drop the `ns/pid` term | namespace identity | The foreign-pid-namespace fixture bind-mounted at the expected path is accepted, and its pids are not pids in the reaper's `kill` namespace. |
| M34 | Remove the startup evidence-channel probe | evidence-channel liveness | The absent-`logger` fixture reports `evidence=ok` and the tool silently becomes report-only forever, or proceeds believing it recorded. |
| M35 | Collapse the staged drop counters back into one `unreadable` | reportability granularity | The mixed fixture cannot distinguish a foreign-uid pre-filter miss from a real masking, which on this box is a ~417-pid constant baseline swamping the signal. |
| M36 | Stop the caller emitting on non-zero rc from the preamble | caller-side detection | The abort fixture produces no line at all and `|| true` hides the status, so "the detector did not run" becomes indistinguishable from "it ran and found nothing". |

**Harness rows.** These edit the **suite**, not the system under test, because a matrix that only mutates the
system under test cannot see a vacuous harness.

| # | Harness edit | Must redden because |
| --- | --- | --- |
| H1 | Stub `fail()` to a no-op | `cases` is incremented at the call site, so it keeps moving while `fails` stops; the conservation check `pass_n + fails == cases` breaks. A floor enforced through the suspect cannot witness the suspect. |
| H2 | Neuter the battery's mutation step so the mutant is byte-identical to the original | Every row must first assert the mutant differs; a no-op edit is reported as a vacuous row, never as a pass. |
| H1b | Rewrite `fail()` to increment `pass_n` instead of `fails` | Conservation still holds (`pass_n` +1, `fails` +0, `cases` +1), the absolute floor still holds, and the suite exits 0 — so neither H1 nor the floor can see it. This is defect #7 of the 2026-08-14 learning verbatim: *"rewriting `fail()` to increment `PASS` left each fully green; an assertion-count floor cannot see it either."* The remedy that learning prescribes and an earlier draft omitted: a **positive control** that calls `pass()` and `fail()` once each and verifies both counters moved. |
| H3 | Delete the assertion-floor block | The floor is absolute and hand-ratcheted to the measured case count; its absence is a failure, not a smaller run. |
| H5 | Force the suite's final `exit` to `0` | Nothing else exercises the suite's own exit path; a suite whose success condition is `fails == 0` exits 0 on `0 passed, 0 failed`. The battery must report every row vacuous rather than green. |
| H4 | Point the suite's procfs seam at a fixture while leaving `TC_PROC_ROOT`/`TC_SELF_PID` at their real values | Self-exclusion silently reads the real `/proc`, so M6 and M7 assert nothing. A harness that leaks the real procfs into a synthetic run is the P1-1 class. |

**Must-PASS fixtures that are not the canonical.** RED rows alone cannot detect a detector that rejects
everything. Each differs from the canonical orphan in a way the contract explicitly permits, and each must
classify as **not flagged** while the detector is correct:

- Both links unlinked, own-uid, correct pgid, same namespace — but **younger than the age floor**.
- A healthy process whose `cwd` is a real directory literally named `… (deleted)` (`st_nlink` 2).
- A process with an unlinked `cwd` and **no** `fd/255`, where no anchor exists anywhere — no anchor, no set.
- The tmpfs-guard cron shape: deleted `fd/1`, live `cwd`, live `fd/255`.
- An own-uid process inside a foreign mount namespace whose links resolve nowhere here.
- A process that vanishes mid-walk: counted `unreadable_gone`, never flagged, and the walk completes.
- A memfd held on `fd/255` with an unlinked cwd — `nlink 0`, but not a script.

**Accept-direction variants — the half an earlier draft inverted.** The 2026-08-13 rule is about the *accept*
direction, and for a **detector** the accept direction is "flag it". Every fixture above is reject-direction,
so a stub that flags nothing satisfies all of them — which is exactly what the naive fixture strategy produced.
These must **flag**, each differing from the canonical in a way the contract permits:

- An anchor whose `fd/255` is a *different* unlinked script path.
- An anchor whose unlinked cwd is on **ext4** (a removed worktree) rather than tmpfs — R1b names cross-device
  semantics and nothing else tests them.
- An anchor with **zero** set members.
- An anchor exactly *at* the age-floor boundary.
- An anchor whose cmdline contains non-printable bytes, which AC23 needs anyway.

Two of these are worth naming as classes rather than cases. A wedged `git commit` from a sibling session — the
session-state doc for this branch records nine in flight at once — is spared by the live-cwd term while its
worktree exists. Once the worktree is gone it becomes a set member, and TERMing it strands `.git/index.lock`,
breaking the *other* session's next commit; that is why the trigger reports rather than reaps, why the
cardinality cap exists, and why this case has its own fixture rather than a reassuring sentence. And
`git worktree remove` on a worktree with a suite still running inside it produces the target signature exactly
— it is both the positive generator and the honest answer to "has this shape ever occurred here", which the
zero-hit census cannot supply.

## Observability

**Layer citation (`hr-observability-layer-citation`): layer 7, `cli-stdout-artifact`** — a synchronous marker
the operator reads in-session on a self-hosted machine, with no Soleur-side sink. That layer is defined by the
execution surface rather than by file location, and this is that surface exactly. Naming it correctly imports
its **durability obligation**: the synchronous marker must be paired with a durable artifact carrying the same
fields. That obligation is what the `report` path failed in an earlier draft, and it is why the journald mirror
below fires on **every** invocation rather than only before a signal.

The premise was verified rather than assumed: `vector.service` does not exist on this host and no `vector`
binary is on `PATH`; `orphan-process-reaper` is absent from the `SYSLOG_IDENTIFIER` allowlist in
`apps/web-platform/infra/vector.toml`, which governs the Hetzner prd host and could not reach this laptop
regardless; and no Sentry DSN is present. Journald here is **persistent, measured**: `/var/log/journal` exists,
`journalctl --disk-usage` reports 3 G, and `--list-boots` reaches back to 2026-05-05 across 24+ boots. That
measurement is the whole basis for cutting the bespoke ledger file, so it is recorded as a number rather than
as "journald default".

**Second surface, declared:** `scripts/test-all.sh` also runs on GitHub-hosted runners (`ci.yml` shards
`scripts`, `webplat`, `bun`) and in `main-health-monitor.yml`. The existing CI exemption guards `tc_acquire`,
not the preamble, so the call would fire there too. The reaper therefore **skips under `CI`** and says so on
one line: a runner's `/proc` cannot hold this operator's orphans, the walk would cost wall-clock on every
shard for a verdict that cannot be actionable, and the whole cost analysis in this plan is dev-box. Where that
skip line does land, it lands in **layer 6, the workflow run log** — durable, retained, readable via
`gh run view --log`, no SSH.

```yaml
liveness_signal:
  what: the `[contention] ORPHAN_SCAN` summary line, emitted on EVERY invocation of either verb — to stdout
    for the counter line, and mirrored verbatim to journald via one `logger -t orphan-process-reaper` call
  cadence: once per test-all.sh launch (skipped under CI, which itself prints one line)
  alert_target: the operator's terminal in-session; journald for the durable read
    (`journalctl -t orphan-process-reaper`, non-follow); the workflow run log on CI
  configured_in: scripts/orphan-process-reaper.sh (producer), scripts/test-all.sh preamble (caller)

error_reporting:
  destination: journald via `logger -t orphan-process-reaper`, plus the stdout counter line and stderr prose
  fail_loud: a failed evidence write refuses the reap. Stated precisely, because the verb previously exceeded
    the mechanism: `logger` confirms a successful SEND, not delivery, and journald rate-limiting can drop
    records while `logger` still exits 0. So the channel is probed once at startup and its state is reported
    as `evidence=ok|down` on the counter line — which also covers the inverse failure the earlier draft could
    not see at all, where a missing `logger` or socket silently turns the tool report-only forever.

failure_modes:
  - mode: the detector did not run, aborted mid-walk, or was killed by the call-site timeout
    detection: the CALLER emits, because the callee cannot. test-all.sh captures the rc and prints
      `[contention] ORPHAN_SCAN valid=0 reason=rc<N>` itself on any non-zero or 124. Absence of a line in a
      preamble that scrolls past hundreds of suite lines is not a signal, and `|| true` guarantees the exit
      code carries nothing — so the earlier draft's answer (an AC asserting the suite can emit the line
      against a fixture) proved the script CAN emit it, never that it DID on this run.
    alert_route: the preamble banner, plus the journald mirror
  - mode: the walk was structurally blind
    detection: `valid=0 reason=<procfs_unreadable|hidepid|scanner_in_doomed_inode|foreign_pid_ns|timeout>`.
      A bare 0|1 covered three causes with three different remedies; every other field on this line
      discriminates, and this one was the outlier.
    alert_route: banner + journald
  - mode: candidates are dropped before or during classification
    detection: split by STAGE and CAUSE, not one bucket — `prefiltered_no_fd255`, `unreadable_denied`
      (EACCES), `unreadable_gone` (ENOENT/ESRCH). Measured on this box: 592 pids, 175 own-uid, 417 foreign,
      and `/proc/<foreign>/fd` is `dr-x------ root root` — so a `[ -e .../fd/255 ]` pre-filter test on a
      foreign pid returns false, byte-identical to "has no fd/255". A single `unreadable` counter therefore
      either carries a ~417 constant baseline that swamps the signal, or is blind at the stage that drops 70%
      of the box. Split, unsatisfiability reads honestly as `prefiltered=417 own_candidates=24 anchors=0`.
      Implementation constraint, measured: bare `readlink` is silent on failure (rc 1, empty stderr), so
      obtaining a cause at all requires `readlink -v` or `stat`.
    alert_route: banner + journald
  - mode: a set is refused for exceeding the cardinality cap
    detection: `refused_cap=N`, distinct from `refused` — "too many to be plausible" and "did not qualify" are
      different facts and only one suggests the detector is wrong
    alert_route: banner + journald, naming the anchor and the set size
  - mode: TERM is sent and the process survives
    detection: the survivor is by construction still an anchor at the next launch, so the periodic re-scan
      reports it again — no polling, no synchronous sleep on the hot path
    alert_route: banner on the next run
  - mode: a false positive terminates live work
    detection: the authorizing record is written to journald BEFORE the signal, ordered verdict / pid /
      starttime / uid / links / age FIRST and the attacker-influenceable cmdline LAST and length-capped,
      because journald truncates at LineMax and the earlier field order let a long cmdline truncate the
      verdict out of the only surviving record
    alert_route: journald, which no health predicate clears
  - mode: the evidence channel itself is down or rate-limited
    detection: `evidence=ok|down`, probed once at startup
    alert_route: banner + the reap refusal

logs:
  where: journald via `logger -t orphan-process-reaper` (durable artifact); the stdout counter line and stderr
    prose in-session; the workflow run log under CI
  retention: measured on this host — persistent journal at /var/log/journal, 3 G on disk, reaching back to
    2026-05-05 across 24+ boots

discoverability_test:
  command: bash -c 'ORPHAN_PROC_ROOT=$PWD/test/fixtures/orphan-proc-dangling bash scripts/orphan-process-reaper.sh report'
  expected_output: "anchors=0 unreadable_gone=1"
  # Three deliberate choices, each closing a way the earlier probe would have failed or proved nothing.
  # (1) The counter line goes to STDOUT. preflight Check 10 runs `bash -c "$CMD" ... 2>/dev/null` and matches
  #     captured stdout, so a line on stderr — where all 14 sibling contention banners go — would have made
  #     this a deterministic FAIL for a reason unrelated to the change.
  # (2) It runs against a COMMITTED FIXTURE via the seam, not the live /proc. Check 10's sandbox degrades
  #     `--proc /proc` to no `--proc` where it cannot be established, leaving no procfs at all (the script
  #     then correctly reports valid=0 -> FAIL); and under `--unshare-all` a mounted /proc shows only the
  #     sandbox's own 2-3 pids, so the real walk is never exercised anyway. `reap` refuses a non-/proc root,
  #     so pointing `report` at a fixture is safe by construction.
  # (0) The `bash -c` wrapper is not cosmetic. probe-verb-gate.sh takes the FIRST whitespace-delimited token
  #     of the dequoted command as the verb, so a leading `VAR=value` assignment becomes the "verb" and is
  #     rejected — there is deliberately no path-shaped or assignment-shaped exemption. Verified against the
  #     gate both ways: the bare form FAILs, the wrapped form passes.
  # (3) The expectation has INFORMATION CONTENT. `mode=report` merely echoes the argv back and `valid=1` says
  #     only that the walk completed — both stay green against a detector whose conjunction never fires,
  #     which is this plan's own top stated worry. Asserting `unreadable_gone=1` against the dangling-symlink
  #     fixture AC30b already requires means the probe reddens on a regression to a suffix test.
  # (4) CORRECTED AFTER MEASUREMENT. The discriminating field is the COUNTER, not the anchor count: under a
  #     suffix regression this fixture still reports `anchors=0`, because `_orphan_cwd_key` independently
  #     re-stats the link and fails. What moves is `unreadable_gone`, measured 1 -> 0. The expectation string
  #     was right; the mechanism sentence above was not, and a probe justified by the wrong mechanism is one
  #     edit away from being "simplified" to `anchors=0`, which discriminates nothing.
  #     The path is `$PWD`-anchored because the script refuses a relative ORPHAN_PROC_ROOT — a tool that
  #     signals processes should never resolve its walk root against an ambient CWD.
```

**One correction to a mitigation rationale rather than to the mitigation.** The trigger section justifies
`timeout 10` partly by unresponsive NFS/FUSE/autofs mounts. That reasoning is wrong and is not repeated:
`timeout` sends SIGTERM (then SIGKILL with `-k`), and a task in `TASK_UNINTERRUPTIBLE` acts on neither until
the syscall returns — that is what D state means. The `timeout` is kept because it bounds every *other*
runaway, and the D-state case is recorded honestly as bounded by nothing, which is a reason not to `stat`
paths that can live on such mounts rather than a reason to trust the wrapper.

## Architecture Decision (ADR/C4)

### ADR

**ADR-195 — the orphan-process boundary is own-uid plus an inode-verified deleted conjunction, not a live-cwd
prefix.** The decision worth recording is not "add a reaper"; it is that this repo now has **two** process
ownership boundaries with opposite polarities, and a reader of `proc.sh` alone would be misled about the
system.

`plugins/soleur/scripts/lib/proc.sh` owns a process when its cwd resolves inside the current worktree, and
therefore refuses every process whose cwd is deleted — for it, a bare `' (deleted)'` suffix test is fail-safe,
because refusing means not signalling. The orphan reaper's entire target set is the set `proc.sh` refuses, so
it cannot borrow that boundary. Its boundary is own-uid plus the conjunction, and for it the identical suffix
test is fail-**dangerous**, because flagging leads to a kill. The ADR records that inversion, the inode
discriminator that resolves it, and the deliberate exclusion of `exe` and of stdout/stderr with the measured
evidence for each. Alternatives considered: extending `proc.sh` (rejected — it ships inside the plugin per
ADR-178/ADR-179 and this is a dev-box concern); wiring detection into `tc_preamble` (rejected on the measured
~6.6 s walk and the one-walk/one-snapshot invariant that plan established).

The ADR also records the **trigger surface** and the **anchor-versus-set** split, because both were forced by
measurement and both are the kind of thing a later reader would otherwise "simplify" back:

- The trigger is suite launch rather than cron, because the cron-adjacent alarm channel deletes its own
  messages on a predicate uncorrelated with what it is reporting (R1c), and because suite launch is where the
  contention is paid and an actor is present.
- The conjunction the issue specifies is an **anchor**, not the reap set, because `fd/255` is bash-only —
  measured at 30 bash plus one `dbus-daemon` box-wide — so the conjunction alone reclaims the wrapper and
  leaves the load (R1a).

This repo now carries three reaping surfaces with three different boundaries: `proc.sh` (signals,
plugin-scoped, worktree-bounded), `tmpfs-guard.sh` (deletes files, cron-scoped, own-uid, skips anything with an
open fd), and this one (signals, repo-root, own-uid, requires an unlinked cwd).

**The framing was corrected at review, and the correction matters more than the original.** An earlier draft
described the split as *two polarities of one predicate*. After the `st_nlink` change that framing dissolves:
`proc.sh` asks a **containment** question — is this cwd inside my worktree — and the reaper asks a **liveness**
question — is this inode unlinked. Those are two different tests that merely both begin by reading a magic
link. Recording them as inverted polarities would send the next reader to unify them on the wrong axis.

What all three actually triplicate is `/proc` magic-link classification: live, unlinked, unreadable, or foreign
namespace. One primitive with three callers, each applying its own policy, is the better structure and the ADR
records it as such. It is not taken now because ADR-178 forbids a plugin-shipped file sourcing a repo-root
library, so the primitive would have to live plugin-side or be vendored — a real cost. **That constraint, not
polarity, is the recorded reason for the divergence.**

The ordinal is **provisional**. Ordinals through ADR-194 are claimed across the 63 `origin/*` refs enumerated
this session; `origin/main` alone shows fewer, which is why the probe quantified over all refs rather than the
default branch. Re-derive immediately before merge, and when renumbering, sweep this plan, `tasks.md`, and
every acceptance criterion naming the ordinal in the same edit.

### C4 views

**No C4 impact**, and here is the enumeration that claim rests on rather than a bare "None". All three model
files — `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, `spec.c4` — were read, not
grepped for the feature's own noun.

- **External human actors:** none introduced. The only human in the flow is the existing `founder` actor
  ("Founder / Operator"), already modelled.
- **External systems / vendors:** none. No inbound webhook, no outbound API, no third-party store. The tool
  makes no network calls at all.
- **Containers / data stores touched:** none. The artifact is a local script writing to operator-local state
  files. The model's operator-side elements are the hook engine and `operatorSystemd` (the per-user systemd
  manager reached over the D-Bus socket); this tool touches neither — it sends signals directly with `kill`
  and creates no transient units.
- **Actor↔surface access relationships that change:** none. No sharing, ownership, or access relationship is
  added or widened.

The local maintenance surface this joins (`scripts/tmpfs-guard.sh`, `scripts/test-all.sh`, the `*/5` crontab
entry) is not modelled in C4 today, so adding a sibling to it neither introduces nor falsifies any element
description. No `view … include` line changes.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Five reviewers ran against this plan — a CTO ruling, `spec-flow-analyzer` on the operator
journey, and the DHH / Kieran / code-simplicity / architecture-strategist panel. Between them they falsified
six things the plan asserted, and every falsification was confirmed by direct measurement in this worktree
before being encoded.

What they changed, in order of severity:

- **The reap set had no self-exclusion** (architecture-strategist). Applied to anchors only, the plan's own
  AC29 generator — `git worktree remove` on a running worktree — put the scanner, its ancestors, and the whole
  suite tree in the reap set. The one concrete in-repo generator was also the one scenario in which the tool
  destroys the session that ran it. Self-exclusion now quantifies over members, with M7 on its own axis and a
  structural refusal when the scanner shares the doomed inode.
- **`st_nlink == 0` replaced the whole discriminator** (architecture-strategist). Measured: 0 for a genuinely
  deleted cwd, 2 for a healthy directory literally named `work (deleted)`. One syscall, no path re-resolution,
  namespace-independent. It obsoletes the suffix test, the `%d:%i` comparison, and the two-stat window — the
  problems M2 and M15 were built to defend against simply stop existing.
- **The stdout veto vetoed the plan's own positive control** (DHH, Kieran, code-simplicity, independently).
  The measured positive fixture has `fd1 = /dev/null` — a still-existing path — and AC29's generator is
  tty-attached. Cut, along with its scoping carve-out, two rows, and four fixtures.
- **The age floor failed open** (Kieran). `_tc_stat_field` returns exit 0 with empty output on an unreadable
  stat file; empty is arithmetic zero even under `set -u`, so `(( (now - "") > 600 ))` passes any floor.
  Verified here. Every borrowed value is now validated against `^[0-9]+$`, with M11 on that axis.
- **`set -euo pipefail` aborts on ordinary outcomes** (Kieran). A bare `stat`/`readlink` capture dies when a
  pid vanishes mid-walk or has no `fd/255` — 561 of 592 processes — and the repo's capture linter does not
  cover either command. Explicit non-zero handling is now an acceptance criterion.
- **Exit code `10` and the live `report` registration** (all four). `suite_exit_class()` classifies `10` as
  `failed`, so the first time the detector worked, the full gate would go red. Both cut.

The panel also cut the two-strike state file, the bespoke kill ledger, the post-signal polls, and the Guard 2
contract entry — roughly a third of the implementation surface — and each cut is recorded with its reason in
Alternatives. `code-simplicity` supplied the diagnosis that explains why that apparatus grew at all: the
Property list named nine identification properties and none about *reaping*, so the kill-side machinery had
nothing to check itself against. P10 was added, and three of the four mechanisms then failed it.

Two recommendations were **not** adopted as given. The CTO ruled "reap on day one"; the plan reports and
requires an explicit `reap`, because granting automatic kill authority on the repo's hottest path to a detector
that has never been observed firing inverts the risk posture the issue is written about — and DHH's point that
a reader's judgment is a stronger first gate than a state file settles it without the state file. The CTO also
proposed dropping suite registration from the risk list; registration stays as acceptance criteria rather than
as a second guard contract entry, since `lint-orphan-test-suites.sh` already owns the property and its own
header records that the `test-*.sh` convention sits outside its producer.

`spec-flow-analyzer` contributed the journey findings that survive: evidence written before the signal, the
`unreadable` counter, and the end-to-end incident trace (AC40) without which every criterion is about a gate
and none is about the incident.

### Product/UX Gate

Not applicable. The mechanical UI-surface override does not fire: no path in `## Files to Create` or `## Files
to Edit` matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any other UI-surface glob.
The semantic sweep agrees — this is a command-line maintenance tool with no user-facing surface. Product: NONE.

Other domains (Finance, Legal, Marketing, Sales, Support, Operations, Product) assessed and not relevant: the
change adds no vendor cost, no contractual or regulated-data surface, no customer-facing behaviour, and no
operational provisioning.

## Gates considered and not fired

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). There is no `spec.md` under
`knowledge-base/project/specs/feat-one-shot-7537-orphan-process-reaper/`; the directory carries only the prior
session's `session-state.md`.

Recorded rather than skipped silently, because a reviewer's first question is why they are absent.

- **GDPR / compliance (2.7):** no regulated-data surface. No schema, migration, auth flow, API route, or
  `.sql` file. No LLM or external API processing of operator data, no new cron reading the knowledge base, no
  new artifact distribution surface, and the brand-survival threshold is `none`. Does not fire.
- **Infrastructure-as-Code (2.8):** introduces no server, secret, vendor account, DNS record, TLS cert,
  firewall rule, systemd unit, or scheduling entry. The deliberate reuse of the existing `*/5` crontab entry
  is what keeps this true, and is the reason a second entry appears on the Cut list. Does not fire.
- **Encryption posture (2.11):** introduces no persistent store and no cross-component connection. No file
  matches `\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, or `docker-compose.*\.ya?ml$`. Does
  not fire.
- **Soak follow-through (2.9.1):** no acceptance criterion is time-gated. Does not fire.

## Acceptance Criteria

Every criterion below is checkable against a **synthesized** fixture (`cq-test-fixtures-synthesized-only`) or a
deterministic command. None may be flipped by an unrelated concurrent session, a sibling worktree, or ambient
machine state (`cq-ac-must-not-depend-on-concurrent-sessions`); where the live machine is unavoidably involved,
the criterion pins a shape rather than a value and says so.

### Detection — positive

1. **The orphan.** A process launched with its cwd inside a temp tree and executing a script in that tree, with
   both the tree and the script unlinked after launch, is an **anchor**. The fixture is built by the suite.
2. **The load, not the wrapper.** In the measured three-process shape — a bash wrapper with an unlinked
   `fd/255`, a second bash, and a non-bash child, all sharing one unlinked cwd inode — all three are in the
   reap set and the non-bash child is signalled **before** the anchor. This is the criterion that ties the plan
   to the 62-CPU-minute incident: a run signalling only the anchor satisfies the issue's literal conjunction
   and still leaves the cores held.

### Detection — negative

3. **The real false positive.** A process with deleted `fd/1`, live `cwd`, and live `fd/255` — the
   `scripts/tmpfs-guard.sh` cron shape — is not flagged. The fixture reproduces the *shape*; it does not name
   the pids observed at plan time, which are gone by merge.
4. **`exe`.** A process with deleted `exe` and live `cwd` is not flagged, and `exe` appears nowhere in the
   classification path — asserted by content anchor on `_orphan_classify`, not a repo-wide token grep.
5. **The measured spoof.** A healthy process whose `cwd` is a real directory literally named `… (deleted)` is
   not flagged. Measured: `st_nlink` 2 versus 0.
6. **Foreign mount namespace.** An own-uid process whose links resolve nowhere in the scanner's namespace is
   not flagged, and is counted `skipped_foreign_ns`.
7. **Fail toward alive.** For each of: unreadable `/proc/<pid>`, unreadable `cwd`, unreadable `fd/255`, absent
   `fd/255`, a pid that vanishes mid-walk, unparseable `stat`, and unreadable `/proc/uptime` — the process is
   not flagged, `unreadable` increments, and the walk completes. Seven cases, each incrementing `cases` at the
   call site.
8. **Age floor, both directions.** A process satisfying the conjunction but younger than the floor is not
   flagged; the same fixture aged past the floor is. One fixture, two directions.
9. **The measured fail-open.** With `_tc_starttime_ticks` returning empty for a fixture, the process is counted
   `unreadable` and **not** flagged. Asserted directly, because empty is arithmetic zero even under `set -u`
   and therefore passes any age floor — the gate fails open without this.
10. **Anchorless.** A process in an unlinked cwd with no anchor anywhere is never signalled.
11. **Self-exclusion, anchors and members.** The scanner never flags itself, an ancestor, or a pid sharing its
    process group — asserted separately for the anchor path and the reap-set path, because an earlier draft
    satisfied the first and still contained the suicide bug.
12. **Structural refusal.** When the scanner's own cwd inode equals a candidate set's, the run aborts with
    `valid=0` and reports, signalling nothing.
13. **Cardinality cap.** A set larger than `ORPHAN_REAPER_MAX_SET` is refused whole, counted `refused_cap`,
    and reported.
14. **Sibling-session safety.** A synthesized wedged own-uid `git commit` whose worktree still exists is not
    flagged. Once the worktree is unlinked it appears as a set member and is **reported, never signalled**, by
    the trigger design — asserted by the absence of any `signalled` line from the preamble path.

### Verbs and evidence

15. `report` signals nothing under every arm above — asserted on **one summary line** by `signalled=0`
    **together with** `would_signal>0`, plus the survival of every fixture process. The paired positive is
    load-bearing: an absence assertion alone is satisfied by renaming or dropping the field, which is the
    "pair every returns-empty assertion with a non-empty positive control" rule from 2026-08-10.
16. Exit codes, asserted against synthetic fixtures: `0` when the walk completes, whether or not anchors were
    found, and `1` only when the walk is structurally invalid. That the default exit is independent of findings
    is the point of the arm.
17. `reap` sends `TERM` only, one pid at a time, never to a process group, never escalating to `KILL` —
    asserted against a captured-signal fixture, not by reading the source.
18. `reap` re-verifies every gate, the starttime, **and** the member's own unlinked state immediately before
    each signal. Asserted by a fixture whose pid is recycled between scan and signal, which must produce
    `late_refused` and no signal.
19. **Seam safety.** `reap` refuses outright when `ORPHAN_PROC_ROOT != /proc` unless a signal sink is
    explicitly injected. Asserted with a fixture directory named for a live pid, which must receive no signal.
20. **Evidence before signal.** Every signal is preceded by a journald record carrying pid, starttime, uid,
    sanitized cmdline, both link readings, measured age, anchor-or-member, and the authorizing verdict. A
    failed evidence write refuses the reap; that refusal is asserted.
21. Dry-run parsing is fail-safe: every value other than an explicit off value yields a rehearsal. Asserted
    with at least `1`, `true`, `yes`, and an empty-but-set value.
22. The counter line prints on every invocation with `anchors`, `set_members`, `would_signal`, `signalled`,
    `failed`, `refused`, `refused_cap`, `late_refused`, `skipped_same_pgroup`, `skipped_foreign_ns`,
    `unreadable`, `scanned`, `valid`, `mode` as separate fields. A fixture with three unreadable entries
    reports `unreadable=3`, distinguishable from a clean walk.
23. Every path reaching any output is sanitized through the canonical **`LC_ALL=C tr -c '[:print:]' '?'`**
    idiom (`plugins/soleur/scripts/lib/proc.sh`). `LC_ALL=C` is load-bearing and pinned: the byte-wise pass is
    what makes `\x7f`, U+2028 and U+2029 fall out as non-printable *bytes*. Fixtures include a directory named
    with an ANSI erase sequence and one containing U+2028, so a locale regression is visible to the matrix.
    Separately — because spaces, `=` and `/` are printable and survive — attacker-influenceable values are
    emitted **last, one per line**, and every assertion on the report grammar is **prefix-anchored**
    (`^signalled `). A directory named `x signalled pid=1 cwd=/y` otherwise renders verbatim inside a report
    line, indistinguishable from a real kill record to a reader, to a `grep signalled`, and to AC15's own
    negative assertion. `cq-assert-anchor-not-bare-token` applies to this tool's own output grammar, not only
    to its argv matching.

### Robustness of the script itself

24. **Errexit discipline.** Every `readlink` and `stat` capture carries an explicit non-zero handler. Asserted
    by a fixture whose pids vanish mid-walk, which must complete rather than abort — and by a source-level
    check, because `scripts/lint-shell-capture-exit.py`'s `NONZERO_IS_AN_ANSWER` set does not include
    `readlink` or `stat`, so the registered live linter structurally cannot see this class.
25. **Glob guard.** The walk carries `[[ -d "$d" ]] || continue`. Asserted by pointing the seam at an empty
    directory and requiring `scanned=0` — without the guard bash iterates the literal pattern once and reports
    `scanned=1`.
26. **Borrowed primitives.** A `declare -F` assertion covers `_tc_self_and_ancestors`, `_tc_pgrp` and
    `_tc_starttime_ticks` immediately after sourcing, in both script and suite; every returned value is
    validated against `^[0-9]+$` before use; `TC_PROC_ROOT` and `TC_SELF_PID` are set from this script's own
    seams **before** sourcing; and no public `tc_*` verb is called anywhere.
27. **Seam honesty.** Every seam declared in the header is read by the code below it — asserted by an arm per
    seam that sets it to a fixture value and requires a named, specific behavioural difference.
28. **Lock discipline, matching the `scripts/tmpfs-guard.sh` precedent.** The reaper takes its own
    non-blocking `flock`; on contention it **logs and** exits 0, never silently. When the lockfile cannot be
    created it runs unserialised and says so, and never falls back to `exec 9>/dev/null` — that locks an inode
    shared with every process on the box. `ORPHAN_REAPER_NO_FLOCK` exercises both arms. It never calls
    `tc_acquire`. Three arms: contention, lockfile-uncreatable, and the no-flock seam.

28b. **Privilege floor.** Both verbs refuse to run when `${EUID:-$(id -u)}` is 0, asserted directly. Without
    it, G1 (`stat -Lc '%u' == id -u`) *passes* under `sudo` and the reap set becomes every root process with
    an unlinked cwd.
28c. **Procfs identity, not name.** `stat -fc '%T' "$ORPHAN_PROC_ROOT"` equals `proc`; `/proc/<pid>/ns/pid`
    equals the scanner's own (G7); `reap` additionally requires `$ORPHAN_PROC_ROOT/$$/stat` to match the
    reaper's own `comm` and starttime. Arms for: foreign pid namespace, seam **unset**, and seam empty-but-set
    (which would otherwise revert the borrowed helpers to the real `/proc` via that library's `:-` default).
28d. **Signal-operand validation.** Pid form is `^[1-9][0-9]*$`; `0`, `0777` and pid 1 are refused; every
    signal is `kill -TERM -- "$pid"`, quoted. Asserted with a fixture entry named `0`, which must never reach
    the signal site.
28e. **Sink shape.** The injected signal sink is a file path pids are appended to, never a command that is
    executed — asserted by a fixture whose sink value is a command name that must not run.
28f. **Set membership is device-qualified.** Compared as `stat -Lc '%d:%i'` on both sides. Asserted with a
    cross-device fixture whose inode *number* collides with the anchor's; it must not join the set.
28g. **Evidence-channel liveness.** `evidence=ok|down` is probed once at startup and printed on the counter
    line. With `logger` absent the tool reports `evidence=down` and refuses to reap, rather than silently
    becoming report-only or proceeding while believing it recorded.
28h. **Exclusion pgid.** On the preamble path, the computed exclusion process group equals the caller's —
    asserted at the real call site, because the synthesized-procfs suite pins `TC_SELF_PID` and structurally
    cannot observe it.
28i. **Stream discipline.** The counter line goes to **stdout** and prose to stderr, asserted by capturing the
    two streams separately. preflight Check 10 matches captured stdout with stderr discarded, so a counter
    line on stderr — where all 14 sibling contention banners go — makes the discoverability probe a
    deterministic FAIL for a reason unrelated to the change.
28j. **CI behaviour.** Under `CI` the reaper skips and prints one line saying so. `test-all.sh` runs on
    GitHub-hosted runners in three `ci.yml` shards and in `main-health-monitor.yml`, and the existing CI
    exemption guards `tc_acquire`, not the preamble.

### Anti-vacuity

29. **Mutation battery.** Every row M1–M36 and every harness row H1, H1b, H2–H5 is implemented and **demonstrated to
    redden**. Four structural requirements, each closing a named prior defect:
    - **Green baseline first.** The unmutated control runs before any row and must be GREEN; a red control
      **aborts** the battery rather than scoring rows. A red baseline makes all rows pass vacuously — the
      `fatal: not a git repository` instance in the 2026-08-14 learning — and the hybrid fixture strategy
      makes an environmental red (helper failed to start, `rmdir` raced) entirely plausible here.
    - **Placement, not just difference.** `cmp`-style "the mutant differs" proves the file changed, never
      *where*. The detector repeats the `|| rc=$?` capture idiom at every `readlink`/`stat` site, so a
      file-wide `sed` without `/g` can land M24 on a site no fixture exercises while difference still reports
      "landed". Every row scopes its edit to a line range, asserts the changed line falls inside the target
      function's span, and asserts **exactly one line changed**.
    - A row whose edit produced no change is reported vacuous and fails the battery.
    - No mutation is applied inside a command substitution.
30. **Axis distinctness is computed, not asserted.** The battery records, per mutant, the **set of failing arm
    labels** from the behavioural suite, and asserts those sets are pairwise **non-identical and non-subset**.
    Two rows that redden the same arms are one mutation wearing two names. This replaces a prose claim that
    could only be checked by re-reading the table — the shape the 2026-08-14 learning calls out — with
    something that runs, and it is what would have caught M17≈M20 and M26≈M6 without a reviewer.
30b. **Fixture realism.** Anchor-positive arms are built from a real unlinked inode — a live process with a
    genuinely unlinked cwd, or a synthesized `/proc` link pointing at a `/proc/<pid>/fd/N` handle held open on
    an unlinked file. A control arm builds the naive dangling-symlink fixture and asserts it classifies as
    `unreadable`, **not** as an anchor. Without that control a refactor back to dangling symlinks turns every
    positive arm green-but-vacuous, because a failed `stat` is `unreadable` under G-fail and reads as a pass.
31. The behavioural suite carries an **absolute** assertion floor, hand-ratcheted to the measured case count,
    written as `if [[ "$cases" -lt <N> ]]` or `if (( cases < <N> ))` so that
    `scripts/guard-vacuity-floor.test.sh`'s shape-derived population recognises it — its `floor_lines_of()`
    matches only those forms, and a floor written otherwise is not covered, not deferred, and not reported as
    unclassified, but simply absent. It also carries an accounting-conservation check
    (`pass_n + fails == cases`) with `cases` incremented at the call site only, verified non-vacuous by H1.
32. `bash scripts/guard-vacuity-floor.test.sh` passes with both new suites present.

### Integration

33. `scripts/test-all.sh` carries **two** `run_suite` lines — behavioural suite and mutation battery — each
    with an explanatory comment in the idiom of its neighbours, and `bash scripts/lint-orphan-test-suites.sh`
    reports neither as an orphan. No live `report` line is registered as a suite.
34. **Preamble.** A `test-all.sh` run emits the `ORPHAN_SCAN` summary line whether or not anything was found;
    the call is `timeout 10 … || true`; and the verb invoked is `report`. Nothing in this plan invokes `reap`
    automatically. All four asserted.
35. **Battery runtime is measured against a named ceiling** before the mutation suite is registered — not
    merely "recorded", which any number satisfies. The budget is **120 s wall-clock** for the full battery on
    an uncontended box; exceeding it requires either trimming rows or moving the battery to its own shard, and
    the measurement is quoted in the PR. 28 rows each running a suite that spawns real helper processes with
    settle waits, on a box this plan itself calls contention-bound, is exactly the cost that should be known
    before it lands.
36. `scripts/tmpfs-guard.sh` is **not modified** — `git diff --stat origin/main -- scripts/tmpfs-guard.sh` is
    empty — and `bash scripts/tmpfs-guard.test.sh` passes. Its fd-skip behaviour is untouched by construction
    rather than by care.
37. `plugins/soleur/scripts/lib/proc.sh` changes by **comment only**: the diff adds no non-comment line, and
    `bash plugins/soleur/test/proc.test.sh` passes. The comment records that the bare suffix test is falsifiable
    by a directory literally named `… (deleted)`, that its failure direction there is a refusal, and that the
    reaper asks a different question. It introduces no plan-local label into a shipped file. `proc.sh` already
    carries one such mention — `i.e. the D6 failure mode` — and the correction here is to the *reason*, not the
    instruction: an earlier draft asserted D6 was defined nowhere, which is false. It is defined in the
    archived plan that built `proc.sh`, and **also** in ADR-068 and two other plans, each time meaning
    something different. A label whose definition depends on which plan you happen to be reading is worse than
    an undefined one, so the reaper's comment names the behaviour rather than borrowing the tag.
38. `bash scripts/orphan-process-reaper.sh report` against the real `/proc` exits 0, reports `valid=1`, and
    reports `scanned` greater than zero. It deliberately asserts no finding count: a real orphan at
    verification time is ambient state. What this pins is that the walk executes against a real procfs at all —
    the class of breakage a synthesized-`/proc` suite structurally cannot see.
39. The ADR exists, and its ordinal is re-derived against freshly-fetched `origin/*` refs immediately before
    merge, with every artifact naming it swept in the same edit.

### End-to-end

40. **Incident trace.** One suite arm reproduces the 2026-08-13 shape from launch to reclamation and asserts
    each hop: `git worktree remove` on a worktree with a running multi-process suite inside it produces an
    anchor; the `test-all.sh` preamble reports it, with the set enumerated and the exact `reap` command named,
    and signals nothing; an explicit `reap` then signals the non-bash child before the anchor; a journald
    record precedes each signal; and the summary reports the set fully accounted for.

    This arm sends a **real `TERM` to a real synthesized victim** rather than an injected sink. Every other
    kill-side criterion (AC17–AC20) runs against the mock, so without this one no process ever actually dies
    in the suite — and since the plan states three times that it has no sensitivity evidence, an end-to-end
    real-signal arm is the only such evidence obtainable before shipping. Without it the plan can be fully
    satisfied while the motivating incident recurs unchanged: every other criterion is about a gate, and none
    is about the journey.

### Post-merge (operator)

None. Every criterion above is verifiable in the PR, and the change introduces no provisioning, no credential,
and no scheduling step.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| **A false positive terminates live work.** The dominant risk, and the reason the whole design is conjunctive. | Six gates, all required, applied to anchors **and** members; the link-count discriminator, which removes the false-positive vector measured at plan time rather than defending against it; the two signals known to fire on healthy processes never consulted at all; the cardinality cap; and a trigger that reports rather than reaps. |
| **The reaper reaps its own caller.** An earlier draft applied self-exclusion to anchors only, so the plan's own generator scenario — `git worktree remove` on a running worktree — put the scanner's whole process tree in the reap set. | Self-exclusion quantifies over members, with M7 on its own axis distinct from M6; plus a structural refusal when the scanner's own cwd inode is the candidate set's. Recorded rather than quietly fixed, because the near-miss is the argument for the rest of the caution. |
| **No sensitivity evidence exists.** The conjunction has never been observed firing on a real orphan; zero hits proves only specificity. | The synthesized positive arm is the only sensitivity evidence the plan claims, and it is labelled as such throughout. Nothing is reaped automatically, so the first real firing is read by a person or an agent before anything is signalled. `git worktree remove` on a live suite is a repeatable in-repo generator, which is the closest thing to field evidence available before shipping. |
| **A report nobody acts on is a declaration site, not a guard** (2026-08-13). | The banner lands in the suite's own stderr at the moment the contention is paid, alongside the existing contention banners, and names the exact `reap` command for the set it found. The earlier alarm-file channel was worse than a declaration site — R1c showed it was a report nobody *receives*. |
| **`fd/255` is bash-only, so the anchor alone reclaims nothing.** Measured: 30 bash plus one `dbus-daemon` box-wide, and the CPU-burning child has none. | The anchor authorizes a reap **set** sharing its unlinked cwd inode, with every gate restated per member. M15 reddens if the set collapses back to the anchor. A process that `exec`s away leaving no anchor anywhere is still invisible; that is stated in the header and pinned by a must-PASS fixture. |
| **The set can reach processes unrelated to the orphan.** An interactive shell, editor, pager, language server, `fchdir`'d process, or a deliberate detached run in a since-removed worktree can share the inode. A wedged `git commit` is the sharpest case: TERMing it strands `.git/index.lock` and breaks a sibling session's next commit. | Enumerated rather than waved at. Every member restates every gate; the cardinality cap converts the worst blast radius from unbounded to reportable; and nothing is signalled without an explicit `reap` invoked by someone who has seen the full set. The git case carries its own fixture. |
| **The tool runs on the repo's hottest path.** | It only ever runs `report` there. The call is `timeout 10 … || true` — `|| true` covers exit status and `timeout` covers what it does not, since an unresponsive NFS/FUSE/autofs mount puts `readlink`/`stat` in uninterruptible sleep where `|| true` never fires. It takes its own non-blocking lock and exits 0 on contention, never `tc_acquire`, whose budget is 3600 s. Survivor detection is the next scan, not a synchronous sleep. |
| **Borrowed primitives fail open.** `_tc_stat_field` returns exit 0 with empty output on an unreadable stat file, and empty is arithmetic zero even under `set -u` — so an unvalidated starttime *passes* any age floor. | Every returned value validated against `^[0-9]+$` before use, with M11 on that axis; `declare -F` on all three names; `TC_PROC_ROOT` and `TC_SELF_PID` set from this script's own seams before sourcing, with H4 catching a harness that leaks the real procfs into a synthetic run. |
| **`set -euo pipefail` aborts on ordinary outcomes.** A vanishing pid and a missing `fd/255` are normal, and both abort a bare capture — with no mechanical backstop, since the repo's capture linter does not cover `readlink` or `stat`. | Explicit non-zero handling at every capture site, pinned by AC24 and M24, plus the `[[ -d "$d" ]] || continue` glob guard. |
| **The mutation battery could pin the design in place.** 26 rows against a detector that has never fired. | Rows are written against **properties** (genuinely unlinked, namespace-independent) rather than mechanisms, so replacing `st_nlink` later is not a guard weakening. M15 pins "the set reaches the CPU-holding child", not "the set is unfiltered", so narrowing the set later does not redden a row designed to prevent narrowing. |
| **This is a hygiene tool, not a security control.** Every gate is trivially evadable by an adversarial own-uid process — `chdir("/")`, `exec` away, or hardlink the script before deleting it so `fd/255` keeps `nlink 1`. | Stated plainly here so it is never cited as a containment boundary. It is not a weakness in the design: a same-uid attacker can already signal any target directly without involving the reaper, so evasion and adversarial recycling are not escalations. What the review *did* change are the inverse cases — mechanisms whose implemented predicate was broader than their stated one (G3/memfd, bare `%i` membership, root) and blast-radius amplification (the cap). |
| **The evidence record is durable but not authentic.** Verified: `/var/log/journal` is `root:systemd-journal`, so an own-uid process cannot erase records. But `logger -t` sets a caller-supplied, unauthenticated `SYSLOG_IDENTIFIER`, and the trusted journald fields (`_UID`, `_PID`, `_COMM`) read `logger` for the genuine record too — so a forged record is indistinguishable from a real one at this privilege level. | Recorded in the ADR rather than papered over. The record is tamper-*resistant* against erasure and tamper-*evident* against nothing; authenticity would require originating it somewhere the same uid cannot impersonate, which is out of scope for a dev-box hygiene tool. |
| **ADR ordinal collision.** Ordinals moved twice in one session on a prior branch. | Provisional, probed across all `origin/*` refs rather than `origin/main`, re-derived immediately before merge with every artifact naming it swept in the same edit. |

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Extend `plugins/soleur/scripts/lib/proc.sh` with an unlinked-cwd verb | It ships inside the plugin for marketplace installs (ADR-178/ADR-179); this is a dev-box concern. It asks a *containment* question — is this cwd inside my worktree — and correctly refuses evidence it cannot establish. |
| A shared `/proc` magic-link classification primitive for all three surfaces | The genuinely better long-term shape, and recorded in the ADR as such. Not taken now: ADR-178 forbids a plugin-shipped file sourcing a repo-root library, so the primitive would have to live plugin-side or be vendored, and that cost is real. The ADR records the constraint as the reason for divergence so the next reader does not unify on the wrong axis. |
| Wire detection into `tc_preamble` | Measured: `_tc_scan_procs` costs ~6.6 s and that plan established that a second walk is a second non-atomic snapshot. |
| A dedicated `*/5` cron entry | Buys nothing an existing schedule does not, and adds a surface that is not IaC-managed. |
| Report-only from `scripts/tmpfs-guard.sh` `main()` — the first draft's choice | Refuted by reading the code. `alarm_clear_if_healthy()` removes the whole alarm file on a `/tmp`-health predicate uncorrelated with orphaned processes; the single reader renders only `tail -1` under a `[tmpfs-guard] /tmp alarm` label; and a non-zero return under that file's errexit can abort `main()` before `heartbeat_write`, taking the tmpfs alarms dark too. |
| Run the walk from the SessionStart hook | That file states its own constraint: a healthy machine must not tax every session's context. The hook reads state; it does not generate it. |
| A stdout veto term | Cut at review: it vetoes the plan's own `/dev/null` positive control and the tty-attached AC29 generator, spends the free-by-construction basis for two properties, and defends the only class in the plan with no measurement behind it. |
| A two-strike state file gating the first kill | Cut at review. It re-implemented in state what the verb split already guarantees; it had no specified path, pruning rule, or corruption semantics; a loose match would let pid `123` inherit a record for `1234`; and because the preamble runs *before* `tc_acquire`, concurrent worktrees would each have raced it. With `report` in the preamble, the first strike is a reader's judgment — strictly stronger. |
| A bespoke append-only kill ledger file | Cut at review: journald is already durable, already rotated, and cleared by no health predicate, which was the ledger's entire specification. A second file with no named reader is the declaration-site shape. |
| Post-signal polls at T+5 s and T+30 s | Cut at review: a ≥30 s synchronous sleep on the repo's hottest path, for a fact the next scan supplies free — a survivor is by construction still an anchor. |
| Exit code `10` for "candidates found", and a live `report` line registered as a suite | Cut at review. `suite_exit_class()` classifies `10` as `failed`, so the first time the detector ever worked the full gate would go red, and the cheapest remedy would be to kill the process or delete the line. The incentive inverts, and the verdict would depend on what else was running. |
| Reap automatically once a detector has fired | Not on day one, and not from the hot path. The conjunction has never been observed firing on a real orphan; granting automatic destruction to it inverts the risk posture the issue is written about. |
| Escalate to `KILL` when `TERM` does not take | Not on day one. Survivors reappear on the next scan and are reported with the escalation command, so escalating stays a recorded decision. |
