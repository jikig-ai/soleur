---
title: "Privacy Policy"
type: privacy-policy
jurisdiction: FR, EU
generated-date: 2026-02-20
---

# Privacy Policy

**Effective Date:** February 20, 2026
**Last Updated:** May 18, 2026 (added Section 8.3 "Automated decision-making and Article 22 rights" disclosing the Web Platform's agent-runtime scope grants and human-review affordance; scoped the Buttondown-newsletter "does not involve profiling or automated decision-making" line to that processor only; previous: May 16, 2026 extended Section 4.5 with the off-site Cloudflare R2 evidence archive for CLA signatures and added Section 5.11 Cloudflare R2 sub-processor entry per #3209)

## 1. Introduction

This Privacy Policy describes how Jikigai ("we," "us," or "our"), operator of Soleur, handles information in connection with the Soleur Company-as-a-Service platform ("the Plugin"), a Claude Code plugin providing agents, skills, commands, and a knowledge base for structured software development workflows, the Soleur documentation website located at soleur.ai ("the Docs Site"), and the Soleur Web Platform at [app.soleur.ai](https://app.soleur.ai) ("the Web Platform").

We are committed to protecting your privacy. This Policy explains what data is and is not collected, how the Plugin operates, and your rights under applicable law, including the EU General Data Protection Regulation (GDPR) and US privacy regulations.

## 2. Who We Are

**Soleur** is a source-available project maintained by **Jikigai**, a company incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France. Jikigai is the data controller for the processing activities described in this Policy.

The Soleur source code is available at the GitHub repository [jikig-ai/soleur](https://github.com/jikig-ai/soleur).

For privacy inquiries, you may contact us at <legal@jikigai.com> (include "Privacy" in the subject line), by opening an issue on the GitHub repository, or through the website at [soleur.ai](https://soleur.ai).

## 3. What the Plugin Does

Soleur is a locally installed Claude Code plugin. It provides 45 AI agents, 45 skills, and a compounding knowledge base to support structured software development workflows. The Plugin is installed via the Claude Code CLI and runs entirely on your local machine.

## 4. Data We Collect

### 4.1 Data Collected by the Plugin: None

The Soleur **Plugin** (the locally installed Claude Code extension) **does not collect, transmit, or store any personal data on external servers**. Specifically:

- The Plugin runs entirely on your local machine.
- All knowledge-base files -- including plans, brainstorms, specifications, and learnings -- are stored exclusively on your local filesystem.
- The Plugin does not phone home, send telemetry, or transmit analytics to Jikigai-operated servers.
- We do not have access to your files, your code, or your usage patterns.

This section applies to the Plugin only. For data collected by the Soleur Web Platform (app.soleur.ai), see Section 4.7 below.

### 4.2 Data Processed Locally

The Plugin creates and manages files on your local filesystem as part of its normal operation. These may include:

- **Knowledge-base files:** Plans, brainstorms, specs, learnings, and other structured documents stored in the `knowledge-base/` directory.
- **Configuration files:** Plugin settings and workflow state stored locally.
- **Git artifacts:** Branches, commits, and worktrees created as part of development workflows.

All of this data remains on your machine. We have no access to it.

### 4.3 Data Collected by the Docs Site

The Soleur documentation site at [soleur.ai](https://soleur.ai) is hosted on **GitHub Pages**. We use **Plausible Analytics** ([plausible.io](https://plausible.io)) for privacy-respecting website analytics. Plausible does not use cookies, local storage, or fingerprinting. It collects the following anonymous, aggregated data:

- Page URLs visited
- Referrer URLs (how visitors find the site)
- Country (derived from IP address, which is not stored)
- Device type (desktop, mobile, tablet)
- Browser and operating system

IP addresses are used only for country-level geolocation and are **not stored** by Plausible. No personally identifiable information is collected or retained by Plausible. The legal basis for this processing is **legitimate interest** (Article 6(1)(f) GDPR) -- understanding website traffic to improve documentation.

Additionally, GitHub, as the hosting provider, may collect certain technical data when you visit the Docs Site, including IP addresses, browser metadata, and page request data. This data collection is governed by [GitHub's Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). We do not control or have direct access to data collected by GitHub.

### 4.4 Data Collected by the GitHub Repository

If you interact with the Soleur GitHub repository (e.g., opening issues, submitting pull requests, starring the repository), GitHub collects data in accordance with its own privacy policies. This is standard GitHub platform behavior and is not controlled by Soleur.

### 4.5 Data Collected Through the Contributor License Agreement (CLA)

If you contribute code to the Soleur project via pull requests, you are asked to sign a Contributor License Agreement (CLA) through the CLA Assistant integrated into the GitHub repository. When you sign the CLA, the following data is collected and stored:

- **GitHub username** (used to identify the signer)
- **Timestamp** of signature
- **Pull request reference** associated with the signing event

This data is stored in the Soleur GitHub repository on a dedicated branch (`cla-signatures`) and is publicly visible. In addition, an off-site **CLA evidence archive** is maintained at a Cloudflare R2 bucket (`soleur-cla-evidence`, region `weur` -- Western Europe) with R2 Lock Rules age-based retention and a ten (10) year floor providing write-once-read-many (WORM) semantics; the bucket contains a content-addressed record per signature (doc-hash, verbatim sign-comment body, PR-of-record, signed_at, capture_method) plus a monthly RFC 3161 timestamp of the bucket manifest (FreeTSA) to provide tamper-evidence over time. The legal basis for this processing is **legitimate interest** (Article 6(1)(f) GDPR) -- specifically, the legitimate interest of Jikigai in maintaining an enforceable record of contributor IP license grants to protect the integrity of the Soleur project's licensing framework, including for the establishment, exercise, and defense of legal claims under Article 17(3)(e).

**Retention:** CLA signature data is retained for ten (10) years on the off-site archive (R2 Lock Rules age-based retention, EU region), balancing GDPR proportionality against the German and UK statutory limitation periods for copyright disputes. The public `cla-signatures` branch is retained indefinitely as a contributor-facing receipt. The license grants in the CLA are irrevocable and survive any withdrawal of the signature record. If you exercise your right to erasure under GDPR Article 17, your signature record on the public branch may be deleted, and the off-site archive object may be removed via an administrator override that writes a permanent tombstone (`tombstones/<sha>.deleted.json`) included in the next monthly RFC 3161 manifest -- preserving the integrity of the timestamp chain. The license grants made under the CLA continue in full effect for all contributions made prior to deletion, as stated in the CLA itself.

### 4.6 Newsletter Subscription Data

If you subscribe to the Soleur newsletter via the signup form on the Docs Site, we collect your **email address** for the purpose of sending periodic newsletter emails. This data is processed by **Buttondown** ([buttondown.com](https://buttondown.com)), a third-party newsletter platform, on our behalf.

- **Data collected:** Email address (actively provided by you); IP address, referrer URL, subscription timestamp, and browser/device metadata (automatically collected by Buttondown during the subscription request).
- **Purpose:** Sending periodic newsletter emails about Soleur updates, features, and content.
- **Lawful basis (email address):** Consent (Article 6(1)(a) GDPR) -- you actively opt in by submitting the signup form and confirming your subscription via the double opt-in confirmation email.
- **Lawful basis (technical metadata):** Legitimate interest (Article 6(1)(f) GDPR) -- Buttondown automatically collects IP address, referrer URL, subscription timestamp, and browser/device metadata as part of standard service operation. This data is necessary for service delivery, abuse prevention, and maintaining the security of the newsletter infrastructure. The processing is minimal, within the reasonable expectations of a newsletter subscriber, and Buttondown's processing of this technical metadata does not itself involve profiling or automated decision-making concerning you. (For Web Platform agent-runtime automated decisions, see Section 8.3.) You may object to this processing under Article 21 by contacting us at <legal@jikigai.com>.
- **Double opt-in:** After submitting your email, Buttondown sends a confirmation email. Your subscription is only activated after you click the confirmation link. This ensures informed, verified consent.
- **Retention (email address):** Your email address is retained by Buttondown until you unsubscribe. You can unsubscribe at any time via the link in every newsletter email. Upon unsubscription, your email is removed from the active subscriber list.
- **Retention (technical metadata):** Governed by Buttondown's data retention practices. See [Buttondown's Privacy Policy](https://buttondown.com/legal/privacy) for details.
- **Third-party processor:** Buttondown acts as a data processor. See Section 5.3 for details.

### 4.7 Data Collected by the Web Platform

The Soleur Web Platform at [app.soleur.ai](https://app.soleur.ai) is a cloud-hosted service operated by Jikigai. Unlike the Plugin (Section 4.1), the Web Platform processes personal data on Jikigai-operated infrastructure. The following data is collected when you use the Web Platform:

- **Account data:** Email address (registration), authentication tokens, and session cookies. If you sign in via an OAuth provider (Google, Apple, GitHub, or Microsoft), we also receive your provider user ID, display name, and profile picture URL from the provider. Accounts with matching verified email addresses are automatically linked.
- **Workspace data:** User workspaces (the `/workspaces/<your-id>/` directory on our infrastructure, containing files generated during your sessions) and encrypted API keys (BYOK -- bring your own key). API keys are encrypted using AES-256-GCM before storage.
- **Team / agent customisation data:** Custom display names you assign to AI agent roles (`team_names`), if any. Used to personalise the interface across your conversations.
- **Subscription data:** Subscription status and billing metadata (managed by Stripe). Card data is handled exclusively by Stripe via Stripe Checkout and never reaches Jikigai servers (PCI SAQ-A). Stripe customer ID and subscription ID are stored on your user record so we can reconcile billing events; Stripe is an independent controller for the card data itself (see Section 5.6).
- **Conversation data:** Conversation metadata (domain leader, status, timestamps) and message content (user messages, assistant responses, tool call metadata) stored in the Supabase database. Conversations are associated with the user's account via user_id. **Partial assistant outputs from aborted turns** -- assistant text generated before a user-initiated Stop or an involuntary client disconnect -- are preserved in the same conversation history with an "aborted" status marker, the token cost of the partial turn, and the list of completed actions. The purpose is to give you a faithful record of what the Service produced (and billed against your usage) on your behalf. Partial-turn rows are retained for the same period as the parent conversation (see the retention paragraph immediately below this list, and Section 7 for the overall retention policy) unless you exercise your erasure right under Section 8.1. See Section 5.5 of the [Terms & Conditions](./terms-and-conditions.md) for the consumption terms that govern partial-turn billing and side effects; your erasure rights (GDPR Article 17) under Section 8.1 below apply equally to partial-turn rows. In rare cases of unexpected service interruption (e.g., kernel-level process termination or container restart) after generation but before persistence completes, a small portion of an in-progress reply may not be retained in the conversation record.
- **Per-turn cost telemetry (Concierge surface):** On conversations handled by the Concierge code path (the `/soleur:go` surface), each completed assistant turn is annotated with a small `usage` record attached to the message row. On this surface the record is **deliberately narrowed to a single numeric field -- the turn's cost in US dollars** (`{ cost_usd: <number> }`); token counts are not persisted on completed Concierge turns, in line with the data-minimisation principle (Article 5(1)(c) GDPR). The legacy single-leader chat surface continues to persist the wider snapshot already described in the preceding bullet (input tokens, output tokens, cost, and completed-action list) on aborted turns only. The purposes of the cost field are: (i) subscription cost accounting; (ii) per-user usage observability via the in-product `/api/usage` aggregator; and (iii) operator-side resolution of cost-cap-related billing inquiries. The legal basis, recipients, hosting region, technical and organisational measures, and retention period are the same as the parent conversation row: Article 6(1)(b) GDPR (contract performance); processed by Supabase (eu-west-1, Ireland) on Hetzner-hosted infrastructure (hel1, Finland); no new third-party recipients; protected by Supabase Row-Level Security gated on `conversation_id` ownership and a service-role write boundary enforced by the cc-dispatcher `assertWriteScope` sentinel; cascade-deleted on account deletion via foreign key (`ON DELETE CASCADE`).
- **Message attachments:** Files you upload to a conversation (images, PDFs, etc.) are stored as binaries in our Storage bucket (`chat-attachments/<your-id>/<conversation-id>/`); a row in `message_attachments` records the file metadata (filename, content type, size). Attachments are retained for the life of the parent message and deleted by cascade when the conversation, message, or your account is deleted.
- **BYOK usage audit log:** For every Anthropic API call we facilitate on your behalf, we log an append-only audit row (`audit_byok_use`) containing the invocation ID, your user ID, the agent role, the token count, and the per-call unit cost. This log is the source of truth for usage display and cost reconciliation; it cannot be edited or deleted by service operators (WORM trigger). Retained for 24 months, then deleted by automated cron job.
- **Technical data:** IP addresses and request headers processed by Cloudflare CDN/proxy.

**Right of access / portability (Articles 15 + 20):** You can request a self-serve export of the data classes enumerated above from `/dashboard/settings/privacy` on the Web Platform; the bundle is delivered by email as a ZIP archive and is bound to the requesting session and network for 7 days. See Section 8.1 below for the full mechanism and the email fallback.

<!-- 2026-05-12: Article 13(3) prior-disclosure refresh for messages.usage column (PR #3603 / PR-A2 #3648). CC_PERSIST_USAGE=true active in prd. -->

**Purpose:** Providing the Web Platform service, including account management, workspace provisioning, subscription billing, and conversational AI interactions with domain-specific agents.

**Legal basis:** Contract performance (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service you signed up for.

**Retention:** Account data is retained while your account is active and deleted upon account deletion request. Conversation data is retained while the account is active and deleted upon account deletion request (cascade delete via foreign key). Payment records are retained per French tax law (10 years, Code de commerce Art. L123-22).

<!-- Added 2026-04-10: KB sharing -->

### 4.8 Content Sharing (Knowledge Base Document Sharing)

The Web Platform allows authenticated users to share individual knowledge base documents via public links. When a document is shared:

- **Data shared publicly:** The document content is accessible to anyone with the share link. Shared pages include `noindex` meta tags and are not indexed by search engines. No cookies are set for unauthenticated viewers, and the CTA banner on shared pages collects no data (it links to the signup page only).
- **Viewer data collected:** For unauthenticated viewers accessing a shared link, only standard **server access logs** are collected (IP address, timestamp, user-agent). These logs are processed by Cloudflare (see Section 5.8) and the hosting infrastructure (see Section 5.7) as part of normal request handling. No additional tracking or analytics is applied to shared page viewers.
- **Share link records:** The Web Platform stores metadata about active share links (document ID, sharing user ID, creation timestamp, share token) in the Supabase database. These records are retained while the share link is active and deleted when the owner revokes the link or deletes their account (cascade delete).
- **Legal basis:** Legitimate interest (Article 6(1)(f) GDPR) for processing viewer access logs (infrastructure security and abuse prevention). Contract performance (Article 6(1)(b) GDPR) for maintaining share link records (providing the sharing feature the user activated).
- **Revocation:** The document owner can revoke a share link at any time, which takes immediate effect. After revocation, the shared URL returns an error and the document content is no longer accessible. However, Jikigai cannot guarantee that recipients have not copied or redistributed the content prior to revocation.

<!-- End: KB sharing -->

<!-- Added 2026-04-13: Push notifications -->

### 4.9 Push Notification Subscriptions

When you enable push notifications on the Web Platform, we store your push subscription data:

- **Data collected:** Push subscription endpoint URL, encryption keys (p256dh, auth), and timestamps (created, last used). This data is associated with your user account.
- **Purpose:** Delivering browser push notifications when an AI agent requires your input (review gate events) and you are not actively connected to the Web Platform.
- **Legal basis:** Consent (Article 6(1)(a) GDPR) -- push subscriptions are created only after you explicitly grant notification permission via the browser's permission prompt.
- **Retention:** Push subscription data is retained while your account is active. Expired or invalid subscriptions (HTTP 410 Gone) are deleted automatically. All subscription data is deleted upon account deletion (cascade delete via foreign key).
- **Withdrawal:** You can revoke notification permission at any time through your browser's settings, which prevents new notifications. You can also remove stored subscriptions by disabling notifications in your browser.

<!-- End: Push notifications -->

## 5. Third-Party Services

### 5.1 Anthropic Claude API

The Soleur Plugin is designed to work with the Anthropic Claude API through the Claude Code CLI. When you use the Plugin:

- **You** connect to the Anthropic API using **your own API key**.
- Data sent to the Anthropic API (such as prompts, code context, and file contents) is transmitted directly between your machine and Anthropic's servers.
- Soleur does not intermediate, intercept, or store any data exchanged between you and Anthropic.
- Anthropic's handling of your data is governed by [Anthropic's Privacy Policy](https://www.anthropic.com/privacy) and their Terms of Service.

### 5.2 GitHub

- The Plugin source code is hosted on GitHub.
- The Docs Site is hosted on GitHub Pages.
- GitHub's data practices are governed by [GitHub's Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

### 5.3 Buttondown (Newsletter)

We use **Buttondown** ([buttondown.com](https://buttondown.com)) to manage newsletter subscriptions and deliver newsletter emails. When you subscribe to our newsletter, your email address is transmitted to and stored by Buttondown. Buttondown also automatically collects technical metadata during the subscription request, including IP address, referrer URL, subscription timestamp, and browser/device metadata. Buttondown acts as a data processor on our behalf.

- Buttondown's privacy practices are governed by [Buttondown's Privacy Policy](https://buttondown.com/legal/privacy).
- Buttondown uses sub-processors for service delivery; the current list is maintained at [buttondown.com/legal/subprocessors](https://buttondown.com/legal/subprocessors).
- Buttondown is a US-based service. International data transfers are governed by the **EU Standard Contractual Clauses** (European Commission Implementing Decision (EU) 2021/914, Module 2: Controller-to-Processor), incorporated by reference into Buttondown's Data Processing Agreement.
- Buttondown's DPA applies to all plan tiers, including the free tier.
- Buttondown does not share subscriber data with third parties for advertising or marketing purposes.

### 5.4 Other Third-Party Integrations

The Plugin may interact with other third-party tools and APIs as part of your development workflow (e.g., MCP servers, browser automation tools). These interactions are initiated by you, configured by you, and use your own credentials. Soleur does not control or monitor these interactions.

### 5.5 Supabase (Web Platform Authentication and Database)

We use **Supabase** ([supabase.com](https://supabase.com)) as the authentication and database provider for the Web Platform. Supabase Inc acts as a data processor on our behalf.

- **Data processed:** Email addresses, hashed passwords, authentication tokens, and session data.
- **Purpose:** User account management, authentication, and session handling for the Web Platform.
- **DPA:** [Supabase Data Processing Agreement](https://supabase.com/legal/dpa). DPA signed 2026-03-19 via PandaDoc.
- The Jikigai Supabase project is deployed to **AWS eu-west-1 (Ireland, EU)**. No international data transfers occur for Supabase-processed data.

### 5.6 Stripe (Web Platform Payments)

We use **Stripe** ([stripe.com](https://stripe.com)) for payment processing on the Web Platform. Stripe Inc acts as a data processor on our behalf.

- **Data processed:** Customer email address and subscription metadata. Card data is handled exclusively by Stripe via Stripe Checkout and never reaches Jikigai servers (PCI SAQ-A).
- **Purpose:** Subscription billing and payment processing for the Web Platform.
- **DPA:** [Stripe Data Processing Agreement](https://stripe.com/legal/dpa) (incorporated into the Stripe Services Agreement automatically).
- Stripe is PCI DSS Level 1 certified. Jikigai's integration uses Stripe Checkout (server-side session creation, client-side redirect), which qualifies for PCI SAQ-A (simplest self-assessment).
- Stripe is a US-based service. International data transfers are covered by the EU-US Data Privacy Framework (DPF) and Standard Contractual Clauses (SCCs), EEA Module 2.

### 5.7 Hetzner (Web Platform Infrastructure Hosting)

We use **Hetzner** ([hetzner.com](https://hetzner.com)) to host the Web Platform infrastructure. Hetzner Online GmbH acts as a data processor on our behalf.

- **Data processed:** User workspaces, Docker containers, and encrypted API keys stored on Hetzner servers.
- **Purpose:** Infrastructure hosting for the Web Platform (compute, storage, networking).
- **DPA:** Hetzner Data Processing Agreement (Auftragsverarbeitungsvertrag / AVV), concluded via the Hetzner Cloud Console account settings (signed 2026-03-19).
- Hetzner is an EU-based company (Germany). The Web Platform is hosted in **Helsinki, Finland (EU)** -- EU-only processing, no international data transfers.

### 5.8 Cloudflare (Web Platform CDN/Proxy)

The Web Platform at `app.soleur.ai` uses **Cloudflare** ([cloudflare.com](https://cloudflare.com)) as a CDN and reverse proxy, extending the existing Cloudflare zone used for `soleur.ai`.

- **Data processed:** IP addresses, request headers, and TLS termination data.
- **Purpose:** CDN, DDoS protection, and DNS resolution for the Web Platform.
- **DPA:** [Cloudflare Customer Data Processing Agreement](https://www.cloudflare.com/cloudflare-customer-dpa/).
- Cloudflare uses the EU-US Data Privacy Framework (DPF), Standard Contractual Clauses (SCCs), and Global CBPR certification for international data transfers.

### 5.9 Resend (Web Platform Transactional Email)

We use **Resend** ([resend.com](https://resend.com)) to send transactional email notifications from the Web Platform. Resend Inc acts as a data processor on our behalf.

- **Data processed:** Recipient email address, email subject, and email body content (review gate notification summaries).
- **Purpose:** Sending email notifications when an AI agent requires user input and the user has no active push notification subscriptions.
- **DPA:** [Resend Data Processing Agreement](https://resend.com/legal/dpa) (incorporated into the Terms of Service, Section 7: Data Processing, automatically applicable).
- Resend is a US-based service. International data transfers are covered by the EU-US Data Privacy Framework (DPF) and Standard Contractual Clauses (SCCs).
- **Legal basis:** Legitimate interest (Article 6(1)(f) GDPR) -- transactional notifications are necessary to inform users of pending decisions that block AI agent progress, which is core to the service functionality.

### 5.10 Sentry (Web Platform Error Monitoring and Breach Detection)

We use **Sentry** ([sentry.io](https://sentry.io)) for Web Platform error monitoring and breach detection. Functional Software GmbH acts as a data processor on our behalf.

- **Data processed:** Error messages, stack traces, request metadata (URL paths, HTTP headers, navigation breadcrumbs), and a pseudonymous user identifier (`userIdHash`). The Sentry SDK on the server and client emits this data when an unexpected error or noteworthy breadcrumb event occurs.
- **Pseudonymisation:** User identifiers are pseudonymised at the emission boundary by replacing the raw `userId` with a keyed cryptographic hash (`userIdHash`) using a server-resident secret pepper. Under GDPR Recital 26, the controller cannot re-identify a data subject from the hash alone without the pepper.
- **Purpose:** Detecting, diagnosing, and responding to service errors and security incidents; meeting the Article 33 breach-notification timeline. The processing surface is the Soleur Web Platform (app.soleur.ai) only.
- **DPA:** [Sentry Sub-processors](https://sentry.io/legal/dpa/) (Sentry's standard EU-region terms; SCCs incorporated).
- Sentry processes data in the DE region (Frankfurt, Germany). **Intra-EU processing -- no third-country transfer.** SCCs apply as belt-and-braces against any future routing change.
- **Retention:** Sentry events retained for 90 days (rolling). Operational logs on the Web Platform infrastructure (pino stdout) are retained in a fixed-capacity Hetzner-local rolling buffer with no off-host copies (see DPD §2.3(m)).
- **Legal basis:** Dual basis. **Legitimate interest** (Article 6(1)(f) GDPR) for service reliability, security, and abuse prevention, balanced against the pseudonymisation safeguard; together with **legal obligation** (Article 6(1)(c) GDPR) for compliance with the Article 33 breach-notification timeline.
- **Right to erasure (Article 17):** Hashed identifiers age out per the rolling retention windows; the controller cannot perform processor-side targeted erasure of a pseudonym whose subject cannot be re-identified, consistent with Recital 26.
- **Sentry monitor classes processed:** issue alerts and cron monitor check-ins (vendor-hosted heartbeat for scheduled GitHub Actions jobs). Both carry no application log content -- only structural metadata (job slug, status, timestamp, pseudonymous identifier where applicable). **Sentry log ingestion (Logs product) is NOT enabled and no application log content is forwarded to Sentry.** A future change introducing a Sentry log channel requires re-disclosure here and an extension of the scrub boundary at `apps/web-platform/server/sentry-scrub.ts`.

### 5.11 Cloudflare R2 (CLA Evidence Archive)

We use **Cloudflare R2** ([cloudflare.com/products/r2](https://www.cloudflare.com/products/r2/)) to operate the off-site CLA evidence archive described in Section 4.5. Cloudflare, Inc. acts as a data processor on our behalf for this distinct processing surface, separate from the Section 5.8 Cloudflare CDN/proxy role.

- **Data processed:** Per-signature evidence records (GitHub username, signature timestamp, signing-comment body, pull request reference, doc-hash, and capture method) plus monthly RFC 3161 timestamp responses derived from the bucket manifest. Bypass records for allowlisted bot accounts (`dependabot[bot]`, `renovate[bot]`, `claude[bot]`) are also recorded; the upstream CLA action filters `github-actions[bot]` (DB-id 41898282) before any record is written.
- **Purpose:** Tamper-evident off-site archive supporting the legitimate-interest basis in Section 4.5 -- defense of legal claims regarding contributor IP grants under Article 17(3)(e).
- **Storage location:** Cloudflare R2 bucket `soleur-cla-evidence`, region `weur` (Western Europe). Intra-EU processing -- no third-country transfer for archive contents at rest.
- **Object Lock:** Governance mode with a ten (10) year retention floor. Administrator override is permitted only via the GDPR Article 17 admin-override procedure documented in the operations runbook; every override writes a permanent tombstone (`tombstones/<sha>.deleted.json`) that is included in the next monthly RFC 3161 manifest, so the timestamp chain reflects deletions transparently.
- **Tamper-evidence:** A monthly cron submits the bucket-state manifest hash to **FreeTSA** ([freetsa.org](https://freetsa.org)), an RFC 3161 timestamp authority. FreeTSA receives only the SHA-256 of the manifest (no signer data, no comment bodies, no PR references); it returns a binary `.tsr` signed by the FreeTSA Time Stamp Authority. The `.tsr` and the source manifest are committed to R2 and to the `cla-signatures` branch of the GitHub repository.
- **DPA:** [Cloudflare Customer Data Processing Agreement](https://www.cloudflare.com/cloudflare-customer-dpa/) (same instrument as Section 5.8).
- **Retention:** Ten (10) years on the bucket; monthly RFC 3161 timestamps retained indefinitely as part of the chain.
- **Legal basis:** Legitimate interest (Article 6(1)(f) GDPR), with the balancing test documented in the GDPR Policy §3.4.

## 6. Legal Basis for Processing (GDPR -- EU Users)

For users in the European Union or European Economic Area:

Because the Plugin itself does not collect or process personal data, no legal basis for processing is required for Plugin usage.

For the Web Platform (app.soleur.ai), the legal basis for processing account data, workspace data, and subscription data is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the user signed up for. For payment processing via Stripe, the legal basis is also contract performance -- processing is necessary to fulfill the subscription agreement. For technical data processed by Cloudflare (IP addresses, request headers -- see Section 5.8), the legal basis is contract performance for authenticated users and **legitimate interest** (Article 6(1)(f) GDPR) for unauthenticated traffic.

For the Docs Site, to the extent that technical data is collected by GitHub Pages, the legal basis is **legitimate interest** (Article 6(1)(f) GDPR) -- specifically, the legitimate interest in making documentation available to users via a standard web hosting service.

For website analytics via Plausible Analytics, the lawful basis is **legitimate interest** (Article 6(1)(f) GDPR) -- understanding documentation traffic patterns to improve content and user experience. This processing is cookie-free, stores no personal data, and does not require consent under the ePrivacy Directive (Article 5(3) does not apply as no information is stored on or accessed from the user's device).

If you interact with the GitHub repository (e.g., filing issues), the legal basis for processing your GitHub profile information in that context is **legitimate interest** (Article 6(1)(f) GDPR) -- facilitating community participation in the project. The balancing test for this interest considers: (a) the processing is limited to publicly available GitHub profile data voluntarily shared by the user, (b) the user initiated the interaction, (c) the processing is necessary for the stated purpose (community participation), and (d) the user can withdraw by deleting their GitHub contributions.

For newsletter subscriptions, the legal basis for processing your email address is **consent** (Article 6(1)(a) GDPR). You provide consent by submitting the signup form and confirming your subscription via the double opt-in email. You may withdraw consent at any time by unsubscribing. For the technical metadata automatically collected by Buttondown during subscription (IP address, referrer URL, subscription timestamp, browser/device metadata), the legal basis is **legitimate interest** (Article 6(1)(f) GDPR) -- service operation and abuse prevention. You may object to this processing under Article 21 (see Section 8).

## 7. Data Retention

- **Plugin data:** All data created by the Plugin is stored locally on your machine. You control its retention and deletion entirely.
- **Web Platform data:** Account data (email, auth tokens) is retained while your account is active and deleted upon account deletion request. Conversation data (messages and conversation metadata) is retained while the user's account is active and deleted upon account deletion request (cascade delete via foreign key). Encrypted API keys are deleted with the associated workspace. Share link records are retained while the link is active and deleted upon revocation or account deletion (cascade delete). <!-- Added 2026-04-10: KB sharing --> Payment records (subscription metadata, invoices) are retained for 10 years per French tax law (Code de commerce Art. L123-22).
- **Docs Site data:** Any data collected by GitHub Pages is retained according to GitHub's data retention policies.
- **Repository interaction data:** Issues, pull requests, and other contributions are retained on GitHub according to its standard policies and your own account settings.
- **Newsletter subscription data:** Your email address is retained by Buttondown for as long as you remain subscribed. Upon unsubscription, your email is removed from the active subscriber list. Technical metadata (IP address, referrer URL, subscription timestamp, browser/device metadata) is retained according to Buttondown's data retention practices. Buttondown may retain anonymized aggregate data (e.g., subscriber counts) after unsubscription.

## 8. Your Rights

### 8.1 Rights Under GDPR (EU/EEA Users)

If you are located in the EU or EEA, you have the following rights with respect to any personal data processing:

- **Right of access** (Article 15) -- the right to obtain confirmation of whether personal data is being processed and access to that data.
- **Right to rectification** (Article 16) -- the right to correct inaccurate personal data.
- **Right to erasure** (Article 17) -- the right to request deletion of personal data ("right to be forgotten").
- **Right to restriction of processing** (Article 18) -- the right to limit how personal data is used.
- **Right to data portability** (Article 20) -- the right to receive personal data in a structured, machine-readable format.
- **Right to object** (Article 21) -- the right to object to processing based on legitimate interests.
- **Right to lodge a complaint** -- the right to file a complaint with your local Data Protection Authority.

For the Plugin, these rights are most relevant to your interactions with GitHub (the hosting platform). For the Web Platform (app.soleur.ai), you may exercise these rights directly against Jikigai for account data, workspace data, conversation data, and subscription data through either of the following channels:

- **Self-serve (Articles 15 + 20):** Visit `/dashboard/settings/privacy` while signed in to the Web Platform. Click "Download my data" and re-authenticate. We will package your account profile, conversations, messages, attachments, knowledge-base share links, team / agent display names, BYOK encrypted credentials, BYOK usage audit log, and workspace files into a ZIP archive (with a `manifest.json` describing every file's GDPR article tag, row count, and SHA-256). The bundle is delivered as a one-time download link, valid for 7 days, bound to the requesting session and network. Conversation-history exports reflect the persistence limitation described in Section 4.7.
- **Email fallback (all rights):** Email <legal@jikigai.com>. We will fulfil the same scope manually. Use this channel for the rights that do not have a self-serve flow yet (rectification, restriction, objection, complaint), or if the self-serve flow fails for any reason.

Both channels fulfil the same legal right; the self-serve path exists for convenience and does not replace the email channel.

To exercise rights related to GitHub-collected data, contact GitHub directly through their privacy channels.

### 8.2 Rights Under US Privacy Laws

Users in the United States may have additional rights under state privacy laws (such as the California Consumer Privacy Act). For the Plugin, these rights are primarily relevant to any data collected by GitHub as the hosting provider. For the Web Platform, you may exercise these rights by contacting <legal@jikigai.com>.

### 8.3 Automated decision-making and Article 22 rights

The Web Platform includes agent-runtime features that can produce decisions on your behalf in response to external events (for example, a Stripe `invoice.payment_failed` webhook). These features are governed by Section 3a ("Agent Command Authority") of the Terms & Conditions and, on the data-protection side, by this section and by Section 2.3(o) of the Data Protection Disclosure.

**Opt-in by class and tier.** The Web Platform performs no automated action on your behalf for an action class (for example, `finance.payment_failed`) unless you have explicitly granted authorization for that class via the `/dashboard/settings/scope-grants` interface, at one of three tiers: `Approve every time` (you authorize each instance), `Draft, one click` (the agent prepares a draft you approve), or `Auto` (the agent executes without per-instance approval, after a second-click acknowledgement at grant time). The absence of a grant is a denial; the `/dashboard/audit` viewer renders every automated action with the action class, tier active at the moment of the event, timestamp, and BYOK token + cost data.

**Article 22 rights.** Where automated processing produces a decision concerning you (in particular, any action under the `Auto` tier), you have the right under Article 22(3) GDPR to:

- **Obtain human intervention** -- request that a human review the decision;
- **Express your point of view** -- submit your perspective on the decision; and
- **Contest the decision** -- challenge its accuracy or appropriateness.

You may exercise these rights through the "Request human review" affordance inlined on every row of `/dashboard/audit`, or by emailing <legal@jikigai.com>. We will provide a substantive response within the timeframes required by applicable law.

**Profiling.** Soleur does not profile users for advertising or third-party data brokerage. Within the Web Platform, automated decision-making is bounded to the explicit action classes you grant; no inferred profile is built from the resulting activity beyond the audit ledger required to make the decisions reviewable. Sub-processors are enumerated in Section 5 of this Policy and in Section 2.3(o) of the Data Protection Disclosure.

## 9. Children's Privacy

The Soleur Plugin and Docs Site are not directed at children under the age of 16 (or 13 in jurisdictions where that threshold applies). We do not knowingly collect personal data from children. If you believe a child has provided personal information through the GitHub repository, please contact us so we can take appropriate action.

## 10. International Data Transfers

The Plugin operates locally and does not transfer data internationally.

For the Web Platform:

- **Supabase:** EU-based deployment (AWS eu-west-1, Ireland). **No international data transfers.** Supabase Inc is a US-based company, but the Jikigai project is deployed to the EU region. See [Supabase DPA](https://supabase.com/legal/dpa).
- **Stripe:** US-based (Stripe, LLC). International data transfers are governed by the EU-US Data Privacy Framework (DPF, adequacy decision) and Standard Contractual Clauses (SCCs), EEA Module 2, as supplementary safeguard. DPA auto-incorporated in Services Agreement (verified 2026-03-19). See [Stripe DPA](https://stripe.com/legal/dpa).
- **Hetzner:** EU-based (Germany). Web Platform hosted in Helsinki, Finland (EU). **No international data transfers.** DPA (AVV) signed 2026-03-19 via Cloud Console.
- **Cloudflare:** Global CDN. International data transfers are governed by the EU-US Data Privacy Framework (DPF), Standard Contractual Clauses (SCCs), and Global CBPR certification. DPA self-executing via Self-Serve Agreement (verified 2026-03-19). See [Cloudflare DPA](https://www.cloudflare.com/cloudflare-customer-dpa/).

For the Docs Site and repository interactions, GitHub may transfer data internationally in accordance with its own policies and applicable data transfer mechanisms (such as Standard Contractual Clauses). See [GitHub's Global Privacy Practices](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement#githubs-global-privacy-practices) for details.

When using the Anthropic Claude API, data may be transferred to Anthropic's servers in the United States. This transfer is governed by Anthropic's privacy policies and your agreement with Anthropic.

For newsletter subscriptions, subscriber email addresses are transmitted to Buttondown, a US-based service. International data transfers are governed by Standard Contractual Clauses (SCCs) per Buttondown's [Data Processing Agreement](https://buttondown.com/legal/data-processing-agreement). See [Buttondown's Privacy Policy](https://buttondown.com/legal/privacy) for details.

Plausible Analytics, used for Docs Site analytics (see Section 4.3), processes all data exclusively within the European Union (Hetzner, Germany). No international data transfers occur for analytics data. See [Plausible's Data Policy](https://plausible.io/data-policy) for details.

## 11. Security

Because the Plugin runs locally and does not transmit data to our servers, the security of Plugin-generated files depends on your local machine's security posture. We recommend:

- Keeping your operating system and development tools up to date.
- Using appropriate access controls on your local filesystem.
- Managing your API keys securely (e.g., not committing them to version control).
- Reviewing the Plugin's source code to verify its behavior.

For the Web Platform (app.soleur.ai), Jikigai implements the following security measures:

- **Encryption at rest:** User API keys are encrypted using AES-256-GCM before storage.
- **Encryption in transit:** All communication with the Web Platform is protected by TLS.
- **EU-only hosting:** Web Platform infrastructure is hosted on Hetzner servers in Helsinki, Finland (EU), with no data transfers outside the EU for infrastructure-hosted data.
- **Payment security:** Card data is handled exclusively by Stripe (PCI DSS Level 1 certified) via Stripe Checkout and never reaches Jikigai servers (PCI SAQ-A).
- **Authentication:** User passwords are hashed by Supabase (bcrypt via GoTrue); authentication tokens are JWT-based.

## 12. Cookies

The Soleur Plugin does not use cookies.

The Docs Site, hosted on GitHub Pages, may use cookies as determined by GitHub's platform. Soleur does not add any first-party cookies to the Docs Site. For details on GitHub's cookie practices, see [GitHub's cookie documentation](https://docs.github.com/en/site-policy/privacy-policies/github-cookies).

The Web Platform at app.soleur.ai uses strictly necessary cookies for authentication (Supabase session cookies) and payment security (Stripe fraud prevention cookies). These cookies are exempt from consent requirements under ePrivacy Directive Article 5(3). For full details, see the [Cookie Policy](cookie-policy.md).

## 13. Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be posted to the GitHub repository and/or the Docs Site. The "Last Updated" date at the top of this document will be revised accordingly.

For material changes, we will make reasonable efforts to notify users (e.g., through a repository release note or a notice on the Docs Site).

## 14. Legal Entity and Contact Us

Soleur is a source-available project maintained by Jikigai, a company incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France.

GDPR Article 27 requires a representative in the EU for controllers not established in the EU. Because Jikigai is incorporated in France, Article 27 does not apply.

If you have questions about this Privacy Policy or our data practices, you can reach us through:

- **Email:** <legal@jikigai.com>
- **GitHub:** Open an issue at [github.com/jikig-ai/soleur](https://github.com/jikig-ai/soleur)
- **Website:** [soleur.ai](https://soleur.ai)
- **GDPR / Data Protection Inquiries:** <legal@jikigai.com> (include "GDPR" in the subject line)

To exercise your data subject rights under GDPR, send a written request to <legal@jikigai.com>. We will acknowledge your request within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3). This period may be extended by two further months where necessary, taking into account the complexity or volume of requests, in which case we will inform you of the extension and reasons within the initial one-month period.

---

> **Related documents:** This Privacy Policy should be read alongside the companion [Cookie Policy](cookie-policy.md) for detailed information about cookies used by the Docs Site (GitHub Pages), the [GDPR Policy](gdpr-policy.md) for detailed GDPR-specific disclosures, and the [Individual Contributor License Agreement](individual-cla.md) for details on contributor data processing.
