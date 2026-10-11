# Tasks — Step A of #7258: zot consumer probe covers the inngest-bootstrap repo

Plan: `knowledge-base/project/plans/2026-10-11-chore-zot-consumer-probe-covers-inngest-bootstrap-plan.md`
Branch: `feat-one-shot-7258-consumer-probe-covers-inngest-bootstrap` | Draft PR: #9979 | PR body uses `Ref #7258`

## Phase 0 — Preconditions (read-only)

- [x] 0.1 Rebase on `origin/main` (never merge main); re-read `BASELINE_DECLARED_PROBES`
- [x] 0.2 Confirm no infra apply or replace workflow is in flight (strictly sequential)
- [x] 0.3 Telemetry existence evidence for `repository:jikig-ai/soleur-inngest-bootstrap` (query output to a file)
- [x] 0.4 Record baselines (heartbeat ids 473113 / 475781, canary counts, apply-stage health) for the PR body; re-confirm D5 concurrency evidence
- [x] 0.5 (not needed: no registry-side preflight applies to a probe-only change) If any registry-side preflight is needed, run it as `doppler run -p soleur -c prd_terraform -- <cmd> > "$SCRATCH/out" 2>&1`

## Phase 1 — RED tests (`web-zot-consumer-probe.test.sh`)

- [x] 1.1 Add `run_override_multi` helper; give EVERY helper a per-run temp `SOLEUR_PROBE_REPOS_MARKER`
- [x] 1.2 Rows T1-T6b (aggregation matrix, 401 no-early-exit, positional seam, empty/whitespace list, trailing comma)
- [x] 1.3 Row T7 (static parity vs the `ZIREF` pins, exact two-element set, non-empty extraction)
- [x] 1.4 Row T8 (mock registry serving two repos; stub-curl credential-channel rows generalized)
- [x] 1.5 Row T9 (marker: per-repo fields, rate limit, missing/empty/garbage/future-dated emits, 401 path)
- [x] 1.6 Run the suite; confirm the new rows fail and rows (a)-(h) + canary rows pass

## Phase 2 — Probe

- [x] 2.1 List parsing, empty-element skip, whitespace FATAL, `probed` gate
- [x] 2.2 Per-repo loop (curl line unchanged except `${r}`), no early exit, `repo=` on fault lines
- [x] 2.3 Extract `_window_open`; add `_repo_markers`; emit markers before aggregation
- [x] 2.4 Aggregation: any 401 -> exit 3; any fault -> no ping; all 200 -> ping
- [x] 2.5 Positional override seam; header comment (list contract, 20 s worst case)

## Phase 3 — Wiring and architecture record

- [x] 3.1 `web-probe.tf` locals (`zot_probe_repo_web`, `zot_probe_repo_inngest_bootstrap`, joined `zot_probe_repo`); no variables.tf / server.tf edit
- [x] 3.2 `model.c4` consumer-probe edge prose; run c4 tests

## Phase 4 — Discoverability baseline

- [x] 4.1 Bump `BASELINE_DECLARED_PROBES` by one with a dated ledger comment; run the suite

## Phase 5 — Local verification

- [x] 5.1 shellcheck + probe suite
- [x] 5.2 Guard 1 and Guard 2 mutation batteries on sandbox copies (cmp-verified); results table for the PR body
- [x] 5.3 Related suites (fresh-boot-parity, web-host-provisioner-parity, journald-config, web-ghcr-deny, cloud-init-web-zot-seed, target-parity, user-data-size, c4)
- [x] 5.4 `terraform fmt -check` / `validate`; `lint-guard-contract.py`; `lint-infra-no-human-steps.py`
- [x] 5.5 All `.claude/hooks/*.test.sh` (including `grep-q-pipe-guard.test.sh`) before enqueue
- [ ] 5.6 (NOT RUN — opportunistic; the apply workflow's destroy-guard and the plan's no-replace evidence stand) Opportunistic read-only scoped `terraform plan` (output to a file), if credentials work

## Phase 6 — Ship

- [ ] 6.1 Re-check nothing in flight; enqueue (operator decision of 2026-10-10 covers the web-1 SSH apply)
- [ ] 6.2 PR body: `Ref #7258`, evidence tables, recipe, web-2 limitation, D5 note

## Phase 7 — Post-merge observation (telemetry only)

- [ ] 7.1 R1 delivery anchor T0 from the apply run log
- [ ] 7.2 R2 marker / fault / canary reads; R3 heartbeat + incidents (credential on stdin config)
- [ ] 7.3 AC13 holds -> comment the outputs on #7258 (Step B gate record)
- [ ] 7.4 File the deferral issue (pinned-tag manifest probe) and the `egress_gateway_web2` bridge-scope tracker if none exists

## Step B (separate later PR — NOT in this change)

- [ ] B.1 Delete `zot-entry-gate.sh` + `zot-entry-gate.test.sh`; two tsv rows; dangling comments; two stale Slack statements (see plan `## Step B follow-up`)
