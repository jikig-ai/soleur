# Decision Challenges — feat-one-shot-8743-web2-plugin-mount-fchmodat2

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Peer-verdict gate: fail vs warn in `web-platform-release.yml` | technical | Ruled by CTO agent, 2026-10-19: FAIL the `Verify peer deploy completion` step — a warn-only arm reproduces the exact silent-failure class #8743 exists to kill; `ok_peer_fanout_degraded` precedent already treats a degraded peer as report-worthy; a failed weight-0 standby is real (stale build, absent watchdog clock) even with zero serving impact. |
| Seed-repair mechanism: container-side `docker run -u 0` vs new sudoers `chown` grant | technical | Ruled by CTO agent, 2026-10-19: container-side seed — deploy is already docker-group root-equivalent by documented decision; a new exact-argv sudoers alias is a heavier terraform-delivered artifact with no additional capability. |
| cloud-init.yml seed-path rewrite | technical | Ruled by CTO agent, 2026-10-19: CUT — `ignore_changes=[user_data]` means it cannot repair the running web-2, and the container-side deploy seed makes birth-time ownership moot. |
| Per-host status route: peers merge on web-1 vs new tunnel ingress vs Better Stack query | technical | Ruled by CTO agent, 2026-10-19: `peers` merge on web-1 via private-net `:9000` GET — ADR-068 constraint (c) pre-decided this shape; per-host tunnel was ADR-068's explicitly rejected option A; a Better Stack query is async/string-fragile and needs query creds in CI. |
