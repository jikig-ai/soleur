---
title: "sec: Dismiss false-positive CodeQL alerts and add CodeQL CI gate"
type: fix
date: 2026-04-16
---

# Dismiss False-Positive CodeQL Alerts and Add CodeQL CI Gate

Dismiss all 21 open CodeQL false-positive alerts via GitHub API and add CodeQL as a
required status check so PRs cannot merge with new security findings.

**Issue:** #2417 | **PR:** #2416 | **Branch:** feat-fix-security-scanning-alerts

## Overview

No application code changes. The work is entirely GitHub API calls:

1. Dismiss 21 alerts with per-alert reasoning (test files: `"used in tests"`,
   production: `"false positive"` with defense explanation)
2. Add CodeQL to the existing "CI Required" ruleset (ID: 14145388)
3. Verify the gate works on this PR

**Why these are false positives:** CodeQL's `extended` query suite flags structural
patterns (any `fetch()` = SSRF, any `path.resolve()` = traversal) without tracing data
flow. Every flagged file has proper defenses: hardcoded env-var URLs, symlink resolution,
3-layer rate limiting, input sanitization. See brainstorm for full analysis.

## Acceptance Criteria

- [x] Zero open CodeQL alerts: `gh api repos/jikig-ai/soleur/code-scanning/alerts --jq '[.[] | select(.state == "open")] | length'` returns `0`
- [x] "CI Required" ruleset includes 4 required status checks (test, dependency-review, e2e, CodeQL)
- [x] PR #2416 shows CodeQL as a required check with status `success` (not just `expected`)

## Test Scenarios

- Given all 21 alerts are open, when the dismissal script runs, then each alert's state
  changes to `"dismissed"` with the correct `dismissed_reason` and `dismissed_comment`
- Given the CI Required ruleset has 3 checks, when updated, then it has 4 checks
  including `CodeQL` with integration_id `57789`
- Given the ruleset is updated, when PR #2416 is viewed, then CodeQL appears as a
  required status check

## Implementation Phases

### Phase 1: Dismiss Test/Tooling Alerts (12 alerts)

Dismiss alerts in test and tooling files as `"used in tests"`.

**API format** (per AGENTS.md `hr-github-api-endpoints-with-enum`): use space-separated
`"used in tests"`, NOT `snake_case`.

**Test one alert first** before batch-dismissing to catch format errors early.

**Rate limiting:** Dismiss sequentially. If any call returns 429/403, respect the
`Retry-After` header. PATCH is idempotent for `state=dismissed`, so re-running is safe.

**Auth scope:** The `gh` CLI token needs `security_events` scope. Verify before starting.

| Alert | File | Rule | Comment |
|---|---|---|---|
| #107 | `plugins/soleur/test/ux-audit/bot-fixture.test.ts:127` | SSRF | Test file; fetch URL from env var SUPABASE_URL |
| #106 | `plugins/soleur/test/ux-audit/bot-fixture.test.ts:39` | SSRF | Test file; fetch URL from env var SUPABASE_URL |
| #105 | `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts:52` | SSRF | Tooling script; Supabase URL from env only |
| #104 | `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts:72` | SSRF | Tooling script; Supabase URL from env only |
| #115 | `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts:122` | HTTP-to-file | Tooling script; controlled path from env |
| #114 | `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts:122` | Path injection | Tooling script; path from env var |
| #113 | `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts:121` | Path injection | Tooling script; path from env var |
| #112 | `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts:212` | User-controlled bypass | Tooling script; Supabase URL from env |
| #111 | `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts:210` | User-controlled bypass | Tooling script; Supabase URL from env |
| #103 | `apps/web-platform/test/workspace.test.ts:38` | Path injection | Test file; controlled test paths |
| #102 | `apps/web-platform/test/workspace.test.ts:41` | Path injection | Test file; controlled test paths |
| #90 | `apps/web-platform/test/fixtures/qa-auth.ts:42` | SSRF | Test fixture; hardcoded Supabase URL from env |

**Command pattern:**

```bash
gh api repos/jikig-ai/soleur/code-scanning/alerts/{N} \
  -X PATCH \
  --field state=dismissed \
  --field dismissed_reason="used in tests" \
  --field dismissed_comment="<defense explanation>"
```

### Phase 2: Dismiss Production Alerts (9 alerts)

Dismiss production code alerts as `"false positive"` with per-alert defense explanation.

| Alert | File | Rule | Defense | Comment |
|---|---|---|---|---|
| #116 | `analytics/track/route.ts:92` | SSRF | URL is `PLAUSIBLE_EVENTS_URL` env var; hardcoded, no user input | Plausible analytics proxy; URL never from request |
| #117 | `analytics/track/route.ts:44` | Property injection | Props stripped of user_id/userId before forwarding; origin validated | Event properties allowlisted at source |
| #92 | `server/github-api.ts:64` | SSRF | GitHub API base URL hardcoded; paths from server-side callers only | DELETE rejected for cloud agents |
| #93 | `server/sandbox.ts:66` | Path injection | realpathSync + symlink resolution + ELOOP/EACCES denial + trailing slash guard | 3-layer path containment |
| #100 | `server/kb-reader.ts:366` | File system race | Symlink guards + bubblewrap sandbox + single-invocation atomicity | TOCTOU mitigated by execution context |
| #95 | `server/ws-handler.ts:254` | Resource exhaustion | Bounded timer with .unref(); cleared on teardown; 30min idle timeout | Subscription refresh interval |
| #88 | `server/ws-handler.ts:175` | Resource exhaustion | IP-based rate limit + concurrent connection cap + per-user session throttle | 3-layer defense-in-depth |
| #96 | `server/kb-route-helpers.ts:170` | HTTP-to-file | randomCredentialPath() temp file; mode 0o700; cleaned in finally block | Short-lived git credential helper |
| #89 | `app/api/kb/upload/route.ts:207` | HTTP-to-file | sanitizeFilename() + isPathInWorkspace() + extension allowlist + 20MB cap | Expected behavior: file upload handler |

### Phase 2.5: Verify All Alerts Dismissed (Hard Gate)

Before modifying the ruleset, confirm all 21 alerts are dismissed. If any remain open,
debug and fix before proceeding — adding the required check while alerts exist risks
blocking all 6 open PRs.

```bash
gh api repos/jikig-ai/soleur/code-scanning/alerts \
  --jq '[.[] | select(.state == "open")] | length'
# Expected: 0
```

### Phase 3: Add CodeQL to CI Required Ruleset

Update ruleset ID `14145388` to add CodeQL as a required status check.

**Current checks:** `test` (15368), `dependency-review` (15368), `e2e` (15368)
**Adding:** `CodeQL` (57789 — `github-advanced-security` app)

**Preserve `conditions` field** (targets default branch only). The current ruleset has
one rule type (`required_status_checks`), so the PUT is safe. Include `conditions` to
avoid losing the branch targeting:

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  -X PUT \
  --input - <<'EOF'
{
  "name": "CI Required",
  "enforcement": "active",
  "target": "branch",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "do_not_enforce_on_create": false,
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          {"context": "test", "integration_id": 15368},
          {"context": "dependency-review", "integration_id": 15368},
          {"context": "e2e", "integration_id": 15368},
          {"context": "CodeQL", "integration_id": 57789}
        ]
      }
    }
  ]
}
EOF
```

**Immediately re-read** to verify the change took effect (GitHub API can silently ignore
some fields — per plan sharp edge).

**Open PR impact:** 6 open PRs will now require a passing CodeQL check. CodeQL runs
automatically on push, so authors just need to push any commit (or re-push) to trigger
the analysis. No manual notification needed — the GitHub UI shows the missing check.

### Phase 4: Verify

1. Confirm zero open alerts: `gh api repos/jikig-ai/soleur/code-scanning/alerts --jq '[.[] | select(.state == "open")] | length'` returns `0`
2. Confirm ruleset shows 4 required checks: `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[0].parameters.required_status_checks | length'` returns `4`
3. Confirm PR #2416 shows CodeQL as a required check with status `success` (not `expected`)
4. If CodeQL shows as `expected` (pending), push an empty commit to trigger it:
   `git commit --allow-empty -m "chore: trigger CodeQL analysis" && git push`

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO confirmed all alerts are false positives, endorsed API-only dismissal,
and recommended adding CodeQL to existing ruleset. No code changes needed. Deferred:
switching CodeQL threat model to `remote` only (#2418).

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-16-security-scanning-alerts-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-fix-security-scanning-alerts/spec.md`
- AGENTS.md rule: `hr-github-api-endpoints-with-enum` (dismissal format)
- Learning: `knowledge-base/project/learnings/2026-04-13-codeql-alert-tracking-and-api-format-prevention.md`
- Deferred: #2418 (CodeQL threat model change)
