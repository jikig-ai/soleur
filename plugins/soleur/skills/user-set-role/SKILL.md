---
name: user-set-role
description: "This skill should be used to promote or demote a user's flag-targeting role across Supabase users.role and the Flagsmith identity trait."
disable-model-invocation: true
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# user-set-role

The only approved path for mutating `public.users.role`. Migration 054's
trigger blocks non-service-role connections from updating that column, so
direct PostgREST writes from authenticated users always fail — this skill
runs the service-role write + the Flagsmith identity trait write together
to keep the two sides aligned.

## When to use

- Promoting yourself or a teammate to the `dev` cohort so you receive
  per-role flag previews before flags promote to `prd`.
- Demoting a user back to `prd` when they no longer need preview access.

## When NOT to use

- Bulk role changes (>5 users at once) — script doesn't batch; run
  individually for now.
- Trying to promote a Supabase user that doesn't exist — skill fails
  early with a clear error.

## Arguments

<arguments> #$ARGUMENTS </arguments>

Required positional args: `<email-or-userId> <prd|dev>`.

- `<email-or-userId>`: email address (resolved to UUID via Supabase) OR
  a Supabase auth UUID directly.
- `<prd|dev>`: target role.

Flag `--dry-run` runs lookup + diff (no writes).

## Prerequisites

- `doppler` CLI authenticated; access to `soleur/prd` config (for
  `SUPABASE_SERVICE_ROLE_KEY` + `NEXT_PUBLIC_SUPABASE_URL`).
- `doppler` access to `soleur/cli_ops` (for
  `FLAGSMITH_MANAGEMENT_API_KEY`).
- `curl` + `python3` on PATH.

## Procedure

The agent runs only the preview (`--dry-run` is honoured in the third position
only; anything else there, or a fourth argument, exits `2`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/user-set-role/scripts/set-role.sh" <email|uuid> <prd|dev> --dry-run
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
   `<ARGS>` with `<email|uuid> <prd|dev>`, without `--dry-run`. It never prints a
   `${CLAUDE_PLUGIN_ROOT}` or repo-relative form. A plugin-root or repo-relative path resolves against whatever directory the operator's terminal happens to be in; the absolute worktree path does not.
3. Does not run the command, and does not run it through Claude Code's `!` prefix
   either (whether that gives the command a TTY is unmeasured, ADR-249). The
   printed command is an undone operator step under
   `wg-block-pr-ready-on-undeferred-operator-steps`: record it where the pipeline
   tracks operator steps, and do not mark a PR ready until the operator says it ran.

<!-- operator-write-command -->
```bash
cd <WORKTREE> && bash <WORKTREE>/plugins/soleur/skills/user-set-role/scripts/set-role.sh <ARGS>
```

The operator types `yes` at the prompt. Any other answer stops the script with exit
`1` and `SOLEUR_BOOTSTRAP_ABORTED stage=ack`, before anything is written.

The script (full procedure in [scripts/set-role.sh](./scripts/set-role.sh)):

1. **Validate args** — role in `{prd, dev}`; identifier looks like
   email-or-UUID.
2. **Resolve userId** — if input is an email, look up via service-role
   Supabase REST: `GET /rest/v1/users?email=eq.<email>&select=id,role`.
   If input is UUID, use directly + read current role for the diff.
3. **Diff** — if `current_role == target_role`, exit 0 ("no change").
4. **Print pre/post** — user UUID + email + current role + target role.
5. **Operator ack** — a typed `yes` at the TTY prompt per
   `hr-menu-option-ack-not-prod-write-auth` (no flag skips it; no TTY means exit
   `64` before any credential fetch). Both role values change a PRD user.
6. **Update Supabase** — `PATCH /rest/v1/users?id=eq.<uuid>` with
   `{ "role": "<target>" }`. Service-role JWT bypasses the trigger.
7. **Update Flagsmith identity trait** — POST to
   `/api/v1/environments/{env_id}/identities/{userId}/traits/` with
   `trait_key=role`, `trait_value=<target>`. Done for BOTH dev (env 90722)
   and prd (env 90721) so the user's flag resolution matches in either
   environment.
8. **Re-verify** — re-read `users.role` AND the Flagsmith identity trait
   in each env. Assert matches `<target>`.

## Exit codes

- `0` — success / no-op / dry-run clean.
- `1` — validation failure (bad role, malformed identifier), or the operator did
  not type `yes` (`SOLEUR_BOOTSTRAP_ABORTED stage=ack`; nothing written).
- `2` — prerequisite missing (Doppler, env vars), or a bad third/fourth argument.
- `3` — user not found in Supabase.
- `4` — Supabase write failed.
- `5` — Flagsmith trait write failed (Supabase already updated;
  re-run is idempotent on Supabase side and will re-apply the trait).
- `64` — a write run with no TTY (`SOLEUR_BOOTSTRAP_INPUT_REQUIRED`): hand the
  command to the operator (above).

## Sharp edges

- **30s flag-cache TTL.** The user's resolved flag values won't pick up
  the new role until the per-replica per-role cache TTL elapses (max 30s).
  Skill prints this hint after success.
- **Trait write is fire-and-forget on the identity side.** Flagsmith
  upserts traits; calling with the same value twice is a no-op.
- **Email collision.** If two users somehow share an email (shouldn't
  happen — `public.users(email)` is unique), the skill aborts with
  exit 3 + the conflicting UUIDs.

## Cross-references

- Migration: `apps/web-platform/supabase/migrations/054_users_role_column.sql`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- Sibling skills: `soleur:flag-set-role`, `soleur:flag-create`
