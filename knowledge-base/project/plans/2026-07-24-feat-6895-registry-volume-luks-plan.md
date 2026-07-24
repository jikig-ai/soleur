---
title: "feat(#6895): guest-side LUKS apparatus for hcloud_volume.registry + ledger flip"
date: 2026-07-24
issue: 6895
parent_gate: 6893
related_issues: [6588, 6893, 6896, 6897, 6901]
related_adrs: [ADR-140, ADR-141, ADR-119, ADR-096]
brand_survival_threshold: none
lane: cross-domain
type: feat
milestone: "Phase 4: Validate + Scale"
---

# feat(#6895): guest-side LUKS at-rest for the registry (zot) volume + posture-ledger flip

> Spec lacks a `lane:` (no `spec.md` for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`hcloud_volume.registry` (`apps/web-platform/infra/zot-registry.tf:407`, `format = "ext4"`) is
the **plaintext** block volume for the self-hosted zot OCI registry (the GHCR mirror at
`/var/lib/zot`). It holds OCI blobs + cosign `.sig` referrers for our two private platform
images. It is **disposable** — a seized/snapshot disk exposes only container-image bytes whose
integrity comes from cosign digest-pinning, and the store re-fills from GHCR on any recreate.
Per ADR-140 it is currently recorded as a `plaintext-exception` row in the encryption-posture
ledger (`scripts/encryption-posture-ledger.json`, expires `2026-10-22`, tracking #6895).

This feature builds the **guest-side LUKS apparatus** for that volume — mirroring the existing
`git_data_luks` apparatus (the correct template; see §Template choice) — and flips the ledger
row from `mechanism: plaintext-exception` → `mechanism: luks`.

**Deliverable = a reviewed, mergeable PR containing ONLY:** the LUKS apparatus (Terraform in
`zot-registry.tf`, guest cryptsetup in `cloud-init-registry.yml`, a mutation-tested guard suite)
plus the one-row ledger flip. **No `terraform apply` runs in this PR.** The destroy+recreate that
actually re-encrypts the live registry volume is a **separate, deliberately gated operator step
OUTSIDE this PR** (see §Infrastructure → Apply path). **Zero live-infra mutation on merge** — the
registry resources are `OPERATOR_APPLIED_EXCLUSION` (never in the per-PR `-target=` list;
`zot-registry.tf:15`), and the 12h drift detector is **plan-only** (`terraform plan
-detailed-exitcode`, files an issue, never applies — `scheduled-terraform-drift.yml:100`).

**Parent gate #6893 and P1 #6588 STAY OPEN** — this PR touches neither.

### Template choice — git_data_luks, not workspaces_luks

The repo has two guest-side LUKS templates. `workspaces_luks` is heavy (10 TF resources across 2
files, a 176 KB freeze/rsync/dead-man/canary cutover, R2 header escrow, a reviewer-gated GitHub
environment, ~9 test files) — all of it exists to migrate **sole-copy, populated, live user data
in place** irreversibly (ADR-119). `git_data_luks` is lean (5 TF resources, boot-time
`cryptsetup` in cloud-init, one mutation-tested guard file, **no escrow, no reviewer gate, no
freeze machinery**) because its volume is **born fresh**. The registry volume is disposable and
born-fresh (re-fills from GHCR) — exactly the `git_data` situation. **Mirror `git-data-luks.tf` +
the `cloud-init-git-data.yml` LUKS block + `git-data-luks.test.sh`. Do NOT port header escrow,
the reviewer environment, the CI boot-token channel, the cutover/freeze/dead-man machinery, or the
emit/harness leaf helpers.** The registry apparatus is even leaner than git-data on the secret
channel: the isolated `soleur-registry` Doppler project + read-only `doppler_service_token.registry`
already exist and already reach the host at boot — so **no new Doppler service token is needed.**

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6895 / task) | Reality (verified against `origin` worktree) | Plan response |
|---|---|---|
| terraform at `zot-registry.tf:407` | Confirmed: `hcloud_volume.registry`, `format = "ext4"`, `size = var.registry_volume_size`, `location = var.registry_location` | Edit in place |
| "disposable GHCR mirror; integrity via cosign digest-pinning" | Confirmed: `rootDirectory` `/var/lib/zot`; re-fills from GHCR; a `registry-region-migrate` dispatch already recreates the store and re-fills | Drives `threshold: none` + lean git-data template |
| "mirror the EXISTING workspaces_luks and git_data_luks apparatus" | Both exist. git_data_luks is the lean/correct fit; workspaces_luks is the heavy sole-copy-data fit | Mirror **git_data_luks** |
| ledger row exists as plaintext-exception | Confirmed: `scripts/encryption-posture-ledger.json:130-152`, `mapper: "registry-plain"`, `expires_on 2026-10-22`, `tracking #6895` | Flip to `luks` in the same PR (linter requires apparatus + row atomic) |
| ledger `kind` "flips" plaintext→guest-luks | **Correction:** `kind` is already `guest-luks-volume` (permanent for the class). What flips is `at_rest.mechanism` `plaintext-exception`→`luks` **and** removal of the `exception` block **and** `mapper` `registry-plain`→`registry` | Edit those fields only |
| "destroy+recreate ... SEPARATE gated operator step" | Registry resources are `OPERATOR_APPLIED_EXCLUSION`; sanctioned operator apply is an untargeted/`-replace` apply, not per-PR | Operator step documented OUTSIDE this PR; PR is code-only |
| Layer A linter is a required check | **Correction:** currently **advisory/non-blocking** (absent from `required-checks.txt`; soaking, tracked #6901) — but the edit must still make `python3 scripts/lint-encryption-posture.py --repo-sweep` PASS | AC gates on a green sweep |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing at merge (code-only, zero apply). If the
apparatus itself is wrong, the **operator's** later gated recut boots a registry host that either
(a) fails loud and zot never starts → Better-Stack liveness-absence alert (the safe failure), or
(b) — the failure this plan guards against — silently mounts plaintext, certifying a false-green
posture row. No end-user data is on this volume.

**If this leaks, the user's data is exposed via:** it is **not** — the registry volume holds only
OCI image blobs + cosign signatures (our own platform images), never user/personal/repo data. A
seized disk exposes container bytes whose integrity is cosign-pinned; at-rest LUKS here is
defense-in-depth on a disposable mirror, not a user-data control.

**Brand-survival threshold:** none.
`threshold: none, reason: the registry volume holds only OCI image blobs + cosign signatures (a disposable GHCR mirror that re-fills from GHCR) — no user, personal, or repository data is ever written to it; at-rest encryption is defense-in-depth, not a user-data confidentiality control.`
(Required scope-out bullet because the diff touches sensitive paths — `.tf` + `cloud-init*.yml` —
per preflight Check 6. No CPO sign-off required at `none`.)

## Goals

1. Add the guest-side LUKS apparatus for `hcloud_volume.registry`, mirroring `git_data_luks`,
   so a freshly-provisioned registry volume boots LUKS-encrypted at `/var/lib/zot`.
2. Flip the ledger row `hcloud_volume.registry` to `mechanism: luks` (remove exception; retarget
   `mapper`), and make `scripts/lint-encryption-posture.py --repo-sweep` resolve the device-binding
   chain to real code and PASS.
3. Ship a mutation-tested guard suite (`registry-luks.test.sh`) mirroring `git-data-luks.test.sh`.
4. Preserve **zero live-infra mutation on merge** and keep #6893 / #6588 open.

## Non-Goals / Out of Scope (deferred — file tracking issues)

- **Running the destroy+recreate re-encryption apply.** Gated operator step, OUTSIDE this PR.
- **R2 LUKS-header escrow** (workspaces `#6649` pattern). Not needed for a disposable volume —
  passphrase loss ⇒ recreate + re-fill from GHCR. Do NOT port `workspaces-luks-header.tf`.
- **A dedicated daily at-rest monitor unit** (`luks-monitor.*` is workspaces-only). Registry
  at-rest liveness rides the existing zot liveness/disk heartbeats + the fail-loud boot guard;
  Layer B live-reconcile (ADR-141, deferred) is the eventual live check. If a decision (D2/D3
  below) is deferred, file a tracking issue with re-evaluation criteria + the Phase-4 milestone.

## Key Design Decisions (surface to CTO / plan-review / deepen-plan)

### D1 — Raw volume + refuse-on-populated discriminator (RECOMMENDED) vs `format=ext4` + `isLuks`
- **Option A (git-data parity):** keep `format = "ext4"`, guard with `if ! cryptsetup isLuks`.
  Simplest, precedented. **Hazard:** on a *populated plaintext* device `isLuks` is false ⇒
  `luksFormat` wipes it (ADR-119 fact 2, the headline data-loss mechanism). Acceptable for a
  disposable mirror, but silent.
- **Option B (workspaces parity — RECOMMENDED):** remove `format` (raw volume) and use the `blkid
  -o value -s TYPE` discriminator: `""` → `luksFormat`; `crypto_LUKS` → `luksOpen` (no-op format);
  **any other TYPE (e.g. `ext4`) → FATAL, refuse to touch.** Fail-loud instead of silent-wipe if
  the apparatus is ever pointed at the old populated plaintext volume (e.g. an accidental
  `registry-host-replace`, which *preserves* the volume, run before the recut). ADR-140-aligned
  (the plaintext/LUKS sibling-namespace hazard is the exact false-green this whole feature exists
  to prevent). Cost: a ForceNew diff on the volume — but drift is plan-only and the resource is
  operator-excluded, so **no live mutation on merge**; the gated recut provides a fresh raw volume
  regardless. **Recommend Option B.** (Note: the host `user_data` change already forces a
  host-replace diff regardless of D1, so D1 does not change the "drift until the operator applies"
  reality — only the safety guard.)

### D2 — Reboot survivability (RECOMMENDED: add a boot-time idempotent luksOpen)
Unlike git-data (never rebooted, only replaced), the registry host has an **existing reboot
self-heal** (`cloud-init-registry.yml:484-506`) that runs `mount -a` + `docker restart zot`.
With LUKS, fstab points at `/dev/mapper/registry`, which is **closed after a reboot** (no
`/etc/crypttab`, matching git-data) — so `mount -a` fails and zot stays dark until re-provision.
**Recommend** a lean idempotent boot-time luksOpen (a `bootcmd`/systemd-oneshot ordered before the
self-heal / zot start) that reads `REGISTRY_LUKS_KEY` via the existing scoped
`doppler_service_token.registry` and opens the mapper — so a routine reboot remounts cleanly. This
is the one place the registry apparatus should exceed bare git-data parity, because the registry
host's self-heal assumes the mount returns. If judged out-of-scope, defer with a tracking issue
(re-eval: "does a registry-host reboot recur outside a full re-provision?").

### D3 — No escrow, no separate at-rest monitor (RECOMMENDED, matches git-data)
git-data has neither; the registry is disposable, so neither is warranted. Confirmed.

### D4 — Recut vehicle for the operator step (OUTSIDE this PR)
The sanctioned operator apply is a scoped `terraform apply -replace` of the volume + attachment +
host (fresh raw volume ⇒ cloud-init luksFormats it ⇒ zot re-fills from GHCR). Two vehicles exist
or could: (i) the operator's untargeted full apply / a local `-replace` (already the sanctioned
`OPERATOR_APPLIED_EXCLUSION` path per `zot-registry.tf:15`); (ii) a lean, destroy-guarded,
typed-confirm `registry-luks-recut` `workflow_dispatch` target mirroring the existing
`registry-region-migrate` / `workspaces-luks-recut` guards. **This PR does NOT add or fire (ii)** —
it is documented as the recommended operator vehicle and deferred to the gated step (file a
follow-up if a dispatch target is wanted). Keeps the PR to "cloud-init + terraform + ledger" per
the task scope.

## Implementation Phases

### Phase 0 — Preconditions (verify, no writes)
- `git branch --show-current` = `feat-one-shot-6895-registry-volume-luks`; #6895 / #6893 / #6588 all OPEN.
- Re-read the four load-bearing sources against HEAD before editing: `zot-registry.tf` (volume
  407, attachment 418, host 290-401, `random_password`/`doppler_secret` blocks 145-287),
  `cloud-init-registry.yml` (packages ~21, mount runcmd 656-687, self-heal 484-506, resize
  642-682), `git-data-luks.tf` + `cloud-init-git-data.yml` LUKS block (the template),
  `scripts/lint-encryption-posture.py` `check_luks_row()` + `git-data-luks.test.sh`.
- Confirm mapper-name choice `registry` is unused elsewhere (`grep -rn 'mapper/registry\|"registry-plain"' apps/web-platform/infra/`).

### Phase 1 — Terraform LUKS resources (in `zot-registry.tf`, co-located with the attachment)
The linter's `file_has_secret_pair` requires the `random_password` + `doppler_secret` pair to live
in the **same file as the attachment** (`hcloud_volume_attachment.registry`, `zot-registry.tf`).
Keep them in `zot-registry.tf` (do NOT split into a new `registry-luks.tf`, which would orphan the
attachment from its secret pair). Add:
1. `resource "random_password" "registry_luks"` — `length = 40`, `special = false` (stdin/htpasswd-safe,
   ~238 bits). No `keepers`, no `ignore_changes` — rotation is operator-explicit `-replace` (see SE).
   Comment cross-refs `random_password.git_data_luks`.
2. `resource "doppler_secret" "registry_luks_key"` — `project = "soleur-registry"`,
   `config = "prd"` (the ISOLATED project's root, via `doppler_environment.registry_prd`),
   `name = "REGISTRY_LUKS_KEY"`, `value = random_password.registry_luks.result`, `visibility = "masked"`.
   (Reuses the isolated project; the existing `doppler_service_token.registry` already reads it —
   **no new service token**.)
3. `hcloud_volume.registry` (`:407`) — **remove `format = "ext4"`** (Option B / D1). Leave name,
   size, location, labels unchanged. Add a SHARP-EDGE comment: raw device + guest luksFormat; there
   is no hcloud `encrypted` attribute (ADR-140).
4. `hcloud_server.registry` — extend `depends_on` with `doppler_secret.registry_luks_key` (mirrors
   the existing `zot_pull_token_registry`/`zot_push_token_registry` boot-ordering guard); add the
   `registry_luks_key`/`REGISTRY_LUKS_KEY` to the boot secret set the host's fail-loud guard expects.
   **Do NOT add `registry_luks` to `lifecycle.replace_triggered_by`** — a passphrase rotation must
   NOT merely replace the host (cloud-init would luksOpen the OLD-key volume with the NEW key and
   fail); rotation is a recut (SE below).
5. `hcloud_volume_attachment.registry` (`:418`) — unchanged (already `volume_id = hcloud_volume.registry.id`,
   which satisfies `attachment_binds_volume`).

### Phase 2 — Guest cryptsetup in `cloud-init-registry.yml`
1. `packages:` — add `cryptsetup` (keep `e2fsprogs`).
2. Pass `REGISTRY_LUKS_KEY` to the guest via the EXISTING scoped Doppler path (the host already
   writes a 0600 root env file with `doppler_service_token.registry.key` and runs `doppler run` at
   boot). Read the key with `doppler run --project soleur-registry --config prd -- ...` (or
   `doppler secrets get REGISTRY_LUKS_KEY --plain`), never argv, never baked into `user_data`.
3. Replace the plaintext mount runcmd (`656-687`) with the git-data-shaped block, keyed off
   `DEV=/dev/disk/by-id/scsi-0HC_Volume_${registry_volume_id}`:
   - Fail-loud: `[ -n "$REGISTRY_LUKS_KEY" ] || { echo "FATAL ... refusing unencrypted mount"; exit 1; }`
   - **D1/Option B discriminator:** `TYPE=$(blkid -o value -s TYPE "$DEV" ...)`; `""` →
     `printf '%s' "$REGISTRY_LUKS_KEY" | cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV"`;
     `crypto_LUKS` → skip format; else → `FATAL` refuse.
   - `[ -e /dev/mapper/registry ] || printf '%s' "$REGISTRY_LUKS_KEY" | cryptsetup luksOpen --key-file - "$DEV" registry`
   - `blkid /dev/mapper/registry >/dev/null 2>&1 || mkfs.ext4 -q /dev/mapper/registry`
   - `mountpoint -q /var/lib/zot || mount /dev/mapper/registry /var/lib/zot`
   - fstab: `/dev/mapper/registry /var/lib/zot ext4 defaults,nofail 0 2` (append-if-absent; no crypttab).
   - **resize path (`642-682`):** `resize2fs` must target `/dev/mapper/registry` (and `cryptsetup
     resize registry` first if the underlying volume grew) — NOT the raw `$DEV`. Update the
     `.resize-result` record accordingly.
   - **raw-device invariant (`664`, `lsblk TYPE ... part`)**: rework — the LUKS device presents
     `crypto_LUKS`, the mapper presents `ext4`; the no-partition assert moves to `$DEV` being
     `crypto_LUKS` (or empty pre-format), not `ext4`-on-raw.
4. **D2 boot-time luksOpen:** add an idempotent boot step (bootcmd/oneshot) ordered before the
   self-heal (`484-506`) that reads `REGISTRY_LUKS_KEY` (scoped doppler) and luksOpens the mapper if
   closed, so `mount -a`/`docker restart zot` on reboot remounts `/dev/mapper/registry`. Keep the
   self-heal's `mountpoint -q /var/lib/zot` short-circuit.

### Phase 3 — Mutation-tested guard suite `registry-luks.test.sh`
Mirror `git-data-luks.test.sh` (each assertion paired with a mutation that must flip it to RED;
enforce a minimum-cardinality floor). Files under test: `cloud-init-registry.yml`, `zot-registry.tf`.
Assertions:
- isLuks/blkid discriminator present (incl. the `crypto_LUKS`→no-op and else→FATAL arms).
- every `luksFormat`/`luksOpen` carries `--key-file -`; `REGISTRY_LUKS_KEY` never a bare argv token.
- key delivered via `printf '%s' "$REGISTRY_LUKS_KEY" | cryptsetup` (stdin).
- `mount /dev/mapper/registry /var/lib/zot` present; fstab evidence `/dev/mapper/registry` present.
- fail-loud empty-key guard present.
- doppler read (scoped `soleur-registry`/`prd`) wraps the setup.
- TF: `resource "random_password" "registry_luks"` + `name = "REGISTRY_LUKS_KEY"` present;
  `hcloud_volume.registry` has **no** `format = "ext4"` (D1/B); attachment binds `hcloud_volume.registry.id`.
- (if D2) boot-time luksOpen present & ordered before the self-heal.
- resize path targets `/dev/mapper/registry`, not the raw `$DEV`.

### Phase 4 — Ledger flip (`scripts/encryption-posture-ledger.json`, the `hcloud_volume.registry` row)
Edit only the registry row (lines 130-152). Set `at_rest.mechanism: "luks"`; **delete the entire
`exception` block**; set `device_binding.mapper: "registry"` (was `registry-plain`). Rewrite:
- `evidence`: `apps/web-platform/infra/cloud-init-registry.yml:<luksFormat-line>,<luksOpen-line> (cryptsetup luksFormat/luksOpen registry); key: random_password.registry_luks + doppler_secret.registry_luks_key (zot-registry.tf); fstab: cloud-init-registry.yml:<fstab-line>` (fill real line numbers post-edit).
- `defends_against`: "a seized/RMA'd or snapshot-imaged Hetzner block volume: OCI blobs + cosign signatures are unreadable without the Doppler-held LUKS passphrase".
- `does_not_defend`: "a leaked credential, an app-layer read on the unlocked live registry host, or exfiltration via a compromised zot process" (must be ≥8 chars, non-empty, not "none/n/a").
- `disclosed_as`: `not-publicly-claimed` (registry LUKS is not a public legal claim).
- `live_verification`: `unavailable:no zot-host at-rest posture probe yet; tracked #6895` (a `luks`
  row does NOT need a live probe; keep `hcloud_volume.workspaces_luks` as the ≥1 `available` row so
  `live_coverage_floor: 1` still holds — do not touch that row).
Verify `python3 scripts/lint-encryption-posture.py --repo-sweep` resolves the chain and PASSES
(device_binding volume+attachment real, attachment binds volume, secret pair co-located in
`zot-registry.tf`, mapper `registry` resolves through the cryptsetup site + fstab evidence).

### Phase 5 — Full verification (no apply)
- `registry-luks.test.sh` green (+ mutation floor met).
- `python3 scripts/lint-encryption-posture.py --repo-sweep` green.
- `cd apps/web-platform && terraform -chdir=infra fmt -check` (or the repo's `terraform validate`
  path) — **plan/validate only, NEVER apply**. If `terraform validate` needs providers, use the
  existing infra test/validation harness; do NOT authenticate to Hetzner/Doppler.
- Existing registry test suites still green: `registry-boot-guard.test.sh`,
  `registry-insecure-config.test.sh`, `zot-liveness-heartbeat.test.sh`, `web-zot-consumer-probe.test.sh`,
  `cloud-init-ghcr-seed-login.test.sh` (grep them for hard-coded `mount $DEV /var/lib/zot` / raw-device
  assumptions that the LUKS change breaks; update in-scope if the change falsifies them).
- `git grep -n 'format *= *"ext4"' apps/web-platform/infra/zot-registry.tf` → **no hit** (D1/B).

## Acceptance Criteria

### Pre-merge (this PR)
- [ ] `hcloud_volume.registry` in `zot-registry.tf` has **no** `format` attribute (D1/B); `grep -c 'format' <the-registry-volume-block>` = 0.
- [ ] `zot-registry.tf` declares `random_password.registry_luks` (length 40, special=false) and `doppler_secret.registry_luks_key` (`project = "soleur-registry"`, `name = "REGISTRY_LUKS_KEY"`), co-located with `hcloud_volume_attachment.registry`.
- [ ] `hcloud_server.registry.depends_on` includes `doppler_secret.registry_luks_key`; `registry_luks` is **absent** from `lifecycle.replace_triggered_by`.
- [ ] `cloud-init-registry.yml` `packages:` includes `cryptsetup`; the mount runcmd does `cryptsetup luksFormat --type luks2 --key-file -` + `luksOpen --key-file - "$DEV" registry` + `mount /dev/mapper/registry /var/lib/zot`; the key is piped from `printf '%s' "$REGISTRY_LUKS_KEY"` (stdin) and never appears as a bare argv token; fail-loud empty-key guard present; else-TYPE→FATAL refuse arm present.
- [ ] fstab line `/dev/mapper/registry /var/lib/zot ext4 defaults,nofail 0 2` present; resize path targets `/dev/mapper/registry`.
- [ ] (D2, if adopted) an idempotent boot-time luksOpen is ordered before the reboot self-heal.
- [ ] `registry-luks.test.sh` passes, meets its mutation-cardinality floor, and every assertion has a paired mutation proven to flip it RED.
- [ ] Ledger row `hcloud_volume.registry`: `at_rest.mechanism == "luks"`, **no `exception` key**, `device_binding.mapper == "registry"`, `does_not_defend` non-empty (≥8 chars), `live_verification` matches `^(available|unavailable:.+)$`.
- [ ] `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 (device-binding chain resolves to real code; positive-work floor + `live_coverage_floor: 1` still satisfied).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is unaffected (no TS touched) — sanity only; the TS gate is not the target here.
- [ ] No `terraform apply` was run; `git status` shows only the intended files changed; #6893 and #6588 remain OPEN (do not reference them with `Closes`).
- [ ] PR body uses `Closes #6895` (title uses no `#`); references #6893/#6588 as `Ref` only.

### Post-merge (operator, OUTSIDE this PR — the gated re-encryption)
- [ ] `Automation: sanctioned OPERATOR_APPLIED_EXCLUSION apply path` (per `zot-registry.tf:15` CTO ruling). The operator runs a scoped `terraform apply -replace='hcloud_volume.registry' -replace='hcloud_volume_attachment.registry' -replace='hcloud_server.registry'` (fresh raw volume ⇒ cloud-init luksFormats ⇒ zot re-fills from GHCR), OR a `registry-luks-recut` dispatch if D4(ii) is later added. Not `Closes`-linked (the fix runs post-merge). Blast radius near-zero (disposable mirror; brief cold-pull gap while it re-fills).
- [ ] After the recut: zot liveness + disk heartbeats green; `web-zot-consumer-probe` green; the volume's device is `/dev/mapper/registry` (LUKS-backed).

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
Phase 2.8 reviewed: ALL infrastructure lives in Terraform (`zot-registry.tf`) + cloud-init
(`cloud-init-registry.yml`) — no SSH, no dashboard clicks, no manual host config. The only
non-in-PR action is the **sanctioned `OPERATOR_APPLIED_EXCLUSION` `terraform apply`** (CTO ruling,
`zot-registry.tf:15`), an established Terraform apply path for the registry resources — not a
manual provisioning step. It is deliberately outside this PR per the task's gating requirement.

### Terraform changes
- Files: `apps/web-platform/infra/zot-registry.tf` (add `random_password.registry_luks` +
  `doppler_secret.registry_luks_key`; remove `format` from `hcloud_volume.registry`; extend host
  `depends_on`), `apps/web-platform/infra/cloud-init-registry.yml` (guest cryptsetup + resize +
  D2 boot open). No new `.tf` file, no new Terraform root (extends the existing
  `apps/web-platform/infra/` root; R2 backend already configured).
- Providers: `hashicorp/random`, `DopplerHQ/doppler`, `hetznercloud/hcloud` — all already required
  in `main.tf`; no new provider, no version-pin change.
- Sensitive vars: **none new required** — the passphrase is `random_password` (Soleur-minted, in
  tfstate, R2-encrypted backend), published to `soleur-registry/prd` as `REGISTRY_LUKS_KEY`. **No
  operator-minted `TF_VAR_*`** (`hr-tf-variable-no-operator-mint-default`); `registry_volume_size`
  already has a default. The isolated `soleur-registry`/`prd` Doppler config already exists.

### Apply path
- **On merge: NONE.** Registry resources are `OPERATOR_APPLIED_EXCLUSION` (never in the per-PR
  `-target=` set); the 12h drift detector is plan-only. Merging is byte-safe.
- **Gated operator re-encryption (OUTSIDE this PR):** scoped `terraform apply -replace` of volume +
  attachment + host (D4). Destroy+recreate of a disposable, born-fresh raw volume ⇒ guest luksFormat
  ⇒ re-fill from GHCR. Expected downtime: a brief cold-pull gap (web hosts re-fill on demand);
  blast radius near-zero.
- **Transient drift note:** between merge and the operator recut, `terraform plan` shows the
  volume + host as pending replace. This is the accepted `OPERATOR_APPLIED_EXCLUSION` state (same as
  the workspaces_luks additive resources before their cutover) — the drift detector files/refreshes
  one advisory issue; it never applies.

### Distinctness / drift safeguards
- `dev != prd`: the registry is prd-only (a single `soleur-registry` host); no dev registry host.
- `lifecycle`: `random_password.registry_luks` has no `keepers` (stable across routine applies);
  the host's `replace_triggered_by` deliberately excludes it (passphrase rotation = recut, not a
  bare host replace).
- State: the passphrase lands in `terraform.tfstate` (R2-encrypted backend) and Doppler
  `soleur-registry/prd` — the same two-plane exposure as `git_data_luks`/`workspaces_luks`.

### Vendor-tier reality check
No new vendor, no free-tier gate (Hetzner volumes + Doppler secrets are already in use). N/A.

## Observability

```yaml
liveness_signal:
  what: zot answers on its private IP (existing SOLEUR liveness heartbeat) — gated on a successful
        LUKS mount of /var/lib/zot; a failed luksOpen/mount => zot never starts => heartbeat stops.
  cadence: existing zot-liveness-heartbeat cron cadence (betteruptime_heartbeat.registry_prd)
  alert_target: Better Stack absence alert (betteruptime_heartbeat.registry_prd)
  configured_in: apps/web-platform/infra/zot-registry.tf (betteruptime_heartbeat.registry_prd) + cloud-init-registry.yml
error_reporting:
  destination: cloud-init fail-loud FATAL (stderr -> journald) + Better Stack liveness-absence; the
               boot guard EXITS non-zero on empty key or an ext4/other-TYPE device (never mounts plaintext)
  fail_loud: true  # refuses to bring zot up rather than serving from an unencrypted/wrong device
failure_modes:
  - mode: empty/unreadable REGISTRY_LUKS_KEY at boot
    detection: cloud-init FATAL exit; zot never starts; liveness heartbeat absence
    alert_route: Better Stack (registry_prd heartbeat)
  - mode: device is populated plaintext ext4 (accidental host-replace before recut)
    detection: blkid TYPE=ext4 -> FATAL refuse (D1/B); in-surface stderr marker "refusing non-LUKS registry device"
    alert_route: Better Stack liveness absence (zot does not start)
  - mode: mapper closed after reboot (no crypttab)
    detection: D2 boot-open reopens it; if absent, mount -a fails -> liveness absence
    alert_route: Better Stack (registry_prd heartbeat)
logs:
  where: journald on the registry host (cloud-init + zot); disk self-report -> Better Stack Logs (SOLEUR_ZOT_DISK)
  retention: existing registry-host journald + Better Stack Logs retention (unchanged)
discoverability_test:
  command: python3 scripts/lint-encryption-posture.py --repo-sweep
  expected_output: exit 0 — hcloud_volume.registry row resolves as mechanism=luks via the real cryptsetup+fstab chain
```
**Blind-surface note (Phase 2.9.2):** the cloud-init cryptsetup block is a blind execution surface.
Its in-surface probe is the **fail-loud boot guard** (a FATAL that discriminates empty-key vs
wrong-TYPE-device vs closed-mapper in one stderr marker) surfaced off-box via the liveness-absence
heartbeat — no SSH needed. Layer B live-reconcile (ADR-141, deferred) is the eventual per-volume
posture probe (`live_verification` stays `unavailable:...#6895` until then).

## Architecture Decision (ADR/C4)

This applies the **already-accepted** design-time default (ADR-140: encryption posture is a
resolvable-evidence ledger; ADR-119: guest-side LUKS is the Hetzner-volume mechanism) to one more
volume; the **ledger row flip IS the recorded decision**. No new cross-cutting invariant, substrate,
or trust boundary is introduced.

### ADR
- **No new ADR.** Recommend a lean **amendment to ADR-096** (the zot-registry ADR) recording: the
  registry store volume flips plaintext->guest-side-LUKS; the recut (D4) is the sanctioned
  re-encryption vehicle; escrow is intentionally omitted (disposable). deepen-plan/CTO to confirm
  whether the amendment is warranted or the ledger row + this plan suffice.

### C4 views
- **Reviewer MUST read all three model files** (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`)
  before concluding — a keyword grep is not sufficient (per the C4-completeness mandate).
- **Enumeration checked:** external human actors — none new (no user interacts with the registry
  volume). External systems — GHCR (already modeled as the upstream mirror source; unchanged);
  Doppler/Hetzner (already modeled). Container/data store — `hcloud_volume.registry` / the zot
  store (already modeled as the registry host's storage; encryption is an at-rest *property*, not a
  C4 element). Access relationship — unchanged (web hosts + CI pull over the private net; the
  passphrase is a boot-time host-scoped read, no new edge). **Expected conclusion: no C4 impact**
  (at-rest LUKS is a mechanism the C4 model does not render) — but the reviewer records this only
  after reading the three files and citing this enumeration; an unsupported "None" is a reject.

### Sequencing
The ledger row's `mechanism: luks` describes the **target** state; it becomes *live* only after the
operator recut. Because Layer A resolves the row against the **apparatus code** (not live state),
the row PASSES the sweep the moment the apparatus lands — no `status: adopting` sequencing gap for
the ledger. Live truth is Layer B's job (deferred, ADR-141).

## Encryption Posture

```yaml
at_rest:
  store: hcloud_volume.registry
  mechanism: luks   # was plaintext-exception
  evidence: apps/web-platform/infra/cloud-init-registry.yml (cryptsetup luksFormat/luksOpen registry) + zot-registry.tf (random_password.registry_luks + doppler_secret.registry_luks_key) + fstab /dev/mapper/registry
  defends_against: a seized/RMA'd/snapshot-imaged Hetzner block volume — OCI blobs + cosign signatures unreadable without the Doppler-held LUKS passphrase
  does_not_defend: a leaked credential, an app-layer read on the unlocked live host, or exfiltration via a compromised zot process
  disclosed_as: not-publicly-claimed
  live_verification: unavailable:no zot-host at-rest posture probe yet; tracked #6895
in_transit:
  # unchanged by this PR — registry pull transport is private-net only (deny-all public firewall);
  # docker->zot is TLS on the private net (proxy-tls.tf / registry endpoint). Not re-declared here.
exception: none   # removed — mechanism is now luks, not plaintext-exception
```

## Domain Review

**Domains relevant:** engineering (infrastructure/security).

### Engineering / Infra (CTO)
**Status:** deferred to plan-review/deepen-plan (headless one-shot). **Assessment:** the load-bearing
CTO calls are D1 (raw+refuse vs ext4+isLuks — the ADR-119-fact-2 safety choice), D2 (reboot
survivability), and D4 (recut vehicle / whether to add a gated dispatch). These are surfaced as
explicit decisions above and routed to the plan-review CTO lens + deepen-plan precedent-diff
(§4.4). No live-infra mutation, no new vendor, no user-data surface.

### Product/UX Gate
**Tier:** none. No `## Files to Create`/`Files to Edit` path matches a UI surface (all changes are
`.tf` / `cloud-init*.yml` / `.json` ledger / `.test.sh`). Skipped.

**Skipped specialists:** none. **Pencil available:** N/A (no UI surface).

## Files to Edit
- `apps/web-platform/infra/zot-registry.tf` — add `random_password.registry_luks` + `doppler_secret.registry_luks_key`; remove `format` from `hcloud_volume.registry`; extend `hcloud_server.registry.depends_on`.
- `apps/web-platform/infra/cloud-init-registry.yml` — add `cryptsetup` package; replace plaintext mount with LUKS format/open/mount; fix resize + raw-device invariant; add D2 boot-open.
- `scripts/encryption-posture-ledger.json` — flip the `hcloud_volume.registry` row to `mechanism: luks` (remove exception; retarget mapper; update evidence/verification fields).
- (possibly) `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — lean amendment (D-decision; confirm at deepen-plan).
- (possibly, if any existing registry test hard-codes the plaintext mount) `apps/web-platform/infra/registry-boot-guard.test.sh` / `registry-insecure-config.test.sh` / `zot-liveness-heartbeat.test.sh` — update in-scope only if the LUKS change falsifies an existing assertion (verify via grep in Phase 5).

## Files to Create
- `apps/web-platform/infra/registry-luks.test.sh` — mutation-tested guard suite (mirrors `git-data-luks.test.sh`).

## Open Code-Review Overlap
None. (`gh issue list --label code-review --state open` bodies grepped for `zot-registry.tf`,
`cloud-init-registry.yml`, `registry-luks`, `encryption-posture-ledger`, `hcloud_volume.registry`
— zero matches.)

## Test Scenarios
- **T1** fresh raw volume → cloud-init `luksFormat`+`luksOpen registry`+`mkfs.ext4 mapper`+`mount /var/lib/zot`; asserted by `registry-luks.test.sh` (mutation-tested).
- **T2** populated plaintext ext4 device → `blkid TYPE=ext4` → FATAL refuse (never wipes); mutation flips the else-arm.
- **T3** already-LUKS device → `crypto_LUKS` → skip format, luksOpen no-op, mount; idempotent.
- **T4** empty `REGISTRY_LUKS_KEY` → fail-loud FATAL, non-zero exit, no mount.
- **T5** `lint-encryption-posture.py --repo-sweep` resolves the device-binding chain (volume+attachment real, secret pair co-located, mapper `registry` → cryptsetup + fstab) → PASS.
- **T6** (D2) reboot with closed mapper → boot-open reopens → `mount -a`/self-heal remounts.
- **T7** ledger: no `exception` key on the registry row; `live_coverage_floor: 1` still satisfied by `hcloud_volume.workspaces_luks`.

## Risks & Sharp Edges
- **A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6.** Filled above (threshold: none + reason).
- **SE1 — passphrase rotation is a recut, not a host replace.** `registry_luks` is deliberately
  absent from `replace_triggered_by`; rotating `random_password.registry_luks` then only replacing
  the host would luksOpen the OLD-key volume with the NEW key and FATAL. Rotation ⇒ `-replace` the
  passphrase + the volume (fresh) + host. Mirror the git-data rotation note.
- **SE2 — the linter requires the `random_password`+`doppler_secret` pair in the attachment's file.**
  Keep them in `zot-registry.tf`; a `registry-luks.tf` split would orphan the attachment and FAIL
  `file_has_secret_pair` — unless the attachment moves too (more churn; not recommended).
- **SE3 — do NOT let the ledger flip land without the apparatus.** Layer A resolves the mapper
  through the real cryptsetup site + fstab; flipping the row before the cloud-init/tf edits ⇒ sweep
  FAILs on the unresolved mapper. Land both in one commit.
- **SE4 — after this merges, an accidental `registry-host-replace` (which PRESERVES the volume) runs
  cloud-init against the still-plaintext ext4 volume.** With D1/B it fails loud (refuse) — safe but
  darks the registry. The ONLY sanctioned first apply is the recut (fresh volume). Document in the
  PR body + the ADR-096 amendment.
- **SE5 — resize + raw-device invariant.** The existing `resize2fs $DEV` and `lsblk TYPE ... part`
  logic assumes ext4-on-raw; both must move to the mapper (`cryptsetup resize` + `resize2fs
  /dev/mapper/registry`), or the disk-full resize apparatus (#6240/#6247) silently no-ops on LUKS.
- **SE6 — verify real line numbers in the ledger `evidence` string post-edit** (cryptsetup +
  fstab lines shift as cloud-init changes); a stale `file:line` still resolves via device_binding
  but the human-facing evidence should be accurate.
- **SE7 — do not reference #6893/#6588 with `Closes`.** They stay open; use `Ref`.

## Rollout
Code-only PR → review → merge (zero apply). The gated operator recut (D4) is a separate,
maintenance-window step outside this PR. If D2/D4/the ADR-096 amendment are descoped, file
tracking issues with re-evaluation criteria + the Phase-4 milestone before marking ready
(`wg-when-deferring-a-capability-create-a`).
