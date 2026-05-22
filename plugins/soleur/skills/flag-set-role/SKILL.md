---
name: flag-set-role
description: "This skill should be used to flip a runtime flag's per-role state in Flagsmith and mirror prd flips to Doppler."
---

# flag-set-role

Flips one role-segment's enablement on a runtime feature flag in Flagsmith. The skill is the **only** approved path for mutating Flagsmith segment overrides — direct UI/curl edits break the fallback-fidelity contract documented in ADR-038 v2 §"Fallback semantics".

## When to use

- Promoting a feature from dev cohort to everyone: `... <flag> prd on`.
- Disabling a feature for everyone: `... <flag> prd off`.
- Enabling a feature for dev cohort only: `... <flag> dev on`.

## When NOT to use

- Creating a brand-new flag → use `soleur:flag-create`.
- Promoting a user to dev → use `soleur:user-set-role`.

## Arguments

<arguments> #$ARGUMENTS </arguments>

Required positional args: `<flag-name> <role> <on|off>`.
- `<flag-name>`: must be a key in `apps/web-platform/lib/feature-flags/server.ts` `RUNTIME_FLAGS` (currently `kb-chat-sidebar`).
- `<role>`: `prd` or `dev`.
- `<on|off>`: target enablement.

Flag `--dry-run` runs detect/diff/validate steps (no writes).

## Prerequisites

- `doppler` CLI authenticated with access to `soleur` project, configs `dev`, `prd`, `cli_ops`.
- `curl` on PATH.
- `python3` on PATH (used for JSON parsing).

## Procedure

Invoke the script:

```bash
bash plugins/soleur/skills/flag-set-role/scripts/flip.sh <flag> <role> <on|off> [--dry-run]
```

The script (full procedure in [scripts/flip.sh](./scripts/flip.sh)):

1. **Validate args.** Flag must be in the known-set; role in `{prd,dev}`; value in `{on,off}`.
2. **Resolve IDs.** Look up `feature_id` from Flagsmith project `39082` by feature name (cached per session). Look up `segment_id` by name (`role-prd` or `role-dev`).
3. **Read current state.** For each env (dev `90722`, prd `90721`), fetch the live version's feature-states + per-segment override.
4. **Apply fallback-fidelity rule.** If proposed = `dev off` AND current `prd on` in either env, abort with exit 1 + clear message. (See ADR-038 v2 §"Fallback semantics" — the env-var fallback can only mirror one state; `dev off / prd on` cannot be represented and would silently re-enable the dev cohort on outage.)
5. **Print pre/post matrix.** Show current (env × segment) enablement table and the proposed delta.
6. **Operator ack.** Wait for literal `yes` (per `hr-menu-option-ack-not-prod-write-auth`). Anything else aborts.
7. **Flip Flagsmith.** For each env, POST to `/api/v1/environments/{env_id}/features/{feature_id}/versions/` with `feature_states_to_create` (first-time) OR `feature_states_to_update` (subsequent), `publish_immediately: true`.
8. **Mirror Doppler (only on `role=prd` flip).** Run `doppler secrets set FLAG_<X>=<0|1> -p soleur -c dev` AND `-c prd` via stdin-piped 0600 temp file (no CLI-arg leak).
9. **Re-verify.** Re-fetch state in both envs and assert matches proposed.

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

## Cross-references

- ADR: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- Plan: `knowledge-base/project/plans/2026-05-22-feat-flagsmith-operator-skills-plan.md`
- Predecessor PR: #4331 (resolution path)
- Sibling skills: `soleur:flag-create`, `soleur:user-set-role`
