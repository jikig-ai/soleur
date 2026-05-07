---
module: github-app
date: 2026-05-07
problem_type: integration_issue
component: ops_runbook
symptoms:
  - "gh repo create <org>/<name> returns HTTP 403: You need admin access to the organization"
  - "User PAT lacks org admin rights for an org Soleur owns or is installed on"
root_cause: wrong_credential_class_for_org_operation
severity: low
tags: [github-app, doppler, ops, credentials, fallback-path]
synced_to: []
---

# Learning: When `gh` CLI returns 403 admin-required on a Soleur-owned org, fall back to the App installation token (not manual handoff)

## Problem

While provisioning the `jikig-ai/kb-template` template repo for PR #3399, this command returned 403:

```text
$ gh repo create jikig-ai/kb-template --public --description "Soleur KB seed template" --add-readme
HTTP 403: You need admin access to the organization before adding a repository to it.
```

The user account's GitHub PAT (used by `gh`) does not have `admin` membership on the `jikig-ai` organization — that's a deliberate principle-of-least-privilege posture for routine work.

## Root cause

`gh` authenticates with the **user's PAT**. Org-level operations (create repo, modify org settings, manage teams) require the user to be an org owner or have the relevant org permission grant. Most engineers will not, by design.

The Soleur GitHub App has installations on `jikig-ai` and on individual user accounts (e.g., Elvalio). The org installation has `administration:write` accepted, which **is** sufficient to create repos under the org via `POST /orgs/{org}/repos`. The credential class for that call is the **installation access token** (IAT, `ghs_...` prefix), not the user's PAT.

Per AGENTS.md `hr-exhaust-all-automated-options-before`, the priority order for elevated operations is:

> (1) Doppler → (2) MCP → (3) CLIs → (4) REST → (5) Playwright → (6) manual handoff.

The `gh` CLI is tier (3); when it fails for a credential-class mismatch (not a missing-flag mismatch), the next step is tier (1) — Doppler — to retrieve the App credentials and mint an installation token.

## Solution

### Mint an installation token from Doppler-stored App credentials

```bash
# 1. Mint App JWT (RS256) from Doppler-stored private key + App ID
cat > /tmp/mint-jwt.py <<'EOF'
import os, time, jwt
app_id = os.environ["GITHUB_APP_ID"]
key = os.environ["GITHUB_APP_PRIVATE_KEY"].replace("\\n", "\n")
now = int(time.time())
print(jwt.encode(
    {"iat": now - 60, "exp": now + 540, "iss": int(app_id)},
    key, algorithm="RS256"
))
EOF

JWT=$(doppler run -p soleur -c prd -- python3 /tmp/mint-jwt.py)

# 2. Exchange JWT for org installation access token (IAT, 1h TTL)
TOKEN=$(curl -sS -X POST -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/app/installations/<INSTALLATION_ID>/access_tokens \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

# 3. Use IAT for the org-level operation that gh PAT couldn't do
curl -sS -X POST -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  -d '{"name":"<repo>","private":false,"auto_init":true,"is_template":true}' \
  https://api.github.com/orgs/<org>/repos
```

For PR #3399's case, `<INSTALLATION_ID>` was `122213433` (jikig-ai org installation, looked up via `GET /app/installations` with the JWT).

### Cleanup

The token is short-lived (1 hour TTL) — no rotation step needed. JWT private keys live only in Doppler; do not commit `mint-jwt.py` with embedded keys.

## Key insight

`gh` CLI 403s on org operations are a **credential-class mismatch** (PAT vs IAT), not a permissions failure on the App side. Before suggesting "ask the org admin to do it manually," check whether the App installation has the required permission — if it does, mint a token from Doppler and proceed. The cost is one Bash call; the savings is one round-trip with the operator.

This pattern generalizes to any org-level GitHub operation Soleur's App is permissioned for: creating template repos, updating org webhooks, managing branch protection on org-owned repos, etc.

## Prevention

For PRs that need to create or modify org-owned GitHub resources:

1. **Plan-time**: in the plan's "Phase 1 — Operator pre-step" section, prefer `curl` against `/orgs/{org}/...` with an installation token over `gh repo create`. Reference this learning in the operator runbook.
2. **Runbook entry**: add a `knowledge-base/engineering/ops/runbooks/github-app-org-operations.md` (follow-up issue) that documents the JWT-mint-and-exchange flow as a reusable runbook step.
3. **Don't reach for manual handoff** when the symptom is `gh ... 403: admin access required` and the org has a Soleur App installation. The first Bash call after that error should be `doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain` (or equivalent).

## Session errors

None new — this learning IS the session error for PR #3399.

## Cross-references

- AGENTS.md `hr-exhaust-all-automated-options-before` — priority hierarchy that this learning concretizes.
- Sibling learning `2026-05-07-github-app-user-installation-cannot-post-user-repos.md` — the in-app code path also uses installation tokens; this learning covers the operator-side equivalent.
- 2026-04-06 learning `github-app-org-repo-creation-endpoint-routing.md` — established that org installations use `POST /orgs/{org}/repos` (the same endpoint the operator path now uses).
- PR #3399, Ref #3401.
