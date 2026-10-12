# Tasks: egress gateway bootstrap bounded TCP-open retry (#10003)

Plan: `knowledge-base/project/plans/2026-10-12-fix-egress-gw-tcp-open-bounded-retry-plan.md`

Spec lacks a `lane:` — defaulted to cross-domain (fail-closed), recorded in the plan frontmatter.

## Phase 1: Setup

- [ ] 1.1 Run `bash scripts/test-all.sh --capacity`; note the contention verdict; run infra suites in isolation and re-run any `rc=124` suite alone
- [ ] 1.2 Record the shellcheck baseline for `egress-gateway-bootstrap.sh` and `egress-gateway.test.sh` (1 SC2046 warning, 6 SC2016 infos); bar is no new finding
- [ ] 1.3 Claims-ledger `docker logs` over journald row already RUN at deepen time (holds, docker 29.7.2); re-run only if the comment wording changes
- [ ] 1.4 Confirm the G1 ratchet moves (`cd plugins/soleur && bun test test/preflight-discoverability-test.test.ts` red at 63 vs 62)
- [ ] 1.5 Re-check `grep -n logformat apps/web-platform/infra/egress-gateway-squid.conf` for credential fields before the log tail may reach the apply log

## Phase 2: Tests first (RED)

- [ ] 2.1 In `apps/web-platform/infra/egress-gateway.test.sh` add the behavioural section: `extract_fn` for `gw_diag` and `wait_for_gw_tcp` (non-vacuity floors 4 and 12 lines), `log`/`die` pulled by grep, executable `docker` stub on a fakes PATH dir (NOT a shell function: `timeout 10 docker logs` execs the binary), bind-then-listen python fixture, outer `timeout` per case
  - [ ] 2.1.1 T1 already-open control (attempt 1)
  - [ ] 2.1.2 T2 late-open (delay 2 s, budget 8 s, attempt >= 2)
  - [ ] 2.1.3 T3 never-open (budget 3 s, rc != 0, die text + STUB-STATE + STUB-LOG, elapsed in [budget-1, budget+10])
  - [ ] 2.1.4 H2 must-pass non-canonical row (127.0.0.2, other port, GW_WAIT_S=7)
- [ ] 2.2 Repoint the line-172 assertion; add static verdicts (call exactly once, old `timeout 5` probe absent, `GW_WAIT_S` default literal); extend the suite trap to kill fixture PIDs; keep the `-lt 30` floor literal
- [ ] 2.3 Run against the unmodified bootstrap and record RED

## Phase 3: Core implementation (GREEN)

- [ ] 3.1 Replace the single probe in `apps/web-platform/infra/egress-gateway-bootstrap.sh` with `GW_WAIT_S`, `gw_diag`, `wait_for_gw_tcp` and the bare call; keep the existing `die` text last; only ledger-verified comment sentences
- [ ] 3.2 Run the suite alone, shellcheck (no new findings), `egress-gw-image-staleness.test.sh`, `scripts/guard-vacuity-floor.test.sh`
- [ ] 3.3 Bump `BASELINE_DECLARED_PROBES` 62 -> 63 in `plugins/soleur/test/preflight-discoverability-test.test.ts` with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment

## Phase 4: Mutation battery

- [ ] 4.1 Run Guard Contract mutations 1-5 and harness row H1 on scratch copies; confirm RED/PASS as stated; one line per row for the PR body

## Phase 5: Ship

- [ ] 5.1 Comment on #10003 with the re-measure (port-22 not reproduced; TCP-open race; plan + PR links)
- [ ] 5.2 Rebase on `origin/main` (never merge); check `gh run list --status in_progress` and `--status queued` for the apply workflow
- [ ] 5.3 PR body: first line states the merge re-provisions both gateways; `Ref #10003`; `## Changelog`; matrix results
- [ ] 5.4 Post-merge (same session, Monitor-armed): both `OK: gateway up` lines, both resources completed, `egress_gw_probe result=ok` from each host after the apply; close #10003 or leave open with findings
