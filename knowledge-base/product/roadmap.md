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

**Known iOS limitations (CTO review):** Push notifications require iOS 16.4+ and home-screen installation. No background execution — WebSocket drops when app is backgrounded. Service worker caches evicted after ~14 days of non-use. Email fallback needed for review gate notifications.

### Architecture Decision: 3-Tier Service Automation (Brainstorm 2026-03-23)

Founders validated service automation as a high-value feature. Server-side Playwright was rejected (HIGH risk from CTO, CLO, CFO). Brainstorm produced a 3-tier architecture:

| Tier | Platform | Coverage | How |
|------|----------|----------|-----|
| **API + MCP** | All (web, mobile, desktop) | ~80% of services | Direct API calls and MCP server integrations. User provides API tokens, stored with BYOK-grade encryption. Deterministic, versioned, no browser needed. |
| **Local Playwright** | Desktop native app only | ~15% (no API/MCP available) | Electron/Tauri desktop app runs Playwright on user's machine. Same pattern as CLI plugin. User's own browser, credentials, and session. |
| **Guided instructions** | Web + mobile (fallback) | ~5% remainder | Agent provides step-by-step with deep links and review gates. |

MCP is a first-class integration tier alongside REST APIs. Services that publish MCP servers (and this list is growing rapidly) get zero-config integration — the agent connects to the service's MCP server directly, no custom API wrapper needed.

The desktop native app earns its existence specifically because browser automation is impossible on PWA, iOS, or Android. This is not "wrapping the web app" — it provides a capability no other surface can.

Full brainstorm: `knowledge-base/project/brainstorms/2026-03-23-browser-automation-cloud-platform-brainstorm.md`

---

## Domain Review Summary (2026-03-23)

This roadmap was reviewed by CTO, CLO, CFO, and CMO before finalization.

| Domain | Key Finding | Impact on Roadmap |
|--------|------------|-------------------|
| **CTO** | Multi-turn conversation is broken (agent has amnesia between turns). Not "partial" — functionally absent. | Promoted multi-turn to P1. Reordered P3. |
| **CTO** | Pin Agent SDK to exact version (`0.2.80`, not `^0.2.80`). Add basic WS rate limiting to P2. | Added to P1 and P2 respectively. |
| **CLO** | Conversation history is a new PII category not in privacy docs. AUP and Cookie Policy not updated for Web Platform. | Added legal updates to P2. |
| **CLO** | Browser automation creates undisclosed agency liability. Needs dedicated legal framework before shipping. | Playwright deferred pending brainstorm + legal architecture. |
| **CFO** | Break-even at 1-2 paying users. EUR 35-44/month burn. BYOK eliminates per-user LLM cost. | No structural change. Confirmed pricing gate sequencing is correct. |
| **CFO** | No finance artifacts exist. Need cost model. Plausible trial expires 2026-03-24. | Flagged for immediate action. |
| **CMO** | Every public surface says "plugin." Roadmap says "cloud platform." Live contradiction. | Added marketing positioning gate before P4 recruitment. |
| **CMO** | At least 3/10 recruited founders must NOT be Claude Code users. | Added recruitment mix constraint to P4. |

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

**Objective:** A new user signs up from any device, has a real multi-turn conversation with a domain leader, and sees agent output without errors. The app is installable as a PWA.

| # | Feature | Priority | Issue | Status |
|---|---------|----------|-------|--------|
| 1.1 | BYOK decryption fix | P1 | [#667](https://github.com/jikig-ai/soleur/issues/667) | Done |
| 1.2 | Integration tests (WebSocket, auth, session) | P1 | [#668](https://github.com/jikig-ai/soleur/issues/668) | Done |
| 1.3 | KB 404 placeholder (graceful empty state) | P2 | [#669](https://github.com/jikig-ai/soleur/issues/669) | Done |
| 1.4 | Vendor DPA review (Supabase, Stripe, Hetzner, Cloudflare) | P1 | [#670](https://github.com/jikig-ai/soleur/issues/670) | Done |
| 1.5 | Mobile-first responsive UI (sidebar → hamburger menu, touch-optimized nav) | P1 | New | Not started |
| 1.6 | PWA manifest + service worker + installability (app shell caching only, no offline mode) | P1 | New | Not started |
| 1.7 | Verify production deployment (end-to-end loop) | P1 | -- | Needs verification |
| 1.8 | **Multi-turn conversation continuity** (session persistence, message history injection) | P1 | New | **Broken** — agent has amnesia between turns (CTO review) |
| 1.9 | Pin Agent SDK to exact version (`0.2.80`) | P1 | New | Not started |

**Why 1.8 is P1 (CTO review):** "A chat product where the agent forgets everything after one turn is not viable even for beta. It will be the first thing every user notices." Each message currently spawns a fresh agent with no memory of prior exchange. `persistSession: false` is explicitly set. This is the most critical gap.

**Exit criteria:**

- New user completes signup, BYOK, multi-turn conversation on mobile browser
- Agent remembers context across turns within a conversation
- PWA installable on iOS, Android, desktop Chrome/Edge
- Lighthouse mobile score > 80

---

### Phase 2: Secure for Beta

**Objective:** Defensible security, legal, and UX posture. No external user touches the platform until every must-pass gate clears.

| # | Feature | Priority | Source | Status |
|---|---------|----------|--------|--------|
| 2.1 | Security audit (OWASP top 10, BYOK handling, workspace isolation, path traversal) | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.2 | CSP + CORS headers on all routes | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Partially done |
| 2.3 | Session timeout + WebSocket expiry on idle | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.4 | Account deletion + data purge (GDPR) | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.5 | Basic WebSocket rate limiting (per-IP connection throttle) | P1 | CTO review | Not started |
| 2.6 | Add `/proc` to sandbox deny list | P1 | CTO review | Not started |
| 2.7 | Update AUP for Web Platform scope | P1 | CLO review | Not started |
| 2.8 | Update Cookie Policy for app.soleur.ai | P1 | CLO review | Not started |
| 2.9 | Add conversation history to Privacy Policy, DPD, GDPR register | P1 | CLO review | Not started |
| 2.10 | Error + empty states (agent failure, network loss, rate limit) | P2 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.11 | First-time onboarding walkthrough (include PWA install guidance for iOS) | P2 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |
| 2.12 | UX audit of all Phase 1 screens | P2 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Not started |

**Exit criteria (beta launch gate):**

| Gate | Pass/Fail | Criteria |
|------|-----------|----------|
| Security audit complete | Must pass | 0 critical or high findings open |
| CSP + CORS deployed | Must pass | Headers present on all routes |
| Session timeout active | Must pass | Idle sessions expire, WebSocket connections close |
| Account deletion works | Must pass | User can delete account and all data (GDPR) |
| WS rate limiting active | Must pass | IP-based throttle prevents auth exhaustion |
| Legal docs updated | Must pass | AUP, Cookie Policy, and privacy docs cover Web Platform + conversation data |
| Error states visible | Must pass | Agent failure, network loss, empty states render meaningful messages |
| Onboarding walkthrough | Should pass | First-time user completes the loop without external docs |
| Integration tests green | Must pass | Auth, WebSocket, session tests pass in CI |

---

### Phase 3: Make it Sticky

**Objective:** Turn "I tried it" into "I use it daily." Close the review loop and make the compounding moat visible.

**Sequencing (per CTO review):** KB API and viewer before inbox.

| # | Feature | Priority | Issue | Status |
|---|---------|----------|-------|--------|
| 3.1 | KB REST API (file tree, content, search) | P1 | [#672](https://github.com/jikig-ai/soleur/issues/672) | Not started |
| 3.2 | KB viewer UI (sidebar tree, markdown rendering, search) | P1 | [#672](https://github.com/jikig-ai/soleur/issues/672) | Stub only |
| 3.3 | Conversation inbox with status badges | P1 | [#672](https://github.com/jikig-ai/soleur/issues/672) | Not started |
| 3.4 | API + MCP service integrations (Cloudflare, Stripe, Plausible first) | P1 | [#1050](https://github.com/jikig-ai/soleur/issues/1050) | Not started |
| 3.5 | Secure token storage for third-party APIs (BYOK-grade encryption) | P1 | New | Not started |
| 3.6 | Usage/cost indicator (BYOK spending) | P2 | [#672](https://github.com/jikig-ai/soleur/issues/672) | Not started |
| 3.7 | Review gate notifications (PWA push + email fallback for iOS) | P2 | [#1049](https://github.com/jikig-ai/soleur/issues/1049) | Not started |
| 3.8 | Guided instructions fallback (deep links + review gates for services without API/MCP) | P2 | New | Not started |
| 3.9 | Pricing page (soleur.ai) | Deferred | [#656](https://github.com/jikig-ai/soleur/issues/656) | Not started |

**Why 3.1-3.2 matter:** The knowledge base is the compounding moat. If founders cannot see plans, brainstorms, brand guides, and competitive analyses their agents produced, the value is invisible. The KB viewer closes the review loop.

**Why 3.3 matters:** A solo founder triggers agents, steps away, returns later. The inbox is the landing page that shows what happened and what needs attention.

**Why 3.4-3.5 matter:** Founders validated service automation as a high-value feature. The 3-tier architecture (API + MCP everywhere, local Playwright on desktop, guided fallback) delivers both guidance and automation. API + MCP integrations cover ~80% of services with zero browser overhead. MCP is a first-class integration tier — services publishing MCP servers get zero-config integration.

**Exit criteria:**

- User can browse KB artifacts produced by agents
- User can see conversation history with status badges (active, waiting, completed, failed)
- Agent can provision Cloudflare zones, Stripe accounts, and Plausible sites via API/MCP
- Review gate notifications reach the user even when offline (push or email)

---

### Pre-Phase 4: Marketing Positioning Gate (CMO review)

Before recruiting founders, all public surfaces must reflect the cloud platform positioning. ~5 hours of work.

| # | Item | Effort | Status |
|---|------|--------|--------|
| M1 | Update brand guide positioning (remove plugin framing, cloud platform as primary) | 30 min | Not started |
| M2 | Update homepage hero subtitle + meta description | 30 min | Not started |
| M3 | Update marketing strategy for cloud pivot | 2 hours | Not started |
| M4 | Draft recruitment messaging templates per channel | 2 hours | Not started |
| M5 | Update Getting Started page (cloud platform primary, CLI plugin secondary) | 2 hours | Not started |
| M6 | Standardize agent/skill counts across all surfaces | 2 hours | Not started |

**Gate:** No recruitment outreach until M1-M4 complete.

---

### Phase 4: Validate + Scale

**Objective:** Recruit founders, prove the CaaS thesis with real usage, activate payments. Triggered by readiness, not calendar.

| # | Feature | Priority | Trigger | Status |
|---|---------|----------|---------|--------|
| 4.1 | Recruit 10 solo founders (mixed channels) | P1 | Phase 2 + Marketing Gate complete | Not started |
| 4.2 | Problem interviews (no demo) | P1 | 10 founders recruited | Not started |
| 4.3 | Guided onboarding with top 5 | P1 | 5+ pass problem interviews | Not started |
| 4.4 | 2-week unassisted usage tracking | P1 | Onboarding complete | Not started |
| 4.5 | Exit interviews + willingness-to-pay | P1 | 2 weeks elapsed | Not started |
| 4.6 | Container-per-workspace isolation | P1 | 5+ concurrent users | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.7 | Rate limiting (per-user concurrency, API rate) | P1 | Before public launch | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.8 | Resource monitoring (CPU/RAM per workspace) | P1 | Before beta invites | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.9 | Monitoring + error tracking | P2 | 10+ users | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.10 | Stripe live mode activation | P1 | 4 of 5 pricing gates pass | Not started |

**Recruitment channels:** Claude Code Discord, GitHub (developers with business-operations repos), IndieHackers, X/Twitter solopreneur network, direct network.

**Recruitment mix constraint (CMO review):** At least 3 of 10 founders must NOT be current Claude Code users. If all recruits come from the Claude Code ecosystem, you validate the plugin-to-cloud migration path, not the cloud platform value proposition from cold.

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

### Phase 5: Desktop Native App (Browser Automation)

**Objective:** Ship a desktop app (Electron or Tauri) that provides local Playwright browser automation — the one capability PWA cannot deliver. Triggered by user demand, not calendar.

| # | Feature | Priority | Trigger | Status |
|---|---------|----------|---------|--------|
| 5.1 | Electron/Tauri app wrapping the web platform | P1 | Beta users request browser automation | Not started |
| 5.2 | Local Playwright integration for third-party service setup | P1 | Desktop app shipped | Not started |
| 5.3 | Reuse ops-provisioner guided setup pattern (3-phase: Setup, Configure, Verify) | P1 | Playwright integrated | Not started |
| 5.4 | Auto-update mechanism | P2 | Desktop app shipped | Not started |
| 5.5 | Code signing (macOS + Windows) | P1 | Before distribution | Not started |

**Why this phase exists:** Browser automation is impossible on PWA, iOS, and Android due to platform sandboxing. Only a native desktop app can run Playwright locally on the user's machine. This is the desktop app's reason to exist — not wrapping the web app, but providing a capability no other surface can.

**Electron vs. Tauri:** Decision deferred to planning. Electron is heavier (~200MB) but mature ecosystem. Tauri is lighter (~10MB) but uses system webview.

**Exit criteria:**

- Desktop app installable on macOS + Windows
- Agent can automate Cloudflare/Stripe/Plausible signup via local Playwright
- Pause at CAPTCHA/OAuth, user handles in their own browser
- Auto-updates work

---

## Pricing

**Hypothesis:** $49/month + BYOK. Stripe in test mode until 4 of 5 pricing gates pass.

| Gate | Criteria | Status |
|------|----------|--------|
| Demand validation | 10+ solo founders used the platform for 2+ weeks | Not started |
| Multi-domain validation | 5+ users engaged with 2+ non-engineering domains | Not started |
| Willingness-to-pay signal | 3+ founders say they would pay $49/month | Not started |
| Infrastructure cost model | Hosting costs per-user understood, margin positive | CFO assessed: EUR 35-44/month burn, break-even at 1-2 users |
| Cowork differentiation clear | Users articulate why Soleur is worth paying for vs. free Cowork plugins | Not started |

Full analysis: `knowledge-base/product/pricing-strategy.md`.

---

## Immediate Actions

| Action | Owner | Deadline | Notes |
|--------|-------|----------|-------|
| Decide Plausible Analytics (keep at EUR 9/month or switch to Cloudflare Web Analytics) | COO | 2026-03-24 | Trial expires tomorrow |
| Create `knowledge-base/finance/cost-model.md` | CFO/budget-analyst | Before P4 | No finance artifacts exist. Pricing Gate #4 partially addressed by CFO review. |

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

_Generated: 2026-03-23. Domain review: CTO, CLO, CFO, CMO (2026-03-23). Sources: business-validation.md (2026-03-12), competitive-intelligence.md (2026-03-12), pricing-strategy.md (2026-03-12), brand-guide.md (2026-02-21). Workshop conducted via /soleur:product-roadmap skill._
