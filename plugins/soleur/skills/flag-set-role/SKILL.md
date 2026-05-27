---
name: flag-set-role
description: "This skill should be used to flip a flag's per-role or per-org state in Flagsmith, mirroring prd flips to Doppler."
---

# flag-set-role

Flips one role-segment's enablement on a runtime feature flag in Flagsmith, or manages per-org segment membership. The skill is the **only** approved path for mutating Flagsmith segment overrides and org-targeted segment rules — direct UI/curl edits break the fallback-fidelity contract documented in ADR-038 v2 §"Fallback semantics".

## When to use

- Promoting a feature from dev cohort to everyone: `... <flag> prd on`.
- Disabling a feature for everyone: `... <flag> prd off`.
- Enabling a feature for dev cohort only: `... <flag> dev on`.
- Adding an org to the per-org segment: `... <flag> prd on --org <orgId>`.
- Removing an org from the per-org segment: `... <flag> prd off --org <orgId>`.

## When NOT to use

- Creating a brand-new flag → use `soleur:flag-create`.
- Promoting a user to dev → use `soleur:user-set-role`.

## Arguments

<arguments> #$ARGUMENTS </arguments>

Required positional args: `<flag-name> <role> <on|off>`.
- `<flag-name>`: must be a key in `apps/web-platform/lib/feature-flags/server.ts` `RUNTIME_FLAGS` (currently `kb-chat-sidebar`).
- `<role>`: `prd` or `dev`.
- `<on|off>`: target enablement.

Flag `--org <orgId>` switches to per-org targeting mode. When provided, the script modifies the `org-targeted` segment's rule definition (adds/removes an `EQUAL orgId <uuid>` condition in the `ANY` rule) instead of flipping a role-segment override. The orgId must be a valid UUID.
Flag `--dry-run` runs detect/diff/validate steps (no writes).
Flag `--confirmed` skips the interactive `read -p` prompt (for agent-driven use; the agent must obtain operator ack via AskUserQuestion before passing this flag).

## Prerequisites

- `doppler` CLI authenticated with access to `soleur` project, configs `dev`, `prd`, `cli_ops`.
- `curl` on PATH.
- `python3` on PATH (used for JSON parsing).

## Procedure

Invoke the script:

```bash
# Dry-run to see the matrix:
bash plugins/soleur/skills/flag-set-role/scripts/flip.sh <flag> <role> <on|off> --dry-run
# After AskUserQuestion confirmation:
bash plugins/soleur/skills/flag-set-role/scripts/flip.sh <flag> <role> <on|off> --confirmed
```

**Agent-driven flow (recommended):**

1. Run with `--dry-run` to get the pre/post matrix (exits 0, no writes, no prompt).
2. Present the matrix output to the operator via **AskUserQuestion** with options: "Yes, apply" / "Cancel".
3. On confirmation, re-run with `--confirmed` (skips the `read -p` prompt, proceeds to write).
4. On cancel, abort.

**Important:** The agent must always pass `--dry-run` (for preview) or `--confirmed` (for apply) — never invoke without one of these flags, or the interactive prompt will hang the agent shell.

The script (full procedure in [scripts/flip.sh](./scripts/flip.sh)):

**Role targeting (default):**

1. **Validate args.** Flag must be in the known-set; role in `{prd,dev}`; value in `{on,off}`.
2. **Resolve IDs.** Look up `feature_id` from Flagsmith project `39082` by feature name (cached per session). Look up `segment_id` by name (`role-prd` or `role-dev`).
3. **Read current state.** For each env (dev `90722`, prd `90721`), fetch the live version's feature-states + per-segment override.
4. **Apply fallback-fidelity rule.** If proposed = `dev off` AND current `prd on` in either env, abort with exit 1 + clear message. (See ADR-038 v2 §"Fallback semantics" — the env-var fallback can only mirror one state; `dev off / prd on` cannot be represented and would silently re-enable the dev cohort on outage.)
5. **Print pre/post matrix.** Show current (env × segment) enablement table and the proposed delta.
6. **Operator ack.** If `--confirmed` is passed, skip (the agent already obtained ack via AskUserQuestion). Otherwise, wait for literal `yes` at the terminal prompt (per `hr-menu-option-ack-not-prod-write-auth`). Anything else aborts.
7. **Flip Flagsmith.** For each env, POST to `/api/v1/environments/{env_id}/features/{feature_id}/versions/` with `feature_states_to_create` (first-time) OR `feature_states_to_update` (subsequent), `publish_immediately: true`.
8. **Mirror Doppler (only on `role=prd` flip).** Run `doppler secrets set FLAG_<X>=<0|1> -p soleur -c dev` AND `-c prd` via stdin-piped 0600 temp file (no CLI-arg leak).
9. **Re-verify.** Re-fetch state in both envs and assert matches proposed.

**Org targeting (when `--org <orgId>` is provided):**

1. **Validate args.** Same as role targeting, plus UUID format validation on the orgId.
2. **Resolve segment.** Look up `org-targeted` segment by name via `resolve_segment_id`.
3. **Read segment rules.** GET the full segment definition, extract all orgIds from the `rules[0].rules[0].conditions[]` array (each condition is `EQUAL orgId <uuid>` inside an `ANY` rule).
4. **Compute new list.** Check presence. If adding and already present, exit 0 ("already present"). If removing and not present, exit 0 ("not present"). Handle empty segment (first org added).
5. **Dry-run display.** Print current membership (one orgId per line), proposed action, and new membership list.
6. **Operator ack.** Same as role targeting.
7. **Audit trail.** WORM audit entry with `target: org:<orgId>` (audit-before-write ordering).
8. **Write segment.** PUT the full segment body back with the conditions array rebuilt (one `EQUAL` condition per org).
9. **Re-verify.** Re-read segment, confirm orgId present/absent as expected.

No Doppler mirror runs for org-targeting (segment membership is not reflected in env vars per ADR-038). No fallback-fidelity check applies (org-targeting modifies segment rule definitions, not per-env overrides).

## Exit codes

- `0` — success (or `--dry-run` clean).
- `1` — fallback-fidelity rule violated (caller error).
- `2` — prerequisite missing (Doppler not authed, FLAGSMITH_MANAGEMENT_API_KEY unset, flag not in RUNTIME_FLAGS).
- `3` — Flagsmith API error (network, 5xx, auth).
- `4` — Doppler write failed (skill aborts — Flagsmith state is now ahead of Doppler; operator must reconcile).

## Sharp edges

- The cache TTL in `apps/web-platform/lib/feature-flags/server.ts` is 30s per role. After a flip, the new state propagates per replica within 30s. Skill prints this hint after a successful flip.
- The `dev off` rejection (Step 4) catches the case where prd is currently on AND you want to remove the dev cohort's preview. The correct sequence is: flip `prd off` first (which auto-flips both segments off via env-var mirror semantics, sort of), then leave dev where you want it. The plan's `dev off / prd on` case is intentionally unreachable.
- Doppler mirror writes (Step 8) happen sequentially: dev first, then prd. If dev write fails, prd is not attempted (avoids cross-config divergence). Exit code 4.
- The `org-targeted` segment is project-level in Flagsmith, not environment-level. A rule change affects all environments (dev + prd). This is by design (ADR-043: "Single-control — Flagsmith segment rule is the sole per-org gate").
- No Doppler mirror runs for `--org` operations — org segment membership is not reflected in env vars.
- The segment uses `EQUAL` conditions (one per org) inside an `ANY` rule, not a single `IN` condition. Matching is case-sensitive.
- `resolve_segment_id` uses `GET /segments/` without pagination. Safe with 3 segments; may need pagination if segment count exceeds 10.

## Cross-references

- ADR: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- Plan: `knowledge-base/project/plans/2026-05-22-feat-flagsmith-operator-skills-plan.md`
- Predecessor PR: #4331 (resolution path)
- Sibling skills: `soleur:flag-create`, `soleur:user-set-role`
