# Decision Challenges — feat-one-shot-7833-git-dir-beats-cwd

Recorded headless per ADR-084. These are places where planning concluded the operator's **stated
direction** should change. The operator's direction is the default; nothing here is applied as
settled, and `/ship` renders this into the PR body and files it as an `action-required` issue.

---

## Challenge 1 — the detector does not go in the fixture-safety scanner family

**Your direction.** "Detector added to the fixture-safety scanner family
(`plugins/soleur/test/lib/fixture-scan.py` + its `.test.sh` + `baseline.txt` pattern): flag a test
that spawns `git` without scrubbing `GIT_DIR`. Note that shell-based tests (`.test.sh`) and Python
scanners can carry the same defect, not only TypeScript."

**What I found.** Three things, each measured:

1. The corpus that rule would need is **not enumerable**. `git grep -l 'git init' -- '*.test.ts'`
   returns 5, but the `execFileSync("git", ["init", …])` array form appears in ≥10 more, python
   list-form spawns (`subprocess.run(["git", "init", …])`) match no `git init` grep at all, and real
   test suites live under `test-*.sh` and in `test/helpers/*.ts`, which a `*.test.sh` / `*.test.ts`
   corpus is structurally blind to. A guard whose population cannot be counted ships a permanent
   grandfathering ledger.
2. A source-shape rule **cannot see the actual hazard in most suites**: they shell out to repo
   scripts that spawn `git` themselves, and the test file's text says nothing about those.
3. All four recurrences of this class (2026-03-24 #1090, 2026-04-03 ×2, now #7833) entered through a
   **hook entry point that lacked the scrub**, never through a test file that lacked a helper. That
   set is closed and tiny: 26 `run:` lines in `lefthook.yml` across two hooks, of which 2 invoke a
   test runner, plus 2 files under `scripts/hooks/`.

**What the plan does instead.** Keeps a detector, re-aims it: a ~30-line standalone guard over the
hook entry points (no baseline needed, because the set is closed), plus a **fail-loud runtime
tripwire** in each runner's prelude that aborts the process if a git-location variable is present at
start. The tripwire covers what no source scan can — transitive script spawns, and entry points
nobody enumerated (an agent shell, `git rebase -x`, an editor's runner). Measured working: a
`bunfig.toml` `[test] preload` aborts the run with rc=97 when `GIT_DIR` is set, rc=0 clean.

**Cost of doing it your way instead.** Roughly +1,200 LOC (a new rule in a 1,015-line shell-lexical
scanner, a ~600-line driver, a ~360-row baseline), a corpus extension that risks perturbing the three
existing rules, and coverage that is strictly *smaller* — it would still miss every transitive spawn.

**What would change my mind.** If you want the shape rule as an additional layer for its
documentation value, it is cheap to add later against an already-converted corpus, where the real
call forms are visible. It is not a good first instrument.

---

## Challenge 2 — the "adopt the helper at every git-spawning site" sweep is deferred, not done

**Your direction.** "Shared helper adopted across every git-spawning test site" — and
`hr-write-boundary-sentinel-sweep-all-write-sites` was cited as applying.

> **Superseded 2026-09-04 (review).** The claim below that "with the entry-point scrub and the
> runtime tripwire in force, none of them can observe a hostile environment in any reachable
> invocation" was FALSIFIED by the review panel and is retracted. Three reachable gaps existed at
> the time it was written: the python arm had no tripwire at all (there was no `conftest.py`
> anywhere in the repo); `cd plugins/soleur && bun test` loaded no preload, because bun resolves
> `bunfig.toml` from the invocation cwd — and `grok-fidelity-gate.sh` does exactly that `cd`; and
> the five `skills/git-worktree/test/*.test.sh` suites, which drive `worktree remove`, `branch -D`
> and `reset --hard`, sourced no prelude. All three are now closed in this PR rather than deferred,
> along with a live bare-`cd` `git commit` in `tests/scripts/test-weakness-miner.sh`. The deferral
> that remains is genuine defence-in-depth over the suites that ARE covered by a tripwire; reasons
> (b) and (c) below stand, reason (a) did not.

**What I found.** The rule is satisfied, but by a different sweep than the brief assumed. The
sentinel in this plan lives at the **process boundary**, so its write sites are the *entry points*,
and those are enumerated exhaustively and pinned mechanically (Guard 2). The ~48 fixture suites are
beneficiaries, not sentinel sites: with the entry-point scrub and the runtime tripwire in force, none
of them can observe a hostile environment in any reachable invocation.

**What the plan does instead.** Converts only the three Bun-discovered suites under
`plugins/soleur/test/` (including the one named in the incident report) plus the two python suites,
and defers the rest to a tracked follow-up as defence-in-depth — with the specific files that fall
between the two lists enumerated in the plan's `## Deferral`.

**Cost of doing it your way instead.** A ~50-file diff coupled to three new guards in one PR, which
reviewers converge on calling a rubber-stamp risk; and the conversion list cannot be derived reliably
(see Challenge 1, point 1), so "every site" would be an unverifiable claim.

**What would change my mind.** If you would rather absorb the large diff now than carry a follow-up,
say so — the work is mechanical once the helper exists, and the plan's Phase 4 already specifies the
helper shape it would use.

---

## Challenge 3 — the reporter's suggested fix has two measurably wrong pieces

Not a direction change so much as a correction to the issue body, recorded because the issue asked
for the suggestion to be evaluated rather than assumed:

- **`GIT_CEILING_DIRECTORIES: dir`** (the fixture directory itself) does **not** stop git escaping to
  the enclosing repository when git's cwd equals that directory. Measured. The working spelling is
  the fixture's **parent**, which both in-repo prior-art sites already use.
- **The `undefined` spelling works.** The issue flagged a risk that `GIT_DIR: undefined` might
  stringify to the literal `"undefined"`. Measured on Bun 1.3.11 and Node v22.22.2 with a control: it
  does not — the key is dropped from the child environment. The real hazard is elsewhere, and it is
  worse: under Bun, `delete process.env.GIT_DIR` takes effect in-process but a child spawned without
  an explicit `env` **still receives the original value**. Node propagates the deletion correctly.
  That divergence is why the scrub belongs on the invocation rather than inside the runtime.
