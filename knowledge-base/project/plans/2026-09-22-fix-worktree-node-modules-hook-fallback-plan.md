---
title: "fix: fresh worktrees lack node_modules — markdown-lint hook hard-fails first docs commit"
type: fix
date: 2026-09-22
slug: worktree-node-modules-hook-fallback
branch: feat-one-shot-8580-worktree-node-modules
issue: 8580
---

## Enhancement Summary

**Deepened on:** 2026-09-22
**Passes run:** inline deepen-plan (no Task/agent-spawn surface in this
harness — halt gates + verify-the-negative greps + precedent diffs executed
directly)

### Key Improvements

1. Caught the M7a single-invoker false-positive trap: any literal
   `markdownlint-cli` / `.bin/markdownlint` / command-position `markdownlint`
   followed by whitespace, written into `worktree-manager.sh` or the new test
   file, would be reported as a second invoker — the plan now prescribes the
   repo's own token-splitting convention (bare names in an array, paths
   composed from a variable).
2. Bound the porcelain parse to the `_porcelain_has_line` precedent —
   capture-then-iterate, never `| grep -q` (SIGPIPE under `pipefail`, proven
   red by `worktree-manager-porcelain-sigpipe.test.sh`) — plus the empty-parse
   and newline-path degradation rules.
3. Corrected two imprecise claims: `git worktree add` does fire
   `post-checkout` (the gap is that hooks are untracked/unshippable, not that
   no hook point exists), and `npx tsc` in `web-platform-typecheck` is a
   second `node_modules`-resolving hook (kept out of scope, now named).
4. Fixed the test design: the sandbox commits its `node_modules` symlink, so
   linked-worktree rows must unlink the materialized copy before the fallback
   path is exercised; added the T1b row proving the porcelain enumeration arm
   (not just the primary fast path).

### New Considerations Discovered

- Engine-version verification must probe nearest-scope-first
  (`markdownlint-cli/node_modules/markdownlint` before hoisted
  `node_modules/markdownlint`) to match node's own resolution.
- `require.resolve` cannot locate the engine's `package.json` — its `exports`
  field rejects the subpath; filesystem probes are the only option.
- The primary checkout appears in `git worktree list --porcelain` with a
  `bare` attribute yet carries `node_modules` — `bare` blocks must not be
  filtered.

# fix: fresh worktrees lack node_modules — markdown-lint hook hard-fails first docs commit

## Overview

Worktrees created outside `worktree-manager.sh` — harness agent worktrees under
`.claude/worktrees/agent-*`, the detached postmerge worktree `ship/SKILL.md`
prescribes, review-panel detached worktrees `review/SKILL.md` prescribes, manual
`git worktree add` recovery paths, and manager-created worktrees whose
`install_deps` step warned and continued — carry no `node_modules`. The
lefthook shim lives in the shared git dir (`.git/hooks/pre-commit`, no
`core.hooksPath`), so **every** linked worktree runs the `markdown-lint`
pre-commit command, which resolves its pinned binary only from the worktree's
own `node_modules/.bin/` and dies before any commit staging a `.md` file.

The fix moves resilience to the consumption point: `scripts/markdown-lint.sh`
is the single invoker every caller already flows through (the M7
single-invoker guard enforces that), so a pin-verified sibling-worktree
resolution there covers every creation path at once — including ones we do not
control (the agent harness) and ones that cannot exist (git has no
post-worktree-add hook). Complementary: `install_deps()` learns to enumerate
the hook-required binaries it just installed (or failed to), and
`scripts/test-all.sh` learns to fail fast with a named remediation instead of
`vitest: not found` (the #2398 arm).

## Problem Statement

Issue #8580 (OPEN, `meta/machinery`): the `markdown-lint` pre-commit hook
refuses an `npx` fallback by design (#7927), so a worktree without
`node_modules` cannot commit any `.md` file. Observed 2026-09-22 on
`feat-queue-health-monitor`: the first docs commit was blocked until a manual
`npm install` was run.

Adjacent issue #2398 (OPEN, `bug`, `priority/p2-medium`,
`domain/engineering`): a manager-created worktree was missing
`apps/web-platform/node_modules`, and `scripts/test-all.sh` failed deep inside
the suite with `vitest: not found`. Its suggested fix — run `npm ci` per app at
create time — is what `install_deps()` already does today (added 2026-03-28 in
`feat-worktree-auto-install`), so the residual is (a) installs that warn and
continue, and (b) creation paths that bypass the manager entirely.

### Why the fix belongs at the consumption point

- **The bypassing creation paths are unenumerable.** `.claude/worktrees/agent-*`
  directories are created by the agent harness, not by repo code we can change.
  `ship/SKILL.md:26` and `review/SKILL.md` prescribe raw
  `git worktree add --detach` for postmerge and report-only seats. Operators
  and recovery procedures add worktrees by hand. There is no *shippable*
  interception point: `git worktree add` does fire `post-checkout`, but hook
  files live in the untracked shared `.git/hooks/` (owned here by the lefthook
  shim) — nothing in that directory can be committed, so a hook-based fix
  could never reach another clone or the harness that creates `agent-*`
  worktrees.
- **The hook fires everywhere.** Lefthook installs its shim at
  `.git/hooks/pre-commit` in the shared git dir (verified: no `core.hooksPath`
  set), so every linked worktree — including detached and harness-created ones —
  runs `bash scripts/markdown-lint.sh {staged_files}` on `.md` commits.
- **The invoker is a chokepoint by design.** `markdown-lint.test.sh` M7 greps
  every lefthook/workflow/package.json command position for a second markdownlint
  invocation; there is exactly one code path that turns a commit into a lint run.

## Research Insights

Measured against the live checkout on 2026-09-22:

- `worktree-manager.sh` `install_deps()` (lines 1650–1754) runs root
  `npm ci --ignore-scripts --prefix <wt>` plus a per-`apps/*/` lockfile-detected
  install, invoked from both creation paths (lines 2055, 2193). Every failure
  arm prints a `Warning:` and **continues** — a worktree can be reported
  "created" with zero binaries installed.
- This worktree's `node_modules/.bin/markdownlint` is a symlink to
  `../markdownlint-cli/markdownlint.js`; `markdownlint --version` prints
  `0.49.1`, matching the exact `package.json` devDependency pin `0.49.1`; the
  rules engine `markdownlint` is installed at 0.41.1, matching the
  `package-lock.json` entry.
- `git worktree list --porcelain` from a linked worktree lists every worktree,
  including the primary checkout as `worktree <path>` + `bare` attribute — and
  that path **does** carry `node_modules` on this host, so a resolver must not
  skip `bare` blocks; the `-x` existence test is the real guard. Verified under
  exported `GIT_DIR`/`GIT_INDEX_FILE` (the lefthook hook environment per
  `lefthook.yml:360-367`): the listing and `git rev-parse --git-common-dir`
  both resolve correctly.
- Binary-presence sweep across live worktrees: the main checkout, this
  worktree, and most `.worktrees/*` carry `node_modules`; most
  `.claude/worktrees/agent-*` and several `postmerge-*`/`ops-*`/`luks-stage-*`
  worktrees do not.
- `markdown-lint.sh` preconditions (lines 50–81): `-x $BIN` dies at line 52;
  CLI pin is read from `package.json` devDependencies via python3 (line 54);
  `bin --version` must equal it (line 60); the engine pin is read from
  `package-lock.json` `packages` (lines 68–75) and compared to
  `$REPO_ROOT/node_modules/markdownlint/package.json` (lines 76–81).
- `node_modules/markdownlint-cli/node_modules/` exists but contains no
  `markdownlint` — the engine is hoisted. Node resolves a dependency
  nearest-scope-first, so a sibling check must probe
  `<NM>/markdownlint-cli/node_modules/markdownlint/package.json` **before**
  `<NM>/markdownlint/package.json`. `require.resolve('markdownlint/package.json')`
  is unusable — the package's `exports` field rejects the subpath (measured,
  ERR_PACKAGE_PATH_NOT_EXPORTED on node v26.8.1).
- `lefthook.yml` audit: `markdown-lint` is the only hook that *hard-requires*
  a root `node_modules/.bin` binary with no runner. Two same-class surfaces
  exist but are out of this plan's mechanism: `web-platform-typecheck` runs
  `npx tsc --noEmit` inside `apps/web-platform` (line 204 — npx resolves
  `apps/web-platform/node_modules/.bin/tsc`, ranged pin `^5.7.0`, and in an
  uninstalled worktree npx either errors or fetches — itself a member of the
  unpinned-resolution class), and `bun-test` runs `bash scripts/test-all.sh`
  (line 356 — the #2398 surface). `lint-fixture-content` runs
  `node apps/web-platform/scripts/lint-fixture-content.mjs`, which imports only
  `node:fs` (verified: single import, line 18) — no deps needed.
- `test-all.sh:2720-2742` runs `cd apps/web-platform && npm run test:ci`
  (`vitest run`) with **no** precondition that
  `apps/web-platform/node_modules/.bin/vitest` exists — the `vitest: not found`
  deep-fail #2398 reports. Vitest pin is ranged (`^4.1.0`); the app has its own
  `package-lock.json` (locked `4.1.0`).
- **Sibling execution is viable for markdownlint and NOT for vitest.**
  markdownlint's config is plain JSON (`--config .markdownlint.json` —
  `.markdownlintignore` is already bypassed via `--ignore-path /dev/null`,
  lines 231–237) and its engine resolves relative to the *binary's* own
  node_modules tree. `vitest run` loads `apps/web-platform/vitest.config.ts`,
  whose imports resolve relative to the *config file's* directory — the
  consuming worktree — never the sibling's node_modules. A sibling vitest
  binary would still die resolving config imports.
- The test suite `scripts/markdown-lint.test.sh` is a hermetic `git init`
  sandbox whose `node_modules` is a symlink to the real tree's; `git worktree
  add` works inside it, so sibling-resolution rows are exercise-able without
  touching the real repo's worktree set (a sandbox's `git worktree list` sees
  only sandbox worktrees — the suite is isolated from the real topology by
  construction). The suite runs only in the `markdown-lint` job of
  `pr-quality-guards.yml`, which does `npm ci --ignore-scripts` first.
- `plugins/soleur/test/*.test.sh` is a registered `SUITE_GLOBS` entry in
  `test-all.sh:78` — a new worktree-manager test file there is auto-discovered.
  No existing test covers `install_deps` output.
- ADR-009 scopes worktree isolation to **files under version control** — its
  2026-07-15 amendment already narrowed "full isolation" for shared `/tmp`
  scratch. A read-only, version-verified resolve of a sibling's *untracked*
  `node_modules` binary extends that boundary in one new direction (reading
  inside a sibling's directory rather than a shared scratch space) and warrants
  a one-paragraph consequence-note amendment, not a new ADR.
- C4: `knowledge-base/engineering/architecture/diagrams/model.c4` models the
  shipped platform and plugin surface; dev-host worktree dependency resolution
  has no element or edge. The only `worktree-manager.sh` mention (the
  `devin -> platform.plugin` edge, re: reap-capability token) is unrelated.
  `views.c4`/`spec.c4` carry no worktree-deps surface. No C4 change.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Measured state | Disposition |
|---|---|---|
| #8580 "worktree creation does not provision node dependencies" | `install_deps()` exists and runs on both manager create paths (1650–1754, called at 2055/2193) | Stale — true before 2026-03-28 (`feat-worktree-auto-install`); the residual is bypass paths + warn-and-continue |
| #8580 "fresh worktrees lack node_modules" | The reporting worktree (`feat-queue-health-monitor`) predates or failed install; agent/postmerge/manual worktrees still get nothing | Confirmed for non-manager paths |
| #2398 "worktree creation doesn't install apps/web-platform node_modules" | Per-app install loop exists (1708–1753) | Stale as stated; residual is silent warn-and-continue + bypass paths |
| #7927 "no npx fallback" | `markdown-lint.sh:52` dies naming `npm install --ignore-scripts`; comment at 44–47 states the invariant | Confirmed — must not regress |

## Proposed Solution

Three small changes, ordered by where each failure is cheapest to intercept:

### 1. `scripts/markdown-lint.sh` — pin-verified sibling resolution

Restructure the precondition block (current lines 48–81) so that "binary
absent" and "binary wrong" stay distinct:

- Compute `PINNED` (package.json devDep) and `ENGINE_PIN` (package-lock.json)
  **before** binary resolution — both read tracked files that exist in every
  worktree regardless of install state.
- Keep today's exact semantics when the local binary **exists**: wrong CLI or
  engine version dies immediately (the #7927 contract is unchanged for an
  installed tree — a half-installed local tree must fail, not silently detour).
- When `$REPO_ROOT/node_modules/.bin/markdownlint` is **absent**, build a
  candidate list:
  1. `$(dirname "$(git rev-parse --git-common-dir)")` — the primary checkout
     (the operator-owned install; smallest trust surface; covers the observed
     incident shape).
  2. Every `worktree <path>` line from `git worktree list --porcelain` —
     dedupe by realpath, drop `$REPO_ROOT` itself, iterate in `LC_ALL=C sort`
     order for determinism. Do **not** filter `bare`-attributed blocks (the
     primary checkout reports `bare` here and carries node_modules). Stale
     (prunable) entries fail the `-x` check naturally.
  - **Parsing must follow the `_porcelain_has_line` precedent**
    (`worktree-manager.sh:1091-1111`, guarded by
    `plugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh`):
    capture `git worktree list --porcelain` into a variable with an rc check
    and `2>/dev/null`, then iterate the `worktree <path>` lines from the
    variable.
    NEVER `| grep -q` or early-break a `while read` fed by the pipe —
    `grep -q` closes the pipe early, git takes SIGPIPE, and `pipefail`
    promotes 141 to failure precisely when the needle is present and early.
    A path containing a newline splits one record across two lines (the
    `worktree-manager.sh:2592` edge note); the truncated candidate fails `-x`
    and is skipped — acceptable degradation, no unquoting needed.
  - If `git worktree list` fails or yields zero `worktree <path>` lines (any valid
    repo emits at least one — the main worktree — so empty output is an
    anomalous registry, per the fail-closed note at
    `worktree-manager.sh:2499-2505`), treat the candidate set as empty and
    continue to the die path.
- A candidate is accepted iff: `-x <wt>/node_modules/.bin/markdownlint`, its
  `--version` equals `PINNED`, **and** its engine version equals `ENGINE_PIN`,
  where the engine package.json is probed nearest-scope-first at
  `<NM>/markdownlint-cli/node_modules/markdownlint/package.json` then
  `<NM>/markdownlint/package.json` with `NM` = `dirname(dirname(<bin>))`
  (node_modules is structurally `dirname(dirname(.bin/markdownlint))` — no
  `readlink` needed; note a future npm-shim-shaped `.bin` entry would make the
  second probe the load-bearing one).
- On fallback success, emit one stderr line:
  `markdown-lint: using pinned binary from <path> (this worktree has no node_modules)`.
  Non-silent by construction; the run is still fully version-pinned.
- On total failure, die with an enriched message: local missing, N sibling
  candidates checked (names them), and the deterministic recovery
  `npm ci --ignore-scripts`. No `npx`, no network, no writes to siblings —
  read-only throughout.

### 2. `worktree-manager.sh` — enumerate hook-required binaries after install

At the end of `install_deps()` (after line 1753, unconditionally — covering
both the install and the `node_modules`-already-present skip paths), loop a
named array of hook-required binary **names** (`markdownlint` today) and test
`"$worktree_path/node_modules/.bin/<name>"` for `-x`. Print a `✓`-style line
when present, else a `Warning:` to stderr naming
`npm ci --ignore-scripts --prefix <wt>` — converts today's warn-and-continue
into a visible diagnosis at the moment of creation.

**Token constraint (measured, load-bearing).** The M7a single-invoker probe
(`markdown-lint.test.sh:301-341`) greps every `*.sh` under `scripts/`,
`plugins/`, `apps/`, `.github/`, `.claude/hooks/`, `tests/` — comment-stripped
— for `markdownlint-cli`, `.bin/markdownlint`, `npx...markdownlint`, or
command-position `markdownlint` (followed by whitespace). Both
`worktree-manager.sh` and the new test file are in its scan set, and a literal
`node_modules/.bin/markdownlint` would false-positive as a "second invoker".
The established evasion is lefthook.yml's own convention ("prose that names a
forbidden literal is a trap worth not setting", `lefthook.yml:22-25`):
the array holds bare names — `("markdownlint")` — and paths are composed as
`"$worktree_path/node_modules/.bin/$hb"`; output text never writes
`markdownlint` adjacent to `.bin/`, followed by whitespace, or with a `-cli`
suffix. Assert on neutral markers (`hook dep`, `missing`, the recovery
command) instead. `markdown-lint.sh` itself and `markdown-lint.test.sh` are
both named exclusions in `call_sites` (lines 304, 308), so the SUT and its
suite may write the literals freely.

### 3. `scripts/test-all.sh` — vitest precondition (adjacent #2398 arm)

Inside the `want_webplat` block (before line 2732's first `run_suite`), check
`[[ -x apps/web-platform/node_modules/.bin/vitest ]]`; if absent, fail the
suite with a named precondition error:
`apps/web-platform/node_modules missing — run: npm ci --ignore-scripts --prefix apps/web-platform`.
Sibling execution is deliberately NOT used here (config-import resolution —
see Research Insights); a graceful *skip* is also rejected because test-all.sh
is a gate and a silent skip is a vacuity.

### 4. Doc/comment coherence

- `lefthook.yml:37-42` — the comment claims worktrees "get deps from
  worktree-manager.sh, so this bites a fresh clone rather than normal use."
  Stale: it bit every non-manager worktree. Update to describe the sibling
  resolution and the die path.
- `plugins/soleur/skills/git-worktree/SKILL.md` — near the manual-add/env-copy
  guidance (~line 320), one bullet: hook-required pinned binaries resolve from
  a sibling checkout automatically; full deps still need
  `npm ci --ignore-scripts` (and app deps for vitest).
- `knowledge-base/engineering/architecture/decisions/ADR-009-git-worktree-isolation.md`
  — consequence-note amendment: a worktree-local hook may READ (never write) a
  sibling worktree's untracked `node_modules` binaries, gated on the binary's
  self-reported version equaling the consuming checkout's pins; tracked-file
  isolation is unchanged.

## Technical Considerations

- **Trust surface.** Executing a sibling worktree's binary is a mild expansion:
  version self-report (`--version`) bounds accidental drift, not adversarial
  tamper. Accepted because every listed worktree is an operator-created
  checkout of the same repo — the same trust domain as the operator's own
  `node_modules`. The primary checkout is tried first precisely because it is
  the smallest surface. A `markdownlint`-specific residual: a deliberately
  planted binary in an agent worktree could spoof `--version`; judged
  acceptable for a local lint gate whose worst case is a wrong verdict on a
  local commit — CI's `markdown-lint` job re-verifies from a clean `npm ci`.
- **Lefthook hook env.** `git` calls inside the script run under
  lefthook-exported `GIT_DIR`/`GIT_INDEX_FILE` (absolute, per
  `lefthook.yml:360-367`). Verified `git worktree list --porcelain` and
  `git rev-parse --git-common-dir` behave correctly under both; a test row
  exports them to lock the behavior.
- **Determinism.** Candidate order is fixed (primary first, then sorted
  porcelain paths); first compliant candidate wins; the emitted notice names
  which one. No timestamps, no randomness.
- **Performance.** The fallback path costs one `git worktree list` plus `-x`
  stat per candidate, and runs only when the local binary is absent — the
  common path is unchanged (one extra `-x` test).
- **Security.** No `npx`, no network, no writes outside the worktree (the
  script only reads sibling paths). Version equality is checked against the
  *consuming* worktree's manifest/lockfile, never the sibling's — a sibling on
  an older commit with a different pin is rejected, not followed.
- **NFR.** Local tooling; no production NFR impact. Reliability improves:
  first-commit friction on non-manager worktrees goes to zero when any
  compliant sibling exists.

## Files to Create

- `plugins/soleur/test/worktree-manager-hook-deps.test.sh` — sandbox test for
  the `install_deps` enumeration output (both the found and missing shapes).

## Files to Edit

- `scripts/markdown-lint.sh` — sibling-resolution block; enriched die message.
- `scripts/markdown-lint.test.sh` — new sibling-resolution mutation rows.
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` —
  `HOOK_REQUIRED_BINS` enumeration at end of `install_deps()`.
- `scripts/test-all.sh` — vitest precondition in the `want_webplat` arm.
- `lefthook.yml` — stale comment update only (no `run:` change).
- `plugins/soleur/skills/git-worktree/SKILL.md` — manual-worktree deps note.
- `knowledge-base/engineering/architecture/decisions/ADR-009-git-worktree-isolation.md`
  — consequence-note amendment.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (2026-09-22) for
paths overlapping this plan's Files to Edit:

- #8496 `cleanup-merged never gh-queries [gone] branches` — same file
  (`worktree-manager.sh`) but a disjoint function (`cleanup_worktrees`, not
  `install_deps`). No conflict; note for the /work phase that the file may
  shift under review.
- No open code-review issues touch `scripts/markdown-lint.sh`,
  `scripts/test-all.sh`, `lefthook.yml`, or the git-worktree SKILL.md.

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-009` (Consequences) — the decision record already scopes isolation
to the working tree and documents the shared-`/tmp` amendment; the new
boundary fact is that a worktree's hook scripts may resolve a **sibling**
worktree's untracked `node_modules` binary read-only, provided the sibling
binary's self-reported versions equal the consuming checkout's pins. One
paragraph; no reversal.

### C4

No model or view change. Verified by reading
`knowledge-base/engineering/architecture/diagrams/model.c4` (824 lines),
`views.c4`, `spec.c4` on 2026-09-22: no element, container, or edge models
dev-host worktree dependency resolution; the only `worktree-manager.sh`
mention is the `devin -> platform.plugin` edge's reap-token clause, unaffected.

## User-Brand Impact

- **If this lands broken, the user experiences:** either a docs commit still
  blocked by a missing binary (no worse than today — the die path is
  preserved), or a lint verdict computed by a wrong-version binary (the
  scenario #7927 exists to prevent). Both failure arms are test-locked: the
  version predicates are unchanged, and a sibling is accepted only after
  passing them.
- **If this leaks, the user's [data / workflow / money] is exposed via:** not
  applicable — read-only resolution of binaries inside operator-owned
  checkouts on the same host; nothing is transmitted or written across
  worktree boundaries.
- **Brand-survival threshold:** `none` — internal developer tooling; no
  sensitive paths touched (Files to Edit matches none of the canonical
  sensitive-path regex classes).

## Observability

The deliverable is a local hook/invoker — its observable signal is the die/notice
text at commit time and the CI job that re-runs the sweep from a clean install.

```yaml
liveness_signal:
  what: "lefthook pre-commit markdown-lint exit code, plus the markdown-lint job in .github/workflows/pr-quality-guards.yml"
  cadence: "per-commit (local) and per-PR (CI)"
  alert_target: "committer's terminal (lefthook surfaces stderr); PR check status"
  configured_in: "lefthook.yml (markdown-lint command) and .github/workflows/pr-quality-guards.yml (markdown-lint job)"

error_reporting:
  destination: "stderr at commit time (markdown-lint: prefixed die/notice lines)"
  fail_loud: "exit 2 die naming the missing binary, the siblings checked, and npm ci --ignore-scripts; the sibling-resolution notice prints which checkout supplied the binary"

failure_modes:
  - mode: "no compliant binary anywhere (local absent, every sibling missing or version-mismatched)"
    detection: "die exit 2 with enumerated candidates — commit blocked with remediation"
    alert_route: "committer's terminal"
  - mode: "install_deps fails or is skipped at create time"
    detection: "worktree-manager output prints the missing hook-binary warning naming the recovery command"
    alert_route: "worktree-manager stdout/stderr at create"
  - mode: "apps/web-platform deps absent when webplat shard runs"
    detection: "test-all.sh precondition fails naming npm ci --ignore-scripts --prefix apps/web-platform"
    alert_route: "suite output / committer's terminal"

logs:
  where: "lefthook hook output and worktree-manager create output on the operator terminal"
  retention: "ephemeral (terminal); CI copy lives in the markdown-lint job log"

discoverability_test:
  command: "grep -l -e 'git worktree list --porcelain' scripts/markdown-lint.sh"
  expected_output: "scripts/markdown-lint.sh"
```

## Guard Contract

### Guard 1 — pin-verified binary resolution (`markdown-lint.sh`)

**Property.** The binary that lints is always the one whose CLI version equals
this checkout's `package.json` pin and whose rules-engine version equals this
checkout's `package-lock.json` pin — regardless of which worktree directory
supplied it — and no resolution path may substitute an unpinned or
network-fetched binary.

**Assembly.** The chokepoint is the `BIN` variable inside
`scripts/markdown-lint.sh`: every invocation — lefthook `{staged_files}`, CI
`--repo-sweep`, manual — flows through this single script (enforced by the M7
single-invoker probe) and reaches `xargs -0 "$BIN"` at the run site. The
candidate set is produced by exactly two enumerators (git-common-dir primary,
then sorted `git worktree list --porcelain` paths); every candidate must pass
the same version predicates before `BIN` is assigned. There is one predicate
site per version (CLI, engine), one `BIN` assignment site, one exec site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Accept a sibling whose `markdownlint --version` differs from `package.json`'s pin | RED |
| 2 | Accept a sibling whose `node_modules/markdownlint` engine version differs from `package-lock.json`'s pin | RED |
| 3 | Resolve via PATH or `npx` when no sibling qualifies (substitute `command -v markdownlint` / package-runner as a candidate source) | RED |
| 4 | Return the first `-x` sibling without running the version predicates (drop the predicate calls in the candidate loop) | RED |

## Acceptance Criteria

- [x] AC1: In a linked worktree with no `node_modules` where a sibling
  worktree carries `node_modules/.bin/markdownlint` at the exact pinned CLI
  and engine versions, `bash scripts/markdown-lint.sh <staged .md>` lints
  successfully and prints the `using pinned binary from <path>` notice.
- [x] AC2: A sibling candidate whose CLI `--version` differs from
  `package.json`'s pin is skipped; if no other candidate qualifies, the script
  dies exit 2 naming the checked candidates and `npm ci --ignore-scripts` — it
  never executes a version-mismatched binary.
- [x] AC3: A sibling candidate whose engine package version differs from
  `package-lock.json`'s `markdownlint` entry is skipped (engine check reads
  the candidate's own node_modules, nearest-scope first).
- [x] AC4: When the local `node_modules/.bin/markdownlint` exists, behavior is
  byte-identical to today — including dying on a version-mismatched LOCAL
  install rather than detouring to a sibling.
- [x] AC5: No `npx`, PATH-search, or network resolution is introduced; the
  script performs no writes outside the worktree.
- [x] AC6: `git worktree list --porcelain` parsing tolerates the `bare`
  attribute block (primary checkout is still a valid candidate when it carries
  the binary) and prunable/stale paths (`-x` filters them).
- [x] AC7: Resolution behaves correctly under lefthook-exported `GIT_DIR` and
  `GIT_INDEX_FILE` (locked by a test row exporting both).
- [x] AC8: `install_deps()` output after a create prints a per-binary status
  line for `node_modules/.bin/markdownlint` — `✓` when present, a warning
  naming `npm ci --ignore-scripts --prefix <wt>` when absent — in both the
  install-succeeded and install-skipped/failed shapes.
- [x] AC9: `bash scripts/test-all.sh` in a worktree missing
  `apps/web-platform/node_modules` fails the webplat arm fast, naming
  `npm ci --ignore-scripts --prefix apps/web-platform`, instead of dying deep
  with `vitest: not found`.
- [x] AC10: New mutation rows land in `scripts/markdown-lint.test.sh` and the
  suite stays green, including the CONTROL row proving the unmutated sandbox
  still sweeps ≥ `MIN_SWEPT_FILES`.
- [x] AC11: `lefthook.yml`'s markdown-lint comment, `git-worktree/SKILL.md`,
  and `ADR-009` are updated to describe the sibling-resolution contract; the
  lefthook `run:` line is unchanged.

## Test Scenarios

Sandbox mechanics that make these rows honest (all verified against
`markdown-lint.test.sh` on 2026-09-22):

- The sandbox **commits** its `node_modules` symlink (`ln -s` at
  `build_sandbox` line 71 precedes `git add -A` at line 126), so a
  `git worktree add`ed linked worktree materializes the symlink too. Every
  "no local bin" row must `rm` (unlink, no trailing slash) the materialized
  symlink in the running worktree first.
- Linked sandbox worktrees are created under `$TMPDIR` via
  `git -C "$SANDBOX" worktree add --detach <dir>` — outside the sandbox tree
  so fixture writes never interact with the corpus sweep (which counts only
  tracked files anyway).
- Stub binaries are synthesized fixtures (cq-test-fixtures-synthesized-only):
  a `#!/bin/sh` file echoing the pin for `--version` and `exit 0` otherwise;
  the engine pin fixture is a synthesized `package.json` carrying
  `{"version":"<ENGINE_PIN>"}` read from the sandbox's copied lockfile. Stub
  paths live under `<sib>/node_modules/.bin/` — never under `scripts/`, so the
  M7 `call_sites` sweep cannot see them.
- The linked worktree's `scripts/markdown-lint.sh` is the version committed in
  `build_sandbox`; rows that mutate the SUT file itself must `cp` the mutated
  copy into the linked worktree before invoking.

- **T1 (AC1, AC6):** linked worktree `$RUN` (materialized `node_modules`
  symlink unlinked); primary `$SANDBOX` keeps the real symlink → SUT invoked
  in `$RUN` → GREEN, notice names `$SANDBOX` (primary fast path).
- **T1b (AC1):** same, plus primary's `node_modules` symlink unlinked and a
  second linked worktree `$SIB` carrying a synthesized correct-version stub →
  GREEN via the porcelain enumeration arm, notice names `$SIB` — proves the
  arm beyond the fast path.
- **T2 (AC2):** primary unlinked; `$SIB` stub reports a wrong `--version` →
  RED, die message enumerates checked candidates and names
  `npm ci --ignore-scripts`.
- **T3 (AC3):** `$SIB` stub with correct CLI version; engine package planted
  at the WRONG version under `$SIB/node_modules/markdownlint-cli/node_modules/markdownlint/`
  while `$SIB/node_modules/markdownlint/package.json` carries the RIGHT one →
  RED — proves the nearest-scope probe order (node resolves nested first).
- **T4 (AC4):** local bin present but reporting a mismatched version → RED
  without sibling consultation (regression-lock of current semantics).
- **T5 (AC5):** no compliant binary anywhere AND PATH seeded with a fake
  `markdownlint` executable → RED — proves no PATH/package-runner fallback
  crept in.
- **T6 (AC7):** T1 re-run under exported `GIT_DIR`/`GIT_INDEX_FILE` pointing at
  the linked worktree's gitdir (the lefthook hook environment per
  `lefthook.yml:360-367`) → still GREEN.
- **T7 (AC8):** `worktree-manager-hook-deps.test.sh` sandbox: `create` on a
  repo whose `package.json` lacks a lockfile (install skipped) → output
  carries the missing-binary warning; and a PATH-stubbed `npm` that fabricates
  the binary → output carries the present-marker line. The test file itself
  must obey the M7a token constraint (compose `.bin` paths from a variable;
  assert on `hook dep`/`missing`/`npm ci --ignore-scripts` markers).
- **T8 (AC9):** `apps/web-platform/node_modules` absent in a throwaway
  worktree; the `want_webplat` arm reports the named precondition failure.
- **T9:** regression — existing M1–M7 rows and the CI `markdown-lint` job
  unchanged; suite green.

## Success Metrics

- A `.md` commit succeeds in a harness-created worktree (`.claude/worktrees/agent-*`)
  without a manual `npm install`, verified by T1/T6 shape.
- Zero commits linted by a binary whose CLI or engine version differs from the
  checkout's pins (version predicates unchanged; T2/T3/T4 lock them).
- `install_deps` warn-and-continue no longer silent about hook binaries (T7).

## Dependencies & Risks

- **Risk: sibling binary spoofed `--version`.** Local lint gates accept
  operator-machine trust; CI's `markdown-lint` job re-verifies from a clean
  `npm ci`, bounding the blast radius to a local wrong-verdict commit.
  Mitigation already in design: primary checkout preferred, exact-version
  predicates, no PATH fallback.
- **Risk: `git worktree list` sees no siblings on a true fresh clone.**
  Then the die path fires as today — degraded gracefully, message improved.
- **Risk: markdownlint-cli packaging change** (e.g., bin becomes a shim rather
  than a symlink). Mitigation: `NM` derives from the `.bin` path structure, not
  `readlink`; nested-scope engine probe covers a nested engine layout.
- **Risk: a sibling is reaped mid-commit.** `-x` test is the only window
  (stat-then-exec); a vanished sibling fails to exec and the commit reports a
  real error, not a wrong verdict.
- **Risk: `set -euo pipefail` interactions in the resolver.** Every candidate
  probe (`"$cand" --version`, engine `package.json` read, `git worktree list`)
  must sit in `if !`/`|| true`-guarded command substitutions — a nonzero
  candidate rc must skip, never abort the script. The `markdown-lint.test.sh`
  suite's sandbox runs the SUT under its own `set -uo pipefail`; the
  version-extraction pipelines (`... | tail -1 | tr -d`) inherit the SIGPIPE
  considerations from the `_porcelain_has_line` precedent.
- **Risk: node absent entirely.** The bin is a node script; `node` is a
  prerequisite the script already assumes (the pin extraction uses python3,
  the lint exec uses node). A machine without node fails `--version` on every
  candidate and lands on the die path — honest degradation.
- **Precedent-diff (deepen-plan 4.4 note):** nearest-precedent pattern is this
  repo's own git-dir-scratch and common-dir resolution idioms
  (`git rev-parse --git-common-dir` in `ship/SKILL.md:26`,
  `git worktree list --porcelain` consumers in `worktree-manager.sh` and
  `worktree-manager-porcelain-sigpipe.test.sh` — note the SIGPIPE guard
  precedent when parsing porcelain output under `set -o pipefail`). No
  canonical "resolve a binary from a sibling worktree" precedent exists;
  pattern is novel to this repo.
- **Dependency:** none external. `python3`, `git`, `node` already assumed by
  the script today.

## References & Research

- `scripts/markdown-lint.sh:35-81` — binary resolution + pin verification.
- `scripts/markdown-lint.test.sh` — hermetic mutation suite (sandbox at lines
  45–141; M-rows from ~192).
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:1650-1754`
  (install_deps), `2055`, `2193` (call sites).
- `lefthook.yml:18-45` (markdown-lint hook), `199-204` (web-platform-typecheck),
  `335-356` (bun-test), `360-367` (GIT_DIR export documentation).
- `scripts/test-all.sh:2693-2742` — webplat shard, no dep precondition.
- `plugins/soleur/skills/ship/SKILL.md:26` and
  `plugins/soleur/skills/review/SKILL.md:1547,1599` — raw `git worktree add
  --detach` prescriptions that bypass install_deps.
- `plugins/soleur/skills/git-worktree/SKILL.md:23,320,342,347-348` — manager
  mandate + documented manual paths.
- `knowledge-base/project/specs/feat-worktree-auto-install/` — the 2026-03-28
  work that added install_deps (why #2398's stated repro is stale).
- `knowledge-base/engineering/architecture/decisions/ADR-009-git-worktree-isolation.md`
  and `ADR-173-bare-config-polarity-for-linked-worktrees.md`.
- `plugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh` and
  `worktree-manager.sh:1091-1111` (`_porcelain_has_line`) — the porcelain-parse
  precedent this plan's resolver must follow.
- `scripts/markdown-lint.test.sh:301-341` — the M7a single-invoker scan whose
  token set constrains every other file this plan touches.
- Issues: #8580 (this), #2398 (adjacent vitest arm), #7927 (no-fallback design).

## Deepen-Plan Revisions

Recorded from the inline deepen pass (2026-09-22). Halt-gate dispositions:
User-Brand Impact present (`none`, no sensitive-path match) — pass;
Observability present, all five fields literal — pass; PAT scan — no hits;
UI-wireframe — no UI surface, skipped; Encryption Posture — no store or
network connection introduced (sibling reads are same-host filesystem reads,
not a cross-component connection), skipped; Guard Contract — present, one
guard, 4-row mutation matrix, `lint-guard-contract.py` green — pass.

- R1: "Git provides no post-worktree-add hook" was imprecise — `git worktree
  add` fires `post-checkout`. Corrected to the real claim: hooks are untracked
  shared-git-dir state, unshippable to other clones and unreachable by the
  harness-created worktrees that need coverage.
- R2: "`markdown-lint` is the only hook resolving a `node_modules/.bin`
  binary" was wrong — `web-platform-typecheck` (`npx tsc`, `lefthook.yml:204`)
  resolves `apps/web-platform/node_modules/.bin/tsc`. Restated: markdown-lint
  is the only hook that *hard-requires* a root bin with no runner; tsc/bun-test
  recorded as same-class out-of-scope surfaces.
- R3: M7a token constraint added to §2 — scanned `.sh` files may not contain
  `markdownlint-cli`, `.bin/markdownlint`, `npx...markdownlint`, or
  `markdownlint` followed by whitespace; the enumeration composes paths from
  a bare-name array, matching `lefthook.yml:22-25`'s own convention.
- R4: porcelain parsing bound to `_porcelain_has_line` (capture full output,
  rc-check, iterate the variable); zero-`worktree`-line output treated as
  anomalous; newline-bearing paths degrade to `-x` skip.
- R5: test design corrected — sandbox `node_modules` is a *committed* symlink,
  so linked-worktree rows unlink the materialized copy first; T1b added to
  prove the enumeration arm independent of the primary fast path; stub
  fixtures synthesized (correct/wrong CLI version × correct/wrong engine) and
  placed outside `call_sites` scan scope.
- R6: engine probe order fixed to nearest-scope-first
  (`markdownlint-cli/node_modules/markdownlint` before hoisted), matching
  node's resolution; `require.resolve` ruled out (exports-gated).
- R7: `bare`-attributed porcelain blocks must not be filtered — the primary
  checkout carries that attribute here and holds `node_modules`.
