---
title: "My test suite reaped the live box, and every gate was green"
date: 2026-08-20
issue: 7537
pr: 7641
category: test-failures
module: scripts/orphan-process-reaper
tags: [guard-vacuity, mutation-testing, destructive-tools, /proc, review-instrument]
---

# My test suite reaped the live box, and every gate was green

## Problem

A nine-agent review found **30 findings, 12 of them P1**, in a change that was fully green: a
148-assertion behavioural suite, a 604-assertion 36-row mutation battery whose rows all reddened,
both CI shards passing, and shellcheck clean.

Almost every P1 was one of two shapes: **a guard that could not fail**, or **a record describing a
mechanism the code did not have**. Neither shape is visible to a passing suite, because a passing
suite is exactly what both produce.

## The findings worth carrying forward

Every one below was **measured** by an agent on the real box, not argued from the source.

### 1. When the subject is a destructive tool, the SUITE is a destructive tool

The end-to-end arm ran `reap` against the real `/proc` with no signal sink, no root seam, no pid
restriction, and `MIN_AGE_S=0`. The suite is registered in `scripts/test-all.sh`, so **every
full-gate run performed an unattended box-wide reap** — and twice, because the mutation battery's
unmutated control runs the suite without the skip-live flag. The `MIN_AGE_S=0` made the test's reap
*wider* than anything an operator could invoke by hand.

Measured blast radius: a planted bystander tree **one second old** would have had three processes
TERMed.

It also falsified the ADR's own sentence, "nothing invokes `reap` automatically anywhere".

**Why nobody caught it:** the arm is named after the feature (`AC40 incident trace`) rather than
after its blast radius. Every reviewer reads the name and checks whether the *feature* works.

**Generalizable:** for any suite whose subject deletes, kills, revokes, or overwrites, ask *what
does this arm do to the machine it runs on* separately from *does the feature work*. The scoping
mechanism should be the **shipped** authorization path, not a test-only bypass — then the arm
exercises the real guard instead of routing around it.

### 2. A gate can be unreachable in production and still look correct

The own-uid gate sat inside the classifier. Measured against a real `/proc` it counted **zero** —
because a foreign process's `/proc/<pid>/fd` is mode `500`, so the cheap `fd/255` pre-filter
rejected it *before* the uid gate ever ran. The gate could not fire, and removing it had **no
observable**.

Moving it into the walk as a fork-free `[[ -O ]]`, ahead of the pre-filter, took it from `0` to
`390` of `627`.

**Generalizable to any cheap-filter-then-expensive-check pipeline:** a gate placed after a filter is
only reachable for inputs the filter admits. Ask, per gate, *which inputs reach this line* — and
give it a counter, because a gate whose removal changes no output cannot be falsified by any test.

### 3. The motivating incident was a TREE of anchors, not one anchor

Every nested `bash <script>` level holds its own `fd/255`. So `git worktree remove` under a running
suite does not leave one anchor with members — it leaves a tree where **every level is an anchor**.

Measured: 7 bash + 3 python3 in one removed worktree gave `anchors=7 set_members=70 signalled=70`
for **ten distinct pids**. Seventy TERMs, seventy evidence records, the cardinality cap evaluated
against a per-anchor total of 10 while the real count was 70 (so it bounded nothing), and
children-before-anchor violated.

**Why no test saw it:** all ~40 fixtures built exactly **one** anchor. The fixture that would have
caught it described "a wrapper, a second bash, and a non-bash child" — and gave that second bash no
`fd/255`, which a real second bash running a script has.

**Generalizable:** when a suite's fixtures are all cardinality-1 on the axis the feature quantifies
over, the whole overlap/dedup/ordering class is invisible. Mutate by **adding a member**, not only
by editing one — and note that an insertion-shaped mutation is one a placement check demanding
"exactly one line changed" structurally cannot express.

### 4. Three harness rows were scored against a red baseline

The battery wrote mutant suites to a bare temp dir. The suite resolves
`REPO_ROOT="$(dirname BASH_SOURCE)/.."` and then reads `$REPO_ROOT/scripts/lib/…` and
`$REPO_ROOT/scripts/test-all.sh`, so seven assertions failed **environmentally**.

Consequence: a purely **cosmetic one-line edit — changing a banner string — was recorded as
"reddens the suite: PASS."** The three harness rows asserted nothing.

**Generalizable:** a relocated script must carry everything it resolves via `BASH_SOURCE`, and a
battery needs a **per-row control** in the worker's own layout. A single global control run from the
repo is structurally incapable of seeing a layout defect.

### 5. 36% of the suite's verdicts had no backstop

`expect_field` carried 48 of 136 assertions, and its `cases` increment lived **inside** the helper.
So a version that keeps the count and drops the verdict is byte-identical green — invisible to the
assertion floor, to the conservation check, and to the pass/fail positive control (which never
routes through it). Measured: it hid two real detector mutants.

**Generalizable:** the positive-control rule applies to **every verdict-emitting helper**, not just
`pass`/`fail`. Litmus: for each helper, *does its own counter move inside it?* If yes, the floor is
dispatched through the thing it guards.

### 6. "Fail-safe by construction" was asserted before it was true

Two of three fault-injection seams could **suppress** a refusal:

* `ORPHAN_REAPER_FORCE_EUID=1234` skipped the root refusal entirely (measured `signalled=3`), so
  `FORCE_EUID=1000 sudo -E … reap` ran as root with the box-wide guard disabled.
* `ORPHAN_REAPER_SELF_CWD_OVERRIDE=/nonexistent` emptied the key whose `-n` conjunct gated the
  anti-suicide refusal (measured `valid=1 signalled=3`).

**Generalizable:** a sentence claiming a safety property is the sentence a future reviewer trusts
*instead of* re-deriving. Make a fault-injection seam refusal-only structurally — test the real
value **independently** of the seam, so the seam can only add a refusal — rather than describing it
as refusal-only.

### 7. A non-numeric operand silently disables an arithmetic gate

`(( age < ORPHAN_REAPER_MIN_AGE_S ))` on a non-numeric operand does not abort. It **errors and
evaluates the `if` as FALSE**, skipping the branch that spares fresh processes.

Measured: `MIN_AGE_S=10m` signalled a **two-second-old** orphan while every counter on the summary
line reported a clean, valid walk. No fault-injection seam involved. `10m` and `600s` are plausible
operator spellings, and the tool's own banner invites overrides. (Bash arithmetic also expands
recursively, so an unvalidated value is an execution surface as well.)

**Generalizable:** validate every numeric seam as `^[0-9]+$` at the boundary. This is the documented
`_tc_stat_field` empty-reading fail-open one level up — there at the *reading*, here at the
*operand*.

### 8. A comment broke a guard — twice

The repo's `guard-vacuity-floor` gate reconstructs a floor block by walking back over lines matching
`^[[:space:]]*NAME=[^;]*$`. The comment written to explain `MIN_CASES` contained a **semicolon**, so
the walk-back skipped the assignment, `MIN_CASES` was unbound in the gate's mutant, and the floor
scored as one that does not fire.

Separately, several source-grep assertions were satisfiable by the prose explaining them — including
one that **passed with the entire root-refusal block deleted**, because its unanchored grep matched
the seam's own header comment and an unrelated `id -u` inside a lockfile name.

**Generalizable:** the moment a task requires both "assert X" and "document X", they collide. Anchor
every source assertion on `^[^#]*` and on something a comment cannot produce.

### 9. G3's justification was false, and the harness could not have shown it

The comment claimed the absolute-path and suffix terms excluded memfds. A real `memfd_create` reads
back as `/memfd:victim.sh (deleted)` — absolute, suffixed, `nlink 0`, regular file. It satisfied
**all four terms**.

Proven end-to-end with a positive control: pre-fix **1 anchor**, shipped **0**. The
synthesized-procfs harness structurally cannot reproduce it, because `readlink` there returns the
fixture's own path rather than the kernel's memfd name.

**Generalizable:** when a comment justifies a term by the class it excludes, construct a member of
that class and check. And know which classes your fixture strategy *cannot* express.

### 10. The hot path blew its own timeout in exactly the scenario it was written for

The anchor pass was O(anchors × pids) — the cwd-key scan, which is **anchor-independent**, ran
inside the anchor loop at ~1.11 s per anchor. Ten anchors under the real `timeout 10` call shape:
`WALL 10.01 rc=124`, twice. The probe is killed, and because path evidence is deferred to the tail,
it emits **no summary, no reap command, and no paths**. The tool goes silent at the moment it has
the most to say — and since nothing reaps automatically, the orphan set persists and every later
launch pays 10 s and learns nothing.

Hoisting the scan out of the loop fixed it. Batching the `stat` needs `%n`: a missing path emits
**no stdout row**, so positional parsing shifts every later path onto the wrong pid — failing toward
**extra** members, the direction that kills.

### 11. Instruments lied repeatedly, and every lie read as a clean answer

* A memfd proof where `os.memfd_create` was unavailable, so the process never started — "correctly
  not an anchor" measured **nothing**.
* A `sed`-built "suffix mutant" that returned before reaching the suffix test, so the discrimination
  check compared a mutant to itself.
* A shard result describing a tree that had since been edited.

**Generalizable:** run every instrument against a **known-positive** before believing a negative. An
instrument that has never been shown to produce a positive has not returned a negative.

## The review instrument itself

* **Nine agents, report-only.** With more than ~3 concurrent agents, in-place edits corrupt each
  other's reads; one agent's uncommitted edit gets attributed to a commit by another.
* **The structural-enumeration seat** (asked for a *map*, explicitly told not to rank or triage) and
  **the measure-the-live-box seat** produced findings no adversarial seat did. The enumeration seat
  found the anchor-confirmed-after-members ordering bug; the live-box seat found the 41-process
  auto-authorized set.
* **The cheap deterministic gate first.** `shellcheck -S warning` found an unused capture that was
  the fingerprint of a dropped value assertion — for one second of runtime, before any agent ran.
* **Two agents disagreed and both were right about different things.** `scripts/tmpfs-guard.sh`
  *does* carry the `exec 9>"$f" 2>/dev/null` pattern, and does *not* suffer it, because its
  `guard_log` writes to `logger` or a file and never to stderr. Present and inert there; live in a
  script that speaks on stderr. An earlier commit message of mine had overstated it as a defect in
  that file.

## Session Errors

1. **`skipped_foreign_uid` counter cut on a simplicity recommendation** *(forwarded from
   session-state.md)* — silently made mutation row M5 an equivalent mutant. Recovery: restored after
   the security review flagged it. **Prevention:** before removing a counter, grep the mutation
   battery for rows whose observable is that counter.
2. **Scratchpad directory absent, so a redirect failed and `rc=1` briefly read as a suite RED.**
   Recovery: `mkdir -p` in the same command. **Prevention:** already in `work/SKILL.md` — create the
   log destination in the command that writes it.
3. **`sed` delimiter collision** (`|` in the replacement). Recovery: switched to a python edit.
   **Prevention:** prefer a quoted-heredoc python patch over `sed` for anything containing shell
   metacharacters.
4. **Python heredoc `\'` escaping emitted a bash line with an unterminated quote** → syntax error.
   Recovery: rewrote the line by index. **Prevention:** after any generated-code patch, `bash -n`
   before running.
5. **A python patch `assert`ed after mutating `s` but before `open(...,"w")`, so an assertion failure
   left the file untouched** — a silent no-op I noticed only from an unchanged test result.
   **Prevention:** assert all anchors FIRST, then mutate, then write; or write to a temp and compare.
6. **`grep | head | cut` under `pipefail` aborted the suite** — `head` closes the pipe, `grep` takes
   SIGPIPE. Recovery: `|| true` inside the substitution. **Prevention:** documented in
   `work/SKILL.md`; hit anyway, which is why the rule needs to be at the authoring site.
7. **Sourcing `test-contention.sh` into the suite's own shell aborted the run** (it rebinds globals
   and installs traps). Recovery: source in a subshell. **Prevention:** never source a library into a
   test harness's own shell to check for a symbol.
8. **The battery's worker inherited the parent's EXIT trap and deleted the parent's work dir.**
   Recovery: moved the worker branch above the `mktemp`/`trap`. **Prevention:** a re-entrant script's
   worker branch must run before any cleanup trap is installed.
9. **11 battery rows mis-escaped or ambiguous** (`NO_MATCH` / `AMBIGUOUS`). Recovery: rewrote the row
   table as a quoted heredoc with whole-line patterns. **Prevention:** anchor mutation patterns on
   whole lines; route them through a heredoc, not bash word-splitting.
10. **5 rows went stale after the SUT restructure** — caught by the battery, which is the battery
    working. **Prevention:** none needed; this is the designed behaviour.
11. **A memfd proof was vacuous** (`os.memfd_create` unavailable, so the process never started).
    Recovery: rebuilt via `ctypes` with a positive control asserting the fixture was actually
    memfd-shaped. **Prevention:** the known-positive rule, below.
12. **A `sed`-built "suffix mutant" returned before reaching the suffix test**, so the discrimination
    check proved nothing. Recovery: replaced the whole function body. **Prevention:** verify a mutant
    reaches the code path it claims to mutate.
13. **Harness reaps misread** — exit 143 at the 2-minute default and exit 144 (SIGUSR1). Recovery:
    `setsid nohup` + an rc file. **Prevention:** documented in `work/SKILL.md`; read the rc file,
    never the notification.
14. **`MIN_CASES` off-by-one, twice** — the floor exceeded the skip-live count, so it fired on every
    mutant and the battery went falsely all-red. **Prevention:** derive the floor from a measured run
    of the mode it guards, not from the other mode's count.
15. **A semicolon in the comment explaining `MIN_CASES` broke the vacuity gate's walk-back.**
    **Prevention:** no trailing comment on a floor's threshold assignment; the reason goes above it.
16. **An AC27 `>=2` occurrence heuristic produced two false positives** (a seam with no default line;
    a seam read in arithmetic context without `$`). Recovery: switched to "read on some line other
    than the declaration". **Prevention:** count *sites*, not occurrences.
17. **Cited `#7652` as the tracking home for the exec-redirect class before verifying it.** It tracks
    a different defect. Recovery: verified with `gh issue view` before referencing.
    **Prevention:** `hr-before-asserting-github-issue-status` — it exists; apply it to peer-supplied
    issue numbers too.
18. **An agent reported "8 commits ahead of main"; re-derived as 3.** **Prevention:** re-derive every
    number an agent hands you, including from a strong agent.
19. **A shard launched before the review fixes described a tree that no longer existed.**
    **Prevention:** documented; a gate describes the tree it was launched against.
20. **Edited the tree while a shard was queued on the advisory lock, invalidating that run.**
    Recovery: killed my own run (cwd-resolved, siblings untouched), committed, relaunched.
    **Prevention:** confirm clean, then do not edit under a queued or running gate.

## Key Insight

A green suite is evidence about the assertions you wrote. A green mutation battery is evidence about
the mutations you imagined. Neither is evidence about the axes you never edited — and the axes an
author never edits are, by construction, the ones they were not thinking about.

The three instruments that found things here had **disjoint** yields: shellcheck (1 second) found a
dropped assertion; measuring the live box found a 41-process auto-authorized set that no fixture
could express; structural enumeration found an ordering bug that no adversarial seat reported. A
review that runs only one of them ships the rest.

## Tags

category: test-failures
module: scripts/orphan-process-reaper
