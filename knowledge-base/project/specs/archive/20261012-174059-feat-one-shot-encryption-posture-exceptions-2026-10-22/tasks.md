# Tasks: close the encryption-posture exceptions expiring 2026-10-22

Plan: knowledge-base/project/plans/2026-10-12-chore-close-encryption-posture-exceptions-expiring-2026-10-22-plan.md

## Phase 1: PR1 - ledger, architecture docs, issue comments (merge before 2026-10-22)

- 1.1 Re-measure at work time (Hetzner read-only API, Better Stack) and confirm the plan's Research Insights table still holds
- 1.2 redis.session_store
  - 1.2.1 Remove the stores[] row and the non_iac_stores entry in scripts/encryption-posture-ledger.json
  - 1.2.2 Edit model.c4 sessionStore description: designed, not provisioned
  - 1.2.3 Add a post-audit correction entry in the 2026-07-23 audit doc
  - 1.2.4 Add the Phase 4a ledger-at-birth note to ADR-068; comment on #5274
  - 1.2.5 (cut by plan-review) no guard issue; obligation carried by ADR-068 note and #5274 comment
- 1.3 git_data.baked_credentials_on_host
  - 1.3.1 Re-point tracking_issue to #8620, expires_on 2026-12-31, new reevaluate_when and live_verification (record 2026-10-11 rebirth, cite #6167)
- 1.4 hcloud_volume.git_data
  - 1.4.1 Renew to 2026-11-12 with the new justification, reevaluate_when and dated live_verification (tracking #6897)
  - 1.4.2 Add the ADR-239 amendment 2026-10-12 (five CLO items, four CLO inputs with measurements, owner, blocker chain)
- 1.5 In-transit rows
  - 1.5.1 File the dedicated in-transit tracker issue
  - 1.5.2 Re-point the three rows, expires_on 2026-11-12, per-link compensating-control statements
  - 1.5.3 Grep docs/legal DPD and privacy policy for over-broad internal-hop TLS language; record findings in decision-challenges.md
- 1.6 Comment on #10112 about hcloud_volume.rehearsal_inngest tracking closed #8285 (no new issue)
- 1.7 Verify: lint sweep from the worktree, lint test, c4-count-parity, C4 syntax/render tests, gh issue view open-state check for every touched tracker
- 1.8 Post the #6897 progress comment; keep #6897 open

## Phase 2: PR2 - rotate-arm assert fix (own review; does not gate the deadline)

- 2.1 Write the three-row mutation matrix tests first (tests/scripts/test-git-data-host-replace-gate.sh)
- 2.2 Extract the post-apply volume loop into the gate lib, pass APPLY_TARGET, and edit the workflow step (apply-web-platform-infra.yml ~4037)
- 2.3 Run terraform-target-parity and gate tests; no dispatch
- 2.4 Link PR2 from #8211

## Operator-authorization items (not part of either PR)

- Wipe of hcloud_volume.git_data (needs the command named by the operator)
- Re-dispatch of apply_target=git-data-host-rotate to mint a D6 stamp (needs the command named)
- Final CLO re-ruling 2026-10-24
