---
title: "sec: Switch CodeQL threat model from remote_and_local to remote only"
type: fix
date: 2026-04-16
---

# sec: Switch CodeQL threat model from remote_and_local to remote only

## Enhancement Summary

**Deepened on:** 2026-04-16
**Sections enhanced:** 2 (Proposed Solution, Implementation Phase 1)
**Research sources:** Context7 GitHub REST API docs, institutional learnings (3 files),
live API verification

### Key Improvements

1. **Fixed broken API call format** -- replaced `--field` with `--input -` heredoc for array
   parameters, preventing HTTP 422 (institutional learning
   `2026-04-10-github-security-enablement-api-patterns.md`)
2. **Corrected language list expectation** -- current config has 5 language entries (GitHub
   auto-expands `javascript-typescript`), not 3. Verification step now checks for all 5.
3. **Added post-PATCH verification for silent failures** -- GitHub API can return 200 OK
   without applying changes (learning from secret scanning enablement); plan now includes
   immediate GET verification after PATCH.

### Relevant Institutional Learnings Applied

- `2026-04-10-github-security-enablement-api-patterns.md` -- `--field` wraps arrays as
  strings; use `--input -` with heredoc. After any settings PATCH, immediately re-read to
  verify the change was applied.
- `2026-04-10-codeql-api-dismissal-format.md` -- GitHub API enum format uses space-separated
  strings, not snake_case. (Not directly applicable here but context for the API surface.)
- `2026-04-13-codeql-to-issues-invalid-workflow-trigger.md` -- CodeQL alert polling pattern
  context; confirms the daily cron + deduplication approach for alert-to-issue tracking.

## Overview

Switch the CodeQL default setup threat model from `remote_and_local` to `remote` to reduce
false positive volume. The current configuration flags server-side code that uses environment
variables, CLI arguments, and file system paths as taint sources -- patterns with no
user-controlled input reaching the sink. Switching to `remote` restricts taint sources to
network requests only, which is the appropriate model for a web application where local inputs
(env vars, file paths) are server-controlled and not adversary-reachable.

## Problem Statement

The `remote_and_local` threat model was enabled in PR #1894 (2026-04-10) because the repo
contains shell scripts and GitHub Actions workflows that process environment variables and CLI
arguments. In practice, this produced 100 false positives (now dismissed) -- 64 `path-injection`
alerts and 9 `request-forgery` alerts driven primarily by the `local` taint sources. These
alerts flag hardcoded env-var URLs as SSRF and server-controlled file paths as traversal, which
are structurally false positives in this codebase.

After the bulk dismissal in PR #2416, zero open alerts remain. However, future PRs will
continue to trigger false positives for the same patterns, creating ongoing triage friction.

### Current state

- **Threat model:** `remote_and_local`
- **Query suite:** `extended`
- **Open alerts:** 0
- **Dismissed alerts:** 100 (68 "false positive", 31 "used in tests", 1 "won't fix")
- **Top dismissed rules:** `js/path-injection` (39), `py/path-injection` (25),
  `js/request-forgery` (9)

## Proposed Solution

A single GitHub API call to update the CodeQL default setup configuration. Use `--input -`
with a heredoc JSON body, not `--field`, because `--field` wraps arrays as strings causing
HTTP 422 (documented in learning `2026-04-10-github-security-enablement-api-patterns.md`):

```bash
gh api -X PATCH repos/jikig-ai/soleur/code-scanning/default-setup \
  --input - <<'JSONEOF'
{
  "state": "configured",
  "query_suite": "extended",
  "languages": ["actions", "javascript-typescript", "python"],
  "threat_model": "remote"
}
JSONEOF
```

**Note on languages:** The current GET response shows 5 language entries (`actions`,
`javascript`, `javascript-typescript`, `python`, `typescript`) because GitHub auto-expands
`javascript-typescript` into separate entries. Sending `["actions", "javascript-typescript",
"python"]` in the PATCH is correct -- GitHub re-derives the expanded set. Verify via GET after
PATCH that all 5 entries are still present.

This preserves the `extended` query suite and all language coverage while restricting taint
sources to network requests only.

### Why this is safe

1. **All 100 dismissed alerts were false positives** -- no genuine vulnerability was found among
   them. The `local` taint sources added noise without catching real issues.
2. **`remote` still covers the actual attack surface** -- user-controlled input arrives via HTTP
   requests. Server-side env vars and file paths are not adversary-reachable.
3. **Reversible** -- switching back to `remote_and_local` is a single API call with no code
   changes required.
4. **No impact on other security tools** -- secret scanning, push protection, and Dependabot
   are unaffected.

## Implementation Phases

### Phase 1: Switch threat model and verify

1. Run the PATCH API call to update `threat_model` from `remote_and_local` to `remote`.
   Use `--input -` with heredoc (not `--field` -- `--field` wraps arrays as strings, HTTP 422):

   ```bash
   gh api -X PATCH repos/jikig-ai/soleur/code-scanning/default-setup \
     --input - <<'JSONEOF'
   {
     "state": "configured",
     "query_suite": "extended",
     "languages": ["actions", "javascript-typescript", "python"],
     "threat_model": "remote"
   }
   JSONEOF
   ```

2. Verify the change via GET: `gh api repos/jikig-ai/soleur/code-scanning/default-setup`
   -- confirm `threat_model` is `remote` and all 5 language entries are preserved
   (`actions`, `javascript`, `javascript-typescript`, `python`, `typescript`)
3. Poll for re-analysis completion via the analyses endpoint:
   `gh api repos/jikig-ai/soleur/code-scanning/analyses?tool_name=CodeQL --jq '.[0] | {created_at, results_count}'`
   -- wait for a new analysis with `created_at` after the config change timestamp
4. Check open alerts: `gh api repos/jikig-ai/soleur/code-scanning/alerts?state=open --jq 'length'`
   -- confirm zero open alerts

### Phase 2: Update documentation

1. Add a note to `knowledge-base/project/specs/feat-enable-github-security-quality/tasks.md`
   recording the threat model change: `[Updated 2026-04-16] threat model switched to remote
   (see #2418)`
2. Update `knowledge-base/project/specs/feat-enable-github-security-quality/session-state.md`
   with the same note

## Acceptance Criteria

- [ ] CodeQL default setup `threat_model` field reads `remote` (not `remote_and_local`)
- [ ] Language list preserved after PATCH (all 5 entries: actions, javascript,
  javascript-typescript, python, typescript)
- [ ] CodeQL re-analysis completes successfully after the config change
- [ ] Previously dismissed alerts remain dismissed (not re-opened by the config change)
- [ ] Spec documentation updated to reflect the new threat model

## Test Scenarios

- Given the CodeQL default setup is configured with `remote_and_local`, when the PATCH API
  sets `threat_model=remote`, then GET returns `threat_model: "remote"` and `languages`
  includes `actions`, `javascript-typescript`, and `python`
- Given the config change triggers a re-analysis, when the analysis completes, then
  `gh api repos/.../code-scanning/alerts?state=open --jq 'length'` returns `0`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- Parent issue: #2417 (closed, merged as PR #2416)
- Deferred from brainstorm: `knowledge-base/project/brainstorms/2026-04-16-security-scanning-alerts-brainstorm.md`
- Original enablement plan: `knowledge-base/project/plans/2026-04-10-feat-enable-github-security-quality-plan.md`
- CodeQL API format learning: `knowledge-base/project/learnings/2026-04-10-codeql-api-dismissal-format.md`
- AGENTS.md rule: `[id: hr-github-api-endpoints-with-enum]`

## References

- [GitHub CodeQL default setup API](https://docs.github.com/en/rest/code-scanning/code-scanning#update-a-code-scanning-default-setup-configuration)
- Issue: #2418
