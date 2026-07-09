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
- [ ] 2.1 `inngest-bootstrap.sh:439` — durable `BACKEND_FLAGS='--postgres-max-open-conns 5 --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 30'` (sentinel FIRST). Conservative FIXED values, safe for any P ≤ 4 (`4×5=20 < 30`); `default_pool_size` stays 30. Lower OPEN only if Phase-0/1 finds P > 4.
- [ ] 2.2 Update flag-rationale comment `inngest-bootstrap.sh:363-371` (per-pool/total distinction + idle-drain lever + sentinel-first invariant).
- [ ] 2.3 Confirm no durability-parser edit needed (`inngest-inventory.sh:163`, `ci-deploy.sh:1007` + `:1851`, `inngest-wiped-volume-verify.sh:99` use substring sentinel). Note only (4 sites, incl. the ci-deploy degraded discriminator).

## Phase 3 — Health-probe cap reconciliation + #5562 re-scope (no prod-write)
- [ ] 3.1 `scheduled-inngest-health.yml:157` — set `INNGEST_CLIENT_CAP` to post-fix total worst-case (≤ 20). Also sweep stale prose `cap (10` at `:220`/`:343` + the stale `:354` ref (spec-flow I6).
- [ ] 3.2 **Do NOT create a pooler-PATCH workflow.** Keep `default_pool_size` at 30. Record the #5562 User-Challenge in `decision-challenges.md` (done) + file an `action-required` follow-up issue re-scoping #5562.

## Phase 4 — Cutover gate + decision-record correction (code/docs)
- [ ] 4.1 `cutover-inngest.yml` op=execute — pool pre-check FIRST (before the 2.0 registry probe); gate on readiness-baseline + burst-headroom (NOT the 80% alert line); fail-closed on every non-clean state (count≥threshold / EMAXCONNSESSION / 401 / non-JSON / empty / curl-fail).
- [ ] 4.2 `inngest.tf:201-232` — correct the #5558→#5562 decision block (remove "client cap 10 holds under 15"; record per-pool model + the decoupled keep-`default_pool_size`-30 posture — #5562 revert superseded, NOT executed).
- [ ] 4.3 `runbooks/inngest-server.md:102-144` — update pool-pressure section (new flags + reconciled cap).
- [ ] 4.4 Vector allowlist: if a new host `logger -t <tag>` is added, add to `vector.toml` Source-4 `include_matches` + drift-guard fixture. Else state "no new host tag".
- [ ] 4.5 Author `ADR-104-inngest-postgres-footprint-per-pool-cap-and-idle-drain.md` (status: adopting; Decision + ≥3 Alternatives). Verify ADR-104 free vs origin/main at ship (ordinal provisional). Reference it in the spec FRs.

## Phase 5 — Deploy (immutable tag)
- [ ] 5.1 Push `vinngest-vX.Y.Z` tag → `build-inngest-bootstrap-image.yml` → `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vX.Y.Z`. Tag push in-PR (not operator).
- [ ] 5.2 Post-deploy: re-run 1.3 controlled burst → confirm bounded plateau, `op=inventory` clean (no EMAXCONNSESSION). Flip ADR-104 → accepted.

## Phase 6 — Tests
- [ ] 6.1 `inngest.test.sh` — assert durable `BACKEND_FLAGS` has all 3 flags, sentinel first; SQLite branch empty.
- [ ] 6.2 `cutover-inngest-workflow.test.sh` — 5 pre-check cases (Test Scenario 3).
- [ ] 6.3 `inngest-wiped-volume-verify` + `inngest-inventory` durability still classify `durable` on the widened flag set.
- [ ] 6.4 `actionlint` on edited/new workflows; `bash -c` extracted `run:` shell (NOT `bash -n` on YAML).

## Post-merge (agent-automated)
- [ ] P1 Push `vinngest-v*` tag + deploy (AC11). P2 Post-deploy burst re-measure on BOTH hosts, no EMAXCONNSESSION, per-host plateau ≤ P×5 (AC12). P3 Verify `default_pool_size` still 30 via Management-API GET; #5562 revert NOT executed (AC13). P4 Close #6258 via `gh issue close` after P2; PR body uses `Ref #6258` not `Closes` (deploy/verify run post-merge).
