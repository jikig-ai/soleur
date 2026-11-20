---
title: The tunnel and its Access gate live in the account that owns the zone
status: adopting
date: 2026-11-19
issue: 12937
related: [12931, 9601]
supersedes: none
related_adrs: [ADR-096, ADR-114, ADR-154, ADR-166, ADR-241, ADR-304]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/cloudflare-service-token-rotation.md
  - knowledge-base/engineering/operations/runbooks/zot-registry-revert.md
---

# ADR-330: The tunnel and its Access gate live in the account that owns the zone

Plan: `knowledge-base/project/plans/2026-11-19-fix-zot-bridge-tunnel-hosts-after-zone-move-plan.md`.
Rulings: `knowledge-base/project/specs/feat-one-shot-12937-zot-bridge-handshake/decision-challenges.md`.
Ref #12937, Ref #12931.

## Context

At about 16:24Z on 2026-11-18 the `soleur.ai` registration moved from the legacy Cloudflare account
(old zone `5af02a2f…`, Pro, now `status: moved`) to the Soleur account (`66d4f93f…`, zone `951ce525…`, Free).
The public nameservers changed with it. From 18:15Z every Web Platform Release push run failed at the zot
mirror's CF-tunnel bridge (`websocket: bad handshake`), and production stayed on the last green build.

zot and the tunnel connector were both healthy. The fault was one layer down:

- The new zone had no working records for the three tunnel hostnames. An import scan had written
  `registry.` and `ssh.` as proxied A records to Cloudflare anycast addresses, which the edge answers with a
  403 and Error 1000. `deploy.` was absent, so it returned NXDOMAIN.
- The tunnel (`soleur-web-platform`), its three Access apps, their policies and the service tokens all
  lived in the legacy account.
- Cloudflare docs (DNS records intro): "The `cfargotunnel.com` subdomain only proxies traffic for DNS
  records in the same Cloudflare account." The old tunnel cannot serve the new zone, whatever its CNAMEs say.

The full account move is #12931. Changing `var.cf_zone_id` and `var.cf_account_id` would move every
zone-scoped and account-scoped resource at once. Some of those moves wait on money decisions (Pro vs
Free, Load Balancing), so the release pipeline cannot wait for them.

The release job could not name the cause. The token preflight's uncredentialed control probe threw away the
response body, so the Error 1000 page was graded `gate-indeterminate` and NXDOMAIN was graded
`host-unreachable`. No telemetry layer showed an edge-side DNS fault.

## Considered Options

- **Option A: re-home only the tunnel slice now, at new `_soleur` addresses that read committed locals
  (chosen).** Pros: restores `registry.`, `ssh.` and `deploy.` without waiting on #12931's money decisions.
  The merge apply stays behind the destroy guard and the target-parity tests, and nothing is destroyed.
  Cons: two tunnels and two Access slices exist until the teardown follow-up, and the `_soleur` suffix is
  either kept on purpose or removed later with `moved {}`.
- **Option B: keep the legacy-account tunnel and point the new zone's CNAMEs at it.** Rejected, because
  Cloudflare docs refute it: tunnel CNAME routing is same-account only.
- **Option C: WARP private routing for CI.** Rejected. It adds a new ingress mode and runner enrolment, and
  it does not fix `deploy.`, which the deploy arm calls over plain HTTPS through Access.
- **Option D: finish the full #12931 migration first.** Rejected as the fix for this outage. It is blocked on
  operator money decisions and holds every release until they are made.
- **Option E: a second provider alias on the temporary Soleur-account token (`CF_API_TOKEN_SOLEUR_ACCT`).**
  Rejected. That token expires 2026-12-18, has no service-token scope, and would add a second credential
  path to the apply.
- **Option F: flip `var.cf_zone_id` / `var.cf_account_id` for the whole root.** Rejected for this slice.
  It is #12931's scope, and the ids are ForceNew on every zone resource.

## Decision

Option A. During the #12931 interim, the tunnel, its Access gate and the tunnel CNAMEs live in the account
that owns the `soleur.ai` zone. They do not follow `var.cf_zone_id` / `var.cf_account_id`.

1. **Addressing.** `apps/web-platform/infra/tunnel.tf` holds committed locals `cf_soleur_account_id` and
   `cf_soleur_zone_id`. New addresses with a `_soleur` suffix sit beside the untouched legacy ones:
   - the tunnel (`…tunnel_cloudflared.web_soleur`, same name `soleur-web-platform`) and its config;
   - three `self_hosted` Access apps and their policies, both scoped by `account_id`;
   - the `ci_ssh` and `registry_push` service tokens;
   - the service-token expiry notification policy;
   - the three proxied CNAMEs in `apps/web-platform/infra/dns.tf`.

   No provider alias, new variable, `state mv`, `import {}`, forget or destroy is part of this change.
2. **Same ingress.** The `_soleur` config carries the same three origin-relative rules as the legacy one,
   taken from the same expressions. ADR-114's I1 and I2 are unchanged.
3. **Credentials.** The existing `CF_API_TOKEN` is widened in place to the Soleur account and zone. The
   deploy token stays outside Terraform (ADR-241 D10). It is minted through the API, its id is committed in
   `local.deploy_service_token_ids_soleur`, and its pair is written to every reader: the GitHub repo
   secrets, Doppler `soleur-infra-privileged/prd` and Doppler `soleur/prd_terraform`.
4. **The registry Doppler secrets follow the token.** `doppler_secret.registry_push_access_token_{id,secret}`
   point at `…registry_push_soleur` and no longer carry `ignore_changes = [value]`, so the merge apply
   updates them in place. `replace_triggered_by` fires only when the referenced resource is updated or
   replaced, never on its create. With `ignore_changes` kept, the old-account secret would have stayed in
   Doppler `prd`. The provider's read never clears `client_secret` for a Terraform-created token, so state
   keeps the secret across refreshes. Two rules follow: a `_soleur` token is never adopted with `import {}`
   (an imported token reads its secret empty), and rotation is a `client_secret_version` bump (ADR-154:
   repair the credential channel, do not hand-copy around it).
5. **Gates.** The new addresses, including the registry ones, ride the merge apply's `-target` list rather
   than `OPERATOR_APPLIED_EXCLUSIONS`. The deploy-policy gate covers the three `_soleur` Access policies,
   each checked against its own committed token reference. A single create is allowed only with an own-line
   `[ack-deploy-policy]`.
6. **Connector re-bake.** A tunnel token reaches a host only through create-time user_data, so the
   connector moves when web-2 is reborn through `web-host-replace` (ADR-304). web-1 is not touched, and
   `app.soleur.ai` never crosses the tunnel.
7. **Detection (ADR-166, measured causes only).** The token classifier keeps the control probe's body and
   adds three causes: `host-nxdomain`, `edge-error-<NNNN>` and `tunnel-down`. One render-only marker,
   `SOLEUR_ZOT_BRIDGE`, prints the measured cause on a bridge failure. The post-apply verify step prints
   `SOLEUR_TUNNEL_VERIFY cause=…` and still exits non-zero. A scheduled zone-authority step files a deduped
   `ci/tunnel-zone-authority` issue when the tunnel zone is not `active`, or when its public nameservers
   differ from its `name_servers`.

## Consequences

- Releases, deploys and CI SSH depend only on the account that answers for the zone. The next move of the
  zone pages through the zone-authority issue, and a failed bridge names its cause in the job log and the
  ops email.
- Two tunnels and two Access slices coexist until the teardown follow-up. The legacy tunnel keeps its
  connector until web-2 is reborn, but nothing routes to it.
- The merge apply is expected red at "Verify tunnel ingress" (`SOLEUR_TUNNEL_VERIFY cause=no-connector`)
  until the re-bake. The connector census reports `zero_connectors` in that window too.
- A revert PR cannot roll back a target-scoped apply. Before the re-bake, rollback is a targeted destroy of
  the `_soleur` addresses behind `[ack-destroy]`. After it, the change is forward-only.
- Once Cloudflare purges the moved zone, the legacy addresses still on the push `-target` list make every
  push apply try to re-create them. That bounds how long the teardown can wait.
- #12931 collides with this slice when it flips `var.cf_account_id` / `var.cf_zone_id`, not only through
  its own tunnel phase (PR #12932). A changed `account_id` or `zone_id` forces replacement, so after the
  flip the legacy addresses would plan to re-create the tunnel name, the three CNAMEs, the Access app
  domains and the registry Doppler secrets where the `_soleur` copies already hold them. The teardown
  follow-up therefore lands before that flip (`removed { destroy = false }` on the legacy slice, its
  `-target` lines dropped), and #12931's tunnel phase adopts the `_soleur` addresses with `moved {}`
  rather than creating a third tunnel.
- This ADR moves to `accepted` when the teardown follow-up lands. That follow-up removes the legacy slice,
  `local.deploy_service_token_ids` and the legacy registry exclusions, and settles the `_soleur` suffix.

## Cost Impacts

None. Tunnels, Access apps and service tokens are included in Zero Trust Free, and service tokens use no
seats. The web-2 replace double-bills one cpx22 for minutes. The Pro-vs-Free and Load Balancing decisions
stay in #12931.

## NFR Impacts

No NFR changes tier.

- **NFR-016 Continuous Automated Delivery:** the release and deploy pipeline is restored, and a future zone
  move now pages instead of silently failing releases.
- **NFR-001 Logging:** `SOLEUR_ZOT_BRIDGE` and `SOLEUR_TUNNEL_VERIFY` carry fixed, validated fields with no
  secrets or bodies.
- **NFR-026 Encryption In-Transit:** unchanged. Only the account that terminates the first two TLS legs
  changes. The private-network leg keeps its accepted exception (#10136).

## Principle Alignment

- AP-001 (Terraform-only): Aligned. Every re-homed resource is Terraform-managed. The deploy token is
  outside state by ADR-241 D10.
- AP-002 (No SSH state mutation): Aligned. The connector moves through a host replace.
- AP-008 (Doppler for secrets): Aligned. Every copy of each pair is written from one value and checked by
  hash.
- AP-021 (Diagnostic honesty): Aligned. Each new cause is derived from a measured curl exit code or
  Cloudflare error-page code.
