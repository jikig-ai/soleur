# Security Scanning Alerts Fix + CI Gate

**Date:** 2026-04-16
**Status:** Complete
**Issue:** #2417

## What We're Building

Dismiss all 21 open CodeQL false-positive alerts via the GitHub API and add CodeQL as a
required status check so PRs cannot merge with new security findings.

### Scope

1. **Dismiss 21 open CodeQL alerts** with per-alert reasoning:
   - 12 alerts in test/tooling files: dismissed as `"used in tests"`
   - 9 alerts in production files: dismissed as `"false positive"` with specific explanation
2. **Add CodeQL to the "CI Required" ruleset** as a required status check alongside
   existing `test`, `dependency-review`, and `e2e` checks
3. **Verify** with a test PR that the gate blocks on new critical/high findings

### Out of Scope

- Inline code suppression comments (decided against: pollutes code, vendor lock-in)
- Custom CodeQL workflow (default setup is sufficient)
- Semgrep or additional SAST tools (no evidence of detection gaps)
- Hono dependency update (already merged in separate session)
- Switching CodeQL threat model to `remote` only (deferred follow-up)

## Why This Approach

### False Positive Analysis

Research confirmed every flagged file already has proper defenses:

| Alert Type | Count | Files | Defense Already Present |
|---|---|---|---|
| SSRF (critical) | 6 | analytics route, bot scripts, github-api, qa-auth, bot-fixture test | Hardcoded URLs from env vars; no user input in URL construction |
| Path injection (high) | 4 | bot-signin, workspace test, sandbox | Symlink resolution, containment checks, controlled test paths |
| User-controlled bypass (high) | 2 | bot-fixture | Supabase URLs from env only |
| Resource exhaustion (high) | 2 | ws-handler | 3-layer rate limiting, bounded timers, .unref()'d |
| Remote property injection (high) | 1 | analytics route | Strips sensitive props before forwarding |
| File system race (high) | 1 | kb-reader | Symlink guards, bubblewrap sandbox mitigation |
| Network data to file (medium) | 3 | kb-route-helpers, upload route, bot-signin | Sanitized filenames, path containment, temp files with 0o700 |

CodeQL's `extended` query suite flags structural patterns (any `fetch()` = SSRF, any
`path.resolve()` = traversal) without tracing data flow to prove user input reaches the
sink. These are definitionally false positives.

### API Dismissal Over Inline Comments

- API dismissals are the established pattern in this repo (alerts #86, #87)
- No code changes needed in any file
- If code at a flagged location changes substantially, CodeQL creates a new alert (correct
  behavior -- the changed code should be re-evaluated)
- Inline `// lgtm[...]` syntax is CodeQL-specific vendor lock-in

### Ruleset Over Custom Workflow

- CodeQL already runs on every PR via GitHub default setup
- The "CI Required" ruleset already exists (ID: 14145388) requiring `test`,
  `dependency-review`, `e2e`
- Adding `CodeQL` to this ruleset is a single API call
- Native CodeQL check only flags NEW alerts from the PR diff (not pre-existing)

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Handle false positives | API dismissal only | Established pattern, no code pollution, correct re-evaluation on code change |
| CI gate mechanism | CodeQL as required status check | Zero custom code, leverages native GitHub features, blocks only new alerts |
| Alert categorization | Per-alert reasoning | Test files as "used in tests", production as "false positive" with specific explanation |
| Additional scanners | None | No evidence of detection gaps; CodeQL extended suite is sufficient |
| Inline suppression | Rejected | Vendor lock-in, code pollution, unnecessary given API dismissal |

## Open Questions

None -- all design decisions resolved.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** CTO confirmed all alerts are false positives, recommended API-only dismissal
over inline comments, and endorsed adding CodeQL to the existing "CI Required" ruleset.
No code changes needed. Follow-up: consider switching CodeQL threat model from
`remote_and_local` to `remote` only to reduce false positive volume long-term.
