---
title: Recommended downstream legal-tooling specialists
last_updated: 2026-05-15
related-brainstorm: knowledge-base/project/brainstorms/2026-05-15-claude-for-legal-evaluation-brainstorm.md
related-issues: ["#3785", "#3786"]
---

# Recommended downstream legal-tooling specialists

> **DRAFT — Recommendations on this page are starting points for evaluating downstream specialists. They are not endorsements, partnerships, or legal advice. Verify suitability with retained counsel before relying on any tool's output. Soleur is a developer tool, not a law firm.**

When a Soleur user (founder) hits a legal need that exceeds founder-grade compliance helping (`/soleur:legal-audit`, `/soleur:legal-generate`, `/soleur:gdpr-gate`, the `clo` agent), this page lists vendor-neutral downstream specialists for the threshold the user has crossed. Each section names ≥ 2 specialists; `anthropics/claude-for-legal` plugins are listed alongside founder-accessible counsel marketplaces and (where applicable) classification SaaS.

If you are handling an inbound event, jump straight to the relevant section:

- [Vendor MSA review](#vendor-msa-review)
- [DSAR request](#dsar-request)
- [AI vendor terms](#ai-vendor-terms)
- [OSS license classification](#oss-license-classification)
- [Breach notice triage](#breach-notice-triage)

## vendor-msa-review

**Trigger.** A vendor sends you a Master Services Agreement (MSA) and you need a red-flag scan before signing — common clauses to inspect include indemnity caps, IP assignment, auto-renewal, MFN, audit rights, and limitation-of-liability carve-outs.

**Statutory deadline.** None. Act before the next vendor decision-point (counter-signature, kickoff call).

| Tool | License | How to get it | Best for | Canonical URL |
|---|---|---|---|---|
| `anthropics/claude-for-legal:commercial-legal:review` | Apache-2.0 | `claude plugin marketplace add anthropics/claude-for-legal && claude plugin install commercial-legal` (Claude Code or Cowork) | Plain-language playbook diff against your standard terms; produces a redline memo for attorney review | https://github.com/anthropics/claude-for-legal |
| Founder-accessible counsel marketplace (LawTrades, Priori, Lawpath) | Commercial SaaS | Sign up → request "vendor contract review" → matched with a contract attorney within 24-48h | One-time MSA review without a retainer; typical cost $300-800 per contract | https://lawtrades.com / https://www.priorilegal.com / https://lawpath.com |
| ContractGen / LegalSifter / ContractWorks | Commercial SaaS | Vendor signup with self-service tier (varies) | Continuous contract-portfolio scanning + clause-library comparison; useful once you have ≥ 5-10 vendor contracts to track | https://www.legalsifter.com |

**If you have no retained counsel.** A founder-accessible counsel marketplace is the right escape hatch — request a one-time review for THIS contract; you do NOT need an ongoing retainer.

## dsar-request

**Trigger.** A user (typically EU/UK/CA) submits a Data Subject Access Request asking for: their data, deletion, correction, portability, opt-out, or restriction of processing.

**Statutory deadline.** **GDPR Art. 12 — 30 days** from receipt (controllers may extend by 60 days for complex requests with notice). **CCPA — 45 days** (extendable by 45 with notice).

| Tool | License | How to get it | Best for | Canonical URL |
|---|---|---|---|---|
| `anthropics/claude-for-legal:privacy-legal:dsar-response` | Apache-2.0 | `claude plugin install privacy-legal@claude-for-legal` | Drafting acknowledgments and substantive responses within statutory timelines; produces draft for attorney review | https://github.com/anthropics/claude-for-legal |
| Founder-accessible privacy counsel marketplace (LawTrades privacy lane, Priori privacy filter, IAPP Member Directory) | Commercial / association | LawTrades/Priori: request privacy specialist; IAPP: directory search + cold outreach | Live-fire DSAR triage when the request is unusual (e.g., joint controller chain, processor handoff, cross-border data) | https://iapp.org/connect/find-a-member/ |
| OneTrust / Securiti / Osano DSAR module | Commercial SaaS | Vendor signup; smaller plans aimed at SMB founders exist (Osano free tier; Securiti and OneTrust have founder/startup pricing) | Workflow-managed DSAR queue with deadline tracking, identity verification, and audit log | https://www.onetrust.com / https://securiti.ai / https://www.osano.com |

**If you have no retained counsel.** For a first-DSAR-ever situation, the marketplace lane is faster than vendor SaaS sign-up. The deadline clock starts the moment the request hits an inbox — engage someone immediately, don't wait for a tool eval.

## ai-vendor-terms

**Trigger.** You are evaluating a vendor's AI Terms of Service or Acceptable Use Policy for: training-on-customer-data, IP assignment over outputs, liability for hallucinations, model-change/deprecation rights, audit rights, sub-processor disclosure, and policy-change-without-notice clauses.

**Statutory deadline.** None. Act before signing or onboarding the vendor.

| Tool | License | How to get it | Best for | Canonical URL |
|---|---|---|---|---|
| `anthropics/claude-for-legal:ai-governance-legal:vendor-ai-review` | Apache-2.0 | `claude plugin install ai-governance-legal@claude-for-legal` | Structured review against training-on-data / liability / model-change / policy-gap categories; produces draft attorney-review memo | https://github.com/anthropics/claude-for-legal |
| Soleur's own `legal-audit benchmark` mode + counsel marketplace | OSS (Soleur) + commercial | `/soleur:legal-audit benchmark` for first-pass; escalate to LawTrades/Priori for substantive sign-off | Founder-grade red-flag scan that surfaces what to ask the lawyer about — saves billable time on the actual review | (this repo) / https://lawtrades.com |

**If you have no retained counsel.** The marketplace lane is appropriate for first-time vendor-AI evaluation. Many AI-vendor ToS issues become moot once you understand the training-on-data clause; the marketplace can clarify that one question for ~$200-400.

## oss-license-classification

**Trigger.** You are pulling in an open-source dependency and want to verify the license category (permissive / weak-copyleft / strong-copyleft / non-commercial / proprietary-with-OSS-shell / SSPL/BSL) before you ship to production.

**Statutory deadline.** None. Act before the dependency lands in a release build.

| Tool | License | How to get it | Best for | Canonical URL |
|---|---|---|---|---|
| `anthropics/claude-for-legal:ip-legal:oss-review` | Apache-2.0 | `claude plugin install ip-legal@claude-for-legal` | Classification + deployment-model fit (SaaS vs distribution vs internal-only); flags AGPL/SSPL/copyleft mismatch with your business model | https://github.com/anthropics/claude-for-legal |
| FOSSA / Snyk / GitHub Dependency Review | Commercial SaaS / GitHub-native | Vendor signup; GitHub dependency review is built into Pull Request flow on Pro plans | License detection across the full dep tree using SPDX identifiers; flags policy violations at PR-time. **Note:** these are license-classification engines, not legal-advice tools — the classification is data, not opinion | https://fossa.com / https://snyk.io / https://docs.github.com/en/code-security/supply-chain-security/end-to-end-supply-chain/end-to-end-supply-chain-overview |
| Founder-accessible IP counsel marketplace (LawTrades IP lane, Priori IP filter) | Commercial SaaS | Marketplace request for IP/OSS specialist | Substantive judgment when license classification is ambiguous (custom licenses, dual-licensed packages, patent grants) | https://lawtrades.com / https://www.priorilegal.com |

**If you have no retained counsel.** FOSSA / Snyk / GitHub Dependency Review give you the classification (which is usually unambiguous); marketplace lane is for the substantive "is this OK for our business model" judgment when the classification surfaces something interesting.

## breach-notice-triage

**Trigger.** You discover (or are told) that personal data was exposed, accessed by an unauthorized party, lost, or destroyed. This includes inadvertent exposure (a logging bug that wrote PII to a public bucket), credential compromise, vendor-side breach affecting your data, or a confirmed bad-actor event.

**Statutory deadline.** **GDPR Art. 33 — 72 hours from awareness** (controllers must notify the supervisory authority unless the breach is unlikely to result in risk; see also Art. 34 for data-subject notification when high risk). **State laws vary** — California (CCPA), New York (SHIELD), and others have their own clocks; some require notification "in the most expedient time possible and without unreasonable delay."

| Tool | License | How to get it | Best for | Canonical URL |
|---|---|---|---|---|
| `anthropics/claude-for-legal:privacy-legal:reg-gap-analysis` | Apache-2.0 | `claude plugin install privacy-legal@claude-for-legal` | Diff your current breach-response posture against current regulator guidance (Art. 33/34 + state laws); produces draft attorney-review memo | https://github.com/anthropics/claude-for-legal |
| Founder-accessible privacy/security counsel marketplace (LawTrades privacy lane, Priori privacy filter, IAPP Member Directory) | Commercial / association | Marketplace privacy/security specialist, urgent request | Live triage of a real breach, including 72-hour clock management and authority notification | https://iapp.org/connect/find-a-member/ |
| OneTrust / Securiti incident-response module | Commercial SaaS | Vendor signup; incident-response is typically a separate module from DSAR | Workflow-managed incident timeline + automated notification templates per jurisdiction; useful if you anticipate breach handling becoming routine | https://www.onetrust.com / https://securiti.ai |

**If you have no retained counsel.** The 72-hour clock means "engage someone immediately, don't wait for a tool eval." Marketplace privacy/security specialist is the fastest path; the IAPP Member Directory is the backup if marketplaces are slow.

---

### Why this page exists

This page is the single source of truth for the founder-threshold detection feature shipped by issue [#3785](https://github.com/jikig-ai/soleur/issues/3785). Background and rationale: see the [2026-05-15 claude-for-legal evaluation brainstorm](../project/brainstorms/2026-05-15-claude-for-legal-evaluation-brainstorm.md) — the triad (CPO + CMO + CLO + CTO) under USER_BRAND_CRITICAL=true converged on no direct integration with `anthropics/claude-for-legal`; this page implements the smaller adjacent yes (vendor-neutral handoff).

Re-evaluation criteria for revisiting the bridge decision are tracked in deferred issue [#3786](https://github.com/jikig-ai/soleur/issues/3786). If you have founder demand signals worth surfacing, comment on that issue.

### Maintenance

- Tool entries are intentionally vendor-neutral (≥ 2 per section). If you propose adding/removing a tool, follow the [vendor-neutrality test](../../plugins/soleur/test/legal-recommended-tools.test.ts) — every section must retain ≥ 2 rows AND no row may be claude-for-legal alone.
- If you rename this file or any H2 anchor, update the inbound references in [`plugins/soleur/agents/legal/clo.md`](../../plugins/soleur/agents/legal/clo.md) and [`plugins/soleur/skills/legal-audit/SKILL.md`](../../plugins/soleur/skills/legal-audit/SKILL.md) atomically — the test will fail commit if anchors don't resolve.
