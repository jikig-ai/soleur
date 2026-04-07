---
title: "feat: complete Buttondown newsletter onboarding"
type: feat
date: 2026-04-07
---

# feat: complete Buttondown newsletter onboarding

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
2. Upload newsletter icon (300x300 PNG, square) -- use existing brand assets or generate via `soleur:gemini-imagegen`
3. Upload share image (1200x630 PNG) -- use existing brand assets or generate

**Asset source check:** Look for existing brand assets in `plugins/soleur/docs/images/` or `knowledge-base/design/brand/`. If a suitable icon does not exist, generate one matching the Gold Circle logo description from brand guide.

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

**Note:** The `status` field for creating a draft vs. published email needs verification during implementation. The API docs do not explicitly document this field. If drafts are not supported via API, use Playwright to compose in the dashboard editor.

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

## Acceptance Criteria

- [ ] Newsletter description set to match website form copy
- [ ] Tint color changed from Buttondown default blue to brand gold `#C9A962`
- [ ] Header displays "Soleur" heading with tagline
- [ ] Footer includes brand tagline and social links
- [ ] Timezone set to `Europe/Paris`
- [ ] Newsletter icon uploaded (300x300 square PNG)
- [ ] Share image uploaded (1200x630 PNG)
- [ ] Sending domain `mail.soleur.ai` configured and verified in Buttondown
- [ ] NS records for `mail.soleur.ai` added to Terraform and applied
- [ ] First newsletter email drafted (or sent if content is approved)
- [ ] Buttondown added to `knowledge-base/operations/expenses.md`

## Test Scenarios

- **API verify (branding):** `doppler run -p soleur -c dev -- curl -s -H "Authorization: Token $BUTTONDOWN_API_KEY" https://api.buttondown.com/v1/newsletters | jq '.results[0] | {description, tint_color, timezone, header, footer}'` expects description non-empty, tint_color `#C9A962`, timezone `Europe/Paris`, header and footer non-empty
- **API verify (icon):** `doppler run -p soleur -c dev -- curl -s -H "Authorization: Token $BUTTONDOWN_API_KEY" https://api.buttondown.com/v1/newsletters | jq '.results[0].icon'` expects non-null URL
- **API verify (sending domain):** `doppler run -p soleur -c dev -- curl -s -H "Authorization: Token $BUTTONDOWN_API_KEY" https://api.buttondown.com/v1/newsletters | jq '.results[0].email_domain'` expects `"mail.soleur.ai"` (or the chosen subdomain)
- **DNS verify:** `dig NS mail.soleur.ai +short` expects two Buttondown nameservers
- **Browser:** Navigate to `https://buttondown.com/settings`, verify icon and share image are displayed, sending domain shows as verified

## Dependencies and Risks

- **Buttondown managed DNS NS values:** Only available after entering the domain in the Buttondown dashboard. The Terraform step depends on retrieving these values first via Playwright.
- **DNS propagation:** NS delegation may take minutes to hours. Verification should include polling.
- **Icon/share image assets:** May need to generate brand assets if suitable files do not exist in the repo. The `soleur:gemini-imagegen` skill can produce these.
- **Draft email API:** The `status: "draft"` field is not explicitly documented. Fallback: use Playwright to create the draft in the dashboard editor.

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

- **Brand guide:** `knowledge-base/marketing/brand-guide.md` (colors, typography, voice, tagline)
- **Newsletter form:** `plugins/soleur/docs/_includes/newsletter-form.njk` (existing description copy)
- **Site config:** `plugins/soleur/docs/_data/site.json` (social links, newsletter username)
- **DNS infrastructure:** `apps/web-platform/infra/dns.tf` (existing Cloudflare DNS records)
- **Terraform config:** `apps/web-platform/infra/main.tf` (provider versions, R2 backend)
- **Terraform variables:** `apps/web-platform/infra/variables.tf` (cf_zone_id, cf_api_token)
- **Cloudflare learning:** `knowledge-base/project/learnings/2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`
- **Buttondown GDPR learning:** `knowledge-base/project/learnings/2026-03-18-buttondown-gdpr-transfer-mechanism-sccs-only.md`
- **Buttondown API docs:** [Configuration and Branding](https://docs.buttondown.com/configuration-and-branding)
- **Buttondown sending domain docs:** [Sending from a custom domain](https://docs.buttondown.com/sending-from-a-custom-domain)
- **Closed issue:** #501 (Newsletter -- subscription forms on site)
