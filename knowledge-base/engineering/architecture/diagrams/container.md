# Soleur Platform — Container Diagram (C4 Level 2)

Generated: 2026-05-13 (visual redesign per SOL-40, was 2026-03-27)

```mermaid
C4Container
title Container diagram for Soleur Platform

UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="2")

Person(founder, "Founder", "Solo founder using Soleur")

Enterprise_Boundary(b0, "Soleur Platform") {

    Container_Boundary(web, "Web Application") {
        Container(webapp, "Web Application", "Next.js PWA", "Dashboard UI + API routes + Supabase Auth — see Details")
    }

    Container_Boundary(cli, "Cloud CLI Engine") {
        Container(engine, "Cloud CLI Engine", "Claude Code", "Agent runtime + plugin discovery + hook engine — see Details")
    }

    Container_Boundary(plugin, "Soleur Plugin") {
        Container(plugin_box, "Soleur Plugin", "Markdown", "Skills + Agents + Knowledge Base — see L3 component-plugin.md")
    }

    Container_Boundary(infra, "Infrastructure") {
        ContainerDb(supabase, "Supabase PostgreSQL", "PostgreSQL", "Users, BYOK-encrypted API keys, conversation sessions")
        Container(compute, "Compute & Tunnel", "Hetzner Cloud + Cloudflare Tunnel", "Docker containers behind zero-trust tunnel")
    }
}

System_Ext(cloudflare, "Cloudflare", "DNS, CDN, Tunnel, R2")
System_Ext(doppler, "Doppler", "Secrets management")
System_Ext(anthropic, "Anthropic API", "Claude LLM")
System_Ext(github, "GitHub", "Source control and CI/CD")
System_Ext(thirdparty, "Third-Party Services", "Discord + Stripe + Plausible — see Details")

Rel(founder, webapp, "Browses and converses", "HTTPS")
Rel(webapp, engine, "Spawns agent sessions", "WebSocket")
Rel(engine, plugin_box, "Loads + guards", "File I/O + event hook")
Rel(webapp, supabase, "Auth and data", "HTTPS")
Rel(engine, supabase, "Sessions and keys", "HTTPS")
Rel(engine, anthropic, "LLM calls", "HTTPS")
Rel(engine, github, "Git operations", "HTTPS/SSH")
Rel(compute, engine, "Hosts + tunnel", "Docker + cloudflared")
Rel(doppler, engine, "Injects secrets", "CLI")
Rel(cloudflare, webapp, "DNS / CDN / Tunnel", "HTTPS")
BiRel(webapp, thirdparty, "Checkout / webhooks / page events", "HTTPS")
Rel(engine, thirdparty, "Notifications", "Webhook")
```

## Details

**`webapp` (Web Application) — folded from L2 source for visual budget; original Mermaid aliases preserved:**

- `dashboard` (React, Next.js) — conversation UI, knowledge base viewer, session management
- `api` (Next.js API) — REST endpoints for auth, sessions, and agent control
- `auth` (Supabase Auth) — JWT authentication, OAuth providers, session tokens

**`engine` (Cloud CLI Engine) — folded from L2 source:**

- `claude` (Claude Code) — executes agent workflows with full orchestration tools
- `skillloader` (Plugin Discovery) — discovers and loads skills, agents, commands from the plugin directory
- `hooks` (PreToolUse Guards) — enforces syntactic rules; blocks commits to main, `rm -rf`, etc.

**`plugin_box` (Soleur Plugin) — see L3 `component-plugin.md` for full decomposition:**

- `skills` — workflow skills (brainstorm, plan, work, review, compound, ship, one-shot, …) under `plugins/soleur/skills/`
- `agents` — domain agents across 8 departments under `plugins/soleur/agents/`
- `kb` — Markdown + YAML conventions, learnings, ADRs, specs, plans, brainstorms under `knowledge-base/`

**`compute` (Compute & Tunnel) — folded from L2 source:**

- `tunnel` (cloudflared) — zero-trust inbound access; no exposed ports (ADR-008)
- `hetzner` (Hetzner Cloud) — Docker containers running web app and CLI engine (ADR-006)

**`thirdparty` (Third-Party Services) — same fold as L1 `system-context.md`:**

- `stripe` — payment processing and subscription checkout + webhooks (test mode)
- `discord` — community notifications and release announcements via webhook
- `plausible` — privacy-focused page-view analytics (no cookies, GDPR-compliant)

## Notes

- Plugin has flat skill structure (skills don't nest) and recursive agent discovery (ADR-016)
- Three enforcement tiers: hooks (syntactic), skills (semantic), prose (advisory) — ADR-011
- Knowledge base compounds ADRs, learnings, and conventions across sessions
- Worktree isolation enforced via PreToolUse hooks (ADR-009)
- Version derived from git tags at merge time, not committed files (ADR-017)
- Stripe handles subscription checkout sessions and payment webhooks (test mode)
- Plausible analytics embedded as JS snippet in the web dashboard (no cookies, GDPR-compliant)
