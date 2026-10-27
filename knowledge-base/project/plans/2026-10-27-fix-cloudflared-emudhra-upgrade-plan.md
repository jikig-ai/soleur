---
title: "fix: cloudflared >= 2026.10.2 fleet-wide — eMudhra intermediate-CA compromise"
type: fix
date: 2026-10-27
slug: fix-cloudflared-emudhra-upgrade
branch: feat-one-shot-cloudflared-emudhra-upgrade
issue:
lane: cross-domain
priority: P1
domain: engineering
brand_survival_threshold: none
---

# fix: cloudflared >= 2026.10.2 fleet-wide — eMudhra intermediate-CA compromise

## Overview

Cloudflare's 2026-10-20 advisory disclosed that the private keys of eight eMudhra
(emSign) intermediate CA certificates are compromised; any holder can mint certificates
for any hostname, so any TLS client whose trust store still chains to those
intermediates can be MITM'd. `cloudflared` shipped the fix in **2026.10.2**
(2026-10-20); 2026.10.3 (10-21) and 2026.10.4 (10-26) are follow-on patches.

This repo runs cloudflared in two places:

1. **CI downloads** — two composite actions (`cf-tunnel-ssh-bridge`,
   `cf-tunnel-registry-bridge`) fetch the pinned linux-amd64 release binary on every
   bridging workflow run. The pin is `2026.5.0` at **10 literal sites across 9
   workflows** (5 env-form `CLOUDFLARED_VERSION`/`CLOUDFLARED_SHA256` pairs + 5
   call-site literals) — **vulnerable**.
2. **Prod connector** — web-1 (`soleur-web-platform`, hel1) runs the tunnel's sole
   live connector on **2026.3.0** (measured via the Cloudflare `/connections` API,
   origin_ip 135.181.45.178, 4 QUIC conns, client_id a281fb1b-…) — **vulnerable**.

The advisory also instructs checking HTTPS origins whose chain hits an affected
intermediate before upgrading: **not applicable** — all three ingress services are
origin-relative and non-TLS (`deploy.`→`http://10.0.1.10:9000`,
`ssh.`→`ssh://10.0.1.10:22`, `registry.`→`tcp://10.0.1.30:5000`). No
`noTLSVerify` exists or is introduced.

web-1 itself cannot carry the fix. `hr-prod-host-config-change-immutable-redeploy`
forbids any in-place edit; `apply_target=web-host-replace` **refuses web-1 by name**
(LUKS-pinned: `hcloud_volume_attachment.workspaces_luks.server_id` is hardcoded to it
and carries `prevent_destroy`; `cloudflare_record.app` pins its ipv4; 22 web-1-pinned
SSH provisioners; guest-side LUKS unlock deferred to #6931 — tracker #6964); cx33 is
unplaceable in all 3 EU DCs (#6482); every host-birth path HALTs on `host_creates`
(#6730). The compliant path is therefore to **move the connector role to the cattle
standby web-2** — a replaceable `cpx22` host the `web-host-replace` dispatch was built
for — and to retire the credential web-1's vulnerable binary holds (tunnel `-replace`
or token rotation). `hcloud_server.web` already carries
`lifecycle { ignore_changes = [user_data, …] }`, so the flag flip and token change
produce no forced-replace diff on web-1.

This PR carries all code for both surfaces plus the detection/guard changes; the
prod migration executes post-merge as an authorized sequence (reviewer-gated dispatch
+ OPERATOR_APPLIED_EXCLUSIONS local apply), filed as a follow-through issue at ship.

## Problem Statement / Motivation

- The connector↔edge link is the management plane: `deploy.` webhooks, the CI
  `ssh.` bridge (terraform_data provisioners), and `registry.` pushes all traverse
  it. A MITM'd connector can observe and inject into all three.
- web-1's 2026.3.0 predates the advisory by ~7 months — the exact staleness class the
  repo already pays freshness owners for (`inngest-cli-staleness`, `zot-image-staleness`,
  `egress-gw-image-staleness`, `cosign-trusted-root-staleness`). No equivalent exists
  for cloudflared.
- `terraform-target-parity.test.ts` asserts pin parity only for **env-form** pins in 4
  files; 5 literal call-site pins (incl. a second literal inside
  `apply-web-platform-infra.yml:3598`, the same file that owns the env pin) are
  uncovered — a partial bump would stay green.
- The connector census (`scripts/tunnel-connector-census.sh`, polled every 15 min by
  `scheduled-inngest-health.yml`) counts connectors but never looks at
  `conns[].client_version` — a vulnerable connector reports `ok` today.

## Proposed Solution

**WS-A — CI pin bump (compliant on merge).** Set every cloudflared pin to
`2026.10.4` (latest stable; floor is 2026.10.2 for Linux, 2026.10.3 only for
non-Homebrew macOS) and recompute the sha256 by `curl`ing the real
`cloudflared-linux-amd64` release asset + `sha256sum` per the composite-action
headers — never paste from docs. Measured this session:
`ae5e8add7884b0531d66bbca4570d1de491ff6da51e4ebe7eb160cdf241d9e42`
(re-verify at work time; releases can be re-pushed).

**WS-B — Deterministic provisioning.** Replace `apt-get update && apt-get install -y
cloudflared` (unpinned; Cloudflare's apt repo rotates versions, so an exact-version
apt pin is fragile) in `cloud-init.yml` with a pinned `.deb` download +
`sha256sum -c` + `soleur-boot-emit cloudflared_checksum fatal` fail-closed arm —
mirroring the adjacent `webhook` install block byte-for-byte in shape. Remove the
now-dead Cloudflare apt source list + `cf_apt_key` stage (grep first for other
consumers). web-1's user_data is `ignore_changes`d → zero plan diff.

**WS-C — Prod connector migration (post-merge, authorized).** Flip
`web_tunnel_connector` in `server.tf` from `each.key == "web-1"` to
`each.key == "web-2"` (the flag is create-time-only; inert on running hosts). The
connector role moves permanently to the cattle standby — when web-1's eventual
#6964 replacement lands it will not re-acquire a connector, and ADR-114 I1 stays
satisfied because all ingress is origin-relative to private IPs web-2 can route.
Then, as an authorized sequence: (1) kill the credential web-1's connector holds —
default `terraform apply -replace` on
`cloudflare_zero_trust_tunnel_cloudflared.web` via the OPERATOR_APPLIED_EXCLUSIONS
local-apply contract (ADR-096); alternative is token rotation (dashboard "Rotate
token" or `PATCH tunnel_secret`) + `DELETE /connections`, which preserves the tunnel
ID; (2) dispatch `apply_target=web-host-replace -f web_host_key=web-2 -f
confirm=REPLACE-web-2 -f image_tag=<PINNED>` (reviewer-gated environment, mandatory
stock preflight — cpx22 is orderable per measured probes) — the fresh host renders
the flipped flag, installs the WS-B-pinned binary, and registers on the new token;
(3) verify the census: exactly 1 connector, every `client_version >= 2026.10.2`.
Management-plane dark window = O1→O2 gap only; `app.soleur.ai` is unaffected (direct
A record, never traverses the tunnel).

**WS-D — Detection + guards.** (1) Extend `tunnel-connector-census.sh` with a
version-floor classifier (`conns[].client_version` field-wise numeric compare —
lexical compare lies: `2026.9.0` > `2026.10.2` as strings) and a
`ci/tunnel-connector-version` `action-required` filing arm in
`scheduled-inngest-health.yml`; (2) extend `terraform-target-parity.test.ts` to a
**census** over every pin token in `.github/` (glob scan, not the hardcoded
PIN_WORKFLOWS list) so all 10 sites + future ones are pinned equal to canonical;
(3) new `cloudflared-pin-staleness.test.sh` + `cloudflared.provenance.md` +
`rule-audit.yml` "Detect cloudflared pin staleness" poll — mirrors the
inngest-cli/zot freshness-owner convention; (4) new
`scripts/cloudflared-compliance-probe.sh` (offline pin-floor census, prints
`PINS_OK`) as the observability discoverability probe.

## Technical Considerations

### Attack Surface Enumeration (security fix)

Cloudflared clients that verify TLS against the compromised intermediates:

- **Every CI bridge run** — `cf-tunnel-ssh-bridge` / `cf-tunnel-registry-bridge`
  download sites enumerated by `grep -rn 'cloudflared-version' .github/`: 10 sites in
  9 workflows. All covered by WS-A + the WS-D census guard (guards against any site
  missed now or added later).
- **The prod connector on web-1** — covered by WS-C. No other prod host runs
  cloudflared: `web_tunnel_connector` gates it to one web host, and sibling
  cloud-init files (git-data, grok-dogfood, inngest, registry) were grepped — none
  install it.
- **Docker/k8s** — none in the repo or prod (grep census; advisory's image-pull
  instruction is not applicable).
- **Operator dev machines** — outside repo reach; ship-message action item
  (macOS floor is 2026.10.3).
- **Unchecked path**: a stray off-fleet connector holding the tunnel token — already
  detected by the existing multi_connector census verdict; WS-D's version floor adds
  a second tripwire. The WS-C credential kill (tunnel `-replace`/token rotation)
  invalidates web-1's copy of the token too.

### Version-compare pitfall

`2026.10.2` vs `2026.9.0`: field-wise numeric compare is REQUIRED — a lexical or
`sort` (non-`-V`) comparison orders `2026.10.2` below `2026.9.0` and both a floor
check and a rollback guard silently invert.

### Boot-path constraints

- `web_tunnel_connector` is evaluated at cloud-init render time only
  (`user_data` is create-time + ignored on web-1); the flip changes nothing on any
  running host until the next create.
- inngest's user_data is near the 32 KB cap — reason the connector stays on the
  web-host cloud-init (web-2), not moved into `cloud-init-inngest.yml`.
- `cloud-init-user-data-size.test.ts` budgets web user_data; the `.deb` block is
  ~10 lines and the removed apt-source write_file + `cf_apt_key` stage partially
  offset it — re-measure at work.

## Research Insights

- **Premise Validation:** all cited issues verified OPEN and live — #6482 (cx33
  unplaceable EU-wide), #6730 (no automated web-1 birth path; every route HALTs),
  #6964 (web-1 replace tracker — the LUKS/`cloudflare_record.app`/provisioner
  blockers, confirmed in ADR-148), #6466 (host-addressability — about web-2 re-join,
  not the single-connector migration), #10479 (flexible SSL — ingress is non-HTTPS,
  consistent), #10835 (drift: pending `hcloud_server.inngest` replace + stray
  `google_gws_recovery` destroy — unrelated to web-1; a full-root apply would sweep
  it in, so the migration uses `-replace`/`web-host-replace` scoping, never a bare
  apply), #10768 (same drift class). All cited file paths confirmed on origin/main.
  Collision precheck: `prs=none` for all cited issues; foreign proc rows are
  unrelated sibling pipelines' `test-all.sh` processes.
- **Property List (what the ask actually requires):**
  - P1: every CI-downloaded cloudflared ≥ 2026.10.2.
  - P2: every future provision installs a deterministic ≥ floor version.
  - P3: the live prod connector runs ≥ floor — or is rendered permanently inert.
  - P4: a live connector below the floor is detected automatically (no SSH, no
    dashboard).
  - P5: pin drift across workflow sites is detected (all sites, including literals).
  - P6: no HTTPS-origin breakage after upgrade (N/A — no TLS origins; asserted, not
    assumed).
- **Cut List (mechanisms removed per Phase 0.6b):**
  - Dedicated connector host (new host class) → property P3 is already bought by
    web-2 + the existing `web-host-replace` dispatch — CUT.
  - Connector on the inngest host → same property; needs a new cloud-init block
    inside a near-cap user_data and couples tunnel uptime to inngest's replace
    cadence — CUT (recorded as fallback if web-2 is unavailable).
  - New monitoring workflow for version checking → P4 is bought by extending the
    existing census monitor on the same endpoint — CUT.
  - Docker/k8s image redeploy → no dockerized cloudflared — CUT (not applicable).
  - apt exact-version pin (`cloudflared=2026.10.4`) → Cloudflare's repo rotates
    versions; a stale pin breaks future provisions — CUT in favor of `.deb`+sha256.
  - unattended-upgrades for ongoing freshness → no such mechanism on main; P4's
    floor alert covers detection — CUT (revisit if advisories recur).
  - In-place `apt upgrade` on web-1 → `hr-prod-host-config-change-immutable-redeploy`
    forbids it ("even a one-liner"); an exception is an ADR + rule-corpus change —
    CUT as the default; recorded as rejected alternative.
- **Measured this session:** 2026.10.4 is latest (2026-10-26); real sha256 of
  `cloudflared-linux-amd64` = `ae5e8add…d9e42`; `.deb` =
  `3d73cd9f085de5a947fce8a72d0acc34a6a18cb23f369549b1cd0efc51121e98` (re-verify at
  work). `hcloud_server.web` already has `ignore_changes = [user_data, ssh_keys,
  image, placement_group_id]` (server.tf:616). `web-host-replace` passes
  `-replace="hcloud_server.web[\"$WEB_HOST_KEY\"]"` explicitly (apply-web-platform-
  infra.yml:5398-ish) and refuses `web-1` at :5196. web-2 (10.0.1.11) is live in
  state, `cpx22` — orderable.
- **Learnings applied:** `2026-07-07-immutable-redeploy.md` (-replace pulls
  dependents; -replace destroys before create → verify stock first — the dispatch's
  `stock_preflight_gate` is mandatory); `2026-03-21-cloudflare-tunnel-server-
  provisioning.md`; `2026-09-28-this-repos-releases-are-immutable` (release
  integrity — recompute sha, never paste).

## Hypotheses (connectivity layers, L3→L7)

The change's riskiest window is the post-merge migration (connector re-registration
on a re-created tunnel/token). L3 checks precede any service-layer conclusion:

1. **L3 — Hetzner firewall, egress of web-2.** `hcloud_firewall.inngest`-style empty
   rule sets default to outbound-allow; web-2 carries `hcloud_firewall_attachment.web`
   (fleet deny-all-inbound). cloudflared needs outbound UDP/TCP 7844 (+443 fallback).
   Verification: `hcloud firewall describe <fw>` for web-2's attached firewall +
   confirm no host-level nftables egress gate on web hosts blocks 7844
   (`cron-egress-allowlist.txt` is container-scoped — verify at work). [unverified —
   to check at work]
2. **L3 — DNS/routing.** `deploy./ssh./registry.` records re-resolve to
   `<new-tunnel-id>.cfargotunnel.com` after the `-replace`; `dig deploy.soleur.ai`
   post-apply. [to verify post-migration]
3. **L7 — connector registration.** CF API `/connections` shows exactly 1 connector
   with ≥4 conns and `client_version >= 2026.10.2`; the 15-min census verdict returns
   to `ok`. [to verify post-migration]
4. **Service layer (deferred).** A connector that registered but cannot serve an
   ingress surfaces as route-specific failure — verify each of deploy./ssh./registry.
   after L3+L7 clear. [to verify post-migration]

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the failure
  modes are management-plane (deploy/ssh/registry tunnel routes dark or a CI bridge
  abort). `app.soleur.ai` is a direct CF-proxied A record and never traverses the
  tunnel. The deepest failure — migration partially done, tunnel dark — still
  leaves user traffic served.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new
  exposure vector; the tunnel token stays in TF state + user_data exactly as today.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the remediation's own blast radius is
  management-plane-only and loud (fail-closed gates, named alerts); the residual it
  removes (MITM of the management plane) is the user-facing risk, not the change.
- *Scope-out override:* `threshold: none, reason: the diff touches
  apps/web-platform/infra (a sensitive path) but its worst-case failure is a dark
  management tunnel and a fail-closed CI abort — no user data, workspace, or serving
  path is reachable by the diff.`

## Observability

```yaml
liveness_signal:
  what:            "Tunnel connector census verdict (sole live connector present) + NEW version-floor verdict (every live conn client_version >= 2026.10.2)"
  cadence:         "every 15 min (scheduled-inngest-health.yml census step)"
  alert_target:    "GitHub issue labelled ci/tunnel-connector-version (NEW) / ci/tunnel-connector-drift (existing) + action-required (harvested by operator-digest)"
  configured_in:   ".github/workflows/scheduled-inngest-health.yml (census + file steps) + scripts/tunnel-connector-census.sh (classifier)"
error_reporting:
  destination:     "workflow run log breadcrumbs (SOLEUR_ORIGIN_HOST_CHURN …) + filed issues"
  fail_loud:       "action-required issue filed per firing verdict; census_unavailable / version_unreadable are soft (breadcrumb only), never a page"
failure_modes:
  - mode:          "live connector runs cloudflared < floor (post-migration regression, or a stray/off-fleet connector at an old pin)"
    detection:     "version-floor classifier reads conns[].client_version on the same /connections poll — layer: the existing scheduled census monitor (L: scheduled workflow)"
    alert_route:   "ci/tunnel-connector-version action-required issue"
  - mode:          "pin drift between the 10 workflow sites (partial bump, or a new site added at a stale version)"
    detection:     "extended terraform-target-parity.test.ts census (per-PR gate) + cloudflared-pin-staleness poll in rule-audit.yml (PR-cadence-independent) — layers: per-PR CI gate + scheduled poll"
    alert_route:   "CI failure / filed drift issue"
  - mode:          "post-migration tunnel dark (connector failed to register on the new token)"
    detection:     "existing zero_connectors census verdict + the O3 verification probe in the follow-through sequence"
    alert_route:   "ci/tunnel-connector-drift action-required issue"
  - mode:          "sha256 mismatch on a bridge or provision download"
    detection:     "sha256sum -c fails closed — bridge aborts before any prod contact; cloud-init aborts at cloudflared_checksum stage"
    alert_route:   "CI job failure / named boot fatal (Sentry via soleur-boot-emit)"
logs:
  where:           "workflow run logs (SOLEUR_ORIGIN_HOST_CHURN breadcrumbs); web-2 journald via Vector → Better Stack Logs source 2457081"
  retention:       "per Better Stack source retention; GH run logs 90d"
discoverability_test:
  command:         bash scripts/cloudflared-compliance-probe.sh
  expected_output: "PINS_OK"
```

## Encryption Posture

```yaml
at_rest:
  - store:            cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token (TF state)
    mechanism:        provider-managed: Cloudflare-issued credential; stored in the R2 Terraform state backend (existing, unchanged by this plan)
    evidence:         apps/web-platform/infra/tunnel.tf output tunnel_token; backend per hr-every-new-terraform-root
    defends_against:  nothing new — same at-rest handling as today
    does_not_defend:  a reader of tfstate holds a live tunnel credential (pre-existing; WS-C rotation is the mitigation event)
    disclosed_as:     not-publicly-claimed
    live_verification: available — token liveness is observable via /connections registration
in_transit:
  - connection:        web-2 cloudflared -> Cloudflare edge (tunnel registration + data)
    enforced_at:       apps/web-platform/infra/cloud-init.yml cloudflared service install + the upstream binary
    tls:               QUIC/TLS 1.3 (cloudflared-managed)
    cert_verification: on — this upgrade is precisely what removes the compromised eMudhra intermediates from the trusted set; noTLSVerify is NOT used anywhere (advisory instruction honored)
    does_not_defend:   trust-store staleness in any OTHER vendored client (out of scope; the staleness poll is the detection half)
    disclosed_as:      not-publicly-claimed
# no exception block: no plaintext-exception, no cert_verification:off
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf` — `web_tunnel_connector` flag: `each.key ==
  "web-1"` → `each.key == "web-2"` (locals in the web host template args; produces no
  plan diff — `user_data` is `ignore_changes`d on `hcloud_server.web`).
- `apps/web-platform/infra/cloud-init.yml` — pinned `.deb` install (+ remove the dead
  Cloudflare apt source/`cf_apt_key` stage if no other consumer).
- `apps/web-platform/infra/tunnel.tf` — comment-only refresh if the connector-host
  prose names web-1.
- No new Terraform root, no new providers, no new sensitive variables. The
  `tunnel_token` template arg to inngest is NOT needed (connector stays on the
  web-host template).

### Apply path

**(b) `terraform apply -replace` + dispatch** — the running-host path. Sequence
(post-merge, per-command operator go-ahead each step — `hr-menu-option-ack`):

```text
# O1 — kill the credential (OPERATOR_APPLIED_EXCLUSIONS local apply, ADR-096):
cd apps/web-platform/infra && doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan  -replace="cloudflare_zero_trust_tunnel_cloudflared.web" -out=tfplan
cd apps/web-platform/infra && doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply tfplan
# O2 — re-born the connector host on the flipped flag (reviewer-gated dispatch):
gh workflow run apply-web-platform-infra.yml -f apply_target=web-host-replace \
  -f web_host_key=web-2 -f confirm=REPLACE-web-2 -f reason="cloudflared eMudhra migration" \
  -f image_tag=<PINNED>
# O3 — verify (auto-executed probe, no SSH):
curl -s -H "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel/<new-id>/connections" \
  | jq -r '[.result[].conns[].client_version] | unique'
```

Alternative for O1: dashboard "Rotate token" or `PATCH tunnel_secret` + `DELETE
/cfd_tunnel/<id>/connections` — preserves the tunnel ID (no CNAME churn); default is
the `-replace` because it is IaC-auditable and every consumer resolves the tunnel by
name or `terraform state`, not by literal ID.

Expected downtime/blast radius: management tunnel dark for the O1→O2 gap (~the
web-host-replace job duration, ≤40 min budget); `app.soleur.ai` unaffected; web-2's
watchdog/dispatch-clock role pauses for its replace (~5 min boot). Drift note: a
bare full-root apply is avoided throughout — pending unrelated drift (#10835:
inngest replace + `google_gws_recovery` destroy) must not ride along; both steps are
explicitly scoped (`-replace` args; the dispatch's own target set).

### Host fan-out

No `terraform_data` SSH provisioner changes; the web-1-pinned provisioners are
untouched (the connector flag is cloud-init create-time only). No fleet sibling is
re-imaged except web-2 via its dedicated dispatch.

### Distinctness / drift safeguards

- `hcloud_server.web` `ignore_changes=[user_data,…]` already absorbs every
  user_data-affecting edit for BOTH web keys — the flag flip is inert until the
  explicit `-replace` in O2.
- `stock_preflight_gate` in the replace job aborts if cpx22 is unplaceable at apply
  time (the #6482 trap; probe first at dispatch time — cheap:
  `GET /v1/datacenters` `.server_types.available`).
- TF state holds the new tunnel token (same sensitivity class as today).

### Vendor-tier reality check

None — Hetzner/Cloudflare tiers unchanged; no new vendor resources.

## Architecture Decision (ADR/C4)

### ADR

- **New ADR (provisional next ordinal — re-verify at ship):** "Tunnel connector
  placement lives on a replaceable host, not the LUKS-pinned origin." Decision: the
  connector role moves permanently off web-1 to web-2 (the cattle standby);
  `web_tunnel_connector` selects it; a credential kill (tunnel `-replace` or token
  rotation) is the sanctioned way to retire a live connector without touching the
  host. Amends ADR-114's connector-placement assumption (I1's runtime invariant is
  unchanged: still exactly one connector; what changes is WHICH host). Author via
  `soleur:architecture`.

### C4 views

- `model.c4` `tunnel` container (:325-327): description says "ONE connector live in
  prod: web-1" and names the `web_tunnel_connector` gate → update to web-2 +
  credential-kill mechanism. `hetzner -> tunnel` edge (:730): same update
  ("ONE web host runs a cloudflared connector in prod (web-1)" → web-2).
- `views.c4`/`spec.c4`: check the tunnel element is included in existing views —
  placement changes no view membership; verify render tests stay green
  (`c4-code-syntax.test.ts`, `c4-render.test.ts`).
- Actors/systems enumerated: no NEW external actor/system is introduced (Cloudflare
  and Hetzner are already modeled; the connector moves between two already-modeled
  hosts). No `view include` additions expected — confirm during work.

### Sequencing

ADR written in this PR describing the target state; the migration completes with the
authorized post-merge sequence (status note acceptable while pending).

## Guard Contract

### Guard 1 — cloudflared pin parity census (extends terraform-target-parity.test.ts)

**Property.** Every cloudflared version/sha256 token anywhere under `.github/`
equals the canonical pin (env and literal forms alike).

**Assembly.** The chokepoint is a glob census: every `CLOUDFLARED_VERSION:` /
`CLOUDFLARED_SHA256:` env pair AND every `cloudflared-version:` /
`cloudflared-sha256:` literal in `.github/workflows/*.yml` +
`.github/actions/*/action.yml`, discovered by scan — NOT the current hardcoded
4-file `PIN_WORKFLOWS` list (the 5 literal sites prove that list is a snapshot, not
an assembly). Canonical = `apply-web-platform-infra.yml`'s env pin.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Bump only `reusable-release.yml`'s literal pin (env pins untouched) | RED |
| 2 | Bump only `apply-web-platform-infra.yml`'s ENV pin | RED (every literal site diverges) |
| 3 | Add an 11th workflow carrying a stale literal pin | RED (a file the hardcoded list never named is caught by the census) |
| 4 | Make the scan match zero files (e.g. rename the token) | RED (0 sites censused is vacuous — the guard reports site count ≥ 10) |
| 5 | Move one site from literal to `${{ env.CLOUDFLARED_VERSION }}` reference while its env pin stays canonical | PASS (env-reference sites resolve through the canonical env pin) |

### Guard 2 — cloudflared pin staleness (test + rule-audit poll + provenance sidecar)

**Property.** The canonical cloudflared pin stays within `MAX_AGE_DAYS` of the
provenance sidecar's capture AND within reach of upstream latest stable; a stale or
incoherent pin files a drift issue.

**Assembly.** Chokepoints: the canonical env pin in `apply-web-platform-infra.yml`
(all other sites are pinned equal by Guard 1), the sidecar
`apps/web-platform/infra/cloudflared.provenance.md`, and the `rule-audit.yml`
poll step. Offline gate exit contract: 0 fresh / 10 drift / 2 detector-failure —
matching the `zot-image-staleness`/`inngest-cli-staleness` convention.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Age the sidecar's capture date > MAX_AGE_DAYS | RED (rc=10) |
| 2 | Corrupt the canonical pin so it no longer parses as a version | RED (rc=2, detector failure — never read as fresh) |
| 3 | Poll reports a newer upstream stable than the pin | issue filed by the rule-audit step (detection half; the gate itself stays a committed-file check) |
| 4 | Anti-vacuity: neuter every assertion and keep the runner | RED via the assertion-count FLOOR (mirrors sibling gates) |
| 5 | Coherent pin at a known-good old release with a fresh sidecar | PASS (sanctioned rollback is legitimate — the floor lives in the version-floor guard, not here) |

### Guard 3 — tunnel connector version floor (census extension)

**Property.** Every live tunnel connection's `client_version` is >= the advisory
floor (2026.10.2); a below-floor live conn pages.

**Assembly.** `scripts/tunnel-connector-census.sh` gets a second classifier over the
SAME `/connections` body — `conns[].client_version`, field-wise numeric compare —
and `scheduled-inngest-health.yml` gets the matching `ci/tunnel-connector-version`
`action-required` filing arm (distinct label; `version_unreadable` is soft like
`census_unavailable`). The chokepoint is the existing 15-min poll — no new
scheduler.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Fixture: 1 connector, conn at `2026.3.0` | RED (`below_floor` verdict → issue arm) |
| 2 | Fixture: 1 connector, conns split `2026.10.4` + `2026.9.0` (one stale conn on a "current" connector) | RED (per-conn check, not per-connector — a second member after a compliant first) |
| 3 | Fixture: version field absent/malformed on a live conn | soft `version_unreadable` breadcrumb, NO page (mirror census_unavailable; must-PASS shape) |
| 4 | Drop the floor constant to `""` (guard cannot compare) | RED (detector must refuse to silently pass — assert floor parses) |
| 5 | Fixture: lexical-trap pair `2026.9.0` (above) + floor `2026.10.2` (below) | RED if compared lexically — must pass numerically |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "upgrade EVERY cloudflared instance to >= 2026.10.2 (>= 2026.10.3 for non-Homebrew macOS)" | WS-A (pin bump), WS-B (provision pin), WS-C (prod connector migration), AC1–AC3 | mapped |
| 2 | "Docker/k8s: pull and redeploy cloudflare/cloudflared:2026.10.3 image" | — | descoped — justification: no dockerized/k8s cloudflared exists in the repo or prod (grep census; all installs are apt/.deb or release-binary) |
| 3 | "Before upgrading: check HTTPS origins whose cert chains to an affected eMudhra cert" | WS-C ordering + Hypotheses L7 | mapped — all three ingress services are non-TLS (`http`/`ssh`/`tcp`); nothing chains to an affected cert. Asserted by reading tunnel.tf ingress, not assumed |
| 4 | "do NOT fix with noTLSVerify" | Encryption Posture `cert_verification: on` | mapped |
| 5 | "review and take necessary actions to make sure we are compliant" | WS-A–D + follow-through sequence | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| WS-A pin bump (10 sites + 2 action.yml comment refs) | "upgrade EVERY cloudflared instance to >= 2026.10.2" | asked |
| WS-B pinned .deb in cloud-init.yml | "upgrade EVERY cloudflared instance" | inferred — justification: an unpinned provision re-creates the advisory's stale-binary class on the next host birth; pinning is the compliance-preserving form |
| WS-C connector migration web-1→web-2 + credential kill | "upgrade EVERY cloudflared instance" | inferred — justification: web-1 cannot be patched in place (hard rule) nor replaced (refusal + LUKS + stock); moving the connector is the only rule-compliant way to satisfy "EVERY instance" |
| WS-D version floor in the census monitor | "make sure we are compliant" | inferred — justification: compliance without a detector silently rots back to a vulnerable connector |
| WS-D pin-parity census extension | "upgrade EVERY cloudflared instance" | inferred — justification: 5 of 10 pin sites are invisible to the current guard; a partial bump would claim compliance while shipping a vulnerable pin |
| WS-D staleness gate + poll + provenance | "make sure we are compliant" | inferred — justification: the repo's own freshness-owner convention for exactly this failure class (7-month-stale pin) |
| Compliance probe script | "make sure we are compliant" | inferred — justification: `hr-observability-as-plan-quality-gate` requires a no-SSH discoverability probe |
| ADR + C4 edits | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — the connector placement is an architectural decision |
| Follow-through issue for the authorized sequence | "take necessary actions" | inferred — justification: `hr-ship-message-no-operator-checklist` — multi-step prod mutation must be filed with auto commands |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform` (infra), `.github` (workflows+actions),
  `plugins/soleur` (test), `scripts/` (census + probe)
- Planned files: ~16 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — at the subsystem-root threshold but every piece is one
  security-remediation unit; splitting would separate the pin bumps from the
  migration plan they serve. The prod *execution* is already separated by being a
  post-merge authorized sequence.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. (Legal: the
advisory is a vendor security remediation, not a legal/compliance-artifact change;
GDPR gate skipped — no regulated-data surface, no new artifact distribution
surface.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — Every `CLOUDFLARED_VERSION`/`cloudflared-version` token under `.github/`
  reads `2026.10.4` and every `CLOUDFLARED_SHA256`/`cloudflared-sha256` reads the
  sha256 of the real `cloudflared-linux-amd64` 2026.10.4 asset, **recomputed at work
  time** via `curl` + `sha256sum` (value pasted into the PR body as evidence —
  `ae5e8add7884b0531d66bbca4570d1de491ff6da51e4ebe7eb160cdf241d9e42` measured this
  session). Both `action.yml` comment refs updated.
- [ ] AC2 — `cloud-init.yml` installs cloudflared via pinned `.deb` +
  `sha256sum -c` + `soleur-boot-emit cloudflared_checksum fatal` fail-closed arm;
  `cloudflared service install` + `soleur-wait-ready … cloudflared_ready || exit 1`
  preserved under `web_tunnel_connector`; `terraform plan` shows NO diff for
  `hcloud_server.web[*]` (both keys, ignore_changes).
- [ ] AC3 — `web_tunnel_connector` selects `web-2`; all tests asserting the
  web-1-connector assumption updated (scheduled-inngest-health remediation prose,
  census fixtures, lb-weight/nic-wait/cloud-init suites as needed).
- [ ] AC4 — Census classifier emits a version-floor verdict (field-wise numeric
  compare) + `scheduled-inngest-health.yml` files `ci/tunnel-connector-version`
  `action-required` on `below_floor`; fixture tests cover the mutation matrix.
- [ ] AC5 — `terraform-target-parity.test.ts` censuses every pin token under
  `.github/` by scan (env + literal forms); a divergent pin at any site is RED,
  including a newly added site.
- [ ] AC6 — `cloudflared-pin-staleness.test.sh` (0/10/2 exit contract + anti-vacuity
  floor) + `cloudflared.provenance.md` + `rule-audit.yml` poll step land.
- [ ] AC7 — `scripts/cloudflared-compliance-probe.sh` prints `PINS_OK` when every
  pin site is ≥ the 2026.10.2 floor.
- [ ] AC8 — ADR (connector placement) + `model.c4`/`views.c4` edits land in this PR.
- [ ] AC9 — No `noTLSVerify`, no `ssh `/human-run step prescribed as primary
  remediation, no web-1 mutation of any kind in the plan.

### Post-merge (operator-authorized)

- [ ] AC10 — The post-merge authorized sequence (O1 credential kill, O2
  `web-host-replace` web-2, O3 census verification, O4 operator-dev-machines note)
  is written as a follow-through issue (or ship-message block) with `auto_command`
  where automatable — per `hr-ship-message-no-operator-checklist`.
- [ ] AC11 — Post-migration steady state verified: CF API `/connections` shows
  exactly 1 connector and every conn's `client_version >= 2026.10.2`; the 15-min
  census verdict returns to `ok`.

## Test Scenarios

- Given a connections fixture with `client_version` `2026.3.0`, when the floor
  classifier runs, then `below_floor` (unit — `tunnel-connector-census.test.sh`).
- Given a fixture mixing `2026.9.0` and floor `2026.10.2`, when compared, then the
  numeric (not lexical) ordering decides (unit).
- Given a fixture with malformed/absent `client_version`, then
  `version_unreadable` breadcrumb and no page (unit).
- Given a workflow file edited so only its literal pin diverges, when the parity
  census runs, then RED naming that file (unit — terraform-target-parity.test.ts).
- Given the staleness sidecar aged > MAX_AGE_DAYS, when the gate runs, then rc=10
  (unit — cloudflared-pin-staleness.test.sh).
- Given a sha256 that does not match the real asset, when the bridge or cloud-init
  verify runs, then fail-closed abort (unit/integration — existing sha-verify
  shapes in the composite actions + boot emit).
- **API verify (post-merge, O3):** `curl` the `/connections` endpoint →
  `[.result[].conns[].client_version] | unique` ⊂ ≥ floor and exactly 1 connector —
  consumed by soleur:qa / the follow-through issue.

## Success Metrics

- CF API `/connections`: exactly 1 live connector, all conns `client_version >=
  2026.10.2` (post-migration steady state — also the new alert's quiet state).
- `bash scripts/cloudflared-compliance-probe.sh` → `PINS_OK` on main.
- Next rule-audit poll: no cloudflared drift issue (or a filed one caught the next
  upstream release, proving detection).

## Dependencies & Risks

- **Dispatch ordering is load-bearing:** the credential kill MUST precede the web-2
  replace, else the fresh connector registers on the old token and dies with it
  (two replaces for nothing). Documented in the follow-through sequence.
- **cpx22 stock at dispatch time** — `stock_preflight_gate` is mandatory; if it
  misses, repin per #6482's remedy before re-dispatching.
- **Drift contamination** — #10835 pending changes (inngest replace,
  `google_gws_recovery` destroy) must not ride a full-root apply; the sequence is
  `-replace`- and dispatch-scoped only.
- **Re-push risk** — release asset re-pushed between plan and work → sha256
  mismatch; the work phase recomputes per the action headers (fail-closed is the
  correct failure).
- **Cadence risk** — if a future advisory needs a faster floor, `MAX_AGE_DAYS` and
  the floor constant are both tunable.
- **Open-context blockers cited, not conflated:** #6482 (stock — moot here: web-2 is
  cpx22), #6730 (birth HALT — moot: `web-host-replace` is the sanctioned path),
  #6466 (re-pooling — NOT required; single connector moves whole), #6964 (web-1
  replace — remains the long-term path, unchanged), #6710 (fail-closed gate
  question — unchanged), #10479 (flexible SSL — separate surface).

## References & Research

- Advisory: Cloudflare blog "8 eMudhra certificates are compromised" (2026-10-20);
  eMudhra compromise tracker; CF changelog posts 2026-10-22/23.
- Releases: `github.com/cloudflare/cloudflared` — 2026.10.2 (10-20), .3 (10-21),
  .4 (10-26; pinned here).
- Mechanism files: `.github/actions/cf-tunnel-{ssh,registry}-bridge/action.yml`
  (download+sha256 verify); `scripts/tunnel-connector-census.sh` + test;
  `apply-web-platform-infra.yml` `web_host_replace` job (:5114+, -replace arg,
  web-1 refusal :5196, stock gate); `server.tf:441` (`web_tunnel_connector`),
  :616 (`ignore_changes`); `cloud-init.yml` connector block + webhook .tar.gz
  precedent.
- ADRs: 114 (I1/I2), 145 (birth), 148 (replace + web-1 refusal), 096
  (OPERATOR_APPLIED_EXCLUSIONS), 068, 263 (guest LUKS).
- Related issues: #6482, #6730, #6964, #6466, #6969, #6425, #6931, #10835, #10479,
  #6604 (the env-pin replication that created today's gap).

## Open Code-Review Overlap

2 open scope-outs touch planned files:

- **#8593** (`review: #6793 probe gate window…`) names `scheduled-inngest-health.yml`
  at :975/:1063 — the `ci/inngest-dedicated-host` and `ci/inngest-no-live-scheduler`
  close-enumeration loops. **Acknowledge** — different functions in the same file;
  our edit touches the connector-census step (:1313+) and its remediation prose.
  Scope-out remains open.
- **#2197** (billing `SubscriptionStatus`) names `infra/server.tf` as a hypothetical
  hazard if someone adds `count = 2`. **Acknowledge** — our server.tf edit flips a
  template flag, not host count.
