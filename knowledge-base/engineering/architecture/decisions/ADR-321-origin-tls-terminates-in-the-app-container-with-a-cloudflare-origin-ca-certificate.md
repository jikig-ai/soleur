# ADR-321: Origin TLS terminates in the app container, with a Cloudflare Origin CA certificate

- Status: proposed
- Date: 2026-11-05
- Refs: #10479, #10205, #10136, ADR-068, ADR-241, ADR-320, plan `knowledge-base/project/plans/archive/20261105-200240-2026-11-05-feat-origin-tls-listener-plan.md`

## Context

Cloudflare reaches `app.soleur.ai` over plain HTTP: the `http_config_settings` ruleset carries an enabled
`flexible` rule for the app host (`apps/web-platform/infra/seo-config-rules.tf`; live state read 2026-11-05, #10479
comment of that date). The Hetzner firewall already admits Cloudflare ranges on 443 (`firewall.tf`), but the app
container published only 80 and 3000 and nothing listened on 443. The CLO ruled the hop must be fixed with a hard stop
of 2026-11-19 (#10479). Two web hosts serve (`var.web_hosts`); each can be replaced from Terraform, and `web-1` is
frozen on its first cloud-init (`ignore_changes = [user_data]`).

## Decision

1. **Terminate TLS in the app container**: a second listener in the same Node process (container port 3443, published
   as host 443) that re-emits the HTTP server's request and upgrade events. No host package, no sidecar image, no host
   unit. It rides the existing deploy path to both hosts.
2. **Certificate: a Cloudflare Origin CA certificate** (ECC, 15 years, `app.soleur.ai` only), one shared by both hosts,
   minted outside Terraform (ADR-320) and delivered as base64 through Doppler `prd` into the container env-file.
3. **Zone mode `strict`, reached through a header-scoped canary rule first**, then host-wide; roll forward only.
4. **Authenticated Origin Pulls are not adopted now.** Revisit trigger recorded in the plan.
5. **A 200 from `/health` through the edge that carries `x-origin-transport` is the handshake proof**; the plain-HTTP
   listener never sets it.

## Consequences

- No `hcloud_server` is touched, so no host replacement and no change to the host-replace gates.
- The certificate is 15 years old at most and Cloudflare sends no expiry notices, so expiry is watched from inside
  (startup log + Sentry warning below 90 days + a Better Stack alert).
- Rotation is a re-mint plus a container restart, never an apply side effect.
- The load balancer monitor stays on http/80 until the listener is proven, then moves to https/443 so pool health
  reflects the path users take.
- Rejected: Cloudflare Tunnel for the app host (changes the serving topology and adds the tunnel to the serving path;
  see the 2026-07-11 deploy-tunnel post-mortem), a host reverse proxy or sidecar (host delivery to a frozen `web-1`,
  parity tests, a new image to pin), Let's Encrypt DNS-01 (renewal automation and a DNS-edit token on the hosts),
  and `full` as the end state (does not authenticate the origin).
