---
last_updated: 2026-03-23
last_reviewed: 2026-03-23
review_cadence: monthly
owner: CPO
depends_on:
  - knowledge-base/product/business-validation.md
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/product/pricing-strategy.md
---

# Product Roadmap: Soleur Cloud Platform

## Strategic Context

The CaaS thesis is validated: solo founders want an AI organization that runs every department. The delivery surface is wrong: no one wants to install a Claude Code plugin. The market wants a **cross-platform cloud service** accessible from web, mobile, and desktop.

This roadmap pivots from plugin-first to **cloud-first**. The CLI plugin remains as a power-user option. The cloud platform (app.soleur.ai) becomes the primary product.

### Strategic Themes

| # | Theme | Rationale |
|---|-------|-----------|
| **T1** | **Ship the Cloud Platform** | The web platform is the product. Mobile-first, PWA for all three surfaces (web, mobile, desktop). No native apps for MVP. |
| **T2** | **Secure Before Beta** | No external user touches PII or API keys on an unaudited platform. Security is table stakes, not a feature. |
| **T3** | **Make the Moat Visible** | Compounding cross-domain knowledge is the structural advantage. If users cannot see what agents produced (plans, brainstorms, brand guides), the value is invisible. |
| **T4** | **Validate + Scale** | Recruit founders, prove the thesis with real usage, activate payments. Triggered by user count, not calendar. |

### Architecture Decision: PWA-First

The platform ships as a Progressive Web App. One Next.js codebase covers web browsers, mobile (installable PWA), and desktop (installable PWA). Native apps (Electron, React Native) are deferred unless PWA hits real limits reported by users.

Server-side Playwright handles browser automation (third-party signups, service configuration). Screenshots stream into the chat UI. The founder handles CAPTCHA/OAuth steps in their own browser.

---

## Current State (2026-03-23)

| Dimension | Status |
|-----------|--------|
| Phase 1.0 (Working Loop) | Complete. All blocking issues closed (#667, #668, #669, #670, #671). |
| Phase 1.5 (Secure + Polish) | Open (#674). 7 tasks unchecked. |
| Phase 2 (Visibility) | Open (#672). Not started. |
| Phase 3 (Hardening) | Open (#673). Not started. |
| Beta users | 0 |
| Pricing gates passed | 0 of 5 |
| Milestones | 0 |

---

## Phases

### Phase 1: Close the Loop (Mobile-First, PWA)

**Objective:** A new user signs up from any device, stores an API key, talks to a domain leader, and sees agent output without errors. The app is installable as a PWA.

| # | Feature | Priority | Issue | Status |
|---|---------|----------|-------|--------|
| 1.1 | BYOK decryption fix | P1 | [#667](https://github.com/jikig-ai/soleur/issues/667) | Done |
| 1.2 | Integration tests (WebSocket, auth, session) | P1 | [#668](https://github.com/jikig-ai/soleur/issues/668) | Done |
| 1.3 | KB 404 placeholder (graceful empty state) | P2 | [#669](https://github.com/jikig-ai/soleur/issues/669) | Done |
| 1.4 | Vendor DPA review (Supabase, Stripe, Hetzner, Cloudflare) | P1 | [#670](https://github.com/jikig-ai/soleur/issues/670) | Done |
| 1.5 | Mobile-first responsive UI audit | P1 | New | Not started |
| 1.6 | PWA manifest + service worker + installability | P1 | New | Not started |
| 1.7 | Verify production deployment (end-to-end loop) | P1 | -- | Needs verification |

**Exit criteria:**

- New user completes signup, BYOK, first conversation on mobile browser
- PWA installable on iOS, Android, desktop Chrome/Edge
- Lighthouse mobile score > 80

---

### Phase 2: Secure for Beta

**Objective:** Defensible security posture. No external user touches the platform until every P1 item passes.

| # | Feature | Priority | Issue | Status |
|---|---------|----------|-------|--------|
| 2.1 | Security audit (OWASP top 10, BYOK handling, workspace isolation, path traversal) | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.2 | CSP + CORS headers on all routes | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Partially done |
| 2.3 | Session timeout + WebSocket expiry on idle | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.4 | Account deletion + data purge (GDPR) | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.5 | Error + empty states (agent failure, network loss, rate limit) | P2 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.6 | First-time onboarding walkthrough | P2 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.7 | UX audit of all Phase 1 screens | P2 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |

**Exit criteria (beta launch gate):**

| Gate | Pass/Fail | Criteria |
|------|-----------|----------|
| Security audit complete | Must pass | 0 critical or high findings open |
| CSP + CORS deployed | Must pass | Headers present on all routes |
| Session timeout active | Must pass | Idle sessions expire, WebSocket connections close |
| Account deletion works | Must pass | User can delete account and all data (GDPR) |
| Error states visible | Must pass | Agent failure, network loss, empty states render meaningful messages |
| Onboarding walkthrough | Should pass | First-time user completes the loop without external docs |
| Integration tests green | Must pass | Auth, WebSocket, session tests pass in CI |

---

### Phase 3: Make it Sticky

**Objective:** Turn "I tried it" into "I use it daily." The features that close the review loop and make the compounding moat visible.

| # | Feature | Priority | Issue | Status |
|---|---------|----------|-------|--------|
| 3.1 | KB REST API (file tree, content, search) | P1 | [#672](https://github.com/jikig-ai/soleur/issues/672) | Not started |
| 3.2 | KB viewer UI (sidebar tree, markdown rendering, search) | P1 | [#672](https://github.com/jikig-ai/soleur/issues/672) | Stub only |
| 3.3 | Conversation inbox with status badges | P1 | [#672](https://github.com/jikig-ai/soleur/issues/672) | Not started |
| 3.4 | Multi-turn conversation continuity | P1 | New | Partial |
| 3.5 | Server-side Playwright with screenshot streaming | P1 | New | Not started |
| 3.6 | Usage/cost indicator (BYOK spending) | P2 | [#672](https://github.com/jikig-ai/soleur/issues/672) | Not started |
| 3.7 | Push notifications for review gates (PWA) | P2 | New | Not started |
| 3.8 | Pricing page (soleur.ai) | Deferred | [#656](https://github.com/jikig-ai/soleur/issues/656) | Not started |

**Why 3.1-3.2 matter:** The knowledge base is the compounding moat. If founders cannot see plans, brainstorms, brand guides, and competitive analyses their agents produced, the value is invisible. The KB viewer closes the review loop.

**Why 3.3 matters:** A solo founder triggers agents, steps away, returns later. The inbox is the landing page that shows what happened and what needs attention.

**Why 3.5 matters:** Founders need agents to automate third-party service signups (Cloudflare, Plausible, Stripe, Buttondown, etc.). Server-side Playwright drives a headless browser, streams screenshots into chat, and hands off for CAPTCHA/OAuth only.

**Exit criteria:**

- User can browse KB artifacts produced by agents
- User can see conversation history with status badges (active, waiting, completed, failed)
- User can resume multi-turn conversations
- Agent can drive third-party signups with screenshot streaming
- PWA push notifications fire on review gates (when user is offline)

---

### Phase 4: Validate + Scale

**Objective:** Recruit founders, prove the CaaS thesis with real usage, activate payments. Triggered by readiness, not calendar.

| # | Feature | Priority | Trigger | Status |
|---|---------|----------|---------|--------|
| 4.1 | Recruit 10 solo founders (mixed channels) | P1 | Phase 2 complete | Not started |
| 4.2 | Problem interviews (no demo) | P1 | 10 founders recruited | Not started |
| 4.3 | Guided onboarding with top 5 | P1 | 5+ pass problem interviews | Not started |
| 4.4 | 2-week unassisted usage tracking | P1 | Onboarding complete | Not started |
| 4.5 | Exit interviews + willingness-to-pay | P1 | 2 weeks elapsed | Not started |
| 4.6 | Container-per-workspace isolation | P1 | 5+ concurrent users | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.7 | Rate limiting (per-user concurrency, API rate) | P1 | Before public launch | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.8 | Monitoring + error tracking | P2 | 10+ users | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.9 | Stripe live mode activation | P1 | 4 of 5 pricing gates pass | Not started |

**Recruitment channels:** Claude Code Discord, GitHub (developers with business-operations repos), IndieHackers, direct network.

**Validation protocol:**

1. Problem interview first (no demo). Does the founder independently describe multi-domain pain?
2. Guided onboarding with top 5. Observe which domain leader they choose first.
3. 2-week unassisted usage. Track: returns, KB growth, non-engineering agent usage.
4. Exit interview. What worked? What's missing? Would they pay $49/month?

**What we learn:**

- If every user only uses the engineering domain, the CaaS thesis is wrong.
- If users engage multiple domains but ignore the KB, the compounding thesis is wrong.
- If users engage multiple domains AND return to the KB, the thesis holds.

**Exit criteria:**

- 10 founders recruited, 5+ use 2+ domains for 2+ weeks
- 3+ express willingness to pay $49/month
- Container isolation handles 5+ concurrent users
- Rate limiting prevents abuse

---

## Pricing

**Hypothesis:** $49/month + BYOK. Stripe in test mode until 4 of 5 pricing gates pass.

| Gate | Criteria | Status |
|------|----------|--------|
| Demand validation | 10+ solo founders used the platform for 2+ weeks | Not started |
| Multi-domain validation | 5+ users engaged with 2+ non-engineering domains | Not started |
| Willingness-to-pay signal | 3+ founders say they would pay $49/month | Not started |
| Infrastructure cost model | Hosting costs per-user understood, margin positive | Not assessed |
| Cowork differentiation clear | Users articulate why Soleur is worth paying for vs. free Cowork plugins | Not started |

Full analysis: `knowledge-base/product/pricing-strategy.md`.

---

## Dependencies

| This roadmap depends on | Path | Why |
|------------------------|------|-----|
| Business validation | `knowledge-base/product/business-validation.md` | PIVOT verdict, demand evidence, customer definition |
| Competitive intelligence | `knowledge-base/product/competitive-intelligence.md` | Tier 0 threats, pricing anchors, differentiation |
| Pricing strategy | `knowledge-base/product/pricing-strategy.md` | Pricing gates, tier structure, competitive pricing |

---

## Review Cadence

Monthly CPO review. Pre-product-market-fit: the landscape changes faster than a quarter allows.

- **Monthly:** Review phase progress. Update statuses. Re-assess priorities based on user signal.
- **After each beta cohort:** Update validation findings. Adjust Phase 3 scope.
- **Quarterly:** Full roadmap revision. Cross-reference with competitive intelligence and marketing strategy.

Next review: 2026-04-23.

---

_Generated: 2026-03-23. Sources: business-validation.md (2026-03-12), competitive-intelligence.md (2026-03-12), pricing-strategy.md (2026-03-12), brand-guide.md (2026-02-21). Workshop conducted via /soleur:product-roadmap skill._
