---
name: provision-cloudflare
description: "This skill should be used when provisioning scoped Cloudflare API tokens for tenant deploys."
disable-model-invocation: true
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# Provision Cloudflare

Create a scoped Cloudflare API token via Terraform `cloudflare_api_token` with least-privilege permissions for a tenant's deploy pipeline.

## Art. 32 Pre-condition

**MUST run on the operator's local machine. MUST NOT run in CI.** Bootstrap credentials are accepted via `read -s` (interactive terminal only) and never persisted to disk, env exports, or CLI args.

## Usage

```
soleur:provision-cloudflare <tenant-slug> <cf-zone-id> <cf-account-id> [--dry-run]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `tenant-slug` | Yes | Canonical tenant identifier (kebab-case) |
| `cf-zone-id` | Yes | Cloudflare zone ID for the tenant's domain |
| `cf-account-id` | Yes | Cloudflare account ID |
| `--dry-run` | No | Print TF plan + smoke-test commands without executing |

## Execution

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/provision-cloudflare/scripts/provision-cloudflare.sh" <slug> <zone-id> <account-id> [--dry-run]
```

The script:

1. Validates prerequisites (DPA gate, format validation, tool availability)
2. Checks idempotency (warns if `cloudflare.tf` already exists)
3. Generates `provisioning/<slug>/cloudflare.tf` with 4 permission groups + sensitive output
4. Emits a copy-pasteable `terraform apply` compound command with credential re-entry
5. After operator confirms TF apply, runs token extraction + smoke-test pipeline
6. Prints teardown commands and bootstrap revocation reminder

## Encryption Posture

If this run provisions a `cloudflare_r2_bucket` for the tenant, R2 has no encryption attribute
either -- it is provider-managed at rest, and a bare "the provider handles it" is not an
acceptable declaration. Do not complete the run without adding a row to
`encryption-posture-ledger.json` (repo-root `scripts/`): `at_rest.mechanism: provider-managed:<named
attestation>`, `at_rest.evidence` (attestation name + URL + retrieval date, plus the bucket's
`location`/jurisdiction field in the `.tf`), `at_rest.does_not_defend`, `at_rest.disclosed_as`,
and `at_rest.live_verification`. This run provisions a scoped API token, not a bucket, so the
step is normally a no-op -- it applies only when a bucket enters scope.

## Sharp Edges

- R2 backend has no state locking. Single operator at N=2.
- Token extraction uses `terraform output -raw` piped to a subshell to avoid terminal scrollback exposure.
- CF provider pinned at `~> 4.0`; upgrade when Soleur's main root upgrades.
- Does NOT grant `User Details:Read` or `Account Settings:Read` (least-privilege).
