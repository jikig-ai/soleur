---
title: "GDPR Policy"
description: "EU General Data Protection Regulation compliance for Soleur."
layout: base.njk
permalink: legal/gdpr-policy/
---

<section class="page-hero">
  <div class="container">
    <h1>GDPR Policy</h1>
    <p>Effective February 20, 2026 | Last Updated March 29, 2026</p>
  </div>
</section>

<section class="content">
  <div class="container">
    <div class="prose">

**Soleur -- Company-as-a-Service Platform**

**Effective Date:** February 20, 2026
**Last Updated:** March 29, 2026 (added conversation management to Section 3.7, added conversation data to Supabase row in Section 4.2, added conversation data retention to Section 8.4, added DPIA re-evaluation for conversation data to Section 9, added processing activity #10 to Article 30 register, added conversation data breach scenario to Section 11.2)

---

## 1. Introduction

This GDPR Policy explains how Jikigai ("we", "us", "our"), operator of Soleur, approaches data protection and privacy in compliance with the General Data Protection Regulation (EU) 2016/679 ("GDPR") and related European data protection legislation. Soleur is a Company-as-a-Service platform delivered as a Claude Code plugin, providing a full-stack AI organization with 63 agents, 62 skills, and a compounding knowledge base for solo founders and technical builders.

This policy applies to all individuals located in the European Economic Area ("EEA") who use or interact with Soleur, including the plugin software, Web Platform (app.soleur.ai), documentation site, and GitHub repository.

---

## 2. Data Controller and Processor Status

### 2.1 Soleur's Role

The Soleur **Plugin** operates as a **locally installed CLI extension**. All data generated, processed, and stored by the Plugin resides exclusively on the user's local machine. The Plugin does not collect, transmit, receive, or store any personal data on external servers.

As a result, **the Plugin does not act as a data processor** within the meaning of Article 4(8) of the GDPR with respect to user content, knowledge-base files, or any data created through the Plugin's operation.

Jikigai acts as a **data controller** for: (a) the documentation site hosted on GitHub Pages, where standard web server logs (IP addresses, browser metadata) are collected via GitHub's infrastructure, (b) the GitHub repository, where issue reports and contributions involve processing of GitHub profile data, and (c) the Soleur Web Platform (app.soleur.ai), where user account data, workspace data, and subscription data are processed on Jikigai-operated infrastructure via third-party processors (Supabase, Stripe, Hetzner, Cloudflare).

### 2.2 Third-Party Services

Users should be aware that interacting with Soleur may involve third-party services that have their own data controller or processor roles:

- **Anthropic (Claude API):** When users invoke Soleur agents and skills, requests are sent to Anthropic's Claude API using the user's own API key. Anthropic acts as an independent data controller or processor under its own terms and privacy policy. Soleur does not intermediate, intercept, or store any data exchanged between the user and Anthropic.
- **GitHub Pages (Documentation Site):** The Soleur documentation site at [soleur.ai](https://soleur.ai) is hosted on GitHub Pages. GitHub acts as a **data processor** for the hosting service, collecting IP addresses, browser metadata, and other standard web server logs on Jikigai's behalf. GitHub's processing is governed by the [GitHub Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) and the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement), which include GDPR compliance commitments. Note: GitHub's formal [Data Protection Agreement](https://github.com/customer-terms/github-data-protection-agreement) applies to paid plans (Enterprise Cloud, Teams) only; Jikigai's free-plan organization is covered by GitHub's standard terms, under which GitHub acknowledges processor obligations and maintains EU-US Data Privacy Framework certification and Standard Contractual Clauses.
- **GitHub (Repository):** Users who interact with the Soleur repository (issues, pull requests, discussions) do so under GitHub's terms and privacy policies. For repository interactions, GitHub and Jikigai act as independent controllers of the data involved in community participation.
- **Supabase (Web Platform):** The Soleur Web Platform uses Supabase for authentication and database services. Supabase acts as a **data processor** on Jikigai's behalf, processing email addresses, hashed passwords, authentication tokens, and session data. Supabase Inc is US-based, but the Jikigai project is deployed to **AWS eu-west-1 (Ireland, EU)** -- no international data transfers occur for Supabase-processed data. DPA signed 2026-03-19 via PandaDoc. See [Supabase DPA](https://supabase.com/legal/dpa).
- **Stripe (Web Platform):** The Soleur Web Platform uses Stripe for payment processing. Stripe acts as a **data processor** on Jikigai's behalf. The integration uses Stripe Checkout (PCI SAQ-A) -- card data is handled exclusively by Stripe and never reaches Jikigai servers. Stripe is PCI DSS Level 1 certified. International data transfers are governed by the EU-US Data Privacy Framework (DPF) and Standard Contractual Clauses (SCCs). See [Stripe DPA](https://stripe.com/legal/dpa).
- **Hetzner (Web Platform):** The Soleur Web Platform is hosted on Hetzner servers. Hetzner Online GmbH acts as a **data processor** on Jikigai's behalf. The Web Platform is hosted in Helsinki, Finland (EU) -- no international data transfers. DPA (AVV) concluded via the Hetzner Cloud Console (signed 2026-03-19).
- **Cloudflare (Web Platform):** The `app.soleur.ai` subdomain uses Cloudflare as a CDN and reverse proxy, extending the existing Cloudflare zone used for `soleur.ai`. International data transfers are governed by DPF, SCCs, and Global CBPR certification. See [Cloudflare DPA](https://www.cloudflare.com/cloudflare-customer-dpa/).

---

## 3. Lawful Basis for Processing

### 3.1 Plugin Operation (Local Processing)

Because Soleur processes all data locally on the user's device and does not transmit personal data to Soleur-controlled infrastructure, there is no personal data processing by Soleur that requires a lawful basis under Article 6 of the GDPR.

### 3.2 Documentation Site

To the extent that GitHub Pages collects data when users visit soleur.ai, the lawful basis is **legitimate interest** (Article 6(1)(f)) -- specifically, the interest in providing and maintaining accessible product documentation. Users are directed to GitHub's own privacy documentation for specifics on data collected by GitHub Pages.

For website analytics via Plausible Analytics, the lawful basis is **legitimate interest** (Article 6(1)(f)) -- understanding documentation traffic patterns to improve content and user experience. This processing is cookie-free, stores no personal data, and does not require consent under the ePrivacy Directive (Article 5(3) does not apply as no information is stored on or accessed from the user's device). See Section 4.3 for details.

### 3.3 Repository Interactions

For processing of GitHub profile data when users contribute to the Soleur repository (issues, pull requests, discussions), the lawful basis is **legitimate interest** (Article 6(1)(f)) -- facilitating community participation in the project. The balancing test considers: (a) the processing is limited to publicly available GitHub profile data voluntarily shared by the user, (b) the user initiated the interaction, (c) the processing is necessary for the stated purpose, and (d) users can withdraw by deleting their GitHub contributions.

### 3.4 Contributor License Agreement (CLA) Signatures

For processing of CLA signature data when contributors sign the Contributor License Agreement via GitHub pull requests, the lawful basis is **legitimate interest** (Article 6(1)(f)). The data processed consists of the contributor's GitHub username, signature timestamp, and associated pull request reference.

**Balancing test:** (1) Maintaining an enforceable record of contributor intellectual property license grants is a legitimate interest of the project maintainer, required to support dual licensing under the Business Source License 1.1. (2) The processing is limited to the minimum data necessary -- only the GitHub username (already public), timestamp, and PR reference are collected. No additional personal data is requested. (3) Contributors' rights are not overridden because they voluntarily initiate the process by submitting a pull request and explicitly consenting by posting the signing comment. Signature data is stored on a dedicated branch (`cla-signatures`) in the public repository. Retention is indefinite because the license grants are irrevocable; however, contributors may request deletion of their signature record, noting that the underlying license grant survives deletion per the CLA terms (Section 8(e)).

### 3.5 Legal and GDPR Inquiry Handling

For processing personal data contained in data subject rights requests and legal inquiries sent to <legal@jikigai.com>, the lawful basis is **legal obligation** (Article 6(1)(c)) for GDPR requests (fulfilling our obligations under Articles 12-22) and **legitimate interest** (Article 6(1)(f)) for other legal inquiries.

### 3.6 Newsletter Subscription

For processing of **email addresses** when visitors subscribe to the Soleur newsletter via the Docs Site, the lawful basis is **consent** (Article 6(1)(a)). Subscribers actively opt in by submitting the signup form and confirming their subscription via a double opt-in confirmation email sent by Buttondown. Consent may be withdrawn at any time by unsubscribing via the link included in every newsletter email. Upon withdrawal, the email address is removed from the active subscriber list.

For the **technical metadata** automatically collected by Buttondown during the subscription request (IP address, referrer URL, subscription timestamp, browser/device metadata), the lawful basis is **legitimate interest** (Article 6(1)(f)). The balancing test for this interest considers: (a) the data is minimal and limited to standard HTTP request metadata, (b) the processing is necessary for service delivery and abuse prevention, (c) the data is within the reasonable expectations of someone subscribing to a newsletter, and (d) the processing does not involve profiling or automated decision-making. Data subjects may object to this processing under Article 21 by contacting <legal@jikigai.com>.

### 3.7 Web Platform Service Delivery

For processing of account data, workspace data, and subscription data through the Soleur Web Platform (app.soleur.ai):

- **Account creation and management:** The lawful basis is **contract performance** (Article 6(1)(b)) -- processing is necessary to provide the Web Platform service the user signed up for. Data processed: email address, hashed password (managed by Supabase), authentication tokens, session cookies.
- **Payment processing:** The lawful basis is **contract performance** (Article 6(1)(b)) -- processing is necessary to fulfill the subscription agreement. Data processed: customer email, subscription metadata. Card data is handled exclusively by Stripe via Stripe Checkout (PCI SAQ-A) and never reaches Jikigai servers.
- **Infrastructure hosting:** The lawful basis is **contract performance** (Article 6(1)(b)) -- processing is necessary to provide workspace environments. Data processed: user workspaces, encrypted API keys (AES-256-GCM), Docker containers. Hosted on Hetzner in Helsinki, Finland (EU-only).
- **Conversation management:** The lawful basis is **contract performance** (Article 6(1)(b)) -- processing is necessary to provide the conversational AI service. Data processed: conversation metadata (domain leader, status, timestamps), message content (user messages, assistant responses, tool call metadata).
- **CDN/proxy processing:** For authenticated users, the lawful basis is **contract performance** (Article 6(1)(b)) -- Cloudflare processes requests as part of delivering the Web Platform service. For unauthenticated traffic (visitors who have not signed up), the lawful basis is **legitimate interest** (Article 6(1)(f)) -- operating CDN and DDoS protection for `app.soleur.ai` is necessary for infrastructure security and service availability (see also GDPR Recital 49). Data processed: IP addresses, request headers, TLS termination data. Processed by Cloudflare (see DPD Section 4.2).

A balancing test is not required for the contract performance basis used in account, payment, and infrastructure processing above. For the legitimate interest basis applied to unauthenticated CDN/proxy traffic, the balancing test considers: (a) the processing is limited to standard HTTP connection metadata (IP addresses, request headers), (b) operating CDN and DDoS protection is within the reasonable expectations of anyone visiting a web application, (c) Cloudflare does not use this data for profiling or advertising, and (d) the processing is necessary for infrastructure security and cannot be achieved without processing technical connection data from all visitors. Data subjects may object under Article 21 by contacting <legal@jikigai.com>.

<!-- Added 2026-04-10: KB sharing -->

### 3.8 Content Sharing

- **Share link management:** The lawful basis is **contract performance** (Article 6(1)(b)) -- processing is necessary to provide the sharing feature the user activated. Data processed: share link metadata (token, document path, creation timestamp, revocation status).
- **Shared page viewer access logs:** The lawful basis is **legitimate interest** (Article 6(1)(f)) -- infrastructure security and abuse prevention for publicly accessible share endpoints. Data processed: IP addresses, timestamps, user-agent strings. The balancing test considers: (a) processing is limited to standard server access log data, (b) no cookies or tracking are applied to shared page viewers, (c) the processing is necessary for rate limiting and abuse prevention on public endpoints. Data subjects may object under Article 21 by contacting <legal@jikigai.com>.

<!-- End: KB sharing -->

---

## 4. Categories of Personal Data

### 4.1 Data NOT Collected by Soleur

The Soleur **Plugin** does not collect, store, or process the following categories of personal data:

- Names or physical contact information
- Account credentials or authentication tokens
- IP addresses or device identifiers
- Location data
- Financial or payment information
- Content generated through the plugin (knowledge-base files, brainstorms, plans, code)

**Note:** The Docs Site collects email addresses from visitors who voluntarily subscribe to the newsletter (see Section 3.6). This data is processed by Buttondown, not by the Plugin.

### 4.2 Data That May Be Processed by Third Parties

The following data may be processed by third-party services when users interact with the broader Soleur ecosystem:

| Category | Third Party | Purpose |
|---|---|---|
| IP address, browser metadata | GitHub (via GitHub Pages) | Hosting documentation site |
| Prompts, code context | Anthropic (via Claude API) | Powering AI agent responses (user authenticates with own credentials) |
| GitHub account data | GitHub (via repository) | Issue tracking, contributions |
| Name, email, inquiry content | Proton AG (via Proton Mail) | Handling legal and GDPR inquiries (<legal@jikigai.com>) |
| GitHub username, signature timestamp, PR reference | GitHub (via CLA Assistant) | Recording CLA signature for contributor IP license grants |
| Email address, IP address, referrer URL, subscription timestamp, browser/device metadata | Buttondown (via newsletter signup) | Managing newsletter subscriptions and delivering newsletter emails |
| Email address, auth tokens, session data, conversation metadata, message content | Supabase (via Web Platform) | Account management, authentication, and conversation storage |
| OAuth provider user ID, display name, profile picture URL | Google, Apple, GitHub, Microsoft (via Web Platform OAuth sign-in) | Authentication and account linking (auto-link on verified email) |
| Customer email, subscription metadata | Stripe (via Web Platform Checkout) | Payment processing (card data handled by Stripe, never reaches Jikigai) |
| User workspaces, encrypted API keys | Hetzner (via Web Platform hosting) | Infrastructure hosting for workspace environments |
| IP addresses, request headers | Cloudflare (via `app.soleur.ai` proxy) | CDN/proxy and DDoS protection |

Users are responsible for reviewing the privacy policies of these third-party services.

### 4.3 Website Analytics Data

The Docs Site uses **Plausible Analytics** ([plausible.io](https://plausible.io)), a cookie-free, privacy-respecting analytics service. Plausible collects the following anonymous, aggregated data:

| Data Point | Storage | Purpose |
|------------|---------|---------|
| Page URL | Aggregated | Understanding which pages are visited |
| Referrer URL | Aggregated | Understanding how visitors find the site |
| Country | Derived from IP (IP not stored) | Geographic distribution |
| Device type | Aggregated | Desktop/mobile/tablet breakdown |
| Browser and OS | Aggregated | Technical compatibility |

**What Plausible does NOT collect:** IP addresses (discarded after geolocation), cookies, local storage, device fingerprints, cross-site tracking identifiers, or any personally identifiable information.

**Legal basis:** Legitimate interest (Article 6(1)(f) GDPR). The three-part test is satisfied: (1) understanding documentation traffic patterns is a legitimate interest of the website operator; (2) cookie-free analytics is the least intrusive means -- no personal data is stored, no cross-site tracking, no device fingerprinting; (3) users' rights are not overridden because no identifying information is collected or retained.

**ePrivacy Directive:** Article 5(3) of the ePrivacy Directive does not apply because Plausible does not store information on or access information from the user's device (no cookies, no local storage).

---

## 5. Data Subject Rights

Under the GDPR, data subjects in the EEA have the following rights. For data processed through the Web Platform (app.soleur.ai), these rights are exercisable directly against Jikigai (see Section 5.3). For newsletter subscriptions and CLA signatures, most rights are exercisable against the relevant third-party service providers or by unsubscribing from the newsletter:

### 5.1 Rights Exercisable Against Third Parties

- **Right of Access (Article 15):** Contact Anthropic or GitHub directly to request access to personal data they hold.
- **Right to Rectification (Article 16):** Contact the relevant third party to correct inaccurate personal data.
- **Right to Erasure (Article 17):** Request deletion of personal data from Anthropic or GitHub under applicable conditions.
- **Right to Restriction of Processing (Article 18):** Request that Anthropic or GitHub restrict processing of your data.
- **Right to Data Portability (Article 20):** Request your data in a portable format from the relevant third party.
- **Right to Object (Article 21):** Object to processing by the relevant third party.

### 5.2 Rights Exercisable Locally

- **Right to Erasure of Local Data:** Because all Soleur plugin data is stored on your local machine, you have full and immediate control over its deletion. Uninstalling the plugin and deleting the plugin directory removes all associated data.
- **Right to Access Local Data:** All knowledge-base files, plans, brainstorms, and other artifacts are stored as plaintext files on your filesystem and are fully accessible to you at all times.

### 5.3 Rights Exercisable Against Jikigai (Web Platform)

For data processed through the Web Platform (app.soleur.ai) where Jikigai acts as data controller (see Section 2.1), data subjects may exercise the following rights by contacting <legal@jikigai.com>:

- **Right of Access (Article 15):** Request confirmation of whether personal data is being processed and obtain a copy of the data (account data, workspace data, conversation data, subscription metadata).
- **Right to Rectification (Article 16):** Request correction of inaccurate personal data held by Jikigai.
- **Right to Erasure (Article 17):** Request deletion of personal data under applicable conditions. Note: payment records (subscription metadata, invoices) subject to French tax law retention (Code de commerce Art. L123-22) may be retained for up to 10 years (see Section 8.4).
- **Right to Restriction of Processing (Article 18):** Request that Jikigai restrict processing of personal data.
- **Right to Data Portability (Article 20):** Request personal data in a structured, commonly used, machine-readable format.
- **Right to Object (Article 21):** Object to processing of personal data. The legal basis for Web Platform processing is contract performance (Article 6(1)(b)), so this right applies primarily when processing extends beyond strict contractual necessity.

Jikigai will acknowledge requests within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3). This period may be extended by two further months where necessary, taking into account the complexity or volume of requests, in which case we will inform you of the extension and reasons within the initial one-month period.

### 5.4 Supervisory Authority

Data subjects have the right to lodge a complaint with a supervisory authority in the EU Member State of their habitual residence, place of work, or place of the alleged infringement. A list of EU Data Protection Authorities is available at [edpb.europa.eu](https://edpb.europa.eu/about-edpb/about-edpb/members_en).

---

## 6. International Data Transfers

The Soleur Plugin itself does not transfer personal data internationally. However, users should be aware of the following transfers:

**Web Platform (app.soleur.ai):**

- **Supabase:** EU-based deployment (AWS eu-west-1, Ireland). **No international data transfers.** Supabase Inc is US-based, but the Jikigai project is deployed to the EU region. See [Supabase DPA](https://supabase.com/legal/dpa).
- **Stripe:** US-based (Stripe, LLC). Transfer via EU-US Data Privacy Framework (DPF, adequacy decision) and Standard Contractual Clauses (SCCs), EEA Module 2. DPA auto-incorporated in Services Agreement (verified 2026-03-19). See [Stripe DPA](https://stripe.com/legal/dpa).
- **Hetzner:** EU-based (Germany). Web Platform hosted in Helsinki, Finland (EU). **No international data transfers.** DPA (AVV) signed 2026-03-19 via Cloud Console.
- **Cloudflare:** Global CDN. Transfer via EU-US Data Privacy Framework (DPF), Standard Contractual Clauses (SCCs), and Global CBPR certification. DPA self-executing via Self-Serve Agreement (verified 2026-03-19). See [Cloudflare DPA](https://www.cloudflare.com/cloudflare-customer-dpa/).

**Other services:**

- **Anthropic Claude API:** API requests may be processed in the United States or other jurisdictions where Anthropic operates. Users should review Anthropic's data processing terms regarding international transfer safeguards.
- **GitHub Pages / GitHub:** GitHub infrastructure is located globally, including in the United States. GitHub (Microsoft Corporation) is certified under the **EU-US Data Privacy Framework** (adequacy decision C(2023) 4745), which provides the primary transfer mechanism. GitHub also maintains Standard Contractual Clauses as a supplementary safeguard. See [GitHub's Global Privacy Practices](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement#githubs-global-privacy-practices).
- **Buttondown (Newsletter):** Buttondown is a US-based newsletter platform. Transfers of subscriber data (email addresses, IP addresses, referrer URL, subscription timestamps, browser/device metadata) from the EEA to the United States are governed by the **EU Standard Contractual Clauses** (European Commission Implementing Decision (EU) 2021/914, Module 2: Controller-to-Processor), incorporated by reference into Buttondown's [Data Processing Agreement](https://buttondown.com/legal/data-processing-agreement). Buttondown's DPA applies to all plan tiers, including the free tier. See also [Buttondown's Privacy Policy](https://buttondown.com/legal/privacy).

Users who are subject to the GDPR and have concerns about international data transfers should review the relevant third-party policies before using these services.

---

## 7. Data Security Measures

### 7.1 Local Security

Because Soleur operates entirely on the user's local machine:

- All data remains within the user's filesystem security perimeter.
- No data is transmitted to Soleur-controlled servers or cloud storage.
- Users are responsible for securing their own devices, including filesystem permissions, disk encryption, and access controls.
- API keys (e.g., Anthropic API keys) are managed locally by the user and are never collected or stored by Soleur.

### 7.2 Recommendations for Users

To maintain data protection when using Soleur, we recommend:

- Enabling full-disk encryption on your device.
- Using strong access controls for your user account.
- Keeping your API keys secure and rotating them periodically.
- Reviewing the security practices of third-party services (Anthropic, GitHub) before use.
- Not including sensitive personal data of third parties in knowledge-base files unless you have a lawful basis to do so.

---

## 8. Data Retention

### 8.1 Local Data

Soleur does not impose any retention period on locally stored data. Files persist on the user's machine until the user deletes them. Users have full control over the lifecycle of all locally stored artifacts.

### 8.2 Legal and GDPR Inquiry Correspondence

Personal data contained in data subject rights requests and legal inquiries (names, email addresses, inquiry content) is retained for the duration necessary to resolve the inquiry, plus three years to comply with the French civil statute of limitations (prescription civile). After this period, correspondence is securely deleted.

### 8.3 Newsletter Subscriber Data

Newsletter subscriber email addresses are retained by Buttondown for as long as the subscriber remains subscribed. Upon unsubscription, the email address is removed from the active subscriber list. Buttondown may retain anonymized aggregate data (e.g., subscriber counts) after unsubscription. Upon termination of the service relationship, Buttondown will, at Jikigai's option, delete or return all personal data in accordance with Buttondown's Data Processing Agreement.

### 8.4 Web Platform Data

Web Platform account data (email, hashed password, auth tokens) is retained while the account is active and deleted upon account deletion request. Conversation data (messages and conversation metadata) is retained while the account is active and deleted upon account deletion request (cascade delete via foreign key). Encrypted API keys are deleted with the associated workspace. Payment records (subscription metadata, invoices) are retained for 10 years per French tax law (Code de commerce Art. L123-22).

### 8.5 Third-Party Retention

Retention periods for data held by Anthropic and GitHub are governed by their respective privacy policies and data retention schedules.

---

## 9. Data Protection Impact Assessment (DPIA)

Jikigai's data processing now includes both the Docs Site (standard web hosting via GitHub Pages) and the Web Platform (app.soleur.ai). A formal DPIA under Article 35 of the GDPR has been evaluated and is **not required** for Jikigai's direct operations. The analysis:

- The Web Platform processes user PII (email addresses, hashed passwords, authentication tokens, encrypted API keys, subscription metadata, conversation metadata, and message content).
- The addition of conversation data (user messages, assistant responses, tool call metadata) as a new PII category does not change the DPIA conclusion. Conversation data does not constitute special categories (Article 9), does not involve systematic monitoring of individuals, and does not involve automated decision-making with legal effects.
- This processing does **not** meet the high-risk thresholds of Article 35(3): (a) no special categories of data (Article 9) are processed, (b) no systematic monitoring of individuals occurs, (c) no automated decision-making with legal effects is performed, and (d) processing is not at a scale that would trigger DPIA requirements for a pre-revenue SaaS with a small user base.
- Payment data (card numbers) is handled exclusively by Stripe and never reaches Jikigai servers (PCI SAQ-A).
- Infrastructure is hosted in the EU (Helsinki, Finland), reducing transfer risk.

This assessment will be revisited if processing activities expand significantly (e.g., large-scale user base, new data categories, automated profiling).

**Important for users:** If you use Soleur's AI agents to process personal data of third parties (e.g., including personal data in knowledge-base files, feeding personal data to the Anthropic API via agent prompts), **you** may be required to conduct a DPIA under Article 35. This is your responsibility as the data controller for locally processed data.

---

## 10. Record of Processing Activities (Article 30)

Jikigai maintains an internal record of processing activities as required by Article 30(1) of the GDPR. The SME exemption under Article 30(5) does not apply because, although Jikigai has fewer than 250 employees, the documentation site hosting constitutes non-occasional processing (continuous web hosting).

The register documents ten processing activities:

1. **Documentation website hosting** (soleur.ai via GitHub Pages) -- IP addresses, browser metadata of visitors
2. **Website analytics** (soleur.ai via Plausible Analytics) -- page URLs, referrer URLs, country (derived from IP, not stored), device type, browser type. Legal basis: legitimate interest (Article 6(1)(f)). No personal data is stored; IP addresses are discarded after geolocation. Plausible Analytics is hosted in the EU.
3. **Source repository management** (GitHub) -- contributor profile data, issue reporters
4. **Legal and GDPR inquiry handling** (<legal@jikigai.com>) -- names, email addresses, inquiry content
5. **CLA signature collection** (GitHub CLA Assistant) -- GitHub username, signature timestamp, pull request reference. Legal basis: legitimate interest (Article 6(1)(f)). Signature data is stored on the `cla-signatures` branch in the public repository. Retention is indefinite (irrevocable license grants).
6. **Newsletter subscription management** (soleur.ai via Buttondown) -- (a) email addresses of newsletter subscribers, legal basis: consent (Article 6(1)(a)), verified through double opt-in; (b) IP address, referrer URL, subscription timestamp, and browser/device metadata automatically collected during subscription, legal basis: legitimate interest (Article 6(1)(f)) for service operation and abuse prevention. Data is processed by Buttondown (US-based). International transfers governed by EU Standard Contractual Clauses (Implementing Decision (EU) 2021/914, Module 2: Controller-to-Processor), incorporated into Buttondown's [DPA](https://buttondown.com/legal/data-processing-agreement). DPA applies to all plan tiers including free. Buttondown's sub-processor list is maintained at [buttondown.com/legal/subprocessors](https://buttondown.com/legal/subprocessors). Email retention: until the subscriber unsubscribes. Technical metadata retention: governed by Buttondown's data retention practices.
7. **Web Platform account management** (app.soleur.ai via Supabase) -- email addresses, hashed passwords (managed by Supabase), authentication tokens (JWT), session data. Legal basis: contract performance (Article 6(1)(b)). Data is processed by Supabase Inc (US-based company; project deployed to AWS eu-west-1, Ireland, EU -- no international data transfer). Retention: while account is active; deleted on account deletion request.
8. **Web Platform payment processing** (app.soleur.ai via Stripe Checkout) -- customer email, subscription metadata. Card data is processed exclusively by Stripe (PCI DSS Level 1, SAQ-A integration) and never reaches Jikigai servers. Legal basis: contract performance (Article 6(1)(b)). Data is processed by Stripe Inc (US-based, DPF + SCCs). Retention: subscription records retained for 10 years per French tax law (Code de commerce Art. L123-22).
9. **Web Platform infrastructure hosting** (app.soleur.ai via Hetzner (Helsinki, Finland, EU)) -- user workspaces, encrypted API keys (AES-256-GCM), Docker containers. Legal basis: contract performance (Article 6(1)(b)). Data is processed by Hetzner Online GmbH (EU-based, no international transfer). Retention: while account is active.
10. **Web Platform conversation management** (app.soleur.ai via Supabase) -- conversation metadata (domain leader, status, timestamps) and message content (user messages, assistant responses, tool call metadata). Legal basis: contract performance (Article 6(1)(b)). Data is processed by Supabase Inc (project deployed to AWS eu-west-1, Ireland, EU -- no international data transfer). Retention: while account is active; deleted on account deletion request.

The register is maintained internally and is available on request to the competent supervisory authority (CNIL for France). Since the 2018 reform of the Loi Informatique et Libertes, no registration or prior declaration to the CNIL is required.

---

## 11. Data Breach Notification

### 11.1 Controller Obligations

In the event of a personal data breach affecting data for which Jikigai acts as controller, Jikigai will:

- Notify the competent supervisory authority (CNIL) without undue delay and, where feasible, within 72 hours of becoming aware of the breach, as required by Article 33 GDPR, unless the breach is unlikely to result in a risk to the rights and freedoms of natural persons.
- Where the breach is likely to result in a high risk to the rights and freedoms of natural persons, notify the affected data subjects without undue delay, as required by Article 34 GDPR.

### 11.2 Practical Context

The most likely breach scenarios include: (a) unauthorized access to the Supabase database (user account data), (b) compromise of the Hetzner server (workspace data, encrypted API keys), (c) unauthorized access to Proton AG (Proton Mail, handling <legal@jikigai.com>), (d) a compromise of the GitHub organization, or (e) unauthorized access to conversation history stored in the Supabase database (user messages, assistant responses). In all cases, the third-party provider would typically be the first to detect and communicate the breach. Jikigai would assess the impact on Web Platform user data and notify affected users as required by Articles 33-34.

---

## 12. Children's Data

Soleur is designed for professional use by solo founders and technical builders. It is not directed at children under the age of 16. We do not knowingly collect personal data from children. The only personal data collected by the Docs Site is email addresses voluntarily provided by newsletter subscribers, and no specific age-verification mechanism is implemented for this collection beyond the double opt-in confirmation process.

---

## 13. Changes to This Policy

We may update this GDPR Policy from time to time to reflect changes in our practices, third-party services, or applicable law. Updates will be published in the Soleur GitHub repository at [github.com/jikig-ai/soleur](https://github.com/jikig-ai/soleur) and, where significant, noted in the project changelog.

We encourage users to review this policy periodically.

---

## 14. Contact Information

For questions about this GDPR Policy or data protection matters:

- **Email:** <legal@jikigai.com>
- **GitHub Repository:** [github.com/jikig-ai/soleur](https://github.com/jikig-ai/soleur) (open an issue)
- **Website:** [soleur.ai](https://soleur.ai)
- **GDPR / Data Protection Inquiries:** <legal@jikigai.com> (include "GDPR" in the subject line)

To exercise your data subject rights under GDPR, send a written request to <legal@jikigai.com>. We will acknowledge your request within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3). This period may be extended by two further months where necessary, taking into account the complexity or volume of requests, in which case we will inform you of the extension and reasons within the initial one-month period.

Soleur is a source-available project maintained by Jikigai, a company incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France.

Jikigai's data processing (standard web hosting, community repository interactions, and Web Platform account/payment/workspace management) does not meet the thresholds requiring a Data Protection Officer (DPO) under Article 37 of the GDPR: the processing is not core business activity involving regular and systematic monitoring of data subjects at large scale, nor does it involve large-scale processing of special categories of data. The Web Platform processes user account data but at a scale consistent with a pre-revenue SaaS and does not involve profiling or monitoring. Accordingly, no DPO has been appointed. Should this assessment change (e.g., significant user base growth), DPO contact information will be added to this policy.

---

## 15. Governing Law

This GDPR Policy shall be governed by and construed in accordance with the laws of France, without regard to its conflict of laws provisions. Any disputes arising under or in connection with this Policy shall be subject to the exclusive jurisdiction of the courts of Paris, France. If you are a consumer in the EU/EEA, nothing in this Policy affects your rights under mandatory EU or member state consumer protection laws, including your right to bring proceedings in the courts of your country of habitual residence.

---

> **Related documents:** This GDPR Policy should be read alongside the companion [Privacy Policy](/legal/privacy-policy/) for broader privacy disclosures, the [Cookie Policy](/legal/cookie-policy/) for information about cookies used by the documentation site, and the [Individual CLA](/legal/individual-cla/) and [Corporate CLA](/legal/corporate-cla/) for contributor license terms.

    </div>
  </div>
</section>
