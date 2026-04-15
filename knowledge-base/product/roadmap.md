---
last_updated: 2026-04-14
last_reviewed: 2026-04-14
review_cadence: weekly
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

## Current State (2026-04-13)

| Dimension | Status |
|-----------|--------|
| Phase 1 (Close the Loop) | Complete. Milestone closed. 0 open, 15 closed. |
| Phase 2 (Secure for Beta) | Complete. Milestone closed. 0 open, 20 closed. |
| Phase 3 (Make it Sticky) | In progress. 8 open, 23 closed (milestone). Core KB, inbox, token storage, onboarding, CI/CD, service automation, analytics, sharing, usage indicator, pricing page, start fresh onboarding, post-connect sync, chat attachments, review gate notifications, guided instructions fallback, subscription management, KB file upload, invoice history, migration 021 follow-through all done. Agent work visualization (#2004) moved to Phase 4. KB chat sidebar (#2345) promoted from Post-MVP to Phase 3 P3 on 2026-04-15 (plan + wireframes written, implementation pending). Remaining: service automation announcement (#1944), QA gate (#2108), KB rename files (#2152), KB PDF preview (#2153), KB delete button layout (#2154), team settings improvements (#2155), custom @mention handles (#2170), KB chat sidebar (#2345). |
| Phase 4 (Validate + Scale) | Not started. 24 open, 11 closed. Blocked by Phase 3 completion + marketing/multi-user gates. Growth audit 2026-04-13 added 7 issues (6 marketing gate P0s + 1 outreach campaign). Agent work visualization (#2004) moved here from Phase 3. |
| Phase 5 (Desktop Native App) | Defined. 5 open, 0 closed. Trigger-gated on user demand. |
| Post-MVP / Later | 92 open, 343 closed. |
| Beta users | 0 |
| Pricing gates passed | 0 of 5 |

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
| 1.5 | Mobile-first responsive UI (sidebar → hamburger menu, touch-optimized nav) | P1 | [#1041](https://github.com/jikig-ai/soleur/issues/1041) | Done |
| 1.6 | PWA manifest + service worker + installability (app shell caching only, no offline mode) | P1 | [#1042](https://github.com/jikig-ai/soleur/issues/1042) | Done |
| 1.7 | Verify production deployment (end-to-end loop) | P1 | [#1075](https://github.com/jikig-ai/soleur/issues/1075) | Done |
| 1.8 | **Multi-turn conversation continuity** (architecture choice deferred to CTO during spec) | P1 | [#1044](https://github.com/jikig-ai/soleur/issues/1044) | Done |
| 1.9 | Pin Agent SDK to exact version (`0.2.80`) | P1 | [#1045](https://github.com/jikig-ai/soleur/issues/1045) | Done |
| 1.10 | **Project repo connection** — clone founder's GitHub repo (public or private via GitHub App), install latest Soleur plugin, keep plugin updated | P1 | [#1060](https://github.com/jikig-ai/soleur/issues/1060) | Done |
| 1.11 | **Tag-and-route conversation model** — one chat input, system routes to relevant leaders, no dedicated domain leader pages | P1 | [#1059](https://github.com/jikig-ai/soleur/issues/1059) | Done |

**Why 1.8 is P1 (CTO review):** "A chat product where the agent forgets everything after one turn is not viable even for beta. It will be the first thing every user notices." Each message currently spawns a fresh agent with no memory of prior exchange. `persistSession: false` is explicitly set. **Dependency note:** The multi-turn architecture choice (CTO decision during spec) has downstream implications for 2.4 (GDPR account deletion — what conversation data must be purged?), 2.9 (privacy docs — what is stored?), and 3.3 (conversation inbox — what is displayed?).

**Why 1.10 is P1:** Without the founder's actual project repo and the Soleur plugin installed, agents operate in a vacuum — no codebase context, no skills, no domain leaders, no institutional memory. The workspace must be the founder's real project, not an empty shell. Supports both public and private repos via GitHub App installation tokens — no deploy keys or long-lived credentials needed.

**Why 1.11 is P1:** The current domain leader selector page consumes significant UI real estate and will be torn down for tag-and-route in P3 — building throwaway pages is wasted effort. The tag-and-route model is simpler for P1: one chat input with system routing (same pattern as the brainstorm skill's domain assessment) instead of 8 dedicated domain leader pages. Build the right UX once rather than building and tearing down the wrong one.

**Deferred from P1:**

- ~~1.12 Telegram bridge~~ → Removed in April 2026 — will redesign as channel connector using unified backend.
- ~~Private repo support for 1.10~~ → Included in P1. GitHub App tokens provide identical security for both public and private repos.

**UX Vision: L2 → L4**

- **L2 (MVP):** KB viewer renders `roadmap.md` with progress indicators. Founder reads their own roadmap.
- **L4 (North Star):** Interactive command center — visual roadmap, department activity, drag-to-reprioritize, inline conversations on any artifact. The founder's operating system.

**Exit criteria:**

- New user completes signup, BYOK, multi-turn conversation on mobile browser
- Agent runs against the founder's actual project repo with Soleur plugin installed
- Agent remembers context across turns within a conversation
- Conversations route to relevant domain leaders automatically (no dedicated department pages)
- PWA installable on iOS, Android, desktop Chrome/Edge
- Lighthouse mobile score > 80

---

### Phase 2: Secure for Beta

**Objective:** Defensible security, legal, and UX posture. No external user touches the platform until every must-pass gate clears.

| # | Feature | Priority | Source | Status |
|---|---------|----------|--------|--------|
| 2.1 | Security audit (OWASP top 10, BYOK handling, workspace isolation, path traversal) | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Done |
| 2.2 | CSP + CORS headers on all routes | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Done |
| 2.3 | Session timeout + WebSocket expiry on idle | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Done |
| 2.4 | Account deletion + data purge (GDPR) | P1 | [#674](https://github.com/jikig-ai/soleur/issues/674), [#1376](https://github.com/jikig-ai/soleur/issues/1376) | Done |
| 2.5 | Basic WebSocket rate limiting (per-IP connection throttle) | P1 | [#1046](https://github.com/jikig-ai/soleur/issues/1046) | Done |
| 2.6 | Add `/proc` to sandbox deny list | P1 | [#1047](https://github.com/jikig-ai/soleur/issues/1047) | Done |
| 2.7 | Update AUP for Web Platform scope | P1 | [#1048](https://github.com/jikig-ai/soleur/issues/1048) | Done |
| 2.8 | Update Cookie Policy for app.soleur.ai | P1 | [#1048](https://github.com/jikig-ai/soleur/issues/1048) | Done |
| 2.9 | Add conversation history to Privacy Policy, DPD, GDPR register | P1 | [#1048](https://github.com/jikig-ai/soleur/issues/1048) | Done |
| 2.10 | Error + empty states (agent failure, network loss, rate limit) | P2 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Done |
| 2.11 | First-time onboarding walkthrough (include PWA install guidance for iOS) | P2 | [#1375](https://github.com/jikig-ai/soleur/issues/1375) | Done |
| 2.12 | UX audit of all Phase 1 screens | P2 | [#674](https://github.com/jikig-ai/soleur/issues/674) | Done |
| 2.13 | Supply chain dependency hardening (lockfile integrity, pinning, scanning) | P1 | [#1174](https://github.com/jikig-ai/soleur/issues/1174) | Done |
| 2.14 | OAuth sign-in (Google, Apple, GitHub, Microsoft) via Supabase redirect flow | P2 | [#1210](https://github.com/jikig-ai/soleur/issues/1210) | Done |

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
| Supply chain hardened | Must pass | Exact version pinning, lockfile integrity in CI, dependency review on all PRs |
| OAuth sign-in functional | Should pass | Google, Apple, GitHub, Microsoft OAuth buttons work on login/signup; legal docs updated |

---

### Phase 3: Make it Sticky

**Objective:** Turn "I tried it" into "I use it daily." Close the review loop and make the compounding moat visible.

**Sequencing (per CTO review):** KB API and viewer before inbox.

| # | Feature | Priority | Issue | Status |
|---|---------|----------|-------|--------|
| 3.1 | KB REST API (file tree, content, search) | P1 | [#1688](https://github.com/jikig-ai/soleur/issues/1688) | Done |
| 3.2 | KB viewer UI (sidebar tree, markdown rendering, search) | P1 | [#1689](https://github.com/jikig-ai/soleur/issues/1689) | Done |
| 3.3 | Conversation inbox with status badges | P1 | [#1690](https://github.com/jikig-ai/soleur/issues/1690) | Done |
| 3.4 | API + MCP service integrations (Cloudflare, Stripe, Plausible first) | P1 | [#1050](https://github.com/jikig-ai/soleur/issues/1050) | Done |
| 3.5 | Secure token storage for third-party APIs (BYOK-grade encryption) | P1 | [#1076](https://github.com/jikig-ai/soleur/issues/1076) | Done |
| 3.6 | Usage/cost indicator (BYOK spending) | P2 | [#1691](https://github.com/jikig-ai/soleur/issues/1691) | Done |
| 3.7 | Review gate notifications (PWA push + email fallback for iOS) | P2 | [#1049](https://github.com/jikig-ai/soleur/issues/1049) | Done |
| 3.8 | Guided instructions fallback (deep links + review gates for services without API/MCP) | P2 | [#1077](https://github.com/jikig-ai/soleur/issues/1077) | Done |
| 3.9 | Chat UX redesign — remove department grid, @-mention autocomplete, auto-routing, sidebar | P2 | [#1289](https://github.com/jikig-ai/soleur/issues/1289) | Done (completed in P2) |
| 3.10 | CI/CD integration (parent — decomposed into 3.10a-d) | P1 | [#1062](https://github.com/jikig-ai/soleur/issues/1062) | Done |
| 3.10a | GitHub App + server-side proxy infrastructure | P1 | [#1926](https://github.com/jikig-ai/soleur/issues/1926) | Done |
| 3.10b | Read CI status and logs via proxy | P1 | [#1927](https://github.com/jikig-ai/soleur/issues/1927) | Done |
| 3.10c | Trigger GitHub Actions workflows via proxy | P1 | [#1928](https://github.com/jikig-ai/soleur/issues/1928) | Done |
| 3.10d | Open PRs via proxy (push to feature branches) | P1 | [#1929](https://github.com/jikig-ai/soleur/issues/1929) | Done |
| 3.11 | Product analytics instrumentation for P4 validation metrics (domain engagement, session frequency, KB growth) | P1 | [#1063](https://github.com/jikig-ai/soleur/issues/1063) | Done |
| 3.12 | Pricing page (soleur.ai) | P1 | [#656](https://github.com/jikig-ai/soleur/issues/656) | Done |
| 3.13 | Subscription management (cancel, upgrade/downgrade) | P1 | [#1078](https://github.com/jikig-ai/soleur/issues/1078) | Done |
| 3.14 | Invoice history + failed payment handling | P2 | [#1079](https://github.com/jikig-ai/soleur/issues/1079) | Done |
| 3.15 | Fix meta tags not rendering in production HTML (OG, canonical, Twitter cards) | P0 | [#1121](https://github.com/jikig-ai/soleur/issues/1121) | Done |
| 3.16 | Start Fresh onboarding — guided first-run with foundation cards (vision, brand, validation, legal) | P1 | [#1751](https://github.com/jikig-ai/soleur/issues/1751) | Done |
| 3.17 | Post-connect sync proposal and project status report | P1 | [#1772](https://github.com/jikig-ai/soleur/issues/1772) | Done |
| 3.18 | KB items, KB, and session sharing (read-only external access with signup CTAs, revocable) | P2 | [#1745](https://github.com/jikig-ai/soleur/issues/1745) | Done |
| 3.19 | Chat attachments (images + PDFs via Supabase Storage, presigned URL upload, AI processing via filesystem write) | P2 | [#1961](https://github.com/jikig-ai/soleur/issues/1961) | Done |
| 3.20 | KB file upload (images, PDFs, CSV, TXT, DOCX via GitHub Contents API, per-directory upload button, binary file preview) | P3 | [#1974](https://github.com/jikig-ai/soleur/issues/1974) | Done |
| 3.21 | Agent work visualization in UX (show agent activity, progress, and outputs) | P2 | [#2004](https://github.com/jikig-ai/soleur/issues/2004) | Moved to Phase 4 |
| 3.22 | Service automation feature announcement (marketing content for launch) | P3 | [#1944](https://github.com/jikig-ai/soleur/issues/1944) | Not started |
| 3.23 | KB chat sidebar (in-doc chat panel + selection-as-context, replaces "Chat about this" new-window) | P3 | [#2345](https://github.com/jikig-ai/soleur/issues/2345) | In progress (plan + wireframes done 2026-04-15) |

**Why 3.1-3.2 matter:** The knowledge base is the compounding moat. If founders cannot see plans, brainstorms, brand guides, and competitive analyses their agents produced, the value is invisible. The KB viewer closes the review loop.

**Why 3.3 matters:** A solo founder triggers agents, steps away, returns later. The inbox is the landing page that shows what happened and what needs attention.

**Why 3.4-3.5 matter:** Founders validated service automation as a high-value feature. The 3-tier architecture (API + MCP everywhere, local Playwright on desktop, guided fallback) delivers both guidance and automation. API + MCP integrations cover ~80% of services with zero browser overhead. MCP is a first-class integration tier — services publishing MCP servers get zero-config integration.

**Exit criteria:**

- User can browse KB artifacts produced by agents
- User can see conversation history with status badges (active, waiting, completed, failed)
- Agent can provision Cloudflare zones, Stripe accounts, and Plausible sites via API/MCP
- Review gate notifications reach the user even when offline (push or email)
- Pricing page live, subscription management works (cancel, upgrade), failed payment handling in place
- Product analytics tracking domain engagement, session frequency, and KB growth per user

---

### Pre-Phase 4: Marketing Positioning Gate (CMO review)

Before recruiting founders, all public surfaces must reflect the cloud platform positioning. ~5 hours of work.

| # | Item | Effort | Status |
|---|------|--------|--------|
| M1 | Update brand guide positioning (remove plugin framing, cloud platform as primary) | 30 min | Done — [#1004](https://github.com/jikig-ai/soleur/issues/1004) |
| M2 | Update homepage hero subtitle + meta description (remove "plugin" from meta descriptions) | 30 min | Done — [#1129](https://github.com/jikig-ai/soleur/issues/1129) |
| M3 | Update marketing strategy for cloud pivot | 2 hours | Not started — [#1051](https://github.com/jikig-ai/soleur/issues/1051) |
| M4 | Draft recruitment messaging templates per channel | 2 hours | Not started — [#1445](https://github.com/jikig-ai/soleur/issues/1445) |
| M5 | Update Getting Started page (cloud platform primary, CLI plugin secondary) | 2 hours | Not started — [#1446](https://github.com/jikig-ai/soleur/issues/1446) |
| M6 | Standardize agent/skill counts across all surfaces | 2 hours | Done — [#1447](https://github.com/jikig-ai/soleur/issues/1447) |
| M7 | Exclude feed.xml from sitemap.xml | 15 min | Done — [#1122](https://github.com/jikig-ai/soleur/issues/1122) |
| M8 | Add case studies to Atom feed entries | 30 min | Done — [#1123](https://github.com/jikig-ai/soleur/issues/1123) |
| M9 | Fix author URL to point to About page (blocked by About page creation) | 30 min | Done — [#1124](https://github.com/jikig-ai/soleur/issues/1124) |
| M10 | Add external source citations to homepage (AEO/GEO citability — zero citations currently) | 1 hour | Done — [#1130](https://github.com/jikig-ai/soleur/issues/1130) |
| M11 | Surface "open source" differentiator on homepage and key pages (absent from headings/meta) | 1 hour | Done — [#1134](https://github.com/jikig-ai/soleur/issues/1134) |
| M12 | Homepage title tag contains zero target keywords (change to include "Company-as-a-Service") | 30 min | Not started — [#2064](https://github.com/jikig-ai/soleur/issues/2064) |
| M13 | Homepage H1 targets no search query (add keyword-bearing heading) | 30 min | Not started — [#2066](https://github.com/jikig-ai/soleur/issues/2066) |
| M14 | No canonical product definition for AI extraction (add extractable answer paragraph) | 1 hour | Not started — [#2067](https://github.com/jikig-ai/soleur/issues/2067) |
| M15 | No author bylines on blog posts (add name, role, About link via template) | 30 min | Not started — [#2068](https://github.com/jikig-ai/soleur/issues/2068) |
| M16 | About page lacks founder credentials and bio (add background, timeline, metrics) | 1 hour | Not started — [#2069](https://github.com/jikig-ai/soleur/issues/2069) |
| M17 | Core pages have 0.7 citations/page vs blog 3.1 (add 2+ external citations per core page) | 2 hours | Not started — [#2070](https://github.com/jikig-ai/soleur/issues/2070) |

**Gate:** No recruitment outreach until M1-M4 and M12-M17 complete.

---

### Pre-Phase 4: Multi-User Readiness Gate (CPO review)

Before recruiting founders, the platform must handle multiple users signing up and getting their own workspaces.

| # | Item | Status |
|---|------|--------|
| MU1 | Signup provisions a workspace (git clone + plugin install per user) | [#1448](https://github.com/jikig-ai/soleur/issues/1448) Depends on P1 item 1.10 — verify |
| MU2 | BYOK encryption works per-tenant (each user's API key isolated) | [#1449](https://github.com/jikig-ai/soleur/issues/1449) Existing — verify |
| MU3 | Workspace isolation at process level (container isolation is P4 hardening, but basic isolation must work) | [#1450](https://github.com/jikig-ai/soleur/issues/1450) Existing bubblewrap sandbox — verify with cross-workspace integration test |

**Gate:** All three must pass before any recruitment outreach.

---

### Phase 4: Validate + Scale

**Objective:** Recruit founders, prove the CaaS thesis with real usage, activate payments. Triggered by readiness, not calendar.

| # | Feature | Priority | Trigger | Status |
|---|---------|----------|---------|--------|
| 4.1 | Recruit 10 solo founders (mixed channels) | P1 | Phase 2 + Marketing Gate + Multi-User Gate complete | [#1439](https://github.com/jikig-ai/soleur/issues/1439) Not started |
| 4.1a | Listicle outreach campaign (zero presence on high-traffic AI tool lists) | P1 | Marketing Gate complete | [#2073](https://github.com/jikig-ai/soleur/issues/2073) Not started |
| 4.2 | Problem interviews (no demo) | P1 | 10 founders recruited | [#1440](https://github.com/jikig-ai/soleur/issues/1440) Not started |
| 4.3 | Guided onboarding with top 5 | P1 | 5+ pass problem interviews | [#1441](https://github.com/jikig-ai/soleur/issues/1441) Not started |
| 4.4 | 2-week unassisted usage tracking | P1 | Onboarding complete | [#1442](https://github.com/jikig-ai/soleur/issues/1442) Not started |
| 4.5 | Exit interviews + willingness-to-pay | P1 | 2 weeks elapsed | [#1443](https://github.com/jikig-ai/soleur/issues/1443) Not started |
| 4.6 | Container-per-workspace isolation | P1 | 5+ concurrent users | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.7 | Plan-based agent concurrency enforcement (slot limits per subscription tier) | P1 | Before public launch | [#1162](https://github.com/jikig-ai/soleur/issues/1162), [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.8 | Resource monitoring (CPU/RAM per workspace) | P1 | Before beta invites | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.9 | Monitoring + error tracking | P2 | 10+ users | [#673](https://github.com/jikig-ai/soleur/issues/673) |
| 4.10 | Stripe live mode activation | P1 | 4 of 5 pricing gates pass | [#1444](https://github.com/jikig-ai/soleur/issues/1444) Not started |

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

| # | Feature | Priority | Issue | Trigger | Status |
|---|---------|----------|-------|---------|--------|
| 5.1 | Electron/Tauri app wrapping the web platform | P1 | [#1423](https://github.com/jikig-ai/soleur/issues/1423) | Beta users request browser automation | Not started |
| 5.2 | Local Playwright integration for third-party service setup | P1 | [#1425](https://github.com/jikig-ai/soleur/issues/1425) | Desktop app shipped | Not started |
| 5.3 | Reuse ops-provisioner guided setup pattern (3-phase: Setup, Configure, Verify) | P1 | [#1427](https://github.com/jikig-ai/soleur/issues/1427) | Playwright integrated | Not started |
| 5.4 | Auto-update mechanism | P2 | [#1428](https://github.com/jikig-ai/soleur/issues/1428) | Desktop app shipped | Not started |
| 5.5 | Code signing (macOS + Windows) | P1 | [#1429](https://github.com/jikig-ai/soleur/issues/1429) | Before distribution | Not started |

**Why this phase exists:** Browser automation is impossible on PWA, iOS, and Android due to platform sandboxing. Only a native desktop app can run Playwright locally on the user's machine. This is the desktop app's reason to exist — not wrapping the web app, but providing a capability no other surface can.

**Electron vs. Tauri:** Decision deferred to planning. Electron is heavier (~200MB) but mature ecosystem. Tauri is lighter (~10MB) but uses system webview.

**Exit criteria:**

- Desktop app installable on macOS + Windows
- Agent can automate Cloudflare/Stripe/Plausible signup via local Playwright
- Pause at CAPTCHA/OAuth, user handles in their own browser
- Auto-updates work

---

### Post-MVP / Later

Low-priority improvements deferred until after validation. Revisit when the platform has active users.

| # | Item | Priority | Issue | Status |
|---|------|----------|-------|--------|
| L1 | Vision page H1 rewrite (zero keyword value — "Vision" alone) | P1 | [#1131](https://github.com/jikig-ai/soleur/issues/1131) | Done |
| L2 | Add external citations to AI Agents for Solo Founders guide | P1 | [#1132](https://github.com/jikig-ai/soleur/issues/1132) | Done |
| L3 | Add source citations to case study cost comparisons (5 posts) | P1 | [#1133](https://github.com/jikig-ai/soleur/issues/1133) | Done |
| L4 | Blog index has no topic categorization (add tags, categories, topic clusters) | P0 | [#2071](https://github.com/jikig-ai/soleur/issues/2071) | Not started |
| L5 | Heading hierarchy issues on homepage and getting-started (h3 should be h2) | P1 | [#2072](https://github.com/jikig-ai/soleur/issues/2072) | Not started |
| L6 | html lang="en" vs en-US inconsistency (align to en-US) | P1 | [#2074](https://github.com/jikig-ai/soleur/issues/2074) | Not started |
| L7 | All blog posts share same generic OG image (create unique per-post images) | P2 | [#2075](https://github.com/jikig-ai/soleur/issues/2075) | Not started |

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

Weekly CPO review (every Monday). Pre-product-market-fit: the landscape changes faster than a month allows.

- **Weekly:** Review phase progress. Update statuses. Re-assess priorities based on user signal.
- **After each beta cohort:** Update validation findings. Adjust Phase 3 scope.
- **Quarterly:** Full roadmap revision. Cross-reference with competitive intelligence and marketing strategy.

Next review: 2026-04-17.

---

_Generated: 2026-03-23. Domain review: CTO, CLO, CFO, CMO (2026-03-23). Milestone audit: 2026-04-03. CPO weekly review: 2026-04-06. Status sync from GitHub milestones: 2026-04-10. CPO weekly review + status sync: 2026-04-13. Sources: business-validation.md (2026-03-12), competitive-intelligence.md (2026-03-12), pricing-strategy.md (2026-03-12), brand-guide.md (2026-02-21). Workshop conducted via /soleur:product-roadmap skill._
