---
component: web-platform
updated: 2026-11-02
primary_location: apps/web-platform/
dependencies: [skills, agents, knowledge-base]
---

# Web Platform

The Soleur Command Center: a Next.js 16 web app that hosts the chat router (`/soleur:go`), the KB Concierge sidebar, and the Claude Agent SDK runners that execute Soleur skills and agents on behalf of signed-in users.

## Purpose

Give founders a browser-based surface for the same Company-as-a-Service workflows the CLI plugin provides, without a local Claude Code install.

## Responsibilities

- Authenticate users and isolate per-user workspaces (Supabase auth + RLS)
- Run agent sessions server-side through the Claude Agent SDK with sandboxing and approval gates
- Render the knowledge base, including C4 diagrams, from the connected GitHub repository
- Serve internal cron/Inngest endpoints and observability (Sentry)

## Key Interfaces

- `app/` — Next.js App Router pages and API routes (`app/api`, `app/internal`)
- `server/` — agent runner, engine adapters, sandbox config, account lifecycle (server-only; guarded by the client/server import boundary in `server/README.md`)
- `components/` — React UI, including the Button primitive family (`components/ui/README.md`)
- `lib/` — shared client/server helpers (feature flags, Inngest, auth, C4 embed)
- `supabase/` — migrations and RLS policies

## Dependencies

- **Internal**: [skills](skills.md), [agents](agents.md), [knowledge-base](knowledge-base.md)
- **External**: Next.js, Supabase, Claude Agent SDK, Inngest, Sentry, Doppler, GitHub App

## Related Files

- `apps/web-platform/README.md` — requirements and local development
- `apps/web-platform/AGENTS.md` — app-scoped agent rules

## See Also

- [Skills](./skills.md)
- [Agents](./agents.md)
- [Knowledge Base](./knowledge-base.md)
