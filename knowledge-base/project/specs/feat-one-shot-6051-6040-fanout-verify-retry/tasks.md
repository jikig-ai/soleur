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
- [ ] 0.4 Confirm `RETRIGGER_MIN_INTERVAL_S` ≥ observed web-1 re-swap wall-clock (avoid
      back-to-back `flock -n` `lock_contention` on the deploy host).

## Phase 1 — Test scaffolding (RED first)

- [ ] 1.1 Create `apps/web-platform/infra/deploy-status-fanout-verify.test.sh` with the
      network removed from the assertion path (injectable status source + POST sink).
- [ ] 1.2 Synthesize JSON fixtures under `apps/web-platform/infra/fixtures/`
      (degraded→degraded→ok / all-degraded / stale-start_ts / bad-tag). `jq empty` each.
- [ ] 1.3 Write failing assertions: AC1 (retry→exit 0), AC2 (all-degraded→terminal exit 1),
      AC3 (POST-count ≤ 1+DEGRADED_RETRY_MAX), AC4 (roster/staleness/tag invariants),
      AC6 (emits `deployed_tag=` to `$GITHUB_OUTPUT`).

## Phase 2 — Core: retry loop in the shared script (GREEN)

- [ ] 2.1 Add env knobs `DEGRADED_RETRY_MAX` (6), `RETRIGGER_MIN_INTERVAL_S` (90),
      `OP_CONTEXT` (recreate) to `deploy-status-fanout-verify.sh`.
- [ ] 2.2 Extract `_retrigger_fanout` (re-read freshest tag + downgrade guard + advance
      `PRE_START_TS` + POST 202 + reset `last_trigger_ts`) and `_recovery_msg` (OP_CONTEXT).
- [ ] 2.3 Convert the `*_peer_fanout_degraded` terminal `exit 1` (`:136-138`) into the
      bounded-retry branch; keep terminal exit-1 on budget exhaustion + unexpected reason.
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
- [ ] 4.4 File the secondary-finding tracking issue (graceful web-1 re-swap / web-2-only
      fan-out path) — `domain/engineering`, `priority/p3-low`; Ref #6051.

## Phase 5 — Verify

- [ ] 5.1 Full infra test suite green; `shellcheck` + `actionlint` clean.
- [ ] 5.2 AC1–AC12 all satisfied; observability `discoverability_test` command passes (no ssh).
- [ ] 5.3 PR body: split Pre-merge / Post-merge ACs; `Closes #6051`, `Closes #6040`.
