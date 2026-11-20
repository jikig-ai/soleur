---
title: "infra(cloudflare): migrate Terraform to the new Soleur account and zone after the 2026-11-18 registration move"
date: 2026-11-18
slug: infra-cloudflare-migrate-terraform-to-soleur-account
branch: feat-one-shot-12931-cf-account-migration
issue: 12931
---

# infra(cloudflare): migrate Terraform to the new Soleur account and zone

## Enhancement Summary

**Deepened on:** 2026-11-19 (plan written 2026-11-18, plan-reviewed the same day).
**Sections enhanced:** 14. They are Phase 0, Phase 0c (new), Phase 1 items 7–12, Phase 2, Phase 3, Phase 5, Guard 1 and Guard 2, Architecture Decision (ADR/C4), Downtime & Cutover (new), Network-Outage Deep-Dive (new), Scope Check and Sharp Edges.
**Research agents used:**

- plan review: DHH, Kieran, code-simplicity, CTO devex;
- deepen: learnings-researcher, terraform-architect (local experiments on TF 1.10.5 plus cloudflare 4.52.7 with no network), security-sentinel, architecture-strategist (all three `.c4` files read in full), and a negative-claim plus self-audit sweep.

### Key improvements

1. **Phase-1 wedge removed.** `cloudflare_record.app` pulls the tunnel through `hcloud_server.web`, so its import moved to the tunnel phase.
2. **Rehearsal is real.** It runs in a scratch root with a `backend "local"` override, measured working with an `s3` main backend. The earlier `-state=` fallback was ignored under s3 and is deleted.
3. **Gate sees what TF silently drops.** These were measured on TF 1.10.5:
   - imports outside `-target` vanish without warning;
   - a `-replace` outside `-target` is dropped;
   - a multi-address `state rm` skips missing addresses and still exits 0.

   Guard 1 and Guard 2 now assert pure imports, `replace_by_request`, physical ids and the removed count.
4. **Security.**
   - Apply legs run under the reviewer-gated `web-platform-infra-apply` environment.
   - Token values never reach a transcript: no Playwright snapshot, hash-compared verification.
   - `_NEXT`/`_PREV` copies and the temporary token are short-lived.
   - The deploy-policy exception checks name, expiry, decision, include set and app.
5. **C4 and ADR completeness.** There are 6 falsified `model.c4` descriptions, not 2, plus the `model.likec4.json` regeneration CI enforces. ADR-329 amends ADR-068 and ADR-321.

### New considerations discovered

- Branch Doppler configs keep their own copies, so the runtime ids and tokens are written per config (CTO devex plus learning `2026-10-19-doppler-branch-config-does-not-inherit-new-keys…`).
- The CLA-evidence bootstrap reads `CF_ACCOUNT_ID` for an object-locked R2 bucket, so it now reads `CF_R2_ACCOUNT_ID`.
- An optional early-noindex step (Phase 0c) closes the indexability window before PR1 merges. It is an operator decision.
- `cloudflare_zone_settings_override` has no importer. A future destroy reverts to the new zone's hand-restored snapshot.

## Overview

The soleur.ai zone moved to a new Cloudflare account and zone on 2026-11-18. The site, app and sign-in were restored by hand; Terraform still points at the old zone and account. This plan moves the Terraform root onto the new zone and account in phases: the redirect and SEO rulesets first (pure Cloudflare edge config), then the tunnel, Access applications and the deploy/ssh/registry hostnames, then the remaining token and secret re-points.

## Research Insights

### Premise Validation

- #12931 is OPEN (verified `gh issue view 12931`, 2026-11-18). The only open PR naming it is #12932, which is this branch's own draft PR (head `feat-one-shot-12931-cf-account-migration`), so it is not a duplicate. `collision-precheck.sh` also listed two `test-all.sh` processes in other worktrees (`feat-12866-bastion-host`, the bare checkout): unrelated test runs, not duplicate work.
- Open PR #12873 (`feat-12866-bastion-host`, draft) also edits `.github/workflows/apply-web-platform-infra.yml`. Expect a rebase conflict in the `apply_target` options list; whichever lands second rebases. This PR is the P1 incident fix and should land first.
- **Live state re-measured 2026-11-18 (read-only API calls):**
  - Old zone `5af02a2f…` reports `status=moved`, plan `Pro Website`. **It is still readable** with the old `CF_API_TOKEN` and `CF_API_TOKEN_RULESETS` (DNS list and the `http_request_dynamic_redirect` entrypoint both return `success:true`). So resources not yet migrated still refresh as no-ops against it.
  - Old tunnel `fc4509ed…` (old account) is `healthy` with 4 connections. That is web-2's cloudflared, which still holds the old tunnel token.
  - New zone `951ce525…`: DNSSEC `disabled`. The public DS lookup for `soleur.ai` (DoH) returns no DS, so the chain is consistent today. NS are `laila`/`lennon`.
  - The new zone holds 39 records against 30 `cloudflare_record` resources in `dns.tf`. **`ssh` and `registry` each carry THREE proxied A records** (`104.26.10.163`, `104.26.11.163`, `172.67.73.132`, the Cloudflare anycast answers the move's DNS scan captured), not one. The old zone held one proxied CNAME to `fc4509ed-….cfargotunnel.com` for each of `deploy`, `ssh` and `registry`. The other extra records (`76624499` CNAME, `send.outbound` MX/TXT, `resend._domainkey.outbound`, two apex TXT) also existed in the old zone, and Terraform did not manage them there either.
  - The new account holds 0 tunnels. The temporary token gets 10000 on zone rulesets and on account LB pools. Its scope matches the issue.
  - Doppler `prd_terraform` `CF_ZONE_ID` and `CF_ACCOUNT_ID` still hold the old ids (prefix-checked).
- **Premise corrections (issue claim vs reality):**
  - "Re-mint every Terraform-minted Cloudflare token (`cf-cert-reissue-token.tf`, `token-drift-read-tokens.tf`, `web-probe-read-token.tf`, `cf-pages.tf`)". The root has **no `cloudflare_api_token` resource**. Every Cloudflare token Terraform uses is operator-minted and only republished: `cf-cert-reissue-token.tf` publishes `var.cf_api_token_dns_edit` into `prd` (the header says `cloudflare_api_token` 403s with 9109), `cf-pages.tf` publishes `var.cf_api_token_pages` to a GitHub Actions secret, and `token-drift-read-tokens.tf` / `web-probe-read-token.tf` mint **Doppler** service tokens, not Cloudflare ones. So "re-mint" means minting new dashboard tokens on the new account, writing them to Doppler, then letting the republishing resources carry them.
  - "Rotate the GitHub Actions secrets `CLOUDFLARE_API_TOKEN_PAGES` and `CLOUDFLARE_ACCOUNT_ID_PAGES`". Both are Terraform resources (`github_actions_secret.cloudflare_api_token_pages` and `.cloudflare_account_id_pages`, `cf-pages.tf`), and both are in the merge apply's stage-1 `-target` list. They follow automatically once `CF_API_TOKEN_PAGES` and the account id change. No hand rotation is needed.
  - "Change `cf_zone_id` and `cf_account_id` (`variables.tf`)". Neither variable has a default. Both come from Doppler `prd_terraform` `CF_ZONE_ID` / `CF_ACCOUNT_ID` through `--name-transformer tf-var`. **Flipping `cf_account_id` as-is would re-home three R2 buckets** (`cloudflare_r2_bucket.workspaces_luks_header`, `.workspaces_luks_header_web`, `.terraform_state_privileged`, all `account_id = var.cf_account_id`). R2 did not move: the state backend endpoint is the old account (`main.tf` backend `endpoints`) and so are the LUKS header buckets. A blind flip would plan those buckets for destroy-and-recreate in the new account. **This is the single most dangerous edge in the migration.**

### Mechanism facts measured

- **An `import {}` block is silently ignored when its `to` address is already in state.** Measured locally with Terraform 1.17.2 and `random_string` (apply, then add `import { to = random_string.x, id = "differentid" }`): the plan reports `No changes`. CI pins 1.10.5, and this behaviour dates from 1.5. Consequence: import blocks alone cannot re-point the old-zone entries. Each must leave state first, by a forget and never a destroy, because the old zone must not be mutated and `zone_id`/`account_id` are ForceNew.
- **The tunnel token reaches the host only at creation.** `server.tf` sets `tunnel_token = cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token` in the `cloud-init.yml` templatefile. `cloud-init.yml` runs `cloudflared service install ${tunnel_token}` under `%{ if web_tunnel_connector ~}`, and the connector is `web-2` (`variables.tf` `web_hosts`, `tunnel_connector = true`; ADR-304). `hcloud_server.web` has `ignore_changes = [user_data, …]`. A new tunnel token therefore reaches a host only through a fresh create, which is the `web-host-replace` dispatch for `web-2`. Doppler `prd_terraform` `CF_TUNNEL_TOKEN` has no consumer (ADR-241 records the repo-secret copy as an orphan).
- **The `web_host_replace` job does not ride the tunnel.** It pins the image from web-1 `/health` (over `app.soleur.ai`) or from the `image_tag` input. The fresh host pulls its seed image from zot over the private network (`10.0.1.30:5000`). Its plan gate (`tests/scripts/lib/web-host-replace-gate.sh`) refuses ANY change outside the four allow-listed addresses. **So the new tunnel must already be in state before the replace runs.** Otherwise `-target` pulls the tunnel create into the plan as a dependency, and the gate aborts.
- **The merge-triggered `apply` job does ride the tunnel.** After its stage-1 targeted apply it runs `Verify tunnel ingress origins are live` (`scripts/verify-tunnel-ingress-origin.sh`: `CF_ACCOUNT_ID` plus the tunnel id from state, then a `deploy-status` curl through `deploy.soleur.ai` with the Tier-B CF Access pair). It then syncs the CI-SSH token and runs the `cf-tunnel-ssh-bridge` SSH-provisioner stage. That job fails today at the verify step because `deploy.` has no record. This is the chicken-and-egg the brief named: the routine apply path cannot repair the tunnel it depends on.
- **Gates a migration plan trips** if it goes through the merge apply: `tests/scripts/lib/deploy-policy-gate.sh` HALTs with no ack on any create of `cloudflare_zero_trust_access_policy.deploy_service_token`, and the new account needs exactly that create. The `apex_move_orphans` guard, the pre-apply entrypoint gate (which reads `CF_ZONE_ID`) and the destroy guard (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`) all inspect the same plan.
- **Write-once Doppler copies.** `doppler_secret.registry_push_access_token_id/_secret` (tunnel.tf) and `doppler_secret.cf_api_token_dns_edit` carry `ignore_changes = [value]`. A recreated token does NOT update them. They need an explicit `-replace` in the same apply, or a direct Doppler write.
- **The deploy Access service token is unmanaged** (`removed { destroy = false }`, ADR-241 D10). Its id is the committed `local.deploy_service_token_ids`. The pair lives only in Doppler `soleur-infra-privileged/prd`. The new account needs a newly minted token, and its id replaces the old one in the local.
- **Free plan fit** (the old zone was Pro at $0, per the expense ledger and COO): `seo_page_redirects` holds 10 rules, which equals the Free dynamic-redirect cap. `seo-rulesets.tf` already cites that cap. Transform has 4, config 3, cache 1, custom WAF 1, and the account bulk-redirect ruleset 2 rules over 2 lists (158 items). `cloudflare_bot_management.soleur_ai` sets `sbfm_definitely_automated` and `sbfm_verified_bots`, which are Super Bot Fight Mode fields (Pro+). The five old-zone `kind=zone` rulesets (snapshot phases, read without copying content) map 1:1 to the five TF zone rulesets. No managed-WAF entrypoint was deployed on the old zone.
- **The `seo_config_settings` import block is pinned to the OLD ruleset id** (`zone/${var.cf_zone_id}/a21ac79d…`, gated by `var.adopt_seo_config_entrypoint`, default true). Once the zone id changes, it would try to import a ruleset that does not exist in the new zone.
- **Origin CA certificate (latent).** `app.soleur.ai` terminates TLS in the container with a Cloudflare Origin CA certificate (ADR-321) that was minted against the old zone (`scripts/mint-origin-ca-cert.sh` uses `CF_ZONE_ID`, token `CF_API_TOKEN_ORIGIN_CA` in `soleur-infra-privileged/prd`). If Cloudflare revokes a zone's Origin CA certificates when it deletes the zone at grace end, `app.soleur.ai` would 526 under `ssl=strict`. The plan re-mints it from the new zone before the old zone can be deleted.

### Consumers of the zone and account ids (repo-research inventory)

- Follow Doppler with no code change: the stage-1 targets, `verify-tunnel-ingress-origin.sh`, `scheduled-inngest-health.yml` (tunnel connector census by name in `CF_ACCOUNT_ID`), `cf-lb-overlay.yml`, `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`, and `scripts/mint-origin-ca-cert.sh`.
- Runtime (`soleur/prd` and its inheriting branch configs `prd_cla`, `prd_ghcr`, `prd_git_data`, `prd_kb_drift_walker`, `prd_scheduled`, `prd_workspaces_luks*`): `CF_ZONE_ID`, `CF_API_TOKEN_PURGE` (`apps/web-platform/server/cf-cache-purge.ts`) and `CF_API_TOKEN_DNS_EDIT` (`cron-gh-pages-cert-reissue.ts`). `dev`, `dev_personal` and `dev_scheduled` hold `CF_ZONE_ID` with `CF_API_TOKEN_AUDIT`. Container env is frozen at `docker run`, so the runtime picks the new values up at the next release or redeploy, which needs the deploy host back.
- Hardcoded literals: `plugins/soleur/agents/engineering/infra/infra-security.md` (old zone and account literals); `.github/workflows/deploy-docs.yml` `PROBE_URL: https://soleur-docs.pages.dev/version.txt` (the new project is `soleur-docs-40x.pages.dev`); `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (`ACCOUNT=4d5ba6…`). The R2 endpoint literal in 8 TF backends, the 3 provisioning-skill templates and `apps/cla-evidence` **stays**, because R2 does not move.
- Tests pinning ids: `apps/web-platform/test/seo-config-rules.test.ts` (`ADOPTED_RULESET_ID = a21ac79d…`), `tests/scripts/fixtures/tfplan-origin-tls-*.json` (same id), and `tests/scripts/fixtures/tfplan-web-platform-real-baseline.json` (old ids as captured data; re-capture is not needed unless an assertion compares id values).
- The `lb-staging` root has its own `cf_zone_id`/`cf_account_id` and LB copies. It is out of scope for the first slices (see Non-Goals).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-27-an-import-block-breaks-terraform-test-and-a-count-ack-reaches-every-destroy.md`: an `import` block reaches the real provider even under `terraform test` with mock providers (hence `var.adopt_seo_config_entrypoint`). The new import blocks must be gated the same way, or `infra-validation.yml`'s credential-free leg dies with 10000.
- `knowledge-base/project/learnings/2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`: the pin is v4. Use `cloudflare_record`, `ingress_rule` and `secret`, and import-id shapes of the v4 family (`zone/<zone>/<ruleset>` singular for rulesets, `<zone>/<record>` for records, `<account>/<project>` and `<account>/<project>/<domain>` for Pages, `<account>/<list>` for lists).
- `knowledge-base/project/learnings/2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md`: apex names stay FQDN (already the case in `dns.tf`).
- `knowledge-base/project/learnings/2026-07-20-terraform-plan-cannot-see-what-a-whole-list-resource-destroys.md` and the `cloudflare-whole-list-entrypoint-audit.md` runbook (ADR-136): GET every new-zone phase entrypoint before a `kind = "zone"` ruleset is created there. The hand restoration may have left an entrypoint the plan cannot see.
- `knowledge-base/project/learnings/2026-07-20-a-plan-can-prescribe-a-resource-its-credential-cannot-create.md` and `knowledge-base/engineering/operations/post-mortems/2026-07-24-cf-token-config-rules-scope-gap-postmortem.md`: probe every phase each new token must WRITE before the apply. A GET proves read, not edit (ADR-130 four-probe set).
- `knowledge-base/project/learnings/2026-06-09-cloudflare-bulk-redirects-v4-schema-and-phase-order.md`: v4 list items use `"enabled"`/`"disabled"` strings, and `from_list` must reference the list resource.
- `knowledge-base/project/learnings/2026-05-29-verify-redirect-ownership-before-codifying-in-terraform.md` and `…redirect-rule-host-match-vs-canonicalizer-phase-ordering.md`: verify www→apex with a live `curl -sIL` hop chain after apply.
- `knowledge-base/engineering/architecture/decisions/ADR-304-tunnel-connector-placement-lives-on-a-replaceable-host.md`: the connector lives on web-2, and its flip is create-time only. `knowledge-base/project/learnings/security-issues/2026-10-27-cloudflared-emudhra-connector-migration-not-in-place-patch.md`: never patch cloudflared in place; migrate the connector.
- `knowledge-base/engineering/operations/runbooks/cloudflare-service-token-rotation.md`: the deploy token is minted outside Terraform, written straight into `soleur-infra-privileged/prd` without printing, and its id is admitted through `local.deploy_service_token_ids`.
- `knowledge-base/project/learnings/2026-03-21-cloudflare-service-token-expiry-monitoring.md`: the expiry notification policy is per account and must be rebuilt.
- `knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md`: runtime `CF_ZONE_ID` needs a fresh container.
- `knowledge-base/project/learnings/2026-07-03-dark-launch-pr-must-exclude-operator-prerequisite-infra.md`: infra that depends on operator-minted prerequisites (new tokens, ids) must not ride a merge that the per-PR apply runs.

### CLAUDE.md / AGENTS conventions in force

`hr-prod-host-config-change-immutable-redeploy` and `hr-no-ssh-fallback-in-runbooks` (the host change goes through `web-host-replace`), `hr-all-infrastructure-provisioning-servers` (no dashboard clicks except token mints, which have no API path because no Soleur token holds API Tokens:Edit, ADR-130), `hr-menu-option-ack-not-prod-write-auth` (each dispatch and Doppler write waits for a typed, command-naming go), `hr-tf-variable-no-operator-mint-default` (new token variables have no default), `hr-dispatch-async-must-arm-watch`, `hr-observability-layer-citation`, `hr-bulk-delete-per-item-live-infra-role-check` (the six broken A records are deleted by pinned id with a per-item type/content check).

### Property List (Phase 0.6b)

- P1: the four Better Stack 301 monitors and the `X-Robots-Tag: noindex` header on app/api/deploy/RSS recover. Edge rulesets and bulk redirects serve from the new zone and account.
- P2: `deploy.`, `ssh.` and `registry.soleur.ai` serve through a tunnel the new account owns, so deploys and CI registry pushes work.
- P3: the deploy path stays recoverable throughout, with no step needing SSH or a host the step itself is repairing.
- P4: Terraform plans cleanly against the new zone and account, with every hand-restored object under management and no old-zone object ever destroyed or mutated.
- P5: R2 state and LUKS-header buckets stay where they are, untouched.
- P6: every runtime and CI consumer reads the new zone and account ids and tokens. The temporary token is revoked.
- P7: the post-mortem flips to `resolved` only on measured monitor recovery.

### Cut List (Phase 0.6b)

- "Rotate GitHub Actions secrets `CLOUDFLARE_*_PAGES` by hand" → P6 → already covered by `github_actions_secret.cloudflare_api_token_pages` / `.cloudflare_account_id_pages` (cf-pages.tf) once the inputs change. Cut as a manual step.
- "Re-mint Terraform-minted tokens" → P6 → there is no Terraform-minted Cloudflare token. Replaced by "mint new-account dashboard tokens, write to Doppler", and the republishing resources carry them.
- "Load balancer in the new account" (`cloudflare-lb.tf`) → no property in P1–P7 needs it (`app.soleur.ai` serves from a plain proxied A record, LB weight on web-2 is gated). It needs paid Load Balancing. Cut to a count-gated, off-by-default shape. The purchase is an operator money decision (see decision-challenges).
- "Copy old-zone snapshots into the repo" → no property. Terraform config is already the source of truth for every ruleset. Snapshots are used only for read-only parity diffs and never committed.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Codebase reality | Plan response |
|---|---|---|
| "Re-mint every Terraform-minted Cloudflare token" | The root has no `cloudflare_api_token` resource. Every CF token is operator-minted (dashboard) and republished by Terraform. | Phase 0 mints the new-account tokens (F11 table) into Doppler. The republishing resources carry them on the phase applies. |
| "Change `cf_zone_id` and `cf_account_id` (`variables.tf`)" | Neither has a default. Values come from Doppler `prd_terraform`. `cf_account_id` also homes three R2 buckets and the LUKS escrow endpoint, and R2 did not move. | A new `var.cf_r2_account_id` (no default) takes every R2 surface. Validations reject the old ids. The Doppler flip is a Phase 2 step, not a code edit. |
| "Rotate GH secrets `CLOUDFLARE_*_PAGES` by hand" | Both are `github_actions_secret` resources in `cf-pages.tf`. | Re-applied in the `zone-rest` phase. No hand rotation. |
| "`ssh` and `registry` hold A records" (singular) | Each name carries three proxied A records, six in total. | F5: a pinned read-then-delete step removes the six by id before the tunnel-phase plan. |
| "Terraform must import the hand-restored objects" | An `import {}` block is ignored while its address is still in state (measured on TF 1.17.2). | F1: forget old-id entries with one state-derived `terraform state rm` (backup first), then import them by new id. |
| "The tunnel move needs a host-side cloudflared token change" | The token is baked into user_data at create time, on web-2 only. `web-host-replace` refuses any out-of-scope change. | The tunnel phase creates the new tunnel first. Then `web-host-replace web-2` re-renders user_data with the new token. |
| "Load Balancing needs a subscription" | The LB resources are unconditional and account-scoped. | F6: count-gated by `var.cf_load_balancing_enabled = false`. The purchase is an operator money decision. |
| (not in issue) `cloudflare_bot_management` on Free | The `sbfm_*` fields are Pro-only. | F7: null unless `var.cf_zone_plan_pro`. |
| (not in issue) DNSSEC | `cloudflare_zone_dnssec` is unconditional. The new zone is unsigned, with no DS. | F10: count-gated off and tracked by a follow-up issue. |
| (not in issue) Origin CA certificate | `app.soleur.ai` serves an Origin CA certificate minted against the old zone. | Phase 3 re-mints it from the new zone before the release redeploy, well inside the old zone's grace period. |

## Problem Statement

Since 16:24 UTC on 2026-11-18 the soleur.ai zone has lived in a new Cloudflare account, and Terraform still addresses the old one. Four user-visible surfaces are degraded:

1. 157 legacy and legal URLs, plus `www.soleur.ai`, no longer return a 301. Four Better Stack monitors are red.
2. `app.soleur.ai`, api, deploy and the RSS feed lost `X-Robots-Tag: noindex`, so `app.soleur.ai` is indexable. The AI-crawler WAF allowlist is also gone.
3. `deploy.soleur.ai` has no record. `ssh.` and `registry.` resolve to Cloudflare IPs and return Error 1000. Web-platform deploys, the CI SSH bridge and CI registry pushes are blocked.
4. Docs CI deploys to the old account's Pages project, so `soleur.ai` stays on build `7e1d286`.

The routine apply path, the push-triggered `apply` job in `apply-web-platform-infra.yml`, cannot repair any of this. It targets the old ids. Its post-apply verification rides the dead tunnel. Its deploy-policy gate HALTs on the policy create the migration needs.

## Proposed Solution

Move the root to the new account with **one flip of the Doppler ids**, protected by a **state-forget-then-import** migration that runs only through a **dedicated, gated dispatch target**. The work ships in **two PRs** (CTO F4), plus a small cleanup PR.

- **PR1 (this branch): redirects first.** The variable split, the R2 carve-out, the free-plan shapes, the migration machinery, and the first two phases (`redirects-dns`, `zone-rest`). It merges with `[skip-web-platform-apply]`. Operator-authorized dispatches then restore:
  - the redirects;
  - the noindex header;
  - the WAF allowlist, cache rule and config rules;
  - Terraform management of every hand-restored DNS record and of the Pages project.
- **PR2 (a new branch from `main` after PR1 merges): deploy hosts.** The tunnel phase: a new tunnel, Access apps, policies, service tokens, CNAMEs, and a pinned A-record pre-delete. Then `web-host-replace web-2` delivers the new tunnel token through the immutable redeploy path.

### The chicken-and-egg, and how this plan avoids it

- The deploy webhook, the SSH bridge and the registry push all ride the tunnel. The routine merge apply also verifies through `deploy.` and provisions over `ssh.`. **No step of this migration uses any of them.** The `cf-account-migrate` job talks only to the Cloudflare API: no bridge, no SSH, no `deploy-status` probe.
- The host-side half, `web-host-replace web-2`, also rides no tunnel. Its image tag comes from `app.soleur.ai/health` or the `image_tag` input, and its seed pull comes from zot over the private network. Its gate needs the new tunnel already in state, which the tunnel phase guarantees.
- **web-1 is never touched.** The new ingress rules keep the same private-IP origins (`10.0.1.10:9000`, `10.0.1.10:22`, `10.0.1.30:5000`), so a connector on a freshly booted web-2 serves all three hosts at once.
- **Recovery if web-2's replace fails:** web-1 keeps serving `app.soleur.ai` from its plain A record, which this work does not touch. The deploy path is already down, so nothing regresses. The `web-host-replace` dispatch can be re-run. web-1 is never re-imaged or changed in place.

## Technical Approach

### Architecture

```text
Doppler prd_terraform                      Terraform root apps/web-platform/infra
  CF_ZONE_ID      old -> 951ce525…   ->    var.cf_zone_id      (validation: != 5af02a2f…)
  CF_ACCOUNT_ID   old -> 66d4f93f…   ->    var.cf_account_id   (validation: != 4d5ba6f0…)
  CF_R2_ACCOUNT_ID (new key) = 4d5ba6f0… -> var.cf_r2_account_id (R2 buckets + local.r2_s3_endpoint)
  CF_API_TOKEN*   re-minted on new acct  -> provider "cloudflare" + aliases (r2 alias unchanged)

cf-account-migrate (dispatch, environment infra-privileged, main-only)
  phase=redirects-dns : state backup -> one atomic state rm (every non-R2 cloudflare_* entry with an old id) ->
                        plan -target={5 zone rulesets, 2 lists, account ruleset,
                                      26 DNS records (import; NOT app), pages project + 2 domains (import),
                                      doppler_secret.cf_zone_id_prd}
                        -> phase gate -> apply -> curl verification
  phase=zone-rest     : plan -target={zone_settings_override, bot_management,
                                      github_actions_secret x2,
                                      doppler_secret.cf_api_token_dns_edit (-replace)} -> gate -> apply
  phase=tunnel (PR2)  : pinned 6-record pre-delete -> plan -target={random_id (-replace), tunnel, config, app record (import),
                        3 apps, 3 policies, 2 tokens, notification policy, deploy/ssh/registry CNAMEs,
                        doppler_secret.registry_push_* (-replace)} -> gate -> apply -> CI-SSH token sync
then  web-host-replace web_host_key=web-2   (fresh user_data carries the new tunnel token)
then  manual-rerun apply                    (routine path green again; in-progress refusal lifts)
```

**The migration-complete predicate (F3)** is computed from state, never from a flag. The migration is complete when two things hold:

- no `cloudflare_*` resource in state carries `zone_id == 5af02a2f…` or a non-R2 `account_id == 4d5ba6f0…`;
- `cloudflare_zero_trust_tunnel_cloudflared.web` is in state with `account_id == var.cf_account_id`.

While the predicate is false, every plan-capable job of `apply-web-platform-infra.yml` except `cf_account_migrate` (and `web_host_replace web-2` once the tunnel is in state) fails with `verdict=cf-account-migration-in-progress`. `scheduled-terraform-drift.yml` is not gated; its red is expected. The `cf-account-migrate` job is the only planner. The full definition is in Phase 1 item 11.

### Implementation Phases

#### Phase 0 — Credentials and ids (prerequisite to any dispatch; no repo change)

1. **Mint the new-account tokens.** `Operator-authorizes:` the mints, done in the operator's signed-in dashboard session and driven by Playwright through the `cf-token-scope` skill flow. No API path exists, because no Soleur token holds API Tokens:Edit (ADR-130). Each value goes straight into Doppler `soleur/prd_terraform` from the browser flow and is never printed.

   Permission groups per token (CTO F11: one token per key, no merges):

   | Doppler key (`prd_terraform` unless noted) | Permission groups on the NEW account / zone `soleur.ai` (951ce525…) |
   |---|---|
   | `CF_API_TOKEN` | Account: Cloudflare Tunnel:Edit, Access: Apps and Policies:Edit, Access: Service Tokens:Edit, Notifications:Edit, Account Settings:Read. Zone: DNS:Edit, Zone:Read. Add Load Balancing: Monitors and Pools:Edit + Load Balancers:Edit only if `cf_load_balancing_enabled` is ever turned on. |
   | `CF_API_TOKEN_ZONE_SETTINGS` | Zone: Zone Settings:Edit |
   | `CF_API_TOKEN_RULESETS` | Zone: Single Redirect Rules:Edit, Transform Rules:Edit, Config Rules:Edit (the UI spells it `Config Rules`), Cache Rules:Edit, Zone WAF:Edit. Account: Account Rulesets:Edit, Account Filter Lists:Edit. |
   | `CF_API_TOKEN_BOT_MANAGEMENT` | Zone: Bot Management:Edit |
   | `CF_API_TOKEN_PAGES` | Account: Cloudflare Pages:Edit only. It must 403 on `/zones/<id>/rulesets`. |
   | `CF_API_TOKEN_DNS_EDIT` (runtime, republished to `prd`) | Zone: DNS:Edit, new zone only |
   | `CF_API_TOKEN_PURGE` (runtime, at the `prd` root, inherited by `prd_*`) | Zone: Cache Purge:Purge, new zone only |
   | `CF_API_TOKEN_ACCESS_MINT` (new, PR2 only, revoked after use) | Account: Access: Service Tokens:Edit only |
   | `CF_API_TOKEN_R2` | **Not re-minted.** It stays on the old account. |
   | `CF_API_TOKEN_ORIGIN_CA` (`soleur-infra-privileged/prd`, Phase 5) | Zone: SSL and Certificates:Edit, new zone |

   **Mint hygiene (security review):**
   - Scope every token to the specific new account and the `soleur.ai` zone only, never "all zones" or "all accounts", and give it an expiry. The default is 90 days for the provider tokens and 7 days for `CF_API_TOKEN_ACCESS_MINT`.
   - **Hand-off (CTO L75, re-ruled on 2026-11-18 evidence).** Mint with `browser_run_code_unsafe`: the Node-side `page.evaluate` creates the token through `/api/v4/user/tokens` (session `x-atok`), and `page.request.post` hands the value to a one-shot python sink bound to `127.0.0.1` that writes a mode-0600 file in the session scratchpad, outside every git work tree. The tool result prints only the token id, the sink status and the length. Bash pipes the file into Doppler on stdin, shreds it, and confirms with `/user/tokens/verify` without printing the value. `browser_evaluate` with `filename` is banned for secrets: on 2026-11-18 it wrote relative to the MCP server's working directory, inside the main repository. After each mint, `git status --porcelain` in the main checkout and the worktree must show no new untracked file. No `browser_snapshot` or screenshot after "Create Token". On any failure, delete that token and re-mint, or fall back to an operator paste.
   - Each token also gets **deny probes**: it must be refused on the old account and old zone, and on one permission group it must not hold.
   - `CF_API_TOKEN_ACCESS_MINT` stays separate from `CF_API_TOKEN` even though the latter holds Access: Service Tokens:Edit. The mint script runs on the agent's machine, and `CF_API_TOKEN` (Tunnel, Access apps and policies, DNS) must never be exported there (CTO F8).
   - The probe must see `success:true` and a parsed `.result` before treating any entrypoint as present or empty, and each phase profile includes one known-present control endpoint, so a degraded `200` or a 404 is never read as "empty" (learning `2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-…`).

   Phase 5 re-scopes the read-only and audit tokens (`CF_API_TOKEN_AUDIT` in `dev*`, `_ANALYTICS_READ`, `_PAGERULES_READ`, `_DNS_RULESETS`, and the duplicate `_BOTMANAGEMENT`) after a consumer census. None of them blocks a phase.

2. **Write-probe every token before its phase's dispatch.** A GET proves read access only (ADR-130; the `2026-07-24-cf-token-config-rules-scope-gap` post-mortem). **Probes never mutate** (plan review). A `PUT` to an absent phase entrypoint would create an empty ruleset that the Terraform create then collides with, and a `PUT` to a present one replaces its rules. Each write probe sends a deliberately invalid body: `400` means authorized, `403`/`10000` means denied. It never `PUT`s a valid body to an entrypoint and never `DELETE`s. **Probe safety (CTO L49):** the invalid body is one fixed literal that can never validate (never `{"rules":[]}`, which would wipe a live entrypoint); any `2xx` response is a fatal abort followed by an immediate read-back of that entrypoint; and each profile first proves, with a known-denied token, that the endpoint answers `403` before `400`, otherwise a `400` does not count as authorized.
   - The rulesets token is probed on every phase entrypoint it must write: `http_request_dynamic_redirect`, `http_response_headers_transform`, `http_config_settings`, `http_request_cache_settings`, `http_request_firewall_custom`, account `http_request_redirect`, and `/accounts/<new>/rules/lists`.
   - The same probe doubles as the whole-list audit (ADR-136). A 404 on an entrypoint means no hand-made entrypoint exists there. Any entrypoint that already exists in the new zone is recorded by id and imported, never overwritten blind.
   - No new probe script. The probe sets become profiles on the existing `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh` (it already runs fail-closed rulesets and default-token probe sets), parameterised by account and zone id plus a `--phase` set. The agent runs it once per phase, before that phase's rehearsal, and records the verdict lines in the PR thread. It is not a job step on every dispatch.
   - **Phase 0a / 0b (CTO devex).** 0a mints and probes only what `redirects-dns` needs (`CF_API_TOKEN` for DNS and Doppler-adjacent records, `CF_API_TOKEN_RULESETS`, `CF_API_TOKEN_PAGES`). 0b (`_ZONE_SETTINGS`, `_BOT_MANAGEMENT`, `_DNS_EDIT`, `_PURGE`) runs while the first dispatch is in flight. If a `-target` plan still configures an unused provider alias and fails on its stale token (unverified), the agent mints 0b first.

3. **Doppler writes.** The agent runs these after a typed, command-naming go. Every write pipes the value on stdin and uses `--silent` with stdout to `/dev/null`. **Verification never prints a secret** (security review): compare `sha256sum` of source and destination (for example `doppler secrets get K --plain … | sha256sum`), and print at most an 8-character prefix for non-secret ids. Copies (`<KEY>` → `<KEY>_PREV`) are direct `get --plain | set` pipes, never via a shell variable or argv.
   - `prd_terraform` `CF_R2_ACCOUNT_ID=4d5ba6f096b2686fbdd404167dd4e125` is a new key. It must land **before PR1 merges**, because the variable has no default (ADR-065 sequencing).
   - **New token values go into staging keys, never over the live ones** (plan review). Write them as `<KEY>_NEXT` (for example `CF_API_TOKEN_RULESETS_NEXT`) in `prd_terraform`. Overwriting `CF_API_TOKEN*` while `CF_ZONE_ID`/`CF_ACCOUNT_ID` still hold the old ids would break every real-credential plan of this root and destroy the rollback values.
   - `CF_ZONE_ID`, `CF_ACCOUNT_ID` and every `<KEY>` ← `<KEY>_NEXT` swap **in one agent-run sequence after PR1 merges, immediately before the first dispatch** (Phase 2 step 2). The old values are first copied to `<KEY>_PREV`, for the runbook's Halt restore, which is valid only before the first `redirects-dns` apply (CTO ruling D4, 2026-11-19). These writes are the stages of the generated `bootstrap.sh` in the #12931 spec directory (CTO ruling D11), never a hand-typed sequence.
   - **Short lifetimes (security review).** The tf-var transformer exports every `prd_terraform` key into every job of this root, so these copies are not left around:
     - `<KEY>_NEXT` is deleted right after the swap.
     - Once the `redirects-dns` apply is verified, `Operator-authorizes:` revoke the superseded old-account non-R2 tokens and delete the token `_PREV` keys. The id `_PREV` keys may stay until cleanup; they are not secrets. After that point nothing is restored: the migration halts at the last verified phase and fixes forward (CTO ruling D4). Each revoke uses the runbook's revoke recipe (token id via `/user/tokens/verify`, dashboard-session delete, read-back that the verify fails, then the key delete).
     - `CF_API_TOKEN_SOLEUR_ACCT` (the temporary token) is revoked as soon as Phase 0a is minted and probed, not in Phase 5 (COO plus security).

4. **Stop the runtime from writing to the moved zone** (CTO risk). This runs at Phase 2 step 2, right after the swap, not before it. `cron-gh-pages-cert-reissue` holds the old `CF_ZONE_ID` and the old `CF_API_TOKEN_DNS_EDIT` in its frozen container env. `Operator-authorizes:` revoke the old-zone "Edit zone DNS" token with the runbook's revoke recipe once the bootstrap's `branch-copies-tokens` stage has put the new token in every holder (runbook Phase 2 step 3). The cron then fails closed as `precondition_blocked`, by design (see the `cf-cert-reissue-token.tf` header). Revoking a user token mutates no zone.

#### Phase 0c — Optional early noindex (operator decision; before PR1 merges)

`app.soleur.ai` stays indexable, including `/shared/[token]` and `/invite/[token]`, until the `redirects-dns` apply, and PR1 is about 1,050 lines (security review).

- Option: with the Phase 0a rulesets token, create only the `http_response_headers_transform` entrypoint in the new zone, with the same four rules `seo-rulesets.tf` declares, rendered from the code by `terraform console`, never hand-typed. The plan's existing "probe found an entrypoint, so import it" path then adopts it in `redirects-dns` as a pure import, and Guard 1 row 9 proves it matches the code.
- This is a production mutation of the new zone. It is recorded as an `operator (production-mutating)` row.
- **Withdrawn as a recommendation (CTO ruling D2, 2026-11-19).** The migrate job now runs the ADR-136 pre-apply entrypoint gate before every apply, so a hand-made entrypoint that holds rules refuses the `redirects-dns` create (`reason=entrypoint-gate-refused`) until an import block for it lands in a PR. Option 0c now costs a code PR to save hours at most; the runbook records it as not recommended.

#### Phase 1 — PR1 code (this branch)

1. **Variables** (`variables.tf`):
   - Add `cf_r2_account_id`: no default, validation `^[0-9a-f]{32}$`.
   - Add validations rejecting the old ids: `cf_zone_id` must not equal `5af02a2f394e9ba6e0ea23c381a26b67`, and `cf_account_id` must not equal `4d5ba6f096b2686fbdd404167dd4e125`. Each error message names #12931 and the runbook.
   - Add five bools: `cf_load_balancing_enabled` (default false), `cf_zone_plan_pro` (default false), `cf_zone_dnssec_enabled` (default false), `cf_migration_imports_enabled` (default true), and `cf_migration_import_app` (default false; flipped in PR2). The tftest sets `cf_migration_imports_enabled` to false, for the same reason it disabled the retired `adopt_seo_config_entrypoint`: the mock provider does not mock `import`.
   - Delete `adopt_seo_config_entrypoint`.
   - **Added by CTO rulings D8 and D9 (2026-11-19):** `cf_r2_account_id` is pinned to the legacy account `4d5ba6f096b2686fbdd404167dd4e125`; the old-id validations also require the 32-hex id format; and `cf_load_balancing_enabled`, `cf_zone_plan_pro`, `cf_zone_dnssec_enabled` and `cf_migration_import_app` are locked to `false` by validation (each with a tftest `expect_failures` row). Turning one on is a reviewed PR that deletes its validation (Load Balancing #12983, DNSSEC #12982), never a tfvar override.
2. **R2 carve-out.** Switch these to `var.cf_r2_account_id`:
   - `workspaces-luks-header.tf`: `local.r2_s3_endpoint` and `cloudflare_r2_bucket.workspaces_luks_header.account_id`;
   - `workspaces-luks-header-web.tf`: `cloudflare_r2_bucket.workspaces_luks_header_web.account_id`;
   - `infra-privileged-environment.tf`: `cloudflare_r2_bucket.terraform_state_privileged.account_id`.

   The rendered value is byte-identical to today's, so every plan shows these and the two `doppler_secret` endpoint copies as no-ops.
3. **LB gate** (`cloudflare-lb.tf`):
   - The monitor, pool, notification policy and load balancer get `count = var.cf_load_balancing_enabled ? 1 : 0`, and every reference is indexed `[0]`.
   - No `moved{}` (F6): the addresses leave state in the first dispatch.
   - `cf-lb-overlay.yml` refuses with an explicit message while the flag is false.
   - Update the LB-address tests to the indexed form (~94 refs): `plugins/soleur/test/terraform-target-parity.test.ts`, `apps/web-platform/infra/lb-weight-gate*.test.sh`, and the `tests/scripts` LB fixtures that pin addresses.
4. **Bot management on Free** (`bot-management.tf`):
   - `sbfm_definitely_automated` and `sbfm_verified_bots` become `var.cf_zone_plan_pro ? "allow" : null`.
   - `fight_mode = false` and `ai_bots_protection = "disabled"` stay.
   - The `zone-rest` phase plan settles whether Free accepts `enable_js`. If it does not, apply the same ternary to it.
5. **DNSSEC gate** (`dns.tf`): `cloudflare_zone_dnssec.soleur_ai` gets `count = var.cf_zone_dnssec_enabled ? 1 : 0`, and its stage-1 `-target` and test refs become `[0]`.
6. **Config-rules import** (`seo-config-rules.tf`):
   - Delete the `import {}` block pinned to `a21ac79d…` and its variable wiring.
   - Update `apps/web-platform/test/seo-config-rules.test.ts`: the `ADOPTED_RULESET_ID` assertions become "no import block pinned to a ruleset id".
   - Touch the `tests/scripts/fixtures/tfplan-origin-tls-*.json` fixtures only where an assertion reads that id.
   - If the Phase 0 probe finds a hand-made `http_config_settings` entrypoint in the new zone, import it by its new id in `cf-account-migration-imports.tf`.
7. **Imports file** (new `cf-account-migration-imports.tf`):
   - Each `import {}` block uses `for_each = var.cf_migration_imports_enabled ? toset(["adopt"]) : toset([])`.
   - Blocks cover the 26 `cloudflare_record` addresses that reference neither the tunnel nor a web host (`<zone>/<record_id>`), `cloudflare_pages_project.docs` (`<account>/soleur-docs`), and `cloudflare_pages_domain.apex` and `.www` (`<account>/soleur-docs/<domain>`).
   - Record ids come from a read-only `GET /zones/951ce525…/dns_records` at work time. They are committed as literals (they are not secret) with a name/type/content comment on each, so the gate can cross-check them.
   - **`cloudflare_record.app` is NOT in `redirects-dns`** (plan review P0). Its `content = hcloud_server.web["web-1"].ipv4_address`, and `hcloud_server.web` renders `cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token`. So `-target=cloudflare_record.app` pulls the forgotten tunnel into the plan as a create (server.tf says this outright). The `app` import block is gated to the `tunnel` phase: it is committed in PR2, or in PR1 behind a separate `cf_migration_import_app` bool that defaults false. Its content `135.181.45.178` equals web-1's IPv4, so the import is a no-op. `app.soleur.ai` keeps serving from the hand-restored record meanwhile.
   - `deploy`, `ssh` and `registry` are NOT imported. PR2 creates them.
   - Every `import` must plan as a pure import (`.change.actions == ["no-op"]`). An import plus update means an id literal is mis-pinned, for example two TXT records swapped, and the gate refuses it (Guard 1).
   - The records Terraform never managed (`76624499`, the `send.outbound` MX/TXT, `resend._domainkey.outbound`, two extra apex TXT) are not adopted.
8. **State-forget script** (new `scripts/cf-account-state-migrate.sh`; **no manifest**, plan review). The candidate set is derived from state itself: every `cloudflare_*` resource in `terraform show -json` except `cloudflare_r2_bucket`. Each entry is then classified by its own id. A hand list would drift whenever a resource is added. The script runs only inside `cf-account-migrate`:
   - It `terraform state pull`s a backup and uploads it with the backend credentials to the state bucket at `web-platform/backups/pre-cf-account-migration-<utc>.tfstate`. The backup is never an artifact and never printed. **In rehearsal mode (CTO L43)** the backup goes to `$RUNNER_TEMP/cf-migrate/` and the script never runs `aws s3 cp`.
   - It reads `terraform show -json`. Classification uses the one non-null id of each entry. Zone rulesets, Access apps and policies, and records carry only `zone_id`. Lists, the account ruleset, service tokens, notification policies, Pages and the LB carry only `account_id`. An entry is `rm` if that id is OLD and `already-migrated` if it is NEW. The script ABORTs before any write if an entry has both ids null, an unknown id, or is a `cloudflare_r2_bucket`. Any other `cloudflare_*` type without either attribute (`cloudflare_zone_settings_override` carries `zone_id`; the fixture covers every resource type declared in the root) is the same abort.
   - **One atomic write** (plan review): all `rm` addresses go to a single `terraform state rm <addr…>` call. The script then asserts that the state `serial` went up by exactly 1. The backend has `use_lockfile = false`, so a per-address loop could leave half-migrated state if it failed partway.
   - It prints one line per address, `cf-state-migrate address=… action=rm|skip|absent`, then a final `verdict=ok removed=N skipped=M`.
   - It is idempotent: a re-run removes 0.
   - **Rehearsal (`plan_only`) mechanism, fixed** (plan review). `-state=` is ignored under the `s3` backend, so the earlier fallback is deleted. The rehearsal copies the root to a scratch directory and writes a `backend_override.tf` there with `terraform { backend "local" { path = "rehearsal.tfstate" } }`. It writes the pulled state to that path, runs `init -reconfigure`, runs the real state-migrate script against the local copy, then plans with normal refresh. Nothing touches the R2 object. The job asserts the remote serial is unchanged before and after the rehearsal, and that no new object appeared under `web-platform/backups/` (CTO L24, L43: a rehearsal writes nothing to R2, because `infra-privileged` has no reviewers and the backup holds secrets). A test runs this shape on a mock-provider root.

   Per F1 everything is forgotten in the first dispatch, so no later plan can contain an old-zone destroy.
9. **Phase gate** (new `scripts/cf-account-migrate-gate.sh`, sourced by the job and by its test). It reads `tfplan.json`; its properties are the Guard Contract below.
10. **Dispatch target** (`apply-web-platform-infra.yml`). *Superseded in part:* CTO L79 moved the dispatch to its own workflow, `cf-account-migrate.yml` (the infra workflow is at its byte cap), and CTO ruling D7 (2026-11-19) splits it into two jobs with literal bindings: `cf_account_migrate_rehearsal` (`infra-privileged`, `REHEARSAL: "true"`) and `cf_account_migrate_apply` (`web-platform-infra-apply`, `REHEARSAL: "false"`). The input is `rehearsal`, not `plan_only`. The text below is the original design.
    - New `apply_target` option `cf-account-migrate`, new input `migrate_phase` (`redirects-dns` | `zone-rest`; PR2 adds `tunnel`), and `confirm=MIGRATE-CF-<phase>`.
    - New job `cf_account_migrate` on `environment: infra-privileged` (main-only), in the shared `terraform-apply-web-platform-host` concurrency group. `plan_only` is honoured.
    - **Environment split (security review).** `infra-privileged` has no reviewers; it only pins the run to `main`. The rehearsal leg (`plan_only=true`) runs there. **Every apply leg runs under `web-platform-infra-apply`**, the reviewer-gated environment `web_host_create` uses (`web-host-birth-environment.tf`), so the operator's environment approval is the authorization for each production write. At work time, verify that environment can load the tier credentials the job needs, mirroring `web_host_create`'s credential steps.
    - **Runner hygiene (security review).** All state copies, `tfplan`, `tfplan.json` and the rehearsal scratch root live under `$RUNNER_TEMP/cf-migrate` with `umask 077` and are removed by an `if: always()` step. The gate and the migrate script print address and action only, never `.change.after`. A workflow-grep test asserts the job has no `upload-artifact` step and no `TF_LOG`. Before dispatch, the agent lists queued and in-progress runs of `apply-web-platform-infra.yml` and refuses if a stale one exists, because a queued run still executes (learning `2026-11-16-web2-kernel-currency-replace-five-operational-traps`).
    - Steps, in order:
      1. tiered credentials;
      2. the state migrate (`redirects-dns` only; against the local rehearsal copy under `plan_only`);
      3. `terraform plan -out` with `-target` args generated from the gate's per-phase allow-set (one list, see Guard 1), then `terraform show -json`;
      4. the phase gate. It asserts the expected counts itself and prints one `verdict=PASS creates=N imports=M destroys=0` line, so the operator compares nothing by eye;
      5. apply (skipped under `plan_only`);
      6. the phase's post-apply curl verification;
      7. a step summary.

      ~~There is no id-preflight step and no per-dispatch probe step.~~ **Re-ruled (CTO ruling D8, 2026-11-19), for the migrate job only:** `check_ids` runs before the state migrate and refuses unless Doppler resolves the new zone and account ids (`zone-id-not-new`, `account-id-not-new`) and `cf_r2_account_id` is the legacy account (`r2-account-not-old`). Each provider token of the phase then gets one GET on the new zone or account and must answer `200`; only the HTTP code prints, and the token goes to `curl --config -` on stdin. The tokens per phase sit next to the phase spec (`cf_account_migrate_phase_tokens`): `redirects-dns` checks `cf_api_token`, `cf_api_token_rulesets` and `cf_api_token_pages`; `zone-rest` checks `cf_api_token_zone_settings` and `cf_api_token_bot_management`. The write-scope probes still run once per phase from the runbook.
    - No SSH, no bridge, no `deploy-status` probe.
11. **Migration-in-progress refusal** (revised after plan review). A sourced predicate `scripts/cf-account-migration-complete.sh` runs before the plan step of **every plan-capable job in `apply-web-platform-infra.yml` except `cf_account_migrate`**. That covers `apply`, `web_host_create`, `ci_ssh_token_replace`, `registry_host_replace` and the rest. `web_host_create` targets `cloudflare_record.app`, which is the tunnel chain, and `ci_ssh_token_replace` would build Access objects out of phase.
    - **Exception:** `web_host_replace` with `web_host_key=web-2` is allowed once the tunnel is in state on the new account (Phase 3 step 4).
    - While the migration is incomplete, the job fails with `verdict=cf-account-migration-in-progress` and an `::error::` naming the runbook. It exits non-zero rather than 0, so it does not mask other merged PRs' unapplied infra.
    - A workflow-grep test asserts that every job running `terraform plan` calls the predicate, except the two named exceptions.
    - `scheduled-terraform-drift.yml` is **not** gated: it only plans, and its red during the migration is an expected red listed in the runbook.
    - **Deny by default (CTO ruling D1, 2026-11-19).** Every workflow that loads `./.github/actions/infra-credentials` is gated unless the predicate names it in its exempt-workflow list (the plan-only and migrator workflows, and the callers that plan other roots or run no Terraform). `key-rotate.yml` and `inngest-key-rotate.yml` are therefore gated. The migrate job's in-flight refusal reads the same exempt list, so a new caller is covered by both without an edit.
    - **Stronger completion definition:** every `cloudflare_*` address the root declares with count > 0 is in state, every one carries the new zone or account id (R2 excepted), the tunnel is in state on the new account, and the census reports at least 1 connector. The last condition is checked by the job's existing census step, so the routine apply does not reopen before web-2 has been replaced.

    Before the Doppler flip, the `cf_zone_id` validation already fails every plan loudly. The predicate covers the window between the flip and the end of the tunnel phase. The Phase 5 cleanup PR removes it.
12. **Runtime zone id and tokens in every config that holds them** (CTO F2, plus the CTO devex review):
    - New `doppler_secret.cf_zone_id_prd` (`project=soleur`, `config=prd`, `name=CF_ZONE_ID`, `value=var.cf_zone_id`). No `ignore_changes`: the id is not a secret and must track the variable.
    - It is in the `redirects-dns` target set and is appended to the push-triggered stage-1 `-target` list.
    - **Branch configs do NOT inherit** (`scripts/check-cloudflare-token-drift.sh` records that branch configs hold their own copies, and 5–7 went stale on past rolls). Before the first dispatch, the agent builds a names-only Doppler listing over `apps/web-platform/infra/doppler-config-inventory.txt` that finds every config holding `CF_ZONE_ID`, `CF_API_TOKEN_PURGE`, `CF_API_TOKEN_DNS_EDIT` or `CF_ACCESS_CLIENT_ID`. It then writes the new value to each one (stdin, silent, verified with a separate `get`). This runs inside the Phase 2 step 2 sequence and doubles as the "every `prd_*` holds the new id" preflight. Doing it in the job after apply would fail a successful redirect restore.
    - Repoint `scripts/check-cloudflare-token-drift.sh` to the new ids **in PR1** (F11). The scheduled drift job, `registry-zot-inventory.yml` and `reusable-release.yml` grade tokens through it.
    - The `dev*` configs carry `CF_ZONE_ID` for the read-only audit token. Those are agent Doppler writes after a go, recorded in the runbook.
13. **Docs CI**: in `.github/workflows/deploy-docs.yml`, probe A's `PROBE_URL` becomes `https://soleur-docs-40x.pages.dev/version.txt`. Update the "Measured 2026-09-02: soleur-docs.pages.dev" comment to match.
14. **Stale literals: deferred to the cleanup PR** (plan review: they restore nothing). These are `plugins/soleur/agents/engineering/infra/infra-security.md` (zone and account ids to the new ones, R2 note) and the `infra-credential-tiers-8209.md` note.
15. **Keep the TEMPORARY `ssl=full` config rule** (overturned 2026-11-19, CTO L55 re-ruling). It is recreated in the new zone with `cloudflare_ruleset.seo_config_settings` in `redirects-dns`. Its removal belongs to #7799, together with the `dns.tf` `github_pages` -> `pages_apex` moved block and the apex rollback tooling; `ssl-full-mitigation.test.sh` stays armed on that moved block. Phase 5 does not delete it. After the state-forget the moved block is a no-op (its source is not in state).
    - `scripts/cf-access-deploy-token-mint.sh` (F8) and `scripts/cf-tunnel-host-predelete.sh` (F5) **move to PR2** (all three reviewers). They serve no PR1 property, and PR2 gets its own review.
16. **Tests come first** (`cq-write-failing-tests-before`): see Test Scenarios. Each guard's mutation matrix is written before the guard.

#### Phase 2 — Redirect restore (after PR1 merges; operator-authorized dispatches)

1. Merge PR1 with a merge-commit line containing exactly `[skip-web-platform-apply]`. Arm a watch on any push-triggered run anyway (`hr-dispatch-async-must-arm-watch`).
2. **Re-ruled (CTO ruling D11, 2026-11-19):** this sequence is the staged `bootstrap.sh` in the #12931 spec directory (`soleur:operator-bootstrap`, ADR-264), not one typed go. Each stage is idempotent and one prompt-approved write: `prev-0a`, `flip-ids`, `swap-0a` (staged `redirects-dns` probe, copy, digest compare, only then delete `_NEXT`), `branch-copies-zone-id`, then the `redirects-dns` dispatch; `prev-0b`, `swap-0b`, `branch-copies-tokens` (refuses while any `CF_API_TOKEN_{PURGE,DNS_EDIT}_NEXT` exists), then the `zone-rest` dispatch. The original single-go design follows. `Operator-authorizes:` ~~one typed go covering the whole sequence~~ (CTO devex: fewer separate approvals while the incident is live). The agent:
   - copies the live `CF_ZONE_ID`, `CF_ACCOUNT_ID` and Phase 0a token values to `<KEY>_PREV`;
   - flips `prd_terraform` `CF_ZONE_ID` to `951ce525552201ec6c696b24251abed7` and `CF_ACCOUNT_ID` to `66d4f93f7397f196544e9fe84c3557c2`, and swaps each `<KEY>` ← `<KEY>_NEXT`;
   - writes the branch-config copies (Phase 1 item 12);
   - asks for the revoke of the old DNS-edit token (Phase 0 step 4).

   Every write goes on stdin with `--silent` and stdout to `/dev/null`, then is read back with a separate `get`.

   **Merge-to-flip window.** From PR1's merge until this step, every plan of this root fails on the old-id validations, including `web-host-replace` and the registry dispatcher. That fails safe, but this step must follow the merge within the same sitting.

   **No rollback by flip** (CTO devex). After the flip, the validations reject the old ids. A failed phase is fixed forward with a new PR.

   **Halt, not revert (CTO ruling D4, 2026-11-19; withdraws CTO L59's full revert).** On any failure, stop at the last verified phase and fix forward. The `_PREV` id restore is allowed only before the first `redirects-dns` apply, and it leaves the root closed (the validations reject the old ids), not reopened. Once that apply ran there is no id restore, no `git revert` of PR1 and no push of the backup over live state: each would point Terraform at the moved zone or reopen routine applies against state that no longer holds the zone's resources. The pre-migration backup is disaster-recovery evidence only, and Phase 5 deletes every `pre-cf-account-migration-*` object. The runbook's `## Halt` section is the operator text; `tests/scripts/test-cf-account-migration-runbook.sh` reds if a `terraform state push` line comes back.

   The dispatches in this phase and in Phase 3 can run under one standing delegation recorded on #12931 (see the operator row in `decision-challenges.md`). Otherwise each needs its own go.
3. `Operator-authorizes:` the rehearsal:

   ```bash
   gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=cf-account-migrate -f migrate_phase=redirects-dns -f plan_only=true -f confirm=MIGRATE-CF-redirects-dns -f reason='#12931 rehearsal'
   ```

   Expected: the gate prints `verdict=PASS`, with counts it computes itself from the committed imports file and the Phase 0 probe output.
   - creates: 7 rulesets/lists, minus any entrypoint the probe found already hand-made (those become imports). `cloudflare_ruleset.cache_shared_binaries` is in no phase list (CTO ruling D3, 2026-11-19): it is created by the Phase 3 step 6 `manual-rerun` through the routine apply's existing `-target`, after the redeploy has loaded the new purge token, so no edge copy of a share exists while revokes cannot purge it;
   - imports: 26 records, 1 Pages project and 2 Pages domains, plus those entrypoints;
   - 1 `doppler_secret` add;
   - 0 destroys;
   - `cf-state-migrate verdict=ok` against the local rehearsal copy, with the remote serial unchanged.
4. `Operator-authorizes:` the same command with `plan_only=false`.
5. Verify, both in the job step and with a local re-run:
   - `https://soleur.ai/pages/agents.html` returns `301`;
   - `https://soleur.ai/pages/legal/privacy-policy.html` returns `301`;
   - `https://www.soleur.ai/` returns `301` with `location: https://soleur.ai/`;
   - `https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/` returns `301`;
   - `https://app.soleur.ai/` carries `x-robots-tag: noindex`;
   - a `GPTBot` user agent on `https://soleur.ai/` gets `200`, not a challenge;
   - the four Better Stack redirect monitors are back to `up`, read from the Better Stack API.
6. `Operator-authorizes:` `migrate_phase=zone-rest`, rehearsal then apply. Expected:
   - a `zone_settings_override` create that adopts the parity settings with 0 visible change;
   - a `bot_management` create or update;
   - 2 `github_actions_secret` updates (the Pages token and account id);
   - a `doppler_secret.cf_api_token_dns_edit` replace. `-replace` is in the phase target set because `ignore_changes=[value]` would otherwise keep the old token.

   Then dispatch a docs publish (`gh workflow run deploy-docs.yml --ref main`, watched) rather than waiting for a docs push: probe A on `soleur-docs-40x.pages.dev` passes (read its step log; it is `continue-on-error`), and probe B (apex `version.txt`) equals the deployed sha. This clears the `deploy-docs.yml` red the PR1 merge itself triggers.

#### Phase 3 — PR2: tunnel, Access and deploy hosts (new branch from `main`)

1. **Mint the deploy Access service token** (CTO F8) with `scripts/cf-access-deploy-token-mint.sh`:
   - It `POST`s `/accounts/<new>/access/service_tokens` with `name=github-actions-deploy` and `duration=8760h`, authenticated with `CF_API_TOKEN_ACCESS_MINT`.
   - It writes the client id and secret to Doppler on stdin, never argv, and never prints them. They go to `soleur-infra-privileged/prd` (`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`) and to the same keys in `soleur/prd_terraform`, because `server.tf` reads `var.cf_access_client_id/secret` for push-infra-config.
   - It prints only the token UUID.

   `Operator-authorizes:` the run. Revoke `CF_API_TOKEN_ACCESS_MINT` afterwards.
2. **PR2 code:**
   - `tunnel.tf`: `local.deploy_service_token_ids = ["<new uuid>"]`.
   - The `tunnel` phase in the job and the gate.
   - Wire in `scripts/cf-tunnel-host-predelete.sh` (F5). It is dry-run by default and refuses unless the request zone id is NEW. For each of the six pinned ids it GETs the record and asserts: name in {`ssh.soleur.ai`, `registry.soleur.ai`}, type `A`, proxied `true`, content in {`104.26.10.163`, `104.26.11.163`, `172.67.73.132`}. If any check fails, it deletes none. It logs every id, and a re-run that finds 0 records exits 0.
   - The phase target set: `random_id.tunnel_secret` (`-replace`, CTO F9), the tunnel, the tunnel config, 3 Access apps, 3 policies, the `ci_ssh` and `registry_push` service tokens, the `service_token_expiry` notification policy, `cloudflare_record.deploy`/`.ssh`/`.registry`, and `doppler_secret.registry_push_access_token_id`/`_secret` (`-replace`).
   - The gate exception: exactly one create of `cloudflare_zero_trust_access_policy.deploy_service_token`, in the NEW zone, whose `include[0].service_token` equals `local.deploy_service_token_ids`. Because the plan is derived from that same local, the comparison alone proves nothing. The gate step therefore also `GET`s `/accounts/<new>/access/service_tokens/<uuid>` and requires a `200` before the apply. The merge path's deploy-policy HALT is unchanged.
   - The `cloudflare_record.app` import moves here (see Phase 1 item 7). It must plan as a pure import.
   - The deploy-token check goes beyond the `200` (security review). With a read-only token, the gate step `GET`s the service token and asserts:
     - its name is `github-actions-deploy`, and its `expires_at` is about 8760h out;
     - the planned policy has `decision = "non_identity"`;
     - `include` holds exactly that one service token: no `everyone`, email, IP or any-valid-service-token rule;
     - the policy's `application_id` is the planned `deploy` Access app.
   - The pre-delete `--apply` runs only as a step inside the gated `cf_account_migrate` tunnel-phase apply leg, after a passing rehearsal. It never runs from the agent's machine.
   - The CI-SSH token sync handles the first-run empty secret. A workflow that consumes a freshly synced secret sees it empty on its first run (learning `2026-05-20-doppler-write-token-bootstrap-cycle-and-access-enum`), so the sync step warns and the runbook expects one re-dispatch.
   - The tunnel name stays `soleur-web-platform`, because the census looks it up by name.
3. **Tunnel phase apply.** Merge PR2 with `[skip-web-platform-apply]`. `Operator-authorizes:` the `migrate_phase=tunnel` rehearsal, then the apply.
   - The post-apply steps reuse the `apps/web-platform/infra/scripts/sync-ci-ssh-access-token.sh` logic to write `CI_SSH_ACCESS_TOKEN_ID/_SECRET` from the new outputs into `prd_terraform`.
   - Expected state after the apply: the new tunnel exists with 0 connectors. `deploy`, `ssh` and `registry` resolve to the new `<id>.cfargotunnel.com` and return 530/1033. They were already down, so this is no regression.
   - The census reports 0 connectors until step 4. That is expected, and the runbook says so.
4. **Replace web-2.** `Operator-authorizes:` the rehearsal, then the same dispatch with `plan_only=false`:

   ```bash
   gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=web-host-replace -f web_host_key=web-2 -f confirm=REPLACE-web-2 -f plan_only=true -f reason='#12931 tunnel token'
   ```

   The replace gate sees exactly its four allow-listed addresses, because the tunnel is already in state. web-2 boots, `cloudflared service install <new token>` registers the connector, and `soleur-wait-ready service cloudflared` gates the boot.
   **Before the release redeploy:** re-mint the Origin CA certificate from the new zone (CTO devex; moved from Phase 5). Run `mint-origin-ca-cert.yml` `mode=plan`, then the `origin-tls-mint.md` §3 deliberate-rotation flow, with `CF_API_TOKEN_ORIGIN_CA` re-scoped to the new zone. The containers read the certificate only at start (`origin-tls-mint.md`), so this lets one redeploy carry both the new runtime ids and the new certificate. `Operator-authorizes:` the mint dispatch.
5. **Verify:**
   - the census shows exactly 1 connector on the new tunnel;
   - `scripts/verify-tunnel-ingress-origin.sh` passes: new `CF_ACCOUNT_ID`, new tunnel id, and `deploy-status` 200 through `deploy.` with the new Access pair;
   - a CI SSH bridge round-trip succeeds;
   - a `registry.` push canary succeeds (`registry-zot-inventory.yml` or the release dual-push);
   - a `web-platform-release.yml` redeploy succeeds. It also loads the new runtime `CF_ZONE_ID`, `CF_API_TOKEN_PURGE` and `CF_API_TOKEN_DNS_EDIT` into the containers.
   After the redeploy a share revoke answers `200` again: until then it answers `502 purge-failed`, because the frozen container env holds the old zone id and purge token (an expected red in the runbook).
6. **Re-run the routine path.** Before the dispatch (CTO ruling D5, 2026-11-19) the agent posts on #12931: (1) `git log --oneline <PR1-merge-sha>..origin/main -- apps/web-platform/infra`, which must list only #12931 commits; (2) the latest `scheduled-terraform-drift.yml` web-platform plan summary, which must show only the migration remainder plus one `cloudflare_ruleset.cache_shared_binaries` create; (3) the owner's review comment on both. A merge freeze holds from the PR1 merge to this step: no non-#12931 change under `apps/web-platform/infra/**` merges (an exception is the operator's priority call). `Operator-authorizes:` `apply_target=manual-rerun`. The migration-complete predicate is now true, so the routine path runs end to end: stage-1 (a no-op or near-no-op), verify, token sync, SSH stage. Expected: green, with exactly one `cloudflare_ruleset.cache_shared_binaries` create (D3).

#### Phase 4 — Close the incident

1. Flip the post-mortem only on measured evidence: all 9 soleur.ai/app Better Stack monitors `up`, and `deploy`, `ssh` and `registry` serving (Phase 3 step 5). The file is `knowledge-base/engineering/operations/post-mortems/soleur-ai-cloudflare-account-move-outage-2026-11-18-postmortem.md`:
   - `status: open` becomes `resolved`, in the frontmatter and in the `## Status` body line;
   - add the recovery timestamps to the timeline;
   - set the #12931 Action Items row to `resolved` with the PR numbers.

   This lands in PR2 if the evidence exists before PR2 merges, otherwise in the cleanup PR. Never on a projection.
2. PR1 and PR2 bodies use `Ref #12931`. `Closes #12931` goes in the body of the PR that lands last, which is the cleanup PR.

#### Phase 5 — Cleanup PR and hardening (third PR, after Phase 3 verification)

1. Remove the temporary machinery: `cf-account-migration-imports.tf`, the state-migrate script, the in-progress predicate and its call sites, the `cf_migration_imports_enabled`/`cf_migration_import_app` variables, **and the `cf_account_migrate` job, its `migrate_phase` input, its `apply_target` option and the phase gate with its suite** (CTO devex plus simplicity: delete, do not retire behind `exit 1`; git history keeps them). Keep `cf-access-deploy-token-mint.sh` and the `cf-token-scope.sh` profiles, linked from `cloudflare-service-token-rotation.md` for the 8760h rotation.
2. `Operator-authorizes:` revoke `CF_API_TOKEN_SOLEUR_ACCT` (and remove its Doppler key) and the old-zone tokens superseded in Phase 0.
3. (Moved to Phase 3 step 4: the Origin CA re-mint.)
4. `Operator-authorizes:` delete the old tunnel `fc4509ed…` from the OLD account once web-2's replace has dropped its connections. It is an account object, not part of the old zone. It is still irreversible, so it needs its own go.
5. Re-scope the read-only tokens to the new ids (`check-cloudflare-token-drift.sh` was already repointed in PR1).
7. `Operator-authorizes:` delete the objects the forget step left behind in the OLD account, each by name after its own go. The delete list comes from the pre-migration state backup, filtered to old-account, non-R2 entries: the LB monitor and pool (they keep health-checking origins and may still bill), the `ci_ssh` and `registry_push` service tokens (valid credentials until they expire), the Access apps and policies, the lists, the account ruleset and the notification policies. Old-ZONE objects are never touched. The zone is `moved` and read-only, and the constraint stands.
   Add two unmanaged leftovers the state-derived list misses (security review): the old deploy service token (the pre-migration `local.deploy_service_token_ids` value `d9204def…`), and the old-zone Origin CA certificate (revoke it once the Phase 3 re-mint serves).
   Delete every `web-platform/backups/pre-cf-account-migration-*` object, every version, not only the current one (check bucket versioning first), and post an empty re-list of that prefix on #12931 (CTO ruling D4). Track the deadline in the cleanup PR's issue.
8. Flip ADR-329 to `accepted`.
6. Update the expense ledger (`knowledge-base/operations/expenses.md`), per the COO. Also move the deferred `infra-security.md` and `infra-credential-tiers-8209.md` literal edits here (they restore nothing):
   - soleur.ai row: "Free, new Soleur account (#12931)";
   - Load Balancing row: retired or deferred;
   - old account: R2 only.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Flip the ids and let a normal apply converge | `zone_id`/`account_id` are ForceNew. The plan would destroy in the moved zone, which is forbidden, and the creates would collide with the hand-restored records. |
| Import blocks only | Ignored while the address is still in state (measured). |
| `removed{}` + renaming every resource (F1b) | Cannot tell old entries from new ones. Renames ~60 addresses and breaks ~94 test refs. |
| Parallel `*_soleur` variables, migrated file by file (F2b) | Invites mixed-account plans and doubles the variable surface. A single flip with fail-closed validation is simpler. |
| Per-phase PRs through the push-triggered apply (F3b) | That job's tunnel verify fails today, and its deploy-policy gate HALTs on the required create. It rides the tunnel it would be repairing. |
| Import + replace for ssh/registry (the original F5) | Three A records per name cannot fit one address (re-ruled). |
| Delete the old zone's objects | Forbidden. The old zone is the only reference copy until the grace period ends. |
| Point the new zone's CNAMEs at the old account's tunnel | `cfargotunnel.com` routing is bound to the account, and it would keep the deploy path on the account being retired. |
| Buy Pro or Load Balancing now | An operator money decision. COO default: stay on Free and defer LB, since the LB serves no traffic today. |

## Non-Goals

- Migrating the `apps/web-platform/infra/lb-staging/` root. It reads the same Doppler ids, but `cf-lb-overlay.yml` refuses while `cf_load_balancing_enabled` is false, so the flip cannot plan a destroy there. Tracked with the LB purchase decision.
- DNSSEC on the new zone (count-gated off, tracked by #12982).
- Re-enabling Load Balancing (tracked with the LB purchase decision, #12983). `cf-lb-overlay.yml` now refuses every arm through its `lb_enabled_gate` job (`cf_lb_gate_lb_enabled` in `tests/scripts/lib/cf-lb-overlay-gate.sh`, reading the committed `cf_load_balancing_enabled` default). The PR that turns it on must also move the GA allow-sets in that lib, which still name `cloudflare_load_balancer.app` and its siblings, to the indexed `[0]` plan addresses. It must also widen `CF_API_TOKEN` with the Load Balancing scopes.
- The `ga-lb-pool-soak-6027` follow-through (tracker #11942, open, the sweeper has graded it FAIL daily through 2026-11-18). It was still armed at work time. PR1 retires it in code: `scripts/followthroughs/ga-lb-pool-soak-6027.sh` exits NOT YET (2) while `cf_load_balancing_enabled` is false, after its secret gates and before any network call. The tracker itself is left open. Closing it as not planned, or keeping it until Load Balancing returns, is a tracker decision for after PR1 merges.
- An app-level `X-Robots-Tag` fallback in Next.js headers (CMO P1). That is new scope, recorded as an `operator (scope)` row in `decision-challenges.md`.
- Adopting the DNS records Terraform never managed.
- Moving R2 (state bucket, LUKS headers, CLA evidence) to the new account.

## Files to Edit

PR1 (this branch):

- `apps/web-platform/infra/variables.tf`: add `cf_r2_account_id`, the old-id validations, `cf_load_balancing_enabled`, `cf_zone_plan_pro`, `cf_zone_dnssec_enabled`, `cf_migration_imports_enabled`; delete `adopt_seo_config_entrypoint`.
- `apps/web-platform/infra/workspaces-luks-header.tf`, `apps/web-platform/infra/workspaces-luks-header-web.tf`, `apps/web-platform/infra/infra-privileged-environment.tf`: R2 surfaces move to `var.cf_r2_account_id`.
- `apps/web-platform/infra/cloudflare-lb.tf`: count gate plus `[0]` references (and `outputs.tf` if any LB output exists; grep at work time).
- `apps/web-platform/infra/bot-management.tf`: `sbfm_*` ternaries.
- `apps/web-platform/infra/dns.tf`: DNSSEC count gate. Records otherwise unchanged.
- `apps/web-platform/infra/seo-config-rules.tf`: delete the old-id import block.
- `apps/web-platform/infra/tests/web-hosts-eu-pin.tftest.hcl`: drop `adopt_seo_config_entrypoint`, set `cf_migration_imports_enabled = false`, and add `cf_r2_account_id`.
- `.github/workflows/apply-web-platform-infra.yml`:
  - `apply_target` option `cf-account-migrate` plus the `migrate_phase` input;
  - job `cf_account_migrate`;
  - the in-progress predicate call in `apply`;
  - `doppler_secret.cf_zone_id_prd` and `cloudflare_zone_dnssec.soleur_ai[0]` in the stage-1 `-target` list.
- `scripts/check-cloudflare-token-drift.sh`: repoint expectations to the new account and zone (F11, in PR1). `plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`: add the per-phase new-account probe profiles (non-mutating invalid-body write probes).
- `apps/web-platform/infra/seo-config-rules.tf`: the TEMPORARY `ssl=full` rule is kept (Phase 1 item 15, #7799).
- `.github/workflows/cf-lb-overlay.yml`: refuse while `cf_load_balancing_enabled` is false.
- `.github/workflows/deploy-docs.yml`: probe A URL.
- `apps/web-platform/test/seo-config-rules.test.ts`: adoption assertions.
- `plugins/soleur/test/terraform-target-parity.test.ts` and the LB-address tests under `apps/web-platform/infra/*.test.sh` and `tests/scripts/`: indexed LB addresses. Enumerate them at work time with `rg -l 'cloudflare_load_balancer(_pool|_monitor)?\.(app|web_1|web)\b|cloudflare_notification_policy\.web_lb_health|cloudflare_zone_dnssec\.soleur_ai'`.
- `apps/web-platform/infra/run-registered-suites.sh` registry inputs (`suite-durations.tsv`, `suite-shard-legs.tsv`): register the new `*.test.sh` suites.
- `plugins/soleur/agents/engineering/infra/infra-security.md`: zone and account ids.
- `apps/cla-evidence/infra/bootstrap.sh`: read `CF_R2_ACCOUNT_ID` (not `CF_ACCOUNT_ID`) from `prd_terraform` for `TF_VAR_cf_account_id`. The CLA-evidence root homes an object-locked R2 bucket on `var.cf_account_id`. After the flip, an unchanged re-run of the bootstrap would plan a replace of that sole-copy legal-evidence bucket into the new account. The variable keeps its name (renaming it would churn the root's state), and the description becomes "Cloudflare account that homes R2 (legacy account, ADR-329)". `apps/cla-evidence/infra/main.test.sh` gets a grep assertion.
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: an R2-account note.
- `knowledge-base/engineering/architecture/diagrams/model.c4`:
  - the `cloudflare` system description (two accounts; LB off);
  - the `inngest -> api` edge text ("The app.soleur.ai load balancer steers…" → plain proxied record while LB is gated off);
  - the `tunnel` container description (the tunnel lives on the Soleur account).

PR2 (new branch): `apps/web-platform/infra/tunnel.tf` (`local.deploy_service_token_ids`), `.github/workflows/apply-web-platform-infra.yml` (`tunnel` phase), `scripts/cf-account-migrate-gate.sh` (tunnel rules), and the post-mortem file (status flip, when evidenced).

Cleanup PR: removes the PR1 temporary files; `knowledge-base/operations/expenses.md`.

## Files to Create

PR1:

- `apps/web-platform/infra/cf-account-migration-imports.tf`: import blocks (26 records, the Pages project, 2 Pages domains; the `app` record import is gated to the tunnel phase).
- `apps/web-platform/infra/cf-runtime-zone-id.tf`: `doppler_secret.cf_zone_id_prd`.
- `apps/web-platform/infra/scripts/cf-account-state-migrate.sh` and `apps/web-platform/infra/cf-account-state-migrate.test.sh`.
- `apps/web-platform/infra/scripts/cf-account-migrate-gate.sh` and `apps/web-platform/infra/cf-account-migrate-gate.test.sh` (fixtures under `apps/web-platform/infra/test-fixtures/cf-account-migrate/`, synthesized only, `cq-test-fixtures-synthesized-only`).
- `apps/web-platform/infra/scripts/cf-account-migration-complete.sh` and `apps/web-platform/infra/cf-account-migration-complete.test.sh`.
- PR2 (not PR1): `apps/web-platform/infra/scripts/cf-access-deploy-token-mint.sh` with `apps/web-platform/infra/cf-access-deploy-token-mint.test.sh` (asserts the no-argv, no-print, stdin-only shape on a stubbed `curl`/`doppler`).
- PR2 (not PR1): `apps/web-platform/infra/scripts/cf-tunnel-host-predelete.sh` with `apps/web-platform/infra/cf-tunnel-host-predelete.test.sh`.
- `knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md`: the phase runbook. Every command is owner-named, with expected outputs and the recovery path.
- `knowledge-base/engineering/architecture/decisions/ADR-329-cloudflare-zone-resources-live-on-the-soleur-account-r2-stays.md`. The ordinal is provisional; `soleur:ship` re-verifies it.
- `knowledge-base/project/specs/feat-one-shot-12931-cf-account-migration/decision-challenges.md`: written at plan time.

## Downtime & Cutover

**Offline-inducing operations and the surface each affects:**

1. **`web-host-replace web-2`** (Phase 3 step 4): a destroy-then-create of `hcloud_server.web["web-2"]`.
   - Surface: the tunnel connector, which carries deploy, ssh and registry.
   - `app.soleur.ai` is served by web-1 through its plain proxied A record (the LB is gated off) and is untouched.
2. **The Doppler id flip plus the state forget** (Phase 2): no serving surface goes offline. Redirects, noindex and the WAF allowlist are already absent, and this step restores them.
3. **The six-record pre-delete and the CNAME create** (Phase 3 step 3): `ssh.`/`registry.` move from Error 1000 to 530/1033. Both are down states, so nothing regresses.

**Zero-downtime evaluation (the default):**

- **Blue-green for the tunnel.** The new tunnel is created next to the old one in a different account. The old tunnel keeps its 4 connections from the current web-2 until web-2 is replaced. The cutover moment is the CNAME create in the new zone, and that already points at a surface that is down today. So no user-visible service drops at any step.
- **Why not run a second connector before the replace:** a connector needs the new token on a host. The only token path is user_data at create (ADR-304). A replace of the connector host is the delivery mechanism, not an avoidable outage. web-2 serves no LB traffic while the LB is gated off.
- **Expand-contract for state.** The forget plus import is state-only re-addressing (the `terraform state mv` class). It runs with no Cloudflare write except the creates of objects that are absent today.

**Residual downtime accepted:** none on `app.soleur.ai`. The deploy, ssh and registry hosts stay down from now until the end of Phase 3 step 4, the window being about one web-2 boot after the tunnel apply. This is the incident's existing outage being ended, not a new one.

**Per-stage verification and rollback:**

| Stage | Verification | Rollback |
|---|---|---|
| Phase 2 dispatches | job curl checks plus Better Stack | fix forward. Full revert per Phase 2 step 2 |
| Tunnel apply | gate PASS; CNAMEs resolve to the new `<id>.cfargotunnel.com` | re-run the phase (idempotent) |
| web-2 replace | `soleur-wait-ready service cloudflared`; census shows 1 connector | re-run `web-host-replace web-2`; web-1 is unaffected |

## Network-Outage Deep-Dive

The trigger keywords (SSH, unreachable, 530/1000) appear because `ssh.soleur.ai` is a broken host in this incident, not a symptom under diagnosis. The cause is known and measured: the records moved to a new zone with no tunnel. Layer status, from L3 to L7:

- **L3 firewall allow-list: not applicable, by evidence.** The Error 1000 / no-record states are generated at Cloudflare's edge, so no packet reaches a Hetzner firewall. The CI SSH path goes through the tunnel (`cf-tunnel-ssh-bridge`), not a public port. A firewall diff would verify nothing about this incident. Recorded as `not verified: packet never leaves the Cloudflare edge`.
- **L3 DNS/routing: verified.** A read-only DoH query at plan time (`curl -s 'https://cloudflare-dns.com/dns-query?name=ssh.soleur.ai&type=A' -H 'accept: application/dns-json'`) returned the three proxied Cloudflare A records 104.26.10.163, 104.26.11.163 and 172.67.73.132. The same held for `registry.`. `deploy.` returned no record.
- **L7 TLS/proxy: verified by symptom.** Error 1000 ("DNS points to prohibited IP") is a Cloudflare edge response. After Phase 3 the expected edge response before web-2's replace is 530/1033 (no connector). `curl -sI https://deploy.soleur.ai/hooks/deploy-status` shows which one.
- **L7 application: not applicable.** The `webhook` service and `sshd` on web-1 are not reached. Health is read after cutover through `verify-tunnel-ingress-origin.sh` and the census, never through SSH (`hr-no-ssh-fallback-in-runbooks`).

## Open Code-Review Overlap

1 open scope-out touches these files: #10462 (rename the zot fill-rate probe, `zot-registry.tf`). **Acknowledge:** a different concern, and this plan does not edit `zot-registry.tf` (the registry Access app lives in `tunnel.tf`). The scope-out stays open.

## Infrastructure (IaC)

### Terraform changes

- Root `apps/web-platform/infra` (existing, R2 backend unchanged on the old account). Providers are unchanged: `cloudflare ~> 4.0` (4.52.7 lock), `doppler ~> 1.21`, `github ~> 6.0`. No new provider.
- New variables and their value sources:
  - `cf_r2_account_id` ← Doppler `prd_terraform` `CF_R2_ACCOUNT_ID` via `TF_VAR_cf_r2_account_id`. No default. It must exist before PR1 merges.
  - `cf_zone_id` and `cf_account_id` are unchanged in name; their VALUES flip in Doppler at Phase 2.
  - The token variables are unchanged in name; their values are re-minted on the new account (Phase 0).
  - The new bools have literal defaults (no operator-minted value, so `hr-tf-variable-no-operator-mint-default` does not apply).
- New resources:
  - `doppler_secret.cf_zone_id_prd`;
  - PR1 creates in the new zone or account: 5 zone rulesets, 2 lists, 1 account ruleset;
  - PR2 creates the tunnel set.
- Imports: 26 records, 1 Pages project and 2 Pages domains in `redirects-dns`, plus any hand-made ruleset entrypoint found by the probe. `cloudflare_record.app` is imported in the `tunnel` phase.
- Forgets: every non-R2 `cloudflare_*` state entry carrying an old id, removed in one atomic `state rm`.

### Apply path

(b) A dedicated targeted apply, the `cf-account-migrate` dispatch, phase by phase. Then a `terraform apply -replace` of `hcloud_server.web["web-2"]` through the existing `web-host-replace` dispatch, for the cloudflared token, which reaches the host only through user_data at create.

- Expected downtime: none for `app.soleur.ai`, which is untouched. `deploy`, `ssh` and `registry` are already down and come back at the end of Phase 3.
- web-2's replace window: about one boot. web-2 holds `lb_weight` gated by `var.web2_lb_weight`, and with the LB gated off it serves no public traffic.
- Blast radius of the forget step: state only. Cloudflare is not changed, and the backup is taken first.

### Host fan-out

This plan adds and edits no `terraform_data` SSH provisioner. The only host change is web-2's user_data, delivered by the existing replace path. Classification per `plan-host-fanout.md`: web-1 is not touched; web-2 is a cattle replace (the tunnel connector).

### What merging PR1 alone does to production

This answer is derived from every workflow whose `on.push.paths` matches a PR1 file (census: `.github/workflows/*.yml` push-path parse, 2026-11-18).

- `apply-web-platform-infra.yml` (`apps/web-platform/infra/**`): skipped by the `[skip-web-platform-apply]` merge-commit line. If the marker were lost, the run still fails closed: before the flip, the old ids in Doppler fail the new validations at plan time, so nothing applies. The marker keeps the run from showing a spurious red; it is not the safety. **Consequence:** between merge and flip, every plan of this root fails, including dispatch targets, so the flip follows the merge in the same sitting (Phase 2 step 2).
- `registry-host-replace-dispatch.yml` (`variables.tf`): wakes, renders the registry user_data offline and must return `deliver=false`, because no registry render input changes. Pre-merge AC: run `apps/web-platform/infra/registry-render-delta.test.sh` (or the dispatcher's render step locally) on the PR1 diff and record `deliver=false`.
- `infra-validation.yml` (`apps/*/infra/**`): validate and test only; no apply.
- `validate-vector-config.yml` (`apps/web-platform/infra/*.sh`): matches the new top-level `*.test.sh` suites; validation only.
- `deploy-docs.yml`: the merge does trigger it, because PR1 edits `deploy-docs.yml` itself and files under `plugins/soleur/skills/**`. It publishes with the old-account `CLOUDFLARE_*_PAGES` secrets to the old project, which changes nothing new, but probe A now reads the new project, so the run goes red. That red is expected until `zone-rest` and is cleared by a dispatched docs publish (Phase 2 step 6). A legal-copy docs change is held until then, or re-run after.

So PR1's merge mutates no production resource. Production changes start at the Phase 2 Doppler flip.

### Consumers of `CF_ACCOUNT_ID` outside this root

- `apps/cla-evidence/infra/bootstrap.sh` (R2, operator-local): fixed in PR1, above.
- `apps/web-platform/infra/lb-staging/` and `cf-lb-overlay.yml`: refuse while LB is gated off (Non-Goals).
- `scheduled-inngest-health.yml` tunnel census: looks the tunnel up by name in `CF_ACCOUNT_ID`. Between the flip and the tunnel phase it finds no tunnel and reports red. The runbook lists this as an expected red.
- `scheduled-followthrough-sweeper.yml` → `scripts/followthroughs/ga-lb-pool-soak-6027.sh` (GitHub secret `CF_ACCOUNT_ID`, LB pools): work-time check whether this followthrough is still armed. If it is, retire it with the LB gate in PR1, because it would read pools that no longer exist. Checked at work time: armed (tracker #11942). Retired in code: the probe exits NOT YET while `cf_load_balancing_enabled` is false (see Non-Goals).
- `plugins/soleur/skills/provision-*/scripts/*.sh` and the other roots' `main.tf` backend endpoints: R2 endpoint literals on the legacy account. Correct as they are; unchanged.
- `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` (the Art. 17 erasure path for the object-locked CLA bucket): reads `CF_R2_ACCOUNT_ID`, fixed on this branch (a403878e6d).
- `apps/web-platform/server/inngest/functions/event-cf-token-expiry-check.ts`: reads the runtime `prd` `CF_ACCOUNT_ID` with `CF_API_TOKEN` to list `/accounts/<id>/access/service_tokens` and watch `github-actions-deploy`. The code is account-agnostic and needs no change, but that token lives on the new account after Phase 3 step 1, so the `prd` `CF_ACCOUNT_ID` (and the token that reads it) must follow then. The bootstrap's `inventory` stage lists every `CF_ACCOUNT_ID` holder, and the runbook's Phase 3 step 1 records a per-holder decision (R2 reader stays legacy or moves to `CF_R2_ACCOUNT_ID`; zone or Access reader gets the new id).

### Distinctness / drift safeguards

- `dev != prd`: Doppler `dev*` configs carry only `CF_ZONE_ID` and the audit token. No Terraform resource writes `dev`.
- Validations make any plan carrying an old id fail before refresh.
- The in-progress predicate makes every plan-capable job except `cf_account_migrate` (and the web-2 `web_host_replace` after the tunnel phase) exit non-zero with `::error::` between the Doppler flip and the end of the tunnel phase. The drift job is not gated: it only runs `terraform plan -detailed-exitcode` (CTO L50).
- The state backup object holds secrets (as all state does). It lives only in the state bucket, under `web-platform/backups/`, and is deleted in the cleanup PR after a successful `manual-rerun`. Logging that deletion is part of the runbook.
- `lifecycle.ignore_changes` call-outs:
  - `doppler_secret.registry_push_*` and `doppler_secret.cf_api_token_dns_edit` (`ignore_changes=[value]`) need `-replace` in their phase;
  - `cloudflare_zero_trust_tunnel_cloudflared.web` (`ignore_changes=[secret, config_src]`) is a fresh create, so it takes the new `random_id` secret;
  - `hcloud_server.web` (`ignore_changes=[user_data]`) is why the token needs a replace.

### Vendor-tier reality check

- New zone on the Free plan (CTO-verified on developers.cloudflare.com):
  - single redirects 10 (uses 10);
  - transform 10 (uses 4);
  - config 10 (uses 3);
  - cache 10 (uses 1);
  - custom WAF 5 (uses 1);
  - bulk redirects 15 rules / 5 lists / 10,000 items per account (uses 1 / 2 / 158).
- Super Bot Fight Mode is Pro+, so it is gated by `var.cf_zone_plan_pro`.
- Load Balancing is a paid add-on, so it is gated by `var.cf_load_balancing_enabled`.
- DNSSEC is free, but it is deferred for cutover safety (F10).

## Observability

```yaml
liveness_signal:
  what: "Better Stack uptime monitors betteruptime_monitor.soleur_www_redirect, .seo_redirect_zone_ruleset, .seo_redirect_bulk_item, .seo_redirect_blog_pair (expected 301) plus the existing app/apex/legal monitors; the 15-min tunnel connector census in scheduled-inngest-health.yml (cfd_tunnel lookup by name soleur-web-platform under CF_ACCOUNT_ID, verdict token from scripts/tunnel-connector-census.sh)"
  cadence: "Better Stack monitors every 3 min; connector census every 15 min; cf-account-migrate step summary per dispatch"
  alert_target: "Better Stack incident to the operator (existing policy); census verdict to the existing ci/tunnel-connector action-required issue path"
  configured_in: "apps/web-platform/infra/uptime-alerts.tf; .github/workflows/scheduled-inngest-health.yml; .github/workflows/apply-web-platform-infra.yml job cf_account_migrate"

error_reporting:
  destination: "GitHub Actions job failure + step summary for every dispatch (cf_account_migrate, web_host_replace); Sentry for the web-2 fresh-boot fatal emits (soleur-boot-emit, baked SENTRY_DSN) and for the runtime cf-cache-purge / cert-reissue paths"
  fail_loud: "cf-state-migrate verdict=abort, cf-account-migrate-gate verdict=REFUSE <reason>, cf-tunnel-host-predelete verdict=refuse, ::error:: lines; verdict=cf-account-migration-in-progress on every blocked plan-capable job is an ::error:: with a non-zero exit plus a summary line, never silent (the drift job is not gated)"

failure_modes:
  - mode: "rulesets token lacks a phase write scope (403 at apply)"
    detection: "cf-token-scope.sh per-phase new-account profile (non-mutating invalid-body write probe) run by the agent before the phase rehearsal prints probe=<phase> verdict=denied; any denied verdict blocks that phase's dispatch"
    alert_route: "dispatch run failure seen by the dispatching agent's armed watch"
  - mode: "a plan would destroy, or would plan any resource outside the phase set or against an old id"
    detection: "cf-account-migrate-gate.sh on tfplan.json, before apply"
    alert_route: "dispatch run failure; nothing applied"
  - mode: "redirects or noindex header not served after apply"
    detection: "post-apply curl verification step in cf_account_migrate; Better Stack 301 monitors stay down"
    alert_route: "Better Stack incident + job failure"
  - mode: "new tunnel has 0 connectors after the web-2 replace"
    detection: "connector census verdict in scheduled-inngest-health.yml; soleur-wait-ready cloudflared readiness gate fails the web-2 boot (fresh-boot Sentry emit)"
    alert_route: "census action-required issue; Sentry boot-fatal event"
  - mode: "LUKS header escrow endpoint re-homed to an account with no bucket"
    detection: "phase gate asserts zero planned change on cloudflare_r2_bucket.* and doppler_secret.workspaces_luks_header_r2_endpoint; tftest asserts local.r2_s3_endpoint uses cf_r2_account_id"
    alert_route: "dispatch run failure; nothing applied"
  - mode: "runtime still targets the moved zone"
    detection: "job step asserts CF_ZONE_ID read from every prd/prd_* config equals the new id"
    alert_route: "dispatch run failure"

logs:
  where: "GitHub Actions run logs + step summaries for apply-web-platform-infra.yml (cf_account_migrate, web_host_replace, apply); Better Stack Logs source 2457081 for the web-2 boot trail (SOLEUR_BOOT_STAGE)"
  retention: "GitHub Actions logs 90 days (repo default); Better Stack Logs per the existing source retention"

discoverability_test:
  command: "curl -s -o /dev/null -w '%{http_code}' https://soleur.ai/"
  expected_output: "200"
```

The redirect property (`https://soleur.ai/pages/agents.html` answers `301`) can only be true after merge plus the `redirects-dns` dispatch, so preflight cannot probe it before merge. Three checks verify it after the apply: the dispatch fails on anything but 301 (`apps/web-platform/infra/scripts/cf-account-migrate-job.sh`, the post-apply curl loop), the Better Stack monitor `seo_redirect_bulk_item` expects `[301]` (`apps/web-platform/infra/uptime-alerts.tf`), and the runbook's Phase 2 verification curl. The pre-merge probe above checks that the zone keeps serving the site through the migration (CTO ruling, 2026-11-20, `decision-challenges.md`).

## Encryption Posture

```yaml
at_rest:
  - store: "R2 object soleur-terraform-state/web-platform/backups/pre-cf-account-migration-<utc>.tfstate (new object in the EXISTING state bucket, old account)"
    mechanism: "provider-managed:Cloudflare R2 encryption at rest (AES-256, all objects)"
    evidence: "Cloudflare R2 data-security reference https://developers.cloudflare.com/r2/reference/data-security/ retrieved_on=2026-11-18; the same attestation already governs the live web-platform/terraform.tfstate object in this bucket (ADR-006)"
    defends_against: "a seized or decommissioned Cloudflare storage device; raw media access at the provider"
    does_not_defend: "anyone holding the backend R2 access key pair (AWS_ACCESS_KEY_ID/SECRET in prd_terraform) reads the full state including sensitive attributes; a Cloudflare-side compromise; a CI log that printed it (prevented: the script never prints or uploads it as an artifact)"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable:R2 exposes no per-object encryption attestation API"
in_transit:
  - connection: "GitHub Actions runner (cf_account_migrate job, scripts/cf-*.sh, terraform cloudflare provider) -> api.cloudflare.com"
    enforced_at: "plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh and apps/web-platform/infra/scripts/cf-account-state-migrate.sh (curl https:// with default CA verification, no -k); cloudflare provider default HTTPS client"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a leaked API token used from elsewhere; a compromised runner"
    disclosed_as: "not-publicly-claimed"
  - connection: "web-2 cloudflared connector -> Cloudflare edge (new tunnel, PR2)"
    enforced_at: "apps/web-platform/infra/cloud-init.yml cloudflared service install (cloudflared default: TLS to the edge with certificate verification)"
    tls: "TLS 1.2+ / QUIC (cloudflared default)"
    cert_verification: "on"
    does_not_defend: "a leaked tunnel token (anyone holding it can register a connector; mitigated by the single-connector census)"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — cf-account-migrate phase gate (`scripts/cf-account-migrate-gate.sh`)

**Property.** A `cf-account-migrate` plan applies only if it destroys nothing, changes only addresses in the requested phase's allow-set, and every planned Cloudflare object carries the NEW zone or account id. The only exceptions are R2 resources, which must be planned as no-op.

**Assembly.** The single chokepoint is the `tfplan.json` produced by the job's plan step. The gate reads `.resource_changes[]` (all actions, including `forget`, `delete`, `create`, `update`, the `["delete","create"]` replace, and `import` via `.change.importing`) and `.resource_changes[].change.after.{zone_id,account_id}`. The phase allow-sets live in the gate file as data, one jq `def` per phase, and the job passes the phase name. A second chokepoint exists because `-replace` is an argv flag: the gate also asserts the replace set equals the phase's declared replace set (`tunnel`: `random_id.tunnel_secret`, `doppler_secret.registry_push_access_token_id/_secret`; `zone-rest`: `doppler_secret.cf_api_token_dns_edit`), so a plan that silently ignored a `-replace` is refused.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add one `delete` of `cloudflare_record.app` to a valid `redirects-dns` fixture | RED |
| 2 | Gate dispatch: pass an unknown phase name, or a plan with zero `resource_changes` | RED (refuses "0 checked") |
| 3 | A valid first ruleset plus a SECOND ruleset create whose `after.zone_id` is the OLD id | RED |
| 4 | A create of `cloudflare_load_balancer.app[0]` (outside every allow-set) | RED |
| 5 | `update` on `cloudflare_r2_bucket.workspaces_luks_header` (account_id change) | RED |
| 6 | `tunnel` phase plan missing the `random_id.tunnel_secret` replace (flag ignored) | RED |
| 7 | `tunnel` phase: a second create of the deploy policy, or `include.service_token` not equal to the committed UUID list | RED |
| 8 | `forget` action on any address (a `removed{}` slipped in) | RED |
| 9 | An `import` entry (non-null `.change.importing`) whose `.change.actions` is anything but `["no-op"]`: `["update"]`, or `["delete","create"]` for a record swapped across types (measured on TF 1.10.5 by the terraform-architect pass) | RED |
| 9b | A declared `-replace` address planned without `.action_reason == "replace_by_request"` (TF drops a `-replace` outside the `-target` set with no warning; measured) | RED |
| 9c | A `-replace` target whose `before` physical id differs from the id recorded in pre-plan state (the gate binds by address AND physical id; learning `2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm`) | RED |
| 10 | An `import` entry whose `.change.importing.id` differs from the committed literal | RED |
| 11 | Counts: one expected import missing from the plan (the plan has fewer imports than the committed file) | RED |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | The suite runs on `tests/scripts/lib/gate-suite-harness.sh`, which already asserts nonzero passes and RED-on-no-op mutation. Making `mutate()` a no-op turns the suite RED. | RED |
| H2 | Must-PASS: a `redirects-dns` plan whose imports come in a different order and that carries an extra `no-op` read of a data source | PASS |

**Anchor.** There is one list per phase: a jq `def` in the gate file. The job generates its `-target` args from that list (`cf-account-migrate-gate.sh --targets <phase>`), so the target set and the allowed set cannot drift. The gate sources `tests/scripts/lib/plan-gate-preamble.sh`, which fails closed on an empty or unreadable plan (#7044 class). The set-identity test against plan prose is cut. Widening the list is a reviewed diff in that one file.

### Guard 2 — state-forget script (`scripts/cf-account-state-migrate.sh`)

**Property.** The script removes a state entry only if that entry's own `zone_id`/`account_id` is an OLD id. It never removes an R2 resource. It removes nothing once it finds any entry it cannot classify.

**Assembly.** There is one input, `terraform show -json` of current state (the candidate set is every non-R2 `cloudflare_*` entry), and one write site: a single `terraform state rm` call carrying every `rm` address. Every entry is classified before any write (CTO L47): an unknown id anywhere aborts with 0 removed and no `state rm` call. There is no per-address re-check. The backup step must succeed before the single `state rm` call.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | An R2 bucket would land in the `rm` set (classifier bug simulated) | RED (abort, 0 removed) |
| 2 | Dispatch: `terraform show -json` returns `{}`, or zero `cloudflare_*` entries | RED ("0 checked" refused) |
| 2b | An entry with both `zone_id` and `account_id` null | RED (abort before any write) |
| 2c | A mixed state where rulesets carry only `zone_id` and lists carry only `account_id`, both old | PASS: both classes `rm` |
| 2d | `state rm` is called more than once, or the serial goes up by more than 1 | RED |
| 3 | First entry old-zone, SECOND entry carries an unknown zone id | RED (abort with 0 removed and no `state rm` call) |
| 4 | Backup upload fails (stubbed `aws s3 cp` exit 1) | RED, 0 removed |
| 5 | Order: the `state rm` call runs before the backup (reorder) | RED. The test observes the stub call order inside the run, not the final state. |
| 6 | Re-run after a complete migration | PASS with `removed=0` |
| 7 | A stubbed `state rm` reports fewer `Successfully removed` lines than the rm set, or the post-rm re-list still shows an old-id entry (CTO L72) | RED |

**Harness rows:** H1 is a must-PASS mixed state (old-zone records plus new-zone records already imported) that yields `rm` only for the old ones. H2: if the stubbed `terraform` ignores `state rm` calls, the test's call-recorder assertion fails, so the suite goes RED.

### Guard 3 — migration-in-progress predicate (`scripts/cf-account-migration-complete.sh`)

**Property.** No plan-capable job other than `cf_account_migrate` (and the web-2 `web_host_replace` after the tunnel phase) plans while any non-R2 `cloudflare_*` state entry carries an OLD id, or while the tunnel is absent from state or carries an account id other than the new one.

**Assembly.** The predicate is called before `terraform plan` in every plan-capable job of `apply-web-platform-infra.yml` except `cf_account_migrate`, with the `web_host_replace web-2` exception once the tunnel is in state. A workflow-grep test enumerates the jobs that run `terraform plan` and asserts each one calls the predicate, so a new job cannot silently skip it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | State with one old-zone `cloudflare_record` | incomplete (refuse) |
| 2 | Empty state JSON | incomplete (fail closed, not "nothing old found") |
| 3 | All records new, SECOND class (the tunnel) still old-account | incomplete |
| 4 | Remove the call site from `web_host_create` (or add a new plan-running job without it) | the workflow-grep test goes RED |
| 6 | All entries new and the tunnel on the new account, but one declared address (for example `cloudflare_ruleset.cache_rules`) absent from state | incomplete |
| 7 | `web_host_replace` with `web_host_key=web-1` during the migration | refused (only web-2 is excepted) |
| 5 | Old-account `cloudflare_r2_bucket` only, everything else new | complete (must-PASS) |

### Guard 4 — old-id variable validations (`variables.tf`)

**Property.** No plan can evaluate with the old zone id or the old account id in `cf_zone_id`/`cf_account_id`.

**Assembly.** Two `validation` blocks, plus `tests/web-hosts-eu-pin.tftest.hcl` `expect_failures` runs.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | tftest run with `cf_zone_id = 5af02a2f…` (old); then delete the validation block | `expect_failures` passes; with the block deleted the run goes RED |
| 2 | tftest run with `cf_account_id = 4d5ba6f0…` (old); then delete the validation block | same as row 1 |
| 3 | Must-PASS: new ids, and a third arbitrary 32-hex id | validates |
| 4 | `cf_r2_account_id` empty or 31 hex chars | RED (validation fires) |
| 5 | Old zone id in upper case (`5AF02A2F…`) | RED: the validation compares on `lower()`, and a test pins it |

### Guard 5 — tunnel-host pre-delete (`scripts/cf-tunnel-host-predelete.sh`)

**Property.** The script deletes a DNS record only if it is one of the six pinned ids in the NEW zone, and its live name, type, proxied flag and content match the pinned broken shape. Either all six pass the pre-check, or none is deleted.

**Assembly.** A pinned id list in the script, one GET per id (the check), and one DELETE call site behind `--apply`. The default is dry-run.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Zone id argument = OLD zone | RED (refuse, 0 deletes) |
| 2 | Dispatch: no `--apply` | dry-run lines only, 0 DELETE calls |
| 3 | First five records match, the SIXTH is a CNAME (already fixed) | RED: 0 deletes, because the check-all completes before any delete |
| 4 | A record's content is `135.181.45.178` (a real origin) | RED |
| 5 | Re-run: all six GETs 404 | exit 0, 0 deletes (idempotent) |

**Harness:** H1: a stubbed `curl` records DELETE calls, and making it swallow them turns row 3's assertion RED.

## Architecture Decision (ADR/C4)

### ADR

New ADR-329 (provisional ordinal): **"Cloudflare zone-bound resources live on the Soleur account; R2 stays on the legacy account."** It covers:

- Decision: zone and account resources (DNS, rulesets, lists, Pages, tunnel, Access, notifications, the LB when enabled) follow `var.cf_account_id`, the Soleur account. R2 (Terraform state backends, LUKS header escrow, the privileged state bucket, CLA evidence) follows `var.cf_r2_account_id`, the legacy account.
- The state-forget-then-import migration mechanism, the old-id validations, and the plan-tier gates (`cf_zone_plan_pro`, `cf_load_balancing_enabled`, `cf_zone_dnssec_enabled`).
- Alternatives: moving R2 too (rejected: 8 backends, no benefit, LUKS escrow risk); parallel variables; a plain flip.

Frontmatter (architecture-strategist pass): `amends: [ADR-068, ADR-321]` and `related_adrs: [ADR-006, ADR-114, ADR-143, ADR-194, ADR-304]`.

- ADR-068 gets a dated addendum. Its 2026-11 amendment records web-2 serving at weight 1 through the LB, and gating the LB off undoes that state.
- ADR-321 gets a dated addendum. Its "adopted rule" (`a21ac79d`) is no longer imported, because Terraform creates the config rule in the new zone. The Origin CA certificate is re-minted from the new zone, and its LB health-monitor wording no longer applies.
- ADR-006 gets a one-line cross-reference only. The backend and its endpoint stay correct.
- ADR-194 gets a cross-reference addendum: the Pages project and the account Bulk Redirects now live on the Soleur account, served at `soleur-docs-40x.pages.dev`.
- ADR-304 gets a cross-reference: recreating the tunnel means a mandatory web-2 replace, which is exactly its retirement mechanism.
- No ADR states "one Cloudflare account" (grep of the decisions directory).

### C4 views

All three model files (`model.c4`, `views.c4`, `spec.c4`) were read in full by the deepen-plan architecture-strategist pass. `views.c4` and `spec.c4` need no change: no view, tag or kind refers to an account, the LB or DNSSEC.

- Already modeled and unchanged: the external actor `Cloudflare` (system), the containers `tunnel` and `zotRegistry`, the edges `github -> tunnel`, `hetzner -> tunnel`, `hetzner -> cloudflare` (LUKS header escrow to R2) and `api -> cloudflare` (the cert-reissue cron).
- No new actor and no new external system.
- Falsified descriptions to edit in `model.c4`, in PR1. Each is identified by its element or edge, not by line number:
  1. **`cloudflare` element, first sentence** ("DNS, CDN, R2 storage, zero-trust tunnel — and…"). New text: DNS, CDN, Pages, rulesets, the zero-trust tunnel and Access live on the Soleur account (`var.cf_account_id`). R2 (the Terraform state buckets, the LUKS header escrow, CLA evidence) stays on the legacy account (`var.cf_r2_account_id`). That is two accounts, one vendor and one DPA (#12931, ADR-329). The zone runs on Free, with DNSSEC gated off.
  2. **`cloudflare` element, the LB passage** (from "Since #11181/PR #11766 it also carries the GA LOAD BALANCER" through "never the routine apply"). New text: the app.soleur.ai LB is gated off since #12931 (`cf_load_balancing_enabled=false`, and `cf-lb-overlay.yml` refuses). The proxied A record serves app.soleur.ai from web-1 alone.
  3. **`inngest -> api` edge** ("The app.soleur.ai load balancer steers each step call…"). New text: while the LB is gated off, every step call lands on web-1 through the app A record. With the LB enabled, it steers each call to any serving host.
  4. **`betterstack -> hetzner` edge** ("Origin uptime probe at the LB-fronted app.soleur.ai surface"). Drop "LB-fronted", or qualify it as "only while `cf_load_balancing_enabled`".
  5. **`github -> cloudflare` edge**: add that the R2 state backend is on the legacy account, while the rulesets GETs and all provider writes target the Soleur account.
  6. **`hetzner -> cloudflare` edge, the LIMITATION clause**: add that both R2 buckets stay on the legacy account, and that the single `cloudflare` node hides the account boundary.
  7. **`tunnel` container** (advisory): "ONE tunnel … on the Soleur account, recreated by #12931 (forcing a web-2 replace, since the token is create-time user_data). The old tunnel lingers on the legacy account until cleanup."
- Splitting the `cloudflare` node in two was rejected: it would change the layout for a boundary the description already states.
- No `views.c4` include changes.
- After the edits, regenerate `knowledge-base/engineering/architecture/diagrams/model.likec4.json` with `scripts/regenerate-c4-model.sh`. Then run `plugins/soleur/test/c4-model-freshness.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`; all must be green. Without the regeneration the freshness gate fails PR1 in CI.

### Sequencing

The ADR is written in PR1 with `status: adopting`. It moves to `accepted` when Phase 3 step 6 (routine apply green) is evidenced. The flip happens in the cleanup PR.

## User-Brand Impact

- **If this lands broken, the user experiences:**
  - legacy links and `www.soleur.ai` keep returning non-301 responses (the four red Better Stack monitors stay red);
  - `app.soleur.ai` keeps sending no `X-Robots-Tag: noindex`, so product pages, including `/shared/[token]` and `/invite/[token]` links, stay indexable;
  - deploys and CI registry pushes stay blocked, so no fix reaches `app.soleur.ai`;
  - worst case, a mis-gated apply re-homes the LUKS header escrow endpoint and a later fresh web host fails to escrow its LUKS header.
- **If this leaks, the user's data / workflow is exposed via:**
  - search-engine indexing of `/shared/[token]` and `/invite/[token]` URLs while the noindex header is missing, a pre-existing exposure this plan closes in Phase 2;
  - the state backup object, which holds the same secrets as live state, if the backend R2 key pair leaks;
  - a newly minted deploy Access pair or tunnel token printed to a CI log.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (CTO ruling D6, 2026-11-19; was `aggregate pattern`):** the plan changes no user-data store, but two vectors can each hurt one named user. A revoked share link could keep serving from the edge cache, and the Art. 17 erasure path for the CLA evidence bucket could address the wrong account. One such incident is a brand event, so the threshold is `single-user incident`, and each vector has a closing artifact below.
- **Also affected (reviewer-requested):**
  - mail and auth records: the Proton and Resend MX, SPF, DKIM and `_dmarc` records are Terraform-managed (`dns.tf`) and are among the 26 `redirects-dns` imports, each of which must plan as a pure no-op import (the gate refuses an import plus update), so no live mail record changes. The unmanaged `send.outbound` pair and `resend._domainkey.outbound` are not adopted and not touched. Sign-in and notification mail keep flowing;
  - `/api/shared/<token>` and `/shared/<token>`: indexable until the `redirects-dns` noindex rule lands; the Phase 4 Search Console check covers all three token URL shapes;
  - deferred: DNSSEC stays off on the new zone (#12982) and Load Balancing stays off (#12983); neither serves user traffic today.
- **Open item:** share revokes answer `502 purge-failed` from now until the Phase 3 step 5 release redeploy, because the running containers hold the old zone id and purge token. The revoke is recorded; only the edge purge fails, and with D3 no edge copy exists to purge. The runbook lists it as an expected red.

Artifact and vector pairs for `soleur:engineering:review:user-impact-reviewer`:

- Redirect and noindex rulesets ↔ `seo-rulesets.tf`, `seo-bulk-redirects.tf`, `seo-config-rules.tf` (gate Guard 1).
- LUKS header escrow endpoint ↔ `workspaces-luks-header.tf` `local.r2_s3_endpoint` (Guard 1 row 5, and the tftest).
- Deploy pair and tunnel token secrecy ↔ `scripts/cf-access-deploy-token-mint.sh` (stdin-only test), the `tunnel_token` sensitive output.
- Revoked share served from the edge ↔ `cloudflare_ruleset.cache_shared_binaries` in no phase list, created only at the Phase 3 step 6 `manual-rerun` after the redeploy (CTO ruling D3; gate suite mutation).
- Art. 17 erasure on the wrong account ↔ `cla-signature-evidence-retrieval.md` reading `CF_R2_ACCOUNT_ID`, pinned by `apps/cla-evidence/infra/main.test.sh` (a403878e6d).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "migrate Terraform to the new Soleur Cloudflare account and zone" [brief] | Phase 1 (PR1 code), Phase 3 (PR2), Phase 5 (cleanup) | mapped |
| 2 | "restoring the redirects and the deploy/ssh/registry tunnel hosts first" [brief] | Phase 2 (redirects-dns dispatch first), Phase 3 (tunnel + web-2 replace) | mapped |
| 3 | "go on #12931 migration restoring the redirects and deploy hosts" [brief, operator directive] | Phases 2 and 3 | mapped |
| 4 | "Terraform must IMPORT, not recreate" [brief] | Phase 1 items 7–8 (imports file + state-forget) | mapped |
| 5 | "the plan should state exactly which permission groups Terraform needs on the new account/zone" [brief] | Phase 0 step 1 table | mapped |
| 6 | "Investigate how the web host receives its tunnel token today" [brief] | Research Insights §Mechanism facts; Proposed Solution §chicken-and-egg | mapped |
| 7 | "plan the cutover that keeps deploys recoverable" [brief] | Proposed Solution §chicken-and-egg; Phase 3 steps 3–6 | mapped |
| 8 | "the plan should treat the LB as optional" [brief] | Phase 1 item 3 (count gate); decision-challenges operator (money) row | mapped |
| 9 | "the plan should include flipping it to resolved once the redirect and deploy-host monitors recover" [brief] | Phase 4 step 1 | mapped |
| 10 | "prefer phasing so redirects (pure Cloudflare, no host change) land and are applied first, then the tunnel/Access/deploy hosts" [brief] | PR1/PR2 split, phases redirects-dns → zone-rest → tunnel | mapped |
| 11 | "Redirects (the 4 Better Stack 301 monitors are red)" [issue #12931] | Phase 2 steps 3–5 | mapped |
| 12 | "Transform rules `http_response_headers_transform`" [issue #12931] | Phase 2 (redirects-dns target set) | mapped |
| 13 | "Config rules `http_config_settings`: … Drop the TEMPORARY `ssl=full` rule" [issue #12931] | Phase 2 (seo_config_settings created from config). The "drop the TEMPORARY rule" half is deferred to #7799 (CTO L55 re-ruling, 2026-11-19): it is removed together with the `github_pages` moved block and the apex rollback tooling. | deferred (#7799) |
| 14 | "Cache rule `http_request_cache_settings`" [issue #12931] | Phase 2 | mapped |
| 15 | "WAF custom rule allowlisting AI crawler UAs … and bot management" [issue #12931] | Phase 2 (allowlist), Phase 2 step 6 (bot management, Free shape) | mapped |
| 16 | "Load balancer `app.soleur.ai` … needs a subscription" [issue #12931] | Phase 1 item 3; operator money row | mapped |
| 17 | "Tunnel hosts: `deploy`, `ssh` and `registry` are down … Notification policies … move too" [issue #12931] | Phase 3 (incl. `service_token_expiry`) | mapped. "Leaked Service Token Alert" is not in Terraform today; the work phase greps the old account's policy list and either codifies it in PR2 or records it as a follow-up. |
| 18 | "Plan: the old zone was Pro … Decide whether to upgrade" [issue #12931] | Vendor-tier reality check; operator money row | mapped |
| 19 | "Terraform: change `cf_zone_id` and `cf_account_id` … Re-mint every Terraform-minted Cloudflare token" [issue #12931] | Phase 0, Phase 2 step 2, Research Reconciliation | mapped |
| 20 | "Doppler: every `CF_ZONE_ID` … still holds the old zone id" [issue #12931] | Phase 1 item 12, Phase 0 step 3, Phase 5 step 5 | mapped |
| 21 | "Rotate the GitHub Actions secrets `CLOUDFLARE_API_TOKEN_PAGES` and `CLOUDFLARE_ACCOUNT_ID_PAGES`" [issue #12931] | Phase 2 step 6 (TF-managed) + Phase 1 item 13 (probe URL) | mapped |
| 22 | "`api.soleur.ai` … Check that the `_acme-challenge.api` renewal works from the new zone" [issue #12931] | Acceptance Criteria (post-merge): `cloudflare_record.supabase_acme_challenge` imported and its content equals the old-zone value; a renewal check is recorded in the runbook before the 2026-12-26 expiry | mapped |
| 23 | "The temporary token is revoked" [issue #12931 Done-when] | Phase 5 step 2 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `variables.tf` edits, imports file, state-migrate script | asks 1, 4, 19 | asked |
| `cf_r2_account_id` + R2 carve-out | — | inferred — justification: safety. A plain `cf_account_id` flip re-homes the LUKS header and state buckets (CTO F2). |
| `cf-account-migrate` job + gate + in-progress predicate | asks 7, 10 | asked |
| LB count gate, `cf-lb-overlay.yml` refusal | ask 8 | asked |
| Bot-management Free shape, DNSSEC gate | asks 15, 18 | asked (DNSSEC: inferred — justification: the unconditional `cloudflare_zone_dnssec` would be created by the first full plan; enabling DNSSEC mid-cutover is a new whole-domain failure mode, CTO F10) |
| `doppler_secret.cf_zone_id_prd` | ask 20 | asked |
| `deploy-docs.yml` probe URL | ask 21 | asked |
| `cf-token-scope.sh` new-account probe profiles (replaces the cut probe script) | — | inferred — justification: safety. The `2026-07-24` scope-gap class means a GET-only check cannot prove write scope. |
| Deploy-token mint script, pre-delete script (PR2) | asks 2, 17 | asked |
| Runbook | ask 7 | asked |
| ADR-329 + C4 edits | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the account split changes recorded architecture |
| `infra-security.md`, `infra-credential-tiers-8209.md` literals | ask 20 ("The same applies to `plugins/soleur/scripts/cloudflare-readonly.sh` …") | asked |
| Origin CA re-mint (Phase 3 step 4) | — | inferred — justification: safety. A certificate minted against the moved zone may be revoked at zone deletion, and `app.soleur.ai` would then fail under `ssl=strict`. |
| Old-tunnel retirement (Phase 5) | — | inferred — justification: leaves no second live tunnel holding the old secret; owner-named, irreversible |
| Expense ledger edit | ask 18 | asked |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `.github`, `plugins/soleur`, `knowledge-base`.
- Planned files (PR1, after plan review): about 32 (21 edits plus about 11 creates, of which 3 scripts and 4 tests: state-migrate, gate, predicate, plus the rehearsal-shape test) | Estimated changed lines (PR1): about 1,050 (workflow job about 300, scripts about 300, tests about 300, the rest config and docs). The manifest, the new probe script, the id-preflight step and the two PR2 scripts were cut or moved.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines. All exceeded.
- Recommendation: split. The split is already structural (CTO F4): PR1 redirects plus machinery, PR2 tunnel, a cleanup PR. A further split of PR1 (machinery first, phases second) is declined: it would add a merge-and-review cycle in front of the P1 redirect restore, and every PR1 file is needed before the first dispatch can run. The deferred scripts (`cf-access-deploy-token-mint.sh`, `cf-tunnel-host-predelete.sh`) are the one movable seam. If PR1 review runs long, move them to PR2.

## Acceptance Criteria

### Pre-merge (PR1)

- [ ] `terraform validate` and `terraform test` (`tests/web-hosts-eu-pin.tftest.hcl`) pass with `cf_migration_imports_enabled = false`. The tftest's `expect_failures` cases prove both old-id validations fire.
- [ ] `rg -n 'var\.cf_account_id' apps/web-platform/infra/*.tf` returns no `cloudflare_r2_bucket` block and no `r2_s3_endpoint` line. `rg -n 'cf_r2_account_id'` hits exactly the 3 bucket blocks, `local.r2_s3_endpoint` and the variable.
- [ ] `rg -n 'adopt_seo_config_entrypoint|a21ac79d368f425a95c895c43a090d57' apps/web-platform/infra apps/web-platform/test` returns only fixture data that no assertion reads, or nothing at all.
- [ ] The state-migrate suite's fixture holds one state entry per `cloudflare_*` resource type declared in the root. The type list is derived by a test that parses `*.tf`, not from a hand list. Every type except `cloudflare_r2_bucket` classifies to `rm` or `already-migrated`, and none aborts on a missing id.
- [ ] Each import block's record id matches a record of the right name and type in a read-only work-time dump, which is checked by the gate fixture and not committed.
- [ ] The Guard 1–5 suites pass, every mutation row reddens its guard, and they are registered in `run-registered-suites.sh`.
- [ ] The workflow-grep test proves the in-progress predicate runs before `terraform plan` in every plan-capable job except `cf_account_migrate` (with the `web_host_replace web-2` exception), and that `cf_account_migrate` has no `cf-tunnel-ssh-bridge` step and no `ssh` invocation.
- [ ] `terraform-target-parity.test.ts`, the LB-address tests and the C4 tests (`c4-code-syntax`, `c4-render`, `c4-count-parity`) pass.
- [ ] `deploy-docs.yml` has no `soleur-docs.pages.dev` probe URL.
- [ ] ADR-329 exists (status `adopting`) and the `model.c4` edits are present.
- [ ] Doppler `prd_terraform` `CF_R2_ACCOUNT_ID` is present before merge, verified by `doppler secrets get CF_R2_ACCOUNT_ID --plain -p soleur -c prd_terraform | cut -c1-8` printing `4d5ba6f0`.

- [ ] The PR1 merge-commit message carries `[skip-web-platform-apply]` on its own line (checked by `soleur:ship` before merge), and the PR body's first line answers "does merging this alone mutate production?" with "No".
- [ ] The registry user_data render delta on the PR1 diff is `deliver=false`.
- [ ] `apps/cla-evidence/infra/bootstrap.sh` sources `TF_VAR_cf_account_id` from `CF_R2_ACCOUNT_ID`, and `main.test.sh` asserts it.

### Post-merge (operator-authorized, evidenced in the PR thread)

- [ ] The `redirects-dns` rehearsal: gate `verdict=PASS creates=N imports=M destroys=0`, with N and M equal to what the gate derived from the imports file and the probe output. The remote state serial is unchanged across the rehearsal.
- [ ] After the `redirects-dns` apply, the curl checks return 301 for each of the four monitor URLs, `x-robots-tag: noindex` on `app.soleur.ai`, and 200 for a GPTBot UA. The four Better Stack redirect monitors are `up`.
- [ ] After the `zone-rest` apply, the next docs push passes probe A (`soleur-docs-40x.pages.dev`) and probe B (apex sha).
- [ ] `CF_ZONE_ID` equals the new id in `prd` and every `prd_*` config, and `dev*` is updated.
- [ ] `cloudflare_record.supabase_acme_challenge` is under management in the new zone. The runbook notes the `api.soleur.ai` renewal check before 2026-12-26.
- [ ] PR2: the census shows 1 connector on the new tunnel, `verify-tunnel-ingress-origin.sh` passes, a CI SSH bridge round-trip and a registry push canary succeed, a `web-platform-release.yml` redeploy succeeds, and `manual-rerun` is green.
- [ ] The post-mortem shows `status: resolved` only after the item above holds, plus all 9 monitors `up`.
- [ ] Cleanup PR: the temporary token is revoked, the old tunnel is deleted after its connections drop, the state backup object is deleted, and `Closes #12931`.
- [ ] PR2/Phase 3: the Origin CA certificate is re-minted from the new zone before the `web-platform-release.yml` redeploy, and `app.soleur.ai` serves it (`curl -sv https://app.soleur.ai/health` through the proxy returns 200 under `ssl=strict`).

## Test Scenarios

All scenarios are `unit` (bash suites with stubbed `terraform`/`curl`/`doppler`/`aws` and synthesized plan or state JSON) unless noted.

### Acceptance Tests (RED phase targets)

- Given a synthesized `redirects-dns` plan with 8 creates and 29 pure imports, all on new ids, when the gate runs, then `verdict=PASS creates=8 imports=29 destroys=0`.
- Given the rehearsal shape (scratch root with a `backend "local"` override, mock provider), when it runs state-migrate and plan, then the S3 backend stub records zero writes.
- Given state JSON with 30 old-zone records, 8 old rulesets/lists and 3 old-account R2 buckets, when the state-migrate script runs, then it removes 38, skips the 3 R2 buckets without touching them, and the backup stub ran first.
- Given the six pinned A records returned by a stubbed GET, when the pre-delete runs with `--apply` and the new zone id, then exactly six DELETEs are issued.
- Given the mint script with a stubbed API returning a token, then the id and secret appear only on the `doppler` stub's stdin, never in argv or stdout, and stdout is exactly the UUID.
- (integration) `terraform plan` in CI's credential-free leg with mock providers passes with the new variables (`infra-validation.yml`).

### Regression Tests

- Given `cf_zone_id = 5af02a2f…`, when `terraform plan` evaluates, then validation fails with the #12931 message, so the old-zone apply wedge cannot recur.
- Given the old `seo_config_settings` import block removed, when the tftest runs, then there is no import read against the real provider (no 10000).

### Edge Cases

- A re-run of `redirects-dns` after a partial apply: state-migrate removes 0, imports already in state are ignored, and the gate passes on the remaining creates.
- A rehearsal (`plan_only=true`) leaves the backend state untouched, asserted by comparing the state serial before and after in the job.
- The Phase 0 probe finds a pre-existing new-zone `http_config_settings` entrypoint: the gate refuses a `create` of `seo_config_settings` and the runbook routes to an import.
- `CF_R2_ACCOUNT_ID` is missing: the plan fails at variable resolution, so the job never reaches state-migrate.

### Integration Verification (for `soleur:qa`)

- **API verify:** `curl -sI https://soleur.ai/pages/agents.html | grep -i '^location'` expects the canonical page; `curl -sI https://app.soleur.ai/ | grep -i x-robots-tag` expects `noindex`.
- **Tunnel (PR2):** the census verdict token from `scripts/tunnel-connector-census.sh` reports one connector.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| R2 buckets or the escrow endpoint re-homed by the flip | `cf_r2_account_id` carve-out, Guard 1 row 5, the tftest assertion |
| A forget removes an entry that should stay | Classification per entry, ABORT on unknown, R2 excluded, backup first, idempotent re-run |
| A hand-made ruleset entrypoint in the new zone is silently overwritten | The Phase 0 whole-list probe; the gate refuses a create where the probe found an entrypoint |
| A token lacks a write scope (the 2026-07-24 class) | Write-probes in the job before plan |
| The cert-reissue cron writes DNS on the moved zone | Revoke the old DNS-edit token in the Phase 2 step 2 sequence; the runtime `CF_ZONE_ID` and token copies are written to every config holding them in the same sequence |
| web-2 replace fails | web-1 untouched and `app.soleur.ai` unaffected; the deploy path was already down; the replace re-runs |
| Old zone deleted before PR2 lands | Nothing in the plan reads the old zone after the first dispatch; the snapshots stay on the operator machine |
| Origin CA revoked at zone deletion | Re-minted in Phase 3 before the release redeploy. Cloudflare has not announced the grace length, so treat it as days, not weeks. |
| Concurrent apply clobbers unlocked R2 state | The `cf_account_migrate` job joins the `terraform-apply-web-platform-host` concurrency group |
| Merge conflict with #12873 (bastion) in `apply-web-platform-infra.yml` | Land this PR first; the bastion PR rebases |
| `-target` pulls in a dependency outside the phase set | The gate refuses (Guard 1 row 4), and the target list is then widened by review, never by the gate |

## Domain Review

**Domains relevant:** Engineering, Operations, Marketing

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled F1–F11 plus the F5 re-ruling and two follow-ups (recorded in `decision-challenges.md`). Key risks raised: the LUKS-header escrow endpoint follows `var.cf_account_id`, and the runtime `CF_ZONE_ID` lets the cert-reissue cron write DNS on the moved zone. Both are folded in (Phase 1 items 2 and 12, Phase 0 step 4).

### Operations

**Status:** reviewed
**Assessment:** COO: the old zone's Pro plan cost $0 (ledger, #8754), so Free costs nothing. Recommended defaults: stay on Free and defer Load Balancing ($5/mo base) until web-2 takes LB traffic. Follow-ups: ledger rows (soleur.ai, Load Balancing, old-account R2-only line), revoke the temporary token at the end of the migration rather than at expiry, and record each new token's account and expiry. Capability gap: no invoice-read tool. Money decisions are recorded as operator rows.

### Marketing

**Status:** reviewed
**Assessment:** CMO: parity restore is correct, and noindex, the WAF allowlist and redirects should all land before the tunnel work (they all ship in `redirects-dns`). Recommended beyond scope: an app-level `X-Robots-Tag` fallback (P1), a Search Console check for `app.soleur.ai` token URLs indexed since 16:24 UTC (P1), a sitemap resubmit (P2), and a GPTBot/ClaudeBot fetch check (P2, added to Phase 2 verification). No public status note is needed. The scope additions are recorded as operator (scope) rows.

### Product/UX Gate

Not applicable: no UI surface in Files to Edit/Create (mechanical override did not fire).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6.
- `doppler secrets set` prints every remaining secret to stdout unless redirected. Every write in this plan pipes the value on stdin with `--silent` and stdout to `/dev/null`, then verifies with a separate `get`. (A hook blocked an unredirected form while this plan was being written.)
- Import-id shapes are v4: rulesets use `zone/<zone>/<id>` (singular), records `<zone>/<record>`, Pages `<account>/<project>[/<domain>]`. A v5-shaped id fails as a misleading 10000. The ruleset level must be exactly `zone` or `account`. v4 reads any other prefix, `zones/` included, as account, and silently sends the read to `/accounts/<zone_id>/rulesets/<id>` (measured). Every bare or under-segmented shape fails locally with a format error.
- `terraform state rm a b c` exits 0 and still bumps the serial when an address is missing, skipping it silently (measured on TF 1.10.5). The state-migrate script asserts `Successfully removed N` equals its `rm` set and re-lists state afterwards to confirm zero old-id entries. Exit code plus serial is not enough.
- An `import {}` whose `to` address is outside a phase's `-target` list is dropped with no warning (measured). Guard 1 row 11 (import count against the committed file) is the only thing that catches a missing target.
- `cloudflare_zone_settings_override` has no importer. Its create reads the zone's current settings into `initial_settings` and applies the declared ones, and a destroy reverts to that snapshot: the new zone's hand-restored state, not the old Pro zone's.
- In the scratch rehearsal root, `rm -rf .terraform` before `init -reconfigure`. A stale `.terraform` that records `s3` is tolerated (measured), but the learning `2026-03-21-terraform-state-r2-migration` records a TLS failure from stale backend metadata.
- `plan_only` must never write the backend. The rehearsal runs in a scratch copy with a `backend "local"` override (`-state=` is ignored under the `s3` backend), and the job asserts the remote serial is unchanged. This is part of the contract, not an optimisation.
- `-target=cloudflare_record.app` pulls `hcloud_server.web` and, through its user_data, the tunnel. Any phase before `tunnel` must not name it. Check every record's `content` expression for a resource reference before adding it to a phase.
- Write probes must send an invalid body. A valid `PUT` to a phase entrypoint creates or replaces the ruleset.
- `-target` is transitive upstream. A phase target set that names a record whose `content` references the tunnel pulls in the tunnel. The `deploy`/`ssh`/`registry` records therefore belong only to the `tunnel` phase.
- Better Stack and the census will show expected red states between dispatches (tunnel 0 connectors). The runbook names each expected red so nobody "fixes" one mid-migration.
