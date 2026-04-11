# Service Deep Links

Reference file for the service-automator agent. Contains signup URLs, token generation links, and required permissions for guided instructions mode.

Separated from the agent prompt so URLs can be updated independently without modifying the agent definition.

## Cloudflare

| Action | URL |
|--------|-----|
| Signup | `https://dash.cloudflare.com/sign-up` |
| Dashboard | `https://dash.cloudflare.com/` |
| API Tokens | `https://dash.cloudflare.com/profile/api-tokens` |
| Add Site | `https://dash.cloudflare.com/?to=/:account/add-site` |
| Domain Registration | `https://dash.cloudflare.com/?to=/:account/domains/register` |

**Token permissions:** Zone:Read, DNS:Edit, Zone Settings:Edit, SSL/TLS:Edit

**Guided steps:**

1. Create a Cloudflare account at the signup URL
2. Add your site domain (Cloudflare will scan existing DNS records)
3. Update your domain's nameservers to the ones Cloudflare provides
4. Wait for nameserver propagation (can take up to 24 hours)
5. Generate an API token at the API Tokens page with the permissions above
6. Store the token in Settings > Connected Services

## Stripe

| Action | URL |
|--------|-----|
| Signup | `https://dashboard.stripe.com/register` |
| Dashboard | `https://dashboard.stripe.com/` |
| API Keys | `https://dashboard.stripe.com/apikeys` |
| Products | `https://dashboard.stripe.com/products` |
| Payment Links | `https://dashboard.stripe.com/payment-links` |

**Token permissions (restricted key):** Products:Write, Prices:Write, Customers:Write, Payment Links:Write, Invoices:Write

**Guided steps:**

1. Create a Stripe account at the signup URL
2. Complete account activation (business details, bank account for payouts)
3. Navigate to API Keys page
4. Create a restricted key with the permissions listed above
5. Store the restricted key in Settings > Connected Services

## Plausible

| Action | URL |
|--------|-----|
| Signup | `https://plausible.io/register` |
| Dashboard | `https://plausible.io/sites` |
| API Keys | `https://plausible.io/settings/api-keys` |
| Add Site | `https://plausible.io/sites/new` |
| Site Settings | `https://plausible.io/{domain}/settings` |

**Token permissions:** Sites API scope (required for site provisioning)

**Guided steps:**

1. Create a Plausible account at the signup URL
2. Add your site domain at the Add Site page
3. Add the Plausible script tag to your site's `<head>` section
4. Visit your site to verify a pageview is recorded
5. Generate an API key at the API Keys page
6. Store the API key in Settings > Connected Services

## Hetzner

| Action | URL |
|--------|-----|
| Signup | `https://console.hetzner.cloud/` |
| API Tokens | `https://console.hetzner.cloud/manage/{project}/security/api-tokens` |
| Servers | `https://console.hetzner.cloud/manage/{project}/servers` |

**Token permissions:** Read/Write (project-scoped)

**Guided steps:**

1. Create a Hetzner Cloud account at the signup URL
2. Create a project for your application
3. Navigate to Security > API Tokens in the project
4. Generate a Read/Write API token
5. Store the token in Settings > Connected Services

## Resend

| Action | URL |
|--------|-----|
| Signup | `https://resend.com/signup` |
| Dashboard | `https://resend.com/overview` |
| API Keys | `https://resend.com/api-keys` |
| Domains | `https://resend.com/domains` |

**Token permissions:** Full access (or send-only for production)

**Guided steps:**

1. Create a Resend account at the signup URL
2. Add and verify your sending domain at the Domains page
3. Generate an API key at the API Keys page
4. Store the API key in Settings > Connected Services
