---
title: The tunnel and its Access gate live in the account that owns the zone
status: adopting
date: 2026-11-19
issue: 12937
related: [12931, 9601]
supersedes: none
related_adrs: [ADR-096, ADR-114, ADR-154, ADR-166, ADR-241, ADR-304, ADR-329]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/cloudflare-service-token-rotation.md
  - knowledge-base/engineering/operations/runbooks/zot-registry-revert.md
  - knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md
---

# ADR-331: The tunnel and its Access gate live in the account that owns the zone

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

- **Option A: re-home only the tunnel slice now, at new parallel addresses that read committed locals
  (chosen 2026-11-19, superseded 2026-11-23 by Option G).** Pros: restores `registry.`, `ssh.` and `deploy.` without waiting on #12931's money decisions.
  The merge apply stays behind the destroy guard and the target-parity tests, and nothing is destroyed.
  Cons: two tunnels and two Access slices exist until a teardown follow-up, and the address suffix is
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

- **Option G: build this slice as ADR-329's `tunnel` phase on the existing addresses (chosen 2026-11-23,
  Ruled by CTO agent).** ADR-329 merged in #12932 while Option A was in review. Its `cf_account_id` validation
  rejects the legacy id, Option A's precondition rejected the Soleur id, and the migration's completion
  predicate keys on the existing `.web` tunnel address, so Option A would have been refused before and after
  the flip. Cons: the bridge returns only after the migration's earlier phases have run.

## Decision

Option G. **ADR-329 owns the addressing and the sequence.** The tunnel, its Access gate, its service tokens
and the three CNAMEs stay at their existing Terraform addresses, read `var.cf_account_id` and `var.cf_zone_id`,
and are recreated on the Soleur account by the `tunnel` phase of
[the migration runbook](../../operations/runbooks/cloudflare-account-migration.md). This ADR owns three things
that phase relies on:

1. **Detection (ADR-166, measured causes only).** The token classifier keeps the control probe's body and
   adds three causes: `host-nxdomain`, `edge-error-<NNNN>` and `tunnel-down`. One render-only marker,
   `SOLEUR_ZOT_BRIDGE`, prints the measured cause on a bridge failure. The post-apply verify step prints
   `SOLEUR_TUNNEL_VERIFY cause=…` and still exits non-zero. A scheduled zone-authority step files a deduped
   `ci/tunnel-zone-authority` issue when the tunnel zone is not `active`, or when its public nameservers
   differ from its `name_servers`.
2. **Access policy gates.** The deploy-policy gate is an address allowlist over the whole Access app and
   policy family. On a routine apply each gated policy may only stay unchanged or update in place in its
   committed shape: one include holding only its own committed token reference. A planned create, delete or
   replace halts, and no ack passes it. The first create happens only in the `tunnel` phase, whose own gate
   applies the same content checks.
3. **The registry Doppler secrets follow the token.** `doppler_secret.registry_push_access_token_{id,secret}`
   no longer carry `ignore_changes = [value]`, so the `tunnel` apply updates them in place. With
   `ignore_changes` kept, the old-account secret would have stayed in Doppler `prd`. The provider's read never
   clears `client_secret` for a Terraform-created token, so state keeps the secret across refreshes. Two rules
   follow: this token is never adopted with `import {}` (an imported token reads its secret empty), and
   rotation is a `client_secret_version` bump (ADR-154: repair the credential channel, do not hand-copy
   around it).

## Consequences

- Releases, deploys and CI SSH depend only on the account that answers for the zone. The next move of the
  zone pages through the zone-authority issue, and a failed bridge names its cause in the job log and the
  ops email.
- Releases stay blocked until the `tunnel` phase has applied and web-2 has been replaced, because a tunnel
  token reaches a host only through create-time user_data (ADR-304).
- Every routine apply refuses while the nil deploy-token placeholder is committed. The minted id replaces it
  before merge.
- The verify step is expected red (`SOLEUR_TUNNEL_VERIFY cause=no-connector`) between the `tunnel` apply and
  the web-2 replace. The connector census reports `zero_connectors` in that window too.
- Until the `tunnel` phase runs, the census finds no tunnel in the Soleur account and reports
  `census_unavailable`, which does not page.
- This ADR moves to `accepted` when the `tunnel` phase has applied and the bridge is proven.

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

- AP-001 (Terraform-only): Aligned. Every recreated resource is Terraform-managed. The deploy token is
  outside state by ADR-241 D10.
- AP-002 (No SSH state mutation): Aligned. The connector moves through a host replace.
- AP-008 (Doppler for secrets): Aligned. Every copy of each pair is written from one value and checked by
  hash.
- AP-021 (Diagnostic honesty): Aligned. Each new cause is derived from a measured curl exit code or
  Cloudflare error-page code.
