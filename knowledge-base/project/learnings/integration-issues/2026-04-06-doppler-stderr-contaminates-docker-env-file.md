---
module: Deploy Pipeline
date: 2026-04-06
problem_type: integration_issue
component: tooling
symptoms:
  - "docker: invalid env file (/tmp/doppler-env.XXX): variable 'Using DOPPLER_CONFIG_DIR from the environment' contains whitespaces"
  - "DEPLOY_ERROR: ci-deploy.sh failed at line 140 (exit 125)"
  - "Health check version mismatch after 120s polling (expected new version, got old)"
root_cause: config_error
resolution_type: code_fix
severity: critical
tags: [doppler, docker, stderr, env-file, deploy-pipeline, ci-deploy]
---

# Learning: Doppler CLI stderr warning contaminates Docker env file

## Problem

Every deploy since v0.13.44 failed silently. The release workflow built and pushed Docker images to GHCR successfully, the deploy webhook fired (HTTP 202), but the server continued serving the old version. The health check polling (12 attempts over 120s) always reported a version mismatch.

The error in `journalctl -u webhook`:

```text
docker: invalid env file (/tmp/doppler-env.YVZXc4): variable 'Using DOPPLER_CONFIG_DIR from the environment. To disable this, use --no-read-env.' contains whitespaces
```

## Investigation Steps

1. **SSH diagnosis confirmed DOPPLER_CONFIG_DIR was set** -- the ProtectHome fix from PR #1575 was already applied via terraform. The plan's hypothesis (terraform not applied) was wrong.
2. **journalctl revealed the real error** -- Doppler CLI outputs a warning to stderr when `DOPPLER_CONFIG_DIR` is in the environment. In `ci-deploy.sh:35`, `2>&1` merged this warning into stdout.
3. **The contaminated output was written to the env file** -- Docker's `--env-file` parser rejects lines with spaces that aren't in `KEY=VALUE` format.
4. **Docker run failed (exit 125)** -- The ERR trap fired, but the async webhook had already returned HTTP 202. CI never saw the failure. The old container kept running.

## Root Cause

In `ci-deploy.sh`, the `resolve_env_file()` function used `2>&1` to capture both stdout and stderr from `doppler secrets download`:

```bash
# BEFORE (broken):
doppler_output=$(doppler secrets download --no-file --format docker ... 2>&1)
echo "$doppler_output" > "$tmpenv"
```

When `DOPPLER_CONFIG_DIR=/tmp/.doppler` is set in the environment (added by the ProtectHome fix), Doppler CLI emits a warning to stderr: `"Using DOPPLER_CONFIG_DIR from the environment. To disable this, use --no-read-env."` This warning was captured into `$doppler_output` and written to the env file alongside the actual secrets.

## Solution

Separated stderr from stdout by redirecting stderr to a temporary file:

```bash
# AFTER (fixed):
doppler_stderr_file=$(mktemp /tmp/doppler-stderr.XXXXXX)
doppler_output=$(doppler secrets download --no-file --format docker ... 2>"$doppler_stderr_file")
# On failure: read stderr file for error message
# On success: clean up stderr file
rm -f "$doppler_stderr_file"
echo "$doppler_output" > "$tmpenv"
```

Also increased health check polling from 120s to 300s (12 to 30 attempts) and replaced fragile `grep -q "ok"` with `jq -r '.status'` for robust status checking.

## Key Insight

Never use `2>&1` when capturing command output that will be written to a file parsed by another tool (Docker env files, config files, JSON). CLI tools may emit warnings to stderr that contaminate the output. Redirect stderr to a separate file or `/dev/null`, and read it only on failure for diagnostics.

This is a variant of the "invisible stderr" pattern documented in `2026-04-06-doppler-protecthome-readonly-config-dir-fix.md` -- in that case, `2>/dev/null` swallowed the actual error. Here, `2>&1` captured too much. The correct approach is `2>"$tmpfile"` -- stderr is preserved for diagnostics but kept out of the primary output stream.

## Session Errors

1. **Doppler DNS resolution failure** -- `doppler run` failed with "server misbehaving" during first terraform apply attempt. Recovery: retried and succeeded. **Prevention:** Add retry logic to terraform apply wrapper scripts, or verify DNS resolution before running doppler commands.

2. **Terraform init required before plan** -- `terraform plan` failed because backend wasn't initialized. Recovery: ran `terraform init` first. **Prevention:** Always run `terraform init` before `terraform plan/apply` when working from a fresh worktree (the `.terraform/` directory is not checked in).

3. **Terraform variable injection via --name-transformer** -- `terraform plan` failed with missing variables because `doppler run -c prd_terraform` does not auto-convert secret names to `TF_VAR_*` format. Recovery: discovered CI uses `--name-transformer tf-var` flag. **Prevention:** When running terraform commands locally with Doppler, always use `doppler run --name-transformer tf-var` to match CI behavior. Also export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` separately for the S3/R2 backend (the transformer renames them to `TF_VAR_*` which the backend ignores).

4. **Plan's root cause hypothesis was wrong** -- The plan identified ProtectHome/terraform-not-applied as the root cause, but SSH diagnosis revealed the fix was already applied. **Prevention:** Always run SSH diagnosis to confirm the hypothesis before applying terraform changes. Don't trust plan assumptions -- verify server state first.

## Prevention

- When writing shell scripts that capture command output for use as config/data files, always separate stderr from stdout
- Use `2>"$stderr_file"` instead of `2>&1` or `2>/dev/null` -- this preserves diagnostics without contaminating the primary output
- Test deploy scripts with all environment variables set that will be present in production (including variables like `DOPPLER_CONFIG_DIR` that trigger CLI warnings)

## Cross-References

- `knowledge-base/project/learnings/integration-issues/2026-04-06-doppler-protecthome-readonly-config-dir-fix.md` -- Related: the ProtectHome fix that introduced `DOPPLER_CONFIG_DIR` into the environment, which triggered this warning
- `knowledge-base/project/learnings/2026-04-05-stale-env-deploy-pipeline-terraform-bridge.md` -- Related: the terraform_data provisioner pattern for pushing deploy script fixes
- GitHub issue #1602 -- The tracking issue for this fix
- GitHub issue #1620 -- Review finding: restore EXIT trap for env file cleanup (defense-in-depth)

## Tags

category: integration-issues
module: deploy-pipeline
