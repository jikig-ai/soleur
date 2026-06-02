---
date: 2026-06-02
category: best-practices
module: web-platform/byok
related: [4825, 4824]
related_adrs: [ADR-048]
tags: [byok, credentials, oauth, structural-boundary, migration, test-mocks]
---

# Two-row-by-provider credential model + lease-accessor-rename test sweep

## Problem

Add a second auth credential (operator Claude Code subscription `oauth_token`)
to a BYOK system where 6 consumers split across two incompatible transports
(raw-REST `x-api-key` cannot authenticate an OAuth token; only the Agent-SDK
subprocess can). A single discriminator column on the existing
`(user_id,'anthropic')` row can't hold both secrets, and injecting both auth
env vars silently bills the API account ("both-keys trap").

## Solution — structural boundary over runtime guard

**Two rows by provider, no `credential_type` column.** `provider='anthropic'`
(api_key) + `provider='anthropic_oauth'` (oauth_token); the existing
`(user_id, provider)` UNIQUE gives at-most-one-of-each for free; the provider
value IS the discriminator. The credential read splits into two lease
accessors that query *different rows*:
- `getRestApiKey()` → `provider='anthropic'` ONLY → **structurally cannot**
  return an oauth token (it lives in a row the query never reads). The
  oauth→`x-api-key` leak is impossible by construction, not by a runtime check
  that can regress.
- `getAgentCredential()` → prefer `anthropic_oauth` (date/owner/kill-switch
  gates fire HERE, the sole reader), fall back to `anthropic`; returns
  `{value, scheme}`. `buildAgentEnv` branches on `scheme`, sets exactly one
  auth var (deletes the other), exhaustive `: never` rail.

## Key Insight

When a security invariant ("X can never reach Y") can be encoded as
*data-shape separation* — X and Y live in rows/tables a given accessor
physically never queries — prefer that over a runtime `if`. A structural
boundary can't be regressed by a future edit the way a guard can; the review
agents (architecture + security) both rated it sound *because* it's
constructional. Centralize the few gates that remain (date/owner/kill-switch)
at the single accessor that reads the gated row, so there is one chokepoint to
audit. Write-path defense-in-depth: a `SECURITY DEFINER` RPC with the provider
**hardcoded** (not a parameter) so a regressed caller can't overwrite the
sibling row.

## Verification without dev drift — transactional dry-run

The migration's unmerged-apply gate (run-migrations.sh, #4241) correctly
*blocks* applying a feature-branch migration to shared dev. To satisfy a
pre-merge "DEV apply" AC without leaving drift, run a **transactional
dry-run**: `BEGIN; <up>; <assertions>; <down>; <assertions>; ROLLBACK;` via
node-pg against the session-mode pooler. This validates the SQL against the
*real* dev schema (constraint name exists, UNIQUE for ON CONFLICT exists, RPC
grants apply against Supabase default-privileges) and proves down reverses —
all rolled back. The real apply runs via the deploy pipeline on merge.

## Session Errors

1. **node-pg ESM import** — `import { Client } from "pg"` → "Named export
   'Client' not found" (pg is CJS). **Recovery:** `import pg from "…/pg/lib/index.js"; const { Client } = pg`. **Prevention:** for CJS deps under an `.mjs` script, default-import then destructure.
2. **Supabase pooler TLS self-signed chain** — node-pg `ssl:{rejectUnauthorized:true}` → `SELF_SIGNED_CERT_IN_CHAIN`; a security hook also warns on disabling verification. **Recovery:** the project's canonical migration runner (`run-migrations.sh`) connects via `psql` with default `sslmode` (encrypt-only, NO chain verification) — a transient, read-only, rolled-back dry-run at parity with that posture is acceptable; documented the rationale inline in the throwaway (uncommitted) script. **Prevention:** for a one-shot dry-run against the Supabase pooler, match the project's established `psql`/`sslmode` posture; do NOT commit a TLS-disabled client into the repo (use the canonical runner for committed paths).
3. **Bash CWD non-persistence** — `cd …/migrations` in one call, follow-up failed "No such file or directory". **Recovery:** absolute paths. **Prevention:** the Bash tool does not persist CWD across calls; always absolute-path or chain `cd && cmd` in one call.
4. **Lease-accessor rename broke 3 test-mock doubles** — renaming `getApiKey`→`getRestApiKey`/`getAgentCredential` broke the lease stub in `cc-dispatcher-real-factory`, `agent-on-spawn-requested-leader-loop`, AND `cc-dispatcher-prefill-guard`; the third surfaced only in the full-suite run, not the targeted runs. **Recovery:** updated each `vi.mock("@/server/byok-lease")` stub + one `toHaveBeenCalledWith` assertion. **Prevention:** when renaming/replacing a lease (or any widely-mocked module) accessor, `grep -rn "<oldName>" apps/web-platform/test/` up front and sweep every mock in the same edit cycle — the full suite is the only thing that catches the stragglers.
5. **Full-suite background "exit 0" masked 10 failures** — a `run_in_background` `vitest run > log; rc=$?` reported exit 0 while the suite had failures. **Recovery:** grepped the log's `Test Files`/`Tests` summary, found the failing file. **Prevention:** never trust the background wrapper's exit echo for a test runner; always grep the captured log's summary line (mirrors the existing `test-all` tail-masking rule).

## Prevention summary

- Renamed widely-mocked accessor → grep all test mocks first (error #4).
- Direct-pg dry-run against Supabase pooler → match the project's `psql`/`sslmode` posture; transactional + ROLLBACK to avoid dev drift (error #2).
- Trust the test-runner log summary, not a background wrapper's exit code (error #5).
