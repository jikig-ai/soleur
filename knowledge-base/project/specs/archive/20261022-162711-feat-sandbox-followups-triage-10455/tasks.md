# Tasks: feat-sandbox-followups-triage-10455 (PR-A, runtime Bash synthetic)

Plan: knowledge-base/project/plans/2026-10-20-feat-sandbox-runtime-synthetic-and-detection-gaps-plan.md. Ref #10455, never Closes.

## 1. Phase 1 — verdict mapping, probe entrypoint, synthetic script (RED first)
- 1.1 Write `web-bash-synthetic.test.sh` RED: nonce missing, each `no_ping` reason, rc 124 before/after dispatch, container replaced mid-run, memory pressure, no scratch-dir escape (Guard 1 rows 1-5)
- 1.2 Extract the shared verdict-mapping function from `run_sdk_bash_smoke` into `infra/lib/`; keep existing smoke tests green; add parity row (Guard 1 row 6)
- 1.3 Add probe runtime mode resolving the selector via bundled `resolveSandboxUnixDeny`; scratch-dir-only writes
- 1.4 Implement `web-bash-synthetic.{sh,service,timer}` until 1.1 is green

## 2. Phase 2 — delivery, heartbeat, arming, parity
- 2.1 `web-probe.tf` heartbeat (`for_each = var.web_hosts`, 900/1800, born paused) + per-host Doppler URL
- 2.2 `server.tf` install block + web-2 twin; `-target` list in `apply-web-platform-infra.yml`
- 2.3 `cloud-init.yml`, `soleur-host-bootstrap.sh`, `web-probe-envwrite.sh`, Dockerfile/.dockerignore, user-data size budget
- 2.4 `arm-heartbeats.sh` two literal `arm_one` calls + host-coverage test row; re-derive the ARM-gate ladder and workflow timeout
- 2.5 `vector.toml` three arrays; vector-admission, vector-pii-scrub, journald-config, doppler-injection-bound, fresh-boot-parity, web-host-provisioner-parity (`FLOOR_BLOCKS`), suite-shard-legs.tsv
- 2.6 `heartbeat-manifest.ts` row; heartbeat-live-reconcile, terraform-target-parity, heartbeat-reprovision-parity tests
- 2.7 Re-measure live Better Stack heartbeat count; `model.c4` counts; run c4-count-parity

## 3. Phase 3 — docs and tracking
- 3.1 ADR-079 addendum; `canary-probe-set.md` runtime-synthetic section
- 3.2 File debt issue (table-driven host-timer registry); comment PR-B checklist and "what shipped" note on #10455

## 4. Verify
- 4.1 Run every suite touched; `terraform validate`/`tflint`; confirm each Guard 1 mutation goes RED
