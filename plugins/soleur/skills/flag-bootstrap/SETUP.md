# Flagsmith Operator Setup — One-time

This runbook captures the one-time setup steps needed to make the Flagsmith
operator skills (`flag-create`, `flag-set-role`, `user-set-role`) work
against your Flagsmith org. **Already completed for `Soleur` org / project
`web-platform`** during PR #2; this doc exists for (a) onboarding new
operators, (b) recreating in a different Flagsmith org/project, and
(c) audit reproducibility.

## Prerequisites

- Flagsmith account with admin access to the organisation.
- `doppler` CLI authenticated with project access to `soleur`.

## Step 1 — Create operator Doppler env+config

```bash
doppler environments create cli cli -p soleur
doppler configs create cli_ops -p soleur -e cli
```

(Doppler requires the config name to start with `cli_` — that's why it's
`cli_ops`, not bare `cli`.)

## Step 2 — Generate Flagsmith Admin API token

1. Flagsmith UI → **Organisation Settings → API Keys** (the per-org keys,
   NOT the per-user `/account` API keys — those have different scope).
   Direct URL: `https://app.flagsmith.com/organisation/<org-id>/settings?tab=api-keys`.
2. **Create API Key**:
   - Name: `soleur-cli-ops`
   - Is admin: ON
   - Expiry: Never (rotate as needed; skill does not require expiry)
3. Copy the token shown on the success modal — Flagsmith does NOT store it
   for re-viewing.

## Step 3 — Write token to Doppler

Pipe via stdin so the value never appears in shell history:

```bash
printf '<paste-token-here>' | doppler secrets set FLAGSMITH_MANAGEMENT_API_KEY \
  -p soleur -c cli_ops --silent
```

Sanity-test:

```bash
TOKEN=$(doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops --plain)
curl -sS -H "Authorization: Api-Key $TOKEN" \
  "https://api.flagsmith.com/api/v1/projects/?organisation=29821" \
  | python3 -c 'import json,sys; print([p["name"] for p in json.load(sys.stdin)])'
# Expected: ['web-platform']
```

## Step 4 — Create the two role segments

Run this once per Flagsmith project. Pre-checked for idempotency by name.

```bash
TOKEN=$(doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops --plain)
PROJECT_ID=39082

# role-prd
curl -sS -X POST -H "Authorization: Api-Key $TOKEN" -H "Content-Type: application/json" \
  "https://api.flagsmith.com/api/v1/projects/${PROJECT_ID}/segments/" \
  -d '{"name":"role-prd","project":'${PROJECT_ID}',"description":"Users with role=prd (default for all users; matches anonymous via ANON_IDENTITY).","rules":[{"type":"ALL","rules":[{"type":"ANY","rules":[],"conditions":[{"operator":"EQUAL","property":"role","value":"prd"}]}],"conditions":[]}]}' \
  | python3 -m json.tool | head -5

# role-dev
curl -sS -X POST -H "Authorization: Api-Key $TOKEN" -H "Content-Type: application/json" \
  "https://api.flagsmith.com/api/v1/projects/${PROJECT_ID}/segments/" \
  -d '{"name":"role-dev","project":'${PROJECT_ID}',"description":"Users with role=dev (beta/internal testers cohort).","rules":[{"type":"ALL","rules":[{"type":"ANY","rules":[],"conditions":[{"operator":"EQUAL","property":"role","value":"dev"}]}],"conditions":[]}]}' \
  | python3 -m json.tool | head -5
```

Verify both exist:

```bash
curl -sS -H "Authorization: Api-Key $TOKEN" \
  "https://api.flagsmith.com/api/v1/projects/${PROJECT_ID}/segments/" \
  | python3 -c 'import json,sys; [print(s["id"], s["name"]) for s in json.load(sys.stdin)["results"]]'
# Expected:
#   1129194 role-dev
#   1129195 role-prd
```

## Step 5 — Archive the dead `command-center-soleur-go` flag

Retired in PR #3270 (the cc-soleur-go runner now runs unconditionally) but
left as an orphan in Flagsmith. Archive to keep the feature list clean:

```bash
curl -sS -X PATCH -H "Authorization: Api-Key $TOKEN" -H "Content-Type: application/json" \
  "https://api.flagsmith.com/api/v1/projects/${PROJECT_ID}/features/209130/" \
  -d '{"is_archived":true}'
```

## Step 6 — Smoke-test the three skills

```bash
# Read-only — no mutations.
bash plugins/soleur/skills/flag-set-role/scripts/flip.sh kb-chat-sidebar dev on --dry-run
bash plugins/soleur/skills/user-set-role/scripts/set-role.sh <your-email> dev --dry-run
bash plugins/soleur/skills/flag-create/scripts/create.sh _test_probe --dry-run
```

Each should print pre-state + proposed mutations + "(dry-run — exiting 0)"
without any writes.

## Why this isn't a Terraform module

The Flagsmith Terraform provider supports `flagsmith_segment` and
`flagsmith_feature_segment` resources. We don't use it here because:

1. The setup runs exactly **once per Flagsmith project** — IaC overhead
   isn't paid back across many applies.
2. The runtime skills (`flag-set-role`, etc.) need to mutate Flagsmith
   on every flag flip; Terraform would create a state-management nightmare
   ("run terraform apply to flip a flag" is worse than "run a skill").
3. The bash runbook above is plain HTTP — anyone can audit it in 30
   seconds. Terraform indirection isn't worth it for ~10 lines of curl.

If you eventually want IaC for your Flagsmith setup, the migration is
straightforward: `terraform import flagsmith_segment.role_prd 1129195` and
`flagsmith_segment.role_dev 1129194`, then write the matching `.tf`.
