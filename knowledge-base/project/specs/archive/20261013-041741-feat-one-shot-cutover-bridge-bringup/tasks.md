---
title: "Tasks — workspaces-luks cutover SSH bridge bring-up (Option C, gated)"
plan: knowledge-base/project/plans/2026-07-18-fix-workspaces-luks-cutover-ssh-bridge-bringup-plan.md
branch: feat-one-shot-cutover-bridge-bringup
lane: cross-domain
---

# Tasks

## Phase 0 — Preconditions (verify, no code)
- [x] 0.1 Confirm `web_hosts["web-1"].private_ip == "10.0.1.10"` (variables.tf:110) and tunnel ingress `ssh://…private_ip:22` (tunnel.tf:69-72).
- [x] 0.2 `git diff origin/main --stat` will touch only: action.yml + workspaces-luks-cutover.yml + workspaces-luks-verify.yml.

## Phase 1 — Composite action: optional `server-ip` (walls #1 + #2)
- [x] 1.1 Add input `server-ip` (`required: false`, default `''`) to `.github/actions/cf-tunnel-ssh-bridge/action.yml`.
- [x] 1.2 Add `SERVER_IP_INPUT: ${{ inputs.server-ip }}` to the "Start cloudflared SSH bridge…" step `env:`.
- [x] 1.3 Guard ONLY the terraform read: `SERVER_IP="${SERVER_IP_INPUT:-}"; if [[ -z "$SERVER_IP" ]]; then SERVER_IP=$(terraform output -raw server_ip); fi`. Keep the empty-check + `::error::`, the `::add-mask::`, and the `SERVER_IP=… >> $GITHUB_ENV` export COMMON to both branches (teardown needs SERVER_IP on the server-ip path).

## Phase 2 — Composite action: gated keyfile + WEB_HOST_SSH/GIT_DATA_SSH export (wall #3)
- [x] 2.1 In the "Decode CI SSH private key…" step, add `SERVER_IP_INPUT: ${{ inputs.server-ip }}` to `env:` and wrap the new block in `if [[ -n "$SERVER_IP_INPUT" ]]; then … fi`.
- [x] 2.2 Inside the gate, IN ORDER: `KEYFILE=$(mktemp); chmod 600 "$KEYFILE"; echo "CI_SSH_KEYFILE=$KEYFILE" >> "$GITHUB_ENV"; printf '%s\n' "$KEY" > "$KEYFILE"` (path exported BEFORE key bytes — spec-flow Gap4).
- [x] 2.3 Export `WEB_HOST_SSH` and `GIT_DATA_SSH` = `ssh -i $KEYFILE -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root` to `$GITHUB_ENV`. Keep GIT_DATA_SSH (consumed by git-data-cutover.sh:82-83,109; refuted "drop" finding).
- [x] 2.4 Broaden the step name to reflect the keyfile/export.
- [x] 2.5 Correct action.yml OUTPUTS/PREREQUISITES header (:48-57) → key+keyfile+NAT-redirect reality; terraform-init only when `server-ip` unset. Extend the CALLER-SIDE TEARDOWN CONTRACT block (:23-46) to document the keyfile shred for server-ip callers.

## Phase 3 — Cutover + verify workflows
- [x] 3.1 `workspaces-luks-cutover.yml`: pass `server-ip: "10.0.1.10"` to the bridge step.
- [x] 3.2 `workspaces-luks-cutover.yml` Run step: add fail-loud guard `[[ -n "${WEB_HOST_SSH:-}" ]] || { echo "::error::bridge did not export WEB_HOST_SSH"; exit 1; }` before the ssh; keep the `# shellcheck disable=SC2086`.
- [x] 3.3 `workspaces-luks-cutover.yml`: add `if: always()` teardown after "Run workspaces-luks cutover" — `set +e` only (no set -u); NAT delete guarded `${SERVER_IP:-}`; kill `${CLOUDFLARED_PID:-}`; shred `[[ -n "${CI_SSH_KEYFILE:-}" && -f "$CI_SSH_KEYFILE" ]] && shred -u "$CI_SSH_KEYFILE" 2>/dev/null || true`; dump /tmp/cloudflared.log (model apply:801-823).
- [x] 3.4 `workspaces-luks-verify.yml`: pass `server-ip: "10.0.1.10"`; add the same fail-loud guard + `if: always()` teardown.
- [x] 3.5 `workspaces-luks-verify.yml`: add `# shellcheck disable=SC2086` above the `${WEB_HOST_SSH:-ssh}` line (:68) — HIGH (mirrors cutover:112); fix the `:59` comment ("key + ProxyCommand" → "key + iptables NAT redirect").

## Phase 4 — Verify
- [x] 4.1 `actionlint` clean on cutover + verify (shellcheck installed so SC2086 is evaluated). Do NOT actionlint action.yml — extract `run:` → `bash -n`/shellcheck.
- [x] 4.2 `bash apps/web-platform/infra/workspaces-luks-header.test.sh` passes (H7 green).
- [x] 4.3 `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` passes.
- [x] 4.4 `git diff origin/main -- .github/workflows/apply-web-platform-infra.yml` empty; same for `git-data-cutover.yml`.
- [x] 4.5 `grep -c terraform .github/workflows/workspaces-luks-{cutover,verify}.yml` = 0.
- [x] 4.6 Standing guard: `grep -E 'WEB_HOST_SSH|GIT_DATA_SSH|CI_SSH_KEYFILE' apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml` → nothing.
- [x] 4.7 PR body uses `Ref #6649` (not `Closes`).

## Phase 5 — Post-merge (ship / operator)
- [ ] 5.1 `/soleur:ship` (or operator) dispatches `gh workflow run workspaces-luks-cutover.yml -f dry_run=true -f confirm=CUTOVER-WORKSPACES-LUKS`.
- [ ] 5.2 Approve the `workspaces-luks-cutover` environment gate (sole human authorization — not automatable past approval).
- [ ] 5.3 `gh run view <id> --log` (NO ssh): confirm bridge step green (no exit 127) + escrow probe GREEN; then close #6649.
