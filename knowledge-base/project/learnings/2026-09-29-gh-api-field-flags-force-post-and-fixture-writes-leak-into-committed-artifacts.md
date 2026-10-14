# Learning: `gh api -f` silently becomes POST, and a second write-path default can leak fixture data into committed artifacts

## Problem

Two distinct traps surfaced shipping #9233 (duration-aware shard packing):

1. `gh api repos/.../actions/workflows/ci.yml/runs -f branch=main -f status=success`
   returned **404 Not Found** while `gh run list --workflow ci.yml --branch main`
   and `gh api repos/.../runs/{id}/artifacts` both worked on the same token.
   Cause: `-f`/`--field` changes `gh api`'s default method to POST, and the
   runs-list routes only exist for GET. The repo's existing helper
   (`latest_green_main_run` in regenerate-shard-manifest.py) was silently
   unreachable under some credential shapes — the shape-dependent part is
   whether the endpoint also exists for POST, and most don't.

2. When the generator grew a SECOND write product (`--durations-out`), every
   pre-existing test fixture that invoked `--write` with a redirected
   `--manifest` but no durations flag began clobbering the committed
   `scripts/suite-durations.tsv` — the table ended up holding fixture labels
   (`dup-suite`, `solo-suite`, `generated-from-runs=local:C`) committed by
   mistake. The defect was found by reading the commit's own `--stat` output
   (532 deletions — a 519-row file reduced to 8 lines), not by a gate.

## Solution

- Replace `gh api <path> -f <params>` with `gh api "<path>?a=b&c=d"` (URL-
  embedded query stays GET) or `gh run list` where it exists. The probe file
  `scripts/followthroughs/ci-leg-balance-9232.sh` carries the convention in
  its header; the generator's `green_main_runs()` uses `gh run list` and
  documents why in its docstring.
- Pair each write product with the artifact the invocation actually emits:
  `--durations-out` > the committed table only when `--manifest` resolves to
  the committed manifest > `<manifest>.durations.tsv` beside the emitted
  manifest. A redirected-manifest `--write` can no longer touch committed
  state.

## Key Insight

- **A new write-product's default destination is a blast radius, not a
  convenience.** The rule that kept fixtures safe for the manifest
  ("--manifest defaults to the committed path") was copied for durations —
  and was correct ONLY when the two artifacts travel together. Side-effect
  writes that look harmless in fixtures silently dirty committed data.
- **`-f` on `gh api` is a method-change flag masquerading as a
  query-builder.** Any `gh api` call that must be GET must embed the query
  in the URL. A 404 on an endpoint you can see in the REST docs is the tell.
- **Fixture parity checks for generated artifacts need the negative arm.**
  Our batteries assert the emitted file's content; the leak survived
  because nothing asserted the committed file was NOT written. A fixture
  battery that exercises `--write` should snapshot the committed sibling
  and diff it afterward (the 43-check suite now passes with the committed
  table byte-identical pre/post).

## Session Errors

1. `gh api` 404s on the runs-list endpoints — caused by `-f` flipping to
   POST. **Prevention:** the convention is now written into
   `ci-leg-balance-9232.sh`'s header and `green_main_runs()`'s docstring;
   grep `gh api.*-f` in new probes before shipping.
2. Push rejected non-FF — self-inflicted by rebasing after the remote plan
   commits were pushed; resolved with a merge fold. **Prevention:** rebase
   a session branch before the remote gets its first push, or accept merge.
3. `--affected` degraded to full-gate and refused on a sibling — transient;
   the sibling was a leftover `--print-affected-set` process. **Prevention:**
   none — the contention machinery is working as designed; re-run when the
   sibling exits.
4. Fixture `--write` leaked into the committed durations table.
   **Prevention:** the pairing rule above; plus the lesson to read
   `git show --stat` anomalies (532 deletions in a "small fix" commit) before
   pushing.
5. Assumed `--enumerate` emits bare labels — it emits
   `SUITE_REGISTRATION\t<label>` plus status lines; a bogus union mismatch
   (529 vs 526) burned a debug cycle. **Prevention:** `head` the output
   before diffing against a derived set.
6. Six of seven review subagent spawns rate-limited (free-model cap);
   lenses ran inline with the limitation disclosed in session-state.
   **Prevention:** spawn seats serially or with delays when the cap is hot.

## Tags
category: workflow-issues
module: scripts/regenerate-shard-manifest.py, scripts/followthroughs/
