---
title: "The exit code I read as 'not encrypted' was a default errno bucket, and the redirect that captured its cause forged the same code"
date: 2026-08-04
category: security-issues
module: apps/web-platform/infra
issues: [7216, 7227, 7005]
pr: 7240
tags: [luks, exit-codes, cryptsetup, dash, posix-special-builtin, sigpipe, fail-open, destructive-branch, infra]
---

# The code I read as "not encrypted" was a default errno bucket, and my capture forged it

## Problem

`cloud-init-git-data.yml` decided whether to `luksFormat` the git-data volume with:

```sh
if ! cryptsetup isLuks "$DEV"; then
  cryptsetup luksFormat ...     # <- destroys a populated store if reached wrongly
fi
```

Issue #7216 filed the obvious half: `!` swallows 126/127, so a probe that could not *run*
takes the format arm. The fix looked mechanical — branch on the exit code instead of its
truthiness. **Three separate measurements showed the mechanical fix was wrong, and the
first draft of it re-introduced the exact bug it was closing.**

## 1. `rc=1` is a default errno bucket, not a "not LUKS" verdict

Measured on the target image's cryptsetup 2.7.0 (`UDEV BLKID KEYRING FIPS KERNEL_CAPI HW_OPAL`):

| device state | `isLuks` rc | stderr | `blkid -o value -s TYPE` |
| --- | --- | --- | --- |
| blank | 1 | *(empty)* | *(empty)* |
| real LUKS2 | 0 | — | `crypto_LUKS` |
| **LUKS2, both header JSON areas corrupted** | **1** | **empty** | **`crypto_LUKS`** |
| zero-length device | 1 | — | — |

`1` is cryptsetup's **default errno bucket**. A LUKS2 device whose header is damaged is
indistinguishable *by return code alone* from a blank volume — and `isLuks` emits nothing on
that path, so the fatal would have carried no cause either. The plan's STOP condition
("rc 1 is the only genuinely-not-LUKS") held for the cases it enumerated and was false for
the case that matters.

**The generalizable lesson: an exit code is a bucket, not a diagnosis.** Before branching
something destructive on a specific non-zero value, enumerate what *else* lands in that
bucket. Here the enumeration takes one `docker run` and it moved the answer from
"safe" to "would reformat a populated encrypted store".

`apps/web-platform/infra/workspaces-luks.tf` had already ruled on exactly this — "MUST use
the `blkid -o value -s TYPE` discriminator … NEVER `cryptsetup isLuks` — the documented
data-destroyer on a populated device" — with an escape clause that git-data was "safe only
because its host is born fresh". **That escape clause silently stopped holding** when
`git-data-cutover.sh` made this volume an rsync target. A sibling's safety rationale is a
dependency; when the premise changes, nothing re-checks the dependents.

The fix: the format arm now requires a **positive proof of blankness** (`blkid` empty), and
`blkid`'s own rc is checked so *"could not measure"* can never read as *"blank"*.

## 2. The redirect that captured the cause forged the code the branch keys on

The draft captured `isLuks` stderr with `cmd 2>>"$LOG" || _rc=$?`. Measured:

```
$ ( set -euo pipefail; _rc=0; /bin/true 2>>/proc/sys/nonexistent/x.log || _rc=$?; echo "rc=$_rc" )
rc=1
```

**`rc=1` with the command never executed.** A failed redirect and a genuinely-not-LUKS
device produce the identical value — so on a host with an unwritable `/run`, the diagnostic
plumbing would have driven the `luksFormat` arm on an encrypted store. The instrument added
to explain the failure became a source of the failure.

Fix: capture via command substitution, with the append separately tolerated, so the
redirect's fate and the command's fate are never the same variable.

**Lesson: a redirect is a command that can fail, and `cmd 2>>f || rc=$?` merges its exit
status with the command's.** Any construct that both *runs* a probe and *records* it needs
the two failure domains kept apart — otherwise the recording apparatus can synthesize the
probe's most dangerous answer.

## 3. `:` is a POSIX special builtin, so a failed redirect exits dash — and bash hides it

Per-stage truncation was written `: > "$F" 2>/dev/null || true`. The parent runcmd shell is
`/bin/sh` = dash:

| shell | form | reached the next statement? |
| --- | --- | --- |
| dash | `: > "" 2>/dev/null \|\| true` | **no — shell exited, rc=2** |
| dash | `( : > "" ) 2>/dev/null \|\| true` | yes, rc=0 |
| bash | `: > "" 2>/dev/null \|\| true` | yes, rc=0 |

A redirect failure on a **special builtin** is fatal to a POSIX shell, and neither
`2>/dev/null` nor `|| true` can catch it — the shell is gone before either applies. The
`|| true` reads as a guard and is decoration.

This is the same mechanism [2026-07-29](2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md)
recorded for `.` (source) killing dash in the `git-data-gc*.service` units. **It is worth
knowing as a class, not as two anecdotes:** dash's special builtins (`:` `.` `eval` `exec`
`export` `readonly` `set` `shift` `times` `trap` `unset`) abort the shell on a redirect or
assignment error. Wrap them in a subshell whenever the redirect target is not guaranteed
writable.

**And note which test found it.** bash tolerates all of this, so the hazard is invisible to
any test that does not run the *real* interpreter. It was caught only by
`git-data-runcmd-rehearsal.test.sh` S1, which extracts the stage and runs it under dash in
a real `ubuntu:24.04` container. A rehearsal that uses a friendlier shell than production
is not a rehearsal.

## 4. The known SIGPIPE fail-open struck again, outside the guard's pathspec

`producer | grep -q` under `set -uo pipefail` fails **open** (grep exits on match, producer
takes SIGPIPE, pipeline returns 141, the `if` takes the ELSE branch). This is documented in
[test-failures/2026-07-18](test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md),
cited in ~12 learnings, and mechanically enforced by `.claude/hooks/grep-q-pipe-guard.test.sh`.

It still shipped here — measured **31/40** on the shape and **1 RED in 10 suite runs**,
after the suite had already been asserted "129 passed, 0 failed".

The reason is structural and worth recording precisely: **the guard asserts zero over a
deliberately narrow, hand-named pathspec** (`.claude/hooks/*.sh`, `.openhands/hooks/*.sh`,
plus two individually-named files), because the pattern is a text search that would match
prose describing the bug if the glob were widened. Its own header says growth happens "by
adding a named file, never by widening a glob", and puts the remaining ~800 repo-wide sites
in **#7005**. `apps/web-platform/infra/*.test.sh` was never in scope, so the class was live
there the entire time the guard was green.

**Measured on this branch after the fix:** the four suites still carry **43 code sites** of
the forbidden shape (luks 28, rung2 8, runcmd 3, capture test 3, capture script 1). The
conversion to herestrings was scoped to the predicates that had actually flaked — which is
a defensible call under a paid-dispatch cap, but it means *these files are not at zero and
must not be added to the guard's named list yet*. Recorded on #7005 rather than filed anew.

**Lesson: a guard that asserts zero over a named pathspec is only as good as the naming, and
its green tells you nothing about the files it does not list.** When a documented class
recurs, check whether the enforcement's *scope* excluded the site before concluding the
lesson was forgotten.

## 5. Review found more defects in the guards than in the fix — three of them shipped green

Ten agents reviewed the branch. The corrections table in
`knowledge-base/project/specs/feat-one-shot-7216-7227-isluks-rc-and-bootstrap-diag/acceptance-verification.md`
runs to 11 rows; **more of them are defects in assertions this PR added than in the code it
was fixing**, and three were introduced by the *fix* pass and were green when written:

- B18 pinned a **count** of `luksFormat` occurrences — a tree with `1) : ;;` and the format
  moved to the `*)` unknown-status arm satisfied every predicate.
- B18 `(h)`/`(i)` pinned **tokens** — flipping `!=` to `==` *inverts the refusal* (blank
  volume bricked, damaged-header store formatted) and `-gt 0` → `-ge 0` breaks the wait on
  iteration 1. Both green at 128/0.
- B20 pinned the bootstrap `log()` writer but nothing pinned the **pipe**; deleting the
  `2>>"$GIT_DATA_RUNCMD_DETAIL"` append returned to the pre-#7227 state, green in two suites.

This class is already well covered — see
[2026-08-03](2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken.md)
and [2026-07-19](2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md),
and the hard rule `cq-assert-anchor-not-bare-token`. The point of repeating it here is the
**ratio**: on a PR whose subject was a destructive branch, the guards were the larger defect
surface. Budget review attention accordingly — the assertion is code, and it is code no
other assertion checks.

## Prevention

- Before branching anything destructive on a specific non-zero exit code, **enumerate the
  bucket**: what other device/host states produce this same value? One `docker run` against
  the pinned image answers it.
- Require a **positive** proof for a destructive arm (`blkid` says empty), never the absence
  of a negative — and check the discriminator's own rc so "could not measure" cannot read as
  "safe to destroy".
- Never merge a redirect's exit status into a probe's: `cmd 2>>f || rc=$?` sets `rc=1` when
  only the redirect failed. Capture by substitution and tolerate the append separately.
- Subshell-wrap POSIX **special builtins** (`:` `.` `eval` `exec` `export` `set` `trap` …)
  whenever a redirect target may be unwritable — dash exits, and neither `2>/dev/null` nor
  `|| true` intercepts it.
- Run extracted boot stages under the **production interpreter** (dash in a container), not
  bash. bash silently tolerates the whole class above.
- When a sibling module's safety rationale contains an escape clause ("safe only because
  X"), treat X as a dependency: re-check it when the topology changes.
- A zero-asserting guard's green covers only its **named** pathspec. On a recurrence, check
  scope before assuming the lesson was forgotten.

## Session Errors

1. **v1 of the fix contained the bug it was closing** — `2>>` on the probe line forged
   `rc=1` without running the command, which on an unwritable `/run` takes the format arm.
   *Recovery:* command-substitution capture with a separately-tolerated append.
   **Prevention:** never let a recording redirect share an exit status with the probe.
2. **"rc 1 is the ONLY genuinely-not-LUKS" was asserted, then refuted.** *Recovery:*
   reproduced the corrupted-header case on the pinned image; gated the format on `blkid`.
   **Prevention:** enumerate the errno bucket before branching destructively on it.
3. **B18 pinned a COUNT, not the destructive branch.** *Recovery:* pinned arm position with
   a relocation mutation. **Prevention:** `cq-assert-anchor-not-bare-token`.
4. **B18 `(h)`/`(i)` pinned TOKENS; an inverting mutation stayed green at 128/0.**
   *Recovery:* pinned operator, branch and comparison; mutation arms now perturb semantics,
   not their own anchor. **Prevention:** same rule; a mutation must not be able to satisfy
   the assertion that grades it.
5. **B20 did not pin the pipe** — deleting the detail-file append was green in both suites.
   *Recovery:* B18p added. **Prevention:** assert the data path, not only its writer.
6. **`R3(3b)(ii)` filtered `$2=="fatal"`** — bound 3 of 7 emit sites, leaving the `gc_timer`
   WARNING (the site the PR narrative names) unbound; widening it surfaced a latent parse
   defect emitting a bogus LITERAL row for a non-call. *Recovery:* widened + row emitted
   only for a real call. **Prevention:** when an assertion quantifies over "every site",
   print the set it actually bound and compare to the enumerated total.
7. **`producer | grep -q` SIGPIPE fail-open, 31/40, after the suite was asserted green.**
   *Recovery:* herestrings on the flaking predicates; 12/12 green. **Prevention:** the
   documented rule; and see §4 — 43 sites remain, recorded on #7005.
8. **Determinism was asserted before it was measured** ("129 passed, 0 failed" was true of
   the runs taken). **Prevention:** for a suite with any pipeline predicate, report N
   consecutive runs, not one.
9. **Arm 10 was satisfied by the refusal message that explains the constraint** — reverting
   the constraint left it GREEN. *Recovery:* re-anchored on the `=~` condition, demonstrated
   RED on the revert. **Prevention:** `cq-assert-anchor-not-bare-token`.
10. **`R3(2d)`'s mutation arm asserted only that its own `sed` landed** and never re-ran the
    check. *Recovery:* both arms now call one function. **Prevention:** a mutation arm must
    re-execute the predicate, not its own edit.
11. **Stale narrative shipped in the template** — "All THREE sites" after `bootstrap_err`
    was deleted, a middle-slot rationale describing routing this PR changed, and "the two
    probes above" where one exists. **Prevention:** a comment asserting a property is a
    claim; sweep comments in the same pass as the code they describe.
12. **ADR model-gap claim was wrong about its own cause** — "~2 kB, Node vs Go zlib" is
    actually a stale regex: the render module emits `replace(file(…))` 9× and
    `base64encode(file(` 0×, so all nine payloads model as 80-byte `x`-runs. **Prevention:**
    when an ADR explains a numeric gap, re-derive the number before citing the explanation.
13. **B19b/c duplicated the strictly-stronger pre-existing A28a.** *Recovery:* deleted.
    **Prevention:** grep for an existing assertion of the property before adding one.
14. **Device wait tested `-e`**, true before the kernel sets capacity; a zero-length device
    also returns rc=1, feeding error 2. *Recovery:* `-b` plus non-zero `getsize64`.
    **Prevention:** a readiness predicate on a block device must assert the property the
    consumer needs (a sized block device), not mere path existence.
15. **Container capture-server's fixed `sleep 1` readiness wait** failed `R3(3a)` under
    sibling load and read as a finding about the emitter rather than a starved fixture.
    *Recovery:* bounded poll. **Prevention:** never use a fixed sleep for fixture readiness
    on a contended box.
16. **`/tmp` (tmpfs, 4 GB) hit 100%** — 2.6 GB belonged to a different live session's
    scratchpad; one command lost its output to ENOSPC. **Prevention:** already recorded —
    durable artifacts go to `/var/tmp`, never `/tmp`.
17. **`rule-metrics-aggregate.sh` exits 5** on its orphan-rule-id gate (7 untagged
    production hook ids), so no aggregate is committable from a local compound run. Its
    write happens *before* the gate, so the partial file must be reverted or a later
    blanket `git add` stages a rejected aggregate. **Prevention:** already tracked in #6531.

## Tags
category: security-issues
module: apps/web-platform/infra
</content>
</invoke>
