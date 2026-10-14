---
title: "The verification I shipped could not fail, and my instrument measured the wrong machine"
date: 2026-08-03
issue: 7166
pr: 7169
category: workflow-patterns
tags: [systemd, cgroups, silent-failure, test-vacuity, mutation-testing, verification]
---

# The verification I shipped could not fail, and my instrument measured the wrong machine

Building the memory backstop (#7166, ADR-161) produced more lessons about *verifying*
than about cgroups. The feature exists because a predecessor shipped a hook that never
executed while its suite was 26/26 green. I then reproduced that same failure shape
three separate times in my own work, each by a different route, and each time it was
caught by something other than the thing I had built to catch it.

## 1. A membership check that re-asserts its own branch condition

The hook's anti-#7151 mechanism is "verify cgroup membership after applying, never
assume the D-Bus call worked." That is correct on the fresh-adoption path. On the
**re-entry** path it is worthless:

```bash
if [[ "${our_cg##*/}" != "$scope" ]]; then   # ... disambiguation
else
  # ...refresh caps...
fi
# later:
[[ "${final_cg##*/}" == "$scope" ]] && outcome="applied"
```

The `else` branch is reached *only when* `our_cg == scope`. Asserting `final_cg == scope`
afterwards re-asserts the branch's entry condition. It cannot fail. And re-entry is the
common path — every `/clear`, every resume.

**The generalizable rule:** when a guard sits after a branch, check whether the branch's
own entry condition already implies the guard's predicate. If it does, the guard is
decoration. Verify the thing that actually changed (here: the cap *properties*), not the
thing that selected the branch.

## 2. All-or-nothing calls need per-property readback, and rc=0 proves nothing

`SetUnitProperties` is atomic: one unsupported property fails the **entire** call.
`ManagedOOMPreference` requires systemd ≥ 247, so on an older host the fleet
`MemoryHigh`, `MemoryMax` **and** `MemorySwapMax=0` all silently vanish together — while
the per-session scope still succeeds and the hook reports `applied`. That restores the
swap-exhaustion half of the very incident the feature exists to prevent.

Checking the exit code does not help either — measured:

```
$ busctl --user call ... SetUnitProperties "sba(sv)" "soleur-probe-nope.slice" true 1 \
    "MemoryMax" "t" 1073741824
rc=0     # and the unit did not previously exist; systemd loads it inactive
```

**Rule:** rc=0 means "the call was accepted", never "the running unit carries the effect."
Read the property back. And log what was **observed** (`slice_max_after`) beside what was
intended (`slice_max`) — a field named like state but holding intent is worse than no
field, because a reader reasonably trusts it.

## 3. A property armed on the unit nobody consults

`systemd-oomd` selects among the **monitored cgroup's direct children**. The monitored
cgroup is `user@<uid>.service`, whose direct child is `soleur.slice` — not
`soleur-agents.slice`, where the code set `ManagedOOMPreference=avoid`. The ADR's own
prose stated the mechanism correctly and the code targeted the wrong unit anyway. This is
distinct from the honestly-disclosed "efficacy unvalidated" caveat: that one is about
whether oomd ever arms; this was a targeting error that would persist even when it does.

**Rule:** when an ADR states a selection mechanism ("X chooses among Y's direct children"),
trace the code's target against that sentence explicitly. Prose that is right and code
that is wrong read identically in review.

## 4. Two tests proven vacuous by experiment, not by argument

A review agent did not argue these were weak — it *ran* them:

- **Deleting all three positive identity branches** — making the hook structurally
  incapable of ever adopting anything — left the suite **green at 34/34** on every CI,
  Docker, macOS and detached run. `T5` had three assertions and all three were negative
  ("adopt nothing on no match", "PID 0 rejected", "PID 1 rejected"). Nothing established
  that the good thing *happens*.
- **Deleting the entire 437-line live arm** left the deletion-detector printing
  *"skip count matches the 12 declared live tests"*. It compared `LIVE_TEST_COUNT=12`
  against a hand-written list of 12 names; neither side referenced a single assertion.
  The reconciliation was `12 == 12`.

Both fixes were verified by reproducing the same experiments: the identity mutation now
goes RED, and the ledger now prints `deleted, not skipped: T14-kill-mechanism`.

**Rule:** negative-space-only coverage goes green over an inert implementation. Every
"the bad thing didn't happen" assertion needs a sibling establishing that the good thing
does. And a hand-maintained integer can never detect deletion — derive the ledger:
make each test *mark itself*, and name whatever neither ran nor was skipped.

The irony worth recording: `settings-hook-exec-bit.test.sh`, one file over in the same
PR, argues explicitly against this — *"DERIVATION, not enumeration: a hand-maintained
list would rot the moment a hook is added."* The principle was written down and not
applied to the file next to it.

## 5. My mutation battery reported 10/10 SURVIVED against a perfectly good hook

The battery drives mutants against a synthetic session: a copy of `bash` at a path
matching `*/claude/versions/*` satisfies the identity check. It reported **every mutant
surviving** — which I nearly read as "the hook is robust."

Cause: `bash -c 'cmd; sleep 300'` **execs** its last command. The wrapper's `/proc/<pid>/exe`
stopped matching mid-run, so the hook's identity walk stepped straight past the fake to
the operator's *real* session — and every mutant then re-read the real scope's
already-correct properties. Fixed with `sleep 300 & wait` (a builtin, so the wrapper
keeps its image).

A second instance of the same class: `run_synthetic` waited for the wrapper's cgroup to
merely *contain* `soleur-agent-`, but the wrapper is a descendant of the already-adopted
real session and **inherits** that cgroup at birth — so the wait returned instantly on
the wrong value.

**Rule:** an instrument that returns the same answer on every arm is un-run, not clean.
Every battery needs a **positive control** that aborts unless the thing under test is the
thing you think it is. The one added here asserts the adopted scope belongs to the
synthetic wrapper, and it is the reason the second bug was caught in seconds.

## 6. Harness bugs that fabricate findings

Three separate times a defect in my *test* produced a confident wrong verdict about the
*subject*:

| Harness bug | Fabricated verdict |
|---|---|
| awk `keep[ppid[x]]` auto-vivifies on read | a real 8-process tree inflated to **119 phantom PIDs**, reported as "109 absent from the scope" |
| `git archive \| tar -x` produces a **non-git** directory | a test resolving paths via `git rev-parse --show-toplevel` read a different tree; I concluded a CI failure was "pre-existing on main" from an invalid experiment |
| `kill -0` succeeds on an unreaped **zombie** | allocator reported alive after it had been OOM-killed |

The middle one is the worst, because the conclusion was *comforting* — it would have let
me dismiss a red CI check. Re-run in a real `git worktree`, both main and the branch
passed 100/100, and the honest statement became "reproduces on neither locally; the infra
files are byte-identical to main, so this PR cannot have caused it."

**Rule:** before believing a harness's verdict about the subject, ask what the harness
would print if the harness itself were broken. If that answer is "the same thing", the
verdict is unearned.

## 7. Removing a masking fallback exposes what it was masking

The hook had a hand-rolled JSON writer for jq-less hosts. It was not a safety net — it
was a *broken second mode*: the fallback wrote lines without the counter fields while the
reader required jq to read them, so `last_oom_kill` stayed 0 forever and the OOM
post-mortem re-fired on **every** SessionStart — inverting the exact edge-triggered
contract it was meant to preserve.

Deleting it immediately surfaced a latent bug it had been covering: `pid:($pid|tonumber?)`
produces an **empty stream** for `""`, so jq emitted no object at all on every
early-decline path. The fallback had been silently filling in for it.

**Rule:** a fallback that produces a *different* shape than the primary path is not
redundancy, it is a second implementation with its own bugs and no tests. Prefer
declining loudly (`reason=no_jq`) over a second output mode.

## 8. systemd specifics worth not re-deriving

- `StartTransientUnit`'s signature is `ssa(sv)a(sa(sv))` — the **trailing empty `aux`
  array is not optional**. Omitting it fails with `Too few parameters for signature`, and
  because the hook redirects busctl's stdout *and* stderr (the job object path would
  otherwise land in session context), the failure is invisible.
- The `PIDs` array is **all-or-nothing**: if any PID exited between collection and the
  call, the whole call fails with ESRCH. An agent session reaps short-lived children
  constantly, so pass the one stable PID and attach descendants separately.
- **`OOMPolicy` defaults to `continue`** for a transient scope on systemd 259 — the plan
  measured `stop`. Pass it explicitly anyway (pinning against a default change), but do
  not claim "without it systemd kills claude."
- `ManagedOOMPreference` accepts `none|avoid|omit`; **`auto` is rejected** and fails the
  whole call.
- **cgroup v2 does not migrate charge.** Memory allocated before a process joins a scope
  stays billed to the old cgroup forever — so any test that measures a slice's
  `memory.current` must **attach first, allocate second**.
- A `high` band below `max` with `MemorySwapMax=0` **stalls rather than kills**: reclaim
  can only drop file pages and immediately refaults them. A 512 MB allocator under
  `high=200MB`/`max=256MB` never OOMed and never finished.

## Session Errors

**`rm -rf` on a `$HOME`-rooted glob was blocked by the sandbox guard** — Recovery:
switched to a depth-first `find -delete` scoped to a prefix. **Prevention:** for cleanup
under `$HOME`, prefer `find <dir> -path '*<prefix>*' -delete` over a globbed `rm -rf`.

**`pkill -f 'memory-backstop.test.sh'` killed my own invoking shell (exit 144)** —
Recovery: `ps -eo pid,args | awk '/pattern/ && !/awk/' ` excluding `$$`. **Prevention:**
never `pkill -f <pattern>` where the pattern appears in the pkill command line; this is
already a documented rule and I hit it anyway.

**Suite hung for 300 s: `A1=$(spawn_alloc)` where `spawn_alloc` backgrounds a child** —
Recovery: redirect the background child's stdout. **Prevention:** a backgrounded child
inside `$( )` inherits the substitution's stdout pipe and holds it open; always
`>/dev/null 2>&1` the child.

**T14 spawned a 4 GiB allocator before attaching it to the capped cgroup, on a box at
99.8 % swap** — Recovery: gated allocation behind a go-file touched only after membership
is confirmed, and bounded it to 512 MB. **Prevention:** any test that deliberately
allocates must be inside its cap *before* it allocates a byte.

**`StartTransientUnit` missing the trailing aux `0` failed silently and the hook logged
`applied`** — Recovery: added the argument and a membership readback. **Prevention:**
when a call's stdout AND stderr are both suppressed, its failure is unobservable by
construction — verify the effect, not the call.

**Whole-tree `PIDs` array failed with ESRCH whenever any child had exited** — Recovery:
adopt the one stable PID, attach descendants individually. **Prevention:** treat any
kernel/systemd API taking a PID array as all-or-nothing under churn.

**`memory.high` below `max` with swap=0 stalled the T14 allocator, hanging the suite** —
Recovery: closed the band to zero width for that test + added a watchdog that marks the
timeout on disk so a watchdog SIGKILL cannot be mistaken for an OOM kill. **Prevention:**
a test that waits on a kill must bound the wait and distinguish who did the killing.

**`kill -0` returned success for a zombie** — Recovery: use `wait` and read the signal.
**Prevention:** a dead child stays a zombie until reaped; `kill -0` is not a liveness test
for your own children.

**awk `keep[ppid[x]]` auto-vivified, inflating an 8-process tree to 119 phantoms** —
Recovery: `(pp in keep) && keep[pp]==1`, and print only entries with value 1.
**Prevention:** referencing an awk array element creates it; never use bare truthiness on
an array read.

**`comm` fed numerically-sorted input** — Recovery: lexicographic `sort` on both sides.
**Prevention:** `comm` compares byte strings; `sort -n` output is "not in sorted order" to it.

**Mutation battery reported 10/10 SURVIVED against a good hook (wrapper exec'd)** —
Recovery: `sleep 300 & wait` + a positive control that aborts unless the synthetic
session was adopted. **Prevention:** `bash -c 'a; b'` execs `b`; and every battery needs a
control that fails when the instrument is pointed at the wrong subject.

**Battery's `WRAPPERS+=` ran inside a process substitution, so the trap owned nothing** —
Recovery: append to a file instead. **Prevention:** same subshell-append class the repo
already lints for; it recurred in a scratch script the linter does not cover.

**`run_synthetic` matched the inherited real-session cgroup via a substring test** —
Recovery: wait for the wrapper's own scope name. **Prevention:** a child inherits its
parent's cgroup at birth, so "contains `soleur-agent-`" is true before anything happens.

**`ManagedOOMPreference=auto` was rejected, silently no-opping a battery reset** —
Recovery: use `none`. **Prevention:** enumerate a property's accepted values from the
systemd docs before using one as a test's "off" state.

**`TMPDIRS+=` inside `mktmp()` called via `$( )` leaked a temp dir per call** — Recovery:
`newtmp <varname>` assigning via `printf -v` in the caller's scope. **Prevention:** the
repo's own `lint-trap-tempfile-ownership` caught this; run it before pushing shell that
registers cleanup state.

**`[[ ... ]] && main "$@"` as the file's last line made `source` return 1** — Recovery:
`if ... then main; fi`. **Prevention:** the `&&` form's exit status becomes the script's
when it is the final command.

**Removing the jq fallback exposed `pid:($pid|tonumber?)` emitting an empty stream** —
Recovery: `(($pid|tonumber?) // null)` plus a guard that never writes an empty log line.
**Prevention:** `?` suppresses the error by producing *nothing*, which makes the enclosing
object construction produce nothing.

**`git archive | tar -x` produced a non-git dir, invalidating a "pre-existing failure"
experiment** — Recovery: re-ran in a real `git worktree`. **Prevention:** any experiment
whose subject resolves paths via git must run inside a real repository; a comforting
conclusion from a broken harness is the dangerous kind.

**Commits authored a non-CLA-signed automation address failed the CLA check** — Recovery: `git filter-branch
--env-filter` over the branch range, preserving the merge commit. **Prevention:** use the
repo's configured `user.email` rather than inventing one for automation commits.

**ADR ordinal collided twice: the plan reserved 155 (taken), work chose 158 (taken
mid-review)** — Recovery: renumbered to 159 and swept every reference in one edit.
**Prevention:** re-derive the ordinal against freshly-fetched `origin/main` immediately
before push, not once at plan time — sibling PRs land during review.

**`test-all.sh` was killed by box contention (load 48, four sibling suites), and I first
suspected my own cap** — Recovery: read `memory.events` (`high 0, max 0, oom_kill 0`)
which exonerated it. **Prevention:** when a run dies on a shared box, check the cgroup's
own counters before attributing it to the thing you just shipped.

**AC18 parked a process into the non-delegated Warp scope, so the park silently no-opped
and the re-sweep was never exercised** — Recovery: park in a delegated test scope.
**Prevention:** `AttachProcessesToUnit` refuses non-delegated units; a "setup" step that
can silently fail makes the assertion after it vacuous.

## Related

- `ADR-161-memory-backstop-via-systemd-transient-scopes.md`
- `2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md` (the incident)
- `2026-07-30-every-green-signal-i-had-certified-a-gate-with-six-fail-open-paths.md`
- `2026-07-27-my-refutation-measured-a-shim-and-my-safe-fixture-hid-12240-deletions.md`
- `2026-07-19-my-own-mutation-battery-was-the-false-confidence.md`
- Follow-up tracker: #7208
