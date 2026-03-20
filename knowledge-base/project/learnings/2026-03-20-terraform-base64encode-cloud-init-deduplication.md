# Learning: Terraform base64encode(file()) for cloud-init write_files deduplication

## Problem

`apps/web-platform/infra/ci-deploy.sh` (135 lines, tested by `ci-deploy.test.sh`) was copy-pasted verbatim into the `write_files` section of both `apps/web-platform/infra/cloud-init.yml` and `apps/telegram-bridge/infra/cloud-init.yml`. This created three independent copies of the same script with two compounding risks:

1. **Drift**: The standalone file had gained `docker system prune` calls that the cloud-init copies lacked. Any future edit to the script would need to be applied in three places.
2. **Interpolation collision**: The inline bash used `${...}` expressions (e.g., `${SSH_ORIGINAL_COMMAND:0:200}`) that collide with Terraform's `templatefile()` syntax. If the servers were ever reprovisioned, `terraform plan` would fail on undeclared variable references. This was a latent bug -- it hadn't fired yet because the servers hadn't been reprovisioned since the script was embedded.

## Solution

Replace inline script content in both `cloud-init.yml` files with Terraform's `base64encode(file())` injection pattern.

### server.tf (each app's infra/)

```hcl
data "cloudinit_config" "server" {
  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init.yml", {
      # ... existing variables ...
      ci_deploy_script_b64 = base64encode(file("${path.module}/ci-deploy.sh"))
    })
  }
}
```

For telegram-bridge, which shares the same script file via cross-module reference:

```hcl
ci_deploy_script_b64 = base64encode(file("${path.module}/../../web-platform/infra/ci-deploy.sh"))
```

### cloud-init.yml (write_files entry)

```yaml
- path: /usr/local/bin/ci-deploy.sh
  permissions: "0755"
  owner: root:root
  encoding: b64
  content: ${ci_deploy_script_b64}
```

Cloud-init's `write_files` natively supports `encoding: b64` -- it decodes the base64 content before writing the file to disk. No decode step is needed in `runcmd`.

## Key Insight

When embedding shell scripts in Terraform-templated YAML (cloud-init), `base64encode(file())` is the correct deduplication strategy. The three alternatives each have concrete failure modes:

1. **`indent()` + YAML block scalar (`|`)**: Terraform's `indent()` does NOT indent the first line (by design -- see HashiCorp docs). This breaks YAML block scalars because the first line of content sits at the wrong indentation level, causing cloud-init schema validation to fail.

2. **`$${...}` escaping**: Terraform's double-dollar escape prevents interpolation, but it trades copy-paste duplication for escape-character maintenance. Every new `${...}` in the script requires a corresponding `$${...}` in the template -- a different maintenance burden, not elimination of it.

3. **Separate shared Terraform module**: Architecturally clean but over-engineered for a 2-app monorepo sharing a single file. A cross-module `file()` reference (`${path.module}/../../web-platform/infra/ci-deploy.sh`) is pragmatic and grep-discoverable.

The `base64encode(file())` approach has zero interaction with Terraform interpolation (the base64 string contains no `${}` sequences), preserves the script as a standalone testable file, and uses a cloud-init feature (`encoding: b64`) that exists specifically for this purpose.

## Session Errors

1. **Ralph loop script path was wrong**: The initial implementation referenced the ralph loop script at `skills/one-shot/scripts/` instead of the correct `scripts/` path. Lesson: when a plan specifies relative paths, trace each `../` step to verify the final target before implementing. This is already codified in AGENTS.md but the error recurred, confirming the rule earns its keep.

2. **Specs directory created with wrong prefix**: The specs directory was initially created as `feat-deduplicate-ci-deploy-843/` instead of `deduplicate-ci-deploy-843/`. The `feat-` prefix belongs on git branch names, not knowledge-base directory names. Lesson: naming conventions that apply in one namespace (git branches) don't automatically transfer to another (filesystem directories) -- check the existing convention in the target namespace.

3. **Security-sentinel false positive on cloud-init schema validation**: A review agent predicted that the `encoding: b64` approach would fail cloud-init schema validation. Local testing with `cloud-init schema -c cloud-init.yml` proved it passes on both templates. Lesson: when an automated reviewer predicts a failure, run the actual validation before accepting the verdict. Review agents reason from training data which may not cover all valid configurations.

## Tags

category: integration-issues
module: apps/web-platform/infra, apps/telegram-bridge/infra
