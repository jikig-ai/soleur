---
date: 2026-10-24
topic: harness-storefronts
status: no-go
issue: 11035
---

# Harness storefronts

**Status:** No-go. Chosen by the operator on 2026-10-24.
**Branch:** `feat-harness-storefronts`
**Draft PR:** https://github.com/jikig-ai/soleur/pull/11033

## User-Brand Impact

- **Artifact:** a Soleur listing that would act as a customer's always-on teammate on a third-party agent product (a Grok Bot, an OpenAI Dot, or a Gemini agent).
- **Vector:** one founder loses files or credentials, or the teammate sends, pays, commits, or writes legal or finance text without Soleur's review gate.
- **Threshold:** single-user incident

Tagged **user-brand-critical** (auto, per #5175). The Phase 0.4 lane is `cross-domain`.

## What We're Building

A decision record. Soleur stays available inside the coding agent a founder already runs: Grok Build, Codex, and the Antigravity CLI. This session publishes no listing, adds no adapter, and opens no publisher account.

The names in the request are always-on teammate products. They are a different surface from the harness adapters already in this repo.

- **Grok Bot** (https://x.ai/bot, checked 2026-10-24) is an always-on teammate with its own computer and a marketplace. Every bot on one account shares one persistent cloud computer. Files, browser state, and logins are per user. Deleting a bot can leave those behind. The download host is Cursor. This is distinct from the Grok Build plugin index (`github.com/xai-org/plugin-marketplace`, a SHA-pinned pull request) and from the in-repo `.grok/` plugin.
- **OpenAI Dots** (https://openai.com/index/introducing-dots, 2026-09-29) are always-on ChatGPT agents with a cloud computer. A dot can start a Codex cloud task. Codex remains the engineering harness. A public plugin is a reviewed ZIP in a directory shared by ChatGPT and Codex. Lifecycle hooks are not eligible for that directory.
- **"Gemini Duets" is not a product name that search returned.** Nearby products are the Gemini enterprise agent (Google Cloud, 2026-10-08, Agent Gallery) and a reported Gemini small-business hub inside the Gemini app (2026-10-20, unverified here). Claude Duet (https://claude.com/resources/articles/claude-duet, 2026-10-21) is Anthropic's product. It is not a substitute for the Gemini question.

## Why This Approach

The operator picked Approach A.

### Approach A: Record the no-go (chosen)

Write this decision and stop. No listing, no new adapter, no publisher account.

**Pros:**

- Matches the leader consensus and the draft legal ruling below.
- Leaves the Phase 4 demand measurement (#1439, 2 of 10 as of the 2026-09-28 comment) as the open product work.
- Adds no new processor or controller role for Jikigai.

**Cons:**

- A founder who wants Soleur on a bot or a dot will not find a Soleur listing there.

**Best when:** demand is unmeasured and the publisher contract would put customer logins on a shared machine outside Soleur's review gate. That is this case.

### Approach B: Operator-only dogfood (parked)

The founder runs Soleur on their own bot, on their own repos, with no listing. The draft legal ruling says that framing is a different question from this one. The operator did not choose it.

### Approach C: Grok Build catalog pull request only (parked)

A SHA-pinned entry in the Grok Build plugin index. That index is a different product from a Grok Bot listing. Whether `hooks/hooks.json` PreToolUse asks or defers on a clean `grok plugin install` is unmeasured. The operator did not choose it.

### Approach D: Specify one shelf anyway (parked)

Override the hold and write a listing spec for one product. The operator did not choose it.

## Key Decisions

- **No-go on a customer-facing listing.** Chosen 2026-10-24. Covers a Grok Bot / Cursor marketplace submission, an OpenAI app or plugin whose purpose is a customer's Dot running these skills, a Gemini Agent Gallery listing, any claim under the name "Gemini Duets", and treating Claude Duet as the stand-in.
- **Existing adapters stay.** Grok Build (`.grok/`), the Codex adapter, and the Antigravity CLI remain the way to run Soleur. This decision does not change them.
- **Cursor marketplace listing stays rejected.** ADR-274: "Submit a listing to the Cursor marketplace" is Rejected. "that submission is a separate contract, and nothing in this decision authorizes it." Install stays a local `--plugin-dir` plus `agent plugin marketplace add` of this git URL.
- **No `.gemini/` revival.** ADR-245 deleted `.gemini/` because it was unmaintained. Re-entry needs a `Harness` member and a generator. Gemini has not re-entered.
- **Demand gate still open.** Issue #1439 is OPEN, title "feat: recruit 10 solo founders (Phase 4 validation)", `updatedAt` 2026-09-28. The latest comment on that date records alpha tester 2 of 10. The business-validation verdict remains PIVOT (re-validated 2026-06-08): measure adoption on the shipped platform. A listing does not answer whether a solo founder who does not already pay that host will use Soleur across two departments for two weeks and pay $49.
- **March 2026 marketplace no-go was not revisited on its date.** `knowledge-base/project/brainstorms/archive/20261012-213508-2026-03-10-claude-marketplace-evaluation-brainstorm.md` says "No-go (revisit April 2026)". No revisit is on record. Enterprise positioning and measured demand are still unmet. A price table exists in `knowledge-base/product/pricing-strategy.md`. Stripe is test-mode. That is not a live offer.
- **Publisher contracts are not accepted.** The operator was not asked to accept Cursor Marketplace Publisher Terms, OpenAI App Developer Terms, or a customer Art. 28 DPA (#4330) for this surface. Those authorizations were not granted.
- **Productize candidate: none.** `knowledge-base/project/learnings/2026-05-15-evaluating-anthropic-first-party-plugin-marketplaces.md` already covers evaluating a vendor marketplace. A new skill would duplicate it. The 2026-03-10 learning `2026-03-10-verify-external-platforms-before-strategizing.md` already covers verifying the live product before naming a strategy. "Gemini Duets" is that failure mode, recorded here as a premise defect.
- **Visual design:** skipped. This decision has no page, component, modal, banner, nav, flow, or email template (`wg-ui-feature-requires-pen-wireframe` trigger is absent).

## Open Questions

Parked. The operator chose to stop, so these are not research tasks for a listing.

- **(out of scope)** Which sentence may fail in public: "the OS you run inside the coding agent you already use" or "a teammate that runs the company while you are away." The homepage currently says both. The smallest honest copy change (one negative line on getting-started, equal denial, no vendor account) was not chosen.
- **(out of scope)** Whether a skill drop onto a user's Dot or Grok Bot, with no directory submission, is already "creating an App" or "submitting a Plugin".
- **(out of scope)** Soleur's license against Cursor Marketplace Publisher Terms §3.3 (GPL, AGPL, and LGPL). Unread.
- **(out of scope)** The SpaceXSI data-processing addendum in full, and which agreement Grok Bot Terms incorporate for consumer X, Teams, and Enterprise.
- **(out of scope)** Whether Dots sit inside "the Services" under the OpenAI Services Agreement. The OpenAI DPA effective 2026-01-01 does not name Dots.
- **(out of scope)** The Google Data Processing Addendum's sub-processors, training, retention, deletion, and SCC module. The Gemini Enterprise business terms fetched on 2026-10-24 do not mention a third-party skill marketplace or "Gemini Duets".
- **(out of scope)** The five engineering measurements the CTO listed (clean-install PreToolUse, a Dot that starts Codex, ZIP rejection of `hooks/hooks.json`, a Grok Bot destructive-push fixture, Gemini `run_skill_script` human prompt). Unrun, because the decision is a no-go.
- **(out of scope)** Customer Art. 28 DPA, still deferred at #4330. `soleur:gdpr-gate` does not scan `docs/legal`. It would run later only if an implementing plan added a regulated path or a non-EEA vendor SDK.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Park Grok Bot and the OpenAI Dot. No-go on "Gemini Duets", on the Gemini Agent Gallery, and on treating Claude Duet as a substitute. A listing does not answer the Phase 4 demand question.

### Legal

**Summary:** Draft ruling only. It is not legal advice. Publishing Soleur so a customer's Grok Bot or OpenAI Dot runs these skills is prohibited to publish now. A Gemini listing, or any claim that a Gemini agent may run Soleur, is not yet knowable: do not list. Marketing pages are not the contract.

The ruling's artifact is a customer-facing publication whose skills execute inside the vendor teammate while that teammate holds the customer's logins. The operator-self-use framing that flipped the June 2026 Anthropic verdict is a different question, and it was not chosen.

Facts the CLO fetched, kept short:

- Cursor Marketplace Publisher Terms bind a Grok Bot plugin submission. The publisher is solely responsible for Plugin Data, must show a privacy policy that describes the processing (Soleur's current notice does not, so §4.2 fails on day one), must not train on Plugin Data, indemnifies Anysphere, and faces a $100 aggregate cap.
- Grok Bot Terms (12 October 2026) put agentic actions, including actions the bot starts on its own, on the customer. Human review is required before external communications, financial transactions, data deletion, permission changes, production systems, or material effects on third parties. Bots on one user share one environment. That environment is not a security boundary.
- OpenAI App Developer Terms (28 September 2026) treat the publisher and OpenAI as separate independent controllers. The publisher is not an OpenAI customer for the published app, so the customer DPA does not attach. The publisher warrants no HIPAA and no PCI, indemnifies OpenAI, and faces a $100 cap. Disconnecting an app does not delete information the dot already obtained.
- Help Center article 20001530: Pro dots are unavailable in the EEA, Switzerland, and the UK. That is a product limit, not a transfer solution.
- Relying on `x.ai/bot` or the Dots launch post as a contract or a DPA is prohibited. A Jikigai-operated machine, credential, or purpose for any of these vendors is prohibited. The published corpus gives Jikigai no role only for a provider-operated session on the user's own credentials and purposes. The named example is a Devin Cloud VM. The 13 September 2026 amendment says xAI is not a Jikigai processor. The 16 September 2026 amendment disables Codex customer-content execution pending a later qualification.

### Engineering

**Summary:** Park overall. A Grok Bot listing is a no-go. A public Dot ZIP is hookless, so it cannot carry Soleur's PreToolUse ask or defer. A Gemini harness port is a no-go. Do not revive `.gemini/`. Complexity order: a Dot ZIP, then a Grok Bot listing, then a Gemini agent. A Grok Build catalog pull request is smaller than all three and is a different product. `git grep` of these product names in the tree returned no package.

### Marketing

**Summary:** Public listing is a no-go on all three shelves. A Codex plugin card, which is not a Dot, stays parked until every real harness can have the same plain install card and external use is measured. ADR-274 already forbids announcing support ahead of measurement.

### Operations

**Summary:** Nothing is submitted. A Gemini partner-sales motion remains a no-go. A $0 listing is still a bad use of founder time when it creates an inbox only the founder reads. Do not open a publisher account. Burden order: Gemini, then an OpenAI ZIP resubmitted on every skill change, then a Grok Bot review form.

## Next Steps

The no-go is the deliverable. Planning a listing, an adapter, or a publisher account is not the next step. The successor skills `soleur:plan` and `soleur:one-shot` stay unused unless the operator reopens the decision.

Archival of this file and of `knowledge-base/project/specs/feat-harness-storefronts/` stays deferred while they are the live decision record on draft PR #11033. `archive-kb.sh` must not move them during compound. Archival of this spec dir must be deferred until the operator is done with the live path, which is after any later `soleur:ship` only if the operator first asks to land the record.
