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
   | `ORIGIN_TLS_REQUIRED` | `1` or unset | Unset: absent/invalid material is inert. `1`: it is fatal (decision 6). Set in Doppler `prd` by the owner as act 1 of the flip order (item 10), before the edge flips; it takes effect at the next container start. |

   A rejected certificate is reported to Sentry as `feature=origin_tls`, `op=load`, `tags.reason=<enum>`; a context that
   cannot be built as `op=create`; a bind error as `op=listen`. The once-per-start line
   `origin-tls: listening ... certificate loaded` is emitted at warn so it reaches Better Stack (Vector drops INFO). From the release that carries PR #12388 it also states `required` (a boolean: whether `ORIGIN_TLS_REQUIRED=1` was in effect in that process), so "REQUIRED is live on this host" is a direct per-host read. Post-bind listener events follow the policy of decision 6 as amended by item 11.
3. **The strict flip is staged, and its lever is the app-host Configuration Rule** (the mechanism is amended by item 10 of the 2026-11-07 amendments below; R6 and R8 are defined in the archived plan, `knowledge-base/project/plans/archive/20261105-200240-2026-11-05-feat-origin-tls-listener-plan.md`): listener inert and deployed to both
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
   a listener error BEFORE the bind completes is reported and then fatal, so the canary container (same env-file) exits, its health
   gate fails and the old container keeps serving. Without it a bad deploy would pass the canary and Cloudflare, in
   `strict`, would answer 525/526 to every user. *Amended by item 11 (PR #12388):* after the bind, an unexpected `close` of the
   https server is also fatal under REQUIRED, and a server `error` is reported at most once a minute and the process continues.
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
- Idle keep-alive is set above Cloudflare's reuse window (`keepAliveTimeout` 905 s) on BOTH servers, from one shared
  constant. `headersTimeout` is a separate matter (item 11, R-A): the plain :80 server sets 910 s, but Node bounds the header phase by
  `requestTimeout` (default 300 s, measured), so 300 s is its operative slow-header cutoff; the :443 listener sets none and keeps
  Node's 60 s default. The ~900 s figure is unverified; a larger value only narrows the 502/520 race (Node closing first), so it is
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
9. **The canary rule (decision 3, step 4), amended 2026-11-07.** `seo-config-rules.tf` carries one static `rules` block, ALWAYS present, appended after the adopted
   `flexible` rule (last match wins): for a request to `/health` on `app.soleur.ai` that carries `x-origin-tls-probe: 1`, `set_config { ssl = "strict" }`; every other request
   to the host stays `flexible`. Its `enabled` flag is `var.enable_origin_tls_canary_rule` (default false, Doppler `prd_terraform` `ENABLE_ORIGIN_TLS_CANARY_RULE`, lowercase
   `true`/`false` only), so merge adds an inert rule and turning the canary on or off is an in-place update (the rule count never changes; see item 10 for why that matters). Proof:
   `origin-tls-probe.sh --canary` (implies `--require-tls`) exits 0 only when the rule applied AND Cloudflare accepted the Origin CA certificate under strict for that request; exit 1
   (525/526) means it applied and the certificate was refused; exit 3 means the rule did not apply. The edge canary reaches the host that carries traffic (web-1) only; web-2
   (weight 0) is covered by the https LB monitor with certificate validation (item 8) and by its `origin-tls: listening` line. The `http_config_settings` phase did accept a
   request-header field (applied 2026-11-07, canary probe exit 0). *Amended again by item 10: the first shape of this rule was a `dynamic "rules"` block that came and went, which
   made the rollback a rule REMOVAL.*
10. **The strict flip (decision 3, step 6; R6(6) amended 2026-11-07).**
    *Ruled by CTO agent, 2026-11-07 (variance from R6(6); there was no earlier ruling for it) and amended the same day by the review round.*
    **Decision.** R6 described the flip as an in-place edit of the `flexible` rule with the canary removed in the same change. Because the per-merge apply targets the whole
    ruleset resource, that edit would flip production at MERGE, before `ORIGIN_TLS_REQUIRED=1` is proven live on both hosts. The flip is therefore ADDITIVE and GATED: a second static
    `rules` block (`ssl = "strict"`, expression `(http.host eq "app.soleur.ai")`, appended last so it wins over `flexible`) that is ALWAYS present and whose `enabled` is
    `var.enable_origin_tls_strict` (default false; Doppler `prd_terraform` `ENABLE_ORIGIN_TLS_STRICT`, lowercase `true`/`false` only). Merge adds one inert (disabled) rule and changes no edge
    behaviour. The adopted `flexible` rule, the canary, the apex/www `full` rule (ADR-194) and the lb-staging host are untouched.
    **Why always-present and not a `dynamic` block (the review-round ruling).** The first shape made the rule come and go with the switch. Removing a rule shrinks `.rules`; the
    destroy guard (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`) counts that as `nested_deletes`, and `apply-web-platform-infra.yml` refuses the apply unless the HEAD commit
    message carries an `[ack-destroy]` line, which exists only on a push (`github.event.head_commit.message` is empty on `workflow_dispatch`). So "unset the switch and re-dispatch" could not roll
    anything back. Options weighed: (a) keep the rule always present and toggle only a value; (b) teach the guard a dispatch-safe ack for `ORIGIN-TLS` removals (modifies a safety guard,
    needs its own tests); (c) document the slower real path (a push with `[ack-destroy]`). Chosen: (a), as `enabled` rather than as the `ssl` value, because a disabled rule matches
    nothing, so it cannot override the canary or `flexible` whatever its position. **Measured, not asserted:** real `terraform plan` and `terraform show -json` documents, planned against a prior
    state built from the "before" configuration's own planned values (no live apply, no credentials), replayed through the real filter (committed as fixtures, asserted by T65 in
    `tests/scripts/test-destroy-guard-counter-web-platform.sh`, empty head message = a dispatch):

    | Scenario (before to after) | rules before/after | resource_deletes / nested_deletes | dispatch outcome |
    |---|---|---|---|
    | first design, rollback (dynamic block removed) | 5 to 4 | 0 / **1** | REFUSED (the hazard) |
    | merge: live 4 rules (canary on) to the new code (strict rule added disabled) | 4 to 5 | 0 / 0 | passes |
    | flip on (`enabled` false to true) | 5 to 5 | 0 / 0 | passes |
    | rollback (strict off) | 5 to 5 | 0 / 0 | passes |
    | canary off | 5 to 5 | 0 / 0 | passes |
    | canary off while strict stays on | 5 to 5 | 0 / 0 | passes |
    | cleanup (flexible edited to strict, both ORIGIN-TLS rules removed) | 5 to 3 | 0 / **2** | needs a PUSH with `[ack-destroy]` (correct for a deliberate removal) |

    The merge-time write is one extra DISABLED rule in the live entrypoint (a whole-list update, like every rule addition here). Its edge behaviour is unchanged by construction (a disabled rule
    matches nothing); the rule count therefore moves 4 to 5 at merge, and `cloudflare-readonly.sh` documents `rule_count` 5 and `enabled_ssl_rules` 2 + one per switch that is on.
    **Order of the production acts (each the owner's go):** (1) `ORIGIN_TLS_REQUIRED=1` in Doppler `prd`; (2) restart both hosts on it (same-version redeploy), so a bad certificate
    makes the candidate container fail, the redeploy fail and the old container keep serving while the edge is still `flexible`; (3) only then the Doppler switch plus an apply dispatch.
    **Scope of the step-2 guarantee.** It covers certificate-material failures caught at the candidate container. It does not cover a production-start failure after the candidate passes (decision 7:
    the previous image is not restored and the host stays down), an older image without the listener deployed later (525/526 under `strict`), or a restart with bad material that has no candidate gate.
    Rollback is `enabled` true to false (delete or set false the Doppler switch, re-dispatch the apply), measured at 109 to 370 s of apply on this workflow; the edge propagation time is not measured.
    **Break-glass is owner-only and not agent-runnable** (the entrypoint PUT of R8 needs a full-body GET and a write token the sanctioned reader does not provide, and a whole-list PUT can drop the
    apex `full` rule or reorder `flexible`); the runbook says so rather than giving an untested recipe. The cleanup change after the flip has baked edits the `flexible` rule to `strict`, removes both
    ORIGIN-TLS rules and both variables, and the owner deletes the two Doppler switches.
    **The planned "Guard 1 strict-flip precondition test" (archived plan, Guard Contract) was built only in part.** Its property (a tree with an app-host strict rule also contains the 443 publish at the
    docker-run sites and an https/443 LB monitor) is now asserted unconditionally in `apps/web-platform/test/seo-config-rules.test.ts` for the monitor half, and the publish half was already mutation-pinned
    by `infra/docker-run-tuple.test.sh` (K24e, K27i). Not built: the mutation-of-the-suite rows and the merge-base anchor the plan described, because the strict rule is present in every tree from now on
    (so there is no tree "with and without" to diff) and the per-merge anchor adds a `git` read to a vitest file for no extra property.
    **Unverified / gaps:** until the release carrying PR #12388 is deployed, the app's startup line does not state whether `ORIGIN_TLS_REQUIRED` was in effect, so "REQUIRED is live" is proven by ordering (the Doppler write precedes a green redeploy whose
    per-host `origin-tls: listening` lines follow it), not read directly; from that release on the line carries `required` and the read is direct. WebSocket upgrades have never crossed the
    edge-to-origin TLS hop under `strict` (the canary exercises `GET /health` only). The apply job auto-approves its own plan, so the human look at the plan is a local read-only plan before the dispatch
    (runbook Act 0). The flip's whole-list update replaces the entire `http_config_settings` entrypoint; a rule added in the dashboard would be deleted, which the read-only `entrypoint-audit` dispatch checks beforehand.
11. **Origin TLS hardening rulings (PR #12388).** *Ruled by CTO agent, 2026-11-08 (review round), two technical forks.*
    **R-A. The :443 server does not set `headersTimeout`.** The PR first mirrored the plain server's `headersTimeout` (910 s) onto :443. Measured: Node does not validate
    `headersTimeout` against `keepAliveTimeout` on property assignment; the operative header-phase bound is `requestTimeout` (default 300 s, nothing sets it), so the assignment
    would have LOOSENED the :443 slow-header cutoff from Node's 60 s default to 300 s; and the stated reason (an idle keep-alive socket closed at 60 s) did not reproduce: with the default,
    an idle socket stayed open at 75 s and the second request was answered on the same socket, on Node 22.23.4 and 26.13.0. Nothing demonstrates a need, so nothing is loosened: the assignment
    and its shared constant are removed, `index.ts` is unchanged in effect from main (comment corrected), and a test pins that `origin-tls.ts` assigns neither `headersTimeout` nor `requestTimeout`.
    Pre-existing and out of scope: the plain :80 server's partial-header window has been 300 s (not 60 s) since the slice-1 deploy, because of the same assignment.
    **R-B. Post-bind policy.** Three options were weighed: keep report-and-continue for every post-bind event; exit under REQUIRED on any `error` (the old behaviour); or exit only on an unexpected `close`.
    Facts: Node's `net` layer emits a server `error` from its connection handler and leaves the listener open, so a post-bind `error` is not a dead listener and `exit(1)` would drop every WebSocket on the
    plain listener for a transient condition; the realistic ways :443 dies (docker-proxy or iptables failure, a rejected certificate) raise neither `error` nor `close`; a server `close` that nobody requested is the
    one in-process sign of a dead listener. **Chosen: (c).** Before the bind: `error` is fatal under REQUIRED (the canary gate, unchanged). After it: a server `error` is reported to Sentry (`feature=origin_tls`,
    `op=listen`, `tags.phase=runtime`) at most once a minute with a suppressed count, and the process continues; an unexpected `close` is reported (`tags.reason=unexpected-close`) and is fatal under REQUIRED, so the
    container's `--restart unless-stopped` restarts it. A `close` requested by our own `close()` (shutdown) is neither. Whether libuv surfaces EMFILE through the server `error` event is unverified (the tests use it only as a
    fixture code).
    **What detects and what recovers a dead :443 after this ruling (truthfully).** Detected in-process and recovered automatically: an unexpected `close` (under REQUIRED). Detected only outside the process, recovered by a
    human redeploy: a dead :443 that raises no event (docker-proxy or iptables failure, a rejected certificate). The real detectors for those are the Better Stack `app`/`app_health` monitors (a page after roughly 4 to 6 minutes of
    failures) and the https LB monitor, which only emails ("Unhealthy") and does not drain web-1 (the B1 fallback pool is web-1 itself). There is **no committed Sentry alert rule for `feature:origin_tls`**: a Sentry event is a
    pull-based check today. A Sentry alert on `feature:origin_tls` (any event; `phase:runtime` and `reason:unexpected-close` are the interesting ones) is warranted, is production-effecting, and belongs in a separate infra
    change; it is not bundled here.
