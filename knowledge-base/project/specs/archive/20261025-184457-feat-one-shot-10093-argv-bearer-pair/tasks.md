# Tasks — feat-one-shot-10093-argv-bearer-pair

Plan: `knowledge-base/project/plans/2026-10-25-fix-argv-bearer-xtrace-refusals-probes-plan.md`
Issues: closes #10363 (xtrace refusals), closes #10093 (argv-bearer residual, already converted — verification + closure).

## Phase 1 — inngest-consumer-probe: refusal + resolve-after-refusal + unit

- [ ] 1.1 `apps/web-platform/infra/inngest-consumer-probe.sh`: insert unconditional xtrace refusal (`case "$-" in *x*)` → printf FATAL to stderr → `exit 78`) after `set -u` (line 2), before the header comment; shape per `web-private-nic-guard.sh:12-14`.
- [ ] 1.2 `inngest-consumer-probe.sh`: replace `URL="${INNGEST_CONSUMER_URL:-}"` (~line 83) with the #10637 block — `_key_ok` (LC_ALL=C, `[A-Z][A-Z0-9_]*` only), `unset URL; URL=""; KEY_BAD=false`, `if _key_ok "${INNGEST_CONSUMER_URL_KEY:-}"; then URL="${!INNGEST_CONSUMER_URL_KEY:-}"; else KEY_BAD=true; fi`; add the KEY_BAD second WARN line on the empty-URL arm of `_ping` (~line 135), copied in shape from `web-zot-consumer-probe.sh:145-147`. Update header comment (test seams + resolve-after-refusal contract).
- [ ] 1.3 `apps/web-platform/infra/inngest-consumer-probe.service`: ExecStart (line 40) → `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /usr/local/bin/inngest-consumer-probe.sh'`; update the comment block (lines 29-38) documenting the old wrapper.
- [ ] 1.4 `apps/web-platform/infra/doppler-injection-bound.test.sh`: remove `inngest-consumer-probe.service` from `WRAPPER_ACK_REASONS` (~line 326), `WRAPPER_ACK_CARDINALITY` 2→1, reword the class-A `ACK_REASONS` entry (~line 271) to the sibling phrasing ("the script resolves INNGEST_CONSUMER_URL_KEY by indirect expansion …"), fix comment counts.
- [ ] 1.5 `apps/web-platform/infra/inngest-consumer-probe.test.sh`: add the F6 block mirroring `web-zot-consumer-probe.test.sh:1283-1404` — real-ExecStart replay under `SHELLOPTS=xtrace` + `BASH_ENV`, refusal[key-only] row, untraced positive row (one stdin `url = "..."` delivery), mutant[hoist] order row.

## Phase 2 — rendered heartbeat body: POSIX refusal + test row

- [ ] 2.1 `apps/web-platform/infra/inngest-bootstrap.sh`: inside the quoted `HEARTBEATSCRIPTEOF` heredoc (~line 185-193), add `case $- in *x*) ... exit 78 ;; esac` as the FIRST executable statement, above `LOG_TAG=`; printf to stderr, value-free AND name-free (no `INNGEST_HEARTBEAT_URL`, no `logger` before LOG_TAG exists). House-style comment citing #7797/#10363.
- [ ] 2.2 `apps/web-platform/infra/inngest.test.sh`: add traced-run row(s) beside `run_ping`/`hb_run` — `sh -x` on the rendered body (WEB_PING; DEDICATED_PING if cheap) with sentinel `INNGEST_HEARTBEAT_URL`: rc=78, refusal on a non-`+` line, sentinel in no stream. Update the suite count ledger comment (~line 3097) if present.

## Phase 3 — verification + closure

- [ ] 3.1 Run the S6-HB derived scan over `apps/web-platform/infra/*.sh` (zero violations, `S6H_ALLOW` empty) + `git grep` evidence for the #10093 list (3 probe scripts, `cloud-init-registry.yml` both heartbeat curls, 4 skill files — all `--config -`); record the user_data/metadata-API residual as out-of-fix-shape.
- [ ] 3.2 Green runs: `inngest-consumer-probe.test.sh`, `inngest.test.sh`, `web-zot-consumer-probe.test.sh`, `doppler-injection-bound.test.sh`, `journald-config.test.sh`, `infra-config-gate.test.sh`, `tests/scripts/test-argv-bearer-sweep.sh` (S6-HB), `lint-shell-trace-credential-refusal.test.sh` + the lint's repo-wide A/B/C+D+E runs (baselines unchanged).
- [ ] 3.3 PR body: `Closes #10363`, `Closes #10093`, merge-consequence block (push-apply redelivery of `terraform_data.inngest_consumer_probe_install`; auto `vinngest-v*` mint + image build + pin bump; heartbeat body lands on next `deploy inngest`/replace). No production apply scheduled by this plan.
