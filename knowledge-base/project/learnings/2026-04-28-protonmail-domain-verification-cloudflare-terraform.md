# Learning: ProtonMail domain verification on a Cloudflare-managed zone (Terraform)

## Problem

Operator wanted to enable Proton Mail on `soleur.ai`. Proton issues a one-shot
TXT record (`protonmail-verification=<token>`) at the zone apex to prove
ownership before activating mail features.

DNS for `soleur.ai` is fully managed via Terraform
(`apps/web-platform/infra/dns.tf`), so `hr-all-infrastructure-provisioning-servers`
forbids dashboard/API edits. The change had to land as a `cloudflare_record`
resource and apply via the documented Doppler-nested invocation in `main.tf`.

## Solution

Add a single `cloudflare_record` resource grouped with the other apex TXT
records (`spf_root`, `google_site_verification`):

```hcl
resource "cloudflare_record" "protonmail_verification" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai" # Use FQDN, not "@" -- CF API normalizes @ to FQDN, causing perpetual drift
  content = "protonmail-verification=<TOKEN>"
  type    = "TXT"
  ttl     = 1
}
```

Apply via the documented nested-Doppler pattern (`apps/web-platform/infra/main.tf`
header) and verify against the Cloudflare authoritative NS rather than public
recursors -- public resolvers lag behind for the TTL window.

```bash
NS=$(dig soleur.ai NS +short | head -1)
dig @$NS soleur.ai TXT +short | grep -i proton
```

## Key Insight

**Apex TXT records on this zone use the literal FQDN, not `"@"`.** The dns.tf
file carries an inline comment on `google_site_verification` documenting that
the Cloudflare provider/API normalizes `@` to the FQDN, producing perpetual
drift on every plan. New apex records (TXT, A, MX, etc.) MUST follow the
literal-FQDN pattern to stay drift-free.

**Verification is step 1 of N for Proton Mail.** Enabling sending later
requires:

- MX records at apex: `mail.protonmail.ch` (priority 10), `mailsec.protonmail.ch` (priority 20)
- Apex SPF widened from the current `v=spf1 -all` to include `_spf.protonmail.ch`
  (today's hard-fail SPF blocks Proton sending until updated)
- DKIM CNAMEs: `protonmail._domainkey`, `protonmail2._domainkey`,
  `protonmail3._domainkey` pointing at Proton's published targets

These are deferred until verification clears in Proton's panel and the operator
provisions the mailbox -- a single resource per ProtonMail console row, same
file, same nested-Doppler apply.

## Session Errors

**Stale bare-repo read before worktree edit** -- I read
`apps/web-platform/infra/dns.tf` from the bare-repo working path before
creating the worktree, then tried to Edit the worktree copy. The Edit tool
rejected it (read-before-edit guard); the bare-repo content was also stale
(55 lines vs the worktree's ~184 lines, missing `spf_root`, `github_pages`,
`supabase_acme_challenge`, etc.).

- **Recovery:** Re-read the file at the worktree absolute path, then Edit succeeded.
- **Prevention:** Already covered by `hr-when-in-a-worktree-never-read-from-bare`
  and `hr-always-read-a-file-before-editing-it`; the Edit tool enforces
  read-before-edit mechanically. Discoverability exit applies -- no new rule
  warranted.

## Tags

category: infrastructure
module: web-platform/infra/dns
