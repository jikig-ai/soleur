---
title: Concurrency enforcement copy — conversation-slot pivot
date: 2026-04-19
author: copywriter
feature: feat-plan-concurrency-enforcement
issue: 1162
pr: 2617
supersedes: none
status: final
---

# Concurrency Enforcement Copy — Conversation-Slot Pivot

Copy execution for feature #1162 (Plan-Based Conversation Concurrency Enforcement). This artifact follows brainstorm Amendment A (2026-04-19): the public noun is **"concurrent conversations"**. No copy uses "agents" to refer to slots, parallelism, or capacity. Internal-only surfaces (telemetry, admin runbooks, DB columns) retain "slots".

**Voice reference:** brand-guide.md — bold, forward-looking, precise, honest. Founder-empathetic. No punitive triggers ("limit reached", "exceeded", "you have hit", "blocked"). Frames upgrade as headroom, not rescue.

**Constraints honored:**

- No "unlimited" anywhere (FTC truth-in-ads).
- "Agents" replaced with "conversations" in every customer-facing surface.
- Scale line reads "up to 50 concurrent conversations (contact us if you need more)".
- Enterprise line reads "Custom concurrency (negotiated per contract)".

---

## 1. Upgrade-at-capacity modal

Rendered on WS close `4010 CONCURRENCY_CAP`. Five states. Modal is small, centered, dismissible. Copy is tier-aware; `{N}` is the user's current active-conversation count (equal to their effective cap).

### 1a. State: Loading

**Title:** Opening checkout
**Body:** Spinning up a secure Stripe session. One moment.
**CTA:** (disabled spinner)

### 1b. State: Default (user hit their tier cap) — variants per tier

All variants share the same structure. The hero number matches the user's cap so the language scales with the tier.

#### Solo hits cap (N = 2)

**Title:** Both conversations are working.
**Subhead:** Solo gives you 2 conversations at once. Bump to Startup to run 5 in parallel — your CTO can review a PR while your CMO ships a post and three more specialists cover the rest.
**Primary CTA:** Upgrade to Startup — $149/mo
**Secondary link:** See all plans

#### Startup hits cap (N = 5)

**Title:** All 5 of your conversations are working.
**Subhead:** You've filled your Startup parallel. Step up to Scale to run up to 50 conversations at once — enough room for every department to move at the same time.
**Primary CTA:** Upgrade to Scale — $499/mo
**Secondary link:** See all plans

#### Scale hits cap (N = 50)

**Title:** All 50 of your conversations are working.
**Subhead:** That's the Scale plan's standing parallel — the platform ceiling today. If you need more headroom, we'll set up a custom quota.
**Primary CTA:** Contact us for a custom quota
**Secondary link:** See all plans

#### Enterprise hits cap (N = negotiated, default 50)

Falls through to state 1e below (Enterprise-cap).

### 1c. State: Error (Stripe Checkout didn't open)

**Title:** Checkout didn't open.
**Body:** Something on our end got in the way. Try again, or reach out and we'll finish the upgrade with you.
**Primary CTA:** Try again
**Secondary link:** Email support

### 1d. State: Admin-override (user has `concurrency_override` set and still hit their custom cap)

This is the rare case: ops raised the user's cap above tier default, and they've now filled that custom number. No upgrade surface — they're already at an ops-granted ceiling.

**Title:** All {N} of your conversations are working.
**Subhead:** You're on a custom parallel set by our team. If you need more room, reply to your last support thread and we'll raise it.
**Primary CTA:** Email support
**Secondary link:** Dismiss

### 1e. State: Enterprise-cap (Enterprise user hit platform hard cap of 50)

**Title:** All 50 of your conversations are working.
**Subhead:** 50 in parallel is the platform ceiling today. Your Enterprise contract can carry more — let's size a custom quota against your usage.
**Primary CTA:** Contact your account team
**Secondary link:** Dismiss

---

## 2. Pricing-page rewrite (`plugins/soleur/docs/pages/pricing.njk`)

Three strings per edit: (a) the file location, (b) current text, (c) new text (Eleventy/njk-safe — no stray quotes, ampersands HTML-escaped), (d) plain-English source for translation/reference.

### 2a. Solo tier bullet — line 184

**Current:** `<li>2 concurrent agent slots</li>`
**New:** `<li>2 concurrent conversations</li>`
**Source:** Two conversations running in parallel.

### 2b. Startup tier bullet — line 199

**Current:** `<li>5 concurrent agent slots</li>`
**New:** `<li>5 concurrent conversations</li>`
**Source:** Five conversations running in parallel.

### 2c. Scale tier feature list — lines 214–217

**Current:**

```njk
<li>Unlimited concurrent agents</li>
<li>Dedicated infrastructure</li>
<li>Unlimited seats</li>
<li>Custom agent configuration</li>
```

**New:**

```njk
<li>Up to 50 concurrent conversations (contact us if you need more)</li>
<li>Dedicated infrastructure</li>
<li>Up to 25 seats</li>
<li>Custom agent configuration</li>
```

**Source:**

- Up to 50 conversations running in parallel. We'll expand on request.
- Dedicated infrastructure.
- Up to 25 seats.
- Custom agent configuration.

> Note on "Unlimited seats": this was a separate claim, not a concurrency claim, but "unlimited" is out per FTC guidance. Replaced with a concrete number. If 25 is wrong, CMO/CPO should confirm — conservative default chosen.

### 2d. Enterprise tier feature list — lines 228–233

**Current:**

```njk
<li>Everything in Scale</li>
<li>Sliding scale: 10% &rarr; 5% as you grow</li>
<li>Dedicated account management</li>
<li>Custom integrations &amp; SLA</li>
```

**New:**

```njk
<li>Everything in Scale</li>
<li>Custom concurrency (negotiated per contract)</li>
<li>Sliding scale: 10% &rarr; 5% as you grow</li>
<li>Dedicated account management</li>
<li>Custom integrations &amp; SLA</li>
```

**Source:**

- Everything in Scale.
- Custom concurrency, negotiated per contract.
- Sliding scale: 10% down to 5% as you grow.
- Dedicated account management.
- Custom integrations and SLA.

### 2e. FAQ — the "concurrent agent slots" question (lines 253–256)

**Current summary:** `What are concurrent agent slots?`
**New summary:** `What are concurrent conversations?`

**Current answer:**

```text
Concurrent slots are the number of agents that can execute at the same time. On the Solo plan, two agents work in parallel -- your CTO reviews a pull request while your CMO drafts a blog post. Every plan includes every agent. Slots determine parallelism, not access.
```

**New answer (Eleventy/njk-safe):**

```njk
<p class="faq-answer">Concurrent conversations are how many chats can run work at the same time. On the Solo plan, two conversations run in parallel &mdash; your CTO reviews a pull request while your CMO drafts a blog post. Inside one conversation, you can still <code>@mention</code> multiple specialists and they work together on that single thread. Every plan includes every agent. Concurrency determines parallelism, not access.</p>
```

**Source:** Concurrent conversations are how many chats can run work at the same time. On Solo, two conversations run in parallel — your CTO reviews a PR while your CMO drafts a blog post. Inside one conversation, you can still @mention multiple specialists and they'll work together on that thread. Every plan includes every agent. Concurrency determines parallelism, not access.

### 2f. JSON-LD `offers.description` / FAQ block — lines 287–291

**Current:**

```json
{
  "@type": "Question",
  "name": "What are concurrent agent slots?",
  "acceptedAnswer": {
    "@type": "Answer",
    "text": "Concurrent slots are the number of agents that can execute at the same time. On the Solo plan, two agents work in parallel -- your CTO reviews a pull request while your CMO drafts a blog post. Every plan includes every agent. Slots determine parallelism, not access."
  }
}
```

**New (Eleventy/njk-safe — plain string, no HTML entities):**

```json
{
  "@type": "Question",
  "name": "What are concurrent conversations?",
  "acceptedAnswer": {
    "@type": "Answer",
    "text": "Concurrent conversations are how many chats can run work at the same time. On the Solo plan, two conversations run in parallel -- your CTO reviews a pull request while your CMO drafts a blog post. Inside one conversation, you can @mention multiple specialists and they work together on that thread. Every plan includes every agent. Concurrency determines parallelism, not access."
  }
}
```

**Source:** same as 2e, minus HTML markup.

### 2g. Grep-check after edit

Before commit, confirm zero remaining hits in `plugins/soleur/docs/pages/pricing.njk`:

- `rg -i "concurrent agent" plugins/soleur/docs/pages/pricing.njk` → zero lines
- `rg -i "agents in parallel" plugins/soleur/docs/pages/pricing.njk` → zero lines
- `rg -i "unlimited" plugins/soleur/docs/pages/pricing.njk` → zero lines

---

## 3. In-product banner (2 weeks post-ship, workspace view)

Dismissible, top-of-workspace. One-line primary + short expand-on-hover. No apology — the pricing page always said this.

**Primary (short):** Concurrent conversations now run per plan — see pricing.
**Primary (medium, if room):** Heads up: concurrent conversations now run per plan. See what your tier includes.
**CTA link text:** See pricing
**CTA URL:** `/pricing`

---

## 4. Downgrade banner (mid-grace-window, after Stripe downgrade webhook)

Persistent until active-conversation count is within new tier cap. Warm, specific, no blame. Avoids "downgrade" as the framing word.

**Option A (1 sentence, preferred):** You're now on {NewTier}. Your running conversations will finish; new ones will start as soon as there's room.

**Option B (2 sentences, if the UI allows):** You're now on {NewTier} — {NewCap} concurrent conversations. Anything running right now will finish; new conversations will start as soon as one wraps.

Pick Option A unless legal/support asks for the explicit cap number. Both variants ship-ready.

---

## 5. "Upgrade pending payment verification" banner (Stripe `incomplete` / 3DS state)

Persistent until `customer.subscription.updated` → `active`. Calm, factual. Frames as a bank step, not a system failure.

**Banner (1 sentence):** Your upgrade is waiting on your bank's payment confirmation — we'll switch you over the moment it clears.

---

## 6. Proactive email (users who exceeded Solo cap in 30d before ship)

Send only if the verification query returns ≥1 user at ship-prep time (per FR8). Tone: founder-empathetic, pre-GA candid, not apologetic. They've been getting more than the pricing page promised; we're aligning. Keep it short.

**From:** Jean Deruelle &lt;<jean@soleur.ai>&gt;
**Reply-to:** <jean@soleur.ai>
**Subject:** A heads-up about concurrent conversations on Soleur

**Body:**

Hey {FirstName},

You've been running a lot of conversations in parallel over the last few weeks — which is exactly what we want to see. Thank you for pushing the product.

As we move toward general availability, we're aligning what the product enforces with what our pricing page has always promised: concurrent conversations per plan. Starting {ShipDate}, Solo will hold 2 conversations at once, Startup 5, and Scale up to 50. Inside any single conversation you can still @mention the full C-suite — fan-out is free.

Given how you've been using the product, I wanted you to hear this from me before you hit it in the app. If Solo's 2-conversation parallel feels tight for what you're building, Startup is $149/mo and gives you 5. Either way, your existing in-flight work will always finish — the cap only applies to starting new conversations.

Reply to this email if anything here is a surprise, or if the limit is going to get in your way. I read every one.

— Jean
Founder, Soleur

---

## 7. Changelog entry (ship-day)

**One line:**

> **Concurrent conversations now run per plan** — Solo: 2, Startup: 5, Scale: up to 50. Inside a conversation, `@mention` as many specialists as you want; they all count as one. Pricing page updated to match. (#1162)

---

## Cross-surface consistency checklist

Before merge, confirm every customer-facing surface aligns:

- [ ] Modal copy (all 5 states, all 4 tier variants of default state) uses "conversations" — never "agents" for capacity
- [ ] `pricing.njk` shows no "Unlimited" and no "concurrent agent" strings
- [ ] FAQ summary and answer reference conversations
- [ ] JSON-LD `name` and `text` fields updated
- [ ] In-product banner (item 3) deployed with 2-week expiry
- [ ] Downgrade banner (item 4) wired to Stripe downgrade webhook
- [ ] Stripe `incomplete` banner (item 5) wired to tier-read retry state
- [ ] Proactive email (item 6) sent only if affected-user query returns ≥1
- [ ] Changelog entry (item 7) in the ship-day changelog
- [ ] Internal surfaces (telemetry field `active_conversation_count`, admin runbook for `concurrency_override`, DB column names) retain "slots" — intentional, not a bug

## Copy that was considered and rejected

- "You've maxed out your parallel." — "maxed out" trips the punitive-trigger rule.
- "Upgrade to unlock more conversations." — "unlock" implies access gating; the FAQ explicitly says access is universal.
- "Wait for a conversation to finish, or upgrade." — reintroduces a queue affordance the product does not have (see spec non-goals).
- "You're at your limit." — direct punitive trigger; banned.
- "Bandwidth" / "throughput" as a user-facing noun — engineering register, not founder register.

## Notes to implementer

1. `{N}`, `{NewTier}`, `{NewCap}`, `{FirstName}`, `{ShipDate}` are interpolation placeholders. The plan phase will map them to real variables in `apps/web-platform` components.
2. If the in-product banner needs a longer copy variant for accessibility/screen-reader contexts, use the medium version in item 3.
3. The wireframe at `knowledge-base/product/design/upgrade-modal-at-capacity.pen` needs re-render to match the title/subhead split in item 1 (prior render used a single headline). Flag to ux-design-lead.
4. Enterprise default state (1b fourth variant) falls through to 1e — do not render 1b for Enterprise users; the hard-cap branch is the only Enterprise surface.
5. Do not add a "Maybe later" or "Dismiss" affordance on 1b default states — the modal itself is dismissible (X in corner); adding a text button there trains users to skip the upgrade prompt.
