---
title: "chore: document .env provisioning after removing CI env setup step"
type: feat
date: 2026-03-20
issue: "#844"
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 7
**Research sources:** Docker env var best practices docs, cloud-init 26.1 docs, BYOK key management guides, 5 institutional learnings

### Key Improvements
1. Added concrete `.env.example` file content for web-platform with grouped sections and inline comments
2. Identified `ANTHROPIC_API_KEY` as a missing required var -- the Claude Code CLI needs it but it was absent from the original var audit
3. Added BYOK key backup procedure with `openssl rand` generation command and critical data loss warning
4. Added entrypoint validation pattern -- cloud-init `runcmd` should validate `.env` is non-empty before starting containers
5. Identified `NEXT_PUBLIC_` build-time vs runtime distinction as a documentation trap that needs explicit callout

### New Considerations Discovered
- The `.env.example` should use SCREAMING_SNAKE_CASE consistently and group vars by service (Supabase, Stripe, Telegram, Claude) with section headers for scannability
- Cloud-init comment placement matters: comments inside `runcmd` YAML blocks must use `#` prefixed on their own line, not inline after commands, to avoid YAML parsing issues
- The `ANTHROPIC_API_KEY` is required by the Claude Code CLI invoked inside the telegram-bridge container but is not listed in `.env.example` -- this is a gap in the existing telegram-bridge documentation too
- Docker `--env-file` silently ignores missing variables (no error, just unset) -- the `.env.example` must clearly mark which vars cause hard failures vs degraded behavior

---

# chore: document .env provisioning after removing CI env setup step

## Overview

PR #825 removed the "Ensure telegram env vars on server" SSH step from `telegram-bridge-release.yml`. The env vars (`TELEGRAM_BOT_TOKEN`, etc.) are now assumed to exist in `/mnt/data/.env` from initial provisioning. Both cloud-init configs create an empty `/mnt/data/.env` placeholder (mode 600, owned by `deploy`), but nothing populates it with actual values. A fresh server rebuild from cloud-init would have an empty `.env`, causing containers to fail on startup.

The telegram-bridge README (`apps/telegram-bridge/README.md`) already documents the `scp .env` step (line 62-66), but:
1. The web-platform has no README or `.env.example` -- its required env vars are scattered across source files
2. Neither cloud-init file documents what `.env` keys are expected
3. There is no single "operations runbook" covering the post-provisioning manual step for either component

## Problem Statement / Motivation

**Gap:** After `terraform apply` creates a new server, the operator must manually populate `/mnt/data/.env` with secrets before containers will function. This step is undocumented for web-platform and only partially documented for telegram-bridge (in its README, not in the infra docs). If the server is ever rebuilt (disaster recovery, migration, or Terraform recreate), the operator must know exactly which env vars to set and in what format.

**Introduced by:** #825 -- the removal is correct (env vars should be provisioned once, not on every deploy), but the documentation gap needs closing.

## Proposed Solution

**Option A (recommended): Documentation-only approach**

1. Create `apps/web-platform/.env.example` listing all required env vars with descriptions
2. Add a "Server Provisioning" section to `apps/telegram-bridge/README.md` infra notes (the existing Quick Start step 6 covers initial setup, but a dedicated section for disaster recovery is clearer)
3. Add inline comments in both `cloud-init.yml` files next to the `.env` placeholder explaining what keys must be populated and pointing to `.env.example`

### Research Insights

**Docker .env best practices ([Docker Docs](https://docs.docker.com/compose/how-tos/environment-variables/best-practices/)):**
- Use `.env.example` committed to version control with placeholder values (never real secrets)
- Group variables by service with comment headers for scannability
- Use SCREAMING_SNAKE_CASE consistently
- Mark required vs optional variables explicitly -- `--env-file` silently passes through missing vars as unset, causing hard-to-debug runtime failures rather than startup errors
- Quote values containing special characters (`=`, `#`, spaces)

**Cloud-init secret provisioning ([cloud-init 26.1 docs](https://cloudinit.readthedocs.io/en/latest/topics/examples.html), [HashiCorp guide](https://www.hashicorp.com/en/resources/cloudinit-the-good-parts)):**
- Cloud-init is not designed for secret injection -- it writes to instance metadata which may be readable by other processes. The current approach (empty placeholder + manual `scp`) is the correct pattern for a single-server setup
- For future scale-out, consider an external secrets manager (Vault, AWS Secrets Manager) with an init container or boot script that fetches secrets at startup
- Documentation should include the purpose of each provisioning step, dependencies, and troubleshooting guidance for initialization failures

**Option B (future, out of scope): Terraform `sensitive_file` provisioning**

Use Terraform to write the `.env` file from variables. This is more automated but introduces sensitive values into Terraform state, requires `terraform.tfvars` to contain secrets, and conflicts with the single-provisioning design (env vars are set once, not on every apply). This option is documented for awareness but deferred -- the operational overhead of managing secrets in Terraform state outweighs the benefit for a single-server setup with infrequent reprovisioning.

## Technical Considerations

### Required env vars per component

**telegram-bridge** (from `apps/telegram-bridge/.env.example` + source audit):

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Yes | Bot API token from @BotFather |
| `TELEGRAM_ALLOWED_USER_ID` | Yes | Numeric Telegram user ID |
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key for Claude Code CLI (used inside container) |
| `SOLEUR_PLUGIN_DIR` | No | Path to Soleur plugin directory |
| `CLAUDE_MODEL` | No | Claude model (default: claude-opus-4-6) |
| `SKIP_PERMISSIONS` | No | Set `false` to disable `--dangerously-skip-permissions` |

### Research Insights

**Missing var discovered:** `ANTHROPIC_API_KEY` is required by the Claude Code CLI that the telegram-bridge spawns inside the container. It is not listed in the existing `apps/telegram-bridge/.env.example`. The bridge container will start and pass health checks without it, but every Claude Code invocation will fail with an auth error. This should be added to the existing `.env.example` as part of this PR.

**web-platform** (from source code grep of `process.env.*`):

| Variable | Required | Failure Mode | Description |
|----------|----------|-------------|-------------|
| `NEXT_PUBLIC_SUPABASE_URL` | Yes | Auth broken, API calls fail | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Yes | Auth broken, API calls fail | Supabase anonymous key |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes | Agent runner + admin ops fail | Supabase service role key |
| `STRIPE_SECRET_KEY` | Yes | Checkout broken | Stripe API secret key |
| `STRIPE_PRICE_ID` | Yes | Checkout broken | Stripe price ID for checkout |
| `STRIPE_WEBHOOK_SECRET` | Yes | Payment events lost | Stripe webhook signing secret |
| `BYOK_ENCRYPTION_KEY` | Yes (prod) | BYOK setup page crashes | 32-byte hex key for BYOK encryption |
| `ANTHROPIC_API_KEY` | Yes | Agent sessions fail | Anthropic API key for Claude Code CLI |
| `PORT` | No | Uses default 3000 | Server port (default: 3000) |
| `NODE_ENV` | No | Set by Dockerfile | Environment (default in container: `production`) |
| `WORKSPACES_ROOT` | No | Uses default `/workspaces` | Workspace directory |
| `SOLEUR_PLUGIN_PATH` | No | Uses default path | Plugin path (default: `/app/shared/plugins/soleur`) |

### Research Insights

**Failure mode column added:** Per [Docker env var management best practices](https://www.envsentinel.dev/blog/environment-variable-management-tips-best-practices), documenting what breaks when a var is missing prevents partial-provisioning surprises. Docker `--env-file` does not validate that all expected vars are present -- it silently passes through whatever is in the file.

**`NEXT_PUBLIC_` build-time caveat:** Per institutional learning `2026-03-17-nextjs-docker-public-env-vars.md`, `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` are inlined into the client-side JavaScript bundle at Docker build time via `ARG` directives. The `.env` file provides them at runtime for server-side code only (middleware, agent-runner, ws-handler). The `.env.example` must note this distinction to prevent confusion -- setting them in `.env` alone does NOT fix a client-side empty-value bug.

### Shared `.env` file

Both components on the same server use `--env-file /mnt/data/.env` (visible in `ci-deploy.sh` lines 122 and 147). This means a single `.env` file must contain vars for both components. Non-applicable vars are simply ignored by each container.

### Cloud-init creates the placeholder

Both cloud-init files already handle:
- `touch /mnt/data/.env` -- creates empty file
- `chmod 600 /mnt/data/.env` -- restricts to owner-only
- `chown -R deploy:deploy /mnt/data` -- grants deploy user ownership

The gap is: no documentation tells the operator what to put in this file.

### Research Insights

**Comment placement in cloud-init YAML:** When adding documentation comments to cloud-init `runcmd` blocks, place comments on their own lines prefixed with `#`. Do not use inline comments after commands -- some YAML parsers and cloud-init versions handle inline comments inconsistently. The existing cloud-init files already follow this pattern (e.g., `# Create .env placeholder and grant deploy user ownership of /mnt/data`).

**Ownership ordering:** Per institutional learning `2026-03-20-cloud-init-chown-ordering-recursive-before-specific.md`, the `chown -R deploy:deploy /mnt/data` must come before any specific ownership overrides. Both cloud-init files currently have the correct order -- the web-platform file applies `chown 1001:1001 /mnt/data/workspaces` after the recursive sweep. The documentation comments should not suggest reordering.

### SpecFlow edge cases

- **Edge case: partial .env** -- If only telegram-bridge vars are set but not web-platform vars, the web-platform container will start and pass the HTTP health check but crash on first Supabase/Stripe call. The `.env.example` should group vars by component to make this clear.
- **Edge case: BYOK_ENCRYPTION_KEY** -- Must be generated once and preserved across server rebuilds (it encrypts stored API keys). If lost, all BYOK keys become unrecoverable. The docs must flag this as critical.
- **Edge case: NEXT_PUBLIC_ vars at build time** -- `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` are baked into the Docker image at build time (Dockerfile ARG). The `.env` file provides them at runtime for server-side code only. This is not a provisioning concern but should be noted to avoid confusion.
- **Edge case: ANTHROPIC_API_KEY** -- Required by both containers (telegram-bridge spawns Claude Code, web-platform uses Agent SDK). Without it, containers start and health checks pass, but all Claude interactions fail. Must be prominently documented as required.

### Research Insights -- BYOK Key Management

**Key backup is critical ([IBM BYOK guide](https://www.ibm.com/think/topics/byok), [Broadcom DR guide](https://techdocs.broadcom.com/us/en/vmware-cis/cloud/vmware-cloud-on-aws/SaaS/operations-guide/about-managing-virtual-machines-in-vmware-cloud-on-aws/bring-your-own-key-for-virtual-machine-encryption/migration-and-disaster-recovery-with-byok-vm-encryption.html)):**
- Cloud providers cannot recover customer-managed encryption keys. If the `BYOK_ENCRYPTION_KEY` is lost, all encrypted data (user API keys stored via the BYOK feature) becomes permanently unrecoverable.
- The reprovisioning documentation must include: (1) a generation command for new deployments (`openssl rand -hex 32`), (2) a warning that existing keys must be preserved from the old server's `.env`, (3) a recommendation to store the key in a secure backup location (password manager, encrypted backup) separate from the server.
- Key rotation is out of scope for this PR but should be noted as a future consideration -- rotating `BYOK_ENCRYPTION_KEY` requires re-encrypting all stored API keys.

## Acceptance Criteria

- [x] `apps/web-platform/.env.example` exists with all required env vars, descriptions, failure modes, and grouping by service
- [x] `apps/telegram-bridge/.env.example` updated to include `ANTHROPIC_API_KEY`
- [x] Both `cloud-init.yml` files have inline comments next to the `.env` placeholder referencing the `.env.example` files and listing required keys
- [x] `apps/telegram-bridge/README.md` has a "Disaster Recovery" or "Reprovisioning" section that covers `.env` restoration
- [x] The shared nature of `/mnt/data/.env` (both components read it) is documented
- [x] `BYOK_ENCRYPTION_KEY` is flagged as critical with generation command and backup warning
- [x] `NEXT_PUBLIC_` build-time vs runtime distinction is documented in `.env.example`

## Test Scenarios

- Given a fresh server provisioned via `terraform apply`, when the operator follows the documentation to populate `/mnt/data/.env`, then both containers start and pass health checks
- Given the operator rebuilds the server (Terraform destroy + apply), when they follow the reprovisioning docs, then they can restore service without guessing which env vars are needed
- Given `BYOK_ENCRYPTION_KEY` is not documented, when the operator reprovisions, then existing BYOK-encrypted API keys are lost -- **prevented by documenting this key as critical with backup instructions**
- Given the `.env` file contains telegram-bridge vars but not web-platform vars, when the operator reads the `.env.example`, then the grouped layout makes the omission obvious
- Given `ANTHROPIC_API_KEY` is missing from `.env`, when either container attempts a Claude Code invocation, then the failure is traceable to the missing var via the `.env.example` documentation

### Edge Cases

- Given the operator generates a new `BYOK_ENCRYPTION_KEY` instead of restoring the old one, when users attempt to use their stored API keys, then decryption fails -- **prevented by documenting that existing keys must be preserved, not regenerated**
- Given `NEXT_PUBLIC_SUPABASE_URL` is set only in `.env` but was missing at Docker build time, when the client-side app loads, then Supabase calls fail -- **documented with explicit note that this var is baked at build time and `.env` only covers server-side usage**

## Files to Modify

1. **`apps/web-platform/.env.example`** (new) -- All web-platform env vars with descriptions, failure modes, grouped by service

   ```bash
   # apps/web-platform/.env.example
   #
   # Required environment variables for the Soleur Web Platform.
   # Copy this file to /mnt/data/.env on the production server.
   # This file is SHARED with telegram-bridge -- both containers
   # read from the same /mnt/data/.env via --env-file.
   #
   # IMPORTANT: NEXT_PUBLIC_ vars are baked into the Docker image
   # at build time. Setting them here only affects server-side code
   # (middleware, agent-runner). Client-side code uses build-time values.

   # --- Supabase ---
   NEXT_PUBLIC_SUPABASE_URL=
   NEXT_PUBLIC_SUPABASE_ANON_KEY=
   SUPABASE_SERVICE_ROLE_KEY=

   # --- Stripe ---
   STRIPE_SECRET_KEY=
   STRIPE_PRICE_ID=
   STRIPE_WEBHOOK_SECRET=

   # --- BYOK Encryption ---
   # CRITICAL: This key encrypts user-provided API keys. If lost,
   # all BYOK-encrypted keys become permanently unrecoverable.
   # Generate for new deployments: openssl rand -hex 32
   # For reprovisioning: RESTORE from the old server's .env backup.
   BYOK_ENCRYPTION_KEY=

   # --- Claude / Anthropic ---
   ANTHROPIC_API_KEY=
   ```

2. **`apps/telegram-bridge/.env.example`** -- Add `ANTHROPIC_API_KEY` (missing required var)
3. **`apps/telegram-bridge/infra/cloud-init.yml`** -- Add comments at `.env` placeholder (lines 200-204) referencing `.env.example` and listing required keys
4. **`apps/web-platform/infra/cloud-init.yml`** -- Add comments at `.env` placeholder (lines 205-209) referencing `.env.example` and listing required keys
5. **`apps/telegram-bridge/README.md`** -- Add reprovisioning section covering `.env` restoration, BYOK key warning, and shared file note

## Dependencies & Risks

- **Low risk:** Documentation-only changes, no behavioral impact
- **Dependency on #843:** The `ci-deploy.sh` deduplication is separate work; this plan does not touch deploy logic
- **Future consideration:** If the project moves to multi-server (separate telegram-bridge host), the `.env` files will split. The documentation should note this is currently a shared file on a single server.
- **Future consideration:** Key rotation for `BYOK_ENCRYPTION_KEY` requires re-encrypting all stored API keys. This is out of scope but should be noted in the documentation as a known limitation.

## References & Research

### Internal References

- Issue: #844
- Related PR: #825 (removed CI env setup step)
- Related issue: #843 (deduplicate ci-deploy.sh)
- Related plan: `knowledge-base/plans/2026-03-20-security-deploy-ssh-user-privilege-boundary-plan.md` (#832)
- Existing `.env.example`: `apps/telegram-bridge/.env.example`
- Cloud-init (telegram-bridge): `apps/telegram-bridge/infra/cloud-init.yml:200-204`
- Cloud-init (web-platform): `apps/web-platform/infra/cloud-init.yml:205-209`
- ci-deploy.sh (both components use `--env-file /mnt/data/.env`): lines 122, 147
- Learning: `knowledge-base/project/learnings/2026-03-20-cloud-init-chown-ordering-recursive-before-specific.md`
- Learning: `knowledge-base/project/learnings/2026-03-17-nextjs-docker-public-env-vars.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-ssh-forced-command-cloud-init-parity-gaps.md`
- Learning: `knowledge-base/project/learnings/2026-02-13-terraform-best-practices-research.md`

### External References

- [Docker Compose Environment Variables Best Practices](https://docs.docker.com/compose/how-tos/environment-variables/best-practices/)
- [Docker Blog: Using ARG and ENV in Dockerfiles](https://www.docker.com/blog/docker-best-practices-using-arg-and-env-in-your-dockerfiles/)
- [Environment Variable Management Best Practices 2026](https://www.envsentinel.dev/blog/environment-variable-management-tips-best-practices)
- [cloud-init 26.1 Configuration Examples](https://cloudinit.readthedocs.io/en/latest/topics/examples.html)
- [Cloud-Init: The Good Parts (HashiCorp)](https://www.hashicorp.com/en/resources/cloudinit-the-good-parts)
- [IBM: What is BYOK?](https://www.ibm.com/think/topics/byok)
- [Broadcom: Migration and Disaster Recovery with BYOK VM Encryption](https://techdocs.broadcom.com/us/en/vmware-cis/cloud/vmware-cloud-on-aws/SaaS/operations-guide/about-managing-virtual-machines-in-vmware-cloud-on-aws/bring-your-own-key-for-virtual-machine-encryption/migration-and-disaster-recovery-with-byok-vm-encryption.html)
- [Futurex: Encryption Key Management Best Practices](https://www.futurex.com/blog/controlling-the-encryption-keys-byok-byoe)
