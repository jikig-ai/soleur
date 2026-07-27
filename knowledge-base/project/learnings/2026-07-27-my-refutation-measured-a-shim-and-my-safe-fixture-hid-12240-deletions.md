---
title: "My refutation measured a shim, and my safe fixture hid 12,240 deletions"
date: 2026-07-27
category: test-failures
module: hooks, scripts
issues: [6992, 6991]
pr: 6998
tags: [sigpipe, pipefail, measurement, fixtures, fail-open, destructive-operations]
---

# My refutation measured a shim, and my safe fixture hid 12,240 deletions

Two guards, two issues, one PR. The engineering was routine. What was not routine
is that **the two most confident claims in the session were both wrong, and both
were wrong because of the instrument rather than the reasoning.**

## 1. A refutation is only as good as the binary it ran against

Issue #6992 filed a `pipefail` + `grep -q` SIGPIPE fail-open. The planning phase
investigated it thoroughly, measured it, and concluded **REFUTED** — the file's
producers are bash builtins, and builtins "cannot raise the race": 0/40 failures
at sizes up to 1 MB. That verdict was written into the plan as findings R1 and
H1, and it re-scoped the whole task: the seven sites the issue names were
reclassified as inert "shape hygiene", and eight *other* sites became "the live
bugs".

It was backwards. Re-measured under a pinned binary:

```bash
env -i PATH=/usr/bin:/bin bash --noprofile --norc -c '
  set -o pipefail
  big=$(printf "MATCHME\n"; head -c 131072 /dev/zero | tr "\0" "x")
  for i in $(seq 1 30); do echo "$big" | grep -q MATCHME || f=$((f+1)); done
  echo "failures=$f/30"'
# failures=30/30
```

| body | builtin `echo` false failures |
|---|---|
| ≤64 KB | 0/30 |
| 65 KB | 1/30 |
| 72 KB | 23/30 |
| ≥128 KB | **30/30** |

The onset is exactly the 64 KiB pipe buffer. Below it, `echo`'s single `write()`
completes into the buffer and the producer exits before `grep` closes anything.
Above it the write blocks, `grep -q` exits on the match, and the blocked write
returns `EPIPE`.

**Why the original measurement said zero:** in a Claude Code agent Bash session,
`grep` resolves to a **ugrep shim shell function**, and ugrep's `-q` *drains its
input*. The producer never blocks, so the race cannot occur, and it measures 0/N
at every size. The instrument silently removed the phenomenon.

That is almost certainly how this defect class survived earlier review: anyone
who checked by hand, in an agent session, got a clean result.

End-to-end on the real hook, body whose first line was `ssh root@example.com`:

| body | pre-fix DENY/30 | post-fix |
|---|---|---|
| 50 KB | 22 | 30 |
| 128 KB | **0** | 30 |
| 512 KB | **0** | 30 |

At ≥128 KB the guard **never** blocked. 38 of the repo's 1754 plan files exceed
64 KiB.

### The generalizable rule

- A measurement of a **race** must pin the binary (`env -i PATH=/usr/bin:/bin bash --noprofile --norc`). Shims, wrappers and shell functions can remove the raced condition entirely.
- A **"refuted"** result is not symmetric with a confirmed one. Confirming a race needs one positive; refuting it needs proof the instrument could have seen it. Add a positive control: something that MUST fail. `yes | grep -q y` → `141` is a two-second control that would have caught this immediately.
- The test suite now asserts `type -t grep` is `file`, and fails loudly rather than passing vacuously.

## 2. A fixture that is uniform where reality is heterogeneous proves nothing

Issue #6991's headline ask: the reaper cannot see a count-shaped leak (~15,000
artifacts of a few hundred bytes; the largest was 372 B against a 100 MB floor).
I built a pressure tier that drops the size floor under count pressure, and
validated it against a 10,000-entry synthetic fixture:

- 66 seconds, comfortably inside the 5-minute cron interval
- socket-held, open-fd-held, denylisted and nested-fresh fixtures all survived
- all 300 count-shaped leaks reclaimed

Review dry-ran the same code against the operator's **actual** `/tmp` (18,832
entries):

- **12,240 entries** cleared every gate
- only ~10,700 were the leak; the rest were authored work — `pr-body-*.md`,
  `review-bak.*`, a 12.5 MB downloaded `doppler` binary, `/tmp/.doppler/.doppler.yaml`
- the pass had **not finished after 10 minutes**
- `find -delete` on a RAM-backed tmpfs is terminal

My fixture was 10,000 instances of *one shape*. Reality was 18,832 instances of
*many*. Every safety property I asserted was true of the shape I imagined.

### And the floor I thought I had was not a floor

The design rested on an invariant I wrote into the header: *"The size floor is
REDUCED under pressure, never removed."* False. `du -sm` **rounds up**:

```bash
$ mkdir d && printf 'x%.0s' $(seq 1 300) > d/f && du -sm d
1	d
```

A 300-byte directory reports `1 MB`. Any floor at or below 1 admits every
non-empty entry. The comment asserted a control that did not exist — and it was
the justification for the entire design.

The deeper point is that this is **not tunable**. A *real* size floor excludes
the 372-byte artifacts the tier exists to catch. So any tier that reclaims a
count-shaped leak in a **shared** namespace must delete small entries, which is
exactly where the unrelated work lives. Age and size are the only value proxies
available, and neither separates a leaked artifact from an old-but-precious one.

**Disposition:** the reap tier was removed. The count signal now alarms and
stops. Re-run against the real `/tmp`: **0 would-reap**, alarm correctly naming
the 19,043-entry leak. Reclamation needs the per-run private scratch roots the
issue itself names — tracked in #7004.

### The generalizable rule

- **Dry-run a destructive change against the real target before merge**, not only against a fixture. A fixture proves the code does what you modelled; only the real target tells you what it will actually touch.
- Ask of any fixture: *what shapes can production produce that this fixture does not contain?* Uniformity is the default miss.
- When a comment states a safety invariant, verify the invariant the way an adversary would — run the actual command (`du -sm` on a 300-byte dir) rather than reasoning about what it should return.
- For a destructive operation, prefer a design whose mistakes are recoverable over one you believe is perfectly selective.

## 3. Everything else review found, compressed

All of these shipped green and were caught by the eight-agent panel:

**Tests that pin one member of a set:**
- `T1` drove 1 of the hook's **6** checks. Reverting any of the other five to the pipe form left the suite **30/30 green** — the filed bug, restored, undetected.
- Nothing asserted the `.claude/settings.json` **registration**. Reverting the matcher restored the production MultiEdit bypass with the MultiEdit test still passing. *A payload piped into a hook proves the hook handles it; it does not prove the hook is ever invoked.*

**Liveness detection that cannot see live things:**
- A unix-socket fd readlinks to `socket:[inode]`, **never its path** — so socket-held directories look idle. Fixed via `/proc/net/unix`.
- `$NF` in awk is the last **whitespace-separated** field, so a socket at `/tmp/x/sock dir/live.sock` yields `dir/live.sock`, fails the `^/` test, and is dropped — deleting a live socket-held directory. Fixed with a 7-field prefix strip.
- A file `open`+`mmap`+`close(fd)` is live but has **no fd**. It appears in `/proc/<pid>/map_files`. The canonical victim is a running JVM's `hsperfdata`, whose tmpfs mtime never advances past the first write fault.

**Parsers that misattribute:**
- `du` emits **newline-delimited** records with no NUL option, so an entry whose *name* contains a newline splits into two and the read loop attributes a **sibling's** size to it. Measured deleting a 14-byte directory because a 20 MB sibling named `<same>\nx` existed.

**Fail-open by omission:**
- `_build_fresh_top` ran inside a process substitution, so `pipefail` could not reach it. A partial walk yields an empty map, which reads as *"nothing is fresh"* and removes the age gate. Sentinel added.
- `flock` fell back to `exec 9>/dev/null` — a **shared inode**, so an unrelated flocker blocks the guard forever while it logs a false reason.

**Assertions matching their own documentation — three times in one PR:**
The AC sweep matched my header comment describing the forbidden shape; two
tmpfs-guard assertions matched the comments explaining the fix. Strip comments
before any source-body grep, or reword so the literal does not survive. This is
already `cq-assert-anchor-not-bare-token`; it recurred anyway, which suggests
the mechanical fix (strip-then-grep) beats the reminder.

**A claim about my own work that was false:**
AC-B5 asserted the test suite no longer writes to the operator's journal. It
still wrote **~232 lines per run**, because `guard_env` set the sink for only 4
of ~20 arms. I had marked it satisfied. It is now zero, verified by journal
cursor rather than by a time window.

## Session Errors

1. **Plan diagnosis inverted by a shimmed binary.** The plan's R1/R5/H1/H5 concluded the SIGPIPE race was refuted; measurement under a pinned GNU grep showed the opposite. — *Recovery:* re-measured, corrected the diagnosis, recorded both in `sweep.md`. — **Prevention:** pin the binary for any race measurement and include a positive control (`yes | grep -q y` → 141).
2. **Scripted converter mangled two line continuations**, moving `<<<` after a trailing `\`. — *Recovery:* hand-fixed both; `bash -n` on every converted file. — **Prevention:** syntax-check every file a bulk converter touches, and diff for the converter's own signature (`\ <<<`).
3. **The sweep pattern under-reported.** `\| *grep +-q` misses `-Eq`, `-iq`, `-Fq`; two live sites survived the first pass. — *Recovery:* the new drift guard caught them on its first run. — **Prevention:** enumerate flag-cluster spellings when writing a pattern over CLI invocations.
4–6. **Assertions matched their own explanatory comments, three times.** — *Recovery:* strip full-line comments before grepping; reword the remaining literal. — **Prevention:** default to strip-then-grep for any source-body assertion.
7. **`pkill -f test-all.sh` matched its own command line** and killed the invoking shell (exit 144). — *Recovery:* rebuilt the pattern so it does not appear literally. — **Prevention:** already documented in `work/SKILL.md`; it recurred because the command was typed from memory.
8. **`PRESSURE_MIN_MB=1` was not a floor** and the header asserted it was. — *Recovery:* tier removed. — **Prevention:** run the command a safety invariant depends on.
9. **AC-B5 was self-reported satisfied and was false** (~232 journal lines/run). — *Recovery:* sink defaulted in `guard_env`; verified by journal cursor. — **Prevention:** verify an AC by running its literal command, and prefer a cursor/delta over a time window.
10. **The suite raced the live cron for a machine-global lock**, so arms passed vacuously. — *Recovery:* fixture-scoped `TMPFS_GUARD_LOCKFILE`. — **Prevention:** any global mutable resource a suite touches needs a fixture-scoped seam, and the seam must be set in the shared env helper, not per-arm.
11. **T1 covered 1 of 6 checks**; 12. **nothing asserted the settings.json registration.** — *Recovery:* parametrized T1 over all six; added T1c. — **Prevention:** when a SUT has N independent members, the assertion must quantify over N.
13. **The on-disk ack applied to `Write`**, so a Write deleting the ack while adding a violation was allowed. — *Recovery:* gated to `Edit|MultiEdit`. — **Prevention:** when adding a fallback lookup, ask which tool shapes it is *sound* for.
14–19. Socket-path space; mmap-only invisibility; newline misattribution; fail-open `_FRESH_TOP`; `DRY_RUN` not covering reaper 1; `flock` `/dev/null` fallback. — *Recovery:* all fixed inline. — **Prevention:** for a delete path, enumerate every way the liveness evidence can be absent rather than false.
20. **Synthetic fixture hid the real blast radius.** — *Recovery:* dry-run against the real `/tmp`; tier removed. — **Prevention:** dry-run destructive changes against the real target before merge.
21. **`sweep.md` counts did not re-derive** (`plugins/` counted under a different scope than `scripts/`). — *Recovery:* recounted; published the command beside each number. — **Prevention:** an evidence record states the command, not just the number.
22. **A comment claimed `skill-security-scan` "denies"**; that hook always exits 0. — *Recovery:* reworded. — **Prevention:** read the header before describing a hook's consequence.
23. **Invented `TMP_BASE`/`REPO_A` in the loader test**; `--milestone 6` rejected (number vs title). — *Recovery:* used the real fixture helper and the milestone title. — **Prevention:** grep the file for its existing fixture idiom before adding an arm.

## Related

- `knowledge-base/project/specs/feat-one-shot-6992-iac-guard-sigpipe-fail-open/sweep.md` — full sweep, measurements, direction taxonomy
- `knowledge-base/project/learnings/test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md` — the prior art this PR's plan cited and then talked itself out of
- #7004 (count-shaped reclamation), #7005 (remaining sweep scope)
