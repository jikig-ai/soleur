---
feature: feat-one-shot-7377-registry-levers
plan: knowledge-base/project/plans/2026-09-28-feat-registry-write-levers-resolved-plan.md
issue: 7377
lane: single-domain
---

# Tasks: resolve the registry host's write-shaped lever set (#7377)

## 1. Tests first (RED)

- [ ] 1.1 `apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts`: FIRE step dispatches the inventory once per new non-OOM tracker; no dispatch on repeat run, OOM cause, or OOM prefix with non-OOM tail; dispatch failure is fail-soft; `actions: write` declared.
- [ ] 1.2 `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh`: dispatch file absent; no workflow listens for the `registry-zot-inventory` label (scan floor, mutation arm, must-PASS on the inngest label route); alarm carries `actions: write` and a non-comment dispatch line; infra-validation paths updated; raise `MIN_ASSERTIONS`.
- [ ] 1.3 `tests/scripts/test-zot-inventory.sh`: END-sample rows (same, higher, boot change with equal count, stale START row, re-poll, sampler failure, non-numeric, no query host, caller-supplied wins, allow-listed env incl. DOPPLER_TOKEN).
- [ ] 1.4 `tests/scripts/test-zot-inventory-assert-marker.sh`: `marker_schema` 2 / missing / 10 → unsupported; 1 → observed; emitter/reader literal parity.

## 2. Implementation (GREEN)

- [ ] 2.1 Delete `.github/workflows/registry-zot-inventory-dispatch.yml`.
- [ ] 2.2 `scheduled-zot-restart-loop.yml`: `actions: write`; fail-soft prefix-gated dispatch in the new-issue arm; rewrite body paragraph.
- [ ] 2.3 `infra-validation.yml`: swap the path filter.
- [ ] 2.4 `scripts/zot-inventory.sh`: `take_end_sample()` (env -i allow-list, re-poll until newer than START, bounded 360 s) + verdict clause + header contract.
- [ ] 2.5 `registry-zot-inventory.yml`: env-contract comment only.
- [ ] 2.6 `scripts/zot-inventory-assert-marker.sh`: `marker_schema` consumer.
- [ ] 2.7 Delete `scripts/followthroughs/registry-luks-blocker-6929.sh` and `scripts/followthroughs/zot-inventory-marker-7278.sh` (+ baseline line, sampler comment).
- [ ] 2.8 Reword the non-OOM `CAUSE` next-action clause in `scripts/zot-restart-loop-alarm.sh`.

## 3. ADR and C4

- [ ] 3.1 ADR-172 amendment 2026-09-28 + status `accepted`.
- [ ] 3.2 `model.c4` inventory clause; regenerate `model.likec4.json`.

## 4. Verify

- [ ] 4.1 Targeted suites + actionlint + C4 tests.
- [ ] 4.2 Post-merge: one inventory dispatch (no replace in progress) → numeric `zot_restarts_at_end`.
