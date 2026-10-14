---
title: "Tasks — Agent-invokable flag-list / flag-delete + cron-list / cron-delete (#5318)"
plan: knowledge-base/project/plans/2026-06-15-feat-agent-invokable-flag-crud-plan.md
issue: 5318
lane: cross-domain
---

# Tasks — #5318 flag/cron CRUD completeness

Derived from the finalized (deepened) plan. Source of truth: the plan's Implementation Phases + Acceptance Criteria.

## Phase 0 — Preconditions (live verification, no code)

- [x] 0.1 Flagsmith DELETE live probe against a throwaway feature: confirm `DELETE /projects/39082/features/{id}/` → 204; re-GET → `results: []`; POST same name → record 201 vs 400 (name-reuse); confirm key has `Delete feature` perm. Pin verified-at + outcome in this spec.
- [x] 0.2 Confirm `doppler secrets delete <NAME> -p soleur -c dev --yes > /dev/null` (stdout redirect mandatory) and the `doppler secrets get ... --plain 2>&1 | grep -q 'not found'` verify form.
- [x] 0.3 Re-measure budget headroom (Node one-liner). Plan-time baseline: 2071/2071, headroom 0.

## Phase 1 — flag-list skill (Read)

- [x] 1.1 Create `plugins/soleur/skills/flag-list/SKILL.md` (frontmatter: name=flag-list, third-person description ~30 words, markdown-linked scripts ref).
- [x] 1.2 Create `plugins/soleur/skills/flag-list/scripts/list.sh`: reuse create.sh constants + `fs_api`; `GET /projects/39082/features/` (paginate if `next`); parse server.ts RUNTIME_FLAGS keys; emit drift rows (Flagsmith-only / code-only).
- [x] 1.3 Always read Doppler dev+prd per flag (single targeted `FLAG_<X>` key; never `doppler secrets download`/`secrets`). NO `--with-doppler` flag.
- [x] 1.4 Enumerate per-flag segment/role override state (resolve via `GET /projects/39082/segments/` + per-env feature-states, mirror flip.sh `resolve_segment_id`).
- [x] 1.5 `--json` array: name, env_var, flagsmith_id, default_enabled, code_wired, doppler_dev, doppler_prd, segments[]. Default → formatted table. List ENV_FLAGS under a separate "build-time env flags (DCE)" heading.
- [x] 1.6 Add `## When to use this skill vs ...` disambiguation (flag-create/flag-set-role/flag-list/flag-delete/flag-bootstrap).

## Phase 2 — flag-delete skill (Delete, inverse of create.sh)

- [x] 2.1 Create `plugins/soleur/skills/flag-delete/SKILL.md` (frontmatter + disambiguation + per-exit-code recovery-state doc).
- [x] 2.2 Create `plugins/soleur/skills/flag-delete/scripts/delete.sh`. Step order (exit map 0/1/2/3/4/5):
  - [x] 2.2.0 Name validation `^[a-z][a-z0-9-]*[a-z0-9]$` FIRST, before any interpolation (P0-2).
  - [x] 2.2.1 Validate flag PRESENT in server.ts RUNTIME_FLAGS; derive ENV_VAR (create.sh:42).
  - [x] 2.2.2 Resolve feature_id via `GET ?q=<name>` + EXACT-name filter (`f['name']==NAME`) before DELETE (P2-2). Absent → warn, continue code cleanup.
  - [x] 2.2.3 Propose + `--dry-run` + typed-`yes` confirmation (no default `--yes`/`--force` bypass).
  - [x] 2.2.4 WORM audit append BEFORE mutation (action=delete, target=global); abort exit 4 on failure.
  - [x] 2.2.5 `DELETE /projects/39082/features/{id}/` expect 204 (cascade handles overrides); non-204 → exit 3.
  - [x] 2.2.6 Strip the `"<name>": "FLAG_<X>",` line from server.ts RUNTIME_FLAGS (python regex).
  - [x] 2.2.7 Delete `^FLAG_<X>=` line from `.env.example`.
  - [x] 2.2.8 Remove `["<name>"]="FLAG_<X>"` entry from `flag-set-role/scripts/flip.sh` FLAG_ENV_VARS map (5th site).
  - [x] 2.2.9 `doppler secrets delete "$ENV_VAR" -c dev --yes > /dev/null` (anchored) + same for prd; verify via `grep -q 'not found'`; exit 5 on failure. Never echo/tee.
  - [x] 2.2.10 Outcome audit / per-exit-code recovery doc (full vs partial delete).
  - [x] 2.2.11 Commit hint.

## Phase 3 — cron-list / cron-delete (thin-pointer skills)

- [x] 3.1 Create `plugins/soleur/skills/cron-list/SKILL.md` — pointer to `schedule`'s `### list` steps; no hardcoded count (examples use `git ls-files '.github/workflows/scheduled-*.yml'`); V1-limitation note.
- [x] 3.2 Create `plugins/soleur/skills/cron-delete/SKILL.md` — pointer to `schedule`'s `### delete <name>` steps; one-time self-neutralization caveat.
- [x] 3.3 Both: `## When to use this skill vs ...` naming schedule (create) / cron-list (read) / cron-delete (delete) / trigger-cron (run-now). Do NOT delete list/delete prose from schedule/SKILL.md (canonical source) — cross-link.

## Phase 4 — Budget + release docs

- [x] 4.1 Author the 4 descriptions tight (~30 routing words each); bump `SKILL_DESCRIPTION_WORD_BUDGET` (components.test.ts:15) by EXACT sum, with a `#5318` bump-note comment.
- [x] 4.2 Run `bash scripts/sync-readme-counts.sh`; update `plugin.json` description counts (+4 skills); do NOT touch `version`.
- [x] 4.3 Eleventy build; verify `component-card` count in `_site/pages/skills.html` reflects +4.

## Phase 5 — Verify ACs + PR

- [x] 5.1 Run AC1–AC9 (see plan). `bun test plugins/soleur/test/components.test.ts` green.
- [x] 5.2 Re-run Open Code-Review Overlap gate.
- [x] 5.3 File deferral issues (flag-get, user-role CRUD, agent/hook CRUD, create-side flip.sh append).
- [x] 5.4 PR: `## Changelog` + `semver:minor` + `Closes #5318`.
