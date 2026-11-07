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
- Expiry is watched from inside: a startup warning and a Sentry warning below 90 days. **There is no Better Stack
  alert and none is planned in the mint slice** (the earlier forward reference to one is withdrawn). The certificate is
  15 years old at expiry, so the first possible expiry event is in 2041; a Better Stack Logs alert built now would be
  untestable against a real event for 15 years and would add a Terraform apply to a slice that touches no Terraform.
  Until a trigger exists (see "Amendment, slice 2" below) the signals are the Sentry warning at container start and the
  mint workflow's `mode=plan`, which prints `existing state=... days_left=...` on any date and reports `near_expiry`
  at 90 days or less. Mid-life expiry under `ORIGIN_TLS_REQUIRED=1` crash-loops on
  restart, which is acceptable because under `strict` users would already be getting 525/526 and the canary rolls the
  deploy back.
- Rotation is a re-mint plus a container restart, never an apply side effect.
- **Per-host proof before PR-2.** The edge probe reaches only `web-1` (`web-2` is weight 0), so it cannot prove a listener
  bound on `web-2`. Until PR-2's `origin-tls-handshake` hook exists, an agent verifies each host from the startup line:
  `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep 'origin-tls: listening'`,
  decoded with `jq -r '.raw | fromjson | "\(.host_name) \(.message)"'` (one line per host per start; absence on a host
  after its deploy means no listener there), and a rejected certificate shows in Sentry as `feature:origin_tls`. Do not
  claim per-host proof before this has been read. `apps/web-platform/.env.example` carries no `ORIGIN_TLS_*` entry
  (editing it is blocked for agents); the variable table in decision 2 is the contract.
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

## Amendment, slice 2 (2026-11-06): the mint workflow

Refs: #10479. Ruled by the CTO agent. Implements decision 2's "minted outside Terraform and delivered through Doppler `prd`".

1. **Where it runs.** `.github/workflows/mint-origin-ca-cert.yml`, dispatch-only, body `scripts/mint-origin-ca-cert.sh`, offline suite
   `plugins/soleur/test/mint-origin-ca-cert.test.sh`. A `guard` job with no environment and no secret (event, first attempt, ref
   `main`, owner allowlist, inputs, typed confirm) and a `mint` job on a Tier-B environment: `infra-privileged` for `mode=plan`
   (no reviewer, read-only) and the reviewer-gated `web-platform-infra-apply` for `mode=apply`. `infra-privileged` has zero
   required reviewers (#11923), so the typed confirm alone is a fat-finger guard; running the write on the reviewer-gated
   environment adds a human approval as a second key. Both environments are main-only and carry
   `DOPPLER_TOKEN_INFRA_PRIVILEGED`.
2. **Credentials.** The Cloudflare token `CF_API_TOKEN_ORIGIN_CA` is read from the Tier-B project `soleur-infra-privileged/prd` (main-only
   environments, ADR-241); `CF_ZONE_ID` (an identifier, not a credential) from `soleur/prd_terraform`. The write to `soleur/prd` uses
   the workplace provider token the Tier-B loader exports (`TF_VAR_doppler_token_tf`), the only credential that writes the
   `soleur/prd` root (ADR-307 fact 3: no CI token writes it generically, and a new narrow write token would be an operator credential
   mint for no gain). The script runs in a deny-by-default child environment so the loader's other exports (Hetzner, R2, GitHub App
   material) never reach it. **History:** slice 2 first shipped reading the token from `soleur/prd_terraform`, which is Tier-A readable
   (ADR-241), so any branch workflow could read it; a follow-up moved it to the Tier-B project and the script no longer falls back
   to `prd_terraform` (a suite row pins that a token present only there is refused). **Residual until the owner deletes the old copy:**
   the original value still sits in `soleur/prd_terraform`. Its blast radius is bounded (it can mint Origin CA certificates for
   `soleur.ai` hostnames, which only Cloudflare trusts, and cannot change any rule or record), and deleting it from `prd_terraform`
   is an owner act in Doppler, not done by this change.
3. **Policy.** Nothing in `prd`, or a half-set, unparseable, wrong-host, expired or at most 90 days to expiry pair: mint. A valid pair
   with more than 90 days left: refused (`already_minted_not_expiring`) unless `replace=true`, which also changes the typed confirm to
   `MINT-ORIGIN-CA-REPLACE-<date>`. A replace never revokes the old certificate (a running container may still hold it until the
   next restart); the verdict names its serial. Revocation is a separate owner act.
4. **Atomicity.** Doppler has no two-secret transaction through the CLI that keeps values out of argv, so the certificate and the key are
   written by two stdin writes, read back and compared by digest, and `prd` is restored to its captured previous state on any failure
   (verdict `*_unrestored` if even the restore cannot be confirmed). Nothing restarts a container: the new value is read at the next
   start, and with `ORIGIN_TLS_REQUIRED` unset a mismatch is inert (decision 6 applies only after the flip).
5. **No secret in output.** Every response stays in a 0600 file under a private temp dir that is shredded on every exit path; the bearer
   token reaches `curl` through a config file and every Doppler value through stdin; an `::add-mask::` is registered for each
   secret-bearing string before it is used; only parsed numbers, ids, dates, digests of public material and fixed verdict tokens are
   printed. The suite scans every stream and every argv of every scenario.
6. **Unverified, carried forward.** (a) That the Cloudflare token's *create* permission is present: `mode=plan` proves the token and
   a certificate LIST for the zone, and the create can only be proven by creating. An apply that gets a 403 fails closed with nothing
   written. (b) That `DOPPLER_TOKEN_TF` is present in `soleur-infra-privileged/prd` (the loader exports it from there); a missing one
   fails closed as `no_provider_token`. (c) Cloudflare's exact response shape was read from current documentation, not from a live call.
7. **Expiry alert: deferred, documented here, not filed.** See Consequences. Trigger to build it: the strict flip landing (PR-5) plus a
   decision that 15-year expiry needs an external signal; or Cloudflare shortening Origin CA validity.

8. **LB monitor move (R7), amended 2026-11-07.** `cloudflare_load_balancer_monitor.web` becomes https/:443, `Host: app.soleur.ai`,
   `allow_insecure = false` (certificate validated), applied only by the dispatch-only `ga-monitor-https` arm of `cf-lb-overlay.yml`, whose
   grader (`cf_lb_gate_ga_monitor_https`) pins that exact shape, whose pre-gate refuses unless both origins are healthy under the current
   probe, and whose post-apply gate fails red unless both origins read healthy under the new one. A merge applies nothing. Cloudflare's
   monitor documentation does not say whether the monitor trusts an Origin CA certificate or uses `Host` as SNI (both unverified); the
   post-apply gate is the measurement, and a red result with both listeners proven is the evidence that would justify a separate,
   deliberate `allow_insecure = true` decision. Rollback is a revert PR plus the existing `ga-monitor-fix` arm (http/:80). A healthy
   https monitor proves a listener answers TLS on each origin with a certificate Cloudflare's monitor accepts; it does not prove the
   edge-to-origin traffic hop uses TLS (still `flexible` until the strict flip).
