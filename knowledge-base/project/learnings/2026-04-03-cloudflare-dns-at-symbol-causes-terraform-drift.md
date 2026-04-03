# Learning: Cloudflare DNS `@` symbol causes perpetual Terraform drift

## Problem

The scheduled Terraform drift detection workflow flagged perpetual drift in `apps/web-platform/infra/`. The `cloudflare_record.google_site_verification` TXT record showed a destroy-and-recreate plan every run because `name = "@"` in the config didn't match `name = "soleur.ai"` in the Cloudflare API's stored state.

The Cloudflare API accepts `@` (DNS shorthand for zone apex) on creation but normalizes it to the FQDN on storage. The Terraform provider v4.x reads back the FQDN, sees a mismatch with the config's `@`, and since `name` is a `ForceNew` attribute, plans a destroy+recreate every time.

## Solution

Changed `name = "@"` to `name = "soleur.ai"` in `apps/web-platform/infra/dns.tf`. Added an inline comment explaining why. `terraform validate` and `terraform fmt` both pass. The config now matches the API's stored state, producing a clean plan.

Updated the existing learning `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` with a zone-apex naming table.

## Key Insight

Never use `@` for zone-apex DNS records in Cloudflare Terraform configs. Always use the FQDN. This applies to both provider v4 and v5. The drift is invisible during initial `terraform apply` — it only manifests on subsequent `terraform plan` runs. A post-apply `terraform plan` in the same session would catch this immediately.

## Session Errors

1. **Bare repo `core.bare=true` leaks into worktree git commands** — ~20 repeated `git status --short` failures from the bare repo root. `git -C` and `cd && git` both failed. Recovery: `GIT_WORK_TREE=$WT GIT_DIR=$WT/.git git <cmd>`. **Prevention:** Add AGENTS.md rule documenting the `GIT_WORK_TREE`/`GIT_DIR` pattern for bare repos. Updated existing learning `2026-03-13-bare-repo-git-rev-parse-failure.md`.

2. **Command repetition loop** — The agent generated the identical failing command ~20 times without modifying it. This is a model-level failure pattern where the same command is retried without adjustment. **Prevention:** Cannot be prevented by a rule (model behavior), but the `GIT_WORK_TREE`/`GIT_DIR` pattern being documented should prevent the root cause from recurring.

3. **`terraform fmt` exit code 3 after edit** — Adding an inline comment caused Terraform formatting mismatch (extra spaces before `#`). Fixed immediately with `terraform fmt`. **Prevention:** Always run `terraform fmt` after editing `.tf` files (already enforced by lefthook pre-commit hook).

## Tags

category: integration-issues
module: infrastructure, terraform, cloudflare, dns
