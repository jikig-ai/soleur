---
title: "Doppler write-capable service token in-band mint: access enum + bootstrap cycle"
date: 2026-05-20
category: integration-issues
tags: [doppler, terraform, github-actions, service-tokens, bootstrap, in-band-mint]
issue: 4195
pr:
---

# Doppler write-capable service token in-band mint: access enum + bootstrap cycle

Context: PR #4181 wired a `Sync CF Access CI-SSH service token to Doppler` post-apply step in `.github/workflows/apply-web-platform-infra.yml`. The step failed at first execution because the workflow's `secrets.DOPPLER_TOKEN` is `prd_terraform`-scoped READ-only and `doppler secrets set` needs `read/write`. The fix (PR #4195) mints a dedicated write-capable service token in-band via Terraform (mirroring `apps/web-platform/infra/kb-drift.tf:65-86`) and publishes it as a separate GH Actions secret `DOPPLER_TOKEN_WRITE`. Three things bit during implementation that would re-bite anyone reaching for the same pattern.

## 1. Doppler `access` enum is `{"read","read/write"}` — NOT `{"read","write"}`

The issue body phrasing "mint a write-capable token" naturally transliterates to `access = "write"` in HCL. The Doppler provider rejects this at `terraform validate`:

```go
// DopplerHQ/terraform-provider-doppler doppler/resource_service_token.go
"access": {
    Type:         schema.TypeString,
    Optional:     true,
    Default:      "read",
    ValidateFunc: validation.StringInSlice([]string{"read", "read/write"}, false),
    ForceNew:     true,
},
```

The canonical write-tier value is the literal string `"read/write"` (with the slash). `access` is also `ForceNew` — any edit triggers destroy-then-create with a fresh token slug.

## 2. Bootstrap cycle: a workflow that consumes its own freshly-minted GH Actions secret is empty on the first run

GitHub Actions interpolates `${{ secrets.X }}` at **job-start** (when the runner is provisioned and receives its environment), not step-start. From <https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions>:

> When a workflow is triggered, GitHub injects the secrets you reference into the runner environment.

A `github_actions_secret` resource created mid-run by `terraform apply` lands in the GH repo's secrets store synchronously — but the runner's environment is already populated. The same workflow run sees `${{ secrets.DOPPLER_TOKEN_WRITE }}` as empty. Subsequent runs see the value.

The correct shape for this kind of in-band-minted secret is a **precondition guard step** that emits `::warning::` (not `::error::`) when the consumer's secret is empty, and gates the consumer step with `if: steps.<id>.outputs.skip_sync != 'true'`:

```yaml
- name: Verify DOPPLER_TOKEN_WRITE present
  env:
    DOPPLER_TOKEN_WRITE_CHECK: ${{ secrets.DOPPLER_TOKEN_WRITE }}
  run: |
    if [[ -z "$DOPPLER_TOKEN_WRITE_CHECK" ]]; then
      echo "::warning::DOPPLER_TOKEN_WRITE not yet present — expected on first apply that creates it."
      echo "skip_sync=true" >> "$GITHUB_OUTPUT"
    else
      echo "skip_sync=false" >> "$GITHUB_OUTPUT"
    fi
  id: doppler_write_check

- name: Sync …
  if: steps.doppler_write_check.outputs.skip_sync != 'true'
  …
```

Operator re-fires the workflow once after first merge via `gh workflow run <wf> --ref main -F reason='bootstrap'`. From the second run on, the consumer step runs normally.

Alternatives considered + rejected:

- **Pre-seed manually via `gh secret set DOPPLER_TOKEN_WRITE` before merge** — defeats the in-band-mint discipline of `hr-tf-variable-no-operator-mint-default` and risks state-vs-secret drift if the operator sets a different value than the resource produces.
- **Split into two jobs with `needs:` chaining the publish + consume** — adds structural complexity for a one-time bootstrap event; secret interpolation timing is per-job, so the second job's `${{ secrets.X }}` would see the freshly-minted value, but the consumer-job-needs-publisher-job ordering is rigid and noisy for the steady-state case.
- **`::error::` instead of `::warning::`** — would fail every first apply, eroding operator trust in the workflow's green/red signal.

## 3. Canonical precedent — `apps/web-platform/infra/kb-drift.tf:65-86`

The in-band-Doppler-service-token + github-actions-secret-publish pattern was first applied in PR-H (#3244) for the KB-drift cron worker, then re-applied in #4150 cleanup (removed 4 operator-mint variables). Post-#4195, this PR is the third invocation. The pattern is now load-bearing and explicitly endorsed by AGENTS.md rule `hr-tf-variable-no-operator-mint-default`.

Two diffs between `kb-drift.tf` and `doppler-write-token.tf`:

- `access = "read/write"` (not `"read"` — kb-drift is a read-only cron).
- `config = "prd_terraform"` (not `"prd_kb_drift_walker"`).

Everything else — `lifecycle` omission so rotation propagates, App-installation auth for `github_actions_secret`, header rotation comment shape — is verbatim.

## 4. Sharp edge: `key` is `Computed + Sensitive` and CANNOT be re-read after creation

```go
"key": {
    Type:        schema.TypeString,
    Computed:    true,
    Sensitive:   true,
},
// Read() comment: "`key` cannot be read after initial creation"
```

The token `key` lands in `terraform.tfstate` on create and is never re-fetched. State-loss is unrecoverable; recovery is `terraform apply -replace=doppler_service_token.write`, which mints a new token and orphans the old one. The orphan is still valid until manually revoked via `doppler configs tokens revoke --slug <slug>`. State storage posture: encrypted R2 backend (same as `doppler_service_token.kb_drift.key`).

## 5. Sharp edge: Doppler API allows duplicate token names within a project+config

`POST /v3/configs/config/tokens` does not enforce name uniqueness — uniqueness is the opaque slug. A pre-existing manual-mint token with the same name will not block a TF apply; the new resource mints a new token and orphans the old one. Phase 0 pre-check:

```bash
doppler configs tokens --project soleur --config prd_terraform --json \
  | jq -r '.[] | select(.name == "ci-tf-write") | "EXISTS:\(.slug)"'
```

If a row matches, revoke the orphan first.

## References

- Doppler provider source: <https://github.com/DopplerHQ/terraform-provider-doppler/blob/master/doppler/resource_service_token.go>
- GitHub Actions secrets timing: <https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions>
- AGENTS.md rule: `hr-tf-variable-no-operator-mint-default`
- Precedent file: `apps/web-platform/infra/kb-drift.tf`
- Sibling learning: `knowledge-base/project/learnings/best-practices/2026-05-20-tf-operator-mint-variables-are-design-smell.md`
