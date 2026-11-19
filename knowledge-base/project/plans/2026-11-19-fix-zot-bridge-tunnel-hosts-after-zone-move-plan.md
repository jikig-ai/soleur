---
title: "fix(infra): re-home the registry/deploy/ssh tunnel hosts into the Soleur Cloudflare account after the soleur.ai zone move (zot bridge bad handshake)"
type: fix
date: 2026-11-19
slug: fix-zot-bridge-tunnel-hosts-after-zone-move
branch: feat-one-shot-12937-zot-bridge-handshake
issue: 12937
ref: 12937
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
---

# fix(infra): re-home the registry/deploy/ssh tunnel hosts into the Soleur Cloudflare account

## Overview

Every Web Platform Release push run since 18:15Z on 2026-11-18 has failed at the zot mirror step's
CF-tunnel bridge (`websocket: bad handshake`, then `docker login to zot (127.0.0.1:5000) failed`,
stage `bridge`). Production still serves `43234154a2`.

The cause was measured during planning (see Root Cause). zot is healthy and so is the tunnel. The
`soleur.ai` registration moved to a different Cloudflare account at about 16:24Z on 2026-11-18. The
new zone has no working records for the three tunnel hostnames, and the tunnel lives in the old
account. Cloudflare only routes a `cfargotunnel.com` CNAME to a tunnel in the same account, so the
old tunnel cannot serve the new zone.

This plan re-homes only the tunnel slice into the Soleur account: the tunnel, its config, three
Access apps with their policies and service tokens, the three DNS CNAMEs, and the token-expiry
alert. It then re-bakes the connector token into web-2 through the existing `web-host-replace`
path. It also makes the release job name this class of failure (Cloudflare edge error, NXDOMAIN,
tunnel down) instead of `gate-indeterminate`, and prints one `SOLEUR_ZOT_BRIDGE` line with the
measured cause. Finally it re-runs the two blocked push runs and runs `soleur:postmerge` for
`5d4851f7af`.

The rest of the account migration stays in #12931: redirect rulesets, LB, the Pro-vs-Free decision,
Pages secrets, `cf_zone_id`/`cf_account_id`, and teardown of the old-account copies.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief / first draft) | Reality (measured) | Plan response |
|---|---|---|
| #12937: "Whether zot itself is up … or only the tunnel's origin side is down" | zot up: `SOLEUR_ZOT_DISK` every 5 min across 2026-11-18 12:00Z → 2026-11-19 09:00Z, `zot_restarts=0`, `zot_uptime_s≈1.97M`, `state_status=running`. Tunnel `fc4509ed…` `healthy`, 4 connections. | Neither zot nor the connector is the fault; fix the DNS/account layer. |
| #12937: "a tunnel outage (530) looks like this" (job's diagnosis) | Edge answered **403 Cloudflare Error 1000** (DNS points to prohibited IP) on `registry.`/`ssh.`; `deploy.` is **NXDOMAIN**. | Classifier gains `edge-error-<NNNN>`, `host-nxdomain`, `tunnel-down` (Phase 2). |
| Brief: tunnel slice can move by changing `var.cf_zone_id`/`var.cf_account_id` | 47 / 20 references; changing them moves every zone resource (#12931 scope) | New committed `locals` + new `_soleur` addresses (CTO Item 2). |
| Brief: the push apply carries the whole slice | Push `-target` list includes tunnel, config, deploy/ssh apps + policies, `ci_ssh` token, `cloudflare_record.deploy/ssh`; **omits** every registry address (they are in `OPERATOR_APPLIED_EXCLUSIONS`, `plugins/soleur/test/terraform-target-parity.test.ts` registry block) | New registry addresses ride the merge apply's `-target` list; old ones stay excluded (CTO Item 2 amendment). |
| `tunnel.tf` comment: `-replace` of `registry_push` token re-writes Doppler | `doppler_secret.registry_push_access_token_*` carry `ignore_changes = [value]`, so a new token does **not** reach Doppler | `replace_triggered_by` on the new token + comment fix. |
| `deploy` service token is Terraform-managed | Hand-minted (`removed {}` block in `tunnel.tf`; `local.deploy_service_token_ids` pins `d9204def…`); read from GitHub repo secrets, Doppler `soleur-infra-privileged/prd`, Doppler `soleur/prd_terraform` (TF var feeding `server.tf` `push-infra-config.sh` local-exec) | Mint in the new account via API; write every copy; hash-equality check. |
| Verify step proves the tunnel | `verify-tunnel-ingress-origin.sh` reads tunnel id from state address `…tunnel_cloudflared.web` and `CF_ACCOUNT_ID` from Doppler (old account); never checks `registry.` | Repoint to the new address, read account id from a TF output, add `registry.`. |
| 16:33Z `supabase-ref-resolver` failure may be a separate defect | Same incident: `api.soleur.ai` in the new zone was scanner-created 16:03Z and only hand-fixed to an unproxied CNAME at 17:09:57Z; the resolver's `dig CNAME` fallback could not see `*.supabase.co` at 16:34Z. Every run since 18:15Z passes both Supabase validation steps. | Not separate. No new issue filed. Recorded in Root Cause. |

## Root Cause (measured, 2026-11-19 ~10:00Z, read-only)

Timeline:

| Time (UTC, 2026-11-18) | Event | Evidence |
|---|---|---|
| 15:54 | Last green release (`43234154a2`) | run 44341012353 |
| 16:03 | New zone `951ce525…` (Soleur account `66d4f93f…`, Free) populated by import scan. `registry`/`ssh` become 3 proxied A records each to Cloudflare anycast IPs; `deploy` absent | CF API `modified_on` 16:03:09Z |
| ~16:24 | Registration moves; public NS → `laila`/`lennon`; old zone `5af02a2f…` (Pro) → status `moved` | CF API zone object; #12931 |
| 16:33–16:35 | Push apply 44348560918: creates 2 Better Stack monitors, then fails "Verify tunnel ingress origins" with `deploy.soleur.ai/hooks/deploy-status` → `HTTP 000` (NXDOMAIN). Release 44348563238 fails at `supabase-ref-resolver` | job logs |
| 17:09:57 | `api.soleur.ai` hand-fixed to unproxied CNAME in new zone | CF API |
| 18:15 → | Every release push run fails at the bridge (`websocket: bad handshake`) | runs 44367779280, 44375972612, 44427650817 |

Live state now:

- `https://registry.soleur.ai/v2/` and `https://ssh.soleur.ai/` → 403, Cloudflare **Error 1000**,
  no `cf-access-*` header.
- `deploy.soleur.ai` → NXDOMAIN at 1.1.1.1 and 8.8.8.8.
- `app.soleur.ai` → fine. It is a proxied A record to web-1 and does not use the tunnel.

The old account still holds the tunnel `soleur-web-platform` (`fc4509ed-91fd-4b9a-b613-6de8e649b8d7`)
and its 3 Access apps: Registry Push (CI), SSH (CI runner), Deploy Webhook. The tunnel ingress is
`deploy.→http://10.0.1.10:9000`, `ssh.→ssh://10.0.1.10:22`, `registry.→tcp://10.0.1.30:5000`.
The new account has 0 tunnels, 0 Access apps and 0 service tokens.

Cloudflare docs (`cloudflare-docs` dns-records-intro): "The `cfargotunnel.com` subdomain only proxies
traffic for DNS records in the same Cloudflare account."

**Why the job could not see it:** the token preflight's uncredentialed control probe
(`scripts/check-cloudflare-token-drift.sh` `access_probe()`) discards the response body
(`-o /dev/null`). So the Error 1000 page fell to `gate-indeterminate`, and NXDOMAIN folds into
`host-unreachable`. No registry-side or Better Stack row can show an edge-side DNS fault. This is the
"cause not visible in telemetry" case the brief names, so the marker is in scope.

## Hypotheses

Network-outage checklist (L3 → L7), applied because the symptom names `handshake`:

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | verified not causal | The registry host firewall is deny-all-public by design (ADR-096). CI reaches it only through the tunnel, never through a public port, so no allow-list sits on this path. The connector (web-2) reaches `10.0.1.30` over the private net, and that path is unchanged: zot keeps serving web-host pulls, and `SOLEUR_ZOT_DISK` `ping_rc=0`. |
| L3 DNS / routing | **verified causal** | DoH: `deploy.soleur.ai` Status 3 (NXDOMAIN); `registry`/`ssh` resolve to CF anycast 188.114.96.3/97.3; public NS `laila`/`lennon` ≠ Terraform zone NS `bradley`/`nora` (zone `status: moved`). |
| L7 TLS / proxy | verified causal (symptom of L3) | `curl -D -` on `registry.soleur.ai/v2/`: `HTTP/2 403`, `server: cloudflare`, body `errorCode: 1000`, no `cf-access-aud`/`cf-access-domain`. |
| L7 application (zot / cloudflared) | verified healthy | `SOLEUR_ZOT_DISK` rows (zot running, 0 restarts); CF API tunnel `status: healthy`, 4 connections on cloudflared 2026.10.4. |

## Proposed Solution

Option A, ruled by the CTO: move only the tunnel slice now. New resource addresses in the Soleur
account and zone sit beside the untouched old-account addresses. The connector re-bakes through
`web-host-replace web-2`. Old-account teardown comes in a follow-up PR (new issue, Phase 7).

### Implementation Phases

#### Phase 0 — Preconditions (gate everything after)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- lint-infra-ignore start: the two items below are Cloudflare dashboard-only acts no repo credential can perform (no token with API-Tokens:Edit exists; the v4 provider cannot mint account tokens — cf-cert-reissue-token.tf); CTO Items 3 and 6 classify them operator-only, and the ## Infrastructure (IaC) section routes everything else through Terraform. Every other step is agent-executed. -->
0.1 Widen the existing user token behind Doppler `soleur/prd_terraform` `CF_API_TOKEN` in place. This
    is operator-only, in the Cloudflare dashboard. Add, for account `66d4f93f7397f196544e9fe84c3557c2`:
    Cloudflare Tunnel Edit, Access: Apps and Policies Edit, Access: Service Tokens Edit,
    Access: Organizations Read, and Notifications Edit. Add DNS Edit on zone
    `951ce525552201ec6c696b24251abed7`. No new secret is minted (CTO Item 3).
0.2 Confirm Zero Trust is enabled on the Soleur account. First, the agent tries a read-only
    `GET /accounts/66d4…/access/organizations` with the widened token. Only if it is absent, the
    operator enables Zero Trust (Free plan) in the dashboard. If Cloudflare asks for a payment method,
    that is a money decision and needs an explicit operator go.
<!-- lint-infra-ignore end -->
0.3 The agent verifies both, read-only: `/user/tokens/verify` is active; GETs on new-account
    `cfd_tunnel`, `access/apps`, `access/service_tokens` and `access/organizations` return
    `success:true`. Record the outputs in the PR body.

#### Phase 1 — Terraform tunnel slice (code)

1.1 `apps/web-platform/infra/tunnel.tf`:
    - Add committed `locals`: `cf_soleur_account_id = "66d4f93f7397f196544e9fe84c3557c2"`,
      `cf_soleur_zone_id = "951ce525552201ec6c696b24251abed7"`, and
      `deploy_service_token_ids_soleur = ["<new deploy token id from Phase 3.1>"]`, with the same
      UUID-shape precondition as `local.deploy_service_token_ids`.
    - Add `random_id.tunnel_secret_soleur` and `cloudflare_zero_trust_tunnel_cloudflared.web_soleur`
      (`account_id = local.cf_soleur_account_id`, `config_src = "cloudflare"`, no `ignore_changes`
      import artifact).
    - Add `cloudflare_zero_trust_tunnel_cloudflared_config.web_soleur` with the **same three
      origin-relative ingress rules** (`deploy.→http://<web-1 private_ip>:9000`, `ssh.→ssh://…:22`,
      `registry.→tcp://10.0.1.30:5000`, catch-all `http_status:404`). Derive them from the same
      expressions as `_config.web` so ADR-114 I2 holds, and never use a literal.
    - Add `cloudflare_zero_trust_access_application.{deploy,ssh,registry}_soleur`,
      `cloudflare_zero_trust_access_policy.{deploy_service_token,ci_ssh_service_token,registry_push_service_token}_soleur`,
      `cloudflare_zero_trust_access_service_token.{ci_ssh,registry_push}_soleur` and
      `cloudflare_notification_policy.service_token_expiry_soleur`, all on `local.cf_soleur_account_id`.
      Mirror the attributes of the old blocks: session duration, `app_launcher_visible`, decision
      `non_identity`, and exactly one `include { service_token = [...] }`.
    - Repoint `doppler_secret.registry_push_access_token_{id,secret}` values to `…registry_push_soleur`
      and add `lifecycle { replace_triggered_by = [cloudflare_zero_trust_access_service_token.registry_push_soleur] }`.
      Keep `ignore_changes = [value]`.
    - Fix the comment that claims `-replace` of the token rewrites Doppler.
    - Repoint `output "tunnel_token"` and `output "ci_ssh_access_service_token_client_{id,secret}"` to
      the `_soleur` resources. Add `output "cf_tunnel_id"`, `output "cf_tunnel_account_id"`
      (= `…tunnel_cloudflared.web_soleur.account_id`, not the bare local: a constant-valued output
      depends on no targeted resource and may not be written by a `-target` apply) and
      `output "cf_tunnel_zone_id"` (= `cloudflare_record.deploy_soleur.zone_id`, read by Guard 4).
    - Leave the old blocks untouched (CTO Item 2: no forget, no destroy in this PR).
1.2 `apps/web-platform/infra/dns.tf`: add `cloudflare_record.{deploy,ssh,registry}_soleur` with
    `zone_id = local.cf_soleur_zone_id`, CNAME to `${…web_soleur.id}.cfargotunnel.com`, proxied,
    `ttl = 1`. Leave the old three untouched.
1.3 `apps/web-platform/infra/server.tf` (the `tunnel_token = …` line in the `hcloud_server.web` cloud-init
    render): change it to `cloudflare_zero_trust_tunnel_cloudflared.web_soleur.tunnel_token`. web-1 and
    web-2 see no diff because `ignore_changes = [user_data, …]`. Only web-2's next create picks it up.
1.4 `.github/workflows/apply-web-platform-infra.yml` push-plan `-target` list: add every new address
    from 1.1–1.2, including the registry ones, and the two `doppler_secret.registry_push_access_token_*`.
    Old addresses are unchanged.
1.5 `plugins/soleur/test/terraform-target-parity.test.ts`: the new registry addresses are push-applied.
    Do not add them to `OPERATOR_APPLIED_EXCLUSIONS`. **Remove** `doppler_secret.registry_push_access_token_{id,secret}`
    from the registry block of `OPERATOR_APPLIED_EXCLUSIONS`, because 1.4 now push-targets them; every
    other old registry address stays excluded. Keep the coverage test green.
1.6 `tests/scripts/lib/deploy-policy-gate.sh` + `tests/scripts/lib/destroy-guard-filter-web-platform.jq`:
    add a branch for `cloudflare_zero_trust_access_policy.deploy_service_token_soleur`. Its single
    **create** is allowed only with an own-line `[ack-deploy-policy]` and exactly one `include` block
    whose `service_token` equals `local.deploy_service_token_ids_soleur`. Mechanism: plan JSON carries
    no locals, so the apply step extracts the committed id list from `tunnel.tf` (the same anchored
    `deploy_service_token_ids_soleur = [...]` line the UUID precondition reads) and passes it to the jq
    filter with `--argjson ids`; the filter compares the planned
    `include[0].service_token` to `$ids` and emits a count the gate reads. A delete, or a second include
    block, stays `deploy_policy_unsafe`. The old address must still plan as no change, or the gate
    reds. Add rows to `tests/scripts/test-deploy-access-token-forget.sh` (or a sibling suite) per the
    Guard 2 matrix.
1.7 `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh`:
    - read the tunnel id from `terraform output -raw cf_tunnel_id` and the account from
      `terraform output -raw cf_tunnel_account_id`, not from Doppler `CF_ACCOUNT_ID`;
    - assert the `registry.` rule `== tcp://10.0.1.30:5000` alongside `deploy.`/`ssh.`;
    - extend `apps/web-platform/infra/verify-tunnel-ingress-origin-infradir.test.sh` per Guard 3.

1.8 `.github/workflows/apply-web-platform-infra.yml` push `apply` job (CTO ruling, fork 1):
    - move "Verify DOPPLER_TOKEN_WRITE present" and "Sync CF Access CI-SSH service token to Doppler"
      to run directly after "Terraform apply" (`if: success()` on the apply), before "Verify tunnel
      ingress origins";
    - in the sync step, when the `ci_ssh` outputs are empty AND this run's plan JSON creates or replaces
      a `cloudflare_zero_trust_access_service_token.ci_ssh*`, print `::error::` and fail (today it warns
      and exits 0, "Falling back to operator sync", leaving the old pair in Doppler with nothing red).
1.9 `verify-tunnel-ingress-origin.sh`: when the data-plane probe fails, read the tunnel's connection
    count from the CF API and print `SOLEUR_TUNNEL_VERIFY cause=no-connector tunnel=<id> connections=0`
    (or `cause=<other measured cause>`), write a one-paragraph explanation to `$GITHUB_STEP_SUMMARY`
    when the cause is `no-connector` (expected before the connector re-bake; see #12937), then **still
    exit non-zero**. No zero-connector pass path is
    added: a dead connector on a future apply must stay red (CTO ruling, fork 1, rejecting the advisor's
    green-skip).

#### Phase 2 — Make the cause visible (classifier + marker)

2.1 `scripts/check-cloudflare-token-drift.sh` `access_probe()`: write the response body to a
    `mktemp` file capped at 64 KiB instead of `/dev/null`, and delete it in the same function. Never
    print the body.
    `verify_access_pair()` control ladder:
    - curl exit 6 → `host-nxdomain` (previously folded into `host-unreachable`). Today
      `access_probe` discards curl's rc (`(( rc != 0 )) && PROBE_CODE=000`) and the ladder grades `000`
      as unreachable first, so export `PROBE_CURL_RC` and branch on 6 **before** the unreachable arm;
    - unstamped 530, or body error code 1033 → `tunnel-down`;
    - unstamped 403/5xx whose body matches the Cloudflare error-page code
      (`errorCode: <NNNN>` / `error code: <NNNN>`, `^1[0-9]{3}$`) → `edge-error-<NNNN>`;
    - everything else unstamped and non-2xx → `gate-indeterminate` (unchanged).
    Add the new causes to the detector's row switch and grep summary.
2.2 `scripts/zot-mirror-diagnosis.sh`:
    - remedies in `zot_mirror_cause_help` for each new cause. `edge-error-1000` and `host-nxdomain`
      say "the tunnel hostname's DNS record is wrong or missing in the zone that is authoritative
      for `<base>`; compare public NS with the Terraform zone (#12931)".
    - new helper `zot_bridge_marker <stage> <verdict> <cause> <host> <rc>` prints exactly
      `SOLEUR_ZOT_BRIDGE stage=<listener|login|push> verdict=<v> cause=<c> host=<h> rc=<n> runbook=knowledge-base/engineering/operations/runbooks/zot-registry-revert.md`
      (the `runbook=` field mirrors `SOLEUR_GHCR_PUSH_FAILED`). An unknown
      cause prints `cause=unknown`. The line carries no token ids, secrets or bodies (CTO Item 7).
2.3 `.github/actions/cf-tunnel-registry-bridge/action.yml`: in both failure branches (listener never
    bound; docker login failed), print the marker once to stderr through the helper.
2.4 `.github/workflows/reusable-release.yml` mirror failure path: print the same marker, and append
    the identical line to the notify-ops email body.
2.5 Tests: `scripts/check-cloudflare-token-drift.test.sh` uses `MOCK_HTTP_BODY` and `MOCK_CURL_EXIT=6`
    rows. `scripts/zot-mirror-diagnosis.test.sh` keeps the cause-set ⇔ remedy-set equality and adds
    marker field-order and unknown-cause rows. Both follow Guard 1.
2.6 `.github/workflows/scheduled-terraform-drift.yml`: add an alerting step (not an apply
    preflight) for the zone that carries the tunnel hostnames (`local.cf_soleur_zone_id`). If its
    `status != active`, or public NS (DoH 1.1.1.1) ≠ the zone's `name_servers`, it files or updates one
    deduped `ci/tunnel-zone-authority` issue. The old `var.cf_zone_id` mismatch stays #12931's
    (Guard 4).

#### Phase 3 — Credentials and DNS hygiene (agent, one script, one operator go)

Phases 3.1-3.3 use one credential (the widened `CF_API_TOKEN`) and run as one agent-executed script
under a single operator go (`hr-multi-step-post-merge-bootstrap-script`), staged and idempotent, each
stage verifying before the next. **Sequencing:** 3.1 runs before the commit that writes the id into
`local.deploy_service_token_ids_soleur`; until that commit lands, the PR's validation plan is expected
red on the UUID precondition, so run 3.1 as soon as Phase 0 is done.

3.1 Mint the deploy service token in the new account through the API with the widened token. Write the
    secret straight to Doppler without printing it. Put its id in `local.deploy_service_token_ids_soleur`
    (committed) before merge.
3.2 Write the deploy pair to **every** reader, which was enumerated read-only during planning:
    - GitHub repo secrets `CF_ACCESS_CLIENT_ID`/`_SECRET`, through the infra GitHub App installation
      token, never a PAT (`hr-github-app-auth-not-pat`);
    - Doppler `soleur-infra-privileged/prd`;
    - Doppler `soleur/prd_terraform`, which is the TF var source for `server.tf` `push-infra-config.sh`.
    All three are written from one in-memory value in one script invocation. Verify the two Doppler
    copies by sha256 (never printed) against the minted value's sha256. GitHub secrets cannot be read
    back, so the GitHub copy is proven behaviourally: the Phase 6.3 deploy arm's
    `deploy.soleur.ai/hooks/deploy-status` call passing Access.
3.3 Any time before merge, delete the 6 scanner-made A records (`registry`×3, `ssh`×3) in the new zone
    (DNS Edit) with a one-time API call, so the CNAME creates do not conflict. Per item
    (`hr-bulk-delete-per-item-live-infra-role-check`): read the record, confirm type `A`, proxied, name
    `registry`/`ssh`, content a Cloudflare anycast address, created by the 16:03Z scan; delete by record
    id; re-read to confirm absence. They already serve Error 1000, so there is no added impact. If a
    record reappears, the merge apply's CNAME create fails loudly (Cloudflare refuses a CNAME beside an
    A), which is the protection; no workflow delete step is added (CTO ruling, fork 2).

#### Phase 4 — Merge and merge-apply

4.1 Merge with `[ack-deploy-policy]` and `[ack-destroy]`, each on its own line. The destroy is the
    `replace_triggered_by` replacement of the two registry `doppler_secret`s. Expect the push apply to
    create every new resource, publish the new CI-SSH pair (step moved, Phase 1.8), then go red at
    "Verify tunnel ingress" with `SOLEUR_TUNNEL_VERIFY cause=no-connector … connections=0`, because the
    new tunnel has no connector yet. Any other red cause is a real failure. **Nothing may be destroyed
    except the two Doppler secrets.** Assert this from the plan JSON in the run log.
4.2 Confirm from the API that the new tunnel exists with 0 connections. Confirm the 3 Access apps and
    policies exist, and that Doppler `prd` `REGISTRY_PUSH_ACCESS_TOKEN_ID` equals the new token's client
    id (written by the apply itself via `replace_triggered_by`), and that Doppler `prd_terraform`
    `CI_SSH_ACCESS_TOKEN_ID` equals the new `ci_ssh_soleur` client id (sha256 of the secret matches the
    state output, never printed). Today's step order ("Terraform apply" → "Verify tunnel ingress"
    `if: success()` → "Sync CF Access CI-SSH service token to Doppler" default `success()`) would skip
    the sync on the expected red, and relying on the Phase 6 re-run to self-heal rests on the unverified
    claim that the v4 provider keeps `client_secret` readable after refresh (`tunnel.tf` #4492 comment).
    Phase 1.8 moves the sync, so this check holds on the merge run itself.

4.3 Second push-triggered apply woken by this diff: `.github/workflows/apply-deploy-pipeline-fix.yml`
    has `apps/web-platform/infra/server.tf` in its `paths:`. Its "CF Tunnel SSH bridge" step runs
    **before** its "Terraform plan" step, so with `ssh.` down the merge run fails at the bridge, never
    plans and creates nothing. Expected red; re-dispatch it (`workflow_dispatch`, reason
    "#12937 post-bridge") after Phase 6.1. Note for that re-dispatch: its `-target` set depends on
    `hcloud_server.web[...]`, whose `user_data` references the new tunnel token, so `-target`
    transitivity reaches `…tunnel_cloudflared.web_soleur`; by then it exists, so it plans no-op. Both
    workflows share concurrency group `terraform-apply-web-platform-host`. Other apply workflows on
    this root are dispatch-only or path-filtered to files this diff does not touch
    (`registry-host-replace-dispatch.yml` → `cloud-init-registry.yml`; `validate-vector-config.yml` →
    inngest cloud-init), measured 2026-11-19.

#### Phase 5 — Connector re-bake (web-2)

5.1 Check stock for web-2's `server_type` (`cpx22`, hel1) through the Hetzner API, using the runbook's
    stock preflight.
5.2 Dispatch `apply-web-platform-infra.yml` with `apply_target=web-host-replace web_host_key=web-2
    confirm=REPLACE-web-2`. The operator's `web-platform-infra-apply` environment approval is the go
    for this act; no separate go is asked. Arm a Monitor watch on the run (`hr-dispatch-async-must-arm-watch`).
    The gate allow-set is exactly the four web-2 addresses. Any tunnel diff aborts, which is why Phase 4
    must already be applied.
5.3 Verify: the new tunnel has ≥1 connection from web-2 (CF API `cfd_tunnel/<id>/connections`).

#### Phase 6 — Prove the fix, then unblock the releases

6.1 Dispatch `apply_target=manual-rerun` (or re-run the Phase 4 push apply). It must be green,
    including "Verify tunnel ingress origins" with `deploy.`, `ssh.` and `registry.` checked against
    the new tunnel.
6.2 Run `doppler run -p soleur -c prd_terraform -- bash scripts/check-cloudflare-token-drift.sh`. It
    must report `REGISTRY_PUSH_ACCESS_TOKEN` and `CI_SSH_ACCESS_TOKEN` LIVE in every config.
6.3 The brief already authorizes these re-runs ("re-run the failed push runs"); no separate go.
    Re-run the failed push runs in chronological order, each with `gh run rerun <id> --failed`, then
    its workflow_run deploy arm:
    - 44375972612 (`5d4851f7af`, #12935), then deploy arm 44376350232;
    - 44427650817 (`52bf12cc5b`, #12704), then deploy arm 44427961170;
    - this PR's own merge push run if it failed at the bridge.
    `deploy-arm.sh`'s ancestry rule refuses to deploy a SHA older than production, so an
    older re-run concludes "superseded" rather than rolling back. Runs 44348563238 (`7e1d286ebe`) and
    44367779280 (`9577d98f5e`) are ancestors of `52bf12cc5b` and are not re-run.
6.4 Verify production serves the newest SHA: `plugins/soleur/scripts/deploy-arm.sh served <sha>` →
    `CONTAINED`, and `/health` version matches.
6.5 Run `soleur:postmerge` for the `5d4851f7af` merge (#12935).

#### Phase 7 — Follow-ups (filed in this PR, not implemented)

7.1 New issue: tear down the old-account slice. Its body lists exactly:
    - every old address (tunnel, config, 3 Access apps + policies, `ci_ssh`/`registry_push` tokens,
      `service_token_expiry`, 3 records) and the hand-minted old deploy token;
    - `local.deploy_service_token_ids` (old) and the old registry rows in `OPERATOR_APPLIED_EXCLUSIONS`;
    - whether the `_soleur` suffix is dropped via `moved {}` blocks or kept on purpose;
    - flipping ADR-329 to `accepted`.
    Due date: the API does not expose the moved zone's deletion date (`GET /zones?status=moved` on
    2026-11-19 returned `deleted_at: null`, `modified_on 2026-11-19T04:11Z`, no purge field), so set it
    to 2026-11-25 and have the issue's first step re-read the zone status. Old-zone resources still in
    state when Cloudflare purges the zone need `removed {}` forgets rather than destroys. Milestone from
    the roadmap, `Ref #12931`.
7.2 Comment on #12931 that its "Tunnel hosts" checkbox is done by this PR, with what remains.

## Files to Edit

- `apps/web-platform/infra/tunnel.tf`
- `apps/web-platform/infra/dns.tf`
- `apps/web-platform/infra/server.tf`
- `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh`
- `apps/web-platform/infra/verify-tunnel-ingress-origin-infradir.test.sh`
- `.github/workflows/apply-web-platform-infra.yml`
- `.github/workflows/reusable-release.yml`
- `.github/workflows/scheduled-terraform-drift.yml`
- `.github/actions/cf-tunnel-registry-bridge/action.yml`
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `tests/scripts/lib/deploy-policy-gate.sh`
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq`
- `tests/scripts/test-deploy-access-token-forget.sh`
- Guard suites that reference the touched resource types (from `git grep -ln
  'zero_trust_tunnel|zero_trust_access_(policy|application|service_token)' -- tests/ scripts/
  plugins/soleur/test/ .github/ apps/web-platform/infra/`); run each, edit if red:
  `apps/web-platform/infra/tunnel-origin-relative-ingress.test.sh`,
  `scripts/cf-tunnel-liveness-gate-mutations.test.sh`,
  `tests/scripts/test-destroy-guard-counter-web-platform.sh`,
  `tests/scripts/test-preapply-entrypoint-gate.sh`, `tests/scripts/test-trio-baseline-census.sh`,
  `tests/scripts/fixtures/tfplan-web-platform-real-baseline.json`
- `scripts/check-cloudflare-token-drift.sh`
- `scripts/check-cloudflare-token-drift.test.sh`
- `scripts/zot-mirror-diagnosis.sh`
- `scripts/zot-mirror-diagnosis.test.sh`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (tunnel container + Cloudflare system descriptions)
- `knowledge-base/engineering/operations/runbooks/cloudflare-service-token-rotation.md` (new-account copy list)
- `knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` ("grep for" section naming
  `SOLEUR_ZOT_BRIDGE` and `SOLEUR_TUNNEL_VERIFY`; remedies point at `zot_mirror_cause_help`, not copied)
- `.github/workflows/scheduled-inngest-health.yml` "Census tunnel connectors (ADR-114 I1)" and
  `scripts/tunnel-connector-census.sh`: today they read Doppler `CF_ACCOUNT_ID` (old account) and
  look up `cfd_tunnel?name=soleur-web-platform`, so after Phase 5 they report `zero_connectors` every
  run while nothing watches the new tunnel. Repoint to the Soleur account id and the new tunnel; the id
  literal lives once in the script with a parity test asserting it equals `local.cf_soleur_account_id`.
  Other `CF_ACCOUNT_ID` readers (`cf-lb-overlay.yml`, `scheduled-followthrough-sweeper.yml`,
  `ga-lb-pool-soak-6027.sh`) are zone/LB scope and stay #12931's (noted in the follow-up).
- `.github/workflows/apply-web-platform-infra.yml` `ci_ssh_token_replace` job: repoint its hard-coded
  `-replace=…service_token.ci_ssh` to `…ci_ssh_soleur`, or it rotates the dead token and re-syncs the
  unchanged new pair.
- `knowledge-base/operations/expenses.md` (soleur.ai row: Free zone in the Soleur account)
- `knowledge-base/operations/domains.md` (three tunnel CNAMEs)

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-329-tunnel-and-access-gate-live-in-the-zone-owning-account.md` (ordinal provisional; ship's ADR-ordinal gate re-checks)

## Research Insights

**Premise Validation.**

- #12937 is open (p1, bug). #12931 is open (p1) and documents the registration move; its "Tunnel
  hosts" checkbox is this outage. Epic #9601 is open. #12863 and #12920 are open and out of scope.
- Collision pre-check: PR #12958 is this branch's own draft, so it is benign. The foreign `test-all.sh`
  processes are in the unrelated `feat-12866-bastion-host` worktree.
- Open draft PR #12873 (bastion host, ADR-327) edits `.github/workflows/apply-web-platform-infra.yml`.
  Expect a rebase conflict, so re-sync before merge.
- Commits `5d4851f7af` and `52bf12cc5b` are on `origin/main`. Both push runs failed in `release /
  release` at the mirror step.

**Property List.**

- P1: a release push run's mirror reaches zot through `registry.soleur.ai`.
- P2: the deploy arm reaches `deploy.soleur.ai/hooks/deploy-status` and `/hooks/deploy`.
- P3: CI SSH through `ssh.soleur.ai` works (the push apply's SSH stage).
- P4: a failure of this class names its measured cause in the job log and ops email.
- P5: the two blocked releases deploy, and postmerge runs for `5d4851f7af`.
- P6: the next move of the tunnel zone pages instead of silently failing releases.

**Cut List.**

- "Re-point the new zone at the old tunnel" → P1–P3 → refuted by Cloudflare docs (same-account only).
- "Full #12931 migration" → P1–P3 → covered by the tunnel slice alone. The rest is blocked on money
  decisions (CTO Item 1).
- "WARP private routing" → P1 → not P2; a new ingress mode (CTO Item 1).
- "Separate `SOLEUR_REGISTRY_EDGE_PROBE` probe" → P4 → covered by the extended classifier; the marker
  only renders it (CTO Items 4 and 7).
- "Apply-time precondition on zone status" → P6 → would block every apply until #12931; covered by
  the drift step.
- "Leaked Service Token Alert" policy (hand-made in old account) → not on P1–P6 → stays in #12931.

**Files and anchors (repo research).**

- Tunnel token reaches a host only via `cloud-init.yml` `cloudflared service install ${tunnel_token}`,
  gated by `web_tunnel_connector`.
- `hcloud_server.web` sets `ignore_changes = [user_data, ssh_keys, image, placement_group_id]`.
- `var.web_hosts`: web-2 `tunnel_connector = true`, validation "exactly one".
- `web_host_replace` job, `apply-web-platform-infra.yml` `web_host_replace:`:
  - environment `web-platform-infra-apply` (reviewer), `confirm=REPLACE-<key>`, refuses web-1;
  - no SSH bridge, no `deploy.`/`ssh.` use;
  - gate allow-set in `tests/scripts/lib/web-host-replace-gate.sh`.
- Destroy guard counts any delete (`destroy-guard-filter-web-platform.jq` `resource_deletes`).
  `access_token_stray_forgets` is un-ackable. `deploy-policy-gate.sh`: a create or delete of the deploy
  policy is `deploy_policy_unsafe`.
- Classifier: `check-cloudflare-token-drift.sh` `access_probe()` / `verify_access_pair()`;
  `zot-mirror-diagnosis.sh` `zot_mirror_cause_help()`. Tests: `check-cloudflare-token-drift.test.sh`
  (curl stub with `MOCK_HTTP_BODY`, `MOCK_CURL_EXIT`); `zot-mirror-diagnosis.test.sh` (cause/remedy
  set equality).
- `registry-host-replace-dispatch.yml` wakes on `variables.tf`, but this plan does not edit
  `variables.tf`. Its render-diff gate makes an unrelated wake `deliver=false`.
- Doppler copies (names only, read 2026-11-19):
  - `REGISTRY_PUSH_ACCESS_TOKEN_*` in `soleur/prd` root, inherited by 9 `prd_*` branch configs;
  - `CI_SSH_ACCESS_TOKEN_*` in `soleur/prd_terraform`;
  - `CF_ACCESS_CLIENT_*` in `soleur/prd_terraform` and `soleur-infra-privileged/prd`, plus the GitHub
    repo secrets.

**Institutional learnings applied.**

- ADR-166 and the 2026-08-03 post-mortem: a CI message names only a measured cause. The classifier
  extension measures; it does not guess.
- ADR-304: connector placement lives on replaceable web-2, and re-bake goes through `web-host-replace`.
- ADR-154: repair the credential channel. Write-once secrets need explicit re-write; hence
  `replace_triggered_by`.
- `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`: no deletions
  ride this PR.
- `2026-11-16-web2-kernel-currency-replace-five-operational-traps.md`: before any mutating dispatch,
  confirm via `gh run view --json jobs` that no earlier queued run applied. The infra apply and
  `cf-lb-overlay.yml` share a concurrency group.
- `2026-03-21-cloudflare-tunnel-server-provisioning.md`: Bot Fight Mode can block the deploy webhook
  before Access. Check the new zone's bot settings in Phase 6.1 (the old zone was Pro with
  `cloudflare_bot_management`).
- `2026-11-08-a-merge-that-edits-registry-cloud-init-auto-replaces-the-registry-host…`: enumerate the
  push-path workflows woken by this diff. Apply, infra-validation and the registry dispatcher are
  woken (the last is a `deliver=false` no-op).

**External docs.** Cloudflare `dns-records-intro` partial (same-account `cfargotunnel.com` routing);
Cloudflare error 1000 "DNS points to prohibited IP".

**CLAUDE.md conventions.** No SSH in runbooks; IaC for every resource; GitHub App auth, not PAT.

## Open Code-Review Overlap

1 open scope-out touches these files: #2197 (billing `SubscriptionStatus` / single-instance throttle
doc) names `apps/web-platform/infra/server.tf` only as context for a `count = 2` warning.
**Acknowledge:** different concern (rate-limiter singleton docs). This plan changes one cloud-init
input line and adds no `count`/`for_each`.

## Downtime & Cutover

- **Offline-inducing operation:** the `web-host-replace` of web-2, the sole tunnel connector
  (destroy + create). The surface it affects is the management plane only (`deploy.`, `ssh.`,
  `registry.`). That plane is **already fully down** since ~16:24Z on 2026-11-18. `app.soleur.ai` is a
  proxied A record to web-1 and is untouched.
- **Zero-downtime path (default, taken):** blue-green at the tunnel layer. The new tunnel, Access apps
  and CNAMEs are created beside the old ones (Phase 4). The connector moves when web-2 is reborn
  (Phase 5). The old tunnel keeps its connector until then and is retired by the follow-up teardown.
  No step takes down a surface that is up today.
- **Per-stage verification / rollback:**
  - Before Phase 5: a revert PR removes the new resources (nothing uses them).
  - After Phase 5: forward-only, because the old tunnel cannot serve the new zone. A failed web-2 birth
    follows `fresh-host-bootstrap-recovery.md` (re-dispatch `web-host-replace`); web-1 keeps serving
    users throughout.
- **Residual downtime:** none added for users. The management-plane outage ends at Phase 6.1.

## Infrastructure (IaC)

### Terraform changes

- Root `apps/web-platform/infra/` (existing, R2 backend):
  - `tunnel.tf`: new `_soleur` tunnel, config, Access apps/policies/tokens, notification policy,
    locals, outputs;
  - `dns.tf`: 3 new CNAMEs;
  - `server.tf`: one render input.
- Provider `cloudflare/cloudflare ~> 4.0` (unchanged); default provider; token
  `TF_VAR_cf_api_token` ← Doppler `soleur/prd_terraform` `CF_API_TOKEN` (widened, Phase 0.1).
- Sensitive values: tunnel token (state, sensitive output), `ci_ssh_soleur`/`registry_push_soleur`
  client secrets (state + Doppler). The deploy token is outside Terraform (ADR-241 D10).

### Apply path

- (b)-shaped, two steps:
  1. merge-triggered targeted apply (creates only; two Doppler secret replaces behind `[ack-destroy]`);
  2. `web-host-replace web-2` (destroy + create of the cattle standby).
- Blast radius: web-2 only. Expected window ~10–15 min for the birth.

### Host fan-out

- `terraform_data` SSH provisioners in `server.tf` pin `connection.host` to web-1. This PR adds none
  and changes none.
- The push apply's SSH stage will red until Phase 5 because `ssh.` is down. The web-1 provisioners
  re-run green at Phase 6.1.
- web-2 is the only host whose `user_data` consumes the changed input, and it is delivered by its
  replace.

### Distinctness / drift safeguards

- No "locals differ from vars" check: #12931's end state sets `var.cf_*` to the Soleur ids on
  purpose, and such a check would red that migration's own apply (plan review).
- The old addresses keep their `ignore_changes`. The new tunnel has none.
- `scheduled-terraform-drift.yml` will keep reporting #12931's old-zone drift. Its new step covers only
  the tunnel zone.

### Vendor-tier reality check

- New zone is Free. Tunnels, Access apps and service tokens are on Zero Trust Free (≤50 seats; service
  tokens use no seats).
- Notification policies exist on Free.
- No `count = var.<paid_tier>` gate needed for this slice. LB and Pro-only rulesets stay in #12931.

## Architecture Decision (ADR/C4)

### ADR

- Create **ADR-329** (provisional ordinal): "The tunnel and its Access gate live in the account that
  owns the zone".
  - Decision: tunnel + Access + tunnel CNAMEs are addressed by committed account/zone locals,
    independent of `var.cf_zone_id`, during the #12931 interim.
  - Alternatives: cross-account CNAME (refuted by docs), WARP private routing, full migration first,
    provider alias on the temp token.
  - Status `adopting` until the teardown follow-up lands.
- No ADR-304 addendum: one record (ADR-329) covers the interim; it cites ADR-304 for the re-bake path
  (plan review: two records for one interim state).
- ADR-114's I1/I2 invariants are unchanged.

### C4 views

- Read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`.
- Elements:
  - **External actor:** GitHub Actions runner — already modeled (`github`).
  - **External systems:** Cloudflare (`cloudflare` system), already modeled. Zero Trust is already
    part of its description. Edit the descriptions of `tunnel` (container, "cloudflared (ONE tunnel …")
    and `cloudflare` to name the Soleur account as the tunnel/Access owner.
  - **Container:** `tunnel`. Relationship edges `github -> tunnel`, `tunnel -> zotRegistry`,
    `tunnel -> hetzner` and `hetzner -> tunnel` are unchanged in shape.
- No new element or edge. Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`
  and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

ADR-329 is authored now as `adopting`. It flips to `accepted` when the teardown follow-up merges.

## Technical Considerations

- **Account-id literals in config:** account and zone ids are identifiers, not secrets. They already
  appear in `tests/scripts/fixtures/tfplan-web-platform-real-baseline.json` for the old ids.
- **Doppler branch inheritance:** `REGISTRY_PUSH_ACCESS_TOKEN_*` is written to `prd` root. If any
  `prd_*` branch overrides it with a stale value, the drift detector reports DEAD there. Phase 6.2
  catches this.
- **Registry Doppler key briefly absent:** the `replace_triggered_by` replace deletes then recreates
  `REGISTRY_PUSH_ACCESS_TOKEN_*` in `prd`, so the 9 inheriting configs see it missing for seconds.
  Harmless while releases are already down.
- **Deploy pair rotation breaks nothing live:** every consumer targets `deploy.soleur.ai`, which is
  NXDOMAIN today.
- **The merge-apply red is expected.** Phase 4.1 asserts its shape (creates only, plus 2 Doppler
  replaces) so an unexpected red is distinguishable.
- **NFR impact:** availability of the release/deploy pipeline (restored); observability (new causes +
  marker).

## User-Brand Impact

- **If this lands broken, the user experiences:** app.soleur.ai keeps serving the 2026-11-18 15:54Z
  build. Fixes merged since then (#12704 KB-only end-of-turn sync push, #12935, #12865, #12844) stay
  undelivered, and every later merge is also blocked. Nothing user-visible regresses, because web-1
  serves users directly.
- **If this leaks, the user's workflow is exposed via:** a leaked new `registry_push` or `ci_ssh`
  service token admits a caller through the tunnel's Access gate. It is still bounded by the zot push
  htpasswd and the CI SSH key. A leaked deploy pair is still bounded by the webhook HMAC. An attacker
  holding both could trigger a deploy of an already-signed image, so a compromise would reach every
  user at once.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** no single user's data or workspace is reached by this change
  (management-plane ingress only, no user-data surface). The failure and leak modes both act on the
  whole fleet at once, not on one user.

*Sensitive-path note:* the diff touches `apps/web-platform/infra/` and release/infra workflows. The
threshold is not `none`, so no scope-out line is needed.

## Observability

```yaml
liveness_signal:
  what: "Web Platform Release run's token preflight verdict (live/stale/unverifiable) plus, on failure, one SOLEUR_ZOT_BRIDGE line; post-apply 'Verify tunnel ingress origins' step on every infra push apply"
  cadence: "per release push run and per infra push apply"
  alert_target: "notify-ops email (Resend) and Slack #releases on release failure; workflow failure email on apply"
  configured_in: ".github/workflows/reusable-release.yml (mirror failure path), .github/actions/cf-tunnel-registry-bridge/action.yml, apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh"

error_reporting:
  destination: "GitHub Actions job log + notify-ops email body (the marker line is appended verbatim); not Better Stack — CI logs are not shipped there (CTO Item 7)"
  fail_loud: "SOLEUR_ZOT_BRIDGE stage=<listener|login|push> verdict=<v> cause=<host-nxdomain|edge-error-NNNN|tunnel-down|gate-indeterminate|...> host=registry.soleur.ai rc=<n> runbook=<path>"

failure_modes:
  - mode: "tunnel hostname record missing or wrong in the authoritative zone (this incident: Error 1000 / NXDOMAIN)"
    detection: "classifier cause edge-error-1000 / host-nxdomain in the release job; scheduled-terraform-drift.yml zone-authority step for the tunnel zone"
    alert_route: "notify-ops email; deduped ci/tunnel-zone-authority issue"
  - mode: "tunnel has no connector (web-2 down or not yet reborn)"
    detection: "classifier cause tunnel-down (530 / 1033); verify-tunnel-ingress-origin.sh prints SOLEUR_TUNNEL_VERIFY cause=no-connector tunnel=<id> connections=0 and writes the expected-red explanation to the step summary; tunnel-connector census (repointed)"
    alert_route: "notify-ops email; failed apply run"
  - mode: "stale registry-push token in Doppler after re-home"
    detection: "token preflight verdict=stale (Access stamp present with credentials) before the mirror"
    alert_route: "release job warning + notify-ops email"
  - mode: "zot down or restarting"
    detection: "SOLEUR_ZOT_DISK zot_restarts / state_status in Better Stack; scheduled-zot-restart-loop.yml"
    alert_route: "ci/zot-restart-loop issue"

logs:
  where: "GitHub Actions run logs (gh run view <id> --log-failed); Better Stack source soleur-inngest-vector-prd for SOLEUR_ZOT_DISK registry rows"
  retention: "GitHub Actions 90 days; Better Stack per plan retention (archive arm via scripts/betterstack-query.sh)"

discoverability_test:
  command: "curl -sS -m 10 -o /dev/null -w '%header{cf-access-domain}' https://registry.soleur.ai/v2/"
  expected_output: "registry.soleur.ai"
```

Baseline at planning time (measured 2026-11-19, curl 8.23): the command prints an empty line, because
Error 1000 carries no Access stamp. After Phase 6.1 it must print `registry.soleur.ai`: Access's own
denial page stamps `cf-access-domain` (`check-cloudflare-token-drift.sh` "rejected -> 403, ~39 kB,
cf-access-aud + -domain"). The command carries no `|`, `$`, `;`, `&`, `<` or `>`, so it passes preflight
Check 10's shell-active reject (`founder-check.py` `_SHELL_ACTIVE`). `%header{}` needs curl >= 7.84.

## Encryption Posture

```yaml
at_rest:
  - store: "none new — this plan re-homes existing Cloudflare configuration; secrets land in Terraform state (R2 backend, existing) and Doppler (existing)"
    mechanism: "provider-managed:Doppler encryption at rest (existing ledger posture, unchanged)"
    evidence: "scripts/encryption-posture-ledger.json existing Doppler/state rows (unchanged by this plan)"
    defends_against: "a stolen storage snapshot of the vendor's backing store"
    does_not_defend: "a leaked Doppler service token or a reader of Terraform state who holds the R2 state credential"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable:vendor-internal"
in_transit:
  - connection: "GitHub Actions runner -> zot registry over the CF Tunnel (registry.<base> -> tcp://10.0.1.30:5000), now via the Soleur-account tunnel"
    enforced_at: ".github/actions/cf-tunnel-registry-bridge/action.yml (cloudflared access tcp); apps/web-platform/infra/tunnel.tf registry ingress rule of _config.web_soleur"
    tls: "runner<->CF edge and edge<->connector TLS 1.2+; connector<->10.0.1.30:5000 plain HTTP on the private network (unchanged)"
    cert_verification: "off"
    does_not_defend: "a passive on-net attacker on 10.0.1.0/24 reading image bytes on the final leg; a leaked CF Access service token or zot push credential"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "Unchanged existing accepted risk for the final private-network leg, ledger row 'GitHub Actions runner -> zot registry over the CF Tunnel' (CTO ruling 2026-11-05, owner record on #10136); this plan changes only which Cloudflare account terminates the first two TLS legs"
  tracking_issue: "#10136"
  reevaluate_when: "a server beyond the five attached to 10.0.1.0/24 joins the network, the registry is exposed publicly, or the link gains TLS"
  expires_on: "2027-01-31"
```

The deploy (`http://10.0.1.10:9000`) and ssh (`ssh://10.0.1.10:22`) legs keep their existing ledger
rows unchanged.

## Guard Contract

### Guard 1 — edge-cause classifier

**Property.** An uncredentialed control probe whose answer is not an Access stamp, an IdP redirect,
`cf-mitigated` or a 2xx is reported with the Cloudflare cause it measured: `host-nxdomain` for curl
exit 6, `tunnel-down` for 530 or error code 1033, and `edge-error-<NNNN>` for any other Cloudflare
error-page code. It is reported `gate-indeterminate` only when no code is readable.

**Assembly.** The single chokepoint is `verify_access_pair()`'s control ladder in
`scripts/check-cloudflare-token-drift.sh`. It is fed by `access_probe()`, the only place the body is
captured. Consumers: the detector row switch and grep summary in the same file, and
`zot_mirror_unverifiable_cause()`/`zot_mirror_cause_help()` in `scripts/zot-mirror-diagnosis.sh`.
Those are reached by `reusable-release.yml` (two call sites), `registry-zot-inventory.yml` and the
bridge action. The cause vocabulary is one closed set, and remedies are pinned by set equality.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `access_probe` to `-o /dev/null` (body discarded) — stub body `errorCode: 1000`, 403 unstamped | RED (cause stays `gate-indeterminate`) |
| 2 | Map curl exit 6 back to `host-unreachable` | RED |
| 3 | Stamped 403 (`cf-access-aud`) whose body also contains `errorCode: 1000` | must stay `gated` (stamp wins) — RED if classified edge-error |
| 4 | Add a cause to the ladder without a remedy in `zot_mirror_cause_help` | RED (set-equality test) |
| 5 | Guard's own dispatch: run the suite with the body-capture rows skipped (0 rows executed) | RED (row-count floor on the new rows) |

**Harness rows.** A suite edit making the `MOCK_HTTP_BODY` stub write nothing must red rows 1 and 3.
Must-PASS: a stamped 403 with a ~39 kB Access page body is `gated`, and an unstamped 200 with 0 bytes is
`ungated`. These are the two measured shapes in the file's 2026-08-01 note.

### Guard 2 — deploy-policy gate covers the new policy address

**Property.** No plan may create, delete or re-include the deploy Access policy at either address
unless it is the single acknowledged create of `…deploy_service_token_soleur` with exactly one include
block equal to the committed id list.

**Assembly.** The `deploy_policy` selectors in `tests/scripts/lib/destroy-guard-filter-web-platform.jq`
plus `tests/scripts/lib/deploy-policy-gate.sh`. Both addresses must flow through the same selector.
An address-equality `select` on only the old address is the defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plan creates `…_soleur` with no own-line `[ack-deploy-policy]` | RED |
| 2 | Plan creates `…_soleur` with two include blocks | RED |
| 3 | Plan creates `…_soleur` correctly AND deletes the old address | RED |
| 4 | Plan with zero deploy-policy changes but the selector list emptied (gate dispatch) | RED via the existing no-op fixture row asserting the selector matched both addresses in a synthetic plan |
| 5 | Plan updates `…_soleur` include to a different id | RED (needs `[ack-deploy-policy]` and id equality) |

**Harness rows.** Must-PASS: a single acknowledged create with the committed id. Must-PASS: a plan
touching neither address. A suite edit that feeds the canonical baseline fixture to every row must red
rows 1–3.

### Guard 3 — post-apply tunnel ingress verification

**Property.** After an infra apply, the tunnel the CNAMEs point at has `deploy.`, `ssh.` and `registry.`
rules equal to their origin-relative targets, and `deploy.` serves `/hooks/deploy-status` 200 through
Access.

**Assembly.** `apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh`. Its tunnel id and
account come from the TF outputs `cf_tunnel_id`/`cf_tunnel_account_id`, the same resources `dns.tf`'s
`_soleur` CNAMEs reference. The only caller is the apply job step "Verify tunnel ingress origins are
live and origin-relative".

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Script reads the old state address `…tunnel_cloudflared.web` | RED (infradir test asserts the output names) |
| 2 | `registry.` rule rewritten to `http://10.0.1.30:5000` | RED |
| 3 | A second `registry.` rule added after a compliant first (e.g. `localhost:5000`) | RED (every matching rule checked, not the first) |
| 4 | Account read from Doppler `CF_ACCOUNT_ID` again | RED |

**Harness rows.** Must-PASS: a fixture config with all three correct rules plus the catch-all. A suite
edit stubbing `terraform output` to an empty string must red, not skip.

### Guard 4 — tunnel-zone authority drift step

**Property.** When the zone that carries the tunnel CNAMEs is not `active`, or the public NS for its
name differ from its `name_servers`, one deduped `ci/tunnel-zone-authority` issue exists.

**Assembly.** One step in `.github/workflows/scheduled-terraform-drift.yml`. It reads the zone id from
the committed local through `terraform output` and the NS through DoH. It has a single filing site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture zone `status: moved` | RED (issue filed) |
| 2 | Fixture public NS `laila/lennon` vs zone NS `bradley/nora` | RED |
| 3 | DoH query fails (curl rc≠0) | RED as `unavailable`, never clean |
| 4 | Step dispatch: zone id resolves empty | RED (refuse, never compare empty sets) |

**Harness rows.** Must-PASS: active zone, NS sets equal in a different order.

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings 1–7 (2026-11-19) adopted in full. Option A tunnel slice; new addresses
via committed locals; widen `CF_API_TOKEN`; extend the single classifier; `SOLEUR_ZOT_BRIDGE` as a
render-only marker; `Ref #12937` (closed post-merge after the re-runs; sharp-edge amendment of Item 5) / `Ref #12931`. The decision log is in
`knowledge-base/project/specs/feat-one-shot-12937-zot-bridge-handshake/decision-challenges.md`.

### Operations

**Status:** reviewed
**Assessment:** COO:

- No new recurring cost. Zero Trust Free covers tunnels, Access apps and service tokens.
- The web-2 replace double-bills cpx22 for minutes (cents).
- Zero Trust enablement becomes an operator step only if the API refuses.
- `CF_API_TOKEN_SOLEUR_ACCT` expires 2026-12-18; track its revocation in #12931.
- Update the `expenses.md` soleur.ai row (Free zone, Soleur account) and the `domains.md` DNS table.
- Re-check the stale web-2 expense row against the Hetzner API.

### Product/UX Gate

Not relevant. There is no UI surface: the Files lists hold no `components/`, `app/**/page.tsx` or UI
path.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Diagnose first by self-pulling telemetry: registry host Better Stack rows for zot and cloudflared (scripts/betterstack-query.sh, creds in Doppler prd_terraform) around 18:15Z 2026-11-18 onward" | Root Cause, Hypotheses | mapped |
| 2 | "determine whether the 16:33Z 2026-11-18 supabase-ref-resolver failure is a separate issue (file it separately if so)" | Research Reconciliation row 8 (same incident, not filed) | mapped |
| 3 | "Fix the root cause" | Phases 0–5 | mapped |
| 4 | "add a SOLEUR_* marker if the bridge failure cause is not visible in telemetry" | Phase 2.2–2.4 (`SOLEUR_ZOT_BRIDGE`) | mapped |
| 5 | "re-run the failed push runs for the 2026-11-18 learnings PR (5d4851f7af) and the 2026-11-19 KB-only sync push PR (52bf12cc5b, push run 44427650817)" | Phase 6.3 | mapped |
| 6 | "then run soleur:postmerge for the 5d4851f7af merge" | Phase 6.5 | mapped |
| 7 | "Follow-ons for later sessions in the same epic (not in this PR): #12863 and #12920" | — | descoped — justification: the brief excludes them from this PR |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `tunnel.tf`, `dns.tf`, `server.tf`, `apply-web-platform-infra.yml`, `terraform-target-parity.test.ts`, deploy-policy gate + jq + test | "Fix the root cause" | asked |
| `verify-tunnel-ingress-origin.sh` + test | "Fix the root cause" | inferred — justification: without the repoint the post-apply gate verifies the old tunnel and can never prove the fix (CTO Item 2 amendment) |
| `check-cloudflare-token-drift.sh` + test, `zot-mirror-diagnosis.sh` + test, bridge action, `reusable-release.yml` | "add a SOLEUR_* marker if the bridge failure cause is not visible in telemetry" | asked |
| `scheduled-terraform-drift.yml` zone-authority step | — | inferred — justification: the root cause was a zone-authority change nothing detected; without it the next move fails releases silently again (CTO Item 4) |
| ADR-329, ADR-304 addendum, `model.c4` | — | inferred — justification: plan Phase 2.10 makes the ADR/C4 update a deliverable of an architecture change (tunnel moves trust boundary to another account) |
| Runbook edits, `expenses.md`, `domains.md` | — | inferred — justification: the runbooks name the copy list and causes operators follow; the ledgers would state a false zone/account (COO) |
| `SOLEUR_TUNNEL_VERIFY` + step summary, CI-SSH sync move + fail-on-empty (Phases 1.8-1.9) | "Fix the root cause" | inferred — justification: CTO ruling on advisor fork 1; without the move the merge run leaves the old-account CI-SSH pair in Doppler with nothing red, and the named cause separates the expected red from a real one |
| Tunnel-connector census repoint, `ci_ssh_token_replace` repoint | "Fix the root cause" | inferred — justification: plan review found both still bound to the old tunnel/token; left alone, the census pages `zero_connectors` every run after Phase 5 |
| Phase 7 follow-up issue + #12931 comment | — | inferred — justification: `wg-when-deferring-a-capability-create-a` (the old-account teardown is deferred) |

### Split Assessment

- Subsystems touched: 6. They are `apps/web-platform`, `.github`, `scripts`, `tests`,
  `plugins/soleur` and `knowledge-base`.
- Planned files: 24. Estimated changed lines: ~750.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines.
- Recommendation: single PR. Justification: the subsystem count is tripped by the parity, gate and
  doc files any infra change must carry. A natural seam exists (Phase 2 observability alone), but it
  is not taken. The marker must ship with the fix, so the Phase 6 re-runs exercise and prove it, and the
  brief scopes one PR. Phase 2 commits are ordered first so they can be split out if review asks.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] The PR's validation plan (`infra-validation.yml`, full-root `-refresh=false`) differs from its
      recorded baseline ("14 to add / 3 to change / 6 to destroy") by exactly the `_soleur` creates
      plus the two `doppler_secret.registry_push_access_token_*` replaces: deltas only, no new destroy
      outside those two. The authoritative check is the merge push apply's targeted plan JSON (post-merge
      AC). The old tunnel, Access, record and token addresses show no new change.
- [ ] `local.deploy_service_token_ids_soleur` holds the id minted in Phase 3.1. The UUID precondition
      passes.
- [ ] `bash scripts/check-cloudflare-token-drift.test.sh` and `bash scripts/zot-mirror-diagnosis.test.sh`
      are green, including every Guard 1 row. A `MOCK_HTTP_BODY` row with `errorCode: 1000` yields
      cause `edge-error-1000`, and `MOCK_CURL_EXIT=6` yields `host-nxdomain`.
- [ ] Guard 2 rows green in `tests/scripts/test-deploy-access-token-forget.sh` (or its sibling).
      `bun test plugins/soleur/test/terraform-target-parity.test.ts` is green.
- [ ] `bash apps/web-platform/infra/verify-tunnel-ingress-origin-infradir.test.sh` is green with Guard 3
      rows.
- [ ] `zot_bridge_marker push live edge-error-1000 registry.soleur.ai 1` prints exactly
      `SOLEUR_ZOT_BRIDGE stage=push verdict=live cause=edge-error-1000 host=registry.soleur.ai rc=1 runbook=knowledge-base/engineering/operations/runbooks/zot-registry-revert.md`.
- [ ] C4 tests green: `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`,
      `plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] Deploy pair Doppler copies (`soleur-infra-privileged/prd`, `soleur/prd_terraform`) match the
      minted value's sha256; the GitHub repo secret copy is proven by the Phase 6.3 deploy arm.
- [ ] The 6 scanner A records are absent in zone `951ce525…` at merge time. The CF API returns 0 A
      records for `registry`/`ssh`.
- [ ] PR body first line answers "does merging this alone mutate production?": yes, the merge-triggered
      targeted apply creates the `_soleur` slice and replaces two Doppler secrets.
- [ ] PR body: `Ref #12937` (not `Closes`; the bridge is restored only post-merge by Phases 5-6) and
      `Ref #12931`, the Phase 0.3 verification output, and the expected red shape of the merge apply
      (`SOLEUR_TUNNEL_VERIFY cause=no-connector`).

### Post-merge (operator-approved stages)

- [ ] The merge push apply created all `_soleur` resources and destroyed nothing but the two Doppler
      secrets. Asserted from the run's plan JSON.
- [ ] `apply-deploy-pipeline-fix.yml` post-Phase-6.1 re-dispatch is green (its merge run is expected
      red at the bridge step).
- [ ] `web-host-replace web-2` run green. The new tunnel shows ≥1 connection from web-2.
- [ ] `manual-rerun` apply green, including "Verify tunnel ingress origins" for `deploy.`, `ssh.` and
      `registry.`.
- [ ] The `discoverability_test` command prints `registry.soleur.ai`, and `deploy.soleur.ai` resolves.
- [ ] `check-cloudflare-token-drift.sh` grades `REGISTRY_PUSH_ACCESS_TOKEN` and `CI_SSH_ACCESS_TOKEN`
      LIVE in every config.
- [ ] Push run 44375972612 re-run green with deploy arm 44376350232 re-run (deployed or `superseded`).
      Push run 44427650817 re-run green with deploy arm 44427961170 deployed.
- [ ] `deploy-arm.sh served <newest released sha>` prints `CONTAINED`, and `/health` reports it.
- [ ] `soleur:postmerge` completed for the `5d4851f7af` merge.
- [ ] Follow-up teardown issue filed (Phase 7.1). #12931 commented (7.2).
- [ ] `gh issue close 12937` run only after Phase 6.3's release re-runs are green, with a comment
      linking the green runs.

## Test Scenarios

- Given an unstamped 403 whose body carries `errorCode: 1000`, when the control probe runs, then the
  cause is `edge-error-1000` (unit, `check-cloudflare-token-drift.test.sh`).
- Given curl exit 6, then the cause is `host-nxdomain` (unit).
- Given an unstamped 530, then `tunnel-down` (unit).
- Given a stamped Access 403, then `gated` regardless of body (unit, regression for #7242 class).
- Given cause `edge-error-1000`, when the mirror fails, then the job log and email carry
  `SOLEUR_ZOT_BRIDGE stage=login … cause=edge-error-1000 …` once (unit for the helper; integration via
  `zot-mirror-diagnosis.test.sh`).
- Given a plan creating `…deploy_service_token_soleur` without `[ack-deploy-policy]`, then
  `deploy_policy_unsafe` (unit, gate suite).
- Given a tunnel config fixture with `registry.` → `http://…`, then verify reds (unit, infradir test).
- Given a zone fixture with `status: moved`, then the drift step files one issue, and a second run
  updates it (unit for the step's script).
- **API verify (post-merge):** `curl -sS -m 10 -o /dev/null -w '%header{cf-access-domain}'
  https://registry.soleur.ai/v2/` expects `registry.soleur.ai`.
- **Regression:** a release push run after Phase 6.1 passes the mirror step with verdict `live`.

## Dependencies & Risks

- **Operator gates:** Phase 0.1 (token widening), 0.2 (Zero Trust, possibly payment), the
  `web-platform-infra-apply` environment approval, and an explicit go per production-mutating agent act
  (Phase 3, merge, dispatch). `hr-menu-option-ack-not-prod-write-auth` applies.
- **Collision:** PR #12873 edits `apply-web-platform-infra.yml`. Rebase before merge and re-run parity.
- **Moved-zone deletion clock:** Cloudflare will delete the old zone after a grace period that is not
  verified. The old tunnel's Access apps go with it, which is harmless after Phase 5. The teardown
  follow-up must land before then for clean state.
- **New zone is Free:** Bot Fight Mode or other defaults may challenge `deploy.` before Access. Check in
  Phase 6.1, and fix through #12931 if so.
- **Stock:** cpx22 in hel1 may be unorderable. The runbook's stock preflight handles a repin.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- `doppler_secret` with `ignore_changes = [value]` never follows its source. Re-homing the token
  without `replace_triggered_by` leaves the old-account secret in Doppler `prd`. The release would then
  fail with an Access refusal, and `verdict=stale` would be the only clue.
- The `web-host-replace` gate aborts on any tunnel diff, so Phase 4 must be applied before Phase 5.
- Both web-host boot paths (`apply_target=web-host-create` and `web-host-replace`) render the same
  `server.tf` cloud-init, so the `tunnel_token` input change reaches every route that can birth a web
  host. Only web-2 renders the connector (`web_tunnel_connector`, validation "exactly one").
- Do not edit `apps/web-platform/infra/variables.tf` or `zot-registry.tf` in this PR. Either wakes
  `registry-host-replace-dispatch.yml`, and although its render gate makes an unrelated wake a no-op,
  keep the wake set minimal.
- Re-run order matters only for clarity. `deploy-arm.sh`'s ancestry rule prevents a rollback.
- Before any dispatch, confirm via `gh run view --json jobs` that no earlier queued run applied
  (learning 2026-11-16).

## References

- Issues: #12937, #12931, #9601, #12873 (bastion, collision), #10136 (zot private-leg acceptance), #2197.
- Runs:
  - release: 44341012353 (last green), 44348563238, 44367779280, 44375972612, 44427650817;
  - apply: 44348560918;
  - deploy arms: 44376350232, 44427961170.
- ADRs: ADR-096, ADR-114, ADR-154, ADR-166, ADR-241, ADR-304, ADR-327.
- Docs: Cloudflare tunnel DNS records (same-account routing); Cloudflare 1xxx errors (1000, 1033).
