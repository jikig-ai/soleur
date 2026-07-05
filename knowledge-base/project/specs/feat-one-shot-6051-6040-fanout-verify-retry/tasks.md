# Tasks — web-2-recreate fan-out verify retry + warm_standby dedup (#6051, #6040)

Plan: `knowledge-base/project/plans/2026-07-05-fix-web2-recreate-fanout-verify-retry-and-warm-standby-dedup-plan.md`
Lane: cross-domain | Threshold: single-user incident (requires_cpo_signoff)

## Phase 0 — Preconditions (verify before coding)

- [ ] 0.1 Read all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`) and confirm the
      "no C4 impact" enumeration (external actors/systems/containers/access-relationships)
      still holds; cite in the ADR/C4 section.
- [ ] 0.2 Re-run the Open Code-Review Overlap two-stage `gh --json … > f.json; jq --arg …`
      check against the final Files list (expect none).
- [ ] 0.3 Confirm `fan_out_to_peers` (`ci-deploy.sh:134-173`) is still single-attempt (no
      host-side peer retry) — the load-bearing premise for client-side re-POST.
- [ ] 0.4 Confirm the web-platform re-POST is a FULL deploy cycle (no same-tag no-op; the
      ~50 ms shortcut at `ci-deploy.sh:1356` is inngest-only) and that `lock_contention`
      writes `exit_code=1` (`:846-849`) — sizes the budget + the retryable-lock handling.
- [ ] 0.5 Measure a realistic fresh-boot window from run logs to set `FRESH_BOOT_WINDOW_S`
      (~600) and the poll budget = window + one full deploy cycle (keep timeout 45m above).

## Phase 1 — Test scaffolding (RED first)

- [ ] 1.1 Create `apps/web-platform/infra/deploy-status-fanout-verify.test.sh` with the
      network removed from the assertion path (injectable status source + POST sink).
- [ ] 1.2 Synthesize JSON fixtures under `apps/web-platform/infra/fixtures/`
      (degraded→degraded→ok / all-degraded / stale-start_ts / bad-tag). `jq empty` each.
- [ ] 1.3 Write failing assertions: AC1 (retry→exit 0), AC2 (all-degraded→terminal exit 1),
      AC3 (exactly 2 POSTs, DEGRADED_RETRY_MAX=1), AC3b (retry gated on FRESH_BOOT_WINDOW_S),
      AC3c (lock_contention retryable→exit 0), **AC3d (P0 regression guard — SAME static
      start_ts across many polls still fires exactly one retry after the window; NOT zero)**,
      AC3e (DEPLOY_TAG reassigned across retrigger → newer-tag ok drives exit 0), AC3f
      (retrigger non-202 → terminal exit 1), AC4 (roster/staleness/tag invariants),
      AC6 (emits `deployed_tag=`). Fixtures hold `start_ts` CONSTANT across repeated degraded
      polls (else AC3/AC3d pass for the wrong reason).

## Phase 2 — Core: retry loop in the shared script (GREEN)

- [ ] 2.1 Add env knobs `DEGRADED_RETRY_MAX` (1), `FRESH_BOOT_WINDOW_S` (600),
      `OP_CONTEXT` (recreate) to `deploy-status-fanout-verify.sh`.
- [ ] 2.2 Extract `_retrigger_fanout` (re-read freshest tag + downgrade guard + **REASSIGN
      outer DEPLOY_TAG** + POST; **terminal exit 1 on non-202**; does NOT touch `PRE_START_TS`)
      and `_recovery_msg` (OP_CONTEXT). Add the `retried` start_ts set marked ONLY when the
      retry fires; keep the ORIGINAL baseline for the whole run; guard `START_TS==0`.
- [ ] 2.3 Convert the `*_peer_fanout_degraded` terminal `exit 1` (`:136-138`) into: single
      re-POST gated on `elapsed ≥ FRESH_BOOT_WINDOW_S`, re-evaluating elapsed EVERY poll (P0:
      do NOT mark `retried` until the retry actually fires); treat `exit_code=1
      reason=lock_contention` as retryable; keep terminal exit-1 on budget exhaustion + genuine
      failure + unexpected reason. Set recreate-job `STATUS_POLL_MAX_ATTEMPTS=120` (AC5b) +
      verify `timeout-minutes` above the budget (AC5c) — recreate job env only, not script default.
- [ ] 2.4 Emit `deployed_tag=<tag>` to `$GITHUB_OUTPUT` (guarded on `-n "${GITHUB_OUTPUT:-}"`).
- [ ] 2.5 Add `elapsed=` + `retrigger K/MAX` annotations on poll log lines.
- [ ] 2.6 Keep ONE overall poll budget (no fresh budget per retry). Re-measure vs ~10-min
      fresh-boot window; bump `STATUS_POLL_MAX_ATTEMPTS` only if needed (job timeout 45m stays).
- [ ] 2.7 Run the new `.test.sh` → all fixtures PASS; `shellcheck` clean.

## Phase 3 — warm_standby migration (#6040)

- [ ] 3.1 Replace warm_standby's 3 inline steps (`apply-web-platform-infra.yml:808-1026`)
      with one shared-script call (id `verify`, `OP_CONTEXT=warm-standby`, poll/settle/roster
      env + webhook/CF secrets). Keep the tf plan/apply (attach-proof) steps unchanged.
- [ ] 3.2 Rewire `Warm-standby summary` `deployed_tag` source to `steps.verify.outputs.deployed_tag`.
- [ ] 3.3 `bash scripts/followthroughs/warm-standby-verify-dedup-6030.sh` → exit 0 (AC5 / #6040 auto-close).
- [ ] 3.4 `actionlint` the workflow; `bash -c '<snippet>'` on embedded `run:` blocks.
- [ ] 3.5 `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh` still passes (2 copies).

## Phase 4 — Wiring, ADR, docs

- [ ] 4.1 Register the new `.test.sh` in `.github/workflows/infra-validation.yml` (AC12).
- [ ] 4.2 Extend `plugins/soleur/test/terraform-target-parity.test.ts` to assert warm_standby
      references the shared script (AC8), or document the follow-through probe as sufficient.
- [ ] 4.3 Amend ADR-068 (in-verify bounded degraded-retry semantics; `Ref #6051`) (AC11).
- [ ] 4.4 File tracking issue(s) (`domain/engineering`, `priority/p3-low`; Ref #6051):
      (a) graceful web-1 re-swap / web-2-only fan-out path (secondary finding);
      (b) private-net web-2 post-accept health probe for GA cutover (user-impact FINDING 2);
      (c) optional cross-pipeline merge-freeze during operator recreate (FINDING 1). May be
      one combined issue.

## Phase 5 — Verify

- [ ] 5.1 Full infra test suite green; `shellcheck` + `actionlint` clean.
- [ ] 5.2 AC1–AC12 all satisfied; observability `discoverability_test` command passes (no ssh).
- [ ] 5.3 PR body: split Pre-merge / Post-merge ACs; `Closes #6051`, `Closes #6040`.
