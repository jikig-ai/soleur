# Tasks — inngest zot-primary bootstrap pull path

Plan: `knowledge-base/project/plans/2026-08-12-fix-inngest-zot-primary-bootstrap-pull-plan.md`
Branch: `feat-one-shot-7462-inngest-zot-bootstrap-pull`
Draft PR: #7516
Refs: #7462 (step 4), #7228 — both stay OPEN.

Ordering is contract-first: TF variables and template wiring exist before the cloud-init
consumer references them, or the consumer is dead code.

## Phase 0 — Preconditions (no edits)

- [x] 0.1 Confirm the **specific** digest pinned in `cloud-init-inngest.yml`
      (`sha256:6cdaa63d1496642e681898a831234b712f75d3b09bd0844bcabec3de74b0a0f8`) is present in
      zot — not merely that the 2026-08-10 mirror step reported success.
- [x] 0.2 Confirm `10.0.1.40 → 10.0.1.30:5000` is permitted by the private-net topology.
- [x] 0.3 Record both results for the PR body.
- [x] 0.4 **Stop condition:** if 0.1 fails, do not edit cloud-init. The remedy is a
      `mirror_only=true` backfill dispatch of `build-inngest-bootstrap-image.yml`.

## Phase 1 — RED tests (before implementation)

- [x] 1.1 Extend `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` with a failing
      assertion per Guard Contract mutation row (see plan `## Guard Contract`).
- [x] 1.2 Row 1: GHCR attempted first → RED.
- [x] 1.3 Row 2: digest dropped from the zot ref (mutable tag) → RED.
- [x] 1.4 Row 3: `inngest_ghcr_fallback` emit silenced → RED.
- [x] 1.5 Row 4: extract container reads the GHCR literal while the pull uses zot → RED.
- [x] 1.6 Row 5: both-legs-failed marker removed → RED.
- [x] 1.7 Row 6 (anti-vacuity): suite fails when it checks zero files → RED.
- [x] 1.8 Confirm all rows are RED before writing any implementation.

## Phase 2 — Terraform variables

- [x] 2.1 `variables.tf`: add `zot_pull_user` — `sensitive = true`, no default.
- [x] 2.2 `variables.tf`: add `zot_pull_token` — `sensitive = true`, no default.
- [x] 2.3 **Hard precondition:** both `TF_VAR_*` values exist in Doppler `prd_terraform` before
      merge. Terraform resolves all root variables before `-target` pruning, so an unresolved
      no-default var fails the entire merge-triggered apply even though the inngest resources
      are `-target`-excluded.

## Phase 3 — Template-var wiring

- [x] 3.1 `inngest-host.tf`: add `zot_registry_endpoint = local.registry_endpoint` to the
      `templatefile(...)` map.
- [x] 3.2 `inngest-host.tf`: add `zot_pull_user = var.zot_pull_user` and
      `zot_pull_token = var.zot_pull_token`, adjacent to the existing `ghcr_read_*` bake.
- [x] 3.3 Carry the same rationale comment shape as the `ghcr_read_*` bake (cold-boot must not
      depend on Doppler answering at the boot instant).

## Phase 4 — Docker insecure-registry entry

- [x] 4.1 `cloud-init-inngest.yml`: add the baked zot endpoint to the docker daemon
      configuration's insecure-registry list, mirroring the equivalent block in
      `cloud-init.yml` including its justification.
- [x] 4.2 Verify cloud-init writes the entry into the daemon config file so it exists at first
      boot ahead of any pull.

## Phase 5 — zot login before the pull

- [x] 5.1 `cloud-init-inngest.yml`: authenticate to zot from the baked creds in the same runcmd
      region as the existing GHCR login.
- [x] 5.2 Emit `zot-login-ok` / `zot-login-FAILED` / `zot-creds-EMPTY` phone-home stages
      mirroring the existing GHCR trio.
- [x] 5.3 Confirm placement precedes the pull — the bootstrap image's own `zot_login` runs too
      late to authorize the pull that fetches that very image.

## Phase 6 — zot-primary ref resolution

- [x] 6.1 Resolve the effective ref once, before `pre-oci-pull`.
- [x] 6.2 Endpoint non-empty → try `<endpoint>/jikig-ai/soleur-inngest-bootstrap@<same-sha256>`.
- [x] 6.3 Success → emit `inngest_zot` (info); use that ref for the pull **and** the
      `docker create` / `docker cp` extract **and** `/etc/default/soleur-inngest-image`.
- [x] 6.4 Miss → emit `inngest_ghcr_fallback` and fall back to the unchanged GHCR ref.
      **Amended 2026-08-13:** done deliberately DIFFERENTLY from the parenthetical this row
      carried ("**warning**, consumed by the fallback-rate alarm"). `inngest-boot-phone-home.sh`
      takes no severity argument, so no "warning" is emitted; and the fallback-rate alarm is
      Sentry-based, which this host does not reach. Checked as done-as-implemented, not
      done-as-specified.
- [x] 6.5 Endpoint empty/unset → skip the zot leg entirely; today's GHCR path exactly.
- [x] 6.6 Carry the `sha256:` digest unchanged on both legs.

## Phase 7 — both-legs-failed marker

- [x] 7.1 When both legs fail, emit a distinct greppable phone-home stage naming which legs were
      attempted and each leg's failure reason.

## Phase 8 — Verification

- [x] 8.1 All Phase 1 rows now GREEN.
- [x] 8.2 `terraform validate` passes on the infra root.
- [ ] 8.3 Full-suite gate green at the commit under review.
- [ ] 8.4 Walk every Acceptance Criterion in the plan and record the evidence.

## Phase 9 — PR body

- [ ] 9.1 Record Phase 0.1 and 0.2 results.
- [ ] 9.2 State plainly that the change is **inert at merge**; name the gated
      `apply_target=inngest-host-replace` dispatch as the delivery path.
- [ ] 9.3 Record that the cutover-sequence arm step in #7462 requires `INNGEST_DIAGNOSTIC_BOOT`
      cleared from `soleur-inngest/prd`; this PR deliberately leaves it set.
- [ ] 9.4 Use `Ref #7462` / `Ref #7228` — never `Closes`. Both remain open.

## Out of scope — do not touch

- The cutover FSM, the flip guard, the monotonic latch, the Redis AOF volume.
- The Doppler `soleur-inngest/prd` config and the boot isolation allowlist (adding ZOT_* keys
  there makes `n_total != n_inngest` → FATAL; this is why the bake path was chosen).
- The `feat-zot-primary-write-path` worktree/branch — adjacent concurrent session, WRITE-path
  scope, unrelated to this PULL-path change.
- Dispatching the host replace.
