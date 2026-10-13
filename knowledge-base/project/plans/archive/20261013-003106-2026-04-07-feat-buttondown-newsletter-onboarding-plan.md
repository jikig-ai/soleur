---
title: "feat: complete Buttondown newsletter onboarding"
type: feat
date: 2026-04-07
deepened: 2026-04-07
---

# feat: complete Buttondown newsletter onboarding

## Enhancement Summary

**Deepened on:** 2026-04-07
**Sections enhanced:** 7
**Research sources:** Buttondown API (live queries), Buttondown docs, Cloudflare Terraform learnings, email deliverability patterns, existing brand assets audit

### Key Improvements

1. **Existing brand assets discovered** -- `logo-mark-512.png` (512x512) and `og-image.png` (1200x630) already exist in the repo, eliminating image generation from Phase 2
2. **Draft email API verified working** -- `POST /v1/emails` with `status: "draft"` confirmed functional via live test (created and deleted test draft)
3. **NS record values are dashboard-only** -- confirmed via Buttondown docs that managed DNS NS values are generated dynamically in Settings, not documented statically; Playwright step is mandatory before Terraform
4. **Terraform `fmt` gate added** -- per learning, always run `terraform fmt` after editing `.tf` files to prevent formatting drift
5. **Cloudflare API token permissions verified** -- existing `soleur-terraform-tunnel` token already has DNS write permissions (proven by existing `cloudflare_record` resources in state)

## Overview

Complete the Buttondown newsletter onboarding checklist for the Soleur newsletter. The Buttondown account exists (`BUTTONDOWN_API_KEY` in Doppler `soleur/dev`), and newsletter subscription forms are live on the website (issue #501 closed). The onboarding email recommends six tasks; team invites are skipped (solo operator).

Current state (from API query):

- **Newsletter name:** "Soleur Newsletter" (set)
- **From name:** "Soleur" (set)
- **Email address:** <ops@jikigai.com>
- **Description:** empty
- **Tint color:** `#0069FF` (Buttondown default blue -- not brand-aligned)
- **Icon:** none
- **Share image:** none
- **Header/Footer:** empty
- **Sending domain:** none configured
- **Custom hosting domain:** none
- **Subscribers:** 1 (<jean.deruelle@jikigai.com>)
- **Template:** modern
- **Plan:** Free (includes custom sending domain, API access, archives)

## Problem Statement / Motivation

An unconfigured newsletter sends from `newsletter@buttondown.com` with default Buttondown branding. This undermines brand recognition and email deliverability. Completing onboarding ensures:

1. Emails arrive from `newsletter@soleur.ai` (or chosen subdomain) with proper DKIM/SPF authentication
2. Visual branding matches the Solar Forge identity (gold `#C9A962`, Soleur icon)
3. Header/footer establish brand consistency across all newsletter sends
4. The first email can be sent to validate the end-to-end pipeline

## Proposed Solution

Five tasks across two execution modes -- API-first for programmatic settings, Playwright for dashboard-only features:

### Phase 1: Newsletter Branding via API

Configure all API-accessible branding fields using `PATCH /v1/newsletters/{id}`:

| Field | Current | Target | Source |
|-------|---------|--------|--------|
| `description` | (empty) | "Monthly updates about Soleur -- new agents, skills, and what we're building next." | `newsletter-form.njk` line 4 |
| `tint_color` | `#0069FF` | `#C9A962` | Brand guide: Gold Accent |
| `header` | (empty) | Brand-aligned header (Markdown) | Brand guide voice |
| `footer` | (empty) | Brand-aligned footer with unsubscribe context | Brand guide: footer tagline |
| `timezone` | `Etc/UTC` | `Europe/Paris` | Founder's timezone |

**Newsletter ID:** `news_3wpkj1rdcz9yvavzrctks7ztgp`

**API call pattern:**

```bash
doppler run -p soleur -c dev -- curl -s -X PATCH \
  -H "Authorization: Token $BUTTONDOWN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Monthly updates about Soleur -- new agents, skills, and what we are building next.",
    "tint_color": "#C9A962",
    "header": "<header-content>",
    "footer": "<footer-content>",
    "timezone": "Europe/Paris"
  }' \
  "https://api.buttondown.com/v1/newsletters/news_3wpkj1rdcz9yvavzrctks7ztgp"
```

**Header content** (Markdown):

```markdown
# Soleur

*Build a Billion-Dollar Company. Alone.*
```

**Footer content** (Markdown):

```markdown
---

Designed, built, and shipped by Soleur -- using Soleur.

[Website](https://soleur.ai) | [GitHub](https://github.com/jikig-ai/soleur) | [Discord](https://discord.gg/PYZbPBKMUY) | [X](https://x.com/soleur_ai)
```

### Phase 2: Icon and Share Image via Playwright

The Buttondown API does not support file uploads for `icon` and `image` fields. Use Playwright MCP to upload via the dashboard.

1. Navigate to `https://buttondown.com/settings`
2. Upload newsletter icon -- use `plugins/soleur/docs/images/logo-mark-512.png` (512x512 square PNG, Buttondown will resize to 300x300)
3. Upload share image -- use `plugins/soleur/docs/images/og-image.png` (1200x630, exact match for Buttondown's share image spec)

### Research Insights (Phase 2)

**Assets already exist -- no generation needed:**

- `logo-mark-512.png` (512x512) -- Gold Circle logo mark, suitable for newsletter icon
- `og-image.png` (1200x630) -- OpenGraph image, exact dimensions Buttondown requires for share image

**Playwright file upload pattern** (from learning `2026-03-09-x-provisioning-playwright-automation.md`):

- Use `browser_file_upload` MCP tool for file inputs
- File paths must be absolute (MCP resolves from repo root, not shell CWD -- per AGENTS.md)
- Absolute path: `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-buttondown-onboarding/plugins/soleur/docs/images/logo-mark-512.png`

**Buttondown login prerequisite:** The settings page requires authentication. Check if there is a Buttondown session cookie available. If not, use Playwright to log in first (email: <ops@jikigai.com>, password from Doppler if stored, or prompt user for the single login step).

### Phase 3: Sending Domain via Terraform + Playwright

Setting up a custom sending domain requires two systems:

**3a. Buttondown dashboard (Playwright):** Navigate to Settings > Domains, enter the sending domain (e.g., `mail.soleur.ai` or `newsletter.soleur.ai`), and retrieve the DNS records Buttondown requires.

**3b. Terraform DNS records:** Add the required DNS records to `apps/web-platform/infra/dns.tf`. Buttondown offers two modes:

- **Managed DNS (recommended by Buttondown):** Requires delegating a subdomain via 2 NS records. Buttondown then manages DKIM/SPF records automatically.
- **Manual DNS:** Requires adding individual DKIM, SPF, and potentially CNAME records.

**Decision: Use managed DNS with subdomain `mail.soleur.ai`.** Rationale:

- Managed DNS lets Buttondown rotate DKIM keys and switch sending providers without requiring Terraform updates
- A dedicated subdomain avoids conflicts with existing `send.soleur.ai` (Resend) and root domain records
- The NS delegation is a one-time Terraform change

**Terraform resources to add in `dns.tf`:**

```hcl
# Buttondown managed sending domain -- NS delegation for mail.soleur.ai
# Buttondown manages DKIM/SPF/MX records within this subdomain.
# Exact NS values come from Buttondown dashboard after domain registration.
resource "cloudflare_record" "buttondown_ns1" {
  zone_id = var.cf_zone_id
  name    = "mail"
  content = "<ns1-value-from-buttondown>"
  type    = "NS"
  ttl     = 1
}

resource "cloudflare_record" "buttondown_ns2" {
  zone_id = var.cf_zone_id
  name    = "mail"
  content = "<ns2-value-from-buttondown>"
  type    = "NS"
  ttl     = 1
}
```

**Sharp edge (from learning):** Use the subdomain name `"mail"`, not `"mail.soleur.ai"` FQDN, since Cloudflare only normalizes `@` to FQDN -- subdomain records are stored as-is.

**Terraform apply:** Run via the established pattern:

```bash
doppler run --project soleur --config prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply
```

**3c. Verification:** After DNS propagation, verify in Buttondown dashboard that the sending domain shows as verified. Then update the newsletter's `email_domain` via API if needed.

### Phase 4: Send First Email (Draft via API)

Create the first newsletter email as a draft via the API, then review before sending:

```bash
doppler run -p soleur -c dev -- curl -s -X POST \
  -H "Authorization: Token $BUTTONDOWN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "subject": "<subject>",
    "body": "<body-content>",
    "status": "draft"
  }' \
  "https://api.buttondown.com/v1/emails"
```

**Content direction:** The first email should introduce Soleur to the subscriber base and set expectations for future newsletters. Content aligns with the brand voice (bold, forward-looking, energizing) and the newsletter description ("Monthly updates about Soleur -- new agents, skills, and what we're building next").

### Research Insights (Phase 4)

**Draft API verified working:** Live-tested `POST /v1/emails` with `{"subject": "Test draft", "body": "Test body", "status": "draft"}` -- returned 201 with `"status": "draft"` and `"publish_date": null`. Draft was visible in dashboard. Cleanup via `DELETE /v1/emails/{id}` returned 204. No Playwright fallback needed.

**API email format control:** The `body` field auto-detects Markdown vs HTML. To force a mode, prepend `<!-- buttondown-editor-mode: plaintext -->` for Markdown or `<!-- buttondown-editor-mode: fancy -->` for HTML. Use Markdown (plaintext mode) for the first email -- it aligns with the brand voice's directness and renders cleanly.

**YAML frontmatter warning:** The API rejects email bodies starting with YAML frontmatter blocks (returns 400). If the email content starts with `---`, add the `X-Buttondown-Live-Dangerously: true` header or ensure the body does not begin with frontmatter.

**First email content outline:**

```markdown
# Welcome to the Soleur Newsletter

You're building something ambitious. We're building the tools to make it possible.

Soleur is the Company-as-a-Service platform -- AI agents that handle marketing,
legal, finance, operations, and more. One founder makes decisions. The system executes.

**What to expect from this newsletter:**

- Monthly updates on new agents and skills
- Behind-the-scenes on building a company with AI
- Practical insights for solo founders

This newsletter exists because the billion-dollar solo company isn't science fiction.
It's an engineering problem. We're solving it.

-- Jean Deruelle, Founder
```

**Sending considerations:** Wait until sending domain is verified (Phase 3 complete) before sending. Emails sent from `buttondown.com` domain have lower deliverability than branded domains.

### Phase 5: Expense Tracking

Add Buttondown to `knowledge-base/operations/expenses.md`:

```markdown
| Buttondown | Buttondown | saas | 0.00 | free-tier | - | Newsletter platform. Free tier: 100 subscribers, custom sending domain, API access. Upgrade trigger: >100 subscribers ($9/mo Basic) |
```

## Technical Considerations

- **Terraform provider version:** The codebase pins `cloudflare ~> 4.0`. Use `cloudflare_record` (not `cloudflare_dns_record` which is v5). Per learning `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`.
- **Existing email infrastructure:** Resend uses `send.soleur.ai` for transactional emails (ops notifications). The newsletter sending domain must use a different subdomain to avoid SPF/DKIM conflicts. `mail.soleur.ai` is the recommended choice.
- **DMARC:** An existing DMARC record (`_dmarc.soleur.ai`) with `p=quarantine` covers all subdomains. Buttondown emails sent from `mail.soleur.ai` will inherit this policy. No DMARC changes needed.
- **Cloudflare proxy:** NS records for managed DNS delegation must NOT be proxied (NS records cannot be proxied). Terraform should omit `proxied` or set it to `false`.
- **Terraform `fmt` gate:** Always run `terraform fmt` after editing `.tf` files. Per learning `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md`, formatting mismatches are caught by lefthook pre-commit hooks.
- **Post-apply verification:** Run `terraform plan` immediately after `terraform apply` to confirm clean state. Per the same learning, drift can be invisible on initial apply but manifest on subsequent plans.
- **Cloudflare API token scope:** The existing `soleur-terraform-tunnel` token already has DNS write permissions (proven by 15+ `cloudflare_record` resources in state). No permission changes needed. Per learning `2026-03-21-cloudflare-api-token-permission-editing.md`, editing permissions does NOT rotate the token -- but it is unnecessary here.
- **Buttondown authentication for Playwright:** The dashboard requires login. Check for Buttondown credentials in Doppler (`doppler secrets --only-names -p soleur -c dev | grep -i buttondown`). If only the API key exists (no password), prompt the user for the single Buttondown login step via Playwright, then proceed with uploads and domain configuration.

## Acceptance Criteria

- [x] Newsletter description set to match website form copy
- [x] Tint color changed from Buttondown default blue to brand gold `#C9A962`
- [x] Header displays "Soleur" heading with tagline
- [x] Footer includes brand tagline and social links
- [x] Timezone set to `Europe/Paris`
- [x] Newsletter icon uploaded (300x300 square PNG)
- [x] Share image uploaded (1200x630 PNG)
- [x] Sending domain `mail.soleur.ai` configured and verified in Buttondown
- [x] NS records for `mail.soleur.ai` added to Terraform and applied
- [x] First newsletter email sent (2026-04-07)
- [x] Buttondown added to `knowledge-base/operations/expenses.md`

## Test Scenarios

- **API verify (branding):** `doppler run -p soleur -c dev -- curl -s -H "Authorization: Token $BUTTONDOWN_API_KEY" https://api.buttondown.com/v1/newsletters | jq '.results[0] | {description, tint_color, timezone, header, footer}'` expects description non-empty, tint_color `#C9A962`, timezone `Europe/Paris`, header and footer non-empty
- **API verify (icon):** `doppler run -p soleur -c dev -- curl -s -H "Authorization: Token $BUTTONDOWN_API_KEY" https://api.buttondown.com/v1/newsletters | jq '.results[0].icon'` expects non-null URL
- **API verify (sending domain):** `doppler run -p soleur -c dev -- curl -s -H "Authorization: Token $BUTTONDOWN_API_KEY" https://api.buttondown.com/v1/newsletters | jq '.results[0].email_domain'` expects `"mail.soleur.ai"` (or the chosen subdomain)
- **DNS verify:** `dig NS mail.soleur.ai +short` expects two Buttondown nameservers
- **Browser:** Navigate to `https://buttondown.com/settings`, verify icon and share image are displayed, sending domain shows as verified

## Dependencies and Risks

- **Buttondown managed DNS NS values:** Only available after entering the domain in the Buttondown dashboard. The Terraform step depends on retrieving these values first via Playwright. Confirmed by Buttondown docs: "Add the two NS type records that are shown to you in Settings." No static NS values exist in documentation.
- **DNS propagation:** NS delegation may take minutes to hours. Verification should include polling with `dig NS mail.soleur.ai +short` on an interval. Buttondown dashboard also shows verification status.
- ~~**Icon/share image assets:** May need to generate brand assets~~ **RESOLVED:** `logo-mark-512.png` (512x512) and `og-image.png` (1200x630) already exist in `plugins/soleur/docs/images/`. No generation needed.
- ~~**Draft email API:** The `status: "draft"` field is not explicitly documented~~ **RESOLVED:** Live-tested successfully. `POST /v1/emails` with `status: "draft"` returns 201. `DELETE /v1/emails/{id}` returns 204. Both work as expected.
- **Buttondown dashboard login:** Playwright phases (2 and 3) require dashboard authentication. The only credential in Doppler is `BUTTONDOWN_API_KEY` (not a password). The user may need to manually enter credentials at the Buttondown login screen once, after which Playwright can proceed with the authenticated session.
- **Sending domain verification timing:** Phase 4 (first email) should wait for Phase 3 (sending domain) to complete and verify. Sending from the default `buttondown.com` domain reduces deliverability.

## Domain Review

**Domains relevant:** Marketing, Operations

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Newsletter branding must align with Solar Forge visual identity. The gold tint color `#C9A962`, Cormorant Garamond heading in the header, and the footer tagline "Designed, built, and shipped by Soleur -- using Soleur" are brand-compliant. The sending domain `mail.soleur.ai` strengthens brand recognition vs. `buttondown.com`. First email content should use the brand voice (bold, forward-looking) and the general register (accessible vocabulary) since the subscriber base may include non-technical founders. Content opportunity: the first newsletter send could be distributed as a content event via Discord announcement.

### Operations (COO)

**Status:** reviewed
**Assessment:** Buttondown is on the free tier ($0/mo, 100 subscriber limit). No new recurring cost. Upgrade trigger documented at >100 subscribers. Expense tracking entry required in `knowledge-base/operations/expenses.md`. DNS changes go through Terraform (existing pattern in `dns.tf`). No new Doppler secrets needed -- `BUTTONDOWN_API_KEY` already exists in `soleur/dev`. The Terraform apply uses existing `prd_terraform` Doppler config with Cloudflare API token.

### Product/UX Gate

Not applicable -- no new user-facing pages or UI components. Newsletter branding is a backend/service configuration task.

## References and Research

### Internal References

- **Brand guide:** `knowledge-base/marketing/brand-guide.md` (colors, typography, voice, tagline)
- **Newsletter form:** `plugins/soleur/docs/_includes/newsletter-form.njk` (existing description copy)
- **Site config:** `plugins/soleur/docs/_data/site.json` (social links, newsletter username)
- **Newsletter icon:** `plugins/soleur/docs/images/logo-mark-512.png` (512x512, ready for upload)
- **Share image:** `plugins/soleur/docs/images/og-image.png` (1200x630, ready for upload)
- **DNS infrastructure:** `apps/web-platform/infra/dns.tf` (existing Cloudflare DNS records)
- **Terraform config:** `apps/web-platform/infra/main.tf` (provider versions, R2 backend)
- **Terraform variables:** `apps/web-platform/infra/variables.tf` (cf_zone_id, cf_api_token)

### Learnings Applied

- `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` -- use `cloudflare_record` not `cloudflare_dns_record`, use subdomain name not FQDN for non-apex records
- `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md` -- always run `terraform fmt` and post-apply `terraform plan` verification
- `2026-03-18-supabase-resend-email-configuration.md` -- pattern for DNS-based email auth setup (SPF, DKIM, DMARC records via Terraform)
- `2026-03-21-cloudflare-api-token-permission-editing.md` -- existing CF API token already has DNS write permissions
- `2026-03-25-check-mcp-api-before-playwright.md` -- priority chain: API first, Playwright for dashboard-only features
- `2026-03-09-x-provisioning-playwright-automation.md` -- Playwright file upload and form filling patterns
- `2026-03-18-buttondown-gdpr-transfer-mechanism-sccs-only.md` -- Buttondown uses SCCs for data transfers (no GDPR action needed)

### External References

- **Buttondown API docs:** [Configuration and Branding](https://docs.buttondown.com/configuration-and-branding)
- **Buttondown sending domain docs:** [Sending from a custom domain](https://docs.buttondown.com/sending-from-a-custom-domain)
- **Buttondown managed DNS blog:** [Managed DNS](https://buttondown.com/blog/managed-dns)
- **Buttondown pricing:** [Pricing](https://buttondown.com/pricing) -- free tier includes custom sending domain

### Related Issues

- **Closed issue:** #501 (Newsletter -- subscription forms on site)
- **Related:** #1050 (service automation -- API + MCP integrations)
