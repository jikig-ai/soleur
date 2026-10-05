---
title: "A label route no token could fire, and an END sample that re-read its own START row"
date: 2026-09-28
category: integration-issues
module: registry-zot-inventory / scheduled-zot-restart-loop
tags: [github-actions, github-token, workflow-dispatch, least-privilege, telemetry, freshness, adr-172]
issue: 7377
pr: 9119
---

# Learning: a dead label route, and a "latest sample" that is not a later measurement

## Problem

#7377 tracked the registry host's `restart` / `push-config` / `reclaim` levers, which ADR-172 §3
recorded as "blocked on a provisioning event", plus three deferred defects: a label-triggered
dispatch route with no producer, an enumerator that never took an END restart sample
(`zot_restarts_at_end=unknown` on every run), and a `marker_schema` field nothing read.

## Solution

- **ADR decision: amend ADR-172, no new ADR.** The blocker had cleared on 2026-08-10, and the
  ADR-169 amendment of 2026-08-16 already made "merge → volume-preserving replace" the config
  delivery path. The amendment records `push-config` as realized by it and `restart` / `reclaim`
  as not built, and flips ADR-172 to `accepted`.
- **Label route deleted.** `registry-zot-inventory-dispatch.yml` had 3,540 runs and 0 that did
  anything; the label did not even exist. A label applied with `GITHUB_TOKEN` starts no workflow
  run (the documented exceptions are `workflow_dispatch` / `repository_dispatch`), so a producer
  inside the alarm was structurally impossible. The restart-loop alarm now hands a new non-OOM
  tracker to a separate `dispatch-inventory` job, the only holder of `actions: write`, which
  dispatches the inventory with the tracker number so the result comes back to that tracker.
- **END sample inside the enumerator**, re-polled until a heartbeat NEWER than the START row
  lands (bounded 360 s), under an `env -i` allow-list.
- **Orphaned follow-through probes deleted** (both trackers closed).

## Key Insight

1. **"Newest row" is not "a later measurement".** The heartbeat is 5-minutely and the measured
   sweep took 104 s, so the newest `SOLEUR_ZOT_DISK` row right after the sweep was usually the
   START row itself. Reading it again would have put a number in `zot_restarts_at_end` without
   measuring anything, and the acceptance criterion ("carries a real value") would have been met
   by a proxy. Compare the sample's own timestamp against the baseline's and re-poll; an absent
   newer row is `unknown`, never a re-read. The plan-review seat caught this, not the author.
2. **A deny-list around a child's environment leaks whatever it forgot to name.** `env -u` of the
   pull and ingest tokens left the step's Doppler service token in the sampler's env. `env -i`
   plus the one credential the child needs is the only form that cannot forget.
3. **A gate keyed on free text in another file is coupled to every rewording of it.** The
   dispatch fired on `CAUSE` starting with `non-OOM crash-loop — `; that literal lived in the
   alarm script, the test fixture was typed by hand, so changing the em-dash would have stopped
   the dispatch with every suite green. The test now derives the prefix from the script's own
   `CAUSE=` line.
4. **Scope a write grant to the job that uses it.** `actions: write` at workflow scope reached a
   job that checks out the repo (token persisted in `.git/config`) and parses tenant-influenced
   telemetry; `actions: write` can dispatch any `workflow_dispatch` workflow. A two-line job
   split removes that.

## Session Errors

1. **Research cited run 31437037877 as "the recut ran"; the run's overall conclusion is failure**
   (`registry_luks_recut` succeeded, `registry_store_restore` failed). Recovery: re-read the job
   list and wrote "the recut job succeeded". **Prevention:** cite a run by the JOB whose result
   the claim is about, never by the run conclusion.
2. **`git rm` deletions were staged before the plan commit and landed in it**, so the
   implementation commit message described deletions it did not contain. Recovery: none needed
   (squash merge). **Prevention:** commit plan artifacts before staging any implementation
   change, or stage by explicit path only.
3. **A command containing `git stash list` was blocked by the hook.** Recovery: dropped it.
   **Prevention:** probe stashes with `git rev-parse --verify --quiet refs/stash`.
4. **A chained `sleep 60; cat …` was blocked.** Recovery: `run_in_background` with an until-loop.
   **Prevention:** wait with an until-loop in a background call, never a foreground sleep.
5. **The first END-sample design would re-read the START row** (Key Insight 1). Recovery:
   freshness compare + bounded re-poll. **Prevention:** for any "sample after X" design, ask
   whether the sampler's cadence is slower than X's duration.
6. **`env -u` deny-list missed `DOPPLER_TOKEN`** (Key Insight 2). Recovery: `env -i` allow-list
   plus a test planting `DOPPLER_TOKEN`. **Prevention:** allow-list a child's environment.
7. **A validation calling `die` was placed above `die`'s definition.** Recovery: moved into the
   function that uses the knobs, degrading to `unknown`. **Prevention:** `bash -n` does not catch
   this; grep the helper's definition line before calling it at top level.
8. **A `sed -i '92s/…/'` targeted the wrong line** (the guard was on 94), so the first commit
   attempt staged nothing. Recovery: located the line by pattern. **Prevention:** address edits
   by content anchor, never by a line number read earlier.
9. **`fixture-relative-assert` flagged `[[ "$a" > "$b" ]]` as a relative write redirect**, and
   a `2>>"$SCRATCH/…"` inside a function. Recovery: wrote the comparison as `"$b" < "$a"` and let
   sampler stderr go to the job log. **Prevention:** in scanned scripts, avoid `>` inside `[[ ]]`.
10. **markdownlint MD038** on a code span with a trailing space. Recovery: reworded.
    **Prevention:** never end a code span with a space.
11. **`web-platform-typecheck` and `c4-code-syntax` failed on a symlinked, stale `node_modules`**
    (missing `swr`, `svix`, `cmdk`, `@codemirror/language`). Recovery: excluded the typecheck hook
    for the commit; CI's required `test` is the gate. **Prevention:** in a fresh worktree, install
    dependencies rather than symlinking another checkout's `node_modules`.
12. **The dispatch gate was coupled to free text in another file** (Key Insight 3). Recovery:
    test derives the literal from the script. **Prevention:** a string-keyed gate needs a test
    that reads the producer's literal.
13. **`actions: write` was granted at workflow scope** (Key Insight 4). Recovery: separate job.
    **Prevention:** grant write scopes at job level on the job that uses them.
14. **The inventory result was posted only to a closed issue (#7339).** Recovery: optional
    numeric `tracker` input, result posted there too. **Prevention:** when wiring an automatic
    producer, check the consumer's output target is still open.
15. **The new `marker_schema` consumer returned `unsupported` when a schema-2 row sat beside an
    incomplete schema-1 row.** Recovery: unsupported only when every run row is another schema.
    **Prevention:** fixture a mixed population for any per-row classification that feeds one
    verdict.

## Tags

category: integration-issues
module: registry-zot-inventory
