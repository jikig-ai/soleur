---
title: "CLO live-terms verification — third-party use of a user's Claude subscription (#9580)"
type: terms-verification
date: 2026-10-06
issue: 9580
related_issue: 9579
baseline: knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md
artifact: apps/web-platform/server/byok-lease.ts (operator-cc-oauth / oauth_token credential); apps/web-platform/app/api/keys/route.ts (oauth_token branch)
brand_survival_threshold: single-user incident
status: DRAFT (CLO-agent-attested, Soleur-as-tenant-zero v1 internal assessment)
disposition: "OWNER-ONLY OPERATOR SELF-USE — AMBIGUOUS-LEANING-TOLERATED, CONTINUES, LEAN WEAKENED (no disposition change, no disable required). CUSTOMER-FACING / TENANT / POOLED SUBSCRIPTION AUTH — PROHIBITED by live Anthropic text; Soleur must not build or advertise it."
reviewed_by: "CLO agent (v1 internal counsel-review attestation, Soleur-as-tenant-zero posture)"
operator: "Jean Deruelle (Jikigai SARL gérant)"
retrieval_date: 2026-10-06
re_evaluation_triggers: "Anthropic un-pauses / ships its promised advance-notice update to the Agent SDK article (support.claude.com article 15036540); OR amends the 'still draw from your subscription's usage limits' sentence; OR amends the 'Authentication and credential use' section of code.claude.com/docs/en/legal-and-compliance or the Note on code.claude.com/docs/en/agent-sdk/overview; OR any move off owner-only operator-self-use (delegation, customer-facing, pooling, tenant-run auth, any Soleur-held Claude.ai token for a non-owner) — which also escalates to EXTERNAL counsel; OR Anthropic takes any enforcement step against the operator's Claude account. Run before any product work that authenticates customer or tenant runs with a user's own subscription."
draft_notice: "Draft internal legal guidance for a non-lawyer founder. NOT a substitute for licensed external counsel."
---

# CLO live-terms verification — third-party use of a user's Claude subscription

> **Draft notice.** Draft internal legal guidance prepared for a non-lawyer founder operating Soleur as tenant-zero. It is not a substitute for licensed external counsel. Every quotation below was taken from the live page on the retrieval date shown, not from memory or from the June audit.

## 0. Bottom line

1. **Owner-only operator self-use: verdict unchanged in disposition, weaker in lean.** June's AMBIGUOUS-LEANING-TOLERATED stands for the owner-only construction, and disabling `CC_OAUTH_ENABLED` is still not mandatory. None of the three June triggers fired. But the June record under-weighted live Anthropic text that was already published in June and was widened in late August 2026 (section 3). The lean is now supported by one unamended metering sentence plus Anthropic's own documented `claude setup-token` path for the owner's own CI/scripts, and cut against by a literal reading of "developers may not collect, store, or intermediate Claude.ai credentials or session tokens". Residual risk stays operator-borne (action against the operator's own Claude account) but is higher than the June record states.
2. **Customer-facing or tenant-run subscription auth: not permitted.** Three independent live Anthropic statements prohibit a third-party developer from routing requests through a user's Free/Pro/Max credentials, offering claude.ai login or rate limits, or collecting/storing Claude.ai tokens. Soleur must not copy the pattern, and the existing `oauth_token` path must stay owner-only.
3. **The only text-supported route to "user's own subscription" in a hosted product** is the narrow carve-out in which the end user signs in to the unmodified Claude Code binary through Anthropic's own flow and the developer never touches the token. That is not what Soleur's stored-`setup-token` path does, and nothing in this audit authorises building it. It would need a fresh review and written confirmation from Anthropic.
4. **#9579 gate:** a homepage line "runs on your Claude plan" is accurate only for the self-hosted plugin. For the hosted tier the product takes a BYOK Anthropic API key, so the line must not be used for hosted (section 6).

## 1. Sources retrieved 2026-10-06

| # | Source | URL | Page's own date / version | How read |
|---|--------|-----|---------------------------|----------|
| S1 | Support article 15036540, "Use the Claude Agent SDK with your Claude plan" | <https://support.claude.com/en/articles/15036540> | Dated June 16, 2026 | Raw HTTP body, text-extracted |
| S2 | Consumer Terms of Service | <https://www.anthropic.com/legal/consumer-terms> | Effective October 8, 2025 | Raw HTTP body, text-extracted |
| S3 | Claude Code, "Legal and compliance" | <https://code.claude.com/docs/en/legal-and-compliance> (and `.md` variant) | Undated | Raw `.md` body, plus WebFetch extraction |
| S4 | Claude Agent SDK overview | <https://code.claude.com/docs/en/agent-sdk/overview> (`.md` variant) | Undated | Raw `.md` body |
| S5 | Claude Code, "Authentication" | <https://code.claude.com/docs/en/authentication> (`.md` variant) | Undated | Raw `.md` body |
| S6 | Commercial Terms of Service | <https://www.anthropic.com/legal/commercial-terms> | Effective June 17, 2025 | Raw HTTP body, text-extracted |
| S7 | Usage Policy (AUP) | <https://www.anthropic.com/legal/aup> | Effective September 15, 2025 | Raw HTTP body, text-extracted |
| S8 | Internet Archive snapshots of S3, used only to date changes | <https://web.archive.org/web/20260601/https://code.claude.com/docs/en/legal-and-compliance> and the 20260616, 20260804, 20260816100738, 20260830094710, 20260909140928 captures | Snapshot dates as listed | Raw HTML |

## 2. What the live terms say

**S1, support article 15036540 (retrieved 2026-10-06, article dated June 16, 2026).** The banner is byte-for-byte the text the June audit quoted:

> Update June 15: We're pausing the changes to Claude Agent SDK usage described below. For now, nothing has changed: Claude Agent SDK, `claude -p`, and third-party app usage still draw from your subscription's usage limits. The previously announced monthly credit, which would have been available to eligible claimants in connection with these changes, isn't available. We're working to update the plan to better support how users build with Claude subscriptions. When we have an update, we'll share it before anything takes effect. The content below reflects the page before June 15. It's preserved for reference but is no longer taking effect on June 15.

Two points the June audit did not draw out. First, the sentence is descriptive of metering, not an authorisation: it says where usage is counted, not that third-party apps may authenticate with a subscription. Second, the pre-pause body that lists "Third-party apps that authenticate with your Claude subscription through the Agent SDK" as covered by the credit is expressly "no longer taking effect"; it is not a source of permission. The article's Team/Enterprise note is also still live in the preserved body: "Teams running shared production automation should use Claude Platform with an API key for predictable pay-as-you-go billing."

**S2, Consumer Terms, Section 3 (retrieved 2026-10-06, effective October 8, 2025).** The automated-access bar is unchanged:

> Except when you are accessing our Services via an Anthropic API Key or where we otherwise explicitly permit it, to access the Services through automated or non-human means, whether through a bot, script, or otherwise.

and, on credentials:

> You may not share your Account login information, Anthropic API key, or Account credentials with anyone else or make your Account available to anyone else.

The Consumer Terms contain no Claude Code, Agent SDK or OAuth-specific provision.

**S3, Claude Code legal-and-compliance, "Authentication and credential use" (retrieved 2026-10-06).**

> **OAuth authentication** is intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic applications.
>
> **Developers** building products or services that interact with Claude's capabilities, including those using the Agent SDK, should use API key authentication through Claude Console or a supported cloud provider. Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users. Moreover, developers may not collect, store, or intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must complete through Anthropic's own flow.
>
> This does not restrict how customers provision and manage their own API keys or third-party inference provider credentials [...] Nor does it prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription, including where a platform hosts Claude Code as described under *Can customers offer Claude Code in their products?* above.
>
> Anthropic reserves the right to take measures to enforce these restrictions and may do so without prior notice.

Same page, "Acceptable use": "Advertised usage limits for Pro and Max plans assume ordinary, individual usage of Claude Code and the Agent SDK." And, "Can customers offer Claude Code in their products?": "Customers may not pay for, resell, or intermediate Claude usage on their end users' behalf. Each end user must authenticate with their own Anthropic API key, Claude subscription plan credentials, or 3P inference provider credential [...]", plus "The Claude Code binary must not be modified" and customers "may not remove, disable, or restrict any authentication method built into it". Running Claude Code in a product also "requires agreeing to our Commercial Terms of Service".

**S4, Agent SDK overview, Note (retrieved 2026-10-06).**

> Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK. Use the API key authentication methods described in the Quickstart instead.

Branding on the same page: allowed "{YourAgentName} Powered by Claude"; not permitted "Claude Code" or "Claude Code Agent" as the product's name; "Your product should maintain its own branding and not appear to be Claude Code or any Anthropic product."

**S5, Authentication (retrieved 2026-10-06).** Documents `claude setup-token` as the supported way to mint a one-year token "for CI pipelines, scripts, or other environments where interactive browser login isn't available" (the page's wording is "Use this for CI pipelines and scripts where browser login isn't available" in the credential-precedence list and "For CI pipelines, scripts, or other environments where interactive browser login isn't available" under the setup-token heading), and states: "This token authenticates with your Claude subscription and requires a Pro, Max, Team, or Enterprise plan." This is Anthropic's own endorsement of a user placing their own subscription token in their own automation, and is the strongest text supporting owner-only self-use.

**S6, Commercial Terms.** D.4 bars building a competing product or reselling "the Services except as expressly approved by Anthropic". A.1 permits Customer to "power products and services Customer makes available to its own customers and end users". These govern API-key use, not subscription credentials. No change relevant to this question.

**S7, Usage Policy.** Nothing found that addresses subscription credentials, third-party apps or usage-limit circumvention beyond the ban-evasion and account-creation-automation lines. Not relied on.

## 3. What changed since the June baseline

| Item | June 16 baseline | Live 2026-10-06 | Status |
|------|------------------|-----------------|--------|
| Article 15036540 pause banner and "still draw from your subscription's usage limits" sentence | Quoted verbatim | Identical; article still dated June 16, 2026; no advance-notice update shipped | **Unchanged** (triggers 1 and 2 not fired) |
| Consumer Terms Section 3 automated-access bar and no-sharing clause | Relied on | Same text, effective October 8, 2025 | **Unchanged** |
| S3: "Anthropic does not permit third-party developers to offer Claude.ai login or to route requests through Free, Pro, or Max plan credentials on behalf of their users." | **Not cited in the baseline.** Present on the 2026-06-01 and 2026-06-16 Archive snapshots | Present, reworded ("login into their own applications") | **Baseline omission.** Does not alter the owner-only conclusion ("on behalf of their users" does not describe owner self-use), but it is the controlling authority for the customer-facing prohibition and the baseline should have cited it |
| S3: "developers may not collect, store, or intermediate Claude.ai credentials or session tokens"; the "Can customers offer Claude Code in their products?" section; the end-user carve-out | Not present | Absent from the 2026-08-04 and 2026-08-16 snapshots; present on the 2026-08-30 snapshot onward | **New since June** (added between 2026-08-16 and 2026-08-30 per Archive captures; exact date not established) |
| S4: no third-party claude.ai login or rate limits for products built on the Agent SDK | Not cited | Present live. Archive dating not performed for this page | **Not dated.** Treat as new-to-the-record |
| S5: `claude setup-token` documented for CI and scripts | Not cited | Present | **Supporting text, new to the record** |
| Owner-only code gate | `OauthDelegationForbiddenError` in `byok-lease.ts` | Class still present; `/api/keys` oauth branch returns 403 unless the caller is in `ADMIN_USER_IDS` and `CC_OAUTH_ENABLED` is on; `.env.example` ships `CC_OAUTH_ENABLED=0` | **Unchanged** (spot-checked by symbol name, not re-audited) |

## 4. Verdict for owner-only operator self-use

**Disposition: AMBIGUOUS-LEANING-TOLERATED, continues; lean weakened. No disable required.**

- *For tolerance:* (a) the unamended metering sentence in S1; (b) S5 documents `setup-token` for the user's own scripts; (c) S3's prohibitions are framed around developers acting "on behalf of their users" and offering "login into their own applications", neither of which describes a token used only for its owner's own runs; (d) S3 itself says advertised limits "assume ordinary, individual usage", so a single owner's own load is within the described envelope.
- *Against tolerance:* (a) "developers may not collect, store, or intermediate Claude.ai credentials or session tokens" read literally covers Soleur's server storing the owner's `setup-token` in `store_oauth_credential`; (b) S2's automated-access bar has no explicit permission for a hosted server loop under a consumer subscription; (c) S3 reserves enforcement "without prior notice".
- *Net:* the June reading survives because the aggravating sentences are scoped to third-party developers serving users, and Jikigai is serving only its own operator. But that is an interpretation, not an Anthropic statement, and the August sentence narrows the room for it. The operator's exposure is rate-limiting or suspension of the operator's own Claude account, as in June. This audit does not find a customer or sub-processor risk from the owner-only path, because no customer runs reach it.
- *Not verified here (CTO question, not legal):* whether the server-side agent path invokes the unmodified Claude Code binary. The S3 end-user carve-out depends on that, and it should not be assumed.

## 5. Customer-facing / tenant-run subscription auth: PROHIBITED

Any design in which Soleur (a) accepts a customer's claude.ai login, (b) stores, forwards or refreshes a customer's Claude.ai OAuth or `setup-token` credential, (c) presents Claude subscription rate limits as a Soleur feature, or (d) runs tenant or delegated workspace runs under any single subscription, falls inside S3 and S4 prohibitions and, for (d), the Consumer Terms no-sharing clause. **Soleur must not copy this pattern.** It also may not pay for or absorb end users' Claude usage in a hosted product (S3, "Customers may not pay for, resell, or intermediate Claude usage on their end users' behalf").

The only text-supported adjacent route is S3's carve-out for an end user signing in to the unmodified Claude Code binary with their own subscription, completed through Anthropic's own flow, with Soleur never collecting or storing the token. That route is conditional on the Commercial Terms, an unmodified binary, and no disabled auth methods. **Do not start it** without a fresh CLO review, external counsel, and written confirmation from Anthropic through the "contact sales" channel S3 itself names.

## 6. Answers that gate #9579 items 1 to 3

Product fact used (verified in the repo, not re-audited): the hosted Web Platform takes a BYOK Anthropic **API key** from customers (`/api/keys`, `api_key` path validates against the Anthropic API; Privacy Policy section 4.7 lists "encrypted API keys (BYOK)"). The subscription-token branch is operator-only and returns 403 to everyone else. The self-hosted plugin runs inside the user's own Claude Code.

**Item 1, "runs on your Claude plan" near the hero.**

1. **Scope it to the self-hosted plugin.** For self-hosted users, signing in to their own Claude Code with their own Pro/Max/Team/Enterprise plan is the user's own use and is what S3 expressly leaves open. A scoped line such as "Run Soleur inside your own Claude Code, signed in with your Claude plan or API key" is supportable.
2. **Never apply "Claude plan", "your Claude subscription", "Pro/Max" or "uses your subscription limits" to the hosted tier.** Hosted runs bill an Anthropic API key. An unscoped hero line would read as hosted-on-subscription, which is inaccurate and would advertise the exact pattern S3 and S4 say third-party developers may not offer.
3. **Hosted wording must say API key**: "Hosted: bring your own Anthropic API key, billed by Anthropic to you." Do not write that Soleur or Jikigai pays, bundles or resells Claude usage.
4. **Existing copy is out of line with the above and should be fixed in the same marketing PR (not edited here):** `plugins/soleur/docs/pages/pricing.njk` FAQ ("Hosted plan users pay their Soleur subscription plus their own Claude Pro, Max, or API costs") and the pricing note ("All plans require a Claude subscription or API key"). Both imply a Pro/Max subscription funds hosted runs. "Pro, Max," should come out of the hosted statements.
5. **Anthropic naming:** plain-text accurate statements that Soleur is built on, or runs, Claude Code are allowed; do not put "Claude Code" or Anthropic names or logos in the product, feature or company name, and do not imply Anthropic endorsement or partnership (S3, S4). "Powered by Claude" is allowed only alongside the product's own name.
6. "Hosted users pay Soleur plus Claude" is accurate if stated as "plus your own Anthropic API usage". It is not accurate as "plus your Claude plan".

**Item 2, visible waitlist privacy text, and privacy-text claims for the hosted tier.**

1. **Do not use "private", "never leaves your machine", "we never see your data" or equivalents for the hosted tier.** The Privacy Policy and Data Protection Disclosure describe hosted workspace content stored on Jikigai infrastructure, content sent to Anthropic under the user's key, workspace Co-Members as recipients, and operator-assisted sessions in which Jikigai reads files. Privacy Policy section 5.1's "Soleur does not intermediate, intercept, or store any data exchanged between you and Anthropic" is expressly limited to the locally installed Plugin and must not be borrowed for the hosted tier.
2. **Permitted:** statements that mirror the Privacy Policy line for line: BYOK key encrypted before storage, who the processors are, and that the waitlist address is used only for waitlist email. Each hosted-tier claim must trace to a Privacy Policy section; any claim that does not trace is out.
3. **Do not state or imply that Soleur holds, stores or uses Claude.ai logins or subscription tokens for customers.** That is both untrue for customers and the conduct Anthropic prohibits.
4. The existing `sr-only` waitlist sentence ("We'll only email you about your Soleur waitlist spot. Unsubscribe anytime.") was not audited against waitlist processing in this review. Making it visible is not a legal problem in itself, but it makes the sentence a public claim, so it needs a one-time check against the Privacy Policy waitlist and newsletter provisions before it goes live.

**Item 3, self-host install as primary CTA.** No constraint beyond the accuracy rules above. The self-host path is the one Anthropic's text leaves open to user subscriptions.

**Sign-off scope.** This gives constraints, not approval of final copy: no copy was drafted. Items 1 to 3 need the finished wording re-submitted for CLO sign-off. #9579 items 4 to 6 are not legal.

## 7. Sutra flag (not a conclusion about Sutra)

A third-party desktop app that "bills as your Claude subscription, never the API" is lawful under the live text only if the user signs in to Anthropic's unmodified Claude Code through Anthropic's own flow and the app never collects, stores or intermediates the Claude.ai credential, and it is not offering claude.ai login or rate limits as its own feature. Whether Sutra does so was not examined, and nothing here concludes that it does or does not. Do not use Sutra's practice, or its "never the API" line, as a model for Soleur copy or product.

## 8. Re-evaluation triggers (updated)

The June three stand, none fired: article un-paused or advance-notice update shipped (no, banner unchanged); "still draw from your subscription's usage limits" sentence amended (no, identical); move off owner-only (no, gate intact). Added by this review: any amendment to S3 "Authentication and credential use" or the S4 Note; any Anthropic enforcement step against the operator's account; any product work that authenticates customer or tenant runs with a user's subscription (blocked pending fresh CLO plus external counsel review).

## 9. Recommended actions

| Action | Owner | Status |
|--------|-------|--------|
| Keep `CC_OAUTH_ENABLED=1` and the owner-only gate fail-closed; no code change | operator / eng | no action |
| Inform the operator that the owner-only risk is modestly higher than the June record stated (S3 August sentence) so the risk-acceptance is re-affirmed with current facts | operator | open, optional veto stays with operator |
| Apply section 6 constraints in the #9579 marketing PR, including the pricing.njk hosted-plan sentences; resubmit final wording for CLO sign-off | marketing | open (#9579) |
| CTO to confirm whether the server agent path runs the unmodified Claude Code binary (S3 carve-out precondition) | CTO | open, only needed if customer-facing subscription use is ever reconsidered |
| Do not build customer-facing or tenant subscription auth; if ever reconsidered, fresh CLO review + external counsel + written Anthropic confirmation | CLO | standing block |
| Re-run this retrieval on the next trigger and quarterly while the pattern stays enabled | CLO | watch |

## 10. Limits of this review

Retrieved by HTTP fetch on 2026-10-06; Anthropic pages can change without notice. The Archive captures date S3's changes only to a window of 2026-08-16 to 2026-08-30. Section 6 states product facts about the hosted tier from the repo and the Privacy Policy and does not audit them. This is a draft internal attestation and not a substitute for licensed external counsel.
