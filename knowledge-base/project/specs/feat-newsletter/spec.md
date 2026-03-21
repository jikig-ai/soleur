# Feature: Newsletter Email Capture

## Problem Statement

Soleur has no way to capture visitor emails for future newsletter distribution or validation outreach. The marketing strategy identifies "Email / newsletter: Does not exist. No way to capture or nurture leads" as a Medium-priority infrastructure blocker. The site currently collects zero personal data.

## Goals

- Enable visitors to subscribe to a future monthly newsletter via email
- Use Buttondown as the newsletter platform (no custom backend)
- Place signup forms in site footer (global), homepage CTA section, and blog page
- Implement GDPR-compliant double opt-in consent flow
- Update all affected legal documents before launching the form

## Non-Goals

- Sending actual newsletter emails (Phase B — gated on 100+ weekly visitors + 4+ articles)
- Building custom subscriber management, unsubscribe handling, or email archives
- Bundling Buttondown MCP server in plugin.json (API key auth, not bundleable)
- Adding email marketing skills or agents to the plugin
- Collecting any data beyond email address (data minimization)

## Functional Requirements

### FR1: Signup Form — Site Footer

Embed a Buttondown signup form in the base layout footer so it appears on every page. Form contains a single email input field and a submit button. Form submits to Buttondown's API endpoint (no backend needed). Displays confirmation message after submission ("Check your email to confirm").

### FR2: Signup Form — Homepage CTA Section

Add a newsletter CTA section to the homepage (index.njk) with brand-aligned copy and the same Buttondown embed form. Position after the main feature sections, before the footer.

### FR3: Signup Form — Blog Page

Add a newsletter signup prompt at the end of individual blog articles via the `blog-post.njk` layout (after the `.prose` content div, not inside it). Captures readers already engaged with content.

### FR4: Double Opt-In Flow

Configure Buttondown to require email confirmation (double opt-in). User enters email → Buttondown sends confirmation email → user clicks link to confirm subscription. Consent is logged by Buttondown with timestamp.

### FR5: Privacy Notice at Point of Collection

Each signup form includes a short transparency notice: purpose of collection, link to Privacy Policy, and statement that unsubscribe is available at any time. Compliant with GDPR Art. 13 transparency requirements.

## Technical Requirements

### TR1: Static Site Integration

Forms must work on the static Eleventy site hosted on GitHub Pages. No server-side processing. Buttondown's embed form or a minimal JS fetch to Buttondown's API endpoint.

### TR2: Legal Document Updates

Update three documents before the form goes live:

- **Privacy Policy** — Add section for newsletter email collection (data category, purpose, lawful basis, retention, third-party processor)
- **GDPR Policy** — Add processing activity entry, update "data NOT collected" section, add Article 30 register entry
- **Data Protection Disclosure** — Add Buttondown as third-party processor

### TR3: DNS Configuration

Add DKIM/SPF DNS records on soleur.ai via Cloudflare for Buttondown sender domain verification (needed for Phase B sends, can be deferred).

### TR4: Brand Consistency

Form styling must match the existing design system: dark background (#0A0A0A), gold accent (#C9A962), @layer cascade layers, responsive design matching current breakpoints.

### TR5: Buttondown DPA Verification

Before launch, verify Buttondown's Data Processing Agreement availability and EU-US data transfer mechanism (DPF certification or SCCs). Document in GDPR Policy.
