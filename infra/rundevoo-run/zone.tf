# rundevoo.run zone — Registrar-created at purchase (2026-11-19), adopted via
# the committed import block below. `type = "full"` keeps Cloudflare as the
# authoritative DNS (the only mode the Registrar-created zone is on anyway).
# No `jump_start`: it is a create-time attribute that is meaningless-to-harmful
# on an imported zone.
resource "cloudflare_zone" "rundevoo_run" {
  zone = "rundevoo.run"
  # The zone lives in the "Soleur" Cloudflare account (66d4f93f…), NOT the
  # prd_terraform CF_ACCOUNT_ID (4d5ba6f0… — the separate R2/state/tunnel
  # account). Literal, not a var: the account id is bound to the zone id
  # below — a zone recreated under a different account changes the zone id,
  # and the import block then fails closed rather than silently repointing.
  account_id = "66d4f93f7397f196544e9fe84c3557c2"
  type       = "full"
}

# Literal zone id, discovered 2026-11-19 via GET /zones?name=rundevoo.run.
# Failure mode: if the zone is ever deleted and recreated in the dashboard the
# id changes and every plan/apply hard-fails on the import read until this
# block is edited — that fail-closed behaviour is deliberate (a repointed or
# recreated zone must not be clobbered silently). The id is valid only for
# this zone, so the literal coupling is correct.
import {
  to = cloudflare_zone.rundevoo_run
  id = "4a16c6fcd6949d1887d6247f95a0d91e"
}

# DNSSEC for rundevoo.run — Cloudflare Registrar auto-propagates the DS record
# (the jikigai.com registrar-side DS dance does not apply). Status is
# computed-only in provider v4.x (not configurable); transitions
# disabled -> pending -> active.
resource "cloudflare_zone_dnssec" "rundevoo_run" {
  zone_id = cloudflare_zone.rundevoo_run.id
}
