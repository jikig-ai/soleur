---
module: System
date: 2026-04-06
problem_type: integration_issue
component: tooling
symptoms:
  - "Sentry API search query with OR operator returns error instead of results"
  - "jq length returns 1 for error response object, masking the real failure"
root_cause: wrong_api
resolution_type: workflow_improvement
severity: low
tags: [sentry, api, search, verification, production]
---

# Troubleshooting: Sentry API Search Does Not Support Boolean Operators

## Problem

During production verification of the GitHub project setup flow (#1489), the plan prescribed a Sentry API query using `OR` operators (`query=getUserById+OR+PGRST106+OR+identity`). The Sentry search API returned an error response instead of results, and piping to `jq 'length'` returned `1` (the error object's key count), briefly suggesting one issue existed when there were actually zero.

## Environment

- Module: System (production verification tooling)
- Affected Component: Sentry API integration for production monitoring
- Date: 2026-04-06

## Symptoms

- `curl ... | jq 'length'` returned `1` instead of expected `0`
- Raw response: `{"detail":"Error parsing search query: Boolean statements containing \"OR\" or \"AND\" are not supported in this search"}`
- The `jq 'length'` on a JSON object counts keys, not array elements -- the error object has 1 key (`detail`)

## What Didn't Work

**Direct solution:** The problem was identified on inspection of the raw response. Split into 3 separate queries.

## Session Errors

**Ralph loop script path incorrect in one-shot skill instructions**

- **Recovery:** Found correct path at `./plugins/soleur/scripts/setup-ralph-loop.sh`
- **Prevention:** One-shot skill should reference the correct script path

**OTP rate limit hit during Playwright authentication**

- **Recovery:** Waited 50s for cooldown, then sent OTP via UI and generated fresh code via admin API
- **Prevention:** When using Playwright OTP auth, call UI "Send sign-in code" first, then use `generate_link` admin API to retrieve the OTP code. Do not call `generate_link` before the UI send -- it triggers the rate limiter.

## Solution

Split boolean queries into separate individual queries:

```bash
# WRONG: Sentry search API does not support OR/AND operators
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://de.sentry.io/api/0/projects/$ORG/$PROJECT/issues/?statsPeriod=14d&query=getUserById+OR+PGRST106+OR+identity"

# CORRECT: Run separate queries for each term
curl -s ... "...?statsPeriod=14d&query=getUserById" | jq 'length'
curl -s ... "...?statsPeriod=14d&query=PGRST106" | jq 'length'
curl -s ... "...?statsPeriod=14d&query=identity" | jq 'length'
```

Always inspect raw API responses before piping through `jq` transformations -- `jq 'length'` on a JSON object counts keys, not array elements.

## Why This Works

1. The Sentry issues search endpoint only supports simple text queries, not boolean logic
2. Each separate query searches for a single term across issue titles, messages, and stack traces
3. Using `jq 'if type == "array" then length else error end'` would catch non-array responses

## Prevention

- When writing production verification plans that query the Sentry API, always use separate queries per search term -- never combine with `OR`/`AND`
- When piping API responses through `jq`, check the response type before applying array operations
- For Playwright OTP auth: trigger the UI "Send sign-in code" first, then call `generate_link` to retrieve the OTP. Reverse order triggers the rate limiter.

## Related Issues

- See also: [sentry-zero-events-production-verification-20260405.md](sentry-zero-events-production-verification-20260405.md)
- See also: [production-observability-sentry-pino-health-web-platform-20260328.md](production-observability-sentry-pino-health-web-platform-20260328.md)
