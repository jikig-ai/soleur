# Tasks — Continuous between-deploy inngest durability detector (#5553)

Plan: `knowledge-base/project/plans/2026-06-18-feat-continuous-inngest-durability-detector-plan.md`
Lane: cross-domain · Threshold: single-user incident (CPO sign-off required pre-/work)

## Phase 0 — Preconditions (no code)
- [ ] 0.1 Re-read canonical durability logic `ci-deploy.sh:264-299` + seam precedent `inngest-wiped-volume-verify.sh:97-98`
- [ ] 0.2 Confirm #5503 purity test gates at `inngest-inventory.test.sh:88-101`
- [ ] 0.3 Confirm `inngest-inventory.test.sh` runs in CI (`infra-validation.yml:199-200`)
- [ ] 0.4 Confirm `inngest-inventory` in Vector tag allowlist (`vector.toml:132`)

## Phase 1 — inngest-inventory.sh: derive + emit durability_state
- [ ] 1.1 Add `derive_durability_state()` mirroring `ci-deploy.sh:277-287` with seams `INVENTORY_EXECSTART` / `INVENTORY_REDIS_ACTIVE`; verdict enum durable|degraded|sqlite_only|unknown; never echo ExecStart
- [ ] 1.2 Add `durability_state` as 4th key in final jq object (extend lines 204-205)
- [ ] 1.3 Append `durability=<enum>` to journald summary (line 201) — enum only, no values
- [ ] 1.4 Update header doc-comment (lines 7-10): new field + seam env vars

## Phase 2 — inngest-inventory.test.sh: seam + state cases (RED first)
- [ ] 2.1 Add `run_inv_durability()` helper (mirror `run_inv()` lines 79-81)
- [ ] 2.2 Five verdict cases: durable / degraded(no-redis-flag) / degraded(redis-inactive) / sqlite_only / unknown
- [ ] 2.3 Secret-leak guard: assert connection-string token absent from `2>&1` (mirror SECRET-BODY guard lines 145-165)
- [ ] 2.4 Purity regression: object has 4 keys incl durability_state; success-path stderr empty

## Phase 3 — cross-file drift guard
- [ ] 3.1 Drift-guard test asserts all three parsers (ci-deploy.sh, inngest-wiped-volume-verify.sh, inngest-inventory.sh) reference `--postgres-uri`, `--redis-uri`, `inngest-redis.service`

## Phase 4 — scheduled-inngest-health.yml: continuous detector
- [ ] 4.1 Probe step reads `.durability_state // "unknown"` → `$GITHUB_OUTPUT` (via strip_log_injection)
- [ ] 4.2 New advisory step gated healthy-AND-sqlite_only: `gh label create ci/inngest-degraded-durability`; file/comment idempotent issue (priority/p2-medium); cite runbook + #5450
- [ ] 4.3 Auto-close step gated healthy-AND-durable (mirror inngest_down auto-close lines 160-174); degraded/unknown neither file nor close
- [ ] 4.4 Leave existing Sentry heartbeat (lines 176-185) unchanged

## Phase 5 — Local verification (no SSH, no prod write)
- [ ] 5.1 `bash apps/web-platform/infra/inngest-inventory.test.sh` → 0 FAIL
- [ ] 5.2 `shellcheck apps/web-platform/infra/inngest-inventory.sh` clean
- [ ] 5.3 `actionlint .github/workflows/scheduled-inngest-health.yml` + `bash -c` each new run-block (NEVER `bash -n` the yml)
- [ ] 5.4 Manual fixture run → `jq .durability_state`

## Acceptance Criteria (see plan for verify commands)
- [ ] AC1 four-key object incl valid durability_state enum
- [ ] AC2 five verdict cases pass
- [ ] AC3 secret purity (SECRET-DSN absent, count 0)
- [ ] AC4 #5503 purity preserved
- [ ] AC5 cross-file drift guard passes
- [ ] AC6 workflow actionlint-clean + writes durability_state output
- [ ] AC7 advisory step gating + labels; auto-close gating
- [ ] AC8 missing field tolerated as unknown, no spurious issue/restart
- [ ] AC9 hooks.json.tmpl unchanged
- [ ] AC10 no `ssh ` in diff
- [ ] AC11 (post-merge) release pipeline re-stages script; cron reads field; no advisory on durable host
