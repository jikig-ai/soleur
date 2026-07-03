# ADR-081: Fresh web-2 boot observability + supply-chain hardening contract

- **Status:** Adopting
- **Date:** 2026-07-03
- **Deciders:** one-shot pipeline (plan + work), CPO threshold carried from ADR-080 (single-user-incident substrate)
- **Relates to:** #5933 (this contract); #5921 / ADR-080 (fresh-host bake-and-extract boot path — the surface these controls observe); #5887 (the operator web-2 cutover these are prerequisites of); #5046 (container egress firewall — the enforcement Item 3 proves); ADR-068 (multi-host web cluster)

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

### Item 1 — per-host absence detector (design; DEFERRED, blocked on #5887)

**Decision (to land with the cutover):** a per-host CF-**proxied** probe hostname
(`web-<n>.app.soleur.ai` → the specific origin IP, preserving the CF-only origin firewall in
`firewall.tf`) + a `betteruptime_monitor` `for_each` over a `monitored`-gated subset of
`var.web_hosts` (add `monitored = optional(bool, true)` to the object type;
`web-2 = { … monitored = false }` until cutover). Rejected alternatives: raw-origin-IP probes
(origin firewall gates 443 to CF IPs only), grey-cloud/unproxied per-host DNS (exposes
origins; Sentry/BetterStack publish no stable probe-source ranges to allowlist).

**Why deferred:** the probe hostname is a main-root `cloudflare_record`, and the main-root
auto-apply (`apply-web-platform-infra.yml`) is currently RED (#5887 — `moved` resources
excluded by the `-target` allow-list). A monitor pointed at a not-yet-created hostname pages
immediately (522 / NXDOMAIN). Both ride the cutover apply, sequenced after #5887.

### Item 2 — A-record drain (design; DEFERRED to the cutover DNS rewire)

**Decision (to land with the cutover):** `cloudflare_record.app` is currently a singleton
(web-1 only); the `for_each` round-robin does not exist yet (a destroy+recreate of the LIVE
app record, deferred to the operator cutover — `dns.tf:4-12`). Recommended drain mechanism:
a **CF Load Balancer** with per-origin health monitors (auto-drain of a failed origin), with
`monitored`-gated `for_each` round-robin membership as the interim (a failed host is pulled
by flipping its flag). There is nothing to drain until the round-robin exists, so this rides
the cutover DNS rewire.

### Item 4 — image digest pin + signature (design; DEFERRED to its own PR)

**Decision (own PR):** pin `var.image_name` from `:latest` to an immutable `@sha256:<digest>`
(the `web-platform-release.yml` build emits the pushed digest → threads into a new
`var.image_digest`), + a cosign verify step in `cloud-init.yml` before `docker pull`/`run`.
The `host_scripts_content_hash` (`server.tf`) is a staleness/coherence control, NOT a
supply-chain control — it hashes content and the same unpinned image runs the app container
with full RCE, so digest-pin + signature is the honest supply-chain defense for both the app
layers and the baked host scripts. Precedents:
`knowledge-base/project/learnings/2026-03-19-docker-base-image-digest-pinning.md`,
`2026-06-10-release-digest-plan-review-catches.md`. Deferred to a focused, security-reviewed
PR — folding a release-pipeline + cosign change into the egress-probe PR would blur two
review surfaces.

## Alternatives Considered

- **Ship all four items in one PR.** Rejected: Items 1 & 2 are blocked on #5887 / the deferred
  DNS rewire, and Item 4 is a cross-cutting supply-chain change. Item 3 is the only fully
  unblocked, inert-on-web-1, highest-severity deliverable.
- **Put the egress probe in `soleur-host-bootstrap.sh`.** Rejected: the app container starts
  after the bootstrap sentinel is written, so the container does not exist when the bootstrap
  runs — the probe must be a post-`docker run` cloud-init step.
- **Reuse `cron-egress-postapply-assert.sh` verbatim on the fresh path.** Rejected: it SKIPS
  the container probes when the container is absent; on the fresh path we run precisely because
  the container is up, so the skip branch would defeat the control.

## Consequences

- A fresh web-2 that boots with a non-enforcing container egress firewall powers off (fail-safe)
  and emits a discriminating Sentry event, instead of serving an exfil path.
- Items 1, 2, 4 remain tracked (follow-up issues) and sequenced against #5887; #5933 closes
  when all four are merged and the web-2 cutover is verified.

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
