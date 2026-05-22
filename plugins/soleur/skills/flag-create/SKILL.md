---
name: flag-create
description: "This skill should be used to create a runtime feature flag end-to-end across Flagsmith, server.ts, .env.example, and Doppler."
---

# flag-create

Creates a new runtime feature flag in Flagsmith **and** wires it into the
codebase + Doppler in one step. Use this instead of the Flagsmith UI when
adding a flag that the app needs to read.

## When to use

- Adding a new runtime flag (server-side resolution path; client consumes
  via `useFeatureFlag()` after rebuild).

## When NOT to use

- Adding an env-only DCE flag (like `dev-signin`) — those don't go through
  Flagsmith; just hand-edit `ENV_FLAGS` in `server.ts` + `.env.example`.
- Toggling an existing flag → use `soleur:flag-set-role`.

## Arguments

<arguments> #$ARGUMENTS </arguments>

Required positional: `<kebab-flag-name>`.
Optional: `--description "<text>"`, `--dev-on` (default off), `--prd-on`
(default off), `--dry-run`.

## Prerequisites

- Doppler authed with access to `soleur` configs `dev`, `prd`, `cli_ops`.
- Worktree of the soleur repo (script edits files in `apps/web-platform/`).
- `curl` + `python3` on PATH.

## Procedure

```bash
bash plugins/soleur/skills/flag-create/scripts/create.sh <flag-name> \
  [--description "..."] [--dev-on] [--prd-on] [--dry-run]
```

The script (full in [scripts/create.sh](./scripts/create.sh)):

1. **Validate name** — kebab-case, not already in `RUNTIME_FLAGS`, not in
   `ENV_FLAGS`, not already a feature in Flagsmith.
2. **Print proposed mutations** (4 lines):
   - Flagsmith: create feature `<name>` with default_enabled=false.
   - server.ts: append `"<name>": "FLAG_<NAME>"` to `RUNTIME_FLAGS`.
   - .env.example: insert `FLAG_<NAME>=0` under the runtime flags section.
   - Doppler dev + prd: `FLAG_<NAME>=<0|1>` (mirrors prd-segment initial state).
3. **Operator ack** — literal `yes`.
4. **Create feature in Flagsmith** —
   `POST /api/v1/projects/39082/features/` with `name`, `description`,
   `default_enabled: false`.
5. **Apply segment overrides** (if `--dev-on` or `--prd-on`) — for each
   env, push a v2 version with `feature_states_to_create` setting the
   target segment's enabled state to true. Same pattern as
   `soleur:flag-set-role`.
6. **Edit files** — append `RUNTIME_FLAGS` entry; append `FLAG_<NAME>=<0|1>`
   to `.env.example`.
7. **Mirror Doppler** — `doppler secrets set FLAG_<NAME>=<0|1>` in dev + prd.
8. **Print next-action hint** — "commit `server.ts` + `.env.example` so
   the resolution path can read the new flag".

## Exit codes

- `0` — success / dry-run.
- `1` — name validation failure.
- `2` — prerequisite missing.
- `3` — Flagsmith API error.
- `4` — file edit failed.
- `5` — Doppler write failed.

## Sharp edges

- The skill edits source files. Run from a clean worktree where you're
  prepared to commit the changes. Skill prints the `git diff` after.
- New flag's identifier sent to Flagsmith uses the same `role:<role>`
  cache pattern as existing flags (see
  `apps/web-platform/lib/feature-flags/server.ts`); no per-user behavior.
- This skill does NOT create a CI verify probe or test for the new flag.
  Add one in the PR that consumes the flag.

## Cross-references

- ADR: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- Sibling skills: `soleur:flag-set-role`, `soleur:user-set-role`
