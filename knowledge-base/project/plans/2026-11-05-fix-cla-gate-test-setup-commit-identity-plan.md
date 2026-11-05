---
title: "fix: cla-signed-author-gate.test.sh setup commits need an explicit git identity"
type: fix
date: 2026-11-05
slug: fix-cla-gate-test-setup-commit-identity
branch: feat-one-shot-12120-cla-gate-test-identity
issue: 12120
closes: 12120
lane: cross-domain
---

# fix: cla-signed-author-gate.test.sh setup commits need an explicit git identity

Spec lacks valid lane: - defaulted to cross-domain (fail-closed). No spec.md exists for this one-shot branch.

## Overview

`.claude/hooks/cla-signed-author-gate.test.sh` fails on CI runners that have no global git
identity. Case T15 runs `git config --unset user.email` and then calls `push_cla_yml`, whose
`git commit -q -m "add cla.yml"` carries no `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env. With the repo
identity unset and no `~/.gitconfig`, git dies with `fatal: unable to auto-detect email address`.
`push_cla_signatures` has the identical latent defect (same bare `git commit`), though no unset
case calls it today. On a developer machine the global identity hides the failure.

Reproduced locally in this worktree before planning (empty `HOME`/`XDG_CONFIG_HOME`,
`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`): the suite exits 128 right after
`PASS: T14` with the issue's exact `fatal:` line.

**T15's intent is load-bearing.** The case proves the hook behaves correctly when the repo
identity is UNSET (the sanctioned `-c user.email` override path for unset-config sessions). The
fix must therefore leave the hook-call path untouched (identity stays unset when `run_hook_noglobal`
runs) and give only the SETUP commits an explicit identity via per-command env. Restoring then
re-unsetting `user.email` around the commit is rejected: it mutates the very state under test and
adds ordering coupling for no benefit.

The case at line 333 (T16) was named in the issue but does not need a change: it calls only
`commit_branch`, which already pins author AND committer via env for the `"a,b"` specs it uses
(verified: T16 passes under the no-identity repro once T15 is fixed).

## Research Insights

**Premise Validation.** Issue #12120 is OPEN with no closing PR; PR #12198 is the draft for this
branch (collision pre-check: only that PR names #12120; three foreign `test-all.sh` processes in
other worktrees are unrelated). The failure reproduces on `origin/main`-equivalent content
(branch is one init commit ahead). Cited line numbers (323, 333) match the file. Both helpers and
`commit_branch` exist as described.

**Property List.**
1. The suite passes on a machine with no global/system git identity (the CI runner shape).
2. T15/T16 still exercise the hook with `user.email` unset in the repo (intent preserved).
3. No fixture-visible behaviour changes: setup commits keep their prior effective identity
   (`Test User <test@test.local>`) and sit on `main`/`cla-signatures`, outside the `main..branch`
   range the hook inspects.

**Cut List.**
- Restore-`user.email`-around-commit alternative -> property 2 -> rejected, it mutates the state
  under test; per-command env covers property 1 without touching config.
- Exporting `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` suite-wide (would make dev
  machines reproduce CI) -> not asked, issue scopes "about 4 lines"; `run_hook_noglobal` already
  masks config for the hook call. Left as a non-goal; verification uses the env at run time.
- Changing `commit_branch` -> property 3 -> already pins identity; its "omitted committer leaves
  git's configured identity" behaviour is deliberate (comment at the helper) and used by tests.

**Learnings / conventions.** Test fixtures are synthesized-only (`cq-test-fixtures-synthesized-only`):
the identity is the suite's existing `test@test.local` / `Test User` pair already used by
`init_git_repo`. `scripts/ci-pr-affected-audit.accept.tsv` has two content-hash-anchored accept
rows for this suite (sha256 of the whitespace-collapsed source line) tied to lines naming the
cla.yml workflow path; the new lines must not contain that path literal (a new boundary match would
create an unaccepted gap), and the anchor is content-keyed so edits that leave those two lines
byte-identical are safe.

## Implementation (single phase, one file)

File to edit: `.claude/hooks/cla-signed-author-gate.test.sh` (only file touched).

1. Add a small helper directly after `commit_branch` (so lines 106-147, which the accept-table
   reason text cites, do not shift):

   ```bash
   # setup_commit <work> <msg> — fixture-setup commit with an explicit identity via env, so the
   # helpers work when a case has unset user.email and the runner has no global identity (#12120).
   # Env, not `git config`: T15/T16 test the hook with the repo identity UNSET.
   setup_commit() {
     env GIT_AUTHOR_NAME="Test User" GIT_AUTHOR_EMAIL=test@test.local \
         GIT_COMMITTER_NAME="Test User" GIT_COMMITTER_EMAIL=test@test.local \
       git -C "$1" commit -q -m "$2"
   }
   ```

2. In `push_cla_yml`, replace `git -C "$work" commit -q -m "add cla.yml"` with
   `setup_commit "$work" "add cla.yml"`.
3. In `push_cla_signatures`, replace `git -C "$work" commit -q -m "signatures"` with
   `setup_commit "$work" "signatures"`.

Do not touch `init_git_repo`, `make_repo`, `commit_branch`, `run_hook_noglobal`, or any case body.
No LUKS/Inngest/infra files are in scope.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Give those helpers an explicit identity via env GIT_AUTHOR_*/GIT_COMMITTER_* like commit_branch already does" [brief] | Implementation steps 1-3 | mapped |
| 2 | "verify by running the suite with HOME pointed at an empty dir and GIT_CONFIG_GLOBAL=/dev/null so no global identity exists" [brief] | AC 1 | mapped |
| 3 | "the fix must keep the hook-call path unset and only give the setup commits an explicit identity" [brief] | Overview + AC 2 | mapped |
| 4 | "Own PR (draft PR #12198 exists), body uses \"Closes #12120\"" [brief] | AC 5 | mapped |
| 5 | "Do not touch any LUKS/Inngest/infra files" [brief] | AC 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `setup_commit` helper | "Give those helpers an explicit identity via env GIT_AUTHOR_*/GIT_COMMITTER_*" | asked |
| `push_cla_yml` edit | "push_cla_yml (and push_cla_signatures)" | asked |
| `push_cla_signatures` edit | "push_cla_yml (and push_cla_signatures)" | asked |

### Split Assessment

- Subsystems touched: 1 - `.claude/hooks/`
- Planned files: 1 | Estimated changed lines: ~10 (one 5-line helper plus 2 one-line swaps)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user surface; a required CI leg (`test-scripts 4/8`) stays intermittently red on unrelated PRs, blocking merges.
- **If this leaks, the user's data is exposed via:** nothing; test-only change using the existing synthetic `test@test.local` identity, no secrets or real addresses.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** test-fixture-only edit in a hook test file with no user-facing or data path; not a sensitive path for preflight Check 6.

## Open Code-Review Overlap

None (no open `code-review` issue names `.claude/hooks/cla-signed-author-gate.test.sh`; checked with the two-stage `gh issue list --json` + `jq --arg` form before drafting).

## Acceptance Criteria

- [ ] AC1: With `HOME=$(mktemp -d) XDG_CONFIG_HOME=$HOME GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash .claude/hooks/cla-signed-author-gate.test.sh`, the suite exits 0 and reports `26/26 passed` (pre-fix: exit 128 after `PASS: T14`).
- [ ] AC2: Normal-environment run is still `26/26 passed`; `T15` and `T16` both print `PASS`. `git diff` shows no change to `run_hook_noglobal`, `init_git_repo`, `make_repo`, `commit_branch` or any `tN()` body (hook-call path stays identity-unset).
- [ ] AC3: `python3 scripts/ci-pr-affected-replay.py audit` summary `gap_refs=` and `stale=` are unchanged versus `origin/main` (no new line in the test file names the cla workflow path literal; the two content-anchored accept rows still match).
- [ ] AC4: `git diff --name-only origin/main...HEAD` outside `knowledge-base/project/{plans,specs}/` lists only `.claude/hooks/cla-signed-author-gate.test.sh`.
- [ ] AC5: PR #12198 body contains `Closes #12120`; PR title no longer `WIP:` at ship time.

## Test Scenarios

- Red-first (`cq-write-failing-tests-before`): the existing T15 is the failing test; AC1's command reproduces the failure before the edit and must be run once pre-edit to confirm RED.
- Mutation check: temporarily revert step 2 only -> AC1 command must go RED at T15; revert step 3 only -> stays green (no unset case calls it) which documents step 3 as defensive, per the issue's explicit "(and push_cla_signatures)".

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - test-only change to a hook fixture helper.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
- Sharp-edges catalogue (`plan-sharp-edges.md`, ~250 KB) was searched for the relevant traps (git identity, `GIT_CONFIG_GLOBAL`, hermetic fixtures) rather than read in full for this one-file change; no entry matched.
- The helper must be placed after line 147 and avoid the cla workflow path literal in new comments (see Research Insights).
