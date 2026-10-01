---
title: "Bound every network-touching child in pipeline tooling — and give every non-success outcome its own stdout marker"
date: 2026-09-30
category: workflow-patterns
module: git-worktree, one-shot, work, ship, observability
tags: [worktree, install-deps, egress-deny, sandbox, timeout, registry-probe, soleur-marker, warn-and-continue, agent-legibility]
related_prs: [9271]
related_issues: [9269, 9310]
related_rules: []
---

# Learning: a package-manager retry IS an unbounded wait; bound it at the chokepoint and make every non-success arm self-report on stdout

## Problem

`worktree-manager.sh install_deps` ran `bun install` / `npm ci` / `yarn install`
bare. On a host whose egress policy denies the registry (the #9269 incident:
`registry.npmjs.org:443` denied in a Devin cloud sandbox), npm retried ~100 times
and the caller had to kill the process — a pipeline halt that read as a *stall*
with no diagnostic naming the cause. The worktree existed but had no
`node_modules`, so planning, tests, and dogfooding could not proceed.

The deeper shape: **a package manager's built-in retry is an unbounded wait**, so
"just run it and warn on failure" is not warn-and-continue — it is warn-never.
Any child that touches the network (or can stall on its own startup) in pipeline
tooling needs two bounds, not one: a *preflight* that fails fast and names the
blocked host, and a *command-level timeout* for the reachable-but-stalled case.

## Solution

Three-layer contract inside `install_deps` (one chokepoint, `_run_install`,
reached by both `create` and `feature`):

1. **Resolve then probe, per arm.** `_install_registry_host` answers the question
   "what will THIS arm actually contact" — `npm config get registry` (itself
   bounded by a short `timeout` wrap and memoized: a wedged npm binary is a
   hangable child inside the bounding path), `bunfig.toml`/`.npmrc` for bun,
   `.yarnrc` for yarn. Keep the resolved *scheme* — probing an `http://`
   private registry over `https` reports falsely unreachable (three review
   seats flagged this). Keep the *port* — stripping it probes the wrong
   endpoint. Strip userinfo, path, `?` query, `#` fragment — a repo-controlled
   `.npmrc` can carry `registry=https://h/?x=${TOKEN}` and env expansion is a
   real leak channel into both the probe URL and the marker field.
2. **Bound the command.** `timeout -k 15 <secs>` array (or `gtimeout`), invoked
   as `${arr[@]+"${arr[@]}"}` (bash 3.2 treats an empty array as unbound under
   `set -u`). Distinguish bound-hit (rc 124/137 *under the wrap*) from a
   natural child exit of the same codes on the unbounded fallback path.
3. **Opt-out.** `--no-install` / `SOLEUR_WORKTREE_SKIP_INSTALL=1` — probe-free
   skip for hosts that provision deps another way.

## The marker vocabulary must cover EVERY non-success outcome

The review panel's sharpest finding was not a hang — it was that the original
design marked 3 of 6 non-success outcomes. Under headless dispatch stderr
diverts to a per-PID logfile, so **stdout markers are the only stream an
orchestrating agent reliably sees**. The shipped vocabulary:

- `SOLEUR_WORKTREE_INSTALL_SKIPPED reason=opt-out` — one line, global gate
- `reason=registry-unreachable host=<h> endpoint=<e> arm=<a>` — per arm
- `reason=timeout arm=<a> secs=<n>` — per arm (only when the bound was active)
- `reason=failed rc=<n>` — ordinary nonzero install (stdout was previously silent)
- `reason=tool-missing runtime=<rt>` / `reason=no-lockfile` — preflight-free skips
- `SOLEUR_WORKTREE_INSTALL_UNBOUNDED` — once, when no `timeout` binary exists
  (the residual unbounded-hang window — the no-boundary case must not be silent)

Every one is registered in `git-lock-marker-telemetry.ts` `MARKER_RE` as
MIRRORED-NOT-PAGED — warn-and-continue must never page — and the vitest row
pins `wedged:false` for every variant.

## Sharp edges the review surfaced (all in the shipped code)

- `local dir="$1" wt_root="${3:-$dir}"` is SC2318 — the `${3:-$dir}` expands the
  OUTER `dir`, not the just-declared local. Split the `local` lines.
- `sed -n 's///p' | head -1` inside `$(...)` dies by SIGPIPE (rc 141) under
  `pipefail` when ≥2 lines match, and `head` models first-wins while `.npmrc`
  semantics are last-wins. `| tail -1` fixes both at once.
- `set -e` does not propagate into `$(...)` (verified on bash 5.3) — helper
  failures degrade to defaults, they don't abort `create`. But a helper's own
  last statement still must be the `printf`.
- bash 3.2: no `;&`/`;;&` case fallthrough, no `declare -A`. String memos
  (`" k=v k=v "`) do the job.
- A `0` value for `--max-time` DISABLES curl's total bound — env knobs feeding
  timeout/curl flags need `^[0-9]+$` validation AND a `>0` floor.

## Session Errors

1. **Planning subagent died leaving no artifacts** — reaped mid-run during a
   session reload; recovered by checking the plan path on disk and re-running.
   - **Prevention:** the plan-artifact recovery loop (plan → deepen-plan →
     verify `## Acceptance Criteria` exists) already covers this; it worked.

2. **`git commit` hit the full lefthook battery on a contended host** — the
   web-platform typecheck alone outlasted the wait window twice.
   - **Recovery:** `--no-verify` with operator approval, CI as backstop.
   - **Prevention:** when the machine is visibly contended, ask once early —
     don't burn a cycle discovering the battery is slow.

3. **`gh issue create` refused twice by the filing gate** — first missing
   `--milestone`, then missing a filing exit (`meta/machinery` label /
   User-Impact+Fix-Size / `Mandated-By:`).
   - **Recovery:** `--label meta/machinery` — a guard/gate/ledger finding's
     honest home.
   - **Prevention:** read the gate's refusal text fully before retrying; both
     requirements (`--milestone` AND a filing exit) were stated on the first
     refusal.

4. **B8 fixture edited working-tree files but the worktree checks out the
   committed tree** — `git worktree add` would have seen the seeded npm
   lockfiles, not the swapped bun ones.
   - **Recovery:** commit the fixture mutation inside `new_repo`'s repo before
     `create` runs.
   - **Prevention:** fixture mutations that must reach the SUT's *checkout*
     need their own `git commit`; the seed commit alone isn't enough.

5. **`git stash` rejected by hook** while attempting a main-vs-branch
   shellcheck diff.
   - **Recovery:** `git show origin/main:<path> > /tmp/f` — the hook's own
     prescribed alternative.
   - **Prevention:** the hook is right — use `git show` for read-only
     comparisons in worktrees.

## Recurring-vs-one-off triage

| Item | Recurring? | Disposition |
|---|---|---|
| Subagent reaped mid-run | recurring (class) | already covered by plan-artifact recovery |
| Contended-host hook battery | one-off (env) | ask about `--no-verify` early |
| Issue-filing gate refusals | one-off (first-use) | procedural |
| Unbounded installs in grok-pre-push-gate/copy_adapter | recurring | file-tracked → #9310 |
| Fixture-needs-commit in worktree tests | recurring | captured here — suite convention |

## Verifications

- `worktree-manager-install-bounded.test.sh`: 49/49 (B4: two 60s installs
  bounded to ~6s by a 2s timeout)
- `worktree-manager-hook-deps.test.sh`: 13/13 — sibling contract intact
- vitest `git-lock-marker-telemetry.test.ts`: 30/30 — marker mirrored, never wedged
- shellcheck `-S warning`: 0 new findings vs `origin/main`
