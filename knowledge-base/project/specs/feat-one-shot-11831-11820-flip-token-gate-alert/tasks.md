# Tasks — feat-one-shot-11831-11820-flip-token-gate-alert

Plan: knowledge-base/project/plans/2026-11-02-infra-pin-token-access-and-flip-unit-silence-alert-plan.md

## Phase 1 — gate pin (#11831), tests first
- 1.1 Add `tok_obj` helper to tests/scripts/test-inngest-host-replace-gate.sh; give every creating token row its `after.access`
- 1.2 Add RED rows: flip create `read`; flip delete+create `read`; boot delete+create `read/write`; `after` absent; `access` absent; must-PASS rows (other replace order, no-op boot token without `after`)
- 1.3 Implement `doppler_token_access_wrong` in tests/scripts/lib/inngest-host-replace-gate.sh (jq counter, numeric assert, echo line, PASS conjunct, reason chain, header comment, ABORT text)
- 1.4 Add mutation rows M3/M4 (copy of gate), harness row (suite pass-count floor)
- 1.5 Run the gate suite and shellcheck

## Phase 2 — silence alert (#11820), tests first
- 2.1 Create apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh (RED), pinned to the real emitter in apps/web-platform/infra/inngest-cutover-flip.sh
- 2.2 Add local SQL, exploration and alert to apps/web-platform/infra/betterstack-logs-alerts.tf
- 2.3 Add the two -target lines to .github/workflows/apply-web-platform-infra.yml
- 2.4 Add the blocking step to .github/workflows/infra-validation.yml
- 2.5 Bump the exploration count anchor 17 -> 18 in betterstack-send-failed-alert-mutation.test.sh
- 2.6 Run betterstack-alert-structure.test.sh, logs-alert-query-period-ceiling.test.sh and fix what reds

## Phase 3 — docs and ratchets
- 3.1 Runbook: Flip-token split step 1, "What an agent may verify" (3), replace-window email line
- 3.2 betterstack-log-query.md bullet; ADR-218 alert list line; ADR-282 append-only addendum
- 3.3 scripts/ci-pr-affected-audit.accept.tsv accept row (anchor ef13fc106737/1)
- 3.4 Run repo-global ratchets (grep-q-pipe-guard, PJ_TRIPLES, suite-shard-legs parity, fixture-relative-assert, capture lint) before the first push
