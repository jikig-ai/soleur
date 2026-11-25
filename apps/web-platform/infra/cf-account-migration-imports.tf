# One-shot adoption of the hand-restored new-zone objects (#12931, ADR-329).
#
# WHY IMPORT, NOT CREATE. During the 2026-11-18 incident these records and the Pages project
# were restored by hand in the Soleur-account zone so users could reach soleur.ai, api. and
# mail again. They already exist; a create would collide. The cf-account-migrate job first
# forgets every old-id cloudflare_* entry from state (scripts/cf-account-state-migrate.sh),
# then the `redirects-dns` phase imports these by their NEW ids.
#
# WHAT AN IMPORT MAY PLAN. tests/scripts/lib/cf-account-migrate-gate.sh refuses an import whose
# id differs from the literal below, and any action other than ["no-op"] with one exception.
# The provider's Read fills `content` only when it is already set, so every cloudflare_record
# import plans ["update"] adding allow_overwrite = false and content. The gate admits exactly
# that shape, and only when a live read by the pinned id, taken after the plan, equals the
# planned record (ADR-329, CTO ruling 2026-11-22). That read is what catches a swapped id, e.g.
# two TXT records exchanged. On 2026-11-19 six scan-created TXT records were unquoted and three
# incident comments cleared in the live zone so they match dns.tf byte for byte.
#
# NOT HERE: cloudflare_record.app (its content is web-1's IPv4 and hcloud_server.web renders
# the tunnel token, so importing it pulls the tunnel into the plan; it rides the tunnel phase
# behind var.cf_migration_import_app), and deploy/ssh/registry (created by the tunnel phase).
# Records Terraform never managed (76624499, the send.outbound pair, resend._domainkey.outbound,
# two extra apex google-site-verification TXT) are not adopted.
#
# Ids are literals on purpose: the gate compares them byte for byte. Record ids are not secret.
# The cleanup PR deletes this file once the migration is complete.

locals {
  cf_migration_import_set     = var.cf_migration_imports_enabled ? toset(["adopt"]) : toset([])
  cf_migration_import_app_set = var.cf_migration_imports_enabled && var.cf_migration_import_app ? toset(["adopt"]) : toset([])
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.dkim_resend
  id       = "951ce525552201ec6c696b24251abed7/7a1e971b4e40dfe50b0baa357ec88a30" # TXT resend._domainkey.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.spf_send
  id       = "951ce525552201ec6c696b24251abed7/da436e8810a4d029a479eed37b0e8af9" # TXT send.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.mx_send
  id       = "951ce525552201ec6c696b24251abed7/57b268f4b29b193fb3c855b12301001f" # MX send.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.dkim_resend_send
  id       = "951ce525552201ec6c696b24251abed7/191e23f8a3e83d6a417c9ccd6de41c54" # TXT resend._domainkey.send.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.spf_send_send
  id       = "951ce525552201ec6c696b24251abed7/c34ec9c745b6e7f45471ab30f6165404" # TXT send.send.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.mx_send_send
  id       = "951ce525552201ec6c696b24251abed7/c004ff2f5d651b30125c29bdeb425db9" # MX send.send.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.dkim_resend_inbound
  id       = "951ce525552201ec6c696b24251abed7/f23fdb229f978bd622789527f22fb7c0" # TXT resend._domainkey.inbound.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.spf_send_inbound
  id       = "951ce525552201ec6c696b24251abed7/6d0ce40316c6514b8428527018263db3" # TXT send.inbound.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.mx_send_inbound
  id       = "951ce525552201ec6c696b24251abed7/17f651e96b3df8fe5d640dd3fd704eeb" # MX send.inbound.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.mx_receiving_inbound
  id       = "951ce525552201ec6c696b24251abed7/f159a787212218bef5c15526a2dc6dab" # MX inbound.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.dmarc
  id       = "951ce525552201ec6c696b24251abed7/58f17b9ece2ac3ca3b0e70fba86485dc" # TXT _dmarc.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.supabase_custom_domain
  id       = "951ce525552201ec6c696b24251abed7/d12dea4d3065c1ca675ae0f677d56863" # CNAME api.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.supabase_acme_challenge
  id       = "951ce525552201ec6c696b24251abed7/08cd4432f1c750d85d3dc548766c1aa8" # TXT _acme-challenge.api.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.spf_root
  id       = "951ce525552201ec6c696b24251abed7/0cef4507ca8fc353bfc7718d28321930" # TXT soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.google_site_verification
  id       = "951ce525552201ec6c696b24251abed7/b565ee1467aec610a531794647c7591f" # TXT soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.protonmail_verification
  id       = "951ce525552201ec6c696b24251abed7/0aaa4bd2c7d69948918ba61d5c809660" # TXT soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.protonmail_mx_primary
  id       = "951ce525552201ec6c696b24251abed7/772e44c9493352a2652351c4ae8e96b6" # MX soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.protonmail_mx_secondary
  id       = "951ce525552201ec6c696b24251abed7/cc80878e1c98939d367b85712fe46a84" # MX soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.protonmail_dkim_1
  id       = "951ce525552201ec6c696b24251abed7/0b2922dce2f0971d02acdbc1c7fd79de" # CNAME protonmail._domainkey.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.protonmail_dkim_2
  id       = "951ce525552201ec6c696b24251abed7/b955000499599137cfb0b25e2352a4c4" # CNAME protonmail2._domainkey.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.protonmail_dkim_3
  id       = "951ce525552201ec6c696b24251abed7/e967cfdfaf92c10b4e111452ab20f79c" # CNAME protonmail3._domainkey.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.pages_apex
  id       = "951ce525552201ec6c696b24251abed7/6649d796e7da5dae3ce3132fc0dd56f4" # CNAME soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.www
  id       = "951ce525552201ec6c696b24251abed7/c9e10a6da158ddb94f059cb5185ddde2" # CNAME www.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.github_pages_challenge
  id       = "951ce525552201ec6c696b24251abed7/3e2a7a4f34fbce65231407be230e9242" # TXT _github-pages-challenge-jikig-ai.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.buttondown_ns1
  id       = "951ce525552201ec6c696b24251abed7/1184ee425c4c440463bd2fe5982bb4b9" # NS mail.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  to       = cloudflare_record.buttondown_ns2
  id       = "951ce525552201ec6c696b24251abed7/d0b1b00f941b22ec6d3e042847e30a35" # NS mail.soleur.ai
}

import {
  for_each = local.cf_migration_import_set
  provider = cloudflare.pages
  to       = cloudflare_pages_project.docs
  id       = "66d4f93f7397f196544e9fe84c3557c2/soleur-docs"
}

import {
  for_each = local.cf_migration_import_set
  provider = cloudflare.pages
  to       = cloudflare_pages_domain.apex
  id       = "66d4f93f7397f196544e9fe84c3557c2/soleur-docs/soleur.ai"
}

import {
  for_each = local.cf_migration_import_set
  provider = cloudflare.pages
  to       = cloudflare_pages_domain.www
  id       = "66d4f93f7397f196544e9fe84c3557c2/soleur-docs/www.soleur.ai"
}

# Tunnel phase only (PR2 flips var.cf_migration_import_app).
import {
  for_each = local.cf_migration_import_app_set
  to       = cloudflare_record.app
  id       = "951ce525552201ec6c696b24251abed7/f21d6911cdacb1e109ae31bcfb440e7d" # A app.soleur.ai
}
