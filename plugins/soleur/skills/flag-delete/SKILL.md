---
name: flag-delete
description: "This skill should be used to delete a runtime feature flag end-to-end (the inverse of flag-create): removes it from Flagsmith, server.ts RUNTIME_FLAGS, .env.example, the flag-set-role flip.sh map, and Doppler dev+prd, with a WORM audit and typed-yes guardrail."
---

# flag-delete

Removes a runtime feature flag from **all five** sites — the exact inverse of
`flag-create`, the **Delete** verb of the flag CRUD set. Destructive: gated by a
dry-run, a typed-`yes` confirmation, and a WORM audit row written before any
mutation.

## When to use

- Retiring a runtime flag whose rollout is complete (or was abandoned).
- Before deleting, run `soleur:flag-list` to see the flag's blast radius
  (which segments/roles/orgs it targets — all destroyed by the Flagsmith
  cascade).

## When NOT to use

- Turning a flag off without removing it → `soleur:flag-set-role <flag> <env> off`.
- Removing a build-time DCE flag (`dev-signin`) → hand-edit `ENV_FLAGS` in
  `server.ts` + `.env.example` (it has no Flagsmith feature).

## When to use this skill vs other flag skills

The flag CRUD set: `soleur:flag-create` (Create), `soleur:flag-set-role`
(Update — per-role/per-org), `soleur:flag-list` (Read),
**`soleur:flag-delete` (Delete — this)**. Initial wiring is the
`flag-bootstrap/SETUP.md` runbook (operator documentation, not an invocable
skill).

## Arguments

<arguments> #$ARGUMENTS </arguments>

Required positional: `<kebab-flag-name>`.
Optional: `--dry-run` (enumerate the 5 mutations and exit before any change).

There is intentionally **no** `--yes`/`--force` bypass — the typed-`yes` prompt
always gates a real delete.

## Prerequisites

- Doppler authed with access to `soleur` configs `dev`, `prd`, `cli_ops`.
- Worktree of the soleur repo (the script edits `apps/web-platform/` + `flip.sh`).
- `curl` + `python3` + `jq` on PATH.

## Procedure

```bash
bash plugins/soleur/skills/flag-delete/scripts/delete.sh <flag-name> [--dry-run]
```

The script (full in [scripts/delete.sh](./scripts/delete.sh)) deletes from **5
sites** (the issue's 4-site framing misses the `flip.sh` map):

1. **Flagsmith feature** — `DELETE /api/v1/projects/39082/features/{id}/` →
   HTTP 204. The DB cascade removes all segment + identity overrides; no manual
   pre-deletion needed. The feature_id is resolved by an **exact** `name ==`
   match (the `?q=` filter is substring, so a bare pick could delete the wrong
   feature).
2. **server.ts** — strip the `"<name>": "FLAG_<X>"` entry from `RUNTIME_FLAGS`.
3. **.env.example** — remove the `FLAG_<X>=` line.
4. **flip.sh** — remove the `["<name>"]="FLAG_<X>"` entry from the
   `flag-set-role` `FLAG_ENV_VARS` map (a stale entry lets `flag-set-role` try
   to flip a deleted flag).
5. **Doppler** — delete the secret in `soleur/dev` AND `soleur/prd` (each delete
   line redirects stdout to `/dev/null` — the Doppler delete command otherwise
   prints the full remaining config).

Order: name-validate → confirm flag present in `RUNTIME_FLAGS` → resolve
Flagsmith id → propose/dry-run/typed-`yes` → **WORM audit (action `archive`)
before any mutation** → Flagsmith DELETE → code edits → Doppler deletes →
verify deletion.

## Exit codes

- `0` — success / dry-run / operator aborted at the prompt.
- `1` — name validation failure (or flag not in `RUNTIME_FLAGS`).
- `2` — prerequisite missing.
- `3` — Flagsmith API error (non-204 DELETE).
- `4` — file edit or audit append failed.
- `5` — Doppler delete failed.

## Recovery from a partial delete

The 5 sites fail independently. The exit code + stderr message identify how far
the delete got, so a partial state is recoverable:

- **exit 3** — nothing mutated (Flagsmith DELETE is the first mutation; a
  non-204 means no code/Doppler change). Re-run is safe.
- **exit 4, "FATAL: audit RPC …"** — pre-mutation: the WORM append failed
  before the Flagsmith DELETE, so nothing changed. Re-run is safe.
- **exit 4, server.ts/.env.example/flip.sh edit message** — the Flagsmith
  feature is gone but a code edit failed. Half-deleted: finish the remaining
  edits + Doppler deletes by hand, or re-run (the code-cleanup steps are
  idempotent — each is a no-op if already removed).
- **exit 5** — Flagsmith + all code files done; a Doppler delete failed. Re-run
  (idempotent) or remove `FLAG_<X>` from Doppler dev/prd by hand.

A clean exit `0` is the full-delete signal. The WORM `action` enum (migration
071: `on`/`off`/`create`/`archive`) has no "delete" value — `archive` is the
sanctioned flag-removed action, so no schema change is needed.

## Sharp edges

- **Destructive + edits source files.** Run from a clean worktree and review
  the diff (server.ts + .env.example + flip.sh) before committing.
- The Flagsmith name is **reusable** after delete (the soft-delete unique index
  ignores deleted rows — verified live 2026-06-15), so a create→delete→recreate
  round-trip works.
- The management API key is read via `doppler secrets get … -c cli_ops --plain`
  and passed only to `curl -H Authorization` — never echoed.

## Cross-references

- ADR: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- Inverse skill: `soleur:flag-create`. Sibling skills: `soleur:flag-list`, `soleur:flag-set-role`.
