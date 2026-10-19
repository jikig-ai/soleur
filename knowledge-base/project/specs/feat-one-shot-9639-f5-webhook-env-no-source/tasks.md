# Tasks - fix: read the webhook-deploy token with sed instead of sourcing it as root (#9639 F5)

Plan: knowledge-base/project/plans/2026-10-19-fix-webhook-deploy-env-read-not-sourced-plan.md
PR body: `Ref #9639`, `Part of tracker #9217` (no closing keyword). Do NOT touch cloud-init.yml, betterstack-logs-alerts.tf, apply-web-platform-infra.yml, server.tf.

## Phase 1 - Tests first (RED): cron-egress-enforce-probe.test.sh
- [x] 1.1 Extend the `doppler` stub to append `${DOPPLER_TOKEN-UNSET}` to `$STUBS/doppler-tok` (not the argv `calls` log).
- [x] 1.2 Add `make_probe_copy` (sed path rewrite of a COPY of the real probe) with an anti-vacuity check that the rewrite hit.
- [x] 1.3 Add `run_probe_copy` driving the container_absent branch with `DOPPLER_TOKEN=inherited-tok` exported.
- [x] 1.4 Rows: F5-S1 static (both scripts, code lines only, non-vacuity), F5-H1 hostile fixture, F5-H2 negative control (`. fixture` variant must execute), F5-P1 non-canonical must-pass fixture, F5-P2 empty/absent fixture keeps inherited token, F5-P3 no-export parity.
- [x] 1.5 Run the suite on the unfixed tree; confirm F5-S1 and F5-H1 are RED; record for the PR body.

## Phase 2 - Bootstrap behavioral block: soleur-host-bootstrap-observability.test.sh
- [x] 2.1 awk-extract `_sentry_emit`, assert non-empty, rewrite the path, run under dash with doppler/curl stubs and SOLEUR_SENTRY_DSN unset.
- [x] 2.2 Rows: hostile no-exec, negative control executes, canonical fixture leaves the token unexported (stub sees UNSET).
- [x] 2.3 If extraction proves brittle, ship the static row only and file a follow-up.

## Phase 3 - GREEN
- [x] 3.1 cron-egress-enforce-probe.sh: add the `# shellcheck disable=SC2034` directive above the assignment (new bare assignment trips SC2034); replace `. /etc/default/webhook-deploy ...` with `_t=$(sed -n 's/^DOPPLER_TOKEN=//p' /etc/default/webhook-deploy 2>/dev/null | tail -n 1)` + `[ -z "$_t" ] || DOPPLER_TOKEN=$_t`; refresh the stale header and `LIMIT:` comments.
- [x] 3.2 soleur-host-bootstrap.sh `_sentry_emit`: identical two lines (POSIX sh).
- [x] 3.3 Run both suites, `bash -n`, `dash -n`, shellcheck; confirm the Sentry TRANSPORT parity and AC8c blocks still pass.

## Phase 4 - Sweep and wrap
- [x] 4.1 `git grep -n "\. /etc/default/webhook-deploy" -- apps/web-platform/infra`: only the cloud-init terminal block may remain.
- [x] 4.2 File a deferred-scope-out tracking issue for that remaining site (blocked on #10501), with milestone from roadmap.md.
- [x] 4.3 Run cron-egress-firewall.test.sh and cloud-init-web-zot-seed.test.sh to confirm no other pin moved.
