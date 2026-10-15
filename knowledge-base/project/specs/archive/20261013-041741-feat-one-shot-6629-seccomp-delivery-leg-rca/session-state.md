# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-18-rca-seccomp-delivery-leg-host-present-false-plan.md
- Status: complete

### Errors
None. (learnings-researcher background agent still running at completion; its corroborating findings — #4927/#4928 fresh-host precedent, hr-fresh-host-iac, probe-first discipline — were already independently folded in. Deepen-plan gates 4.5–4.9 passed.)

### Decisions
- Probe-first RCA structure (heeds #6536 sharp edge): Phase 1 self-pulls the diagnosis (Better Stack boot markers, /hooks/deploy-status history, R2 state, apply/drift run logs — NO SSH) and ships alone; no hypothesis is CONFIRMED/REFUTED until its discriminator datum is pulled. Fix ships only after Phase 1 licenses it.
- New H0 (architecture review, checked first): the /hooks/deploy-status probe may have read warm-standby web-2 (no SSH provisioners by design) since tunnel ingress was a web-1/web-2 coin-flip until #6595 pinned it the day after the incident. If so, host_present=false is expected, not drift.
- In-repo defect: seccomp profile's only writer is the SSH provisioner with no boot-time delivery, on a host running ignore_changes=[user_data]; apparmor has a hash-only trigger (no server_id). Multiple non-merge, non-item-4 paths to host_present=false exist (three silent SSH-leg skip paths) — fires the #6628 build-gate.
- Fix reshaped by review triad (two P0s): (1) write_files-baking the 16,615-byte profile is a CI-hard-blocker (WEB_GZIP_BUDGET) → use image-bake + boot-extraction path (#5921/ADR-080); (2) fresh-host container started unenforced regardless of file presence → add --security-opt to cloud-init docker run + fail-closed, track seccomp_profile_loaded_matches_host (not just host_present), hard-require apparmor parity. ADR retargeted from ADR-079 to new ADR-122 anchored to ADR-080.
- Brand threshold single-user incident (strictest, requires_cpo_signoff): kept; blast radius of a realized sandbox escape is cross-tenant on shared web-1.

### Components Invoked
- Skill soleur:plan
- Skill soleur:deepen-plan
- Agent soleur:engineering:research:learnings-researcher (background)
- Agent soleur:engineering:review:architecture-strategist
- Agent soleur:engineering:review:security-sentinel
- Agent Explore (network-outage L3→L7 deep-dive)
- emit_incident hr-ssh-diagnosis-verify-firewall (network-outage gate telemetry)
