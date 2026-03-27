# Container Diagram

Generated: 2026-03-27

````mermaid
graph TB
    subgraph "Web Application (Next.js PWA)"
        dashboard["Dashboard<br/>(React)"]
        auth["Auth Module<br/>(Supabase Auth)"]
        api["API Routes<br/>(Next.js)"]
    end

    subgraph "Cloud CLI Engine"
        claude["Claude Code<br/>(Agent Runtime)"]
        skillloader["Skill Loader<br/>(Plugin Discovery)"]
        hookengine["Hook Engine<br/>(PreToolUse Guards)"]
    end

    subgraph "Soleur Plugin (plugins/soleur/)"
        commands["Commands<br/>(go, sync, help)"]
        skills["Skills<br/>(61 workflow skills)"]
        agents["Agents<br/>(65 domain agents)"]
        kb["Knowledge Base<br/>(Conventions, Learnings)"]
    end

    subgraph "Infrastructure"
        supabase_db["Supabase PostgreSQL<br/>(Users, Keys, Sessions)"]
        r2["Cloudflare R2<br/>(Terraform State)"]
        tunnel["Cloudflare Tunnel<br/>(Zero-Trust Access)"]
        hetzner["Hetzner Cloud<br/>(Compute)"]
    end

    dashboard --> api
    api --> claude
    claude --> skillloader
    skillloader --> skills
    skillloader --> agents
    skillloader --> commands
    hookengine --> claude
    skills --> kb
    agents --> kb
    api --> supabase_db
    claude --> supabase_db
    tunnel --> api
    hetzner --> claude
````

## Notes

- Plugin has flat skill structure (skills don't nest) and recursive agent discovery
- Three enforcement tiers: hooks (syntactic), skills (semantic), prose (advisory) — see ADR-011
- Knowledge base compounds decisions (ADRs), learnings, and conventions
- Worktree isolation enforced via hooks (ADR-009)
