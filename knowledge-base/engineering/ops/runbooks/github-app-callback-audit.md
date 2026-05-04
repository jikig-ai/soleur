---
title: GitHub App callback URL audit runbook
date: 2026-05-04
owners: engineering/ops
applies_to:
  - https://github.com/organizations/jikig-ai/settings/apps/soleur-ai
  - .github/workflows/scheduled-oauth-probe.yml
  - apps/web-platform/test/oauth-probe-contract.test.ts
related_issues: [1784, 3183]
related_prs: [3181]
---

# GitHub App callback URL audit runbook

The GitHub App `soleur-ai` (client_id `Iv23li9p88M5ZxYv1b7V`) serves
**both** of our GitHub OAuth flows:

- **Flow A — Supabase-mediated SSO.** `signInWithOAuth({provider:"github"})`.
  Effective `redirect_uri` is whatever Supabase advertises:
  - `https://api.soleur.ai/auth/v1/callback` (custom-domain, healthy state)
  - `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback`
    (canonical, advertised during custom-domain re-provisioning)
- **Flow B — `/api/auth/github-resolve`.** App-direct OAuth used by
  email-only users on `/connect-repo` to discover their GitHub username.
  `redirect_uri` = `https://app.soleur.ai/api/auth/github-resolve/callback`.

Therefore the App's "Callback URL" textarea MUST contain ALL THREE
entries, one per line. Losing any one entry breaks the corresponding
flow with a GitHub-rendered error page:

> The `redirect_uri` is not associated with this application.

Both healthy and failing states return HTTP 200 — only the response body
distinguishes them. The `scheduled-oauth-probe.yml` workflow greps for
`redirect_uri is not associated` against every registered URL every 15
minutes; this runbook is the operator-side companion to that probe.

## Required callback URLs (production)

```text
https://app.soleur.ai/api/auth/github-resolve/callback
https://api.soleur.ai/auth/v1/callback
https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback
```

For local-dev convenience the textarea MAY also include
`http://localhost:3000/api/auth/github-resolve/callback` and
`http://localhost:54321/auth/v1/callback`. These are NOT required for
prod and are flagged by the probe as "noise but not failure" if absent.

## Audit procedure

### 1. Read the current state

```bash
xdg-open 'https://github.com/organizations/jikig-ai/settings/apps/soleur-ai'
```

Navigate to **Identifying and authorizing users → Callback URL** and
capture the textarea contents verbatim. Paste into the tracking issue
along with the byte count: `wc -c <<<"$contents"`.

The byte count is the forensic anchor — future drift comparisons use it
to detect whitespace/case-only changes that visual review would miss.

### 2. Diff against the required list

The required list is in this runbook (above). Compare line-by-line:

- **Trailing slash matters.** GitHub treats `…/callback` and
  `…/callback/` as different URLs (path-prefix matching is from the
  registered URL forward, not the other direction).
- **Scheme matters.** `http://` ≠ `https://` even on localhost.
- **Host case matters** in some setups; preserve the source-of-truth
  spelling.

### 3. Apply the diff (operator click)

Add any missing entries — one per line. Confirm "Request user
authorization (OAuth) during installation" is checked. Click **Update**
(CSRF-protected; agent shells cannot auto-submit).

### 4. Verify via probe

```bash
gh workflow run scheduled-oauth-probe.yml
sleep 5
RUN_ID=$(gh run list --workflow=scheduled-oauth-probe.yml --limit 1 \
  --json databaseId --jq '.[0].databaseId')
# Poll until completed; should be ~30s
gh run view "$RUN_ID" --json status,conclusion --jq '"\(.status) \(.conclusion)"'
```

Conclusion must be `success`. If it's `failure`, the probe issue body
will name the specific URL still failing — re-open the dashboard and
double-check that line for invisible characters (Unicode hyphens, NBSP,
zero-width joiners — common when copy-pasting from chat).

### 5. Close the tracking issue

Per `/ship` Phase 7 Step 3.5 callback-URL audit anchor, the closing
comment MUST contain ALL THREE fields:

1. The verbatim `redirect_uri` value(s) verified — paste each registered
   callback URL byte-for-byte.
2. The workflow run ID showing the probe ran green AFTER the dashboard
   change (URL of the form
   `https://github.com/jikig-ai/soleur/actions/runs/<id>`).
3. The byte count of the GitHub App's Callback URL textarea contents.

A close attempt without all three fields is workflow non-compliance per
`wg-when-fixing-a-workflow-gates-detection`. This is the gate that was
absent for #1784 (closed without verified second remediation) and led
to recurrence in #3183.

## Rollback

GitHub does not version the Callback URL field. Rollback is "remove the
new entry, re-add the previous one verbatim from the issue body
forensic snapshot, click Update, re-run probe."

## Common operator mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Trailing slash inconsistency | Probe fails on one URL only | Match the source-of-truth spelling exactly |
| Pasted with leading/trailing whitespace | Same | GitHub trims, but the byte count tells you if a manual edit drifted |
| Removed the canonical `supabase.co` URL "because we have a custom domain" | Flow A breaks during the next custom-domain CNAME re-provision (silent until then) | Restore. The custom-domain advertisement is not guaranteed; canonical is the durable fallback. |
| Rotated `GITHUB_CLIENT_SECRET` "to be safe" | None — secret rotation does not affect callback URL registration | Rolling the secret is harmless but extends MTTR. Do not cargo-cult. |
| Edited the wrong App (an old OAuth App vs. the GitHub App) | Probe stays red after Update | Verify via `gh api /app` JWT-authenticated — `client_id` must match `Iv23li9p88M5ZxYv1b7V` |

## Cross-references

- `/ship` Phase 7 Step 3.5 — Callback URL audit anchor and closure gate
  (`plugins/soleur/skills/ship/SKILL.md`).
- `apps/web-platform/test/oauth-probe-contract.test.ts` — sentinel
  string + required-paths assertions; refresh in lockstep with this
  runbook if GitHub rewords its error page.
- `oauth-probe-failure.md` — runbook for `github_oauth_*_unregistered`
  and adjacent failure modes.
- `knowledge-base/project/learnings/integration-issues/2026-05-04-github-app-callback-url-three-entries.md`
  — the underlying invariants (single client_id, three callback URLs,
  body-grep load-bearing).
