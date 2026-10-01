# Learning: stopping a dev-machine disk leak — the guards were narrower than the property, and `env -i` scrubbed the isolation

## Problem

A 150G developer disk hit 95% from `/var/tmp` leftovers (~33G, ~81k entries), `~/.codex/.tmp`, and package
caches. The task assumed every named leak (`vac<pid>`, `td-*`, `perf-*`, `mut*`, `kbcov-*`, `gdpr-gate-*`, …) had a
committed `mktemp` site to fix. Measurement said otherwise: the biggest names had **no committed writer** (they are
full-repo copies built by review/mutation seat agents following prose), the test-suite names leaked because direct
runner invocations had no per-process root, and the caches are not written by any Soleur script.

## Solution

Extend the ownership-keyed machinery (ADR-250), do not fork it: per-process `soleur-run.<pid>.*` root at every runner
chokepoint (bun preload, vitest globalSetup, pytest conftest, unittest import), marker-at-creation for the incident
sandbox, an agent sandbox allocator (`scripts/soleur-sandbox.sh new|rm`), a read-only `soleur-tmp-purge.sh --report`,
lint rules (d)/(e), durable test-all log GC, and a runbook cache table (document, do not invent controls).
An 11-seat review then found the guards narrower than the property they name (see Key Insight).

## Key Insight

1. **A prose-brief leak needs an enforceable allocator and a brief at the spawn contract.** Pointing a seat at a
   script that exists only in this checkout (not in a plugin consumer's repo, not from a subdirectory) reproduces the
   leak; the brief needs an anchored command, an allocation-failure rule and a no-script fallback.
2. **Guard windows are function-scoped.** `fixture-scan.py`'s guard window runs from the *latest function head* to the
   use, so one top-level `assert_fixture_dir "$BASE"` covers nothing after any later function definition. Guard each
   writing window; do not regenerate the baseline.
3. **`env -i … HOME="$HOME"` scrubs every isolation export you set earlier.** A suite that exports
   `SOLEUR_PURGE_LEDGER` at the top and then runs fixtures under `env -i` still appends to the operator's real
   ledger. Pass the variable through each `env -i`, and assert the real file's size is unchanged across the run
   (with a sensitivity control).
4. **A destructive manual procedure must be at least as strict as the classifier it bypasses.** The runbook's
   hand-written `.git` search stopped at depth 6 (the classifier has no bound), `DAYS=0` disabled the age guard, and
   the next documented step (`TTL=0 --drain`) made the loss permanent. Source the predicates from the library.
5. **A rung nobody asked for is the first thing to cut.** The plan kept a destructive `--attest` rung "per operator
   direction", but task e only asked for an older-than-N-days prune that reports sizes. Three of seven plan reviewers
   recommended the cut; the lead cut it and recorded the challenge.

## Session Errors

- **Filing hook could not read an issue body from the scratchpad** — Recovery: moved the body into the repo — Prevention: write `gh issue create` bodies inside the worktree (already in the review skill).
- **Plan named a nonexistent consumer (`test-all-affected.sh`) and an ADR Alternatives table that does not exist** — Recovery: deepen corrected both — Prevention: `git ls-files` every path the plan prescribes before writing it.
- **Plan attributed a destructive rung to operator direction that the task did not give** — Recovery: lead cut it and recorded a decision challenge — Prevention: quote the user's own words next to any "per operator direction" default.
- **New shell suites tripped the fixture-relative ratchet (12 sites)** — Recovery: `assert_fixture_dir` in each writing window — Prevention: Key Insight 2.
- **`env -i` scrubbed the ledger isolation, and a review seat plus `test-scratch-session.sh` wrote to the real ledger** — Recovery: pass the variable through `env -i`, size-delta assertion — Prevention: Key Insight 3; brief seats to set `SOLEUR_PURGE_LEDGER` before any purge experiment.
- **A fix agent's nested `EOF` made the shell execute runbook text (a dry-run against the real `/var/tmp`, matched nothing)** — Recovery: redid the splice with the Write tool — Prevention: never nest a heredoc terminator inside another heredoc; write documents with the Write tool.
- **Generator regeneration of `suite-durations.tsv` also rebalanced 10 unrelated suites in `suite-shard-legs.tsv`** — Recovery: accepted (the manifest test requires matching keys); CI is the judge — Prevention: regenerate against the base table plus only the new rows and review the leg diff.
- **Stop hook fired on closing text promising a next action while background agents ran** — Recovery: emitted a `BLOCKED:` stop line naming the wait — Prevention: when waiting on background work, end with the `<stop>BLOCKED:` form, not a first-person commitment.

## Tags

category: workflow-issues
module: scratch-reclamation, test-harness, lint
