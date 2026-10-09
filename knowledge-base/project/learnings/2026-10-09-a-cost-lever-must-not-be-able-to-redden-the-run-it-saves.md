# Learning: a cost lever must not be able to redden the run it saves, and every clause of its detective probe needs its own fixture

## Problem

ADR-276 S2 (#9512, PR #9808) adds a `push-dedupe` job that skips the second full CI run on a push to `main` when an identical-SHA `merge_group` run already passed. Review of the first cut found two P1s and, after the fixes, two more fail-opens introduced by the fixes themselves:

1. A job-level failure of the lever (lost runner, platform fault) concluded the whole push run `failure`, which blocks that SHA's deploy (`ci_not_green`) even while the kill switch is off.
2. The soak probe read the activation from the repository variable; the sweeper's `GITHUB_TOKEN` gets a 403 on Actions variables, so the probe would sit at CANNOT ESTABLISH forever.
3. Fix round: the "suite still registered" check was a `grep -cF` over `scripts/test-all.sh`, so a commented-out `run_suite` line or an `echo` naming the path still counted; the ADR-status compare was case-sensitive (`Proposed`, `"proposed"`, `proposed # note` all slipped through).
4. A mutation pass over the rewritten probe left 22 of 31 mutants alive: each clause had a fixture that was also covered by a second clause (a skipped job that also had a null `runner_id`), or no fixture at all (latest-of-two markers, idle sample cap, CRLF bodies).

## Solution

- Put `continue-on-error: true` on the JOB (not only the step) of anything whose purpose is cost. A failed job then leaves its outputs empty, every gated job's `!= 'true'` runs the full battery, and the run stays `success`.
- Read state a sweeper cannot reach from a channel it can: operator comments on the tracker (`S2-ACTIVATED: <ISO>`), filtered to `author_association` OWNER/MEMBER/COLLABORATOR, matched at line start and end, CRLF stripped, paginated.
- Registration and status checks over config files must be comment-aware and normalising: anchor on the invocation form (`^[[:space:]]*run_suite[[:space:]].*<path>`), lowercase, strip quotes and a trailing `# note`.
- A red check on a green run pages nobody: the probe counts the lever's own job failures and fails above 20% of the sampled runs, in the dark phase too.
- Give every probe clause a fixture that only that clause discriminates (mixed skipped/success legs, no test job at all, a heavy sibling job running, an expensive pre-activation run, two activations, a deactivation older than the activation, an elided run beyond the idle cap) and a mutant that deletes the clause. Give every checker tag in the YAML guard a mutant that trips it; a tag no mutant reaches is dead code the suite cannot see.

## Key Insight

A lever allowed to fail in one direction needs that direction enforced at every layer it can fail at (step, job, run), and its detective probe is itself a fail-open surface: a probe clause with no discriminating fixture is a comment. The fix commit is the least-audited code in the diff: both fail-opens in this PR's fix round were introduced by the commit closing the previous round, by applying the fix to the instance (the one grep) and not the class (every "is X present in this config file" check).

## Session Errors

- **YAML plain scalar containing `: `** — Recovery: block scalar for the step run. **Prevention:** write multi-line shell steps as `run: |` from the start.
- **`local f="$SANDBOX/..."` unbound under `set -u`** — Recovery: split declaration and assignment. **Prevention:** never reference a sibling `local` in the same `local` statement.
- **Mutant anchors with wrong indentation or more than one match** — Recovery: unique anchors; the mutation helper refuses count != 1. **Prevention:** keep the count-must-be-1 guard in every mutation helper.
- **Existing guards tripped by the workflow change** (e2e anchors, merge-group coverage engine, concurrency-key regex, aggregator W4) — Recovery: carve-outs and a positive `merge_group` disjunct. **Prevention:** grep `plugins/soleur/test/ci-*.test.sh` for the edited job names before editing `ci.yml`.
- **P1: job-level failure could redden a dark run; P1: sweeper cannot read Actions variables** — Recovery: job-level `continue-on-error`; tracker-comment activation. **Prevention:** for any new workflow job ask "what concludes the run if this job dies?"; for any probe ask "which token reads this?".
- **Fix-round fail-opens (comment-counting grep, case-sensitive status)** — Recovery: anchored invocation grep, normalised status. **Prevention:** a registration/status check over a config file is comment-aware and normalising by default.
- **Fixture-relative-assert ratchet and kb-consumers baseline tripped** — Recovery: re-assert the fixture dir before late writes; baseline rows. **Prevention:** run `fixture-relative-assert.test.sh` and `test-affected-kb-consumers.test.sh` directly before pushing a new `*.test.sh`.
- **Shell cwd reset between calls** — Recovery: absolute paths. **Prevention:** `cd` into the worktree in each command that depends on it.
- **Two fixture designs that could not fail** (`twodeact` built with elided runs so the early-elision FAIL pre-empted it; `midact` lines that did not end in a timestamp so the dropped-anchor mutant stayed green) — Recovery: reshaped fixtures. **Prevention:** run the mutant against the new row before trusting the row.
- **Read a superseded review report after compaction** (round-1 `testdesign.md` instead of `fr1/testdesign.md`) — Recovery: re-read the fix-round file. **Prevention:** after a compaction, list the report directory and read by newest mtime.
- **Duplicate Monitor arms** (hook warning) — Recovery: TaskStop the older one. **Prevention:** one Monitor per target file.
- **A harness safety check refused an inline `bash -c` (no removal in it)** — Recovery: verified by reading the file. **Prevention:** avoid inline `bash -c` with quoting-heavy payloads; read the file instead.

## Tags

category: ci-workflow
module: ci.yml push-dedupe, scripts/followthroughs/ci-push-dedupe-soak-9512.sh
