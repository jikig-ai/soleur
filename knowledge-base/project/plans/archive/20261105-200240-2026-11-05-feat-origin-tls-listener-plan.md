---
title: "feat: origin TLS listener for the web hosts (Origin CA + strict), staged behind a canary"
type: feat
date: 2026-11-05
branch: feat-origin-tls-listener-10479
issue: 10479
epic: 10205
pr: 12181
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# feat: origin TLS listener for the web hosts

Ref #10479. Ref #10205. This plan and its draft PR (#12181) never close either issue.

## Summary

Browsers reach Cloudflare over TLS, but Cloudflare reaches our web hosts over plain HTTP, because an enabled
`flexible` configuration rule applies to `app.soleur.ai`. Session cookies, chat content, BYOK keys at submission and
the Inngest step-calls cross that public hop in the clear. The CLO ruled it must be fixed (target 2026-11-12, hard
stop 2026-11-19, early checkpoint 2026-11-09).

Done-condition from #10479: the origin serves TLS with a certificate Cloudflare verifies (Origin CA), the zone rule is
`strict` for `app.soleur.ai`, a handshake probe shows it, and published wording is re-checked against the measured mode.

This PR (#12181) is the first of five slices. It is code-only and inert: it adds the listener, publishes container
port 3443 as host 443, and adds a read-only handshake probe. It mints no certificate, changes no Cloudflare rule and
touches no host definition. The strict flip is a later, separately gated PR.

## Verified findings (read of `origin/main` at 3b95267fac, plus public GETs, 2026-11-05)

| # | Finding | Evidence |
|---|---|---|
| F1 | No origin TLS listener existed. The app container published `-p 0.0.0.0:80:3000` and `-p 0.0.0.0:3000:3000` only. | `ci-deploy.sh` (prod `docker run`), `cloud-init.yml` (first-boot `docker run`), `lib/docker-run-tuple.py` (`TUPLES`) |
| F2 | The only in-app TLS server is the private-net session proxy on 8443 (`SOLEUR_PROXY_BIND`, peer allowlist), count-gated off. It is not an origin listener. | `server/session-proxy.ts` (`createProxyServer`), `infra/proxy-tls.tf` (`host_proxy_tls_enabled`) |
| F3 | No Origin CA certificate, no `cloudflare_origin_ca_certificate`, no Authenticated Origin Pulls anywhere in the repo. The many `443` / `origin` grep hits in `infra/` are the firewall rule, egress allowlists, Cloudflare cache/redirect rules and unrelated host scripts. | `git grep -i -E 'origin_ca\|api_user_service_key\|authenticated_origin\|tls_client_auth'` over the repo returned only documentation and the NFR register row |
| F4 | The firewall already admits Cloudflare ranges on tcp/443. Permit existed, listener did not. | `firewall.tf` (the `port = "443"` rule) |
| F5 | The Cloudflare Load Balancer monitor is `type = "http"`, `port = 80`, `/health`, deliberately, because there was no 443 listener. It therefore cannot see a broken 443 path. | `cloudflare-lb.tf` (`cloudflare_load_balancer_monitor.web`) |
| F6 | `lb-staging.soleur.ai` is in the flexible rule's expression but no longer resolves (`getent hosts` returns nothing; `curl` exit 000). A throwaway staging host for the flip does not exist and recreating it is a production DNS write. | `seo-config-rules.tf` expression; `infra/lb-staging/lb-staging.tf` (separate root, applied by `cf-lb-overlay.yml`); live DNS check |
| F7 | Live today (public probe): `https://app.soleur.ai/health` is 200 with no transport header, matching Flexible. | `bash apps/web-platform/infra/origin-tls-probe.sh` printed `transport=none result=OK`; with `--canary --expect tls` it exited 3 |
| F8 | Zone SSL mode is `strict`; one enabled `flexible` rule (ref `dcb85b75...`) applies to the app host; Terraform owns the entrypoint. The flip therefore edits that rule, not the zone setting. | #10479 comments of 2026-11-05 (Class R reads A, B and the drift-run read) |
| F9 | Web hosts: `hcloud_server.web` has `ignore_changes = [user_data, ...]`, so editing `cloud-init.yml` replaces no host. `ci-deploy.sh` reaches running hosts through `terraform_data.deploy_pipeline_fix` and `deploy_pipeline_fix_web2` (triggers hash the file). | `server.tf` (`lifecycle` of `hcloud_server.web`; the two `terraform_data` resources) |
| F10 | Under a weight-0 pool member, the edge only ever exercises web-1. web-2's listener cannot be proven from the edge. | `cloudflare-lb.tf` (`cloudflare_load_balancer_pool.web_1`, web-2 `weight = 0`) |
| F11 | Cloudflare documents: Origin CA certificates are compatible with Strict; creation uses an API token with Zone SSL and Certificates Edit; no renewal and no expiry notification exists; Full (strict) needs unexpired, trusted-issuer, hostname-matching certificate and a 443 origin. | developers.cloudflare.com/ssl/origin-configuration/origin-ca and /ssl-modes/full-strict (fetched 2026-11-05) |
| F12 | Not documented (labelled `unverified`): whether the LB monitor trusts an Origin CA certificate; whether LB monitors present Authenticated Origin Pulls client certificates; whether a header-matching expression is accepted by a Configuration Rule `ssl` override. Each has a built-in falsifier below. | Cloudflare monitor, AOP and Configuration Rules pages return no statement |

## Rulings

All forks below are technical. They are recorded, not asked.

### R1 - Ruled by CTO agent, 2026-11-05: Option A (Origin CA + origin :443 listener + `strict`), not the Cloudflare Tunnel

- **Decision:** terminate the Cloudflare-to-origin hop with TLS on the web hosts' own :443; do not route `app.soleur.ai` through the tunnel.
- **Rationale:** the tunnel option changes the serving topology (the LB pool origins are IP addresses; the tunnel is a hostname connector), puts `cloudflared` in the path of every user request (the 2026-07-11 deploy-tunnel dial-storm post-mortem is the evidence that it is a fragile dependency), and cannot be done without a DNS and LB rewrite that is itself a production write with no staging host (F6). Option A is additive: the new listener is inert until material exists, and the zone stays `flexible` until proven.
- **Rejected alternatives:** tunnel (above); interim `full` as the end state (encrypts, does not authenticate the origin; the CLO ruled it does not meet done-when).
- **Dissent:** none recorded. Evidence that would flip it: the tunnel already fronting the serving path for another reason.

### R2 - Ruled by CTO agent, 2026-11-05: TLS terminates inside the app container (second listener in the Node process)

- **Decision:** `server/origin-tls.ts` starts an `https` server on container port 3443 that re-emits the plain server's `request` and `upgrade` events; Docker publishes it as host 443. Not a host reverse proxy, not a sidecar container.
- **Rationale:** (1) it needs no change to any host: no package, unit, image or `hcloud_server` attribute, so `hr-prod-host-config-change-immutable-redeploy` is not engaged and no host is replaced (`web-1` cannot be replaced anyway); (2) it rides the release path that already reaches both hosts (`ci-deploy.sh` fan-out); (3) the certificate arrives the way every other runtime secret does (Doppler `prd` to env-file); (4) the app stays single-process and the two listeners cannot drift, because there is one handler set. WebSocket upgrades are covered by re-emitting `upgrade` to the listener that `setupWebSocket` registered (test: 101 over TLS).
- **Rejected alternatives:** host stunnel/nginx/Caddy (delivery to a frozen `web-1`, apt on a running host, parity tests, an extra failure domain on every request); a sidecar container (a new image to pin and cosign-verify, a second restart unit, port 443 handed between containers during the canary swap); `--network host` (changes the whole container network model).
- **Dissent:** a host proxy would keep the key out of the app process. Accepted: the app container already holds higher-value secrets (Supabase service role, BYOK master key); the agent subprocess receives an env allowlist (`server/agent-env.ts`, `AGENT_ENV_ALLOWLIST`), so the key does not reach agent code.

### R3 - Ruled by CTO agent, 2026-11-05: Cloudflare Origin CA certificate, ECC, 15 years, one name (`app.soleur.ai`), one pair shared by both hosts

- **Decision:** Origin CA, `request_type = origin-ecc`, `requested_validity = 5475`, SAN `app.soleur.ai` only (no wildcard, no `lb-staging`), one key and certificate for the fleet.
- **Rationale:** Origin CA is the certificate Cloudflare verifies under `strict` and needs no ACME client, renewal job or DNS credential on the hosts. A single name limits what a leaked key can impersonate (and an Origin CA certificate is trusted only by Cloudflare, not by browsers). A shared pair avoids per-host Doppler selection that a frozen `web-1` cannot receive (same reasoning as `proxy-tls.tf`).
- **Rejected alternatives:** Let's Encrypt via DNS-01 (needs an ACME client in the image, 90-day renewal automation and `CF_API_TOKEN_DNS_EDIT` reachable from the serving container; more moving parts than a 15-year certificate); self-signed (valid only under `full`, which does not authenticate); wildcard `*.soleur.ai` (wider impersonation surface for no benefit).
- **Dissent:** none. Evidence that would flip it: Cloudflare shortening Origin CA validity or deprecating the endpoint.

### R4 - Ruled by CTO agent, 2026-11-05: the key is minted OUTSIDE Terraform and delivered through Doppler `prd`; renewal needs no operator

- **Decision:** a dispatch-only mint workflow (PR-2, modelled on `key-rotate.yml`) generates the key and CSR on the runner, calls the Origin CA API, and writes `ORIGIN_TLS_KEY_B64` and `ORIGIN_TLS_CERT_B64` to Doppler `soleur/prd`. No `tls_private_key`, no `cloudflare_origin_ca_certificate`, no Terraform resource holds the key.
- **Rationale:** ADR-320 forbids a Terraform-minted secret in the Tier-A-readable web-platform state when it grants production access; an origin TLS key lets an on-path party read and forge the hop that carries credentials and user content, so it is in scope. The stricter option applies because the key class is not clearly outside ADR-320. Renewal: 15-year validity means no renewal event in the product's planning horizon; expiry is watched from inside (startup log, Sentry warning at under 90 days, Better Stack alert) because Cloudflare sends no expiry notice (F11). Re-mint is the same dispatch plus a container restart.
- **Rejected alternatives:** `tls_private_key` + `cloudflare_origin_ca_certificate` in the web-platform root (key in readable state; also a new no-default root variable would fail every merge-triggered apply until the credential exists, per the note in `seo-config-rules.tf`); an operator pasting the key by hand (hr-never-label-any-step-as-manual).
- **Dissent:** the Terraform route is shorter. Accepted cost: one extra workflow.
- **Credential (name and access level only):** a Cloudflare API token, permission "Zone / SSL and Certificates / Edit", resource scope zone `soleur.ai`, stored in Doppler `prd_terraform` as `CF_API_TOKEN_ORIGIN_CA`. Existing tokens are not reused (`CF_API_TOKEN_DNS_EDIT` is DNS-only and runtime-reachable; the rulesets token has no certificate scope as far as is known, `unverified`).

### R5 - Ruled by CTO agent, 2026-11-05: Authenticated Origin Pulls are NOT adopted in this effort (CLO condition 7)

- **Decision:** no AOP now. Origin CA cert owner: the CTO function (Jikigai Cloudflare account). Renewal: R4. Revisit trigger: after `strict` has been stable for 14 days AND the LB-monitor question (F12) is answered, or any evidence of direct origin access.
- **Rationale:** AOP closes "another Cloudflare tenant dials our origin IP", an exposure that already exists on :80, requires knowing the origin IP, and is bounded because the app authenticates every request EXCEPT the loopback-gated internal endpoints (corrected by review, #12181: those now also refuse requests carrying proxy markers, see ADR-321 decision 4) itself (session cookies, HMAC webhooks). AOP adds a failure mode of its own (a misconfigured client-certificate check is an outage under `strict`) and it is unknown whether LB monitors present client certificates (F12). The stricter-for-users option is to avoid a second outage lever during the deadline window.
- **Rejected alternatives:** shared-certificate AOP (proves only "came from Cloudflare", which the firewall allowlist already says); zone-level custom AOP now (new credential scope and a new upload step on the critical path).
- **Dissent:** the CLO asked for a decision, not for AOP. A tracking issue is filed with the revisit trigger (see Follow-ups).

### R6 - Ruled by CTO agent, 2026-11-05: staged flip = listener, host-side proof, header-scoped canary rule, monitor, host-wide `strict`; no throwaway host

- **Decision:** order of effects: (1) listener deployed inert on both hosts; (2) material minted and loaded, verified per host; (3) LB monitor moved to https/443; (4) a canary configuration rule sets `ssl = "strict"` ONLY for requests with host `app.soleur.ai`, path `/health` and header `x-origin-tls-probe: 1`, placed after the flexible rule (set_config is last-wins); (5) probe `origin-tls-probe.sh --canary --expect tls` must exit 0; (6) only then the host-wide rule edit to `strict` (flexible rule edited, canary rule removed in the same change); (7) port 80 stays open until the post-flip probe passes (CLO condition 3).
- **Rationale:** F6 removes the throwaway host, so the canary has to be on the real hostname, and a header-scoped rule gives a strict-mode request that no user can trigger by accident while every user stays `flexible`. If Cloudflare rejects a header expression, the apply fails closed with nothing changed; if it accepts but ignores it, the probe sees no `x-origin-transport` header and exits 3, so the canary cannot read as success. Fallback if header scoping is unavailable: a `full` step on the host (separates a 525 handshake failure from a 526 certificate failure) after the host-side proofs.
- **Rejected alternatives:** recreate `lb-staging` (a production DNS and LB write on the critical path, torn down once already); flip straight to `strict` after the host-side proofs (a bad certificate is a user-visible 526 until rollback).
- **Dissent:** none.

### R7 - Ruled by CTO agent, 2026-11-05: LB monitor moves to https/443 before the host-wide flip; `allow_insecure = false` first

- **Decision:** after step (2) of R6, change `cloudflare_load_balancer_monitor.web` to `type = "https"`, `port = 443` through the `cf-lb-overlay.yml` `ga-monitor-fix` arm. Start with certificate verification ON. If the pool goes Unhealthy only because the monitor does not trust the Origin CA (observable in the pool health notification), set `allow_insecure = true` with a dated exception block in the encryption-posture ledger; the user-path certificate proof then rests on the `strict` 200 plus the transport header, not on the monitor.
- **Rationale:** a monitor left on :80 stays green while :443 is broken, and the B1 self-fallback hides an unhealthy pool, which is the defect `cloudflare-lb.tf` already documents in the other direction. Moving it after the material is verified avoids paging on the expected gap.
- **Rejected alternatives:** leave the monitor on :80 (false green after the flip); `allow_insecure = true` from the start (gives up the check before it is known to be needed).
- **Dissent:** none.

### R8 - Ruled by CTO agent, 2026-11-05: rollback is roll-forward only; the listener is inert-able without a deploy of code

- **Decision:** roll back the flip by re-PUTting the app rule to `flexible` through the `http_config_settings` entrypoint (a Terraform edit of the rule applied by the merge apply, or the same PUT through the entrypoint endpoint if the apply is unavailable), never `git revert` (a revert plans a destroy of the whole entrypoint; `seo-config-rules.tf` documents this). Port 80 and the firewall are not touched by any slice. To disable the listener: remove the two Doppler secrets and restart the container; the listener starts only on valid material.
- **Dissent:** none.

### R9 - Ruled by CTO agent, 2026-11-05: per-host proof comes from the host, not the edge (F10)

- **Decision:** PR-2 adds a signed read-only webhook hook `origin-tls-handshake` (modelled on `inngest-tls-handshake` in `hooks.json.tmpl`) that, on a given web host, completes a TLS handshake to 127.0.0.1:443 with SNI `app.soleur.ai` and returns chain issuer, SAN, notAfter and TLS version. The app also logs the loaded certificate fingerprint per host at start (already in this PR), readable in Better Stack by `host_name`.
- **Rationale:** the CLO's evidence set requires a handshake probe per web host; the edge reaches only web-1 while web-2 is drained.
- **Dissent:** none.

## Design (this PR)

```text
Cloudflare edge --(plain HTTP today)--> host:80  -> container:3000  (server.listen, unchanged)
Cloudflare edge --(TLS, after material)--> host:443 -> container:3443 (server/origin-tls.ts)
                                                         |-- re-emits 'request' and 'upgrade' to the SAME HTTP server handlers
                                                         `-- /health only: response header x-origin-transport: <TLSv1.x>
```

- `loadOriginTlsMaterial` returns `absent`, `invalid(reason)` or `ready`. `ready` requires: both variables present, base64 PEM, key parses, certificate parses, key matches certificate, leaf (not a CA), inside its validity window, covers `app.soleur.ai`.
- `startOriginTlsListener` never throws. Absent: info log, nothing starts. Invalid: `reportSilentFallback(feature "origin_tls", op "load", tags.reason)`, nothing starts, the plain listener keeps serving. Bind error: `reportSilentFallback(op "listen")`. Under 90 days to expiry: `warnSilentFallback(op "cert_expiry")`.
- Neither the key nor any PEM body is logged or put into an error or Sentry extra (test asserts this).
- Keep-alive and timeouts are left at the same defaults as the plain server (parity, no new knob).
- `index.ts` closes the TLS listener on SIGTERM next to the HTTP server.
- Container port 3443 is published as host 443 at the production site in `ci-deploy.sh`, the first-boot site in `cloud-init.yml`, and declared in `lib/docker-run-tuple.py` (both app tuples). The canary container (3001) does not publish it.
- Publishing 443 with no listener behind it is harmless: the connection is refused, the firewall admits only Cloudflare ranges, and Cloudflare does not use 443 while the zone is `flexible`.

## Slices

| PR | Content | Production effect at merge |
|---|---|---|
| PR-1 (#12181, this) | Plan, ADR-321, listener, port publish, tuple gate, handshake probe + test | Yes: `apps/web-platform/**` triggers the release deploy, and `infra/**` triggers the apply that re-pushes `ci-deploy.sh` to both hosts (`deploy_pipeline_fix`, `deploy_pipeline_fix_web2`). The classifier says `production-effecting` (`reason=outside-allowlist`). No user-visible change: nothing listens on 3443 yet. |
| PR-2 | Mint workflow (dispatch-only, `CF_API_TOKEN_ORIGIN_CA`), `origin-tls-handshake` hook, Better Stack expiry alert, ledger row `scripts/encryption-posture-ledger.json` converted to "measured" after the flip | Yes (hook delivered by the infra-config push) |
| PR-3 | Monitor to https/443 (`cf-lb-overlay.yml` arm, dispatch) and the canary configuration rule + test updates (`seo-config-rules.test.ts` rule count and expressions, `ssl-full-mitigation.test.sh`) | Yes (Cloudflare write) |
| PR-4 | None (reserved: monitor fallback to `allow_insecure` only if R7 says so) | - |
| PR-5 | The `strict` flip: edit the flexible rule to `strict`, remove the canary, mirror-pair legal wording is the CLO's separate PR | Yes (Cloudflare write) |

Each slice is its own draft PR and each production-effecting step is a named hold below.

## Operator Holds

No standing delegation covers this PR: the epic #10205 delegation (comment 6491716897) names only #11287 and #11324, and the owner gave none for this work. Every production-mutating step is therefore reserved. The commands are written out so the owner can say yes to each by name.

- Hold: Operator-reserved: mark #12181 ready for review (`gh pr ready 12181`). Merging it deploys the new image to both web hosts and re-pushes `ci-deploy.sh`; no user-visible change.
- Hold: Operator-reserved: queue #12181 to merge (`gh pr merge 12181 --squash --auto`) after its required checks pass.
- Hold: Operator-reserved: mint the Cloudflare API token `CF_API_TOKEN_ORIGIN_CA` (permission Zone / SSL and Certificates / Edit, zone soleur.ai only) and store it in Doppler `prd_terraform`. Credential minting is yours; the CTO cannot create it (the existing broad token lacks the scope for token creation, per `cf-cert-reissue-token.tf`).
- Hold: Operator-reserved: run the certificate mint (PR-2 workflow dispatch, `gh workflow run mint-origin-ca-cert.yml`). It writes `ORIGIN_TLS_KEY_B64` and `ORIGIN_TLS_CERT_B64` to Doppler `soleur/prd`, a production secret write.
- Hold: Operator-reserved: restart the app container on both web hosts so they load the certificate (the web-platform release redeploy dispatch). A container restart briefly drops WebSocket sessions on that host.
- Hold: Operator-reserved: dispatch the load balancer monitor change to https/443 (`cf-lb-overlay.yml`, `ga-monitor-fix` arm).
- Hold: Operator-reserved: merge the canary configuration rule PR (PR-3). It changes a Cloudflare rule on the production zone, for requests carrying one probe header only.
- Hold: Operator-reserved: the strict flip itself (PR-5 merge). It changes `app.soleur.ai` to `strict` for every user. Not to be requested until the canary probe exits 0 and both hosts' handshake hooks show the certificate.
- Hold: Operator-reserved: any change to the Cloudflare Authenticated Origin Pulls or Page Rules scope; and a token with Page Rules read for Class R check C, which is a credential change.
- Hold: the mint waits for this PR's listener to be deployed on both hosts.
  Gate: pr-merged 12181

## Class R Checks

Run by the CTO agent, 2026-11-05, GET and local-test only; no write, no credential used.

- Checked: live app host transport #10479 - `bash apps/web-platform/infra/origin-tls-probe.sh` printed `origin-tls-probe: mode=plain http=200 transport=none cf_cache=DYNAMIC result=OK`; with `--canary --expect tls` it exited 3. Matches Flexible.
- Checked: lb-staging host existence #10479 - `getent hosts lb-staging.soleur.ai` returned nothing and `curl` returned status 000. The throwaway staging host is gone (F6).
- Checked: merge classifier #12181 - `merge-effect-class.sh --pr 12181` printed `production-effecting reason=outside-allowlist sha=222a37a6...`.
- Checked: docker-run tuple gate #12181 - `docker-run-tuple.test.sh` 296 passed, 0 failed; `cloud-init-user-data-size.test.ts` 87 passed.
- Unverified: Cloudflare pagerules-ssl (C) #10479 - other: token-lacks-scope (carried from the 2026-11-05 read). A legacy page rule could still override SSL for the app host; the flip PR must re-check it or state it unverified.
- Unverified: LB monitor trust of Origin CA, AOP client certificates on monitors, header expressions in Configuration Rules #10479 - other: not-documented (F12). Each has a falsifier in R6 and R7.
- Unverified: whether an existing token carries SSL and Certificates scope #10479 - other: no read-only check exists in the wrapper for it. Not worked around.

## Observability

```yaml
liveness_signal:
  what: "GET https://app.soleur.ai/health response header x-origin-transport (set only by the TLS listener), read by origin-tls-probe.sh; plus the existing keyword monitor on /health"
  cadence: "probe on demand and in the flip PR gate; Better Stack betteruptime_monitor.app_health every 180 s covers the user path (a 526 under strict fails it)"
  alert_target: "Better Stack uptime policy already attached to app_health; Cloudflare notification policy web_lb_health for pool health"
  configured_in: "apps/web-platform/infra/uptime-alerts.tf (app_health), apps/web-platform/infra/cloudflare-lb.tf (web_lb_health), apps/web-platform/infra/origin-tls-probe.sh"
error_reporting:
  destination: "Sentry, feature=origin_tls (op=load with tags.reason, op=listen, op=cert_expiry); pino line origin-tls:* to Better Stack Logs with host_name"
  fail_loud: "yes: invalid material and bind errors are reportSilentFallback (error); under 90 days to expiry is warnSilentFallback; the plain listener keeps serving so a bad certificate is loud but not an outage while the zone is flexible"
failure_modes:
  - mode: "material present but invalid (wrong key, wrong host, expired, CA cert)"
    detection: "Sentry origin_tls/load with tags.reason; startup log absent"
    alert_route: "Sentry issue alert on feature:origin_tls (added in PR-2); Better Stack log line origin-tls: listening absent after a deploy"
  - mode: "listener down while zone is strict (user sees 521/525/526)"
    detection: "app_health keyword monitor fails; LB pool Unhealthy once the monitor is https/443"
    alert_route: "Better Stack uptime escalation; Cloudflare web_lb_health email"
  - mode: "certificate nearing expiry (no Cloudflare notice exists)"
    detection: "startup log daysLeft and Sentry warning below 90 days; Better Stack Logs alert on the origin-tls line (PR-2)"
    alert_route: "Sentry warning today; the Better Stack alert policy is a forward reference added with the mint workflow in PR-2 (review of #12181 found none in PR-1)"
  - mode: "strict accepted at the edge but a host's listener is down (web-2 is drained so the edge cannot see it)"
    detection: "origin-tls-handshake hook per host (PR-2)"
    alert_route: "post-deploy gate in the release workflow output; flip PR refuses without both hosts"
logs:
  where: "container stdout to journald to Better Stack Logs (host_name tagged); Sentry for errors"
  retention: "Better Stack Logs retention as configured for the web sources; Sentry project retention"
discoverability_test:
  command: "bash apps/web-platform/infra/origin-tls-probe.sh"
  expected_output: "origin-tls-probe:"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Doppler soleur/prd secrets ORIGIN_TLS_KEY_B64 and ORIGIN_TLS_CERT_B64 (PR-2 writes them)"
    mechanism: "Doppler secret store, masked; the key is never in Terraform state (ADR-320)"
    evidence: "no tls_private_key or doppler_secret for these names in infra/*.tf; ADR-321"
    defends_against: "key exposure through the Tier-A-readable R2 state bucket"
    does_not_defend: "a holder of Doppler prd read access; a compromise of the app container, which holds the key in its environment; crypto-erasure (copies live in Doppler history)"
    disclosed_as: "ADR-321, this plan"
    live_verification: "the mint workflow's read-back (PR-2); this PR stores nothing"
in_transit:
  - connection: "Cloudflare edge to web host :443 (new)"
    tls: "TLS 1.2 minimum (Node default raised explicitly), ECC Origin CA certificate"
    cert_verification: "on (Cloudflare strict verifies issuer, expiry and hostname)"
    does_not_defend: "no origin authentication of Cloudflare (Authenticated Origin Pulls not adopted, R5); other Cloudflare tenants can still reach the origin IP; the Origin CA certificate is trusted only by Cloudflare, so direct non-Cloudflare clients cannot validate it"
    disclosed_as: "Privacy Policy s11 and DPD 8.1(c) amended by the CLO's wording PR after the flip; today's wording says TLS is not claimed for this hop"
  - connection: "Cloudflare edge to web host :80 (existing, stays open until the post-flip probe passes)"
    tls: "none (plain HTTP)"
    cert_verification: "off (no TLS)"
    does_not_defend: "everything on this hop: cookies, tokens, content, BYOK key at submission"
    disclosed_as: "Privacy Policy s11 'not claimed' wording already live; scripts/encryption-posture-ledger.json row for this hop"
  - connection: "Cloudflare LB monitor to web host (https/443 after R7)"
    tls: "TLS; verification starts ON"
    cert_verification: "on, with a possible dated exception (allow_insecure) per R7"
    does_not_defend: "if the exception is taken, the monitor does not authenticate the origin; the user-path proof is the strict 200 with the transport header"
    disclosed_as: "R7"
exception:
  justification: "the :80 row is a plaintext exception that exists today and is retired by PR-5; no new plaintext path is added"
  tracking_issue: "#10479"
  reevaluate_when: "the PR-5 post-flip probe passes, then port 80 is reviewed for closure"
  expires_on: "2026-11-19"
```

## User-Brand Impact

- **If this lands broken, the user experiences:** (this PR) nothing: no listener starts without material. (the flip) every dashboard page and the chat WebSocket return Cloudflare 521, 525 or 526 for all users until the rule is rolled forward to `flexible`.
- **If this leaks, the user's data and workflow are exposed via:** the Cloudflare-to-origin hop today (session cookies and auth tokens, chat prompts and agent output, knowledge-base content, a BYOK API key at submission, Inngest step-call inputs and outputs) to an on-path observer between Cloudflare and Helsinki. After the fix, via the origin private key if it is mis-stored (hence ADR-320 handling) or logged (hence the no-key-in-logs test).
- **Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true` is set in the frontmatter: CPO sign-off is required before PR-5 (the flip), which is the only slice with a user-visible failure mode. This slice changes no user-visible behaviour. `soleur:engineering:review:user-impact-reviewer` runs at review time of PR-5.

## Infrastructure (IaC)

- **Blast radius of PR-1:** no `hcloud_server`, volume, firewall or Cloudflare resource is touched. `cloud-init.yml` is rendered into `user_data`, which `hcloud_server.web` ignores, so no host is replaced and none is rebuilt unattended. The merge apply re-pushes `ci-deploy.sh` to both hosts through the existing provisioners (host fan-out class: `twin`, already implemented as `deploy_pipeline_fix` and `deploy_pipeline_fix_web2`). The release deploy restarts the container (brief WebSocket reconnect), as every `apps/web-platform/**` merge does.
- **Fresh hosts:** `cloud-init.yml` carries the same `-p 0.0.0.0:443:3443`, so a replaced web-2 is born with the port published; the tuple gate pins the parity.
- **Doppler / secrets:** this PR reads two env names it never writes. Values are minted by PR-2. No value appears in the repository, the PR body or any comment.
- **Terraform:** none in this PR, on purpose (R4). PR-3 and PR-5 edit `seo-config-rules.tf`; the apply is the per-merge `-target` apply that already includes `cloudflare_ruleset.seo_config_settings`. The `Pre-apply entrypoint gate` and the drift run protect the whole-list replacement.
- **Order guarantee:** the app is never down because of ordering: listener (inert), material, monitor, canary, flip, in that order, each gated by the previous step's evidence (R6).

## Guard Contract

### Guard 1 - strict-flip precondition test (PR-5, written before the flip)

**Property.** A tree whose app-host `ssl` rule is `strict` also contains every precondition that makes strict safe: the 443 publish at the two LB-served docker-run sites (prod in ci-deploy.sh and first-boot in cloud-init.yml; the canary is deliberately NOT published, ADR-278), the load balancer monitor on https/443, and no `lb-staging`-only coupling.

**Assembly.** The chokepoint is the set of `ssl` rules in `seo-config-rules.tf` that match the app host (the flexible rule and the canary rule), the three `docker run` sites enumerated by `lib/docker-run-tuple.py` (canary, prod, first-boot), and `cloudflare_load_balancer_monitor.web`. Members are derived by parsing the files, not listed by name; the test fails if it finds zero `ssl` rules or zero run sites.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| M1 | App rule set to `strict` while `ci-deploy.sh` loses `-p 0.0.0.0:443:3443` | precondition (publish) missing at a run site |
| M2 | App rule `strict` while the monitor stays `http`/80 | monitor would stay green on a broken 443 |
| M3 | Add a second, wider `ssl` rule for the app host after a compliant first | a check that stops at the first member |
| M4 | The test's own dispatch: parser returns zero rules | a guard that checks 0 and exits 0 is vacuous |
| M5 | Move the canary rule BEFORE the flexible rule | last-wins ordering: the canary would be overwritten (REORDER row) |

**Harness rows.** Edit the suite to skip the monitor assertion (must be caught by a mutation-of-the-suite row). Must-PASS input that is not the canonical: a tree with the canary rule only, app rule still `flexible`.

**Anchor.** The preconditions are checked against `origin/main` merge-base, not only against the PR's own tree, so one diff cannot weaken both the rule and the check.

## Acceptance Criteria (PR-1)

- [x] `apps/web-platform/test/origin-tls.test.ts` passes (17 cases: every `invalid` reason, valid material over real TLS, `/health` header present and absent on the plain server, WebSocket upgrade over TLS, untrusted-client refusal, bind-error report). Command: `cd apps/web-platform && npx vitest run --project unit test/origin-tls.test.ts`.
- [x] `npx tsc --noEmit` and `npx eslint` clean on the touched files.
- [x] `bash apps/web-platform/infra/docker-run-tuple.test.sh` passes (296 rows) with the 443 port declared on both app tuples and absent from the canary tuple.
- [x] `bash apps/web-platform/infra/origin-tls-probe.test.sh` passes (17 assertions, floor 16).
- [x] `closingIssuesReferences` of #12181 is empty before the body is saved (verified with `gh pr view 12181 --json closingIssuesReferences`).
- [ ] CI: `ci-deploy.test.sh` (long suite) green on the PR.
- [ ] No Cloudflare rule change, no certificate, no Terraform resource in the diff (`git diff --stat origin/main` shows none under `*.tf`).

## Test scenarios

- Given no ORIGIN_TLS env, when the server starts, then no TLS port is bound and nothing is reported.
- Given a key and certificate for another host, when the server starts, then no TLS port is bound, Sentry gets `origin_tls/load reason=hostname-mismatch`, the plain listener serves.
- Given valid material, when a client with the pinned certificate requests `/health`, then 200 with `x-origin-transport: TLSv1.2|3` and the plain `/health` has no such header.
- Given valid material, when a client sends a WebSocket upgrade over TLS, then the same upgrade listener answers 101.
- Given the live zone is Flexible, when `origin-tls-probe.sh --expect tls` runs, then it exits 3 (never reads as success).

## Domain Review

**Domains relevant:** Engineering (this plan), Legal (CLO owns the wording and the 2026-11-09 checkpoint), Operations (`knowledge-base/operations/domains.md` "SSL Mode" caveat after the flip).

### Legal

**Status:** deferred to the owning leader. The CLO rulings of 2026-10-27 and 2026-11-02 (#10479) fix the dates and conditions; this plan satisfies conditions 2 to 7 by R3 to R8 and leaves condition 1 (CTO read-only checks) with the Class R section above. Wording changes to Privacy Policy s11, DPD 8.1(c), the Article 30 register markers and `legal-doc-shas.ts` are the CLO's separate PR after the flip; nothing in this PR edits a legal document.

### Product/UX Gate

**Tier:** none (no UI). Wireframe gate (`wg-ui-feature-requires-pen-wireframe`) is not applicable: no page, component or user-visible string changes.

## Architecture Decision

ADR-321 (proposed) is committed with this PR: TLS terminates in the app container, Origin CA, mint outside Terraform. C4: no new container or external system; the existing Cloudflare-to-web-host relationship gains "TLS" as its protocol after the flip, to be updated in PR-5.

## Capability gaps

- A read-only Class R check for "which token carries SSL and Certificates scope" does not exist in `cloudflare-readonly.sh`; PR-2 should add one rather than testing tokens ad hoc. (PR #12176 already re-derives the wrapper's `enabled_ssl_rules` snapshot.)
- No web-host no-SSH read hook for listener state exists (R9, PR-2).

## Follow-ups to file

- Authenticated Origin Pulls decision record with the R5 revisit trigger.
- Close port 80 on the firewall only after PR-5's post-flip probe and a review (not scheduled here).

## Sharp edges

- The edge probe sees web-1 only (F10); never treat a green edge probe as proof for web-2.
- A header-scoped rule that Cloudflare accepts but ignores looks like success unless the probe demands the transport header; that is why `--expect tls` exists and why the flip gate must run it.
- `cloud-init.yml` is size-budgeted and effectively comment-frozen; the added line is one flag. The size test passes.
- Never run a Cloudflare read outside `cloudflare-readonly.sh`; the token check above is therefore `unverified`, not guessed.
- Roll forward only: never `git revert` a PR that touched `seo-config-rules.tf`.
