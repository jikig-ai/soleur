# Secrets Manager Adoption Brainstorm

**Date:** 2026-03-20
**Issue:** #734
**Branch:** feat-secrets-manager
**Status:** Decision made

## What We're Building

Centralized secrets management using **Doppler** to replace the current scattered credential pattern (GitHub Actions secrets + local `.env` files + server `/mnt/data/.env` + Terraform variables). All 4 credential surfaces will be migrated incrementally.

## Why This Approach

### Pain Points (All Active)

1. **Disaster recovery** — If the Hetzner server dies, rebuilding `/mnt/data/.env` requires recalling ~12 secrets from memory. The BYOK_ENCRYPTION_KEY has no backup; its loss means permanent user data loss.
2. **Secret sprawl / drift** — Same logical secret (e.g., `DISCORD_WEBHOOK_URL`) exists in 3 places with no mechanism to ensure sync after rotation.
3. **Dev machine exposure** — Root `.env` contains live Cloudflare, Discord, and X/Twitter credentials in plaintext. A past API key leak required full git history rewrite across 10 branches.
4. **Rotation friction** — Rotating a credential means updating 2-3 locations manually. Easy to miss one.

### Why Doppler Over Alternatives

| Option | Why Not |
|--------|---------|
| **1Password CLI** | No existing subscription. Would cost $27/mo (personal + service account) — nearly doubling current infrastructure spend. |
| **Infisical SaaS** | Tighter free tier (3 projects, 3 envs, 5 identities vs Doppler's 10/4/50). No versioning or rollback on free tier ($18/mo for Pro). Manual Terraform wiring needed. |
| **Infisical self-hosted** | Can't fit on CX22 (4GB RAM) alongside production workloads. Would need ~$11/mo server upgrade, defeating the cost purpose. |
| **GitHub Actions only** | No local dev or server-side story. Only addresses CI surface. |
| **`pass` + scripts** | No audit trail, no web UI, requires custom glue code for every integration. |

### Why Doppler Specifically

1. **Terraform DX** — `--name-transformer tf-var` auto-converts secrets to `TF_VAR_*` in one flag.
2. **Free-tier versioning** — Full secret history and rollback at $0. Critical for 2 AM production incidents.
3. **Free-tier headroom** — 10 projects, 4 environments, 50 service tokens covers all surfaces with room to grow.
4. **Cost** — $0/mo added to infrastructure spend.
5. **Maturity** — 8 years old, established, active development.

## Key Decisions

1. **Tool: Doppler** — Free tier covers all requirements. Zero new cost.
2. **Injection pattern: Runtime** — Containers pull secrets on start via `doppler run`. No plaintext `.env` files on disk (local dev or server).
3. **Migration strategy: Incremental by surface** — Local dev first, then CI (GitHub Actions), then server runtime, then Terraform. Validate each step before proceeding.
4. **BYOK_ENCRYPTION_KEY** — Gets an offline backup regardless of Doppler migration. This is urgent and independent.
5. **Bootstrap credential** — Server needs one `DOPPLER_TOKEN` service token, provisioned via cloud-init or Terraform user-data. This is the "turtles all the way down" problem — accepted as the one manual secret.

## Migration Order

| Phase | Surface | Secrets | Risk |
|-------|---------|---------|------|
| 0 | **Doppler setup** | N/A — create account, project, environments (dev/ci/prod) | None |
| 1 | **Local dev** | ~10 (CF, Discord, X/Twitter tokens) | Low — only affects developer machine |
| 2 | **CI (GitHub Actions)** | ~25 via `secrets.*` across 14 workflow files | Medium — broken CI blocks deploys |
| 3 | **Server runtime** | ~12 in `/mnt/data/.env` | High — broken injection = production down |
| 4 | **Terraform** | 3 sensitive vars (hcloud_token, cloudflare_api_token, deploy_ssh_public_key) | Medium — only affects provisioning |

## Open Questions

1. **Terraform state backend** — Currently local-only with no encryption. Should this be migrated to a remote backend (Terraform Cloud free tier) as a prerequisite or separate initiative?
2. **Web-platform `.gitignore`** — Missing `.tfvars` exclusion (telegram-bridge has it). Fix as part of this work or separate PR?
3. **Docker runtime model** — Current pattern is `--env-file /mnt/data/.env`. Doppler runtime injection replaces this with `doppler run -- docker compose up` or an entrypoint wrapper. Which fits the existing cloud-init + systemd pattern better?
4. **LinkedIn token rotation** — The scheduled check workflow monitors expiry. Should Doppler also own monitoring, or keep the existing GH Actions workflow?

## Domain Leader Assessments

### CTO Assessment
- Identified 6 risks (R1-R6) in current state, severity HIGH to MEDIUM
- Recommended 1Password if subscribed, Doppler otherwise
- Flagged: root `.env` plaintext exposure is highest-severity current risk
- Flagged: `.gitignore` doesn't list `*.tfstate` — should be fixed regardless

### COO Assessment
- Challenged the premise: at $16/mo burn, migration cost may exceed problem cost
- Recommended starting with secrets inventory + BYOK backup before any tool
- Identified hidden costs (1Password service account: $19/mo)
- Confirmed Doppler free tier is the only $0 option with full coverage

## Institutional Learnings Applied

- **API key leak (2026-02-10):** Full git history rewrite across 10 branches. Prevention: pre-commit scanning, no plaintext on disk.
- **Env vars over CLI args (2026-02-18):** Secrets as env vars only. `chmod 600` before writing. Never echo token values.
- **CI secrets gotcha (2026-02-12):** `secrets.*` can't be used in job-level `if:` conditions. Move checks inside step scripts.
- **Token lifecycle (2026-03-02):** `claude-code-action` revokes its token in post-step cleanup. Account for token lifecycle timing.
- **Terraform best practices (2026-02-13):** `sensitive = true` on all secret vars. No defaults. Inject via `TF_VAR_*` or `-var-file`.
