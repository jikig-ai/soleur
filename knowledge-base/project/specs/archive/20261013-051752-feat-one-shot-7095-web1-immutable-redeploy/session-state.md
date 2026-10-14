# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-01-fix-web1-credential-delivery-channel-dark-plan.md
- Status: complete

### Errors
Two non-blocking notes from the planning subagent:
1. The initial plan Write was blocked by the IaC-routing guard (triggered by a rejected-alternative row
   mentioning hand-editing) — resolved with the `iac-routing-ack` marker and rewording.
2. deepen-plan gates 4.8 and 4.9 produced false positives (`var.doppler_token` is a pre-existing Doppler
   credential, not a GitHub PAT; the `components/**` hit was the Product/UX Gate quoting its own glob
   list) — both verified non-applicable. All other gates passed cleanly.

### Decisions
- **Baked-token hypothesis: CONFIRMED.** web-1's Doppler token is written once at first boot from
  `var.doppler_token` with no re-delivery path. The host emits 55 x `Doppler Error: Invalid Auth token`
  while the same value in Doppler authenticates (HTTP 200) — a *delivery* gap, not a *value* gap.
  The zot-gate-dark -> unauthenticated-GHCR -> `auth_denied` chain is confirmed verbatim from the host's
  own `ci-deploy` log.
- **Immutable redeploy REFUTED as executable.** `cx33` (server_type 115) stock is zero in all 6 Hetzner
  datacenters, verified live. `-replace` destroys before it creates, so it would take prod from
  *stale but serving* to *destroyed and unbootable*; `hr-prod-host-config-change-immutable-redeploy`'s
  own stock precondition fails. It also would not bypass the blocker — a fresh host needs 16 SSH
  installers through the same dark channel. ADR-154 records that zero stock makes `-replace`
  *unavailable*, not merely inadvisable.
- **PR #7097 failed because its delivery leg depends on a root-SSH bridge it never probed.**
  `deploy_pipeline_fix` (SSH-free `local-exec`) `depends_on` `infra_config_handler_bootstrap`
  (root SSH). The apply destroyed both resources, then failed with `connection reset by peer`;
  the payload never shipped. Reproduced identically on a second run.
- **Root cause of the three-day *duration* is an alert-response gap, not a detection gap.**
  The existing drift detector named the credential, symptom and remedy three times into an unread
  email channel. Phase 4 was reframed from "build a probe" to "make the existing verdict block the
  channel, and escalate to an `action-required` issue".
- **Draft Phase 3 cut in full** after three review agents independently flagged that converting the
  Access tokens to `doppler_secret` resources would publish `.deploy`'s *dead* state secret over the
  *live* Doppler value, removing the last remote write path to an unreplaceable host.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents: `Explore`, `architecture-strategist`, `security-sentinel`, `spec-flow-analyzer`,
  `git-history-analyzer`, `user-impact-reviewer`, `code-simplicity-reviewer`
- Live telemetry: `curl` /health + CF Access 3-probe control set, `scripts/betterstack-query.sh`
  (ClickHouse SQL), Cloudflare API, Hetzner API, Doppler API, `terraform init/output` against R2 state,
  `gh run view/list` across 5 workflows

## Collision reconciliation (parent, post-plan)
Two OPEN sibling PRs overlapped the plan; neither was visible to the Step 0a.5 merged-PR probes.

- **#7127** (`feat-fix-token-drift-ssh-origin`) — OPEN draft, all checks green, 2 files. Rewrites
  `check-cloudflare-token-drift.sh`'s exit contract, which plan Phase 0.4/4.1/4.5 depend on. It also
  establishes that the detector graded `ssh.<base>` DEAD *unconditionally* (it accepted only HTTP 200,
  but that origin speaks SSH), so the "3 consecutive dead verdicts" the plan cited were structurally
  guaranteed. An independent 403 confirms the token genuinely is dead, so the H6 diagnosis survives.
- **#7115** (`feat-one-shot-ci-ssh-token-replace`) — OPEN, stalled since 2026-07-31, plan-only with
  zero implementation. Its unbuilt deliverable is exactly plan Phase 1.1's `ci-ssh-token-replace` arm.

**Operator decision (2026-08-01):** land #7127 first and build this branch on top of it; absorb #7115's
scope here and close #7115 as absorbed.

**Operator decision (2026-08-01):** every prod write in Phases 1, 2, 4b and 5 stops for its own
explicit per-command go-ahead, per `hr-menu-option-ack-not-prod-write-auth`. Plan approval is not
write approval.
