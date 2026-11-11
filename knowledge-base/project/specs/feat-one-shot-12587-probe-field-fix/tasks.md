# Tasks — fix(followthrough): placement_decision probe reads CONTAINER_NAME + message_json (#12587)

Plan: `knowledge-base/project/plans/2026-11-11-fix-placement-probe-field-isolation-plan.md`
Branch: `feat-one-shot-12587-probe-field-fix` · Issue: #12587 (Ref, never Closes) · semver:patch

## Phase 1: Probe field fix

- [ ] 1.1 In `scripts/followthroughs/placement-decision-forward-9137.sh`, rewrite the
      row-isolation + payload extraction (`:38-40`): `select(.CONTAINER_NAME == $id)`
      and `(.message_json // {}) | select(type == "object") | select(.event ==
      "placement_decision") | {decision, host_ip}` emitted with `jq -c`, so the
      existing `grep '"forward"'` / `grep '"execute"'` / `host_ip` arms (`:42-45`)
      and the `fwd > 0 && exe > 0` verdict are unchanged.
- [ ] 1.2 Rewrite the header field-rationale comment (`:26-29`): untagged docker
      journald → `SYSLOG_IDENTIFIER` is the rotating container short ID,
      `CONTAINER_NAME` carries the app name, doppler/host-journald rows lack the
      field (exclusion preserved); restate the exit contract (0/1/2, no exit 0 on
      partial success).
- [ ] 1.3 Confirm `lint-followthrough-varq-ban.sh` still passes on the edited probe
      (no `${VAR:?}`, no retired credential names, no `/events/` lines).

## Phase 2: Fixture test

- [ ] 2.1 Create `scripts/followthroughs/placement-decision-forward-9137.test.sh`
      (sibling convention: `actions-queue-tail-8450.test.sh`,
      `anthropic-admin-key-6297.test.sh`) — `env -i` hermetic runs with
      `PLACEMENT_FT_QUERY` pointed at an executable fixture-printing stub;
      fixture rows are `{dt, raw:"<json-string>"}` envelopes whose decoded raw
      carries `CONTAINER_NAME` / `SYSLOG_IDENTIFIER` / `message` / `message_json`.
      Cases: both arms → 0 + `split verified`; execute-only → 1; forward-only → 1;
      forward-on-exec (`host_ip=10.0.1.10`) → 1; doppler contaminant (no
      CONTAINER_NAME) → satisfies neither arm; bare-SYSLOG_IDENTIFIER host row →
      satisfies neither arm; `.message`-mentions-`placement_decision` with no
      qualifying `message_json` → neither arm; stub exits non-zero → 2; stub
      non-executable → 2; empty set → 1; anti-vacuity floor + `All fixtures passed.`
      success line.
- [ ] 2.2 `chmod +x` the new test file (index mode 100755 —
      `followthrough-exec-bit.test.sh` gates every `scripts/followthroughs/*.sh`).
- [ ] 2.3 Register the suite: `python3 scripts/regenerate-shard-manifest.py
      --incremental --write` (adds `scripts/followthroughs/placement-decision-forward-9137`
      to `scripts/suite-shard-legs.tsv`; `lint-orphan-test-suites.sh` enforces).

## Phase 3: Verification & ship

- [ ] 3.1 `bash scripts/followthroughs/placement-decision-forward-9137.test.sh` —
      all fixtures pass locally.
- [ ] 3.2 Live verify: `doppler run -p soleur -c prd_terraform -- bash
      scripts/followthroughs/placement-decision-forward-9137.sh` exits 0 printing
      `placement_decision split verified`.
- [ ] 3.3 PR body carries `Ref #12587` (never `Closes #12587` — the sweeper owns
      closure) + `## Changelog`; `semver:patch` label.
