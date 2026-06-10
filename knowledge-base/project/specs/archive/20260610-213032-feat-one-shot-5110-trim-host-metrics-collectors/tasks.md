# Tasks — fix: trim Vector host_metrics collectors (Better Stack ≤25k rows/day, re-open of #5110)

Plan: `knowledge-base/project/plans/2026-06-10-fix-betterstack-host-metrics-collector-trim-plan.md`
Lane: cross-domain (no spec.md — TR2 fail-closed default)

## Phase 1 — vector.toml Source 4 collector trim

- [x] 1.1 Replace the Source 4 block (`apps/web-platform/infra/vector.toml:99-118`) with the trimmed form from plan Phase 1: `collectors = ["cpu", "memory", "disk", "filesystem", "load"]` (network dropped), `mountpoints.includes = ["/", "/mnt/data", "/var/lib/vector"]` added under `[sources.host_metrics.filesystem]`, `devices.excludes` retained on both sub-tables, 300s interval unchanged, updated comment (no `30s scrape` literal, no `"network"` literal anywhere in the file)
- [x] 1.2 Verify AC1–AC4 greps and AC5/AC6 diffs (awk exclusive-boundary form for AC6)

## Phase 2 — records

- [x] 2.1 `knowledge-base/operations/expenses.md` — append second-pass sentence to the Better Stack free-tier row Notes (no `|` chars; real PR number after `gh pr create`)
- [x] 2.2 `knowledge-base/engineering/operations/post-mortems/betterstack-quota-near-miss-postmortem.md` — append-only second-pass corrections (versions line + #5110 follow-up row description)

## Phase 3 — local verification (pre-push)

- [x] 3.1 Download pinned Vector 0.43.1 binary (form from `validate-vector-config.yml`)
- [x] 3.2 `vector validate --no-environment --config-toml apps/web-platform/infra/vector.toml` → exit 0 (AC7)
- [x] 3.3 `bash apps/web-platform/test/infra/vector-pii-scrub.test.sh` with `VECTOR_BIN` → green (AC8; `bun install --frozen-lockfile` in apps/web-platform first if node_modules absent)

## Phase 4 — PR

- [ ] 4.1 PR body: `Ref #5110` + `Ref #4296` (NEVER `Closes`), deployment note (tag v1.1.13 → image → pin bump → webhook → AC13 fast verdict → AC14 daily verdict), AC13/AC14 verdict rules (AC10)
- [ ] 4.2 CI `validate-vector-config.yml` green on the PR (AC11)

## Phase 5 — post-merge (operator; automation per AC12)

- [ ] 5.1 Tag merge commit `vinngest-v1.1.13` + push (re-check next free semver first)
- [ ] 5.2 `build-inngest-bootstrap-image.yml` run → success
- [ ] 5.3 Follow-up PR: `cloud-init.yml` pin `v1.1.12` → `v1.1.13` (all 4 occurrences; AC6 drift guard)
- [ ] 5.4 Deploy webhook `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.1.13` (HTTPS HMAC form; operator ack required)
- [ ] 5.5 `/hooks/deploy-status` → `exit_code: 0`, clean `vector_journal_tail`
- [ ] 5.6 Comment on #5110: second-pass remediation deployed (PR, tag, timestamp)
- [ ] 5.7 AC13 fast verdict (~30 min): per-5-min buckets ≤ 86 rows (predict ~69) AND filesystem series present (>0)
- [ ] 5.8 AC14 daily verdict (≥24h, first full post-deploy day): host rows ≤ 25,000 → comment exactly `RESULT: PASS` on #5110 (sweeper closes); else `RESULT: FAIL` + re-open with next lever
- [ ] 5.9 Issue hygiene: #5110 + #4296 still OPEN immediately after merge
