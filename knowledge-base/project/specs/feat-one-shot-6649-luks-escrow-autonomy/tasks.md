# Tasks — workspaces-luks escrow autonomy (#6649)

Plan: `knowledge-base/project/plans/2026-07-18-fix-6649-workspaces-luks-escrow-autonomy-plan.md`
Lane: cross-domain · Brand threshold: single-user incident · ADR-119 (addendum)

## Phase 0 — Preconditions (verify, no code)
- [ ] 0.1 Confirm `WEB_HOST_SSH` = `ssh … -l root` (lands root; pipes tar + stdin) — `.github/actions/cf-tunnel-ssh-bridge/action.yml`.
- [ ] 0.2 Confirm scoped cutover `-target` set is EXACTLY the five workspaces_luks resources (`apply-web-platform-infra.yml:2660-2664`) — new `github_actions_secret` must NOT go there.
- [ ] 0.3 Verify (WebFetch GH Actions docs) an empty-string job `environment:` runs ungated; else use split-job fallback.

## Phase 1 — BLOCKER 3: content-carrier → file execution
- [ ] 1.1 Harden `workspaces-cutover.sh` `${BASH_SOURCE[0]}` → `${BASH_SOURCE[0]:-…}` (`:63/:475/:477/:478`). (luks-monitor.sh NOT hardened — always run as a file.)
- [ ] 1.2 cutover.yml: `REMOTE_DIR` on **STATE_DIR** (`mktemp -d -p /var/lib/workspaces-luks`, chmod 700 — NOT tmpfs `/tmp`, or shred is a no-op / F7); tar-pipe bundle (workspaces-cutover.sh + workspaces-luks-emit.sh + luks-monitor.{sh,service,timer}); write `.env` + arm shred trap + run `bash <dir>/workspaces-cutover.sh` in ONE remote `bash -c` (no sudo — root already, preserves HOME=/root); preserve `WEB_HOST_SSH` guard + `set +e`/rc/`::error::`.
- [ ] 1.3 cutover.yml: `if: always()` teardown SSHes `rm -rf "$REMOTE_DIR"` (belt-and-suspenders; trap already shredded `.env`).
- [ ] 1.4 verify.yml: tar-pipe `luks-monitor.sh`+emit to STATE_DIR; SAME 0600-stdin-envfile + host-local shred discipline for the boot token; run `bash <dir>/luks-monitor` (read-only) — replaces `sudo /usr/local/bin/luks-monitor`.

## Phase 2 — BLOCKER 4: boot-token delivery
- [ ] 2.1 workspaces-luks.tf: add `github_actions_secret.workspaces_luks_boot_token` → `doppler_service_token.workspaces_luks.key` (no `ignore_changes`); reconcile the env-gate comment (`:190-210`) AND the `workspaces-luks-cutover.yml:9-16` comment block for the conditional/split gate.
- [ ] 2.2 apply-web-platform-infra.yml: add TWO `-target` lines to the DEFAULT allow-list (near `:361`): `doppler_service_token.workspaces_luks` + `github_actions_secret.workspaces_luks_boot_token`. (Mirror the inngest precedent.)
- [ ] 2.3 terraform-target-parity.test.ts: **REMOVE** `doppler_service_token.workspaces_luks` from `OPERATOR_APPLIED_TOKEN_EXCLUSIONS` (#5566 rule `:686-688` — a token feeding a github_actions_secret MUST be targeted, not excluded). Verify interaction with the general 5-resource exclusion + scoped gate against the inngest precedent.
- [ ] 2.4 cutover.yml: step env `WORKSPACES_LUKS_BOOT_TOKEN` + fail-loud presence check; write 0600 root `.env` over stdin (`install -m600 /dev/stdin`) with DOPPLER_TOKEN+WORKSPACES_LUKS_DEV+DRY_RUN+ROLLBACK; source it; shred on host-local EXIT trap (same `bash -c` as 1.2). NEVER `sudo VAR=val`.
- [ ] 2.5 workspaces-cutover.sh (real arm): persist `DOPPLER_TOKEN` into `/etc/default/luks-monitor` (0600 root, preserve baked DSN).
- [ ] 2.6 luks-monitor.service: add `Environment=HOME=/root`.

## Phase 3 — BLOCKER 5: WORKSPACES_LUKS_DEV
- [ ] 3.1 cutover.yml: resolve volume id via hcloud API by name `soleur-web-platform-data-luks` (HCLOUD_TOKEN from prd_terraform), regex-guard numeric, build `/dev/disk/by-id/scsi-0HC_Volume_<id>`; `curl --max-time` pinned. Pass via the Phase-2 `.env`.

## Phase 4 — AUTONOMY: gate only the freeze arm
- [ ] 4.1 workspaces-luks-cutover.yml:62 → `environment: ${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}` (fail-closed). Fallback: split rehearse/freeze jobs with static `environment:` on freeze.
- [ ] 4.2 ADR-119 authorization-model addendum (conditional gate + reversibility proof + truth table).

## Phase 5 — Tests + verification
- [ ] 5.1 Extend `workspaces-luks-header.test.sh` (cover BOTH cutover.yml + verify.yml): file-execution (assert the ASSEMBLED `install`+`trap`+`bash <file>` command, not just `tar xzf`) / no-`bash -s` / no `sudo VAR=val` argv / token-via-stdin-only / `.env` on STATE_DIR (not tmpfs) / shred-on-EXIT / WORKSPACES_LUKS_DEV passed / fail-closed env expression (mutation-RED on the inverted `dry_run && '' || 'X'` form) / `HOME=/root` in service (mirror `web-git-data-probe.test.sh:120-121`) / reviewers non-empty. Mutation-test each.
- [ ] 5.2 Run all suites green: workspaces-luks.test.sh, web-1-swap-concurrency-parity.test.sh, terraform-target-parity.test.ts (vitest), test-workspaces-luks-cutover-gate.sh.
- [ ] 5.3 Post-merge (autonomous): DEFAULT apply publishes token + attaches volume → confirm prd_workspaces_luks has 4 header keys → `gh workflow run workspaces-luks-cutover.yml -f dry_run=true -f confirm=CUTOVER-WORKSPACES-LUKS` runs WITHOUT approval → probe GREEN (read from Sentry/Better Stack) → `gh issue close 6649 --comment "<run URL> — escrow probe green"`.
