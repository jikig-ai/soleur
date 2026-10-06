---
title: "Counsel review audit — #9579 / #9580 (PR #9584: homepage hero, hosted-tier wording, waitlist privacy line, Anthropic attribution)"
type: counsel-review
date: 2026-10-06
issue: 9579
related_issue: 9580
pr: 9584
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-10-06
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED. All seven artifacts are shippable as written, with NO required in-PR content edit. Five tracking actions are conditions of discharge (section 'Conditions'); two are corrections to existing issue bodies (#9590, #9605) that would otherwise point at a wrong outcome."
binding_constraints: "knowledge-base/legal/audits/2026-10-06-clo-9580-live-anthropic-terms-subscription-auth.md section 6 (the audit this PR lands)"
branch_head_reviewed: 38efa3aebf
reading_recorded: "The clause 'including when hosted access opens' in the waitlist privacy line is a READING of Privacy Policy 4.6 (which names the newsletter, not the waitlist). Naming the waitlist is tracked in #9590."
re_evaluation_triggers: "ANY of: (1) Anthropic amends S3 'Authentication and credential use', the S4 Agent SDK Note, or the support article 15036540 banner (same triggers as the 2026-10-06 live-terms audit); (2) the hosted tier goes on sale or app.soleur.ai signup is opened or closed on purpose (the availability reconciliation, condition C4); (3) Buttondown double opt-in is found OFF (published consent claims then become false; condition C2); (4) any hosted-tier copy that mentions a Claude plan, subscription or login, or says the hosted tier is private; (5) first arms-length waitlist DSAR or erasure request; (6) Inc. or Anthropic disputes the attributed paraphrase."
draft_notice: "Draft internal legal attestation for a non-lawyer founder. External counsel re-review is reserved for the triggers above."
---

# Counsel review audit — #9579 / #9580 (PR #9584)

This file is the discharge evidence for the Counsel-Review CLO-Attestation Gate (soleur:ship Phase 5.5) on PR #9584. The PR changes marketing copy on the Eleventy docs site and touches nothing under `docs/legal/` or `plugins/soleur/docs/pages/legal/` (verified with `git diff origin/main...HEAD --stat -- docs/legal plugins/soleur/docs/pages/legal`, empty). Nothing is attested here as a legal-document amendment. What is attested is that the new public claims are true against the repo and consistent with the published legal corpus, and that they respect the wording constraints in section 6 of the live-terms audit.

## How the review was run

- Read the diff `git diff origin/main...HEAD` for `plugins/soleur/docs/**` at head 38efa3aebf.
- Built the site from the worktree into a scratch directory (`SOLEUR_DOCS_OFFLINE=1 npx @11ty/eleventy --quiet --output=<scratch>`; 66 files) and extracted visible text and JSON-LD from `index.html`, `pricing`, `getting-started`, `about`, `vision`, `company-as-a-service`, both compare pages and `llms.txt`. Searched every sentence for plan, subscription, login, Pro/Max, "private", "never see", "your data", "cloud" and hosted/self-hosted mixing.
- Read Privacy Policy 4.6, 5.3, 5.1, 4.7 and 4.3, GDPR Policy 3.6, DPD 2.1b / 2.3(g), AUP scope, Article 30 register PA-6, `compliance-posture.md`, `apps/web-platform/app/api/checkout/route.ts`, the plan and its four Addenda, and `decision-challenges.md`.
- Independently corroborated the Amodei and Krieger attribution by web search (section Artifact 4); Inc.com itself returned 403 to automated fetches.
- Line numbers below are for head 38efa3aebf and are navigational only; the content anchor is the quoted text.

## Verdict table

| # | Artifact | Verdict | Condition |
|---|----------|---------|-----------|
| 1 | Who pays for Claude / which plan or login applies (hero, FAQs, pricing note, getting-started, compare, llms.txt, JSON-LD) | DISCHARGED | none |
| 2 | Waitlist privacy line (hero `index.njk`, pricing `pricing.njk`, getting-started helper) | DISCHARGED, reading recorded | C1 (widen #9590) |
| 3 | Post-submit success text and footer newsletter text | DISCHARGED (footer rides #9605) | C2 (correct #9605) |
| 4 | Attribution paraphrase, Inc. links, non-affiliation line, no endorsement | DISCHARGED | none (one note) |
| 5 | Hosted tier "coming soon", prices, offer JSON-LD, compare and getting-started pages; Stripe route and legal present tense | DISCHARGED; availability mismatch is TRACKED, not a blocker | C3 (file issue) |
| 6 | "Founding cohort of 10 teams" and "team collaboration" | DISCHARGED; no change required now | C4 (file issue) |
| 7 | Cross-artifact drift: Anthropic, Buttondown, Plausible | DISCHARGED; two pre-existing drifts tracked | C1, C5 |

Overall: **DISCHARGED**.

---

## Artifact 1 — Who pays for Claude usage, and which plan or login applies

**Files:** `plugins/soleur/docs/index.njk` (hero install note line 21, hosted plan line 42, plan line 41, FAQ "Is Soleur free?" 184, "How do I get started?" 192, JSON-LD twins 239 and 255), `pages/pricing.njk` (note line 279, "Do I pay for Claude separately?" 298, "Is there a free option?" 302, JSON-LD twins 344 and 352), `pages/getting-started.njk` (lines 50 to 52, FAQ 213), `pages/compare-soleur-vs-cursor.njk` (78, 119, 189), `pages/compare-soleur-vs-devin.njk` (82), `llms.txt.njk` (24, 27), `_includes/base.njk` (offer JSON-LD, line 97).

**Checked against live-terms audit section 6, item 1:**

| Section 6 rule | Result in the built site |
|---|---|
| Scope any "Claude plan" line to self-hosted | Every "Claude plan" occurrence is in a sentence whose subject is the self-hosted version: hero plan line 41 ("Self-hosted runs inside your own Claude Code, signed in with your Claude plan or an Anthropic API key."), getting-started line 52, pricing 298, homepage FAQ 192 and its JSON-LD twin. This is the wording section 6.1 calls supportable. |
| Never "Claude plan / Pro / Max / subscription limits" on hosted | None found. Pro/Max are gone from the hosted statements (the old pricing FAQ "plus their own Claude Pro, Max, or API costs" is replaced). The only "Pro" left on those pages is Cursor's own "Pro" price tier on the compare page. Pricing line 279 and FAQ 298 say hosted "use your own Anthropic API key, billed by Anthropic to you". |
| Hosted wording says API key | Hero line 42 ("Hosted version (coming soon): bring your own Anthropic API key, billed by Anthropic to you."), pricing 279 and 298, homepage FAQ and JSON-LD, offer JSON-LD description ("Hosted plans use your own Anthropic API key."). |
| Nothing implies Soleur pays for or bundles Claude usage | Pricing 279 and 298 add "Soleur plans don't include Claude usage." Hero note 21: "you pay for your own Claude usage." No sentence says Soleur or Jikigai pays, bundles or resells. |
| No "private" / "we never see your data" about hosted | A sentence-level search across the nine surfaces found no "private", "never leaves", "never see", "your data", "keep every byte" or "your compute". The two old getting-started claims ("keep every byte of memory on your own machine", "your data, your compute") are replaced by "keep your knowledge base as plain files on your own machine" (self-hosted-scoped) and "full access to your own files". |
| Hosted and self-hosted not mixed in one sentence | Hero keeps the two plan sentences in separate `<p>` elements (lines 41 and 42). Homepage "How do I get started?" puts the self-hosted credential sentence first and "Or join the waitlist for the hosted version, which takes your own Anthropic API key." as its own sentence. |
| Anthropic naming | "Built on Claude Code" appears only as plain-text description. No Anthropic name or mark is in a product, feature or company name. |

**Product-fact check.** The hosted tier takes a BYOK Anthropic API key (Privacy Policy 4.7 lists "encrypted API keys (BYOK)"; the oauth branch of `/api/keys` is operator-only per the live-terms audit). The copy is accurate for the hosted plan as designed. It does not describe operator-assisted sessions, where Jikigai's own key is used (Privacy Policy 4.2; the 2026-08-06 alpha-tester determination). Those are a non-marketed configuration for named testers, not a hosted-plan feature, so the sentence "Hosted plans use your own Anthropic API key" is not falsified by them. If operator-assisted runs are ever advertised, this row re-opens.

**Two pre-existing sentences noted, not changed by this PR, not blockers.** (a) `compare-soleur-vs-cursor.njk` line 119 says self-hosting is "with your own Claude API key"; it is narrower than the homepage ("Claude plan or an Anthropic API key") but not inaccurate. (b) Privacy Policy 5.1 says "using your own API key"; that wording is the subject of #9590, item 2, and is the reason the policy and the marketing copy differ by one credential type.

| Counsel | Date | Channel | Sign-off | Comments |
|---|---|---|---|---|
| CLO agent (v1 internal attestation, Soleur-as-tenant-zero) | 2026-10-06 | Counsel-review gate, PR #9584 | DISCHARGED | Each plan and login sentence traces to section 6 of the live-terms audit; the hosted tier is described only as BYOK API key billed by Anthropic; no subscription language touches hosted; no privacy superlative touches hosted. |

---

## Artifact 2 — Waitlist privacy line

**Text (identical on the hero, `index.njk` line 36, and pricing, `pricing.njk` line 43):** "We'll email you Soleur updates, including when hosted access opens. Unsubscribe any time. Sent through Buttondown. Privacy Policy." Getting-started line 21 carries the shorter helper "We'll email you Soleur updates, including when hosted access opens." beside a link to the pricing form, not a form of its own.

**Clause-by-clause trace:**

| Clause | Published source | Result |
|---|---|---|
| "We'll email you Soleur updates" | Privacy Policy 4.6 Purpose: "Sending periodic newsletter emails about Soleur updates, features, and content." GDPR Policy 3.6 and the Art. 30 register PA-6 (b)(i) | Matches |
| "including when hosted access opens" | Art. 30 register PA-6 (b)(ii): waitlist subscribers are notified when the hosted platform opens. Not in Privacy Policy 4.6, which does not contain the word "waitlist" (`grep -ri waitlist docs/legal/` is empty) | **A READING of 4.6**, see below |
| "Unsubscribe any time" | Privacy Policy 4.6 retention bullet: unsubscribe at any time via the link in every email; GDPR 3.6 | Matches |
| "Sent through Buttondown" | Privacy Policy 4.6 and 5.3: Buttondown as processor on Jikigai's behalf | Matches |
| Privacy Policy link | `/legal/privacy-policy/` exists in the built site | Present (links the policy, not the 4.6 anchor; acceptable) |

**Recorded reading.** The clause "including when hosted access opens" is a reading of Privacy Policy 4.6, not a quotation of it. 4.6 names the newsletter signup and its purpose ("Soleur updates, features, and content"); a launch notice of the hosted version is a Soleur update, so the reading is natural, but 4.6 does not say "waitlist" and does not say "early access". Naming the waitlist in the policy is tracked in #9590 (open) and is not done here because a `docs/legal/` edit pulls in the Eleventy mirror, the SHA re-pin and five CI gates.

**Is the reading acceptable to ship now? Yes, on condition C1.**

- Direction of the gap. The line discloses more than the policy names, not less. The previous visible-to-assistive-tech sentence ("We'll only email you about your Soleur waitlist spot") and the old pricing line ("We email you once when early access opens") were narrower than what happens technically: the waitlist form posts to the same Buttondown endpoint as the newsletter form and is separated only by the `homepage-waitlist` and `pricing-waitlist` tags, so a waitlist subscriber is on the newsletter list. Under-disclosing and then sending newsletters is the purpose-limitation problem; the new line removes it. This is why the new text is safer than the text it replaces.
- Consent quality. The visible line sits directly under the submit control (the screenshot gate asserts this, with contrast of at least 4.5), so the consent is informed at the point of action, which the old `sr-only` text did not achieve for sighted users.
- Residual gap, and why it is tolerable. A reader who opens the Privacy Policy finds the newsletter purpose and the same processor, double opt-in and unsubscribe route. There is no data category, processor, retention or transfer that the policy omits for waitlist subscribers, because they are processed identically to newsletter subscribers. The gap is one word of scope, and it is already tracked.
- **Drift this review found that #9590 does not yet cover.** Art. 30 register PA-6 (b) says the waitlist is notified "once" and calls both lists "single-purpose, consent-scoped marketing lists". The new copy tells waitlist subscribers they will receive "Soleur updates", which is wider than "once". The register is the more restrictive text and will be the one read by a regulator. It must be reconciled when #9590 is done (condition C1), not edited in this PR (the register change belongs with the policy change so the two cannot disagree for a period).

| Counsel | Date | Channel | Sign-off | Comments |
|---|---|---|---|---|
| CLO agent (v1 internal attestation) | 2026-10-06 | Counsel-review gate, PR #9584 | DISCHARGED, reading recorded | Ship. The clause is a reading of 4.6, safer than the narrower text it replaces, and tracked at #9590. Condition C1 widens #9590 to the Art. 30 register PA-6 and the GDPR Policy. |

---

## Artifact 3 — Post-submit text and the footer newsletter text

**Waitlist success text (`_includes/base.njk` lines 359 and 370, both forms):** "You are on the list. If a confirmation email arrives, open it to finish signing up. We will notify you when the hosted version is ready."

- Accuracy. True whether or not double opt-in is enabled, because the confirmation step is conditional ("If a confirmation email arrives"). It does not assert that the subscription is active, it does not promise an email to someone who never confirms (the sentence that tells them to confirm precedes the promise), and it says "hosted version", matching the rest of the site, in place of "cloud platform".
- Consent record. It is consistent with the published Privacy Policy 4.6 double-opt-in statement ("Your subscription is only activated after you click the confirmation link") without depending on it.
- It is acceptable as shipped. Buttondown double opt-in could not be read through the API (#9605). Indirect evidence recorded in #9605 (19 of 37 subscribers `unactivated` from the embedded form) points to double opt-in being ON. If it is ON, a stronger line ("Check your inbox to confirm your spot") would be better UX, not required for legal accuracy.

**Footer newsletter success text (`base.njk` line 351, 63 pages, unchanged by this PR; it is the same string as on `main`):** "Subscribed. You will hear from us when it matters."

**Ruling: it may ride #9605. It does not have to change in this PR.** Reasons: (i) the string is pre-existing and not touched by the diff, so this PR neither introduces nor widens it; (ii) the exposure is a user who believes the subscription is active before clicking the confirmation link, which costs the user a missed newsletter and no legal position or money; (iii) changing it means changing the inline script and recomputing the CSP `sha256` in the `Content-Security-Policy` meta tag, a deploy-sensitive edit on every one of 63 pages; (iv) it is the same unverified fact (is double opt-in on) as the waitlist text, so a single verification should drive both.

**Correction required to #9605 (condition C2).** The issue body says, for the case where double opt-in is OFF, "close this item with a comment". That is the wrong outcome. The published Privacy Policy 4.6 and 5.x, GDPR Policy 3.6 ("verified through double opt-in") and the Art. 30 register PA-6 (TOMs: "double opt-in confirmation (consent verification)") all state that double opt-in is operating. If Buttondown double opt-in is OFF, those statements are false and the consent basis (Art. 6(1)(a), Art. 7(1) ability to demonstrate consent) is mis-described, which is a CLO finding, not a closed item. The issue must say: if ON, restore the stronger waitlist strings and change the footer to the confirmation wording below; if OFF, escalate to CLO and correct the three published documents before anything else.

**Drafted wording for #9605, if ON (not applied here):**

- Footer (`base.njk` line 351): `'You are on the list. If a confirmation email arrives, open it to finish signing up.'` Use the same wording as the waitlist text so one string is verified once. Recompute the CSP hash last and run the CSP validator.

| Counsel | Date | Channel | Sign-off | Comments |
|---|---|---|---|---|
| CLO agent (v1 internal attestation) | 2026-10-06 | Counsel-review gate, PR #9584 | DISCHARGED | Waitlist success text is true on both branches of the unverified fact. Footer text rides #9605 as ruled; #9605 must be corrected so its OFF branch escalates rather than closes (C2). |

---

## Artifact 4 — Attribution: Amodei and Krieger paraphrase, Inc. links, non-affiliation

**Surfaces:** `index.njk` lines 95 to 97 (paraphrase, source line, note), `pages/company-as-a-service.njk` lines 137 and 141, `pages/about.njk` line 36, `pages/vision.njk` line 26, footer line in `_includes/base.njk`.

**What changed against `main`.** The verbatim blockquote ("I would not be surprised if the first single-person billion-dollar company ... happens in the next couple of years.") is removed; the "As seen in Inc.com" strip is removed; the Organization `subjectOf` NewsArticle block (false structured data with a wrong date) is removed from the JSON-LD; `company-as-a-service` no longer says "interview" or "told Inc.com". Built output contains no quotation marks around any Amodei or Krieger words.

**Shipped wording (homepage, line 95):** "In May 2025, at Anthropic's Code with Claude developer conference in San Francisco, Anthropic CEO Dario Amodei was asked whether a billion-dollar company run by one person using AI could be built. He said it would certainly happen, as soon as 2026. Inc. reported that in a later press Q&A he slightly walked back that prediction, putting the chance at 70-80 percent." Source line: "Inc. report by Ben Sherry, May 23, 2025", linked to the Inc. article. Krieger (`company-as-a-service` line 141): "then Anthropic's chief product officer and co-founder of Instagram, said at Anthropic's Code with Claude conference that he built a billion-dollar company with 13 people and that, with Claude 4, he and his co-founder could probably manage on their own, as Inc. reported."

**Is the fact-checker's recorded result adequate, given Inc. returned 403 to automated fetches?** Yes, for a past-tense, attributed, unquoted paraphrase that links its source, on four grounds.

1. The sentence is attributed to a named reporter and outlet and links the article. A reader can verify it. The legal exposure of a past-tense paraphrase with attribution is far below that of the removed verbatim quotation, which the fact-checker found was not in the cited article (that finding, not the 403, is what drove this PR).
2. The fact-checker did read the page (Playwright rendered it in full during planning; plan Phase 0 step 4 and Addendum round 1 record the verdicts), and the fact-check corrected three overstatements in the plan's own first draft (the question asked, the answer, the month) and the Krieger "told Inc.com" sentence. The shipped text is the corrected version.
3. Independent corroboration performed in this review (web search, 2026-10-06): multiple outlets report that Amodei, at Anthropic's Code with Claude developer conference, was asked when the first billion-dollar company with one human employee would appear and answered "2026" (for example Benzinga, "Anthropic CEO says the first billion-dollar company staffed by one person will appear next year"; and Horasis). That supports the question, the answer, the venue and the date. It does not independently confirm the word "certainly" or the later 70-80 percent figure; those, and Krieger's remark, rest on the fact-checker's reading of the Inc. article.
4. The subject matter is a public statement by public figures about a forecast, stated neutrally, with no statement that could damage either speaker.

Two notes, neither a blocker. (a) "certainly" is the strongest word and the one least corroborated outside the fact-checker's record. If the fact-checker's verdict can be re-run when Inc. is next readable by a browser, do so; if it cannot support "certainly", the safe edit is to delete the word on `index.njk` line 95, `company-as-a-service.njk` line 137 and `vision.njk` line 26 together (the guard tests pin the attribution vocabulary, so run the suite). (b) By the time this ships the "as soon as 2026" window has about twelve weeks left; that is a CMO freshness question, not a legal one.

**No endorsement, no Anthropic marks.** The footer on every built page reads "Soleur is an independent product, not affiliated with, sponsored by, or endorsed by Anthropic." (`_includes/base.njk`, footer block; confirmed in the built `pricing`, `index` and `getting-started` output). The homepage attribution block repeats it (`landing-quote-note`, line 97). No Anthropic logo or mark is used. "Claude Code" and "Anthropic" appear only as plain-text descriptions of the platform Soleur runs on and of speakers' titles. No page names the product, a feature or the company with an Anthropic or Claude Code name (section 6, item 5; S3 and S4 branding rule). No page says "partner", "official", "certified" or "endorsed by". The Inc. page is cited as a press report, not as an endorsement.

**Residue outside this PR's diff.** Blog posts and distribution content still carry the earlier unverified quotations; that is #9589 (open) and is correctly out of scope. Re-run the fact-checker on each when #9589 is worked.

| Counsel | Date | Channel | Sign-off | Comments |
|---|---|---|---|---|
| CLO agent (v1 internal attestation) | 2026-10-06 | Counsel-review gate, PR #9584 | DISCHARGED | Past tense, attributed, unquoted, linked, dated; non-affiliation on every page; no Anthropic marks. The 403 does not undermine it because the exposure it would have mitigated (a false verbatim quotation) is gone. |

---

## Artifact 5 — Can the hosted tier be bought or signed up for now?

**Facts as the repo shows them.**

- The marketing surface offers only a waitlist for hosted: every pricing tier card carries a "Coming Soon" badge and a waitlist or contact call to action (`pricing.njk` lines 231, 245, 259); the pricing meta description reads "from $49/month once hosted plans open. Join the waitlist."; the hosted offer JSON-LD is named "Solo (Hosted version, coming soon)" with the description "from $49 per month once the waitlist opens" and declares no `availability`, `PreOrder`, `BuyAction` or `OrderAction` (a guard asserts that on every marketing page). Compare pages say "hosted version coming soon, from 49 dollars per month". Getting-started says "hosted plans (coming soon; join the waitlist)". `llms.txt` says "hosted version is coming soon (waitlist)". `/vision/` links the waitlist. No marketing page links to `app.soleur.ai` as a way to buy.
- Remaining price statements are hosted-only and sit under that framing: the pricing page's "$49/mo" tier prices (each card badged), "From $49/mo" in the comparison stack, and the FAQ "Why should I pay $49/mo when AI coding tools cost $20?" (`pricing.njk` line 290). That FAQ question states a price without availability wording but sits on a page whose header, tier cards and the adjacent FAQ (line 307, "We are building the hosted platform now. Join the waitlist...") say it is not yet available. I rule it acceptable. An optional tightening is "Why would I pay $49/mo (planned hosted price) when AI coding tools cost $20?", with its JSON-LD twin at line 328 changed identically (the parity test pins the pair).

**The mismatch the lead asked about.** The following also exist, and the "coming soon" wording is in tension with them:

- `apps/web-platform/app/api/checkout/route.ts` ships a Stripe Checkout session route with tier validation (`VALID_TARGET_TIERS`: solo, startup, scale, enterprise) and double-charge guards.
- The roadmap lists "Stripe live mode activation" as Done (item 4.10, #1444).
- `apps/web-platform/app/(auth)/signup/page.tsx` is a public sign-up page; no invite or waitlist gate is visible in `(auth)/signup`.
- `docs/legal/data-protection-disclosure.md` 2.1b and 2.3(g) and `docs/legal/acceptable-use-policy.md` scope paragraph describe `app.soleur.ai`, "subscription and payment processing through the Web Platform" and Stripe Checkout in the present tense. Terms & Conditions 3b governs team workspaces on the Web Platform.
- A published blog post (`plugins/soleur/docs/blog/...agents-that-use-apis-not-browsers`, outside this diff) carries "Connect your repo at app.soleur.ai" as a call to action.

**Ruling: not a blocker for this PR; TRACKED (condition C3).** Reasons.

1. Direction of the error. The PR moves the marketing surface toward the more conservative statement: it stops advertising a purchasable hosted tier. A "coming soon" label on a product that technically has a reachable sign-up understates availability; it does not induce a purchase of something that does not exist, and the checkout path is not offered from any page this PR touches. The harm pattern of a false availability claim (a visitor pays for something undeliverable) is absent.
2. The legal pages are not made false by the PR. They describe the processing that actually occurs when someone does sign up (and must, because any account or payment that exists is governed by them). They were true before this PR and remain true.
3. The reconciliation is a product and legal decision, not a copy fix: either gate `app.soleur.ai` sign-up and checkout to match "coming soon" (CTO/CPO), or state a limited-availability posture in the DPD, AUP and Terms and in the marketing copy (CLO/CMO), and fix the blog CTA. Doing it inside a marketing-copy PR would either edit `docs/legal/**` (which this PR deliberately does not) or invent a product posture.
4. The plan's own Addendum (round 2) already records the mismatch and removed "No payment is taken yet" from the offer JSON-LD precisely because that sentence could be false while `checkout/route.ts` ships. That is the correct handling and it is verified in the built output: the sentence is absent.

**Issue to file (C3), title and body for the lead to use:** "legal+product: reconcile hosted-tier availability (marketing 'coming soon'/waitlist vs live app.soleur.ai signup, shipped Stripe checkout, present-tense DPD/AUP/T&C, blog CTA)". Body: list the five facts above; decide gate-vs-disclose; if disclosing, name a limited-availability sentence in DPD 2.1b, AUP scope and T&C and align the blog CTA; label `domain/legal`, `domain/product`, priority p2. Re-evaluation trigger: the first arms-length paying customer, or any change to checkout availability.

| Counsel | Date | Channel | Sign-off | Comments |
|---|---|---|---|---|
| CLO agent (v1 internal attestation) | 2026-10-06 | Counsel-review gate, PR #9584 | DISCHARGED, mismatch TRACKED (C3) | No sentence states or implies hosted can be bought or signed up for from the marketing surface. The offer JSON-LD carries no availability claim. The checkout route and the present-tense legal descriptions do not make "coming soon" misleading in a way that harms a visitor; the reconciliation is a separate decision. |

---

## Artifact 6 — "Founding cohort of 10 teams" and "team collaboration"

**Both are pre-existing** (neither is in the diff's changed lines except by context): `getting-started.njk` line 22 ("Founding cohort — limited to 10. Book intro"), line 206 ("We're onboarding a founding cohort of 10 teams by hand ... Access opens in waves ... we ship weekly and move people off the list as capacity grows") with its JSON-LD twin at line 250; and "team collaboration" in the hosted feature list at line 226 with its twin at line 290.

**"Team collaboration": backed, no change.** The published corpus documents team workspaces as a shipped Web Platform feature: Terms & Conditions 3b (Workspace Owner and Co-Members), DPD 2.3(u) (workspace members), and the PA-19 and PA-20 ledgers attested in `2026-05-counsel-review-4353.md` and `2026-05-counsel-review-4289.md`. The statement "The hosted version (coming soon) adds ... team collaboration" is accurate as a feature description. (The lead's premise that no artifact backs it is mistaken for this half; it is backed by the legal corpus and the shipped substrate.)

**"Founding cohort of 10 teams": partly backed, no change required now, tracked (C4).** The roadmap records a recruitment target of 10 solo founders (row 4.1, #1439, "In progress, 1 of 10"). So a cohort of 10 exists as a target. What is not backed: that the cohort is "teams" (the roadmap says solo founders), that it is "onboarded by hand" on the hosted tier (alpha tester 1 was onboarded on the self-hosted plugin), and that "access opens in waves" and people are moved "off the list as capacity grows" (no process artifact). These are operational claims, not legal-term claims; the limit "10" matches the real target, so the scarcity claim is not invented. The consumer-law risk (a false scarcity or process claim) is low and the claims are pre-existing and unchanged. This PR need not touch them.

**Issue to file (C4):** "content: substantiate or soften 'founding cohort of 10 teams' and 'access opens in waves' (getting-started line 22, FAQ line 206 and JSON-LD twin) against roadmap 4.1; owner CMO/CPO". Suggested wording if the claim cannot be substantiated: "We're onboarding a founding cohort of 10 founders by hand. Run the self-hosted version today."

| Counsel | Date | Channel | Sign-off | Comments |
|---|---|---|---|---|
| CLO agent (v1 internal attestation) | 2026-10-06 | Counsel-review gate, PR #9584 | DISCHARGED | "Team collaboration" is backed by T&C 3b and DPD 2.3(u). "Founding cohort of 10" matches a real roadmap target; the surrounding process claims are unsubstantiated and tracked, not blocking. |

---

## Artifact 7 — Cross-artifact drift for each named vendor

| Vendor | What the diff says | What the published legal pages say | What `compliance-posture.md` says | Result |
|---|---|---|---|---|
| **Anthropic** | Self-hosted: runs in the user's own Claude Code with a Claude plan or API key. Hosted (coming soon): the user's own Anthropic API key, billed by Anthropic to the user. Soleur does not include Claude usage. Independent of, not endorsed by Anthropic. | Privacy Policy 4.7 lists encrypted BYOK API keys; 5.1 (Plugin) says content goes to Anthropic with "your own API key" (#9590 item 2 will widen to "your own credentials"); Terms and DPD describe content sent to Anthropic under the user's key. | Anthropic PBC row: Jikigai-keyed Anthropic API surface only; DPA via Commercial Terms Section C. The user's own key is the user's own relationship with Anthropic, so the row's scope (Jikigai-keyed) is consistent with the "billed by Anthropic to you" wording. | Consistent. One-word difference in 5.1 is tracked in #9590. |
| **Buttondown** | "Sent through Buttondown" on the waitlist line. | Privacy Policy 4.6 and 5.3, GDPR Policy 3.6, 5.x and 8.3, DPD 2.3 and the register of processors: Buttondown is a US-based processor under SCCs Module 2; DPA applies to all tiers. | **No Buttondown row** in the Vendor DPA Status table (the string does not appear in the file). A DPA verification issue existed (#529, closed) but no DPA snapshot exists under `knowledge-base/legal/data-processing-agreements/` (only anthropic, flagsmith, openai). Article 30 register PA-6 does carry Buttondown. | The diff's framing matches the public pages. **Pre-existing drift:** the living status document does not track the Buttondown DPA that three published documents assert. Not caused by this PR; the PR makes the processor name visible at the form, which raises the importance of the row. Condition C5. |
| **Plausible** | One new custom event name (`Hero Self-host Click`, via the class `plausible-event-name=Hero+Self-host+Click` on the install link) on the existing Plausible script; no new data category. | Privacy Policy 4.3 and 5.x: cookie-free analytics, EU-hosted, no personal data stored, legitimate interest. | Plausible row is PENDING (region verification and status flip), pre-existing, scoped to the legacy `agent-runner.ts` path. | Consistent; an event name adds no personal data. The PENDING status is pre-existing and not widened. |
| **Out-of-diff note** | `/vision/` card "Bring Your Own Intelligence" names "Anthropic, OpenAI, Gemini, Llama" as pluggable keys. Pre-existing and unchanged. | Privacy Policy 4.7 and the processor lists name Anthropic as the BYOK provider; no published statement covers OpenAI, Gemini or Llama keys on the hosted tier. | No Gemini or Llama row; OpenAI has a snapshot file but no posture row in the Vendor table. | Not part of this PR. Recorded so it is not mistaken for approved wording. Fold into condition C3's product-availability reconciliation or a CMO claim sweep. |

| Counsel | Date | Channel | Sign-off | Comments |
|---|---|---|---|---|
| CLO agent (v1 internal attestation) | 2026-10-06 | Counsel-review gate, PR #9584 | DISCHARGED | The diff's framing of each vendor agrees with the published pages. Two pre-existing drifts (Buttondown missing from the posture table; PA-6 "once" versus "updates") are tracked, neither introduced here. |

---

## Conditions of discharge

No in-PR edit to docs, plans, templates or tests is required. The following are tracking actions the lead applies as GitHub issue edits or new issues (none touches a file in this PR):

| ID | Action | Why it is a condition |
|---|---|---|
| C1 | Comment on #9590 widening its scope. In addition to Privacy Policy 4.6 (add "and notices about waitlist or early access") and 5.1 ("your own credentials"): amend Article 30 register PA-6 (b)(ii) so it no longer says the waitlist is notified "once" and "single-purpose" if the list receives Soleur updates; align GDPR Policy 3.6 and its processing-register item 6, and DPD 2.3(g). State the reading in the issue: "the visible line says 'including when hosted access opens' as a reading of 4.6; naming the waitlist closes it." | The register is the more restrictive text and currently disagrees with the visible copy. The reading is acceptable to ship only while that reconciliation is tracked. |
| C2 | Edit #9605 so that its "If OFF, close this item" branch reads "If OFF, escalate to CLO: Privacy Policy 4.6, GDPR Policy 3.6 and Art. 30 PA-6 assert double opt-in", and so that its ON branch also lists the footer string (`base.njk` line 351, 63 pages) alongside the two waitlist strings. | As written, #9605 can close a false published consent statement. |
| C3 | File the availability-reconciliation issue in Artifact 5. | The "coming soon" copy and the shipped checkout, open sign-up page, present-tense legal pages and a blog CTA cannot all be right; ruled tracked, not blocking. |
| C4 | File the "founding cohort of 10 teams / access opens in waves" substantiation issue in Artifact 6. | Pre-existing unsubstantiated process claims; low risk, tracked. |
| C5 | File an issue to add a Buttondown row (DPA status, SCCs, instrument source) to the Vendor DPA Status table in `knowledge-base/legal/compliance-posture.md`, reusing the closed #529 verification as the source, and to store a DPA snapshot beside the other three. | The living status document does not track a processor the public pages name three times. |

Optional edits, left to the lead, neither required: (a) tighten the pricing FAQ question as drafted in Artifact 5 (change the visible question and its JSON-LD twin together); (b) delete "certainly" from the three Amodei sentences as noted in Artifact 4 if the fact-checker cannot re-confirm it.

## Decision record

**Decision:** Discharge PR #9584 on a CLO-agent attestation, with five tracking conditions and no required in-PR edit.

**Rationale:** (a) every hosted-tier claim in the diff traces to the live-terms audit section 6 or to a published Privacy Policy section; (b) the privacy line is wider than the policy's wording by one clause but narrower in risk than the text it replaces, because it discloses what the technical setup already does; (c) the footer text and the Buttondown double-opt-in question are pre-existing and share one unverified fact, so one verification (#9605) should drive both, and #9605 must be corrected so it cannot close a false statement; (d) the hosted-availability mismatch is real and wider than a marketing PR can settle, and the PR moves the copy in the conservative direction; (e) the attributed paraphrase removed the actual exposure (a verbatim quotation not in the cited article).

**Side effects:** This PR makes the waitlist privacy claim visible and public for the first time, so the line now functions as a representation to data subjects; the register and policy reconciliation in C1 is therefore not optional housekeeping. It also lands the live-terms audit, whose section 6 constraints now bind future hosted-tier copy; the guard tests in `plugins/soleur/test/seo-aeo-drift-guard.test.ts` enforce a restated form of them.

## Limits of this review

Draft internal attestation, not a substitute for licensed external counsel. The Inc.com article could not be fetched by automated tools; the Amodei "certainly" wording and the Krieger remark rest on the fact-checker's recorded reading, with corroboration of the question, the answer and the date from other outlets. Buttondown double opt-in state was not verified (#9605). Whether `app.soleur.ai` sign-up and checkout are in practice open to the public was inferred from the repo (public sign-up page, shipped checkout route, roadmap), not tested against production. Section 6 of the live-terms audit itself states product facts from the repo and was not re-audited here. Anthropic pages can change without notice.

## Post-sign-off actions

1. Lead applies C1 to C5 as issue comments, edits or new issues; none requires a commit to this branch.
2. The PR body states: no `docs/legal/**` change; the waitlist line is a recorded reading of Privacy Policy 4.6 (#9590); footer newsletter text deliberately left for #9605; availability mismatch tracked (C3).
