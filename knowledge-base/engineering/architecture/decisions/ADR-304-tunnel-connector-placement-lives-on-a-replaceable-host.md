---
title: Tunnel connector placement lives on a replaceable host, not the LUKS-pinned origin
status: accepted
date: 2026-10-27
amends: [ADR-114]
supersedes: none
issue:
related: [6482, 6730, 6964, 6466]
related_adrs: [ADR-096, ADR-114, ADR-143]
---

# ADR-304: Tunnel connector placement lives on a replaceable host, not the LUKS-pinned origin

## Context

Cloudflare's 2026-10-20 advisory disclosed that eight eMudhra (emSign) intermediate
CA certificates use weak private keys; `cloudflared` before **2026.10.2** still trusts
them. Measured live state: the sole production tunnel connector ran **2026.3.0** on
web-1 (`soleur-web-platform`), ~7 months stale — precisely the failure class the
repo's freshness-owner gates exist for, with none covering cloudflared.

web-1 cannot carry the fix by any sanctioned path:

- **In-place package upgrade** — `hr-prod-host-config-change-immutable-redeploy`
  forbids any running-host edit, "even a one-liner."
- **Host replace** — `apply_target=web-host-replace` refuses web-1 by name: the LUKS
  `hcloud_volume_attachment` is pinned to it with `prevent_destroy`,
  `cloudflare_record.app` pins its IPv4, and 22 SSH provisioners are web-1-pinned
  (tracker #6964; guest-side LUKS unlock is #6931's residual).
- **Stock** — cx33 (web-1's type) is unorderable in all three EU DCs (#6482;
  re-probed 2026-10-27 via `GET /v1/server_types` `.locations[].available`), so even
  a sanctioned replace cannot create like-for-like.
- **Birth path** — every automated web-1 creation route HALTs (#6730).

Meanwhile the connector itself is a **placement decision, not a host property**:
`web_tunnel_connector` in `server.tf` selects the host at cloud-init render time,
and `hcloud_server.web`'s `ignore_changes=[user_data]` means the flag flip produces
no forced-replace diff on any running host.

## Decision

**The tunnel connector role lives on the cattle standby web-2, permanently — not on
web-1.** Concretely:

1. `web_tunnel_connector` flips `each.key == "web-1"` → `each.key == "web-2"`
   (create-time only; inert until web-2's next replace).
2. cloud-init installs cloudflared as a **pinned `.deb` + `sha256sum -c`** with a
   fail-closed `soleur-boot-emit cloudflared_checksum fatal` arm — replacing the
   unpinned `apt-get install cloudflared` from `pkg.cloudflare.com` that produced
   the stale 2026.3.0.
3. web-1's live connector is retired by **credential kill**: `terraform apply
   -replace="cloudflare_zero_trust_tunnel_cloudflared.web"` under the
   OPERATOR_APPLIED_EXCLUSIONS local-apply contract (ADR-096), or token rotation +
   `DELETE /connections` as fallback. This also repairs the `secret`-vs-state
   divergence carried since import (`ignore_changes` on `secret`, tunnel.tf).
4. Detection: the 15-min connector census gains a `client_version` floor verdict
   (`below_floor` pages via a `ci/tunnel-connector-version` action-required issue);
   a glob pin-parity census pins all `.github/` cloudflared pin sites equal.

ADR-114's I1 runtime reading is amended: "exactly one connector" was always a
construction-time gate (it never re-ran on booted hosts). What changes now is
**which host the gate selects** — a replaceable one. The origin-relative ingress
invariant (ADR-114 I2, #6594) is untouched: all three services target web-1's
private IPs, which web-2 routes over the shared 10.0.1.0/24.

## Consequences

- The connector can be re-imaged on demand: `web-host-replace` accepts web-2, and
  `stock_preflight_gate` keeps cpx22 orderability honest.
- A vulnerability class that required either a forbidden in-place edit or an
  impossible web-1 replace now resolves to a routine cattle-host replace.
- web-2 concentrates connector + warm-standby + watchdog roles; a web-2 replace
  drops the management tunnel briefly (the dispatch is itself the recovery path).
- web-1 carries a dead-but-present vulnerable binary until #6964 replaces it —
  inert by revoked credential; the census floor verdict is the tripwire.
- Management-plane dark window during migration is bounded to the credential-kill →
  replace-dispatch gap; `app.soleur.ai` never traverses the tunnel.

## Alternatives Considered

- **In-place `apt-get install --only-upgrade cloudflared` on web-1** — rejected: the
  hard rule exists because in-place prod edits caused #6122/#6453-class drift; a
  standing CVE exception re-opens that class permanently (CTO ruling 2026-10-27).
- **Connector on the inngest host** — rejected: no connector block exists in its
  cloud-init, its user_data is at the 32 KB cap, and it couples tunnel uptime to
  inngest's replace cadence.
- **Dedicated connector host** — rejected: no birth dispatch exists for a new host
  class (#6730); new host class + dispatch + monitoring inside a security
  remediation is scope violation.
- **Wait for web-1's #6964 replacement** — rejected: indefinite exposure of the
  management plane (deploy webhooks, CI SSH bridge, registry pushes) to MITM.

## Relationship to other ADRs

- **ADR-114** — amends the connector-placement assumption; I2's origin-relative
  ingress makes the move safe (correctness no longer depends on which replica
  answers).
- **ADR-096** — the OPERATOR_APPLIED_EXCLUSIONS contract carries the credential-kill
  apply; "no cloudflared on the registry host" unchanged.
- **ADR-143** — web-2's role expands from pure standby to standby + connector; the
  D1 sizing (cpx22, measured web-1 usage) still holds — cloudflared is ~50 MB RAM.
