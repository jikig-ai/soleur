# Tasks: document .env provisioning (#844)

## Phase 1: Setup

- [ ] 1.1 Read existing `apps/telegram-bridge/.env.example` for reference format
- [ ] 1.2 Grep web-platform source for all `process.env.*` references to build complete var list
- [ ] 1.3 Verify `ANTHROPIC_API_KEY` is used by both containers (telegram-bridge spawns Claude Code, web-platform uses Agent SDK)

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/.env.example` with all required env vars grouped by service (Supabase, Stripe, BYOK, Claude/Anthropic), including failure mode comments and NEXT_PUBLIC_ build-time caveat
- [ ] 2.2 Update `apps/telegram-bridge/.env.example` -- add missing `ANTHROPIC_API_KEY` with description
- [ ] 2.3 Update `apps/telegram-bridge/infra/cloud-init.yml` -- add inline comments at `.env` placeholder (lines 200-204) referencing `.env.example` and listing required keys
- [ ] 2.4 Update `apps/web-platform/infra/cloud-init.yml` -- add inline comments at `.env` placeholder (lines 205-209) referencing `.env.example` and listing required keys
- [ ] 2.5 Update `apps/telegram-bridge/README.md` -- add "Reprovisioning / Disaster Recovery" section covering: `.env` restoration from backup, BYOK key preservation warning with `openssl rand -hex 32` generation command for new deploys, shared `.env` file note, and ANTHROPIC_API_KEY requirement

## Phase 3: Validation

- [ ] 3.1 Verify `.env.example` contains all vars found in source grep (no missing keys)
- [ ] 3.2 Verify cloud-init comments reference correct file paths
- [ ] 3.3 Verify BYOK_ENCRYPTION_KEY has critical backup warning in both `.env.example` and README
- [ ] 3.4 Verify NEXT_PUBLIC_ build-time distinction is documented
- [ ] 3.5 Run compound checks
