# Tasks — feat-one-shot-11103-execstart-cred-expansion

Plan: `knowledge-base/project/plans/2026-10-26-fix-inngest-execstart-inner-bash-credential-expansion-plan.md`
Issue: #11103 — inngest-redis + rendered inngest-server ExecStarts expand credentials in an inner `bash -c` (traced launch prints them to journald)

## Phase 1 — Failing assertions (TDD)

- [ ] 1.1 `apps/web-platform/infra/doppler-injection-bound.test.sh`: add the inner-`-c` stage — scanner (extract `bash -c` bodies, resolve `@@NAME@@` sentinels against same-file `NAME='...'`/`"..."` assignments, flag `\$+\{?[A-Z][A-Z0-9_]{2,}` except `${!...}`), `INNER_C_ACK_REASONS` + `INNER_C_ACK_CARDINALITY = 0`, `MIN_INNER_C_UNITS` census floor, identity pins for `inngest-redis.service` + rendered `inngest-server.service`
- [ ] 1.2 Same file: mutation battery rows per the plan's Guard Contract matrix (restore-requirepass, own-dispatch counter, second member, `@@` fragment expansion, scanner-side regex neuter, `sh -c` must-PASS, `${!...}` no-double-flag); raise `MIN_ASSERTIONS` to measured green count
- [ ] 1.3 `apps/web-platform/infra/inngest.test.sh`: `SERVERLAUNCH_BLOCK` extraction + refusal-first ordering assert + `sh -x`/`bash -x`/`SHELLOPTS=xtrace`/`BASH_ENV` replay block (exit 78, refusal on non-trace line, sentinel absent, guard-removed positive control); re-anchor assertions at :2434/:2464/:2497-2498/:2554-2574 to the launch-script heredoc
- [ ] 1.4 Run both suites — confirm RED, attributed to the two live sites (AC5, AC6)

## Phase 2 — Site 1: `inngest-redis.service` + conf + acl writer

- [ ] 2.1 `inngest-redis-bootstrap.sh`: new step after 3.5 installing `/usr/local/bin/inngest-redis-acl.sh` via `install -m 0755 /dev/stdin <<'ACLEOF'` — unconditional `case "$-"` refusal (exit 78) first, then non-empty + charset validation, then atomic 0600 `user default on >"$INNGEST_REDIS_PASSWORD" ~* &* +@all` write (AC2)
- [ ] 2.2 `inngest-redis.conf`: add `aclfile /mnt/data/redis/inngest-redis.acl`; rewrite the `requirepass` injection comment
- [ ] 2.3 `inngest-redis.service`: `ExecStart=/usr/bin/redis-server /mnt/data/redis/inngest-redis.conf`; new `ExecStartPre=/usr/bin/doppler run --config ${DOPPLER_CONFIG} --only-secrets INNGEST_REDIS_PASSWORD -- /usr/local/bin/inngest-redis-acl.sh` AFTER the mount-guard; comment updates (AC1)

## Phase 3 — Site 2: rendered `inngest-server.service` + launch script

- [ ] 3.1 `inngest-bootstrap.sh`: `SERVERLAUNCHEOF` heredoc → `/usr/local/bin/inngest-server-launch.sh` + `chmod 0755`, reconcile-always (outside `SKIP_BINARY_INSTALL`); refusal → `set -u` → signing-key strip → `@@BACKEND_ENV@@` → `exec ... "$@"` (AC4)
- [ ] 3.2 Same file: `ExecStart` → `doppler run --config @@DOPPLER_CONFIG@@ -- /usr/local/bin/inngest-server-launch.sh @@BACKEND_FLAGS@@ --poll-interval 60 --sdk-url @@SDK_URL@@`; `@@BACKEND_ENV@@` substitution retargeted to the script; durable fragment re-spelled single-`$` (AC3)
- [ ] 3.3 Comment updates at inngest-bootstrap.sh:1549-1587 (secrets-delivery prose names the new shape)

## Phase 4 — Comments sweep + green run

- [ ] 4.1 `cat-deploy-state.sh:746-747` and `inngest.tf:166` comment corrections
- [ ] 4.2 Green run: `doppler-injection-bound.test.sh`, `inngest.test.sh`, `journald-config.test.sh`, `vector-admission.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `cat-deploy-state.test.sh`, `inngest-cutover-flip.test.sh` (AC7, AC8)
- [ ] 4.3 Verify AC9 (`grep -c 'bash -c' inngest-redis.service` = 0; rendered unit expansion-free)

## Notes

- `GuardA` designed-advisory red expected while the `vinngest-v*` pin propagates (ADR-232) — non-required.
- Site-2 fix takes effect on the dedicated host only at the sanctioned replace (force-replace-only); repo-side fix lands now per the issue.
- `Closes #11103` in the PR body (label: `type/security`).
