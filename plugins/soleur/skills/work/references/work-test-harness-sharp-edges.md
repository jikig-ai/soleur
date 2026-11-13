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
  `git ls-files` and cannot see untracked files. A floor-bearing suite under
  a DEFERRED dir (`DEFERRED_DIRS` in `guard-vacuity-floor.test.sh`, e.g.
  `plugins/soleur/skills/*/test/`, `apps/web-platform/infra/`, `.claude/hooks/`)
  grows the deferred ledger and reddens ARM 5c: add the file to `PROMOTED_FILES`
  (one edit to the single canonical line there; on merge conflict keep main's
  set plus yours), never raise `MAX_DEFERRED` (#12146)
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

## A nested `test-all.sh` sandbox inherits whatever selection env its parent exported

A suite's own `bash sandbox/test-all.sh` inherits the selection env its parent process exported.
Since #11939 the runner drops the export attribute of `TEST_GROUP` (and unsets `SCRIPTS_SHARD`, #7902),
so a suite the runner spawns inherits neither; the cases that still bite are a suite run outside the
runner (standalone, `bun test`, a hook) from a shell that exported them, and an operator-exported
`SOLEUR_TEST_FORCE_ALL`. With `TEST_GROUP=affected` inherited (a `--affected` alias since #8621) the
sandbox takes the affected path against a sandbox diff that selects zero suites and exits 0 — reading
as "the refusal arm never fired" in every arm that measures refusal. Keep the scrub as defence:
`env -u TEST_GROUP -u SCRIPTS_SHARD -u SOLEUR_TEST_FORCE_ALL`:
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

- **An empty `$(…)` file list handed to a test runner that defaults to "run everything" runs EVERYTHING.** `vitest run $(git grep -ln … -- test)` with no match is `vitest run`: the whole suite, which loads the machine and can void a concurrent mutation battery (its unmutated control reads red). Capture the list first, `[ -n "$files" ] || { echo none; exit 1; }`, then run. **Why:** #10194 — a stray full run turned a 7-row battery's control red and cost a re-run. See `knowledge-base/project/learnings/2026-10-25-a-framing-guard-for-a-channel-nobody-feeds-ships-green-and-inert.md`.

- **A section-only fast runner is an iteration tool, never a verdict, and a shared helper's cleanup glob must match only what its own section creates.** A harness helper that `rm -f`s a broad pattern (`ERR4*RL_*`) deletes fixtures an EARLIER section creates for a LATER one; the later row then stays green on a stub miss (which also retries) and its mutant survives, visible only in the full-file run (469 of 470) and never in the section-only runner. Before committing a change to a shared helper's cleanup or fixture set, run the whole file once; scope the glob to the section's own marker paths. **Why:** #10865 probe fix, 2026-10-27 — see `knowledge-base/project/learnings/2026-10-27-a-section-only-runner-cannot-see-a-cleanup-glob-deleting-another-sections-fixture.md`.

- **Curl mock URL logs must record transfer targets, not URL-shaped option values.** Parse positional, `--url`/`--url=` operands across schemes; consume curl proxy selectors (`--proxy`, `--proxy1.0`, `--preproxy`, SOCKS4/4a/5/5-hostname, `-x`, and clustered `-sSx`), capture original argv before shifting, and test each selector/form alone and beside a real target. Pin exactly one `--noproxy '*'` per request, exact target counts, and the proxy-option deny check so proxy destinations cannot masquerade as requests or re-enable proxy routing.

- **A suite deferred to a later phase is the suite the current edit needs.** When a task list schedules "run the named suites directly" but delegates one file's own suite to a later pipeline phase (affected-run delegation), re-check the deferred set against the files actually edited before moving on — `bash -n` plus green sibling suites cannot see a semantic break (a `#` line interposed inside a `\`-continuation splits the command; the file's argv-shape rows are what catch it). Run the edited file's suite WITH the edit, or record the gap in the deviation note so the next phase knows it is uncovered. **Why:** PR #11735 (#11553) — the exemption comment inside a curl continuation silently killed the Sentry cross-check while `anthropic-admin-key-6297.test.sh` sat deferred; shellcheck SC2215 caught it in review. See `knowledge-base/project/learnings/2026-10-31-a-comment-inside-a-backslash-continuation-splits-the-command-the-fold-thought-was-one.md`.

- **A bash regex RANGE follows the locale, and a probe that tests a LINE must prove the token is absent from that line's prose.** `[[ x =~ ^[0-9a-f]{40}$ ]]` accepted 39 hex digits plus an accented letter under `LC_ALL=en_US.utf8` (bash 5.3) and rejected it under `C`/`C.UTF-8`: pin `LC_ALL=C` function-locally for any security-relevant validation and fixture a non-ASCII letter under a collating locale (a mutant that deletes the pin is killable only where that locale exists, so fail rather than skip on CI). A follow-through probe grepping a command line for `headSha` returned PASS on the unfixed tree because the same line carries the prose "by headSha/createdAt": parse the `--json` field list, require exactly one matching line, and run the probe once against the real file expecting the UNFIXED verdict plus a lookalike and a decoy-comment fixture. **Why:** #12320/PR #12350 — see `knowledge-base/project/learnings/2026-11-08-a-locale-ordered-regex-range-and-a-probe-that-matched-the-prose-on-its-own-line.md`.

- **When a verification's VERDICT is the deliverable, do not bound its wall — a timeout kill is `unknown`, never pass or fail.** A `ratchet`/suite verify re-run under a self-imposed `timeout`/bounded exec was killed at 120 s mid-run and could have been misread either direction; re-run unbounded and let it finish. Bound the SUT's per-invocation calls (a `REPLAY_SUT_TIMEOUT`-style knob), never the verification harness itself. **Why:** PR #12419 — see `knowledge-base/project/learnings/performance-issues/mutant-side-runaway-read-as-pristine-site-cost-ci-replay-20261108.md` session error 4.

- **A suite run is evidence for the tree it ran on — re-run the touched suites after the LAST edit of the commit, comment-only edits included.** A comment can trip a strict substring pin: a test-all.sh comment naming an array that contains a refused prefix turned the lint's unit suite red at the pushed head, after the suite had run green one edit earlier. **Why:** #12348/PR #12561 — all 11 escalation seats found it; see `knowledge-base/project/learnings/2026-11-11-each-fix-round-found-the-next-sibling-until-the-test-stated-its-residuals.md`.

## `0 issues in 0 files` is a skipped lint, not a clean one

`markdownlint-cli2` never reads a path matched by `.markdownlintignore` (for
example `knowledge-base/project/`), and still prints a clean-looking summary.
Lint a `/var/tmp` copy with the pinned binary and `-c .markdownlint.json`, and
confirm a known-bad copy fails, before reporting clean. **Why:** #12536 — see
`knowledge-base/project/learnings/2026-11-10-a-verify-only-key-slot-guard-anchors-on-what-every-signer-needs.md`
session error 5.
