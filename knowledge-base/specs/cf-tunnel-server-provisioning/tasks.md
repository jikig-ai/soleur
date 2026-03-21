# Tasks: Cloudflare Tunnel Server-Side Provisioning

## Phase 1: Credential Gathering

- [ ] 1.1 Retrieve hcloud API token from Hetzner Cloud console (or create new project token)
- [ ] 1.2 Retrieve Cloudflare API token (`soleur-terraform-tunnel`) from Cloudflare dashboard
- [ ] 1.3 Retrieve Cloudflare zone ID and account ID from Cloudflare dashboard
- [ ] 1.4 Source or regenerate `WEBHOOK_DEPLOY_SECRET` value
- [ ] 1.5 Retrieve Doppler service token for prd config
- [ ] 1.6 Identify current admin IP(s) from Hetzner firewall rules
- [ ] 1.7 Create `terraform.tfvars` with all gathered credentials (gitignored)

## Phase 2: Terraform State Bootstrap

- [ ] 2.1 Run `terraform init` in `apps/web-platform/infra/`
- [ ] 2.2 Import hcloud resources
  - [ ] 2.2.1 Import `hcloud_ssh_key.default`
  - [ ] 2.2.2 Import `hcloud_server.web`
  - [ ] 2.2.3 Import `hcloud_volume.workspaces`
  - [ ] 2.2.4 Import `hcloud_volume_attachment.workspaces`
  - [ ] 2.2.5 Import `hcloud_firewall.web`
  - [ ] 2.2.6 Import `hcloud_firewall_attachment.web`
- [ ] 2.3 Import Cloudflare resources
  - [ ] 2.3.1 Import `cloudflare_record.app` (A record)
  - [ ] 2.3.2 Import `cloudflare_record.deploy` (CNAME)
  - [ ] 2.3.3 Import `cloudflare_record.dkim_resend` (TXT)
  - [ ] 2.3.4 Import `cloudflare_record.spf_send` (TXT)
  - [ ] 2.3.5 Import `cloudflare_record.mx_send` (MX)
  - [ ] 2.3.6 Import `cloudflare_record.dmarc` (TXT)
  - [ ] 2.3.7 Import `cloudflare_zero_trust_tunnel_cloudflared.web`
  - [ ] 2.3.8 Import `cloudflare_zero_trust_tunnel_cloudflared_config.web`
  - [ ] 2.3.9 Import `cloudflare_zero_trust_access_application.deploy`
  - [ ] 2.3.10 Import `cloudflare_zero_trust_access_service_token.deploy`
  - [ ] 2.3.11 Import `cloudflare_zero_trust_access_policy.deploy_service_token`
- [ ] 2.4 Import `random_id.tunnel_secret` (may need special handling)
- [ ] 2.5 Run `terraform plan` -- verify zero changes (or only expected drift)
- [ ] 2.6 Fix any drift between Terraform config and actual resource state

## Phase 3: Server-Side Provisioning (via SSH)

- [ ] 3.1 SSH into server: `ssh root@<server_ip>`
- [ ] 3.2 Install cloudflared
  - [ ] 3.2.1 Download Cloudflare GPG key
  - [ ] 3.2.2 Add Cloudflare apt repository
  - [ ] 3.2.3 `apt-get update && apt-get install -y cloudflared`
- [ ] 3.3 Register cloudflared service: `cloudflared service install <CF_TUNNEL_TOKEN>`
- [ ] 3.4 Verify cloudflared: `systemctl status cloudflared` shows active
- [ ] 3.5 Install webhook binary
  - [ ] 3.5.1 Download webhook v2.8.2 binary
  - [ ] 3.5.2 Verify SHA256 checksum: `4e41966a498b92d3e7a645968e0d55589f1a03d8bb327b0ccaadc3ea9a3a12ee`
  - [ ] 3.5.3 Extract to `/usr/local/bin/webhook` and `chmod +x`
- [ ] 3.6 Write `/etc/webhook/hooks.json` with HMAC secret
- [ ] 3.7 Write `/etc/systemd/system/webhook.service`
- [ ] 3.8 Deploy ci-deploy.sh to `/usr/local/bin/ci-deploy.sh` (from repo, `chmod 755`)
- [ ] 3.9 `systemctl daemon-reload && systemctl enable --now webhook`
- [ ] 3.10 Verify webhook: `curl -sf localhost:9000/hooks/deploy` returns 403

## Phase 4: Cloudflare Access Configuration

- [ ] 4.1 Activate Zero Trust team domain in Cloudflare dashboard (browser interaction)
- [ ] 4.2 Verify Access application for `deploy.soleur.ai` exists and is enforcing
- [ ] 4.3 Verify service token `github-actions-deploy` exists
- [ ] 4.4 Verify Access policy allows service token with `non_identity` decision
- [ ] 4.5 Set `CF_ACCESS_CLIENT_ID` GitHub secret (from Terraform output)
- [ ] 4.6 Set `CF_ACCESS_CLIENT_SECRET` GitHub secret (from Terraform output)

## Phase 5: Firewall Hardening

- [ ] 5.1 Verify tunnel routes traffic correctly before removing SSH rules
- [ ] 5.2 Remove `0.0.0.0/0` SSH firewall rule (keep admin_ips rules)
- [ ] 5.3 Apply firewall change via Terraform or Hetzner console
- [ ] 5.4 Verify admin SSH still works after firewall change

## Phase 6: End-to-End Verification

- [ ] 6.1 Trigger `web-platform-release.yml` via `workflow_dispatch`
- [ ] 6.2 Monitor workflow: release job creates tag, deploy job sends webhook
- [ ] 6.3 Verify: deploy webhook returns 200, container deploys, health check passes
- [ ] 6.4 Verify: `https://app.soleur.ai` is accessible
- [ ] 6.5 Verify: external port scan shows no open ports (except ICMP)
- [ ] 6.6 Trigger `telegram-bridge-release.yml` to verify bridge deploy path

## Phase 7: Cleanup and Documentation

- [ ] 7.1 Add `HCLOUD_TOKEN` and `CLOUDFLARE_API_TOKEN` to Doppler (optional, recommended)
- [ ] 7.2 Update issue #967 with completion status
- [ ] 7.3 Close issue #967
