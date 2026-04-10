---
title: "Terms & Conditions"
description: "Terms and Conditions governing use of the Soleur platform."
layout: base.njk
permalink: legal/terms-and-conditions/
---

<section class="page-hero">
  <div class="container">
    <h1>Terms & Conditions</h1>
    <p>Effective February 20, 2026</p>
  </div>
</section>

<section class="content">
  <div class="container">
    <div class="prose">

**Soleur -- Company-as-a-Service Platform**

**Effective Date:** February 20, 2026

**Last Updated:** March 20, 2026 -- added Web Platform service terms, scoped local-only statements to Plugin, updated data practices and GDPR rights sections for Web Platform; added subscription cancellation, refund, and EU withdrawal policy (Section 5); added Article 12(3) two-month extension provision to response timeline.

---

## 1. Introduction and Acceptance

These Terms & Conditions ("Terms") govern your access to and use of the Soleur platform ("Soleur," "the Plugin," "the Service") and the Soleur Web Platform at app.soleur.ai ("the Web Platform"), Company-as-a-Service products developed and maintained by Jikigai ("we," "us," "our"), a company incorporated in France with its registered office at 25 rue de Ponthieu, 75008 Paris, France. Soleur is a Claude Code plugin that provides AI-powered agents, skills, commands, and a compounding knowledge base for structured software development workflows. The Web Platform is a cloud-hosted companion service providing account management, workspace environments, and subscription services.

By installing, accessing, or using Soleur (whether the Plugin or the Web Platform), you ("User," "you," "your") agree to be bound by these Terms. If you do not agree to these Terms, do not install or use the Plugin or the Web Platform.

These Terms apply to all Users globally, with specific provisions for Users in the European Union / European Economic Area (EU/EEA) under the General Data Protection Regulation (GDPR) and Users in the United States.

## 2. Definitions

- **"Plugin"** refers to the Soleur Claude Code plugin, including all agents, skills, commands, configuration files, and knowledge-base components.
- **"Knowledge Base"** refers to the locally stored collection of brainstorms, plans, specs, learnings, and other artifacts generated during use.
- **"Documentation Site"** refers to the website hosted at soleur.ai on GitHub Pages.
- **"Third-Party Services"** refers to external services accessed through or in connection with the Plugin, including but not limited to the Anthropic Claude API, GitHub, and GitHub Pages.
- **"Account Data"** refers to email address, authentication tokens, session data, and other information provided during Web Platform registration and use.
- **"Subscription"** refers to a paid plan for Web Platform access, managed through Stripe Checkout.
- **"User Content"** refers to all data, files, configurations, and artifacts created, modified, or stored by the User through the Plugin.
- **"Web Platform"** refers to the Soleur cloud-hosted service at app.soleur.ai, including account management, workspace environments, and subscription services.

## 3. Eligibility

You must be at least 18 years of age (or the age of majority in your jurisdiction) to use the Plugin or the Web Platform. By using Soleur, you represent and warrant that you meet this requirement.

If you are using the Plugin or the Web Platform on behalf of an organization, you represent and warrant that you have the authority to bind that organization to these Terms.

## 4. Description of the Service

Soleur is a locally installed Claude Code plugin that provides:

- **{{ stats.agents }} AI agents** organized across {{ stats.departments }} domains ({{ agents.departmentList }})
- **{{ stats.skills }} skills** for structured software development workflows
- A **compounding knowledge base** that stores project context locally
- **Commands** for orchestrating development workflows (brainstorm, plan, review, work, ship)

### 4.1 Local-First Architecture

The Plugin is installed and operates locally on your machine via the Claude Code CLI. All knowledge-base files, configuration data, and Plugin-generated User Content are stored exclusively on your local file system. The Plugin does not collect, transmit, or store your data on remote infrastructure controlled by us.

This section applies to the Plugin only. For the Web Platform, see Section 4.3 below.

### 4.2 Third-Party API Interactions

The Plugin facilitates interactions with the Anthropic Claude API and other third-party services. These interactions occur through your own API keys and accounts. You are solely responsible for:

- Maintaining the security of your API keys and credentials
- Complying with the terms of service of all third-party providers
- Any costs or charges incurred through third-party API usage

### 4.3 Web Platform Service

The Soleur Web Platform at [app.soleur.ai](https://app.soleur.ai) is a cloud-hosted service operated by Jikigai. Unlike the Plugin (Section 4.1), the Web Platform processes data on Jikigai-operated infrastructure.

When you create a Web Platform account:

- You provide an email address and authenticate via magic link or an OAuth provider (Google, Apple, GitHub, or Microsoft). Authentication credentials are managed by Supabase. If you use OAuth, your provider user ID, display name, and profile picture URL are stored. Accounts with matching verified email addresses are automatically linked.
- You may store encrypted API keys (BYOK -- bring your own key) in your workspace.
- If you subscribe to a paid plan, payment is processed by Stripe via Stripe Checkout. Card data is handled exclusively by Stripe and never reaches Jikigai servers.

The Web Platform is hosted on Hetzner servers in Helsinki, Finland (EU) and uses Cloudflare as a CDN/proxy. Full data processing details are described in the [Privacy Policy](/legal/privacy-policy/) Section 4.7.

By creating a Web Platform account, you accept these Terms and acknowledge that your data will be processed as described in the Privacy Policy. Acceptance requires checking the "I agree to the Terms & Conditions and Privacy Policy" checkbox on the signup page before account creation. The checkbox is unchecked by default; you must actively check it to proceed. Your acceptance is timestamped and recorded.

## 5. Subscriptions, Cancellation, and Refunds

Subscriptions renew automatically at the end of each billing period (monthly or annually, as selected at checkout) unless cancelled.

### 5.1 Cancellation

You may cancel your Subscription at any time. Cancellation takes effect at the end of the current billing period. You will retain access to paid features until the end of the period for which you have already paid.

### 5.2 Account Deletion with Active Subscription

If you delete your Web Platform account while a Subscription is active, the deletion triggers cancellation of your Subscription effective at the end of the current billing period. Account data is deleted as described in Section 14.1b.

### 5.3 EU Right of Withdrawal

If you are a consumer in the EU/EEA, you have a 14-day right of withdrawal under Directive 2011/83/EU. However, by subscribing and requesting immediate access to the Web Platform's paid features, you expressly consent to the performance of the digital service beginning immediately and acknowledge that you thereby waive your right of withdrawal in accordance with Article 16(m) of Directive 2011/83/EU. If you do not consent to immediate access, your access to paid features will begin after the 14-day withdrawal period has expired, during which you may withdraw and receive a full refund. To exercise your right of withdrawal, contact <legal@jikigai.com> or use the model withdrawal form available upon request.

### 5.4 Refunds

Except as required by applicable law (including the EU right of withdrawal described in Section 5.3), all Subscription fees are non-refundable. Jikigai may, at its sole discretion, issue refunds or credits on a case-by-case basis. Any discretionary refund does not entitle you to future refunds in similar circumstances.

## 6. License and Intellectual Property

### 6.1 License Grant

The Plugin is licensed under the Business Source License 1.1 (BSL 1.1). Subject to your compliance with these Terms and the BSL 1.1 license, you may copy, modify, create derivative works, redistribute, and make production use of the Plugin for your personal or internal business purposes.

### 6.2 Restrictions

You shall not:

- Offer the Plugin to third parties on a hosted or managed basis in order to compete with Jikigai's commercial offerings
- Reverse engineer, decompile, or disassemble the Plugin except as expressly permitted by applicable law (including EU Directive 2009/24/EC on the legal protection of computer programs)
- Remove, alter, or obscure any proprietary notices, labels, or marks
- Use the Plugin in any manner that violates applicable laws or regulations

Each version of the Plugin converts to the Apache License 2.0 four years after its publication date. Prior versions (v3.0.10 and earlier) remain under the Apache License 2.0.

### 6.3 User Content Ownership

You retain all rights, title, and interest in your User Content. We claim no ownership over any files, knowledge-base entries, code, or artifacts generated or stored on your local machine through use of the Plugin. For the Web Platform, you retain all rights to data you store in your workspaces, including encrypted API keys and workspace configurations.

### 6.4 Our Intellectual Property

All rights, title, and interest in and to the Plugin (including agent definitions, skill configurations, command logic, and documentation) remain with us. These Terms do not grant you any rights to our trademarks, service marks, or trade names.

### 6.5 Contributor Intellectual Property

If you contribute code or other materials to the Soleur project via pull requests, you must sign a Contributor License Agreement (CLA) before your contribution can be accepted. The CLA grants Jikigai a perpetual, irrevocable license to use, modify, sublicense, and relicense your contribution, while you retain your copyright. The CLA includes an express patent grant covering contributed code. Full terms are set out in the [Individual Contributor License Agreement](/legal/individual-cla/) and [Corporate Contributor License Agreement](/legal/corporate-cla/).

## 7. AI-Generated Output

### 7.1 Nature of AI Output

Soleur leverages AI models to generate code, documentation, legal document drafts, plans, reviews, and other content. All AI-generated output is provided on an "as-is" basis and:

- May contain errors, inaccuracies, or omissions
- Does not constitute professional advice (legal, financial, technical, or otherwise)
- Requires human review and validation before use in production or business-critical contexts

### 7.2 Legal Document Generation

The Plugin includes a legal document generation capability. Documents generated by this feature are explicitly marked as drafts requiring professional legal review. These generated documents do not constitute legal advice and should not be relied upon without review by a qualified legal professional.

### 7.3 Responsibility for Output

You are solely responsible for reviewing, validating, and assuming liability for any AI-generated output you choose to use, publish, deploy, or distribute.

## 8. Data Practices and Privacy

### 8.1 Local Data Storage

Soleur operates on a local-first model. The Plugin itself does not collect, transmit, or store personal data on external servers. All User Content, configuration files, and knowledge-base entries remain on your local machine under your control.

This section applies to the Plugin only. For Web Platform data practices, see Section 8.1b and the [Privacy Policy](/legal/privacy-policy/) Section 4.7.

### 8.1b Web Platform Data Practices

The Soleur Web Platform collects and processes personal data as necessary to provide the service. This includes:

- **Account data** (email, authentication tokens) processed by Supabase (EU-hosted, AWS eu-west-1, Ireland).
- **Payment data** processed by Stripe (PCI SAQ-A -- card data handled exclusively by Stripe).
- **Workspace data** (encrypted API keys, workspace configurations) hosted on Hetzner (Helsinki, Finland, EU).
- **Technical data** (IP addresses, request headers) processed by Cloudflare CDN/proxy.

For comprehensive data processing details, legal bases, retention periods, and your rights, see the [Privacy Policy](/legal/privacy-policy/) and [GDPR Policy](/legal/gdpr-policy/).

<!-- Added 2026-04-10: KB sharing -->

### 8.1c Shared Content

The Web Platform allows you to share individual knowledge base documents via public links. By using this feature:

- **Your responsibility:** You are solely responsible for the content you choose to share. You must ensure that shared documents do not contain confidential third-party information, personally identifiable information of others without their consent, or material that infringes third-party intellectual property rights. See the [Acceptable Use Policy](/legal/acceptable-use-policy/) for detailed rules.
- **Jikigai's role:** Jikigai acts as a processor making the document content available at the shared URL on your instruction. Jikigai does not review, moderate, or approve shared content prior to publication.
- **Revocation:** You may revoke a share link at any time from the Web Platform. Revocation takes immediate effect. However, Jikigai cannot guarantee that recipients have not copied, downloaded, or redistributed the content prior to revocation.
- **No warranty of recipient conduct:** Jikigai makes no representation regarding how recipients will use shared content and accepts no liability for any downstream use by recipients.

<!-- End: KB sharing -->

### 8.2 Documentation Site

The Soleur documentation site (soleur.ai) is hosted on GitHub Pages. GitHub, as the hosting provider, may collect certain data such as IP addresses and browser metadata in accordance with GitHub's own privacy practices. We do not control GitHub's data collection. Please refer to GitHub's Privacy Statement for details.

### 8.3 Third-Party Data Processing

When the Plugin facilitates interactions with the Anthropic Claude API or other third-party services, data transmitted to those services is governed by their respective privacy policies and terms of service. We are not responsible for the data practices of third-party service providers.

### 8.4 EU/EEA Users -- GDPR Rights

If you are located in the EU/EEA, you have rights under the GDPR including the right of access, rectification, erasure, restriction of processing, data portability, and objection.

For the Plugin, these rights are inherently satisfied by your local control over Plugin-generated data.

For the Web Platform, you may exercise these rights against Jikigai by contacting <legal@jikigai.com>. See the [GDPR Policy](/legal/gdpr-policy/) Section 5 for full details on how to exercise each right.

For any GDPR-related inquiries concerning the documentation site or third-party integrations, please contact us through the channels listed in Section 17.

## 9. Acceptable Use

You agree to use the Plugin and the Web Platform only for lawful purposes and in accordance with these Terms. You shall not use the Plugin or the Web Platform to:

- Violate any applicable local, national, or international law or regulation
- Generate, store, or distribute content that is illegal, harmful, threatening, abusive, defamatory, or otherwise objectionable
- Infringe on the intellectual property rights of any third party
- Attempt to gain unauthorized access to systems, networks, or data
- Introduce malware, viruses, or other harmful code
- Circumvent, disable, or interfere with security features of the Plugin or connected services
- Use the Plugin for automated decision-making that produces legal effects on individuals without appropriate human oversight, as required under GDPR Article 22

## 10. Disclaimer of Warranties

### 10.1 "As Is" Provision

THE PLUGIN AND THE WEB PLATFORM ARE PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, AND ACCURACY.

### 10.2 No Guarantee of Availability or Accuracy

We do not warrant that the Plugin or the Web Platform will be uninterrupted, error-free, secure, or free of harmful components. We do not warrant the accuracy, completeness, or reliability of any output generated by the Plugin's AI capabilities. The Web Platform does not include a Service Level Agreement (SLA). No specific uptime, response time, or availability guarantees are provided.

### 10.3 EU Consumer Rights

Nothing in this section limits or excludes any warranty rights that you may have under mandatory applicable law, including EU consumer protection legislation. If you are a consumer in the EU/EEA, you benefit from mandatory statutory warranty rights that cannot be waived or limited by contract.

## 11. Limitation of Liability

### 11.1 General Limitation

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL WE BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF PROFITS, DATA, BUSINESS OPPORTUNITIES, OR GOODWILL, ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF THE PLUGIN OR THE WEB PLATFORM.

### 11.2 Aggregate Liability Cap

OUR TOTAL AGGREGATE LIABILITY TO YOU FOR ALL CLAIMS ARISING OUT OF OR RELATING TO THESE TERMS OR YOUR USE OF THE PLUGIN OR THE WEB PLATFORM SHALL NOT EXCEED THE GREATER OF (A) THE AMOUNT YOU PAID US (IF ANY) IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM, OR (B) ONE HUNDRED EUROS (EUR 100).

### 11.3 EU/EEA Limitations

For Users in the EU/EEA, the limitations in this section apply only to the extent permitted by applicable law. Nothing in these Terms excludes or limits liability for:

- Death or personal injury caused by negligence
- Fraud or fraudulent misrepresentation
- Any liability that cannot be excluded or limited under applicable EU or member state law

## 12. Indemnification

You agree to indemnify, defend, and hold harmless Jikigai and its affiliates, contributors, and licensors from and against any claims, damages, losses, liabilities, costs, and expenses (including reasonable attorneys' fees) arising out of or relating to:

- Your use of the Plugin or the Web Platform
- Your violation of these Terms
- Your violation of any applicable law or regulation
- Your User Content
- Your use or misuse of AI-generated output

For EU/EEA Users, this indemnification obligation applies only to the extent permissible under applicable law and does not require you to indemnify us for losses caused by our own negligence or breach.

## 13. Modifications to the Terms

We reserve the right to modify these Terms at any time. Changes will be posted to the Soleur GitHub repository (jikig-ai/soleur) and/or the documentation site (soleur.ai). Material changes will be communicated through the repository's release notes or changelog.

Your continued use of the Plugin or the Web Platform after changes take effect constitutes acceptance of the modified Terms. If you do not agree to the modified Terms, you must stop using the Plugin and the Web Platform.

For EU/EEA Users, we will provide reasonable advance notice of material changes (at least 30 days where practicable) and you may terminate your use of the Plugin or the Web Platform if you do not accept the modified Terms.

## 14. Termination

### 14.1 Termination by You

You may stop using the Plugin at any time by uninstalling it from your Claude Code environment. No notice to us is required.

### 14.1b Termination of Web Platform Account

You may delete your Web Platform account at any time. Upon account deletion:

- Account data (email, authentication tokens) is deleted from Supabase.
- Workspace data and encrypted API keys are deleted from Hetzner.
- Payment records (subscription metadata, invoices) are retained for 10 years per French tax law (Code de commerce Art. L123-22).

If a Subscription is active at the time of account deletion, it is handled as described in Section 5.2.

For details on data retention after account deletion, see the [Privacy Policy](/legal/privacy-policy/) Section 7.

### 14.2 Termination by Us

We may suspend or terminate your right to use the Plugin or the Web Platform for cause, including but not limited to violation of these Terms. For EU/EEA Users, we will provide at least 30 days' notice before termination takes effect, except where termination is necessitated by a legal obligation or where the User has repeatedly or materially breached these Terms.

### 14.3 Effect of Termination

Upon termination, your license to use the Plugin ceases. Plugin-generated User Content remains on your local machine under your control. For the Web Platform, account termination triggers data deletion as described in Section 14.1b.

Sections 5.4, 6.4, 7, 8, 10, 11, 12, 15, and 16 survive termination.

## 15. Governing Law and Dispute Resolution

### 15.1 Governing Law

These Terms shall be governed by and construed in accordance with the laws of France, without regard to its conflict of laws provisions.

### 15.2 Jurisdiction

Any disputes arising under or in connection with these Terms shall be subject to the exclusive jurisdiction of the courts of Paris, France.

### 15.3 EU/EEA Consumers

If you are a consumer in the EU/EEA, nothing in these Terms affects your rights under mandatory EU or member state consumer protection laws, including your right to bring proceedings in the courts of your country of habitual residence. The European Commission provides an Online Dispute Resolution (ODR) platform at <https://ec.europa.eu/consumers/odr>. We are not obligated to participate in ODR procedures but will consider doing so on a case-by-case basis.

## 16. General Provisions

### 16.1 Entire Agreement

These Terms, together with any referenced policies (including our Privacy Policy and Acceptable Use Policy), constitute the entire agreement between you and us regarding your use of the Plugin and the Web Platform.

### 16.2 Severability

If any provision of these Terms is found to be unenforceable or invalid, that provision shall be limited or eliminated to the minimum extent necessary, and the remaining provisions shall remain in full force and effect.

### 16.3 Waiver

Our failure to enforce any right or provision of these Terms shall not constitute a waiver of that right or provision.

### 16.4 Assignment

You may not assign or transfer these Terms or your rights hereunder without our prior written consent. We may assign these Terms without restriction.

### 16.5 Force Majeure

We shall not be liable for any failure or delay in performance resulting from causes beyond our reasonable control, including but not limited to natural disasters, war, terrorism, pandemics, government actions, or failures of third-party services.

### 16.6 No Third-Party Beneficiaries

These Terms do not confer any rights on any third party unless expressly stated.

## 17. Legal Entity and Contact Information

Soleur is a source-available project maintained by Jikigai, a company incorporated in France, with its registered office at 25 rue de Ponthieu, 75008 Paris, France. These Terms are offered by Jikigai on behalf of the Soleur project.

For questions or concerns regarding these Terms, please contact us through:

- **Email:** <legal@jikigai.com>
- **GitHub Repository:** [github.com/jikig-ai/soleur](https://github.com/jikig-ai/soleur)
- **Website:** [soleur.ai](https://soleur.ai)
- **Issues:** [github.com/jikig-ai/soleur/issues](https://github.com/jikig-ai/soleur/issues)
- **GDPR / Data Protection Inquiries:** <legal@jikigai.com> (include "GDPR" in the subject line)

To exercise your data subject rights under GDPR, send a written request to <legal@jikigai.com>. We will acknowledge your request within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3). This period may be extended by two further months where necessary, taking into account the complexity or volume of requests, in which case we will inform you of the extension and reasons within the initial one-month period.

---

> **Related documents:** This Terms & Conditions document references privacy practices, data handling, cookies, acceptable use policies, and contributor agreements. Please review the companion documents:
>
> - [Privacy Policy](/legal/privacy-policy/) -- details data practices referenced in Section 8
> - [Acceptable Use Policy](/legal/acceptable-use-policy/) -- expands on the acceptable use provisions in Section 9
> - [Cookie Policy](/legal/cookie-policy/) -- covers cookies used by the documentation site
> - [Disclaimer](/legal/disclaimer/) -- standalone version of warranty and liability provisions
> - [Data Protection Disclosure](/legal/data-protection-disclosure/) -- sub-processor details and data processing transparency
> - [GDPR Policy](/legal/gdpr-policy/) -- detailed GDPR-specific policy for EU/EEA users
> - [Individual CLA](/legal/individual-cla/) -- contributor license agreement for individuals
> - [Corporate CLA](/legal/corporate-cla/) -- contributor license agreement for organizations

    </div>
  </div>
</section>
