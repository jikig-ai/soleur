---
title: The fake transport raced a no-op push, and the guard rows sampled one push of two
date: 2026-11-11
category: test-failures
module: apps/web-platform/test (git-data real-git suites)
tags: [flaky-test, git, sigpipe, receive-pack, mutation-testing, url-rewrite-guard, fixture-env]
issue: 9601
pr: 12655
---

# Learning: the fake transport raced a no-op push, and the guard rows sampled one push of two

## Problem

The F21 real-git row in `git-data-replication.test.ts` failed 3 times in 130 runs. Each failure showed
`Command failed: git push` with empty stderr. That put mutant kill attribution in doubt: F21 appeared in other mutants' RED lists. Separately, the new url/remote
rewrite rows killed every existing mutant, yet the review panel found two guard mutations they could not kill.

## Root cause

**The flake.** The second replicate's main push changes nothing but carries push options. Here is the sequence
(`send-pack.c`):

1. send-pack writes a flush.
2. It writes the push-option packets.
3. It writes a separate trailing flush.

receive-pack reads the first flush, finds no commands, and exits. If it exits before the client's last write, the client
gets EPIPE, which git turns into SIGPIPE: rc 141 with an empty stderr. The empty stderr does not match the production
transient-retry regex. The test's fake transport piped the client straight into a local `receive-pack`, so nothing held
the pipe open the way an ssh intermediary does.

Measured on git 2.56:

| Fake transport | Failed no-op pushes |
|---|---|
| direct pipe | 1972 / 10000 (10 copies in parallel) |
| draining wrapper | 0 / 10000 |

**The coverage gaps.** Replication pushes twice when a local rescue branch exists: first the rescue refs, then main. One
guard check precedes both pushes. The rows sampled one member of each axis:

- **Push count.** No row created a rescue branch, so the rows only ever saw one push. A guard moved below the rescue push
  (N6-MOVE) survived and leaked rescue refs into another tenant's store.
- **Key class.** Of the `url.*` keys, only `insteadOf` was planted. A guard narrowed to `insteadOf` (M-A) survived, and `pushInsteadOf` still
  pushed into B.
- **Report field.** The "no path of B in the report" check ran `JSON.stringify` over the mock calls, and
  `JSON.stringify(new Error(...))` is `{}`. It could not see `Error.message`.

## Solution

1. **Wrap receive-pack.** For pushes only, the fake splices
   `--receive-pack=sh -c 'git-receive-pack "$0"; s=$?; exec >/dev/null; cat; exit $s'`. The wrapper keeps reading after
   receive-pack exits, models the intermediary, and keeps receive-pack's exit status.
2. **Pin the splice in the argv** with a unit row (UG-FAKE). Deleting the splice leaves F21 green on almost every run,
   because the race hit 2 of 1000 serial no-op pushes, so only the argv pin sees it (mutant H-SPLICE-DROP).
3. **Widen the push rows.** Each carrier row runs with and without a rescue branch. `pushInsteadOf` gets its own row.
   Rows assert the exact op list, the exact transport argv, and that no `Error.message` contains B's path.
4. **Harden the fake.**
   - Refuse unknown verbs.
   - Refuse any argv that names a remote program, including abbreviations (git accepts `--receiv=`).
   - Set `-c protocol.ssh.allow=never` and pin `GIT_ALLOW_PROTOCOL=file` (an inherited `GIT_ALLOW_PROTOCOL` overrides
     the `-c` setting).
   - Bound each call, and put the status and signal in the error.

## Key insight

- **A fake that removes an intermediary can create a race production may never see.** When a real-git flake has empty
  stderr and rc 141, check which writes happen after the peer has already decided to exit. Model the intermediary in
  the fake, then pin the fake's argv, because a race this rare can't guard its own fix.
- **A preflight that covers a sequence needs a row where the first step of the sequence is present.** Enumerate the
  axes: how many operations the guard precedes, every key class it filters, and every field a "no leak" assertion
  reads. Then give each axis a member that would leak if the guard were moved or narrowed.

## Session Errors

1. **Planning subagent rate-limited (429).** Recovery: the work phase was resumed on "continue". Prevention: none (a
   provider limit).
2. **The first helper shape failed fixture-env-adoption.** Recovery: inject the builder. Prevention: read the guard's
   derivations before you design a helper that spawns git.
3. **The helper was edited mid-measurement loop.** Recovery: measurements.md records the split. Prevention: never edit
   a file a running measurement or seat reads. Commit, then measure on the pinned tree (route: work sharp edge).
4. **A hook blocked a commit-message path containing `$r`.** Recovery: rewrote the command. Prevention: pass commit
   messages through a quoted heredoc.
5. **A `cd` left the worktree.** Recovery: cd back. Prevention: use absolute paths. The existing worktree rule covers this.
6. **The stop hook flagged unkept commitments twice.** Recovery: did the work in the same turn. Prevention: end a paused
   turn with "Paused: <event>", never with a future "I'll".
7. **A fix-round regex refused production's `--update-shallow`, and 4 rows went red.** Recovery: switched to a
   prefix-of-option-name check, and pinned `--update-shallow` as passing. Prevention: give any new refusal a must-pass
   row built from the production argv. Review's "a fix commit is its own change" rule already covers this.
8. **Splitting `opts.exec(` and `"git",` across lines disarmed the line-based fixture-env-adoption guard.** Recovery:
   put them back on one line, with a comment, and falsified the guard (removing the builder makes it red, 26/27).
   Prevention: after reformatting a spawn site, run the guard with the builder removed. Carry-forward: make the guard
   multi-line aware (different subsystem, not filed).
9. **tsc rejected `{}` as `ProcessEnv`.** Recovery: a cast. Prevention: none (one-off).
10. **The mutant harness reset the shell's cwd.** Recovery: cd back. Prevention: none (one-off).
11. **The affected gate hit its 3000 s timeout with no verdict.** Recovery: reported the suites after the cut-off as
    unaccounted, not as passing. Prevention: the targeted suites are the evidence. Carry-forward: the gate's wall time on
    a loaded host.
12. **I wrote the gate log inside the worktree, in a directory git does not ignore.** Recovery: moved it to the
    scratchpad before anything was committed. Prevention: logs go to the scratchpad.
13. **I wrote an unmeasured raw finding count into the dedup ledger.** Recovery: corrected it before the push.
    Prevention: write only counts you derived with a command.
14. **I edited the live tree while fix-round seats ran suites on it.** Two seats saw the intermediate state. Recovery:
    the seats discarded those runs and re-ran on the pinned SHA. Prevention: hold live-tree edits until the seats return,
    or tell the seats to run suites only from a `git archive` of the pinned SHA (route: review sharp edge).
15. **My own fixes introduced false prose, and the seats caught it.** The four claims: shorter carriers masked including
    pushInsteadOf, includeIf covered, "collided", one extra sh. Recovery: corrected each. Prevention: the existing review
    rule, "check every claim the diff's prose asserts".
16. **A PR-body edit cancelled the running jobs, and they showed as `fail`.** Recovery: read each job's `conclusion`
    (`cancelled`). Prevention: in `gh pr checks`, a 1-2 s `fail` with an empty runner is a cancellation. Read
    `gh api .../jobs/<id> --jq .conclusion` before you diagnose it.

## Tags
category: test-failures
module: apps/web-platform/test
