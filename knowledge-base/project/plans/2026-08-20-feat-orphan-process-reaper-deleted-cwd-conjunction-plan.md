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
| `knowledge-base/engineering/architecture/decisions/ADR-195-orphan-process-boundary-is-inode-verified-deleted-conjunction.md` | The decision record (ordinal provisional — see the ADR section). |

**Naming, stated so a reviewer cannot conflate the two.** `apps/web-platform/infra/orphan-reaper.sh` already
exists on `main`. It is a 33-line systemd-timer script that removes stale `.orphaned-*` workspace
**directories** on the production web host, and it has nothing to do with processes, with `/proc`, or with this
box. The new artifact carries `process` in its name for that reason, and its header must say so explicitly.

## Files to Edit

| Path | Edit |
| --- | --- |
| `scripts/test-all.sh` | (a) The preamble invocation, `|| true`, alongside the existing contention banners. (b) Three explicit `run_suite` lines — behavioural suite, mutation battery, and a live `report` line — following the idiom already used for `scripts/tmpfs-guard` and `scripts/lint-orphan-test-suites`. `scripts/*.test.sh` is not auto-globbed, so without those lines the suites gate nothing. |
| `plugins/soleur/scripts/lib/proc.sh` | Comment only, at the `[[ "$cwd" == *' (deleted)' ]] && return 1` line in `_proc_owns()`. Records that the bare suffix test is falsifiable by a directory literally named `… (deleted)`, that its failure direction there is fail-**closed** (a refusal, which that file's header calls the D6 shape), and that `scripts/orphan-process-reaper.sh` carries a device-qualified inode discriminator because its direction inverts. A reciprocal comment goes in the reaper. No behaviour change. |
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
the direction that kills. Every comparison uses `stat -Lc '%d:%i'` against `stat -c '%d:%i'`.

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
| G1 | Own uid | `stat -c %u /proc/<pid>` equals `id -u`. Read for **reporting**; enforcement remains the fact that `readlink` fails on a foreign process. Both, because a check that cannot report what it skipped is indistinguishable from one that passed. |
| G2 | `cwd` deleted, device-qualified | `readlink /proc/<pid>/cwd` ends in `' (deleted)'` **and** `stat -c '%d:%i' "<verbatim value>"` either fails or differs from `stat -Lc '%d:%i' /proc/<pid>/cwd`. |
| G3 | `fd/255` deleted, device-qualified | The same two-part test against `/proc/<pid>/fd/255`. |
| G4 | Not the scanner | Not self, not an ancestor, not in the scanner's own process group. |
| G5 | Older than the age floor | Default 600 s, from `/proc/<pid>/stat` starttime against `/proc/uptime`. The uptime reading must be `> 0` before the age term is evaluated at all — a zero uptime yields a negative elapsed, which is fail-safe only by accident under a naive comparison. |
| G6 | **Veto:** stdout is not live | Do **not** flag if `fd/1` resolves to a still-existing path, a pipe, or a tty. |

G6 deserves its own note, because it is the one place this plan uses stdout at all. The issue bans stdout as a
**positive** term, and rightly — that is the signal that would kill this repo's own `tmpfs-guard.sh` cron
instance. It says nothing about stdout as a **negative** term. A veto can only reduce sensitivity and can never
introduce a false positive, so it is strictly safe to add, and it closes the one residual shape the conjunction
does not otherwise exclude: a self-deleting process that unlinks its scratch and its script, keeps working, and
writes to a live stdout (some installers and wheel builds do exactly this). It costs nothing against the target,
whose output the issue describes as unrecoverable by construction.

**Never consulted as a positive term:** `exe`, `fd/1`, `fd/2`. These are the two signals this box demonstrably
produces on healthy processes, and consulting either as a positive is a mutation the suite must redden on.

### The reap set

Anchors are what the detector *identifies*; the reap set is what a confirmed anchor *authorizes*.

- The reap set is every own-uid process whose `cwd` resolves to the same deleted `dev:inode` pair as a
  confirmed anchor, plus the anchor itself.
- G6's veto applies to the **anchor only**. Applying it to the set would spare the very children the set exists
  to reach: in the probe above the `python3` child inherited `>/dev/null`, a still-existing path, so a
  set-wide veto would defeat the fix.
- Children are signalled **before** the anchor, so a supervising parent cannot respawn them.
- The set is deliberately wider than "descendants of the anchor": ancestry is unreliable for orphans, which are
  reparented. Two unrelated own-uid processes sharing one deleted cwd inode are both in a deleted cwd and are
  both reaped. That widening is stated here rather than discovered later, and it carries its own fixture.

### Verbs and the two-strike rule

Mirroring `proc.sh`'s `list_runs` / `kill_mine` split, for the reason that file gives: the dry view is the
thing to reach for first.

- `report` — the default. Walks, classifies, prints one line per anchor and its set, plus a summary. Signals
  nothing.
- `reap` — signals `TERM`, one pid at a time, never to a process group, with no automatic escalation to
  `KILL`.

**Exit codes.** `0` the walk completed, `1` the walk was structurally invalid. Findings are reported on the
summary line, **not** in the default exit code; `report --strict` additionally exits `10` when any anchor was
found, for a caller that wants to branch on it.

That split is deliberate and was not the first draft. Making "found something" the default non-zero exit
couples the health of any caller to **ambient machine state**: the live registration line in `test-all.sh`
would turn the whole gate red because an unrelated orphan happened to exist on the box, which is
`cq-ac-must-not-depend-on-concurrent-sessions` reproduced inside the tool rather than in an acceptance
criterion. Structural invalidity is a property of the run; a stray orphan is a property of the machine, and
only the first belongs in an exit code a suite reads.

Verified rather than reasoned: `scripts/test-all.sh`'s `suite_exit_class()` classifies `0` as `ok`, treats
`rc > 128 && rc <= 192` with a resolvable signal name as `killed`, and falls through to `failed` for
everything else — so `rc=10` classifies as **failed**, and `run_suite` captures the rc rather than testing it
(`"$@" || rc=$?`). A `report` line exiting 10 on findings would therefore have turned the full gate red
because an unrelated process existed on the box.

**The two-strike rule is how this plan resolves reap-now versus report-first**, and it is mechanical rather
than a promise to revisit. The reaper refuses to signal any anchor it has not already recorded in a previous
run. State is keyed on `pid` **plus** `/proc/<pid>/stat` starttime, so a recycled pid is a new entity and
starts over. The first sighting always reports; a later sighting reaps.

This matters because it converts the plan's central evidentiary problem into an automatic process. Zero
conjunction hits on a box containing no orphan is specificity evidence only, and nothing has ever shown this
detector firing on a real orphan. A two-strike rule means the very first real firing is observed and recorded
before anything is killed — without deferring to anyone's memory, and without a tracking issue that rots. It
also costs nothing against the motivating incident, which persisted for 62 minutes and would have been sighted
many times over.

**Pid recycling** is closed exactly rather than narrowed: starttime is captured at scan and re-read
immediately before the signal, and any change aborts that signal. `proc.sh` narrows this window with an
ownership re-check and documents that it does not close it; the starttime comparison is available here because
`scripts/lib/test-contention.sh` already ships `_tc_starttime_ticks`.

Dry-run parsing is fail-safe: anything other than an explicit off value means rehearsal, because `proc.sh`
already paid for the alternative (`PROC_SH_DRY_RUN=true` once performed a real kill on a rehearsal request).

### The kill ledger

Append-only, at `~/.local/state/soleur/orphan-process-reaper-ledger.log`, written **before** any signal and
kept lifecycle-independent of every alarm file — nothing clears it on a "healthy" predicate.

Each record carries timestamp, pid, starttime, uid, sanitized cmdline, both link values with their
deleted-state and `dev:inode` readings, measured age, anchor-or-set-member, verb, signal, and the post-signal
outcome. The reason it must precede the signal is specific and not general caution: after a successful kill the
`/proc` entry is gone, so the four evidence links can never be re-examined by anyone — and the primary victim
class has unrecoverable output by construction, so the ledger is the only record that a false positive ever
happened.

**Post-signal verification** closes the other half. TERM is not assumed to work: a mutation battery is exactly
the shape that installs cleanup traps, and a stopped process needs `CONT` before TERM is delivered at all. The
reaper polls at roughly T+5 s and T+30 s, records the outcome per pid, and reports survivors explicitly with
the escalation command rather than exiting 0 in silence.

### Trigger surface

`scripts/test-all.sh`'s preamble path, not cron.

The contention is paid at suite launch, and that is where an actor is present and already reading stderr. The
banner joins the ones `scripts/lib/test-contention.sh` already prints, so it lands in a channel someone reads,
with no alarm file and nothing that self-erases. No new cron entry is created, which was the original goal —
now achieved for a reason that survives review rather than by inheriting a channel that deletes its own
messages.

The cost objection that ruled out `tc_preamble` does not transfer. That objection was measured against
`_tc_scan_procs` (~6.6 s, reading `cmdline` for 592 pids). This walk **pre-filters on `fd/255` existence
first** — 31 pids box-wide as measured above — and only then performs the readlink and `stat` work, which is
roughly two orders of magnitude cheaper. The one-walk/one-snapshot invariant that plan established also does
not bind here: it binds because two walks made an *agreement* claim about the same quantity, and this walk has
a different predicate, different output, and asserts no agreement with `tc_preamble`.

The call site is `|| true`, because `test-all.sh` runs under errexit and no failure of this tool may ever
prevent a test run.

Two placements were considered and rejected on evidence: `scripts/tmpfs-guard.sh` `main()` (R1c — the channel
erases itself, and the errexit abort can suppress the heartbeat), and the SessionStart hook (that file's own
stated constraint, *"a healthy machine must not tax every session's context"* — the hook reads state, it does
not generate it).

## Implementation Phases

Ordered so that every contract lands before its consumer. The suite is written before the detector, per
`cq-write-failing-tests-before` — and, more pointedly, because a mutation matrix derived from finished code
tests the code that exists rather than the property.

### Phase 1 — the mutation matrix and the failing suite (RED)

Write `scripts/orphan-process-reaper.test.sh` against a `/proc` synthesized under the suite's own `mktemp -d`,
in the `tmpfs-guard.test.sh` idiom (`mkdir -p "$FAKE_PROC/4242"; ln -sfn … "$FAKE_PROC/4242/cwd"`). Every gate
asserted in both directions. `cases` incremented at the call site; `pass()` / `fail()` never move it. The
accounting-conservation check and an absolute assertion floor at the bottom. Suite must fail — the script does
not exist yet.

### Phase 2 — the detector

`scripts/orphan-process-reaper.sh`: seams declared at the top and each one actually read; `set -euo pipefail`;
`_orphan_is_deleted <pid> <link>` implementing the device-qualified discriminator **once**; `_orphan_classify`
as the single classification chokepoint; one `for d in "$PROC_ROOT"/[0-9]*` walk, pre-filtered on `fd/255`
existence, feeding both verbs.

Sources `scripts/lib/test-contention.sh` for `_tc_self_and_ancestors`, `_tc_pgrp` and `_tc_starttime_ticks`,
pinning `TC_TMPDIR` explicitly at the call site because that library binds it at source time — the exact
fail-open `scripts/test-all.sh` documents. Two binding conditions on that dependency:

- Only those three private helpers are used. No public `tc_*` verb is ever called: `tc_acquire` takes a lock
  and `tc_preamble` performs the 6.6 s walk.
- A `declare -F` assertion for all three names runs immediately after sourcing, in both the script and its
  suite. They are underscore-private, so a rename upstream is the failure that silently empties the exclusion
  set — and an empty exclusion set means the reaper can select its own ancestor chain. Errexit would abort on a
  missing function, but that abort is the only thing standing between a rename and a self-kill, and nothing
  currently documents the dependency.

Phase 1 goes green.

### Phase 3 — reap set, verbs, counters, ledger

The `dev:inode` reap-set expansion; `report` and `reap` with distinct exit codes (`0` / `10` / `1`); the
two-strike state file keyed on pid plus starttime; starttime re-validation at the signal site; children
signalled before the anchor; post-signal verification polls at ~T+5 s and ~T+30 s with survivors reported
explicitly. The counter line prints on **every** invocation with `anchors`, `set_members`, `would_signal`,
`signalled`, `survived`, `failed`, `refused`, `late_refused`, `skipped_same_pgroup`, `skipped_foreign_uid`,
`unreadable`, `scanned`, `valid` and `mode` as separate fields.

`unreadable` is load-bearing and not decoration: the fail-toward-alive rule silently drops candidates, and
without a count of those drops there is no evidence distinguishing "no orphans" from "the conjunction is
unsatisfiable in production". The kill ledger is written here, before any signal.

### Phase 4 — the mutation battery

`scripts/orphan-process-reaper-mutation.test.sh`. Each row copies the detector to a temp path, applies one
edit, runs the behavioural suite against the mutant, and asserts it **fails**. Two structural requirements,
both learned the hard way and both non-negotiable:

- The mutation is never applied inside `$( )`. A `jq`/`sed` failure inside a command substitution cannot fail
  the suite, which is how a fully broken harness once left 16 of 18 rows green.
- Every row first asserts the mutant **differs** from the original. A row whose edit matched nothing is
  vacuous and must be reported as such, not counted as a pass.

### Phase 5 — registration and wiring

Three `run_suite` lines in `scripts/test-all.sh`, each carrying the same explanatory comment shape its
neighbours use, plus the `|| true` preamble invocation alongside the existing contention banners. The
comment-only note in `plugins/soleur/scripts/lib/proc.sh` and its reciprocal in the reaper. Confirm
`scripts/lint-orphan-test-suites.sh` passes.

### Phase 6 — the decision record

Write the ADR, re-deriving its ordinal against freshly-fetched refs immediately before merge.

## Guard Contract

### Guard 1 — the orphan conjunction detector

**Property.** No process is signalled unless a confirmed **anchor** exists — own-uid, `cwd` and `fd/255` both
device-qualified-inode-verified deleted, not the scanner or an ancestor or same-process-group, older than the
age floor, and not vetoed by a live stdout — and the process is either that anchor or shares its deleted cwd
`dev:inode`; and no reading error, unparseable link, or ambiguity anywhere in that determination can produce a
signal.

**Assembly.** The chokepoint is `_orphan_classify` in `scripts/orphan-process-reaper.sh`: one `for d in
"$PROC_ROOT"/[0-9]*` walk emits pids, every pid passes through that single function, and both verbs consume
that one walk's classified output without re-deriving a verdict. The structural claim — not a list of today's
members — is *one walk, one classifier, one deletion predicate, two consumers*. Three things follow, and they
are what the matrix tests. If a second classification site appears (a verb testing a link itself, a "quick
pre-filter" that decides rather than narrows), the guard's scope is narrower than the property it names. The
deletion test must exist in exactly one place, `_orphan_is_deleted`, because a second copy is where the two
drift apart — and this repo already has a second, deliberately divergent copy in `proc.sh`, so the drift is not
hypothetical. And the reap set must be derived from a confirmed anchor rather than computed independently,
because a set computed on its own predicate is a second detector wearing the first one's authority. The
membership that matters is the set of *sites that can reach a signal*, and the suite asserts that set has one
element rather than asserting which links are checked today.

**Mutation matrix.** Each row edits a different **axis** — several edits of one shape are one mutation.

| # | Mutation | Axis | Must redden because |
| --- | --- | --- | --- |
| M1 | Drop the `fd/255` conjunct; classify on `cwd` alone | conjunction arity | The deleted-cwd-only fixture is flagged, and the conjunction the issue specifies is gone. |
| M2 | Replace `_orphan_is_deleted` with a bare `*' (deleted)'` suffix match | deletion semantics | The healthy process whose cwd is a directory literally **named** `work (deleted)` is flagged — the measured false positive. |
| M3 | Add `exe` to the conjunction | signal selection | The claude-self-update fixture (deleted `exe`, live `cwd`) changes verdict; the issue forbids this signal by name. |
| M4 | Add `fd/1` as a disjunct | signal selection | The tmpfs-guard cron fixture (deleted stdout, live cwd, live script) is flagged — the failure that kills this repo's own guard. |
| M5 | Remove the own-uid gate | ownership boundary | A foreign-uid fixture reaches classification instead of being refused. |
| M6 | Remove the self / ancestor / pgid exclusion | self-exclusion | The scanner's own pid appears among candidates. |
| M7 | Remove the age floor | recency | The two-second-old orphan fixture is flagged, so a process mid-teardown is a target. |
| M8 | Invert the error default: an unreadable link counts as deleted | fail direction | The unreadable-`/proc`-entry fixture is flagged instead of left alive. |
| M9 | Point the walk at a glob that matches nothing (`"$PROC_ROOT"/nonexistent*`) | **the guard's own dispatch** | The suite must fail on its absolute assertion floor and on `scanned=0`, rather than printing a clean total and exiting 0. |
| M10 | Make `_orphan_classify` return after its first candidate | **second member after a compliant first** | The two-orphan fixture yields one flag; a checker that stops at the first member is an instance of the very class this contract exists to catch. |
| M11 | Move the `cwd` test out of `_orphan_classify` into the `reap` verb | assembly | Two classification sites now exist; `report` and `reap` can disagree, and the parity arm reddens. |
| M15 | Drop `%d` from the discriminator, leaving a bare `%i` comparison | device qualification | The cross-device fixture — a live directory named `… (deleted)` on a different filesystem, contrived to collide on inode number with a genuinely deleted cwd — is flagged. |
| M16 | Remove the G6 stdout veto | veto term | The self-deleting-installer fixture (cwd and script unlinked, stdout on a live pipe) is flagged. |
| M17 | Apply the G6 veto to the reap set as well as the anchor | veto scoping | The `python3` child inheriting `>/dev/null` is spared, and the set no longer reaches the process holding the CPU — the R1a defect, restored. |
| M18 | Restrict the reap set to the anchor alone | reap-set derivation | The measured three-process fixture yields one signalled pid; the child that burns the cores survives. |
| M19 | Derive the reap set from its own predicate instead of from a confirmed anchor | reap-set derivation | An anchorless fixture — a process in a deleted cwd with no anchor anywhere — is signalled, which is a second detector wearing the first one's authority. |
| M20 | Signal the anchor before its children | ordering | The supervising-parent fixture respawns a child after the anchor dies, and the survivor arm reddens. |
| M21 | Remove the two-strike gate | evidence accrual | A first-sighting fixture is signalled on the very first run, so no firing is ever observed before a kill. |
| M22 | Key the two-strike state on pid alone, dropping starttime | identity | The recycled-pid fixture inherits a prior strike and is signalled on its first sighting. |
| M23 | Remove the starttime re-validation at the signal site | pid recycling | The fixture whose pid is recycled between scan and signal is signalled, and the `late_refused` arm reddens. |
| M24 | Remove the `uptime_s > 0` precondition on the age term | clock validity | The unreadable-`/proc/uptime` fixture yields a negative elapsed that passes the floor, and the arm reddens. |
| M25 | Drop the `unreadable` counter from the summary line | reportability | The fixture with three unreadable `/proc` entries reports the same summary as a clean walk, so a silent drop is indistinguishable from a real zero. |
| M26 | Remove the `declare -F` assertion, then rename `_tc_pgrp` upstream in the fixture | borrowed-primitive drift | The exclusion set empties silently and the scanner's own ancestor chain becomes selectable. |

**Harness rows.** These edit the **suite**, not the detector, because a matrix that only mutates the system
under test cannot see a vacuous harness.

| # | Harness edit | Must redden because |
| --- | --- | --- |
| H1 | Stub `fail()` to a no-op | `cases` is incremented at the call site, so it keeps moving while `fails` stops; the conservation check `pass_n + fails == cases` breaks. A floor enforced through the suspect cannot witness the suspect. |
| H2 | Neuter the battery's mutation step so the mutant is byte-identical to the original | Every row must first assert the mutant differs; a no-op edit is reported as a vacuous row, never as a pass. |
| H3 | Delete the assertion-floor block | The floor is absolute and hand-ratcheted to the measured case count; its absence is itself a failure, not a smaller run. |

**Must-PASS fixtures that are not the canonical.** RED rows alone cannot detect a detector that rejects
everything. Each of these differs from the canonical orphan in a way the contract explicitly permits, and each
must classify as **not flagged** while the detector is correct:

- Both links deleted, own-uid, correct pgid — but **younger than the age floor**.
- A healthy process whose `cwd` is a real directory literally named `… (deleted)`.
- The same, on a **different device**, contrived to collide on inode number with a genuinely deleted cwd.
- A process with deleted `cwd` and **no** `fd/255` at all, where no anchor exists anywhere (an `exec`ed-away
  script, or a stray process in a deleted directory) — no anchor, therefore no reap set, therefore untouched.
- The live tmpfs-guard cron shape: deleted `fd/1`, live `cwd`, live `fd/255`.
- The self-deleting installer: cwd and script unlinked, stdout on a live pipe — vetoed by G6.
- An anchor on its **first** sighting: reported, never signalled, because of the two-strike rule.

Two of these are worth naming as classes rather than cases. A wedged `git commit` from a sibling session — the
session-state doc for this branch warns by name that nine such were in flight and must not be killed — is
spared by the live-cwd term for as long as its worktree exists, and becomes a legitimate target only once the
worktree is gone, at which point its output really is unrecoverable. And `git worktree remove` on a worktree
with a suite still running inside it produces the target signature exactly: cwd unlinked, script unlinked,
process alive. Parallel worktrees are this repo's documented workflow, so that is a concrete, in-repo,
repeatable generator — it is both the positive fixture and the honest answer to "has this shape ever occurred
here", which the zero-hit census cannot supply.

### Guard 2 — suite registration

**Property.** Both new suites, and the live report line, execute in at least one runner on every full gate.

**Assembly.** The chokepoint is `scripts/lint-orphan-test-suites.sh`, whose producer is `git ls-files
'*.test.sh'` over the whole repository and whose covered set is the union of six registration surfaces. The
structural claim is that registration lives in `scripts/test-all.sh` as explicit `run_suite` lines, because
`scripts/*.test.sh` is deliberately excluded from that runner's auto-glob — *"an unregistered gate never
runs."* The `*.test.sh` suffix is the producer's key, which is why the suites are named to match it.

**Mutation matrix.**

| # | Mutation | Must redden because |
| --- | --- | --- |
| M12 | Delete the `run_suite` line for `orphan-process-reaper.test.sh` | The linter's whole-repo walk reports a tracked suite run by no runner. |
| M13 | Delete the `run_suite` line for the mutation battery | Same, for the second suite — asserting the check quantifies over both, not just the first. |
| M14 | Rename a suite to a name outside the `*.test.sh` suffix | The producer's key no longer matches, so the suite silently leaves the population; the acceptance criterion that asserts both names must catch what the linter structurally cannot. |

## Observability

Layer citation: this host has **no path to Sentry or Better Stack**. `scripts/tmpfs-guard.sh` records the
reason in its own header — Vector is not installed here, `tmpfs-guard` is not in the Vector tag allowlist, and
no local Sentry DSN exists. The observability layer for a cron-driven script on this box is therefore
operator-local state files plus journald, surfaced into the agent's session context by
`.claude/hooks/session-rules-loader.sh`, which is the only SessionStart reader of that channel. No SSH is
involved anywhere, because the host is the machine the command runs on.

The channel is the **suite's own stderr banner plus an append-only ledger** — deliberately not the tmpfs-guard
alarm file, which R1c showed deletes the whole file on a healthy-`/tmp` predicate uncorrelated with orphaned
processes, and whose single reader renders only `tail -1` under a `[tmpfs-guard] /tmp alarm` label.

```yaml
liveness_signal:
  what: the `[contention] ORPHAN_SCAN` summary line, printed on EVERY test-all.sh preamble run whether or not
    anything was found, carrying scanned/anchors/unreadable/valid
  cadence: once per test-all.sh launch — the moment the contention it detects is actually being paid
  alert_target: the operator's own terminal, in the same banner block as the existing LOW_TMP_HEADROOM /
    SIBLING_RUN_DETECTED / CAPACITY_* banners that scripts/lib/test-contention.sh already prints
  configured_in: scripts/orphan-process-reaper.sh (producer), scripts/test-all.sh preamble (caller)

error_reporting:
  destination: ~/.local/state/soleur/orphan-process-reaper-ledger.log (append-only, never cleared by any
    health predicate), plus the stderr banner, plus `logger -t orphan-process-reaper` to journald
  fail_loud: yes — an unwritable ledger path REFUSES the reap outright rather than signalling unrecorded. The
    ledger is the only surviving evidence of a kill, so losing it is not a degraded run, it is a run that must
    not happen. The refusal prints on the banner with the path that could not be written.

failure_modes:
  - mode: the detector stops running (preamble call removed or short-circuited)
    detection: the ORPHAN_SCAN banner line is absent from a test-all.sh run; scripts/test-all.sh's own suite
      asserts the line is emitted, so its removal reddens CI rather than going quiet
    alert_route: CI failure on the behavioural suite's banner arm
  - mode: procfs unreadable or hidepid-masked, so the walk observes nothing
    detection: an explicit 0|1 validity flag, reported as `valid=0`, never degraded to "no orphans found" — a
      probe that degrades to a number is indistinguishable from a real reading of that number
    alert_route: banner line, plus non-zero exit (1) from the live `report` registration in test-all.sh
  - mode: candidates are silently dropped by the fail-toward-alive rule
    detection: the `unreadable=N` counter, printed on every run — the only evidence separating "no orphans"
      from "the conjunction is unsatisfiable in production"
    alert_route: banner line
  - mode: TERM is sent and the process survives it
    detection: post-signal polls at ~T+5s and ~T+30s re-read /proc/<pid>; survivors are counted in
      `survived=N` and named individually
    alert_route: banner line naming each surviving pid and the escalation command, never a silent exit 0
  - mode: a false positive terminates live work
    detection: the authorizing record — pid, starttime, uid, sanitized cmdline, both link values with their
      deleted-state and dev:inode readings, measured age, verb, signal — is written to the ledger BEFORE the
      signal, because after a successful kill the /proc entry is gone and the evidence is unrecoverable
    alert_route: the ledger, which no health predicate ever clears
  - mode: the detector reports zero for a long period
    detection: `scanned=<N>` and `anchors=0` on every run distinguish a walk that observed 592 processes and
      found nothing from a walk that observed none; the two-strike state file additionally records every
      first sighting, so the first real firing is durably recorded even though nothing was killed
    alert_route: none — this is the healthy state, and the healthy state stays quiet by design

logs:
  where: the test-all.sh stderr banner; ~/.local/state/soleur/orphan-process-reaper-ledger.log; journald via
    `logger -t orphan-process-reaper`
  retention: the ledger is append-only and rotated on size by the same convention the sibling state files use;
    journald default on this host

discoverability_test:
  command: bash scripts/orphan-process-reaper.sh report
  expected_output: "valid=1 mode=report"
  # The expectation is deliberately a STABLE SUBSTRING of the summary line, not the whole line. preflight
  # Check 10 substring-matches stdout against this value, and every other field on that line — scanned,
  # anchors, unreadable — varies with whatever happens to be running on the box. Pinning them would make the
  # probe fail for reasons that have nothing to do with the change under review.
```

The probe's first token is `bash`, which is on `PROBE_VERB_ALLOWLIST` in
`plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh`. `credentials_required` is deliberately omitted:
the probe needs no credentials, and a declaration that waives nothing waives nothing.

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

This repo now carries three reaping surfaces with three different ownership boundaries: `proc.sh` (signals,
plugin-scoped, worktree-bounded, refuses deleted cwd), `tmpfs-guard.sh` (deletes files, cron-scoped, own-uid,
skips anything with an open fd), and this one (signals, repo-root, own-uid, requires deleted cwd). Recording
which boundary belongs to which surface, and why the deleted-cwd predicate's failure direction inverts between
the first and the third, is the substance of the decision.

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
**Assessment:** The CTO ruling approved the repo-root location, the name disambiguation, and sourcing
`scripts/lib/test-contention.sh` (ADR-178 is one-directional — it constrains plugin-shipped files sourcing
repo-root libraries, not the reverse), subject to two binding conditions now in Phase 2: private readers only,
and a `declare -F` assertion pinning them. It returned three findings that changed the design and are recorded
as R1a–R1c with the measurements that forced them: the `fd/255` term is bash-only so the anchor alone leaves
the load; `%i` without `%d` is not device-unique and reintroduces the false positive in the killing direction;
and the first draft's report channel erases its own messages. It ruled against the `tmpfs-guard.sh` call site
and for the suite-launch trigger, ruled that `proc.sh`'s bare suffix test gets an in-place comment rather than
an issue (two of three `wg-defer-only-after-inline-triage` conditions fail), and added the stdout **veto** — a
term the issue's framing does not reach, because the issue considers stdout only as a positive signal.

It also named `git worktree remove` on a worktree with a running suite as a concrete in-repo generator of the
target signature, which is the closest thing available to the sensitivity evidence the census cannot supply.

Two of its recommendations were not adopted as given. It ruled "reap on day one"; the plan reaps, but behind a
two-strike gate, because granting immediate kill authority to a detector that has never been observed firing
is the risk posture the issue is written about — and the gate is mechanical, so it costs nothing against a
62-minute orphan. It also proposed dropping suite registration from the risk list as "protected, not exposed";
registration stays as Guard 2 with its own mutation rows, since `lint-orphan-test-suites.sh` protects the
`*.test.sh` population and its own header records that the `test-*.sh` convention sits outside its producer.

The `spec-flow-analyzer` pass over the operator journey converged independently on the same channel defect and
contributed the kill ledger, post-signal verification, distinct exit codes, the `unreadable` counter, and the
end-to-end incident-trace criterion (AC29) — each of which closed a dead end where the journey terminated in
text with no next action.

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

### Pre-merge (PR)

1. `scripts/orphan-process-reaper.sh` exists, is executable, and its header states in prose that it reaps
   **processes** and is unrelated to `apps/web-platform/infra/orphan-reaper.sh`, which reaps `.orphaned-*`
   **directories** on the prod web host.
2. **Positive arm (synthesized, per `cq-test-fixtures-synthesized-only`).** A process launched with its cwd
   inside a temp tree and executing a script in that tree, with both the tree and the script unlinked after
   launch, is **flagged**. The fixture is built by the suite; no fixture is read from disk or from a live
   incident.
3. **Negative arm (the real false positive).** A process with deleted `fd/1`, live `cwd`, and live `fd/255` —
   the `scripts/tmpfs-guard.sh` cron shape, reproduced live on this box at plan time as pids 1531891/1531892
   — is **not flagged**.
3b. **Positive arm (the load, not the wrapper).** In the measured three-process shape — a bash wrapper with a
   deleted `fd/255`, a second bash, and a non-bash child, all sharing one deleted cwd `dev:inode` — **all
   three** are in the reap set and the non-bash child is signalled **before** the anchor. This is the
   criterion that ties the plan to the 62-CPU-minute incident: a run that signalled only the anchor would
   satisfy the issue's literal conjunction and still leave the cores held.
4. **Negative arm (`exe`).** A process with deleted `exe` and live `cwd` is **not flagged**, and `exe` appears
   nowhere in the classification path. Asserted by content anchor on `_orphan_classify`, not by a bare
   repo-wide token grep.
5. **Negative arm (the measured spoof).** A healthy process whose `cwd` is a real directory literally named
   `… (deleted)` is **not flagged**.
5b. **Negative arm (cross-device collision).** The same, on a different device, contrived to collide on inode
   number with a genuinely deleted cwd, is **not flagged**. Every comparison uses `%d:%i`; a bare `%i`
   comparison appears nowhere in the script.
5c. **Negative arm (the stdout veto).** A process with deleted `cwd` and deleted `fd/255` whose `fd/1` is a
   live pipe, a tty, or a still-existing path is **not flagged**. Three cases, one per stdout kind.
5d. **Veto scoping.** The same veto does **not** apply to reap-set members: the child inheriting `>/dev/null`
   in the arm-3b fixture is still signalled. Asserted in both directions from one fixture.
5e. **Anchorless.** A process in a deleted cwd with no anchor anywhere in the walk is **never** signalled.
5f. **Sibling-session safety.** A wedged own-uid `git commit` whose worktree still exists is **not flagged**
   (live cwd). The session-state doc for this branch records that nine such processes were in flight from
   other sessions and must not be killed.
6. **Negative arm (fail-toward-alive).** For each of: unreadable `/proc/<pid>`, unreadable `cwd`, unreadable
   `fd/255`, absent `fd/255`, and unparseable `stat` — the process is **not flagged**. Five separate cases,
   each incrementing `cases` at the call site.
7. **Negative arm (age floor).** A process satisfying the full conjunction but younger than the age floor is
   **not flagged**; the same fixture aged past the floor **is** flagged. Both directions, one fixture.
8. **Self-exclusion.** The scanner never flags itself, an ancestor, or a pid sharing its process group.
9. `report` signals nothing under every arm above, asserted by the absence of any `signalled` line and by the
   survival of every fixture process.
10. Exit codes asserted against synthetic fixtures, never the live machine: `0` when the walk completes
    (whether or not anchors were found), `1` when the walk is structurally invalid, and `10` from
    `report --strict` when an anchor was found. Asserting the default exit is independent of findings is the
    point of the arm — it is what keeps the live registration line from reddening on ambient machine state.
11. `reap` sends `TERM` only, one pid at a time, never to a process group, and never escalates to `KILL`
    automatically. Asserted against a captured-signal fixture, not by reading the source.
12. `reap` re-verifies the full conjunction **and the starttime** immediately before signalling. Asserted by a
    fixture whose pid is recycled between scan and signal, which must produce a `late_refused` count and no
    signal.
12b. **Two-strike.** An anchor on its first sighting is reported and **not** signalled; the same anchor on a
    later run **is** signalled. State is keyed on pid plus starttime, so a recycled pid does not inherit a
    strike — asserted in both directions.
12c. **Kill ledger.** Every signal is preceded by a ledger record carrying timestamp, pid, starttime, uid,
    sanitized cmdline, both link values with deleted-state and `dev:inode`, measured age, anchor-or-member,
    verb, and signal. An unwritable ledger path **refuses the reap** rather than signalling unrecorded, and
    that refusal is asserted. No health predicate anywhere clears the ledger.
12d. **Post-signal verification.** A fixture that traps and ignores `TERM` is reported as `survived=1`, named
    individually, with the escalation command — never a silent exit 0.
13. Dry-run parsing is fail-safe: every value other than an explicit off value yields a rehearsal. Asserted
    with at least `1`, `true`, `yes`, and an empty-but-set value.
14. The counter line prints on every invocation with `anchors`, `set_members`, `would_signal`, `signalled`,
    `survived`, `failed`, `refused`, `late_refused`, `skipped_same_pgroup`, `skipped_foreign_uid`,
    `unreadable`, `scanned`, `valid`, and `mode` as separate fields. A fixture with three unreadable `/proc`
    entries reports `unreadable=3`, distinguishable from a clean walk.
14b. **Borrowed primitives.** A `declare -F` assertion covers `_tc_self_and_ancestors`, `_tc_pgrp` and
    `_tc_starttime_ticks` immediately after sourcing, in both script and suite; no public `tc_*` verb is
    called anywhere. Asserted by a fixture that renames one of the three and requires a loud failure rather
    than an empty exclusion set.
14c. **Clock validity.** With `/proc/uptime` unreadable, the age term is not evaluated and nothing is flagged.
14d. **Preamble banner.** A `test-all.sh` run emits the `ORPHAN_SCAN` summary line whether or not anything was
    found, and the preamble call is `|| true` so no failure of this tool can prevent a test run. Both
    asserted.
15. Every path reaching any output is sanitized through the `tr -c '[:print:]'` idiom; a fixture directory
    named with an ANSI erase sequence cannot alter the operator's terminal or forge an audit line.
16. **Mutation battery.** Every row M1–M26 and every harness row H1–H3 in the Guard Contract above is
    implemented, and each is **demonstrated to redden** — the battery asserts the mutant suite FAILS, and
    first asserts the mutant differs from the original. A row whose edit produced no change is reported as
    vacuous and fails the battery. The rows span distinct **axes**, not one axis repeated: conjunction arity,
    deletion semantics, device qualification, signal selection, veto presence, veto scoping, reap-set
    derivation, ordering, ownership, self-exclusion, recency, clock validity, identity, evidence accrual,
    reportability, borrowed-primitive drift, fail direction, guard dispatch, and second-member handling.
17. No mutation is applied inside a command substitution. Asserted by the battery's own structure and pinned
    by H2.
18. The behavioural suite carries an **absolute** assertion floor, hand-ratcheted to the measured case count,
    and an accounting-conservation check (`pass_n + fails == cases`) with `cases` incremented at the call site
    only. Verified non-vacuous by H1.
19. `bash scripts/guard-vacuity-floor.test.sh` passes with the two new suites present, and the new suites'
    floors are recognised by its shape-derived population rather than reported as unclassified.
20. `scripts/test-all.sh` carries three explicit `run_suite` lines — behavioural suite, mutation battery, and
    the live `report` line — each with an explanatory comment in the idiom of its neighbours.
21. `bash scripts/lint-orphan-test-suites.sh` passes; neither new suite is reported as an orphan.
22. `python3 scripts/lint-guard-contract.py` passes against this plan file: both `### Guard` entries carry a
    non-placeholder `**Property.**` and `**Assembly.**`, and each mutation matrix has at least three rows.
23. `scripts/tmpfs-guard.sh` is **not modified** — `git diff --stat origin/main -- scripts/tmpfs-guard.sh` is
    empty — and `bash scripts/tmpfs-guard.test.sh` passes. Its fd-skip behaviour is untouched by construction
    rather than by care.
23b. `plugins/soleur/scripts/lib/proc.sh` changes by comment only: `git diff origin/main --
    plugins/soleur/scripts/lib/proc.sh` adds no non-comment line, and `bash plugins/soleur/test/proc.test.sh`
    passes. The comment records the divergent deletion predicate and its inverted failure direction, and the
    reaper carries the reciprocal note.
24. `bash scripts/orphan-process-reaper.sh report` against the real `/proc` exits 0, reports `valid=1`, and
    reports `scanned` greater than zero. It deliberately does **not** assert `anchors=0`: a real orphan on the
    box at verification time is ambient state, and a criterion it can flip measures the machine rather than
    the change. What this criterion pins is that the walk executes against a real procfs at all — the class of
    breakage a synthesized-`/proc` suite structurally cannot see.
25. Every seam declared in the script header is read by the code below it; a seam that is documented but
    unimplemented is asserted absent by a suite arm that sets each one and observes an effect.
26. The ADR exists, its ordinal is re-derived against freshly-fetched `origin/*` refs immediately before
    merge, and no acceptance criterion, plan line, or task line names a stale ordinal.
27. Every `knowledge-base/` path cited in this plan resolves **at merge time**:
    `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'`
    prints nothing. Run at plan time it prints exactly two lines — the ADR and `tasks.md`, both of which this
    plan creates — and that is the only permitted output before those files land. Stating the carve-out
    matters: an unqualified residual-zero criterion and a plan that cites its own deliverables contradict each
    other, and the contradiction resolves in favour of deleting the citation, which is the wrong direction.
28. The plan's prose nowhere claims the detector has been shown to detect a real orphan. The zero-hit
    measurement is described as specificity in a sample containing no orphan, in every place it appears.
29. **End-to-end incident trace.** One suite arm reproduces the 2026-08-13 shape from launch to reclamation
    and asserts each hop: `git worktree remove` on a worktree with a running multi-process suite inside it
    produces an anchor; the first `test-all.sh` preamble run reports it and signals nothing; a later run
    signals the non-bash child first, then the anchor; the ledger carries a record for each written before its
    signal; and the summary reports `survived=0`. Without this arm the plan can be fully satisfied while the
    motivating incident recurs unchanged — every other criterion is about a gate, and none of them is about
    the journey.

### Post-merge (operator)

None. Every criterion above is verifiable in the PR, and the change introduces no provisioning, no credential,
and no scheduling step.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| **A false positive terminates live work.** The dominant risk, and the reason the whole design is conjunctive. | Five independent gates, all required; the inode discriminator closing the one false-positive vector measured at plan time; the two signals known to fire on healthy processes excluded by name and pinned by mutation rows M3/M4; report-only default; TERM without escalation; a durable pre-signal record. |
| **No sensitivity evidence exists.** The conjunction has never been observed firing on a real orphan; zero hits proves only specificity. | The synthesized positive arm is the only sensitivity evidence the plan claims, and it is labelled as such. The first shipped posture is non-destructive, so field evidence accrues before anything is killed. |
| **A report nobody acts on is a declaration site, not a guard** (2026-08-13). | The first draft's channel was worse than that — R1c showed it was a report nobody *receives*. The reporting path now terminates in the suite's own stderr, at the moment the contention is paid, in the banner block an operator is already reading. The two-strike rule means a persistent orphan is reaped rather than accumulating notifications. |
| **`fd/255` is bash-only, so the anchor alone reclaims nothing.** Measured: 30 bash plus one `dbus-daemon` box-wide, and the CPU-burning child has none. | The anchor authorizes a reap **set** defined by the shared deleted cwd `dev:inode` — exact set membership, measured identical across parent and child. M17/M18 redden if the set collapses back to the anchor. A process that `exec`s away and leaves **no** anchor anywhere is still invisible; that is stated in the script header and pinned by a must-PASS fixture. |
| **The reap set is wider than "descendants".** Two unrelated own-uid processes sharing one deleted cwd inode are both reaped. | Stated in the design rather than discovered later, and carried by its own fixture. Ancestry is not usable here because orphans are reparented. The widening is bounded by requiring a confirmed anchor first — M19 reddens if the set is ever computed on its own predicate. |
| **Sourcing `scripts/lib/test-contention.sh` from a killer.** That library declares itself observe-only. | Sourcing does not change what the library does. Only three underscore-private readers are used; no public `tc_*` verb is called, since `tc_acquire` locks and `tc_preamble` performs the 6.6 s walk. A `declare -F` assertion pins all three names, because a silent rename empties the exclusion set and an empty exclusion set lets the reaper select its own ancestor chain. The caller pins `TC_TMPDIR` explicitly, that library binding it at source time being the exact fail-open `test-all.sh` documents. |
| **Kill authority now fires from the repo's hottest path.** | Bounded three ways: the two-strike rule means nothing is ever killed on first sighting, so no unobserved firing can cause a kill; the harm bound is structural, since a process whose script and cwd are both unlinked cannot produce recoverable output through those paths; and the call site is `|| true`, so no failure of this tool can prevent a test run. |
| **ADR ordinal collision.** Ordinals moved twice in one session on a prior branch. | The ordinal is declared provisional, the probe quantifies over all `origin/*` refs rather than `origin/main`, and AC26 requires a re-derivation immediately before merge plus a sweep of every artifact naming it. |

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Extend `plugins/soleur/scripts/lib/proc.sh` with a deleted-cwd verb | It ships inside the plugin for marketplace installs (ADR-178/ADR-179); this is a dev-box maintenance concern. Its ownership boundary is a live-cwd prefix test that structurally cannot own a process whose cwd is gone, and its refusal of deleted cwd is a documented, correct decision for what that file does. |
| Wire detection into `tc_preamble` | Measured: `_tc_scan_procs` costs ~6.6 s, and `test-all.sh` establishes that a second walk is a second non-atomic snapshot. A detector there taxes every suite launch and re-opens a defect a prior plan closed. |
| A dedicated `*/5` cron entry | Buys nothing an existing entry does not, and adds a scheduling surface that is not IaC-managed. |
| Report-only from `scripts/tmpfs-guard.sh` `main()` — the first draft's choice | Refuted by reading the code, not by argument. `alarm_clear_if_healthy()` removes the whole alarm file on a `/tmp`-health predicate uncorrelated with orphaned processes, so a report written at T is gone by T+5min; the single reader renders only `tail -1`, under a `[tmpfs-guard] /tmp alarm` label that mis-routes diagnosis. Separately, a non-zero return under that file's errexit can abort `main()` before `heartbeat_write` and take the tmpfs alarms dark too. |
| Run the walk from the SessionStart hook | That file states its own constraint: a healthy machine must not tax every session's context. The hook reads state; it does not generate it. |
| Report-only everywhere, with reaping deferred to a follow-up issue | Leaves the motivating incident unaddressed by construction, and makes the fix depend on someone re-opening a tracking issue. The two-strike rule achieves the same evidentiary caution mechanically: nothing is killed on first sighting, so the first real firing is always observed and recorded first — without a deferral that can rot. |
| Reap unconditionally on first sighting | Zero conjunction hits on a box containing no orphan is specificity evidence only. Granting immediate destruction to a detector that has never been observed firing inverts the risk the issue is written about. The two-strike rule keeps the reaping while removing the unobserved-first-kill. |
| Escalate to `KILL` when `TERM` does not take | Not on day one. Survivors are counted, named, and reported with the escalation command instead, so the decision to escalate is recorded rather than automatic — and the `survived` counter is the evidence that would justify changing it later. |
| Match on stdout/stderr as the issue's original discriminator suggested | Falsified by the issue's own measurement and re-measured here: it is this repo's own tmpfs-guard cron shape, live on the box at plan time. |
