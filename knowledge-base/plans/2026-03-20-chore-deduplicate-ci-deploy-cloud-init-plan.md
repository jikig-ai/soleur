---
title: "chore: deduplicate ci-deploy.sh between standalone file and cloud-init.yml"
type: refactor
date: 2026-03-20
---

# chore: deduplicate ci-deploy.sh between standalone file and cloud-init.yml

## Overview

`apps/web-platform/infra/ci-deploy.sh` is the source-of-truth deploy script, validated by `ci-deploy.test.sh`. Its full contents are copy-pasted into the `write_files` section of both `apps/web-platform/infra/cloud-init.yml` and `apps/telegram-bridge/infra/cloud-init.yml`. The copies have already drifted -- the standalone file has `docker system prune` calls and an extra comment line that the cloud-init embeds lack. Future edits to the deploy script will inevitably forget to update one or both cloud-init copies.

## Problem Statement

Three identical (or near-identical) copies of the deploy script exist:

| Location | Lines | Has `docker system prune`? | Tested? |
|----------|-------|---------------------------|---------|
| `apps/web-platform/infra/ci-deploy.sh` | 135 | Yes | Yes (`ci-deploy.test.sh`) |
| `apps/web-platform/infra/cloud-init.yml` (lines 44-172) | 129 | No -- already drifted | No |
| `apps/telegram-bridge/infra/cloud-init.yml` (lines 44-172) | 129 | No -- already drifted | No |

The drift is small today (two `docker system prune` blocks and one comment line), but it will grow. The test suite only covers the standalone file, so cloud-init embeds can silently regress.

## Proposed Solution

Replace the inline script content in both `cloud-init.yml` files with Terraform's `file()` function to read the standalone `ci-deploy.sh` at `terraform apply` time. Both infra modules already use `templatefile()` for `cloud-init.yml`; adding a `ci_deploy_script` variable that passes the file content is the minimal change.

### Why `file()` and not `templatefile()` for the script

The standalone `ci-deploy.sh` contains bash `${...}` expressions that collide with Terraform's template interpolation syntax:

- `${SSH_ORIGINAL_COMMAND:0:200}` -- bash substring
- `${SSH_ORIGINAL_COMMAND:-}` -- bash default value
- `${ALLOWED_IMAGES[$COMPONENT]+x}` -- bash array key test
- `${ALLOWED_IMAGES[$COMPONENT]}` -- bash associative array access

Terraform's `templatefile()` would try to interpret these as HCL expressions and fail. Using `file()` reads the content as a raw string with no interpolation, which is exactly what cloud-init `write_files` needs.

### Why not `$${...}` escaping

An alternative is keeping the inline script but escaping all bash `${...}` as `$${...}` for Terraform. This trades one maintenance burden (duplicate content) for another (remembering to double-escape every new bash variable). It also makes the standalone `ci-deploy.sh` and the cloud-init version structurally different, defeating the purpose of deduplication.

### Architecture

```text
apps/web-platform/infra/
  ci-deploy.sh            <-- source of truth (unchanged)
  ci-deploy.test.sh       <-- tests (unchanged)
  cloud-init.yml          <-- remove 129-line inline script, use ${ci_deploy_script}
  server.tf               <-- pass ci_deploy_script = file("ci-deploy.sh") to templatefile()

apps/telegram-bridge/infra/
  cloud-init.yml          <-- remove 129-line inline script, use ${ci_deploy_script}
  server.tf               <-- pass ci_deploy_script = file("../web-platform/infra/ci-deploy.sh")
```

Both cloud-init files reference the same single `ci-deploy.sh` file, so edits propagate automatically.

## Acceptance Criteria

- [ ] `apps/web-platform/infra/cloud-init.yml` no longer contains an inline copy of the deploy script
- [ ] `apps/telegram-bridge/infra/cloud-init.yml` no longer contains an inline copy of the deploy script
- [ ] Both `cloud-init.yml` files use `${ci_deploy_script}` in the `write_files` entry for `/usr/local/bin/ci-deploy.sh`
- [ ] Both `server.tf` files pass `ci_deploy_script` via `file()` into `templatefile()`
- [ ] `terraform validate` passes for both `apps/web-platform/infra/` and `apps/telegram-bridge/infra/`
- [ ] `ci-deploy.test.sh` continues to pass (standalone script unchanged)
- [ ] `cloud-init schema` validation passes for the raw template file (CI step in `infra-validation.yml`)
- [ ] The YAML indentation of the injected script content is correct for cloud-init `write_files` (content under `|` block scalar)

## Test Scenarios

- Given the standalone `ci-deploy.sh` is modified, when `terraform plan` runs, then the `user_data` of the server resource shows the updated script content (single source of truth).
- Given `terraform validate -backend=false`, when run in `apps/web-platform/infra/`, then validation passes with the new `ci_deploy_script` variable in the `templatefile()` call.
- Given `terraform validate -backend=false`, when run in `apps/telegram-bridge/infra/`, then validation passes with the cross-directory `file()` path.
- Given `bash ci-deploy.test.sh`, when run after the change, then all tests pass (standalone script is unchanged).
- Given `cloud-init schema -c cloud-init.yml`, when run on the raw template file containing `${ci_deploy_script}`, then the schema validator does not reject the file (it validates YAML structure, not content values).
- Given the `ci-deploy.sh` content contains `${...}` bash expressions, when Terraform processes the template, then those expressions appear verbatim in the rendered cloud-init (no interpolation errors).

## Context

- Issue: #843
- Related: #825 (restrict CI deploy SSH key), #747 (original forced command implementation)
- Learning: `knowledge-base/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` (documents the `docker system prune` addition that caused the current drift)

## MVP

### apps/web-platform/infra/server.tf

```hcl
resource "hcloud_server" "web" {
  # ... existing fields ...

  user_data = templatefile("${path.module}/cloud-init.yml", {
    image_name            = var.image_name
    deploy_ssh_public_key = var.deploy_ssh_public_key
    ci_deploy_script      = file("${path.module}/ci-deploy.sh")
  })
}
```

### apps/telegram-bridge/infra/server.tf

```hcl
resource "hcloud_server" "bridge" {
  # ... existing fields ...

  user_data = templatefile("${path.module}/cloud-init.yml", {
    image_name            = var.image_name
    deploy_ssh_public_key = var.deploy_ssh_public_key
    ci_deploy_script      = file("${path.module}/../../../apps/web-platform/infra/ci-deploy.sh")
  })
}
```

**Note on path:** The telegram-bridge `server.tf` uses a relative path from its own module to the web-platform infra directory. The `${path.module}` prefix ensures Terraform resolves from the correct base. Trace: `apps/telegram-bridge/infra/` + `../../../` = repo root, then `apps/web-platform/infra/ci-deploy.sh`. Wait -- that is wrong. `apps/telegram-bridge/infra/` + `../../../` goes three levels up from `infra/` which is `apps/telegram-bridge/infra/ -> apps/telegram-bridge/ -> apps/ -> repo-root`. Then `apps/web-platform/infra/ci-deploy.sh` appended gives `repo-root/apps/web-platform/infra/ci-deploy.sh`. That is correct but overly deep. A simpler relative path: `${path.module}/../../web-platform/infra/ci-deploy.sh` -- trace: `apps/telegram-bridge/infra/` + `../../` = `apps/`, then `web-platform/infra/ci-deploy.sh`. This is the correct and shorter path.

Corrected:

```hcl
ci_deploy_script = file("${path.module}/../../web-platform/infra/ci-deploy.sh")
```

### apps/web-platform/infra/cloud-init.yml (write_files entry replacement)

Replace the 129-line inline script block with:

```yaml
  # CI deploy forced command script. The CI SSH key in authorized_keys uses:
  #   restrict,command="/usr/local/bin/ci-deploy.sh" ssh-ed25519 AAAA... ci-deploy-2026@soleur-web-platform
  # This restricts the CI key to only execute deploy commands (see #747).
  # Content injected from ci-deploy.sh via Terraform file() -- do not inline.
  - path: /usr/local/bin/ci-deploy.sh
    content: |
      ${ci_deploy_script}
    owner: root:root
    permissions: '0755'
```

### apps/telegram-bridge/infra/cloud-init.yml (write_files entry replacement)

Same pattern, with the bridge-specific comment updated:

```yaml
  # CI deploy forced command script. The CI SSH key in authorized_keys uses:
  #   restrict,command="/usr/local/bin/ci-deploy.sh" ssh-ed25519 AAAA... ci-deploy-2026@soleur-bridge
  # This restricts the CI key to only execute deploy commands (see #747).
  # Content injected from ci-deploy.sh via Terraform file() -- do not inline.
  - path: /usr/local/bin/ci-deploy.sh
    content: |
      ${ci_deploy_script}
    owner: root:root
    permissions: '0755'
```

### YAML indentation concern

When `templatefile()` substitutes `${ci_deploy_script}`, the multi-line script content will be inserted at the indentation level of the `${ci_deploy_script}` placeholder. Cloud-init's `content: |` block scalar requires consistent indentation. Terraform's `templatefile()` does NOT automatically indent multi-line substitutions to match the surrounding YAML context.

Two approaches to handle this:

1. **`indent()` function:** Use `${indent(6, ci_deploy_script)}` to add 6 spaces of indentation to every line of the script content, matching the YAML block scalar indentation level. This is the cleanest approach.

2. **Place the placeholder at column 0:** Restructure the YAML so the placeholder is at the start of the line, avoiding indentation issues. This is awkward and breaks YAML readability.

Approach 1 is recommended. The cloud-init `write_files` `content: |` block uses 6-space indentation (2 for list item + 4 for content level). The corrected template becomes:

```yaml
  - path: /usr/local/bin/ci-deploy.sh
    content: |
${indent(6, ci_deploy_script)}
    owner: root:root
    permissions: '0755'
```

Note: `${indent(6, ...)}` adds 6 spaces to the beginning of each line, including the first. The placeholder must be at column 0 (no leading whitespace) to avoid double-indentation.

## References

- [Terraform `file()` function](https://developer.hashicorp.com/terraform/language/functions/file)
- [Terraform `templatefile()` function](https://developer.hashicorp.com/terraform/language/functions/templatefile)
- [Terraform `indent()` function](https://developer.hashicorp.com/terraform/language/functions/indent)
- [cloud-init `write_files` module](https://cloudinit.readthedocs.io/en/latest/reference/modules/write_files.html)
- Related issue: #843
- Related PR: #825
