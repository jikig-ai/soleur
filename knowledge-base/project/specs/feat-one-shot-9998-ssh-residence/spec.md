---
title: "provisioner-parity: SSH resources in non-server.tf files escape fleet classification (G2 residence is web-2-only)"
issue: 9998
branch: feat-one-shot-9998-ssh-residence
lane: single-domain
type: fix
date: 2026-10-12
---

# Spec — #9998 provisioner-parity G2 fleet-dialer residence

## Ask

`gh issue view 9998`: Guard 2's residence check in
`apps/web-platform/infra/web-host-provisioner-parity.test.sh` is web-2-only, so an
SSH `connection` block in any other `.tf` file dialing web-1 (or a future web-3)
with a valid `host_key` evades the §1 fleet classification (`uncovered`, `stale`,
`_fleet_extra`). Fix shape per the issue: extend the G2 residence rule to all
declared fleet hosts (or add a `w1_elsewhere` arm), plus battery row G2-19 proving
a web-1-dialing block WITH the correct local reds via `outside server.tf`.

## Scope

Single-domain (engineering infra tooling): two files under
`apps/web-platform/infra/` — the guard and its mutation battery. Plan:
`knowledge-base/project/plans/2026-10-12-fix-provisioner-parity-ssh-residence-plan.md`.

## Key correction vs the issue body

Four SSH `terraform_data` resources dialing web-1 already live outside server.tf
(`ci-ssh-key.tf:root_authorized_keys`; `workspaces-luks.tf:luks_monitor_token_install`,
`luks_monitor_install`, `workspaces_boot_unlock_install`), so the residence arm
ships with a per-resource, host-scoped, reason-mandatory `EXT_RESIDENCE` allowance
rather than a blanket rule — see plan §Research Insights / §Proposed Solution.
