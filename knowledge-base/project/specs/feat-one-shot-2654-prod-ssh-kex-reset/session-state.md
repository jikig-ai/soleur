# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2654-prod-ssh-kex-reset/knowledge-base/project/plans/2026-04-19-fix-prod-ssh-kex-reset-plan.md
- Status: complete

### Errors

None

### Decisions

- Root-cause hypothesis pinned: `ssh deploy@<ip>` typo → `AllowUsers root` rejects → 5 rejected connections within 10 min triggers fail2ban `[sshd]` jail → `bantime.increment = true` with no upstream `bantime.maxtime` default escalates ban exponentially.
- Two-phase fix: Phase 1 operator unban via Hetzner Cloud Console (one unavoidable manual step — SSH is the channel that's down); Phase 2+3 codify tuning in Terraform via new `terraform_data.fail2ban_tuning` following the existing `disk_monitor_install` pattern.
- Tuning knobs: explicit `bantime=10m`, `findtime=10m`, `maxretry=5`, `bantime.increment=true`, `bantime.factor=2`, `bantime.maxtime=1h` (load-bearing new knob — caps worst-case recovery time). Rejected `ignoreip = <operator IP>` (stale-whitelist drift) and `bantime = -1` (permanent lockout).
- Firewall left unchanged — already correctly scoped to `var.admin_ips`.
- No new tests — infrastructure-only, exempted from TDD gate; verification is runtime via `fail2ban-client -d` and `get` subcommands on the live host.

### Components Invoked

- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Bash, Read, WebSearch, ToolSearch, Grep, Write, Edit
