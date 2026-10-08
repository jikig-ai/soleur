---
title: "Spec — feat-5863-tenant-fs-isolation (ADR-075 Option B: outer per-session bwrap wrap)"
date: 2026-10-08
issue: 5863
brainstorm: knowledge-base/project/brainstorms/2026-10-08-tenant-fs-isolation-brainstorm.md
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# Spec — True per-tenant filesystem isolation for the Concierge agent

Tracking issue: #5863. Epic: #6641 (isolation bar = #5862 + #5863 + #4672).
Baseline: PR #9709 (merged 2026-10-07) — vendored CLI 2.1.284 deny-then-restore
with constant parent `denyRead`. Folds in #9723 and #9725 by construction.

## Problem Statement

The Concierge agent shares one container, one node process, one uid, and one
`-v /mnt/data/workspaces:/workspaces` mount across all tenants. The #5862
baseline hides sibling *content* (`--tmpfs /workspaces`) but siblings remain
*observable*: mount-table/stat existence of the parent tmpfs, real `/proc` via
the argv-tail `--bind /proc /proc` (#9723 — a same-uid cross-tenant
`/proc/<pid>/environ` credential channel), shared `/tmp` and `~/.npm/_logs`/
`~/.claude` scratch, and a deny root that diverges from the workspace resolver
root after the git-data cutover (#9725). File tools (Read/Write/Edit/Glob/Grep/
LS/Notebook*) execute inside the **unsandboxed** `claude` CLI child, guarded
only by the in-process realpath hook — bwrap never bounds them. Arms-length
hosted tenants are coming; the re-evaluation trigger has effectively fired.

## Goals

- G1: No sibling workspace is present — content, existence, or mount-table
  entry — on **any** agent filesystem surface (sandboxed Bash AND file tools).
- G2: Session `/proc` shows only the session's own processes (closes the
  cross-tenant environ channel; #9723).
- G3: Isolation derives the mount table from `workspacePathForWorkspaceId` /
  `getWorkspaceWorktreeRoot()` — correct under both `WORKSPACES_ROOT` and the
  post-cutover `WORKTREE_ROOT` layout (closes #9725).
- G4: The isolation property is authored by us (outer argv), not delegated to
  the vendored SDK builder — immune to SDK-bump argv drift (#5849 class).
- G5: Post-ship, the `/workspaces` `denyRead` machinery simplifies per the
  issue's payoff (deny becomes unnecessary; `allowWrite:[workspacePath]`
  alone gives rw with zero leak). File-tool realpath hook downgrades to
  defense-in-depth.
- G6: Realized-state verification — an in-sandbox probe asserts the actual
  mount table / `/proc` contents, dark-launched before it gates a deploy.

## Non-Goals

- Per-tenant subprocess/container executor (kernel/credential boundary,
  subsumes #9543-class residuals) — deferred follow-up issue, staged behind
  capacity work.
- In-process orchestrator isolation (BYOK leases, session state in the shared
  node heap) — out of scope; a separate residual class.
- #9724 (canary gate coverage on the *existing* capture machinery) — stays an
  independent issue; this spec adds its own canary requirement.
- Credential broker (#9543) — env-token denial beyond the existing
  `credentials.envVars` deny list is unchanged.
- Nested-userns suppression inside the agent sandbox (#8752 residual).

## Functional Requirements

- FR1: `Options.pathToClaudeCodeExecutable` points at a repo-owned wrapper that
  `exec`s the real `bwrap` binary **by absolute path** (never PATH-resolved —
  the #8752 shim's NEWUSER filter must not inject into the outer namespace)
  around the vendored `claude` executable.
- FR2: The outer mount table contains the tenant's own workspace at its real
  resolved path and **no other entry under the workspaces parent** — no
  `--ro-bind / /`-style whole-fs base that could expose siblings or
  future-created siblings.
- FR3: The outer wrap creates a new PID namespace (`--unshare-pid`) so any
  procfs visible inside is scoped to the session's own processes.
- FR4: Per-session private `/tmp` and `$HOME` scratch — no cross-tenant shared
  scratch (`/tmp/claude-1001`, `~/.npm/_logs`, `~/.claude` session dirs).
- FR5: The inner SDK sandbox (`buildAgentSandboxConfig` + inner bwrap) keeps
  working unchanged inside the outer namespace, including `--unshare-net` +
  socat egress proxying and the #8752 PATH-shim (fd hygiene + nested-userns
  filter) on the *inner* layer.
- FR6: An in-sandbox realized-state probe asserts no sibling-bearing mount and
  session-scoped `/proc` — emitted via the `feature:agent-sandbox` Sentry
  channel; dark-launched (non-blocking) before it can gate a deploy.
- FR7: Failure to construct the outer namespace fails the session loudly
  (fail-closed, `sdk-startup` classifier path) — never a degraded
  less-isolated spawn.
- FR8: Wrapper passes through `--version`/probe calls, stdio transport,
  SIGTERM/`--die-with-parent` semantics, and graceful-drain behavior (ADR-078)
  unchanged.

## Technical Requirements

- TR1: Container envelope respected — no CAP_SYS_ADMIN assumed;
  `unshare(NEWUSER)`, post-userns `NEWNS`/`NEWPID`, `mount`/`umount`/
  `pivot_root` permitted by `infra/seccomp-bwrap.json`; `clone3`, `setns`,
  `open_tree`/`move_mount`/`fsopen` are EPERM and must not be required.
- TR2: Outer argv is self-authored and version-checked against the prod bwrap
  version (re-measure — 0.8.0 vs 0.12.0 evidence conflicts across issues).
- TR3: CLI filesystem footprint fully enumerated before the minimal table
  ships: plugin root, transcript dirs (`~/.claude*`), session `/tmp` dirs, MCP
  socket paths, socat proxy socket, GIT_ASKPASS script dir under the workspace
  `.git/`.
- TR4: Works under both workspace roots; any new ci-deploy `-v` mount for the
  `WORKTREE_ROOT` layout is part of the same change (not a flag-day surprise).
- TR5: The #8752 fd-hygiene prelude pattern applies to the outer spawn too.
- TR6: Observability — per-session structured log (`op` naming per repo
  convention) plus the Sentry `feature:agent-sandbox` channel for probe
  verdicts; plan must carry the `## Observability` block per
  `hr-observability-as-plan-quality-gate`.
- TR7: Art. 30 register entry in honest tense (mechanism, measurement arm,
  residuals, status `adopting` until prod-measured); no public claim until
  production measurement (#9603 discipline). `soleur:gdpr-gate` runs at plan
  Phase 2.7 and work Phase 2 exit.

## Acceptance Criteria (draft — plan refines)

- AC1: Inside an agent session (Bash AND file tools), no path under the
  workspaces parent other than the session's own workspace exists or is
  stat-able; `/proc/self/mounts` shows no sibling-derived mount.
- AC2: `/proc` inside the session lists only session processes; another
  tenant's concurrent agent process is absent.
- AC3: A sibling workspace created *after* session start is never observable.
- AC4: Shared-scratch audit: no cross-tenant readable/writable path under
  `/tmp` or `$HOME` beyond the session's own.
- AC5: Session startup failure under a broken outer wrap is loud and
  fail-closed; no degraded-isolation spawn is possible.
- AC6: Canary/diff coverage for the outer-wrap argv exists and is
  non-blocking at first deploy per `wg-dark-launch-deploy-gates`.
- AC7: `denyRead` for the workspaces root is removed or demonstrably
  vestigial post-landing (simplification or explicit residual note).

## Open Questions

See brainstorm `## Open Questions` — `pathToClaudeCodeExecutable` probe/stdio
compat, complete CLI fs footprint, prod bwrap version re-measurement,
`enableWeakerNestedSandbox` interaction.
