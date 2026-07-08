# Tasks — registry-host-replace CI path + Better Stack ops@ recipient IaC

Derived from `knowledge-base/project/plans/2026-07-08-fix-registry-host-replace-ci-path-and-ops-alerting-plan.md`.
lane: cross-domain | brand_survival_threshold: aggregate pattern

## Phase 0 — Preconditions (verify before coding)

- [ ] 0.1 Confirm `betteruptime_team_member` schema against the pinned provider (`terraform providers schema -json`): `email`/`role` args, whether a **global** token requires `team_name`, a free-tier-valid `role`, and the free-tier team-seat limit.
- [ ] 0.2 Confirm Doppler `soleur/prd_terraform` `BETTERSTACK_API_TOKEN` → `var.betterstack_api_token` (Uptime API bearer; distinct from the Telemetry `BETTERSTACK_QUERY_*` creds).
- [ ] 0.3 Read `tests/scripts/lib/inngest-host-replace-gate.sh` + its test in full; copy the **positive-action** `out_of_scope` filter verbatim (excludes `no-op` AND `read`).
- [ ] 0.4 Confirm the pending `hcloud_volume.registry` size delta (live 10 → desired 30) is a pending `["update"]`.
- [ ] 0.5 Dry-run the scoped 5-`-target` `terraform plan` (with ephemeral ssh key) to capture the real `resource_changes` shape (seed gate fixtures) and confirm no other plan-time evaluation errors under `-target`.
- [ ] 0.6 Inventory every guard/parity suite (`git grep -ln 'registry|dispatch|-target=|parity' tests/ apps/web-platform/infra/*.test.sh plugins/soleur/test/`); determine if the parity test enumerates resources from `.tf` or a hardcoded list.

## Phase 1 — FIX A: registry-host-replace dispatch path

- [ ] 1.1 Add `registry-host-replace` to the `apply_target` `choice` options + input description in `.github/workflows/apply-web-platform-infra.yml`.
- [ ] 1.2 Add the `registry_host_replace` job (guarded on `inputs.apply_target=='registry-host-replace'`, `timeout-minutes: 20`, same workflow → shared concurrency serializer), mirroring `inngest_host_replace` (checkout / setup-terraform / doppler / ephemeral ssh key / R2 creds / init).
- [ ] 1.3 Plan + destroy-guard step: `terraform plan` with `-replace='hcloud_server.registry'` + the **5** `-target`s; `terraform show -json`; source `registry-host-replace-gate.sh`; abort (naming store/NIC/firewall/volume) on gate fail. No `[ack-destroy]` bypass.
- [ ] 1.4 Apply the saved plan + jq backstops (`hcloud_volume.registry` 0 delete/forget; `hcloud_server_network.registry` create).
- [ ] 1.5 Best-effort (non-gating) heartbeat-status line in the summary via the Uptime API.
- [ ] 1.6 Dispatch summary step (`if: always()`).

## Phase 2 — FIX B: betteruptime_team_member.ops

- [ ] 2.1 Add `betteruptime_team_member.ops` (email `ops@jikigai.com`, `role="responder"`, `team_name` only if 0.1 requires it) to `apps/web-platform/infra/uptime-alerts.tf`.
- [ ] 2.2 Append `-target=betteruptime_team_member.ops` to the per-merge apply target list in the workflow.
- [ ] 2.3 Parity edit for FIX B per 0.6 (covered set or self-balancing); NOT an OPERATOR_APPLIED_EXCLUSION.

## Phase 3 — Destroy-guard gate + tests + guard-suite sweep

- [ ] 3.1 Create `tests/scripts/lib/registry-host-replace-gate.sh` (positive-action filter; 5-member allow-set; counters: out_of_scope==0, store_destroyed==0, volume_bad_update==0, server_replaced==1, nic_recreated==1, firewall_ok).
- [ ] 3.2 Create `tests/scripts/test-registry-host-replace-gate.sh` (6 synthesized fixtures: PASS-with-volume-update / volume-delete-ABORT / volume-replace-ABORT / out-of-scope-ABORT / no-op-ABORT / NIC-stripped-ABORT); register per the repo's shell-test runner.
- [ ] 3.3 Empirically validate the parity strip: run parity with `registry_host_replace` present-but-unstripped; add `stripJob(...,"registry_host_replace")` (exact literal) iff RED; add unit assertion; confirm no registry address in `MOVED_OPERATOR_CONSUMED`.
- [ ] 3.4 Run every guard suite from the 0.6 inventory; add any mechanically-failing suite to the edit set.

## Phase 4 — Docs / ADR / C4

- [ ] 4.1 Amend `ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` (reprovision path + recipient decision).
- [ ] 4.2 Add a header note in `apps/web-platform/infra/zot-registry.tf` about the dispatch-replace path.

## Phase 5 — After merge (automated, not deferred to a human)

- [ ] 5.1 After the merge-triggered apply drains the concurrency group, `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=registry-host-replace -f reason="…"`.
- [ ] 5.2 `gh run watch`; confirm guard passed, apply succeeded, volume preserved+resized to 30 GB, NIC re-attached.
- [ ] 5.3 Bounded-poll the Uptime API until `soleur-registry-disk-prd` `status=="up"`; then bounded-poll `/api/v2/incidents` until auto-resolved (distinguish non-2xx from not-yet-up).
- [ ] 5.4 Failure branch: on mid-apply failure, re-dispatch (re-creates from preserved volume); never auto-re-replace on a verification lag.
- [ ] 5.5 Close the incident artifact only after 5.3 green; PR body uses `Ref` not `Closes`.

## Verification (Acceptance Criteria)
See the plan's `## Acceptance Criteria` (Pre-merge / Post-merge) — do not duplicate here.
