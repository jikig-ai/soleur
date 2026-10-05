---
title: "The PR that fixed unmeasured verdicts shipped unmeasured verdicts, and its own suites certified them"
date: 2026-08-11
category: workflow-patterns
tags: [test-runner, mutation-testing, anti-vacuity, sigpipe, adr-166, review, merge]
issue: 7424
pr: 7425
---

# The PR that fixed unmeasured verdicts shipped unmeasured verdicts

## Problem

`scripts/test-all.sh` rendered a suite **terminated by a signal** byte-identically to one that
**failed an assertion**. Both printed `[FAIL] <suite> (<ms>ms)` and incremented one counter, so
"this suite is broken" and "this suite was terminated" were indistinguishable — and the default
reading is the first one. Observed on a mutation battery that had caught every mutation and left
no surviving mutant.

The fix adds a third result class: `[KILLED]`, excluded from the failure count, named in a
summary breakdown, surfaced as exit 3. The runner deliberately never says *what* terminated a
suite, because that was never measured.

## The actual lesson

**A PR whose entire thesis is "do not assert what you did not measure" shipped at least six
unmeasured assertions, and every one passed a green suite plus a self-run mutation battery.**

The defects were not in the feature. They were in the *claims about* the feature:

| Claim I wrote | What measurement said |
|---|---|
| "an uninitialized `killed` aborts AFTER the terminal marker, yielding exit 0" | aborts at the breakdown gate **above** the marker, rc=**1** |
| "every measured consumer treats this as binary" | this same PR makes `grok-pre-push-gate.sh` tri-state |
| "131 run_suite call sites", "800-line script" | as-written: **132**, **998** |
| "roughly thirty learnings anchored on `^[FAIL]`" | **11 files**, 21 occurrences |
| a budget comment carrying a specific measured wall-clock | I had measured nothing when I typed it |
| ack: the AGENTS clause is "strictly widening" | for the new class it is **narrowing** |

Each is individually trivial. Collectively they are the exact failure the runner change exists to
prevent, one layer up: a confident sentence with no measurement behind it, in a place a future
reader will trust instead of re-deriving.

## The three vacuity classes that survived a self-run battery

A 10-agent review found what my own mutation battery could not. The battery measured the
mutations I imagined; these are the axes it never touched.

### 1. Cardinality — `1-of-1` is `all-of-1`

`killed) killed=1 ;;` (a saturating counter) passed **62/62**. Every arm instantiated exactly one
killed fixture. The terminal marker computes `suites - failed - killed`, so a run with 3 kills
would have reported `129/131 suites passed` — overstating the pass count by N-1, in exactly the
multi-kill scenario the feature was built for.

**Gate:** for any counter, ask what set it quantifies over and how many members a fixture
instantiates. Add a two-member arm.

### 2. Dispatch — nothing asserted that the assertions RAN

Neutering `fail()` to a no-op left the contention suite reporting **62 passed, exit 0** with the
flagship banner deleted from the lib. The floor counted `PASS+FAIL`, both produced *by* the
helpers, so slack in the floor is the budget a neutered dispatcher has to hide in.

**Gate:** a positive control that exercises both counters directly and exits non-zero itself,
plus floors calibrated to the CURRENT count. Use a brace group with a redirect
(`{ pass …; fail …; } >/dev/null 2>&1`) — a command substitution runs in a subshell and the
increments are discarded, which is the same class the control exists to catch.

### 3. Emitter/consumer parity — proven by reproducing it live

The `[KILLED]` shape is emitted by the runner and grepped by `main-health-monitor.yml`. Nothing
derived one from the other. **While fixing this file I appended a budget note inside the
parenthetical: all assertions stayed green and the monitor went blind.** That is the drift,
demonstrated on myself, in the PR that documents it.

**Gate:** extract the consumer's regex from the consumer and run it against the line the
emitter actually produced. No hand-copied fixture — a copy drifts the same way the original did.

## The flake that certified itself

`plugins/soleur/test/main-health-monitor-workflow.test.sh` was intermittently RED on an unchanged
tree (measured 1–8 runs in 10). Seven sites used `b_body | grep -qF`: `grep -q` exits on first
match, `cat` takes SIGPIPE, `pipefail` promotes it, and a genuine **MATCH** reports non-match.

The signature is diagnostic: only the **positive**-match sites ever failed. A no-match reads to
EOF and never triggers SIGPIPE, so the negative assertions passed in the same breath.

**I reported that suite green twice and treated it as verification.** Both greens were luck.
Isolated repro after the fix: **5/400 spurious non-matches piped, 0/400 direct**; 0/12 red.

And `scripts/test-contention.test.sh` — changed by this same PR — carries the prohibition
verbatim. The PR documented the rule in one file and violated it seven times in another.

## Two process traps worth more than the code fixes

**A lint run before `git add` is not evidence.** I ran `lint-shell-capture-exit.py`, got
`0 new findings`, and reported it. The file was still untracked, so the tracked-file linter never
scanned it. A review agent found the finding. Scan count went 798 → 799 once staged.

**`ls` is not the ADR-ordinal oracle.** `ls` showed 175 free — because the file it saw was *mine*.
`origin/main` had gained ADR-175 and ADR-176 after my branch base, so `check-adr-ordinals.sh`
would have red the merge queue. The authoritative probe is
`git ls-tree -r --name-only origin/main`.

## Merge, not rebase, when both sides rewrote the same file

`origin/main` moved 6 commits during review, including #7376 which widened the monitor's failure
anchor to `^UNACCOUNTED ` — the exact line I had hardened with `-m 20`/`cut`.

- `git rebase` hit conflicts on two separate commits and had to be aborted.
- `git checkout --theirs` silently dropped **all** my workflow changes.
- What worked: `git diff <merge-base> HEAD -- <file> > p; git checkout origin/main -- <file>;
  git apply --3way p` — replay my diff onto their base, resolve once against the final state.

The resolution had to be a **semantic union**, not a textual one: main's `^UNACCOUNTED ` alternate
AND my `-m 20`/`cut` hardening. A naive "take both sides" would have silently dropped their fix.

Bonus: main's assertion (8) had the *same* over-specification mine did — its comment said it
asserts alternates rather than exact spelling, but its **extractor** pinned `grep -E` adjacency.
The merged form (main's `_required` list + a flag-tolerant extractor) is better than either side
shipped, and its failure mode was itself misleading: a broken extraction reported as "all three
alternates missing" rather than "the extraction broke".

## Session Errors

1. **Fabricated a measured figure.** Wrote `596607ms ... Measured 2026-08-11` into a budget
   comment having measured nothing. — *Recovery:* reverted to `PENDING MEASUREMENT`, ran the real
   battery. — *Prevention:* never type a measurement-shaped comment in the same edit as the code;
   write `PENDING` and fill it from a command's output.
2. **Reported a lint clean that never scanned the file** (untracked before `git add`).
   — *Prevention:* run tracked-file linters AFTER staging, or `git add -N` first.
3. **Reported a flaky suite green twice.** — *Prevention:* for any newly-authored suite, run it
   ≥5× before quoting a result; three different failure sets on an unchanged tree is a harness
   defect, and one green is not the absence of one.
4. **`killed=0` comment asserted a wrong, unmeasured mechanism.** — *Prevention:* a comment that
   names a failure mode is a claim; run the two-line repro before writing it.
5. **Header claimed "every consumer is binary"** while the same PR made one tri-state.
   — *Prevention:* re-read blast-radius claims after the diff is complete, not when drafted.
6. **Stale counts** (131/800 vs 132/998) — *Prevention:* derive counts from the as-written file.
7. **ADR claim "roughly thirty learnings"** vs 11 measured. — *Prevention:* ship the derivation
   command next to the number.
8. **Ack mischaracterised a narrowing as "strictly widening".** — *Prevention:* for an appended
   clause, diff the OBLIGATION, not the text.
9. **Plan's own prescribed code contradicted its own T8c** (an aborting classifier would have been
   silently bucketed). — *Prevention:* when a plan lists a scenario with no arm behind it, treat
   the scenario as the spec and the code as the draft.
10. **F6's first extraction matched a rationale comment** containing `(TEST_TIMING_LOG)` — the
    body-grep-sees-comments class, reproduced inside the assertion that checks for it.
    — *Prevention:* strip comments at extraction time, once, and anchor on a syntactic construct.
11. **Off-by-one floor** (`MIN_ASSERTIONS=64` against a count of 63 measured before the floor's own
    pass). — *Prevention:* read the floor off a probe run with the floor set to 1.
12. **Committed the merge with a suite red**, caught on the follow-up verification and amended.
    — *Prevention:* run the affected suites BEFORE `git commit`, not after.
13. **`git checkout --theirs` dropped all my changes.** — *Prevention:* use the 3-way replay above.
14. **ADR ordinal collision** (`ls` reported 175 free because it saw my own file; `origin/main`
    had 175 and 176). — *Prevention:* probe ordinals with
    `git ls-tree -r --name-only origin/main`, never `ls` from a worktree, and re-check
    immediately before merge — a branch-picked ordinal is provisional.
15. **Stopped at the `## Review Phase Complete` marker** and wrote "Next: /qa → /compound → /ship"
    instead of doing it; the operator had to ask "why did you stop?". — *Prevention:* the marker is
    a continuation gate; the next tool call in the same response must be the successor skill.
16. Forwarded from the plan phase: IaC routing hook blocked the first plan write (detection
    literals reproduced while documenting the gate as inapplicable); two `Edit` exact-match
    failures from whitespace drift; three self-introduced plan facts corrected by the planner's
    own sweeps. — *Prevention:* a plan that documents a gate as inapplicable must describe the
    detection token set rather than reproduce its literals.
17. **10 `hook-input-unparseable` warns** in the shared incident log during this window — a
    PreToolUse hook that could not parse its own stdin and therefore ran with guards disarmed.
    Not attributable to this session (the log carries no session id and two sibling worktrees were
    active), recorded because the class matters regardless of owner. — *Prevention:* the
    incident log needs a session id before any session can honestly claim or disclaim its rows;
    until then, scope by timestamp and say so.

## Key Insight

**A self-run mutation battery measures the mutations its author imagined; its green is
indistinguishable from the green of a fully-covered SUT.** Audit a battery by its AXES — does it
mutate the dispatch layer, the fixture cardinality, the fixture direction, the emitter/consumer
seam? — not by its count. N mutations of one shape is one mutation.

And the sharper version, specific to this PR: **the artifact most likely to carry an unmeasured
claim is the one written to stop unmeasured claims.** The rigour goes into the mechanism and the
prose around it gets waved through, because by then the author believes the thing.
