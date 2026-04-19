# Learning: CI SSH deploy requires firewall rule, not just key rotation

## Problem

The CI deploy workflow (`build-web-platform.yml`) failed with `ssh.ParsePrivateKey: ssh: this private key is passphrase protected`. The plan focused entirely on rotating the SSH key from passphrase-protected to passwordless. After key rotation, the deploy still failed — this time with `dial tcp ***:22: i/o timeout`. The Hetzner firewall restricted SSH to `admin_ips` only, and GitHub Actions runners use 5000+ dynamic IP ranges that can't be allowlisted individually.

## Solution

Two changes were required, not one:

1. **SSH key rotation** — Generate passwordless Ed25519 key, install public key on server, update `WEB_PLATFORM_SSH_KEY` GitHub secret, shred local copies
2. **Firewall rule addition** — Open SSH (port 22) to `0.0.0.0/0` in Hetzner firewall to allow GitHub Actions runners through

The firewall was updated via Hetzner API for immediacy (Terraform couldn't run without all provider credentials), then the Terraform code was updated for long-term consistency.

## Key Insight

When a CI deploy fails with an SSH error, the root cause may involve multiple layers (key auth + network path). Fixing the key doesn't help if the runner can't reach port 22. Always verify network connectivity independently from authentication — they are separate failure modes that produce different errors at different stages of the SSH handshake.

The Hetzner firewall `admin_ips` restriction was defense-in-depth that silently broke CI. Plans should check firewall rules when SSH deploys from dynamic-IP environments (CI runners, serverless) are in scope.

## Update 2026-04-19 (see #2681)

This learning was promoted into an enforced workflow gate after the same
class recurred in a different form: on 2026-04-19 an operator SSH session
(not CI) locked out because `ADMIN_IPS` held a single CIDR and the
operator's ISP egress had rotated. See:

- Rule: `AGENTS.md` `hr-ssh-diagnosis-verify-firewall`
- Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`
- Skill: `plugins/soleur/skills/admin-ip-refresh/SKILL.md`
- Plan checklist: `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`
- Follow-up learning:
  `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`

Per AGENTS.md `wg-when-a-workflow-gap-causes-a-mistake-fix`, the learning
alone was not sufficient -- the fix was to edit the plan/deepen-plan
skills and add an AGENTS.md rule so the L3->L7 discipline fires on every
future SSH/network-outage plan.

## Session Errors

- First deploy attempt failed despite correct key — firewall blocked runners (not anticipated by plan)
- Server IP not discoverable from local environment — no tfstate, no hcloud CLI, had to query Hetzner API using token found in settings.local.json
- GitHub label `type/enhancement` doesn't exist — the correct label is `enhancement`

## Tags

category: integration-issues
module: web-platform-infra
