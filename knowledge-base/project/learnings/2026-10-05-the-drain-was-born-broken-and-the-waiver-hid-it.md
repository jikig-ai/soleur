# Learning: the drain was born broken — and three instruments each told a partial truth

## Problem

The Sentry cron monitor for `scheduled-machinery-drain` reported "no successful
check-in since 2026-09-21". The obvious framing — "the claude-code-action bump
(v1.0.161 → v1.0.236 in 6d27cd17da, 2026-09-29) removed implicit OIDC compat" —
was FALSE: run logs showed the identical `getOidcToken` hard-fail at v1.0.161
(runs 34591772975, 34825797967), including on the concluded-**success** run of
2026-09-14. The workflow was born 2026-09-11 without `id-token: write` and never
drained anything (`closed=0` on every run). `WAIVED-SUPPLY` masked the death
while the machinery pool sat below floor=20; the defect surfaced the first week
the pool crossed it — a masking instrument, not a regression.

A second instrument lied in the same direction: `gh issue list --limit 100`
returned the newest-100 window, which a ~1700-open-issue repo had already
outgrown, so the standing measurement issue was invisible and the workflow
re-filed its own issue weekly (four live duplicates: #8068/#8482/#9132/#9508).

## Solution

- Trusted `workflow_dispatch` consumer: job-level `id-token: write`
  (least-privilege convention; `permissions: {}` top-level deny-all so a future
  second job inherits nothing).
- Untrusted `pull_request` consumer (fix-constraints-stage-a, ADR-074):
  `github_token: ${{ github.token }}` step input — the action's
  `setupGitHubToken` early-returns on `OVERRIDE_GITHUB_TOKEN` before
  `getOidcToken()` (verified at pin 20f0b248). `id-token: write` deliberately
  withheld: a minted OIDC token exchanges for write-capable app credentials,
  which would hand PR-head code exactly the capability the split withholds.
  The generator template (`constraint-scaffold/references/…stage-a.template`)
  got the same fix — the latent defect lived there first and a scaffold re-emit
  would reinstall it.
- Standing-issue census switched to `gh issue list --label keep-open`
  (index-free, label-scoped, single-sources the title literal) with
  bot-author + `meta/machinery` conjuncts gating the auto-close arm.
- Census guard `plugins/soleur/test/claude-code-action-auth.test.sh` (25 rows)
  covering per-step token paths, anchor evasion, composite actions, and
  duplicate-key semantics.

## Key Insight

**Audit the axes a guard's own battery missed.** The first-cut census shipped
with six verified silent-green holes (per-job instead of per-step arm-A,
`github_token:` counted inside `prompt: |` scalars, quoted/spaced/case `uses:`
spellings, duplicate `permissions:` keys reading first-wins where YAML is
last-wins, an empty-valued `github_token:` key satisfying the presence check).
A mutation matrix measures the mutations its author imagined; the
structural-enumeration seat — "enumerate every path to the sink, then ask if the
assembly equals the property" — is what found the rest. Treat a green battery as
evidence about the mutations, not the guard.

**Two more measured traps:**

- `gh issue list --json author` returns `app/github-actions`; `gh api
  search/issues` returns `github-actions[bot]` — the same identity, two spellings
  per API surface. A predicate verified against one surface silently matches
  nothing on the other. Verify filter predicates against live data, never the
  remembered shape.
- claude-code-action validates that the dispatched workflow file is IDENTICAL
  to its default-branch content before minting the app token — a branch
  dispatch of a modified consumer skips the agent cleanly ("workflow validation
  failed … your workflow will begin working once you merge your PR"), so
  pre-merge live verification proves the OIDC mint only, never the agent run.

## Session Errors

1. Guard census shipped with six silent-green holes caught only by panel
   enumeration.
   **Prevention:** for any new guard, budget the structural-enumeration seat at
   author time — enumerate the sink's reachability map before writing mutation
   rows.
2. Assumed `github-actions[bot]` author shape from the search API; `gh issue
   list` reports `app/github-actions` — the corrected predicate (`is_bot` +
   `login ~ github-actions`) was verified live only after the first rewrite
   returned `[]`.
   **Prevention:** any `gh`/`jq` filter that gates a write (close, comment,
   update) gets one live `--jq` dry-run against the real dataset before commit.
3. Commit/plan prose inherited the "bump broke it" narrative; pre-bump run logs
   refuted it in one `gh run view`.
   **Prevention:** every causal claim in a fix narrative names the command that
   would falsify it; run it before the claim is written.
4. Apostrophe inside a single-quoted awk program broke the suite (SC1011).
   **Prevention:** no `'` in comments inside single-quoted awk programs —
   reword.
5. `git stash` attempt blocked by the worktree guard; orphan-suite false alarm
   while the new test was untracked.
   **Prevention:** covered by existing rules; commit WIP before switching
   context and before suite-registration lints.

## Tags

category: ci
module: github-actions / claude-code-action / sentry-crons
