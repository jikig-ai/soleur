---
title: "chore: deduplicate ci-deploy.sh between standalone file and cloud-init.yml"
type: refactor
date: 2026-03-20
deepened: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Proposed Solution, MVP, YAML indentation, Test Scenarios)
**Research sources:** Terraform docs, HashiCorp Discuss threads, GitHub issues

### Key Improvements

1. **Critical bug fix in plan:** `indent()` does NOT indent the first line -- the original plan incorrectly stated it does. The recommended approach is now `base64encode()` which completely avoids indentation issues.
2. **Added `base64encode()` as the recommended approach** -- simpler, no indentation pitfalls, cloud-init natively supports `encoding: b64`.
3. **Corrected `indent()` usage** as a fallback -- the first line gets its indentation from the template position, not from `indent()`.
4. **Added `cloud-init schema` validation edge case** -- the raw template with `${ci_deploy_script}` may fail schema validation in CI since it is not valid YAML until Terraform renders it.

### New Considerations Discovered

- The existing inline `ci-deploy.sh` in both `cloud-init.yml` files contains unescaped bash `${...}` expressions that would fail `terraform plan` if the server were reprovisioned -- this is a latent bug, not just a maintenance concern.
- `cloud-init schema -c cloud-init.yml` in CI validates the raw template before Terraform rendering, so Terraform template variables in content fields may cause validation failures.

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

### Research Insights [Updated 2026-03-20]

**Latent bug in current code:** The existing inline `ci-deploy.sh` in both `cloud-init.yml` files contains unescaped bash `${...}` expressions (e.g., `${SSH_ORIGINAL_COMMAND:0:200}`, `${ALLOWED_IMAGES[$COMPONENT]+x}`). These are inside a `templatefile()` call in `server.tf`. Terraform should fail on these during `terraform plan` because they are not valid HCL expressions. This means either: (a) the server has never been reprovisioned since the script was inlined, or (b) Terraform's parser is lenient about `${...}` expressions it cannot parse inside YAML block scalars. Either way, the deduplication fixes a latent correctness issue, not just a maintenance concern.

**Three viable approaches exist (ranked):**

1. **`base64encode()` (recommended):** Encode the script content as base64 and use cloud-init's `encoding: b64` field. Completely avoids YAML indentation issues. Zero risk of template interpolation conflicts. Cloud-init decodes at write time.
2. **`indent()` with correct placement:** Use `${indent(N, var)}` at the correct column offset in the template. Requires understanding that `indent()` does NOT indent the first line -- the first line gets its indentation from its position in the template file.
3. **`jsonencode()`:** Wrap the content in `jsonencode()` to produce a quoted YAML string. Valid since YAML is a JSON superset. Adds escape characters that make the template harder to read.

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

- [x] `apps/web-platform/infra/cloud-init.yml` no longer contains an inline copy of the deploy script
- [x] `apps/telegram-bridge/infra/cloud-init.yml` no longer contains an inline copy of the deploy script
- [x] Both `cloud-init.yml` files use `${ci_deploy_script_b64}` (or `${ci_deploy_script}` with `indent()`) in the `write_files` entry for `/usr/local/bin/ci-deploy.sh`
- [x] Both `server.tf` files pass the script content via `base64encode(file(...))` (or `file()`) into `templatefile()`
- [x] `terraform validate` passes for both `apps/web-platform/infra/` and `apps/telegram-bridge/infra/`
- [x] `terraform fmt -check` passes for both infra directories
- [x] `ci-deploy.test.sh` continues to pass (standalone script unchanged)
- [x] `cloud-init schema -c cloud-init.yml` in CI either passes or the CI step is updated to handle templates (see edge case below)
- [x] The rendered cloud-init (after Terraform processing) produces a valid script at `/usr/local/bin/ci-deploy.sh` with correct content and permissions

### Research Insight: cloud-init schema validation edge case [Updated 2026-03-20]

The CI workflow (`infra-validation.yml`) runs `cloud-init schema -c cloud-init.yml` on the raw template file. After this change, the file will contain `${ci_deploy_script_b64}` (a Terraform template variable), which is not valid YAML content until Terraform renders it. The schema validator may reject this.

**Mitigation options:**

1. **Accept the limitation:** `cloud-init schema` validates structure (keys, types), not content values. A base64 string placeholder may still pass since the `content:` field accepts any string.
2. **Skip schema validation for template files:** Update the CI step to detect Terraform template variables and skip validation, or render the template first with dummy values.
3. **Test during implementation:** Run `cloud-init schema` on the modified template to determine actual behavior before deciding.

## Test Scenarios

- Given the standalone `ci-deploy.sh` is modified, when `terraform plan` runs, then the `user_data` of the server resource shows the updated script content (single source of truth).
- Given `terraform init -backend=false && terraform validate`, when run in `apps/web-platform/infra/`, then validation passes with the new template variable.
- Given `terraform init -backend=false && terraform validate`, when run in `apps/telegram-bridge/infra/`, then validation passes with the cross-directory `file()` path.
- Given `terraform fmt -check`, when run in both infra directories, then formatting is correct.
- Given `bash ci-deploy.test.sh`, when run after the change, then all 21 tests pass (standalone script is unchanged).
- Given the `ci-deploy.sh` content contains bash `${...}` expressions, when Terraform processes the template via `base64encode(file(...))`, then those expressions survive encoding/decoding verbatim (base64 is a transparent encoding).
- Given `cloud-init schema -c cloud-init.yml`, when run on the raw template, then determine if the `${ci_deploy_script_b64}` placeholder causes validation failure. If yes, update CI to handle this.

### Research Insight: base64 round-trip verification [Updated 2026-03-20]

With the `base64encode()` approach, bash `${...}` expressions in the script never enter the Terraform template parser. The data flow is: `file()` reads raw bytes, `base64encode()` converts to a safe ASCII string, `templatefile()` inserts the ASCII string (no `${...}` to misinterpret), cloud-init decodes base64 back to the original bytes. This is inherently safe -- no escaping or indentation logic needed.

## Context

- Issue: #843
- Related: #825 (restrict CI deploy SSH key), #747 (original forced command implementation)
- Learning: `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` (documents the `docker system prune` addition that caused the current drift)

## MVP -- Approach A: `base64encode()` (Recommended)

This approach encodes the script as base64 and lets cloud-init decode it at write time. It completely avoids YAML indentation issues and template interpolation conflicts.

### apps/web-platform/infra/server.tf

```hcl
resource "hcloud_server" "web" {
  # ... existing fields ...

  user_data = templatefile("${path.module}/cloud-init.yml", {
    image_name                = var.image_name
    deploy_ssh_public_key     = var.deploy_ssh_public_key
    ci_deploy_script_b64      = base64encode(file("${path.module}/ci-deploy.sh"))
  })
}
```

### apps/telegram-bridge/infra/server.tf

```hcl
resource "hcloud_server" "bridge" {
  # ... existing fields ...

  user_data = templatefile("${path.module}/cloud-init.yml", {
    image_name                = var.image_name
    deploy_ssh_public_key     = var.deploy_ssh_public_key
    ci_deploy_script_b64      = base64encode(file("${path.module}/../../web-platform/infra/ci-deploy.sh"))
  })
}
```

**Path trace for telegram-bridge:** `apps/telegram-bridge/infra/` + `../../` = `apps/`, then `web-platform/infra/ci-deploy.sh`. Verified correct.

### apps/web-platform/infra/cloud-init.yml (write_files entry replacement)

Replace the 129-line inline script block (lines 39-174) with:

```yaml
  # CI deploy forced command script. The CI SSH key in authorized_keys uses:
  #   restrict,command="/usr/local/bin/ci-deploy.sh" ssh-ed25519 AAAA... ci-deploy-2026@soleur-web-platform
  # This restricts the CI key to only execute deploy commands (see #747).
  # Content injected from ci-deploy.sh via Terraform base64encode(file()) -- do not inline.
  - path: /usr/local/bin/ci-deploy.sh
    encoding: b64
    content: ${ci_deploy_script_b64}
    owner: root:root
    permissions: '0755'
```

### apps/telegram-bridge/infra/cloud-init.yml (write_files entry replacement)

Same pattern, with the bridge-specific comment:

```yaml
  # CI deploy forced command script. The CI SSH key in authorized_keys uses:
  #   restrict,command="/usr/local/bin/ci-deploy.sh" ssh-ed25519 AAAA... ci-deploy-2026@soleur-bridge
  # This restricts the CI key to only execute deploy commands (see #747).
  # Content injected from ci-deploy.sh via Terraform base64encode(file()) -- do not inline.
  - path: /usr/local/bin/ci-deploy.sh
    encoding: b64
    content: ${ci_deploy_script_b64}
    owner: root:root
    permissions: '0755'
```

### Why base64encode() is better than indent()

- **No indentation pitfalls.** The base64 string is a single line -- no multi-line YAML alignment needed.
- **No template interpolation risk.** The base64 encoding happens in HCL before the string enters the template, so bash `${...}` expressions in the script never touch the template parser.
- **cloud-init native support.** The `encoding: b64` field is a first-class cloud-init feature ([write_files documentation](https://docs.cloud-init.io/en/latest/reference/yaml_examples/write_files.html)).
- **Simpler template.** One line instead of a multi-line block scalar with indentation rules.

## MVP -- Approach B: `indent()` (Fallback)

If base64 is undesirable (e.g., for readability of `terraform plan` output), use `indent()` with correct placement.

**Critical: `indent(N, str)` does NOT indent the first line.** The first line gets its indentation from its position in the template file. Subsequent lines get N spaces prepended.

([Source: Terraform docs](https://developer.hashicorp.com/terraform/language/functions/indent) -- "adds a given number of spaces to the beginnings of all lines in a given multi-line string, **except the first line**")

### Correct template pattern

```yaml
  - path: /usr/local/bin/ci-deploy.sh
    content: |
      ${indent(6, ci_deploy_script)}
    owner: root:root
    permissions: '0755'
```

How this works:

- The `${indent(6, ci_deploy_script)}` placeholder is at column 6 (6 spaces from left margin).
- The **first line** of `ci_deploy_script` (e.g., `#!/usr/bin/env bash`) inherits the 6-space indentation from the placeholder's position in the template.
- **All subsequent lines** get 6 spaces prepended by `indent()`.
- Result: every line of the script is at 6-space indentation, which is correct for YAML `content: |` at this nesting level.

### server.tf for indent approach

Same as Approach A but pass the raw string without base64:

```hcl
ci_deploy_script = file("${path.module}/ci-deploy.sh")
```

### Edge case: trailing newline

`file()` reads the file including its trailing newline. In a YAML block scalar (`|`), a trailing newline is preserved. This matches the current behavior of the inline script (which also has a trailing newline before `owner:`). No special handling needed.

## References

### Terraform documentation

- [Terraform `file()` function](https://developer.hashicorp.com/terraform/language/functions/file)
- [Terraform `templatefile()` function](https://developer.hashicorp.com/terraform/language/functions/templatefile)
- [Terraform `indent()` function](https://developer.hashicorp.com/terraform/language/functions/indent) -- "adds spaces to all lines except the first"
- [Terraform `base64encode()` function](https://developer.hashicorp.com/terraform/language/functions/base64encode)

### cloud-init documentation

- [cloud-init `write_files` with encoding](https://docs.cloud-init.io/en/latest/reference/yaml_examples/write_files.html) -- `encoding: b64` support

### Community discussions (informed approach selection)

- [Wrong indent with multiline content in cloud-init write_files](https://discuss.hashicorp.com/t/wrong-indent-with-multiline-content-to-cloud-init-write-files-content-directives/35011) -- recommends `base64encode()` or `yamlencode()` over manual indentation
- [templatefile should keep consistent indentation for multiline strings](https://github.com/hashicorp/terraform/issues/29824) -- confirms `indent()` is the official workaround, documents first-line behavior
- [Wrong indentation in YAML inserted into terraform template](https://discuss.hashicorp.com/t/wrong-indentation-in-yaml-file-inserted-into-terraform-template/31450)

### Project context

- Issue: #843
- Related: #825 (restrict CI deploy SSH key), #747 (original forced command implementation)
- Learning: `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md`
