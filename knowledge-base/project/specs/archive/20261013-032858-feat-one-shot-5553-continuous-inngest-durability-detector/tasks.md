# Tasks — Continuous between-deploy inngest durability detector (#5553)

Plan: `knowledge-base/project/plans/2026-06-18-feat-continuous-inngest-durability-detector-plan.md`
Lane: cross-domain · Threshold: single-user incident (CPO sign-off required pre-/work)

## Phase 0 — Preconditions (no code)
- [x] 0.1 Re-read canonical durability logic `ci-deploy.sh:264-299` + seam precedent `inngest-wiped-volume-verify.sh:97-98`
- [x] 0.2 Confirm #5503 purity test gates at `inngest-inventory.test.sh:88-101`
- [x] 0.3 Confirm `inngest-inventory.test.sh` runs in CI (`infra-validation.yml:199-200`)
- [x] 0.4 Confirm `inngest-inventory` in Vector tag allowlist (`vector.toml:132`)

## Phase 1 — inngest-inventory.sh: derive + emit durability_state
- [x] 1.1 Add `derive_durability_state()` mirroring `ci-deploy.sh:277-287` with seams `INVENTORY_EXECSTART` / `INVENTORY_REDIS_ACTIVE`; verdict enum durable|degraded|sqlite_only|unknown; never echo ExecStart
- [x] 1.2 Add `durability_state` as 4th key in final jq object (extend lines 204-205)
- [x] 1.3 Append `durability=<enum>` to journald summary (line 201) — enum only, no values
- [x] 1.4 Update header doc-comment (lines 7-10): new field + seam env vars; **AND correct the stale line ~35 "does NOT reach Better Stack — see #5495" — it DOES now via vector.toml:132 (#5526)** [review obs-P2]

## Phase 2 — inngest-inventory.test.sh: seam + state cases (RED first)
- [x] 2.1 Add `run_inv_durability()` helper (mirror `run_inv()` lines 79-81)
- [x] 2.2 Five verdict cases: durable / degraded(no-redis-flag) / degraded(redis-inactive) / sqlite_only / unknown
- [x] 2.3 Secret-leak guard: assert connection-string token absent from `2>&1` (mirror SECRET-BODY guard lines 145-165)
- [x] 2.4 Purity regression: object has 4 keys incl durability_state; success-path stderr empty

## Phase 3 — cross-file drift guard (token tripwire, NOT verdict-equivalence proof)
- [x] 3.1 Drift-guard test asserts all three parsers (ci-deploy.sh, inngest-wiped-volume-verify.sh, inngest-inventory.sh) reference `--postgres-uri`, `--redis-uri`, `inngest-redis.service`, `inngest-server.service` [review P1-1/P2-3]

## Phase 4 — scheduled-inngest-health.yml: continuous detector
- [x] 4.1 Probe reads `.durability_state // "absent"` → `$GITHUB_OUTPUT` (strip_log_injection); `absent`→`::notice::` (older host, benign), literal `unknown`→`::warning::` (redeployed host read-failure) [review P1-2/P1-3]
- [x] 4.2 Advisory step gated healthy-AND-(sqlite_only OR **degraded**): `gh label create ci/inngest-degraded-durability`; file/comment idempotent issue; **priority/p1-high for degraded, priority/p2-medium for sqlite_only**; transition comment on sqlite_only↔degraded; cite runbook + #5450 [review P0-1, P2-1]
- [x] 4.3 Auto-close step gated healthy-AND-durable (mirror inngest_down auto-close lines 160-174); only absent/unknown neither file nor close — **degraded DOES file via 4.2**
- [x] 4.4 Leave existing Sentry heartbeat (lines 176-185) unchanged

## Phase 5 — Local verification (no SSH, no prod write)
- [x] 5.1 `bash apps/web-platform/infra/inngest-inventory.test.sh` → 0 FAIL
- [x] 5.2 `shellcheck apps/web-platform/infra/inngest-inventory.sh` clean
- [x] 5.3 `actionlint .github/workflows/scheduled-inngest-health.yml` + `bash -c` each new run-block (NEVER `bash -n` the yml)
- [x] 5.4 Manual fixture run → `jq .durability_state`

## Acceptance Criteria (see plan for verify commands)
- [x] AC1 four-key object incl valid durability_state enum
- [x] AC2 five verdict cases pass
- [x] AC3 secret purity (SECRET-DSN absent, count 0)
- [x] AC4 #5503 purity preserved
- [x] AC5 cross-file drift guard passes (4 tokens incl inngest-server.service)
- [x] AC6 workflow actionlint-clean + writes durability_state output
- [x] AC7 advisory gated on non-durable union (sqlite_only OR degraded); p1 for degraded, p2 for sqlite_only; auto-close on durable — **degraded MUST file**
- [x] AC8 missing field→absent (notice, no issue); literal unknown→warning (no issue); neither restarts
- [x] AC9 hooks.json.tmpl unchanged
- [x] AC10 no `ssh ` in diff
- [ ] AC11 (post-merge) release pipeline re-stages script; cron reads field; no advisory on durable host
