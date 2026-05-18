---
title: "Data Protection Disclosure"
description: "Data processing relationship clarification for Soleur under GDPR."
layout: base.njk
permalink: legal/data-protection-disclosure/
---

<section class="page-hero">
  <div class="container">
    <h1>Data Protection Disclosure</h1>
    <p>Effective February 20, 2026 | Last Updated May 16, 2026</p>
  </div>
</section>

<section class="content">
  <div class="container">
    <div class="prose">

**Effective Date:** February 20, 2026

**Last Updated:** May 18, 2026 (extended Section 2.3(o) to disclose the per-tenant `scope_grants` ledger, the `/dashboard/audit` viewer, and the Article 22(3) human-review affordance shipped in PR-G #3947; re-confirmed Inngest remains self-hosted and no new sub-processor is engaged; previous: May 16, 2026 extended Section 2.3(d) and added Section 2.3(n) for the off-site CLA evidence archive)

This Data Protection Disclosure ("DPD") describes the data processing relationship between:

- **Jikigai** ("Provider," "we," "us," or "our"), the operator and maintainer of the Soleur Claude Code plugin, accessible at [https://www.soleur.ai](https://www.soleur.ai) and the GitHub repository [jikig-ai/soleur](https://github.com/jikig-ai/soleur); and

- **You** ("User," "Controller," or "you"), the individual or entity using the Soleur plugin.

This DPD supplements our [Terms and Conditions](/legal/terms-and-conditions/) and [Privacy Policy](/legal/privacy-policy/) and transparently describes the data processing relationship under the General Data Protection Regulation (EU) 2016/679 ("GDPR"). Because Soleur is not a data processor (see Section 2), this is not a Data Processing Agreement under Article 28. It is a disclosure document that clarifies data handling responsibilities.

Soleur is a source-available project maintained by Jikigai, a company incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France.

---

## 1. Definitions

**1.1** "Personal Data" means any information relating to an identified or identifiable natural person as defined in Article 4(1) of the GDPR.

**1.2** "Processing" means any operation or set of operations performed on Personal Data, as defined in Article 4(2) of the GDPR.

**1.3** "Controller" means the natural or legal person which, alone or jointly with others, determines the purposes and means of the Processing of Personal Data, as defined in Article 4(7) of the GDPR.

**1.4** "Processor" means a natural or legal person which processes Personal Data on behalf of the Controller, as defined in Article 4(8) of the GDPR.

**1.5** "Sub-processor" means any Processor engaged by a Processor to carry out Processing activities on behalf of the Controller.

**1.6** "Plugin" means the Soleur Claude Code plugin, including all agents, skills, commands, and the knowledge base it provides.

**1.7** "Local Data" means all files, knowledge-base entries, brainstorms, plans, specs, code, and other data generated or stored on the User's local filesystem through use of the Plugin.

**1.8** "Docs Site" means the Soleur documentation website hosted at [https://www.soleur.ai](https://www.soleur.ai) via GitHub Pages.

---

## 2. Data Processing Relationship Classification

### 2.1 The Soleur Plugin Is Not a Data Processor

**This section is critical to understanding the data processing relationship for the Plugin.**

The Soleur Plugin operates entirely on the User's local machine. It is installed via CLI and runs as a local extension within the User's development environment.

As a result:

- **(a)** The Plugin does **not** process Personal Data on behalf of the User within the meaning of Article 28 of the GDPR.
- **(b)** The Plugin does **not** have access to, collect, store, transmit, or otherwise process any Local Data created or managed through the Plugin.
- **(c)** All knowledge-base files, plans, brainstorms, specs, generated code, and other artifacts remain exclusively on the User's local filesystem under the User's sole control.
- **(d)** The Plugin does **not** act as an intermediary for any API calls made by the User to third-party services (including, but not limited to, the Anthropic Claude API). Users authenticate directly with third-party services using their own API keys and credentials.

**Therefore, Soleur is neither a Controller nor a Processor with respect to the data processed locally through the Plugin.**

### 2.1b Web Platform Data Processing

The Soleur Web Platform at [app.soleur.ai](https://app.soleur.ai) is a cloud-hosted service operated by Jikigai. Unlike the Plugin (Section 2.1), the Web Platform involves server-side processing of User data on Jikigai-operated infrastructure.

For the Web Platform:

- **(a)** Jikigai acts as the **data controller** for User account data, workspace data, and subscription data processed through the Web Platform.
- **(b)** Jikigai engages the following **data processors** under Article 28 of the GDPR: Supabase (authentication and database), Stripe (payment processing), Hetzner (infrastructure hosting), and Cloudflare (CDN/proxy). See Section 4.2 for the full processor table.
- **(c)** Data processed includes: email addresses, hashed passwords, authentication tokens, session data, encrypted API keys, subscription metadata, conversation metadata, message content, and technical data (IP addresses, request headers).
- **(d)** The legal basis for this processing is **contract performance** (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service the User signed up for. For Cloudflare CDN/proxy processing of unauthenticated traffic (visitors who have not signed up), the legal basis is **legitimate interest** (Article 6(1)(f) GDPR) -- see Section 4.2 for the full dual-basis disclosure.

This section fulfills the commitment made in Section 8.1(a) to update this DPD with Article 28-compliant terms when cloud features are introduced.

### 2.2 User's Responsibilities as Controller

The User is solely responsible for:

- **(a)** All Personal Data processed on their local machine through use of the Plugin;
- **(b)** Ensuring a lawful basis for any processing of Personal Data that occurs through their use of the Plugin;
- **(c)** Compliance with GDPR and other applicable data protection laws with respect to data processed locally;
- **(d)** Securing their local environment, including filesystem permissions, encryption, and access controls;
- **(e)** Managing API keys and credentials used to interact with third-party services; and
- **(f)** Any data shared with third-party services (e.g., Anthropic Claude API) through the Plugin's functionality, including compliance with those services' own data processing terms.

### 2.3 Limited Processing by Soleur

Soleur's data processing activities are limited to:

- **(a)** **Docs Site hosting and analytics:** The Soleur documentation website is hosted on GitHub Pages. GitHub may collect standard web server logs, including IP addresses, browser user-agent strings, and page request data. This processing is governed by [GitHub's Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). Additionally, the Docs Site uses **Plausible Analytics** ([plausible.io](https://plausible.io)) for privacy-respecting website analytics. Plausible is cookie-free, does not store IP addresses, and collects only aggregated, anonymous data (page URLs, referrer URLs, country, device type, browser type).
- **(b)** **GitHub repository interaction:** Users who submit issues, pull requests, or participate in discussions on the Soleur GitHub repository interact with GitHub's platform. This processing is governed by GitHub's terms and privacy policies.
- **(c)** **Plugin distribution:** The Plugin is distributed via GitHub and npm. Download and installation telemetry is handled by those respective platforms under their own privacy policies.
- **(d)** **Contributor License Agreement (CLA) signatures:** Contributors who submit pull requests to the Soleur repository are asked to sign a CLA via the CLA Assistant integrated into GitHub. This processing collects the contributor's GitHub username, signature timestamp, and associated pull request reference. Signature data is stored in the Soleur GitHub repository on a dedicated branch (`cla-signatures`) and is publicly visible. The legal basis is legitimate interest (Article 6(1)(f) GDPR) in maintaining an enforceable record of contributor IP license grants. Signature data on the public branch is retained indefinitely as a contributor-facing receipt; an off-site evidence archive of the same record is retained for ten (10) years per Section 2.3(n).
- **(e)** **Newsletter subscription management:** Visitors who subscribe to the Soleur newsletter via the Docs Site provide their email address, which is transmitted to and processed by **Buttondown** ([buttondown.com](https://buttondown.com)), a third-party newsletter platform. Buttondown also automatically collects IP address, referrer URL, subscription timestamp, and browser/device metadata during the subscription request. Buttondown acts as a data processor on behalf of Jikigai. Buttondown's sub-processor list is maintained at [buttondown.com/legal/subprocessors](https://buttondown.com/legal/subprocessors). The legal basis for email address processing is consent (Article 6(1)(a) GDPR), verified through a double opt-in confirmation email. The legal basis for technical metadata is legitimate interest (Article 6(1)(f) GDPR) -- service operation and abuse prevention. Email addresses are retained until the subscriber unsubscribes. Technical metadata retention is governed by Buttondown's data retention practices.
- **(f)** **Web Platform account management:** The Web Platform (app.soleur.ai) processes email addresses, authentication tokens, and session data for user account management and authentication. Users may authenticate via magic link or OAuth providers (Google, Apple, GitHub, Microsoft). OAuth sign-in additionally processes provider user IDs, display names, and profile picture URLs. Accounts with matching verified email addresses are automatically linked. OAuth identity data is managed by Supabase. Legal basis: contract performance (Article 6(1)(b) GDPR). Retention: while account is active; deleted on account deletion request.
- **(g)** **Web Platform payment processing:** The Web Platform processes customer email addresses and subscription metadata via Stripe Checkout. Card data is handled exclusively by Stripe and never reaches Jikigai servers (PCI SAQ-A). Legal basis: contract performance (Article 6(1)(b) GDPR). Retention: subscription records retained for 10 years per French tax law (Code de commerce Art. L123-22).
- **(h)** **Web Platform infrastructure hosting:** The Web Platform hosts user workspaces, encrypted API keys (AES-256-GCM), and Docker containers on Hetzner servers in Helsinki, Finland (EU-only). Legal basis: contract performance (Article 6(1)(b) GDPR). Retention: while account is active.
- **(i)** **Web Platform conversation management:** The Web Platform stores conversation metadata and message content associated with user accounts. Data processed: conversation status, domain leader assignment, user messages, assistant responses, tool call metadata, and -- when usage telemetry is enabled per operator configuration -- per-message `usage` jsonb (token consumption and cost metadata). Legal basis: contract performance (Article 6(1)(b) GDPR). Retention: while account is active; deleted on account deletion request (cascade delete).
- **(j)** **Web Platform push notification subscriptions:** The Web Platform stores push notification subscription data (endpoint URL, encryption keys) when users enable browser push notifications. Data processed: push subscription endpoint, p256dh and auth encryption keys, timestamps. Legal basis: consent (Article 6(1)(a) GDPR) -- subscriptions are created only after explicit browser permission grant. Retention: while account is active; expired subscriptions (HTTP 410 Gone) deleted automatically; all data deleted on account deletion (cascade delete).
- **(k)** **Web Platform transactional email notifications:** The Web Platform sends email notifications via Resend when an AI agent requires user input and the user has no active push subscriptions. Data processed: recipient email address, notification content (agent name, question summary, conversation deep link). Legal basis: legitimate interest (Article 6(1)(f) GDPR) -- transactional notifications are necessary to inform users of pending decisions that block AI agent progress. Retention: email delivery logs retained per Resend's data retention policy.
- **(l)** **DSAR (Articles 15 + 20) self-serve export:** The Web Platform packages a user's data into a ZIP archive on request at `/dashboard/settings/privacy`. Data processed: the categories enumerated in Section 5.3 below (account profile, conversations, messages, message attachments, KB share links, team / agent names, BYOK credentials and usage audit, workspace files). The bundle is delivered as a one-time signed URL bound to the requesting session and IP prefix, valid for 7 days. An audit row (`dsar_export_audit_pii`) recording requester IP, user agent, and event timestamp is written for each lifecycle event (enqueue, download_complete, reissue, expire, fail). Legal basis for the bundle generation: legal obligation (Article 6(1)(c) GDPR) under Articles 15 + 20. Legal basis for the audit row: legal obligation (Article 6(1)(c)) under Article 5(2) accountability. Retention: bundle Storage object 7 days hard-cap (whichever first: download or pg_cron sweep); audit row 24 months then automatic delete; both anonymised on account erasure via the Article 17 cascade. Sub-processors: Supabase Storage (bundle ZIP), Resend (delivery email containing the download link).
- **(m)** **Operational telemetry & breach detection:** The Web Platform emits two operational telemetry streams to support service reliability and breach-detection obligations under GDPR Articles 32 and 33. (i) **Structured application logs** are written to standard output by the application server on Hetzner infrastructure in Helsinki, Finland (EU-only) and retained in a rolling Docker log buffer (capacity-bounded; no off-host log shipping is configured). (ii) **Error and breadcrumb events** are sent to Sentry (Functional Software GmbH, DE region; Standard Contractual Clauses) for error monitoring. In both streams, user identifiers are pseudonymised at the emission boundary by replacing the raw `userId` with a keyed cryptographic hash (`userIdHash`) computed using a server-resident secret pepper. Under GDPR Recital 26, the controller cannot re-identify a data subject from the hash alone without the pepper. Legal basis: legitimate interest (Article 6(1)(f) GDPR) in service reliability, security, and abuse prevention, balanced against the pseudonymisation safeguard; together with legal obligation (Article 6(1)(c) GDPR) for compliance with the Article 33 breach-notification timeline (see Section 7.2). Retention: Sentry events retained for 90 days (rolling); pino stdout retained in a fixed-capacity Hetzner-local rolling buffer (no off-host copies). Right to erasure (Article 17 GDPR): hashed identifiers age out per the rolling retention windows; the controller cannot perform processor-side targeted erasure of a pseudonym whose subject cannot be re-identified, consistent with Recital 26. **Sentry monitor classes processed:** issue alerts and cron monitor check-ins (vendor-hosted heartbeat for scheduled GitHub Actions jobs); both carry no application log content and only structural metadata (job slug, status, timestamp, pseudonymous identifier where applicable). **Sentry log ingestion (Logs product) is NOT enabled and no application log content is forwarded to Sentry**; if a future change introduces a Sentry log channel, the disclosure must be re-extended in advance and the scrub boundary at `apps/web-platform/server/sentry-scrub.ts` must be widened to cover it. **Inngest server liveness heartbeat:** the self-hosted Inngest durable-trigger server (bullet (o)) emits a 60-second loopback-fed heartbeat to Better Stack s.r.o. (EU); the payload is an opaque ping + timestamp + HTTP status code and carries no personal data, user identifiers, or application content — Better Stack is therefore NOT a sub-processor of personal data under GDPR Article 28 and no SCC/DPA is required.
- **(o)** **Web Platform autonomous-draft runtime (Inngest CFO) and per-tenant scope grants:** The Web Platform runs a server-side trigger substrate (self-hosted Inngest OSS on Hetzner, eu-central, bound to `127.0.0.1` with SQLite state on the same host -- no external sub-processor) that converts a Stripe `invoice.payment_failed` event into a CFO-domain customer-response **draft** persisted to the user's `messages` table and surfaced on `/dashboard` Today. Data processed: `founderId` (UUID), `invoiceId` (Stripe identifier, non-PII), `customerEmailHash` (sha256 of customer email -- the **cleartext customer email is hashed at the webhook boundary BEFORE the Inngest envelope is signed**; `payment_method` is dropped entirely), `amount`, `currency`, `failureCode`, plus the generated draft text. **Drafts only, sends nowhere** -- enforced at the DB level by the `messages_external_tier_status_check` CHECK constraint (migration 046); the user decides Send / Edit / Discard for each draft. Per-tenant hourly Anthropic-API cost cap (default $20/hr, configurable per founder) enforced atomically by `record_byok_use_and_check_cap()` plpgsql RPC with leading `SELECT ... FOR UPDATE`. A page-level disclosure banner above the Today section displays the `RUNTIME_COST_DISCLOSURE` notice (Article 13 transparency).

  **Per-tenant scope grants (PR-G, #3947).** As of May 18, 2026, the substrate's `inngest.send` call is gated by a per-tenant `scope_grants` ledger (`public.scope_grants`, migration 048): the webhook produces no Inngest event for an action class unless the founder has an active grant for that class via `/dashboard/settings/scope-grants`. The ledger is append-only WORM (grant, tier change, revocation all preserved); RLS self-select (`auth.uid() = founder_id`); writes routed through three SECURITY DEFINER RPCs (`grant_action_class`, `revoke_action_class`, `anonymise_scope_grants`). Data processed in the ledger: `founder_id` (UUID), `action_class` (text), `tier` (one of `auto` / `draft_one_click` / `approve_every_time`), `granted_at`, `revoked_at`, `revoked_reason`. The grant tier active at the moment of each Inngest event is recorded on the event envelope so the audit ledger pins the consent that was in force when the action ran.

  **Audit viewer (`/dashboard/audit`).** Founders can inspect their own per-tenant runtime ledger via `/dashboard/audit`: (1) BYOK invocations from `audit_byok_use` (RLS + belt-and-suspenders founder filter), (2) Inngest run history via a server-only proxy at `/api/dashboard/runs` (signing-key never reaches the client; raw customer identifier masked server-side; `authorizing_event` rendered only as the redacted summary). Each row inlines a "Request human review →" (`mailto:legal@jikigai.com`) affordance and a "Change authorization →" link to the scope-grants page, satisfying Article 22(3).

  **Legal basis:** contract performance (Article 6(1)(b) GDPR) for the draft generation feature, the scope grants ledger, and the audit viewer; legitimate interest (Article 6(1)(f) GDPR) for the cost-telemetry rows in `audit_byok_use` that evidence per-tenant cap enforcement. **Retention:** draft rows controlled by the user via Send / Edit / Discard; scope grants ledger retained indefinitely as an append-only consent record (the substrate of the user's authorization to act on their behalf), anonymised on account erasure via the Article 17 cascade (`anonymise_scope_grants` runs before the `anonymise_tc_acceptances` step in `server/account-delete.ts`); Inngest event store on a 30-day rolling SQLite window (operator-managed; not personal-data-bearing because customer email is hashed before persistence). **Sub-processors:** none new (Inngest remains self-hosted; Anthropic receives BYOK API calls under the user's own API key, governed by the user's bilateral Anthropic relationship via BYOK). ADR-030 records the trigger-substrate decision; ADR-031 records the per-tenant scope grants substrate decision.
- **(n)** **CLA evidence archive (off-site):** Jikigai maintains an off-site, tamper-evident archive of CLA signature evidence at a Cloudflare R2 bucket (`soleur-cla-evidence`, region `weur` -- Western Europe). For each signature recorded under Section 2.3(d), a content-addressed evidence record is written to the bucket containing: signer GitHub username, signature timestamp, verbatim sign-comment body, pull-request-of-record, SHA-256 hash of the CLA document text at the PR base SHA, and capture method. Bypass records for allowlisted bot accounts (`dependabot[bot]`, `renovate[bot]`, `claude[bot]`) are recorded once per principal per quarter; the upstream CLA action filters `github-actions[bot]` (DB-id 41898282) so no record is written for that actor. R2 Lock Rules enforce an **age-based ten (10) year retention floor** providing write-once-read-many (WORM) semantics; administrator override is reserved for GDPR Article 17 erasure cases and writes a permanent tombstone (`tombstones/<sha>.deleted.json`) included in the next monthly RFC 3161 manifest, preserving the integrity of the timestamp chain. A monthly cron submits the SHA-256 of the bucket-state manifest to **FreeTSA** ([freetsa.org](https://freetsa.org)) -- an RFC 3161 Time Stamp Authority -- and stores the returned `.tsr` at `timestamps/<yyyy-mm>/manifest.tsr` in the bucket and as a paper trail on the `cla-signatures` branch. FreeTSA receives only the SHA-256 hash and no contributor-identifying data. **Legal basis:** legitimate interest (Article 6(1)(f) GDPR) -- defense of legal claims regarding contributor IP grants under Article 17(3)(e); the three-part balancing test is documented in the GDPR Policy §3.4. **Retention:** ten (10) years on the bucket; monthly RFC 3161 timestamps retained indefinitely as part of the evidentiary chain. **Sub-processors:** Cloudflare R2 (storage, EU region) and FreeTSA TSA (timestamping authority, DE -- EU).

For these activities, Jikigai acts as a Controller with respect to data it directly collects and processes (including CLA signature data and Web Platform account data). Third-party processors are engaged as described in Section 4.2.

---

## 3. Technical and Organizational Measures

### 3.1 Plugin Architecture (Local-Only)

Soleur's architecture is designed to minimize data processing concerns:

- **(a)** The Plugin executes entirely within the User's local CLI environment.
- **(b)** No data is transmitted to Soleur-operated servers.
- **(c)** No telemetry, analytics, or usage tracking is embedded in the Plugin itself.
- **(d)** The Plugin does not establish network connections to Soleur-controlled endpoints.

### 3.2 User-Side Security Recommendations

While Soleur does not process User data, we recommend the following security measures for Users:

- **(a)** Use encrypted filesystems for local data storage.
- **(b)** Restrict filesystem permissions on knowledge-base directories and generated artifacts.
- **(c)** Rotate and securely store API keys used with third-party services.
- **(d)** Review the data you send to third-party APIs (e.g., Anthropic Claude API) and ensure compliance with your own data protection obligations.
- **(e)** Maintain access controls on the development environment where the Plugin is installed.

---

## 4. Third-Party Services and Sub-processors

### 4.1 Plugin Sub-processors

The Plugin does not process Personal Data on behalf of Users (see Section 2.1). Accordingly, there are no Plugin-level Sub-processors to disclose under Article 28(2) of the GDPR.

### 4.2 Service Processors

For processing activities where Jikigai acts as Controller (see Sections 2.1b and 2.3), the following third-party processors are engaged:

**Docs Site and Newsletter Processors:**

| Processor | Processing Activity | Data Processed | Legal Basis | Sub-processor List |
|-----------|-------------------|----------------|-------------|-------------------|
| GitHub Pages ([pages.github.com](https://pages.github.com)) | Docs Site hosting | IP addresses, browser user-agent strings, page request data | Legitimate interest (Article 6(1)(f)) | [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) |
| Plausible Analytics ([plausible.io](https://plausible.io)) | Privacy-respecting website analytics (cookie-free, EU-hosted) | Aggregated anonymous data only: page URLs, referrer URLs, country, device type, browser type (no IP addresses stored; see Section 2.3(a)) | Legitimate interest (Article 6(1)(f)) | [Plausible DPA](https://plausible.io/dpa) |
| Buttondown ([buttondown.com](https://buttondown.com)) | Newsletter subscription management and email delivery | Email addresses of subscribers | Consent (Article 6(1)(a)) — double opt-in | [Buttondown Sub-processors](https://buttondown.com/legal/dpa) |

**Web Platform Processors:**

| Processor | Processing Activity | Data Processed | Legal Basis | Sub-processor List |
|-----------|-------------------|----------------|-------------|-------------------|
| Supabase Inc ([supabase.com](https://supabase.com)) | Web Platform auth + database | Email addresses, hashed passwords, auth tokens, session data, conversation metadata, message content | Contract performance (Article 6(1)(b)) | [Supabase DPA](https://supabase.com/legal/dpa) |
| Stripe Inc ([stripe.com](https://stripe.com)) | Web Platform payment processing (Stripe Checkout, PCI SAQ-A) | Customer email, subscription metadata (card data handled exclusively by Stripe) | Contract performance (Article 6(1)(b)) | [Stripe Sub-processors](https://stripe.com/legal/service-providers) |
| Hetzner Online GmbH ([hetzner.com](https://hetzner.com)) | Web Platform infrastructure hosting (Helsinki, EU-only) | User workspaces, encrypted API keys, Docker containers | Contract performance (Article 6(1)(b)) | [Hetzner DPA](https://www.hetzner.com/legal/terms-and-conditions/) |
| Cloudflare Inc ([cloudflare.com](https://cloudflare.com)) | Web Platform CDN/proxy (`app.soleur.ai`, extending existing `soleur.ai` zone) | IP addresses, request headers, TLS termination data | Contract performance (Article 6(1)(b)) for authenticated users; legitimate interest (Article 6(1)(f)) for unauthenticated traffic | [Cloudflare DPA](https://www.cloudflare.com/cloudflare-customer-dpa/) |
| Sentry (Functional Software GmbH) ([sentry.io](https://sentry.io)) | Web Platform error monitoring and breach detection (Sentry SDK) | Error messages, stack traces, request metadata (URL paths, HTTP headers, navigation breadcrumbs), pseudonymous user identifier (`userIdHash`) | Legitimate interest (Article 6(1)(f)) for service reliability; legal obligation (Article 6(1)(c)) for Article 33 breach-notification timeliness | [Sentry Sub-processors](https://sentry.io/legal/dpa/) |
| Resend Inc ([resend.com](https://resend.com)) | Web Platform transactional email notifications (review gate alerts) | Recipient email address, email content (notification summaries) | Legitimate interest (Article 6(1)(f)) for transactional notifications | [Resend DPA](https://resend.com/legal/dpa) |
| Cloudflare Inc ([cloudflare.com](https://cloudflare.com)) -- R2 Storage | CLA evidence archive (`soleur-cla-evidence` bucket, region `weur`; R2 Lock Rules age-based retention, 10yr floor) | Per-signature evidence records (GitHub username, signature timestamp, sign-comment body, PR-of-record, doc-hash, capture method); monthly RFC 3161 timestamp responses | Legitimate interest (Article 6(1)(f)) -- Section 2.3(n) | [Cloudflare DPA](https://www.cloudflare.com/cloudflare-customer-dpa/) (same instrument as CDN row) |
| FreeTSA ([freetsa.org](https://freetsa.org)) -- RFC 3161 Time Stamp Authority | Monthly RFC 3161 timestamping of the CLA evidence bucket manifest (SHA-256 only); no contributor data leaves the bucket | SHA-256 hash of bucket-state manifest (no personal data) | Legitimate interest (Article 6(1)(f)) -- Section 2.3(n) | Public free-of-charge service; no DPA available. FreeTSA receives no personal data, only a 32-byte hash; processing falls outside Article 28 scope. |

This disclosure is consistent with Sections 2.1b, 2.3(a), 2.3(e), 2.3(f), 2.3(g), 2.3(h), 2.3(i), 2.3(j), 2.3(k), 2.3(l), and 2.3(m).

### 4.3 Third-Party Services Used by Users

Users may interact with the following third-party services through the Plugin's functionality. These interactions are initiated and controlled by the User, not by Soleur:

| Service | Purpose | User's Relationship |
|---------|---------|-------------------|
| Anthropic (Claude API) | AI model inference | Direct customer of Anthropic |
| GitHub | Code hosting, issue tracking | Direct customer of GitHub |
| npm | Package distribution | Direct customer of npm |

Users are responsible for reviewing and complying with the data processing terms of any third-party service they use in conjunction with the Plugin.

---

## 5. Data Subject Rights

### 5.1 Local Data

Because Soleur does not have access to Local Data, data subject requests (access, rectification, erasure, portability, restriction, objection) related to data processed locally must be addressed by the User directly. Soleur cannot fulfill such requests as it has no access to the data.

### 5.2 Docs Site and GitHub Data

For data processed through the Docs Site or GitHub repository:

- **(a)** Users may exercise their data subject rights by contacting us through the [Soleur GitHub repository](https://github.com/jikig-ai/soleur).
- **(b)** For data processed by GitHub as a platform, Users should refer to [GitHub's data subject request process](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

### 5.3 Web Platform Data

For data processed through the Web Platform (app.soleur.ai) where Jikigai acts as controller (see Section 2.1b), data subjects may exercise the following rights by contacting <legal@jikigai.com>:

- **(a)** **Right of Access (Article 15):** Request confirmation of whether personal data is being processed and obtain a copy of the data (account data, workspace data, conversation data, subscription metadata).
- **(b)** **Right to Rectification (Article 16):** Request correction of inaccurate personal data held by Jikigai.
- **(c)** **Right to Erasure (Article 17):** Request deletion of personal data under applicable conditions. Note: subscription records subject to French tax law retention (Code de commerce Art. L123-22) may be retained for up to 10 years (see Section 2.3(g)).
- **(d)** **Right to Restriction of Processing (Article 18):** Request that Jikigai restrict processing of personal data.
- **(e)** **Right to Data Portability (Article 20):** Request personal data in a structured, commonly used, machine-readable format.
- **(f)** **Right to Object (Article 21):** Object to processing of personal data. The legal basis for Web Platform processing is contract performance (Article 6(1)(b)), so this right applies primarily when processing extends beyond strict contractual necessity.

Jikigai will acknowledge requests within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3). This period may be extended by two further months where necessary, taking into account the complexity or volume of requests, in which case we will inform you of the extension and reasons within the initial one-month period. For full details on how each right applies, see the companion [GDPR Policy](/legal/gdpr-policy/) Section 5.

---

## 6. International Data Transfers

### 6.1 Local Data

No international data transfers are performed by Soleur with respect to Local Data.

### 6.2 Third-Party Transfers

When Users interact with third-party services (e.g., Anthropic Claude API, GitHub), data may be transferred internationally. These transfers are governed by the respective third-party's data processing agreements and transfer mechanisms. Users are responsible for ensuring adequate safeguards are in place for any such transfers.

### 6.3 Buttondown (Newsletter)

Transfers of newsletter subscriber data (email addresses, IP addresses, referrer URL, subscription timestamps, browser/device metadata) from the EEA to the United States are governed by the **EU Standard Contractual Clauses** (European Commission Implementing Decision (EU) 2021/914, Module 2: Controller-to-Processor), incorporated by reference into Buttondown's [Data Processing Agreement](https://buttondown.com/legal/data-processing-agreement). Buttondown's DPA applies to all plan tiers, including the free tier used by Jikigai.

### 6.4 Web Platform

For the Web Platform (app.soleur.ai):

- **Supabase:** EU-based deployment (AWS eu-west-1, Ireland). **No international data transfers.** Supabase Inc is a US-based company, but the Jikigai project is deployed to the EU region. DPA (Data Processing Addendum) signed 2026-03-19 via PandaDoc.
- **Stripe:** US-based (Stripe, LLC). Transfer via EU-US Data Privacy Framework (DPF, adequacy decision) and Standard Contractual Clauses (SCCs), EEA Module 2. DPA auto-incorporated in Services Agreement (verified 2026-03-19).
- **Hetzner:** EU-based (Germany). Web Platform hosted in Helsinki, Finland (EU). **No international data transfers.** DPA (AVV) signed 2026-03-19 via Cloud Console.
- **Cloudflare:** Global CDN. Transfer via EU-US Data Privacy Framework (DPF), Standard Contractual Clauses (SCCs), and Global CBPR certification. DPA self-executing via Self-Serve Subscription Agreement (verified 2026-03-19).
- **Sentry:** DE region (Frankfurt, Germany), processed by Functional Software GmbH. Transfer mechanism: Standard Contractual Clauses (Sentry's standard EU-region terms). Intra-EU processing — no third-country transfer. DPA self-executing via Sentry's terms of service (verified 2026-05-13).
- **Cloudflare R2 (CLA evidence archive):** EU region (`weur` -- Western Europe). R2 Lock Rules age-based retention, 10yr floor. Intra-EU processing for archive contents at rest. DPA self-executing via the same Cloudflare Customer Data Processing Agreement as the CDN row.
- **FreeTSA (RFC 3161 Time Stamp Authority):** DE-based public service. The service receives only a SHA-256 hash of the monthly manifest; no contributor data is transmitted. Intra-EU processing. No DPA -- the input is not personal data within the meaning of Article 4(1) GDPR (a 32-byte unkeyed hash of bucket-state metadata).

### 6.5 Docs Site

The Docs Site is hosted on GitHub Pages, which may involve data processing in the United States and other jurisdictions where GitHub operates. GitHub maintains appropriate transfer mechanisms as described in its data processing agreements.

Plausible Analytics, used for privacy-respecting website analytics on the Docs Site (see Section 4.2), processes all data exclusively within the European Union (Hetzner, Germany). No international data transfers occur for analytics data.

---

## 7. Data Breach Notification

### 7.1 Local Breaches

Soleur has no visibility into the User's local environment and therefore cannot detect or report data breaches affecting Local Data. Users are solely responsible for breach detection and notification obligations under Article 33 and Article 34 of the GDPR with respect to locally processed data.

### 7.2 Platform Breaches

In the unlikely event that a breach affects the Soleur GitHub repository, Docs Site, Web Platform (app.soleur.ai), or distribution channels:

- **(a)** We will notify affected Users without undue delay, and in any event within 72 hours of becoming aware of the breach, where feasible (Article 33 GDPR).
- **(b)** Notification will be provided via the [Soleur GitHub repository](https://github.com/jikig-ai/soleur) and, where possible, through direct communication (including email notification for Web Platform users with an account on file).
- **(c)** The notification will include the nature of the breach, likely consequences, and measures taken or proposed to address it.

---

## 8. Cloud Features Transition

### 8.1 Transition Status

The Soleur Web Platform (app.soleur.ai) represents the introduction of cloud-hosted features described prospectively in the original version of this section. The commitments made below have been addressed as follows:

- **(a)** This DPD has been updated with Article 28 GDPR-compliant data processing terms (see Sections 2.1b, 2.3(f)-(h), and 4.2). **FULFILLED.**
- **(b)** Users are notified of cloud processing via this updated DPD and the updated Privacy Policy. **FULFILLED.**
- **(c)** Technical and organizational measures implemented: encryption at rest (AES-256-GCM for API keys), TLS for data in transit, EU-only hosting (Helsinki, Finland) for infrastructure. **FULFILLED.**
- **(d)** Processor list maintained in Section 4.2. **FULFILLED.**
- **(e)** Transfer mechanisms documented: EU-only for Supabase (eu-west-1, Ireland) and Hetzner (Helsinki, Finland), DPF + SCCs for Stripe (see Section 6.4). **FULFILLED.**
- **(f)** DPIA evaluation: The Web Platform processes user PII (email, auth tokens, encrypted API keys, subscription metadata) but does not involve special categories (Article 9), systematic monitoring, or automated decision-making. Processing remains below the high-risk thresholds of Article 35(3). **Evaluated -- DPIA not required.** See the companion GDPR Policy Section 9 for the full analysis.
- **(g)** Users accept the updated Terms and Conditions via a clickwrap checkbox on the Web Platform signup page (app.soleur.ai/signup). The checkbox is unchecked by default and must be actively checked before account creation. Acceptance is timestamped and recorded in the user database. **FULFILLED.**

### 8.2 Future Changes

Any further expansion of cloud processing beyond the Web Platform (e.g., additional cloud services, new data categories) will follow the same disclosure process and will be communicated:

- **(a)** At least 30 days before the change takes effect;
- **(b)** Via the Soleur GitHub repository, Docs Site, release notes, and Web Platform (app.soleur.ai) (including email notification for Web Platform users with an account on file);
- **(c)** With a clear description of what data will be processed, for what purpose, and what safeguards are in place.

---

## 9. Audit Rights

### 9.1 Current Architecture

Given the local-only nature of the Plugin, traditional audit rights under Article 28(3)(h) of the GDPR are not applicable. However:

- **(a)** The Soleur Plugin source code is available for inspection on [GitHub](https://github.com/jikig-ai/soleur).
- **(b)** Users may verify that the Plugin does not transmit data by inspecting network activity during use.
- **(c)** Soleur welcomes security audits and responsible disclosure through the GitHub repository.

### 9.2 Web Platform Audit Rights

For the Web Platform, audit rights consistent with Article 28(3)(h) are provided through the individual processor DPAs: [Supabase DPA](https://supabase.com/legal/dpa), [Stripe DPA](https://stripe.com/legal/dpa), and [Hetzner DPA](https://www.hetzner.com/legal/terms-and-conditions/). Users may request audit information from Jikigai regarding Web Platform data processing by contacting <legal@jikigai.com>.

---

## 10. Termination and Data Deletion

### 10.1 Plugin Removal

Users may uninstall the Plugin at any time. Upon removal:

- **(a)** All Local Data remains on the User's filesystem under their sole control.
- **(b)** Soleur does not retain any copy of Local Data, as no such data was ever transmitted to Soleur.
- **(c)** Users are responsible for deleting or retaining Local Data according to their own data retention policies.

### 10.2 Docs Site and Repository Data

Users who wish to have their data removed from the Soleur GitHub repository (e.g., issue comments, pull request contributions) should follow GitHub's standard data deletion procedures or contact us through the repository.

### 10.3 Web Platform Account Deletion

Users may delete their Web Platform account at any time via account settings. Upon account deletion:

- **(a)** Account data (email, authentication tokens, session data) is deleted from Supabase.
- **(b)** Encrypted API keys and workspace data are deleted from Hetzner infrastructure.
- **(c)** Stripe retains payment records (subscription metadata, invoices) for 10 years per French tax law (Code de commerce Art. L123-22).
- **(d)** Conversation data (messages and conversation metadata) is deleted from Supabase (cascade delete via foreign key).
- **(e)** Cloudflare cache entries expire per standard TTL; no persistent user data is stored by Cloudflare.

See the [Terms and Conditions](/legal/terms-and-conditions/) Section 14.1b for the full account termination procedure.

---

## 11. Governing Law and Jurisdiction

**11.1** This DPD shall be governed by and construed in accordance with the laws of the European Union and the Member State in which the User is established, to the extent required by the GDPR.

**11.2** Any disputes arising out of or in connection with this DPD shall be subject to the exclusive jurisdiction of the courts of the Member State in which the User is established, unless otherwise required by mandatory law.

**11.3** Nothing in this DPD shall limit the rights of data subjects under the GDPR or the powers of supervisory authorities.

---

## 12. Contact Information

For questions, concerns, or requests related to this DPD:

- **Email:** <legal@jikigai.com>
- **GitHub Repository:** [https://github.com/jikig-ai/soleur](https://github.com/jikig-ai/soleur)
- **Website:** [https://www.soleur.ai](https://www.soleur.ai)

---

## 13. Amendments

**13.1** Soleur reserves the right to update this DPD to reflect changes in the Plugin's architecture, applicable law, or regulatory guidance.

**13.2** Material changes will be communicated at least 30 days in advance through the Soleur GitHub repository, Docs Site, and Web Platform (app.soleur.ai) (including email notification for Web Platform users with an account on file).

**13.3** Continued use of the Plugin after the effective date of changes constitutes acceptance of the updated DPD.

---

> **Related documents:** This Data Protection Disclosure references data practices and privacy obligations. Please review the companion [Privacy Policy](/legal/privacy-policy/), [GDPR Policy](/legal/gdpr-policy/), [Terms and Conditions](/legal/terms-and-conditions/), and [Individual Contributor License Agreement](/legal/individual-cla/) documents to ensure consistency.

    </div>
  </div>
</section>
