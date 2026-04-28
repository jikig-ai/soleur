# Learning: Enabling Proton Mail on a Cloudflare-managed zone (Terraform)

## Problem

Operator wanted to migrate `@soleur.ai` mailboxes onto Proton Mail. The full
enablement spans seven DNS records issued across four Proton admin tabs
(Verify, MX, SPF, DKIM, DMARC):

| Tab | Record | Type | Apex/Host |
|---|---|---|---|
| Verify | `protonmail-verification=<token>` | TXT | apex |
| MX | `mail.protonmail.ch` (10), `mailsec.protonmail.ch` (20) | MX | apex |
| SPF | `v=spf1 include:_spf.protonmail.ch ~all` | TXT | apex (replace existing) |
| DKIM | 3× per-domain CNAME targets (`protonmail{,2,3}.domainkey.<id>.domains.proton.ch`) | CNAME | `protonmail{,2,3}._domainkey` |
| DMARC | (already configured) | TXT | `_dmarc` |

DNS for `soleur.ai` is fully managed via Terraform
(`apps/web-platform/infra/dns.tf`), so `hr-all-infrastructure-provisioning-servers`
forbids dashboard/API edits. Every record landed as a `cloudflare_record`
resource and applied via the documented Doppler-nested invocation in `main.tf`.

## Solution

Land the verification record first (a no-op for receivers), get verification
green in Proton's panel, then land the rest atomically. Apex records that
return `"@"` from the Proton UI MUST use the literal FQDN (`name = "soleur.ai"`)
to avoid perpetual CF API normalization drift -- the inline comment on
`google_site_verification` is the canonical reference.

Order in dns.tf (grouped together for grep-ability):

```hcl
resource "cloudflare_record" "protonmail_verification" { ... }  # apex TXT
resource "cloudflare_record" "protonmail_mx_primary"   { ... }  # apex MX 10
resource "cloudflare_record" "protonmail_mx_secondary" { ... }  # apex MX 20
resource "cloudflare_record" "protonmail_dkim_1"       { ... }  # protonmail._domainkey
resource "cloudflare_record" "protonmail_dkim_2"       { ... }  # protonmail2._domainkey
resource "cloudflare_record" "protonmail_dkim_3"       { ... }  # protonmail3._domainkey
# spf_root resource updated in-place: -all -> include:_spf.protonmail.ch ~all
```

DKIM CNAME targets are issued **once per domain** in the Proton admin panel
(format `protonmail.domainkeyN.<base32-id>.domains.proton.ch`). All three share
the same `<id>`. Do not regenerate without coordinating with Proton support.

## Key Insights

**Apex TXT/MX records on this zone use the literal FQDN, not `"@"`.** The
Cloudflare provider/API normalizes `@` to the FQDN, producing perpetual drift
on every `terraform plan`. New apex records (TXT, MX, A, etc.) MUST follow the
literal-FQDN pattern.

**Multi-step record placement order matters for safety.** Verification first
(no-op for active mail), then MX/SPF/DKIM atomically once verification is
green. Splitting MX from DKIM creates a window where mail flows but signing
fails -- DMARC `p=reject` (the existing posture) would then bounce all
unsigned outbound, locking out the mailbox at exactly the moment it activates.
Atomic apply avoids that window.

**Per-Proton DKIM tokens are not in their public docs.** They appear only in
the admin panel after verification clears, must be copied from the panel's
copy buttons (the UI truncates with `...` and pasting the truncated string
silently breaks DKIM signing).

**Existing strict DMARC (`p=reject`) is intentionally retained.** Proton's
suggested `p=quarantine` is laxer; with proper SPF + DKIM in place,
`p=reject` is the correct posture and was kept untouched. Caveat: the
`rua=mailto:dmarc-reports@soleur.ai` mailbox is a future-Proton mailbox --
DMARC reports will silently bounce until that mailbox is provisioned in the
Proton panel.

**SPF posture moved from hardfail (`-all`) to softfail (`~all`).** Proton's
recommended value uses softfail for compatibility with mailing-list rewriting
and other forward scenarios. Tighten back to `-all` once deliverability is
observed clean across major receivers (Gmail, Outlook, iCloud, Yahoo).

## Session Errors

**Stale bare-repo read before worktree edit** -- read
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

**Cloudflare anycast NS edge propagation lag misread as apply failure** --
immediately after `terraform apply` succeeded for 5 new records + 1 update,
`dig @<authoritative-ns>` returned empty/stale answers for MX, SPF, and 2 of
3 DKIM CNAMEs. Looked like a partial apply.

- **Recovery:** Queried the Cloudflare REST API directly
  (`/client/v4/zones/<id>/dns_records`) to confirm all 7 records existed in
  CF's source-of-truth. NS edge caught up within ~30 seconds.
- **Prevention:** When `dig @<ns>` disagrees with `terraform apply` success,
  the API is the source-of-truth. CF's anycast edge can lag the API by tens
  of seconds for newly-mutated records; do not interpret an empty `dig`
  response as a failed apply without first checking the API. Discoverability
  exit applies (clear empty `dig` output) -- no new rule warranted.

## Tags

category: infrastructure
module: web-platform/infra/dns
