# Tasks — inngest vector delivery (#11602 + #7596)

Plan: `knowledge-base/project/plans/2026-10-30-chore-inngest-vector-delivery-plan.md`

## Phase 1 — Probes

- [ ] 1.1 Create `scripts/followthroughs/inngest-hostmetrics-trim-11602.sh`: trailing-window (default 24h) GROUP BY `tags.collector` isolated on `tags.host='soleur-inngest'` (metric rows = native Vector shape, no top-level host/host_name — the issue's own grouping field) via `scripts/betterstack-query.sh`; exit 0 PASS iff observed set == {memory, filesystem} with ≥1 row each; exit 2 TRANSIENT (`untrimmed`/`no_host_metrics`/`query_failed`/`credentials_unprovisioned`); xtrace refusal exit 78; header: credential posture, exit contract, TRACKER #11602, directive block, RETIREMENT list.
- [ ] 1.2 Create `scripts/followthroughs/inngest-hostmetrics-trim-11602.test.sh` with the Guard Contract Guard-2 battery (rows 1–3, 6): untrimmed fixture → TRANSIENT; empty window → TRANSIENT; partial set → TRANSIENT; stubbed-always-TRANSIENT probe → suite RED.
- [ ] 1.3 Edit `scripts/followthroughs/inngest-bs-token-restage-7596.sh`: add generation floor (`MIN_DT` baked at filing/enrollment date (ISO-8601, suite-asserted) + `_BOOT_ID` must positively resolve AND match the newest `inngest-server-probe` boot id — unresolvable → TRANSIENT `boot_id_unresolvable`); BOOT_STAGE curl-marker second read; leg-attributed TRANSIENT reasons (`pre_replace`/`leg_unit` — no `leg_journald` TRANSIENT: arm-2 PASS preempts it); second PASS arm on post-floor `bs-token-restaged` markers carrying `pass_arm=boot_stage journald_rows=absent` in output (journald arm preferred when both present); update header exit table + TRACKER note + add `RETIREMENT:` block.
- [ ] 1.4 Create `scripts/followthroughs/inngest-bs-token-restage-7596.test.sh`: floor-exclusion row, `boot_id_unresolvable` fixture (post-floor row + absent server-probe → no exit 0), leg-attribution rows, both PASS arms, stubbed-probe RED row.
- [ ] 1.5 Register both new suites in `scripts/test-all.sh` via explicit `run_suite` lines (orphan linter `EXCLUSIONS=()` is empty — unregistered = CI blocker).

## Phase 2 — Guard + docs

- [ ] 2.1 Add **Guard A4 (#11602)** to `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` after Guard A3: pinned-tag + HEAD `[sources.host_metrics]` asserts (`scrape_interval_secs = 900`, `collectors = ["memory", "filesystem"]`), own counted span + anti-vacuity row.
- [ ] 2.2 Run the full `cloud-init-inngest-bootstrap.test.sh` suite green against the current `v1.1.67` pin.
- [ ] 2.3 Edit `knowledge-base/engineering/operations/runbooks/inngest-server.md`: amend `### Post-replace: the boot-trace allowlist (#7596)` (~L298-346) in place — `leg_*` verdict taxonomy, automated sweeper close, #11602 counterpart — not merely a rider append.

## Phase 3 — Verify + enroll

- [ ] 3.1 Live-read verification (read-only): `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/inngest-hostmetrics-trim-11602.sh` exits 2 `untrimmed`; `inngest-bs-token-restage-7596.sh` exits 2 `channel_dark`-family.
- [ ] 3.2 Run the shard(s) containing the touched suites; green.
- [ ] 3.3 Branch sweeper dry-run: `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true` — both trackers' `exit=` lines report expected TRANSIENT reasons, never PASS.
- [ ] 3.4 `gh issue edit` both issues **post-merge**: add `follow-through` label; paste unfenced column-0 directive (`script=` respective probe, `earliest=<filing-date>T00:00:00Z`, `secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD`); comment on each issue with enrollment note + anomaly evidence + deferred operator dispatch.
- [ ] 3.5 PR body: `Refs #11602 #7596` (never Closes); `## Changelog` section; deferred operator step named verbatim (`gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='…'`).

## Deferred operator step (tracked, not executed)

- `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='deliver vector.toml trim (#11602) + boot-trace allowlist (#7596); riders: epic #10390 bucket 2'` — owner-only, fresh per-command go per `hr-prod-host-config-change-immutable-redeploy`.
