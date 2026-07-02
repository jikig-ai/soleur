---
title: "Terms & Conditions"
type: terms-and-conditions
jurisdiction: FR, EU
generated-date: 2026-02-20
---

# Terms & Conditions

**Soleur -- Company-as-a-Service Platform**

**Effective Date:** February 20, 2026

**Last Updated:** July 2, 2026 -- amended Section 3a.5 (BYOK cost ceiling) to describe the Web Platform's best-effort spending safeguards (a per-run cost ceiling, a per-run step limit, and a rolling short-window ~1-hour cumulative-spend cap per account, with pause-and-notify on trip and operator-cleared resume), to remove the prior statement that the Web Platform includes no Jikigai-provided cost ceiling, and to allocate all BYOK API charges and overage -- including spend incurred before a best-effort safeguard halts a run -- to the operator subject to Section 11 (feat-l5-runaway-guard / #5767); previously June 4, 2026 -- added Section 3a.7 "Autonomous command execution (Web Platform)" and Section 10.4 "Autonomous command execution -- residual risk", and a Section 9 sibling bullet, disclosing that the Web Platform agent runs shell commands on your connected workspace automatically (without per-command approval) once you acknowledge the first-run consent soft-gate or enable autonomous mode; admits the residual risk (the blocklist is illustrative, not exhaustive; a non-blocked command can auto-run and change or delete files), names the git-backed-recovery and visible-in-chat mitigations, distinguishes own-workspace commands from third-party sends under Section 3a.1-3a.6 / Article 22, and is substantively consistent with the in-product autonomous-execution disclosure banner and Acceptable Use Policy Section 5.7 (PR #4949 / #4952); previously May 22, 2026 -- softened Section 3b.4 (Side Letter and customer-DPA roadmap): the per-Co-Member Side Letter is no longer required; Workspace Owners may satisfy the Section 3b.1-3b.3 responsibility framework by any sufficient means, including reliance on the Co-Member's click-through acceptance of these Terms; the Side Letter remains available as an optional belt-and-braces instrument; refreshed Section 3b.3(d) indemnification trigger to align with the new responsibility framing in Acceptable Use Policy Section 5.5; previously same-day added Section 3b "Workspace Members" governing the team-workspace feature (workspace owner is controller; co-members access under the owner's account; owner indemnifies including co-member access to the workspace send-audit ledger) gated by `FLAG_TEAM_WORKSPACE_INVITE` (PR #4289); May 19, 2026 -- extended Section 3a.2 to add the fourth tier `Auto with daily digest` for `infra.*` action classes and to clarify that the typed-SEND verbatim acknowledgement applies to the brand-critical classes under the `Approve every time` tier; refreshed the "drafts everywhere, sends nowhere" invariant to admit both autonomous tiers (PR-H #4077); May 18, 2026 -- added Section 3a "Agent Command Authority" governing per-action-class scope grants and per-grant deny-by-default authorization for automated Web Platform actions; tightened Section 9 cross-reference; April 10, 2026 -- added Section 8.1c Shared Content terms.

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

## 3a. Agent Command Authority

The Web Platform includes agent-runtime features that can act on your behalf in response to external events (for example, a Stripe `invoice.payment_failed` webhook) without your live presence at the moment the event fires. This section governs the scope, limits, and revocation of that authority.

### 3a.1 Per-action-class scope grants

The Web Platform performs no automated action on your behalf for an action class (for example, `finance.payment_failed`) unless you have explicitly granted authorization for that class via the `/dashboard/settings/scope-grants` interface. Authorization is opt-in per action class; the absence of a grant is a denial. The Web Platform's per-tenant scope grants ledger is the source of truth for this authorization, recorded as an append-only WORM record at the moment of grant and at the moment of revocation.

### 3a.2 Default tier and "drafts everywhere, sends nowhere"

Each grant carries one of four tiers:

- **Approve every time** -- the agent proposes; you authorize each instance before any external effect is produced. For brand-critical action classes (marketing email blasts, public X threads, enterprise-tier Slack DMs, Soleur-handle Bluesky replies), you type `SEND` verbatim at click-time as the explicit consent primitive. This is the safest tier and the default for any new action class.
- **Draft, one click** -- the agent prepares a draft; you approve with one click before any external effect is produced.
- **Auto** -- the agent executes the action without a per-instance approval step. This tier is consequential; selecting it requires an explicit second-click acknowledgement on the grant page.
- **Auto with daily digest** -- the agent executes infrastructure-class actions (`infra.*` -- for example, `infra.dependency_bump`, `infra.log_rotate`) without per-instance approval; you review the actions in a next-business-day digest in the Today section. Designed for action classes where per-instance oversight is uneconomic but a review window is still required.

Regardless of tier, the Web Platform's binding invariant is "drafts everywhere, sends nowhere": no external message, payment instruction, or third-party transmission is produced unless either (a) you authorize that specific draft through the Web Platform user interface, or (b) you have granted the `Auto` or `Auto with daily digest` tier for the specific action class triggering the event. Any send produced from a draft you authorize is your action, performed through Soleur as your instrument.

### 3a.3 Revocation

You may revoke a scope grant at any time via the same `/dashboard/settings/scope-grants` interface. Revocation takes effect for the next trigger of the action class; runs already in flight when the revocation is recorded may complete according to the tier active at the moment the trigger fired. The grant ledger records both the original grant and the revocation, with the tier that was active at the moment of each recorded event preserved for audit purposes (the `/dashboard/audit` viewer renders this history).

### 3a.4 Soleur is not an agent-in-fact for third parties

Soleur executes the actions you authorize within the Web Platform's user interface and the action classes you grant. Soleur is not your legal agent, attorney-in-fact, or authorized representative for any third party. No grant made via the Web Platform creates an agency relationship between Jikigai and any third party. Any obligation owed to a third party that results from an action you authorize through Soleur remains your obligation.

### 3a.5 BYOK cost ceiling

Where the Web Platform performs automated actions on your behalf, those actions consume API credits on your Anthropic API key (Bring-Your-Own-Key, "BYOK"). The Web Platform records the per-call token count and unit cost in the audit ledger; you control the spending cap on your own key directly with Anthropic.

The Web Platform applies its own best-effort spending safeguards in addition to any cap you set with Anthropic: a per-run cost ceiling, a bounded per-run step limit, and a rolling short-window (approximately one hour) cumulative-spend cap per account. When a safeguard trips, the Web Platform pauses further automated spending on your account and notifies you; you resume by clearing the pause and starting a fresh run. These safeguards are provided on a best-effort basis and are not a guarantee: they may not prevent all overspending, and network, timing, or system conditions can allow spend to exceed a ceiling before a run halts.

Jikigai does not bill, proxy, or guarantee any cost incurred against your BYOK key, and is not liable for any API charges, overage, or credit consumption on your key -- including amounts incurred before a best-effort safeguard halts a run. You remain solely responsible for all spend on your own Anthropic key. This allocation of responsibility is subject to Section 11 (Limitation of Liability).

### 3a.6 Right to human review (GDPR Article 22(3))

Where the Web Platform produces a decision concerning you through automated processing (including any action under the `Auto` tier), you have the right to obtain human intervention, to express your point of view, and to contest the decision. The `/dashboard/audit` viewer surfaces a "Request human review" affordance on each automated run; you may also contact us at <legal@jikigai.com> at any time to request human review of any automated action.

### 3a.7 Autonomous command execution (Web Platform)

The Web Platform's hosted agent can run shell commands in the workspace you connect **automatically**, without a separate per-command approval step. This is distinct from the third-party "sends" governed by Sections 3a.1 through 3a.6: those Sections govern external effects (messages, payment instructions, transmissions to third parties) under the per-action-class scope-grant model; this Section 3a.7 governs commands that the agent runs **on your own connected workspace** (your repository, your connected accounts) as part of the development workflow.

**Consent model.** Autonomous command execution is governed by a first-run owner consent soft-gate: the first time a non-blocked command would auto-run in a workspace with no recorded acknowledgement, the command is held and the Workspace Owner is shown a disclosure banner. The Owner's acknowledgement is recorded per workspace and releases the held command; subsequent non-blocked commands then run without a per-command approval step. The Owner may keep the workspace in autonomous (trusted) mode or return it to ask-each-time at any time.

**Residual-risk admission.** Soleur always blocks a fixed set of clearly-dangerous commands and auto-approves only a narrow read-only allowlist, but **no blocklist is exhaustive or perfect.** A command that is neither blocked nor on the read-only allowlist can run automatically, and a non-blocked command that appears safe could still change or delete files in the connected workspace without asking you first. Soleur does not warrant that autonomous command execution cannot run a harmful command (see Section 10.4).

**Mitigations and your responsibility.** Your work is git-backed (the connected repository is the recovery surface) and every command is visible in the chat as it runs; these are mitigations of the residual risk, not a guarantee that no harm can occur. You are responsible for connecting only repositories and accounts you trust, for reviewing command activity, and for the consequences of a non-blocked command that auto-runs while the workspace is in autonomous mode. This Section is the contractual counterpart of the in-product autonomous-execution disclosure banner and of Acceptable Use Policy Section 5.7.

**GDPR Article 22.** Autonomous command execution is a development-workflow action on your own connected systems, not automated decision-making that produces legal or similarly significant effects on a third party. Automated effects on third parties remain governed by Sections 3a.1 through 3a.6 and your Article 22(3) right to human review under Section 3a.6.

## 3b. Workspace Members

The Web Platform supports team workspaces in which a natural person or legal entity (the "Workspace Owner") may invite additional natural persons (each a "Co-Member") to access the same workspace under the Owner's account. This section governs the controllership, visibility, and indemnification arrangement among Jikigai, the Workspace Owner, and Co-Members when the team-workspace feature is enabled for the Owner's organization (gated by `FLAG_TEAM_WORKSPACE_INVITE` and the per-organization allowlist `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`).

### 3b.1 Workspace Owner is the data controller

The Workspace Owner is the controller, within the meaning of Article 4(7) GDPR, of all personal data processed by the Web Platform on behalf of the workspace -- including conversation content, knowledge-base queries, BYOK API-key usage, and the per-(founder, action_class) scope grants and per-send signature ledger records produced by the workspace. Co-Members access the workspace under the Owner's account; their use of the Web Platform constitutes use by the Owner's organisation for purposes of these Terms, and their actions are attributable to the Owner under the "authorized users" framework of the Anthropic Commercial Terms §C. Soleur acts as a processor (Article 4(8) GDPR) for the Workspace Owner with respect to all such data; the Data Protection Disclosure Section 2.3(u) records the categories and the lawful-basis cross-reference.

### 3b.2 Co-Member visibility scope

Co-Members of a shared workspace are recipients (within the meaning of Article 13(1)(e) GDPR) of one another's workspace-scoped metadata for the in-workspace conversations and operations they participate in -- including conversation participation records, knowledge-base query identifiers, scope-grant ledger rows, send-audit ledger rows (`action_sends`, including recipient identifier hashes (`recipient_id_hash`), per-send body hashes (`per_send_body_sha256`), and template hashes (`template_hash`)), and template-authorization rows. Each Co-Member retains, against Jikigai, the independent rights of access, rectification, erasure, restriction, portability, and objection conferred by Articles 15 through 22 GDPR over rows that are identifiable to that Co-Member. The Web Platform's row-level security predicates and the `is_workspace_member(workspace_id, user_id)` helper enforce cross-member visibility scope as the load-bearing technical measure under Article 32 GDPR; the Privacy Policy Section 4.11 records this disclosure in user-facing form.

### 3b.3 Workspace Owner indemnification

The Workspace Owner agrees to defend, indemnify, and hold harmless Jikigai, its officers, employees, and affiliates from any and all third-party claims, damages, fines, regulatory orders, and reasonable legal fees arising from or related to: (a) any Co-Member's use of the Web Platform under the Owner's account; (b) any Co-Member's access to, retention of, exfiltration of, or onward disclosure of workspace-scoped data visible to that Co-Member under Section 3b.2, **including without limitation access to and any use of the workspace's send-audit ledger** (the `action_sends` and `template_authorizations` records and, where the Web Platform records cross-member action provenance via the `workspace_member_actions` audit ledger, those rows); (c) any claim by one Co-Member against another Co-Member arising from in-workspace activity; and (d) any breach by the Workspace Owner of the responsibility in the Acceptable Use Policy Section 5.5 (the Owner must ensure each invited Co-Member is bound by appropriate confidentiality and intellectual-property assignment terms, by any means the Owner deems sufficient including reliance on these Terms). This indemnification survives termination of these Terms and is in addition to, not in lieu of, the general indemnification in Section 12.

### 3b.4 Side Letter and customer-DPA roadmap

The Workspace Owner is responsible for ensuring Co-Members they invite are bound by appropriate confidentiality, intellectual-property assignment, and workspace-activity-logged acknowledgement terms covering the obligations that flow from Section 3b.1 through Section 3b.3. The Owner may satisfy this responsibility by any means the Owner deems sufficient, including reliance on the Co-Member's click-through acceptance of these Terms (the canonical click-through anchor for the Section 3b obligations applicable to all users of the Web Platform), reliance on an existing employment/contractor/consultancy agreement between the Owner and the Co-Member, or execution of the optional Soleur Side Letter (template available from Jikigai at <legal@jikigai.com>) as a separate bilateral instrument. **IP-assignment note:** the Co-Member's click-through acceptance of these Terms is sufficient for confidentiality reliance but does NOT by itself effect intellectual-property assignment from the Co-Member to the Workspace Owner; Owners who require enforceable IP assignment from a Co-Member should rely on an instrument (an existing engagement or the Soleur Side Letter) that names the Workspace Owner as the assignee. The Soleur Side Letter is offered as a belt-and-braces reference document; Jikigai does not require its execution. If executed, the Side Letter remains a bilateral document between the Workspace Owner and the Co-Member -- Jikigai is not a party. Once Jikigai publishes a customer-facing Data Processing Agreement for organizational tenants, that instrument supersedes the per-Co-Member responsibility framework at the organizational level; the supersession will be announced in writing to the Workspace Owner and recorded as an update to this Section 3b.4.

## 4. Description of the Service

Soleur is a locally installed Claude Code plugin that provides:

- **45 AI agents** organized across five domains (Engineering, Legal, Marketing, Operations, Product)
- **45 skills** for structured software development workflows
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

The Web Platform is hosted on Hetzner servers in Helsinki, Finland (EU) and uses Cloudflare as a CDN/proxy. Full data processing details are described in the [Privacy Policy](privacy-policy.md) Section 4.7.

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

### 5.5 Metered Usage and Partial Consumption (Web Platform Stop)

The Soleur Web Platform exposes a Stop control (a button on the chat surface and the `Esc` keyboard shortcut while a turn is streaming) that allows you to interrupt an in-progress assistant turn at any time. The Stop control is a best-effort cancellation: the Service signals the underlying language model and any in-flight tool calls to halt as soon as practicable, but the following terms apply to consumption that has already occurred at the moment Stop is invoked. By using the Stop control, you acknowledge that token consumption and tool-call side effects that have already occurred at the moment of cancellation cannot be reversed by the Service, and that any third-party (BYOK) provider charges incurred before cancellation propagates are not subject to Jikigai's refund authority.

- **Tokens consumed before Stop are billed.** If you use your own API key (BYOK) for a third-party language model provider (for example, Anthropic Claude), the provider bills you directly for tokens generated before the cancellation propagates -- including tokens generated by sub-agents or tool callbacks dispatched within the same turn. Jikigai does not refund or credit third-party token charges. Where Jikigai itself meters usage against a paid Subscription tier, tokens consumed before Stop count toward your tier's allowance, and the discretionary-refund posture in Section 5.4 continues to apply. Cancellation propagation typically completes within seconds of pressing Stop, but degraded-network or third-party provider-side conditions may extend this window; tokens consumed during that window remain billable, and Jikigai cannot guarantee an upper bound on consumption when the underlying provider's network is degraded or unresponsive.
- **Side-effecting tool calls already dispatched are not automatically reversed.** Tool calls that ran to completion before the Stop signal arrived (for example, file writes, shell commands, third-party API calls, repository pushes, or external service mutations) are NOT rolled back by the Service. The Service surfaces a list of completed actions in the aborted-turn marker so that you can review what ran and decide whether any manual reconciliation is appropriate. You are solely responsible for reviewing the completed-actions list and performing any reconciliation (rollbacks, refunds to downstream parties, manual corrections, or notifications) that the side effects of the partial turn require. Sections 7 (AI-Generated Output) and 11 (User Responsibilities) of these Terms continue to govern your responsibility for outputs and side effects produced before cancellation, and the AI-generated output and local-system-risk provisions of the [Disclaimer](./disclaimer.md) (Sections 2 and 3) continue to apply.
- **Partial assistant output is preserved.** When you Stop a turn, any assistant text already generated up to the point of cancellation is persisted to your conversation history alongside an "aborted" status marker (with cause: user-initiated, client-disconnect, or network), the token cost of the partial turn, and the list of completed actions. This applies equally when a streaming turn is interrupted by a tab close, network disconnect, or other involuntary client termination. Privacy and retention of this partial transcript material follow Section 4.7 of the [Privacy Policy](./privacy-policy.md), and your erasure rights remain available as described in Section 8.1 of that policy and Section 8.4 below.

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

If you contribute code or other materials to the Soleur project via pull requests, you must sign a Contributor License Agreement (CLA) before your contribution can be accepted. The CLA grants Jikigai a perpetual, irrevocable license to use, modify, sublicense, and relicense your contribution, while you retain your copyright. The CLA includes an express patent grant covering contributed code. Full terms are set out in the [Individual Contributor License Agreement](individual-cla.md) and [Corporate Contributor License Agreement](corporate-cla.md).

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

This section applies to the Plugin only. For Web Platform data practices, see Section 8.1b and the [Privacy Policy](privacy-policy.md) Section 4.7.

### 8.1b Web Platform Data Practices

The Soleur Web Platform collects and processes personal data as necessary to provide the service. This includes:

- **Account data** (email, authentication tokens) processed by Supabase (EU-hosted, AWS eu-west-1, Ireland).
- **Payment data** processed by Stripe (PCI SAQ-A -- card data handled exclusively by Stripe).
- **Workspace data** (encrypted API keys, workspace configurations) hosted on Hetzner (Helsinki, Finland, EU).
- **Technical data** (IP addresses, request headers) processed by Cloudflare CDN/proxy.

For comprehensive data processing details, legal bases, retention periods, and your rights, see the [Privacy Policy](privacy-policy.md) and [GDPR Policy](gdpr-policy.md).

<!-- Added 2026-04-10: KB sharing -->

### 8.1c Shared Content

The Web Platform allows you to share individual knowledge base documents via public links. By using this feature:

- **Your responsibility:** You are solely responsible for the content you choose to share. You must ensure that shared documents do not contain confidential third-party information, personally identifiable information of others without their consent, or material that infringes third-party intellectual property rights. See the [Acceptable Use Policy](acceptable-use-policy.md) for detailed rules.
- **Jikigai's role:** Jikigai acts as a processor making the document content available at the shared URL on your instruction. Jikigai does not review, moderate, or approve shared content prior to publication.
- **Revocation:** You may revoke a share link at any time from the Web Platform. Revocation takes immediate effect -- the shared URL will no longer serve the document content. However, Jikigai cannot guarantee that recipients have not copied, downloaded, or redistributed the content prior to revocation. You acknowledge that once content is shared via a public link, Jikigai has no ability to enforce deletion by recipients.
- **No warranty of recipient conduct:** Jikigai makes no representation regarding how recipients will use shared content and accepts no liability for any downstream use by recipients after they access the shared document.

<!-- End: KB sharing -->

### 8.2 Documentation Site

The Soleur documentation site (soleur.ai) is hosted on GitHub Pages. GitHub, as the hosting provider, may collect certain data such as IP addresses and browser metadata in accordance with GitHub's own privacy practices. We do not control GitHub's data collection. Please refer to GitHub's Privacy Statement for details.

### 8.3 Third-Party Data Processing

When the Plugin facilitates interactions with the Anthropic Claude API or other third-party services, data transmitted to those services is governed by their respective privacy policies and terms of service. We are not responsible for the data practices of third-party service providers.

### 8.4 EU/EEA Users -- GDPR Rights

If you are located in the EU/EEA, you have rights under the GDPR including the right of access, rectification, erasure, restriction of processing, data portability, and objection.

For the Plugin, these rights are inherently satisfied by your local control over Plugin-generated data.

For the Web Platform, you may exercise these rights against Jikigai by contacting <legal@jikigai.com>. See the [GDPR Policy](gdpr-policy.md) Section 5 for full details on how to exercise each right.

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
- Circumvent, disable, or interfere with the human-in-the-loop boundary established by the `draft / Send / Edit / Discard` flow or the per-action-class scope grants ledger described in Section 3a (Agent Command Authority); attempting to send messages or trigger external effects without a grant or without an authorized draft is a material breach of these Terms
- Circumvent, disable, or interfere with the command-safety layer governing autonomous command execution (Section 3a.7 and Acceptable Use Policy Section 5.7), or connect a repository or account you are not authorized to expose to autonomous command execution

## 10. Disclaimer of Warranties

### 10.1 "As Is" Provision

THE PLUGIN AND THE WEB PLATFORM ARE PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, AND ACCURACY.

### 10.2 No Guarantee of Availability or Accuracy

We do not warrant that the Plugin or the Web Platform will be uninterrupted, error-free, secure, or free of harmful components. We do not warrant the accuracy, completeness, or reliability of any output generated by the Plugin's AI capabilities. The Web Platform does not include a Service Level Agreement (SLA). No specific uptime, response time, or availability guarantees are provided.

### 10.3 EU Consumer Rights

Nothing in this section limits or excludes any warranty rights that you may have under mandatory applicable law, including EU consumer protection legislation. If you are a consumer in the EU/EEA, you benefit from mandatory statutory warranty rights that cannot be waived or limited by contract.

### 10.4 Autonomous command execution -- residual risk

The Web Platform's hosted agent can run shell commands in the workspace you connect automatically, without a per-command approval step, once you have acknowledged the first-run disclosure or set the workspace to autonomous (trusted) mode (Section 3a.7). Soleur blocks a fixed set of clearly-dangerous commands and auto-approves only a narrow read-only allowlist, but **the blocklist is illustrative and not exhaustive, and no blocklist is perfect.** TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, WE DO NOT WARRANT THAT AUTONOMOUS COMMAND EXECUTION CANNOT RUN A COMMAND THAT CHANGES OR DELETES FILES IN YOUR CONNECTED WORKSPACE, OR THAT ANY NON-BLOCKED COMMAND IS SAFE. The mitigations Soleur provides -- your work is git-backed (the connected repository is the recovery surface) and every command is visible in the chat as it runs -- reduce but do not eliminate this residual risk, and are not a guarantee of safety. You accept this residual risk when you acknowledge the disclosure or enable autonomous mode, and you are responsible for connecting only repositories and accounts you trust. This Section does not limit or exclude any liability that cannot be limited or excluded under mandatory applicable law (see Section 11.3), and the EU consumer-rights reservation in Section 10.3 applies.

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

For details on data retention after account deletion, see the [Privacy Policy](privacy-policy.md) Section 7.

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
> - [Privacy Policy](privacy-policy.md) -- details data practices referenced in Section 8
> - [Acceptable Use Policy](acceptable-use-policy.md) -- expands on the acceptable use provisions in Section 9
> - [Cookie Policy](cookie-policy.md) -- covers cookies used by the documentation site
> - [Disclaimer](disclaimer.md) -- standalone version of warranty and liability provisions
> - [Data Protection Disclosure](data-protection-disclosure.md) -- sub-processor details and data processing transparency
> - [GDPR Policy](gdpr-policy.md) -- detailed GDPR-specific policy for EU/EEA users
> - [Individual CLA](individual-cla.md) -- contributor license agreement for individuals
> - [Corporate CLA](corporate-cla.md) -- contributor license agreement for organizations
