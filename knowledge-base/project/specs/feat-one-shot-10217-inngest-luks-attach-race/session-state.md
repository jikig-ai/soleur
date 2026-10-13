# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10217-inngest-luks-attach-race/knowledge-base/project/plans/2026-10-13-fix-inngest-luks-volume-attach-race-plan.md
- Status: complete

### Errors
- Suite-shaped `discoverability_test` failed deepen gate 4.7 on a new block (Check 10 cap detector + `0 failed` tokenization); fixed in-place to a grep-based test (verified live).
- Self-audit caught one inconsistent emit name (`reopen_fstab`); unified.
- No Agent/Task tool in planning subagent: CTO rulings recorded as `pending - assumed:` rows (D1–D7 + contract/threshold/dispatch rows) in decision-challenges.md for `soleur:engineering:cto` re-ruling; deepen fan-out ran inline with `Reviewed-Coverage: sequential-fallback` disclosure.
- `inngest-redis-luks-loopback.test.sh` needs sudo; not run (floors marked "→ measured").

### Decisions
- Bounded counted attach-wait in BOTH readers (runcmd `LUKSEOF` stage + `inngest-luks-open.sh`): `${INNGEST_LUKS_ATTACH_WAIT_S-300}` validated before first probe; probe-once at bound 0; `udevadm settle --timeout=5` + `sleep 5` charged 10/pass; whole-predicate retry; unchanged FATALs — mirrors the sibling `_gd_attach_wait` shape (300s ≈ 3.75× measured ~80s attach). Signature stays `wait_dev <path>`.
- Self-heal = `ensure_mount` inside the existing reopen unit (fstab line + fstab-driven mount); extends "opens ONLY; never mounts" to "opens, then completes the mount; never formats, never mkfs". ADR-142 amendment is an in-PR deliverable.
- Seam strip via `/usr/bin/env -u` inside the `doppler run` invocation (covers Doppler + shared-runcmd-shell `set -a` leak); reopen needs none.
- Gates: 4.6/4.7/4.8/4.9/4.10/4.11/4.12 pass; 4.5/4.55 fired and satisfied (telemetry emitted).
- Fix reaches hosts only via operator-gated `inngest-host-replace` (merge is inert: `hcloud_server.inngest` user_data ForceNew).

### Rulings
- cto_spawns=1 (2026-10-13): one batched soleur:engineering:cto spawn ruled D1-D8; D4 overturned the assumed env seam (literal 300, no `env -u`), D1 moved settle post-loop, D2 added `After=systemd-remount-fs.service` pin. Plan + tasks.md amended in place.

### Components Invoked
soleur:plan (manual from plugin-cache SKILL.md — no Skill tool in subagent), soleur:deepen-plan (manual sequential pass, sequential-fallback disclosure), soleur:engineering:cto (pending rulings recorded — no Agent tool in subagent)

## Review-round decisions (2026-10-13, panel fixes)

- Design-pass + panel findings folded inline: atomic fstab install in BOTH writers (`mv -f`), source-congruent fast path with stacked-mount refusal, `findmnt` pipefail guard, `backing_is` on the noop path, post-cutover-evidence refusal (`reopen_pointer_lost`), `head -1`→`tail -1` on every findmnt SOURCE read (incl. inngest-redis-bootstrap.sh guard), timeout-wrapped blockdev probe + post-settle re-probe, `/usr/bin/udevadm`, stale `30s` strings → `300s`.
- Loopback floor moved to the CI-measured 118 (run 38425065480); SH5 wrong-source arm added; sleep/systemctl recorder liveness asserted.
- Precedent attribution corrected: the mirrored shape is the sibling's `cloud-init-git-data.yml` heredoc wait, not `_gd_attach_wait`.
