# Tasks: fix worktree node_modules — markdown-lint hook fallback (#8580, #2398-adjacent)

Source plan: `knowledge-base/project/plans/2026-09-22-fix-worktree-node-modules-hook-fallback-plan.md`

## Phase 1: Sibling-resolution tests (RED first)

- [x] 1.0 Sandbox mechanics (plan §Test Scenarios): linked worktrees via `git -C "$SANDBOX" worktree add --detach $TMPDIR/<dir>`; the sandbox COMMITS its `node_modules` symlink so every "no local bin" row first unlinks (`rm`, no trailing slash) the materialized symlink in the running worktree; stub bins are synthesized `#!/bin/sh` echoing the pin under `--version`; stub paths stay under `<sib>/node_modules/.bin/` (outside M7 `call_sites` scope)
- [x] 1.1 In `scripts/markdown-lint.test.sh`, add a `run_sut_in <dir>` helper (or equivalent) so the SUT can be invoked from a linked worktree of the sandbox repo
- [x] 1.2 Add T1 row: linked worktree `$RUN` with materialized symlink unlinked; primary `$SANDBOX` keeps real symlink → GREEN + `using pinned binary from <path>` notice naming `$SANDBOX`
- [x] 1.2b Add T1b row: primary's symlink also unlinked; sibling `$SIB` carries a correct-version stub → GREEN via porcelain enumeration, notice names `$SIB`
- [x] 1.3 Add T2 row: primary unlinked; `$SIB` stub reports wrong `--version` → RED + enriched die enumerating candidates
- [x] 1.4 Add T3 row: `$SIB` correct CLI version but wrong engine planted at the nested scope (`markdownlint-cli/node_modules/markdownlint/`) while hoisted copy is correct → RED (proves nearest-scope-first)
- [x] 1.5 Add T4 row: local bin present but version-mismatched → RED without sibling detour
- [x] 1.6 Add T5 row: no compliant binary anywhere + fake `markdownlint` on PATH → RED (no PATH/package-runner fallback)
- [x] 1.7 Add T6 row: T1 shape re-run under exported `GIT_DIR`/`GIT_INDEX_FILE` → GREEN
- [x] 1.8 Confirm rows fail RED against the unmodified SUT

## Phase 2: `scripts/markdown-lint.sh` — pin-verified sibling resolution

- [x] 2.1 Reorder preconditions: compute `PINNED` (package.json) and `ENGINE_PIN` (package-lock.json) before binary resolution
- [x] 2.2 Keep existing local-binary path byte-identical: `-x` + CLI version + engine version → die on mismatch
- [x] 2.3 When local bin is absent: build candidate list — primary checkout (`dirname "$(git rev-parse --git-common-dir)"`) first, then sorted deduped `git worktree list --porcelain` `worktree <path>` entries minus `$REPO_ROOT`; do not skip `bare` blocks. Parse per `_porcelain_has_line` precedent: capture output to a var with rc check + `2>/dev/null`, iterate the var — never `| grep -q`/early-break (SIGPIPE under pipefail). List failure or zero `worktree <path>` lines → empty candidate set → die path.
- [x] 2.4 Per candidate: `-x` check, `--version` == PINNED, engine version == ENGINE_PIN probed nearest-scope-first (`<NM>/markdownlint-cli/node_modules/markdownlint/package.json` then `<NM>/markdownlint/package.json`, `NM` = `dirname(dirname(bin))`)
- [x] 2.5 On fallback success print the stderr notice naming the sibling; on total failure die listing checked candidates + `npm ci --ignore-scripts`
- [x] 2.6 Verify T1–T6 rows now pass GREEN; full suite green including CONTROL

## Phase 3: `worktree-manager.sh` — hook-binary enumeration

- [x] 3.0 M7a token constraint (plan §2, deepen R3): no scanned `.sh` file may contain literal `markdownlint-cli`, `.bin/markdownlint`, `npx...markdownlint`, or `markdownlint` followed by whitespace. Store bare names `("markdownlint")` and compose `"$worktree_path/node_modules/.bin/$hb"`; same rule for the new test file's assertions
- [x] 3.1 Add a `HOOK_REQUIRED_BINS`-style array of bare binary names + comment citing `lefthook.yml` `markdown-lint` as source of truth
- [x] 3.2 At end of `install_deps()` (unconditional — covers install AND node_modules-present skip paths), print the per-binary status: present marker, or `Warning:` to stderr naming `npm ci --ignore-scripts --prefix <wt>`
- [x] 3.3 New `plugins/soleur/test/worktree-manager-hook-deps.test.sh` (auto-discovered via `SUITE_GLOBS`): assert the missing-binary warning on a lockfile-less create and the present-marker line under a PATH-stubbed `npm` that fabricates the binary

## Phase 4: `scripts/test-all.sh` — vitest precondition (#2398 arm)

- [x] 4.1 In the `want_webplat` block (before the first `run_suite` at ~line 2732), fail fast when `apps/web-platform/node_modules/.bin/vitest` is not executable, naming `npm ci --ignore-scripts --prefix apps/web-platform`

## Phase 5: Doc/comment coherence

- [x] 5.1 `lefthook.yml:37-42` — update stale "worktrees get deps from worktree-manager.sh" comment
- [x] 5.2 `plugins/soleur/skills/git-worktree/SKILL.md` (~line 320) — note sibling-resolution for hook bins; `npm ci` still required for full/app deps
- [x] 5.3 `ADR-009` — consequence-note amendment: read-only sibling `node_modules` binary resolution gated on pin equality

## Phase 6: Verify

- [x] 6.1 `bash scripts/markdown-lint.test.sh` green
- [x] 6.2 `bash plugins/soleur/test/worktree-manager-hook-deps.test.sh` green
- [x] 6.3 Manual end-to-end: in a scratch `git worktree add` without node_modules, stage a `.md` and commit — hook passes via sibling notice
- [x] 6.4 `git grep -n 'npx' scripts/markdown-lint.sh` — confirm no package-runner path was introduced
