# Tasks - feat-one-shot-9377-web-escrow-distinct-passphrase

Derived from `knowledge-base/project/plans/2026-10-03-chore-web-host-luks-distinct-passphrase-escrow-gate-plan.md`.
Lane: `cross-domain` (spec lacks a valid `lane:`, defaulted fail-closed). Brand-survival threshold: `single-user incident`.
Offline-only: no apply, no dispatch, no Doppler write, no Cloudflare or R2 mint; `Ref #9377`, never `Closes`.

## Phase 0 - Baselines (read-only)

- [x] 0.1 Record the workflow byte size (`wc -c .github/workflows/apply-web-platform-infra.yml`, 482,795 at plan time) and run the baseline suites listed in plan Phase 0.1; note pre-existing reds.
- [x] 0.2 Re-confirm `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` read `disabled_manually` (`gh api repos/jikig-ai/soleur/actions/workflows`); if either is active, STOP.
- [x] 0.3 Re-run the Files-to-Edit derivation grep from the plan; add any new hit.

## Phase 1 - Distinct passphrase (tests first)

- [x] 1.1 `workspaces-luks-header-web.test.sh`: update W2, W3 (5 resources), add W7 (password shape) and W8 (never names web-1's password); recompute the assertion floor. RED first.
- [x] 1.2 `workspaces-luks-header-web.tf`: add `random_password.workspaces_luks_web` (length 40, special false, `prevent_destroy`), repoint the key secret, rewrite the header comment.
- [x] 1.3 `check-web-host-escrow-config.test.sh` Guard 1 mutation rows (RED), then `check-web-host-escrow-config.sh --static` passphrase-distinct clause (GREEN); update `--live` docs.
- [x] 1.4 `workspaces-luks-provision.test.sh`: empty web-class key never retried against `prd_workspaces_luks` (fatal `key` arm, exit 13); audit `luks-monitor` and reopen tests for shared-key fixtures.
- [x] 1.5 `workspaces-luks-fresh-boot.tf` comments narrowed.
- [x] 1.6 Workflow `-target=random_password.workspaces_luks_web`; `terraform-target-parity.test.ts` `freshBoot` entry and `WEB_HOST_REPLACE_PRESERVED` entry.

## Phase 2 - Rotation HALT and gate naming

- [x] 2.1 Create the three `tfplan-workspaces-luks-passphrase-*.json` fixtures; add counter rows to `test-destroy-guard-counter-web-platform.sh` (RED).
- [x] 2.2 Widen `luks_passphrase_rotations` in `destroy-guard-filter-web-platform.jq` to six addresses (GREEN).
- [x] 2.3 Generalize the `apply` job HALT message, add the workspaces remediation, widen the offending-lines grep; keep the block before the `destroy_count` sum.
- [x] 2.4 Name the web copy and the new password in the cutover, recut and replace gates (`luks_passphrase_touched`); leave the by-name web-1 refusal untouched; add gate-suite rows.
- [ ] 2.5 `terraform-target-parity.test.ts`: job-reach row (web copies only in the `apply` job; HALT block present there; floor on extracted jobs).

## Phase 3 - Escrow check as a workflow gate

- [ ] 3.1 `web-host-escrow-preflight.test.sh` against the Doppler stub (RED): env token wins, fallback reads one named secret, empty token fails before the checker, no token bytes in output, xtrace refused.
- [ ] 3.2 `scripts/web-host-escrow-preflight.sh` (GREEN; xtrace refusal first, `::add-mask::` and `^dp\.pt\.` shape check on the fallback read); checker failure output gains the one-line cause map (no new flag).
- [ ] 3.3 Census test `plugins/soleur/test/web-host-escrow-preflight-census.test.ts` first (RED): predicate is a `-target`/`-replace` of `hcloud_server.web[` in a job with `terraform apply`; fixture rebirth-shaped workflow; floor of two host-creating jobs; separate assertion pinning the `host_creates` HALT of `apply-web-platform-infra.yml:apply` and `apply-deploy-pipeline-fix.yml:apply`.
- [ ] 3.4 Add the step (`bash scripts/web-host-escrow-preflight.sh`, `timeout-minutes: 2`, no `working-directory`, no `if:`, no `continue-on-error`) to `web_host_create` and `web_host_replace`; register the new suites in `scripts/test-all.sh`; update `suite-shard-legs.tsv` per the shard-totality test.
- [ ] 3.5 Runbooks `web-host-birth.md` and `web-host-replace.md`: Step 0 is a diagnostic; remediation for a paged `escrow=missing` (replace re-attempts; data-bearing hosts depend on the #9372 follow-up).

## Phase 4 - Paging and op routing

- [ ] 4.1 Update both op-contract suites first (RED): escrow to `PAGE_STAGES` with the `PAGE_AT_WARNING` carve-out; `resolve_link_local` in `ROUTED_OPS`.
- [ ] 4.2 `issue-alerts.tf`: move the escrow stage to `web_luks_boot_fatal`; add `resolve_link_local` to `egress_blocked`; update comments.
- [ ] 4.3 `alert-reference.json` for the three rules.
- [ ] 4.4 Sweep stage counts and "NoOne" statements (`rg 'workspaces_luks_provision_escrow|13 stages|thirteen'` over `knowledge-base/`).

## Phase 5 - Shape-validate the R2 pair

- [ ] 5.1 `workspaces-luks-provision.test.sh` Guard 5 rows with a stdin-recording curl stub (RED).
- [ ] 5.2 `_escrow` shape check before `_curl`, under `LC_ALL=C`.

## Phase 6 - Architecture, legal, docs

- [ ] 6.1 ADR-263 addendum (D7 rewrite, D8, residual rewrite, counts) via `soleur:architecture`.
- [ ] 6.2 Article 30 register and compliance posture cells (identical edits, CLO wording, scoped to NEW births).
- [ ] 6.3 `encryption-posture-ledger.json` row text; run the posture lint suite.
- [ ] 6.4 Read all three `.c4` files; add one clause to the `doppler -> hetzner` edge description; regenerate `model.likec4.json`; run C4 tests and `c4-count-parity.test.sh`.
- [ ] 6.5 Rationale note in `apply-web-platform-infra-job-rationale.md`.

## Phase 7 - Verification and hand-off

- [ ] 7.1 Byte budget (at most 485,300) and `workflow-file-size.test.ts`.
- [ ] 7.2 Full affected suites; `scripts-shard-totality.test.sh`; `lint-guard-contract.py`; `lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 7.3 Post the decision record on #9377 (A1, A2, B1, B2, still-open items).
- [ ] 7.4 File the deferral issue for the read-only preflight token.
- [ ] 7.5 PR body: first line answers "does merging this alone mutate production?"; `Ref #9377`; Merge-time effects table; "no live step performed".
