# Test-harness sharp edges (work)

Loaded from `work/SKILL.md` §9 on demand. Three measured traps from #10161's
affected-shard cycle — each cost a full gate run before it surfaced.

## Mid-run commits trip the repo-write boundary, not only mid-run edits

The boundary check samples `[head]` and `[refs]` as well as the worktree, so
`git commit` (or a merge, a push that moves refs, an amended tree) inside a
running `test-all.sh` reads as "A SUITE WROTE TO THE LIVE REPOSITORY" with no
attribution to you — the suites were innocent, the FATAL still fires (#10161
QA run: two commits during a shard, twice). A QUEUED run counts as running
for this rule only once it acquires the lock: the snapshot is taken after
`tc_acquire`, so an edit made while `LOCK_WAIT_HEARTBEAT` is printing is safe,
and one made after acquire is not. Recovery: queue the commit until the
terminal marker, or commit first and restart the run — a discarded run costs
minutes, a misattributed one costs the investigation.

## A new `.claude/hooks/*.sh` policy hook reaches ~15 registration/ratchet surfaces

Run each surface's own suite standalone BEFORE the shard, not as shard
discoveries — each is a seconds-long standalone run and every one has its own
enforcer; the shard merely makes the misses expensive. The enumerated list
lives in
`knowledge-base/project/learnings/workflow-issues/2026-10-13-gh-pr-merge-shipped-live-kb-artifacts-archival-needed-a-gate.md`
(Session Errors, item 4):

- `settings.json` matcher entry + `.devin/config.json` `^exec$` twin +
  `devin-dispositions.tsv` bind row
- `INSCOPE21`/`REWRITERS` classification in `hook-input-contract.test.sh`
  when the hook sources `lib/hook-input.sh` (README "Scope of the mandate"
  list + count too)
- `suite-shard-legs.tsv` + `regenerate-shard-manifest.py --incremental --write`
- `PROMOTED_FILES` promotion only *after `git add`* — the derivation reads
  `git ls-files` and cannot see untracked files
- no `producer | grep -q` in a policy hook (`grep-q-pipe-guard`)
- `mktemp` needs an owning EXIT trap (`lint-trap-tempfile-ownership`)
- `assert_fixture_dir` on same-function `git -C "${work}"` fixture writes
  (`fixture-dir-operand-assert`)
- `fixture-relative-assert --write-baseline` in the same commit as a new
  fixture-relative test file
- `--no-tags` on any `git fetch`/`pull` inside a battery closure
  (`battery-tag-authorship` measures authorship by tag presence)
- no bare `knowledge-base/` literals in test argv (`test-affected-kb-consumers`
  charges them to your suite)
- rule-corpus index+body pair, body ≤600B (`lint-agents-rule-budget`)

**Why:** #10161 — the hook suite was 84/84 green at the first shard and still
produced six separate shard-discovered surfaces, one FAIL per cycle.

## A nested `test-all.sh` sandbox inherits the enclosing run's selection env

Under an outer `TEST_GROUP=affected` shard, a suite's own
`bash sandbox/test-all.sh` inherits `TEST_GROUP`/`MODE`/`SCRIPTS_SHARD`/
`SOLEUR_TEST_FORCE_ALL`, takes the affected path against a sandbox diff that
selects zero suites, and exits 0 — reading as "the refusal arm never fired"
in every arm that measures refusal. Scrub with
`env -u TEST_GROUP -u MODE -u SCRIPTS_SHARD -u SOLEUR_TEST_FORCE_ALL`:
empty assignments like `TEST_GROUP=` are NOT equivalent — the runner's enum
validation rejects an empty-but-set value with rc=2 — and the `-u` forms must
precede the arm's own vars so an intentional `TEST_GROUP=affected` still
lands. Same class as the `SOLEUR_SUBAGENT` scrub every nested-runner suite
already carries — see
`knowledge-base/project/learnings/2026-09-28-an-exported-session-env-var-forked-nested-runner-behavior.md`
(#8940). **Why:** #10161 — `test-all-orphan-log-retention` and
`fanout-suite-scope` were green standalone and red (18 and 26 arms) inside
`TEST_GROUP=affected`; both needed the scrub.

- **A "never raises" stderr helper needs a `sys.stderr is None` case, and a baseline run must come from a pristine tree.** `cmd 2>&-` sets `sys.stderr` to `None`, so `except (OSError, ValueError)` does not catch the `AttributeError`; run the helper's probe with `None`, a closed file and a raising stream. Take a baseline for a before/after diff from a detached `git worktree add` at `HEAD`, never the live tree you are about to edit (#10375).

## A mutation row is vacuous until a fixture distinguishes the mutant

**A mutation row is vacuous until a fixture distinguishes the mutant — fabricate the discriminating state when the live corpus can't produce it.** Before writing a sed-and-diff mutation row, name the input on which the mutant's verdict differs; if the live tree can't supply it, inject synthetic module state (`o._TRACKED = (real | {synthetic}, …)` in an importlib-probed module) or build a scratch `git init`+`git add` index under TESTROOT (`rm -rf` after staging yields the index-dir-absent-on-disk shape). A mutant that lands and emits the same vector is the quietest green. Twin trap: a stale-expectation guard must assert the vector the OLD rule actually emits — a hand-extended "stale" string that no rule produces can never match, and `!=` on it passes vacuously on empty output; shape-pin instead (`=~ ^([01] ){N}[01]$`). **Why:** #10117's review found three mutation rows whose distinguishing fixtures could not exist in the live index. See `knowledge-base/project/learnings/test-failures/2026-10-14-a-mutation-row-is-vacuous-until-a-fixture-distinguishes-the-mutant.md`.
