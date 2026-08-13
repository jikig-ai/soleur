---
title: The local test runner treats the shared tmpfs as a managed resource and serialises worktrees via an advisory lock
status: active
date: 2026-07-22
---

# ADR-133: `test-all.sh` — managed tmpfs + advisory cross-worktree lock

## Context

Parallel worktrees are this repo's documented workflow, but two sessions running
`scripts/test-all.sh` concurrently could produce failures that look like real
regressions (#6789, prior data points #6726, #4096, #3817/#4128). The only
mitigation was prose in `plugins/soleur/skills/work/SKILL.md` telling the agent
to run `ps -ef | grep test-all` and wait — detection guidance for a human, not
isolation. Every overlap was serialised by hand, and a contended run read as a
bug that did not exist.

The recorded cause in `work/SKILL.md` named `skill-security-scan`'s
`.scan-meta.json` plus the semgrep bootstrap as "the known pair" of colliding
shared paths. Both halves were refuted by measurement (see Alternatives
Considered). The actual contended resource is **capacity**, not a name: every
suite's `mktemp` lands in the same machine-global, RAM-backed 4 GiB `/tmp`
tmpfs, measured at 86% full with swap exhausted. A second run competes for the
memory the first is holding, which is exactly the condition under which the two
implicated suites' documented timeout-flake class fires.

## Decision

1. **Instrumentation ships ahead of every fix.** `scripts/lib/test-contention.sh`
   is observe-only (creates no files, takes no locks, deletes nothing). It prints
   a contention preamble (`/tmp` + runtime-dir headroom, sibling `test-all.sh`
   runs resolved to their worktrees via `/proc/<pid>/cwd`, machine load) and
   named banners (`LOW_TMP_HEADROOM` / `SIBLING_RUN_DETECTED`, joined by
   `SIBLING_SUITE_DETECTED` in #7424) so a contended run
   is self-identifying and a false RED is never again diagnosed as a regression.
   A per-suite `/tmp` entry-count delta, appended to the existing
   `TEST_TIMING_LOG` channel, is the probe for a residual shared-tempfile
   hypothesis.

2. **The shared tmpfs is a managed, reaped resource — not unbounded scratch.**
   `scripts/tmpfs-guard.sh` (already a 5-minute cron) is extended beyond its
   `.output`-only scope to reap stale, large, own-uid `/tmp` scratch entries,
   gated on age **and** size **and** ownership **and** liveness, never protected
   session dirs. `skill-security-scan`'s per-pid `meta_dir` — a measured 12,889
   leaked dirs with no cleanup — is age-reaped at run-scan startup.

3. **Worktrees serialise via a git-common-dir ADVISORY lock.** `test-all.sh`
   reuses `session-state.sh`'s `acquire_lock` (no new primitive, no modification
   to the shared one). The lock is advisory: on timeout it proceeds with a
   `LOCK_CONTENDED_PROCEEDING` banner and NEVER aborts, so no failure mode of the
   lock can prevent or wedge a test run. CI is exempt; the kill switch and
   fail-open behaviour of the primitive are inherited.

## Alternatives Considered

- **`.scan-meta.json` collides across worktrees (the recorded H2).** REFUTED.
  `run-scan.sh` PID-scopes it to `${XDG_RUNTIME_DIR:-/tmp}/skill-security-scan-$$`;
  `git log -S'skill-security-scan-$$'` returns a single commit — the skill's
  original one. It was PID-scoped from birth, so the attribution was wrong when
  written, not stale-after-a-fix. Its real defect was an unbounded directory
  leak, not a collision.

- **The semgrep bootstrap is the other colliding half (the recorded H1).**
  REFUTED by reachability. `ensure-semgrep.sh` is invoked only by agent-driven
  paths (`review/SKILL.md`, the workflow, the `semgrep-sast` agent); a grep over
  the exact suite globs `test-all.sh` enumerates returns zero hits. No suite the
  runner reaches can run the bootstrap.

- **Reap `.scan-meta.json` with an `EXIT` trap.** REJECTED. The file is GDPR
  Art. 32 evidence with a documented post-exit consumer (`override-mechanism.md`),
  so an EXIT trap would delete the artifact the override flow references.
  Age-reaping older siblings at startup bounds the leak without touching the
  current run's artifact.

- **Make the lock blocking (abort on timeout).** REJECTED. Aborting converts
  today's silent wait into a hard failure — strictly worse than the status quo.
  An advisory lock that proceeds-with-announcement preserves the worst case (an
  interleaved run) while making it attributable, which is the actual defect.

- **Implement stale-holder detection on the lock.** REJECTED as dead code.
  `flock` is kernel-managed and inode-bound, released automatically once the last
  fd holder dies (measured with a positive control; a "dead pid still holds the
  lock" state is unreachable with real `flock`). Stale detection is only needed
  for hand-rolled `mkdir`/PID-file schemes.

- **Reap the many small `/tmp` entries (by count).** REJECTED. 4,294 small
  entries held 160 MB (4.5%) while three trees held 3.1 GiB (88%). Reaping by
  count recovers 4.5% of the problem while feeling thorough; the reaper sorts by
  bytes.

## Consequences

- A false RED from contention is now self-announced, not hand-diagnosed.
- The 4 GiB tmpfs cap (Layer 3 of the 2026-03-28 tmpfs guard) stays intact; what
  was missing was a reaper for the artifact class filling it, now added.
- Concurrent runs serialise, adding wait for a second run — announced and
  bounded, with a kill switch, rather than the silent interleave-or-manual-wait
  it replaces.
- No product runtime surface, user data, or tenant boundary is touched; this is
  local developer tooling on the operator's own machine.

## Addendum — 2026-08-10 (#7376): scope of the "capacity, not a colliding path" verdict

<!-- lint-infra-ignore start: describes a PAST measurement's environment (which machine and mount ADR-133's original verdict was taken on), not a step anyone is being asked to perform. The actor+environment co-occurrence is what the linter keys on; there is no imperative here. -->
This ADR's verdict — that the observed flakiness was **capacity**, not a colliding path —
was measured on one specific machine and mount: a **RAM-backed 4 GiB `/tmp`** at 86% full
with swap exhausted, on the operator's workstation, under **cross-worktree** overlap.
<!-- lint-infra-ignore end -->

It does **not** transfer to `apps/web-platform/infra/run-registered-suites.sh` running on a
4-vCPU **hosted GitHub runner** against disk-backed `/var/tmp`, as a **single** run. Those
differ on every variable the verdict rests on.

The distinction is load-bearing because this ADR is the obvious thing to cite when the next
parallel-runner flake appears, and citing it as *evidence* about a different machine would
close the investigation on a measurement that was never taken there. Its **method** — probe
before committing to a mechanism, and let a measurement rather than an argument settle it —
transfers completely. Its **conclusion** is a prior, not evidence.

Recorded because #7376 was, in fact, a colliding path in part: `run-registered-suites.test.sh`
is itself a registered suite, and it created and deleted a fixture inside the live
`apps/web-platform/infra/` directory while `credential-persist-home-guard.test.sh` was
copying that directory and diffing the copy against the still-live source. Under this ADR's
verdict alone, that class would not have been looked for.

### Two departures from this ADR's decisions, recorded rather than left implicit

**Decision 1's "observe-only" clause does not hold for #7376's instrument.** ADR-133 specifies
instrumentation that "creates no files, takes no locks, deletes nothing." The per-suite capture
in `run-registered-suites.sh` creates a directory plus two files per suite (186 files for
today's 93) and removes that directory on a green run.

That matters beyond bookkeeping: **an instrument that is not observe-only is a confound for the
hypothesis it exists to measure.** Converting 93 suites' output from `/dev/null` to 186 file
writes adds I/O at exactly the contended moment H2 (capacity) is about. So a post-fix green loop
is partly an observer effect unless the baseline was run *with the instrument present*, and any
future investigator comparing runs across that boundary is comparing two different systems.

**Decision 1's "instrumentation ships ahead of every fix" ordering also does not hold.** The
load-bearing property that rule protects is *no fix commits to an unmeasured mechanism* — both
hypotheses this ADR recorded were refuted by measurement after being committed to in prose.
#7376 honours the property while departing from the ordering: the two fixes it ships are provable
**by reading** (a registered suite mutating the live tree that a sibling diffs against; an
`exit 0` on `PASS + RED != count`), and the fix that *would* have needed measurement — the
capacity arm — is explicitly declined. H2 (capacity) and H4 (polling deadline) remain UNKNOWN on
the hosted runner as of #7376; the collision finding above is a partial cause, not a refutation
of the others.

**Decision 2's "managed, reaped resource" needed the producer's help.** `scripts/tmpfs-guard.sh`
scopes to `/tmp` while this runner exports `TMPDIR=/var/tmp`, and this ADR explicitly rejected
count-based reaping — so retained `infra-suites.*` dirs were unreapable by construction and grew
to 414 dirs / 23 MB on the author's workstation before anyone looked. The runner now age-reaps
its own older siblings at startup and reaps the current dir from its `EXIT` trap, mirroring the
`meta_dir` precedent this ADR set for `skill-security-scan`.

## Addendum — 2026-08-11: the bytes were finally measured, and the lock stays

A post-mortem of a ~45-minute full-gate run proposed replacing Decision 3's advisory mutex with
**admission control on actual `/tmp` headroom**. This addendum records the measurement that
proposal asked for, and the verdict. **Decision 3 is unchanged; `status:` stays `active`.**
Nothing above is edited — this appends.

### Why a new instrument was needed

This ADR's capacity verdict is about **bytes** — it rejected count-based reaping precisely because
"4,294 small entries held 160 MB (4.5%) while three trees held 3.1 GiB (88%)". But the per-suite
probe shipped to observe contention records `tmp_delta=<ENTRY COUNT>`. The quantity this decision
exists to protect had never been measured by the instrument built to measure it.

`scripts/lib/test-contention.sh` now carries `tc_used_bytes`, reading `df -P -k` field 3
**per mount**, sampled at run boundaries into `TEST_TIMING_LOG` as `bytes_tmp=` / `bytes_tmpdir=`.

`df`, not `du`, and this is not a style preference: measured on the author's workstation,
`du -sk /tmp` took **2.15 s** and `du -sk /var/tmp` **did not finish in 115 s**. At the per-suite
hook originally specified that is ~578 recursive walks per mount — an unbounded observer effect on
the very run being instrumented, and the same objection that got a background sampler rejected.

### The measurement (2026-08-11, one full-gate run, `SOLEUR_TEST_FORCE_ALL=1`)

| Mount | Start | End | Delta |
|---|---:|---:|---:|
| `/tmp` (`TC_TMPDIR`, the 4 GiB tmpfs) | 3,553,042,432 B (3.31 GiB, **83%** used) | 3,810,562,048 B (3.55 GiB, **89%** used) | **+245.6 MiB** |
| `/var/tmp` (`TMPDIR`, disk-backed) | 378,100,240,384 B (352.1 GiB) | 377,556,484,096 B (351.6 GiB) | −518.6 MiB |

**Both figures are quoted deliberately.** One directory alone is incomplete by this addendum's own
reject condition: the two are different mounts on purpose, and a single number spanning them would
report health from whichever is roomier — indistinguishable from a healthy mount.

### What the numbers do and do not license

**The premise still holds.** ADR-133 described "a machine-global RAM-backed 4 GiB `/tmp` at 86%
full". Measured a month later: **83% at run start, 89% at run end**, with available headroom
dipping to **699 MB — below the runner's own 1024 MB floor**, firing `LOW_TMP_HEADROOM`. This is
not a historical condition that the `TMPDIR=/var/tmp` migration retired.

**The delta is an upper bound, not an attribution.** Three sibling `test-all.sh` runs were active
for part of this run (`SIBLING_RUN_DETECTED` fired, naming all three). The +245.6 MiB on `/tmp` is
the mount's movement, not this run's footprint, and cannot be split without a single-runner
baseline this budget did not buy.

**A near-zero `/tmp` delta would NOT have meant "no pressure, drop the lock."** It would have meant
the `TMPDIR=/var/tmp` mitigation works — which is a different claim, and the one this reading
actually supports. The mount still sat at 83–89% throughout, so the capacity hazard is live.

### The sharper finding: the lock is not currently serialising anything

The run queued on `tc_acquire` for the **full 900 s `TC_LOCK_TIMEOUT`** and then proceeded, while
**three sibling runs executed concurrently** — 3,775 s, 5,787 s and 5,763 s elapsed at the moment
of the probe, against a ~45-minute uncontended baseline. Because the lock is advisory and proceeds
on timeout, it is charging every session up to 15 minutes of delay while delivering no isolation.

That reframes the open question. It is not "mutex versus admission control"; it is **why a mutex
that proceeds on timeout is being relied on as a mutex**. Raising `TC_LOCK_TIMEOUT`, or making
acquisition blocking with a documented escape, are candidates the original Alternatives never
considered because the failure mode had not been observed.

### Verdict: keep the lock

The decision rule was fixed before the data arrived, so the data decides rather than the author.
The measurement does not clear the bar, and two mechanism-level objections survive any amount of
measurement:

- **TOCTOU.** Admission control is a point-in-time prediction about a 15-minute future. Two runners
  both sample abundant headroom, both admit, both allocate. Fixing that needs a reservation — the
  mutex again.
- **Non-monotonic degradation.** The mutex degrades to *slow*. Admission control degrades to
  ENOSPC mid-suite, producing a RED that reads as a code regression — the same
  "signal that is not evidence" harm this ADR exists to prevent, inverted.

**The evidence bar that was NOT met** (recorded so the next session inherits data rather than an
argument): an in-suite sampler at <= 2 s resolution; >= 3 single-runner runs for variance; >= 2 runs
at N=2 and >= 1 at N=3 with the lock disabled via `SOLEUR_DISABLE_SESSION_STATE=1`; a re-verified
filesystem premise (done — 83%, above); and one adversarial run starting the top-3 consumers
simultaneously. One run measures the *uncontended* case while the lock protects the *contended*
one, so n=1 clears no honest bar for replacing a mutex. Tracked at #7454 item 3.

The named follow-up candidate is a headroom **bypass on top of** the mutex, not a replacement.

## Addendum — 2026-08-12 (#7484): the wait is now measured, not asserted

The addendum above rests on an observation — "the run queued for the **full 900 s**" — that the
instrument of the day could not actually produce. `tc_acquire` printed
`LOCK_CONTENDED_PROCEEDING: '<name>' still held after ${timeout_s}s` unconditionally on every
non-zero return from `acquire_lock`, so the duration in that line was the *budget it was handed*,
never the time it waited. The 900 s figure was recovered by other means; the banner would have
printed it either way.

Worse, `acquire_lock` returns the same `99` for "waited the whole budget" and for
"`flock(1)` is not installed" — so a run that never waited at all reported as contention, and then
stated a duration for a wait that had not happened. `work/SKILL.md` instructs an agent to grep that
line to decide whether a RED is trustworthy, which made the false statement load-bearing.

**What changed** (confined to `scripts/lib/test-contention.sh`; `test-all.sh` and
`session-state.sh` are untouched):

- Both post-wait banners now report the elapsed **measured** across the `acquire_lock` call —
  `LOCK_ACQUIRED: '<name>' after <N>ms` and
  `LOCK_CONTENDED_PROCEEDING: '<name>' — gave up after <N>ms of <timeout_s>s`. Where timing is
  unavailable the banner prints `unknown`, never a fabricated `0ms`: a zero is indistinguishable
  from a lock that was free, which would re-introduce the same defect one branch over.
- The **dominant** `rc=99` source is removed by a `command -v flock` precheck emitting the existing
  `LOCK_UNAVAILABLE`. This is exact where an elapsed-time threshold would be approximate, and it
  needs no new outcome name — a missing `flock` is the same class as the two `LOCK_UNAVAILABLE`
  cases already there: the serialization layer is absent.

  **It removes one of three, and the residue is recorded rather than implied.** `_acquire_lock_impl`
  returns `99` from three places: the `flock` precondition (now precluded), the `exec {fd}>>` open of
  the lock file, and the genuine `flock -w` timeout. An unwritable lock directory therefore still
  reports `LOCK_CONTENDED_PROCEEDING` — measured on this branch as
  `gave up after 5ms of 900s`. That is a **non-timeout failure still classified as a timeout**, so
  the second half of the Guard Contract's property is enforced for one cause rather than all of
  them. What changed is that the case is now self-diagnosing: 5 ms against a 900 s budget is legible
  as a precondition failure, where the previous text printed the identical flat lie
  `still held after 900s` whether or not anything was ever held. Classifying the residue by an
  elapsed threshold was considered and rejected — approximate where `command -v` is exact — and
  closing it properly means reaching into `session-state.sh`'s internals, which is a separate change.
- `LOCK_WAITING` is emitted after every skip path, so its presence is a fact about control flow
  ("this run reached the wait") and a long block reads as a queue rather than a hang.
- Both banner **tokens** are byte-identical. Only post-colon text moved, so this ADR's own
  vocabulary, `work/SKILL.md`'s contention grep and the existing arms all still match.

Every `tc_acquire` exit path still returns `0` — Decision 3's fail-open contract, since an instrument
that could wedge the run it observes would violate the contract it exists to serve.

**A structural assertion of that contract is not sufficient, and this change is the demonstration.**
The first cut asserted it by grepping the function body: every `return` is a `return 0`. That check
passed while the function could still **abort without returning at all** — `test-all.sh` sources this
lib under `set -euo pipefail`, so the bare `$EPOCHREALTIME` reads the measurement introduced were an
unbound-variable abort on any shell lacking the variable. It also made the `unknown` branch
unreachable on precisely the platform it was written for: the abort happens at the read, before the
guard is entered. Both are fixed (`${EPOCHREALTIME:-}` at every read) and the contract is now asserted
**behaviourally** as well — an arm that de-specialises `EPOCHREALTIME` under `set -euo pipefail` and
requires a `0` return plus the honest `unknown` token. The general form, worth carrying forward: a
grep over exit statements cannot see an exit that is not a statement.

**First two readings from the instrument** (2026-08-12, this repo, real runs on the ship path):

| Run | Banner | Outcome |
|---|---|---|
| queued behind 2 sibling worktrees | `LOCK_CONTENDED_PROCEEDING: 'test-all' — gave up after 899122ms of 900s` | abandoned at budget |
| lock free | `LOCK_ACQUIRED: 'test-all' after 12ms` | uncontended floor |
| queued behind 2 sibling worktrees | `LOCK_ACQUIRED: 'test-all' after 616310ms` | **redeemed at 616 s** |

The first independently reproduces this ADR's 2026-08-11 "waited the full 900 s" figure — which the
banner of the day could not have produced, since it printed the budget whether or not a wait
occurred. The second is the uncontended floor.

**The third is the one the instrument was built for, and it is the first of its kind in this repo.**
It is an *uncensored* observation of a redeemed wait: the run queued, waited **616 s**, and then
acquired — it was not truncated at the budget. So the plan's honest question ("does the wait ever
pay off, and what is the longest wait that was redeemed?") now has a first answer: **yes, and at
least 616 s.** Before this change that run and the 12 ms run printed the identical
`LOCK_ACQUIRED: 'test-all'` line with no duration, so the two were indistinguishable and this datum
did not exist.

Its immediate consequence is negative, which is why it is worth recording: a `TC_LOCK_TIMEOUT`
lowered to any value under ~620 s would have converted this run from *serialized* into *interleaved*.
The option the measurement most directly supports is therefore **not** the one a censored reading
suggested. That is a single observation, not a distribution, and it does not license a mechanism
change on its own — but it is the first evidence that the budget's current value is doing work
rather than merely being waited out.

**What this does NOT settle.** Contended observations are **right-censored** at the fixed budget, so
they cannot answer "would a longer wait have succeeded?" — and the short-circuit-on-holder-age
candidate is parameterised by the *holder's* remaining run, while every duration here is the
*waiter's*. The mechanism question the addendum above opened therefore remains open on the same
terms; this change makes the waiter's side of it a measured quantity rather than an inferred one.
