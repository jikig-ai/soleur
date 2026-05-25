---
title: "Privacy Policy"
description: "How Soleur handles data with its local-first architecture."
layout: base.njk
permalink: legal/privacy-policy/
---

<section class="page-hero">
  <div class="container">
    <h1>Privacy Policy</h1>
    <p>Effective February 20, 2026 | Last Updated May 25, 2026</p>
  </div>
</section>

<section class="content">
  <div class="container">
    <div class="prose">

**Effective Date:** February 20, 2026
**Last Updated:** May 25, 2026 (#4290 — added `byok_delegations` WORM ledger to `DSAR_TABLE_ALLOWLIST` per PR-A of feat-byok-delegations (#4232); production exposure at PR-A merge is internal-only — gated by the `byok-delegations` feature flag (default-off); DSAR worker wired with five per-column `.eq()` chains for OR-semantics across grantor_user_id, grantee_user_id, created_by_user_id, revoked_by_user_id, cap_updated_by_user_id; full erasure cascade ships in PR-B; previous: May 22, 2026 added departed-workspace-member DSAR disclosure for the `workspace_member_removals` WORM ledger introduced by migration 062 / PR #4294 (Article 30 register Processing Activity 19 — distinct from PA-20 `workspace_member_actions`); Section 8.1 paragraph block clarifies that departed Co-Members retain Art. 15 / 17 / 20 rights against Jikigai over their identifiable removal-event row; 36-month retention floor per Art. 82(2) shortest-applicable-jurisdiction limitations period; Art. 17 cascade extended via `anonymise_workspace_member_removals(p_user_id)` SECURITY DEFINER RPC step 3.905 in `server/account-delete.ts` BEFORE step 3.91 `anonymise_workspace_members` cascade DELETE, BEFORE step 3.93 `anonymise_workspace_member_actions` (PA-20), and BEFORE `auth.admin.deleteUser` (step 4); RPC NULL-sets both PII columns `removed_user_id` AND `removed_by_user_id`; lineage columns `id` and `removed_at` preserved post-erasure unconditionally for Art. 5(2) accountability, `workspace_id` preserved while the parent workspace exists (may transition to NULL via the FK's `ON DELETE SET NULL` cascade at step 3.92 orphan-org cleanup per ADR-039 §Invariants); WORM trigger bypass is structural-shape detection (PII columns transition NOT NULL → NULL only, lineage columns unchanged) at the trigger body itself — NOT a `SET LOCAL session_replication_role` GUC bypass (deliberate post-#4294-review divergence from mig 037 / mig 051 precedent per learning 2026-05-18, because pg_cron runs as `postgres` not `service_role`); departed Co-Members cannot read their own PA-19 row via the workspace RLS predicate after removal, so Art. 15 access is fulfilled via the service-role DSAR worker keyed single-arm on `removed_user_id` (the row's owner-of-record); no new sub-processor engaged; this update closes the legal-doc-cross-document-gate lockstep gap left by PR #4294 (#4333); previous: added Section 4.11 "Workspace co-members" data-class block for the team-workspace feature gated by `FLAG_TEAM_WORKSPACE_INVITE` per AC-LEGAL-FLIP; the disclosure carries dual-perspective coverage — Workspace Owner perspective and Co-Member perspective — satisfying Article 13(1)(e) recipient disclosure on both sides; added a Section 4.7 recipient-note cross-reference; the load-bearing technical measure is the SECURITY DEFINER `is_workspace_member()` RLS helper (migration 053); Workspace Owners are responsible for ensuring each invited Co-Member is bound by appropriate confidentiality and IP-assignment terms per Terms & Conditions Section 3b.4 and AUP Section 5.5 (by any sufficient means, including click-through Terms reliance, existing engagement agreement, or the optional Soleur Side Letter template); no new sub-processor engaged — co-members are NOT processors under Article 28 GDPR (see Data Protection Disclosure Section 4.2 carve-out); cross-references Article 30 register Processing Activity 2 (already amended by PR #4225); previous: May 21, 2026 (extended Section 8.3 with the template-level authorization layer introduced by PR-I #4078: per-(founder, template) consent envelope under Article 7(3) "specific" + "informed" via the first-send-IS-authorization pattern, NOT NULL bounded columns 100/30/90, per-row Revoke surface at `/dashboard/settings/scope-grants` satisfying Article 7(3) "as easily withdrawable as given", forward-reference to retroactive-reclassification in PR-I+1 #4216; no new sub-processor engaged; previous: May 19, 2026 extended Section 8.3 to add the fourth tier `Auto with daily digest` for `infra.*` action classes, refresh action-class examples to include the new `external_low_stakes` and `infra.*` categories landed in PR-H #4077, and add the Article 22(3) one-liner that the next-business-day digest review window IS the human-review path for `auto_with_digest`; added Section 4.10 "LinkedIn Company Page publication" data-class block, Section 5.12 "LinkedIn Ireland Unlimited Company" and Section 5.13 "Microsoft Ireland Operations Ltd" sub-processor entries, extended Section 6 with the dual-basis disclosure for LinkedIn Page operation [Art. 6(1)(f) marketing + Art. 6(1)(c) K-bis business-verification transfer], extended Section 7 retention, added Section 8.1 "LinkedIn-published content carve-out" paragraph for Article 17 cascade limitation per EDPB Guidelines 5/2019, and extended Section 10 international-transfers with the LinkedIn Ireland + Microsoft Ireland rows per #4051; previous: May 18, 2026 added Section 8.3 "Automated decision-making and Article 22 rights" disclosing the Web Platform's agent-runtime scope grants and human-review affordance; scoped the Buttondown-newsletter "does not involve profiling or automated decision-making" line to that processor only; May 16, 2026 extended Section 4.5 with the off-site Cloudflare R2 evidence archive for CLA signatures and added Section 5.11 Cloudflare R2 sub-processor entry per #3209)

## 1. Introduction

This Privacy Policy describes how Jikigai ("we," "us," or "our"), operator of Soleur, handles information in connection with the Soleur Company-as-a-Service platform ("the Plugin"), a Claude Code plugin providing agents, skills, commands, and a knowledge base for structured software development workflows, the Soleur documentation website located at soleur.ai ("the Docs Site"), and the Soleur Web Platform at [app.soleur.ai](https://app.soleur.ai) ("the Web Platform").

We are committed to protecting your privacy. This Policy explains what data is and is not collected, how the Plugin operates, and your rights under applicable law, including the EU General Data Protection Regulation (GDPR) and US privacy regulations.

## 2. Who We Are

**Soleur** is a source-available project maintained by **Jikigai**, a company incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France. Jikigai is the data controller for the processing activities described in this Policy.

The Soleur source code is available at the GitHub repository [jikig-ai/soleur](https://github.com/jikig-ai/soleur).

For privacy inquiries, you may contact us at <legal@jikigai.com> (include "Privacy" in the subject line), by opening an issue on the GitHub repository, or through the website at [soleur.ai](https://www.soleur.ai).

## 3. What the Plugin Does

Soleur is a locally installed Claude Code plugin. It provides {{ stats.agents }} AI agents, {{ stats.skills }} skills, and a compounding knowledge base to support structured software development workflows. The Plugin is installed via the Claude Code CLI and runs entirely on your local machine.

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

The Soleur documentation site at [soleur.ai](https://www.soleur.ai) is hosted on **GitHub Pages**. We use **Plausible Analytics** ([plausible.io](https://plausible.io)) for privacy-respecting website analytics. Plausible does not use cookies, local storage, or fingerprinting. It collects the following anonymous, aggregated data:

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
- **Workspace data:** User workspaces and encrypted API keys (BYOK -- bring your own key). API keys are encrypted using AES-256-GCM before storage.
- **Subscription data:** Subscription status and billing metadata (managed by Stripe). Card data is handled exclusively by Stripe via Stripe Checkout and never reaches Jikigai servers (PCI SAQ-A).
- **Conversation data:** Conversation metadata (domain leader, status, timestamps) and message content (user messages, assistant responses, tool call metadata) stored in the Supabase database. Conversations are associated with the user's account via user_id. **Partial assistant outputs from aborted turns** -- assistant text generated before a user-initiated Stop or an involuntary client disconnect -- are preserved in the same conversation history with an "aborted" status marker, the token cost of the partial turn, and the list of completed actions. The purpose is to give you a faithful record of what the Service produced (and billed against your usage) on your behalf. Partial-turn rows are retained for the same period as the parent conversation (see the retention paragraph immediately below this list, and Section 7 for the overall retention policy) unless you exercise your erasure right under Section 8.1. See Section 5.5 of the [Terms & Conditions](/legal/terms-and-conditions/) for the consumption terms that govern partial-turn billing and side effects; your erasure rights (GDPR Article 17) under Section 8.1 below apply equally to partial-turn rows. In rare cases of unexpected service interruption (e.g., kernel-level process termination or container restart) after generation but before persistence completes, a small portion of an in-progress reply may not be retained in the conversation record.
- **Per-turn cost telemetry (Concierge surface):** On conversations handled by the Concierge code path (the `/soleur:go` surface), each completed assistant turn is annotated with a small `usage` record attached to the message row. On this surface the record is **deliberately narrowed to a single numeric field -- the turn's cost in US dollars** (`{ cost_usd: <number> }`); token counts are not persisted on completed Concierge turns, in line with the data-minimisation principle (Article 5(1)(c) GDPR). The legacy single-leader chat surface continues to persist the wider snapshot already described in the preceding bullet (input tokens, output tokens, cost, and completed-action list) on aborted turns only. The purposes of the cost field are: (i) subscription cost accounting; (ii) per-user usage observability via the in-product `/api/usage` aggregator; and (iii) operator-side resolution of cost-cap-related billing inquiries. The legal basis, recipients, hosting region, technical and organisational measures, and retention period are the same as the parent conversation row: Article 6(1)(b) GDPR (contract performance); processed by Supabase (eu-west-1, Ireland) on Hetzner-hosted infrastructure (hel1, Finland); no new third-party recipients; protected by Supabase Row-Level Security gated on `conversation_id` ownership and a service-role write boundary enforced by the cc-dispatcher `assertWriteScope` sentinel; cascade-deleted on account deletion via foreign key (`ON DELETE CASCADE`).
- **Technical data:** IP addresses and request headers processed by Cloudflare CDN/proxy.

<!-- 2026-05-12: Article 13(3) prior-disclosure refresh for messages.usage column (PR #3603 / PR-A2 #3648). CC_PERSIST_USAGE=true active in prd. -->

**Purpose:** Providing the Web Platform service, including account management, workspace provisioning, subscription billing, and conversational AI interactions with domain-specific agents.

**Legal basis:** Contract performance (Article 6(1)(b) GDPR) -- processing is necessary to provide the Web Platform service you signed up for.

**Retention:** Account data is retained while your account is active and deleted upon account deletion request. Conversation data is retained while the account is active and deleted upon account deletion request (cascade delete via foreign key). Share link records are retained while the link is active and deleted upon revocation or account deletion (cascade delete). Payment records are retained per French tax law (10 years, Code de commerce Art. L123-22).

**Workspace co-member recipients (Article 13(1)(e)).** Where you are a Workspace Owner and the team-workspace feature is enabled for your organization (Section 4.11), Co-Members you invite are recipients of your workspace-scoped activity under this Section 4.7. Where you are a Co-Member, the Workspace Owner and other Co-Members are recipients of your workspace-scoped activity. See Section 4.11 for the bilateral disclosure.

<!-- Added 2026-04-10: KB sharing -->

### 4.8 Content Sharing (Knowledge Base Document Sharing)

The Web Platform allows authenticated users to share individual knowledge base documents via public links. When a document is shared:

- **Data shared publicly:** The document content is accessible to anyone with the share link. Shared pages include noindex meta tags and are not indexed by search engines. No cookies are set for unauthenticated viewers, and the CTA banner on shared pages collects no data (it links to the signup page only).
- **Viewer data collected:** For unauthenticated viewers accessing a shared link, only standard server access logs are collected (IP address, timestamp, user-agent). No additional tracking or analytics is applied to shared page viewers.
- **Share link records:** The Web Platform stores metadata about active share links (document ID, sharing user ID, creation timestamp, share token) in the database. These records are retained while the share link is active and deleted when the owner revokes the link or deletes their account (cascade delete).
- **Legal basis:** Legitimate interest (Article 6(1)(f) GDPR) for processing viewer access logs. Contract performance (Article 6(1)(b) GDPR) for maintaining share link records.
- **Revocation:** The document owner can revoke a share link at any time, which takes immediate effect. After revocation, the shared URL returns an error. However, Jikigai cannot guarantee that recipients have not copied or redistributed the content prior to revocation.

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

<!-- Added 2026-05-19: LinkedIn Company Page publication (#4051) -->

### 4.10 LinkedIn Company Page publication

Jikigai operates the Soleur-branded LinkedIn Company Page at `https://www.linkedin.com/company/jikigai/` as a marketing, community, and case-study distribution channel for Soleur content. The Page is administered by Jikigai SARL as a controller. The legitimate-interest analysis under Article 6(1)(f) for this processing is documented in the standalone Legitimate Interest Assessment at `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`. Article 30 register entry: Processing Activity 15 (`knowledge-base/legal/article-30-register.md`).

- **Data subjects:** (i) **LinkedIn members who follow the Jikigai Page**; (ii) **LinkedIn members who engage with Jikigai Page posts** (reactions, comments, shares); (iii) **the Jikigai SARL gérant** (Jean Deruelle) as a separately-identifiable data subject for the K-bis business-verification transfer to Microsoft Ireland (one-time at appeal-flow step).
- **Data processed (Page operation):** Post content (operator-authored — no Soleur-user personal data; no `@mention` of LinkedIn members; no follower-list extraction to Soleur-controlled storage). Operational secrets (`LINKEDIN_ORG_ACCESS_TOKEN`, 60-day OAuth bearer, Doppler `prd` + GitHub Actions secret; `LINKEDIN_ORG_ID` organisation URN).
- **Data processed (Page Insights consumption):** **Aggregate metrics only** surfaced by LinkedIn Page Insights to the Page admin — impressions, reactions, comments, shares, follower growth. No per-individual decisioning, no profiling on Soleur infrastructure, no cross-referencing against Soleur's own user database.
- **Data processed (K-bis transfer, one-time):** K-bis extract contents (gérant full legal name, Jikigai SARL registered address, French commerce-registry number (RCS Paris 927 585 729), capital structure metadata) plus tax registration and registered-address proof — submitted once to Microsoft Ireland Operations Ltd via the LinkedIn Page admin upload UI; no Soleur-side persistence beyond the operator's local file system at the upload moment.
- **Purpose:** Operating the Jikigai LinkedIn Company Page as a marketing / community / case-study distribution channel for Soleur content; consuming aggregate Page Insights to measure marketing effectiveness; satisfying LinkedIn's business-verification requirements (one-time K-bis transfer) as a precondition to Community Management API access.
- **Legal basis (Page operation + Page Insights):** **Legitimate interest (Article 6(1)(f) GDPR)** — operating a B2B marketing presence on the canonical professional-network platform; the LIA referenced above documents the three-part purpose / necessity / balancing test.
- **Legal basis (K-bis transfer):** **Legal obligation (Article 6(1)(c) GDPR)** — Microsoft's KYC-equivalent business-verification is a condition of Community Management API access under the LinkedIn Platform Terms; Jikigai must transmit corporate identity documents to satisfy the platform-side legal-due-diligence obligation.
- **Joint-controller posture (Page Insights):** Under CJEU C-210/16 *Wirtschaftsakademie Schleswig-Holstein* and EDPB Guidelines 07/2020, the Page admin and LinkedIn Ireland are joint controllers with respect to Page Insights analytics on aggregate visitor data. The standard joint-controller arrangement provided by LinkedIn in its Page Admin terms governs this relationship; the Article 26 information requirements toward data subjects are satisfied via this Section 4.10 and Section 5.12 below.
- **Recipients:** **LinkedIn Ireland Unlimited Company** (independent controller for the Page; joint controller with Jikigai for Page Insights — see Section 5.12); **Microsoft Ireland Operations Ltd** (custodian of business-verification documents — see Section 5.13). No other third-party recipients.
- **Retention:** Posts and engagement metadata are controlled by LinkedIn under its Page-data retention policies — Soleur does not set the envelope. `LINKEDIN_ORG_ACCESS_TOKEN` follows the 60-day vendor-mandated rotation. K-bis extracts retained by Microsoft Ireland under its EU Data Boundary commitments (no Soleur-side persistence). The internal rolling tracker (GitHub Issue #4046) is append-only operational log, closed when queued posts are re-published post-approval.
- **Right of erasure (Article 17) — LinkedIn-published content carve-out:** See Section 8.1 below. Soleur can delete its source copy of any post and issue a corresponding deletion request to LinkedIn, but cannot guarantee removal from LinkedIn's cached or replicated systems.

<!-- End: LinkedIn Company Page publication -->

### 4.11 Workspace co-members

Where the team-workspace feature is enabled for your organization (gated by `FLAG_TEAM_WORKSPACE_INVITE` and the per-organization allowlist `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`), the Web Platform admits additional natural persons ("Co-Members") to access your account. This Section addresses two distinct perspectives — the Workspace Owner and the Co-Member — because the same data is visible to each from a different angle. Article 30 register entry: existing Processing Activity 2 (amended for "workspace co-member" data category in PR #4225).

**From the Workspace Owner's perspective.** When you invite a Co-Member to your workspace, that Co-Member becomes a recipient (Article 13(1)(e) GDPR) of workspace-scoped activity you create — your conversations, knowledge-base queries, BYOK API-key usage records, scope-grant ledger rows, `action_sends` rows (including recipient identifier hashes, body hashes, template hashes), and `template_authorizations` rows. You remain the data controller (Article 4(7) GDPR) for everything processed under your account; you indemnify Jikigai for the Co-Member's use of the account under Terms & Conditions Section 3b.3, including for the Co-Member's access to and onward disclosure of the workspace's send-audit ledgers.

**From the Co-Member's perspective.** If you accept an invitation to join a workspace, your activity (conversations you participate in, knowledge-base queries you submit, sends and template authorizations you create under the workspace's grants) is visible to the Workspace Owner and to other Co-Members of the same workspace. The Workspace Owner is the controller of the workspace's data under Terms & Conditions Section 3b.1; your independent rights of access, rectification, erasure, restriction, portability, and objection (Articles 15 through 22 GDPR) against Jikigai over rows identifiable to you are unaffected by your membership in the workspace. The Workspace Owner is responsible for ensuring you are bound by appropriate confidentiality, intellectual-property assignment, and workspace-activity-logged acknowledgement terms covering Terms & Conditions Section 3b. The Owner may satisfy this by any sufficient means, including reliance on your click-through acceptance of these Terms (sufficient for confidentiality but NOT by itself sufficient for IP assignment), reliance on an existing employment/contractor/consultancy agreement between you and the Owner, or execution of the optional Soleur Side Letter template (`knowledge-base/legal/side-letter-template.md`) as a separate bilateral instrument with you.

**Technical measure.** Cross-member visibility scope is enforced by the SECURITY DEFINER `is_workspace_member(workspace_id, user_id)` helper (migration 053) wired into the row-level-security predicates on the six affected tables. The Data Protection Disclosure Section 2.3(u) records the categories and the lawful-basis cross-reference.

**Recipients (Article 13(1)(e)).** Co-Members of your workspace; no other third-party recipients. Co-Members are NOT processors under Article 28 GDPR (see Data Protection Disclosure Section 4.2 carve-out); access is contract-mediated under the Anthropic Commercial Terms §C "authorized users" framework.

<!-- End: Workspace co-members -->

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

### 5.12 LinkedIn Ireland Unlimited Company (LinkedIn Company Page)

We operate the Soleur LinkedIn Company Page at `https://www.linkedin.com/company/jikigai/`. **LinkedIn Ireland Unlimited Company** ([linkedin.com](https://www.linkedin.com)) is an independent controller for the LinkedIn platform and a **joint controller** with Jikigai for Page Insights analytics (per CJEU C-210/16 *Wirtschaftsakademie* and EDPB Guidelines 07/2020).

- **Data processed:** Posts published by Jikigai (operator-authored content); aggregate Page Insights metrics (impressions, reactions, comments, shares, follower growth); follower identifiers (display name + profile URL slug, voluntarily made public by the follower); engagement metadata (timestamps, reaction type, comment body).
- **Purpose:** Operating the Jikigai Company Page as a B2B marketing / community / case-study distribution channel for Soleur content; consuming aggregate Page Insights to measure marketing effectiveness.
- **DPA / Joint-controller arrangement:** [LinkedIn Subscription Agreement](https://www.linkedin.com/legal/l/subscription-agreement) and the [LinkedIn Pages Terms](https://www.linkedin.com/legal/l/pages-terms), incorporating the standard joint-controller arrangement for Page Insights. The arrangement is accepted by Jikigai SARL via its Page admin role on the `jikigai` Page slug.
- **Storage location:** LinkedIn operates EU-region infrastructure for Page data with US fallback. International transfers governed by EU-US Data Privacy Framework (DPF) and Standard Contractual Clauses (SCCs), Module 2.
- **Legal basis:** Legitimate interest (Article 6(1)(f) GDPR) — operating the marketing channel and consuming aggregate Page Insights. The full three-part test is documented at `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`.
- **Data subject rights:** LinkedIn members exercise their rights under LinkedIn's own data-subject-request flows for data LinkedIn holds about them; for the Jikigai-specific Page admin's aggregate analytics, contact <legal@jikigai.com>. See Section 8.1 "LinkedIn-published content carve-out" for the Article 17 limitation.

### 5.13 Microsoft Ireland Operations Ltd (LinkedIn business verification)

We use **Microsoft Ireland Operations Ltd** (a Microsoft subsidiary; Microsoft is LinkedIn's parent company) as the custodian of the K-bis business-verification documents required by LinkedIn's Community Management API access flow. Microsoft Ireland acts as a **separate controller** for the document-custody role (distinct from LinkedIn Ireland's role as Page-data controller).

- **Data processed:** K-bis extract contents (gérant full legal name, Jikigai SARL registered address, French commerce-registry number (RCS Paris 927 585 729), capital structure metadata) plus tax registration and registered-address proof. **One-time transfer** at the appeal-flow step; no ongoing transfer.
- **Purpose:** Satisfying LinkedIn's KYC-equivalent business-verification requirement as a precondition to Community Management API access under the LinkedIn Platform Terms.
- **DPA:** Microsoft's controller-to-controller transfer terms apply; document custody falls under [Microsoft's EU Data Boundary](https://aka.ms/EUDataBoundary) commitments.
- **Storage location:** Microsoft routes verification documents under its EU Data Boundary; onward transfer safeguards rest on Microsoft's published EUDB scope (intra-EU at custody).
- **Legal basis:** Legal obligation (Article 6(1)(c) GDPR) — Microsoft's verification process is a condition of LinkedIn API access under the LinkedIn Platform Terms, and Jikigai must transmit corporate identity documents to satisfy the platform-side legal-due-diligence obligation.
- **Retention:** Controlled by Microsoft Ireland under its EUDB commitments — typical KYC retention envelope (years). Jikigai does not retain a Soleur-side copy beyond the operator's local file system at the upload moment.
- **Note on natural-person disclosure:** The K-bis extract names the SARL gérant (Jean Deruelle) as a natural person; this is a controller-to-controller transfer of natural-person data per CNIL délibération SAN-2024-006. The gérant is informed of this transfer via this Section 5.13 and via Section 4.10 above.

### 5.14 Better Stack s.r.o. (Operational Log Aggregation)

We use **Better Stack Logs** ([betterstack.com](https://betterstack.com)) for off-host long-tail operational log aggregation on the Web Platform inngest plane. **Better Stack s.r.o.** (Czech Republic) acts as a data processor on our behalf. This is a separate processor role from the existing Better Stack heartbeat surface disclosed in the Data Protection Disclosure §2.3(m)(i) — the heartbeat carries an opaque ping payload and no personal data.

- **Data processed:** journald log lines (mirrors pino stdout from `inngest-server.service`) and host_metrics scrapes (CPU, memory, disk, filesystem, load, network) shipped from the Hetzner inngest VM via the Vector agent. Log lines may incidentally include pseudonymous user identifiers (`userIdHash`), conversation IDs, request metadata, and error stack traces, scoped to the inngest plane's failure surface. Application-layer user-content keys (`body`, `content`, `message`, `userMessage`, `prompt`, `chat_message`, `userInput`, `user_input`) are explicitly dropped at the Vector boundary before egress to mitigate Article 9 special-category-data exposure.
- **Pseudonymisation:** User identifiers are pseudonymised at the Vector boundary by replacing the raw `userId` / `user_id` with a keyed cryptographic hash (`userIdHash`) using a server-resident secret pepper held in Doppler. The Vector VRL transform reuses the same `SENTRY_USERID_PEPPER` as the Sentry pseudonymisation pipeline (architectural single-source-of-truth per ADR-029 §I4), and computes `HMAC-SHA256` + `base16` encoding bit-for-bit equivalent to the TS `hashUserId` primitive (parity asserted by CI fixture `apps/web-platform/test/infra/vector-pii-scrub.test.sh`). Under GDPR Recital 26, the controller cannot re-identify a data subject from the hash alone without the pepper, which is not shared with Better Stack.
- **Purpose:** Long-tail diagnostic recall beyond the 30 MB Hetzner Docker json-file rolling buffer — enables operator query of journald lines older than ~24 hours without production-host SSH (per the no-SSH operational rule that governs incident-response runbooks).
- **DPA:** [Better Stack DPA](https://betterstack.com/legal/dpa) is available for execution under standard EU-region terms (SCCs incorporated as belt-and-braces against any future routing change). The Vendor DPA Status table in `knowledge-base/legal/compliance-posture.md` tracks the signing state; signing is an open operator action under AC15 of PR #4293 and will be reflected here on completion.
- Better Stack processes data in the **EU region — Hetzner Falkenstein cluster `eu-fsn-3`** (Germany), pinned by per-source ingest URL (`https://s2457081.eu-fsn-3.betterstackdata.com/`) in `apps/web-platform/infra/vector.toml`. **Intra-EU processing — no third-country transfer.**
- **Retention:** Better Stack paid-tier default for journald + host_metrics. Hashed identifiers and operational metadata age out per the processor retention window.
- **Legal basis:** **Legitimate interest** (Article 6(1)(f) GDPR) for service reliability, diagnostic recall, and incident response, balanced against the pseudonymisation safeguard and the user-content key drop at the Vector boundary.
- **Right to erasure (Article 17):** Hashed identifiers age out per the rolling retention window; the controller cannot perform processor-side targeted erasure of a pseudonym whose subject cannot be re-identified, consistent with the same Recital 26 treatment applied to Sentry events.

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
- **Web Platform data:** Account data (email, auth tokens) is retained while your account is active and deleted upon account deletion request. Conversation data (messages and conversation metadata) is retained while the user's account is active and deleted upon account deletion request (cascade delete via foreign key). Encrypted API keys are deleted with the associated workspace. Payment records (subscription metadata, invoices) are retained for 10 years per French tax law (Code de commerce Art. L123-22).
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

For the Plugin, these rights are most relevant to your interactions with GitHub (the hosting platform). For the Web Platform (app.soleur.ai), you may exercise these rights directly against Jikigai for account data, workspace data, conversation data, and subscription data by contacting <legal@jikigai.com>. You may request export of your conversation history (messages and metadata) in a structured, machine-readable format under the right to data portability (Article 20). Conversation-history exports reflect the persistence limitation described in Section 4.7. To exercise rights related to GitHub-collected data, contact GitHub directly through their privacy channels.

**Departed workspace members (`workspace_member_removals` audit ledger).** Where the team-workspace feature is enabled for a Workspace Owner's organization (gated by `FLAG_TEAM_WORKSPACE_INVITE`), the Web Platform records a write-once-read-many (WORM) audit row in the `workspace_member_removals` ledger whenever a Co-Member is removed from a workspace (introduced by migration 062 / PR #4294 — Article 30 register Processing Activity 19, distinct from PA-20 covering the broader `workspace_member_actions` membership-mutation log from migration 063 / PR #4231). The departed Co-Member remains identifiable in that row via `removed_user_id` for at least 36 months (shortest-applicable-jurisdiction Article 82(2) limitations floor) after removal. If you have been removed from a workspace, you retain rights against Jikigai over your identifiable removal-event row independently of any continuing account relationship with Jikigai: **Article 15 (access)** — request a copy of your row via the channels below; **Article 17 (erasure)** — your removal-event row is anonymised as part of the account-deletion cascade via the `anonymise_workspace_member_removals(p_user_id)` SECURITY DEFINER RPC at step 3.905 in `server/account-delete.ts`, which runs BEFORE the broader `anonymise_workspace_members` cascade DELETE (step 3.91), BEFORE `anonymise_workspace_member_actions` (step 3.93, PA-20), and BEFORE `auth.admin.deleteUser` (step 4); the RPC NULL-sets both PII columns (`removed_user_id` and `removed_by_user_id`) on every row where either matched you; lineage columns (`id`, `removed_at`) are preserved post-erasure as Article 5(2) accountability evidence of the removal event itself, and `workspace_id` is preserved while the parent workspace exists (it may transition to NULL via its `ON DELETE SET NULL` FK if the parent workspace and organization are deleted as part of the orphan-org cleanup at step 3.92, per ADR-039); **Article 20 (portability)** — the row is included in the self-serve DSAR ZIP export at `/dashboard/settings/privacy` and in the email-channel manual export. Because departed Co-Members cannot read their own removal row via the workspace's row-level-security predicate after removal (the SECURITY DEFINER `is_workspace_member()` helper returns false post-removal), Article 15 requests grounded on `workspace_member_removals` are fulfilled via the service-role DSAR worker — email <legal@jikigai.com> if you are not currently signed in to the Web Platform, or use the self-serve flow at `/dashboard/settings/privacy` if you still hold an account. See Section 4.11 "Workspace co-members" for the data-class disclosure of the underlying membership substrate.

### 8.2 Rights Under US Privacy Laws

Users in the United States may have additional rights under state privacy laws (such as the California Consumer Privacy Act). For the Plugin, these rights are primarily relevant to any data collected by GitHub as the hosting provider. For the Web Platform, you may exercise these rights by contacting <legal@jikigai.com>.

### 8.3 Automated decision-making and Article 22 rights

The Web Platform includes agent-runtime features that can produce decisions on your behalf in response to external events (for example, a Stripe `invoice.payment_failed` webhook). These features are governed by Section 3a ("Agent Command Authority") of the Terms & Conditions and, on the data-protection side, by this section and by Section 2.3(o) of the Data Protection Disclosure.

**Opt-in by class and tier.** The Web Platform performs no automated action on your behalf for an action class (for example, `finance.payment_failed`, `external.low_stakes.customer_status_update`, `infra.dependency_bump`) unless you have explicitly granted authorization for that class via the `/dashboard/settings/scope-grants` interface, at one of four tiers: `Approve every time` (you authorize each instance, typing `SEND` verbatim at click-time for brand-critical classes), `Draft, one click` (the agent prepares a draft you approve), `Auto` (the agent executes without per-instance approval, after a second-click acknowledgement at grant time), or `Auto with daily digest` (the agent executes infrastructure-class actions and summarizes them in a next-business-day digest you review). The absence of a grant is a denial; the `/dashboard/audit` viewer renders every automated action with the action class, tier active at the moment of the event, timestamp, and BYOK token + cost data. For infrastructure-class actions (`Auto with daily digest`), the right to human review under Article 22(3) is exercised via the next-business-day digest review window provided in the Today section -- you may revoke the grant or re-classify the action class at any time at `/dashboard/settings/scope-grants`.

**Article 22 rights.** Where automated processing produces a decision concerning you (in particular, any action under the `Auto` or `Auto with daily digest` tier), you have the right under Article 22(3) GDPR to:

- **Obtain human intervention** -- request that a human review the decision;
- **Express your point of view** -- submit your perspective on the decision; and
- **Contest the decision** -- challenge its accuracy or appropriateness.

You may exercise these rights through the "Request human review" affordance inlined on every row of `/dashboard/audit`, or by emailing <legal@jikigai.com>. We will provide a substantive response within the timeframes required by applicable law.

**Profiling.** Soleur does not profile users for advertising or third-party data brokerage. Within the Web Platform, automated decision-making is bounded to the explicit action classes you grant; no inferred profile is built from the resulting activity beyond the audit ledger required to make the decisions reviewable. Sub-processors are enumerated in Section 5 of this Policy and in Section 2.3(o) of the Data Protection Disclosure.

**Template-level authorization and revocation (PR-I, May 2026).** In addition to the class-level grants described above, the Web Platform records a per-template authorization layer when you click Send for the first time on a `Draft, one click` action: the Send click on a labeled `draft_one_click` button -- with the typed-confirm context applied to brand-critical classes -- IS the Article 7(3) "specific" + "informed" consent act under the first-send-IS-authorization pattern. The authorization carries provisional bounds (90-day expiry, 30-day soft re-confirmation, 100-send quota) that you can revoke at any time at `/dashboard/settings/scope-grants`. The Article 7(3) "as easily withdrawable as given" right is satisfied by the per-row Revoke button on the same surface; revoking is one click and produces an append-only audit row recording the revocation reason. Subsequent send attempts gate on the bounds; expiry or quota-exhaustion are surfaced inline on the draft card and re-click to re-authorize re-starts the 100-send window. The forward-reference: a follow-up release (PR-I+1, #4216) will add a retroactive-reclassification surface that lets you mark a prior send as misclassified and have the corresponding authorization quarantined automatically. Article 30 register entry: Processing Activity 18 (`knowledge-base/legal/article-30-register.md`); Data Protection Disclosure cross-reference: Section 2.3(t).

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

The Web Platform at app.soleur.ai uses strictly necessary cookies for authentication (Supabase session cookies) and payment security (Stripe fraud prevention cookies). These cookies are exempt from consent requirements under ePrivacy Directive Article 5(3). For full details, see the [Cookie Policy](/legal/cookie-policy/).

## 13. Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be posted to the GitHub repository and/or the Docs Site. The "Last Updated" date at the top of this document will be revised accordingly.

For material changes, we will make reasonable efforts to notify users (e.g., through a repository release note or a notice on the Docs Site).

## 14. Legal Entity and Contact Us

Soleur is a source-available project maintained by Jikigai, a company incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France.

GDPR Article 27 requires a representative in the EU for controllers not established in the EU. Because Jikigai is incorporated in France, Article 27 does not apply.

If you have questions about this Privacy Policy or our data practices, you can reach us through:

- **Email:** <legal@jikigai.com>
- **GitHub:** Open an issue at [github.com/jikig-ai/soleur](https://github.com/jikig-ai/soleur)
- **Website:** [soleur.ai](https://www.soleur.ai)
- **GDPR / Data Protection Inquiries:** <legal@jikigai.com> (include "GDPR" in the subject line)

To exercise your data subject rights under GDPR, send a written request to <legal@jikigai.com>. We will acknowledge your request within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3). This period may be extended by two further months where necessary, taking into account the complexity or volume of requests, in which case we will inform you of the extension and reasons within the initial one-month period.

---

> **Related documents:** This Privacy Policy should be read alongside the companion [Cookie Policy](/legal/cookie-policy/) for detailed information about cookies used by the Docs Site (GitHub Pages), the [GDPR Policy](/legal/gdpr-policy/) for detailed GDPR-specific disclosures, and the [Individual Contributor License Agreement](/legal/individual-cla/) for details on contributor data processing.

    </div>
  </div>
</section>
