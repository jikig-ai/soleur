# Browser Automation for Cloud Platform

**Date:** 2026-03-23
**Issue:** #1050
**Status:** Decided

## What We're Building

A 3-tier service automation system for the Soleur cloud platform that helps founders set up third-party services (Cloudflare, Stripe, Plausible, Buttondown, Supabase, Hetzner, etc.) with both expert guidance and hands-free automation.

### The 3-Tier Architecture

| Tier | Platform | Coverage | Automation Level |
|------|----------|----------|------------------|
| **API + MCP** | All (web, mobile, desktop) | ~80% of services | Full — deterministic API calls and MCP server integrations. MCP is first-class: services publishing MCP servers get zero-config integration. |
| **Local Playwright** | Desktop native app (Electron/Tauri) only | ~15% of services without API/MCP | Full — local browser on user's machine, user's credentials |
| **Guided instructions** | Web + mobile (fallback) | ~5% remainder | Agent guides with deep links, user clicks |

## Why This Approach

### Problem

Founders validated browser automation as a high-value feature — agents that both know what to configure AND do the configuration. The original server-side Playwright approach was flagged as HIGH risk by three domain leaders:

- **CTO:** 2-3 weeks complexity, 500MB RAM per instance, SSRF attack surface, sandbox conflicts, brittle CSS selectors
- **CLO:** Undisclosed agency liability under French civil law (Code civil Art. 1984-2010), third-party ToS violations, CFAA exposure
- **CFO:** Only roadmap item that could force 2-4x infrastructure cost increase

### Why API-First

The CLI plugin used browser automation because it was the universal approach from the user's machine. The cloud platform has a different advantage — server-side API access. Most services founders need (Cloudflare, Stripe, Plausible, etc.) have robust REST APIs. API calls are:

- Deterministic (no brittle selectors)
- Versioned (no surprise breakage from UI changes)
- Authorized (user provides their own API token — no undisclosed agency)
- Lightweight (near-zero server cost vs. 500MB RAM for headless Chromium)

### Why Desktop Native App for Browser Automation

| Surface | Can run local Playwright? | Why |
|---------|--------------------------|-----|
| PWA (web/mobile/desktop) | No | Browser sandbox prevents controlling other windows |
| Electron/Tauri desktop app | Yes | Full Node.js/Rust access, same as CLI today |
| iOS native | No | iOS sandboxing prevents app-to-app control |
| Android native | No (fragile) | Accessibility services are fragile and policy-violating |

The desktop native app earns its existence specifically because browser automation is impossible on any other surface. This is the justification for building it — not just wrapping the web app.

### Why Guided Instructions as Fallback

For the ~5% of services without APIs, and for web/mobile users who don't have the desktop app, the agent provides:

- Step-by-step instructions with screenshots/deep links
- Context-aware guidance (agent knows the user's infrastructure from KB)
- Review gates to confirm each step is complete

## Key Decisions

1. **API-first is the primary automation mechanism.** Browser automation is the fallback, not the primary.
2. **Browser automation is a desktop-exclusive feature.** PWA/web/mobile users get API automation + guided instructions.
3. **Desktop native app (Electron or Tauri) goes back on the roadmap** as a Phase 4/5 item, justified by browser automation.
4. **Server-side Playwright is permanently rejected.** The risk profile (CTO + CLO + CFO all HIGH) is not acceptable.
5. **API tokens stored securely alongside BYOK key.** Same AES-256-GCM encryption, same per-user HKDF derivation.
6. **Reuse ops-provisioner pattern** for the guided setup flow (3-phase: Setup, Configure, Verify).

## Open Questions

1. **Electron vs. Tauri?** Electron is heavier (~200MB) but has the larger ecosystem. Tauri is lighter (~10MB) but uses system webview (potential rendering inconsistencies). Decision deferred to planning.
2. **Which services get API integration first?** Likely Cloudflare (most complex setup), Stripe (payment integration), Plausible (analytics). Prioritize by founder request frequency.
3. **API token management UX.** How many tokens does a founder manage? One per service? Should there be a "connected services" page?
4. **Desktop app distribution.** Direct download from soleur.ai, or app stores (Mac App Store, Microsoft Store)?

## Domain Assessments

**Assessed:** Engineering (CTO), Legal (CLO), Finance (CFO), Marketing (CMO)

### Engineering (CTO)

**Summary:** Server-side Playwright is HIGH risk (RAM, SSRF, sandbox conflicts). API-first eliminates all three concerns. Desktop native app for local Playwright is architecturally sound — same pattern as CLI plugin. Recommend Tauri over Electron for smaller bundle size unless Electron-specific features are needed.

### Legal (CLO)

**Summary:** API-first with user-provided tokens eliminates undisclosed agency liability. User explicitly authorizes each service connection. No third-party ToS violations when using official APIs as intended. Desktop local Playwright runs in user's own browser with their own credentials — no Jikigai liability.

### Finance (CFO)

**Summary:** API-first has near-zero marginal cost. Desktop app distribution cost is minimal (code signing certificate ~$100/year). No server-side browser infrastructure needed. The 2-4x infra cost risk from server-side Playwright is fully eliminated.

### Marketing (CMO)

**Summary:** Desktop app as a "power user" surface creates a natural upgrade path: web (try it) → desktop (go deeper). Browser automation as a desktop-exclusive feature is a compelling differentiator against Polsia (cloud-only, no local automation). Messaging: "Your AI organization, running in your browser."
