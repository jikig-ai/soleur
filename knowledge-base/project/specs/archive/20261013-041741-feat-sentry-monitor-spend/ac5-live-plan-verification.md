---
feature: feat-sentry-monitor-spend
issue: 6589
ac: AC5
date: 2026-07-17
plan: knowledge-base/project/plans/2026-07-17-fix-sentry-iac-delete-path-plan.md
---

# AC5 — live read-only full-root plan verification

Re-run at implementation time against live state, on the branch's as-written
config. The plan quoted a measurement taken at plan-authoring time; a
plan-quoted number is a precondition to verify, not a fact — this is the
re-derivation.

**Command** (read-only; the artifact was secret-scanned and shredded, see below):

```
cd apps/web-platform/infra/sentry
export SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_IAC_AUTH_TOKEN -p soleur -c prd_terraform --plain)
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false
terraform plan -no-color -input=false -out=/tmp/ac5-tfplan
terraform show -json /tmp/ac5-tfplan > /tmp/ac5.json
```

The provider reads a **raw** `SENTRY_AUTH_TOKEN`. Do NOT route it through
`doppler run --name-transformer tf-var` — that mangles it to
`TF_VAR_sentry_auth_token` and the provider dies with
`failed to perform health check`.

## Result — `Plan: 0 to add, 0 to change, 2 to destroy.`

### AC5a — the delete SET (identity, not cardinality)

```
jq -r '[.resource_changes[]|select(.change.actions==["delete"])|.address]|sort|.[]'
```

```
sentry_cron_monitor.scheduled_ghcr_token_minter
sentry_issue_alert.kb_tenant_mint_silent_fallback
```

Exactly the two known orphans, and **nothing else**. Asserted as a set because a
count cannot distinguish them from a different pair: a plan destroying
`soleur_apex` + `scheduled_oauth_probe` would satisfy `count == 2` verbatim while
deleting two live, load-bearing monitors.

### AC5b — creates and nested deletes

`destroy-guard-filter-sentry.jq` over the same plan:

```
{"resource_deletes":2,"resource_creates":0,"nested_deletes":0}
```

`resource_creates == 0` — nothing is created, so the create gate has nothing to
match and the full-root widening introduces no duplicate-create risk.
`nested_deletes == 0` — no array-of-blocks shrink.

### AC5c — the widened `ignore_changes` assumption

The filter's "the import-only alerts never appear in a plan diff" note went from
covering 2 `sentry_issue_alert` addresses to covering 22. Verified, not assumed:

| | count |
|---|---:|
| `sentry_issue_alert` changes in plan | 23 |
| of which `no-op` | **22** |
| of which `delete` | 1 (`kb_tenant_mint_silent_fallback` — the intended orphan destroy) |

All 22 **declared** alerts plan as no-op, including the 4 import-only `auth_*`
placeholders. The 23rd is the state-only orphan with no remaining block, which is
the resource this PR exists to destroy. This reconciles with the plan's
state/config census (state 50 cron / 23 issue_alert / 4 uptime; `.tf` 49/22/4).

### Plan-wide histogram

| n | actions |
|---:|---|
| 2 | `delete` |
| 75 | `no-op` |

77 addresses total. **Byte-for-byte reproduction of the plan-time measurement**
(`delete: 2, no-op: 75, create: 0`), from a different session against the branch's
as-written config.

## Artifact handling

`terraform show -json` embeds plan-input variables verbatim, including any
declared `sensitive = true` (`sensitive` masks render-time text output, NOT JSON
serialization) — see
`knowledge-base/project/learnings/security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md`.

This artifact was **not committed**. Before shredding it was scanned:

- `.variables` keys present: `sentry_org`, `sentry_project`, `sentry_region` — all
  non-sensitive. The auth token is **not** a TF variable here; the provider reads
  it from the raw env var, so it never enters the plan JSON.
- canonical secret-shape scan (`BEGIN … PRIVATE KEY|sntrys_|dp\.(pt|st|sa|ct)\.…|AKIA…`): **0 matches**.

The plan file, its JSON, and the local `.terraform/` were then shredded, and
`.terraform.lock.hcl` was restored to HEAD — a local `init` fetches only this
machine's platform and had silently dropped 2 of the 3 committed provider hashes,
which would have broken CI's `-lockfile=readonly` init on its own platform.
