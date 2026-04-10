---
title: "Cookie Policy"
description: "Cookie usage on the Soleur documentation site. The Soleur plugin itself does not use cookies. Analytics are privacy-friendly via Plausible."
layout: base.njk
permalink: legal/cookie-policy/
---

<section class="page-hero">
  <div class="container">
    <h1>Cookie Policy</h1>
    <p>Effective February 20, 2026 | Last Updated March 29, 2026</p>
  </div>
</section>

<section class="content">
  <div class="container">
    <div class="prose">

**Soleur -- Company-as-a-Service Platform**

**Last updated:** March 29, 2026

## 1. Introduction

This Cookie Policy explains how Jikigai ("we," "us," or "our"), operator of Soleur, uses cookies and similar tracking technologies on our documentation website at [soleur.ai](https://soleur.ai), our web platform at [app.soleur.ai](https://app.soleur.ai), and in connection with our Company-as-a-Service platform (the "Service"). This policy is designed to comply with the EU General Data Protection Regulation (GDPR), the ePrivacy Directive, and applicable US privacy laws.

Soleur is a Claude Code plugin providing a full-stack AI organization with 63 agents, 62 skills, and a compounding knowledge base, designed for solo founders and technical builders.

## 2. What Are Cookies?

Cookies are small text files that are placed on your device (computer, tablet, or mobile) when you visit a website. They are widely used to make websites work more efficiently, to provide information to site owners, and to enable certain features. Cookies may be "session" cookies (deleted when you close your browser) or "persistent" cookies (remaining on your device for a set period or until you delete them).

Similar technologies include web beacons, pixels, local storage, and other tracking mechanisms that function in a comparable manner.

## 3. Our Cookie Usage

### 3.1 The Soleur Plugin

The Soleur plugin itself **does not use cookies**. It operates as a Claude Code plugin within your local development environment and does not set, read, or transmit cookies of any kind.

### 3.2 The Documentation Website (soleur.ai)

Our documentation website is hosted on **GitHub Pages**. We use **Plausible Analytics** for privacy-respecting website analytics. Plausible is a cookie-free analytics service -- it does not set, read, or require any cookies on your device. No advertising or tracking cookies are deployed on the documentation site.

However, GitHub Pages, as our hosting provider, may set certain cookies necessary for the operation and security of the platform. These are third-party cookies controlled by GitHub (Microsoft Corporation). We do not control the cookies set by GitHub Pages.

### 3.3 The Web Platform (app.soleur.ai)

The Soleur Web Platform at [app.soleur.ai](https://app.soleur.ai) uses a limited set of strictly necessary cookies for authentication and payment security. No analytics, advertising, or tracking cookies are deployed on the Web Platform.

| Cookie | Provider | Purpose | Type | Duration |
|--------|----------|---------|------|----------|
| `sb-*-auth-token` | Supabase (via app.soleur.ai) | Authentication session (JWT) | Strictly necessary (first-party) | Persistent (400 days; SameSite=Lax, HttpOnly=false per Supabase SSR defaults) |
| `sb-*-auth-token-code-verifier` | Supabase (via app.soleur.ai) | PKCE code verifier for OAuth flow | Strictly necessary (first-party) | Session (consumed and cleared after OAuth exchange) |
| `__stripe_mid` / `__stripe_sid` | Stripe (via Stripe Checkout redirect) | Fraud prevention during checkout | Strictly necessary (third-party) | Session / 1 year |

**Note on OAuth sign-in:** When you sign in via an OAuth provider (Google, Apple, GitHub, or Microsoft), your browser is temporarily redirected to the provider's consent page and back. The Supabase PKCE code verifier cookie listed above secures this exchange. No additional cookies are set by the OAuth providers during this redirect flow.

**Note on CSRF protection:** The Web Platform validates the Origin header on state-changing requests as CSRF protection. This is not a cookie but is documented here for transparency. No CSRF token cookie is set.

## 4. Types of Cookies

The following categories describe the types of cookies that may be encountered when visiting soleur.ai:

### 4.1 Strictly Necessary Cookies

These cookies are essential for the website to function and cannot be switched off in our systems. They are typically set by the hosting infrastructure (GitHub Pages) in response to actions you take, such as setting your privacy preferences, logging in, or filling in forms.

| Cookie Provider | Purpose | Duration |
|-----------------|---------|----------|
| GitHub Pages | Platform operation, security, and abuse prevention | Varies (session or persistent) |
| Supabase (via app.soleur.ai) | Authentication session (JWT) and PKCE code verifier | Persistent (400 days) / Session |
| Stripe (via Stripe Checkout) | Fraud prevention during payment checkout | Session / 1 year |

### 4.2 Analytics

We use **Plausible Analytics** ([plausible.io](https://plausible.io)) for website analytics. Plausible **does not use cookies** of any kind -- no session cookies, no persistent cookies, no first-party or third-party cookies. It does not use local storage, fingerprinting, or any other mechanism that stores information on your device.

Plausible collects the following anonymous, aggregated data without cookies:

| Data Point | Purpose |
|------------|---------|
| Page URL | Understanding which pages are visited |
| Referrer URL | Understanding how visitors find the site |
| Country (derived from IP, not stored) | Geographic distribution of visitors |
| Device type (desktop/mobile/tablet) | Understanding how visitors access the site |
| Browser and operating system | Technical compatibility insights |

IP addresses are used only for country-level geolocation and are **not stored** by Plausible. No personally identifiable information is collected or retained.

### 4.3 Advertising and Tracking Cookies

**We do not use any advertising or tracking cookies.** No advertising networks, retargeting services, or cross-site tracking mechanisms are deployed on our website.

### 4.4 Functional Cookies

**We do not currently set any functional cookies.** If this changes in the future, this policy will be updated accordingly.

## 5. Third-Party Cookies

As noted above, GitHub Pages may set cookies when you visit soleur.ai. For information about how GitHub handles cookies and your data, please refer to:

- [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
- [GitHub Subprocessors and Cookies](https://docs.github.com/en/site-policy/privacy-policies/github-subprocessors-and-cookies)

Additionally, when you initiate a payment through the Web Platform (app.soleur.ai), you are redirected to **Stripe Checkout**, which sets cookies (`__stripe_mid`, `__stripe_sid`) for fraud prevention. For information about how Stripe handles cookies and your data, please refer to:

- [Stripe Privacy Policy](https://stripe.com/privacy)
- [Stripe Cookie Policy](https://stripe.com/cookie-settings)

We do not have control over these third-party cookies and are not responsible for the practices of third-party providers. We encourage you to review their policies directly.

## 6. Your Rights and Choices

### 6.1 Browser Controls

You can manage or delete cookies through your browser settings. Most browsers allow you to:

- View what cookies are stored and delete them individually or in bulk
- Block third-party cookies
- Block cookies from specific sites
- Block all cookies
- Delete all cookies when you close your browser

Please note that blocking all cookies may impact the functionality of some websites.

Instructions for common browsers:

- **Chrome:** Settings > Privacy and Security > Cookies and other site data
- **Firefox:** Settings > Privacy & Security > Cookies and Site Data
- **Safari:** Preferences > Privacy > Manage Website Data
- **Edge:** Settings > Cookies and site permissions

### 6.2 Rights Under GDPR (EU/EEA Users)

If you are located in the European Union or European Economic Area, you have the following rights under the GDPR with respect to any personal data collected through cookies:

- **Right of access** -- You may request information about what personal data is processed.
- **Right to erasure** -- You may request deletion of your personal data.
- **Right to object** -- You may object to processing based on legitimate interests.
- **Right to withdraw consent** -- Where processing is based on consent, you may withdraw it at any time.
- **Right to lodge a complaint** -- You may file a complaint with your local data protection authority.

Given that we do not deploy our own cookies, these rights are most relevant to any cookies set by GitHub Pages. For GitHub-related data requests, please contact GitHub directly.

### 6.3 Rights Under US Privacy Laws

Depending on your state of residence, you may have additional rights under state privacy laws (such as the California Consumer Privacy Act or similar legislation) including the right to know what personal information is collected, the right to delete it, and the right to opt out of the sale or sharing of personal information. We do not sell or share personal information collected through cookies.

## 7. Legal Basis for Processing (GDPR)

Where cookies process personal data, the legal basis depends on the type of cookie:

- **Strictly necessary cookies:** Legitimate interest (Article 6(1)(f) GDPR) -- these are essential for the website to function.
- **Non-essential cookies:** Consent (Article 6(1)(a) GDPR) -- we will obtain your consent before setting any non-essential cookies, should we introduce them in the future.

The app.soleur.ai session cookies (Supabase authentication, Stripe fraud prevention) are strictly necessary for the service the user explicitly requested -- authentication and secure payment processing. These cookies are exempt from consent requirements under Article 5(3) of the ePrivacy Directive (2002/58/EC, as amended by 2009/136/EC). We do not set non-essential cookies. If we introduce non-essential cookies in the future, we will implement an appropriate consent management mechanism before doing so, in compliance with Article 5(3).

**Note for UK users:** The UK Privacy and Electronic Communications Regulations 2003 (PECR) applies post-Brexit in place of the ePrivacy Directive. The same strictly necessary exemption applies under PECR Regulation 6.

## 8. Do Not Track Signals

Some browsers transmit "Do Not Track" (DNT) signals. While we use Plausible Analytics for cookie-free, privacy-respecting website analytics, Plausible does not track users across sites and does not respond to DNT signals because it has no cross-site tracking to disable. We honor the spirit of DNT by using analytics that collect no personally identifiable information.

## 9. Changes to This Cookie Policy

We may update this Cookie Policy from time to time to reflect changes in our practices, technology, or legal requirements. When we make material changes, we will update the "Last updated" date at the top of this policy. We encourage you to review this policy periodically.

If we introduce new categories of cookies (such as analytics or functional cookies), we will update this policy **before** deploying them and, where required by law, obtain your consent.

## 10. Legal Entity and Contact Us

Soleur is a source-available project maintained by Jikigai, a company incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France.

If you have questions about this Cookie Policy or our data practices, you can reach us through:

- **Email:** <legal@jikigai.com>
- **GitHub Repository:** [github.com/jikig-ai/soleur](https://github.com/jikig-ai/soleur)
- **Website:** [soleur.ai](https://soleur.ai)
- **GDPR / Data Protection Inquiries:** <legal@jikigai.com> (include "GDPR" in the subject line)

---

> **Related documents:** This Cookie Policy references data collection and privacy practices. Consider reviewing the companion [Privacy Policy](/legal/privacy-policy/) for comprehensive coverage of personal data handling, the [Terms & Conditions](/legal/terms-and-conditions/) for the governing law that applies to this policy, and the [GDPR Policy](/legal/gdpr-policy/) for EU/EEA-specific data protection obligations.

---

    </div>
  </div>
</section>
