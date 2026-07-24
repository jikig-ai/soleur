---
title: "Tasks — feat(#6895): registry volume guest-side LUKS + ledger flip"
plan: knowledge-base/project/plans/2026-07-24-feat-6895-registry-volume-luks-plan.md
issue: 6895
lane: cross-domain
---

# Tasks — feat(#6895) registry LUKS at-rest

Derived from the plan. Template = `git_data_luks`. Deliverable = code-only PR (Terraform +
cloud-init + ledger flip + guard suite); **no `terraform apply`**; #6893 / #6588 stay OPEN.

## Phase 0 — Preconditions (no writes)
- [ ] 0.1 Confirm branch `feat-one-shot-6895-registry-volume-luks`; #6895/#6893/#6588 all OPEN (`gh issue view`).
- [ ] 0.2 Re-read against HEAD: `zot-registry.tf` (vol 407 / attach 418 / host 290-401 / secret blocks), `cloud-init-registry.yml` (packages ~21 / mount 656-687 / self-heal 484-506 / resize 642-682), `git-data-luks.tf` + `cloud-init-git-data.yml` LUKS block, `lint-encryption-posture.py::check_luks_row`, `git-data-luks.test.sh`.
- [ ] 0.3 `grep -rn 'mapper/registry\|"registry-plain"' apps/web-platform/infra/` — confirm mapper name `registry` is free.
- [ ] 0.4 Carry decisions: D1 = raw+refuse (Option B, recommended; A is valid); D2 = boot-open **REQUIRED** (host self-reboots :610); D4 = guarded `registry-luks-recut` dispatch recommended (in-PR vs follow-up = plan-review/CTO). P1-A/P1-B are required correctness fixes.

## Phase 1 — Terraform (in `zot-registry.tf`)
- [ ] 1.1 Add `resource "random_password" "registry_luks"` (length 40, special=false, no keepers/ignore_changes; comment cross-refs `git_data_luks`).
- [ ] 1.2 Add `resource "doppler_secret" "registry_luks_key"` (`project="soleur-registry"`, `config="prd"`, `name="REGISTRY_LUKS_KEY"`, `value=random_password.registry_luks.result`, `visibility="masked"`). Reuse existing `doppler_service_token.registry` — no new token.
- [ ] 1.3 Remove `format = "ext4"` from `hcloud_volume.registry` (D1/B); add SHARP-EDGE comment (raw device + guest luksFormat; no hcloud `encrypted` attr, ADR-140).
- [ ] 1.4 Extend `hcloud_server.registry.depends_on` with `doppler_secret.registry_luks_key`; add `REGISTRY_LUKS_KEY` to the boot secret set. Do **NOT** add `registry_luks` to `lifecycle.replace_triggered_by`.
- [ ] 1.5 Leave `hcloud_volume_attachment.registry` unchanged (already binds `hcloud_volume.registry.id`).

## Phase 2 — Guest cryptsetup (`cloud-init-registry.yml`)
- [ ] 2.1 `packages:` add `cryptsetup`.
- [ ] 2.2 **P1-B (REQUIRED reorder):** move the Doppler CLI install + `/etc/default/registry-doppler` write AHEAD of the mount block (currently at ~695-711, after the mount block). Then read `REGISTRY_LUKS_KEY` via the existing scoped doppler path (`--project soleur-registry --config prd`); never argv, never baked into user_data.
- [ ] 2.3 Replace plaintext mount (656-687): fail-loud empty-key guard → `blkid` TYPE discriminator (`""`→luksFormat luks2 `--key-file -`; `crypto_LUKS`→skip; else→FATAL refuse) → `luksOpen --key-file - "$DEV" registry` → `mkfs.ext4` mapper if unformatted → `mount /dev/mapper/registry /var/lib/zot` → fstab `/dev/mapper/registry ... nofail`. **DELETE the stale by-id fstab line (:687).**
- [ ] 2.4 Rework resize (642-682) to `cryptsetup resize registry` + `resize2fs /dev/mapper/registry`; update `.resize-result`.
- [ ] 2.5 Rework the raw-device invariant (664) for `crypto_LUKS`/mapper (not ext4-on-raw).
- [ ] 2.6 **D2 (REQUIRED):** add idempotent boot-time luksOpen ordered after `network-online` and before the self-heal (484-506) so `mount -a` remounts on reboot (host self-`reboot`s via NIC guard :610). No crypttab-keyfile.
- [ ] 2.7 **P1-A (REQUIRED):** widen the isolation self-check (:741-746) cardinality `3→4`, admit `REGISTRY_LUKS_KEY` in the names regex, update the "THREE admitted" comments (:730,:740).

## Phase 3 — Guard suite (`registry-luks.test.sh`, mirrors `git-data-luks.test.sh`)
- [ ] 3.1 Author mutation-tested assertions: discriminator (incl. crypto_LUKS/else-FATAL arms), `--key-file -` + no key in argv, printf-stdin delivery, `mount /dev/mapper/registry /var/lib/zot`, fstab evidence, fail-loud guard, scoped doppler read, TF (`random_password.registry_luks` + `REGISTRY_LUKS_KEY` present; no `format="ext4"`; attachment binds volume), resize-targets-mapper, **D2 boot-open present (unconditional)**, **P1-A isolation self-check admits REGISTRY_LUKS_KEY + cardinality 4**, **P1-B Doppler-before-LUKS ordering**, **stale by-id fstab line absent**.
- [ ] 3.2 Enforce a minimum-assertion floor; each assertion paired with a mutation proven to flip RED (P1-A mutation: leave count at 3 ⇒ RED).

## Phase 4 — Ledger flip (`scripts/encryption-posture-ledger.json`, `hcloud_volume.registry` row only)
- [ ] 4.1 `at_rest.mechanism` → `"luks"`; **delete the `exception` block**; `device_binding.mapper` → `"registry"`.
- [ ] 4.2 Rewrite `evidence` (real cloud-init luksFormat/luksOpen + fstab line numbers + tf secret pair), `defends_against`, `does_not_defend` (≥8 chars, non-empty), `disclosed_as: not-publicly-claimed`, `live_verification: "unavailable:no zot-host at-rest posture probe yet; tracked #6895"`.
- [ ] 4.3 Do NOT touch `hcloud_volume.workspaces_luks` (keep the ≥1 `available` row for `live_coverage_floor: 1`).

## Phase 5 — Verify (no apply)
- [ ] 5.1 `registry-luks.test.sh` green (+ mutation floor).
- [ ] 5.2 `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 (chain resolves).
- [ ] 5.3 `terraform -chdir=apps/web-platform/infra validate`/`fmt -check` (validate/plan only, NEVER apply).
- [ ] 5.4 Re-run existing registry suites (`registry-boot-guard`, `registry-insecure-config`, `zot-liveness-heartbeat`, `web-zot-consumer-probe`, `cloud-init-ghcr-seed-login`); grep for hard-coded plaintext-mount assumptions; fix in-scope only if falsified.
- [ ] 5.5 `git grep -n 'format *= *"ext4"' apps/web-platform/infra/zot-registry.tf` → no hit.
- [ ] 5.6 **Exclusion parity test:** if resource-enumerated, register `random_password.registry_luks` + `doppler_secret.registry_luks_key`; parity/exclusion suites green. Confirm drift-issue dedup.
- [ ] 5.7 `git status` shows only intended files; no apply ran; #6893/#6588 still OPEN.

## Phase 6 — ADR + deferrals / follow-ups
- [ ] 6.1 Land the **required** lean ADR-096 amendment (plaintext→guest-LUKS flip, D4 recut vehicle, `registry-host-replace`=FATAL footgun, escrow omission).
- [ ] 6.2 D4(ii): decide (plan-review/CTO) whether the guarded `registry-luks-recut` dispatch lands in this PR (unfired) or a follow-up. **Floor regardless:** file the D4(ii) tracking issue (re-eval criteria + Phase-4 milestone) + flag the wrong-dispatch=FATAL footgun in the PR body — `wg-when-deferring-a-capability-create-a`.
- [ ] 6.3 PR body: `Closes #6895`; `Ref #6893`, `Ref #6588` (never `Closes` on those).
