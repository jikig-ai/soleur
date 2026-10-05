---
title: "ADR-195 — the orphaned-process boundary is an inode-verified deleted-cwd conjunction, and it reports rather than reaps"
status: accepted
date: 2026-08-20
issue: 7537
tags: [tooling, test-contention, process-lifecycle, safety]
---

# ADR-195 — the orphaned-process boundary is an inode-verified deleted-cwd conjunction

## Status

Accepted, 2026-08-20. Implemented by `scripts/orphan-process-reaper.sh` (#7537).

## Context

Nothing in this repository terminates a *process* that has outlived its work.
`scripts/tmpfs-guard.sh` reclaims **files** and deliberately skips entries with open file
descriptors — correct for a live run, and precisely why an orphaned process survives it.
`plugins/soleur/scripts/lib/proc.sh` enumerates and signals processes with a full safety
apparatus, but it is scoped to a *worktree it can identify* and refuses a deleted cwd outright.

The gap between them is a process whose working directory and executing script have both been
unlinked out from under it — the shape `git worktree remove` produces when a suite is still
running inside the worktree. It keeps consuming CPU and tmpfs, and its output is unrecoverable
by construction.

The hard part is the discriminator, not the signal. Under `ps` a detached run and an orphaned
run are identical.

## Decision

**1. The boundary is a conjunction, and "deleted" means `st_nlink == 0`.**

A pid is an **anchor** only when all of: own uid; `cwd` genuinely unlinked; `fd/255` an unlinked
regular file at an absolute path ending `' (deleted)'`; same mount namespace; same pid namespace;
not the scanner, an ancestor, or its process group; and older than an age floor.

Deletedness is the kernel's own link count, not the `' (deleted)'` suffix. Measured on the
implementing box:

| subject | `stat -Lc '%h'` |
| --- | --- |
| genuinely deleted cwd | `0` |
| healthy process whose cwd is a real directory named `work (deleted)` | `2` |
| ordinary healthy process | `21` |

The suffix is a string the kernel appends and a directory may legitimately carry, so a suffix
test produces a false positive **in the direction that kills**. The link count also retires two
weaker remedies that were considered and are recorded here because they were wrong for
instructive reasons: an inode-number comparison is not unique across devices, and a
device-qualified `%d:%i` comparison needs two stats with a window between them. All three
problems disappear rather than being defended against.

The property this ADR fixes is *"genuinely unlinked, namespace-independently."* `st_nlink` is
today's mechanism for it. Tests are written against the property so that changing mechanism later
does not read as weakening a guard.

**2. `exe`, `fd/1` and `fd/2` are never consulted at all.**

Not "never as a positive term" — never. A `claude` self-update unlinks the running binary (the issue
reported ~11 live hits; re-probed while writing this record the count was **0**, so it is an
issue-time reading rather than a measurement taken here — the class is real, the number is
transient), and a deleted stdout with a live cwd **is** this repo's own
`scripts/tmpfs-guard.sh` cron instance. Keeping those reads out of the code makes both false
positives structurally impossible rather than dependent on a polarity discipline a later edit can
flip.

**3. The anchor identifies; a confirmed anchor authorizes a SET.**

Measured: `fd/255` is bash's script descriptor. Of ~594 processes, 27 carry one — 26 `bash` plus
one `dbus-daemon`, whose `fd/255` is an `anon_inode:[pidfd]` rather than a script descriptor. So it
is absent on every non-shell process **as a script descriptor**; the flat claim "absent on every
non-shell process" is falsified by its own example sentence, and the census figure drifts with the
box — it is quoted as an order of magnitude, not a constant. So the
issue's own conjunction flags the bash **wrapper** and leaves the `python3` child that is actually
holding the cores. Since the motivating incident is a battery that ran for 62 minutes of wall-clock
(not 62 CPU-minutes — on a 16-core box at `-P6` those are different quantities, and the issue says
the former), and a battery's CPU lives in its children, the conjunction alone would not have reclaimed the thing it
was written for.

The conjunction is therefore preserved verbatim as an **anchor**, and a confirmed anchor extends
to every own-uid process sharing that anchor's cwd **`dev:inode`** — measured identical across all
three processes in that shape, because children inherit cwd across `fork` and an unlinked
directory keeps its inode. Membership restates the gates it CAN restate, and this is stated precisely because an earlier draft of
this record claimed parity it does not have. A member must satisfy: own uid, same mount and pid namespace,
not the scanner or an ancestor or its process group, cwd genuinely unlinked, the anchor's cwd `dev:inode`,
the anchor's **session id**, and the age floor. It is **not** subject to G3 — the `fd/255` conjunction is
anchor-only, because `fd/255` is bash's script descriptor and a non-shell child does not have one. That is
the entire reason the set exists, so the omission is deliberate; claiming "every gate" merely invited the
next reader to skip re-deriving the member predicate.

The device qualifier is load-bearing here even though the link count retired it from the
deletedness test: membership is still an inode-*number* equality test, `/tmp` is dev 50 (tmpfs)
while a worktree is dev 66307 (ext4), and tmpfs hands inode numbers from a monotonic counter — so
the number is steerable and a bare `%i` match is reachable by an unrelated process.

**4. Self-exclusion quantifies over MEMBERS, not just anchors.**

An earlier draft applied it to anchors only. Run the motivating scenario against that: `git
worktree remove` on a worktree with a suite running inside it leaves the runner, the reaper it
spawned, and every suite child sharing one unlinked cwd — so the reap set becomes the caller's
entire process tree and the reaper kills its own ancestors. The one concrete in-repo generator was
also the one scenario in which it destroys the session that ran it.

**5. It reports; it does not reap.**

The trigger is a `report` invocation in `scripts/test-all.sh`'s preamble. Nothing invokes `reap`
automatically anywhere — and this sentence was **false when first written**. The behavioural suite's
end-to-end arm ran `reap` against the real `/proc` with no signal sink and no pid restriction, so every
full-gate run performed an unattended box-wide reap, twice. It is true now because that arm is scoped
through the refusal-only authorization seam, and because a suite assertion pins that no direct `reap`
invocation lacks a root seam, a sink, or a pid list. A claim of this shape needs a mechanical check
rather than a sentence, which is the whole lesson of the record it sits in.

This follows from the evidence, not from timidity: the conjunction returned **zero hits across 222
own-uid processes**, which is evidence of *specificity in a sample containing no orphan* and is
**not** evidence of sensitivity. The only sensitivity evidence that exists is a synthesized
end-to-end arm. Until the detector has been observed firing on a real orphan, the first strike is
a reader's judgment.

## Consequences

- Ownership is established **once**, in the walk, as a fork-free `[[ -O ]]`. This is a
  correction: the gate originally sat in the classifier and measured `skipped_foreign_uid=0`
  against a real `/proc`, because a foreign process's `/proc/<pid>/fd` is mode 500 and the
  `fd/255` pre-filter rejected it first. The gate was unreachable in production and its removal
  had no observable — a guard that could not fire.
- Every unreadable `/proc` entry, unparseable link, failed `stat` and ambiguity leaves the process
  **alive** and increments a counter. The counters are not decoration: without them a silent drop
  is indistinguishable from a real zero, and "no orphans" is indistinguishable from "the
  conjunction is unsatisfiable in production".
- The two predicates are not two answers to one question, and recording them that way is the trap. `proc.sh`
  asks a **containment** question — "is this process inside the worktree I own?" — for which an unresolvable
  path is a refusal. The reaper asks a **liveness** question — "is this inode unlinked?" — for which the same
  reading is positive evidence. Describing them as inverted polarities of one deletedness test, as an earlier
  draft of this record did, would send the next reader to unify them on the wrong axis.
- The unification that WOULD be legitimate is blocked by a constraint worth naming: ADR-178 forbids a
  plugin-shipped file from sourcing a repo-root library, so a shared primitive would have to live plugin-side
  or be vendored. The target shape, if anyone takes it on, is one primitive with three callers each applying
  its own policy — because the repo now carries **three** `/proc` classification sites (`proc.sh`,
  `scripts/lib/test-contention.sh`, and this reaper), which is the inventory a future consolidator needs.
- The tool refuses to run as root. Under `sudo`, "own uid" silently becomes uid 0 and the
  enforcement-by-accident (`readlink` failing on a foreign process) evaporates — measured,
  `readlink /proc/1/cwd` fails as uid 1001 and succeeds as root — so the reap set would become
  every root process with an unlinked cwd, a populated class on a box mid-`apt`.
- The cardinality cap bars *automatic* action only. The full set is always reported and `reap`
  takes an explicit override, because the cap is also a free denial-of-reaping: any own-uid process
  can `fchdir` into the doomed inode enough times to hold a set over it.

## Alternatives considered

- **Extend `proc.sh`.** Rejected: it refuses deleted cwds by design, and inverting that would
  change the failure direction of a file that signals processes for a different reason.
- **A `tmpfs-guard.sh` reporting channel.** Rejected on measurement: `alarm_clear_if_healthy()`
  deletes the whole alarm file whenever `/tmp` is healthy, and `/tmp` occupancy is uncorrelated
  with orphaned processes — the motivating orphan's cwd was already unlinked, so it occupied no
  `/tmp` entries at all. A report written at T is deleted at T+5min. That is worse than a report
  nobody acts on; it is a report nobody receives.
- **An `fd/1` veto** (do not flag if stdout resolves to a live path). Rejected: it vetoes this
  design's own positive control, whose `fd/1` is `/dev/null`, and it spends the
  free-by-construction argument for keeping stdout unread.
- **An exit code for "candidates found".** Rejected: `test-all.sh`'s `suite_exit_class()` maps it
  to `failed`, so the first time the detector ever worked the gate would go red and the cheapest
  remedy would be to delete the line. The incentive inverts.
- **A bespoke append-only ledger.** Rejected as redundant with journald, which is already durable,
  already rotated, and cleared by no health predicate.
- **Inngest (ADR-033's canonical path for scheduled work).** Does not apply: this is not scheduled
  work. It runs inside `test-all.sh` on a developer's own box and reads a `/proc` that exists only
  on that machine; an Inngest function runs on a different host and could not see the processes in
  question.
