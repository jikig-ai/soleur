---
title: "My mutation battery measured one axis, and every fixture I built to check my own work was broken"
date: 2026-08-03
category: test-failures
module: hooks
issues: [7190, 7173, 7219]
pr: 7195
tags: [mutation-testing, vacuity, fixtures, sigpipe, fail-open, adr-ordinals, measurement]
---

# My battery measured one axis, and every fixture I checked my work with was broken

## Problem

A PR whose entire thesis was *"this suite's assertions are mutation-proven"* shipped a
16-mutation battery reporting **11 survivors on `main` now caught, 0 surviving**. Twelve
review agents then found **nine survivors** the battery could not see, three of them live
security disarms at a full green 62/62 — plus three security defects in the code the PR was
fixing, one of them **introduced by the PR itself**.

Separately, five of the measurements I ran to check my own work were wrong in a way that
produced a *confident, clean-looking result*.

## The generalizable lesson

**A green mutation battery is evidence about the mutations its author imagined. Audit the
AXES it edits, not the count it reports.**

My 16 mutations were one axis in three costumes: *change a hook's exit code, or change a
file in the hook tree, then check the suite reds*. Review mutated five axes I never
touched — suite dispatch, test-harness helpers, loop cardinality, set closure, and the
unasserted slots of the helper — and nine survived.

The sharpest instance: **commenting out the 14 assertion-dispatch lines gave `rc 0,
PASS=0, FAIL=0` and printed `0/0 pass`.** `test-all.sh` branches on the exit code alone,
so CI was green with zero assertions executed — and *every* "mutation-proven" row in my PR
body was conditional on assertions running, which nothing asserted. The fix is a
`MIN_ASSERTIONS` floor. **A floor, not equality**: the count is developer-incremented, so
`-eq` turns every new assertion into a spurious failure.

The second: **`INSCOPE20` was a hardcoded literal backing 11 assertions**, and every one of
their messages printed its length ("all 20 in-scope hooks…"). Shrinking it to one member
left 62/62 with an *identical pass count* — the cardinality was a `printf` argument, not a
measured quantity. The live regression that opened: a **new hook sourcing the helper with
`|| true` — defect 2 verbatim — was invisible** to three assertion groups because it was
not in the literal. Fix: derive the set from the filesystem, assert the difference empty
in both directions, and put a non-vacuity control on the discovery itself.

**Corollary — a fixture that cannot contain the thing it looks for is not a test.** A7
guards "no payload content in telemetry" and its fixture was a payload whose only
interesting field the program emits *empty by construction*. There was nothing to leak, so
A7 could not fail. A mutation that leaked a real field value into the reason string landed
attacker text in the ledger on disk and **A7 reported PASS**. Ask of every guard: *what
input makes this go green while the thing it protects is broken?*

## Every measurement I ran to check my own work was wrong at least once

This is the part worth internalising. Five distinct instruments, five wrong readings, each
of which looked like a result:

1. **Under the 64 KiB pipe buffer, a SIGPIPE race cannot occur.** My first F1 probe padded
   to 30 KB, saw a clean deny, and I nearly recorded a real, live `rm -rf $HOME` bypass as
   *refuted*. At 131 KB and 526 KB it returned rc 0 with no decision. Always pin the real
   binary (`env -i PATH=/usr/bin:/bin`), assert `type -t grep` is `file`, and include a
   positive control (`yes | grep -q y` → 141) — **if the control does not fire, the
   measurement is void, not clean.**
2. **`E2BIG`.** The second attempt passed a 128 KB payload on argv; `jq` died with
   *Argument list too long* before the hook ever ran. Feed large fixtures from a **file**.
3. **`command -v` returns a bare name for a builtin, a function or an alias.** My jq-less
   shim did `ln -sf "$(command -v grep)"`, and in this shell `grep` is a wrapper function —
   so it created a **dangling self-referential symlink**, `grep` vanished inside the shim,
   and the conservative-deny branch reported "not firing" about code that was correct.
   Guard with `[[ "$src" == /* ]] || continue`.
4. **`env -i … command -v` cannot work** — `command` is a shell builtin, so the rebuilt
   shim came out empty and every probe returned 127. Use
   `env -i PATH=… bash -c 'command -v "$1"' _ "$b"`.
5. **A mutation that does not land reports the baseline, which reads exactly like a pass.**
   A non-vacuity check reported `32/32` against a mutation whose regex anchor never
   matched. Assert the edit landed against a **pristine backup** (`diff -q`), never against
   `HEAD` — the tree is legitimately dirty during a review pass — and treat
   baseline-identical as **UN-RUN**, never as evidence.

And a sixth, about fixture *semantics* rather than mechanics: my first padding fixture used
`git stash`, whose guard only fires inside a worktree. On a `/tmp` payload it correctly
allowed, so the case **passed for the wrong reason**. The pin only became real once it used
`rm -rf $HOME`, which denies unconditionally — the guard the bypass actually defeated.

## Three security defects the first pass missed, and one it created

- **Padding bypass (pre-existing, live).** 20 sites fed a model-controlled value into
  `grep -q` through a pipe under `set -euo pipefail`. Past the pipe buffer the producer
  takes SIGPIPE, `pipefail` promotes 141, the `if` reads false, the guard is skipped. The
  recursive-delete ownership proof, the commit-on-main gate and the stash guard were all
  evadable by **padding the command**. The guard that exists to prevent exactly this class
  scoped its pathspec to `.claude/hooks` only, so it passed green the whole time the class
  was live in the sibling harness.
- **`internal` class, totally silent (pre-existing).** A shape-program failure assigned a
  fallback nothing branched on: `rc 0`, zero bytes out, every guard disarmed, no record —
  while the ADR claimed that class failed open *loudly*.
- **Unconditional fail-open on missing jq (INTRODUCED by the fix).** `main` gave rc 127,
  undefined. My fix resolved that ambiguity **toward open**, and `rm -f /usr/bin/jq` is not
  matched by the mirror's own `rm -rf` regex — so `rm -f /usr/bin/jq` → `rm -rf $HOME` ran
  clean. **When a fix converts an undefined outcome into a defined one, ask which direction
  you defined it in.** The resolution was neither of the two obvious options: the raw
  document is still in hand when the parser is gone, so that branch now pattern-matches it
  and denies on a hit, while every repair command (`apt-get install jq`, `export PATH=…`,
  `ln -s`) still passes.

## ADR ordinals collide when a branch is in flight, and `grep -c` will not tell you

The plan's provisional ordinal (158) was taken. I renumbered to **160** — taken by a PR
that landed mid-session. Then **161** — taken by another. Landed on 162.

I nearly shipped the second collision because I read `grep -c` wrong: it returned `1` (a
match *count*), and my `|| echo "FREE"` fallback only fires when grep **fails**, so a
successful match printed the count and my eye read the fallback's absence as absence of a
collision. **Derive the next ordinal from `max(existing)+1`, never from a presence check.**

Worse, nine dangling `ADR-158 D3` citations shipped **inside the hook code**, five of them
in the agent-facing deny reason string, pointing at an unrelated ADR and at a clause label
the shipped ADR does not have. The plan prescribed a sweep — and the sweep was
*structurally incapable* of finding them: it globbed
`knowledge-base/project/{plans,specs}/feat-…-*/`, but `plans/` holds **flat files**, and it
never covered `.openhands/` at all. **A prescribed sweep command is a claim to verify, not
an instrument to trust.**

## The deny reason named an action outside the agent's action space

The mirror's refusal said *"Re-send a well-formed envelope."* The agent authors
`tool_input` values; the **runtime** assembles the envelope, the `working_dir` and the JSON
framing. The parity fixture I wrote puts the offending byte in `working_dir` — and
`guardrails.sh` is registered on *both* matchers, so on that payload it denied every tool
the agent had, with an instruction it could not follow. It loops. **When a guard emits
guidance, check the guidance names something the recipient can actually do.**

## Prevention

- Audit a battery's **axes**, not its count. Before crediting one, ask: does it mutate the
  test harness? the dispatch? the loop's cardinality? the set's closure? the slots nothing
  asserts?
- Put a floor under the assertion count. A suite that can report `0/0 pass` and exit 0 has
  no lower bound.
- Derive any set an assertion quantifies over; never hardcode it beside a message that
  prints its length.
- Give every fixture a positive control, and verify the control fires **before** reading
  the result.
- Assert every mutation landed against a pristine backup; baseline-identical is UN-RUN.
- For a SIGPIPE race: exceed 64 KiB, pin the real binary, feed from a file.
- Next ADR ordinal = `max(existing) + 1`, re-derived at ship, against a freshly fetched
  `origin/main`.

## Session Errors

1. **ADR ordinal collided three times** (158 → 160 → 161 → 162), two of them discovered
   mid-session. **Prevention:** derive from `max+1` against a fresh fetch at ship time; the
   plan's ordinal is provisional by construction.
2. **Misread `grep -c` as a free/taken signal** — a match count with a failure-only
   fallback. **Prevention:** never use a presence check to establish absence; print and read
   the count itself.
3. **Nine dangling ADR citations shipped in hook code**, five agent-facing. **Prevention:**
   run the sweep unscoped (`grep -rn --exclude-dir=.git`), and verify the prescribed glob
   can match at least one known file before trusting it.
4. **Mutation battery measured one axis.** **Prevention:** the axis audit above.
5. **Introduced an unconditional fail-open** on missing jq. **Prevention:** when a fix
   defines a previously-undefined outcome, state which direction and justify it.
6. **My own new parity assertions were vacuous** — `jq -r` on empty stdin emits nothing and
   exits 0, so a `// "none"` fallback is unreachable and every `!= "deny"` case passed
   against a nonexistent hook. **Prevention:** assert positively (`== "none"`), and pair the
   verdict with an exit code so an abort cannot read as a clean allow.
7. **Parity suite wrote real rows into the operator's live telemetry ledger** (1349 B/run,
   synthetic command text feeding the metrics aggregate). **Prevention:** every
   hook-invoking test helper sets `INCIDENTS_REPO_ROOT`; grep for helpers that do not.
8. **Suite doubled a global file leak** (40→81/run) while claiming one owning trap.
   **Prevention:** redirect `SOLEUR_SESSION_STATE_ROOT` under the suite's own tmproot.
9. **Three false comments written by me.** **Prevention:** a comment asserting a property is
   a claim; if nothing fails when it is false, it is decoration.
10. **SIGPIPE probe under the buffer, then E2BIG on argv** — the first "refuted" a live bug.
    **Prevention:** the measurement rules above.
11. **Three fixture defects** (dangling shim symlink; `env -i` + builtin; wrong guard for
    the payload). **Prevention:** verify the fixture can observe the phenomenon before
    reading its verdict.
12. **A non-vacuity check reported 32/32 on an un-run mutation.** **Prevention:** `diff -q`
    against a pristine backup.
13. **Ran a rename script during an unresolved rebase conflict**, editing files containing
    conflict markers. **Prevention:** check `git diff --name-only --diff-filter=U` before
    any scripted edit.
14. **Scratchpad reaped mid-session** (`/tmp` at 87%, cron reaper) — lost the battery.
    **Prevention:** durable artifacts go to `/var/tmp`, never `/tmp`.
15. **A review agent left an untracked `run.sh`** in the worktree root. **Prevention:**
    `git status --untracked-files=all` before staging; never `git add -A`.
