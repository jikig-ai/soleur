# Tasks: Resolve Terraform Infrastructure Drift

## Phase 1: Setup

- [x] 1.1 Sync worktree to latest main (`git fetch origin && git merge origin/main`)
- [x] 1.2 Verify Terraform files match expected state (DMARC reject, Cloudflare IPs in firewall)

## Phase 2: Terraform Apply

- [x] 2.1 Run `terraform init` in `apps/web-platform/infra/`
- [x] 2.2 Run `terraform plan` and confirm exactly 2 changes, 0 adds, 0 destroys
- [x] 2.3 Run `terraform apply -auto-approve` to push desired state to live infrastructure

## Phase 3: Verification

- [x] 3.1 DNS verify: `dig TXT _dmarc.soleur.ai +short` shows `p=reject`
- [x] 3.2 Health check: `curl https://app.soleur.ai/health` returns 200
- [x] 3.3 Re-run `terraform plan` to confirm zero drift (0 to add, 0 to change, 0 to destroy)

## Phase 4: Cleanup

- [x] 4.1 Close issue #1899 with resolution comment
