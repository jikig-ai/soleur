---
date: 2026-09-23
category: workflow-patterns
module: ci/guard-scripts
issue: "#8583"
pr: "#8597"
tags: [ci-guard, anti-self-neuter, git-ls-tree, vacuity-floor, migration-immutability, fail-closed]
---

# Learning: a PR must not control the guard that judges it — and "absent on base" has two different meanings

## Problem

PR #8597 added `lint-migration-immutability.sh` — a CI step in `tenant-integration.yml`'s
always-run `detect-changes` job that fails a PR which mutates an already-merged
`supabase/migrations/*.sql` (the #8507/138_agent_engine_runs.sql drift class: the runner's
filename ledger short-circuits on edited content). The review panel found that the naive
wiring — `bash apps/web-platform/scripts/lint-migration-immutability.sh --from-pr-diff` —
lets the judged PR weaken the judge: the same diff could neuter the script and mutate a
migration, and CI would run the neutered copy.

## Solution

Three-arm execution in the workflow step:

1. `git show "origin/$base:$GUARD_PATH" > $RUNNER_TEMP/copy` succeeds → run the **base-ref
   copy** (`bash $GUARD_COPY --from-pr-diff --repo $GITHUB_WORKSPACE`) — the PR cannot touch it.
2. `git show` fails AND `git log -1 origin/$base -- $GUARD_PATH` is empty → the guard never
   existed on base (the introduction window, i.e. this PR) → run the checkout copy.
3. `git show` fails but `git log` finds history → the guard was **deleted on base** → fail
   closed. A naive "fallback on any `git show` failure" opens a two-PR neuter: PR-A deletes
   the guard on main, PR-B ships a neutered copy that runs as its own judge.

The same panel round surfaced the supporting contracts that make a guard trustworthy:

- **Oracle tri-state, not boolean:** `git ls-tree` empty-at-rc0 means "absent"; rc≠0 is an
  oracle failure and must exit 2 — `|| true` there is a silent false-green.
- **Degenerate pass must be audible:** the summary always prints
  `touched=/on-main-checked=/new=/down-exempt=`, and a migration-touching diff with 0 checked
  files emits `::notice::` — a stubbed oracle can never produce a report indistinguishable
  from a real check.
- **New-file arm needs a mode check too:** a NEW symlink at a migration path admits as "new"
  but is a persistent unguarded channel (the runner follows the link; the ledgered blob stays
  byte-identical). New paths must be regular blobs (100644/100755).
- **Flag parsers need `need_value`:** `--base` as the last arg made `shift 2` a no-op inside
  `while [[ $# -gt 0 ]]` — an infinite loop, not an error.
- **Vacuity-floor mutant constructibility:** the `guard-vacuity-floor` mutant builder only
  carries contiguous simple assignments directly above the floor's `if`. A threshold defined
  at the top of file leaves the mutant unbound → CONSTRUCTION, not FIRES. Put the bound
  (`EXPECTED_CASES=20`) on the line above the `if`, and promote the new suite into
  `PROMOTED_FILES` — the deferral ledger is shrink-only; a new floor-bearing suite in a
  deferred directory must be promoted, never ratcheted up.

## Key Insight

**Any check whose source lives in the PR's own diff is judge-and-jury for the change it
evaluates.** The fix pattern generalizes: extract the base-ref copy, distinguish
"never existed" from "was deleted" with `git log` (not exit-code inference), and make the
fallback arm a deliberate, named exception (introduction window) rather than a catch-all.

## Prevention

- When adding a CI guard/lint script invoked from a workflow, always run the base-ref copy
  via `git show` when it exists; gate the checkout-copy fallback on a `git log`
  never-existed probe, and fail closed otherwise.
- Guard outputs need a counted summary so "checked nothing" is never green-looking.
- New suite in `apps/web-platform/{scripts,infra,test/infra}/`, `.claude/hooks/`, or
  `plugins/soleur/skills/*/test/` carrying an assertion floor → add it to
  `PROMOTED_FILES` in `scripts/guard-vacuity-floor.test.sh` with a justification entry;
  keep the floor bound as a literal adjacent to the `if`.
