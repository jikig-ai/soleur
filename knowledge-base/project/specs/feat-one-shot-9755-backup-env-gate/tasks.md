# Tasks — feat-one-shot-9755-backup-env-gate (#9755)

Plan: `knowledge-base/project/plans/2026-10-28-fix-cutover-op-backup-tier-b-reviewer-gate-plan.md`

## Phase 1 — Workflow + script re-plumb

- [x] 1.1 In `.github/workflows/cutover-inngest.yml`, add `|| inputs.op == 'backup'` inside the `environment:` ternary (line ~100) and update the gate comment block (~lines 87-99) to record `op=backup` as a prod-artifact writer on the same reviewer gate.
- [x] 1.2 Insert between `Install Doppler CLI` and `Run cutover host op via webhook`: a step `if: inputs.op == 'backup'`, `uses: ./.github/actions/infra-credentials`, `with: doppler-token-infra-privileged: ${{ (inputs.op == 'backup') && secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED || '' }}`, no `doppler-token-legacy`. Constraint: no `HCLOUD` literal on any non-comment line; no `doppler-token-infra-privileged:` or `DOPPLER_TOKEN_INNGEST_ARM:` text earlier than the real lines.
- [x] 1.3 In `scripts/cutover-inngest.sh` `backup)` arm: replace `HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN --plain)` with `HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"`; rewrite the `ALLOWLISTED READ` comment into the Tier-B delivery description; refusal `::error::` names the loader + `inngest-cutover`. Keep `_bearer_ok` → `::add-mask::` → `_bearer_curl` order.

## Phase 2 — Pinned suite (`apps/web-platform/infra/cutover-inngest-workflow.test.sh`)

- [x] 2.1 Extend the membership loop to `for _op in arm rollback resume reflush backup`.
- [x] 2.2 Rewrite the `#7674` parity block: extract `PRIV_OPS` from the `doppler-token-infra-privileged:` line; assert `ENV_OPS == sort -u(TOK_OPS ∪ PRIV_OPS)`; add `backup ∉ TOK_OPS`; keep anti-vacuity + loader-located rows.
- [x] 2.3 Add assertions: loader step exists (`uses: ./.github/actions/infra-credentials` + `if:` on backup); no `doppler-token-legacy:` in the file.
- [x] 2.4 Behavioral driving of the extracted `backup)` arm: unset/empty env → `SOLEUR_CREDENTIAL_REFUSED` + zero curl; mis-shaped → same; sentinel → `::add-mask::` precedes first `_bearer_curl`; non-201 → named `::error::`. Assert no `doppler` invocation in the arm.
- [x] 2.5 Bump `_EXACT_FLOOR` to the measured count + changelog comment (`1135 -> N (+K) at #9755: …`).

## Phase 3 — Lint allowlist retirement

- [x] 3.1 In `scripts/lint-hcloud-token-readonly-no-fallback.sh`: delete `ALLOW_*` constants, `allow_hits`, the match arm, the `F-allowlist` check, and the expiry-warning block; update header prose (`ALLOWLIST`/`EXPIRY`/`OWNER AND TRACKERS`); drop or pin `allowlisted=` in the summary line — pick one shape and match the battery.
- [x] 3.2 In `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh`: update `GREEN`/live-row expectations; delete or rework M1, M8a, M8b, T3a, T3b, X2, X3, O1 and any `allowlisted=1` fixture expectations; keep all F-literal/F-sameline/population/self-test rows.

## Phase 4 — Records + verification

- [x] 4.1 Append the dated ADR-241 amendment entry (re-plumb, allowlist retirement, missed-deadline retrospective — append-only).
- [x] 4.2 Update the `op=backup` row in `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (env `inngest-cutover`, `DOPPLER_TOKEN_INFRA_PRIVILEGED` → loader → `HCLOUD_TOKEN` env).
- [x] 4.3 `inngest-server.md` step 0.5: note the dispatch holds in "Waiting" for the `inngest-cutover` approval.
- [x] 4.4 Run locally: `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`, `bash scripts/lint-hcloud-token-readonly-no-fallback.sh`, `bash tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh`, `bash tests/scripts/test-infra-privileged-tier-census.sh`, `bash tests/scripts/test-trio-baseline-census.sh` — all exit 0.
- [x] 4.5 Post-merge (operator hold): confirm the push-triggered `apply-web-platform-infra` run is green (provisioners) + `bash scripts/betterstack-query.sh`, no SSH; operator may then dispatch `op=backup` to prove the hold end-to-end.
