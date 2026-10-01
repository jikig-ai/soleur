---
name: flag-set-role
description: "This skill should be used to flip a flag's per-role or per-org state in Flagsmith, mirroring prd flips to Doppler."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# flag-set-role

Flips one role-segment's enablement on a runtime feature flag in Flagsmith, or manages per-org segment membership. The skill is the **only** approved path for mutating Flagsmith segment overrides and per-feature org-segment rules — direct UI/curl edits break the fallback-fidelity contract documented in ADR-038 v2 §"Fallback semantics".

Per-org targeting uses a **per-feature segment** `<flag>-orgs` (ADR-043 §"Per-feature segment scoping", 2026-05-29) — each org-targetable flag gets its own segment, so the org set for one flag is independent of another's. (The legacy shared `org-targeted` segment is retained until `team-workspace-invite` is migrated off it; new per-org scoping uses `<flag>-orgs`.)

## When to use

- Promoting a feature from dev cohort to everyone: `... <flag> prd on`.
- Disabling a feature for everyone: `... <flag> prd off`.
- Enabling a feature for dev cohort only: `... <flag> dev on`.
- Adding an org to the per-org segment: `... <flag> prd on --org <orgId>`.
- Removing an org from the per-org segment: `... <flag> prd off --org <orgId>`.
- Migrating a feature off the legacy shared `org-targeted` segment onto its own `<flag>-orgs` segment: `... <flag> prd on --detach-shared --org <memberId>`.

## When NOT to use

- Creating a brand-new flag → use `soleur:flag-create`.
- Promoting a user to dev → the operator types `soleur:user-set-role` (user-invoked, ADR-236:
  the model cannot run it, so hand over the exact command, rendered per `formatSkillInvocation`).

## Arguments

<arguments> #$ARGUMENTS </arguments>

Required positional args: `<flag-name> <role> <on|off>`.

- `<flag-name>`: must be a key in `apps/web-platform/lib/feature-flags/server.ts` `RUNTIME_FLAGS` (and in the script's `FLAG_ENV_VARS` map).
- `<role>`: `prd` or `dev`.
- `<on|off>`: target enablement.

Flag `--org <orgId>` switches to per-org targeting mode. When provided, the script provisions the feature's own `<flag>-orgs` segment (creates it + ensures an ON feature-state override in both envs) and adds/removes an `EQUAL orgId <uuid>` condition in its `ANY` rule, instead of flipping a role-segment override. The orgId must be a valid UUID.
Flag `--control-org <orgId>` (per-org mode only) sets the control org for the eval-layer re-verify (the org asserted to be NOT enabled — proves no leak). Defaults to a synthetic non-member UUID; pass a real sibling org (e.g. one sharing the legacy `org-targeted` segment) for a stronger leak check.
Flag `--detach-shared` (migration verb; requires `--org <memberId>` and value `on`) removes the feature's override on the legacy shared `org-targeted` segment in BOTH envs by publishing a version with `segment_ids_to_delete_overrides:[<org-targeted id>]` (resolved by name, never hard-coded), then eval-verifies the feature STILL resolves `enabled=true` for the member org (served by its own `<flag>-orgs` segment now) and `enabled=false` for the control org. Provision `<flag>-orgs` via the `--org` path FIRST — detach removes the shared override, it does not create the per-feature one. Idempotent: a no-op for any env with no override, and a clean no-op if `org-targeted` is already gone.
Flag `--dry-run` runs detect/diff/validate steps (no writes).
There is no flag that skips the typed-`yes` prompt. The one that used to exist for
agent-driven use was removed (#8486): an operator's "yes" in a menu is not
authorization for a production write (`hr-menu-option-ack-not-prod-write-auth`).
Passing it now fails as an unknown flag (exit `2`) with a message pointing at the
operator's own terminal.

## Prerequisites

- `doppler` CLI authenticated with access to `soleur` project, configs `dev`, `prd`, `cli_ops`.
- `curl` on PATH.
- `python3` on PATH (used for JSON parsing).

## Procedure

The agent runs only the preview, which prints the pre/post matrix (exit 0, no writes,
no prompt):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/flag-set-role/scripts/flip.sh" <flag> <role> <on|off> --dry-run
```

Every write changes BOTH Flagsmith environments (dev and prd), whichever role
segment it names, so a `dev` flip is a production write too.

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
   `<ARGS>` with `<flag> <role> <on|off>` plus any `--org`, `--control-org` or `--detach-shared` the operator chose, without `--dry-run`. It never prints a
   `${CLAUDE_PLUGIN_ROOT}` or repo-relative form. A plugin-root or repo-relative path resolves against whatever directory the operator's terminal happens to be in; the absolute worktree path does not.
3. Does not run the command, and does not run it through Claude Code's `!` prefix
   either (whether that gives the command a TTY is unmeasured, ADR-249). The
   printed command is an undone operator step under
   `wg-block-pr-ready-on-undeferred-operator-steps`: record it where the pipeline
   tracks operator steps, and do not mark a PR ready until the operator says it ran.

<!-- operator-write-command -->
```bash
cd <WORKTREE> && bash <WORKTREE>/plugins/soleur/skills/flag-set-role/scripts/flip.sh <ARGS>
```

The operator types `yes` at the prompt. Any other answer stops the script with exit
`1` and `SOLEUR_BOOTSTRAP_ABORTED stage=ack`, before anything is written.

## Incident rollback (the operator, in their own terminal)

When a flip has to be undone during an incident, skip the preview: give the
operator the rollback command at once, with the opposite value, in the same shape
as above:

```bash
cd <WORKTREE> && bash <WORKTREE>/plugins/soleur/skills/flag-set-role/scripts/flip.sh <flag> <role> <on|off>
```

- Run it in the operator's own terminal (Warp). Not through Claude Code's `!`
  prefix: whether that gives the command a TTY is unmeasured (ADR-249).
- If it exits `4` with `FATAL: audit …` (the WORM append failed, so nothing was
  written), the break-glass is the Flagsmith dashboard: make the same change there.
  A dashboard write leaves no WORM row, so record it afterwards (what, when, why) in
  the incident's issue.

The script (full procedure in [scripts/flip.sh](./scripts/flip.sh)):

**Role targeting (default):**

1. **Validate args.** Flag must be in the known-set; role in `{prd,dev}`; value in `{on,off}`.
2. **Resolve IDs.** Look up `feature_id` from Flagsmith project `39082` by feature name (cached per session). Look up `segment_id` by name (`role-prd` or `role-dev`).
3. **Read current state.** For each env (dev `90722`, prd `90721`), fetch the live version's feature-states + per-segment override.
4. **Apply fallback-fidelity rule.** If proposed = `dev off` AND current `prd on` in either env, abort with exit 1 + clear message. (See ADR-038 v2 §"Fallback semantics" — the env-var fallback can only mirror one state; `dev off / prd on` cannot be represented and would silently re-enable the dev cohort on outage.)
5. **Print pre/post matrix.** Show current (env × segment) enablement table and the proposed delta.
6. **Operator ack.** Wait for a typed `yes` at the terminal prompt (per `hr-menu-option-ack-not-prod-write-auth`); anything else exits `1`. No flag skips it, and with no TTY the script already stopped at exit `64` before step 2.
7. **Flip Flagsmith.** For each env, POST to `/api/v1/environments/{env_id}/features/{feature_id}/versions/` with `feature_states_to_create` (first-time) OR `feature_states_to_update` (subsequent), `publish_immediately: true`.
8. **Mirror Doppler (only on `role=prd` flip).** Run `doppler secrets set FLAG_<X>=<0|1> -p soleur -c dev` AND `-c prd` via stdin-piped 0600 temp file (no CLI-arg leak).
9. **Re-verify.** Re-fetch state in both envs and assert matches proposed.

**Org targeting (when `--org <orgId>` is provided):**

1. **Validate args.** Same as role targeting, plus UUID format validation on `--org` and `--control-org` (and they must differ).
2. **Read current membership.** Resolve the feature's own `<flag>-orgs` segment (may not exist yet → empty membership) and extract its orgIds from the `rules[0].rules[0].conditions[]` array (each condition is `EQUAL orgId <uuid>` inside an `ANY` rule).
3. **Compute new membership + display.** Add (on) or remove (off) the target org. Print current membership, proposed action, control org, and the new membership. No "already present" early-exit — the override may still be missing, so provisioning + eval-verify always run.
4. **Dry-run / operator ack.** `--dry-run` prints the plan and exits 0 with no writes. Otherwise wait for a typed `yes`.
5. **Audit trail.** WORM audit entry with `target: org:<orgId>` BEFORE any Flagsmith mutation (append-before-flip).
6. **Provision `<flag>-orgs`.** Idempotently create the segment (ALL→ANY/EQUAL-orgId envelope) and ensure an ON feature-state override for the flag in BOTH envs (`provision_feature_segment`).
7. **Write membership.** Re-read the segment immediately before the PUT (shrinks the read-modify-write window), then PUT the conditions array rebuilt from the fresh read (one `EQUAL` condition per org).
8. **Eval-layer re-verify (the load-bearing check).** Evaluate the flag for a transient identity carrying the `orgId` trait (the production `getIdentityFlags("org:<orgId>:<role>", {role, orgId}, transient)` path, against `edge.api.flagsmith.com`): assert the **target** org resolves `enabled == (on)` AND the **control** org resolves `enabled == false`. Membership-set equality alone is NOT sufficient — a missing override, or an override present in only one env, leaves the flag OFF while the org is "in" the segment. Eval propagation is polled (eventual, completes within seconds).

No Doppler mirror runs for org-targeting (segment membership is not reflected in env vars per ADR-038/ADR-043 — a per-org-only flag falls back **OFF** on a Flagsmith outage). No fallback-fidelity check applies (org-targeting modifies segment rule definitions, not per-env role overrides).

**Detach from the shared segment (when `--detach-shared` is provided):**

This is the migration verb (#4617), not a routine flip — it moves a feature off the legacy shared `org-targeted` segment onto its own `<flag>-orgs` segment. Ordering is load-bearing: provision `<flag>-orgs` (the `--org` path) and eval-verify the member is enabled BEFORE detaching, or the member loses the feature in the window between detach and provision.

1. **Validate args.** Requires `--org <memberId>` (a member org to eval-verify stays enabled), value `on`, and UUID format on `--org`/`--control-org` (they must differ).
2. **Dry-run / operator ack.** `--dry-run` prints the plan (which envs, member/control) and exits 0 with no writes. Otherwise wait for a typed `yes`.
3. **Audit trail.** WORM audit entry with `target: detach:org-targeted` BEFORE any Flagsmith mutation (append-before-flip). Enablement is unchanged (the feature stays ON, now served by `<flag>-orgs`), so before/after are both `true`.
4. **Detach.** Resolve `org-targeted` by name. For each env (dev `90722`, prd `90721`) where the feature has an override row on the shared segment, POST a new version with `segment_ids_to_delete_overrides:[<org-targeted id>]` and empty create/update arrays (`publish_immediately: true`). Envs with no override are skipped (idempotent).
5. **Eval-layer re-verify.** Evaluate the flag for the member org (must STILL be `enabled=true` — served by `<flag>-orgs`) AND the control org (must settle to `enabled=false` — no leak), against `edge.api.flagsmith.com`. A dropped member or a control leak fails loud (exit 3). No Doppler mirror.

## Exit codes

- `0` — success (or `--dry-run` clean).
- `1` — fallback-fidelity rule violated (caller error), or the operator did not type `yes` (`SOLEUR_BOOTSTRAP_ABORTED stage=ack`; nothing written).
- `2` — prerequisite missing (Doppler not authed, FLAGSMITH_MANAGEMENT_API_KEY unset, flag not in RUNTIME_FLAGS), a usage error, or an unknown flag (including the removed prompt-skip flag).
- `3` — Flagsmith API error (network, 5xx, auth).
- `4` — Doppler write failed (skill aborts — Flagsmith state is now ahead of Doppler; operator must reconcile), or the WORM audit append failed before any write.
- `64` — a write run with no TTY (`SOLEUR_BOOTSTRAP_INPUT_REQUIRED`): nothing was fetched or changed; hand the command to the operator (above).

## Sharp edges

- The cache TTL in `apps/web-platform/lib/feature-flags/server.ts` is 30s per role. After a flip, the new state propagates per replica within 30s. Skill prints this hint after a successful flip.
- The `dev off` rejection (Step 4) catches the case where prd is currently on AND you want to remove the dev cohort's preview. The correct sequence is: flip `prd off` first (which auto-flips both segments off via env-var mirror semantics, sort of), then leave dev where you want it. The plan's `dev off / prd on` case is intentionally unreachable.
- Doppler mirror writes (Step 8) happen sequentially: dev first, then prd. If dev write fails, prd is not attempted (avoids cross-config divergence). Exit code 4.
- The `<flag>-orgs` segment is project-level in Flagsmith, not environment-level. A membership (conditions) change affects all environments; the ON feature-state override is applied per-env to both. This is by design (ADR-043: the segment rule is the per-org gate, the override makes the flag ON for matched orgs).
- No Doppler mirror runs for `--org` operations — per-org segment membership is not reflected in env vars, so a per-org-only flag falls back **OFF** on a Flagsmith outage (env-var = 0). Verify `FLAG_<X>` is `0` in prd Doppler before relying on this for a legally-sensitive flag.
- The segment uses `EQUAL` conditions (one per org) inside an `ANY` rule, not a single `IN` condition. Matching is case-sensitive. An empty `<flag>-orgs` (last org removed) matches nobody → the flag is OFF for all via that segment.
- Re-verify is at the **evaluation** layer (identity + orgId trait), not segment membership: a correct membership set with a missing/one-env override silently leaves the flag OFF. The control-org assertion catches a leak to a non-targeted org.
- `resolve_segment_id` uses `GET /segments/` without pagination. Safe with a handful of segments; may need pagination as the per-feature segment count grows.
- `--detach-shared` removes the shared-segment override but does NOT create the `<flag>-orgs` one — run the `--org` path first to provision + eval-verify the per-feature segment, then `--detach-shared`. Detaching before provisioning drops the feature for the member. The post-detach eval-verify (member still `enabled=true`) is what catches a wrong ordering. After every feature is detached, retire the now-orphaned `org-targeted` segment (zero attachments) and flip ADR-043 to fully-superseded.
- A single `--detach-shared` run eval-verifies ONLY the one member passed in `--org` (plus the control). For a feature with **multiple** member orgs, run `--detach-shared --org <member>` **once per member**: the first run performs the (one-time, both-env) detach AND eval-verifies that member; each subsequent run is an idempotent no-op detach that eval-verifies the next member still resolves `enabled=true`. Do not assume one run proves every member survived. The control is a non-member org — when every real org in the shared segment is a member that must stay enabled, the synthetic-default control (a guaranteed non-member) is the correct leak check; the warning is expected in that case.

## Cross-references

- ADR: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`, `ADR-043-flagsmith-per-org-targeting.md` (§"Per-feature segment scoping")
- Plan: `knowledge-base/project/plans/2026-05-22-feat-flagsmith-operator-skills-plan.md`, `2026-05-29-feat-flag-org-scoping-plan.md`, `2026-05-29-chore-twi-migrate-off-shared-org-targeted-plan.md` (#4617, `--detach-shared`)
- Predecessor PR: #4331 (resolution path), #4612 (#4581 PR-2, per-feature segments)
- Sibling skills (flag CRUD set): `soleur:flag-create` (Create), `soleur:flag-list` (Read), `soleur:flag-delete` (Delete), `soleur:user-set-role`
