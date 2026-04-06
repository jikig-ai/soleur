# Soleur Platform — Container Diagram (C4 Level 2)

Generated: 2026-03-27

```mermaid
C4Container
title Container diagram for Soleur Platform

Person(founder, "Founder", "Solo founder using Soleur")

System_Ext(anthropic, "Anthropic API", "Claude LLM")
System_Ext(github, "GitHub", "Source control and CI/CD")
System_Ext(cloudflare, "Cloudflare", "DNS, CDN, Tunnel, R2")
System_Ext(doppler, "Doppler", "Secrets management")
System_Ext(stripe, "Stripe", "Payment processing")
System_Ext(plausible, "Plausible", "Privacy-focused analytics")
Enterprise_Boundary(b0, "Soleur Platform") {

    Container_Boundary(web, "Web Application") {
        Container(dashboard, "Dashboard", "React, Next.js", "Conversation UI, knowledge base viewer, session management")
        Container(api, "API Routes", "Next.js API", "REST endpoints for auth, sessions, and agent control")
        Container(auth, "Auth Module", "Supabase Auth", "JWT authentication, OAuth providers, session tokens")
    }

    Container_Boundary(cli, "Cloud CLI Engine") {
        Container(claude, "Agent Runtime", "Claude Code", "Executes agent workflows with full orchestration tools")
        Container(skillloader, "Skill Loader", "Plugin Discovery", "Discovers and loads skills, agents, commands from plugin directory")
        Container(hooks, "Hook Engine", "PreToolUse Guards", "Enforces syntactic rules — blocks commits to main, rm -rf, etc.")
    }

    Container_Boundary(plugin, "Soleur Plugin") {
        Container(skills, "Skills", "Markdown SKILL.md", "61 workflow skills — brainstorm, plan, work, review, compound, etc.")
        Container(agents, "Agents", "Markdown Agent Defs", "65 domain agents across 8 departments")
        Container(kb, "Knowledge Base", "Markdown + YAML", "Conventions, learnings, ADRs, specs, plans, brainstorms")
    }

    Container_Boundary(infra, "Infrastructure") {
        ContainerDb(supabase, "Supabase PostgreSQL", "PostgreSQL", "Users, BYOK-encrypted API keys, conversation sessions")
        Container(tunnel, "Cloudflare Tunnel", "cloudflared", "Zero-trust inbound access — no exposed ports")
        Container(hetzner, "Compute", "Hetzner Cloud", "Docker containers running web app and CLI engine")
    }
}

Rel(founder, dashboard, "Browses and converses", "HTTPS")
Rel(dashboard, api, "Calls", "HTTPS")
Rel(api, claude, "Spawns agent sessions", "WebSocket")
Rel(claude, skillloader, "Loads plugin", "File I/O")
Rel(skillloader, skills, "Discovers", "Directory scan")
Rel(skillloader, agents, "Discovers", "Recursive scan")
Rel(hooks, claude, "Guards tool calls", "Event hook")
Rel(skills, kb, "Reads/writes", "File I/O")
Rel(agents, kb, "Reads", "File I/O")
Rel(api, supabase, "Auth and data", "HTTPS")
Rel(claude, supabase, "Sessions and keys", "HTTPS")
Rel(claude, anthropic, "LLM calls", "HTTPS")
Rel(claude, github, "Git operations", "HTTPS/SSH")
Rel(tunnel, api, "Routes traffic", "HTTPS")
Rel(hetzner, claude, "Hosts", "Docker")
Rel(doppler, claude, "Injects secrets", "CLI")
Rel(auth, supabase, "Validates tokens", "HTTPS")
Rel(api, stripe, "Checkout and webhooks", "HTTPS")
Rel(dashboard, plausible, "Page view events", "JS snippet")
```

## Notes

- Plugin has flat skill structure (skills don't nest) and recursive agent discovery (ADR-016)
- Three enforcement tiers: hooks (syntactic), skills (semantic), prose (advisory) — ADR-011
- Knowledge base compounds ADRs, learnings, and conventions across sessions
- Worktree isolation enforced via PreToolUse hooks (ADR-009)
- Version derived from git tags at merge time, not committed files (ADR-017)
- Stripe handles subscription checkout sessions and payment webhooks (test mode)
- Plausible analytics embedded as JS snippet in the web dashboard (no cookies, GDPR-compliant)
