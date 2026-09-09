---
title: "Shell git-fixture containment: repair the vacuity, adopt the tripwire, and prove containment is not refusal"
date: 2026-09-09
slug: fix-shell-git-fixture-containment-sweep
branch: feat-one-shot-7822-7835-shell-git-fixture-env-sweep
issue: 7822
# Operator overruled the plan's challenge on 2026-09-09: #7835 CLOSES, #7822 stays Ref.
# See "Ref, not Closes" below for the evidence, and the OPERATOR RULING that supersedes it.
closes: 7835
refs: 7822
type: fix
classification: test-infrastructure
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened:** 2026-09-09. **Reviewers:** architecture-strategist, code-simplicity-reviewer,
spec-flow-analyzer, test-design-reviewer, learnings-researcher, a repo precedent sweep, and a
mechanical claim-verification sweep.

### What review changed, in order of consequence

1. **The containment arm could not have passed as first drafted — two independent root causes, both
   measured.** `SOLEUR_GIT_TRIPWIRE_ALLOW=1` **announces and falls through; it does not scrub**, and
   the hostile value was aimed at scratch rather than at the victim. Either alone makes the arm
   unfalsifiable. Fixed by naming the two layers explicitly (the tripwire is *refusal*;
   `scripts/test-all.sh`'s `unset` is *containment*), invoking the child through a **sandbox copy** of
   that `unset` line, and pointing the hostile environment **at the victim**. Measured as **M-10**,
   which doubles as the arm's positive control.
2. **The nine-variable partition is now DERIVED, not asserted.** An earlier draft hand-split them
   into "seven write/ref-redirecting" and two code-execution. **M-13 falsified that**: which
   variables can move the victim triple depends on the *child's write shape*, so the hand-split would
   have shipped up to six arms that cannot fail. The suite now calibrates and floors on the derived
   set.
3. **Both `Closes` downgraded to `Ref`.** 0 of the 10 files #7822 enumerates are touched, and 4 of
   #7835's TypeScript fixtures are still unscrubbed — falsifying the brief's "the TypeScript half
   shipped" premise. Recorded as a **User-Challenge**; the residue is filed as a durable issue rather
   than named in a PR body.
4. **The adoption metric was wrong.** `grep -l` counts *mentions*: real source-anchored adoption is
   **44/88 → 47/88**, not 51 → 54. The naive figure would have been posted to #7849 and would not
   have been reproducible by its own command.
5. **Four mutation rows were undriveable or wrong** (Guard 1 M4 had no member list; Guard 1 H4 tested
   another suite's property; Guard 2 M5 claimed an assertion floor catches an *added* case, which a
   shrink-only `>=` floor cannot; Guard 1 M6 named a variable M-13 shows cannot move the triple). All
   four replaced; **M7** and **M8** added to catch the two vacuity modes nothing else covered.
6. **The victim oracle was BLIND to a real breach.** A test-design pass measured — and this run
   independently reproduced — that `GIT_COMMON_DIR` and `GIT_OBJECT_DIRECTORY` write the child's
   objects into the victim's store (3 → 6 loose objects) while HEAD, refs and the index stay
   byte-identical. The oracle is now a **quadruple**. Without the fourth component, two of the nine
   variables are breaches this guard would have certified as contained.
7. **Four mutation rows were polarity-inverted** — they weaken the guard and expect RED, but a
   weakened guard passes. M2, M5, M7 and Guard 2 M6 are now differentials or paired with a fixture
   that gives them a kill, and a **comparator self-test** was added as the instrument three of them
   depend on. Two more rows had the wrong mechanism attributed (M3 reds via the refusal arm, not the
   floor; Guard 2 H1 reds via the structural derivation, because nothing in the repo pins floor
   *values*).
8. **Two ratchets were missing from the brief's list of 14** — `scripts/lint-shell-capture-exit-live`
   (a 15th, repo-wide) and `fixture-dir-operand-assert`'s strict `SITES_LIVE == ACK_TOTAL` arm, which
   is stricter than the P1b arm the plan already described.
9. **Scope cut**: the committed predicate script (it would be the only never-invoked file in
   `plugins/soleur/test/lib/` and would join two ratchet corpora), a recurrence ratchet already served
   at the entry-point layer by `hook-git-env-coverage.test.sh`, and two acceptance criteria that could
   not fail.
10. **Precedent replaced invention.** Three of the four idioms A3 needs already exist and are now
   cited by function name — including `git-fixture-env.test.ts`, which is Guard 1's TypeScript half
   and already performs the exact victim-triple comparison A3 must port. Three compositions are
   genuinely novel and are flagged as such.

### The finding most likely to bite the implementer

`set -uo pipefail` **does not clear `-e`** — only `set +e` does. Sourcing `test-helpers.sh` therefore
adds `-e` permanently to a suite whose own `set` line omits it, taking `gitleaks-merge-commit.test.sh`
from 27/27 to rc=1. The remedy (`set +e -uo pipefail`) is measured green, and the tripwire still fires
through it.

## Overview

PR 2 of the two-PR shell-git-env-scrub sequence — Phases A1-A3 of the merged plan
`2026-09-08-fix-shell-git-env-scrub-and-hook-fault-diagnosis-plan.md`. PR 1 (the hook-input
classifier) merged 2026-09-08 as `9ee572041` and is out of scope. The TypeScript half
(`git-clean-env.ts`) is also out of scope — but **it did not fully ship**, and this plan does not
repeat the brief's claim that it did (measured below: 4 of the `apps/web-platform` fixtures #7835
names still carry no scrub).

Three deliverables, and they are not the same kind of thing:

- **A1 — the vacuity repairs.** A case that runs a gate in a deliberately non-git directory, to
  prove the gate fails for want of a repository, inverts under an inherited `GIT_DIR`: the
  directory *is* a repository, the gate succeeds, and the case stays green while proving nothing.
  Each such case gains a precondition that evidences its own premise, with a positive control.
- **A2 — the tripwire sweep.** Three suites build a committing git fixture and carry no
  `test-helpers.sh` source, no `exit 97` tripwire, and no git-location scrub. They adopt the
  helper. This is adoption bookkeeping that advances #7849, not containment.
- **A3 — the containment regression test.** The one test here that can reproduce the incident
  #7835 records. Two arms, because asserting only the victim's state certifies "contained **or**
  refused to run".

**What this plan measured that its predecessor assumed.** The source plan warned that "adopting the
helper changes failure semantics in at least two of the five; verify each still passes rather than
assuming the source line is inert." It did not say *how* the semantics change, and the natural
reading — "the suite's own `set` line runs after the source, so the suite's options win" — is
**false**. `set -uo pipefail` does not clear `-e`; only `set +e` does. Measured below: sourcing the
helper into `gitleaks-merge-commit.test.sh` takes it from 27/27 green to rc=1, dying in its first
case. The remedy is one measured line per suite, and it is in this plan rather than left to /work.

## Research Reconciliation — Brief vs. Codebase

Re-derived on 2026-09-09 in the worktree. The brief instructed re-derivation rather than
inheritance; four of its figures moved.

| Claim as briefed | Reality on this branch | Plan response |
|---|---|---|
| Sweep set is **five** suites | The pinned predicate returns **four**. `proc.test.sh` drops out. | Sweep set restated as 4; `proc.test.sh` stays in scope for A1 on its own merits. |
| `proc.test.sh` is a predicate member | `proc.test.sh:385` already carries `env -u PROC_SH_WORKTREE -u GIT_DIR -u GIT_WORK_TREE` (blame `6ad705063f`, 2026-08-13 — *predates* planning). It carries a scrub, so the predicate excludes it. | This is a predicate-**application** error in the inherited list, not corpus drift. `proc.test.sh` is an **A1 vacuity** member (T9 `NOGIT`, line 383), which is what the source plan actually assigned it. |
| Corpus is 82 suites (grew 81→82) | `git ls-files 'plugins/soleur/test/*.test.sh'` = **88**. | Restated. The membership did not move with the corpus, which is the point the brief was making — it just moved for a different reason. |
| `harvest-debt.test.sh` is a member | **Confirmed member**, but only under a `git -C`-aware regex: it uses `git -C "$d" init -q` (lines 29, 60). A `^git init` anchor misses it entirely. | The predicate is pinned as an executable script (below), not as prose. |
| `fixture-dir-operand-assert.test.sh` runs `git init` | Its only `git init` is in a **comment** at line 8. Its real git write is `git -C "$dir" config commit.gpgsign false` at line 287. | Still an **A1 vacuity** member, as the source plan assigned it — but the predicate matches it for the wrong reason, which is itself evidence the predicate must be executable and inspected, not trusted. |
| Repo-wide is **30**, with **7** under `.claude/hooks/` | Regex-sensitivity-bound. The narrow anchor `measurements.md` used returns **17 / 6**; a `git -C`-aware anchor returns **41 / 13**. Neither reproduces 30 / 7. | Ship **one** executable predicate, report the number **it** yields, and say so. A count whose regex is unstated is not falsifiable, which is the property AC13 requires. |
| The TypeScript half (`git-clean-env.ts`) "shipped earlier" | **False.** 4 of the `apps/web-platform` fixtures #7835 names carry no scrub idiom (`cc-reprovision-git-discriminator`, `helpers/context-queries-fixture`, `worktree-config-seed`, `git-config-atomic`). #7849 corroborates, listing two as "neither converted nor waived". | `#7835` downgraded to **`Ref`**. The unscrubbed TS fixtures join the residue issue. |
| `.claude/hooks/` cannot take a cross-tree `source` | **6 of 47** `.claude/hooks/*.test.sh` already reference `test-helpers.sh`. | The residue argument is rewritten to be about shape and ownership, not about a barrier that does not exist. |
| Adoption is 51 of 88 | `grep -l` counts **mentions**. Source-anchored, real adoption is **44 of 88**; seven suites merely name the helper. | All adoption figures restated as **44 → 47**, from the source-anchored grep. |
| Do-not-touch owner set includes the CCLA instrument-hashing PR | That PR **merged** 2026-09-08 as `dc9eaab84` and is no longer open. Re-derived owner set: **#7879** owns all three paths; **#7976, #7954, #7390, #6778** own `scripts/test-all.sh`. | The constraint holds and is *more* contended than the stale list said. Re-assert immediately before `gh pr ready`. |

Two further reconciliations that change the work rather than the numbers:

| Claim | Reality | Plan response |
|---|---|---|
| A3's **refusal arm** is new work | `plugins/soleur/test/git-tripwire.test.sh` already asserts a shell suite sourcing `test-helpers.sh` aborts `rc=97` under `GIT_DIR=/tmp/hostile`, and that `SOLEUR_GIT_TRIPWIRE_ALLOW=1` permits the run and announces itself. | The refusal arm is **not new coverage**. It is retained in A3 as a **paired control**: a refusal proven against a *different* child cannot certify that *this* child refuses, and without it the containment arm cannot distinguish "contained" from "refused". Stated in the plan so the duplication is deliberate rather than accidental. |
| A3's **containment arm** is covered by the same suite | It is **not**. That escape-hatch arm runs a trivial *bun* probe and asserts `rc == 0` plus a `DISARMED` stderr banner — two assertions, both about the runner. It never performs a git write and never reads a victim repository's state. | The containment arm — hostile env, tripwire disarmed, child exits 0 **and** the victim's HEAD / ref set / staged list are unchanged — is the genuinely new mechanism in this PR. |

## Research Insights

### Premise validation (Phase 0.6)

Every reference cited by the brief was probed. `#7822` OPEN (`test fixtures inherit GIT_DIR under
lefthook and commit onto the caller's branch`), `#7835` OPEN (`Test fixtures escape their git
sandbox under pre-commit…`), `#7849` OPEN (`adopt gitFixtureEnv() at every fixture-creating
suite`). `9ee572041` is `fix(hooks): the hook_self_fault reason could not name its cause (#7943)`.
`dc9eaab84` is the CCLA PR. Both source documents exist and were read. **No premise was stale
except the four figures reconciled above.**

### Property list (Phase 0.6b)

The ask proposes mechanisms; these are the properties underneath.

- **P1.** A case that asserts "this directory is not a repository" fails when that premise does not
  hold — including under an inherited `GIT_DIR`.
- **P2.** A shell suite that builds a committing git fixture cannot run at all under an inherited
  git-location environment.
- **P3.** With the tripwire deliberately disarmed and a hostile git-location environment set, a
  swept suite's git writes reach its own fixture and **not** the caller's repository.
- **P4.** The sweep's membership is falsifiable: a reader can re-run the predicate and get the same
  set.
- **P5.** #7849's exit condition moves measurably, and the PR says by how much and from what.

### Cut list (Phase 0.6b)

| Mechanism proposed | Property it buys | Already covered on `origin/main`? | Disposition |
|---|---|---|---|
| A3 **refusal arm** (child exits 97 under hostile env) | P2 for *this* child | **Yes, three times** — `git-tripwire.test.sh` `=== K: shell arm ===` generically, plus A2's own AC17/T6 per-suite. | **KEPT for cost (~8 lines), with the justification CORRECTED.** An earlier draft claimed it "stops the containment arm being satisfied by a refusal". **That is false**: the containment arm asserts the child exits **0**, and a refusal exits 97, so the containment arm rejects a refusal on its own. The disambiguation lives entirely in the exit-code oracle. The refusal arm asserts P2 for this specific child and nothing more — recorded so the bad reasoning is not reused to justify the next redundant arm. |
| A3 **containment arm** (victim triple unchanged) | P3 | **No.** `git-tripwire.test.sh`'s escape arm runs a bun probe and asserts `rc==0` plus a `DISARMED` stderr banner — both about the runner, neither about a repository. | **KEPT.** This is the new mechanism. |
| A per-file `GIT_*` scrub in the three A2 suites | P2 | Partially — layers 1-3 of #7833 already cover every *reachable* invocation. | **CUT.** Sourcing `test-helpers.sh` buys the same P2 *and* P5; a bespoke scrub buys P2 only and does not advance #7849. |
| A new registration of the A3 file in `scripts/test-all.sh` | reachability | **Yes** — `SUITE_GLOBS` already matches `plugins/soleur/test/*.test.sh`. | **CUT**, and it must be: `scripts/test-all.sh` is a do-not-touch path. Naming, not registration — the same resolution Phase A4 of the source plan reached. |
| A `--write-baseline` regeneration of `fixture-relative-assert.baseline.txt` | ratchet green | n/a | **CUT.** That launders real findings. The remedy is to guard the sites so no new row is produced. |
| **Promote the sweep predicate to a shrink-only CI ratchet** over the test-file corpus, so the class cannot recur — i.e. #7822's ask 2 | "the class cannot recur" | **Yes** — `plugins/soleur/test/hook-git-env-coverage.test.sh` (Guard 2) already ratchets this class, over hook **entry points**. | **CUT, and the reason is the whole point of this gate.** This plan reached for it, then read the sibling. Guard 2's header carries the measurement: all four recurrences entered through an **entry point**, never through a test file, and *"that corpus is not enumerable anyway"* — which this plan independently re-proved by getting **17, 30 and 41** from three readings of the same predicate. A ratchet whose baseline is a regex artifact can be silently narrowed, which is the defect it would claim to prevent. |

### Measurements taken at plan time

All run in this worktree on 2026-09-09. Ambient environment carried `GIT_EDITOR=true` and **no**
git-*location* variable — worth recording, because `GIT_EDITOR` matches a naive `GIT_[A-Z_]+`
exclusion and is *not* one of the nine variables the tripwire refuses.

**M-1 — the three A2 candidates are green today.**

```
bash plugins/soleur/test/gitleaks-merge-commit.test.sh   -> rc=0, 27/27 passed
bash plugins/soleur/test/harvest-debt.test.sh            -> rc=0, 19 passed
bash plugins/soleur/test/roadmap-reconcile.test.sh       -> rc=0, 20 passed
```

**M-2 — naive adoption BREAKS one of the three.** Sourcing the helper first, then the suite:

```
bash -c 'source plugins/soleur/test/test-helpers.sh; source plugins/soleur/test/<f>.test.sh'
  gitleaks-merge-commit -> rc=1   (dies in its first case; 27/27 -> failure)
  harvest-debt          -> rc=0
  roadmap-reconcile     -> rc=0
```

**M-3 — the mechanism.** `set -uo pipefail` is **additive**; it does not clear `-e`.

```
bash -c 'set -euo pipefail; set -uo pipefail; case $- in *e*) echo "-e STILL ON";; esac'
  -> -e STILL ON
```

`test-helpers.sh:5` runs `set -euo pipefail`. `gitleaks-merge-commit.test.sh:41` and
`harvest-debt.test.sh:12` run `set -uo pipefail` — deliberately without `-e`, because both are
mutation-proof suites whose cases *expect* non-zero returns inline. After the source, `-e` stays on
through their own `set` line, and the first legitimately-non-zero command aborts the suite.

**M-4 — the remedy, measured.** Source the helper, then restore `+e` in the suites that ran
without it:

```
bash -c 'source .../test-helpers.sh; set +e; source .../<f>.test.sh'
  gitleaks-merge-commit -> rc=0, 27/27 passed
  harvest-debt          -> rc=0, 19 passed
  roadmap-reconcile     -> rc=0, 20 passed
bash -c 'set -euo pipefail; set +e -uo pipefail; …'  -> -e cleared, -u and pipefail retained
```

**M-5 — the tripwire still fires through the remedy.** With `GIT_DIR=/tmp/hostile-probe`, all three
compositions (with and without the `set +e`) abort `rc=97` with a `FATAL` line. The `+e`
restoration does **not** disarm the tripwire, because the tripwire `exit`s rather than returning.

**M-10 — with no scrub in the child's path, all three swept suites write into the victim.** Run
exactly as the containment arm specifies (victim = synthesized `mktemp` repo; hostile
`GIT_DIR` = the victim's `.git`; `SOLEUR_GIT_TRIPWIRE_ALLOW=1`), but **without** a scrub anywhere in
the path:

| child suite | child rc | victim HEAD | victim staged |
|---|---|---|---|
| `harvest-debt.test.sh` (post-A2 edit) | 1 | unchanged | **0 → 3** |
| `gitleaks-merge-commit.test.sh` | 1 | **moved — 4 commits landed** | **0 → 5** |
| `roadmap-reconcile.test.sh` | 0 | **moved — `init` on the victim tip** | **0 → 1** |

Two things follow, and both are load-bearing. **First, this is not a defect in the plan — it is
Guard 1's mutation M1, measured at plan time.** "Remove the scrub → the victim's HEAD moves" is
precisely what the table shows, so the containment arm's positive control already exists as evidence
rather than as a promise. `gitleaks-merge-commit` is a byte-for-byte reproduction of #7835.
**Second, it proves the arm must run the child through a scrub**, because `git -C "$d"` does not save
a fixture — #7822 says so in as many words — and `ALLOW=1` does not scrub. Hence the sandbox copy of
`test-all.sh`'s `unset` line, below.

**M-11 — the adoption metric counts MENTIONS, not sources.** `grep -l 'test-helpers.sh'` returns
**51**, but only **44** actually source it; seven merely name it in prose or extract from it
(`fixture-dir-operand-assert`, `git-env-list-parity`, `git-tripwire`, `hook-git-env-coverage`,
`hook-git-env-receipt`, `hook-input-classification-mutation`,
`preflight-check10-suite-integrity`). Real adoption is **44 of 88**, and A2 takes it to **47 of 88**.
The number posted to #7849 must come from the source-anchored form
`grep -lE '^[[:space:]]*(\.|source) .*test-helpers\.sh'`, or the PR posts a figure that is both
wrong and not reproducible by its own command — against an exit condition the denominator exists to
measure. A3 must also not inflate it: if A3 references `test-helpers.sh` to extract the canonical
operand guard, the naive grep counts it as an adopter when it is not one.

**M-12 — `.claude/hooks/` already uses the cross-tree reference.** **6 of 47**
`.claude/hooks/*.test.sh` reference `test-helpers.sh`. An earlier draft justified the hooks residue
partly with "no suite in that tree carries the tripwire, and the established pattern there is an
inline byte-pinned copy rather than a cross-tree `source`". The second half is **false as a barrier**
and has been removed from the residue argument.

**M-13 — which variables can move the victim triple depends on the CHILD'S WRITE SHAPE.** Measured
per variable, with a `git -C "$d" init && git -C "$d" add -A && git -C "$d" commit` child (the
#7835 shape) against a synthesized victim, snapshotting HEAD + `for-each-ref` + `diff --cached`:

| variable | victim triple |
|---|---|
| `GIT_DIR` | **MOVED** |
| `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_NAMESPACE` | unchanged |

But with a **different** child — one that writes a file into the victim's work tree and runs
`git add` — `GIT_INDEX_FILE` (with `GIT_WORK_TREE`) **does** move the staged list. So the partition
is a function of the child, not a property of the variable, and **any hand-written partition is
wrong for some child**. This is why the Assembly derives the containment set by calibration and
floors on its size, and why `CHILDREN` must carry **two different write shapes** rather than two
copies of one. A control run with a nonsense value confirmed the harness reports `UNCHANGED`
correctly, so the negatives above are readings and not a broken probe.

**M-14 — the HEAD/refs/staged triple is BLIND to a real breach; the oracle must be a QUADRUPLE.**
Measured, same harness as M-13, additionally counting loose objects under the victim's
`.git/objects`:

| hostile variable (aimed at the victim) | triple | victim object count |
|---|---|---|
| `GIT_DIR` | **MOVED** | 3 → 6 |
| `GIT_COMMON_DIR` | unchanged | **3 → 6** |
| `GIT_OBJECT_DIRECTORY` | unchanged | **3 → 6** |

`GIT_COMMON_DIR` and `GIT_OBJECT_DIRECTORY` put the child's objects into the victim's store while
HEAD, refs and the index stay **byte-identical**. That is a genuine write-boundary breach — the
victim's repository grew — and the triple cannot see it. So the oracle carries a **fourth**
observable (a loose-object count, e.g. `find "$V/.git/objects" -type f | wc -l`, or
`git count-objects -v`), and those two variables move from the refusal-only class into the
containment class. Without the fourth component, two of the nine variables are breaches this guard
would certify as contained.

**M-6 — the canonical adoption idiom** is `source "$SCRIPT_DIR/test-helpers.sh"`, used by 44 of the
suites that source it, so `SCRIPT_DIR` must be bound *before* the source line. The three A2
candidates differ, and the difference is per-suite work rather than one repeated edit:

| suite | current state | consequence for the edit |
|---|---|---|
| `harvest-debt.test.sh` | binds `SCRIPT_DIR` **after** its `set` line | move the binding above, then source |
| `roadmap-reconcile.test.sh` | binds `SCRIPT_DIR` **after** its `set` line | same |
| `gitleaks-merge-commit.test.sh` | **binds no `SCRIPT_DIR` at all** — it uses `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"`, itself below the `set` line | a **new** binding is introduced, not a reordering |

An earlier draft of this measurement said all three bind it after their `set` line. That is wrong for
`gitleaks-merge-commit.test.sh`, which binds it nowhere — caught by the deepen verification sweep.

**M-7 — the `git-tripwire.test.sh` shell-arm coupling, checked and found benign.** That suite picks
its subject as the first `grep -l 'test-helpers.sh' plugins/soleur/test/*.test.sh | sort | head -1`,
which is `auto-close-scanner.test.sh`. None of the three A2 additions sorts earlier, so the shell
arm's subject does not change. Re-assert this at /work: adding a suite that sorted first would
silently move that guard's subject.

**M-8 — the P1a byte-exactness corpus is repo-wide.** `fixture-dir-operand-assert.test.sh` builds
its drift corpus from `git -C "$REPO_ROOT" ls-files -z '*.sh'`, matching any tracked `.sh` that
*defines* `assert_fixture_dir`. An inline copy in the new A3 file therefore **joins that corpus**
and must be byte-identical to the canonical body in `test-helpers.sh`. The same suite also refuses
any file carrying the assertion that redefines `exit`, `printf`, or `return`.

**M-9 — the P1b ratchet is row-by-row equality, not a floor.**
`fixture-relative-assert.test.sh` compares live scan rows to
`fixture-relative-assert.baseline.txt` **row by row, keyed by file path**; `FILES` carries a
separate `>= 900` floor. A new tracked `.sh` raises `FILES` harmlessly, but any
`operand not provably absolute` site inside it creates a **new row** and reddens the equality arm.
The scanner already resolves `mktemp` in every form; the surviving residue is caller parameters,
never-bound globals, and uses that textually precede their binding.

### Institutional learnings

Consulted via `learnings-researcher`; findings folded into Sharp Edges below. The load-bearing ones
for this change are the anti-vacuity/false-green family (a guard that cannot be driven red is
vacuous; a delete-only mutation battery certifies a property about a *window* it never tested) and
the plan-time-measurement family (a prescribed shell form must be executed, not recalled).

### CLAUDE.md / AGENTS.md conventions in force

`cq-write-failing-tests-before` (the mutation matrix is written before the guard),
`cq-test-fixtures-synthesized-only`, `cq-assert-anchor-not-bare-token`,
`cq-cite-content-anchor-not-line-number`, `hr-always-read-a-file-before-editing-it`,
`hr-never-git-stash-in-worktrees`, `wg-defer-only-after-inline-triage`,
`hr-verify-repo-capability-claim-before-assert`.

## The predicate, pinned as an executable script

Prose predicates are not falsifiable; three different readings of this one produced 17, 30 and 41.
The PR body carries **this script and the number it yields**, not a remembered figure.

**Not a committed file — a command.** An earlier draft shipped this as
`plugins/soleur/test/lib/git-fixture-sweep-predicate.sh`. **Cut**: every one of the six files in
`plugins/soleur/test/lib/` is invoked by something, this would be the first that nothing calls, and a
new tracked `.sh` joins *both* the `fixture-relative-assert` and `fixture-dir-operand-assert`
corpora — real permanent cost for a script that runs once, by hand, and whose output is then
hand-filtered anyway. The three predicate clauses go in the PR body verbatim, inside a fenced block,
where they are identically re-runnable and outlive nothing.

```bash
# A tracked *.test.sh that CREATES a git repository and WRITES to one, carrying none of:
#   a test-helpers.sh source | an `exit 97` tripwire | a git-LOCATION scrub.
# `git -C <dir>` and `git --git-dir=<dir>` forms are matched: an anchor of `^git init` misses
# harvest-debt.test.sh, which is a real member. GIT_EDITOR / GIT_AUTHOR_* are NOT scrubs — the
# tripwire refuses nine LOCATION variables only, so the scrub arm must name them, not `GIT_.*`.
_creates() { grep -qE 'git( +-[^ ]+| +"[^"]*")* +(init|clone)' "$1"; }
_writes()  { grep -qE 'git( +-[^ ]+| +"[^"]*")* +(add|commit|rm|mv|checkout|switch|branch|tag|push|reset|merge|apply|update-ref|config)' "$1"; }
_guarded() { grep -qE 'source .*test-helpers\.sh|exit 97|unset +GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES|NAMESPACE|TEMPLATE_DIR|EXEC_PATH)|env +-u +GIT_|env +-i|SOLEUR_GIT_TRIPWIRE' "$1"; }
```

Scope argument selects `plugins/soleur/test/*.test.sh` (scoped) or `*.test.sh` (repo-wide).

**Known imprecision, stated rather than hidden — and AC13 is worded to match it.** `_creates`
matches text in comments, which is why `fixture-dir-operand-assert.test.sh` matches on a line-8
comment. The predicate emits a **superset**; the four-member set is human judgment applied
afterwards. So AC13 does **not** claim "falsifiable in one command" — that would be false. It claims
the weaker, true thing: the command and its raw output are in the PR body, the hand-filtering step is
named, and each member's disposition is recorded, so a reader can re-run the screen and audit the
judgement separately.

**This is NOT a recurrence gate, and the PR body must say so.** The gate for this class is
`plugins/soleur/test/hook-git-env-coverage.test.sh` (Guard 2), which ratchets **hook entry points** —
the layer all four recurrences actually entered through. This script exists so that *this PR's* sweep
membership is falsifiable in one command; it is a one-shot screen over a corpus the repo has already
measured as **not enumerable** (the `execFileSync("git", ["init", …])` array form and python
list-spawns match no `git init` grep). A reader who mistakes it for a coverage ratchet would conclude
the test-file corpus is closed, which is exactly false. Cross-reference Guard 2 beside it.

**Scoped result (2026-09-09, corpus = 88):**

```
plugins/soleur/test/fixture-dir-operand-assert.test.sh   A1 (vacuity)
plugins/soleur/test/gitleaks-merge-commit.test.sh        A2 (sweep)
plugins/soleur/test/harvest-debt.test.sh                 A2 (sweep)
plugins/soleur/test/roadmap-reconcile.test.sh            A2 (sweep)
```

Plus `plugins/soleur/test/proc.test.sh` — **not** a predicate member (it carries a partial scrub),
carried into **A1** because its T9 `NOGIT` case is the vacuity class the predicate cannot see.

## Which exit condition the sweep discharges

This section is a **PR-body deliverable**, not commentary. `measurements.md` records that the
scoped count and the repo-wide count are both correct and measure different sets; a sweep shipping
against the smaller number must say which condition it is discharging.

**It discharges none outright. It advances one, and the PR states by how much.**

#7849's re-evaluation trigger 2 reads, verbatim: *"The fixture helpers are consolidated so scrubbing
happens in exactly one place — e.g. if `plugins/soleur/test/*.test.sh` reaches **full**
`test-helpers.sh` adoption (measured 2026-09-04: 41 of 73 suites source it). At that point Guard 3's
shell arm becomes a true chokepoint and this issue can be closed as unnecessary."*

- The condition is **full adoption across all `plugins/soleur/test/*.test.sh`** — not adoption
  across the suites matching this plan's git-fixture predicate. Those are different sets.
- Measured 2026-09-09, **source-anchored** (see M-11): **44 of 88** suites actually source the
  helper — a naive `grep -l` says 51, but seven only mention it. A2 takes real adoption to
  **47 of 88**.
- **#7849 therefore stays OPEN and is NOT in `closes:`.** The PR posts the new count to #7849 as
  adoption bookkeeping.
- **#7822 and #7835 are closed by A1 and A3, not by A2.** A1 removes the class of case that stays
  green while proving nothing; A3 pins the containment property that #7835's incident violated.

**The residue, named as required.** Under the pinned predicate run repo-wide, the members outside
`plugins/soleur/test/` remain unconverted, and a substantial share sit under `.claude/hooks/`. The
brief characterised this as "where #7822 says exposure is highest". **#7822 does not use that
phrasing**, and the plan must not either: it says those suites are *"the ones most likely to be
executed **from** a hook"* and that they are *"candidates, not confirmed defects — I have not driven
each one under `GIT_DIR`."* Its list is headed by
`apps/web-platform/infra/workspaces-luks-loopback.test.sh`, a **do-not-touch path**. The PR body
states it that way, prints the exact counts from the pasted predicate, and links the residue issue
filed below.

## Ref, not Closes — and the measurements that forced it

> **OPERATOR RULING (2026-09-09) — supersedes this section's conclusion for #7835.**
> The challenge below was put to the operator with its evidence. Ruling:
> **`Closes #7835`, `Ref #7822`.** #7822 stands as argued here — its ten enumerated
> files are disjoint from the sweep set and one is a do-not-touch path, so it stays
> open. #7835 is CLOSED on the strength of A3: the containment regression test
> reproduces and pins the exact incident #7835 reports (an inherited `GIT_DIR`
> rewriting a live branch tip and wiping the index).
> **Condition of the ruling:** the four unscrubbed TypeScript fixtures named below
> do NOT disappear with the issue. They are carried into the residue issue
> explicitly, by filename, so closing #7835 cannot lose them.
> Scope ruling, same exchange: **stay narrow** — AC15's wider vacuity table
> (`.claude/hooks/{guardrails,session-rules-loader}`,
> `scripts/{check-pa-22,lint-legal-registers,skill-security-scan-step-body}`) is
> NOT pulled into this PR; it is named residue.

The brief's stated direction was *"Work targets to close: #7822 and #7835."* **This plan downgrades
both to `Ref`.** That reverses an operator instruction, so it is recorded as a **User-Challenge** in
`specs/<branch>/decision-challenges.md` for `ship` to render into the PR body and file as an
`action-required` issue — the operator can overrule it. The evidence:

**#7822 — 0 of the 10 files it enumerates are touched.** Its `## Measured population` lists ten shell
suites and calls that list *"the work, not the finding."* Run against this plan's own `_guarded()`
clause, **10 of 10 are still unguarded**, and **0 of 10** are in this PR's four-member sweep set —
the sets are disjoint. One of the ten
(`apps/web-platform/infra/workspaces-luks-loopback.test.sh`) is a declared **do-not-touch path**, so
this PR is structurally barred from fixing it. Of #7822's three asks: ask 1 (a shared scrub helper)
shipped; ask 2 (a lint) is served at the entry-point layer by
`plugins/soleur/test/hook-git-env-coverage.test.sh` — see the Cut List — but not over the population
#7822 enumerates; ask 3 (the regression test) is this PR's A3. That is a real contribution and it is
not closure.

**#7835 — the TypeScript half did not ship.** The brief asserted it did, and an earlier draft of this
plan repeated that. Measured against #7835's own list of exposed fixtures: `cc-reprovision-git-discriminator.test.ts`,
`helpers/context-queries-fixture.ts`, `worktree-config-seed.test.ts` and `git-config-atomic.test.ts`
carry **no** scrub idiom (`gitFixtureEnv` / `gitCleanEnv` / `GIT_SAFE_ENV` / either lib import).
#7849's body independently corroborates this, listing two of them as *"neither converted nor waived."*
Phase 0.6 verified that the cited issues are OPEN and the cited SHAs exist; it did **not** probe this
substantive claim, and that is the gap this row closes.

**What would earn closure**, recorded so the choice is available rather than implied: give the
predicate a `--gate` mode that exits non-zero on any member outside a committed acknowledgment file,
register it as a ratchet, and seed the file with today's members — roughly 20 lines. **This plan does
not do that**, because the Cut List's reasoning still holds (the gate for this class lives at the
entry-point layer, and the test-file corpus is measurably not enumerable — 17/30/41). The residue is
instead filed as a durable issue, below.

## The residue is filed as an issue, not left in a PR body

`wg-when-an-audit-identifies-pre-existing` requires a durable artifact — *"never conversation only"* —
and a PR body is not one. The residue also passes `wg-defer-only-after-inline-triage`'s triple test:
it is not a sub-30-minute one-file fix (10+ files across two trees); it has a concrete trigger
(#7822's reproduction, #7835's realized incident); and it is plausible within six months because it
has already fired twice.

**Deliverable: file one `type/bug`, `priority/p2-medium` issue** enumerating the ten shell files from
#7822's population plus the four unscrubbed TypeScript fixtures from #7835, noting that
`workspaces-luks-loopback.test.sh` is owned by PR #7879. Task 6.3 references it **by number**; the PR
body links it.

**The hooks residue argument, corrected.** An earlier draft said *"no suite in that tree carries the
tripwire, and the established pattern in the hooks tree is an inline byte-pinned copy rather than a
cross-tree `source`."* Measured: **6 of 47** `.claude/hooks/*.test.sh` already reference
`test-helpers.sh`, so the cross-tree reference is not the barrier that draft claimed. The honest
scope argument is narrower and is only about *shape and ownership*: those suites need the
hooks-tree idiom rather than a `source`, one of the ten is a do-not-touch path, and converting ten
files across two trees in this PR would couple a containment proof to a large mechanical diff. It is
**not** an argument that their exposure is tolerable — #7822 is explicit that they are *"the ones
most likely to be executed **from** a hook"*, i.e. the surface where the hostile environment is
actually present. That is precisely why it gets an issue rather than a sentence.

## Hard constraint — three paths this diff must not touch

```
scripts/test-all.sh
plugins/soleur/test/test-helpers.sh
apps/web-platform/infra/workspaces-luks-loopback.test.sh
```

Sweep suites MAY `source` `test-helpers.sh`; they may NOT edit it. Owner set re-derived 2026-09-09
via `gh pr list` + per-PR file lists (the brief's list was stale — the CCLA PR it named merged as
`dc9eaab84`):

| PR | Paths it owns |
|---|---|
| **#7879** | all three |
| #7976, #7954, #7390, #6778 | `scripts/test-all.sh` |

**Enforcement, before `gh pr ready`:**

```bash
git diff --name-only origin/main...HEAD | grep -E \
  '^(scripts/test-all\.sh|plugins/soleur/test/test-helpers\.sh|apps/web-platform/infra/workspaces-luks-loopback\.test\.sh)$' \
  && { echo "FATAL: diff touches a do-not-touch path"; exit 1; } || echo "OK: none of the three touched"
```

This is AC19 and it is a **hard blocker**, not a checklist line.

## Implementation Phases

### Phase 0 — preconditions (measure; do not assume)

1. Re-run the pinned predicate script; reconcile against the four-member set above. **If membership
   moved, the sweep moves** — restate it in the PR body rather than shipping the plan's list.
2. Re-run M-1 (three suites green today). A suite red *before* the edit is not this PR's regression
   and must be triaged inline per `wg-defer-only-after-inline-triage`.
3. Confirm the ambient environment carries no git-location variable
   (`env | grep -E '^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES|NAMESPACE|TEMPLATE_DIR|EXEC_PATH)='`
   returns nothing). Every measurement below is void otherwise.
4. Re-run M-7: `grep -l 'test-helpers.sh' plugins/soleur/test/*.test.sh | sort | head -1`. Record
   it. If A2 changes this value, `git-tripwire.test.sh`'s shell arm has silently changed subject.
5. Record the adoption count: `grep -l 'test-helpers.sh' plugins/soleur/test/*.test.sh | wc -l`
   (source-anchored; expected 44) against `git ls-files 'plugins/soleur/test/*.test.sh' | wc -l` (expected 88).

### Phase A1 — the vacuity repairs

The semantic half, and the part no other layer covers: an entry-point scrub only makes these cases
*accidentally* green for the right reason.

**The precondition needs a positive control, or it inherits the defect it fixes.** A bare "`git
rev-parse --git-dir` must fail" is satisfied by `git` missing from PATH, by the directory not
existing, and by a permission error — all while the case is as vacuous as before. The assertion is
three-part, run **under the subject's own environment and working directory**:

1. the same probe **succeeds** in a known repository,
2. it **fails** in the fixture directory,
3. the failure text names `not a git repository`.

**A1.1 — `plugins/soleur/test/proc.test.sh`, case T9 (`NOGIT`, at the `--- T9:` banner).**
The case asserts `rc9 -ne 0` and no `killed=[1-9]`. Both halves are satisfied by *any* failure:
`$HELPER` missing, a syntax error, or `git` absent all produce a green T9 that proves nothing about
"outside a git repo". Add an `assert_not_a_repo "$NOGIT"` immediately after the `mktemp -d`, run
under the **same** `env -u …` prefix the case itself uses, so the precondition and the subject see
one environment. Note the existing scrub names only `GIT_DIR` and `GIT_WORK_TREE` of the nine —
the precondition, not a widened `env -u` list, is what makes the case honest, because it asserts the
*outcome* rather than enumerating the *causes*.

**A1.2 — `plugins/soleur/test/fixture-dir-operand-assert.test.sh`.** Its non-repo arms follow the
same pattern. **This suite is one of the 14 repo-wide ratchets and its subject is
`assert_fixture_dir` byte-exactness** — the edit must not perturb its `$HELPERS` extraction, its
synthesized weak/drift fixtures, or its `passes`/`fails`/`VERDICT_LOG` harness. It also carries an
assertion floor; adding assertions raises the count, so the floor must be re-derived from a green
run in the same commit, never lowered.

**Both A1 suites keep their own harness.** Neither adopts `test-helpers.sh`:
`fixture-dir-operand-assert.test.sh` reads the canonical helper as *data* and sourcing it would put
the function under test into its own process; `proc.test.sh` has a 724-line harness with its own
mutation battery and assertion floor. A1's deliverable is the precondition, nothing else.

### Phase A2 — adopt the tripwire in the three measured suites

Sourcing is **not** additive, and the diff must account for it — with the measured remedy, not a
hope.

| Suite | Current `set` | Edit |
|---|---|---|
| `gitleaks-merge-commit.test.sh` | `set -uo pipefail` (no `-e`, deliberate) | bind `SCRIPT_DIR` above the `set` line; `source "$SCRIPT_DIR/test-helpers.sh"`; change the `set` line to `set +e -uo pipefail` |
| `harvest-debt.test.sh` | `set -uo pipefail` (no `-e`, deliberate) | same shape |
| `roadmap-reconcile.test.sh` | `set -euo pipefail` | bind `SCRIPT_DIR` above; `source "$SCRIPT_DIR/test-helpers.sh"`; **leave the `set` line alone** — it already runs `-e`, and adding `+e` would change its semantics in the opposite direction |

The `+e` must be co-located with the options declaration, with a one-line comment naming
`test-helpers.sh` as the reason, so a reader who deletes the source line also sees the `+e` that
became wrong. Each suite's own `pass`/`fail`/`ok` helpers and counters are defined **after** the
source and continue to win by redefinition; `roadmap-reconcile.test.sh` redefines the helper's
`assert_eq` and `assert_contains`, which is why the source must sit **above** those definitions.

**Verify, do not assume.** Each of the three must be re-run standalone after its edit and match its
M-1 count exactly (27/27, 19, 20) — an adoption that changes a pass count has changed behaviour.
Then each must abort `rc=97` under `GIT_DIR="$(mktemp -d)/hostile.git"` — a fresh path per run, never
a fixed shared one (`cq-ac-must-not-depend-on-concurrent-sessions`).

Record the new adoption count (**47 of 88**, source-anchored per M-11) in #7849. This advances #7849's exit condition.

**A2 does buy containment, and an earlier draft denied it on a false premise.** That draft said the
sweep "is not containment, because under the only runner that reaches these suites the entry-point
scrub has already removed every variable the tripwire would fire on." There is no such *only*
runner: **M-1 in this very plan invoked all three suites directly** — `bash plugins/soleur/test/<f>.test.sh`
— with no entry point and therefore no scrub. Direct invocation is how a developer runs one suite,
and it is the path with no layer-1 protection at all. Under it, A2 is the *only* thing standing
between an inherited `GIT_DIR` and a fixture's commits. The bookkeeping value is real but secondary.

### Phase A3 — the containment regression test

New file: `plugins/soleur/test/git-fixture-containment.test.sh`. Reached by `scripts/test-all.sh`'s
existing `plugins/soleur/test/*.test.sh` glob — **by naming, not by registration**, because
`scripts/test-all.sh` is a do-not-touch path.

**The oracle must include the child's exit code, or the test is false-green.** A swept suite sources
`test-helpers.sh`, so under a hostile `GIT_DIR` the tripwire fires and the child exits 97 *before
running any git write*. The victim is then trivially unchanged and the test passes — and it keeps
passing if an entry point's `unset` is removed, which is the single most likely real regression.

- **Refusal arm.** Tripwire armed, hostile environment set: assert the child exits **97**.
- **Containment arm.** Tripwire disarmed via `SOLEUR_GIT_TRIPWIRE_ALLOW=1`, hostile environment set:
  assert the child exits **0** *and* the victim's **HEAD, ref set, staged-file list and loose-object
  count** are unchanged.

The victim's observables are compared as a **quadruple**, not HEAD alone. Two independent reasons,
both measured: with `GIT_DIR` scrubbed, an absolute `GIT_INDEX_FILE` still retargets `git add` while
HEAD stays put (hence refs + index); and `GIT_COMMON_DIR` / `GIT_OBJECT_DIRECTORY` write the child's
objects **into the victim's object store while HEAD, refs and the index stay byte-identical**
(M-14) — a real breach the three-component oracle certifies as contained.

#### The two layers, because conflating them is what makes this arm meaningless

This is the crux of Phase A3 and it must be read before the arms below.

| Layer | Mechanism | What it does | What it does NOT do |
|---|---|---|---|
| **Refusal** | the `test-helpers.sh` prelude | Detects the nine location variables and `exit 97`s | **Never scrubs.** Its own comment: *"This ABORTS rather than unsetting."* |
| **Containment** | `unset GIT_DIR … GIT_EXEC_PATH` in `scripts/test-all.sh` | Removes the variables before any suite runs | Nothing detects; it is silent when it works |

**`SOLEUR_GIT_TRIPWIRE_ALLOW=1` disarms the refusal layer by ANNOUNCING and FALLING THROUGH — it
does not scrub.** Verified: the `if` branch of that prelude contains a single `printf` to stderr and
no `unset`; the nine-variable loop lives only in the `else`. So a swept suite run with
`ALLOW=1` and a hostile `GIT_DIR` keeps the hostile environment **fully intact**.

**Therefore: A2 buys refusal. It does not buy containment, and no amount of sourcing will.** The
containment arm is a test of `scripts/test-all.sh`'s `unset` line — a *different layer* — and if that
line is not in the child's invocation path, the arm is red from birth. That is exactly what M-10
measures. An earlier draft of this plan did not name the child's invocation path at all, which is
what hid the contradiction.

#### Three things that would make the containment arm unable to fail

Both were present in an earlier draft of this plan and are the reason this phase is specified in
this much detail.

**(1) The hostile environment must BE the victim.** Every hostile value measured elsewhere in this
plan is `GIT_DIR=/tmp/hostile-probe` — a path that resolves nowhere near the victim. That value is
correct for the *refusal* arm, which only needs the tripwire to see *a* location variable. It is
**fatal** for the containment arm: if the hostile `GIT_DIR` does not point at the victim, the
victim's triple **cannot move whether containment holds or not**, and Guard 1's M1 ("remove the
scrub → the victim's HEAD moves") cannot be driven red. The containment arm therefore sets

```
GIT_DIR="$VICTIM/.git"   GIT_WORK_TREE="$VICTIM"   GIT_INDEX_FILE="$VICTIM/.git/index"
```

which is the shape #7835 actually records. Guard 1 **M7** exists to pin this.

**(2) There must be a scrub in the path for the arm to be about.** The scrub the containment arm
depends on is the `unset GIT_DIR GIT_WORK_TREE … GIT_EXEC_PATH` line in `scripts/test-all.sh`
(verified present, immediately below its "cause test-spawned git commands to operate on the parent
repo" comment). That runner **cannot** be the child's invocation path: it takes only
`all|webplat|bun|scripts|infra` and has no single-suite mode, it refuses with **rc 4** under
`SOLEUR_SUBAGENT=1` without `SOLEUR_ALLOW_FULL_GATE=1`, and A3 nesting it inside its own run is
absurd. But invoking a swept suite *directly* means **no scrub exists anywhere in the path** — the
A2 suites carry none by definition — so the containment arm would be RED from birth.

A3 therefore builds a **sandbox copy of the scrub line** and invokes the child through that copy —
the `run_suite`-recorder technique already used by `plugins/soleur/test/fanout-suite-scope.test.sh`
and `scripts/test-all-infra-coverage-notice.test.sh`. Mutation **M1** is then well-defined and
mechanical: *delete the scrub line from the sandbox copy*. **Never invoke the real
`scripts/test-all.sh`** — it is a do-not-touch path and its full run is not this suite's subject.

**(3) The children are synthesized, not real swept suites.** `CHILDREN` holds **two** synthesized
fixture suites written into the sandbox (`cq-test-fixtures-synthesized-only`), each sourcing
`test-helpers.sh` and performing a git write. Pointing the arms at real A2 suites would make this
guard's verdict track unrelated churn in those suites, and would couple a containment proof to a
27-assertion gitleaks battery. Two children, because Guard 1 M4 needs a second member to break.

**Construction constraints, all measured (M-8, M-9):**

- The file **must not** `source test-helpers.sh` — it controls the tripwire, so sourcing it would
  abort this suite in the exact arms it exists to exercise. `git-tripwire.test.sh` carries the same
  constraint and states it in its own header; follow that precedent.
- **Prefer not to define `assert_fixture_dir` at all.** Every constraint in the next bullet is a
  *consequence* of defining a function with that name, not a requirement of the test. Bind fixture
  paths directly from `mktemp` in the scope that uses them — the P1b scanner already resolves
  `mktemp` in every form, so a file with no path-taking helper produces no row and joins no drift
  corpus. `run_child()` and `victim_quad()` take the **child path** and the **victim path** as
  parameters, so this needs care, not wishing: pass them, and guard them (next bullet), or hold them
  in the enclosing scope and let the helpers close over them.
- **If, and only if, the P1b scan produces a row after that**, add the guard — and then the full
  constraint applies: the inline copy **joins `fixture-dir-operand-assert.test.sh`'s repo-wide drift
  corpus** (`git ls-files '*.sh'`) and must be **byte-identical** to the canonical body in
  `test-helpers.sh`. Extract it with the same awk the guard uses rather than retyping it; do not
  redefine `exit`, `printf` or `return`. Place the call at the **enclosing function head** — the P1b
  window starts there, so one call at the top of the file does not cover a helper. Measure first;
  do not pre-commit to the copy.
- The hostile `GIT_DIR` **must never resolve under `$PWD`**, and the victim repository is a
  synthesized `mktemp -d` fixture — never the developer's worktree
  (`cq-test-fixtures-synthesized-only`).
- **The oracle reads git state, never the child's stderr.** Under `SOLEUR_GIT_TRIPWIRE_ALLOW=1` the
  helper prints `[git-tripwire] DISARMED by SOLEUR_GIT_TRIPWIRE_ALLOW=1 …` to stderr on **every**
  containment-arm invocation. A triple derived from child output rather than from the victim
  repository would be reading the wrong thing, and would drift the moment that message changes.
- **`exit 97` is a shared constant with copies in four places already** (`test-helpers.sh`,
  `git-tripwire.test.sh`'s `TRIPWIRE_RC`, AC17, T6); this file adds a fifth. Bind it once as a
  `readonly TRIPWIRE_RC=97` at the top, mirroring `git-tripwire.test.sh`, rather than inlining `97`.
- Carry an **assertion floor** and an **instrument self-test** in the shape
  `git-tripwire.test.sh` uses (drive `ok()`/`bad()` and the dispatcher once each, require both
  counters to move, then subtract). A battery that only mutates its subject cannot see a neutered
  harness.

#### Precedent — so nothing in A3 is invented

Deepen-pass finding: **three of the four idioms A3 needs already exist, and three specific
compositions do not.** Cite these rather than inventing; and treat the novel compositions as the
places to look hardest in review.

| Need | Precedent to copy | Status |
|---|---|---|
| Sandbox copy of a `scripts/test-all.sh` behaviour | `scripts/test-all-infra-coverage-notice.test.sh` `build_sandbox()`; `plugins/soleur/test/fanout-suite-scope.test.sh` `build_sandbox()` + `run_arm()` (its own header cites the former). Both `cp` the target, relocate its libs, and rewrite anchors through a `python3` heredoc that asserts the anchor occurs **exactly once** before replacing. `run_arm()` is the closest structural model for `run_child()`. | technique established; **scrub-line-as-wrapper is NOVEL** |
| Extracting the `unset GIT_…` line itself | `plugins/soleur/test/git-env-list-parity.test.sh` `scrub_list()` — strips comments with `sed 's/[[:space:]]*#.*$//'` then `grep -oE '\bunset[[:space:]]+GIT_[A-Z_ ]+'`. **Reuse this**; it is the derivation task 4.3c already calls for. | established (read-only) |
| Synthesizing a child suite on disk | `plugins/soleur/test/fixture-dir-operand-assert.test.sh` `synth()` — body arrives **on stdin via a quoted heredoc**, never as a single-quoted argument, because a multi-line single-quoted string reads as live code to the line-oriented scanners and self-flags the guard. `fixture-cd-containment.test.sh` uses the same convention. | writer established; **an executed shell child that sources `test-helpers.sh` is NOVEL** |
| Victim repo + before/after triple | `plugins/soleur/test/git-fixture-env.test.ts` `makeVictim()` / `read()` / `hostileEnv()` — **this is Guard 1's TypeScript half and it already does exactly what A3 must do in shell**, including setting `GIT_DIR=<victim>/.git` and `GIT_INDEX_FILE=<victim>/.git/index` (independent confirmation of "the hostile env IS the victim"). | exists in **TS only**; **the bash port is NOVEL** |
| Floor + instrument self-test | `plugins/soleur/test/git-tripwire.test.sh` — the AP-023 block (drive `ok`/`bad` once, require both counters to move, then subtract), **plus a separate dispatcher self-test** because `run_bun` sits *above* `ok`/`bad` and the counter self-test cannot see it. Shortest copyable form: `git-env-list-parity.test.sh`. Strongest accounting: `fixture-dir-operand-assert.test.sh`'s `$VERDICT_LOG` ledger cross-checked against the counters. | established — copy directly |
| Mutation battery | `plugins/soleur/test/proc.test.sh` `mutate()` / `expect_red()`; `git-fixture-env.mutation.sh` and `hook-git-env-coverage.mutation.sh` (`apply <row> <file> RED\|GREEN '<why>'` with an `EXPECTED_ROWS` floor and a pristine-restore check). | established — copy directly |

**Three precedent details that are load-bearing, not stylistic:**

- **`mutate()` must set a global, never echo.** `proc.test.sh` documents the reason inline: a
  `t=$(mutate …)` form put its `fail` call inside a command substitution, so the counter moved in a
  subshell and never in the parent. `expect_red()` also treats an **empty** oracle reading as a FAIL —
  *"a mutant that cannot RUN is not a detected mutation"*.
- **The victim read needs a fail-closed empty guard.** The TS precedent throws on
  `head === ""` with *"victim HEAD read empty — baseline is not established"*, and
  `git-fixture-env.mutation.sh` row **H2** exists specifically to prove that guard is load-bearing
  (it deletes the victim setup and requires RED). Port both the guard and the row: without it, a
  victim that failed to initialise reads as "unchanged" and the containment arm passes vacuously.
  **This is a mutation row the current matrix does not have** — add it as Guard 1 **M8**.
- **`git for-each-ref` appears in no `.sh` test in this repo.** The triple is a genuine port, so the
  exact command set is worth pinning here: `git rev-parse HEAD`,
  `git for-each-ref --format='%(refname) %(objectname)'`, `git diff --cached --name-only`.

### Phase A4 — CUT

Registering the new battery in `scripts/test-all.sh` is cut: that file is owned by five open PRs and
is a do-not-touch path. The obligation it discharged — *this plan's own battery must not ship
ungated* — is met by naming, and AC18 asserts the glob reaches it.

## Files to Create

- `plugins/soleur/test/git-fixture-containment.test.sh` — the A3 regression test (both arms,
  victim triple, inline byte-exact `assert_fixture_dir`, assertion floor, instrument self-test).

## Files to Edit

- `plugins/soleur/test/proc.test.sh` — A1.1 precondition at T9.
- `plugins/soleur/test/fixture-dir-operand-assert.test.sh` — A1.2 preconditions; re-derive its
  assertion floor.
- `plugins/soleur/test/gitleaks-merge-commit.test.sh` — A2 source + `set +e -uo pipefail`.
- `plugins/soleur/test/harvest-debt.test.sh` — A2 source + `set +e -uo pipefail`.
- `plugins/soleur/test/roadmap-reconcile.test.sh` — A2 source only.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — **only if** the A3 file legitimately
  produces a row after the per-function guards are in place, and then only with the row's
  justification in the commit message. **Never** via `--write-baseline`.
- `knowledge-base/INDEX.md` — regenerated, never hand-merged.

**Not edited, by hard constraint:** `scripts/test-all.sh`,
`plugins/soleur/test/test-helpers.sh`, `apps/web-platform/infra/workspaces-luks-loopback.test.sh`.

## Open Code-Review Overlap

**None.** Queried 2026-09-09: `gh issue list --label code-review --state open --limit 200` returns
**64** open issues; none names any of the seven paths in `## Files to Create` / `## Files to Edit`.
Check recorded so the next planner can see it ran.

## User-Brand Impact

Carried from the source plan's framing, which set this threshold for the same defect class.

- **If this lands broken, the user experiences:** a test suite that commits into their own
  repository. #7835 records the realized form: a fixture's writes rewrote a live branch tip and
  wiped the index. The user does not see a test failure — they see their work gone, from a command
  they ran to *check* their work.
- **If this leaks, the user's workflow is exposed via:** not a data leak but a **write-boundary**
  breach. An inherited `GIT_TEMPLATE_DIR` copies hooks into a fixture before any config is
  consulted, and an inherited `GIT_EXEC_PATH` is prepended to `PATH` for every subprogram git
  spawns — both are arbitrary code execution in the user's checkout, reached through a green test
  run.
- **Brand-survival threshold:** `single-user incident`. One occurrence is unacceptable: the harm is
  destructive, silent, and lands in the artifact the user trusts most.

`requires_cpo_signoff: true` is set. `user-impact-reviewer` is invoked at review time per the
review skill's conditional-agent block.

**The second-order risk this plan must not create.** A1 and A2 *add* assertions and *change*
failure semantics in suites that are green today. A regression introduced here lands in the same
blast radius as the defect being fixed. That is why every A2 edit is measured against its exact
pre-edit pass count (M-1) rather than against "still green".

## Observability

The Files-to-Edit are `plugins/soleur/test/*.test.sh` — outside plan Phase 2.9's code-class trigger
set (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`) and introducing no
infrastructure surface. They are not pure-docs either, so the section is written rather than skipped.
For a test-infrastructure change the observability surface **is** the guards' own exit codes, read by
`scripts/test-all.sh` and by CI; there is no runtime, no service and no log sink to instrument.

```yaml
liveness_signal:
  what: the three A2 suites, the two A1 suites and the A3 containment suite each exit 0 in CI
  cadence: every CI run, plus every local `scripts/test-all.sh` invocation
  alert_target: the CI job's own red/green (a failing suite fails the run; there is no separate alert)
  configured_in: scripts/test-all.sh SUITE_GLOBS `plugins/soleur/test/*.test.sh`

error_reporting:
  destination: the suite's stderr and its process exit code, surfaced by scripts/test-all.sh's per-suite verdict line
  fail_loud: >
    yes, and it is the whole point. The tripwire aborts rc=97 rather than warning; every floor in
    this plan reports with `printf >&2` + `exit 1` DIRECTLY rather than through a verdict helper
    (ADR-193), so a neutered harness cannot silence its own floor.

failure_modes:
  - mode: an inherited git-location environment reaches a swept suite
    detection: the test-helpers.sh prelude aborts rc=97 naming the variable and a remedy that clears it
    alert_route: the suite's non-zero exit; scripts/test-all.sh marks it [FAIL]
  - mode: the entry-point scrub is removed and a fixture writes into the caller's repository
    detection: the A3 containment arm's victim triple (HEAD, ref set, staged list) moves
    alert_route: git-fixture-containment.test.sh exits 1
  - mode: a "no repository here" case silently inverts and passes while proving nothing
    detection: the A1 three-part precondition fails its negative half, or its positive control fails
    alert_route: the owning suite exits 1
  - mode: the guards themselves are neutered (stubbed helpers, dead dispatch, narrowed corpus)
    detection: the assertion floors, the instrument self-test, the chokepoint floor and the variable-coverage floor
    alert_route: each reports directly to stderr and exits 1, never through the helpers it audits

logs:
  where: CI job output and local terminal; no persistent sink (these are test suites, not services)
  retention: GitHub Actions log retention for the run

discoverability_test:
  command: bash plugins/soleur/test/git-fixture-containment.test.sh
  expected_output: >
    both arms run, the assertion floor is satisfied, and the suite prints its summary and exits 0.
    No credentials, no network, no SSH — it builds its own victim and children under mktemp.
```

## Guard Contract

The deliverable **is** guards. The matrices below are written from the design, before the guards
exist — that ordering is the point of this section. Governed by
`ADR-193-anti-vacuity-floor-contract.md`: a floor reports with `printf >&2` + `exit 1` **directly**,
never through the suite's own `pass`/`fail` helpers, and a case counter increments at the **call
site**, never inside `$( )`.

### Guard 1 — the containment regression test (`git-fixture-containment.test.sh`)

**Property.** With a hostile git-location environment set and the tripwire deliberately disarmed, a
swept suite's git writes reach its own fixture and leave the victim repository's HEAD, ref set and
staged-file list byte-identical — and the child exits 0, not 97.

**Assembly.** Two chokepoints: `run_child()` — the only site that invokes a child suite — and
`victim_quad()` — the only site that reads victim state (HEAD, ref set, staged list, loose-object
count; see M-14 for why the fourth component is load-bearing). Both arms flow through both, so any future
arm is a member by construction; there is no second way to invoke a child or read the victim.

The property quantifies over a **cross-product of two real sets**, and both must be enumerable or
Guard 1's second-member row has no member to add:

- **The child set.** A2 converts **three** suites. `run_child()` takes the child suite path as a
  parameter and the arms iterate a `CHILDREN=( … )` array carrying **at least two** of them. An
  earlier draft hardcoded a single child, which made mutation M4 undriveable — there was no list to
  add a second member to. A guard that proves containment for one suite and is *claimed* for the
  sweep is exactly the "stops at the first member" defect.
- **The hostile-variable set, DERIVED at runtime — never hand-partitioned.** The tripwire refuses
  nine, but they do not share an oracle, and conflating them manufactures vacuity. An earlier draft
  of this plan hand-asserted a "write/ref-redirecting (7)" split. **M-13 falsified it**: which
  variables can move the victim triple depends on the *child's write shape*, so no fixed partition is
  correct. Under the canonical `git -C "$d" init && add && commit` child, **only `GIT_DIR`** moves the
  triple; under a child that writes a file into the victim's work tree, `GIT_INDEX_FILE` moves it too.
  A hand-written list would therefore have shipped up to six arms that **cannot fail** — the exact
  vacuity A1 exists to delete, re-introduced inside the guard that polices it.

  Measured baseline, so the calibration has an expected shape to check itself against: against the
  **quadruple** (M-14), `GIT_DIR` and `GIT_INDEX_FILE` move the first three components, and
  `GIT_COMMON_DIR` and `GIT_OBJECT_DIRECTORY` move only the fourth. `GIT_WORK_TREE` set *alone* is
  fatal to git (`fatal: GIT_WORK_TREE ... not allowed without specifying GIT_DIR`), which makes the
  child perform **no git write at all** — the most vacuous possible pass, and the reason `run_child()`
  needs the child-side positive control below. `GIT_NAMESPACE` takes a *name*, not a path, so no value
  of it can satisfy "the hostile environment must BE the victim" at all.

  So the suite **calibrates**: for each of the nine, and each child in `CHILDREN`, it runs the arm
  once with the sandbox scrub **removed** and records whether the quadruple moved.
  - Variables that move it form the **containment set** — the arm asserts the triple is unchanged
    *with* the scrub, and the calibration run is that assertion's positive control.
  - Variables that cannot move it under any child are covered by the **refusal** arm only, where
    "the suite must not run at all" is the right claim.
  - The suite **prints the derived partition** and floors on its size, so a variable silently
    dropping out of the containment set is visible rather than absorbed.
  `GIT_TEMPLATE_DIR` and `GIT_EXEC_PATH` will always land in the refusal-only class, and it is worth
  saying why rather than leaving it to the calibration: they are **code-execution** vectors, not
  write redirection — git copies `$GIT_TEMPLATE_DIR`'s hooks into a fixture before any config is
  read, and `$GIT_EXEC_PATH` is prepended to `PATH` for every subprogram git spawns. "The victim is
  unchanged" is simply the wrong question for them. Stated so a later reader does not "complete" the
  matrix by forcing them into the containment arm.

**Two floors make the Assembly structural rather than a snapshot** — without them, "there is no
second way to invoke a child or read the victim" is a claim about a file that nothing preserves, and
a `run_child()` parameterized over the variable but only ever *called* with `GIT_DIR` satisfies every
row in the matrix below:

- **Chokepoint floor.** The suite greps **its own source** and fails, reporting directly, if a git
  read verb or a child invocation appears outside `victim_quad()` / `run_child()`. This is the
  derivation shape `git-tripwire.test.sh` uses at its K4 *"one prelude per REGISTERED runtime
  (derived, not hand-copied)"* arm.
- **Variable-coverage floor.** The suite **derives** the nine location variables from
  `test-helpers.sh`'s `for _v in GIT_DIR …` loop — `plugins/soleur/test/git-env-list-parity.test.sh`
  already derives exactly that list across three languages, so reuse its derivation rather than
  hand-copying nine names — partitions them into the two classes above, and asserts the containment
  arm actually drove all **seven** and the refusal arm all **nine**. A hand-copied list drifts the
  day a tenth variable is added.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| M1 | Remove the entry-point `unset` the containment arm depends on | **RED** — victim HEAD moves. This is the real regression the guard exists for, and the one a victim-state-only oracle would miss. |
| M2 | **Differential, not RED.** Reduce the containment oracle to HEAD alone, hostile `GIT_INDEX_FILE` | The full-quadruple oracle goes **RED**; the HEAD-only oracle must be shown to **PASS**. Both readings recorded. Tabling this as a bare "RED" was a **polarity inversion**: weakening an oracle makes a guard *easier* to satisfy, so a HEAD-only oracle under `GIT_INDEX_FILE` is measurably GREEN. The evidence is the pair, exactly as AC14 already requires for the victim-state-only variant. |
| M3 | **Own dispatch:** make `run_child()` return 0 without invoking anything | **RED via the refusal arm's `exit 97` assertion**, which receives 0. **Not** via the assertion floor — an earlier draft said so and it is wrong: the arms still *run* under this mutation, only the child does not, so the comparison still executes, still passes, and the count never drops. The consequence is worth stating: if the refusal arm is ever reordered after the containment arm or its exit-code assertion softened, M3 stops being caught and the floor was never the net. |
| M4 | **Second member:** with `CHILDREN` carrying two children, break containment for the **second** only — **by editing child2's synthesized body to write at the victim by absolute path**. Naming the mechanism matters: the sandbox scrub is one `unset` line shared by both children, so it cannot be broken per-child, and the reader's default assumption (delete the scrub for child2) is unreachable. | **RED** — a check that stops at the first member is itself an instance of the class. Driveable only because `CHILDREN` is a real array; see Assembly. |
| M5 | **Reorder, not delete:** move the victim-state snapshot from *before* the child runs to *after* it | **RED — but only because of the comparator self-test below.** Left to the arms alone this mutation is **GREEN**: both snapshots become post-child and compare equal, and the chokepoint floor constrains *where* git reads happen, not *when*. The property is about a **window**, and nothing in the arms observes the window. The comparator self-test is what makes this row driveable; without it the row is prose. The snapshot must also be a **standalone statement** movable without breaking `set -u` binding order — the same constraint the floor block carries. |
| M6 | **Drop one variable from the derived containment set** (make the calibration skip it) while leaving the arms otherwise intact | **RED** via the partition floor — the derived set shrank. Two earlier drafts of this row were undriveable: one swapped `GIT_DIR` for `GIT_NAMESPACE` (M-13/M-14: `GIT_NAMESPACE` cannot move any component, and takes a name rather than a path so it cannot even aim at the victim), and the general "swap the variable" shape is redundant with M1 and M2 once the impossible members are struck. The mutation to fear is not "use a different variable", it is "quietly stop covering one". |
| M7 | **Point the hostile variable at a scratch path instead of at the victim**, scrub removed | **RED — via a new arm precondition, not via the arms.** An earlier draft tabled this as RED with no instrument, and its own prose admitted the arm *passes* under it. The row becomes real only when `run_child()` asserts, reporting directly, that the hostile value resolves under `$VICTIM` (`[[ "$hostile_value" == "$VICTIM"* ]]`). This is the guard on the guard, and it needs one line of assertion to exist at all. |
| M9 | **Add a tenth variable to a temp copy of the real `scripts/test-all.sh` `unset` line** | **RED** — the sandbox scrub must be **derived** from that file at runtime (using the extractor `git-env-list-parity.test.sh` already carries), never transcribed. A transcribed copy drifts silently the day a variable is added upstream, and the guard then certifies a scrub production no longer has, green forever. This is the only copy of that list in the design with no parity check, in a repo that already carries three. |
| M10 | **Neuter the synthesized child's `git commit`** so the child performs no git write | **RED** — via a child-side positive control asserting the child's **own** fixture HEAD/index advanced. Not hypothetical: with `GIT_WORK_TREE` set alone, every git call in the child fails `not a git repository` and the child still exits 0, so "child exits 0 and the victim is unchanged" is satisfied by a child that did nothing. |
| M8 | **Delete the victim's setup** so `victim_quad()` reads an empty HEAD | **RED** — an empty baseline compares equal to an empty after-reading, so an uninitialised victim makes the containment arm pass vacuously. Ported from `git-fixture-env.mutation.sh` row H2, which exists to prove exactly this guard is load-bearing. `victim_quad()` therefore refuses an empty HEAD with *"baseline is not established"* rather than returning it. |

**One instrument carries M2, M5 and H1's substitution case, and it must exist for them to be
assertions rather than prose: a comparator self-test.** Against a throwaway victim, the suite
advances HEAD, stages a file, creates a ref, and writes a loose object — asserting the comparator
reds **independently on each of the four components**. Without it, three rows above are hand-driven
claims about polarity that a weakened oracle satisfies silently.

**Harness rows.**

| # | Edit to the SUITE (not the guard) | Must |
|---|---|---|
| H1 | **Delete** the victim-quadruple assertion (not: substitute `true` for its expression) | **RED** via the floor, reported directly — not through `fail()`, which this edit could equally silence. The distinction is load-bearing and an earlier draft left it ambiguous: *deleting* the assertion drops the counter and the floor fires, but substituting `true` for the comparison **expression** leaves `ok()` firing and the count unchanged, which is **GREEN**. The substitution case is caught by the comparator self-test, not by the floor. |
| H2 | Stub the `ok()`/`bad()` counters to no-ops | **RED** — the instrument self-test drives both once and requires both counters to move before any arm runs. |
| H3 | **Must-PASS, non-canonical:** victim fixture rooted under a symlink that the test **constructs** (`ln -s "$real" "$link"`) | **PASS** — the canonical operand guard deliberately uses no `realpath` because a symlinked scratch root is a real configuration. The symlink must be **constructed**, not inherited: `/tmp` is a real directory on the machine of record (`stat -c %F /tmp` → `directory`), so a row relying on an ambient symlink would not exercise the case at all. |
| H4 | **Must-PASS, non-canonical:** containment arm where the child legitimately creates **and then deletes** its own fixture branch | **PASS** — the oracle is the *victim's* triple, not "no git activity occurred". A guard that reds here is reading the wrong repository. Replaces an earlier row that asserted identity/config variables are permitted: that is a property of `test-helpers.sh`'s variable list, this file does not source it, and `git-env-list-parity.test.sh` already enforces that list across all three languages. |

### Guard 2 — the A1 vacuity preconditions

**Property.** Every case asserting "this directory is not a repository" evidences its own premise:
the same probe, run under the subject's own environment and working directory, **succeeds** in a
known repository, **fails** in the fixture directory, and the failure text names
`not a git repository`.

**Assembly.** The chokepoint is one `assert_not_a_repo()` per suite, called at the head of each such
case. Structural membership: any case whose oracle is "the subject failed" and whose fixture is a
bare `mktemp -d` is a member. Current members are `proc.test.sh` T9 (`NOGIT`) and the non-repo arms
of `fixture-dir-operand-assert.test.sh`. The probe must run under the **case's own** `env -u …`
prefix, not the suite's ambient environment — a precondition evaluated in a different environment
from its subject certifies nothing about the subject.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| M1 | Remove `git` from `PATH` for the probe | **RED** — the positive-control half fails. Without it, a bare non-zero exit is satisfied by a missing binary and the case is as vacuous as before. |
| M2 | Point the fixture directory at a real repository | **RED** — the negative half fails. |
| M3 | Set a hostile `GIT_DIR` for the case | **RED — but the mutation must land in the CASE, not the process.** This lands directly on the `fixture-dir-operand-assert.test.sh` member, which carries no `env -u`. It does **not** land on `proc.test.sh` T9 by exporting `GIT_DIR` before the suite: T9's own `env -u PROC_SH_WORKTREE -u GIT_DIR -u GIT_WORK_TREE` prefix strips it before both the subject *and* (per A1.1) the precondition, so an operator running `GIT_DIR=… bash plugins/soleur/test/proc.test.sh` gets a green suite and wrongly records "M3 caught". For T9 the mutation is an **edit to the prefix itself** — drop `-u GIT_DIR` and inject a hostile value inside the `env` — and is tabled as its own class. |
| M4 | **Own dispatch:** make `assert_not_a_repo()` a no-op | **RED via the same structural derivation M5 uses**, *not* via the assertion floor. The tension is real and is resolved here rather than left implied: `proc.test.sh` carries an absolute `MIN_ASSERTIONS` whose header documents the slack as **deliberate budget for added arms**, so a no-op that drops a handful of assertions can stay above it. Tightening that floor to catch M4 would fight the suite's own stated convention and would redden on every future added arm. **The floor keeps its slack; the derivation carries both M4 and M5.** The suite enumerates its non-repo fixtures and asserts a precondition ran for each — a no-op'd `assert_not_a_repo()` fails that count, reported directly. |
| M5 | **Second member:** add a second non-repo case after a compliant first and omit its precondition | **RED — and NOT via the assertion floor.** An earlier draft claimed the floor catches this; it does not. The floor is a shrink-only `>=` ratchet, so an *added* case with no precondition leaves the count higher than before and the floor passes. The mechanism must be **structural**: the suite derives its non-repo fixture set (every `mktemp -d` bound to a name matching the suite's non-repo convention) and asserts a precondition exists for **each**, reporting directly. Without that derivation the row is undriveable. |
| M6 | Weaken the text match to "any stderr output", **paired with a permission-denied fixture** | **RED only as that composite.** Weakening an assertion alone cannot red a suite — a **polarity inversion**, and without a fixture whose probe fails with non-`not a git repository` stderr the weakened match is never discriminated against and the row is GREEN. The permission-denied fixture is what gives it a kill. Note the overlap with M1 (a missing `git` binary is also "stderr that is not `not a git repository`"); the two share the positive control, so score them as one axis. |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | **Composite:** delete an assertion **and** lower the floor to match | **RED via the structural precondition-coverage check (2.4b), NOT via any ratchet.** An earlier draft tabled "lower the floor" alone as RED. That is **GREEN**: lowering a `-lt` threshold makes a suite easier to pass, and nothing pins floor *values* — `scripts/guard-vacuity-floor.test.sh` verifies a floor **fires under neutered assertion machinery** and reports directly; it never compares a threshold to a baseline, and no ratchet does. The detector is the derivation, which notices a non-repo fixture with no precondition regardless of what the floor says. |
| H2 | **Must-PASS:** fixture directory created under `TMPDIR=/var/tmp` instead of `/tmp` | **PASS** — the contract is about repo-ness, not about a particular scratch root. |

## Acceptance Criteria

### Pre-merge (PR)

AC13-AC15 are carried verbatim in substance from the source plan's "PR 2 (A1-A3)" block; the rest
are new and come from this plan's measurements.

1. **AC13 (the sweep is complete against a pinned predicate).** The PR body carries the three
   predicate clauses **verbatim**, their raw scoped output, their raw repo-wide output, and the
   `.claude/hooks/` sub-count — each produced by running the pasted command, not recalled. The raw
   scoped output is a **superset**; the PR body names the hand-filtering step and records each
   member's disposition, so the screen is re-runnable and the judgement is auditable separately.
   Each of the three A2 suites sources `test-helpers.sh` and
   **each still passes with its exact pre-edit count**: 27/27, 19, 20 — and the PR body records the
   pre-remedy reading beside it (`gitleaks-merge-commit` rc=1 under a naked source), because a
   post-remedy green alone does not show the hazard was real. `harvest-debt` and
   `gitleaks-merge-commit` carry `set +e -uo pipefail`; `roadmap-reconcile` keeps `set -euo pipefail`
   unchanged. **(absorbs the former AC16.)**
2. **AC14 (containment is demonstrated, and refusal is not mistaken for it).** The A3 test's
   **refusal arm** asserts the child exits 97. Its **containment arm**, run under
   `SOLEUR_GIT_TRIPWIRE_ALLOW=1`, asserts the child exits 0 *and* the victim's HEAD, ref set and
   staged list **and loose-object count** are unchanged (the fourth component is load-bearing — see
   M-14). **The containment set is DERIVED by calibration, not hand-written**
   (M-13: the partition is a function of the child's write shape, so any fixed list is wrong for some
   child): for each of the nine and each child, the suite runs once with the sandbox scrub removed,
   records whether the triple moved, and prints the derived partition. Every calibration reading
   appears in the PR body; the refusal arm covers all nine. Without this, `run_child()`'s variable
   parameter is exercised once with `GIT_DIR` and is indistinguishable from a hardcoded value. **A version asserting only the victim state must be shown to pass with
   the sandbox scrub line removed, and a HEAD-only oracle must be shown to pass under a hostile
   `GIT_INDEX_FILE`** (the differential form; a bare "must go RED" on a weakened oracle is a polarity
   inversion) — that demonstration is the evidence AC14 requires, and its
   before/after readings go in the PR body. This is mutation M1 + M2 of Guard 1.
3. **AC15 (vacuity is repaired, with a positive control — with readings, not prose).** For each
   named case the PR body carries **three recorded readings**: the probe **succeeding** in a known
   repository, **failing** in the fixture directory, and the failure text containing
   `not a git repository`. Plus the driven verdicts for Guard 2 M1-M6 — noting that M3 lands on
   `fixture-dir-operand-assert.test.sh` directly but on `proc.test.sh` T9 only via an edit to its own
   `env -u` prefix (exporting `GIT_DIR` before that suite is stripped by the case and yields a false
   "caught"). Each named case asserts, under the
   subject's own environment and working directory, that the probe succeeds in a known repository
   and fails in the fixture directory with text naming `not a git repository`. Each fails when its
   precondition does not hold, including under a hostile `GIT_DIR` (Guard 2, M1-M3).
4. **AC17 (the tripwire actually fires through the adopted composition).** Each of the three suites,
   run with `GIT_DIR="$(mktemp -d)/hostile.git"`, exits **97** and prints a `FATAL` line naming the
   variable. Asserted per-suite, not once. **Not a fixed `/tmp/hostile-probe`**: two concurrent
   sessions racing one shared path is the shape `cq-ac-must-not-depend-on-concurrent-sessions` and
   `cq-test-fixtures-synthesized-only` both exist to prevent. The same applies to T6.
5. **AC19 (the do-not-touch constraint holds).** `git diff --name-only origin/main...HEAD` contains
   **none** of `scripts/test-all.sh`, `plugins/soleur/test/test-helpers.sh`,
   `apps/web-platform/infra/workspaces-luks-loopback.test.sh`. Asserted **before** `gh pr ready`.
   Hard blocker.
6. **AC20 (the exit condition is named, not implied).** The PR body states that the sweep discharges
   **no** exit condition outright; that it advances #7849's re-evaluation trigger 2 (full
   `test-helpers.sh` adoption across `plugins/soleur/test/*.test.sh`) from **44/88 to 47/88**
   (source-anchored — the naive `grep -l` figure of 51 counts mentions); that
   **#7849 stays open and is not in `closes:`**; that **#7835 is closed by A3** (whose containment
   arm reproduces the exact incident it reports) while **#7822 is `Ref` only** — its ten enumerated
   files are disjoint from the sweep set and one is a do-not-touch path; and it names both the
   `.claude/hooks/` residue and the four unscrubbed TypeScript fixtures as explicitly out of scope,
   carried by the residue issue.
7. **AC21 (the ratchets are green, and the baseline was not laundered).** All **15** repo-wide ratchets — the brief's 14 plus `scripts/lint-shell-capture-exit-live` —
   pass. `fixture-relative-assert.test.sh` is green **without** `--write-baseline`. If
   `fixture-relative-assert.baseline.txt` changed at all, the diff shows the added rows and the
   commit message justifies each; a header-only or wholesale rewrite is a reject.
8. **AC22 (the new suite survives the meta-guard).** `scripts/guard-vacuity-floor.test.sh` is green.
    `COVERED_DIRS` is `^(scripts/|plugins/soleur/test/)`, so the A3 file is mutation-classified, not
    deferred: its floor block must be independently runnable and must report with `printf >&2` +
    `exit 1` directly, per ADR-193.
9. **AC23 (both `fixture-dir-operand-assert` arms; byte-exactness only if a copy is added).**
    Its strict **`SITES_LIVE == ACK_TOTAL` equality arm** is green — no new unasserted operand site in
    the A3 file — and its repo-wide byte-exactness corpus is green.
    The A3 file **preferably defines no `assert_fixture_dir` at all**; if it does not, this AC is
    satisfied by `grep -c 'assert_fixture_dir()' <the A3 file>` returning **0**, which is the better
    outcome and not a shortfall. **If** the P1b scan produces a row and the operand guard is therefore
    added, the inline copy must be byte-identical to the canonical body in `test-helpers.sh` and the
    file must redefine none of `exit`, `printf`, `return`.
10. **AC24 (the shell arm's subject did not move).** The subject is **stable across the sweep** —
    asserted as before-equals-after, **not** against a literal filename. Measured: the value is
    locale-dependent (`auto-close-scanner.test.sh` under `en_US.UTF-8`,
    `_base-notice-frontmatter.test.sh` under `LC_ALL=C`, since `_` is 0x5F < `a`), and
    `git-tripwire.test.sh`'s own `sort` is **unpinned**, so its subject already moves with the
    runner's locale. Pin `LC_ALL=C` in the AC's own comparison — the idiom
    `scripts/lint-orphan-test-suites.sh` uses for exactly this class — and compare the two readings.

11. **AC26 (the guard's own load-bearing structure is asserted, not assumed).** Four things the Guard
    Contract makes load-bearing and no other criterion covered:
    (a) `CHILDREN` holds **at least two** members with **different write shapes** — M4's entire
    drivability rests on it;
    (b) the **comparator self-test** runs and reds independently on each of the four oracle
    components — M2, M5 and H1's substitution case are prose without it;
    (c) the **chokepoint floor** and the **variable-coverage floor** both exist and fire (AC22's
    meta-guard checks only the ADR-193 *report shape*, never that these two specific floors exist);
    (d) the sandbox scrub is **derived** from `scripts/test-all.sh` at runtime and matches it — the
    M9 drift row.

### Post-merge

12. **AC25.** The new adoption count (47/88, source-anchored) is posted to #7849 as a comment. #7849 is **not**
    closed.

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed (inline, by direct measurement rather than by delegation — this is a
shell-test-infrastructure change with no product, legal, financial, marketing, sales, support or
operations surface).

**Assessment:** The change is confined to `plugins/soleur/test/`. It adds no runtime code path, no
dependency, no infrastructure, no persistent store, no network call, and no user-facing surface. The
engineering risk is concentrated in exactly one place — that A2 changes the shell options of two
suites that are green today — and that risk was measured at plan time and closed with a measured
remedy (M-2 through M-5) rather than deferred to implementation. The secondary risk is the
interaction with three repo-wide ratchets (`fixture-relative-assert`, `fixture-dir-operand-assert`,
`guard-vacuity-floor`), each of which is named with its exact mechanism and its exact constraint.

### Product/UX Gate

**Not applicable.** The mechanical UI-surface override was evaluated against `## Files to Create`
and `## Files to Edit`: every path is a `*.test.sh`, a `*.baseline.txt`, or `knowledge-base/`. No
path matches any UI-surface term or glob, so the override does not fire, and the semantic sweep
finds no Product relevance. Tier **NONE**; no wireframe is owed.

## Gates evaluated and skipped, with reasons

Recorded rather than silently skipped, so a reviewer can check the judgement. **In one line:** no
runtime code, no infrastructure, no persistent store, no regulated-data surface and no UI surface, so
gates 1.4, 2.7-2.11 and 2.9.1 have no trigger. The per-gate rows below exist because a bare "no
trigger" is indistinguishable from "not evaluated".

| Gate | Verdict |
|---|---|
| 1.4 Network-outage checklist | **Skip.** No trigger token in the feature description, and no `provisioner`/`connection` block in scope. |
| 2.7 GDPR / compliance | **Skip.** No regulated-data surface: no schema, migration, auth flow, API route or `.sql`. None of the four expansion triggers fires — no LLM/external-API processing, no new cron reading `learnings/` or `specs/`, no new distribution surface. The `single-user incident` threshold is declared, which *is* trigger (b) — evaluated and found to concern a **write-boundary**, not personal data. |
| 2.8 Infrastructure-as-Code routing | **Skip.** No server, service, cron, vendor account, DNS record, cert, secret or firewall rule. No detection phrase present. |
| 2.9 Observability | **Skip.** Files-to-Edit are `plugins/soleur/test/*.test.sh` — none under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/` or `plugins/*/scripts/`, and no new infrastructure surface. The guards' own signal is their exit code, read by `scripts/test-all.sh`. |
| 2.9.1 Soak follow-through | **Skip.** No acceptance criterion is time-gated; nothing here closes on a soak. |
| 2.10 ADR / C4 | **Skip.** No architectural decision. The change adds a `source` line to three suites, preconditions to two, and one test file; it introduces no ownership or tenancy boundary, no substrate, no resolver or trust boundary, and reverses no ADR. It **conforms to** ADR-193 and ADR-129 rather than amending either. No external human actor, external system, container, data store or access relationship changes, so the C4 completeness rubric has no member to add — and no `model.c4` cardinality moves, because no monitor, workflow or heartbeat slug is added. |
| 2.11 Encryption posture | **Skip.** No persistent store and no new cross-component connection. |
| 4.5 Scoped advisor consult | **Run inline.** The riskiest phase (A2) was resolved by measurement, which is strictly better evidence than a second opinion on unmeasured prose; the remaining design forks (A3's arm structure, the inline-vs-source fork for `assert_fixture_dir`) were each decided against a probed constraint (M-8, and `git-tripwire.test.sh`'s own stated precedent). Recorded so the skip is deliberate. |

## Out-of-scope, with decisions recorded

### ADR-194 `ssl="full"` deferred cleanup

**Untouched.** Still deferred until the rollback window closes. The orphaned
`scheduled-gh-pages-cert-state` monitor reporting `disabled` in Sentry (55/56 healthy) is the
**expected** state, not a new fault. No action, no investigation, no issue.

### The Incident-PIR precedent-citation gate — DECISION

The brief requires a decision in this run rather than a wait. **Decision: the fixture discharges the
remaining criterion. The issue can be closed on that basis; closing it is not this PR's work.**

- The code fix merged to `main` 2026-09-05. It is not reopened and not re-examined.
- The remaining criterion was *a behavioural observation at the next `/ship`*. PR 1's ship did not
  provide one, and the reason is structural rather than unlucky: the **pre-fix** gate was measured
  against that same PR and was **also** silent, so the PR never exercised the path. An observation
  that both the fixed and unfixed gate produce identically carries **zero** information about the
  fix.
- A chance observation is a sample of opportunity. It can only ever confirm on a PR that happens to
  contain the shape, it has no positive control, and — as PR 1 demonstrated — it cannot distinguish
  "the fix works" from "the path was not reached".
- `plugins/soleur/test/fixtures/ship-incident-pir-gate/precedent-citation-inside-hypothetical-paragraph.md`
  pins the same property deterministically and adversarially: **pre-fix FIRES, post-fix silent, both
  already measured.** It is consumed by `scripts/ship-incident-pir-gate-mutation.test.sh` and
  `plugins/soleur/test/ship-incident-pir-gate.test.ts`, and reached by `scripts/test-all.sh`, so it
  re-runs on every CI cycle rather than once.
- The fixture is therefore **strictly stronger** evidence than the criterion asked for: it has the
  positive control the chance observation structurally cannot have, and it is repeated rather than
  single-shot. Waiting for a chance observation would trade better evidence for worse, on a timeline
  nobody controls.

**Recorded, not acted on:** this PR does not close that issue, does not edit the gate, and does not
edit the fixture.

### The `hook_self_fault` detector issue

**Untouched and stays open.** PR 1 served it partially; it is out of scope here and is not
mentioned in `closes:`.

## Test Scenarios

Each is a command with a checkable post-condition, not a phase-output audit.

| # | Command | Expected |
|---|---|---|
| T1 | the predicate snippet, run scoped (a pasted command — no committed file) | the four-member set; any delta restated in the PR body |
| T2 | the same snippet, run repo-wide | a total and a `.claude/hooks/` sub-count, both printed |
| T3 | `bash plugins/soleur/test/gitleaks-merge-commit.test.sh` | rc=0, **27/27** |
| T4 | `bash plugins/soleur/test/harvest-debt.test.sh` | rc=0, **19 passed** |
| T5 | `bash plugins/soleur/test/roadmap-reconcile.test.sh` | rc=0, **20 passed** |
| T6 | `GIT_DIR="$(mktemp -d)/hostile.git" bash plugins/soleur/test/<each A2 suite>` | rc=**97**, `FATAL` names the variable |
| T7 | `bash plugins/soleur/test/proc.test.sh` | rc=0, floor re-derived, T9 carries its precondition |
| T8 | `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` | rc=0, floor re-derived |
| T9 | `bash plugins/soleur/test/git-fixture-containment.test.sh` | rc=0; both arms ran; comparator self-test, chokepoint floor, variable-coverage floor and assertion floor all satisfied |
| T10 | Guard 1 **M1-M10** and H1-H4, driven by hand | each RED / PASS / differential-pair as tabled; every reading in the PR body |
| T11 | Guard 2 M1-M6 and H1-H2, driven by hand | each RED / PASS as tabled |
| T12 | `bash plugins/soleur/test/git-tripwire.test.sh` | rc=0; its shell arm's subject unchanged (AC24) |
| T13 | `bash plugins/soleur/test/fixture-relative-assert.test.sh` | rc=0, **no** `--write-baseline` |
| T14 | `bash scripts/guard-vacuity-floor.test.sh` | rc=0, A3 file classified, not deferred |
| T15 | the AC19 do-not-touch grep | prints `OK: none of the three touched` |

**When `TEST_GROUP=all` is refused** (rc 4, no marker, sibling full-gate run in flight): its own
message — "run the suite covering your files instead" — is **not sufficient**. On PR 1 that advice
missed a repo-wide ratchet CI then caught. Run the change-covering suites **and all 14 ratchets**:
`.claude/hooks/hookeventname-coverage`, `.claude/hooks/settings-hook-exec-bit`,
`.claude/hooks/skill-context-queries`, `plugins/soleur/test/fixture-cd-containment`,
`plugins/soleur/test/fixture-dir-operand-assert`, `plugins/soleur/test/fixture-relative-assert`,
`scripts/follow-through-closure-guard`, `scripts/followthrough-exec-bit`,
`scripts/guard-vacuity-floor`, `scripts/lint-dual-lockfile`, `scripts/lint-orphan-test-suites`,
`scripts/lint-shell-trace-credential-refusal`, `scripts/lint-trap-tempfile-ownership`,
`scripts/test-all-infra-coverage-notice`.

## Risks & Sharp Edges

- **`set -uo pipefail` does not clear `-e`; only `set +e` does.** This is the single highest-value
  finding in this plan and it inverts the intuitive reading. Sourcing `test-helpers.sh` (which runs
  `set -euo pipefail`) into a suite whose own line is `set -uo pipefail` leaves `-e` **on** for the
  whole suite. Measured: `gitleaks-merge-commit.test.sh` goes 27/27 → rc=1, dying in its first case,
  because it is a mutation-proof suite whose cases *expect* non-zero returns inline. The remedy —
  `set +e -uo pipefail` — is measured green in this plan, and it must be co-located with a comment
  naming `test-helpers.sh`, so that whoever deletes the source line also sees the `+e` that became
  wrong.
- **The learnings pass recommended the opposite of the measured answer, and it must not be
  followed.** It advised "upgrade all three suites to `set -euo pipefail`". That is precisely the
  change measured to break `gitleaks-merge-commit.test.sh`. Recorded here because the recommendation
  is plausible, is in the institutional record, and would be reached again by anyone reasoning from
  convention rather than running the suite.
- **The same pass suggested sizing the A3 fixture for concurrency ("13,815 files").** Rejected: the
  `GIT_DIR` inheritance vector is environmental, not size- or concurrency-dependent. A one-commit
  victim reproduces it deterministically — measured, all three suites abort `rc=97` on a bare
  `GIT_DIR=/tmp/hostile-probe`. Do not gold-plate the fixture.
- **SIGPIPE under `pipefail` fails on an EARLY match, not a late one.** `producer | grep -q` has
  `grep` exit at the first hit, close the pipe, the producer take SIGPIPE (141), and `pipefail`
  promote it to the pipeline's status. The intuition is backwards. The A3 victim-triple oracle reads
  refs and the staged list — **capture to a variable first**, then match, so there is no reader to
  quit early.
- **`test-helpers.sh` registers no EXIT trap** — verified, so ADR-129's one-trap-per-script
  collision does not arise for the three A2 suites, each of which registers its own. Re-verify if
  the helper ever gains one.
- **`fixture-relative-assert` compares row by row, keyed by file path.** `FILES` is a `>= 900`
  floor, so a new file is harmless; a single unresolved-operand **site** inside it creates a new
  **row** and reddens the equality arm. The guard window starts at the **enclosing function head**,
  so a single call at the top of the file does not cover a helper — per-function calls are needed.
  **Never** take its `--write-baseline` remedy: that launders real findings.
- **The inline `assert_fixture_dir` in the A3 file joins a repo-wide byte-exactness corpus.**
  `fixture-dir-operand-assert.test.sh` builds its drift corpus from `git ls-files '*.sh'`, matching
  any tracked `.sh` that *defines* the function. Extract the canonical body with the same awk the
  guard uses rather than retyping it, and do not redefine `exit`, `printf` or `return` in that file.
- **An anti-vacuity floor must not be dispatched through the helpers it backstops** (ADR-193). A
  floor that calls `fail()` is silenced by the same edit that neuters `fail()`. Report with
  `printf >&2` + `exit 1` directly, and increment case counters at the call site, never inside
  `$( )` — a subshell discards the increment.
- **`guard-vacuity-floor.test.sh` mutation-classifies the new file.** `COVERED_DIRS` is
  `^(scripts/|plugins/soleur/test/)`, so the A3 file is in the covered scope: its floor block must
  be **independently runnable**, because the mutant is built by widening backward over contiguous
  simple assignments and an unbound variable under `set -u` kills the mutant before it reaches the
  floor — scoring a compliant floor as a construction failure. `git-tripwire.test.sh` documents this
  exact hazard at its `VITEST_ARM_RAN=${VITEST_ARM_RAN:-0}` re-bind; follow that shape.
- **A delete-only mutation battery certifies a property about a window it never tested.** Guard 1's
  M5 is a **reorder**, not a delete, for this reason: deleting the victim snapshot reddens any arm
  that reads it at all, while *moving* it to after the child runs reddens only a guard that actually
  observes the window the property is about.
- **`GIT_EDITOR` is not a git-location variable.** The ambient environment carries it, and a naive
  `GIT_[A-Z_]+` exclusion in a sweep predicate matches it — which is one of the ways the repo-wide
  count moved between 17, 30 and 41. The predicate names the **nine** variables the tripwire
  refuses, explicitly.
- **`knowledge-base/INDEX.md` conflicts on essentially every merge of `origin/main`.** Resolve
  **only** by re-running `bash scripts/generate-kb-index.sh`; never hand-merge. Expect 3-5 resyncs —
  `main` merges faster than a CI cycle and branch protection requires up-to-date.
- **Five open PRs contend for `scripts/test-all.sh`.** The A4 cut is not a stylistic preference; it
  is the reason this PR can merge at all. Re-derive the owner set before `gh pr ready` rather than
  trusting this table.
- **A 15th repo-wide ratchet the brief's list omits: `scripts/lint-shell-capture-exit-live`.**
  Registered in `scripts/test-all.sh` beside its own suite, it walks `git ls-files -z '*.sh'`
  **repo-wide** and is suppressed only by a file+code+text fingerprint baseline. Its subject is
  exactly what A3 will write — `x=$(grep …)`, `git … | grep -q`, `… | wc -l` where non-zero is a
  normal answer. Any such site in a new file is an un-baselined finding and reds it. This compounds
  the SIGPIPE bullet above: the remedy is the same capture-then-match discipline, but it must be run
  as a **gate**, not followed as advice.
- **`fixture-dir-operand-assert.test.sh` carries a SECOND arm the plan's M-8 does not describe: an
  EXACT `SITES_LIVE == ACK_TOTAL` equality**, with an explicit *"HIGHER: a new unasserted site
  appeared — fix it, do not regenerate"* failure path and a `NAMED_WANT=8` pin. It is **stricter**
  than the P1b row-equality arm, because the population is one file and equality binds in both
  directions. A single `git -C "$x"` in a new file whose operand is not provably absolute takes it
  8 → 9 and hard-fails. The remedy is a guarded operand, **never** a baseline row. Its
  `copies -lt 1` check is a floor, not a ceiling, so an added inline copy is safe.
- **`fixture-cd-containment.test.sh` is an A3-only constraint the plan nearly missed.** Its rule
  fires when three things hold together: no `set -e` in scope, an unguarded `cd`, and a following
  git **write** spelled without `-C`. A3 will run `set -uo pipefail` (it must survive non-zero child
  returns) and will do git writes, so a bare `cd "$VICTIM"` before one trips it. Every A3 git write
  is `git -C "$dir"` preceded by an operand guard, or `cd … || exit`. A2 adds no `cd` sites and is
  neutral here.
- **Four failure paths that must not dead-end.** Each is given a branch rather than a diagnosis:
  - *Phase 0.1, the predicate returns a different set* → the PR body restates the sweep and explains
    the delta. AC13 is worded to permit this (it asserts the output and the plan's set are both
    published, not that they are equal) — an earlier wording asserted equality and would have
    contradicted this branch.
  - *Phase 0.3, the ambient environment carries a location variable* → re-exec the phase under
    `env -u <the nine> bash …` and record that you did. Do not proceed on a void measurement.
  - *Phase 3.4, a swept suite's count ≠ its Phase 0.2 count* → **revert that suite's A2 edit**,
    record the delta as a finding, and ship the other two. A2 is bookkeeping plus direct-invocation
    containment; dropping one member costs a number in AC20, not a property.
  - *Phase 5.4, `guard-vacuity-floor` still red after the `VITEST_ARM_RAN`-style re-bind* → hoist the
    floor block's variable bindings **into** the block so the mutant is self-contained.
- **Use `Ref #7849`, never `Closes #7849`.** The sweep advances its exit condition by three suites
  and leaves 34 unconverted. Auto-closing it would delete the only tracking anchor for the remaining
  adoption.
