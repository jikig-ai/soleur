# Tasks: document .env provisioning (#844)

## Phase 1: Setup

- [ ] 1.1 Read existing `apps/telegram-bridge/.env.example` for reference format
- [ ] 1.2 Grep web-platform source for all `process.env.*` references to build complete var list

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/.env.example` with all required env vars grouped by service (Supabase, Stripe, BYOK, optional)
- [ ] 2.2 Update `apps/telegram-bridge/infra/cloud-init.yml` -- add inline comments at `.env` placeholder (lines 200-204) referencing `.env.example` and listing required keys
- [ ] 2.3 Update `apps/web-platform/infra/cloud-init.yml` -- add inline comments at `.env` placeholder (lines 205-209) referencing `.env.example` and listing required keys
- [ ] 2.4 Update `apps/telegram-bridge/README.md` -- add "Reprovisioning / Disaster Recovery" section covering `.env` restoration, BYOK key preservation warning, and shared `.env` file note

## Phase 3: Validation

- [ ] 3.1 Verify `.env.example` contains all vars found in source grep (no missing keys)
- [ ] 3.2 Verify cloud-init comments reference correct file paths
- [ ] 3.3 Run compound checks
