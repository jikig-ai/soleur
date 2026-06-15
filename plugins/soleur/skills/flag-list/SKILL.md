---
name: flag-list
description: "This skill should be used to read and audit all runtime feature flags before a promotion or delete decision: Flagsmith state, server.ts code-wiring, live Doppler dev/prd values, and per-segment overrides, with drift detection."
---

# flag-list

Reads every runtime feature flag across all three sources of truth and shows
them side by side — the **Read** verb of the flag CRUD set. Use it to audit
active flags before a promotion (`flag-set-role`) or a delete (`flag-delete`).

## When to use

- Auditing active flags before promoting one dev→prd, or before deleting one.
- Detecting drift: a Flagsmith feature with no `RUNTIME_FLAGS` entry, or a
  code-wired flag missing from Flagsmith.
- Seeing a flag's blast radius (which segments/roles/orgs it targets) before a
  destructive change.

## When NOT to use

- Creating a flag → `soleur:flag-create`.
- Toggling a flag per role/org → `soleur:flag-set-role`.
- Removing a flag → `soleur:flag-delete`.

## When to use this skill vs other flag skills

The flag CRUD set: `soleur:flag-create` (Create), `soleur:flag-set-role`
(Update — per-role/per-org), **`soleur:flag-list` (Read — this)**,
`soleur:flag-delete` (Delete). Initial wiring is the `flag-bootstrap/SETUP.md`
runbook (operator documentation, not an invocable skill).

## Arguments

<arguments> #$ARGUMENTS </arguments>

Optional: `--json` (emit a JSON array instead of the formatted table).

## Prerequisites

- Doppler authed with access to `soleur` configs `dev`, `prd`, `cli_ops`.
- Worktree of the soleur repo (the script reads `server.ts`).
- `curl` + `python3` on PATH.

## Procedure

```bash
bash plugins/soleur/skills/flag-list/scripts/list.sh [--json]
```

The script (full in [scripts/list.sh](./scripts/list.sh)):

1. **Fetch Flagsmith features** — `GET /api/v1/projects/39082/features/`
   (paginated while `next` is present).
2. **Parse code-wiring** — extract `RUNTIME_FLAGS` (and `ENV_FLAGS`) keys from
   `apps/web-platform/lib/feature-flags/server.ts`.
3. **Read live Doppler values** — a single targeted `FLAG_<X>` read per flag in
   both `soleur/dev` and `soleur/prd` (never `doppler secrets download` /
   `doppler secrets`, which dump the whole config). Always on — the dev→prd
   value comparison is the audit's headline data, not an optional extra.
4. **Enumerate segment overrides** — per flag, per env, resolve which segments
   (`role-dev`, `<flag>-orgs`, …) carry an ON/OFF override (mirrors
   `flag-set-role`'s feature-state read shape).
5. **Flag drift** — Flagsmith-only features and code-only flags are surfaced
   distinctly.
6. **Render** — formatted table, or `--json` array with fields `name`,
   `env_var`, `flagsmith_id`, `default_enabled`, `code_wired`, `doppler_dev`,
   `doppler_prd`, `segments`.

`ENV_FLAGS` (build-time DCE flags like `dev-signin`) are listed under a
separate heading — they are not runtime/Flagsmith flags.

## Exit codes

- `0` — success.
- `2` — prerequisite missing (token / binaries / `server.ts`).
- `3` — Flagsmith API error.

## Sharp edges

- **Read-only.** No mutations, no WORM audit append, no `--dry-run` needed.
- The management API key is read via `doppler secrets get … -c cli_ops --plain`
  and passed only to `curl -H Authorization` — never echoed.
- A `doppler_dev`/`doppler_prd` of `unset` means the `FLAG_<X>` key is absent
  from that Doppler config (legitimate for flags wired but not yet mirrored).

## Cross-references

- ADR: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- Sibling skills: `soleur:flag-create`, `soleur:flag-set-role`, `soleur:flag-delete`
