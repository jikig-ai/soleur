---
name: provision-hetzner
description: "This skill should be used when provisioning Hetzner sub-projects and tokens for tenant infrastructure."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

# Provision Hetzner

Guide the operator through Hetzner Console project creation, accept a project-scoped API token, and run a write-class smoke-test to verify scope.

## Art. 32 Pre-condition

**MUST run on the operator's local machine. MUST NOT run in CI.** The Hetzner token is read from `SOLEUR_BOOTSTRAP_HCLOUD_TOKEN` when that variable is set; otherwise it is prompted for with `read -rs` on a TTY; with neither, the script exits 64 with `SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=SOLEUR_BOOTSTRAP_HCLOUD_TOKEN`. It is never persisted to disk, never exported beyond the smoke-test subshell, and never placed on CLI args.

## Usage

```
soleur:provision-hetzner <tenant-slug> [--dry-run]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `tenant-slug` | Yes | Canonical tenant identifier (kebab-case) |
| `--dry-run` | No | Print Console guidance + smoke-test commands without executing |

## Execution

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/provision-hetzner/scripts/provision-hetzner.sh" <slug> [--dry-run]
```

The script:

1. Validates prerequisites (DPA gate, slug format, `hcloud` CLI)
2. Displays guided instructions for Console project creation + token minting
3. Accepts the token (environment variable, else `read -rs` on a TTY, else exit 64) and, after a per-command `yes` acknowledgement that has **no** skip variable, runs the write-class smoke-test (create + delete cx11)
4. Uses deterministic probe name (`probe-provision-<slug>`) so orphans are findable
5. Trap handler ensures probe server cleanup on EXIT/INT/TERM
6. Prints teardown commands on any exit

## Environment

| Variable | Effect |
|---|---|
| `SOLEUR_BOOTSTRAP_HCLOUD_TOKEN` | Supplies the project-scoped token; the `read -rs` prompt is skipped. Set it for the current command only (`SOLEUR_BOOTSTRAP_HCLOUD_TOKEN="$(…)" bash …`), never exported into the shell. |
| `SOLEUR_BOOTSTRAP_SKIP_HETZNER_TOKEN_BARRIER` | Any non-empty value skips the "Token created? Type 'yes'" barrier. The smoke test that follows is the independent verification the barrier attests to, so skipping it is safe only because that test still runs. |
| `SOLEUR_BOOTSTRAP_LEDGER` | Run-ledger path. Default: `<cwd>/.soleur/bootstrap-runs.jsonl` (gitignored; the DPA gate already requires cwd to be the monorepo root). |

There is **no** variable for the "Create the billable probe server now?" acknowledgement. Without a TTY the script exits 64 there with `SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=destructive-write-ack(no-skip-variable-by-design)`; only a person at a terminal can answer it (`hr-menu-option-ack-not-prod-write-auth`). Exit codes and every stdout marker: the header of `plugins/soleur/scripts/lib/operator-script.sh`.

## Encryption Posture

If this run provisions a persistent volume for the tenant, `hcloud_volume` carries no
`encrypted` attribute -- encryption means the guest-side LUKS apparatus (`random_password` ->
dedicated Doppler config -> `cryptsetup luksFormat` -> `/dev/mapper/*` mount; see
soleur:engineering:infra:terraform-architect's Hetzner/Cloudflare requirements). Do not complete the run without adding a
row to `encryption-posture-ledger.json` (repo-root `scripts/`) for the new volume: `at_rest.mechanism`
(`luks` or a named `plaintext-exception` with `tracking_issue` + `expires_on`),
`at_rest.evidence`, `at_rest.does_not_defend`, `at_rest.disclosed_as`, and
`at_rest.live_verification`. This run provisions sub-projects and tokens, not volumes, so the
step is normally a no-op -- it applies only when a volume enters scope.

## Sharp Edges

- Hetzner has no TF resource for project creation or token minting (Console-only). This is the one manual step in this skill; it is tracked as an automation gap with revisit criteria in **Tracks #4604** (per `hr-never-label-any-step-as-manual-without`) — do not treat it as permanently-manual.
- The smoke-test creates a real cx11 server (~EUR 0.006/hr prorated). Trap handler cleans up.
- If `hcloud server delete` fails, the probe server must be deleted manually via Console.
- Read-only tokens silently succeed for reads; the write-class test (server create) is essential.
