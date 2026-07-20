---
adr: ADR-082
title: Fresh web-2 boot observability + supply-chain hardening contract
status: superseded-in-part
date: 2026-07-03
superseded_by: [ADR-128]
---

# ADR-082: Fresh web-2 boot observability + supply-chain hardening contract

> **Status: superseded-in-part by [ADR-128](./ADR-128-coherence-two-invariants.md) (2026-07-20, #6575).**
> This ADR's entire subject is **web-2**, which was retired 2026-07-17 (#6538/#6463). `var.web_hosts`
> is single-host; every "fresh web-2 boot" premise below is historical. What is superseded is the
> **web-2 scoping**, not the controls — three of the five items have a live disposition:
>
> **Remains IN FORCE.** *Item 3* (fresh-host post-container egress-enforcement probe) — shipped, baked,
> host-generic, and it executes at boot on **any** fresh web host. *Item 5* (web-host Vector log
> shipping + terminal-block boot-emit trap + `pull_failure` `host_id`) — the terminal-block trap is
> now web-1's **sole no-SSH boot page**, retained deliberately (ADR-128 §Consequences).
>
> **Remains IN FORCE but UNMET — owned by #6730.** *Item 4* (image digest pin + signature
> verification). The **running-host** half shipped (`ci-deploy.sh` cosign verify, WARN). The
> **fresh-host** half did **not**: nothing pins `var.image_name`, which still defaults to the mutable
> `ghcr.io/jikig-ai/soleur-web-platform:latest`, and the boot path performs **no** signature
> verification — `server.tf`'s own threat-model comment says so. **Do not record Item 4 as
> discharged.** It is the enforcement arm of ADR-128's *cross-commit skew* invariant, and #6730's
> digest-pinned birth path is what would meet it.
>
> **Dies with the retire.** *Item 1* (per-host uptime absence detector) — its subject host is gone and
> the #5933 per-host probe was already retired; the app.soleur.ai probe fully covers the single-host
> fleet. *Item 2* (A-record drain on boot failure) — there is no second origin to drain to; a
> round-robin/LB drain rides #6459, not this ADR. *Item 5's web-2-specific clauses* — see the two
> corrections below.
>
> **Two claims below are FALSIFIED by the retire and are corrected here rather than edited away:**
>
> 1. **`:52-53`** — *"the SOLE page for a dead web-2 warm standby"*. The alert
>    (`sentry_issue_alert.web_terminal_boot_fatal`) filters on `stage` and **never on host**, so it
>    was never web-2-specific. Post-retire it is the sole no-SSH boot page for **web-1**. The same
>    false framing was encoded in that resource's Terraform comment and is corrected there in the
>    same change. The alert itself is host-generic and survives unchanged — deleting it as "web-2
>    surface" would have removed live coverage for the only web host.
> 2. **`:45-46`** — Item 5's Vector log shipping described as *"Half-met at ship (web-2 only)"*. With
>    web-2 retired the only host that ever met it no longer exists, so post-retire Item 5's log-shipping
>    clause is **0%-met**: web-1 still ships `host_name=soleur-inngest-prd` and gets correct per-host
>    attribution only at its next recreate (#6616). "Half-met" now reads as more coverage than exists.
>
> Read the web-2 provisioning framing below as historical. For the coherence invariants that replaced
> Item 4's framing, and for the retention rule governing which verifiers survived the sweep, see
> ADR-128.

- **Status:** superseded-in-part (was: Adopting)
- **Date:** 2026-07-03
- **Deciders:** one-shot pipeline (plan + work), CPO threshold carried from ADR-080 (single-user-incident substrate)
- **Relates to:** #5933 (this contract); #5921 / ADR-080 (fresh-host bake-and-extract boot path — the surface these controls observe); **#5274 Phase 3.D** (the operator web-2 provisioning cutover these are prerequisites of — `dns.tf:4`); #5887 (a `moved`-block CI fix that RED-blocked the auto-apply; **now CLOSED/merged** — Item 1's original deferral reason, see amendment below); #5046 (container egress firewall — the enforcement Item 3 proves); ADR-068 (multi-host web cluster); **ADR-100 / #6396** (Item 5 — the inngest cutover defaulted `web_colocate_inngest=false`, dropping the co-located web-host Vector path; #6396 re-adds it independently + the terminal-block trap + pull-failure host_id)

## Context

The fresh Hetzner **web-2** boot surface (ADR-080 / #5921 bake-and-extract cloud-init path)
is a **blind execution surface**: no SSH, CI cannot reach the host. #5921 shipped the
SSH-free *error-path* Sentry trap (`soleur-host-bootstrap.sh` `emit_fail` →
`{stage, failed_file, host_id}`) and the fail-closed `/run/soleur-hostscripts.ok` sentinel
(the terminal `docker run` block poweroffs if it is absent). But four observability /
hardening gaps only bite once web-2 is actually provisioned behind the #5887 cutover, and
they are hard prerequisites of that cutover. #5921 itself is inert on running web-1 and
provisions nothing, so it does not require these to merge.

## Decision

A four-control **fresh-host observability + supply-chain contract** for web-2. Each control
targets a distinct blind-surface failure mode:

1. **Per-host uptime absence detector** (PRIMARY).
2. **A-record drain on boot failure.**
3. **Fresh-host post-container egress-enforcement probe** — **SHIPPED in this PR**.
4. **Image digest pin + signature verification.**
5. **Layer-3 web-host log shipping + terminal-block no-SSH cause breadcrumb + pull-failure host attribution** — **added #6396** (see Item 5 below).

### Item 5 — web-host Vector log shipping + terminal-block boot-emit trap + pull_failure host_id (#6396)

Three additions closing the observability blind spots left after the ADR-100 inngest cutover:

- **Vector on every web host, ungated from `web_colocate_inngest`.** ADR-100 moved scheduling to
  a dedicated host and defaulted `web_colocate_inngest = false`, which silently dropped the
  co-located web-host Vector install — so a fresh `soleur-web-platform` / `soleur-web-2` host
  ships **no** journald/host_metrics to Better Stack. The shipper is now decoupled: baked into the
  ungated `soleur-host-bootstrap.sh` path (authors `/usr/local/bin/soleur-vector-install`), run
  **fail-open** and **wall-clock-bounded** at the END of the cloud-init runcmd chain (AFTER the app
  binds `:80`/`:3000`) so *observing* the boot can never *break* serving. The shared `vector.toml`
  carries a `@@HOST_NAME@@` sentinel resolved per-host from the TF-injected server name (the sole
  discriminator in the ONE shared Logs source 2457081); the web unit carries
  `EnvironmentFile=/etc/default/webhook-deploy` (its DOPPLER_TOKEN source — the inngest-only
  `/etc/default/inngest-server` is absent on a non-colocated host). No new secret:
  `BETTERSTACK_LOGS_TOKEN` already lives in `soleur/prd`. **Half-met at ship (web-2 only)** — web-1
  is never force-`-replace`d; it ships logs after its next ADR-068 blue-green recreate (tracked).
- **Terminal serving-block boot-emit trap.** The cloud-init terminal `docker run` block had no
  named `soleur-boot-emit` fatal trap: a `doppler secrets download` `exit 1` or a `docker run`
  `set -e` abort reached only the SSH-only `cloud-init-output.log`. A composite EXIT trap (armed
  right after `set -e`, mutable `stage` ∈ {`terminal_preamble`, `hostscripts_incomplete`,
  `doppler_download`, `docker_run`}, disarmed before the self-emitting egress probe) now makes
  these boot failures no-SSH observable and PAGES via a NEW Sentry issue-alert — the SOLE page for
  a dead web-2 warm standby (no standing uptime coverage; the #5933 per-host probe was retired).
- **`host_id` on `ci-deploy.sh`'s `pull_failure_event`.** A deploy-path `image pull failed` now
  carries `tags.host_id`, so the failing host is identifiable from Sentry alone (PR #6395 had to
  cross-reference the release aggregate JSON to attribute it to web-2).

### Item 3 — post-container egress-enforcement probe (SHIPPED)

**Decision:** a baked `cron-egress-enforce-probe.sh` runs the positive+negative in-container
egress probe at boot, **after** the app container starts (invoked from `cloud-init.yml`'s
terminal block), and **fail-closed poweroffs** a host whose container egress is not provably
enforcing.

**Why this shape:**
- The web-1 SSH provisioner (`cron-egress-postapply-assert.sh`) **skips** the container
  probes on a fresh host (no container yet) and defers proof to "the next apply after
  deploy". On the cloud-init-only web-2 path there is no SSH re-apply, so that proof never
  lands — a non-enforcing (inert) ruleset would serve silently. `nft -f` exits 0 on an inert
  ruleset; **only a real in-container negative probe proves enforcement** (#5046 threat).
- The app container starts AFTER `soleur-host-bootstrap.sh` writes the sentinel, so the probe
  **cannot** live in the bootstrap script — it is a separate post-`docker run` step.
- Fail-closed poweroff: an open container-egress path on a serving host (a live exfil vector)
  is worse than an absent host — the absence is what Item 1's per-host detector pages on.
- **Discriminating telemetry (blind-surface, `hr-observability-as-plan-quality-gate`):** the
  probe emits the #5921 `emit_fail` envelope PLUS a `probe_result` tag ∈
  `{negative_fail (under-enforcing = the exfil hole), positive_fail (over-blocking),
  structure_fail (chain/unit missing), container_absent}` — so the root-cause hypothesis is
  decided in ONE SSH-free event.

**Inert on web-1:** the baked script ships to web-1 on the next `apps/web-platform/**` deploy
but only executes at boot; web-1 is not rebooting, and its egress enforcement is still proven
by the existing SSH-provisioner path.

### Item 1 — per-host absence detector (design; web-1 SHIPPED #5933, web-2 rides #5274)

**Decision:** a per-host CF-**proxied** probe hostname
(`web-<n>.app.soleur.ai` → the specific origin IP, preserving the CF-only origin firewall in
`firewall.tf`) + a `betteruptime_monitor` `for_each` over a `monitored`-gated subset of
`var.web_hosts` (`monitored = optional(bool, true)` on the object type;
`web-2 = { … monitored = false }` until cutover). **The `monitored` filter gates BOTH the
monitor AND its probe `cloudflare_record` (`dns.tf`)** — an ungated `for_each = var.web_hosts`
references `hcloud_server.web["web-2"]` (excluded from the auto-apply `-target` set), which
`-target` would transitively drag into a routine apply and provision web-2 out-of-window.
Rejected alternatives: raw-origin-IP probes (origin firewall gates 443 to CF IPs only),
grey-cloud/unproxied per-host DNS (exposes origins; Sentry/BetterStack publish no stable
probe-source ranges to allowlist).

**Amendment (2026-07-03, #5933): deferral trigger CLEARED — web-1 shipped now.** The original
"blocked on #5887" reason was that the main-root auto-apply (`apply-web-platform-infra.yml`) was
RED (`moved` resources excluded by the `-target` allow-list). **#5887 is now fixed & merged and
the apply is green**, so the `monitored`-gated design ships web-1's probe record + monitor on the
normal per-PR merge-apply (with the two resources added to the `-target` allow-list). web-2's
record + monitor stay out of state (`monitored=false`) until the #5274 Phase 3.D cutover provisions
web-2 and flips the flag — pointing a monitor at a not-yet-created hostname pages immediately
(522 / NXDOMAIN). **Note:** when Item 2's CF Load Balancer origin health-checks land at #5274 they
may duplicate this per-host monitor — retire one at that time.

### Item 2 — A-record drain (design; DEFERRED to the cutover DNS rewire)

**Decision (to land with the cutover):** `cloudflare_record.app` is currently a singleton
(web-1 only); the `for_each` round-robin does not exist yet (a destroy+recreate of the LIVE
app record, deferred to the operator cutover — `dns.tf:4-12`). Recommended drain mechanism:
a **CF Load Balancer** with per-origin health monitors (auto-drain of a failed origin), with
`monitored`-gated `for_each` round-robin membership as the interim (a failed host is pulled
by flipping its flag). There is nothing to drain until the round-robin exists, so this rides
the cutover DNS rewire.

### Item 4 — image signing + verify (design; split: running-host SHIPPED, fresh-host rides #5274)

**Decision:** cosign-**keyless-sign** the released image digest (`reusable-release.yml`,
OCI-attached Rekor bundle) + cosign-**verify at every consumption point** before the image
runs. The `host_scripts_content_hash` (`server.tf`) is a staleness/coherence control, NOT a
supply-chain control — the same unpinned image runs the app container with full RCE, so
signing + verify is the honest supply-chain defense.

**Amendment (2026-07-04, #5933 PR 2/2): dual-path verify + scope split.** The `var.image_name`
digest-pin only protects a FRESH boot (`ignore_changes=[user_data]`, `server.tf` — the cloud-init
template change never reaches a *running* host). The running host (web-1, serving users today)
pulls its image by semver tag via `ci-deploy.sh` and was unverified. So verify is extended to a
**second consumption point** — the running-host deploy path (`ci-deploy.sh`) — as an amendment,
NOT a new ADR (it is one supply-chain decision: verify the image wherever it runs). This PR ships
the **running-host** half: signing in the release pipeline + `ci-deploy.sh` verify (SHA-pinned
cosign container, `--offline` bundle so no sigstore egress is needed past the #5046 firewall;
identity pinned to `reusable-release.yml@(refs/heads/main|refs/tags/v*)`; runs the VERIFIED
DIGEST not the tag → no TOCTOU). Verify lands **WARN** (emits a discriminating `verify_result`
Sentry event, never blocks); the **WARN→ENFORCE flip is a soak-gated fast-follow** after one
signed release deploys clean. The **fresh-host** half (`cloud-init.yml` verify + `var.image_digest`
pin, threaded via Doppler `TF_VAR_image_digest`, not committed tfvars) **rides the #5274 cutover**
where web-2 actually boots and it is end-to-end testable.

Precedents: `knowledge-base/project/learnings/2026-03-19-docker-base-image-digest-pinning.md`,
`2026-06-10-release-digest-plan-review-catches.md`.

**Amendment (2026-07-04, #6005): private-GHCR credential model + offline-verify mechanism → ADR-087.**
Live validation found the shipped WARN verify **cannot pass on the real host**: the app +
inngest-bootstrap GHCR packages flipped **PRIVATE**, so (a) the anonymous host `docker pull` AND
(b) the cosign container's OCI-attached `.sig` fetch both fail `UNAUTHORIZED`; and (c) v3.1.1
`cosign verify` has no `--new-bundle-format`, its `--offline` is deprecated, and even `--offline`
still needs a registry round-trip (bare `--offline` without a pinned root reaches TUF → firewall-
blocked → never passes). The full verify-invocation design (a `--network host` ephemeral verifier
that keeps the container egress allowlist UNwidened; a pinned committed `trusted_root.json` mounted
`:ro`, delivered out-of-image via the baked HOST-image host-scripts set + a running-host SSH
provisioner, NEVER baked into the DEPLOY image) is recorded in **ADR-087** (this amendment owns the
PULL + verify credential; ADR-087 owns the invocation shape). The credential is a scoped, read-only,
machine-account `read:packages` **PAT** over both packages, recorded as a **deliberate, narrow
exception to `hr-github-app-auth-not-pat`** (AP-016): security-sentinel affirmed it as the security-
*superior* choice — the App-installation path would force the org-wide-**write** App private key onto
the host at token-mint time (~2 orders of magnitude larger blast radius than a single-package
**read** token). Counter-cost recorded: a ≤1yr PAT is a worse secret-at-rest than a 1h installation
token and expires silently → a proactive expiry alarm + rotation follow-through are required
(tracked with the WARN→ENFORCE flip). The ENFORCE flip stays OUT OF SCOPE, now additionally gated on
the CI trusted-root staleness gate (`cosign-trusted-root-staleness.test.sh`).

## Alternatives Considered

- **Item 4: verify by tag (`cosign verify …:v1.2.3` / run `:$TAG`).** Rejected: a tag is mutable
  and can be re-pointed between verify and run (TOCTOU). Chosen: resolve the pulled tag to its
  immutable `@sha256` digest (`docker inspect RepoDigests`), verify that, and RUN that digest.
- **Item 4: thread the release digest into TF via a committed `image-digest.auto.tfvars`.**
  Rejected: the release workflow writing back to `main` risks a commit-loop + an apply-race
  against the `apps/web-platform/infra/**` auto-apply. Chosen: Doppler `TF_VAR_image_digest`
  (a non-secret public digest, no git write). Rides #5274 with the fresh-host pin.
- **Item 4: loose cosign identity `reusable-release.yml@refs/(heads|tags)/.+`.** Rejected: it
  accepts a signature minted by the same workflow on ANY intra-repo branch/tag push
  (attacker-branch RCE that ENFORCE would trust). Chosen: `@(refs/heads/main|refs/tags/v[0-9].+)`.
- **Ship all four items in one PR.** Rejected: Items 1 & 2 are blocked on #5887 / the deferred
  DNS rewire, and Item 4 is a cross-cutting supply-chain change. Item 3 is the only fully
  unblocked, inert-on-web-1, highest-severity deliverable.
- **Put the egress probe in `soleur-host-bootstrap.sh`.** Rejected: the app container starts
  after the bootstrap sentinel is written, so the container does not exist when the bootstrap
  runs — the probe must be a post-`docker run` cloud-init step.
- **Reuse `cron-egress-postapply-assert.sh` verbatim on the fresh path.** Rejected: it SKIPS
  the container probes when the container is absent; on the fresh path we run precisely because
  the container is up, so the skip branch would defeat the control.
- **Item 5: inline the Vector-install + emit bodies directly in `cloud-init.yml` runcmd.**
  Rejected: comments + bodies count against the 32,768-byte user_data cap (already ~29.6 KB,
  ~0.4 KB headroom). Baked into `soleur-host-bootstrap.sh` (0 user_data), per the bake-and-extract
  precedent (learning `2026-07-06-cloud-init-user-data-cap-bake-bodies`).
- **Item 5: provision a new `doppler_secret` / `TF_VAR` for the web-host Better Stack token.**
  Rejected: `BETTERSTACK_LOGS_TOKEN` already lives in `soleur/prd`; a new var re-introduces the
  no-default-var-on-auto-apply footgun for zero benefit.
- **Item 5: force a web-1 `-replace` to apply Vector immediately.** Rejected: powers off the sole
  live origin. web-1 rides the immutable-redeploy channel; it ships logs at its next ADR-068
  blue-green recreate.
- **Item 5: derive `host_name` from runtime `$(hostname)`.** Rejected: cloud-init sets no explicit
  `hostname:`/`fqdn:` and relies on Hetzner seeding it — a generic/duplicate value would collapse
  web-1 and web-2 into one host_name in the shared source. Chosen: the TF-injected per-host server
  name (`SOLEUR_HOST_NAME`), guaranteed distinct.

## Consequences

- A fresh web-2 that boots with a non-enforcing container egress firewall powers off (fail-safe)
  and emits a discriminating Sentry event, instead of serving an exfil path.
- Items 1, 2, 4 remain tracked (follow-up issues) and sequenced against #5887; #5933 closes
  when all four are merged and the web-2 cutover is verified.
- **Item 5 (#6396):** every web host ships journald + host_metrics to Better Stack, and the
  terminal serving-block + deploy-path pull failures are no-SSH observable/pageable. Half-met at
  ship (web-2 only); web-1 ships logs after its next ADR-068 blue-green recreate (tracked). The
  fail-open Vector install can never wedge the boot; the terminal-block trap PAGES a dead web-2
  standby that otherwise has no standing uptime coverage (the #5933 per-host probe was retired).
- **Item 5 amendment (2026-07-15, #6425) — host attribution extends to the READ surfaces.**
  #6396 gave per-host attribution to *pushed* signals (journald `host_name`, the boot-fatal Sentry
  emits, `pull_failure` `host_id`). The **pull** surfaces had none: `/hooks/deploy-status` and
  `/hooks/inngest-liveness` answer over the Cloudflare Tunnel, which selects a connector per edge
  colo, so a read could be served by a host the caller never meant — and the response did not say
  which. Both now emit `host_id` (the hcloud id terraform knows), on the **success × failure**
  axis: the failure bodies are the ones the watchdog reads
  (`hooks.json.tmpl` `include-command-output-in-response-on-error`), and the 2026-07-15 incident
  was a plain-text `FATAL __FETCH_FAILED__` — so `host_id` on the JSON success emits alone would
  have been absent from the very incident that motivated it. This closes the ADR's attribution
  story: **pushed signals say who sent them; pulled signals now say who answered.**
  > **The stale `monitored = false` note above (`:91`, `:104`) is about the per-host uptime
  > MONITOR, not the connector.** Do not read "web-2 unmonitored until cutover" as "web-2 is
  > inert": until #6425 it ran a live connector and answered management-plane reads ~50% of the
  > time while carrying no monitor at all — unmonitored **and** load-bearing. Since #6425 it runs
  > no connector (ADR-114 I1), which is what finally makes the `monitored=false` posture honest.

## C4 impact

Reviewed all three model files (`model.c4`, `views.c4`, `spec.c4`). **No C4 change for the
shipped item (Item 3):**
- **External human actors:** none added (a boot-time internal correctness control).
- **External systems / vendors:** none added — the Hetzner compute container and its GHCR
  image-pull relationship are already modeled (`model.c4:164-166`, `:240`, `:300`); the probe
  verifies the container→internet egress boundary, an internal property of that already-modeled
  container, not a new edge.
- **Containers / data stores:** none added.
- **Access relationships:** unchanged — the egress boundary is an internal control, not a C4
  relationship.

**Deferred C4 work:** Item 1 (per-host absence detector) WILL add an external
uptime-monitor actor (Sentry/BetterStack) + a per-host probe edge to the Hetzner compute
container — that `.c4` edit lands with Item 1's cutover PR, not here.

**Item 5 C4 change (#6396):** adds the `hetzner -> betterstack` container-view edge (web-host
Vector log shipping to the shared Logs source 2457081), mirroring the existing `inngest ->
betterstack` edge; and CORRECTS the stale `betterstack -> hetzner` edge that asserted the
#5933-retired per-host origin uptime probe. Both endpoints are already in the `containers` view
include, so no `views.c4` change is needed (LikeC4 auto-draws the edge). `model.likec4.json`
regenerated + committed (the `c4-model-freshness` orphan suite gates it).
