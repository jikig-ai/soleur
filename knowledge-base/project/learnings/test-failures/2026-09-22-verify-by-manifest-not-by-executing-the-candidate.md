---
module: scripts/markdown-lint.sh + scripts/markdown-lint.test.sh
date: 2026-09-22
problem_type: design_defect
component: hook_guards
symptoms:
  - "sibling-binary candidates were version-checked by EXECUTING --version — an unverified binary ran before the checks meant to gate it"
  - "the local arm probed only the hoisted engine manifest while the sibling arm probed nearest-scope-first — the two arms verified different copies of the same package"
  - "the lockfile engine pin took the FIRST matching entry — multiple installed versions produced order-dependent verification"
root_cause: verification_order_and_asymmetry
resolution_type: code_fix
severity: high
status: closed
tags: [worktrees, node-modules, pin-verification, trust-boundary, test-isolation, git, review-findings]
synced_to: [review]
issue: 8580
pr: 8581
---

# Verify a candidate by reading its manifest — a binary you run to check has already run

## Problem

#8580 added a sibling-worktree fallback to `scripts/markdown-lint.sh`: when a
fresh worktree has no `node_modules`, the hook resolves a version-compliant
`markdownlint` binary from the primary checkout or another linked worktree,
preserving #7927's no-`npx`/no-PATH/no-network contract.

The first implementation verified each sibling candidate by running
`"$cand" --version`. Two reviewers (security-sentinel, structural seat)
converged on the same defect: **the check executed the thing it was checking.**
A candidate had already run — with repo-write hook privileges — before its
version was known. A second, subtler defect rode alongside: the LOCAL arm
verified only the hoisted `node_modules/markdownlint/package.json` while the
SIBLING arm probed nearest-scope-first (`markdownlint-cli/node_modules/` then
hoisted). Node loads nested-first, so the local arm could certify a hoisted
copy the runtime never used. Third: the lockfile pin extraction printed the
first matching `markdownlint` package entry — two installed engine versions
made the pin order-dependent.

## Solution

Verification is now **file reads only, before any exec**, identical in shape
on both arms:

- `_pkg_version` reads a `package.json`'s `version` (never runs anything).
- `cli_manifest_version_for` reads the candidate's own
  `markdownlint-cli/package.json` — the sibling's *installed* version, not the
  sibling's *declared* pin and never the candidate's self-report.
- `engine_version_for` probes nearest-scope-first and is shared by the local
  AND sibling arms — one probe order, matching node's.
- The `.bin` entry must `realpath` inside that candidate's own
  `node_modules` (a symlink escaping it is a different trust surface than the
  manifests just read).
- The lockfile pin collects ALL matching versions and dies on >1 distinct —
  an ambiguous pin is refused, not sampled.
- Skip reasons are enumerated per-candidate (`SKIPWHY`), and every failure
  names `npm ci --ignore-scripts --prefix <abs-path>` — a cwd-relative remedy
  is not a remedy (the run may be anywhere).

Regression locks added: T7 plants a marker-dropping stub behind a
wrong-version manifest and asserts the marker file was never created; T8
plants a compliant-manifest sibling whose `.bin` symlink escapes
`node_modules` and asserts refusal. T5's PATH decoy now answers `--version`
with the PIN (a probe-then-reject mutant that consults PATH is caught by the
FAKE-INVOKED assert instead of dying green).

## Key Insight

**"Verify by executing" is a contradiction: the verification IS the
execution.** Any candidate gate that runs the candidate to decide whether it
may run has already granted the thing it exists to deny. The evidence must
come from the filesystem (manifests the candidate ships), and the probe order
must be IDENTICAL on every arm that feeds the same verdict — a stricter
sibling check than local check is not defense-in-depth, it is two different
predicates certifying different files.

Also measured here: pin extraction from a lockfile must be a SET, not a
first-match — "the pin" is only meaningful when exactly one version exists.

## Prevention

- For any candidate-selection guard: list what may run BEFORE verification
  and require that list to be empty; express it in tests as a side-effect
  probe (marker file) the rejected path must never touch.
- When two code paths verify the same property (local vs sibling), extract
  ONE predicate and call it from both — divergence is invisible until a
  reviewer diffs the arms.
- Aggregate pins (`first match wins`) must fail closed on ambiguity: collect
  distinct values, die on `> 1`.

## Session Errors

1. `git pull` at session start ran against a detached HEAD and reported
   `main` as un-mergeable; `main` was pinned by a linked worktree — a safe
   refusal, left untouched. **Prevention:** when a pull targets a ref checked
   out elsewhere, check `git worktree list` before concluding divergence.
2. First `git push` was rejected — the remote held a different empty
   `chore: initialize` commit from draft-PR creation. Resolved by merge, not
   force-push. **Prevention:** fetch + inspect the remote tip's diff before
   choosing integrate-vs-rebase; an empty init commit merges clean.
3. Commit hook `plugin-component-test` failed on a pre-existing
   collision-gate red (`.github/workflows/scheduled-actions-queue-health.yml`,
   #8578 → tracked #8586). **Prevention:** on a hook red, diff the failure's
   file against `origin/main` first — pre-existing reds are excluded by hook
   name, not by disabling the gate.
4. First review-fix commit failed YAML parse: the `lefthook.yml` `run:`
   plain scalar contained `web-platform-typecheck:` and `run:` — a colon +
   space inside a plain scalar is a mapping error. **Prevention:** in YAML
   plain scalars (hook `run:` lines), never write `<token>: ` inside the
   command string — use `--`/`,` separators or quote the scalar.
5. `fixture-relative-assert` flagged the new `plant_engine` write site;
   guarding `$1` did not clear it — the scanner correlates
   `assert_fixture_dir` with the write's OPERAND variable (`$t`), not the
   function parameter. **Prevention:** place `assert_fixture_dir` on the
   exact operand the redirection names, immediately above the write.
6. `gh pr` file listing transiently showed unrelated files mid-recompute
   after a merge push; the compare API gave the true three-dot diff.
   **Prevention:** after a push that changes the merge base, verify PR
   file lists via `gh api repos/.../compare/base...head`, not the PR view.
7. `session-state.md` still claimed "work not invoked" after implementation
   landed — review caught the stale doc. **Prevention:** update
   session-state.md in the same commit that changes the phase it describes.

## Cross-References

- `test-failures/2026-09-14-git-hook-env-prefix-scrub-and-anchored-recovery-grep.md`
  — the GIT_* scrub precedent this PR reuses (markdown-lint.sh now scrubs the
  same set before its `git rev-parse`/`worktree list` calls).
- `test-failures/2026-09-19-every-guard-i-shipped-pinned-spelling-not-the-executed-program.md`
  — sibling class: a guard that certifies the wrong property; here, a check
  whose execution was itself the hazard.
- `ADR-009` amendment (2026-09-22) — the read-only sibling `node_modules`
  boundary this mechanism operates under.
- #7927 — the no-unpinned-fallback contract preserved; #8586 — the
  pre-existing baseline red excluded at commit.
