---
feature: feat-one-shot-zot-disk-full-capacity-retention
lane: single-domain
plan: knowledge-base/project/plans/2026-07-09-fix-zot-disk-full-capacity-retention-plan.md
type: ops-remediation
ref_issue: 6247
---

# Tasks — zot disk full: grow volume 30→60 GB + tighten retention keep-set

Derived from the finalized (deepened) plan. Apply path is the `registry-host-replace`
`workflow_dispatch` (dispatch-only OPERATOR_APPLIED_EXCLUSION), NOT the per-PR CI `-target` path.

## Phase 0 — Preconditions (read-only, in-session)

- [ ] 0.1 Read current `SOLEUR_ZOT_DISK`: `scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK`.
  Confirm the #6247 trigger (`resize_ok=true`, `fs_size_gb≈block_size_gb`, `pcent≥85`). If
  `resize_ok=false` / `fs_size_gb << block_size_gb`, STOP — resize regression, not capacity.
- [ ] 0.2 `gh issue reopen 6247` (tracking issue for this recurrence; postmortem listed it "open" but
  it was CLOSED-COMPLETED prematurely).
- [ ] 0.3 Re-derive live `hcloud_volume.registry` size via a scoped `terraform plan` (do not quote a
  stale number); confirm current 30 GB.
- [ ] 0.4 Read all three `.c4` files (`model,views,spec`) to confirm/cite "no C4 impact".
- [ ] 0.5 Phase 1.7.5 code-review overlap grep on the finalized Files-to-Edit list.
- [ ] 0.6 Check the persisted decision-challenge (`specs/.../decision-challenges.md`): if the operator
  resolved it to DROP the `sha256-.*` bound, skip the sha256-* edits (1.3 sha256 arm, ADR-087 note,
  test reword) and ship only the volume grow + v*/commit-sha 10→5.

## Phase 1 — Grow the volume (stop the bleed)

- [ ] 1.1 `apps/web-platform/infra/variables.tf`: `registry_volume_size` default `30 → 60`; rewrite
  the description (drop falsified "30 GB … with headroom" / "10 v* + 10 sha").
- [ ] 1.2 `apps/web-platform/infra/zot-registry.tf`: update the stale `30 GB` comment at `:375`.

## Phase 2 — Tighten the keep-set (stop the refill)

- [ ] 2.1 `apps/web-platform/infra/cloud-init-registry.yml` `keepTags`: `v.*` `mostRecentlyPushedCount`
  10→5; `[0-9a-f]{7,64}` 10→5.
- [ ] 2.2 (unless dropped per 0.6) `sha256-.*`: add `mostRecentlyPushedCount` **50** (NOT 20 — true
  keep req ~12–18/repo; backfill can evict out of order; 50 never prunes a kept image at current scale).
- [ ] 2.3 Rewrite the `:48-65` + `:21` comment narrative (bound + cosign-verify coupling; drop the
  "ALWAYS keep every sha256-*" absolute framing).
- [ ] 2.4 Verify rendered `user_data` < 32,768 bytes:
  `gzip -9 -c apps/web-platform/infra/cloud-init-registry.yml | base64 -w0 | wc -c` (measured ~10.9 KB
  raw; ample headroom) and byte-exact at first `terraform plan`.

## Phase 3 — Tests + docs

- [ ] 3.1 `apps/web-platform/infra/registry-boot-guard.test.sh`: re-word the `:106` `sha256-.*) UNCHANGED`
  assertion to assert the now-BOUNDED keep-set (anchor on the invariant, not comment prose); add
  positive assertions for the new v*/commit-sha `count: 5` (+ sha256 `count: 50` unless dropped). Keep
  all resize2fs / gc / delay assertions.
- [ ] 3.2 Amend `ADR-096-*.md` — "Capacity-vs-retention recurrence (2026-07-09, #6247)" (volume 30→60 +
  keep-set tighten + cosign-verify coupling constraint).
- [ ] 3.3 (unless dropped per 0.6) `ADR-087-*.md` — one-line consequence note (sig bound must never
  prune a kept image's sig; WARN→ENFORCE #5933 becomes blocking).
- [ ] 3.4 Ship deliverable: `knowledge-base/engineering/operations/post-mortems/zot-registry-disk-full-postmortem.md`
  — record the 2026-07-09 recurrence + capacity-vs-retention resolution; update the #6247 action-item row.
- [ ] 3.5 (optional sweep) `tests/scripts/lib/registry-host-replace-gate.sh:17` stale "10->30 GB" comment.
- [ ] 3.6 Run: `registry-boot-guard.test.sh`, `tests/scripts/test-registry-host-replace-gate.sh`, C4
  tests, and the full-suite exit gate (repo canonical runner — do not assume a framework).

## Phase 4 — Ship + dispatch + verify (post-merge, in-session)

- [ ] 4.1 Ship the PR — PR body uses `Ref #6247` (NOT `Closes`); record the +€1.32/mo Hetzner volume
  expense via `ops-advisor` before PR-ready; `ship` renders decision-challenges.md into the PR body +
  files the `action-required` issue.
- [ ] 4.2 Post-merge: dispatch `gh workflow run apply-web-platform-infra.yml -f
  apply_target=registry-host-replace -f reason="#6247 grow 30→60 + tighten keep-set"`. Reconcile the
  transient drift ONLY via this dispatch — never the drift issue's generic "terraform apply locally".
- [ ] 4.3 Verify (no SSH) via `Monitor`: first post-redeploy `SOLEUR_ZOT_DISK` shows `pcent<85`,
  `resize_ok=true`, `fs_size_gb≈57-58`, `block_size_gb=60`, `zot_restarts` stops climbing;
  `soleur-registry-disk-prd` heartbeat `status==up`; Better Stack disk incident auto-resolves. Confirm
  the private NIC bound (peer web-host zot-mirror push succeeds from `10.0.1.30:5000`).
- [ ] 4.4 `gh issue close 6247` after verification.
