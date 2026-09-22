# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8539-inngest-nic-race/knowledge-base/project/plans/2026-09-22-fix-inngest-private-nic-boot-race-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None (one plan citation pointed at a wrong learning path; fixed before commit).

### Decisions
- Option (a) inline `network {}` rejected: hcloud provider v1.63.0 attaches post-boot whenever public networking is enabled, so it cannot close the race; stale "force-replace" claim in network.tf/ADR-115 corrected.
- Option (b) alone rejected: a post-boot-attached NIC never self-configures without a reboot or an in-guest action (#6400: ~14 days; 2026-09-22: 97 s); cloud-init's hotplug handler runs only after runcmd; a reboot fallback does not re-run once-per-instance runcmd.
- Adopted (c): write_files systemd-networkd fallback for a non-eth0 virtio link (DHCP, network MTU, DNS/hostname/NTP disabled) + early `networkctl reload` + a 150 s never-abort wait before the zot login emitting exactly one event (private_nic_ok|timeout|probe_fault) with `by=`, route and links, to Better Stack and Sentry. ADR-115 amended; ADR-114 §4 marked contested.
- Delivery (replace + human-approved op=resume) stays with the orchestrator after merge; decision challenge T5 records the ride-along alternative. T1-T4, T6 in decision-challenges.md.
- Follow-up #8562 filed (bootstrap pull as a retrying unit + forced-race rehearsal). Closing keyword only for #8539; Ref for #6438, #6500, #6122, #8562.

### Components Invoked
soleur:plan, soleur:deepen-plan; research: repo-research-analyst, learnings-researcher, functional-discovery, cto, strong-model consult; plan review: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer; deepen: architecture-strategist, security-sentinel, observability-coverage-reviewer, test-design-reviewer, verify-the-negative pass.
