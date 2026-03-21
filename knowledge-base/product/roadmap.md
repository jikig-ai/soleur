---
last_updated: 2026-03-17
last_reviewed: 2026-03-17
review_cadence: monthly
owner: CPO
depends_on:
  - knowledge-base/product/pricing-strategy.md
  - knowledge-base/project/specs/feat-web-platform-ux/tasks.md
---

# Product Roadmap: Web Platform (app.soleur.ai)

## Current State

| Dimension | Status |
|-----------|--------|
| Phase 1 (Working Loop) | Deployed. All 15 tasks complete. Auth, BYOK, chat, agent execution, Stripe, Hetzner infra. |
| BYOK decryption | Broken. #667 blocks all agent execution for new users. Nothing works until this is fixed. |
| Integration tests | None. #668. No automated coverage for WebSocket, auth, or session flows. |
| Beta users | 0. No external user has completed the auth-to-chat loop. |
| Pricing | $49/mo + BYOK hypothesis. 0 of 5 pricing gates passed. Stripe in test mode. |
| Security posture | Unaudited. No CSP, no CORS policy, no session timeout, no OWASP review. |
| Vendor compliance | No DPA review for Supabase, Stripe, Hetzner, or Cloudflare. #670. |

**Product maturity stage:** Building (Phase 1 deployed, pre-beta, zero external users).

---

## Strategic Recommendation

**Option A (recommended): Fix + Secure + Validate**

Ship the smallest surface that a beta tester can use without encountering broken flows or security gaps. Do not build visibility features (Phase 2) until real users ask for them. Promote security hardening from Phase 3 to Phase 1.5 because shipping an unaudited platform to beta users -- even 5 founders -- creates reputational and legal risk disproportionate to the time saved.

| Option | Risk | Scope | Trade-off |
|--------|------|-------|-----------|
| A: Fix + Secure + Validate | Low | Medium (2-3 weeks) | Delays beta invites by ~2 weeks. Users arrive to a platform that works and is safe. |
| B: Fix + Invite immediately | High | Small (days) | Faster to first user. Unaudited security, no error states, no onboarding. First impression is rough. |
| C: Build Phase 2 first | Medium | Large (4-6 weeks) | KB viewer and inbox are useful but premature. No evidence users need them yet. |

Recommendation: Option A. The BYOK fix (#667) is a blocker measured in hours. The security audit and polish are measured in days. The cost of doing them now is small; the cost of a security incident with beta users is large.

---

## Phases

### Phase 1.0: Fix What's Broken (in progress)

Unblock the deployed platform. Every item here prevents a new user from completing the core loop.

| # | Item | Issue | Priority | Status |
|---|------|-------|----------|--------|
| 1 | BYOK decryption fix -- key retrieval fails after storage | [#667](https://github.com/jikig-ai/soleur/issues/667) | P1 | In progress |
| 2 | Integration tests for WebSocket, auth, and session flows | [#668](https://github.com/jikig-ai/soleur/issues/668) | P1 | Not started |
| 3 | Knowledge base page 404 placeholder (graceful empty state) | [#669](https://github.com/jikig-ai/soleur/issues/669) | P2 | Not started |
| 4 | Vendor DPA review + expense recording (Supabase, Stripe, Hetzner, Cloudflare) | [#670](https://github.com/jikig-ai/soleur/issues/670) | P1 | Not started |

**Exit criteria:** A new user can sign up, store a BYOK key, start a conversation with a domain leader, and receive streamed agent output without errors.

### Phase 1.5: Secure + Polish (beta gate) -- [#674](https://github.com/jikig-ai/soleur/issues/674)

Items promoted from Phase 3 (security) and added (UX polish) to create a defensible beta experience. Nothing ships to external users until this phase passes.

| # | Item | Origin | Priority | Notes |
|---|------|--------|----------|-------|
| 1 | Security audit: workspace isolation, BYOK key handling, OWASP Top 10 | Promoted from Phase 3 (was 3.1) | P1 | Non-negotiable before beta invites. |
| 2 | CSP headers + CORS policy | Promoted from Phase 3 (was 3.6) | P1 | Prevents XSS and unauthorized API access. |
| 3 | Session timeout + WebSocket expiry | Promoted from Phase 3 (was 3.7) | P1 | Stale sessions are a security and resource leak. |
| 4 | UX audit of Phase 1 screens | [#671](https://github.com/jikig-ai/soleur/issues/671) | P2 | Login, BYOK setup, domain selector, chat. Identify broken flows before users hit them. |
| 5 | User settings page: API key rotation, account deletion | New (GDPR requirement) | P1 | Account deletion is a legal requirement, not a feature. Key rotation is a security baseline. |
| 6 | Error and empty states in chat and dashboard | New | P2 | No conversation yet, agent error, network disconnect, rate limit -- all need visible handling. |
| 7 | First-time onboarding walkthrough | New | P2 | Guide the user from login to first successful agent conversation. Reduce time-to-value. |

**Exit criteria (beta launch checklist):**

| Gate | Pass/Fail | Criteria |
|------|-----------|----------|
| BYOK works end-to-end | Must pass | New user stores key, key decrypts, agent executes. |
| Security audit complete | Must pass | No critical or high findings open. |
| CSP + CORS deployed | Must pass | Headers present on all routes. |
| Session timeout active | Must pass | Idle sessions expire. WebSocket connections close after inactivity. |
| Account deletion works | Must pass | User can delete account and all associated data. GDPR compliance. |
| Error states visible | Must pass | Agent failure, network loss, and empty states all render a meaningful message. |
| Onboarding walkthrough | Should pass | First-time user can complete the loop without external documentation. |
| Integration tests green | Must pass | Auth, WebSocket, and session tests pass in CI. |
| DPA review complete | Must pass | Data processing terms reviewed for all vendors. |

### Phase 2: Visibility (essential for beta) -- [#672](https://github.com/jikig-ai/soleur/issues/672)

The features that make the platform useful beyond a single conversation. Phase 2 is the difference between "I tried it" and "I use it." Build after Phase 1.5 passes, but scope should be shaped by observed user behavior during beta.

| # | Item | Priority | Notes |
|---|------|----------|-------|
| 2.1 | KB REST API (file tree, content, search) | P1 | The data layer for the review loop. |
| 2.2 | KB viewer UI (sidebar tree, markdown rendering, search) | P1 | The founder reviews plans, brainstorms, and domain leader outputs here. |
| 2.3 | Conversation inbox with status badges | P1 | The action loop. Which conversations need attention, which are complete, which are blocked on review gates. |
| 2.4 | Usage/cost indicator for BYOK spending | P2 | Users pay Anthropic directly. They need visibility into what their agents cost. |
| 2.5 | Email notifications for offline review gates (Resend) | Deferred | Build only if users report missing review gates. |
| 2.6 | Execution history (completed conversations with outcomes) | Deferred | Build only if users want to revisit past sessions. |

**Why 2.1-2.2 matter:** The knowledge base is Soleur's compounding moat. If users cannot see what their agents produced -- plans, brainstorms, brand guides, competitive analyses -- the value is invisible. The KB viewer closes the review loop: agent produces artifact, founder reviews it, founder refines it, knowledge compounds.

**Why 2.3 matters:** Without an inbox, the user has no sense of what happened while they were away. For a solo founder who triggers agents and returns later, the inbox is the landing page.

### Phase 3: Hardening -- [#673](https://github.com/jikig-ai/soleur/issues/673)

Triggered by user count, not timeline. Each item has a concrete trigger condition.

| # | Item | Trigger | Notes |
|---|------|---------|-------|
| 3.1 | Container-per-workspace | 5+ concurrent users | Current shared-process model is fine for 1-3. Beyond that, isolation matters. |
| 3.2 | Rate limiting (per-user concurrency, API rate) | Before public launch | Prevents abuse and runaway costs. Not needed during invite-only beta. |
| 3.3 | Monitoring (execution metrics, error rates, uptime) | 10+ users | Operational visibility. Before this threshold, logs suffice. |
| 3.4 | Error tracking (Sentry or equivalent) | 10+ users | Structured error tracking replaces grepping logs. |
| 3.5 | Load testing (50+ concurrent users) | Before public launch | Validates that the architecture holds under real concurrency. |

---

## Pricing

**Current hypothesis:** $49/month subscription + BYOK (user provides their own Anthropic API key).

**Status:** 0 of 5 pricing gates passed. Stripe is in test mode. Do not activate live payments until at least 4 gates pass.

| Gate | Criteria | Status |
|------|----------|--------|
| Demand validation | 10+ solo founders used the platform for 2+ weeks | Not started |
| Multi-domain validation | 5+ users engaged with 2+ non-engineering domains | Not started |
| Willingness-to-pay signal | 3+ founders say they would pay $49/month | Not started |
| Infrastructure cost model | Hosting costs understood per-user, margin is positive | Not assessed |
| Cowork differentiation clear | Users articulate why Soleur is worth paying for vs. free Cowork plugins | Not started |

**Decision:** Keep Stripe in test mode through Phase 1.5 and Phase 2. Revisit pricing after beta validation data exists. Full analysis in `knowledge-base/product/pricing-strategy.md`.

---

## Validation Plan

The business validation verdict is PIVOT: stop building features, start validating with users. The web platform exists to make that validation possible -- it is the onboarding surface for beta testers who do not use Claude Code locally.

### Recruitment

- **Target:** 5-10 solo founders from mixed channels.
- **Channels:** Claude Code Discord, GitHub (developers with business-operations repos), IndieHackers, direct network.
- **Selection criteria:** Must be building a real product (not exploring). Must be willing to use the platform for 2+ weeks. Prefer founders already using Claude Code or similar AI tools.

### Protocol

1. **Problem interview first (no demo).** Does the founder independently describe multi-domain pain? If fewer than 5 of 10 describe it, the thesis does not resonate.
2. **Guided onboarding with the top 5.** Walk them through auth, BYOK, first conversation. Observe which domain leader they choose first and why.
3. **2-week unassisted usage.** Track: Do they return? Does the knowledge base grow? Do they use non-engineering agents without prompting?
4. **Exit interview.** What worked? What was missing? Would they pay $49/month? What would it need to deliver?

### What we learn

- Phase 2 scope should be shaped by what users ask for, not what we assume they need.
- If every user only uses the engineering domain leader, the CaaS thesis is wrong and the platform is a worse Cursor.
- If users engage multiple domains but ignore the KB, the compounding thesis is wrong and the platform is a chatbot.
- If users engage multiple domains AND return to the KB, the thesis holds and Phase 2 (KB viewer, inbox) becomes urgent.

---

## Dependencies

| This roadmap depends on | Path | Why |
|------------------------|------|-----|
| Pricing strategy | `knowledge-base/product/pricing-strategy.md` | Pricing gates, tier structure, competitive pricing context. |
| Web platform spec and tasks | `knowledge-base/project/specs/feat-web-platform-ux/tasks.md` | Phase 1 task list, Phase 2-3 task definitions. |
| Business validation | `knowledge-base/product/business-validation.md` | PIVOT verdict, demand evidence, customer definition. |
| Competitive intelligence | `knowledge-base/product/competitive-intelligence.md` | Tier 0 threats, pricing anchors, differentiation axis. |

---

## Review Cadence

Monthly CPO review. More frequent than marketing's quarterly cadence because the product is pre-product-market-fit -- the landscape changes faster than a quarter allows.

- **Monthly:** Review phase progress against this roadmap. Update statuses. Re-assess priorities based on user signal (or lack of it).
- **After each beta cohort:** Update validation findings. Adjust Phase 2 scope. Re-evaluate pricing gates.
- **Quarterly:** Full roadmap revision. Cross-reference with competitive intelligence and marketing strategy.

Next review: 2026-04-17.

---

_Generated: 2026-03-17. Sources: business-validation.md (2026-03-12), pricing-strategy.md (2026-03-12), tasks.md (2026-03-16), marketing-strategy.md (2026-03-13)._
