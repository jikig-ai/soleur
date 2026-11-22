# Safe-by-default DNS posture for the parked rundevoo.run zone (phase 1 of
# #12971; the product shape is deferred to #12972). The apex must not send
# email, so the zone declares that unambiguously rather than leaving the
# spoofing surface implicit.
#
# `name` values spell the provider's read-back form: FQDN at the apex
# ("@" would normalize to the FQDN — perpetual drift), the zone-relative
# label for subdomains — the provider strips the zone suffix on read, so
# `name = "_dmarc.rundevoo.run"` forces replacement forever (the 2026-11-20
# state-reconciliation plan measured exactly that).

# RFC 7505 null MX — declares the apex accepts no mail. `content = "."` is the
# literal null-MX target (verified against the committed 4.52.10 lockfile provider schema
# before authoring — provider docs drift, see
# knowledge-base/project/learnings/integration-issues/2026-04-10-context7-terraform-provider-version-mismatch.md).
resource "cloudflare_record" "null_mx" {
  zone_id  = cloudflare_zone.rundevoo_run.id
  name     = "rundevoo.run"
  content  = "."
  type     = "MX"
  priority = 0
  ttl      = 1
  proxied  = false
}

# The import blocks below adopt the records the first post-merge apply
# created before its state save died on S3 PutObject 403 (2026-11-20 — the
# job read prd_terraform's read-only pair because it never invoked the
# Tier-B loader). With the state object absent, a plan without them would
# propose duplicate CREATEs against live records; importing keeps live and
# state consistent without a protection gap. Same literal-coupling
# contract as the zone import block: a record recreated out-of-band gets a
# new id, the stale literal then fails closed at plan.
import {
  to = cloudflare_record.null_mx
  id = "4a16c6fcd6949d1887d6247f95a0d91e/61c50f6790fdf5d1c59e9ae250c3671e"
}

# Deny-all SPF — no host may send mail as @rundevoo.run.
resource "cloudflare_record" "spf_deny_all" {
  zone_id = cloudflare_zone.rundevoo_run.id
  name    = "rundevoo.run"
  content = "v=spf1 -all"
  type    = "TXT"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_record.spf_deny_all
  id = "4a16c6fcd6949d1887d6247f95a0d91e/ea8cfd1ba5d2ca736c900501df1005e3"
}

# DMARC p=reject — receivers drop mail claiming @rundevoo.run. No rua: the
# domain sends nothing, so aggregate reports carry no signal worth the
# address's upkeep.
resource "cloudflare_record" "dmarc_reject" {
  zone_id = cloudflare_zone.rundevoo_run.id
  name    = "_dmarc"
  content = "v=DMARC1; p=reject"
  type    = "TXT"
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_record.dmarc_reject
  id = "4a16c6fcd6949d1887d6247f95a0d91e/06b99698811902941847e718e90351e8"
}
