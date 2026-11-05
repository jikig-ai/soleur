---
title: Origin TLS terminates in the app container, with a Cloudflare Origin CA certificate
status: active
date: 2026-11-05
---

# ADR-321: Origin TLS terminates in the app container, with a Cloudflare Origin CA certificate

Refs: #10479, #10205, #10136. Related: ADR-068 (multi-host), ADR-194 (apex `ssl = "full"` rollback window),
ADR-241, ADR-320 (no key in Terraform state). Plan: `knowledge-base/project/plans/archive/20261105-200240-2026-11-05-feat-origin-tls-listener-plan.md`.

## Context

Cloudflare reaches `app.soleur.ai` over plain HTTP. The **zone** SSL mode is already `strict` (read live 2026-11-05,
#10479); the hop is plain because the `http_config_settings` ruleset carries an enabled **`flexible` Configuration
Rule for the app host** (`apps/web-platform/infra/seo-config-rules.tf`, the `set_config` rule whose expression names
`app.soleur.ai`). The lever that changes the hop is therefore that rule, not the zone setting; editing the zone
setting would be a no-op for this host. The rule's expression also matches `lb-staging.soleur.ai`, which no longer
resolves, so that part is harmless today.

The Hetzner firewall already admits Cloudflare ranges on 443 (`firewall.tf`), but the app container published only 80
and 3000 and nothing listened on 443. The CLO ruled the hop must be fixed, with a hard stop of 2026-11-19 (#10479).
Two web hosts serve (`var.web_hosts`); each can be replaced from Terraform, and `web-1` is frozen on its first
cloud-init (`ignore_changes = [user_data]`), so `web-1` cannot be rebuilt to deliver this.

The apex and `www` carry their own `ssl = "full"` rule, which ADR-194 requires to stay for the whole GitHub Pages
rollback window (`runbooks/gh-pages-cert-renewal.md`, guarded by `ssl-full-mitigation.test.sh`). It is **out of scope**
here and this change must not touch it.

## Considered Options

- **A. Cloudflare Origin CA certificate, listener inside the app container (chosen).** Free, 15-year ECC certificate
  that only Cloudflare trusts; one shared by both hosts; no host package, no new image, rides the existing deploy path.
  Cons: the hop is authenticated only against Cloudflare's CA, and a 15-year certificate needs expiry watched from
  inside because Cloudflare sends no expiry notices.
- **B. Cloudflare Tunnel for the app host (rejected).** Removes the need for any origin listener. Changes the serving
  topology and puts the tunnel in the path of every request (see the 2026-07-11 deploy-tunnel post-mortem).
- **C. Host reverse proxy or sidecar (rejected).** Terminates TLS outside the app. Needs host delivery to a frozen
  `web-1`, parity tests between two delivery paths, and a new image to pin.
- **D. Let's Encrypt via DNS-01 (rejected).** Publicly trusted, but needs renewal automation and a DNS-edit token on the
  hosts.
- **E. Stay on `full` as the end state (rejected).** Encrypts the hop but does not authenticate the origin.

## Decision

1. **Terminate TLS in the app container** (option A): a second listener in the same Node process (container port 3443,
   published as host 443) that re-emits the HTTP server's request and upgrade events. No host package, no sidecar image,
   no host unit. The listener starts inside the `server.listen` callback so both come up together.
2. **Certificate: one Cloudflare Origin CA certificate** (ECC, 15 years, `app.soleur.ai` only) shared by both hosts,
   minted outside Terraform (ADR-320) and delivered as base64 through Doppler `prd` into the container env-file.

   | Variable | Content | Notes |
   |---|---|---|
   | `ORIGIN_TLS_KEY_B64` | base64 of the private key PEM | `base64 -w0 < key.pem` (one line: the env-file is line-oriented). Deleted from `process.env` after boot. |
   | `ORIGIN_TLS_CERT_B64` | base64 of the certificate PEM, **leaf first**, then any intermediates | Must be a leaf (not a CA), inside its validity window, cover `app.soleur.ai` (a `*.soleur.ai` + apex certificate does), match the key, and every block must parse. |
   | `ORIGIN_TLS_REQUIRED` | `1` or unset | Unset: absent/invalid material is inert. `1`: it is fatal (decision 6). Set only by the flip PR. |

   A rejected certificate is reported to Sentry as `feature=origin_tls`, `op=load`, `tags.reason=<enum>`; a context that
   cannot be built as `op=create`; a bind error as `op=listen`. The once-per-start line
   `origin-tls: listening ... certificate loaded` is emitted at warn so it reaches Better Stack (Vector drops INFO).
3. **The strict flip is staged, and its lever is the app-host Configuration Rule**: listener inert and deployed to both
   hosts, certificate loaded and checked per host, load balancer health check to HTTPS/443, a header-scoped canary rule
   that runs only the probe request in `strict`, probe passes, then the rule is changed host-wide. Roll forward only:
   rollback is putting the rule back to `flexible`, never a `git revert`. Port 80 stays open until the post-flip probe
   passes. The apex/`www` rule is untouched (ADR-194).
4. **Authenticated Origin Pulls are not adopted now.** The residual risk they close already exists on port 80, and they
   add an outage risk inside the deadline window. The original premise "the app authenticates every request itself"
   was false for the loopback-gated internal endpoints, a gap this change closes separately: `/internal/metrics` and
   `/internal/readyz` now also refuse any request carrying a proxy marker (`cf-ray`, `cf-connecting-ip`, `forwarded`,
   `x-real-ip`, `x-forwarded-for`), because a loopback `Host` header alone is reachable by anyone who points their own
   Cloudflare zone at the origin IP. That is defence in depth, not origin authentication; the revisit trigger is
   unchanged (the plan records it).
5. **Proof of transport.** A 200 from `/health` through the edge that carries `x-origin-transport: TLSv1.2|TLSv1.3`
   proves the hop used TLS; the plain-HTTP listener never sets it. It proves **Cloudflare accepted the certificate**
   only when the zone or the canary rule is in `strict` for that request, because under `full` Cloudflare dials TLS
   without validating the certificate. `apps/web-platform/infra/origin-tls-probe.sh` reports `result=` and its exit
   code: `0` TLS (or plain without `--require-tls`), `1` non-200, `2` unreachable, `3` `--require-tls` not satisfied,
   `64` usage. Today `--require-tls` exits 3 and that is the correct pre-flip answer.
6. **Fail closed at the flip.** With `ORIGIN_TLS_REQUIRED=1`, absent or invalid material, an unbuildable TLS context, or
   a listener error is reported and then fatal at startup, so the canary container (same env-file) exits, its health
   gate fails and the old container keeps serving. Without it a bad deploy would pass the canary and Cloudflare, in
   `strict`, would answer 525/526 to every user.
7. **Deploy safety for the new publish.** The canary does not publish host 443, so `ci-deploy.sh` checks that host 443
   is free (`host_443_preflight`) before the canary starts, refusing with `host_443_in_use` or
   `host_443_check_unavailable` while the old container still serves. Restoring the previous image when the production
   start fails for any reason is a pre-existing gap, **accepted here and not fixed by this change**: the arm leaves the
   host down until a human intervenes. The pre-swap check is check-then-act (a listener that appears between the check
   and `docker run` still reaches the arm), it is skipped when the running container already publishes 3443, and a
   docker-proxy/iptables failure of the new publish is unguarded. A restore of the previous image needs a known previous
   image reference and a tested rollback in the deploy script and is its own change.

## Consequences

- No `hcloud_server` is touched, so no host replacement and no change to the host-replace gates. Merging redeploys
  both web hosts through the normal path (live sessions reconnect), but nothing listens on 443 until a certificate
  exists.
- **Preconditions the flip PR (PR-5) must satisfy, written here so it cannot skip them:** (a) `ORIGIN_TLS_REQUIRED=1`
  is set in Doppler `prd` and visible in the canary's container environment; (b) both hosts run a release containing the
  switch; (c) the per-host handshake probe (PR-2's `origin-tls-handshake` hook) exits 0 on each host; (d) the load
  balancer monitor move to HTTPS/443 (R7) has been gated on **both** pool members reporting healthy and on the monitor
  trusting an Origin CA certificate. A previous `https` monitor reported every origin down and the B1 self-fallback hid
  it (`cloudflare-lb.tf`), so a healthy-looking pool is not enough on its own.
- Expiry is watched from inside: a startup warning, a Sentry warning below 90 days, and a Better Stack alert. **The
  Better Stack alert does not exist yet** (a forward reference, added with the mint workflow in PR-2); until then the
  Sentry warning at container start is the only signal. Mid-life expiry under `ORIGIN_TLS_REQUIRED=1` crash-loops on
  restart, which is acceptable because under `strict` users would already be getting 525/526 and the canary rolls the
  deploy back.
- Rotation is a re-mint plus a container restart, never an apply side effect.
- Idle keep-alive is set above Cloudflare's reuse window (905 s, `headersTimeout` 910 s) on BOTH servers, from one shared
  constant. The ~900 s figure is unverified; a larger value only narrows the 502/520 race (Node closing first), so it is
  conservative if the real window is lower. The canary is a health gate and does not exercise Cloudflare's connection
  reuse, so the 502/520 rate is watched after the deploy.
- Unverified preconditions carried forward from the plan: legacy page rules may override SSL for the app host (the
  `pagerules-ssl` check is being given its own read token), and per-host proof for `web-2`, which carries no traffic,
  can only come from PR-2's hook, not from the edge.
- The published legal text promises a 2026-11-12 target (privacy policy section 11, data-protection disclosure 8.1(c)).
  The CLO held that target and a 2026-11-19 hard stop. On 2026-11-12 the CLO decides whether the published text stays
  or is amended, with engineering supplying the status; this ADR does not restate the date as an engineering
  commitment.

## Cost Impacts

None. A Cloudflare Origin CA certificate is issued free on the existing Cloudflare plan; no new vendor and no new paid
service (`knowledge-base/operations/expenses.md` unchanged).

## NFR Impacts

NFR-026 (Encryption In-Transit): the Cloudflare edge to web-host origin link stays **Not Implemented** until the strict
flip lands; this ADR defines the path and its preconditions. This slice moves no NFR status by itself, because the
listener is inert until a certificate exists.

## Principle Alignment

- AP-001 (Terraform-only infrastructure provisioning): Aligned. No host or Terraform resource changes in this slice.
  The certificate and its private key are deliberately minted outside Terraform per ADR-320.
- AP-004 (Agent-native parity): Aligned. The probe is read-only and machine-readable, and the mint, the per-host proof and
  the flip are agent-runnable except the credential mint.
- AP-008 (Doppler for all secrets management): Aligned. Key and certificate live in Doppler `prd`; the key is removed
  from the process environment after boot and listed in `SENSITIVE_KEY_NAMES`.
- AP-021 (Diagnostic honesty in operator-facing messages): Aligned. The probe and the proof wording name only what was
  measured (TLS on the hop, certificate acceptance only in `strict`).
