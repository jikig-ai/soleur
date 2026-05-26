---
name: provision-github
description: "This skill should be used when provisioning GitHub repos and environments for tenant workflows."
---

# Provision GitHub

Create a GitHub repository + `production` Environment via Terraform, then drive the Soleur App install to the human consent screen.

## Art. 32 Pre-condition

**MUST run on the operator's local machine. MUST NOT run in CI.** The GitHub PAT is accepted via `read -s` (interactive terminal only) and never persisted to disk, env exports, or CLI args.

## Usage

```
soleur:provision-github <tenant-slug> <tenant-org> <reviewer-github-username> [--dry-run]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `tenant-slug` | Yes | Canonical tenant identifier (kebab-case) |
| `tenant-org` | Yes | GitHub organization owning the tenant repo |
| `reviewer-github-username` | Yes | GitHub username for required deployment reviewer |
| `--dry-run` | No | Print TF plan + install URL without executing |

## Execution

```bash
bash plugins/soleur/skills/provision-github/scripts/provision-github.sh <slug> <org> <reviewer> [--dry-run]
```

The script:
1. Validates prerequisites (DPA gate, slug format, `gh` auth, `terraform`)
2. Checks idempotency (warns if repo already exists via `gh repo view`)
3. Resolves numeric org-id for the App install URL
4. Generates `provisioning/<slug>/github.tf` (repo + Environment + deployment policy + reviewer)
5. Emits a copy-pasteable `terraform apply` compound command with credential re-entry
6. After TF apply, presents the human consent gate for App installation (per ToS B.3)
7. Verifies App install permissions via `gh api`
8. Prints teardown commands including `bypass_actors` sweep reminder

## Sharp Edges

- GitHub TF provider requires explicit `token` auth — does NOT inherit from `gh` CLI.
- R2 backend has no state locking. Single operator at N=2.
- App install preserves human consent gate per GitHub ToS B.3. Skill does NOT automate the install click.
- After uninstalling the App, sweep `bypass_actors` for ghost entries (GitHub does NOT auto-prune).
- The `production` Environment + required reviewers is the security control that caps `actions:write` blast radius.
