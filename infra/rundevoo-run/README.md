# infra/rundevoo-run

Terraform root for the `rundevoo.run` Cloudflare zone — parked domain for a
future Soleur test/product surface (issue #12971; the product shape is the
deferred follow-up #12972). Phase 1 ships a safe-by-default DNS posture only:

- RFC 7505 null MX (`MX 0 .`), `v=spf1 -all`, DMARC `p=reject`, DNSSEC.
- No site, no app, no mail-sending surface.

## Backend

R2 (`soleur-terraform-state`, key `rundevoo-run/terraform.tfstate`,
`use_lockfile = false` — R2 has no S3 conditional writes; the apply workflow's
`concurrency` group is the single-writer mechanism). Pattern copied from
`apps/cla-evidence/infra/main.tf`.

## Credential tiers

| Tier | Credential | Scope | Where |
|---|---|---|---|
| Persistent | `CF_API_TOKEN_RUNDEVOO` → `TF_VAR_cf_api_token_rundevoo` | Zone Read + DNS Write + Zone Settings Write on `rundevoo.run` only | Doppler `prd_terraform`; no default in `variables.tf` — fail closed |
| Ephemeral | `CF_ADMIN_TOKEN_BOOTSTRAP` (1h dashboard mint) | User → API Tokens → Edit + Zone → Zone → Read | bootstrap.sh only; trap-revoked on EXIT |

There is deliberately **no** `cloudflare_api_token` resource or
`data.cloudflare_api_token_permission_groups` in this root — that data source
needs `User → API Tokens → Read`, which the zone-scoped token lacks, and
declaring it makes every PR plan + drift run permanently red (the same reason
`apps/cla-evidence/infra` carries `.pr-plan-skip`; this root must plan under
the Tier-A credential).

DNSSEC is covered by **DNS Write** — `PATCH /zones/{id}/dnssec`'s accepted
permission per the API reference — not a separate group.

## Bootstrap

```bash
CF_ADMIN_TOKEN_BOOTSTRAP=<1h token> bash infra/rundevoo-run/bootstrap.sh
```

Mints the zone-scoped token (name `soleur-tf-rundevoo-run`), writes it to
Doppler `prd_terraform` as `CF_API_TOKEN_RUNDEVOO` with a byte-exact read-back,
and verifies coverage by live probe (GET zone/records/dnssec + a
create-delete TXT write probe + a negative probe against the soleur.ai zone
id). Re-run to rotate; the script revokes the previous same-named token and
self-revokes the admin token on EXIT.

**Cross-app coupling:** sources
`apps/cla-evidence/scripts/_cf-admin-token.sh` for the verify / self-revoke /
confined-curl helpers. If that file moves or is deleted, this script breaks —
update the `source` line and this note together.

## Apply path

The zone pre-exists (Cloudflare Registrar created it at purchase) and is
adopted by the committed `import {}` block in `zone.tf` with the literal zone
id — `terraform apply` from empty state reproduces zone + records with no
extra steps. Post-merge apply runs via
`.github/workflows/apply-rundevoo-infra.yml`; scheduled drift via the 4th
`scheduled-terraform-drift.yml` matrix leg, which also runs
`scripts/rundevoo-dns-set-equality.sh` (a refreshing plan cannot see
out-of-band *added* records — the REST whole-list probe covers that).

## Failure modes

- **Zone deleted/recreated:** the zone id changes; the committed `import {}`
  block hard-fails every plan until edited. Deliberate fail-closed — fix by
  updating the literal id in `zone.tf`.
- **Token revoked/expired:** drift + apply both fail on 401/403; re-run
  `bootstrap.sh` to rotate.
- **Out-of-band DNS edit:** drift plan (`-detailed-exitcode`) reds on changes
  Terraform manages; the set-equality probe reds on added records.
