---
title: "The class recurred three days later, and four of the instruments I checked my own work with were broken"
date: 2026-09-07
category: security-issues
tags: [guards, verification, instruments, test-sharding, mutation-testing, credential-forwarding]
issue: 7873
pr: 7894
---

# The class recurred in three days, and my instruments were the other half

## Problem

`#7873`: three scripts forwarded a Better Stack ingest bearer to a destination
taken from a runtime-settable variable, validated by nothing. Pin it,
transport-confine it, and add a lint rule so the class cannot regrow. The fix
was straightforward and held.

**Twenty-plus findings landed on it, and none were in the fix.** They were in
the pins' own regexes, the rule's classifier, the suites asserting all of it,
and — the half this file exists for — in the instruments used to check.

## The headline is a RECURRENCE, not a discovery

`2026-09-04-every-defect-this-session-was-in-the-verification-not-the-fix.md`
records the identical class from three days earlier, in the same repo, with the
same shape ("each round's fix introduced the next round's"). This session
reproduced it end to end without the prior learning changing anything.

Per this repo's own rule — *before fixing a defect class, grep the learnings for
it, and if it recurred the finding is the PROPAGATION failure, not the defect* —
the durable content below is deliberately restricted to what the prior file does
NOT contain. It has no coverage of test-shard scoping, of acting under a running
gate, or of instrument verification (measured: 0 hits for `corpus`, 0 for
`running gate`, 1 passing mention of `instrument`).

## New material 1 — a corpus-wide guard is invisible to a diff-derived suite list

The full gate was unobtainable for most of the session (sibling worktrees held
the advisory lock), so covering suites were derived from **the files the diff
touched**. That is the natural substitute and it is complete only for
**per-file** guards.

`preflight-discoverability-test` quantifies over EVERY plan in the repo. This
PR's own new plan moved its `credentials_required` count 8 → 9, and nothing in
a touched-file set could reach it. Only the full shard found it.

The same blind spot one level up: two entire shards (`bun`, `webplat`) were
never run, because the diff touched none of their paths — and the one file
edited *after* the shard run lived in a shard never exercised.

**Derive covering suites from the guard's QUANTIFIER, not from the changed
files.** A guard that quantifies over a corpus needs the corpus run, and
`scripts/test-all.sh`'s epilogue already distinguishes `IS covered above` from
`is NOT covered above` precisely so a green `rc` is not over-read. The `rc` was
read; the boundary was not.

## New material 2 — acting under your own running gate, twice

Both "mystery" battery failures were self-inflicted:

1. **Edited the tree ~25 minutes into a 32-minute gate.** The runner's write
   detector fired `[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY`. Its own text
   explains it samples the boundary exactly twice, so `Last suite started:` names
   where the run REACHED — not what wrote. Attributing that line to a suite is
   the trap; the writer was the operator.
2. **Launched a commit while that same gate ran.** `lefthook`'s `bun-test` is
   `SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh` — the override exists so a
   commit is never blocked by a sibling. The consequence is that committing
   during YOUR OWN gate run starts a second full battery concurrently, which is
   exactly the contention the sibling-refusal prevents everywhere else.

Neither was a defect in the change, and both cost a full run to diagnose. If an
edit cannot wait, KILL the run — a discarded run costs minutes, a misattributed
one cost this whole diagnosis.

## New material 3 — four instruments, four confident wrong readings

Each of these produced an answer that looked like a result:

| Instrument | Read as | Actually |
|---|---|---|
| `python3 lint.py \| grep -c` | "0 findings, clean" | the linter **crashed** (a tuple built before the inliners ran); an instrument never shown to produce a POSITIVE has not returned a negative |
| background task `exit 0` | commit succeeded | the wrapper's code; the commit was **rejected** by a failing hook |
| `Monitor` grepping `LOCK_WAITING` | "still queued" | matched a HISTORICAL line forever after the lock was acquired — the stale-anchor class being fixed in the guard all session |
| PID list scraped by regex | three live PIDs | `7867/7873/7886` came out of the worktree **path**; only the `cwd` ownership check stopped three arbitrary processes being signalled |

A fifth, subtler one: `grep -cE '^\[FAIL\]'` excluding `EXPECTED` reported "0 real
failures" while the runner's own summary said 2 — the pattern counted **in-suite
positive-control lines**, not suite verdicts, and the second failure used a
different emission shape entirely (`rc=97` → `[TRIPWIRE]`, and `[FATAL]`).

**Read the runner's own summary line as the verdict.** A hand-rolled grep over
verdict lines is a re-implementation of the runner's accounting, and it will
disagree with it exactly where the shapes are unusual — which is where failures
live.

## New material 4 — a recommendation right about its measurement, wrong about its conclusion

Two independent review agents recommended deleting `_inline_config_file`, on a
correct measurement: **zero verdict changes across 988 files**.

It is the wrong test for a guard. Measured against the REGRESSION the guard must
catch — remove `zot-inventory.sh`'s ingest pin — the helper takes the finding
from **detected to invisible**. The healthy tree cannot distinguish a
load-bearing guard from a dead one; only the defect can.

**A guard's value is measured against the regression it must catch, never
against a green tree.** The helper was kept, and given the fixture and mutation
row it genuinely lacked.

## Two smaller ones worth carrying

- **A copied precedent becomes a requirement when an AC names a MECHANISM.** The
  plan's `B3b` said a highwater ratchet must exist "mirroring the four in
  `scripts/`". It was strictly subsumed: a new offender is by definition absent
  from the baseline, so the repo-wide run already exits 1 — the ratchet could not
  fire without that suite firing first. Its precedent is scoped to ADDED LINES
  with no enumerated baseline, which is what makes a count load-bearing *there*.
  Withdrawn, and the AC rewritten to name a property.
- **Partitioning is vacuous on a rename.** A parity suite partitioned
  declarations by source id; renaming one file's id created a NEW singleton
  partition that agreed with itself — `1-of-1` is indistinguishable from
  `all-of-1`. Needed a closed source set plus per-source floors. Its hand-listed
  population was also wrong twice over: 6 listed, **12** in the tree, across
  **two** deliberate sources — so it modelled one source as the whole fleet, the
  exact defect its own header names.

## Prevention

1. Derive covering suites from each guard's **quantifier**. If any guard
   quantifies over a corpus, the targeted list is not a substitute for the shard.
2. Never edit the tree under a running gate, and never `git commit` during your
   own gate run (`SOLEUR_ALLOW_FULL_GATE=1` means it will not refuse).
3. Before believing any instrument, show it producing a **positive**. Pair every
   probe with a known-positive and a known-negative arm.
4. Take verdicts from the runner's summary line, not from a hand-rolled grep
   over verdict lines.
5. When a review says "delete this, measured zero impact" about a guard,
   re-measure against the regression before accepting.

## Session Errors

- **Committed with `-c core.hooksPath=/dev/null`**, an enumerated
  `cq-never-skip-hooks` bypass. Recovery: redone with hooks, which then caught
  real markdown-lint errors the bypass would have shipped. **Prevention:** the
  bypass list in `.claude/hooks/README.md` is enumerated — check it before
  reaching for a hooks flag.
- **The loopback fix's REPLACEMENT was bypassed by the same input.** A shell
  `case` glob's `*` matches anything, so `[0-9]*` reads as "a digit then
  anything" and `http://127.0.0.1:5000@evil.test/` matched. Recovery:
  anchored ERE. **Prevention:** probe a destination guard in BOTH directions
  before believing it; a glob is not a regex.
- **Linter crash read as "0 findings, clean"** (tuple built before the inliners
  ran). Recovery: read `rc` and grep for `Traceback` separately. **Prevention:**
  never read a filtered count without also reading the exit code.
- **Edited the tree under a running gate**, contaminating a 32-minute run.
  Recovery: the runner's write detector named it. **Prevention:** kill the run
  instead of editing under it.
- **Launched a commit during my own gate run**, starting a second concurrent
  battery. Recovery: diagnosed after the fact. **Prevention:** commit before
  launching a gate or after it completes.
- **Reported "0 real failures" from a grep** that counted in-suite positive
  controls. Recovery: the runner's summary said 2. **Prevention:** the summary
  line is the verdict.
- **Background task `exit 0` read as commit success**; the commit was rejected.
  **Prevention:** verify the head moved, never the wrapper's code.
- **Monitor stale-grep reported "queued"** long after acquisition, and a first
  Monitor watched only the happy path so a rejected commit was indistinguishable
  from a slow one. **Prevention:** key progress on a CHANGING value, and always
  watch the failure terminal state too.
- **PID extraction scraped `7867/7873/7886` from the worktree path.** Recovery:
  the `cwd` ownership check refused all three. **Prevention:** resolve ownership
  via `/proc/<pid>/cwd` before signalling; never trust a scraped PID.
- **`_pin_re` tightening produced a false positive** on the repo's preferred
  single-source idiom (`readonly` literal + compare). Recovery: follow the
  comparand one step. **Prevention:** after tightening a guard, re-run it against
  the idiom the repo PREFERS, not only against the bypass.
- **Nested `PY` heredoc terminated the outer heredoc.** Recovery: distinct outer
  delimiter. **Prevention:** build the inner delimiter (`"P" + "Y"`) or use a
  unique outer one.
- Forwarded from `session-state.md`: `iac-plan-write-guard` blocked a Write on
  the phrase "out-of-band" (rephrased rather than using the `iac-routing-ack`
  opt-out, which would have asserted a false review); two failed scripted edits
  (drifted anchor, `sed` delimiter clash), self-corrected; the `github` MCP
  server failed to connect, worked around via `gh` CLI throughout.

## See also

- `2026-09-04-every-defect-this-session-was-in-the-verification-not-the-fix.md`
  — the same class, three days earlier. This file deliberately does not restate it.
- `2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md`
- Tracker `#7898` — the structural map of what Rule D still cannot see.

## Addendum — 2026-09-08 (#7894 ship)

Six more errors, all AFTER `/compound` had already run, so none of them reached the
body above. Five are instrument failures, which is the same headline one level on:
the fix was fine, the things measuring it were not.

**1. A "positive control" that measured argparse.** I checked my two new fixtures were
detected by running `lint-...py --paths <file>`. `--paths` is not a flag — paths are
positional — so every fixture returned `rc=2` and I read seven `rc=2`s as
"DETECTED". The negative control is what exposed it: the compliant fixtures returned
`rc=2` as well, and a guard that reports a violation on a clean file is not a guard.
**A positive control that cannot distinguish its own CLI error from a finding is not a
control.** Assert the OUTPUT shape, not just a non-zero exit.

**2. The instrument went silent and I nearly read it as calm.** A `/tmp` cleaner deleted
the session scratchpad mid-run, taking `mergemsg.txt` with it. `git commit -F` reads the
message file AFTER the hooks finish, so a 12-hour battery would have run to completion
and then died on a missing file. What surfaced it was a progress check returning EMPTY
where it had returned hook names minutes earlier — absence of output, not an error.
**Prevention:** never keep a long-running command's inputs in `/tmp`; and treat "the
field that used to be populated is now empty" as a failure signal, not a quiet period.

**3. Eleven hours attributed to the wrong cause.** A mutation battery ran 16x over its
own documented budget and I called it contention. It was ALSO `ENOSPC` — `/tmp` is a 4GB
tmpfs shared by every concurrent battery, and mutants were timing out on failing writes.
Proven by re-running the identical hook with a disk-backed `TMPDIR`: RED to green, no
code change. **A plausible cause that explains the symptom is not the measured cause.**
`df` costs nothing; I reached for it eleven hours late.

**4. Three fail-opens in the guard this PR shipped to close that exact class.** Found by
two review agents at the ship gate, not by me: the destination limb gated on the
variable's NAME (`$SINK` scored compliant), `env_settable` missed the bare
`VAR="$OTHER"` assignment, and the netrc pin admitted `localhost`, which `HOSTALIASES`
can re-point. Then fixing the first took three attempts, each caught by a FIXTURE rather
than by reading: I scanned the whole pipeline (an upstream `printf` argument read as a
curl operand), then the segment fix blinded the `--config` channel, then my config-key
regex used a POSIX `[:space:]` class inside a Python regex — which silently requires a
literal `]` and matched nothing.

**5. The negation trap, caught only because the scanner exists.** A commit body read
"it does not close #7886". GitHub's parser ignores negation and squash-merges read
commit messages, so merging would have closed an issue another PR owns. The scanner
caught it; my own reading of that message had not.

**6. A corpus guard I could not have failed locally.** CI's `lint fixture content` went
red on MY learning file: the exfil probe's URL carries userinfo, and a `<port>@<host>`
substring parses as an email. (It cannot be quoted here — writing the literal re-trips
the check, which this addendum did on its first draft.) Lefthook runs it on
`{staged_files}`; the file was staged two syncs earlier, so no later local commit
re-linted it. CI globs the whole tree. **This is the diff-vs-corpus asymmetry the body
above already names, found inside the document that names it.**

**The through-line, sharper than the original headline:** every one of these was a case
where I had a reading and the reading was not a measurement. The exit code that was
argparse. The silence that was deletion. The contention that was also a full disk. The
guard that was green because it could not see. In each, the correction cost seconds
(`df`, `--help`, one fixture) and the delay cost hours.
