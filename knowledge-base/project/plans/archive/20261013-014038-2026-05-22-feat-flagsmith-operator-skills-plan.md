---
name: feat-flagsmith-operator-skills
title: Flagsmith operator skills + segment bootstrap (PR #2 of two-PR Flagsmith adoption)
date: 2026-05-22
branch: feat-flagsmith-operator-skills
predecessor: knowledge-base/project/plans/2026-05-22-feat-flagsmith-adoption-plan-v2.md
predecessor-pr: 4331
status: approved
---

# Plan: Flagsmith operator skills + segment bootstrap

## Context

PR #4331 shipped the identity-aware resolution path: `users.role` column, per-role cache, `getRuntimeFlag(name, identity)`, `FeatureFlagProvider` + `useFeatureFlag`. The system can resolve runtime flags per role TODAY in prd, but:

1. Flagsmith has no `role-prd` / `role-dev` segments — every identity-flag call returns the env-level default (currently effectively the same for all roles).
2. No tooling exists for the operator (Claude) to create flags, flip segments, or assign user roles. The only path is direct `curl` to the Flagsmith Admin API.

This PR closes the loop by shipping the operator interface.

## Discovery (live API state captured 2026-05-22)

- **Project:** `web-platform` (id `39082`)
- **Environments:** Development (id `90722`, api_key `PRHE5c9eWXYuRDFFPtbFxj`), Production (id `90721`, api_key `QMEpRRzFx8kpEcY7nZmhJd`)
- **Features:** `kb-chat-sidebar` (id `209129`), `command-center-soleur-go` (id `209130`, dead — to be archived)
- **Segments:** none (this PR creates `role-prd` + `role-dev`)
- **Admin API token:** lives in Doppler `soleur / cli_ops` as `FLAGSMITH_MANAGEMENT_API_KEY`. Format: prefix `Authorization: Api-Key <token>`. Verified: returns 200 on `GET /api/v1/projects/?organisation=29821`.

## Goals

- **G1**: One-time bootstrap script creates the two segments (`role-prd` matches identity with trait `role=prd` OR no identity; `role-dev` matches `role=dev`).
- **G2**: `soleur:flag-set-role <flag> <role> <on|off>` — flips one segment's enablement on the named flag. If `role=prd` is being mutated, also `doppler secrets set FLAG_<X>=<0|1>` in dev + prd configs so env-var fallback stays in sync. **Rejects** `dev off` when `prd on` (fallback-fidelity invariant from ADR-038 v2).
- **G3**: `soleur:user-set-role <email|userId> <prd|dev>` — updates `public.users.role` via service-role Supabase + writes the `role` trait to the Flagsmith identity for the same userId.
- **G4**: `soleur:flag-create <name>` — interactive create. Asks: description + initial state per role (default both off). Calls Admin API to create the feature with default-off, then applies per-segment overrides. Edits `RUNTIME_FLAGS` in `lib/feature-flags/server.ts`, adds env var to `.env.example`, runs `doppler secrets set` for dev + prd to mirror initial prd state.
- **G5**: All three skills follow the `admin-ip-refresh` shape: SKILL.md with phased procedure, scripts/ holding pure-bash imperatives, references/ holding the full procedure for "read the SKILL.md inline" mode.
- **G6**: Archive the dead `command-center-soleur-go` feature as part of bootstrap (one less footgun for future audits).

## Non-goals

- Multi-environment flag overrides beyond dev + prd.
- Per-identity overrides (the V1 cache rejects them by design — see PR #4331 review).
- Webhook listeners for Flagsmith → Doppler sync (skill is the only mutator; manual UI changes by an operator break the contract).
- Reverse rollback (e.g. moving a flag from dev-only back to off) — supported, just no special tooling.

## Architecture

### Doppler config layout

```
soleur (project)
├── dev          (env: dev)      → FLAGSMITH_ENVIRONMENT_KEY = PRHE5c9eWXYuRDFFPtbFxj (server SDK key, app reads)
├── prd          (env: prd)      → FLAGSMITH_ENVIRONMENT_KEY = QMEpRRzFx8kpEcY7nZmhJd
└── cli_ops      (env: cli)      → FLAGSMITH_MANAGEMENT_API_KEY = We9lyPiT.… (admin API, skills only)
```

`cli_ops` is intentionally separate so app secrets never see the admin key.

### Skill anatomy

Each of the three skills follows this shape:

```
plugins/soleur/skills/<skill-name>/
├── SKILL.md                       (yaml frontmatter + phased procedure)
├── references/
│   └── procedure.md               (full step-by-step for "deep" mode)
└── scripts/
    ├── <core>.sh                  (curl calls + Doppler mutations)
    └── <core>.test.sh             (bash-test fixtures with mocked curl)
```

### Skill contracts (one-line each)

- `soleur:flag-create <name> [--dev-on] [--prd-on]` — create feature in Flagsmith + register in `RUNTIME_FLAGS` + add env var + mirror Doppler.
- `soleur:flag-set-role <flag> <role> <on|off>` — flip per-segment override; on `role=prd` flip, also mirror Doppler.
- `soleur:user-set-role <email-or-id> <prd|dev>` — Supabase users.role write + Flagsmith identity trait write.

All skills require explicit operator ack before any write (`hr-menu-option-ack-not-prod-write-auth`). All write paths are idempotent.

## Implementation stages

### Stage 1 — Bootstrap script (one-shot)

`plugins/soleur/skills/flag-bootstrap/scripts/bootstrap.sh`:
1. Verify `FLAGSMITH_MANAGEMENT_API_KEY` is set (else exit 2 with hint).
2. Idempotently create segment `role-prd` (project 39082) with rules: `role IS NOT_EQUAL "dev"` (matches `prd` AND missing-trait paths). Return segment id.
3. Idempotently create segment `role-dev` with rules: `role EQUAL "dev"`. Return segment id.
4. For existing feature `kb-chat-sidebar`: idempotently create segment overrides for both segments with `enabled: false` initial state (operator flips later via `flag-set-role`).
5. Archive `command-center-soleur-go` feature (DELETE or set archived: true depending on API support).
6. Print final state summary.

Idempotency: skill greps `GET /projects/{id}/segments/` for existing names before POSTing.

### Stage 2 — `soleur:flag-set-role` skill

The most-used skill. Bash script:
1. Validate args: flag name in `RUNTIME_FLAGS`, role in {prd, dev}, value in {on, off}.
2. Resolve feature id + segment id via Admin API.
3. Fetch current per-segment state (both segments). Compute proposed state.
4. **Enforce fallback-fidelity rule**: if proposed change = `dev off` AND current `prd on`, exit 1 with "Flip prd off first to preserve fallback parity (see ADR-038 v2 §Fallback semantics)".
5. Print pre/post matrix + diff. Wait for literal `yes` ack.
6. PUT to `/api/v1/features/feature-segments/{id}/` (or POST if first override) to flip the segment.
7. If role=prd, also `doppler secrets set FLAG_<X>=<0|1> -p soleur -c dev` AND `-c prd` from a 0600 temp file.
8. Re-fetch and assert post-state matches. Exit 0.

### Stage 3 — `soleur:user-set-role` skill

1. Validate args: identifier (email or UUID), role in {prd, dev}.
2. Resolve identifier → userId via Supabase service-role select if email given.
3. Pre-check: read current `users.role`. If already == target, print "no change" and exit 0.
4. Print pre/post + wait for `yes` ack.
5. `update users set role=<target> where id=<uuid>` via service-role Supabase client (raw curl to PostgREST, or via psql shim).
6. Write Flagsmith identity trait: `POST /api/v1/identities/{userId}/traits/` with `trait_key=role`, `trait_value=<target>`.
7. Re-read both sides to confirm. Exit 0.

### Stage 4 — `soleur:flag-create` skill

1. Validate flag name (kebab-case, not already in `RUNTIME_FLAGS`).
2. Prompt for description + initial state (default `--prd-off --dev-off`).
3. Print proposed mutations (4 lines: Flagsmith feature, RUNTIME_FLAGS edit, .env.example edit, Doppler dev+prd writes). Wait `yes` ack.
4. Create feature via Admin API: `POST /api/v1/projects/39082/features/` with `default_enabled=false`.
5. Resolve segment IDs (role-prd, role-dev). For each: if requested-on, create segment override with `enabled: true`.
6. Edit `apps/web-platform/lib/feature-flags/server.ts`:
   - Add entry to `RUNTIME_FLAGS` const: `"<name>": "FLAG_<NAME>"`.
7. Edit `apps/web-platform/.env.example`: add `FLAG_<NAME>=<0|1>` line under the runtime flags section.
8. Run `doppler secrets set FLAG_<NAME>=<0|1> -p soleur -c dev -c prd` (mirrors prd-segment initial state).
9. Print summary + next-action hint ("commit the server.ts + .env.example changes").

### Stage 5 — Tests

Each skill ships a test script that runs the bash with `MOCK_CURL=1` and asserts:
- Argument validation rejects bad input.
- Idempotency: second invocation with same state is a no-op.
- Operator-ack gate blocks writes when ack absent.
- Fallback-fidelity rule rejects `dev off` while `prd on`.
- Doppler mirror fires only on `role=prd` flips.

Mock pattern: write `mock-curl` shim that records calls + returns canned fixture JSON. Test runner: bash with `set -euo pipefail`.

### Stage 6 — ADR-038 amendment + plugin README

ADR-038 amendment: append a "Phase 4 PR #2 shipped" section to the Status block. Update Operational notes with the cli_ops config name (already pinned in v2). Confirm "every flag flows through a segment — no per-identity overrides" still holds (it does).

Update `plugins/soleur/README.md` with the three new skills (or run `scripts/sync-readme-counts.sh` per ship convention).

### Stage 7 — Run bootstrap against prd

After PR merges, operator runs the bootstrap script once. This creates the two segments + archives the dead flag. Verify segments exist via `curl GET /projects/39082/segments/`.

## Acceptance criteria

- [ ] **AC1**: `bash plugins/soleur/skills/flag-bootstrap/scripts/bootstrap.sh` is idempotent — running twice produces no API mutations on second run.
- [ ] **AC2**: After bootstrap, `GET /api/v1/projects/39082/segments/` returns exactly 2 segments: `role-prd` and `role-dev`.
- [ ] **AC3**: `command-center-soleur-go` feature is archived (or deleted) post-bootstrap.
- [ ] **AC4**: `bash plugins/soleur/skills/flag-set-role/scripts/flip.sh kb-chat-sidebar dev on` flips Flagsmith dev-segment for the feature AND does NOT mutate Doppler (verified by `doppler secrets get FLAG_KB_CHAT_SIDEBAR -p soleur -c prd` unchanged).
- [ ] **AC5**: `... flip.sh kb-chat-sidebar prd on` flips prd-segment AND runs `doppler secrets set FLAG_KB_CHAT_SIDEBAR=1` in dev + prd.
- [ ] **AC6**: `... flip.sh kb-chat-sidebar dev off` is REJECTED with exit 1 + clear message when current `prd on`.
- [ ] **AC7**: `bash .../user-set-role.sh harry@example.com dev` (or with UUID) updates `public.users.role` AND writes Flagsmith identity trait. Second invocation with same value is a no-op.
- [ ] **AC8**: `bash .../flag-create.sh foo --dev-on` creates Flagsmith feature `foo`, segment override on `role-dev`=true, adds `"foo": "FLAG_FOO"` to `RUNTIME_FLAGS`, adds `FLAG_FOO=0` to `.env.example`, writes `FLAG_FOO=0` to Doppler dev+prd.
- [ ] **AC9**: All four skills' bash test suites pass (`bash scripts/test-all.sh` or per-skill `*.test.sh`).
- [ ] **AC10**: ADR-038 amended with PR #2 reference; plugin README updated with 3 new skills.

## Rollback strategy

- Code: single revert PR.
- Doppler: `cli_ops` config can be deleted (won't affect app).
- Flagsmith: segments + archived feature can be restored manually via UI.
- Skills: removing from `plugins/soleur/skills/` is a code revert; bootstrap-once side effects (segments) persist harmlessly.

## Out of scope (Phase 5 follow-on, not this PR)

- Webhook from Flagsmith → Doppler for out-of-band UI changes.
- Multi-region Flagsmith setup (currently edge.api.flagsmith.com).
- Bulk role promotion (e.g. "all internal staff → dev"); use individual `user-set-role` calls.
- Audit log surfacing in Sentry — skills already log to stdout/stderr; cumulative audit is the chat transcript.
