# Tasks — fresh web-2 boot observability prerequisites (Ref #5933)

Plan: `knowledge-base/project/plans/2026-07-03-chore-fresh-web2-boot-observability-prereqs-plan.md`
Lane: cross-domain · Threshold: single-user incident

## Phase 1 — Fresh-host post-container egress-enforcement probe (Item 3)

- [x] 1.1 Read `soleur-host-bootstrap.sh` (full) + `cloud-init.yml` terminal block (~540-600) to confirm container-start line + fail-closed model before editing.
- [x] 1.2 Create `apps/web-platform/infra/cron-egress-enforce-probe.sh` (`#!/bin/sh`, `set -e`), reusing the positive+negative container-egress probe from `cron-egress-postapply-assert.sh:77-89` WITHOUT the fresh-host skip; add structure asserts (DOCKER-USER jump, service active); emit discriminating Sentry `{stage:egress-enforce, probe_result, image_ref, host_id}` on failure then `exit 1`.
- [x] 1.3 Extract shared Sentry-emit helper `host-sentry-emit.sh` from `soleur-host-bootstrap.sh` `emit_fail()` (or inline byte-identical copy + envelope-parity assertion).
- [x] 1.4 Wire probe into `cloud-init.yml` AFTER `docker run … ${image_name}`: bounded container-readiness until-loop → run probe → `poweroff -f` on non-zero (fail-closed).
- [x] 1.5 Add `"cron-egress-enforce-probe.sh"` to `local.host_script_files` (`server.tf:16-47`) AND the Dockerfile `/opt/soleur/host-scripts/` set (lockstep).
- [x] 1.6 Add install-verify (`test -x` + mode 0755) for the new script in the bootstrap install loop.
- [x] 1.7 Write `cron-egress-enforce-probe.test.sh` (static asserts + awk ordering + envelope parity + lockstep grep); register in `.github/workflows/infra-validation.yml`.
- [x] 1.8 Run: `sh -n cron-egress-enforce-probe.sh`; the new `.test.sh`; `cloud-init-user-data-size.test.ts`; `web-hosts-fanout-parity.test.sh`; #5921 bootstrap tests.

## Phase 2 — ADR-082 + C4

- [x] 2.1 Create `ADR-082-fresh-web2-boot-observability.md` (`status: adopting`) recording all 4 items (3 shipped; 1/2/4 designed).
- [x] 2.2 Read all three `.c4` files; add external uptime-monitor actor / egress-enforcement edge if absent (+ `view include`), run `c4-code-syntax.test.ts` + `c4-render.test.ts`; else cite "no impact" with the actors/systems checked.

## Phase 3 — Follow-up tracking + ship prep

- [x] 3.1 `gh label list` verify → create 3 issues (Items 1, 2, 4), each blocked-on/re-eval-criteria, link ADR-082, milestone from roadmap.
- [x] 3.2 Open Code-Review Overlap check on final Files-to-Edit list.
- [x] 3.3 PR body: `Ref #5933` (NOT `Closes`); summarize scope + deferrals.


## Deferred (tracked in #5947)
- Items 1, 2, 4 → consolidated tracker #5947 (blocked on #5887 / cutover DNS rewire / own supply-chain PR); designs in ADR-082.
