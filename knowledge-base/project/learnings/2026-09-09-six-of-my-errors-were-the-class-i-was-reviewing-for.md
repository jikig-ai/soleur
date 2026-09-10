---
title: "Six of my session errors were the defect class I was reviewing for"
date: 2026-09-09
category: workflow-issues
tags: [review, verification, anchoring, instruments, vacuity, credential-confinement]
issues: [7898, 7055]
pr: 7986
---

# Six of my session errors were the defect class I was reviewing for

> Nine, by the end: the class recurred three times more AFTER this file was written — see
> errors 14, 16 and 17. Error 16 was caught by CI, not by me, on a RED I had already read
> past; error 17 is the same defect in the instrument I built to watch for it.

## Problem

A ten-agent panel reviewed a credential-confinement PR and found, among ~50
findings, three recurring shapes: assertions anchored on bare tokens that also
appear in prose, verdicts read from instruments nobody had verified, and guards
whose windows were narrower than their names.

While applying those findings I committed six instances of the same three shapes.
Not before reading the reports — *during*, in the commands written to verify them.

## The instances

**Anchored on my own comment.** Verifying the panel's claim that `cmd_verify`
sources `.env` *below* the API-base assignment, I greped for the bare token
`source "$env_file"` and took the first hit. It returned line 29, so I concluded
the source came FIRST and the vector was refuted. Line 29 was the prologue comment
*I had just written*, which quotes that exact idiom in prose to explain why the arm
is unconditional. Anchored on `^[[:space:]]*source`, the real sites are 206/445/381
and the vector is live: a repo `.env` retargets the destination and the founder's
app password follows it, with every new transport flag intact.

**Anchored on ANSI.** Mutation-proving the drift guard, I grepped vitest output for
a `^ *(Tests|Test Files) ` line and got nothing, because the line begins with an
escape byte. I nearly read "no output" as "no result". The fix was to read the exit
status, which is what a caller branches on.

**Instrument bugs, six of them.** A liveness check matching process *names* while
the script runs as `bash`, reporting the runner gone on a healthy run. A vitest
invocation with `--project unit` against a file in `unit`'s exclude list, exiting 1
on "No test files found" — which I nearly filed as a regression. A `cd` that landed
in the bare repo instead of the worktree. A trailing-newline bug that printed a
false DELTA for every file in a shellcheck comparison. A Python edit that asserted
its second anchor *after* mutating the string, so the write never happened while the
run reported success. A self-test inserted above the function it calls, so it
invoked an undefined function and fired its own FATAL against a healthy tree.

## Key insight

**The reviewer's instruments are not covered by the review.** Every defect-class
rule in this repo is written about the code under review. None of them attach to the
commands the reviewer types to check that code — and those commands are written
fast, under the belief that they are bookkeeping rather than authorship. That is the
same belief that makes a fix PR's *new assertions* the least-audited part of it.

The asymmetry that makes this expensive: a broken instrument does not error. It
*answers*. A search returns a line, a process probe returns a count, a runner
returns an exit code — each arrives already shaped like a result, and the wrong ones
are indistinguishable from the right ones without a second check. Five of my six
instrument bugs produced a confident wrong reading rather than a failure, and two of
them (the comment anchor, the ANSI anchor) would have REFUTED a correct panel
finding had I trusted them.

## Prevention

Before reading any instrument's verdict, run it against a case whose answer you
already know. A search that must match something, a probe that must fail. An
instrument that has never been shown to produce a positive has not returned a
negative — it has returned silence, and silence is not a measurement.

Specifically:

- **Anchor on syntax, and check what else the file contains.** The moment a task
  requires both "assert X" and "document X", they collide. Anchor on
  `^[[:space:]]*<code>`, never a bare token, and re-read the hit before concluding
  from it.
- **Read exit status, never coloured output.** Any assertion anchored on a runner's
  formatted line is unmatchable the moment it is coloured.
- **A wrong flag is a broken instrument, not a finding.** Before recording a red,
  ask whether the command could have produced that red for a reason unrelated to the
  subject — a wrong project selector, a missing fixture, a CWD outside the tree.
- **Assert an edit landed before reporting it.** A guarded string-replace that
  throws after mutating its buffer writes nothing and says nothing.

## Session Errors

1. **Planning subagent died on a session rate limit (429)** mid-edit, never emitting
   its Session Summary. Recovery: one-shot's plan-artifact-recovery contract — the
   on-disk plan carried `## Acceptance Criteria`, so planning had finished and was
   not re-spent. **Prevention:** none needed; the contract worked as written.
2. **AC4 was a vacuous pass** — `OK: 0 scanned file(s)`, exit 0, because `--changed`
   diffs committed state and the work was uncommitted. **Prevention:** AC4 amended to
   require a non-zero scanned count, mirroring AC1's existing guard against exactly
   this zero-scan trap.
3. **A process-liveness probe matched nothing** because it keyed on the script name
   while the process name is `bash`. **Prevention:** use
   `plugins/soleur/scripts/lib/proc.sh list_runs`, which resolves ownership through
   `/proc/<pid>/cwd`; it already exists and I did not reach for it.
4. **vitest `--project unit` on an excluded file** exited 1 on "No test files found".
   **Prevention:** when a suite reds, check the runner found files at all before
   treating the red as a subject failure.
5. **CWD drifted into the bare repo** on a relative `cd`. **Prevention:** absolute
   paths, or `cd <worktree> && cmd` in one call.
6. **Verification search matched my own prologue comment** (detailed above).
   **Prevention:** anchor on `^[[:space:]]*source`, not the bare token.
7. **Shell-quoting error** in an inline proof. **Prevention:** put multi-quote proofs
   in a file with a quoted heredoc.
8. **Trailing-newline bug** made every file a false DELTA in a shellcheck diff.
   **Prevention:** compare with `diff` over sorted extractions, not shell string
   equality on command output.
9. **Search anchored on ANSI-coloured output** (detailed above). **Prevention:** read
   the exit status; strip ANSI before any text assertion.
10. **Python replace asserted its second anchor after mutating the buffer**, so the
    file was never written while the run printed success. **Prevention:** assert all
    anchors before the first mutation.
11. **Self-test inserted above its function definition** — called an undefined
    function, fired its own FATAL on a healthy tree. **Prevention:** a new control
    that fails on a known-good tree is a bug in the control; verify the control's
    green case before trusting its red.
12. **A probe's CWD moved to a scratch dir**, breaking fixture resolution → exit 2
    read as a floor failure. **Prevention:** when relocating a probe, carry
    everything it resolves relative to its CWD.
13. **A process-kill guardrail denied a self-matching pattern.** One-off; the
    guardrail was right and named the correct alternative.
14. **A verification fixture failed a format check before reaching the subject.**
    Re-verifying AC21 after my own edits, the probe returned EMPTY output for all four
    message arms and I briefly read that as the arms being broken. The cause was the
    fixture: a placeholder `DISCORD_BOT_TOKEN=x` fails the script's
    `base64.base64.base64` format validation and exits before curl is ever invoked.
    With a correctly-shaped synthetic token all four arms emit distinct markers.
    **Prevention:** when a probe returns nothing, first ask whether the subject was
    reached at all — an empty result is "the instrument did not get there" at least as
    often as "the subject produced nothing".

    Recorded because of WHEN it happened: after this learning was written and committed,
    in the session it documents. Knowing the class does not prevent it — which is the
    argument for the mechanical habit (run the instrument against a case whose answer you
    know) over the intention to be careful.
15. **This learning file could not be written via a shell heredoc**, because its own
    text describes the pattern that guardrail blocks — the command was denied for
    quoting the thing it documents. Written with the Write tool instead.
    **Prevention:** none warranted; it is the "documenting X collides with asserting
    X" class one level up, and the guardrail behaved correctly. Worth knowing that
    prose about a blocked construct is itself a blocked construct in `bash -c`.
16. **I explained an aggregate's RED from the suites I already knew about.** The battery's
    `plugins/soleur` aggregate failed; I attributed it to the two suites I had just fixed and
    wrote "the aggregate rolls up two of those". It rolled up THREE. The third —
    `scratch-path-collision`, reddened by a literal `/tmp/attacker-ca.pem` I had written into
    seven prologue comments — sat at line 9214 of the log I had already read. I then verified
    the two suites INDIVIDUALLY and never re-ran the aggregate, so nothing in my verification
    could have surfaced the one I had not enumerated. CI found it.
    **Prevention:** an aggregate's RED is a claim about a SET. Enumerate the set from the log
    (`grep '(fail)'`), never from the members you can already name, and re-run the AGGREGATE to
    confirm green — a green member is not a green aggregate. This is the same shape as errors 6
    and 9 (an instrument that answers rather than errors), applied to my own triage prose.

    Note the collision that produced it: the literal path existed only to DOCUMENT a TLS-MITM
    threat, and the guard forbidding literal `/tmp` paths cannot tell a prescription from an
    illustration. That is the third instance this session of "documenting X collides with
    asserting X" (errors 6 and 15). The fix removed the literal rather than widening the
    allowlist — and doing so also repaired a false claim, since the comment asserted it
    "matches the line in `scripts/betterstack-query.sh`", which uses no literal path at all.
17. **My own merge poll exited on a field it never verified.** I wrote a Monitor whose `DIRTY`
    arm stopped the poll, because that is what ship's own arm does. GitHub reported `DIRTY` four
    times on this PR and **three were stale cache** — `git merge-tree --write-tree` returned rc=0
    and `origin/main` matched the remote SHA exactly, so the branch was merely BEHIND. The poll
    halted on noise, and the canonical recovery tool `sync-pr-behind.sh` no-ops on that state
    (it keys strictly on `BEHIND`), so the documented path stalls exactly when a fast-moving
    `main` is the reason you reached for it. Fixed by verifying with `merge-tree` before acting:
    rc=0 → treat as BEHIND and sync; rc≠0 → real conflict. The verified arm then auto-recovered
    the next two occurrences unattended. Filed on #7472, which owns this property.
    **Prevention:** `mergeStateStatus` is a cache, not a measurement. Before branching on any
    remote status field, ask what local command decides the same question, and run that. The
    generalisation of errors 6, 9 and 16: prefer the instrument that EXECUTES over the one that
    REPORTS.

    Worth stating plainly, because it is the session's actual through-line: of the four times I
    suspected a claim and measured it, **three times the claim was right and my instrument was
    wrong** — a skill count of five that was six (I had excluded `*test*`, and the sixth skill is
    named `test-browser`), a file count of eighteen that was seventeen (I had not excluded
    `knowledge-base/`), and a `DIRTY` that was clean. Had I "corrected" any of them I would have
    written a false statement into a security document while believing I was fixing one. The
    rule that survives: when a measurement contradicts a written claim, suspect the measurement
    first — it is younger, and it was written in a hurry.
