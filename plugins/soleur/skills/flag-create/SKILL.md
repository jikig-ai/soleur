---
name: flag-create
description: "This skill should be used to create a runtime feature flag end-to-end across Flagsmith, server.ts, .env.example, and Doppler."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

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
(default off), `--dry-run`, `--flagsmith-only`.

`--flagsmith-only` creates **only** the Flagsmith feature for a flag that is
**already code-wired** (already in `RUNTIME_FLAGS` + `.env.example` + Doppler).
It skips the server.ts / `.env.example` / Doppler mutations **and** the "already
appears in server.ts" exit-1 precheck (which would otherwise fire precisely
because the flag is already wired). Use it to back-fill the Flagsmith feature for
a flag that shipped its code wiring in an earlier PR, before scoping it per-org
with `soleur:flag-set-role <flag> <env> on --org <orgId>`.

## Prerequisites

- Doppler authed with access to `soleur` configs `dev`, `prd`, `cli_ops`.
- Worktree of the soleur repo (script edits files in `apps/web-platform/`).
- `curl` + `python3` on PATH.

## Procedure

The agent runs only the preview:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/flag-create/scripts/create.sh" <flag-name> \
  [--description "..."] [--dev-on] [--prd-on] --dry-run
```

## Writes run in the operator's own terminal (#8486, ADR-249)

The write path asks for a typed `yes` through the operator-script library's TTY
acknowledgement. It has no skip variable and no flag. An agent's shell has no TTY,
so a write run there stops with exit `64` and `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` on
stdout, before any credential is fetched. Exit `64` is a refusal, never a success.
The agent therefore:

1. Runs the script with `--dry-run` and shows the preview. That mode needs no TTY
   and makes no writes.
2. Prints the exact write command below, in a fenced block, for the operator to run
   in their own terminal (Warp). It replaces `<WORKTREE>` with the absolute path of
   the worktree that holds this change (`git rev-parse --show-toplevel`) and
   `<ARGS>` with `<flag-name>` plus any `--description`, `--dev-on`, `--prd-on` or `--flagsmith-only` the operator chose, without `--dry-run`. It never prints a
   `${CLAUDE_PLUGIN_ROOT}` or repo-relative form. The script also edits repo files in the directory it runs from, so an operator running it from the main checkout or another worktree would land the code wiring in the wrong tree while Flagsmith and Doppler change.
3. Does not run the command, and does not run it through Claude Code's `!` prefix
   either (whether that gives the command a TTY is unmeasured, ADR-249). The
   printed command is an undone operator step under
   `wg-block-pr-ready-on-undeferred-operator-steps`: record it where the pipeline
   tracks operator steps, and do not mark a PR ready until the operator says it ran.

<!-- operator-write-command -->
```bash
cd <WORKTREE> && bash <WORKTREE>/plugins/soleur/skills/flag-create/scripts/create.sh <ARGS>
```

The operator types `yes` at the prompt. Any other answer stops the script with exit
`1` and `SOLEUR_BOOTSTRAP_ABORTED stage=ack`, before anything is written.

The script (full in [scripts/create.sh](./scripts/create.sh)):

1. **Validate name** — kebab-case, not already in `RUNTIME_FLAGS`, not in
   `ENV_FLAGS`, not already a feature in Flagsmith.
2. **Print proposed mutations** (4 lines):
   - Flagsmith: create feature `<name>` with default_enabled=false.
   - server.ts: append `"<name>": "FLAG_<NAME>"` to `RUNTIME_FLAGS`.
   - .env.example: insert `FLAG_<NAME>=0` under the runtime flags section.
   - Doppler dev + prd: `FLAG_<NAME>=<0|1>` (mirrors prd-segment initial state).
3. **Operator ack** — a typed `yes` at the TTY prompt (no flag skips it; no TTY
   means exit `64` before any credential fetch).
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
- `1` — name validation failure, or the operator did not type `yes`
  (`SOLEUR_BOOTSTRAP_ABORTED stage=ack`; nothing written).
- `2` — prerequisite missing, or a `--description` value that starts with `--`.
- `3` — Flagsmith API error.
- `4` — file edit or audit append failed.
- `5` — Doppler write failed.
- `64` — a write run with no TTY (`SOLEUR_BOOTSTRAP_INPUT_REQUIRED`): hand the
  command to the operator (above).

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
- Sibling skills (flag CRUD set): `soleur:flag-set-role` (Update), `soleur:flag-list` (Read), `soleur:flag-delete` (Delete), `soleur:user-set-role`
