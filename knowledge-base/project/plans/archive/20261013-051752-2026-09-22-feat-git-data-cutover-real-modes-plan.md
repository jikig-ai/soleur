---
title: "git-data cutover: rebuild the real modes (cutover, rollback, wipe) on real mechanisms"
date: 2026-09-22
slug: feat-git-data-cutover-real-modes
branch: feat-one-shot-8211-git-data-cutover-real-modes
issue: 8211
closes: []
type: feat
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# git-data cutover: rebuild the real modes on real mechanisms

## Enhancement Summary

**Deepened on:** 2026-09-22
**Research and review agents used:** repo-research-analyst, learnings-researcher, cto (three
rulings), clo, cpo, spec-flow-analyzer (twice), a scoped advisor consult, dhh-rails-reviewer,
kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, security-sentinel,
data-integrity-guardian, deployment-verification-agent, observability-coverage-reviewer,
test-design-reviewer, user-impact-reviewer.

### Key improvements

1. **The mechanism changed**, from a runtime rsync plus repoint to a LUKS-only render delivered by
   the next ordinary replace (ADR-239). This removes two defects the literal design carried: the
   repoint did not survive a replace, and a fixed mapper assertion on a plaintext host would have
   refused every Art. 17 erasure.
2. **The erasure path fails closed.** A positive `store-verified` marker, bound to the mapper's
   filesystem UUID, is written only after every boot check passes. The probe runs the real erasure
   path as `git`, with `env -i` outside `runuser` (security P0).
3. **Every new FATAL pages.** Each goes out as `stage=bootstrap`, which is already in
   `git_data_boot_fatal`, so `issue-alerts.tf` needs no edit.
4. **The boot checks can be tested without root**, using an extracted-block seam and stubs, and
   the Guard rows that would have been vacuous now go RED.
5. **Deployment gap found.** When the replace's boot poll fails, the pin publishes but the pin
   redeploy is skipped with no email. Recovery is an unconditional redeploy dispatch.

### New considerations discovered

- `noload` can hide journal-only directory entries. A volume that `dumpe2fs -h` reports as needing
  recovery is treated as `plaintext_unverified`.
- Doppler can inject the test seams into `git-data-gc.service`. The unit strips them with `env -u`.
- `AcceptEnv` accumulates across sshd drop-ins. The boot `sshd -T` stage now enforces the set.
- A boot-FATAL window shows users the erasure-pending notice. The runbook sweeps the refused ids
  after the forward fix.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).


#8211 asks for the git-data LUKS cutover's real modes (cutover, rollback, wipe) rebuilt on
mechanisms that exist, plus the rest of #8101 (the fence must not dangle after the store changes;
the three forced-command wrappers must assert the mapper device before `GIT_DATA_STORE_ENABLED`
flips) and a same-version web redeploy in place of `git-data-pin-redeploy.yml`'s forced patch
release (DC-2 of #8549).

Research changed the mechanism. The store has never been enabled and holds zero repositories, and
a runtime repoint of `/mnt/git-data` does not survive a `git_data_host_replace`: cloud-init mounts
the plaintext volume there again, and since ADR-237 every replace rotates the host key, so replaces
are routine. The CTO ruled for an **immutable, cloud-init-rendered serving store**, and then, on
the advisor consult, for its simplest form (**"B-lite"**): the git-data render **always serves the
LUKS mapper at `/mnt/git-data`**. There is no plaintext/luks toggle. The serving-device change
happens at the next ordinary `git_data_host_replace` (ADR-237's pin-publishing step 3), while the
flag is off and the store is empty. This reverses ADR-068 D10 (new ADR-239). #8101's wrapper
assertion, a fixed `/dev/mapper/git-data`, becomes correct as written, because the new layout and
the new wrappers arrive in the same render.

**Split recommendation (explicit): split #8211 into two PRs. This branch is PR1.**

- **PR1: this branch, the hash-bound payload PR** of the runbook's two-PR sequence. It carries:
  - the LUKS-serving layout;
  - the plaintext volume checked read-only once per instance and never mounted after that;
  - the mapper assertion plus a positive `store-verified` marker in every store-acting script;
  - boot-time proofs on real hardware: plaintext emptiness, fence on the mapper, and an erasure
    self-probe;
  - ADR-239 and its amendments, and the C4 and PA-36 addenda;
  - the operator's two fold-ins: archive the host-key-pinning spec directory, and a compound pass
    on that PR's ship-phase errors.

  **Why now:** `main` has no rung-2 evidence, because PR #8511 deleted it and its re-rehearsal has
  not run. Landing PR1 first lets one paid rehearsal cover both payload changes.
- **PR2: follow-on, not hash-bound.** It carries:
  - the real modes of `git-data-cutover.sh`/`.yml`: proof, flip, and rollback (flag-off only;
    plaintext paths refused);
  - the same-version redeploy, rebuilt inside `.github/actions/dispatch-web-redeploy/`. It replaces
    the forced patch release and accepts DC-2;
  - the app's `git_data_store=` startup line, for the in-container proof;
  - the ADR-220 D6 fresh replace, which also replaces the LUKS key and volume;
  - the ADR-237 D6 amendment.

  PR2 closes #8101 and #8549. It is specified below under "Phase B" and gets its own plan pass when
  it is picked up.
- **Later, by operator dispatch or small PRs:**
  - the ADR-237 step-3 replace, which becomes the serving-device change, gated as described below;
  - the flip, after the D6 replace;
  - the soak;
  - the wipe PR (DL-2, #6897).

The real modes keep refusing (`verdict=real_cutover_unreconciled`) throughout PR1. #8209 is a
precondition of the real **run** (the flag flip), not of landing this code.

**Does merging PR1 alone mutate production? No.** No workflow applies git-data `user_data` on
merge. The bytes reach the host only at a dispatched `git_data_host_replace`, which refuses until
the rung-2 evidence for PR1's template lands in an evidence-only PR.

## Research Insights

### Premise Validation (Phase 0.6)

- **#8211** OPEN; **#8101** OPEN; **#8549** OPEN (DC-2 names #8211's same-version redeploy as the
  replacement for `git-data-pin-redeploy.yml`); **#8209** OPEN (parallel session, PR #8563, no files
  yet); **#8210** CLOSED (fix PR #8312 reopens the mapper at boot, target read from `/etc/fstab`,
  accepting `/mnt/git-data` or `/mnt/git-data-luks`); **#8451** CLOSED but owned by another
  session (Sentry `issue-alerts.tf`) — not touched; **#5914** OPEN; **#8094** CLOSED (a refused
  erasure is no longer swallowed, `account-delete.ts:219`); **#6897** OPEN (plaintext-volume
  exception, expires 2026-10-22); **PR #8454** MERGED (fence probe); **PR #8511** MERGED
  2026-09-22T12:07Z (`0aa119838b`).
- **Stale premise 1 — "rsync hooks/ so the fence doesn't dangle after repoint".** The store has
  never been enabled, so the plaintext store holds zero repositories (runbook "What users see";
  the dry run's `store_not_empty` probe). The first cutover has nothing to copy, and the hooks are
  installed by the bootstrap onto whatever is mounted at `/mnt/git-data`
  (`cloud-init-git-data.yml` ~L656, `git-data-bootstrap.sh`).
- **Stale premise 2 — a runtime repoint is durable.** A fresh git-data host always mounts the
  plaintext volume at `/mnt/git-data` (`cloud-init-git-data.yml` L937-942) and the mapper at
  `/mnt/git-data-luks` (L1156-1168). A runtime repoint plus `/etc/fstab` edit survives a reboot
  but not a `git_data_host_replace`, and since ADR-237 every replace rotates the host key, so
  replaces are routine. It is also an in-place config change to a running prod host
  (`hr-prod-host-config-change-immutable-redeploy`).
- **Stale premise 3 — "an unconditional `/dev/mapper/git-data` assertion in all three wrappers".**
  `removeGitDataRepo` (`apps/web-platform/server/git-data-replication.ts:457`) is deliberately not
  flag-gated, so every Delete Account in prd reaches `git-data-remove.sh`. A hardcoded mapper
  assertion delivered by ANY replace before the cutover (ADR-237 step 3, or ADR-220 D6's fresh
  replace, which precedes the cutover) would refuse every erasure — one Art. 17 failure event per
  deletion — until the cutover, possibly weeks while #8209 is open.
- **ADR corpus (mechanism check).** ADR-068 D10 rejected "born-on-LUKS" because "revisiting it
  would rewrite a cutover path that is already built and tested". That rationale is false today:
  #8189 deleted the path, which had never run (ADR-220 Context). Reversing D10 is legitimate and is
  an ADR deliverable of this plan (ADR-239).
- **Rung-2 state.** `origin/main` carries NO `git-data-rung2-boot-evidence.env` (PR #8511, a
  payload PR, deleted it; its re-rehearsal has not run). Birth and replace already refuse. A
  hash-bound PR that lands before that rehearsal shares it; one that lands after costs a second
  paid rehearsal and a second interlock window.

### Property List (Phase 0.6b)

- P1. The device serving `/mnt/git-data` is the LUKS mapper before any repository is written.
- P2. The serving device survives every reboot AND every `git_data_host_replace` (a replace
  must never silently revert to the plaintext volume).
- P3. The three forced-command wrappers refuse to act on a store not backed by the device the
  host is configured to serve, and erasures keep succeeding on a correctly configured host in
  both modes (no pre-cutover Art. 17 regression).
- P4. A push after the serving-device change runs the fenced `pre-receive` from the served store
  (#8101's goal).
- P5. `GIT_DATA_STORE_ENABLED` is proven from inside every running web container (`var.web_hosts`:
  web-1 and web-2), not from Doppler.
- P6. Rollback turns the flag off (proven in-container) before any serving-device change back.
- P7. The old plaintext volume is decommissioned only after a healthy soak, with emptiness and
  mount identity re-asserted at the destructive step.
- P8. After a git-data replace rotates the host-key pin, the app loads the new pin within a
  mechanically bounded time without a forced patch release (DC-2).
- P9. The real modes refuse until every precondition holds (#8209, #5914, pin present, fresh LUKS
  key + replace, replication-pin-fault paging).
- P10. A serving layout the rung-2 rehearsal never booted cannot reach production.

### Cut List (Phase 0.6b)

- Freeze sentinel writer, bulk+delta rsync, `assert_distinct_endpoints`, hooks rsync, post-copy
  sha256 listing compare, `core.hooksPath` scan of copied repos → buy P1/P4 **for a populated
  store only**; for the first cutover (0 repositories) P1/P4 are bought by the bootstrap
  mounting the mapper and installing the fence on it. Deferred to a tracked issue (populated-store
  copy mode, trigger: before the first rotation of a populated store). The real script refuses a
  populated-store cutover.
- In-place repoint (mount over SSH + fstab edit) buys P1 but fails P2 and violates
  `hr-prod-host-config-change-immutable-redeploy`. It is replaced by the LUKS-serving render.
- A plaintext/luks mode selector: a selector file or variable, a luks-mode interlock, a PR2
  transition guard, and a tier-2 rollback to plaintext. Their only property is a rollback to a store
  that has never held data. The advisor proposed the cut; the CTO ruled on it. Recorded in ADR-239
  as a lost capability.
- A new rung-2 evidence key or gate code. P10 is already bought by the template hash, because the
  layout change is a template change. `git_data_rung2_bound_files` binds the template and every
  `file()` payload.
- A new redeploy action. `.github/actions/dispatch-web-redeploy/` already exists. Its `track.sh` is
  rebuilt (PR2) on the same-version mechanism in `apply-deploy-pipeline-fix.yml` (step "Redeploy to
  load applied profile", #5875 item 4).
- An expected-device file. With one serving layout, the expected device is the constant
  `/dev/mapper/git-data`, behind the #8101 test-only seam `GIT_DATA_STORE_DEVICE`. sshd's
  `AcceptEnv LANG LC_*` cannot reach that seam.

### Relevant files

- `apps/web-platform/infra/git-data-cutover.sh` (492 lines; `refuse_real_modes` L122,
  `refuse_if_fence_not_intact` L416 exits 5 via `_store_refuse` L325; `WEB_HOSTS` default
  `10.0.1.10` L75; no `assert_distinct_endpoints`).
- `.github/workflows/git-data-cutover.yml` (workflow-level `git-data-state`; env
  `web-platform-infra-apply`; not in `web-1-swap`).
- Wrappers `apps/web-platform/infra/git-data-{provision,remove,transport-wrapper}.sh` (mount seam
  `GIT_DATA_MOUNT_ROOT`, `mountpoint -q`, `stat -c %m`; freeze sentinel
  `${MOUNT_ROOT}/.cutover-freeze`) and suites `git-data-{provision,remove,transport-wrapper}.test.sh`.
- `apps/web-platform/infra/cloud-init-git-data.yml`, `git-data-bootstrap.sh` (raw-glob fallback
  mount L77; LUKS_ROOT section L84-126; `boot_complete` emit L459), `git-data-luks-reopen.sh`
  (target phase L143-156).
- Render module `apps/web-platform/infra/modules/git-data-userdata/main.tf` (payload map L83-108,
  called by `git-data.tf:380` and `rung2-rehearsal/rehearsal.tf:162`); budget mirror
  `git-data-userdata-budget.sh`; parity `git-data-render-strip-parity.test.sh`.
- Rung-2 gate `tests/scripts/lib/git-data-birth-readiness-gate.sh` (`git_data_rung2_bound_files`,
  payload floor "ship binds 9", `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` L666).
- Same-version redeploy precedent: `.github/workflows/apply-deploy-pipeline-fix.yml` ~L1841-2100
  (running version from `/health`, `POST /hooks/deploy`, poll `/hooks/deploy-status` for
  `component=web-platform`, `tag=target`, `start_ts > prior`; `lock_contention` and
  `adr027_prod_already_running` non-terminal; no `peers`).
- Pin redeploy: `.github/workflows/git-data-pin-redeploy.yml`,
  `.github/actions/dispatch-web-redeploy/{track.sh,source-run-gate.sh}`,
  `tests/scripts/test-dispatch-web-redeploy.sh`; referenced from `.github/CODEOWNERS`,
  `apply-web-platform-infra.yml`, `git-data.tf`, ADR-220, ADR-237, `model.c4`,
  `git-data-luks-cutover-5274.md`, `plugins/soleur/test/terraform-target-parity.test.ts`,
  `scripts/encryption-posture-ledger.json`, `scripts/test-all.sh`.
- App: `apps/web-platform/server/git-data-replication.ts` (pin startup line L235-249,
  `git_data_replication_push` op L747), `server/index.ts:78`, `server/workspace-resolver.ts:57`.
- Release deploy fan-out: `web-platform-release.yml` deploy job (`web-1-swap`, peers
  `10.0.1.10,10.0.1.11`); `var.web_hosts` = web-1 + web-2 (`variables.tf` L92-108).

### Institutional learnings applied

- `2026-09-21-a-selector-that-settles-on-the-first-qualifier-…` — a `workflow_run` run's
  `head_sha` is `main`'s tip when it fired; `deploy-arm.sh` reads `resolve-target`'s checkout. Any
  redeploy poller must key on its own frame (`start_ts > prior`), never on run `head_sha`.
  (Measured today: release runs 35726731583 and 35727079685 are stamped `0aa119838b` but were
  fired by CI for `ec68b3ec42` and `974ae02446`.)
- `2026-07-05-cross-pipeline-serialization-via-shared-job-level-concurrency-group` — every job that
  swaps web-1 joins `web-1-swap` at job level.
- `2026-07-17-pure-fail-closed-on-in-place-rebootstrap-downs-live-service` — a new fail-closed
  wrapper check must be proven on the host state it will actually meet (the first production boot of the new render, proven by the rehearsal and `erasure_probe`).
- `2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured`,
  `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous…`,
  `2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill` — guard
  contracts need precondition-holds-property-fails rows and must be validated against the tree the
  remediation produces.
- `2026-06-18-destructive-datastore-migration-backup-inventory-after-diff` — the wipe needs an
  inventory before and a diff after, even for an "empty" volume.
- `2026-05-27-bash-set-e-leaks-from-functions-use-or-true` — never toggle `set -e` in a guard
  function.

### Domain consults already run

- **CTO (architecture fork):** ruled **option B** (immutable, cloud-init-rendered serving store)
  over A (runtime rsync + repoint) and C (hybrid), then, on the advisor consult, **B-lite**
  (LUKS-only render, no mode toggle) with five hard conditions (see Proposed Solution); recommended
  the split below;
  in-container flag proof via the app's warn-level startup line read from Better Stack (SSH
  `docker inspect` and `/health` rejected); rebuild `dispatch-web-redeploy/` rather than add an
  action; ADR-239 plus amendments to ADR-068 D10, ADR-220 D6, ADR-237 D6.
- **CLO:** provider volume deletion suffices for the plaintext volume only because it never held
  a repository; record repository count at the flip, absence of Hetzner snapshots/backups of
  `hcloud_volume.git_data`, the destroying apply, and the soak. PR1 adds a PA-36 (g)(2) addendum
  worded "fires on the merge of PR #N"; PA-36 (g)(1), PA-1 (g)(13) and PA-2 (g)(17) stay DRAFTED
  until `findmnt` reads the mapper.
  No `docs/legal/**` edit.
- **CPO:** sign-off with conditions (see Domain Review).

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue / brief | Reality on `main` | Plan response |
|---|---|---|
| The cutover must rsync `hooks/` so the fence does not dangle after the repoint (#8101 item 1). | The store holds 0 repositories. The bootstrap installs `hooks/pre-receive` and `core.hooksPath` onto whatever is mounted at `/mnt/git-data`. | No copy. In the new render the mapper IS `/mnt/git-data` when the bootstrap runs, so the fence is planted on the mapper. `boot_complete` proves it (`fence_on_mapper`). Copy mode is deferred to #8571. |
| Assert `/dev/mapper/git-data` unconditionally in the three wrappers (#8101 item 2). | Erasure is not flag-gated. A fixed mapper assertion on a host that still serves plaintext would refuse every Delete Account. | Correct under B-lite: layout and wrappers ship in one render, so no host ever runs the new wrappers over the plaintext layout. Kept as #8101 wrote it, with the `GIT_DATA_STORE_DEVICE` test seam. |
| Rebuild the freeze, repoint and reload on real mechanisms (#8211). | Freeze has no writer; repoint is not replace-durable; the reload units never existed. | The durable mechanism is the replace. The reload is a same-version redeploy (the #5875 item-4 precedent; PR2). Freeze and rsync are needed only for a future populated-store rotation. |
| Replace `git-data-pin-redeploy.yml` in this PR (brief). | Not hash-bound; unrelated to the rung-2 window. | Moved to PR2 (split recommendation; recorded as a decision challenge). |
| Rollback remounts plaintext after the flag goes off (#8101 AC). | There is no plaintext serving layout after PR1. | Rollback is flag-off only (PR2); data stays on LUKS. PR2's rollback refuses a plaintext path explicitly. ADR-239 records the lost capability. |
| #8211 must page on `git_data_replication_push` pin faults before the flip. | That is a Sentry rule in `apps/web-platform/infra/sentry/issue-alerts.tf`, which another session owns. | Tracked in #8572 as a flip precondition. PR2's real mode refuses until it exists. |
| A windowed `prd` flag-write credential. | None exists (`DOPPLER_TOKEN_WRITE` is `prd_terraform`-scoped). #8209 is redesigning the credential chain in parallel. | Not built here. PR2 consumes it through an interface agreed with #8209 and refuses `verdict=flag_write_credential_absent` until then. Tracked in #8573. |

## Problem Statement

`git-data-cutover.sh` is a read-only proof. #8189 deleted the body that moved data, repointed the
mount and flipped the flag, because it called systemd units that do not exist. Rebuilding it as it
was would bring back two defects that research found:

- a repoint that any routine replace silently undoes;
- a wrapper assertion that, if it reached a host still serving plaintext, would refuse every
  account-deletion erasure.

The first real cutover moves no data, because the store is empty. Most of the old machinery would
therefore ship untested against real data.

## Proposed Solution

### The LUKS-serving render (PR1)

- **`cloud-init-git-data.yml`**
  - L937-942 no longer mount the plaintext volume, and write no fstab line for it. Nothing mounts
    the plaintext volume after boot.
  - The luks_open heredoc mounts the mapper at `/mnt/git-data` and writes its fstab line with that
    target (L1162/L1168).
  - Stale `FRESH_ROOT`/rsync-source comments are corrected.
- **`git-data-bootstrap.sh`**
  - §1 (the raw-glob plaintext mount and its FATAL, L65-81) and §1b merge into one section. `LUKS_ROOT`
    becomes `GIT_DATA_ROOT` (`/mnt/git-data`). The reopen self-heal (L95-123) runs first, then the
    FATAL unless `findmnt -n -o SOURCE --mountpoint /mnt/git-data` equals `/dev/mapper/git-data`.
    Nothing falls back to plaintext (CTO condition 3; Kieran P2-7). The duplicated post-bootstrap
    checks (L309-316) collapse into that one assertion.
  - The completion line and telemetry text stop saying "plaintext volume mounted".
- **`git-data-luks-reopen.sh`**: narrow the accepted fstab target (L152-156) to `/mnt/git-data`
  only. It ships in the same render and the same rehearsal (architecture P2-1).
- **`git-data.tf`**: set `automount = false` on `hcloud_volume_attachment.git_data` (L547), matching
  `rung2-rehearsal/rehearsal.tf:240,246`. The provider default is false, so the plan must show no
  change for that address. An AC verifies this with a local plan (see Acceptance Criteria).

### Store verification at boot (PR1)

The bootstrap runs these steps in order. Each step either passes or ends in a named FATAL stage.
Nothing later can run until the steps before it pass (spec-flow P1-5).

1. **Serving device.** `/mnt/git-data` is the mapper (above).
2. **Plaintext volume check.** This runs only when `git_data_volume_id` is non-empty.
   - Mount the volume read-only and temporarily (`mount -o ro,noload`) at a private
     `mktemp -d` path.
   - Require the mount SOURCE to resolve (`realpath`) to the by-id device. A mount that failed
     leaves an empty directory that would count as empty, so the source must be checked, not just
     the count (spec-flow P0-1, architecture P0).
   - Count every entry under `repositories/`, excluding `.*.init.lock` and `lost+found`, not only
     `*.git` (architecture P2-6).
   - Unmount, and remove the directory.
   - A failed mount or a wrong source is FATAL `plaintext_unverified`. A non-zero count is FATAL
     `plaintext_residue count=<n>` (Kieran P2-8).
   - The data is safe in both cases: the volume is retained and was read-only.
3. **Fence on the mapper.** Install the hooks, then assert
   `findmnt -n -o SOURCE -T /mnt/git-data/hooks/pre-receive` equals the mapper.
4. **Positive store marker.** Write root-owned `/etc/git-data/store-verified` (0644) only now. The
   marker is written only after steps 1-3 pass: the scripts refuse until it exists, rather than
   refusing only once a residue marker appears (DHH P1, architecture P1).
   - Why this matters: the wrappers and `authorized_keys` land in `write_files`, before `runcmd`,
     so a Delete Account arriving mid-bootstrap is refused. It is never reported `erased`.
   - The marker lives in `/etc`, so it survives a reboot. The bootstrap does not re-run on reboot,
     and nothing mounts the plaintext volume after boot, so the verification stays true.
5. **Erasure probe.** Run
   `env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=boot-probe-0 runuser -u git -- /usr/local/bin/git-data-remove.sh`.
   - It must exit 0, and its captured stderr must contain `not present (no-op)`.
   - `env -i` comes BEFORE `runuser`. `runuser -u` without `-l` keeps its caller's environment, so
     `runuser … env -i` would briefly run a `git`-uid process that still holds `GIT_DATA_LUKS_KEY`
     in `/proc/<pid>/environ` (security P0; Kieran P1-4).
   - `boot-probe-0` passes the remove script's id validation. Its 0-byte lock dotfile is invisible
     to gc (`*.git` only) and to the served-repo count. Both are test rows.
6. **Emit `boot_complete`** with `yes`/`no` values only. The readers grep `"<field>":"yes"`
   (capture L1114-1135, `git-data-boot-signal-poll.sh:228`), so a third value would pass
   unchecked (Kieran P1-2, architecture P1).
   - New terminal booleans: `fence_on_mapper` and `erasure_probe`.
   - `plaintext_empty` reads `yes` when the volume is empty or absent. It is reached only on pass.
   - Informational fields: `plaintext_volume=present|absent` and `served_repos=<n>`.
   - A non-zero `served_repos` is FATAL `luks_residue count=<n>`, not informational. It is counted in
     step 2, before the probe writes its lock dotfile, with the same exclusions as the plaintext
     count. Unknown content on an adopted volume blocks the host rather than being served
     (data-integrity P1).

All `boot_complete` readers are updated in the same edit. Kieran P1-3 listed them:

- `scripts/followthroughs/git-data-rung2-evidence-capture.sh`, the rung-2 evidence;
- `scripts/lib/git-data-boot-signal-poll.sh` (`GIT_DATA_BOOT_TERMINAL`, L228). This is the gate on
  the production replace job;
- `scripts/followthroughs/git-data-birth-emitter-6982.sh`;
- the roster guard in `apps/web-platform/infra/git-data-emit.test.sh`.

The summary text at `apply-web-platform-infra.yml:4338` will go stale, because the plan does not
edit that file (#8209's surface). That is recorded as a known follow-up in the PR body.

**Reboot arm.** The evidence capture accepts the reboot arm on `luks_reopen_ok action=reopened`
alone. It must also read the `target` field, which the reopen already emits
(`git-data-luks-reopen.sh:190`), and FAIL unless `target=/mnt/git-data`. This is CTO condition 2 and
Kieran P0-1: without it, the rehearsal never proves the re-attach. The capture's `HOST_SQL`
(L596-605) gains the column, and `test-git-data-rung2-evidence-capture.sh` gains the rows.

### The store assertion (PR1; #8101 item 2)

- `git-data-provision.sh`, `git-data-remove.sh`, `git-data-transport-wrapper.sh` and
  `git-data-gc.sh` each refuse, with a named message and a non-zero exit, unless:
  - `findmnt -n -o SOURCE --mountpoint "$MOUNT_ROOT"` equals
    `STORE_DEVICE="${GIT_DATA_STORE_DEVICE:-/dev/mapper/git-data}"`, compared by equality;
  - `findmnt` is on PATH (fail closed);
  - the marker `${GIT_DATA_STORE_VERIFIED:-/etc/git-data/store-verified}` exists.
- The check runs after `mountpoint -q` and before the freeze-sentinel check.
- **Test seams.** `GIT_DATA_STORE_DEVICE` and `GIT_DATA_STORE_VERIFIED` are test-only, like the
  existing `GIT_DATA_MOUNT_ROOT`.
  - The suites run their helpers under `env -i` (for example `git-data-remove.test.sh:41`). Thread
    the seams through each helper, and derive the value with `--mountpoint "$mnt"`, not `-T`.
  - The curated-PATH rows (T6, T8, T10) gain a twin where `findmnt` is missing (Kieran P2-10).
- **sshd.** One census row asserts that the rendered `sshd_config` never widens `AcceptEnv`, never
  sets `PermitUserEnvironment yes`, and that no `authorized_keys` line carries `environment=`. That
  covers CTO condition 4 for every seam, including the existing `GIT_DATA_MOUNT_ROOT`.
- **Census scope** (Kieran P1-5). The payloads bound by `file()` in `main.tf` that act on the store,
  with these exemptions by name:
  - `git-data-bootstrap.sh` creates the store and cannot require its own marker;
  - `git-data-pre-receive-placeholder.sh` is a placeholder copied into `hooks/` and runs only under
    the transport wrapper, which asserts first.

  The expected set is exactly the four basenames above, and a floor pairs with that set identity.
- Stale "git-data-cutover.sh plants …" comments are corrected.

### Pre-replace evidence for the serving change (CTO condition 1, adjusted)

The on-host check in step 2 above is the mechanical gate. It reads the real volume, fails closed, and
runs before any erasure can be answered. That meets the CTO's condition more strongly than a
proxy read in the replace job. It also keeps a `prd` token out of `apply-web-platform-infra.yml`,
which #8209 is redesigning. The CTO accepted this deviation on devex review, and it is recorded in
ADR-239.

The runbook adds one recorded step before the ADR-237 step-3 replace. Both reads are linked in the
replace run summary:

- **The flag.** Dispatch `git-data-cutover.yml` from `main`. Before step 3 it refuses at the
  precheck with `verdict=git_data_host_key_unavailable reason=absent`. The precheck refuses
  `flag_already_true` before it reads the pin (`git-data-flag-precheck.sh`, the flag read precedes
  the pin read), so that exact line proves the flag is not `true`.
- **The flag has never been true, for the CLO record.** Page `doppler configs logs -p soleur -c prd`
  until the oldest entry predates the host's birth (2026-09-14). Open with `doppler configs logs get`
  any entry that names `GIT_DATA_STORE_ENABLED`, and record the oldest date the read reached
  (spec-flow P2-7).

The `gc_report` read is dropped. Step 2 measures the same fact directly (simplicity and DHH).

### Recovery paths (PR1 runbook; spec-flow P0-2 and P1-4, CTO devex)

- **Boot FATAL after the step-3 replace**, from `plaintext_unverified`, `plaintext_residue`, §1b, the
  fence check or the probe:
  - The store marker is never written, so every Delete Account is refused. The refusal is logged,
    and the account deletion still completes.
  - The store is empty, so nothing is left behind. The refusals are still Art. 17 events: record
    their count from Sentry `op:git-data-bare-repo-erasure`.
  - The forward fix is a PR, then a rehearsal, then an evidence PR, then a replace. This takes hours
    to days, and the runbook names the operator as the decision-maker.
  - Rolling back to a tag without PR1 is not possible. Such a tag must postdate #8511 (runbook
    "The rung-2 emergency-replace gap"), and no evidence exists for #8511's template alone.
  - The runbook states whether the pin publishes and whether the pin redeploy fires when the boot
    poll reds the job. This is verified in `/work` against `apply-web-platform-infra.yml`'s job
    order, which is read and not edited.
- **`plaintext_residue`:** the data stays read-only on the retained volume. Escalate to the CLO,
  bump #8571 (copy mode), and block the wipe. No SSH.
- **`erasure_probe=no` in production:** forward fix plus replace, with the same Art. 17 count as
  above.
- **The dry run after step 3** reads `already_cut_over` (exit 5). That is expected until PR2
  generalizes `proof`, and the verdict map says so.

### Phase B — PR2 (pointer; planned in its own pass)

PR2 builds the parts of #8211, #8101 and #8549 that PR1 does not:

- the real modes: `proof`, `flip`, and `rollback`. Rollback is flag-off only and refuses any
  plaintext path;
- the same-version redeploy in `dispatch-web-redeploy/`, sending `peers` and accepting `ok` only;
- the in-container `git_data_store=` startup line on every web host;
- the ADR-220 D6 fresh replace, which rotates the host key, the LUKS key and the LUKS volume, gated
  on a recent `proof`. It re-asserts `served_repos=0` before the volume is replaced;
- the ADR-237 D6 amendment.

The real modes refuse with these verdicts: `precondition_8209_open`,
`precondition_5914_open`, `pin_absent`, `pin_fault_paging_absent` (#8572),
`flag_write_credential_absent` (#8573), `d6_replace_stale`, and `store_populated`.

### Operator sequence

1. **Hold the #8511 rehearsal until PR1 merges.** This saves one paid rehearsal. At `/work` start,
   comment on #5914, which tracks ADR-237's post-merge sequence, and note it in the runbook
   (architecture P1).
2. Merge PR1. Dispatch the rung-2 rehearsal from `main`, which also serves ADR-237 post-merge step
   2. It must read `boot_complete` with `luks_mounted=yes fence_on_mapper=yes erasure_probe=yes plaintext_empty=yes`,
   and the reboot arm must read `luks_reopen_ok action=reopened target=/mnt/git-data`. Land the
   evidence-only PR.
3. Record the two reads above. Dispatch the ADR-237 step-3 `git-data-host-replace`: serving moves to
   LUKS, the pin publishes, and the pin redeploy runs. Read `boot_complete` from Better Stack.
4. After PR2: `proof`, then the D6 replace, then `proof`, then `flip`, then a soak of at least 7 days.
5. **Wipe PR.**
   - Record the CLO evidence set first: the repository count at the flip, the absence of Hetzner
     snapshots and backups of `hcloud_volume.git_data`, the destroying apply, and the soak window.
   - Emptying `git_data_volume_id` switches to a render branch that no rehearsal has booted. The
     wipe PR therefore requires a rehearsal with an empty volume id, declared under
     `RUNG2_VAR_DIVERGENCE` (Kieran P1-6, architecture P2-4).
   - Order: replace the host with the new render first, which detaches nothing that is mounted,
     then destroy the attachment and the volume (spec-flow P2-9).
   - Close the git-data half of #6897.

## Files to Edit (PR1)

- `apps/web-platform/infra/cloud-init-git-data.yml`: remove the plaintext mount and fstab line; the
  mapper at `/mnt/git-data`; stale comments.
- `apps/web-platform/infra/git-data-bootstrap.sh`: merge §1 and §1b; steps 1-6 above; completion text.
- `apps/web-platform/infra/git-data-luks-reopen.sh`: narrow the target to `/mnt/git-data`.
- `apps/web-platform/infra/git-data-provision.sh`, `git-data-remove.sh`,
  `git-data-transport-wrapper.sh`, `git-data-gc.sh`: the store assertion and marker; stale comments.
- `apps/web-platform/infra/git-data.tf`: `automount = false` on `hcloud_volume_attachment.git_data`.
- `apps/web-platform/infra/git-data-gc.service`: add `env -u` for the four seams in `ExecStart`.
- `apps/web-platform/infra/cloud-init-git-data.yml`, `sshd -T` stage: enforce `acceptenv` and
  `permituserenvironment`; add `no-user-rc` to the `authorized_keys` options.
- `apps/web-platform/test/git-data-replication.test.ts`: a unit row pinning that exit 1 maps to
  `refused`. Test only; no app-code change in PR1.
- The suites: `git-data-provision.test.sh`, `git-data-remove.test.sh`,
  `git-data-transport-wrapper.test.sh`, the gc coverage, `git-data-luks-reopen.test.sh`,
  `git-data-emit.test.sh`, and the bootstrap/runcmd render suites. Enumerate them with
  `git grep -ln 'scsi-0HC_Volume_\|git-data-luks\|GIT_DATA_BOOT_TERMINAL' -- tests/ scripts/ apps/web-platform/infra/ plugins/soleur/test/`.
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` and
  `tests/scripts/test-git-data-rung2-evidence-capture.sh`: the new booleans and the reboot-arm
  `target`.
- `scripts/lib/git-data-boot-signal-poll.sh` (and its suite), plus
  `scripts/followthroughs/git-data-birth-emitter-6982.sh`: the new terminal booleans.
- `apps/web-platform/infra/git-data-userdata-budget.sh`: re-measure against 32,768 B.
- `apps/web-platform/infra/git-data-cutover.sh`: header text only; the real modes still refuse.
- `knowledge-base/engineering/architecture/decisions/ADR-068-…md` (D10) and `ADR-220-…md` (D6,
  marked "pending PR2" for the rotation): dated amendments.
- `knowledge-base/engineering/architecture/diagrams/model.c4`, plus the regenerated
  `model.likec4.json`.
- `knowledge-base/legal/article-30-register.md`: the PA-36 (g)(2) addendum, and Superseded markers
  on PA-36 (g)(1), PA-1 (g)(13) and PA-2 (g)(17) as to mechanism.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` and
  `git-data-rung2-rehearsal.md`.
- `scripts/encryption-posture-ledger.json`: only if its git-data entry names the deleted repoint.

## Files to Create (PR1)

- `apps/web-platform/infra/git-data-store-device-census.test.sh` (Guard 1), registered in
  `scripts/test-all.sh`.
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`
  (ADR-239; ADR-238 is taken on another branch).
- A learning under `knowledge-base/project/learnings/` from the compound pass, or an extension of
  an existing one.
- `knowledge-base/project/specs/feat-one-shot-8211-git-data-cutover-real-modes/decision-challenges.md`
  (already written at plan time).

## Technical Considerations

- **The Hetzner 32,768 B user_data cap.** Run `git-data-userdata-budget.sh`. The rationale strip
  removes comments, so keep the logic terse.
- **`ro,noload`.** Plain `ro` on ext4 can still replay the journal.
  - The rehearsal's plaintext volume is freshly formatted, so it never boots the production case: a
    volume last mounted read-write by a destroyed host, with a dirty journal (spec-flow P1-6).
  - If `noload` then refuses the mount, step 2 fails closed as `plaintext_unverified`.
  - This is a known P10 gap, recorded in ADR-239. The failure is safe and its recovery is written
    down.
- **Reboot.** The bootstrap runs once per instance. A reboot emits `luks_reopen_ok target=…` from
  the reopen unit, not `boot_complete`. The marker and the scripts' device check cover the reboot
  path.
- **Parallel sessions.** Do not edit:
  - `apply-web-platform-infra.yml`;
  - `apply-git-data-root-key.yml`;
  - the Doppler Terraform;
  - the credential steps of `git-data-cutover.yml` (#8209, PR #8563);
  - `apps/web-platform/infra/sentry/**`.

  Re-probe PR #8563's file list before opening PR1 and again before merge.
- **Downtime (`hr-prod-host-config-change-immutable-redeploy`).** PR1 changes no running host. Its
  bytes reach git-data only at the step-3 replace: a store-host outage of a few minutes while the
  flag is off.
  - Web requests see nothing.
  - Delete Account waits up to the 30 s `execFile` timeout per deletion, and is refused until the
    marker is written.
- **`git-data.tf` edit and auto-apply.** `automount` is expected to be a no-op diff. If the local
  plan shows a replace of `hcloud_volume_attachment.git_data`, drop the edit and record the reason.
  Do not ship an attachment replace in PR1.


## Downtime & Cutover

- **What goes offline.** `hcloud_server.git_data` is destroyed and recreated by the ADR-237 step-3
  `git_data_host_replace`. That replace is already required to publish the pin, so PR1 adds no
  extra replace. The git-data host is offline for the replace job's duration, usually a few
  minutes.
- **What that affects.** With `GIT_DATA_STORE_ENABLED` off, no web request reaches git-data:
  provision, replicate and fetch all return early. The only live consumer is the Art. 17 erasure
  behind Settings → Delete Account. Each deletion in the window waits up to the 30 s `execFile`
  timeout, and logs an erasure event. The deletion itself completes, and no repository exists to be
  left behind.
- **Zero-downtime path evaluated and rejected.** ADR-220 "Considered options: zero-downtime key
  delivery" already evaluated blue-green for this host and rejected it:
  - both volumes attach to one server;
  - `10.0.1.20` is fixed in every consumer;
  - a second host needs a new address, volume moves and a consumer repoint.

  A few-minute outage of a surface no user request depends on while the flag is off is the smaller
  risk. An in-place change is barred by `hr-prod-host-config-change-immutable-redeploy`.
- **The maintenance window is bounded.** It lasts from the replace dispatch to the fresh host's
  `boot_complete`, read from Better Stack. The replace job's boot-signal poll already bounds it and
  reds the job if the host does not come up. The operator authorizes the step-3 replace explicitly,
  as ADR-237's post-merge sequence requires.
- **What each stage verifies, and how to roll back.**
  - **Before:** the recorded pre-replace reads.
  - **After:** `boot_complete` with every terminal boolean `yes`.
  - **On failure:** the recovery paths under Proposed Solution. The store marker is not written,
    so erasures refuse but never mis-report; the forward fix is PR, then rehearsal, then evidence,
    then replace. There is no revert to a pre-PR1 tag.
- **The flag flip (PR2) causes no host downtime.** Its same-version redeploy of the web container is
  a drained, canary-validated swap through the existing `/hooks/deploy` path, in the `web-1-swap`
  mutex.

## Alternative Approaches Considered

| Option | Why not |
|---|---|
| A: rebuild the runtime rsync and repoint | Not replace-durable, and an in-place host config change. It copies nothing on the first run. The CTO ruled against it. |
| B: a plaintext/luks mode selector | Its only property is a rollback to a plaintext store that never held data. It costs a selector, an interlock and a guard. Cut to B-lite. |
| C: hybrid | Machinery with nothing to run on. |
| Keep the plaintext volume mounted read-only for its lifetime | Its only use is a one-time count. A temporary mount during the bootstrap removes a permanent path the scripts could reach (DHH). |
| A residue marker that the scripts refuse on | It fails open during the bootstrap window. The positive `store-verified` marker fails closed (DHH, architecture). |
| Prove emptiness with the existing dry run (`store_not_empty`) instead of on the host | Before step 3 the dry run refuses at the precheck (no pin), so its store probes never run (simplicity suggestion; verified against `git-data-flag-precheck.sh`). |
| A replace-job step that reads the `prd` flag | Needs a `prd` token in `apply-web-platform-infra.yml`, the file #8209 is redesigning. The CTO accepted the on-host check. |
| Ship PR1 and PR2 as one PR | Pushes the hash-bound half past the #8511 rehearsal. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a Settings → Delete Account whose git-data
  erasure is `refused`. The deletion completes, and an Art. 17 failure event is logged for each one.
  This happens because the host booted without the mapper at `/mnt/git-data`, or failed a boot
  check, and so never wrote the store marker. Later, with the flag on, repository replication would
  also fail until a forward fix.
- **If this leaks, the user's data is exposed via:** a boot or replace that serves the plaintext
  volume at `/mnt/git-data`, so a repository lands on an unencrypted disk while the Article 30 record
  says it is encrypted; or an erasure reported `erased` against the LUKS store while the user's
  repository sits on the plaintext volume.
- **Brand-survival threshold:** `single-user incident`. The store will hold every connected user's
  source code, and the erasure path is live today. CPO sign-off is recorded under Domain Review.
  `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "git-data stage:boot_complete event (luks_mounted, fence_on_mapper, erasure_probe, plaintext_empty as yes/no; plaintext_volume, served_repos informational), emitted once per instance by git-data-emit to Sentry (baked DSN) and Better Stack; on reboot, luks_reopen_ok with target=/mnt/git-data from git-data-luks-reopen.service"
  cadence: "per instance (every birth, git_data_host_replace and rung-2 rehearsal); per boot for luks_reopen_ok"
  alert_target: "operator email via the existing git-data boot-stage Sentry rules (issue-alerts.tf, unchanged); the production replace job reds on any terminal boolean not yes (git-data-boot-signal-poll.sh); rung-2 gate HOLD"
  configured_in: "apps/web-platform/infra/git-data-bootstrap.sh (boot_complete emit) and scripts/lib/git-data-boot-signal-poll.sh (GIT_DATA_BOOT_TERMINAL)"

error_reporting:
  destination: "Sentry (git-data baked DSN for host-side stages; web-platform SENTRY_DSN for the app-side erasure outcome)"
  fail_loud: "a store-acting script prints 'remote: git-data <verb>: store at /mnt/git-data is not served by /dev/mapper/git-data' or 'store not verified' and exits non-zero; the app maps it to erasure status refused and reports op:git-data-bare-repo-erasure (existing rule, issue-alerts.tf ~L689)"

failure_modes:
  - mode: "LUKS open or mount fails at boot; /mnt/git-data is not the mapper"
    detection: "bootstrap FATAL stage (git-data-emit fatal); on later boots the reopen unit's luks_reopen fatal"
    alert_route: "git-data boot fatal Sentry rule to operator email"
  - mode: "plaintext volume cannot be verified or holds repositories at the serving change"
    detection: "bootstrap log 'FATAL: plaintext_unverified reason=<word>' or 'FATAL: plaintext_residue count=<n>', emitted as stage=bootstrap fatal; the store marker is never written, so every store-acting script refuses"
    alert_route: "git_data_boot_fatal Sentry rule (stage=bootstrap) to operator email"
  - mode: "the erasure path refuses on a correctly booted host"
    detection: "bootstrap log 'FATAL: erasure_probe=no' (emitted as stage=bootstrap fatal) plus boot_complete erasure_probe=no; the replace job's boot poll reds"
    alert_route: "git_data_boot_fatal Sentry rule (stage=bootstrap, already in its list) to operator email; failed replace job"
  - mode: "the fence landed under the mountpoint instead of on the mapper"
    detection: "bootstrap log 'FATAL: fence_on_mapper=no' (stage=bootstrap fatal) plus boot_complete fence_on_mapper=no"
    alert_route: "git_data_boot_fatal Sentry rule (stage=bootstrap) to operator email; failed replace job; rung-2 HOLD"
  - mode: "the adopted LUKS volume already holds repository content"
    detection: "bootstrap log 'FATAL: luks_residue count=<n>' (stage=bootstrap fatal); no store marker"
    alert_route: "git_data_boot_fatal Sentry rule (stage=bootstrap) to operator email"

logs:
  where: "Better Stack git-data source (boot events posted by git-data-emit); Sentry issues; the rung-2 rehearsal run log and evidence artifact"
  retention: "Better Stack plan retention; Sentry 90 days; Actions logs 90 days"

discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 30d --grep boot_complete"
  expected_output: "erasure_probe"
  credentials_required: "Better Stack ClickHouse read connection (BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD in Doppler soleur/prd_terraform) — the boot_complete event is stored only in Better Stack Logs and Sentry; no unauthenticated endpoint exposes a private-network host's boot state"
```

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_volume.git_data_luks (serves /mnt/git-data from PR1's first production boot)"
    mechanism: "luks"
    evidence: "implied by device_binding: every store-acting script asserts findmnt SOURCE of /mnt/git-data equals /dev/mapper/git-data and requires /etc/git-data/store-verified (Guard 1); boot_complete luks_mounted and fence_on_mapper prove it per instance"
    defends_against: "a seized, RMA'd or snapshot-imaged block volume; a boot or replace that would otherwise serve the plaintext volume"
    does_not_defend: "root on the unlocked host, a leaked GIT_DATA_LUKS_KEY together with volume access, or a leaked git-data root key (ADR-220 D4)"
    disclosed_as: "knowledge-base/legal/article-30-register.md PA-36 (g)(1), PA-1 (g)(13) and PA-2 (g)(17), DRAFTED / NOT-YET-ACTIVE until findmnt reads the mapper in production (not a docs/legal claim)"
    live_verification: "available: boot_complete luks_mounted and fence_on_mapper in Better Stack; PR2 proof mode"
  - store: "hcloud_volume.git_data (plaintext; attached, unmounted after boot, until the wipe)"
    mechanism: "plaintext-exception"
    evidence: "apps/web-platform/infra/git-data.tf hcloud_volume.git_data format ext4; scripts/encryption-posture-ledger.json git-data entry"
    defends_against: "nothing at rest; it has never held a repository (the flag was never set) and the bootstrap verifies that on every instance before any store action is allowed"
    does_not_defend: "a seized or snapshot-imaged volume would be readable if any repository had ever been written to it"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available: boot_complete plaintext_empty and plaintext_volume"
in_transit: []
exception:
  justification: "The plaintext volume is retained, unmounted and empty until the post-soak wipe; it is the existing #6897 exception, not a new one."
  tracking_issue: "#6897"
  reevaluate_when: "the wipe PR empties git_data_volume_id and destroys hcloud_volume.git_data"
  expires_on: "2026-10-22"
```

## Infrastructure (IaC)

### Terraform changes

- The template `cloud-init-git-data.yml` and the payloads `git-data-bootstrap.sh`,
  `git-data-luks-reopen.sh`, `git-data-provision.sh`, `git-data-remove.sh`,
  `git-data-transport-wrapper.sh` and `git-data-gc.sh`.
- `git-data.tf`: `automount = false`, expected to be a no-op diff.
- No new provider, resource, secret, module variable or `TF_VAR_*`.

### Apply path

The apply path is (b), cloud-init plus the existing immutable replace, at the ADR-237 step-3
`git_data_host_replace`. That happens after the rung-2 rehearsal of PR1's template and its
evidence-only PR. Blast radius: the git-data host only, a store-host outage of a few minutes while
the flag is off.

### Distinctness / drift safeguards

- The layout change is a template change. The rung-2 hash voids older evidence, so birth and replace
  hold until PR1's template is rehearsed.
- The plaintext volume and its attachment are retained.
- The wipe's render branch (empty `git_data_volume_id`) needs its own rehearsal (Operator sequence
  step 5).
- `scheduled-terraform-drift` shows the pending `user_data` change until the replace. This is
  expected.

### Vendor-tier reality check

None: there is no new vendor resource.

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-239** via `soleur:architecture`: "git-data serves its store from LUKS at birth". The
  plan first probed ADR-238, which another branch took; the operator assigned ADR-239 on
  2026-09-22, and `soleur:ship` re-verifies it.
  - **Decision:**
    - the render always mounts `/dev/mapper/git-data` at `/mnt/git-data`;
    - the plaintext volume is checked read-only once per instance and never mounted after that;
    - the store-acting scripts assert the mapper and a positive verification marker;
    - the serving change rides the next ordinary replace, with the store empty and the flag off.
  - **Consequences:**
    - tier-2 rollback to plaintext no longer exists (CTO condition 5); rollback after the flip is
      flag-off only;
    - copy mode is deferred (#8571);
    - condition 1 is met on the host plus recorded reads, not in the replace job (the CTO accepted
      this);
    - the recovery path after a failed step-3 replace, and its Art. 17 window;
    - the dirty-journal `noload` gap;
    - the wipe branch needs its own rehearsal.
  - **Alternatives:** the table above.
  - **Status:** `adopting` until a production instance reports
    `luks_mounted=yes fence_on_mapper=yes erasure_probe=yes`.
- **Amend ADR-068 D10**: superseded by ADR-239.
- **Amend ADR-220 D6**: there is no runtime repoint; the serving change is the first replace of the
  new render. The rotation of the LUKS key and volume before the flip is marked "pending PR2".
- ADR-237 D6 is amended in PR2.
- If the ordinal is renumbered, sweep `grep -rn 'ADR-239' knowledge-base/project/{plans,specs}/`.

### C4 views

All three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` were
read.

- **Checked:**
  - external actors: the founder/operator, and end users through Delete Account;
  - external systems: Hetzner, Doppler, Sentry, Better Stack and GitHub Actions;
  - containers: `gitDataStore` and `workspacesVolume`;
  - edges: `github -> gitDataStore`, `claude -> gitDataStore` and
    `gitDataStore -> sentry|betterstack|doppler`.
- **Result:** no new element.
- **Edit:** the AT REST sentence of the `gitDataStore` description.
- **Tests:** `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
  `plugins/soleur/test/c4-count-parity.test.sh`.
- Regenerate `model.likec4.json` per ADR-235.

### Sequencing

ADR-239 is authored in PR1 with status `adopting`. It flips to `accepted` on the production
`boot_complete` above.

## Guard Contract

### Guard 1 — only a verified, mapper-served store is acted on

**Property.** No store-acting script proceeds unless `/mnt/git-data` is served by
`/dev/mapper/git-data` and the bootstrap has written `/etc/git-data/store-verified`.

**Assembly.**

- The first chokepoint is the set of payloads bound by `file()` in
  `modules/git-data-userdata/main.tf`. The census derives that set from `main.tf`.
  - Two payloads are exempt by name: `git-data-bootstrap.sh` (it creates the store) and
    `git-data-pre-receive-placeholder.sh` (it runs under the transport wrapper).
  - The expected set is exactly `git-data-provision.sh`, `git-data-remove.sh`,
    `git-data-transport-wrapper.sh` and `git-data-gc.sh`.
- The second chokepoint is the sshd environment path: the rendered `sshd_config` `AcceptEnv` and
  `PermitUserEnvironment`, and the `authorized_keys` options.

**Mutation matrix.** Each row is a self-test in the census or the script suites. The test mutates a
temporary copy and expects RED, so no row lives in the PR body (DHH P2).

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the device check from `git-data-remove.sh` only | RED |
| 2 | Break the census's `main.tf` extraction so it iterates zero payloads | RED (the floor plus set identity) |
| 3 | Add a fifth store-acting payload without the check, after four compliant ones | RED |
| 4 | Move the check after `rm -rf` in `git-data-remove.sh` (an order row) | RED (the target is intact after a refusal) |
| 5 | Keep the check only in a comment | RED (comment-stripped read) |
| 6 | Use a prefix or glob match instead of equality | RED (`/dev/mapper/git-data-old` fixture) |
| 7 | Add `AcceptEnv GIT_DATA_*` or `PermitUserEnvironment yes` to the rendered `sshd_config` | RED |
| 8 | Drop the marker requirement from one script | RED |
| 9 | `findmnt` missing from PATH, and the script proceeds | RED |

**Harness rows.**

- **Must-PASS:** the suite's real temp root, with the seam set to that root's own `--mountpoint`
  SOURCE and the marker present. The erasure removes the fixture repository.
- **Suite mutation:** a suite edit that sets the seam to a refusing value in every case must make
  the must-PASS row fail.

**Anchor.** A floor pairs with set identity. The payload set is the one the rung-2 hash binds.

### Guard 2 — an instance proves its layout before any store action is allowed

**Property.** Unless the plaintext volume is verified empty or absent, the fence sits on the mapper,
and a real erasure succeeds as `git`, (a) no store marker is written, and (b) the host can never
release a production replace or a rung-2 evidence PASS.

**Assembly.**

- `git-data-bootstrap.sh` steps 1-6 are the single producer of both the marker and `boot_complete`.
- The consumers are `git-data-rung2-evidence-capture.sh`, `git-data-boot-signal-poll.sh`
  (`GIT_DATA_BOOT_TERMINAL`), `git-data-birth-emitter-6982.sh` and the roster guard in
  `git-data-emit.test.sh`.
- The reboot arm's `target` read is in the capture.

**Mutation matrix.** Each row is a self-test.

| # | Mutation | Expected |
|---|---|---|
| 1 | The plaintext mount fails (empty directory) and the count reads 0 | RED (FATAL `plaintext_unverified`, no marker) |
| 2 | The count matches only `*.git`, and the fixture has a partial `repositories/x` directory | RED |
| 3 | `erasure_probe` skips the real wrapper call | RED (a refusing wrapper stub must yield `no`) |
| 4 | A new boolean is emitted but left out of `GIT_DATA_BOOT_TERMINAL` or the capture's required set | RED |
| 5 | The marker is written before step 2 (an order row) | RED (the marker is absent when step 2 FATALs) |
| 6 | The reboot arm accepts `target=/mnt/git-data-luks` | RED |
| 7 | The probe runs without `env -i`, or with `env -i` inside `runuser` instead of before it | RED (a fixture `GIT_DATA_LUKS_KEY` must not be visible to the stub; a static row asserts `env -i` precedes `runuser`) |

**Harness rows.**

- **Must-PASS:** a fixture instance with all checks true yields the marker, the `yes` values and
  PASS evidence.
- **Suite mutation:** an edit that checks only the capture's exit code, not its verdict, must make
  row 4 RED.

**Anchor.** The evidence lands only in an evidence-only commit (#8043 Guard 4).

## Acceptance Criteria

### PR1 (this branch)

- [ ] The rendered user_data mounts `/dev/mapper/git-data` at `/mnt/git-data`, with exactly one
  fstab line for it. It contains no `/mnt/git-data-luks`, no fstab line or persistent mount for the
  plaintext by-id device, and no raw-glob mount. Render tests assert this.
- [ ] `git-data-luks-reopen.sh` accepts only `/mnt/git-data`, and its suite passes with that
  fixture.
- [ ] `git-data-userdata-budget.sh` reads under 32,768 B, and the number is in the PR body.
- [ ] Guard 1 and Guard 2: every matrix row is an automated self-test that reddens, and the
  must-PASS rows pass. The PR body cites the suite run.
- [ ] Every `boot_complete` consumer is updated (the capture, `git-data-boot-signal-poll.sh`,
  `git-data-birth-emitter-6982.sh`, the `git-data-emit.test.sh` roster), and the reboot arm reads
  `target`.
- [ ] `terraform plan` on `apps/web-platform/infra` shows no change for
  `hcloud_volume_attachment.git_data` after the `automount = false` edit. Otherwise the edit is
  dropped.
  - Run it with TF >= 1.10.
  - Export the R2 `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` directly.
  - Run `terraform init -input=false`.
  - Wrap the plan in a single
    `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan`.
- [ ] ADR-239 exists (`adopting`) and records everything listed under Consequences above. ADR-068
  D10 and ADR-220 D6 carry dated amendments.
- [ ] `model.c4` `gitDataStore` is updated, and the c4 syntax, render and count-parity tests pass.
- [ ] PA-36 (g)(2) addendum, worded "fires on the merge of PR #N". PA-36 (g)(1), PA-1 (g)(13) and
  PA-2 (g)(17) get Superseded markers only as to mechanism. No `docs/legal/**` edit.
- [ ] The runbook covers:
  - the hold on the #8511 rehearsal until PR1 merges;
  - the pre-replace reads, with the exact precheck line;
  - that step 3 is the serving change;
  - the verdict-map rows for `plaintext_unverified`, `plaintext_residue`, `erasure_probe=no` and
    the post-step-3 `already_cut_over`;
  - the failed-replace recovery and its Art. 17 window.
- [ ] `git-data-cutover.sh` still refuses real modes, and its header no longer says "#8211 must
  carry hooks in both passes".
- [ ] `knowledge-base/project/specs/feat-one-shot-7226-5914-host-key-pinning/` is archived via
  `soleur:archive-kb`, with history preserved.
- [ ] The compound pass on PR #8511's ship-phase errors produces a learning, or extends one,
  covering:
  - fixes that were not re-checked against earlier CI failures;
  - the shared repo going shallow at 12:48 on 2026-09-22 (link #7924 and PR #8510; record what was
    checked to find the cause);
  - deploy-arm runs stamped with main's tip `head_sha` (link the 2026-09-21 selector learning and
    `deploy-arm.sh`; say whether ship bypassed it, and route the fix to the skill that did).
- [ ] The PR body:
  - opens with "Merging this alone does not change production";
  - carries `Ref #8211`, `Ref #8101` and `Ref #8549`, with no `Closes`;
  - names #8571, #8572 and #8573;
  - records the stale summary text at `apply-web-platform-infra.yml:4338` as a known follow-up;
  - renders the decision challenges.
- [ ] The diff touches no file under `apps/web-platform/infra/sentry/`, no
  `apply-web-platform-infra.yml`, no `apply-git-data-root-key.yml` and no Doppler Terraform. Expected
  pipeline artifacts (`session-state.md`, and `knowledge-base/INDEX.md` if regenerated) are allowed.
- [ ] Merge only when every required check is present and green on the exact head SHA
  (`--match-head-commit`), and only after asking the operator.

### Post-merge (operator)

- [ ] Dispatch `git-data-rung2-rehearsal.yml` from `main` (`REHEARSE-GIT-DATA`, `dry_run=false`).
  - `boot_complete` must read `luks_mounted=yes fence_on_mapper=yes erasure_probe=yes plaintext_empty=yes`.
  - The reboot arm must read `target=/mnt/git-data`.
  - Then land the evidence-only PR. This also discharges ADR-237 post-merge step 2.
- [ ] Before step 3, record the precheck line and the paged Doppler audit read, as the runbook
  specifies.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering

**Status:** reviewed

**Assessment:** The CTO ruled option B, then B-lite (the LUKS-only render), with five conditions.

- **Honored on devex review:** conditions 2 to 5, with the reboot `target` read added after plan
  review.
- **Accepted as a deviation:** condition 1, met on the host with a positive marker plus recorded
  reads.
- **Runbook additions from devex:** a residue recovery row, and quoting the exact precheck line.
- **Unchanged:** the split and the redeploy-action ruling.

### Legal

**Status:** reviewed

**Assessment:** The CLO found:

- Provider deletion of the plaintext volume is adequate only because it never held a repository.
- The wipe records the repository count at the flip, the absence of snapshots and backups, the
  destroying apply and the soak.
- PR1 adds a PA-36 (g)(2) addendum. (g)(1) stays DRAFTED until `findmnt` reads the mapper in
  production. There is no `docs/legal/**` edit.
- The Art. 17 path changes, so ship's CLO attestation applies.
- The flag flip is hard-blocked on #8209, #5914, the pin and the fresh key rotation.

### Product/UX Gate

**Tier:** none (no UI surface; CPO sign-off is recorded for the single-user-incident threshold)
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO: **sign-off with conditions.**

- **PR1:**
  1. A real boot must prove that an erasure succeeds. The rehearsal's `erasure_probe=yes` meets
     this.
  2. A refused erasure is never swallowed. #8094 already meets this (`account-delete.ts:219`).
  3. There is no "erased" copy when the erasure is refused. #8094 meets this too.
- **PR2:**
  - the per-host in-container proof fails the deploy on a mismatch;
  - the rollback rehearsal runs a successful erasure;
  - every flip blocker is kept.

## Plan Review Revisions (2026-09-22)

The panel was DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, and the
CTO on the devex lens. Changes applied, all classed Mechanical:

- The residue marker was inverted into a positive `store-verified` marker, written only after the
  boot checks. The old marker failed open during the bootstrap window (DHH P1, architecture P1).
- The permanent read-only plaintext mount was replaced by a temporary mount during the bootstrap,
  with a source-identity check, so a failed mount cannot read as empty (DHH P1, spec-flow P0-1,
  architecture P0). The count now covers every entry, not only `*.git`.
- `boot_complete` values are binary `yes`/`no`. The production replace gate
  (`git-data-boot-signal-poll.sh`) and `git-data-birth-emitter-6982.sh` were added as consumers
  (Kieran P1-2 and P1-3).
- The reboot arm must read `target=/mnt/git-data`. This is what makes CTO condition 2 real (Kieran
  P0-1).
- The erasure probe runs under `env -i`, which keeps `GIT_DATA_LUKS_KEY` out of the `git` process
  (Kieran P1-4).
- The census exemptions were corrected: the bootstrap, and the pre-receive *placeholder* (Kieran
  P1-5).
- The wipe branch requires its own rehearsal (Kieran P1-6, architecture P2-4).
- §1 and §1b merged. The reopen target was narrowed. `automount = false` is set explicitly, with a
  no-op-plan AC.
- The `gc_report` read was dropped. The Doppler audit read is paged (spec-flow P2-7).
- Recovery paths were added for a failed step-3 replace, residue, and a refused probe (spec-flow
  P0-2 and P1-4, CTO devex).
- The Observability claim now matches reality: `boot_complete` fires per instance, and a reboot is
  covered by `luks_reopen_ok target=` (spec-flow P1-3).
- The mutation rows are automated self-tests, not tables in the PR body (DHH P2).
- Phase B was cut to a pointer (DHH P2).
- The runbook adds a hold on the #8511 rehearsal until PR1 merges (architecture P1).

**Rejected, with evidence:** simplicity's suggestion to prove emptiness with the existing dry run.
Before step 3 the dry run refuses at the precheck because no pin exists, so `store_not_empty` never
runs (`git-data-flag-precheck.sh` reads the pin before the store probes are reached).

**Kept against a reviewer (User-Challenge, recorded as DC-3):** DHH asked to move the spec archive
and the #8511 compound pass into a separate PR. The operator asked for both to be folded into this
one.

## Deepen-Plan Revisions (2026-09-22)

Each item below is binding on `/work`. It extends Proposed Solution, Guard Contract and Test
Scenarios.

### Security

- **Probe order (P0).** `env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=boot-probe-0 runuser -u git -- /usr/local/bin/git-data-remove.sh`.
  A static row asserts that `env -i` precedes `runuser` (applied above).
- **The sshd environment is enforced at boot, not only linted.** The existing `sshd -T` stage in
  `cloud-init-git-data.yml` (~L836) FATALs unless:
  - the `acceptenv` values are a subset of {`LANG`, `LC_*`};
  - `permituserenvironment` is `no`.

  The census stays as a lint. `authorized_keys` options gain `no-user-rc`.
- **The gc unit strips the seams.** `git-data-gc.service` `ExecStart` wraps the call in
  `env -u GIT_DATA_STORE_DEVICE -u GIT_DATA_STORE_VERIFIED -u GIT_DATA_MOUNT_ROOT -u GIT_DATA_REPO_ROOT`.
  Doppler `prd_git_data` could otherwise inject them. A census row checks this.
- **Marker directory.** `install -d -m0755 -o root -g root /etc/git-data`, then an atomic write
  (temp file plus `mv`). A census row asserts the bootstrap is the only writer under
  `/etc/git-data`.
- **Temporary plaintext mount.**
  - Mount at `$(mktemp -d)/mnt`, so the 0700 parent still protects it once the volume's own root
    mode takes over.
  - Use `-o ro,noload,nosuid,nodev,noexec`.
  - A trap unmounts it on every exit. A failed `umount` is FATAL `plaintext_unverified
    reason=umount`.

### Data integrity

- **`luks_residue` is FATAL** (applied above).
- **Journal state.** If `dumpe2fs -h` on the plaintext device shows `needs_recovery`, the result is
  `plaintext_unverified reason=journal`, and nothing is counted.
- **The marker is bound to one volume.** It holds the mapper's filesystem UUID. Every store-acting
  script compares it with `findmnt -n -o UUID --mountpoint "$MOUNT_ROOT"`, so a mapper reopened on a
  different volume refuses.
- **`erased` means unlinked, not physically destroyed.** Deleted blocks stay readable to a holder
  of the LUKS key until the key or the volume is rotated (D6, PR2). ADR-239 and the PA-36 addendum
  say so.
- **Deferred to PR2** (it touches app code): `removeGitDataRepo` should require a positive stderr
  sentinel (`erased bare repo` or `not present (no-op)`) as well as exit 0. PR1 adds the
  `git-data-remove.test.sh` contract row asserting both strings stay exact.

### Observability

- **Every new failure pages.** Each is emitted through `log "FATAL: <reason> …"`, which is
  `stage=bootstrap`, a value already in `git_data_boot_fatal`, so `issue-alerts.tf` is not edited.
  The failures are `plaintext_unverified`, `plaintext_residue`, `luks_residue`, `fence_on_mapper=no`
  and `erasure_probe=no`. A test row asserts the emitted stage is `bootstrap`.
- **gc** refuses with `exit 1`, so `git-data-gc-failure.service` fires its OnFailure emit. A test
  row covers this.
- **Reopen target.** Because `git-data-luks-reopen.sh` narrows to `/mnt/git-data`, any other target
  `die`s and pages as the existing `luks_reopen` stage.
- **Deferred to PR2** (unreachable while the flag is off): an app-side mirror for provision and
  transport refusals.

### Deployment (recovery)

- The pin is published by Terraform inside the apply (`git-data.tf:356`). The boot poll runs after
  it, so a failed poll leaves the pin published.
- `source-run-gate.sh` then skips the pin redeploy without failing, so no email is sent. After any
  failed step-3 replace, the runbook dispatches
  `gh workflow run git-data-pin-redeploy.yml --ref main`, with no `source_run_id`, because passing
  one re-reads the failure and skips again.
- Every recovery path starts with a Sentry or Better Stack read, never with a replace.

### User impact

- During a boot-FATAL window, a user who deletes their account sees the existing erasure-pending
  notice (`?erasure=pending`, `account-delete.ts:229`), not a clean success.
  - After the forward fix, the runbook sweeps the refused workspace ids from Sentry
    `op:git-data-bare-repo-erasure` and re-drives each erasure. Refusals only happen while the store
    is empty, so each resolves as `not present`.
  - The runbook records each id on the Art. 17 record.
- The store refusal uses the wrappers' `reject` (exit 1): never 0, never 255. The remove suite
  asserts that exit code, and an app-side unit row asserts `removeGitDataRepo` maps exit 1 to
  `refused`. This is an existing mapping; the row only pins it.
- What a user sees when replication is refused with the flag on is PR2's User-Brand Impact, not
  PR1's.

### Test design

These fixes make Guard 2 drivable without root.

- **Extraction.** Put sentinel comments around bootstrap steps 2 to 5 and extract them as one unit
  with a line floor, following the `_reopen_unit` precedent in `git-data-luks-reopen.test.sh`. A
  static row checks there is exactly one marker writer, placed after every `plaintext_*` and
  `luks_residue` FATAL.
- **Stubs.**
  - `mount` logs its argv (asserting `ro,noload,nosuid,nodev,noexec`) and copies a fixture tree
    into its target.
  - The real `findmnt` drives row 1: a no-op mount must read as `plaintext_unverified`.
  - A by-id seam points at a temp symlink for the positive control.
- **Seams.** The bootstrap honours `GIT_DATA_STORE_VERIFIED` and `GIT_DATA_STORE_DEVICE`, so a
  non-root run cannot pass "marker absent" through EACCES. There is also a positive control: the
  marker is present on the all-pass path.
- **The `runuser` stub** strips `-u git --` and preserves the environment exactly. The remove-script
  path is a seam, and a census row asserts its default stays `/usr/local/bin/git-data-remove.sh`.
- **Contract row in `git-data-remove.test.sh`:** `env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=boot-probe-0`
  gives exit 0 and exactly `not present (no-op)`.
- **Guard 1 row 6** derives its look-alikes from the real SOURCE (`"${src%?}"`, `"${src}-old"`),
  never a hand-typed `/dev/mapper/git-data-old`.
- **Guard 1 row 9** keeps `mountpoint` on the curated PATH, and anchors on the script's own `findmnt`
  refusal text.
- **Guard 2 row 4** derives the required set from the bootstrap's `boot_complete` arguments, and
  checks it against both `GIT_DATA_BOOT_TERMINAL` and the capture's required set.
- **Guard 2's harness row** asserts the capture's verdict text, not its exit code, unless `/work`
  confirms the exit code differs between PASS and FAIL.
- **btrfs.** Always set the seam from `findmnt --mountpoint "$(stat -c %m "$root")"`. btrfs prints a
  `[/subvol]` suffix.

## Test Scenarios

- **Script suites** (provision, remove, transport, gc):
  - match (the seam set to the root's `--mountpoint` SOURCE, marker present);
  - mismatch;
  - a prefix look-alike;
  - the marker absent;
  - `findmnt` missing;
  - the order row: the target is intact after a refused erasure.
- **Census:** the set derived from `main.tf` with the two named exemptions, the Guard 1 rows, and
  the sshd row.
- **Bootstrap suite:**
  - plaintext verified empty, absent, mount-failed (FATAL `plaintext_unverified`), and non-empty or
    partial (FATAL `plaintext_residue`);
  - `fence_on_mapper` true and false;
  - `erasure_probe` against a passing stub, a refusing stub, and an env-leak stub;
  - the marker written only on the all-pass path;
  - the probe's lock dotfile is invisible to the gc and `served_repos` counts.
- **Evidence capture and boot poll:** each new boolean `no` gives no PASS. A reboot-arm `target`
  other than `/mnt/git-data` FAILs.
- **Render suites:** the mapper is at `/mnt/git-data`; there is no plaintext fstab line, no
  `/mnt/git-data-luks` and no raw-glob mount; the budget is under the cap.
- `git-data-luks-reopen.test.sh`: only the `/mnt/git-data` target is accepted.
- The existing `git-data-cutover-access.test.sh` and `git-data-flag-precheck.test.sh` stay green.

## Open Code-Review Overlap

None. On 2026-09-22 the 72 open `code-review` issues were checked against every path in Files to
Edit and Files to Create; no issue body names any of them.

Two issues without that label are handled as follows:

- #8093 is acknowledged, not folded in, because it is a different concern.
- #6897 is referenced by the Encryption Posture exception, and the wipe PR closes it.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6. This one is filled.
- The `boot_complete` readers grep for `"<field>":"yes"`. Any value other than `yes` or `no` passes
  unchecked.
- `findmnt -n -o SOURCE --mountpoint` prints the device-mapper name. Compare by equality, never by
  prefix or glob.
- Mount the plaintext volume `ro,noload`. Plain `ro` can replay the journal. Verify the source, not
  only the count.
- Run the erasure probe as `env -i PATH=… SSH_ORIGINAL_COMMAND=… runuser -u git -- …`, with `env -i`
  outside `runuser`. `runuser` keeps its caller's environment, and the bootstrap's environment holds
  `GIT_DATA_LUKS_KEY`.
- After the step-3 replace, today's dry run reads `already_cut_over` (exit 5). That is expected; do
  not fix it in PR1.
- `refuse_if_fence_not_intact` exits 5. PR2 must call it before any mutation, or give it a
  return-a-verdict mode.
- For every `#N` in the PR body, run `gh issue view N --json title,state` first. #8451 is closed and
  #8563 is a PR.
