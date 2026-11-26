---
title: "Counsel review audit — #12971 (rundevoo.run zone onboarding): Art. 30 register scope note (parked domain + zone-scoped Cloudflare credential)"
type: counsel-review
date: 2026-11-19
issue: 12971
pr: 12968
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-11-19
signed_off_by: "CLO agent function run via subagent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED for the merge of PR #12968. Not external counsel. The register's out-of-scope conclusion is accurate on the in-scope test, and every credential claim checks against code."
non_blocking:
  - "N1 — The register note does not cross-reference domains.md's WHOIS/registrant posture (registrant org Jikigai SARL is the intended public disclosure; Cloudflare redacts personal contact data). A reader of the register alone would not see it; both are public in the same repo."
  - "N2 — 'Masked' is literal in the apply leg (::add-mask::) but effectual in the drift leg (env -i allowlist, no GITHUB_ENV write, literal redaction before the public-issue post). The claim stands in substance."
re_evaluation_triggers: "Any non-DNS resource type under infra/rundevoo-run/ OR a product surface on rundevoo.run (#12972 — the register itself re-applies the test then) OR a token scope change / new consumer of CF_API_TOKEN_RUNDEVOO OR mailboxes or mail-sending on the domain OR a personal-data-bearing record content"
---

# Counsel review audit — #12971 (rundevoo.run zone onboarding)

v1 internal counsel-review attestation under the ship gate (`brand_survival_threshold: single-user incident`). Authority: CLO agent function (Soleur-as-tenant-zero v1); operator veto retained. Output is draft material, not legal advice.

**Method.** Every register claim checked against code: `infra/rundevoo-run/{main.tf,zone.tf,dns.tf,variables.tf,bootstrap.sh,README.md}`, `.github/workflows/{apply-rundevoo-infra.yml,scheduled-terraform-drift.yml}`, `scripts/rundevoo-*.sh`, `scripts/encryption-posture-ledger.json`, `knowledge-base/operations/{domains.md,expenses.md}`.

## Artifact — article-30-register.md scope note (2026-11-19, #12971)

| Claim | Checked against | Verdict |
|---|---|---|
| Out-of-scope conclusion: DNS-only zone, no limb of the membership predicate | dns.tf (null MX `0 .`, `v=spf1 -all`, `v=DMARC1; p=reject`), zone.tf (`cloudflare_zone`, `cloudflare_zone_dnssec`); nothing else declared | TRUE — record contents are literals, no personal data processed |
| Token scope `Zone:Read + Zone:DNS:Edit + Zone:Settings:Edit`, limited to zone `4a16c6fc…` | bootstrap.sh permission-group resolution + `com.cloudflare.api.account.zone.$ZONE_ID` resource; import-block literal id | TRUE (API group names "Zone Read / DNS Write / Zone Settings Write" are the same groups) |
| Ephemeral 1h admin token, self-revokes on exit, revokes prior mint on re-run | `trap cleanup EXIT` → `cf_token_self_revoke`; revoke-on-remint block | TRUE |
| Stored only as `CF_API_TOKEN_RUNDEVOO` in Doppler `soleur/prd_terraform` | script constants; repo-wide grep — no other storage site | TRUE |
| Exactly two consumers (provider via `TF_VAR_cf_api_token_rundevoo`; set-equality probe via `CLOUDFLARE_API_TOKEN`), exported masked per-run | main.tf explicit `api_token` binding; both workflows' extract steps | TRUE (see N2) |
| Blast radius = rundevoo.run zone alone; soleur.ai probe must 4xx | mint policy resources; negative probe enforces 4xx (execution records 403) | TRUE |
| Minted token `soleur-tf-rundevoo-run`, id `dd84ecdf…`, no expiry | `TOKEN_NAME`; mint body carries no `expires_on` | TRUE — id is an identifier, not a secret |
| No token material in repo; state in encrypted R2; `cloudflare_zone` is `non_store_types` | grep (no committed secret); ledger diff | TRUE |

## Operations ledgers

domains.md (registrant Jikigai SARL, account `66d4f93f…` matching zone.tf literal, auto-renew hedged to post-merge G1 verify) and expenses.md ($21.20/yr recurring + one-time row): accurate and internally consistent.

## Decision record

**Decision:** DISCHARGED — no claim unsupported by code; no missing disclosure beyond N1.
