# Tasks — digest-pinned automated web-host birth path (#6730)

Plan: `knowledge-base/project/plans/2026-07-25-feat-web-host-birth-path-plan.md`
Lane: cross-domain · Threshold: single-user incident · ADR-145 (provisional)

## Phase 0 — Preconditions (verify, do not assume)

- [x] 0.1 Lift the `install_crane()` shape from `reusable-release.yml` (crane is NOT preinstalled — verified)
- [x] 0.2 Read `workspaces_luks_cutover` end-to-end (closest first-provision `+create` precedent)
- [x] 0.3 Read the `apply` job's `host_creates` guard + `destroy-guard-filter-web-platform.jq` counter shape
- [x] 0.4 Enumerate the `-target` fan-out for one web host from `server.tf`'s `for_each` consumers

## Phase 1 — Birth gate lib (tests FIRST)

- [x] 1.1 Write `tests/scripts/test-web-host-birth-gate.sh` with reject arms: zero creates, two creates,
      wrong `each.key`, `resource_deletes > 0`, `nested_deletes > 0`, `reboot_updates > 0`, non-numeric counter
- [x] 1.2 Implement `tests/scripts/lib/web-host-birth-gate.sh` to satisfy them (sibling gate-lib interface)
- [x] 1.3 Mutation-prove each arm (flip the guard → the arm reds)
- [x] 1.4 Register the suite in `scripts/test-all.sh`

## Phase 2 — The dispatch job

- [x] 2.1 Add `web-host-create` to the `apply_target` enum AND its description string
- [x] 2.2 Add inputs: `web_host_key` (required), `confirm` (typed literal typo-guard); reuse `reason`
- [x] 2.3 Add the `web_host_create` job (parallel to `workspaces_luks_cutover`): `if:`, `environment:`,
      `concurrency`, `timeout-minutes`, Doppler install, backend creds, `terraform init`
- [x] 2.4 R1 gate — `SENTRY_DSN` non-empty in `prd_terraform` before anything else; fail-closed on unreadable
- [x] 2.5 Resolve digest via `resolve-web1-known-good-tag.sh` + `crane digest` → pinned `@sha256:` ref
- [x] 2.6 Mandatory `host-image-coherence-preflight.sh` with the pinned ref (non-zero aborts pre-apply)
- [x] 2.7 `terraform plan` (scoped `-target` + `-var image_name=<pinned>`) + source the birth gate
- [x] 2.8 `terraform apply tfplan`
- [x] 2.9 R2/R3/R4/R5 surfacing — `de.sentry.io`, client-side regex filter, `if: always()`

## Phase 3 — Re-add the lost assertions

- [x] 3.1 Replace the CAPABILITY-LOST block in `soleur-host-bootstrap-observability.test.sh` with live
      AC8/AC8b/AC13/AC14/AC16 assertions against the new job
- [x] 3.2 Register the job⇄gate pairing in `plugins/soleur/test/terraform-target-parity.test.ts`

## Phase 4 — Docs + ADR

- [x] 4.1 Author ADR-145 (`## Decision` + `## Alternatives Considered`); re-verify the ordinal at ship
- [x] 4.2 Amend ADR-128's R1–R5 preamble (the "until that path exists" framing is now false)
- [x] 4.3 Rewrite `web-host-birth.md` to lead with the dispatch; laptop-run chain → break-glass appendix
- [x] 4.4 Update the `host_creates` HALT text — "NO automated path" for `hcloud_server.web[*]` is now false

## Phase 5 — Verify by unwedging main

- [ ] 5.1 Dispatch `apply_target=web-host-create -f web_host_key=web-2`
- [ ] 5.2 Confirm `soleur-web-2` via the Hetzner API; R2 surfaces `cloud_init_complete`, no `fatal`
- [ ] 5.3 Confirm the next merge to main no longer HALTs

## Exit gate

- [x] `bash scripts/test-all.sh` green
- [x] `actionlint` clean on `apply-web-platform-infra.yml`
- [x] `check-adr-ordinals.sh` clean
- [x] `lint-infra-no-human-steps.py --changed` clean
