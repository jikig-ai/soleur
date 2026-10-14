---
module: Testing / CI infrastructure
date: 2026-10-10
problem_type: best_practice
component: testing_framework
symptoms:
  - "Thirteen env-gated integration suites ran nowhere while reporting green"
  - "A wired gate variable still left dsar-departed-member dormant — the collecting workflow filtered test/server/ only and the file sat at test/ root"
  - "A multi-gate file (mu1) set one of two gates in the collecting workflow and skipped"
root_cause: missing_validation
resolution_type: tooling_addition
severity: medium
tags: [dormant-tests, env-gates, ci-wiring, sentinel, skipIf, conjunction]
---

# Env-gated suite dormancy is a conjunction, not a wiring check

## Problem

`describe.skipIf(!process.env.X === "1")` suites pass vacuously forever when no
CI job sets the gate. A census of `apps/web-platform/{test,lib}` found **12
distinct gate vars across 59 files**, 13 of which ran nowhere (#9855). The
obvious guard — "every gate var must be set somewhere in `.github/workflows/`"
— is necessary but NOT sufficient, and its insufficiency is exactly the class
the bug lived in.

## Root cause

Coverage is a three-way conjunction evaluated **per file, per workflow**:

1. the file (or a depth≥2 ancestor dir, `test/server/`) is a bounded token in
   the workflow's run lines — a *collection* check;
2. every non-allowlisted gate var on the file is set in a *setting position*
   in that workflow — not just anywhere in the repo;
3. clauses 1 and 2 must hold in the **same** workflow.

`dsar-departed-member.integration.test.ts` gates on `TENANT_INTEGRATION_TEST`,
which *was* wired — but the only workflow setting it collects `test/server/`,
and the file sits at `test/` root. Wired var, dormant file: a var-level check
reports green while the suite never runs.

Setting-position grammar also matters more than a bare grep: a `# env X=1`
comment line, `echo "env X=1 ..."`, or `echo "X: 1"` in a `run:` body all
contain the token and certify wiring without setting anything. The grammar
that survived review: `env` in command position (line-start / `run:` /
`&&`/`||`/`;`/`-- ` boundary) OR a line-start-anchored `X: "1"` mapping — ERE
cannot see quote scope, so string-literal shapes inside quotes are the
documented residual.

## Solution

`scripts/lint-integration-env-gates.sh` — two-arm sentinel:

- **var-level**: every non-allowlisted gate var must appear in a setting
  position in at least one workflow (distinct-var dedupe → `wired_map`
  var<TAB>workflow persisted once; ~26× faster than per-file×var rescanning).
- **file-level**: candidates = INTERSECTION over the file's vars of the
  workflows setting each (`comm -12` on sorted map rows); covered iff some
  candidate collects the file. Empty intersection ⇒ dormant.
- Producers scan source extensions only (`.ts|.tsx` — prose quoting the idiom
  is not a gate); non-`.test.` source files are var-level-only (helpers are
  never path-filter targets; their importers carry coverage).
- Anti-vacuity: census floor + a 30-row mutation battery pinning each grammar
  arm (comment-strip, echo/string non-settings, depth-1 dir rejection, `!==`
  polarity, `.yaml` glob, conjunction, sub-floor census).

## Prevention

- When adding a `process.env.X === "1"` gate, the sentinel runs red until you
  wire it in a workflow that *also collects the file* — or add an allowlist
  entry with a cited reason.
- When adding a *collection* filter (a new `-- test/...` arg or a new
  workflow), grep for newly-collectable gated files; the sentinel enforces it
  automatically in `test-all.sh` and the ci.yml advisory leg.
- When reviewing a guard whose producer grammar accepts a token form, ask
  "can a comment/echo/doc contain this token?" — the strip + command-position
  + line-start-anchor triple is what turned token-matching into
  setting-position-matching.

## Session Errors

- `grep -vE … | grep -qE` pipelines under `pipefail` produced a heisenbug:
  `grep -q` exits on first match, upstream strip dies of SIGPIPE (rc 141),
  pipeline reads as no-match → false UNWIRED. **Prevention:** materialize
  filtered bodies to files once; grep file operands, never `x | grep -q`.
- `_var_wired_in "$v" | head -1` repeated the same class at the call site —
  `head` closes early, producer dies writing the second match.
  **Prevention:** `$(…)` capture, never `| head`.
- `grep | while` under `set -e` died silently on a zero-match census before
  printing the summary. **Prevention:** `grep … || true` in command
  substitution, or read the file directly.
- Wrote the checkout SHA from memory instead of the repo-canonical pin —
  caught by self-review against sibling workflows. **Prevention:** copy pins
  from the repo, never memory.
- `dsar-departed-member` was invisible to the first file-level pass because
  it checked only the immediate parent dir — `test/server/scope-grants/…`
  false-positives taught the ancestor-walk. **Prevention:** directory-filter
  semantics must walk ancestors deepest-first with an explicit depth bound.
- The producer enumerated `test/README.md` (doc prose quoting the idiom) as
  a gate → `UNWIRED-VAR: X`. **Prevention:** producer filters to source
  extensions; battery row M15 pins it.
- Mutation fixtures lacked `mkdir -p` (writes failed silently); an early
  conjunction row did not exercise the intended path until the fixture was
  completed. **Prevention:** mutation rows must be verified to red for the
  intended arm — a row that reds via the wrong mechanism pins nothing
  (M8/M14 both had this in review).
- `DECLARED_ROWS` miscount after adding rows; wrong token asserted in M25.
  **Prevention:** run the battery immediately after row edits — the exact-
  count self-check exists for this.

## Verification

- `bash scripts/lint-integration-env-gates.sh` — `env-gates: found=59
  wired=8 allowlisted=4 uncovered=0`.
- `bash scripts/lint-integration-env-gates.test.sh` — `30 passed, 0 failed`.
- Review: two fix-rounds across 8 panel + 6 targeted seats, all APPROVE /
  APPROVE-WITH-CHANGES, every finding fixed inline.
