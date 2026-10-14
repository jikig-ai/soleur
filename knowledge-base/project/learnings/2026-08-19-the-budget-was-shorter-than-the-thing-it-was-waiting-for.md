---
date: 2026-08-19
issue: 7545
pr: pending
category: workflow-patterns
tags: [test-runner, contention, advisory-lock, mutation-testing, measurement]
---

# The budget was shorter than the thing it was waiting for

#7545 was filed as "a session cannot tell before launching whether the box can absorb another full
gate", and asked for a pre-launch **decision** that declines an over-capacity run. The decision was
cut, the root cause turned out to be one constant, and the most expensive defect of the session was
in the test harness rather than the product.

## 1. The mechanism was a timeout, not a missing lock

`scripts/lib/test-contention.sh` already serialized every worktree of the repo through an advisory
lock. `TC_LOCK_TIMEOUT` was **900 s** against a **~45-minute (~2700 s)** uncontended full gate. (An
earlier draft of this file also cited "sibling holds of 3,775 / 5,787 / 5,763 s". Those runs were
*concurrent*, the figures elapsed-at-probe-time, and at most one held the lock — and citing them as
hold times makes the argument self-defeating, since it condemns 3600 too. The claim that survives is
narrower: 3600 is a bounded improvement over 900, not a value proven sufficient.)

A budget at roughly a third of the hold time **cannot serialize what it is waiting for**. It expires
by construction, `LOCK_CONTENDED_PROCEEDING` fires, and every queued run proceeds *at once*. That is
how six concurrent full gates land on one 16-core box — not because a lock is missing, but because
the lock's budget guarantees it will be waited out.

**Transferable:** before adding a mechanism to serialize something, check that the existing
mechanism's *timeout* exceeds the *hold time* of the thing it waits for. A wait budget below the
hold time is not a weak lock; it is a scheduled release of every waiter simultaneously. The tell is
that the contended banner fires *routinely* rather than rarely.

## 2. The decline was refuted by the ADR the issue rested on

The first design declined an over-capacity run with `exit 4`. Four reviewers converged against it,
and the decisive evidence was already in ADR-133: a run recorded as
`LOCK_ACQUIRED … after 616310ms` — a wait **redeemed at 616 s** behind two siblings. A `>= 1`
sibling decline refuses that exact run at t=0, converting a gate that **completed** into no coverage
at all.

The draft's "Pareto — never worse than the status quo" claim had reasoned only about the
missed-decline direction. Two further consumers it never swept: `lefthook`'s `pre-commit` hook runs
the runner, so a non-zero exit would have blocked `git commit` on any staged `.ts` while a sibling
ran; and `ship/SKILL.md` documents `rc=4` as "you are a spawned agent", whose documented remedy sets
`SOLEUR_ALLOW_FULL_GATE=1` — the exact override that re-creates the incident.

**Transferable:** when a plan cites an ADR as its *licence*, read that ADR for the datum that
**falsifies** the plan, not only the one that supports it. Here the licence and the refutation were
in the same file, four lines apart. And a "never worse" claim is a claim about *both* directions —
enumerate the direction you did not consider before writing it.

## 3. A degraded probe and a critical reading were the same number

`tc_avail_mb`, `tc_used_pct` and `tc_used_bytes` all degrade an unreadable or unparseable probe to
**`0`** — which is below every floor. So "could not read the filesystem" and "read a critically low
number" were indistinguishable, and a verdict consuming the value alone would have reported a broken
probe as a measured emergency.

The fix is a `0|1` **validity flag** promoted beside each value, with degraded readings rendering as
`?` rather than a digit, and uncertainty evaluated **per signal** so one dead probe does not suppress
a real finding from a live one.

**Transferable:** any probe with a "degrade to a sentinel number" contract silently converts *absence
of measurement* into *measurement of an extreme*. Grep for `|| { printf '0\n'; return 0; }`-shaped
fallbacks before consuming a probe in a decision, and carry validity separately from value.

## 4. The most expensive bug was a subshell increment in my own fixtures

The suite's fixture builder was called as `FX=$(make_fixture …)` — a **command substitution**, i.e.
a subshell — and used a counter to name its directory. The increment was discarded in the parent, so
every fixture landed in the same directory and **accumulated the previous arm's processes**. The
2-sibling fixture reported 5; the at-threshold tmpfs row read as contended.

This is the same trap the harness header already warned about for the `cases` counter, one construct
over. It did not fail loudly — it produced *plausible wrong numbers*, and 12 arms failed in a way
that pointed at the implementation rather than the fixtures.

**Transferable:** inside a function that will be called in `$( … )`, never carry state in a variable.
Mint uniqueness with `mktemp -d`, which works in a subshell. And when several arms fail together with
values that are *near* the expected ones rather than absent, suspect the fixture builder before the
system under test.

## 5. A hermetic suite cannot catch a "second non-atomic snapshot"

One mutation in the matrix — "have the verdict re-walk `/proc` instead of consuming the promoted
readings" — is **equivalent** against any fixed fake `/proc`: two walks over a directory nobody is
mutating return the same count. The defect it names is not a wrong number but a second snapshot that
can disagree on a *live* box, which is exactly the box no suite can fixture.

So the property was asserted where it is decidable: a structural arm grepping
`tc_capacity_line`'s body for a scan call, anchored on the call construct rather than a bare word so
a mention in a comment can neither satisfy nor break it.

**Transferable:** when a mutation row would survive as an equivalent mutant on a hermetic fixture,
say so and move the assertion to a surface where it can fail — do not leave the row in the matrix
implying coverage it does not have.

## 6. Ten review agents found what a green suite and a 24-row battery could not

The implementation reached review with 66 green assertions, a mutation battery reporting 24/24 RED,
and a green `scripts` shard. Review found **~37 findings, 10 of them P1** — and not one was
reachable by mutating the implementation, which is what the battery did. They lived in:

- **the environment it ships into.** The suite was `66/0` locally and `58/8` under `CI=1` — and it
  is registered in `test-all.sh`, which CI's required check runs. Green for the author, red on
  merge. Found by running it under `CI=1`, not by reading it.
- **the entry point, not the function.** `tc_capacity_line` consumed one `/proc` walk exactly as
  designed; the `--capacity` *branch* then walked again for the detail rows, and printed
  `CAPACITY_OK measured_runs=0` directly above three enumerated siblings. The structural arm guarding
  "one walk" grepped the function's body, so the feature's own entry point walked past its guard.
- **the axis the fixtures never varied.** No fixture crossed two thresholds at once, so the reason
  accumulator only ever ran at one member and overwriting instead of joining survived. No fixture
  asserted the *rendering* of a degraded value, so `measured_runs=0` for an unmeasurable procfs
  survived — the exact collapse the validity flags exist to prevent, one field over from the
  mutation that did catch it.
- **the suite's own exit decision.** Inserting `fails=0` before the summary printed
  `59 passed, 0 failed (66 assertions)` and exited 0. Conservation ran upstream on true counters;
  the floor read an intact `cases`. The fix is that the exit reads an **append-only** failure log,
  so silencing it means deleting evidence rather than moving a number.
- **the baseline.** AC9 compared against `origin/main`, so it self-destructs on merge into `X == X`.
  Demonstrated by pointing `origin/main` at the branch's own content with a regression injected into
  both sides: green. Now pinned to an immutable SHA.

**Transferable:** a mutation battery measures the axes it edits. Before crediting one, enumerate the
axes — SUT content, fixture shape, fixture *direction*, member cardinality, harness dispatch, stub
fidelity, the baseline's own freshness, and the environment — and say which ones it never touched.
N mutations of one shape is one mutation.

## 7. Simplification retired more findings than fixing would have

Two components caused most of the damage, and neither survived: a diff-justification report that
could not change a decision under either `TEST_GROUP` value (~7 findings), and a heartbeat that
identified the lock holder by taking `head -1` of a `/proc` walk — naming a fellow *waiter* ~83% of
the time while costing ~313 CPU-seconds and ~154,000 forks per wait, on a box whose failure mode is
fork starvation (~5 findings). Deleting the first and reducing the second to *"which lock, and how
long have I waited"* removed twelve findings without patching any of them.

**Transferable:** when review returns a long list, sort it by *component* before sorting by
severity. A component with many findings is often one that has not earned its place, and the cheapest
fix for a mechanism that cannot change a decision is deletion.

## 8. Measured, not asserted

- `TC_LOCK_TIMEOUT` raised 900 → 3600 (source: ADR-133's recorded ~2700 s baseline, **not** a fresh
  measurement — a fresh uncontended reading was unobtainable, since the box carried load 43.67 with
  two live sibling runs at implementation time, and taking one would have meant launching a seventh
  full gate onto a contended machine to measure contention). The source is stated in the addendum
  rather than left to look like a measurement.
- Relevance-gating's real ceiling: **4** gated suites against
  **170** `run_suite` registrations
  (`grep -cE '^[[:space:]]*run_suite[[:space:]]' scripts/test-all.sh`) — ~2.4%. **The command is
  published because the first draft of this line said "167" and no counting rule reproduces it**;
  review measured 165/164 and 170/169 depending on the predicate. A number without its command is
  exactly the unverifiable claim the rest of this file is about, and it was the one figure here a
  reader could check.
- Diff-justification shipped as **nothing**: it was cut on review. A report that cannot change a
  decision under either `TEST_GROUP` value is not a smaller version of the feature, it is a fifth
  hand-written path list to keep in sync — and it was already wrong on `.github/`, `CLAUDE.md` and
  four `apps/web-platform` subtrees.
- One suite run: **~190 s**, 73 assertions.

## Session Errors

Fourteen, of which nine are recurrences of classes this repo already documents. That ratio is the
finding: the rules existed and were not reached for.

1. **`iac-plan-write-guard` blocked the first plan write** on an incidental "operator runs" phrase
   co-occurring with "mount" *(forwarded from the plan phase)*. Recovery: rephrase, not the ack
   opt-out — there was no infrastructure step to acknowledge. **Prevention:** none warranted; the
   guard failing closed on an ambiguous phrase is the correct direction.
2. **`lint-guard-contract.py` read 0 mutation rows** — escaped pipes (`\|\|`) broke its table parser
   and no guard carried the field it scopes on *(forwarded)*. **Prevention:** already fixed in-session.
3. **A counter incremented inside `$( )`.** `make_fixture` was called as `FX=$(make_fixture …)`, so
   the subshell discarded the increment, every fixture landed in one directory, and arms accumulated
   the previous arm's processes. It failed as *plausible wrong numbers* (2 siblings reported as 5),
   which pointed at the implementation rather than the fixtures. **Prevention:** in any function that
   will be called in `$( )`, mint uniqueness with `mktemp -d`; never carry state in a variable.
4. **`until ! pgrep -f 'cap-battery.sh'` matched its own command line**, so the loop never
   terminated and burned a 5-minute timeout. **Prevention:** `plugins/soleur/scripts/lib/proc.sh
   list_runs` resolves ownership via `/proc/<pid>/cwd` and excludes self — use it instead of `pgrep`.
5. **The same self-match again**, in `pgrep -c -f "sleep 47"`, reporting 2 orphans where there were
   0 — nearly recording a fix as failed. **Prevention:** as #4. Twice in one session with the rule in
   view is the argument for reaching for the helper by default.
6. **A Python anchor matched inside a comment.** `s.index("tc_acquire() {")` first matches the
   string `` `tc_acquire() { :; }` `` in a comment, so the replacement truncated a pre-existing block,
   duplicated two functions, and left an unbalanced backtick that bash expanded as a command
   substitution. **Prevention:** anchor structural edits on `^`-anchored, regex-bounded matches and
   assert `count == 1`; when a file is mangled, rebuild from the last good commit rather than
   repairing in place.
7. **`cp -a .` copied `.git`**, so the `rm -rf` guardrail correctly refused to clean the sandbox.
   **Prevention:** for a suite needing a real git dir, mutate in place against a pristine backup with
   a restore trap; sandbox-copy only when the suite is git-independent.
8. **A blocked Bash call took its heredoc with it.** The denial aborted the whole call, so the
   mutator file was never written and the next call reported 8 rows NOT-APPLIED. **Prevention:**
   write files in a call separate from any gated command — the documented pattern for hook-gated `gh`
   invocations, which applies to every gated command.
9. **A grep anchored on a bare token** (`LOCK_WAITING|LOCK_ACQUIRED`) matched the suite's own
   assertion *text* rather than the runner's output, and the lock state was misread. **Prevention:**
   `cq-assert-anchor-not-bare-token` — anchor on the emitter prefix (`^\[contention\] LOCK_`).
10. **Three unguarded `$(grep …)` captures**, where a no-match exits 1, pipefail propagates, and
    `set -e` kills the suite — making the "extraction failed" branches directly below unreachable.
    Caught by `lint-shell-capture-exit` in 700ms, after ten review agents did not.
    **Prevention:** the lint already exists and is registered; run the cheap deterministic gates
    BEFORE the panel, not after.
11. **The version-skew arm was vacuous twice.** v1 drove `--capacity`, which carries its own guard;
    v2 asserted "named in the guard OR stubbed in the body", which every function satisfies by
    construction. Only mutation caught both. **Prevention:** for every new assertion, name an
    implementation that satisfies it while violating the property — and mutation-prove the fix, not
    just the original defect.
12. **A comment asserted an enumeration it had not completed.** `TC_CLEAN`'s comment said the list
    was "enumerated FROM THE SUT (`grep …`), not from memory"; that grep returns `XDG_RUNTIME_DIR`
    and `TMPDIR` and neither was in the list. **Prevention:** when a comment claims a command
    produced a list, paste the command's output into the list rather than transcribing from memory.
13. **An overstated datum, reported to the operator.** The 941s measurement was described as
    preventing a "fifth concurrent gate"; it supports ~41s of avoided overlap with one holder.
    **Prevention:** state what the datum bounds, not what it suggests — and correct it in every
    artifact, not only where it was noticed.
14. **An unreproducible figure.** "167 top-level `run_suite` registrations" matches no counting rule
    (measured 165/164 and 170/169). **Prevention:** publish the command beside any count; a number
    pinned to prose rots exactly like a citation pinned to a line number.

**Not counted as deviations:** `.claude/.rule-incidents.jsonl` shows 1,516 deny/bypass rows since
2026-08-19, dominated by fixtures (`gh pr merge 1`, `-some-project`, `${{ github.event.issue.title }}`).
These are the repo's own hook test suites, which the `scripts` shard runs — and that shard ran four
times today. They are test artifacts, not session violations.
