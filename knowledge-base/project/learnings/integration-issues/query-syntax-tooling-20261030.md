---
module: Developer Tooling
date: 2026-10-30
problem_type: integration_issue
component: tooling
symptoms:
  - "`gh issue view` rejected the unsupported `authorAssociation` JSON field."
  - "A `gh --jq` filter with escaped parentheses failed before returning comments."
  - "ClickHouse rejected double-quoted SQL string literals with `UNKNOWN_IDENTIFIER`."
  - "A Better Stack query returned no listener-start event; source inspection showed INFO logs are filtered."
  - "A repository script path and a tracked-file glob initially resolved incorrectly."
root_cause: wrong_api
resolution_type: documentation_update
severity: low
tags: [github-cli, jq, clickhouse, betterstack, shell-quoting, worktree, query-syntax]
---

# Troubleshooting: Query and repository tools have distinct input boundaries

## Problem

During an investigation of open epic #11181, several read-only lookups failed before returning evidence: a GitHub CLI field name was unsupported, a jq regex did not parse, and ClickHouse interpreted double-quoted strings as identifiers. A separate empty result was initially inconclusive because the successful listener-start log is filtered before Better Stack ingestion.

## Environment

- Module: Developer Tooling
- Affected component: GitHub CLI, jq, ClickHouse query helper, and worktree-based research
- Date: 2026-10-30

## Symptoms

- `gh issue view` returned `Unknown JSON field: "authorAssociation"`.
- The jq expression with escaped parentheses failed before the issue comments were inspected.
- ClickHouse returned `UNKNOWN_IDENTIFIER` for `_HOSTNAME` when SQL double quotes were used for string literals.
- A successful Better Stack query returned no proxy-listener INFO event; Vector's app-container filter admits WARN+ only.

## What Didn't Work

**Attempted solution 1:** Request `authorAssociation` from `gh issue view --json`.

- **Why it failed:** That field is not exposed by the installed `gh issue view` JSON schema. The command printed its supported field list and exited non-zero.

**Attempted solution 2:** Use an escaped-parenthesis regex in a shell-quoted `gh api --jq` expression.

- **Why it failed:** The jq parser rejected the expression before returning the API response. Fixed phrases did not need regex matching.

**Attempted solution 3:** Use double quotes around ClickHouse string arguments inside SQL passed to `betterstack-query.sh`.

- **Why it failed:** ClickHouse treated the double-quoted values as identifiers and returned `UNKNOWN_IDENTIFIER`; no log query ran.

**Attempted solution 4:** Look for `betterstack-query.sh` under `plugins/soleur/scripts/`.

- **Why it failed:** The helper is at repository-root `scripts/betterstack-query.sh`, as the runbook documents.

## Session Errors

**The session-start temp sweep skipped because the local tmpfs guard held its lock.**

- **Recovery:** Inspected the lock holder with `lslocks`, `fuser`, and `ps`; left the active guard untouched and did not retry the sweep.
- **Prevention:** Treat lock contention as an interlock; never remove the lock or retry while its holder is running.

**An initial issue query requested unsupported `authorAssociation`.**

- **Recovery:** Re-ran with fields supported by `gh issue view` and read the needed issue state/body.
- **Prevention:** Check the specific subcommand's supported `--json` fields before adding optional fields.

**An initial artifact glob returned no #11181 matches.**

- **Recovery:** Used `git ls-files '*11181*'` from the active worktree to enumerate tracked artifacts.
- **Prevention:** When the exact tracked artifact set matters, verify with `git ls-files` rather than treating a broad glob miss as absence.

**A CPO subagent's jq filter used an escaped-parenthesis regex that failed to parse.**

- **Recovery:** Replaced it with literal `contains()` predicates and recorded the query-syntax learning.
- **Prevention:** Use fixed-string predicates for fixed phrases; reserve jq regexes for genuine pattern matching.

**The repository-research and CLO subagents each briefly grepped the bare checkout from a worktree session.**

- **Recovery:** Both discarded the bare-checkout results and re-verified from the specified worktree and HEAD.
- **Prevention:** Use only the supplied absolute worktree path for reads and searches; the worktree rule already requires this for subagents.

**The Better Stack helper was first sought under the plugin tree.**

- **Recovery:** Located it at repository-root `scripts/betterstack-query.sh` and read the runbook before invoking it.
- **Prevention:** Resolve script paths against the active repository tree; do not assume every helper is plugin-owned.

**The first ClickHouse query used SQL double quotes for string literals.**

- **Recovery:** Used SQL single-quoted literals inside a shell variable and escaped `$BS_TABLE` for the helper's substitution.
- **Prevention:** Keep shell, SQL, and helper-token quoting rules separate; test the smallest query before the credential-wrapped call.

**The Better Stack lookup returned no proxy-listener INFO rows.**

- **Recovery:** Checked `vector.toml` and found that the app-container stream filters below WARN+, so the empty query was not used to infer listener state.
- **Prevention:** Verify instrumentation and log filters before treating an empty telemetry query as evidence of absence; use the required on-host runtime-bind probe.

**An empty patch move hunk was rejected.**

- **Recovery:** Renamed the already-read learning file with `mv`, then staged the old and new paths explicitly.
- **Prevention:** Supply a non-empty patch hunk for a move or use a filesystem rename for a content-preserving move.

**The push output reported 87 Dependabot alerts.**

- **Recovery:** Queried the open-alert API and verified the reported severity counts; this was unrelated to #11181.
- **Prevention:** Verify automated security notices through their source API before treating them as a new finding for the current task.

**A grep pattern accidentally contained a NUL byte and was rejected by the tool.**

- **Recovery:** Re-ran the phase-heading search without the NUL byte.
- **Prevention:** Keep search patterns to visible regex characters and retry after correcting tool-input validation errors.

**A compound solution-extractor agent answered the prior Notifications-route fix instead of this session's scope.**

- **Recovery:** Discarded that response and used the issue/PR evidence and other assessments for the #11181 conclusion.
- **Prevention:** Anchor each specialist prompt to the current question and require an explicit match to the requested scope before accepting its result.

**The compound documentation prompt did not include the full parent error inventory.**

- **Recovery:** Retained the parent-session inventory as authoritative and corrected the learning from that list.
- **Prevention:** Include the explicit error inventory in each documentation-writer prompt; do not assume a child receives parent conversation history.

**A post-rename `git add` still named the absent source path.**

- **Recovery:** Staged the destination path only; the prior `git mv` had already staged the source removal.
- **Prevention:** After a rename, stage the new path and check the index status instead of passing both old and new paths blindly.

## Solution

For GitHub issue state, request fields supported by the exact `gh` subcommand; when another endpoint's field is required, use its documented API response. For exact phrases in jq, prefer `contains()` over regex. For ClickHouse, use SQL single quotes for string literals and preserve the `betterstack-query.sh` `$BS_TABLE` substitution token through the shell layer. Read helpers from the repository path documented by the runbook. For runtime claims, inspect the logging pipeline before relying on empty results; the proxy listener's successful bind needs the separate on-host probe.

```bash
# Fixed phrase: avoid a regex in gh --jq.
gh api 'repos/jikig-ai/soleur/issues/11181/comments?per_page=100' \
  --jq '.[] | select(.body | contains("Operator answers")) | {id,created_at}'

# SQL literals use single quotes; escape the helper token from shell expansion.
SQL="SELECT count() FROM remote(\$BS_TABLE) WHERE JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-web-platform' FORMAT JSONEachRow"
```

## Why This Works

The same command line passes through multiple parsers: the shell, a CLI's option parser, jq or SQL, and sometimes a repository helper's own token substitution. Quoting valid in one layer may be invalid or semantically different in another. Separately, an empty telemetry query is meaningful only when the success signal is actually shipped; here INFO app logs are filtered before Better Stack ingestion.

## Prevention

- Validate unfamiliar GitHub CLI JSON fields against that subcommand's supported field list.
- Use literal jq predicates for fixed phrases and the query language's own string-literal syntax.
- Read helper paths and query examples from the active worktree's runbook before use.
- Confirm that a signal is instrumented and retained before interpreting an empty query; use the on-host runtime-bind probe for this listener.
- In a worktree, pass absolute worktree paths and the pinned HEAD to subagents; discard and re-run any bare-checkout result.

## Related Issues

- See also: [`gh --jq` does not forward `--arg`](../2026-04-15-gh-jq-does-not-forward-arg-to-jq.md) — related GitHub CLI/jq boundary, with a different root cause.
- See also: [enumerate umbrella child PRs before spawning leaders](../2026-05-15-brainstorm-enumerate-umbrella-child-prs-before-leader-spawn.md) — the existing #11181 state-reconciliation pattern.
