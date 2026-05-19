---
date: 2026-05-18
category: integration-issues
topic: git pathspec silent zero-match in CI matrix-detection pipelines
related_issues: [4012]
related_prs: [4021]
related_learnings:
  - 2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md
  - 2026-03-21-lefthook-gobwas-glob-double-star.md
---

# Learning: git pathspec silent zero-match in CI matrix-detection pipelines

## Problem

`.github/workflows/infra-validation.yml` `detect-changes` job used
`git diff --name-only "origin/${BASE_REF}...HEAD" -- 'apps/*/infra/' 'infra/'`
to enumerate changed infra roots. Three PRs (#3985, #4002, #4003) merged
with `validate: SKIPPED` even though their diffs touched
`apps/web-platform/infra/...`. Workflow status reported `success` in
every case — there was no failure signal.

Reproduction on commit `7e6f6726`:

```bash
$ git diff --name-only 7e6f6726^..7e6f6726 -- 'apps/*/infra/' 'infra/'
(empty)

$ git diff --name-only 7e6f6726^..7e6f6726
apps/web-platform/infra/sentry/uptime-monitors.tf
apps/web-platform/infra/uptime-alerts.tf
...
```

## Root Cause

Default git pathspec semantics: `*` does NOT cross `/`. The form
`'apps/*/infra/'` (single `*`, trailing slash, no `**`) requires the
matched path to be EXACTLY `apps/<one-component>/infra/<file-at-depth-0>`,
and even then the trailing-slash-as-directory-marker interpretation is
inconsistent across git versions. In practice the form returns empty for
everything beneath `apps/*/infra/`.

Two safe forms (both verified on `git 2.53.0`):

```bash
# Option A: opt into glob magic with `:(glob)` prefix
git diff --name-only "origin/${BASE_REF}...HEAD" \
  -- ':(glob)apps/*/infra/**' ':(glob)infra/*/**'

# Option B: drop pathspec, filter via shell-level regex
git diff --name-only "origin/${BASE_REF}...HEAD" \
  | grep -E '^(apps/[^/]+/infra|infra/[^/]+)/'
```

## The Hiding Mechanism

GitHub Actions reports overall workflow status as `success` when
ALL upstream jobs succeed AND downstream jobs are merely skipped via
`if:` conditions. A matrix that fans out to `[]` (because the
upstream `detect-changes` job emitted `directories=[]`) skips every
shard cleanly — no `failure` signal anywhere. The defect is invisible
in the PR check list except as the **absence** of a `validate (...)` row,
which no reviewer trains themselves to look for.

## Solution

PR #4021 replaces the pathspec form with Option B (shell-level regex
filter), guarded by `{ grep -E ... || true; }` so a zero-match grep
doesn't fail the step on docs-only PRs. Adds
`plugins/soleur/test/infra-validation-detect.test.sh` — 8 unit-test
scenarios + real-commit-baseline assertion — wired into
`scripts/test-all.sh` via the existing `plugins/soleur/test/*.test.sh`
auto-walk.

## Key Insight

**Any pathspec-driven matrix-detection pipeline MUST be regression-
gated by a fixture test that pipes synthetic `git diff` output through
the same pipeline and asserts non-empty matrix output for the canonical
shape.** Pathspec semantics drift across git versions and across
authors' mental models of what `*` and `**` do; the only reliable gate
is a hermetic unit test that exercises the pipeline directly.

## Prevention

1. **Never use bare `*` in a git pathspec that needs to span `/`.** Use
   `:(glob)<pattern>/**` (explicit) or drop pathspec entirely and filter
   downstream with `grep -E`.
2. **Audit existing CI matrix-detection jobs** for the same defect
   class: `git grep -nE "git diff.*-- '" .github/` returns every site
   that uses pathspec. Every hit needs a fixture test in
   `plugins/soleur/test/`.
3. **For any GitHub Actions job whose `success` outcome depends on a
   downstream matrix actually running**, add a `required: true` rule on
   the matrix (forces at least one shard to run, or the workflow fails
   visibly). Out of scope for #4012 — would need a CODEOWNERS / branch-
   protection update — but worth filing if this class recurs.

## Sibling Failure Mode

`2026-03-21-lefthook-gobwas-glob-double-star.md` documents the
equivalent failure mode in lefthook's gobwas glob: `**` is unsupported
(treated as "1+ directories" not "0+"). Same class — glob semantics
differ across tools, defect is silent zero-match. This PR adds the
git-pathspec data point to the class.

## Session Errors

1. **`security_reminder_hook.py` advisory fired on workflow Edit.** The
   PreToolUse hook returned an error-toned reminder about
   `${{ github.event.* }}` interpolation safety even though the edit
   introduced no new interpolation surface (only added a `grep -E`
   filter to an existing pipeline). Retrying the same Edit succeeded.
   - **Recovery:** retry the Edit; the hook is advisory not blocking.
   - **Prevention:** the hook could distinguish advisory output from
     blocking output via separate prefix or exit code, so agents don't
     interpret the warning as a hard reject. Out of scope for this PR.
