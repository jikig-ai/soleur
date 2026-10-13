# Tasks: inngest LUKS stage tolerates a late volume attachment; a lost first-boot race self-heals

Plan: `knowledge-base/project/plans/2026-10-13-fix-inngest-luks-volume-attach-race-plan.md`
Branch: feat-one-shot-10217-inngest-luks-attach-race. Closes #10217. Mirror of sibling draft PR #10210 (git-data), adapted to the inngest host's pointer/pre-cutover arms and its boot-reopen unit.
No task in this file dispatches a workflow, runs terraform apply, writes Doppler, reboots, or touches a host.
Do NOT touch `cloud-init-git-data.yml` or `git-data-bootstrap.sh` (sibling scope). Do NOT merge or rebase onto PARKED PR #10081 (expect textual overlap in `cloud-init-inngest.yml`).

## Phase 0: RED tests first

- [x] 0.1 `inngest-redis-luks.test.sh`: re-pin T1.6 to the ruled mechanism in BOTH `wait_dev` bodies (literal `300` bound, `sleep 1` counted passes, one post-loop `udevadm settle --timeout=10 || true` — NOT per pass) — expect RED
- [x] 0.2 `inngest-redis-luks.test.sh`: absence pin — zero `INNGEST_LUKS_ATTACH_WAIT_S` tokens in `cloud-init-inngest.yml`; `doppler run … -- bash -s` invocation pinned byte-identical (no `env -u`); ordering pin asserting `After=systemd-remount-fs.service` on `inngest-luks-open.service`
- [x] 0.3 `inngest-redis-luks.test.sh`: rows for `ensure_mount` in the reopen (mountpoint check, fstab line write, fstab-driven `mount`, `reopen_mount` emit, `fail reopen_mount` on mount failure) and that the `open_as` noop path still reaches it
- [x] 0.4 `inngest-redis-luks-loopback.test.sh`: retarget `render_stage`/`render_reopen`'s `-lt 30` sed rebind to `-lt 300` (kept mechanism — the seam was dissolved, not replaced); add `/mnt/data` + `/etc/fstab` rebinds to `render_reopen`; add the `udevadm` recorder stub next to `logger`
- [x] 0.5 `inngest-redis-luks-loopback.test.sh`: new arms — by-id link materialises mid-wait (verdict equals on-time, exactly one post-loop settle in calls.log); never-appears ends in the SAME named FATAL inside the rebound bound; a one-reader-bound-drift arm fails T1.6; bound 0 probes once with zero sleeps
- [x] 0.6 `inngest-redis-luks-loopback.test.sh`: BOOT2 self-heal arms — reopen with mapper reopened but `/mnt/data` unmounted and no fstab line ends mounted + exactly one fstab line + `reopen_mount` emitted; already-open noop path still mounts; normal boot (line + mount present) costs zero writes
- [x] 0.7 Confirm every new/changed row is RED against the current template

## Phase 1: Bounded counted attach-wait in both readers

- [x] 1.1 `cloud-init-inngest.yml` runcmd `LUKSEOF` stage: rewrite `wait_dev()` to the counted bound as ruled — literal `300`, existing `sleep 1`-per-pass loop, probe-once at 0, whole-predicate re-probe each pass, emit wait-start and appeared-after lines, `return 1` after the bound, ONE `udevadm settle --timeout=10 || true` AFTER the loop (never the clock); all call sites unchanged, FATAL sentences byte-identical
- [x] 1.2 `cloud-init-inngest.yml` `inngest-luks-open.sh` payload: same `wait_dev()` rewrite (the file's own comment requires the two readers not drift); escaping rule: bare `$` everywhere, `$${` only where a brace follows
- [x] 1.3 `cloud-init-inngest.yml`: verify the `doppler run … -- bash -s <<'LUKSEOF'` invocation is byte-identical to `main` — no `env -u`, no `INNGEST_LUKS_ATTACH_WAIT_S` anywhere in the file (CTO D4: no seam)

## Phase 2: Self-heal — the reopen completes the mount

- [x] 2.1 `inngest-luks-open.sh`: add `ensure_mount <source> <mountpoint>` (`mountpoint -q` fast path → fstab_set-equivalent write of `<source> <mp> ext4 defaults,nofail 0 2` asserting exactly one → `mkdir -p` → `mount <mp>` fstab-driven → `emit reopen_mount`; fstab or mount failure `fail`s the unit)
- [x] 2.2 Call `ensure_mount` on every verified arm: pointer canonical `/mnt/data`, pre-cutover crypto_LUKS `/mnt/data`, pre-cutover ext4-skip `/mnt/data` (after the `reopen_skip_plaintext` emit), staging `/mnt/data-luks`; include the `open_as` noop path
- [x] 2.3 Update the script's contract comment and the unit `Description=` to "opens, then completes the mount for the arm it verified — never formats, never mkfs"; add `After=systemd-remount-fs.service` to `inngest-luks-open.service` (CTO binding — fstab write/`mkdir -p` must not race a read-only root)

## Phase 3: Suites green + floors

- [x] 3.1 `bash apps/web-platform/infra/inngest-redis-luks.test.sh` GREEN; set the floor to the MEASURED count (was 64)
- [ ] 3.2 (CI-only, sudo — will measure at integration) `sudo bash apps/web-platform/infra/inngest-redis-luks-loopback.test.sh` GREEN; set the floor to the MEASURED count (was 85, projected)
- [x] 3.3 `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `inngest-host.test.sh`, `inngest.test.sh`, `inngest-luks-cutover.test.sh`, `inngest-luks-sole-copy.test.sh`, `journald-config.test.sh` all GREEN
- [x] 3.4 `bash apps/web-platform/infra/inngest-userdata-budget.sh --json`; record post-change headroom (pre-change stored 19,692 / headroom 13,076 of 32,768)

## Phase 4: Docs

- [x] 4.1 `soleur:architecture`: dated ADR-142 amendment (first boot may precede attachment completion; counted fail-closed bound in both readers; reopen contract now opens-then-mounts)
- [x] 4.2 `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`: dated entry (iid 170091264 incident timeline; what a `reopen_mount` row means)
- [x] 4.3 `bash plugins/soleur/test/c4-count-parity.test.sh` green (no C4 edit)

## Phase 5: Handoff (no dispatch)

- [x] 5.1 Full local suite list from the plan's Acceptance Criteria; `git diff --name-only origin/main...HEAD` contains neither sibling file
- [x] 5.2 PR body: first line answers "does merging this mutate production?" (`no — user_data ForceNew, inert until the next sanctioned inngest-host-replace`); `Closes #10217`; does NOT close #6442; lists `inngest-host-replace` (and the optional `inngest-provision-rehearsal.yml` paid end-to-end check) as UNRUN operator-gated dispatches
