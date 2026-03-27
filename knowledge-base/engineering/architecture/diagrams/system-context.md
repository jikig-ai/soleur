# System Context Diagram

Generated: 2026-03-27

````mermaid
graph TB
    subgraph "External Actors"
        founder["Founder (User)"]
        anthropic["Anthropic API"]
        github["GitHub"]
        cloudflare["Cloudflare"]
        doppler["Doppler"]
        discord["Discord"]
    end

    subgraph "Soleur Platform"
        webapp["Web App<br/>(Next.js PWA)"]
        cliengine["Cloud CLI Engine<br/>(Claude Code Instances)"]
        plugin["Soleur Plugin<br/>(61 Skills, 65 Agents)"]
        supabase["Supabase<br/>(Auth, DB, Storage)"]
    end

    founder -->|"Interacts via browser"| webapp
    webapp -->|"Thin view/control layer"| cliengine
    cliengine -->|"Loads"| plugin
    cliengine -->|"LLM calls"| anthropic
    cliengine -->|"Git operations"| github
    plugin -->|"Domain routing"| cliengine
    webapp -->|"Auth, data"| supabase
    cliengine -->|"BYOK keys, sessions"| supabase
    cloudflare -->|"Tunnel, DNS, CDN"| webapp
    doppler -->|"Runtime secrets"| cliengine
    cliengine -->|"Notifications"| discord
````

## Notes

- Web App is a thin view/control layer over the CLI engine (ADR-003)
- CLI engine preserves 100% of orchestration capability
- BYOK encryption isolates per-user API keys (ADR-004)
- All infrastructure provisioned via Terraform (ADR-019)
- Secrets managed via Doppler (ADR-007)
