# My `elif` arm ate the selection walk — a bounded-selection banner on a silent full battery

## Problem

On #9173 (`--affected-scope=staged` for the lefthook `bun-test` gate) I added a
scope-aware `runner-changed` arm to the affected pre-pass's `if/elif/else`
ladder in `scripts/test-all.sh`. Under staged scope the arm printed
`AFFECTED_RUNNER_IN_SCOPE` and deliberately left `_aff_fallback` empty — and
*because it consumed the `elif`*, the terminal `else` (the nested
`--enumerate-commands` walk that fills `_aff_sel[]` and sets `_aff_ready=1`)
never ran. The chokepoint reads `_aff_ready=0` + `${_aff_sel[ord]:-1}` as
**select-everything** — the fail-safe direction — so a commit staging
`test-all.sh` ran the silent ~4h full battery the flag exists to remove,
under a telemetry line claiming bounded selection. Two independent design
seats (code-simplicity and performance-oracle) found the same P1. My own `sc6`
sandbox arm was written to catch exactly this — but the suite was never run to
the sc6 row before the commit pushed (interrupted run + an explicit
"rely on CI" instruction), so the canary existed but never sang.

The fix moved the scope test into the `elif` **condition** (`!= staged`), so
the staged case falls through to the `else` walk and the note emits *inside*
the walk — where the bounded selection actually happens.

## Root cause

An `elif` ladder mixes *classification* (which arm) with *execution* (what the
arm does). Adding a case that means "same outcome, different telemetry" is not
a new arm — a dedicated arm **consumes the chain** and skips the work the
arm-free case would do. The telemetry was honest about intent and wrong about
effect: `AFFECTED_RUNNER_IN_SCOPE` printed while the run selected everything.
Three companions from the same review:

- **The seam must live in the sandbox, not the ship.** I shipped
  `SANDBOX_STAGED_NAMES` inline in the runner because intra-*branch* placement
  was required to prove darkness — but placement and *shipping* are orthogonal.
  `build_sandbox` can inject at an intra-branch anchor (the
  `diff --cached --name-status` line); the shipped runner then has no
  env-readable substitution, matching every sibling `SANDBOX_*` seam. An
  exported var would have narrowed a real run's diff while `AFFECTED_SCOPE`
  reported honestly — the presence-≠-ownership class the flag exists against.
- **The fixture BUILD needs the scrub too, not only the eval.** sc9 built its
  scratch repo with `git init/add/commit/update-ref` unscrubbed — and the
  suite is `always_on`, so it runs inside the very lefthook hook whose
  `GIT_INDEX_FILE`/`GIT_DIR` injection redirects those writes at the live
  repo (the #7772/#7835 data-loss class the PR defends). The runner survives
  via a named 9-name unset; the fixture had none. Fix: sweep the whole
  `${!GIT_@}` prefix in the subshell (a named list went stale within a day in
  the prior incident), applied to build AND evals.
- **`SHELLOPTS` exports `nounset` into `bash -c` children.** An eval leg that
  intentionally left `_AFFECTED`/`TEST_GROUP` unbound aborted on
  `(( _AFFECTED == 1 ))` inside the extracted assembly before printing — bind
  every var the extracted code reads, even to its non-firing value.

## Key insight

"Same outcome, different note" is a property of the *walk*, not a new ladder
arm — emitting it from a dedicated `elif` eats the chain it was meant to
annotate. And a mutation arm that was never run is indistinguishable from no
arm: the suite catching a defect in CI is a weaker guarantee than the author
watching it go red first. When a review finding reshapes code, re-grep every
splice/anchor consumer of the old text — the `elif` rewrite also broke
`fanout-suite-scope.test.sh`'s Arm-11 exact-text neuter outside the PR's own
file list (fixed by hoisting a `_aff_runner_in_diff` flag, which gave the
splice a cleaner anchor than the arm text it replaced).

## Session Errors

- **elif-arm consumed the selection walk (the learning).** Recovery: scope-gate
  the `elif` condition; emit the note inside the `else` walk. Prevention: this
  learning; in an `if/elif/else` ladder, never put telemetry-only behavior in a
  dedicated arm — and run the arm written to catch a change before calling it
  pinned.
- **Shipped `SANDBOX_STAGED_NAMES` inline (env-readable narrowing seam).**
  Recovery: `build_sandbox` injects at the intra-branch anchor. Prevention:
  treat intra-*placement* and *shipping* as separate questions; every env-read
  in production code is either sanctioned scope or a hole.
- **sc9 fixture build ran unscrubbed git writes under lefthook's `GIT_*`
  env.** Recovery: `${!GIT_@}` prefix sweep in the build subshell and both
  evals. Prevention: the data-loss class covers writes, not only reads — any
  git op in an always-on suite's scratch repo runs inside the hook that
  injects them.
- **`TC_QUEUE_TIMEOUT=300` didn't bound the head-ticket lock acquire**
  (queue defaults to `TC_LOCK_TIMEOUT`; head waits flock up to 3600s).
  Recovery: hook uses `TC_LOCK_TIMEOUT=300` (bounds both stages). Prevention:
  name the wait's two stages before quoting a bound; check the default chain.
- **awk range end-pattern matched my own comment containing
  `git ls-files --others`.** Recovery: reworded the comment. Prevention:
  substring anchors see comments — never name the anchored command in the
  extracted window's comments.
- **`SHELLOPTS` `nounset` propagation into `bash -c` eval legs.** Recovery:
  bind all read vars. Prevention: eval'd code + `bash -c` under a `-u` suite
  means every read var needs a value, even a non-firing one.
- **Broke `fanout-suite-scope.test.sh` Arm-11 splice anchor** by rewriting the
  elif text it replaces. Recovery: hoisted `_aff_runner_in_diff` and re-anchored
  the splice on the flag. Prevention: when changing code, grep for
  `assert s.count(old)`-style text anchors in sibling test files — the blast
  radius is outside `git diff --name-only`.
- **8/8 panel agents died on free-model rate limit.** Recovery: waited out the
  reset and resumed transcripts in batches per Gate 2b. One-off.
- **Interrupted local suite run left orphan sandbox processes** (self-exited;
  verified via `list_runs`). One-off.
- **Plan/tasks/docs named `TC_QUEUE_TIMEOUT` and called the `GIT_*` unset a
  "blanket sweep"** — both stale after review. Recovery: corrected all
  carriers (plan, tasks, session-state, ADR, code comment). Prevention:
  when a review finding renames a mechanism, sweep the noun repo-wide, not
  just the edited files.

## Tags
category: test-failures
module: scripts
issue: 9173
