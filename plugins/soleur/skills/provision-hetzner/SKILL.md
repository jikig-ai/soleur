---
name: provision-hetzner
description: "This skill should be used when provisioning Hetzner sub-projects and tokens for tenant infrastructure."
---

# Provision Hetzner

Guide the operator through Hetzner Console project creation, accept a project-scoped API token, and run a write-class smoke-test to verify scope.

## Art. 32 Pre-condition

**MUST run on the operator's local machine. MUST NOT run in CI.** The Hetzner token is accepted via `read -s` (interactive terminal only) and never persisted to disk, env exports, or CLI args.

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
bash plugins/soleur/skills/provision-hetzner/scripts/provision-hetzner.sh <slug> [--dry-run]
```

The script:
1. Validates prerequisites (DPA gate, slug format, `hcloud` CLI)
2. Displays guided instructions for Console project creation + token minting
3. Accepts token via `read -s` and runs write-class smoke-test (create + delete cx11)
4. Uses deterministic probe name (`probe-provision-<slug>`) so orphans are findable
5. Trap handler ensures probe server cleanup on EXIT/INT/TERM
6. Prints teardown commands on any exit

## Encryption Posture

If this run provisions a persistent volume for the tenant, `hcloud_volume` carries no
`encrypted` attribute -- encryption means the guest-side LUKS apparatus (`random_password` ->
dedicated Doppler config -> `cryptsetup luksFormat` -> `/dev/mapper/*` mount; see
terraform-architect's Hetzner/Cloudflare requirements). Do not complete the run without adding a
row to `scripts/encryption-posture-ledger.json` for the new volume: `at_rest.mechanism`
(`luks` or a named `plaintext-exception` with `tracking_issue` + `expires_on`),
`at_rest.evidence`, `at_rest.does_not_defend`, `at_rest.disclosed_as`, and
`at_rest.live_verification`. This run provisions sub-projects and tokens, not volumes, so the
step is normally a no-op -- it applies only when a volume enters scope.

## Sharp Edges

- Hetzner has no TF resource for project creation or token minting (Console-only). This is the one manual step in this skill; it is tracked as an automation gap with revisit criteria in **Tracks #4604** (per `hr-never-label-any-step-as-manual-without`) — do not treat it as permanently-manual.
- The smoke-test creates a real cx11 server (~EUR 0.006/hr prorated). Trap handler cleans up.
- If `hcloud server delete` fails, the probe server must be deleted manually via Console.
- Read-only tokens silently succeed for reads; the write-class test (server create) is essential.
