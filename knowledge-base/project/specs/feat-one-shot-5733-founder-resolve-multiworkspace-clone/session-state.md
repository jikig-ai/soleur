# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-30-fix-agent-readiness-absent-git-strand-and-per-workspace-clone-plan.md
- Status: complete (broadened to D0 clone-landing after operator decision)

### Errors
None blocking. Transient API rate-limit on a forensic sub-agent (re-launched); a "commit on main" harness guard intermittently rejected multi-line commit messages (worked around with single-line). FS-divergence forensic folded as the /work Phase-0 root-cause gate (not a blocker).

### Decisions
- Live forensics: workspace-reconcile-on-push FIRES + selects 754ee124 on every push (45 events/48h), reaches the clone gate, yet ensureWorkspaceRepoCloned emits ZERO telemetry, .git stays absent, repo_status stays false-`ready`. reconnect (/api/repo/setup) has NEVER landed the repo (operator).
- Root cause call site: cold path already clones in-process at cc-dispatcher.ts:1987 (keyed on the workspace's own install via resolve_workspace_installation_id, gated on is_workspace_member ANY role — the "member-null benign-skip" was a phantom). The defect: the :1987 clone OUTCOME is SWALLOWED. Given zero clone-telemetry + absent-at-agent, the remaining landing bug is filesystem/mount path divergence — no clone change fixes that; it is the /work Phase-0 root-cause gate.
- D0 (revised, review-triad): consume the existing :1987 clone outcome LOUDLY — distinct repo_clone_failed event, reason via sanitizeGitStderr (no token / no /workspaces/<uuid> PII into captureException). NOT a new clone site; NOT a service-role column read (keeps cc-dispatcher service-role-free).
- Data-integrity F4 gating: flip repo_status→error ONLY on solo/owner path (workspaceId===userId) AND after a post-clone .git-absence CAS (never let a member flip a co-owned workspace's shared status; never clobber a concurrent ready). Emit-only on team path. Fixes the pre-existing graftReadyButGitAbsent→failHonestly F4 inconsistency.
- D2 (un-strand, correct regardless of FS verdict): evaluateAgentReadiness treats absent/dir-invalid as a strand → emit + honest-block (phase-scoped so reconcile doesn't pollute the soak signal). D3: isInSandboxRevParseStrand matches stderr-suppressed empty output. D1: founder/membership-independence regression test.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: Explore; general-purpose ×2 (prod forensics + FS-divergence); review triad architecture-strategist + data-integrity-guardian + security-sentinel + earlier code-simplicity-reviewer
