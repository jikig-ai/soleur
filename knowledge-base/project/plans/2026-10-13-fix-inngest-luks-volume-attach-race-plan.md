---
title: "fix: inngest LUKS stage tolerates a late volume attachment (bounded fail-closed wait) and a lost first-boot race self-heals"
date: 2026-10-13
slug: inngest-luks-volume-attach-race
branch: feat-one-shot-10217-inngest-luks-attach-race
issue: 10217
closes: 10217
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-13 (manual sequential pass — this harness has no Task/Agent tool; the per-section fan-out, skills fan-out, learnings fan-out and review-agent fan-out ran inline by the author, `Reviewed-Coverage: sequential-fallback` — no independent review is claimed)
**Sections enhanced:** Observability (discoverability probe made Check-10 compliant), Proposed Solution (runcmd shared-shell leak channel; RequiresMountsFor Requires-strength note; udevadm availability), Dependencies & Risks (measured-vs-reasoned systemd caveat; #9175 forced-race precedent), Research Insights (additional learnings applied)

### Key Improvements

1. `discoverability_test` replaced the suite-shaped command (Check-10 15 s cap reject on a new block, and `0 failed` tokenizes to a single whitespace-bearing token → reject) with a plain `grep` probe over the liveness marker — allowlisted verb, ms runtime, whitespace-free literal.
2. The `env -u` seam strip now covers BOTH injection channels: the Doppler env AND the shared-runcmd-shell leak (cloud-init joins all `runcmd` entries into one POSIX `sh` script, so an earlier `set -a; . envfile` entry exports into every later entry).
3. The systemd mountinfo claim (generated `.mount` units mark active over an existing mount) is now explicitly labelled reasoned-not-measured, with the loopback BOOT2 arm as the measuring authority and the RequiresMountsFor fallback making a wrong claim harmless.

### New Considerations Discovered

- #9175 is the inngest provision-rehearsal root's own forced-race precedent — a `rehearsal_attach_delay_s` knob (sibling Phase 3's shape) is therefore a natural optional follow-up, still not required by any merge gate.
- The plaintext backstop's 2026-10-09 destroy makes the reopen-mount self-heal load-bearing in a way the sibling's was not: this store has no second copy.

## Overview

The inngest host's first-boot LUKS stage in `apps/web-platform/infra/cloud-init-inngest.yml` waits a fixed 30 counted one-second passes for the canonical volume's by-id link, then refuses. On the 2026-10-13 production `inngest-host-replace` (iid 170091264) the `hcloud_volume_attachment.inngest_redis_luks` — which lands in the same `terraform apply` as the server, so attach latency races first boot — took ~80 s and the stage FATAL'd at `pointer_device_wait` (rc=1). The boot-reopen unit (`inngest-luks-open.sh`, `enable --now`'d after the stage even when the stage aborted, #9939) later opened the mapper — `reopen_ok` — but reopen opens only, never mounts, and the mount + `fstab_set` steps sit AFTER the failed wait, so no fstab entry existed either. `inngest-redis` then failed closed forever (`FATAL: /dev/mapper/inngest-redis is open but /mnt/data is not a mountpoint`), the provision unit gave up `bootstrap-done-DEGRADED` (`why=.redis-inactive.no-durable-execstart`), `op=resume` G4 refused (run 38390026971), and no reboot could heal it: recovery cost a second full `inngest-host-replace` (run 38392893745 → iid 170097260) plus a ~40 min scheduler gap.

Two coupled defects, one fix each. (1) Every `wait_dev` site waits a fixed 30 s for a resource whose attach latency is measured up to ~125 s on this estate. Both readers — the `LUKSEOF` runcmd stage (three sites: `pointer_device_wait`, `device_wait`, `staging_wait`) and the boot-reopen script (three sites: pointer, pre-cutover, staging) — get the sibling-proven remedy (#10210, `git-data` `_gd_attach_wait`): a bounded, counted-passes wait (default 300 s, `udevadm settle` each pass, an env seam validated fail-closed for tests, never the clock) that ends in the SAME named FATAL. (2) A mapper-open-but-unmounted state is today unhealable by construction: reopen completes the mount itself — the fstab line plus the mount for the arm it opened — so ANY lost race converges on the same boot (the `enable --now` arm runs after an aborted stage) and on every later one, instead of requiring a host replace. The LUKS volume is the SOLE copy of the store since the 2026-10-09 plaintext-backstop destroy (#8285), which is why convergence must live in the boot path, not in a runbook.

## Research Insights

**Premise validation (Phase 0.6, 2026-10-13).** Cited items checked with `gh` and `git grep` on this branch: **#10217** OPEN, `closedByPullRequestsReferences` empty — premise holds. **#10210** OPEN draft (the sibling git-data remedy, fetched and read: `sibling-git-data-attach-race` at `cloud-init-git-data.yml`, `git-data-bootstrap.sh`, `git-data-bootstrap-store-verify.test.sh`). **#6442** OPEN (same attach-race class on `hcloud_firewall_attachment`; context only, NOT closed here). **PR #10081** OPEN, titled PARKED (`strip the dead plaintext-volume resolver arm`; touches `cloud-init-inngest.yml`, both LUKS suites, `inngest-redis-luks.tf`, `inngest-host.tf`, rehearsal root, ADR-142, ADR-199 — textual overlap expected, do not merge or rebase onto it). Cited paths verified on `origin/main`: `wait_dev` definitions at `cloud-init-inngest.yml` ~line 189 (reopen script) and ~line 1674 (runcmd stage), call sites ~1770 (`pointer_device_wait`), ~1799 (`device_wait`), ~1912 (`staging_wait`), ~219/228/241 (reopen); mount + `fstab_set` at ~1789-1790 (pointer arm) and ~1833/1853 (pre-cutover arms) sit after the waits; the `FATAL: … is open but /mnt/data is not a mountpoint` guard is installed by `inngest-redis-bootstrap.sh` step 3.5 as `inngest-redis-mount-guard.sh`, pinned by `RequiresMountsFor=/mnt/data` on `inngest-redis.service`.

**ADR-corpus check on the proposed mechanism** (Phase 0.6 item 4): a bounded, counted, fail-closed wait is the established remedy for this exact class — ADR-115 records that "the attach needs a *created* server, and a created server is *already booting*" (no ordering can beat the race; the remedy there was `soleur-inngest-nic-wait`, a bounded counted wait), and the sibling remedy shipped the same shape for volumes. No ADR rejects it. ADR-142 describes the reopen unit as opens-only today — the self-heal EXTENDS that contract, so the amendment is an in-plan deliverable (Phase 2.10), not a divergence. `inngest-redis-luks.tf` confirms the plaintext volume was destroyed 2026-10-09 and `hcloud_volume.inngest_redis_luks` + its Doppler key are the sole copy; `inngest-host.tf` renders `inngest_volume_id` as the retired literal (pointer-mode allowlist member only).

**Property List.**

- P1. A canonical-volume attachment landing within the bound no longer FATALs first boot at `pointer_device_wait` or `device_wait`; the stage's downstream verdict is identical to the on-time case.
- P2. A volume that never attaches (or attaches past the bound) ends in the SAME named FATAL — fail-closed, nothing past the wait runs, no fstab line, no mount.
- P3. The additive/staging volume wait tolerates a late attach too (`staging_wait`, reopen's staging wait) — same race, same bound; absent-after-bound still reads `staging_absent`, never a FATAL change.
- P4. The boot-reopen unit's own device waits use the same bound — it runs on every later boot AND on the aborted-first-boot `enable --now` path where the race also exists.
- P5. A boot in which the mapper is open but `/mnt/data` (or `/mnt/data-luks`) is not a mountpoint converges to mounted-plus-fstab'd — reopen completes the mount for the arm it verified — instead of requiring a host replace.
- P6. The bound is testable without wall-clock time (an env seam) and cannot be set from Doppler (`env -u` strip on the `doppler run` invocation).
- P7. The structural pins (T1.6-class) and the loopback rebind move with the implementation — a suite that pinned the old literal 30 without the mechanism pin would grade a budget it invented (the loopback file's own warning).

**Cut List (mechanism → property → what already covers it).**

- Terraform ordering fix (attach before boot): cut — the attachment needs the server's id; a created server is already booting (ADR-115's identical reasoning for the NIC).
- Re-running first boot via a reboot primitive: cut — runcmd is once-per-instance and `user_data` is ForceNew; the reopen+mount self-heal already covers reboot convergence (P5).
- A separate one-shot late-mount unit (issue's alternative): cut in favour of extending `inngest-luks-open.sh` — the unit already exists, is enabled, is ordered `Before=inngest-redis.service`/`local-fs.target`, already knows the pointer/devices/arm it took, and its `enable --now` already runs after an aborted stage; a second unit duplicates all of that plus enable/condition machinery.
- Write the fstab entries EARLIER in the runcmd stage (early-fstab): cut — it cannot cover the pre-signature failure (the arm, hence the fstab source, is unknown until `blkid`), while reopen-mount covers every arm because the reopen re-probes and re-derives the arm each boot; the stage's fstab writes stay where they are.
- `mount -a` or a mount inside the Redis mount-guard: cut — the guard stays a pure refusal (its fail-closed semantics are the point); repair belongs in the boot-reopen path.
- A bound beyond 300 s: cut — 300 s ≈ 3.75× the measured ~80 s attach (the sibling used 300 s vs a 125 s observation); a slower attach still ends in the same named FATAL, unchanged failure mode.
- The sibling's `label+predicate` helper signature: cut — all six inngest sites share the identical `-b <path> && size>0` predicate already factored as `wait_dev <path>`; a signature change would churn six call sites for no property.

**Institutional precedents used.** `git-data-bootstrap.sh` `_gd_attach_wait` (sibling branch, #10138/#10210 — the shape being mirrored: `${VAR-300}` plain-dash default, `case ''|*[!0-9]*` validation + length cap + `10#`, probe-once, `udevadm settle --timeout=5 || true` + `sleep 5` counted at 10/pass, whole-predicate retry, direct call never `$( )`, unchanged FATAL sentences, `env -u` seam strip); `soleur-inngest-nic-wait` (ADR-115 amendment: loop counter, never the clock); `git-data-luks-reopen.sh` (`GIT_DATA_REOPEN_DEVICE_WAIT` seam precedent); the loopback suite's own extraction/rebind conventions (`inngest-redis-luks-loopback.test.sh` — real dm-crypt devices, Terraform's two escapes only, `wait_dev` bound rebind); learnings `2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics` (pin `exit 1` semantics, not token presence; gate the consumer on the mount — here the mount itself is what we're healing), `2026-09-21-a-selector-that-settles-on-the-first-qualifier-cannot-see-the-candidate-created-after-it` (re-probe the whole predicate each pass), `2026-10-13-a-sibling-session-shipped-the-same-fix-while-i-planned` (the sibling collision class this pipeline's scope constraint exists to prevent).

**Functional/community checks.** Phase 1.5 stack scan: no uncovered stack (bash/systemd/cloud-init/Terraform all covered by repo suites) — skipped. Phase 1.5b functional-overlap agent: no Agent tool on this harness; inline equivalent — the mechanism being extended (`wait_dev`) already exists in-repo; no community artifact applies. Phase 1.6 external research: skipped — strong local precedent (the sibling remedy is the spec).

**Skill-description budget (Phase 1.8).** No `SKILL.md` `description:` edit is candidate — skipped.

### Deepen-pass verification (2026-10-13)

- **Gates:** 4.6 User-Brand Impact present, threshold `aggregate pattern`, sensitive path (`apps/web-platform/infra/`) with a non-`none` threshold: pass. 4.7 Observability: five fields present; `discoverability_test.command` is `grep SOLEUR_INNGEST_LUKS_STAGE apps/web-platform/infra/cloud-init-inngest.yml` (allowlisted verb, no ssh, no shell tokens, ms runtime), `expected_output` the whitespace-free literal `SOLEUR_INNGEST_LUKS_STAGE` — the earlier suite-shaped form was replaced at this pass because a new block's suite shape hits the deliberate over-inclusive cap detector AND `0 failed` tokenizes to a single whitespace token. 4.8 PAT-shaped variables: none. 4.9 UI: no UI-surface file, skipped. 4.10 Encryption Posture: `at_rest` entry carries non-empty `does_not_defend`; no exception block needed (mechanism is `luks`, not `plaintext-exception`); `in_transit` empty — no new connection. 4.11 `python3 scripts/lint-guard-contract.py`: 3 guard entries, rc=0; adequacy read — each Assembly names a chokepoint (the single `wait_dev` body per reader, `ensure_mount` as the single mount path every arm flows through, the single `doppler run` invocation line), not a snapshot of members. 4.12 Scope Check: exactly one unfenced `## Scope Check`, all three subsections, no `unmapped` cell, `Recommendation:` present. 4.55 Downtime gate FIRED (user_data is ForceNew on the serving host): section present with the zero-downtime evaluation (blue-green not available on a single-host scheduler; residual accepted via the sanctioned operator-gated dispatch, bounded by the existing replace mechanics). 4.5 network-outage gate FIRED on the `firewall` keyword (the #6442 cross-reference): layer-by-layer opt-outs with evidence are in Hypotheses.
- **Citations resolved live:** #10217 and #6442 and PRs #10210/#10081 OPEN (confirmed 2026-10-13); #7695, #9939, #9962, #8285, #9879, #6894, #9175 CLOSED (verified `gh issue view` this pass). ADR-142, ADR-115 and runbook `inngest-luks-cutover-6894.md` exist at the cited paths. Rule ids: `cq-write-failing-tests-before` active in AGENTS.md; `wg-architecture-decision-is-a-plan-deliverable` migrated-active per `scripts/migrated-rule-ids.txt`. Every suite named in Acceptance Criteria exists at the cited path and `inngest-redis-luks.test.sh` measured 0.57 s locally.
- **Negative claims checked against code:** (a) "Doppler config cannot reach the reopen's env" — the unit carries exactly `EnvironmentFile=/etc/default/inngest-doppler` + `EnvironmentFile=/etc/default/inngest-luks`, both unprefixed runcmd writes (the #9939 skip-vs-fail comment confirms): confirmed. (b) "merge is inert" — `hcloud_server.inngest` carries NO `ignore_changes=[user_data]` (ForceNew) and is NOT in the per-merge `-target=` allowlist; only `inngest-host-replace` (`-replace='hcloud_server.inngest'` + `-target=`) reaches it: confirmed in `inngest-host.tf` and `apply-web-platform-infra.yml`. (c) "no `luksFormat`/`mkfs` invocation in the reopen today" — the only token hits are the contract comment itself: confirmed (AC3 written as a presence-pin accordingly). (d) "the mount guard is Requires-strength, not just ordering" — `RequiresMountsFor=/mnt/data` on `inngest-redis.service` and `Before=local-fs.target`/`After=systemd-udev-settle.service` on `inngest-luks-open.service` read at `cloud-init-inngest.yml` ~lines 130-150: confirmed.
- **Precedent diff (`wait_dev` vs `_gd_attach_wait`, sibling branch read 2026-10-13):** matches the shape — `${VAR-300}` plain-dash default, `''|*[!0-9]*` + length-cap + `10#` validation before first probe, probe-once at bound 0, `udevadm settle --timeout=5 || true` + `sleep 5` charged 10/pass (the 10 s/pass charge counts BOTH the settle and the sleep: never the clock), whole-predicate retry, unchanged refusal. Deliberate deviations: (i) signature stays `wait_dev <path>` — six call sites share one identical predicate, so the sibling's `label+predicate` params buy nothing; (ii) emits go through each file's own emitter (`luks_emit`/`emit`) rather than a new channel; (iii) no `readonly` on the bound (the helper reads the env once at validation, same effect). No in-repo precedent exists for `ensure_mount` — the nearest writer is the stage's own `fstab_set` (`inngest-luks-cutover.sh` shares the semantics); pattern is novel-in-name, canonical-in-shape.
- **Semantic-change test audit (full enumeration):** `git grep -rlE 'wait_dev|LUKSEOF|inngest-luks-open|inngest-luks-stage' -- 'apps/web-platform/infra/*test*' 'tests/' 'scripts/'` on this branch returns 7 files. Dispositions: `inngest-redis-luks.test.sh` + `inngest-redis-luks-loopback.test.sh` (this plan's suites), `journald-config.test.sh` (Vector tag allowlist — the new `reopen_mount` emit rides the existing `inngest-luks-stage` tag; re-run, no edit expected), `scripts/followthroughs/inngest-provision-rehearsal-capture.test.sh` (rehearsal-capture fixtures naming `inngest-luks-open.service` journald rows; re-run, no edit expected — the new emit keeps the same tag/shape), `git-data-bootstrap-store-verify.test.sh`/`git-data-luks-reopen.test.sh`/`git-data-luks.test.sh` (match the same-named `LUKSEOF` delimiter in `cloud-init-git-data.yml` — sibling scope, do not touch). Suites that consume the template without matching those tokens and are re-run per AC: `inngest-luks-cutover.test.sh`, `inngest-luks-sole-copy.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `inngest-host.test.sh`, `inngest.test.sh`.
- **Additional learnings applied this pass:** `2026-08-19-the-budget-was-shorter-than-the-thing-it-was-waiting-for` (a bound is a bounded improvement, not a proof — the 300 s bound keeps the same FATAL past it), `2026-09-19-every-systemd-claim-i-reasoned-was-inverted-by-a-thirty-second-measurement` (the mountinfo claim is labelled reasoned-not-measured; the loopback arm measures the end state), `2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots` (T1.6 pins run over the extracted heredoc bodies — the render proxy — and the userdata budget is re-rendered through terraform), `2026-09-18-every-instrument-i-waited-on-was-counting-itself` (the wait's emit lines are exercised by the late-attach arms, not merely present), `2026-09-27-the-monitor-that-was-never-installed-and-the-dependency-that-would-have-mounted-plaintext` (Requires-strength dependencies mount what fstab names — accounted in Solution 2).

## Hypotheses

The feature description mentions `firewall` (sibling-class issue #6442), firing the L3→L7 checklist. The failure here is guest-internal block-device propagation, not a connectivity symptom — each layer opts out citing the evidence, per the checklist's opt-out clause:

1. **L3 firewall allow-list** — [opt-out: the incident's evidence is `SOLEUR_INNGEST_LUKS_STAGE stage=pointer_device_wait rc=1` inside the guest at 11:22:41 UTC, before any network-dependent step; the inngest host has no SSH at all, so no client path exists to verify].
2. **L3 DNS/routing** — [opt-out: same artifact; no name resolution or route is implicated in a `/dev/disk/by-id` absence].
3. **L7 TLS/proxy** — [opt-out: no HTTPS path involved].
4. **L7 application** — [verified by the issue's Better Stack rows: `inngest-luks-FAILED stage=pointer_device_wait rc=1` → `inngest-luks-reopen-armed` → `reopen_ok` → `bootstrap-done-DEGRADED`, plus `op=resume` G4 refusal run 38390026971 and recovery run 38392893745; the guest's own stage log is the service-layer journal, and it names the device wait].

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (read 2026-10-13, this branch) | Plan response |
|---|---|---|
| "the mount + fstab_set steps in the luks stage come AFTER the failed wait, so no fstab entry exists" | Confirmed — pointer arm order is `pointer_device_wait` (~1770) → `pointer_blkid_probe` → `pointer_luks_open` → `pointer_mapper_probe` → `mount_luks` (`mount` ~1789, `fstab_set` ~1790); an abort at the wait leaves no `/mnt/data` line. | Self-heal writes the fstab line from the reopen path (P5), which owns convergence whenever the stage did not finish. |
| "the boot-reopen arm later opened the mapper (reopen_ok) but reopen opens only, never mounts" | Confirmed — `inngest-luks-open.sh` `open_as()` does `cryptsetup luksOpen` + `emit reopen_ok`; no `mount`, no fstab anywhere in the script. | `ensure_mount` added on the same arm, so `reopen_ok` is followed by `reopen_mount` when the mount is absent. |
| "A reboot cannot heal it" | Confirmed on `origin/main` — reopen has no mount logic and there is no fstab line for the fstab path to consume. | After the fix a reboot (and even the same boot via `enable --now` + `RequiresMountsFor`) heals: reopen opens, `ensure_mount` writes the line and mounts; systemd marks the generated `mnt-data.mount` active from mountinfo. |
| "reopen opens only" is incidental, not contractual | The file's header documents "Opens ONLY; never formats, never mkfs" — the constraint is about FORMAT decisions (a boot-time unit that can create a filesystem can destroy one), not about mounting a device it just verified `crypto_LUKS`. Mounting makes no format/mkfs decision. | The contract line is updated to "opens, then completes the mount for the arm it verified; never formats, never mkfs" and the unit `Description=` follows. |
| The failure surface is only `pointer_device_wait` | The same 30-pass `wait_dev` bounds `device_wait` (pre-cutover, dead arm since the 2026-10-09 backstop destroy — PR #10081 strips it), `staging_wait` (additive volume), and all three reopen waits. | One shared `wait_dev` body per file — the fix reaches every site for free; no per-site negotiation. |
| PARKED PR #10081 "touches the same file" | It strips the pre-cutover/plaintext resolver arms this plan also edits (`wait_dev` body is shared, and the reopen's ext4/pre-cutover block sits beside the pointer arm). | Keep pre-cutover edits minimal and symmetric (shared helper body + one `ensure_mount` call per arm); flag the conflict surface in Risks; do not merge or rebase onto #10081. |

## Problem Statement

Hetzner attaches block volumes as separate actions once the server exists, so a created server is already booting while the attachment is in flight (ADR-115). On iid 170091264 the `inngest_redis_luks` attachment finished ~80 s after boot began; the stage's 30-pass wait expired, `pointer_device_wait` FATAL'd, and every step after it — open, probe, `mount`, `fstab_set` — never ran. The reopen arm then did exactly what it is specified to do (open only), producing a state no boot can heal: mapper open, no mountpoint, no fstab line, Redis refused by its own guard. The store is the sole copy (#9879), so the host's only recovery was a second destroy-and-recreate.

## Proposed Solution

Rulings are recorded in `knowledge-base/project/specs/feat-one-shot-10217-inngest-luks-attach-race/decision-challenges.md` — this harness has no Agent tool, so each technical row is `pending - assumed: <default>` mirroring the sibling's CTO rulings, to be re-ruled by `soleur:engineering:cto` at review if contested.

1. **Bounded counted attach-wait, one shared body per file (D1, D3).** `wait_dev()` in the `LUKSEOF` runcmd stage AND `wait_dev()` in `inngest-luks-open.sh` are rewritten to the same shape (keeping the `<path>` signature — every call site is unchanged): bound read as `${INNGEST_LUKS_ATTACH_WAIT_S-300}` (plain-dash — an EMPTY value is refused, never defaulted), validated `^[0-9]{1,4}$` and evaluated `10#` before the FIRST probe (an invalid value is its own named FATAL `attach_wait_invalid`, `exit 1`); probe once immediately (bound 0 still probes exactly once); on a miss emit one "waiting up to Ns for <path>" line through the file's own channel, then per pass `udevadm settle --timeout=5 >/dev/null 2>&1 || true`, `sleep 5`, and `waited=$((waited + 10))` (iteration count, never the clock — settle and sleep each take their own time, so 10 s/pass is a conservative charge; worst case ≈ bound, not bound×2); re-run the whole `-b <path> && blockdev --getsize64 > 0` predicate each pass; emit "<path> appeared after Ns of the bound" on resolution; `return 1` after the bound. All six call sites keep their existing post-wait semantics byte-identically: the two canonical FATALs unchanged, `staging_absent` still a tolerated non-fatal. `set -euo pipefail` discipline per the sibling's review: the predicate is an `&&` chain inside a condition context, the helper is called directly (never `$( )`), no `((n++))` from 0. `udevadm` is part of the `udev`/systemd package present on the cloud image (and the call is `|| true`, so even an image without it loses only the settle nudge, not the wait).
2. **Self-heal: the reopen completes the mount (D2).** `inngest-luks-open.sh` gains `ensure_mount <source> <mountpoint>`: `mountpoint -q` no-op fast path → `fstab_set`-equivalent write of `<source> <mp> ext4 defaults,nofail 0 2` (replace-in-place, assert exactly one — the same semantics as the stage's `fstab_set`; a fstab rewrite failure is `fail reopen_fstab`) → `mkdir -p` → `mount <mountpoint>` (fstab-driven: the line just written is the source of truth for source and options; a mount failure is `fail reopen_mount`) → `emit reopen_mount`. Called after the arm's open/verify: pointer arm `ensure_mount "$MAPPER" /mnt/data` before `exit 0`; pre-cutover `crypto_LUKS` arm the same; pre-cutover `ext4` + `expect_luks=false` arm `ensure_mount "$DEV" /mnt/data` after the `reopen_skip_plaintext` emit (the emit stays truthful — nothing was OPENED); staging arm `ensure_mount "$STAGING_MAPPER" /mnt/data-luks` after `open_as`. The noop path (`$2 already open`) still runs `ensure_mount` — that is the incident's exact post-state. Header comment and `[Unit] Description=` updated to "opens, then completes the mount for the arm it verified — never formats, never mkfs". Ordering is unchanged (`DefaultDependencies=no`, `Before=local-fs.target`/`inngest-redis.service`): the reopen mounts before local-fs processing. The claim that systemd then marks the generated `mnt-data.mount` active from mountinfo is REASONED, not measured (learning `2026-09-19` — reasoned systemd claims invert under measurement); the loopback BOOT2 arm measures the end state that matters (mountpoint holds, fstab line exists, unit succeeds), and even if the generated unit mounted over the same mountpoint from the same source, `RequiresMountsFor` and the Redis mount guard still see the mountpoint — a wrong version of the claim is harmless, not a hazard. A mid-cutover reboot mounts the mapper the STAGED pointer names — the cutover FSM maintains `/etc/default/inngest-luks`'s `INNGEST_LUKS_ACTIVE_VOLUME_ID` and fstab together, so reopen mounts what fstab will name anyway; convergence, not a new fork. Belt on the belt: `RequiresMountsFor=/mnt/data` on `inngest-redis.service` is Requires-strength — once the fstab line exists, Redis's own unit-start mounts it even if every other path missed; the incident's failure was precisely that no fstab line existed to consume.
3. **Seam strip (D4).** The `LUKSEOF` invocation becomes `doppler run --project soleur-inngest --config ${inngest_doppler_config} -- /usr/bin/env -u INNGEST_LUKS_ATTACH_WAIT_S bash -s <<'LUKSEOF'` — a `prd` Doppler key cannot lower (or inflate) the production bound. The strip sits inside the `doppler run` child env, so it also covers the OTHER leak channel: cloud-init joins all `runcmd` entries into ONE POSIX `sh` script, and an earlier `set -a; . envfile; set +a` entry exports into every later entry's environment — `env -u` in this child's env strips the name regardless of which channel set it. The three extraction anchors that pattern on `-- bash -s <<.LUKSEOF.` are updated (they now pin the strip). The reopen script needs no strip: its env is the two `EnvironmentFile=` files the stage itself writes — Doppler config cannot reach it (stated, not assumed).
4. **Structural pins and harness (mirror the sibling's test plan).** `inngest-redis-luks.test.sh`: T1.6 re-pins the new mechanism in BOTH readers (seam name, `-300` default, counted `+10`/pass, `udevadm settle`, validation FATAL) instead of the literal 30; new rows pin `attach_wait_invalid`, the `env -u` strip on the invocation, `ensure_mount` presence in the reopen (mountpoint check, fstab write, `mount`, `reopen_mount` emit), and that `open_as`'s noop path still reaches `ensure_mount`; floor 64 → measured. `inngest-redis-luks-loopback.test.sh`: `render_stage`/`render_reopen` drop the `-lt N` sed in favour of passing `INNGEST_LUKS_ATTACH_WAIT_S` in the run env (a declared harness knob, same role as today's bound rebind); `render_reopen` gains the `/mnt/data` and `/etc/fstab` rebinds (the reopen now touches both); a `udevadm` recorder stub joins `logger` on PATH; new arms — a by-id link materialised mid-wait (background `sleep`; `ln -s`) proceeds with the on-time verdict, a never-arriving link ends in the unchanged FATAL inside the seam bound, and a BOOT2 self-heal arm where the reopen runs with no fstab line and no mount → the mapper is opened AND `/mnt/data` is a mountpoint AND the fstab line exists AND `reopen_mount` was emitted. Loopback floor 85 → measured.
5. **Docs.** ADR-142 amendment (dated): first boot may begin before volume attachments finish; both device readers wait under a counted, fail-closed bound; the boot-reopen completes the mount for the arm it verified, so a lost race self-heals. Runbook `inngest-luks-cutover-6894.md` dated entry (incident timeline, what `reopen_mount` means on a boot row). C4: no change — see Architecture Decision section for the enumeration.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Wait-bound extension only (exact sibling mirror) | Leaves the whole post-open failure class unhealable: ANY stage failure after `luksOpen` (transient mount failure, a FATAL past the wait) still yields mapper-open-but-unmounted with no fstab — the state that cost a host replace. The issue's second half asks for the self-heal explicitly. |
| Early fstab in the runcmd stage | Cannot cover a pre-signature failure: the fstab source depends on the blkid arm, which a pre-`device_wait` failure never reaches. Writing `$MAPPER` unconditionally would be WRONG in the pre-cutover ext4 world (fstab would name a mapper that never opens → permanent dark host on healthy plaintext data). |
| Separate one-shot late-mount unit | More machinery (new unit file, enable wiring, conditions, its own emitter) duplicating context `inngest-luks-open.sh` already holds — pointer, devices, the arm it took, the correct boot ordering. |
| Reboot to re-run the stage | runcmd is once-per-instance; `user_data` is ForceNew. A reboot never re-runs the stage — that is the incident's whole problem. |
| Poll Hetzner attach state instead of guest-side wait | The host's boot token is scoped `soleur-inngest/prd` Doppler read/write, not Hetzner API; adding an HCLOUD token to user_data for a state poll is a new credential surface to fix a guest-local observation (`/dev/disk/by-id` propagation) the guest already measures. |
| Per-site bounds (short staging, long canonical) | One shared body keeps the bound undriftable — the file's own comment already warns the two readers must not drift; a second bound invites it. The staging wait's tolerated-absent cost is bounded and rare (the additive volume is declared in the same apply). |

## Boot-budget analysis

- The `LUKSEOF` stage runs inside cloud-init `runcmd` on first boot; the provision unit (`soleur-inngest-provision.service`) is `After=inngest-luks-open.service` and bounds its own attempts (~54 min bounded sum + ~11 min margin ≈ 65 min, per the unit's own accounting comment at `cloud-init-inngest.yml` ~1395-1408). A ≤ ~330 s wait inside runcmd finishes before the provision unit's clock starts and inside any boot-completion watch window.
- The wait overlaps `terraform apply`'s own attach wait: apply blocks until `hcloud_volume_attachment` completes, so most of a late attach is already paid by the apply before first boot's runcmd reaches the stage. Post-attach tail on the sibling class was ≤ ~56 s.
- Reopen on normal boots ≥2: the volumes are attached; the extended bound is never consumed (present device returns on the first probe).
- Worst-case added boot time when the attachment is genuinely lost: ~300 s + settle overhead per missing device (canonical first, then staging), before the same FATAL the code emits today — a louder, later, identical failure mode, inside the provision unit's retry envelope.

## Implementation Phases

**Phase 0 — RED first (`cq-write-failing-tests-before`).** In `inngest-redis-luks.test.sh`: update T1.6 to the new mechanism pin (both readers), add rows for `attach_wait_invalid`, the `env -u` strip, `ensure_mount` (mountpoint check, fstab line, `mount`, `reopen_mount` emit, noop-path coverage) — expect RED. In `inngest-redis-luks-loopback.test.sh`: swap the bound rebind for the seam env, add the `udevadm` recorder stub, add `/mnt/data` + `/etc/fstab` rebinds to `render_reopen`, add the late-attach and BOOT2 self-heal arms — expect RED on the new arms.

**Phase 1 — the bounded wait.** Rewrite `wait_dev` in both readers to the shared counted-bounds shape (seam, validation, probe-once, settle+sleep pass, emit on wait/resolution); insert `/usr/bin/env -u INNGEST_LUKS_ATTACH_WAIT_S` in the `LUKSEOF` invocation; update the three extraction anchors to pin the strip.

**Phase 2 — the self-heal.** Add `ensure_mount` + its fstab write to `inngest-luks-open.sh`; call it on each arm (pointer canonical, pre-cutover crypto_LUKS and ext4-skip, staging); update the header contract comment and the unit `Description=`; new emit tokens `reopen_mount` / `reopen_fstab` / `reopen_mount` fail detail.

**Phase 3 — suites green + floors.** Re-run `inngest-redis-luks.test.sh` (floor 64 → measured), `inngest-redis-luks-loopback.test.sh` under sudo (floor 85 → measured), plus `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `inngest-host.test.sh`, `inngest.test.sh`, `inngest-luks-cutover.test.sh`, `inngest-luks-sole-copy.test.sh`, `journald-config.test.sh`; `bash apps/web-platform/infra/inngest-userdata-budget.sh --json` (headroom 13,076 B pre-change — record post).

**Phase 4 — docs.** ADR-142 amendment via `soleur:architecture`; runbook entry in `inngest-luks-cutover-6894.md`; confirm `bash plugins/soleur/test/c4-count-parity.test.sh` green (no C4 edit).

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml` — `wait_dev` bodies (runcmd stage + reopen script), `env -u` on the LUKSEOF invocation, `ensure_mount` + fstab write + calls in `inngest-luks-open.sh`, unit `Description=` + header contract comment.
- `apps/web-platform/infra/inngest-redis-luks.test.sh` — T1.6 mechanism repin (both readers), new rows (`attach_wait_invalid`, `env -u` strip, `ensure_mount`, emit pins), extraction anchors for the invocation, floor.
- `apps/web-platform/infra/inngest-redis-luks-loopback.test.sh` — seam env passing, `udevadm` stub, `render_reopen` `/mnt/data` + `/etc/fstab` rebinds, late-attach + BOOT2 self-heal arms, floor.
- `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` — dated amendment.
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` — dated entry.

## Files to Create

None in source. Spec artifacts only: `knowledge-base/project/specs/feat-one-shot-10217-inngest-luks-attach-race/{decision-challenges.md,tasks.md}`.

Not edited, by design: `cloud-init-git-data.yml` / `git-data-bootstrap.sh` (sibling PR #10210's scope — per the brief's explicit constraint), `inngest-redis-bootstrap.sh` and the mount guard (stays a pure refusal), `inngest-luks-cutover.sh` (already maintains envfile + fstab together), `inngest-provision-rehearsal/*` (no hash gate forces a re-rehearsal; see Dependencies & Risks), `.github/workflows/*` (no budget change needed).

## Open Code-Review Overlap

None. Queried open `code-review` issues (200 limit) for each file in Files to Edit on 2026-10-13; zero matches.

## User-Brand Impact

**If this lands broken, the user experiences:** scheduled agent work that never fires — the sole Inngest scheduler dark for the length of a host-replace cycle (the incident measured a ~40 min scheduler gap plus one wasted host cycle; armed future reminders are sole-copy state in the AOF, #9879).
**If this leaks, the user's [data / workflow / money] is exposed via:** the opposite failure — the mount guard being bypassed would put the AOF on the ephemeral root disk while every artifact claims LUKS at rest; this plan does NOT relax the guard (it heals the mount so the guard passes honestly), and the Guard Contract mutation-tests the fail-closed wait.
**Brand-survival threshold:** `aggregate pattern` (planner default, challengeable; recorded as taste in decision-challenges.md). Reason: the blast radius is fleet-wide scheduler availability (aggregate), not single-user data; the change is fail-closed by construction — a broken wait still ends in the same named FATAL and a broken self-heal leaves the unit `failed` and phoned home.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_INNGEST_BOOT_STAGE bootstrap-done row (per boot, iid-keyed) + SOLEUR_INNGEST_LUKS_STAGE stage=<name> rows incl. the new reopen_mount emit; inngest-luks-reopen-armed / reopen-ARM-FAILED phone-home on first boot"
  cadence: "once per boot (runcmd stage + enable --now arm); reopen emits per boot >= 2"
  alert_target: "Better Stack soleur-inngest source (journald -> Vector Source 4, tag allowlisted in vector.toml, asserted by journald-config.test.sh); provision unit's provision-attempt-exit-* phone-home"
  configured_in: "apps/web-platform/infra/cloud-init-inngest.yml (luks_emit, emit, inngest-boot-phone-home.sh calls)"
error_reporting:
  destination: "Better Stack via logger -t inngest-luks-stage + /usr/local/bin/inngest-boot-phone-home.sh; the runcmd detail /run/inngest-luks-stage.log shipped as the fatal's cause"
  fail_loud: "unchanged named FATALs after the bound (pointer/pre-cutover device wait, staging probes); new attach_wait_invalid FATAL on a bad seam value; reopen-mount failure -> unit failed -> inngest-luks-reopen-ARM-FAILED"
failure_modes:
  - mode: "canonical volume never attaches within the bound"
    detection: "SOLEUR_INNGEST_LUKS_STAGE stage=pointer_device_wait|device_wait rc=1 + inngest-luks-FAILED phone-home — identical sentence to today"
    alert_route: "Better Stack row; provision unit never reaches bootstrap-done"
  - mode: "invalid INNGEST_LUKS_ATTACH_WAIT_S reaches the stage"
    detection: "FATAL attach_wait_invalid before the first probe; the seam is also stripped from the doppler run env (Guard 3)"
    alert_route: "same FATAL path; structural suite pins the strip"
  - mode: "mapper open but mount missing on a later boot"
    detection: "reopen_mount emit (heal observed) or reopen_mount fail -> unit failed -> journald row; Redis mount guard remains the last line. Once-per-boot cadence: a dedicated alert on the heal, if ever added, needs its OWN alert rule — a once-only signal must not share a throttle window with a repeating sibling (#9176 class)"
    alert_route: "Better Stack stage rows; inngest-luks-reopen-ARM-FAILED on first boot"
  - mode: "wait loop silently succeeds on a miss / self-heal removed"
    detection: "loopback arms + structural pins + mutation matrix below (CI), not a runtime signal"
    alert_route: "CI infra-validation job fails the PR"
logs:
  where: "journald tag inngest-luks-stage -> Vector Source 4 -> Better Stack soleur-inngest source; /run/inngest-luks-stage.log (0600) on first boot"
  retention: "Better Stack source retention (inherited, not re-measured); /run is tmpfs, per-boot"
discoverability_test:
  command: grep SOLEUR_INNGEST_LUKS_STAGE apps/web-platform/infra/cloud-init-inngest.yml
  expected_output: SOLEUR_INNGEST_LUKS_STAGE
```

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_volume.inngest_redis_luks (SOLE COPY — the Redis AOF store, mapper inngest-redis at /mnt/data)"
    mechanism: luks
    evidence: "apps/web-platform/infra/cloud-init-inngest.yml LUKSEOF stage (cryptsetup luksFormat/luksOpen, passphrase via Doppler env, stdin only) and inngest-luks-open.sh (staged 0600 key); unchanged by this plan — only WHEN/HOW RELIABLY the same device is opened and mounted changes"
    defends_against: "a seized or RMA'd disk; a raw volume snapshot"
    does_not_defend: "a leaked Doppler token or Terraform-state reader holding INNGEST_REDIS_LUKS_KEY; an unlocked running host; a root compromise of the host; ciphertext+header loss (sole copy, no backup — residual named in model.c4)"
    disclosed_as: "ADR-142 + encryption-posture ledger (internal)"
    live_verification: "available: probe row data_mount_src=/dev/mapper/inngest-redis + data_mount_devid pin (the healthy replace measured data_mount_devid=scsi-0HC_Volume_106903269, redis_keys=3939); the new reopen_mount emit adds heal evidence to the same row family"
in_transit: []
```

No new store and no new cross-component/network connection are introduced; the change alters guest-local boot behaviour on an existing store.

## Guard Contract

### Guard 1 — Every device wait is bounded, counted and fail-closed (both readers)

**Property.** Every `wait_dev` call site ends either in the device satisfying the whole `-b <path> && size>0` predicate within the bound, or in the same refusal the site has today (canonical FATAL / `staging_absent` / `reopen_device_wait` / `reopen_staging_absent`), and a timeout can never read as success.

**Assembly.** The single `wait_dev` body in each of the two readers — the `LUKSEOF` runcmd stage (sites: `pointer_device_wait`, `device_wait`, `staging_wait`) and `inngest-luks-open.sh` (pointer, pre-cutover, staging) — plus the `INNGEST_LUKS_ATTACH_WAIT_S` seam validation (chokepoint: the function itself; all six sites flow through it).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | after the bound, `wait_dev` returns 0 on timeout (the fail-open the whole change forbids) | RED: never-appears fixture exits 0 / mapper opened on an absent device |
| 2 | the canonical site's post-wait refusal removed (carries on after timeout) | RED: absent-device arm reports success instead of the named FATAL |
| 3 | helper never called at the reopen sites (dispatch removed from one of the two readers) | RED: reopen late-attach arm FATALs instead of proceeding — the second-reader coverage is dead |
| 4 | bound ignored (hard-coded huge loop), seam dropped | RED: small-bound fixture exceeds the sleep-call cap |
| 5 | predicate evaluated once, then only sleeps (no re-probe per pass) | RED: late-attach fixture never proceeds |
| 6 | `udevadm settle` removed from the pass | RED: calls.log carries no `udevadm|settle` before the first retry |
| 7 | invalid seam falls back to 300 instead of FATAL | RED: `abc`/`-5`/empty fixtures expect `attach_wait_invalid` |
| 8 | predicate loosened to `-e` (drops block-special and size > 0) | RED: zero-size / regular-file fixtures still FATAL |

**Harness rows.** (a) Suite-side edit that must RED it: make the `sleep` stub never materialise the late link and assert the FATAL row still passes only because of the refusal (paired late-link row goes RED on a stub that makes everything pass). (b) Must-PASS inputs that are not canonical: link lands on the 1st sleep, on the last pass before the bound, through a symlink chain, and bound 0 with the link already present (one probe, zero sleeps). (c) Floors: structural suite `executed >= <measured>` and loopback `>= <measured>`, moved only by measured count.

**Anchor.** Floors are counts paired with set identity (named arms). What must move outside the commit for a weakening to pass: the rendered user_data the real host boots is produced by terraform's own templatefile in `inngest-userdata-budget.sh` — a semantic no-op edit still re-measures — and `infra-validation.yml` runs both suites (loopback under sudo) on every PR.

### Guard 2 — A mapper-open-but-unmounted state converges (the self-heal)

**Property.** On any boot where the canonical mapper (or staging mapper, or the pre-cutover plaintext device) is verified and opened by the reopen but its mountpoint is not a mount, `ensure_mount` leaves the fstab line AND the mount in place — and a state where nothing needed doing costs nothing.

**Assembly.** `inngest-luks-open.sh`: `ensure_mount` itself, its call sites on all four arms (pointer canonical, pre-cutover crypto_LUKS, pre-cutover ext4-skip, staging), and the fstab write it performs (chokepoint: `ensure_mount` — every arm flows through it; the `open_as` noop path included).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `ensure_mount` deleted or never called on the pointer arm (dispatch removed — the incident's shape re-introduced) | RED: BOOT2 self-heal arm — mapper open, no mount, no fstab — ends unmounted |
| 2 | `mountpoint -q` short-circuit removed but mount call kept (re-mount every boot — benign-looking drift) | RED: mount-on-already-mounted arm counts a second mount attempt |
| 3 | fstab write skipped, mount performed (mount heals the boot, not the next one) | RED: self-heal arm's fstab carries no `/mnt/data` line |
| 4 | mount performed without the fstab-driven form (source/options re-typed diverging from the stage's line) | RED: fstab line pins `ext4 defaults,nofail 0 2` and the suite diffs it against the stage's own line |
| 5 | `ensure_mount` called only when `open_as` actually opened (noop path skips it — the incident's exact post-state survives) | RED: already-open arm asserts the mount still happens |
| 6 | mount failure ignored (`|| true`) | RED: unmountable-source arm must `fail reopen_mount`, not report a heal |

**Harness rows.** Must-PASS: normal boot with fstab line present and mount present (zero writes, zero emits beyond reopen_noop); staging self-heal on `/mnt/data-luks` — a second member after the compliant first.

**Anchor.** The suite pins both the emit (`reopen_mount`) and the on-disk fstab; the external anchor is the provision unit's `After=inngest-luks-open.service` ordering plus `RequiresMountsFor=/mnt/data` on `inngest-redis.service` — a heal that doesn't converge still hits the unchanged Redis guard, never a silent serve.

### Guard 3 — The test seam cannot reach production from Doppler

**Property.** `INNGEST_LUKS_ATTACH_WAIT_S` is removed from the `LUKSEOF` stage's environment before the heredoc reads it.

**Assembly.** The single `doppler run … -- /usr/bin/env -u … bash -s <<'LUKSEOF'` invocation in `cloud-init-inngest.yml`; the extraction anchors in both LUKS suites (which now pin the strip line).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `-u INNGEST_LUKS_ATTACH_WAIT_S` removed or misspelled | RED: invocation pin row names the exact strip |
| 2 | `env -u` moved before `doppler run` (strip then re-inject) | RED: strip sits after `--` in the invocation |
| 3 | invocation reshaped so the anchor extracts nothing (guard's own dispatch) | RED: extraction row reports a missing `env -u … bash -s` match |

**Harness rows.** Must-PASS: the strip list extended with additional `-u` names (order not pinned). Anchor: the reopen script needs no strip (its env is the two EnvironmentFiles the stage writes) — a structural row pins that claim by grepping the unit for `EnvironmentFile=` exactly.

## Infrastructure (IaC)

### Terraform changes

None — no `.tf` file changes. The deliverable is `cloud-init-inngest.yml` (rendered through terraform's own `templatefile` in `inngest-host.tf` and `inngest-provision-rehearsal/rehearsal.tf`) plus suites and docs. No new provider, variable, secret or resource.

### Apply path

(a)+(b) hybrid: code-only at merge; the change reaches the host on the next sanctioned `inngest-host-replace` dispatch (`user_data` is ForceNew — the running host does not re-provision at merge). No downtime is introduced by the PR itself; each dispatch is an operator authorization, not a plan step.

### Host fan-out

No `terraform_data` SSH provisioner is introduced. The inngest host is the only consumer of this template (`inngest-provision-rehearsal` renders the same file on a throwaway host when next dispatched).

### Distinctness / drift safeguards

`inngest-userdata-budget.sh` re-measures the stored payload on every infra PR (pre-change headroom 13,076 B of 32,768). The rehearsal root's plan-shape gate (`inngest-provision-plan-shape.sh`) is untouched.

### Vendor-tier reality check

Hetzner attach latency is variable (~17–125 s measured across this estate, ~80 s in this incident); the 300 s bound is a bound, not a claim about Hetzner.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-142 (`soleur:architecture`, in-PR task): a dated amendment recording (a) first boot may begin before volume attachments finish — measured iid 170091264 — and both device readers now wait under a counted, fail-closed bound (seam `INNGEST_LUKS_ATTACH_WAIT_S`, default 300, stripped from the production invocation); (b) the boot-reopen contract is now "open, then complete the mount for the arm it verified" — never formats, never mkfs — so a lost first-boot race converges instead of requiring a host replace.

### C4 views

No C4 change. Checked all three model files (`model.c4`, `views.c4`, `spec.c4`) on 2026-10-13: external human actors — none new; external systems/vendors — none new (Hetzner, Doppler, Better Stack, Sentry already modeled); containers/data-stores — none new (`inngest` and `inngestRedis` already carry the LUKS/sole-copy/pointer description this plan only makes more reliable); actor↔surface access relationships — none changed (the reopen unit is internal to the already-modeled `inngestRedis` container). `bash plugins/soleur/test/c4-count-parity.test.sh` green post-edit.

### Sequencing

The amendment describes the target state and ships in this PR; ADR-142's existing status handling is unchanged.

## Downtime & Cutover

- **Offline-inducing operations:** only the post-merge, separately authorized `inngest-host-replace` dispatch — the existing sanctioned path (`-target=` set: server + network attachment + `hcloud_volume_attachment.inngest_redis_luks`, never the volume). This PR changes code and tests only.
- **Surface affected:** the Inngest scheduler host (durable trigger layer). The AOF is sole-copy LUKS; a replace preserves the volume and re-reads the key.
- **Zero-downtime evaluation:** blue-green is not available for a single-host scheduler; the change cannot reach the host any way but a replace. The fix must land before the NEXT replace so that replace cannot lose the race again.
- **Residual downtime acceptance:** none requested; the dispatch is gated on an operator go-ahead naming the command. Post-fix recovery shape if a race is ever lost again: self-heal in-band (reopen completes the mount), not a second replace.

## Domain Review

**Domains relevant:** none

No cross-domain implications among the eight business domains — infrastructure/boot-code change on an internal host. Technical forks were recorded as `pending - assumed:` rows in `decision-challenges.md` (no Agent tool on this harness); a `soleur:engineering:cto` ruling at review supersedes them. Product/UX gate: no UI-surface file in Files to Edit/Create — the mechanical override did not fire. GDPR gate: no schema/auth/API-route/.sql surface and none of the four expansion triggers applies.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "[issue #10217] Extend the `pointer_device_wait` bound and/or poll the attach state rather than a fixed short wait" | Proposed Solution 1; Files to Edit `cloud-init-inngest.yml` | mapped |
| 2 | "[issue #10217] consider making the reopen path able to complete the mount (or a one-shot late-mount unit) so a lost first-boot race self-heals instead of requiring a host replace" | Proposed Solution 2; Guard 2 | mapped |
| 3 | "[brief] Do NOT touch cloud-init-git-data.yml or git-data-bootstrap.sh … MAY read that branch's diff … to mirror its remedy pattern" | Files-to-Edit exclusion note; Research Insights precedents | mapped |
| 4 | "[brief] Same attach-race class as open issue 6442 … context for the design, NOT a work target; do not claim to close it" | frontmatter `closes:` names only 10217; Context note | mapped |
| 5 | "[brief] PARKED PR 10081 … expect textual overlap; do not merge it, rebase onto it, or let it drive scope" | Reconciliation row 6; Risks | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Bounded counted wait in both readers | "Extend the `pointer_device_wait` bound and/or poll the attach state rather than a fixed short wait" | asked |
| Reopen completes the mount | "making the reopen path able to complete the mount … so a lost first-boot race self-heals" | asked |
| Env seam + `env -u` strip | "poll the attach state rather than a fixed short wait" (sibling's tested shape — "mirror its remedy pattern for the inngest LUKS stage") | inferred — justification: testability without wall-clock + the sibling's proven shape, which the brief tells this plan to mirror |
| Suite/harness updates + floors | "mirror its remedy pattern" (the sibling's remedy is inseparable from its mutation-tested suites) | inferred — justification: `cq-write-failing-tests-before` + the loopback suite's own rebind machinery demands co-movement |
| ADR-142 amendment + runbook entry | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — the reopen contract change is an architecture record, not a follow-up |
| staging/pre-cutover arm coverage | — | inferred — justification: same race class on sibling volumes; the shared helper makes exclusion impossible anyway (one body) |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 5 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `grep -n 'INNGEST_LUKS_ATTACH_WAIT_S-300' apps/web-platform/infra/cloud-init-inngest.yml` shows the seam-with-300-default in BOTH `wait_dev` bodies (runcmd stage and reopen script), and `grep -c 'udevadm settle' apps/web-platform/infra/cloud-init-inngest.yml` >= 2.
- [ ] The `LUKSEOF` invocation reads `doppler run … -- /usr/bin/env -u INNGEST_LUKS_ATTACH_WAIT_S bash -s` and every extraction anchor in the two LUKS suites matches the new line.
- [ ] `inngest-luks-open.sh` (as rendered) calls `ensure_mount` on all four arms (pointer canonical, pre-cutover crypto_LUKS, ext4-skip, staging) and on the `open_as` noop path; the only `luksFormat`/`mkfs` tokens in the script remain inside comment lines — no invocation is added (presence pin, not an absence grep: the contract comment itself contains the word `mkfs`).
- [ ] `bash apps/web-platform/infra/inngest-redis-luks.test.sh` exits 0 with its floor at the measured count; T1.6 passes naming the new mechanism in both readers.
- [ ] `sudo bash apps/web-platform/infra/inngest-redis-luks-loopback.test.sh` exits 0 in CI with its floor at the measured count, including the late-attach arm (verdict equals on-time) and the BOOT2 self-heal arm (mapper open → `/mnt/data` mounted + fstab line + `reopen_mount` emitted).
- [ ] `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `inngest-host.test.sh`, `inngest.test.sh`, `inngest-luks-cutover.test.sh`, `inngest-luks-sole-copy.test.sh`, `journald-config.test.sh` all exit 0.
- [ ] `bash apps/web-platform/infra/inngest-userdata-budget.sh --json` reports `stored` <= 32,768 (pre-change stored 19,692 / headroom 13,076 — post-change headroom recorded in the PR).
- [ ] `git diff --name-only origin/main...HEAD` contains neither `cloud-init-git-data.yml` nor `git-data-bootstrap.sh` (sibling-scope constraint).
- [ ] ADR-142 carries a dated amendment for the wait + reopen-mount change; `inngest-luks-cutover-6894.md` has a dated entry; `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.
- [ ] PR body's FIRST line answers "does merging this mutate production?" (`no — user_data is ForceNew; inert until the next sanctioned inngest-host-replace`), says `Closes #10217`, does NOT reference closing #6442, and lists `inngest-host-replace` as an unrun operator-gated dispatch (no dispatch, apply, Doppler write, or reboot was run from this branch).

## Test Scenarios

- Given the canonical by-id link is absent on probe 1 and materialises after the 2nd `sleep`, when the stage runs under the seam bound, then the stage proceeds with the on-time verdict and `udevadm settle` ran before each retry. (`loopback`, integration)
- Given the link never materialises, when the stage runs under a small seam bound, then it ends in the SAME named FATAL — no mapper opened, no fstab line, nothing past the wait ran. (`loopback`, integration; regression for the incident shape)
- Given the seam is invalid (`abc`, `-5`, empty), then `attach_wait_invalid` fires BEFORE the first probe. (`loopback`/`structural`, unit)
- Given boot 2 where the mapper reopens but `/mnt/data` was never mounted and fstab has no line, when the reopen runs, then it emits `reopen_mount`, writes exactly one `/mnt/data` fstab line, and the mountpoint holds. (`loopback`, integration — the incident's heal)
- Given boot 2 where the mapper was ALREADY open (noop path) but unmounted, when the reopen runs, then `ensure_mount` still mounts — the incident's exact post-state converges. (`loopback`, integration)
- Given a normal boot where the fstab line and mount already exist, when the reopen runs, then `ensure_mount` costs zero mounts and zero fstab writes. (`loopback`, integration)
- Given the staging volume attaches late, then `staging_wait` tolerates it; absent after the bound still emits `staging_absent` (never a FATAL change). (`loopback`, integration)
- Given the structural suite, then T1.6 names the counted bound + seam + settle in BOTH readers and the `env -u` strip pins the invocation. (`structural`, unit)
- Verification (read-only, local, no dispatch): `bash apps/web-platform/infra/inngest-redis-luks.test.sh`, `sudo bash …/inngest-redis-luks-loopback.test.sh`, `bash apps/web-platform/infra/inngest-userdata-budget.sh --json`.

## Dependencies & Risks

- **PARKED PR #10081 conflict surface.** It strips the pre-cutover/plaintext arms this plan also edits (shared `wait_dev` body; the reopen's ext4 block). Mitigation: keep pre-cutover edits minimal (shared body + one `ensure_mount` call); whichever PR merges second rebases; this plan does NOT touch `inngest-host.tf`, `inngest-redis-luks.tf`, or the rehearsal root that #10081 edits, narrowing the overlap to the one file.
- **Reopen-mount on a sole-copy store.** The reopen mounts only devices it verified `crypto_LUKS` (or the pre-cutover ext4 device under `expect_luks=false`) — never formats, never mkfs, never picks a device the pointer does not name. The Redis mount guard still stands as the last line.
- **Bound sizing.** 300 s ≈ 3.75× the measured 80 s attach; the sibling used 300 s vs 125 s. A slower attach still ends in the same named FATAL — the failure mode is unchanged, not worse.
- **Provision-rehearsal not re-run.** Unlike git-data's hash-bound rung-2 gate, the inngest rehearsal is a manually-dispatched, artifact-only run with no payload interlock; the loopback suite (real dm-crypt devices) is the behavioral authority for this change. An optional `inngest-provision-rehearsal.yml` dispatch post-merge is the paid end-to-end check — recorded, not required (D6). If a later change wants an enforced forced-attach-delay proof, the rehearsal root already carries a forced-race precedent (#9175) and the sibling's `rehearsal_attach_delay_s` knob is the shape to copy — out of this PR's scope.
- **userdata budget.** Headroom 13,076 B pre-change; the added wait/mount logic plus emit lines are ~60–90 rendered lines — re-measure (AC).
- **`enable --now` semantics on an aborted stage.** The reopen arm runs even when the stage aborted (#9939 design) — that is what makes boot-1 self-heal work; a reopen-mount failure there surfaces as `reopen-ARM-FAILED` phone-home, which is the intended loudness.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- The two `wait_dev` bodies live in DIFFERENT files-in-one-file (the `write_files` payload and the `LUKSEOF` runcmd item) — the file's own comment already warns the bound must not drift between readers; edit both in the same diff and pin both in T1.6.
- Terraform's template unescape is EXACTLY two transforms (`$${`→`${`, `%%{`→`%{`); the reopen script lives inside `write_files`, so every `$` not followed by `{` is literal — write a bare `$` for everything and the doubled form only where a brace follows (the #6894 syntax-error incident).
- The `mount` in `ensure_mount` is fstab-driven (`mount <mp>`) — re-typing the source/options duplicates what the fstab line already says and invites drift (Guard 2 row 4 pins it).
- The `-lt N` sed rebind in `render_stage`/`render_reopen` is replaced by the seam env — a rebind left in place would silently match nothing once the literal is gone (the render's own unsubstituted-token check would catch only a survivor, not a missing mechanism).
- Suite floors (`executed >=`) move by MEASURED count after the arms land — never by estimate; the loopback floor's own comment requires accounting for any delta arm by arm.
- `env -u` must sit INSIDE the `doppler run` invocation (after `--`); outside it strips then re-injects.
- Do not add `ConditionPathExists` to `inngest-redis.service` (deliberately unconditioned, #9962) and do not weaken the mount guard — it is the last line this plan keeps honest.
- The `inngest` and `inngest-provision-rehearsal` terraform roots render the SAME template; the rehearsal's `inngest_doppler_config` is a scratch config — the `env -u` strip is correct there too (a rehearsal-only key must not lower the bound).
- Mutation-matrix rows are applied to the EXTRACTED scripts in a scratch copy (the suites' own extraction outputs under `$FX*`), never by flipping matchers over the real file — the loopback suite's helpers include process/file teardown (`cryptsetup close`, `umount`, `rm`); an inverted match in an ancestor-walking helper is the known session-killing mutant class.
- Rollback is "replace from the prior template revision": `inngest-host-replace` always rebuilds the host, so reverting the template and dispatching a replace restores the old boot code with state intact on the volume. The failed-host path is unchanged — no rollback runbook beyond the existing replace gate.
