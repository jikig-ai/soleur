# Tasks — feat-one-shot-6604-workspaces-luks-cutover

Plan: `knowledge-base/project/plans/2026-07-17-fix-6604-workspaces-luks-cutover-plan.md`
Parent: `knowledge-base/project/plans/2026-07-17-fix-6588-luks-encrypt-workspaces-volume-plan.md`
(its `## Deepen Pass Corrections` C1–C19 are BINDING).

Issue: #6604 (PR 2 of #6588). ADR-119 (`status: adopting`) already on main. `Ref #6588`, never `Closes`.
Legal PR (AC1–AC10) is **PR 3 — out of scope**, opened by the soak actor after the canary passes.

> **Already shipped by #6593 — do NOT re-create:** `workspaces-luks.tf`, `workspaces-luks.test.sh`,
> ADR-119, the `model.c4` element+edge, and the `OPERATOR_APPLIED_EXCLUSIONS`. Keep them green (regression).

---

## Phase 0 — Read-only preconditions (no code, NOT blocked)
- [x] 0.1 Verify the LIVE web-1 `/etc/fstab` + mount state over the SSH bridge (read-only). If `/mnt/data`
      is unmounted (rebooted host), STOP + remediate the mount before proceeding (the sequencing assumes it mounted).
- [x] 0.2 `du --apparent-size -sh /mnt/data/workspaces` — confirm near-empty ⇒ single-pass rsync, no `--delete` on the critical path.
- [x] 0.3 Confirm `prd_workspaces_luks` Doppler config exists; regression-baseline the drift guard + exclusion parity green.

## Phase 1 — Pin the mount, fail-closed (ships independently — a live latent-bug fix)
- [x] 1.1 `cloud-init.yml`: glob → explicit volume-ID device + `nofail` + `grep -q` fstab guard; boot emit on mount failure.
- [x] 1.2 Persist the Sentry DSN to a boot-written env file the `luks-monitor` unit sources (Q8/C14 P0-2).
- [x] 1.3 Sweep `git-data-bootstrap.sh` (`:46`,`:71`) — pin by volume ID or document the git-data-host non-ambiguity (Q5).
- [x] 1.4 Edit `soleur-host-bootstrap-observability.test.sh` AC6b — re-point at the new invariant; argue the reversal in-file (C10).
- [x] 1.5 `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` (budget 21,900) + the observability test green.

## Phase 2 — The cutover gate + observability plumbing (mergeable, inert until dispatched)
- [x] 2.1 `tests/scripts/lib/workspaces-luks-cutover-gate.sh` + `test-workspaces-luks-cutover-gate.sh` (CAP-COUPLING, sourced-not-copied, synthesized fixtures). **DP-1: this is a FIRST PROVISION — allow-set = all five workspaces_luks resources; the create job `-target`s exactly those five.** Counters (4-verb create/update/delete/forget filter, bracketed indexed addresses): `luks_volume_created>=1 && luks_attachment_created>=1 && luks_secret_created>=1 && old_volume_touched==0 && old_attachment_touched==0 && web1_server_touched==0 && luks_volume_destroyed==0 && luks_passphrase_touched==0 (update/delete/forget ONLY, never create) && resource_deletes==0 && out_of_scope==0` (exact `IN(.address; allow[])`). NO `[ack-destroy]`. Register in `test-all.sh`.
- [x] 2.2 `vector.toml` add `luks-monitor` to `include_matches.SYSLOG_IDENTIFIER` + update `vector-pii-scrub.test.sh` fixture (Q9).
- [x] 2.3 `sentry/issue-alerts.tf` new `sentry_issue_alert` (feature:workspaces-luks / op:workspaces-luks-drift, notify_email IssueOwners/ActiveMembers) + mirror in `configure-sentry-alerts.sh` (C14 P1-5).
- [x] 2.4 `uptime-alerts.tf` new `betteruptime_heartbeat.workspaces_luks` (positive-control for the soak).
- [x] 2.5 `workspaces-luks-emit.sh` — mirror `cron-egress-enforce-probe.sh`; 9 discriminating fields `{device_type,mount_source,mapper_present,luks_open_result,header_uuid_match,cryptsetup_unit_result,doppler_reachable,mountpoint_ok,host,reason}`; persisted DSN.
- [x] 2.6 `luks-monitor.{sh,service,timer}` — DAILY escrow(`--test-passphrase`)+header-UUID probe → heartbeat (NOT a 5-min poll).
- [x] 2.7 Baked LUKS block + structural `RequiresMountsFor`/`crypttab`/`chattr +i` in `soleur-host-bootstrap.sh` (fresh-host path; dead on web-1, ADR-119 §(e)).
- [x] 2.8 `.github/workflows/workspaces-luks-verify.yml` — read-only re-assert (the no-SSH runbook artifact).

## Phase 3 — Additive-volume dispatch apply + escrow + rehearsal + bulk rsync (ZERO downtime)
- [x] 3.1 New `apply_target=workspaces-luks-cutover` job in `apply-web-platform-infra.yml` (git_data_host_replace shape: ephemeral keygen, `doppler run --name-transformer tf-var`, sources the gate lib, no `environment`, no `[ack-destroy]`). Add the choice option + description. **Job-level `concurrency: group: web-1-swap`.**
- [x] 3.2 `workspaces-cutover.sh` (copy git-data-cutover.sh's SHAPE; never invoke it). L3 gates (Hypotheses 1-2) abort before any freeze.
- [x] 3.3 `prepare_luks_target`: select FRESH device by volume ID; blkid raw-signature discriminator; open mapper at a staging path.
- [x] 3.4 **Escrow proof (BLOCKING, AFTER 3.3):** `printf '%s' "$KEY" | cryptsetup luksOpen --test-passphrase --key-file - "$REAL_DEV"`, key via `doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks` (R9). Then `luksHeaderBackup` off-host to a bucket distinct from tfstate; assert `luksDump` UUID match (C4).
- [x] 3.5 G2 manifest: enumerate workspaces; `git rev-parse` every ref incl. `refs/checkpoints/*`; `git status --porcelain`. Derive a `count > 0` floor.
- [x] 3.6 Rollback rehearsal: read-only remount of the retained plaintext at a distinct path (no container restart — C15 caveat).
- [x] 3.7 Bulk `rsync -aHAX` (no `--delete`) into the empty LUKS target against the live tree.

## Phase 4 — The freeze (≤20 min budget, ≤2h hard abort, environment-gated)
- [x] 4.1 `.github/workflows/workspaces-luks-cutover.yml` (mirror git-data-cutover.yml): confirm token; `dry_run`/`rollback`/`confirm_wipe`; SSH bridge; `web-1-swap`; **`environment: workspaces-luks-cutover`** with a required reviewer on the freeze/wipe steps + the #4220 counter-argument comment (C19 sign-off mechanism).
- [x] 4.2 **DP-6: HOST-SIDE** EXIT trap — `workspaces-cutover.sh` runs ON web-1 via the bridge, so `trap cleanup EXIT` rolls back (unmount-mapper→remount-plaintext→restart) WITHOUT CI SSH (precedent `git-data-cutover.sh` ROLLBACK mode). Persist freeze state to a HOST FILE (`/var/lib/…`), not shell vars, so a reboot doesn't destroy it. Post-reboot re-canary is its OWN gated step reading persisted state (pre-reboot `CANARY_OK=true` must NOT satisfy it). Add a host-local dead-man timer (auto-remount plaintext if no orchestrator heartbeat in N min); make the pre-freeze SSH gate a RENEWING lease.
- [x] 4.3 Halt `webhook.service`; `docker stop -t 120 soleur-web-platform` (C8); interrupted-write asserts (no `index.lock`/`tmp_pack_*`/`gc.pid`); `lsof +D /mnt/data` empty (G4).
- [x] 4.4 G3 manifest AFTER the freeze on SRC vs DST (same instant, opposite volumes — C9); `refs/checkpoints/*` its own named check.
- [x] 4.5 Drop caches; pass-2 `rsync -aHAX --delete --checksum`; itemized verify `-aHAXi … --dry-run --out-format='%i %n' | wc -l == 0` mutation-proven; `du --apparent-size` byte match; `git fsck --full` per workspace; `df` + `df -i` preflight. NO post-verify chown.
- [x] 4.6 `repoint_luks_mount`: mapper → `/mnt/data` (backup fstab; `findmnt` assert).
- [x] 4.7 Host-level canary BEFORE `docker start`: `blkid`=crypto_LUKS AND `findmnt`=/dev/mapper/workspaces AND `cryptsetup status workspaces` (mapper→device link) AND `mountpoint -q`. Emit discriminating fields.
- [x] 4.8 `docker start`; resume `webhook.service`; app canary (`/api/health` 200 + workspace read); **reboot-once + re-canary** (C15).
- [x] 4.9 Any failed assert ⇒ EXIT-trap rollback to plaintext.

## Phase 5 — Soak → (separate env-gated dispatch) converge → wipe → open PR 3
- [x] 5.1 **DP-4/DP-5: READ-ONLY soak** `scripts/followthroughs/workspaces-luks-soak-6604.sh` (sweeper-run, env -i, no GH/Doppler token): PASSes only on OBSERVED completion — zero `op:workspaces-luks-drift` Sentry events (`SENTRY_AUTH_TOKEN`, status-checked first ⇒ TRANSIENT never false-PASS) AND heartbeat present (`BETTERSTACK_QUERY_*`, positive control, archive arm for real 7d span) AND retained volume detached+gone (read-only Hetzner probe) AND PR 3 open AND ADR-119 accepted. Real ISO `earliest=` + internal elapsed-window floor ≥7d (never the literal placeholder). Before completion: comment "SOAK PASSED — wipe authorized", leave tracker OPEN. Precedent `inngest-rls-drop-6488.sh`.
- [x] 5.2 **DP-4: destructive dispatch is SEPARATE + `environment:`-gated** (its own actions/pull-requests perms + non-empty required reviewer). Wipe: `lsblk -D` → `blkdiscard -z` → verified read-back (random offsets + offset 0) → Hetzner API delete → **DETACH** the retained volume (C5; structural precedent `inngest-wiped-volume-verify.sh`). DP-7: re-verify the durable run-keyed `canary_ok` artifact's header-UUID against the live mapper immediately before blkdiscard.
- [x] 5.3 **DP-2: convergence is a `for_each` key-set NARROWING, not a block delete.** API-detach → API-delete (BEFORE state rm) → `state rm`/`removed{}` the two `["web-1"]` instances → same PR narrows `for_each = { for k,v in var.web_hosts : k=>v if k != "web-1" }` on BOTH `hcloud_volume.workspaces` AND its attachment (server.tf). Or sequence after #6538. NEVER delete the whole block (destroys web-2's volume) or drop web-1 from var.web_hosts (destroys the web-1 server).
- [x] 5.4 Flip ADR-119 `adopting → accepted`; flip `model.c4` `workspacesVolume` description PLAINTEXT→LUKS; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [x] 5.5 Open **PR 3** (the legal flip: AC1–AC10 + present-tense LUKS + SHA re-pin; re-derive the clause-site count at that PR). Enrol tracker directive + `follow-through` label.

## Exit gate
- [x] E.1 `bash tests/scripts/test-all.sh` reads `N/N suites passed`.
- [x] E.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (NOT `npm run -w`).
- [x] E.3 Pre-merge ACs (AC13–AC20b) met; post-merge ACs (AC21–AC30) specified for the dispatch run.
- [x] E.4 PR body: `Ref #6588` (never `Closes`); Tier-1 classification; the C19 sign-off + soak enrollment stated.
