---
title: "gh GraphQL 500k-node cost cap + bot-branch attribution heuristics"
date: 2026-05-11
category: best-practices
tags: [gh-cli, github-api, graphql, bash, attribution-heuristic]
related_pr: 3572
related_issues: [3545, 3544, 3561]
component: scripts
---

# gh GraphQL 500k-node cost cap + bot-branch attribution heuristics

## Problem

Two distinct gotchas surfaced while building the CodeQL bot-PR coverage audit (#3545).

### Gotcha 1: `gh pr list --limit N --json commits` blows the GraphQL cost cap

```bash
$ gh pr list --state all --limit 100 --author "app/github-actions" --json number,headRefName,commits
GraphQL: This query requests up to 1,005,050 possible nodes which exceeds the maximum limit of 500,000.
```

GitHub's GraphQL endpoint applies a cost limit of 500,000 estimated nodes per request. Each PR's `commits[]` is ~10,000 nodes due to the bounded-traversal pre-estimate. Fetching `commits` for N PRs costs ~N × 10k. 50 PRs already exceeds the cap. The error is loud (HTTP error) but the script's `2>/dev/null || echo '[]'` fallback silently swallows it, producing `total=0 / exit 0` — a false-pass that masks the audit.

### Gotcha 2: Stem-prefix branch attribution silently misses

Bot branches follow `ci/<short-name>-<date>` convention where `<short-name>` is a slug, NOT the workflow filename stem. Examples:

- `rule-metrics-aggregate.yml` → `ci/rule-metrics-*` (stem ≠ slug)
- `scheduled-rule-prune.yml` → `ci/rule-prune-retire-*` (slug isn't even a prefix of stem)
- `scheduled-content-publisher.yml` → `ci/content-publisher-*` (works after stripping `scheduled-`)

A naive `${stem#scheduled-}` + substring-match attribution loop sends 3 of 8 live PRs to `<unattributed-bot-pr>` because `rule-metrics-aggregate` doesn't appear as a substring in `ci/rule-metrics-2026-05-10`.

## Root cause

### Gotcha 1
GitHub limits GraphQL request cost; the `gh` CLI translates `--json` field requests into GraphQL fragments whose cost is estimated server-side, not by `gh`. Adding a `commits` field per PR multiplies cost by ~10k nodes (the page-size pre-estimate for the connection). The error is a runtime HTTP error, not a client-side guardrail.

### Gotcha 2
Slug-derivation patterns are not contractual — they're encoded ad-hoc in each bot workflow's branch-naming convention. There is no API that returns "branches authored by workflow X." Static stem-vs-slug mapping drifts; pure substring match fails when the stem is a superset of the slug.

## Fix

### Gotcha 1: two-phase fetch

```bash
# Phase 1: cheap fetch (number + headRefName only)
bot_prs=$(gh pr list --state all --limit 100 --author "app/github-actions" \
  --json number,headRefName 2>/dev/null || echo '[]')

# Hard-fail when phase 1 returns empty — masks API outage as false-pass
if [[ "$(printf '%s' "$bot_prs" | jq 'length' 2>/dev/null || echo 0)" == "0" ]]; then
  echo "::error::gh pr list returned no bot PRs — API outage, auth failure, or workflow drift. Aborting." >&2
  exit 1
fi

# Phase 2: resolve head SHAs one PR at a time (cheap; each gh pr view is bounded)
while IFS=$'\t' read -r branch pr; do
  sha=$(gh pr view "$pr" --json commits --jq '.commits[-1].oid' 2>/dev/null || echo "")
  ...
done
```

### Gotcha 2: progressively shorter dash-prefix matching

```bash
for wf in $WORKFLOWS; do
  stem=$(basename "$wf" .yml)
  short="${stem#scheduled-}"
  for slug in "$short" "${short%-*}" "${short%-*-*}"; do
    if [[ -n "$slug" && "$branch" == *"$slug"* ]]; then
      attributed="$wf"
      break 2
    fi
  done
done
```

The `${var%-*}` parameter expansion strips the rightmost dash-suffix. Trying full stem → 1-suffix-stripped → 2-suffixes-stripped covers `rule-metrics-aggregate` → `rule-metrics` → `rule`. Combined with surfacing `unattributed_count` in the envelope summary and a >30% warn threshold, the heuristic degrades visibly when it does miss.

## Prevention

- **Pre-estimate GraphQL cost before fetching arrays.** Rule of thumb for `gh pr list --json`:
  - `number`, `headRefName`, `title`, `state`: ~50 nodes/PR
  - `commits`, `comments`, `reviews`, `files`: ~10,000 nodes/PR
  - Multiply by `--limit`. Stay under 500,000.
- **Always validate empty-array responses.** `2>/dev/null || echo '[]'` is a footgun — pair with `jq length == 0` hard-fail when zero means "API outage."
- **Test branch-attribution heuristics with a realistic fixture before shipping.** A 5-PR fixture exercising the slug-vs-stem mismatch would have caught the bug at TDD time, not at the live-audit smoke test.
- **Surface unattributed counts in audit envelopes.** Silent attribution misses become loud when a `summary.unattributed > 0` line appears in the JSON output.

## Session Errors (encountered during PR #3572)

- **gh GraphQL cost cap blew up first attempt to fetch bot PRs.** Recovery: split fetch into number+headRefName then per-PR `gh pr view`. Prevention: pre-estimate cost; `commits[]` is ~10k/PR.
- **Inline-pattern enumeration regex missed scheduled-content-publisher.yml (multi-line `gh api ... -f name=test`).** Recovery: switched from single-line regex to two-`grep -q` AND pattern. Prevention: AND two greps per file when matching multi-line idioms.
- **Branch attribution heuristic missed 3/8 live PRs (silent `<unattributed-bot-pr>`).** Recovery: dash-prefix peel-off (`${short%-*}`). Prevention: TDD with realistic branch-name fixtures before shipping attribution logic.
- **Test harness `set -euo pipefail` aborted silently when `grep -c` per-file count returned 0 (non-zero exit).** Recovery: wrap `grep -c ... 2>/dev/null` in `( ... || true)` subshell. Prevention: any `grep -c <file>` in a `set -e` harness needs `|| true` because zero-match is non-zero exit per file.
- **plan/deepen-plan subagent: Task tool unavailable for parallel lens spawning.** Recovery: synthesized inline. Prevention: none — agent surface availability is harness-side.

## References

- PR #3572 — CodeQL bot-PR coverage audit
- Issue #3545 — origin (R15 follow-up D2)
- Issue #3544 — sibling audit (bypass_actors)
- Issue #3561 — drift-guard `tr '\x7f'` latent bug filed during #3555
- `scripts/audit-bot-codeql-coverage.sh` — implementation
- `scripts/lib/strip-log-injection.sh` — shared sanitation lib extracted from review
- GitHub Docs: [GraphQL API resource limits](https://docs.github.com/en/graphql/overview/resource-limitations)
