# Session state — feat-kb-blueprint-manifest (#7332 / PR #7336)

**Last updated:** 2026-08-09 · **HEAD:** `a77cee758` · tree clean, pushed, **0 ahead / 6 behind `origin/main`**

> ⚠️ Everything in `### Decisions` below is INTENT unless marked VERIFIED. Probe each
> outward-facing claim before treating it as done (`gh issue view`, `ls`, re-run the
> command). This section is written mid-flight and a crash leaves claims without acts.

## Where this is

PR #7336 is **still a draft**, labels `semver:minor` + `secret-scan-allow-rename`.
Scope is PR 1 only (CLI producers); PR 2 (manifest + dashboard) is deferred and scoped
in the plan. Issue #7332 stays OPEN — the PR body deliberately uses `Ref`, not `Closes`,
because the issue's subject is the *manifest*, which PR 2 delivers.

**CI has never run on any of these commits.** Only `pull_request_target` workflows (CLA)
fire on a draft; `pull_request` ones — including `test` — do not. Marking ready is what
finally exercises them. CodeQL is the one exception and it passes.

## What is done

Implementation (Phases 0–5) plus a 13-agent review whose findings are all closed:
**9 review-fix commits**, `1c536d2a5..a77cee758`. Every finding's evidence lives in its
commit message — read those rather than re-deriving. The scratchpad `findings.md` is gone.

Verification at HEAD: 1,363 unit tests + 8 shell suites green, `tsc --strict` clean on
the four changed TS modules.

## Do this next, in order

1. **Rebase onto `origin/main` (6 behind) — this is not routine here.**
   `e9a44b055` is *"legal: controller/processor determination for alpha-tester repository
   data (#7342)"*. ADR-171 §Observability boundary claim 3 argues exactly that: routing
   customer repo data to Soleur infra "makes Soleur a data controller for data it never
   disclosed collecting". **Reconcile ADR-171 against #7342 before shipping** — if that
   determination says something different, the ADR's consent argument (which is what
   carries the whole layer-7 decision, since the second reason was refuted) needs
   amending. A premise refuted or confirmed at Phase 0 is stale after a rebase.
   Also re-check `1839306b5` (worktree lease fix) against this worktree's lease.

2. **`/soleur:compound`** — four learnings, one of which is the highest-value output of
   this whole session:
   - **The shell-capture trap, three distinct instances in one PR.** `x=$(cmd)` aborting
     under `set -e`; `grep | wc -l` aborting in a new guard; `grep -c` printing `0` AND
     exiting 1 so `|| echo 0` yields `"0\n0"`. One root: a command that legitimately
     exits non-zero, captured without deciding what its exit means. **This deserves a
     repo-level lint (`scripts/lint-*` + `test-all.sh` registration), not a fourth
     comment** — I hit it twice while writing fixes for it.
   - A gate whose inputs are parsed from a tool's output has the parse as part of the gate
     (`relations` vs `relationships` made it fire on every corpus).
   - A mutation battery only covers the axes you mutate — mine reported 13/13 killed;
     an independent one found 15 of 16 surviving.
   - Self-referential pinning: tests that index the constant they pin (`[0]`, `.length`)
     verify internal consistency and cannot see a wrong value.

3. **`/soleur:ship`** — marks ready, which is when CI first runs. Expect to iterate.

## Landmines a fresh session will otherwise re-derive

- **`.claude/settings.json` has no PostToolUse `Bash` matcher**, so the local CLI is
  unmirrored — but `plugins/soleur/**` IS vendored into the prod image and executed
  there under the `Bash` marker extractor (`agent-runner-query-options.ts` loads the
  plugin and registers the hook in the same options object). **Layer 7 is a property of
  the EXECUTION surface, not the file's location.** My first pass got this wrong and it
  is corrected in three places; do not "fix" it back.
- **`npx -y <pkg>@<version>` ignores a global install** (verified with a control), so
  `ci.yml`'s `npm install -g likec4` does nothing for the producer suite.
- **`test-scripts` now needs `setup-bun`** — added, with a guard
  (`scripts-shard-runtime-coverage.test.sh`) that reds if it is removed. The old
  detection predicate `grep -l '^bun '` is column-1 anchored and cannot see a call inside
  a function body; do not restore it.
- **The relationship gate reads `edges.length`, NOT the rendered count.** `likec4 export
  json .` renders the whole directory, so the merged count is dominated by any
  hand-authored `model.c4`. Reverting this makes the gate unreachable on any repo that
  already has a C4 model.
- **`kb-coverage.md` is a STATE snapshot; stdout is the RUN log.** Every marker field is
  a pure function of the tree. Do not reintroduce count flags — an absent `--c4-elements`
  silently became `0`, byte-identical to the failure mode the artifact exists to detect.
- Registering a new `plugins/soleur/test/*.test.sh` is auto-globbed into the scripts
  shard; a new `tests/scripts/test-*.sh` is NOT — it needs an explicit `run_suite` line.

## Known-open, none blocking

`writeIfAbsent`'s filename-only spec.c4 check (documented limitation, not a false claim
any more); `init`'s check-then-create race (`mv` replaces unconditionally; `sync.md` calls
it every run); the `mktemp` cross-device non-atomicity in `init_register`/`write_row`;
`loadComponentDir` unguarded against a FIFO named `*.md`; register created at mode 0600.
All are recorded in the review commit messages with reproductions.
