---
title: "test-contention: no reaper exists for orphaned suite processes, and the fd-based discriminator is falsified as stated"
date: 2026-08-20
slug: feat-orphan-process-reaper-deleted-cwd-conjunction
branch: feat-one-shot-7537-orphan-process-reaper
issue: 7537
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
| P9 | The detector runs periodically. | **Yes.** An existing `*/5` user crontab entry already drives `scripts/tmpfs-guard.sh` (recorded in `knowledge-base/project/learnings/2026-03-28-tmpfs-guard-cron-defense-in-depth.md`). |

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
