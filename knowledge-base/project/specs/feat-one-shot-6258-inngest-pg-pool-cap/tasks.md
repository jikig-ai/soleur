# Tasks — fix(inngest) web-host Postgres pool cap (#6258)

Plan: `knowledge-base/project/plans/2026-07-09-fix-inngest-web-host-pg-pool-cap-plan.md`
Branch: `feat-one-shot-6258-inngest-pg-pool-cap` · lane: cross-domain · threshold: single-user incident (requires_cpo_signoff)

## Phase 0 — Preconditions (no code)
- [ ] 0.1 Extract pinned `INNGEST_CLI_VERSION` from `inngest.tf` locals; confirm `--postgres-max-idle-conns` + `--postgres-conn-max-idle-time` exist in `inngest start --help` for that version. Pin the output (`<!-- verified: YYYY-MM-DD source: … -->`). If absent → pivot to per-pool `OPEN` lowering + CLI-bump task.
- [ ] 0.2 Confirm `SUPABASE_ACCESS_TOKEN` reaches the pooler-PATCH workflow (precedent: `scheduled-inngest-health.yml`, `scheduled-followthrough-sweeper.yml`).
- [ ] 0.3 Source-read the pinned inngest Go pool instantiation (`pgxpool.New`/`sql.Open` sites) → count P distinct pools. Confirms per-subsystem-vs-total before the live burst.

## Phase 1 — Diagnostic + immediate readiness (automatable, no code)
- [ ] 1.1 `gh workflow run restart-inngest-server.yml` (drops pinned pool; remediation #1; no SSH).
- [ ] 1.2 Read the live ExecStart (no-SSH) — decide H1 (flag present, still bursts → per-subsystem) vs H2 (flag absent → config drift).
- [ ] 1.3 Fire ≥6 `op=inventory` scans; re-measure inngest-attributable backends via the Management-API `pg_stat_activity` filter; record plateau + derive P. Persist P + plateau to the spec.

## Phase 2 — Durable fix: bound total + drain idle (code)
- [ ] 2.1 `inngest-bootstrap.sh:439` — durable `BACKEND_FLAGS='--postgres-max-open-conns <OPEN> --postgres-max-idle-conns <IDLE> --postgres-conn-max-idle-time <SECS>'` (sentinel FIRST). Values from 1.3: `P × OPEN ≤ pool_size − 5`, `IDLE ≤ 2`, `SECS ≤ 60`. Default posture keeps pool_size 30 + low OPEN.
- [ ] 2.2 Update flag-rationale comment `inngest-bootstrap.sh:363-371` (per-pool/total distinction + idle-drain lever + sentinel-first invariant).
- [ ] 2.3 Confirm no durability-parser edit needed (`inngest-inventory.sh:163`, `ci-deploy.sh:1007`, `inngest-wiped-volume-verify.sh:99` use substring sentinel). Note only.

## Phase 3 — Observability + pool-size reconciliation (AFTER Phase 2 verified)
- [ ] 3.1 `scheduled-inngest-health.yml:157` — set `INNGEST_CLIENT_CAP` to the measured post-fix total worst-case (comment cites 1.3).
- [ ] 3.2 Create `.github/workflows/apply-inngest-pooler-config.yml` — **`workflow_dispatch`-ONLY** (NOT merge-triggered): PATCH `…/config/database/pgbouncer` 30→15 via `SUPABASE_ACCESS_TOKEN` + GET-verify. DECOUPLED — may be split to a follow-up PR; never force the revert if footprint > 15 − headroom.

## Phase 4 — Cutover gate + decision-record correction (code/docs)
- [ ] 4.1 `cutover-inngest.yml` op=execute — pool pre-check before 2.1 capture; fail-closed on every non-clean state (pressure / EMAXCONNSESSION / 401 / non-JSON / empty / curl-fail).
- [ ] 4.2 `inngest.tf:201-232` — correct the #5558→#5562 decision block (remove "client cap 10 holds under 15"; record per-pool model + sequenced revert).
- [ ] 4.3 `runbooks/inngest-server.md:102-144` — update pool-pressure section (new flags + reconciled cap).
- [ ] 4.4 Vector allowlist: if a new host `logger -t <tag>` is added, add to `vector.toml` Source-4 `include_matches` + drift-guard fixture. Else state "no new host tag".
- [ ] 4.5 Author `ADR-103-inngest-postgres-footprint-per-pool-cap-and-idle-drain.md` (status: adopting; Decision + ≥3 Alternatives). Verify ADR-103 free vs origin/main at ship (ordinal provisional). Reference it in the spec FRs.

## Phase 5 — Deploy (immutable tag)
- [ ] 5.1 Push `vinngest-vX.Y.Z` tag → `build-inngest-bootstrap-image.yml` → `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vX.Y.Z`. Tag push in-PR (not operator).
- [ ] 5.2 Post-deploy: re-run 1.3 controlled burst → confirm bounded plateau, `op=inventory` clean (no EMAXCONNSESSION). Flip ADR-103 → accepted.

## Phase 6 — Tests
- [ ] 6.1 `inngest.test.sh` — assert durable `BACKEND_FLAGS` has all 3 flags, sentinel first; SQLite branch empty.
- [ ] 6.2 `cutover-inngest-workflow.test.sh` — 5 pre-check cases (Test Scenario 3).
- [ ] 6.3 `inngest-wiped-volume-verify` + `inngest-inventory` durability still classify `durable` on the widened flag set.
- [ ] 6.4 `actionlint` on edited/new workflows; `bash -c` extracted `run:` shell (NOT `bash -n` on YAML).

## Post-merge (agent-automated)
- [ ] P1 Push tag + deploy (AC11). P2 Post-deploy burst re-measure, no EMAXCONNSESSION (AC12). P3 Sequencing-gated `default_pool_size` 30→15 PATCH + GET-verify, only if total < 15 − headroom (AC13). P4 Close #6258 via `gh issue close` after P2/P3; PR body uses `Ref #6258` not `Closes` (ops-remediation).
