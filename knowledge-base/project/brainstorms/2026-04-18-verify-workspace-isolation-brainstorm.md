---
title: Verify Workspace Isolation at Process Level (MU3)
date: 2026-04-18
issue: "#1450"
status: decided
---

## What We're Building

A cross-workspace isolation test suite that proves the existing bubblewrap (bwrap) OS sandbox — configured through the Claude Agent SDK at `apps/web-platform/server/agent-runner.ts:941-958` — prevents one user's workspace from reading or writing another user's workspace via the filesystem, `/proc`, shared `/tmp`, or SDK session files.

Two surfaces:

1. **Vitest integration test** (`apps/web-platform/test/sandbox-isolation.test.ts`) — subset of adversary cases, runs on every PR, skips cleanly if `bwrap` or `ANTHROPIC_API_KEY` is absent.
2. **Canary shell test** (extension of `apps/web-platform/infra/ci-deploy.test.sh`) — full adversary matrix + shared-surface audit, runs post-deploy inside the canary Docker container against production seccomp/AppArmor, is the authoritative MU3 gate.

The PR closes **#1450** (test infrastructure exists). The **MU3 gate** stays open until all discovered-gap follow-up issues also close.

## Why This Approach

The issue reads "verify existing mechanism, don't rewrite," and MU3 is the last gate blocking founder recruitment per the Pre-Phase 4 Multi-User Readiness section of `knowledge-base/product/roadmap.md`. Four tensions shaped the decisions:

- **bwrap is SDK-internal.** Our code passes declarative options (`allowWrite`, `denyRead`); the SDK assembles bwrap argv. The test cannot inspect args — it must assert OS behavior by attempting cross-workspace access and observing denial. That forces a real integration test, not a unit test.
- **Four defense tiers, not one.** PreToolUse hooks → SDK `disallowedTools` → `canUseTool` callback → bwrap. If a test uses a path that tier 3 (`isPathInWorkspace`) already denies, the test proves tier 3, not bwrap. Each case must use an attack vector that reaches tier 4 — raw Bash syscalls, `/proc` reads, symlinks after realpath canonicalization, or explicitly disable tiers 1–3 in the test config.
- **Scope creep risk.** Adversary + shared-surface audit will likely expose real gaps: the SDK's `/tmp` is per-container tmpfs (shared across concurrent sandboxes); `~/.claude/projects/` session files live outside any workspace. These are not currently in the `denyRead` list. The "verify, don't rewrite" boundary is preserved by **landing the test, failing on gaps, and filing follow-up issues**, not patching bwrap config in this PR.
- **CI environment.** bwrap requires `CLONE_NEWUSER`. Production Docker has a custom seccomp profile (`seccomp-bwrap.json`) that permits it; GitHub Actions runners may not. The canary tier is authoritative precisely because it runs in the production-seccomp canary container.

## Key Decisions

| Decision | Chosen | Why | Deferred / Alternative |
|---|---|---|---|
| Test scope | Adversary matrix + shared-surface audit (full) | MU3 is a security gate; narrow smoke test gives false confidence if `/tmp` or session dirs leak | Minimal smoke test rejected — leaves known-unknowns unchecked |
| Execution model | Vitest (PR subset, skip-if-no-key) + canary shell (full, deploy gate) | Fast PR feedback + authoritative production-env check; canary gate is the source of truth | Single vitest-only rejected (GHA runner may not permit `CLONE_NEWUSER`); canary-only rejected (no PR feedback) |
| Failure handling | Land test; failing cases → `test.fails({ todo: '#NNNN' })` or shell `expect_fail_with_todo`; file one issue per gap; #1450 closes; MU3 gate stays open until issues close | Respects "verify, don't rewrite"; separates test authoring from isolation-architecture fixes; keeps this PR scoped | Fix-inline rejected — unbounded PR scope; block-until-green rejected — single PR becomes an arbitrarily large rewrite |
| Tier-isolation strategy | Each adversary case selects attack vector that reaches tier 4. Test config sets `settingSources: []`, empty `permissions.allow`, explicit `ANTHROPIC_API_KEY`, and where needed temporarily sets `bypassPermissions` to disable tiers 1–3 and isolate tier 4 | Otherwise a green test proves tier 1 or 3, not bwrap | Keep all tiers enabled rejected — ambiguous attribution on pass |
| Test fixture model | Two real directories on disk under a temp `WORKSPACES_ROOT`; no Supabase, no HTTP layer; just `provisionWorkspace(userId)` + SDK `query()` | Process-level test, not full E2E; MU1 (provisioning flow) is a separate gate | Full E2E through web API rejected — over-scoped |
| Canary test orchestration | Node script `apps/web-platform/infra/canary-sandbox-isolation.ts` invoked via `docker exec` from `ci-deploy.test.sh`; mirrors the existing bwrap canary check pattern | Existing precedent (`assert_bwrap_canary_check`); avoids reverse-engineering SDK argv in shell | Pure shell rejected — can't meaningfully exercise SDK `query()` |
| Completeness guard | Integration test enumerates SDK `FILE_TOOLS` set and asserts each has a cross-workspace denial case; new tool additions fail the test until paired with a case | Prevents silent regression when SDK or server adds a path-accepting tool (learning: `2026-03-20-security-fix-attack-surface-enumeration.md`) | Static list rejected — rots |

### Adversary cases (full matrix — subset in vitest, all in canary)

1. **Direct cross-workspace read**: Bash `cat /workspaces/B/secret.md` from a sandbox bound to `/workspaces/A`. Tier-4 case (Bash command substrings bypass tier 3).
2. **Direct cross-workspace write**: Bash `echo owned > /workspaces/B/pwned` — must fail with permission denied.
3. **Prefix-collision path**: Workspace at `/workspaces/tenant`, target at `/workspaces/tenant-evil/secret`. Past-fix regression (CWE-22 learning).
4. **Symlink escape within workspace**: Inside workspace A, create `link -> /workspaces/B/secret`; attempt Read / Bash `cat link`. Past-fix regression (CWE-59 learning).
5. **Dangling symlink**: `link -> /nonexistent`; ensure the failure mode is "target missing," not a permission bypass.
6. **`/proc/<pid>/environ`**: Start long-running process in sandbox B with marker env var; from sandbox A attempt `cat /proc/<B-pid>/environ`. Bwrap `denyRead: ["/proc"]` should block.
7. **Shared `/tmp` (expected gap)**: Sandbox A writes `/tmp/A-marker`; sandbox B reads `/tmp/A-marker`. **Likely fails today** — file follow-up issue `feat: private /tmp per sandbox`.
8. **Shared SDK session files (expected gap)**: Query running under tenant A persists session to `~/.claude/projects/...`; sandbox B attempts to read it. **Likely fails today** — file follow-up issue `feat: per-tenant SDK session root`.
9. **LS of peer workspace**: `LS /workspaces/B` via the LS tool (past-audit case, `feat-audit-ls-notebookread-path-validation`).
10. **NotebookRead of peer workspace**: `NotebookRead /workspaces/B/foo.ipynb` (past-audit case).
11. **Agent subagent with cross-workspace target**: `Agent` tool receives a prompt pointing at `/workspaces/B/`; verify sub-session inherits sandbox.
12. **Completeness guard**: Enumerate current SDK `FILE_TOOLS`; assert each has a matching case above.

## Open Questions

- **How does the SDK configure `/tmp` inside bwrap?** Research flagged `/tmp` as container-scoped tmpfs (shared across sandboxes in the same container), but the SDK's internal bwrap argv may or may not add a `--tmpfs /tmp` per-sandbox. Case 7 will answer empirically.
- **Does `~/.claude/projects/` include per-tenant isolation?** SDK default persists under the Node process's home. If the process is shared across tenants (one Node server, many users), session files mix. Case 8 will answer.
- **`bypassPermissions` vs. per-tier disable.** The SDK may not expose tier-3 disable directly; `bypassPermissions` skips tiers 1–3. Confirm semantics before writing tier-4-isolating cases.
- **Concurrent-sandbox fixture.** Cases 6, 7 need two sandboxes running simultaneously. The SDK may serialize `query()` calls within a Node process; concurrent fixtures may require two child processes. Plan phase will decide.

## Domain Assessments

**Assessed:** Engineering (CTO-implicit via repo research). CPO gates this work via MU3 but the task is internal-engineering verification — no user-facing surface changes, so CMO/CPO routing skipped per `hr-new-skills-agents-or-user-facing` (applies only to new user-facing capabilities).

### Engineering

**Summary:** bwrap is SDK-internal (argv not visible in our code); test must assert behavior not configuration. Four defense tiers exist; the test must isolate tier 4. Known gaps in `/tmp` and session-file handling are predicted to surface — filed as follow-up issues, not patched in this PR.

## Capability Gaps

Predicted but unconfirmed until the test lands (will file as issues at implementation time if cases 7 and 8 fail):

- **Private `/tmp` per sandbox** — if the SDK does not add a per-sandbox tmpfs, two concurrent tenants share `/tmp`. Remediation: SDK config flag if available, otherwise bwrap wrapper.
- **Per-tenant SDK session root** — `~/.claude/projects/` appears to be process-global. Remediation: `HOME` override per session, or `CLAUDE_PROJECT_DIR` if the SDK honors it.

Both block the MU3 gate from closing but do NOT block merging #1450's test infrastructure.
