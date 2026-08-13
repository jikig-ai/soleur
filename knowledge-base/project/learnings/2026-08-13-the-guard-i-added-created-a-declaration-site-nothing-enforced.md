---
title: "The guard I added created a sixth declaration site, and nothing enforced it"
date: 2026-08-13
category: best-practices
module: scripts/test-all.sh
issue: 7494
pr: 7495
tags: [guards, mutation-testing, vacuity, test-gates, measurement]
---

# The guard I added created a sixth declaration site, and nothing enforced it

## Problem

PR #7495 extended ADR-181's "relevance decline" mechanism in `scripts/test-all.sh` from two gated
suites to four. The implementation was TDD'd, mutation-proven 11/11, green on a 303-suite local
gate, clean on shellcheck and on the repo's own shell-capture linter, and satisfied all six
acceptance criteria.

An 8-agent review panel then found **30 issues, two of them P1 — and every one of them was inside a
guard the PR itself had added.** Not one was in the gating logic the PR existed to ship.

## The two P1s

**1. A new registration table became a declaration site that nothing checked.**

To stop the gate harness from naming two suites while four existed, I introduced a `GATED` table and
drove every assertion from it. That is the right move, and it silently created a *sixth* place a
gated suite must be declared. I guarded it with `if [[ "${#GATED[@]}" -lt 4 ]]` and wrote a comment
saying a missing entry "reds via the derived floor in `lint-orphan-test-suites.sh`".

It does not. That floor compares `RELEVANCE_ARRAYS` against the runner and never reads `GATED`. So a
fifth gate added by following my own new `HOW TO ADD A RELEVANCE GATE` block **verbatim** left the
linter green, the harness green (5 ≥ 4), and every behavioural arm quantifying over 4 of 5 — while
`MIN_ASSERTIONS` shrank in lockstep, because it derives from `${#GATED[@]}`.

That is verbatim the defect the table was introduced to remove, reproduced one level up, under a
comment asserting it could not happen. **Three agents found it independently**, by three different
routes (structural enumeration, simplification, anchoring analysis).

**2. A decline was asserted by its TEXT and never by its COUNT.**

ADR-181's whole thesis is that a decline is a *counted verdict, not an absence*. My harness asserted
`grep -qF "[skip] <label> (relevance)"` per suite. Replacing `skip_suite` with bare `echo`s that
reproduce its output byte-for-byte left the suite at **99/0 green** while the denominator went
303 → 302 and `skipped` 5 → 4.

The behavioural denominator arms *did* exist — and every one of them runs under
`SOLEUR_TEST_FORCE_ALL=1`, so they only ever measured the **infra** gate. The four suites the PR was
about had no denominator coverage at all.

## Key insight

**When a PR's deliverable is a guard, its defects live in the guard and fail OPEN.** A bug in
guarded code errors; a bug in the guard certifies broken-as-fine. That makes a guard PR strictly
more dangerous than a feature PR, and it makes the author's own green mutation battery the least
reliable signal available — a battery measures the mutations its author imagined.

Three concrete corollaries, each measured here:

- **A floor derived from its own subject is a tautology.** `MIN_ASSERTIONS` derives `ELEM_TOTAL`
  from the arrays the element loop walks, so trimming an array removes one observed assertion *and*
  one unit of floor. Completeness for a set has to be answered by a consumer that reads the set
  independently — here, the linter.
- **A `grep` on the SUT's source pins SPELLING, not participation.** Both my "source anchors" stayed
  green when the *assignment target one line above them* was renamed — the command was still spelled
  there, and had stopped feeding anything. No fixture arm can ever catch this, by construction: the
  sandbox seam replaces the blob wholesale. The fix was an arm that drives **real git state** (a
  throwaway repo with a `git mv` and an untracked file) through the extracted assembly.
- **Ask what a new table is guarded *against*, not whether it is guarded.** `-lt 4` guards vacuity
  (the table is not empty). It does not guard registration (the table matches reality). Deriving the
  expected **array names** from the artifact under test and comparing sets guards both, and also
  catches a substitution that any cardinality check is blind to.

## Measurement lessons, same session

- **Measure the remedy — then measure the correction too.** The plan prescribed
  `grep -cE '_diff_touches "\$\{[A-Z_]+\[@\]\}"'`. Run, it counted **3 of 4** gates:
  `C4_PRODUCER_PATHS` carries a digit. I fixed the class to `[A-Z0-9_]+` — and review found *that*
  still missed `${NAME[@]:-}`, the `set -u`-safe form this repo mandates elsewhere. Same failure,
  one idiom over. Both under-count `want`, so a **shorter** registry satisfies the floor and the
  unseen gate is the one that rots.
- **A wall-clock figure in a filed issue is a claim, not a fact.** #7494 quoted 429 s and 95 s.
  Re-measured on an unchanged tree: 23/34/91 s and 163/205 s, with two sibling `test-all.sh` runs
  active. The spread exceeds the effect and the deviation runs in **both directions**, so the machine
  cannot resolve it. The justification moved to the **skip rate** — a deterministic `git log` replay
  load cannot touch — and the `~465 s/run` headline was withdrawn from every shipped artifact.
- **Anchor a replay to a SHA.** `origin/main` is a moving window: the same recipe returned 96%/56%
  at `fcae560b4` and 95%/51% four commits later. Without the anchor a reader cannot distinguish "the
  predicate rotted" from "the window moved".
- **A predicate is a claim about a dependency set, and `git ls-files` hides in suites you did not
  read.** `GITHUB_SCRIPTS_SUITE_PATHS` missed `test-no-at-mention-credfile-footgun.sh`, which scans
  `plugins/soleur/{skills,agents,commands,docs,hooks}` on the real tree. A diff touching
  `plugins/soleur/skills/preflight/SKILL.md` **declined** it — and that guard exists because a
  documentation example in exactly that file class leaked an operator's live root token (#6830).
  Declared at a deliberate **56% → 15%** skip-rate cost: a slower local loop is recoverable, a
  credential-footgun token in a transcript is not.

## Solution

- Registration floor in the harness deriving expected **array names** from `$TARGET` and comparing
  sets, with a non-vacuity floor on the extraction itself.
- Counted-verdict assertion (`skipped == ${#GATED[@]} + 1`) plus a cross-arm denominator comparison.
- Real-git-state arm replacing spelling-based source anchors.
- `pass()`/`fail()` positive control — a no-op `fail()` was a 99/0 green oracle.
- Per-array cardinality floors, `REQUIRED_RUNNERS` and primary-glob cardinality guards, and a
  self-inclusion check for the data file (the HOW-TO's "AND this file" clause was enforced by
  nothing, and it is what AC5's demonstration rests on).
- Force-all lever scoped to relevance declines: gated on `skipped`, it promised to recover a suite
  it cannot force, and obeying it re-printed it verbatim — advice that does not terminate.

**Round-2 mutation battery: 14/14**, targeting only the guards the review pass added. A
review-driven fix is exactly as unpinned as the blind spot it closes.

## Session Errors

1. **Planning subagent's own draft carried a blocking defect** — a `skip_suite` pairing check
   anchored on the battery *file path* while `skip_suite` takes a *display label*; they differ for
   both existing arrays. Caught in-session by plan review (4 of 5 reviewers, independently).
   **Prevention:** run a proposed check before defending it — it would have reddened a clean tree.
2. **Planning subagent asserted lefthook runs the linter**; `grep -c orphan lefthook.yml` is 0.
   **Prevention:** an Observability block's enforcement route is a claim to grep.
3. **`git log --merges` returned nothing** on this squash-merge repo, so the first skip-rate
   measurement silently sampled zero commits. **Prevention:** assert non-zero cardinality before
   reading any replay result.
4. **The plan's dispatch-floor regex counted 3 of 4 gates** (digit in an array name), and the
   correction still missed `${NAME[@]:-}`. **Prevention:** measure the remedy, then measure the
   correction; enumerate the shapes rather than alternating the two you thought of.
5. **`want=$(grep -c …)` aborted the linter under `set -e`** in exactly the zero-gate case the floor
   exists to catch. Found by `lint-shell-capture-exit.py` in the full gate — the only real failure
   in the first dogfood run. **Prevention:** it is already a repo lint; run it before pushing.
6. **AC3's literal command is unsatisfiable by construction** — the suite captures the producer's
   markers into shell variables, so they never reach stdout. **Prevention:** run an AC's literal
   command when writing it; amend explicitly rather than satisfying a looser variant.
7. **My AC2 grep tripped on my own comment** naming the two identifiers it asserts are gone.
   **Prevention:** the documented collision — assert X and document X are adversaries in one file.
8. **Checked task 9.2 while PR #7495's body was still the draft placeholder.** **Prevention:** a
   checkbox is a CLAIM; ship-time steps stay unchecked until ship.
9. **`tasks.md` cited mutation row `M5`**, which the plan's matrix (M1–M4) never defined.
10. **`session-state.md` cites pre-rebase SHAs** that are now dangling, and a scope-check line that
    no longer holds. True when written, false now.
11. **My round-2 battery's landing check passed the wrong file** for four rows, reporting four false
    `FATAL - mutation did not land`. It failed in the *safe* direction. **Prevention:** the landing
    assertion is why this surfaced at all — keep it, and pass the mutated file, not the guard's.
12. **My first predicate-variant replay omitted two array elements**, producing 45 vs 46. Reconciled
    against the merge-base-anchored figure. **Prevention:** replay the array, not a hand-typed subset.
13. **Push rejected after rebase** — needed `--force-with-lease` after verifying the three
    remote-only commits were my own pre-rebase versions and no other author's.
14. **Plan wall-clock figures contradicted in both directions**; D3 counterfactual moved 51% → 48%
    when the window shifted. Both corrected in append-only addenda.

## Recurring-vs-one-off triage

| item | recurring? | disposition |
|---|---|---|
| Guard PR's own registration/vacuity surfaces unguarded (1, 4, 5) | **recurring** | fix-now-inline (done) + route to `review/SKILL.md` |
| `grep`-on-source pins spelling not participation | **recurring** | fix-now-inline (done); already a documented class, reinforced |
| Floor derived from its own subject | **recurring** | fix-now-inline (done) |
| `changelog-data` GitHub-API flake | **recurring** | already file-tracked as **#6842** — no new filing |
| Replay anchored to a moving `origin/main` | **recurring** | fix-now-inline (SHA anchor + comment) |
| Checkbox/citation drift (8, 9, 10) | one-off | recorded above; no fix |
| Battery landing-check arg (11), replay subset (12), push rejection (13) | one-off | recorded above; no fix |

Net issue flow: **closing 1 (#7494), filed 1 (#7498) → net 0.**
