---
title: "Tasks — workspaces-luks cutover SSH bridge bring-up (Option C)"
plan: knowledge-base/project/plans/2026-07-18-fix-workspaces-luks-cutover-ssh-bridge-bringup-plan.md
branch: feat-one-shot-cutover-bridge-bringup
lane: cross-domain
---

# Tasks

## Phase 0 — Preconditions (verify, no code)
- [ ] 0.1 Confirm `web_hosts["web-1"].private_ip == "10.0.1.10"` (variables.tf:110) and tunnel ingress `ssh://…private_ip:22` (tunnel.tf:69-72).
- [ ] 0.2 `git diff origin/main --stat` shows only the three target files will change.

## Phase 1 — Composite action: optional `server-ip` (walls #1 + #2)
- [ ] 1.1 Add input `server-ip` (`required: false`, default `''`) to `.github/actions/cf-tunnel-ssh-bridge/action.yml`.
- [ ] 1.2 Add `SERVER_IP_INPUT: ${{ inputs.server-ip }}` to the "Start cloudflared SSH bridge…" step `env:`.
- [ ] 1.3 Guard the terraform read: `SERVER_IP="$SERVER_IP_INPUT"; [[ -z "$SERVER_IP" ]] && SERVER_IP=$(terraform output -raw server_ip)` — keep the empty-check + `::error::` for the terraform branch byte-for-byte.

## Phase 2 — Composite action: keyfile + WEB_HOST_SSH/GIT_DATA_SSH export (wall #3)
- [ ] 2.1 In the "Decode CI SSH private key…" step, after the existing heredoc write, write `$KEY` to `KEYFILE=$(mktemp)`; `chmod 600 "$KEYFILE"`.
- [ ] 2.2 Export `CI_SSH_KEYFILE`, `WEB_HOST_SSH`, `GIT_DATA_SSH` to `$GITHUB_ENV`; the ssh vars = `ssh -i $KEYFILE -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root`.
- [ ] 2.3 Broaden the step name to reflect the added keyfile/export.
- [ ] 2.4 Correct the five false comments (header OUTPUTS/PREREQUISITES :48-57; the ProxyCommand claims) → key + keyfile + iptables NAT redirect; terraform-init only required when `server-ip` unset.

## Phase 3 — Cutover + verify workflows
- [ ] 3.1 `workspaces-luks-cutover.yml`: pass `server-ip: "10.0.1.10"` to the bridge step.
- [ ] 3.2 `workspaces-luks-cutover.yml`: add `if: always()` teardown after "Run workspaces-luks cutover" — NAT delete (`-d "$SERVER_IP"`), kill `$CLOUDFLARED_PID`, shred `$CI_SSH_KEYFILE`, dump `/tmp/cloudflared.log` (all `-n`/`-f` guarded; model on apply:801-823).
- [ ] 3.3 `workspaces-luks-verify.yml`: pass `server-ip: "10.0.1.10"`; add the same `if: always()` teardown.
- [ ] 3.4 `workspaces-luks-verify.yml`: fix the `:59` comment ("key + ProxyCommand" → "key + iptables NAT redirect").

## Phase 4 — Verify
- [ ] 4.1 `actionlint` clean on `workspaces-luks-cutover.yml` + `workspaces-luks-verify.yml` (NOT on `action.yml` — extract `run:` snippets → `bash -n`/shellcheck).
- [ ] 4.2 `bash apps/web-platform/infra/workspaces-luks-header.test.sh` passes (H7 green — no AWS creds in cutover workflow).
- [ ] 4.3 `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` passes.
- [ ] 4.4 `git diff origin/main -- .github/workflows/apply-web-platform-infra.yml` empty; same for `git-data-cutover.yml`.
- [ ] 4.5 `grep -c terraform .github/workflows/workspaces-luks-{cutover,verify}.yml` = 0.
- [ ] 4.6 PR body uses `Ref #6649` (not `Closes`).

## Phase 5 — Post-merge (ship / operator)
- [ ] 5.1 `/soleur:ship` (or operator) dispatches `gh workflow run workspaces-luks-cutover.yml -f dry_run=true -f confirm=CUTOVER-WORKSPACES-LUKS`.
- [ ] 5.2 Approve the `workspaces-luks-cutover` environment gate (sole human authorization — not automatable past approval).
- [ ] 5.3 `gh run view <id> --log` (NO ssh): confirm bridge step green (no exit 127) + escrow probe GREEN; then close #6649.
