---
title: Token-Authenticated Git Automation Leaks Through Channels Normal Usage Never Exercises
date: 2026-09-19
category: security
tags: [git-trace, credential-leak, github-actions, bot-automation, gh-cli, fork-pr, x-access-token, code-review]
module: CI Automation
component: tooling
problem_type: security_issue
resolution_type: code_fix
root_cause: missing_validation
severity: high
symptoms:
  - "GIT_TRACE=1 echoes the full x-access-token URL into stderr on push — credential anonymization covers error messages only"
  - "gh pr list --head <branch> returns cross-repository (fork) PRs with a colliding headRefName; an unfiltered .[0] selects them"
  - "an unbounded sed anchor rewrote the well-formed prefix of a malformed ref, leaving residue that passed every post-count check"
---

# Troubleshooting: Token-Authenticated Git Automation Leaks Through Channels Normal Usage Never Exercises

## Problem

PR #8360 added `bump-inngest-bootstrap-pin.sh`, a workflow-invoked script that pushes a bot branch with `https://x-access-token:${GH_TOKEN}@github.com/<repo>.git` and then creates/merges PRs. The nine-seat review panel found three independent defects with one shared root: **every channel that only fires when automation does something a human never does was unguarded.** Normal `git push` failures anonymize the credential URL; `gh pr list` from a terminal returns your own repo's PRs; a sed anchor that matches today matches what the file contains today. The automation paths invalidate all three assumptions.

## Environment

- Module: `.github/scripts/bump-inngest-bootstrap-pin.sh` + `bump-cloud-init-pin` job in `build-inngest-bootstrap-image.yml`
- Review: nine-seat panel on commit `115671db8`, PR #8360 (issue #8359)
- Date: 2026-09-19

## Symptoms

1. `GIT_TRACE=1` (or any `GIT_TRACE*`/`GIT_CURL_VERBOSE`/`GIT_HTTP_TRACE_AUTH_HEADER` variant) prints the credential-bearing push URL verbatim to stderr. Verified empirically: git's anonymization applies to error strings, not its own trace channels. A debugging `env:` line in a workflow step would land the live installation token in the run log. The script's existing `set -x` refusal (#7797) covered shell xtrace only.
2. `gh pr list --repo R --head <branch> --state open` matches `headRefName` on **any** repository — the `owner:branch` disambiguation syntax is unsupported (cli/cli#10945). A fork PR named `soleur/inngest-pin-vX.Y.Z` would be selected by `.[0]`, and `gh pr merge --auto` would be armed on the wrong PR.
3. The rewrite anchor `soleur-inngest-bootstrap:vX.Y.Z(@sha256:…)?` was unbounded on both ends. A malformed line (`v1.2.3rc1`, a 65-hex digest, `pre-jikig-ai/…`) let sed rewrite the well-formed *prefix*, producing a corrupt ref that then passed the tag/digest count checks — a self-masking fixed point: the corruption erased the evidence of itself.

## What Didn't Work

- **Refusing `set -x` alone.** Necessary but insufficient — the leak surface is git's own `GIT_TRACE*` family, not shell tracing.
- **Counting matches post-rewrite.** Counts certify cardinality, not token integrity; a rewritten prefix + residue keeps the count at 2 while the ref is corrupt.
- **Trusting `gh pr list --head` ordering.** `.[0]` is whichever PR GitHub returned first — nothing scopes it to same-repo or bot authorship.

## Solution

1. Unconditionally `unset GIT_TRACE GIT_TRACE_PACKET GIT_TRACE_PERFORMANCE GIT_TRACE_SETUP GIT_TRACE_CURL GIT_TRACE_CURL_NO_DATA GIT_TRACE_REDACT GIT_TRACE2 GIT_TRACE2_PERF GIT_TRACE2_EVENT GIT_CURL_VERBOSE GIT_HTTP_TRACE_AUTH_HEADER` before any credential-bearing git operation — cheap insurance against a debugging `env:` line. Kept the `set -x` + live-`GH_TOKEN` refusal as the louder guard.
2. PR reuse filters `gh pr list --json url,number,author,isCrossRepository` down to `isCrossRepository == false && author.login == 'soleur-ai[bot]'`; the new-PR number is parsed from the `gh pr create` response URL rather than re-listed.
3. Bounded ERE with explicit left/right boundaries (`(^|[^[:alnum:]_.@-])` … `([^[:alnum:]_.:@=-]|$)`) plus **token-level** post-checks: extract the whole whitespace/quote-delimited ref token and require exact string equality with the new ref — residue fails loudly instead of substring-matching into a false pass.

## Prevention

- For any script that pushes with a token-bearing remote: grep the diff for `GIT_TRACE` scrubbing; the `set -x` refusal is not the whole surface.
- For any `gh pr list --head` consumed by automation: require `isCrossRepository` + author filters, and take new-PR identifiers from the create response, never a re-list.
- For any match-and-rewrite: bound the pattern on both ends AND verify complete tokens afterward. A count is not an equality check.
- The fixture suite (`test-bump-inngest-bootstrap-pin.sh`) now drives all three: `gittrace`, `forkpr`, `residuetag`/`residuedig` rows.

## Session Errors

1. **sed `|` delimiter collided with the bounded pattern's own `|` alternation groups** — the first remediation draft produced 65 fixture failures because `s|...(|…`)-containing-pattern...|` terminated the pattern early. Same defect class as the earlier gh-stub `\|` bug: in GNU sed ERE, `\|` inside a pattern is alternation, and `|` as s-expression delimiter cannot coexist with `|` in the pattern. **Prevention:** when the pattern contains alternation, default the delimiter to `#` or `@`; when the pattern needs a literal pipe, write `[|]`. Two instances in one session — treat this as the house default, not a case-by-case choice.
2. **`env MOCK_GH_MERGE_FAIL=1 run_bump`** — `env` executes programs, not bash functions; the fixture row silently didn't inject the mock. **Prevention:** export the mock var inside the fixture, or make `run_bump` read env at call time.
3. **`export LC_ALL=C` ran before the xtrace refusal** — a traced shell printed the export, tripping the trace-credential lint. **Prevention:** the refusal case-block must precede every statement that could run traced; keep it as the first executable block.
4. **Lefthook `test-all` under sibling-worktree contention** — inherited `GIT_AUTHOR_*`/`GIT_COMMITTER_*` re-authored fixture commits as the developer, tripping `fixture-env-adoption`. **Prevention:** every fixture suite creating git repos must source `git-fixture-env.sh` and call `git_fixture_env` — the adoption guard enforces this now.
5. **`npx vitest` from the worktree root reports "no tests"** — vitest config lives in `apps/web-platform`; run it from that cwd. **Prevention:** check the app's own test script before invoking a runner at repo root.
6. **LikeC4 rejects self-relations** (`github -> github` = "Invalid parent-child relationship"). **Prevention:** document same-system interactions on an existing edge's description, or in `views.c4` notes — never retry the self-edge.
7. **Minor edit slips** (dropped Guard-2 section header, stray fixture line) — caught by the suite immediately; **Prevention:** re-run the fixture suite after every structural edit, not just at phase end.

## Related

- #7797 — credential leakage through traced commands (the `set -x` refusal this extends)
- #8359 / PR #8360 — the automation this review round hardened
- cli/cli#10945 — `gh pr list --head` cross-repo matching
- ADR-232 — the shipped design record
