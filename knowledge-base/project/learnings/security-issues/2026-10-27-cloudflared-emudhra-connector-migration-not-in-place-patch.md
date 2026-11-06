---
title: "cloudflared eMudhra remediation: migrate the connector, never patch in place"
category: security-issues
date: 2026-10-27
---

# cloudflared eMudhra remediation: migrate the connector, never patch in place

Cloudflare's 2026-10-20 advisory (8 compromised eMudhra/emSign intermediates; floor
cloudflared 2026.10.2) found this fleet at 2026.3.0 on web-1 — the unpinned
`apt-get install cloudflared` from pkg.cloudflare.com was the mechanism that
produced a 7-month-stale binary.

The compliant fix was NOT an in-place `apt upgrade` (hr-prod-host-config-change-
immutable-redeploy forbids it, even a one-liner) and NOT a web-1 replace (LUKS
prevent_destroy + cx33 unplaceable EU-wide, #6482 + #6964). Instead:

1. `web_tunnel_connector` flag flipped web-1→web-2 (create-time only; `ignore_
   changes=[user_data]` makes the flip zero-diff on running hosts).
2. cloud-init now installs a pinned `.deb` + `sha256sum -c` + `soleur-boot-emit
   fatal` — deterministic, like the adjacent webhook block.
3. web-1's live connector is retired by credential kill (`terraform -replace` of
   `cloudflare_zero_trust_tunnel_cloudflared.web`), leaving the binary inert.
4. Detection added: `conns[].client_version` floor verdict in the 15-min census
   (FIELD-WISE numeric compare — `2026.9.0` > `2026.10.2` lexically), glob pin-
   parity census over all `.github/` sites (5 of 10 were literals invisible to the
   old hardcoded PIN_WORKFLOWS list), and a staleness poll + provenance sidecar.

Lesson: a security advisory on a host you cannot touch is remediated by moving
the role and killing its credential — the version-floor monitor is what keeps
"inert" from silently becoming "registered again."
