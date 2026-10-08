---
title: "The vendored CLI already emits deny-then-restore — verify the vendor before planning a patch; and an ordering pin must quantify over EVERY covering mount op"
date: 2026-10-07
category: engineering
tags: [sandbox, bubblewrap, claude-agent-sdk, denyRead, tenant-isolation, toctou, ordering-pin, capture-fixture, issue-5862, adr-075]
symptoms: [per-sibling denyRead enumeration carried a TOCTOU — siblings created after namespace build were never denied; plan assumed an SDK patch was the only fix until the vendored binary's own builder was read]
module: web-platform
component: agent-sandbox
problem_type: security_issue
resolution_type: code_fix
root_cause: external_dependency_behavior_change
severity: high
---

# The vendored CLI already emits deny-then-restore — verify the vendor before planning a patch; and an ordering pin must quantify over EVERY covering mount op

## Problem

Issue #5862 was filed as "vendor/patch the SDK's bwrap argv so sibling deny mounts land before the workspace rw bind" — the ADR-075 exit criterion for the residual TOCTOU in per-sibling `denyRead` enumeration (a sibling workspace created *after* a session's namespace build was never in the enumerated deny set, so it stayed readable via the base `--ro-bind / /`).

The plan's research read the vendored `@anthropic-ai/claude-agent-sdk@0.3.284` / CLI 2.1.284 binary's embedded builder and found the fix already shipped upstream: each `denyRead` landing emits `--tmpfs <landing>` FIRST, then every covered `allowWrite` path is re-bound rw (`Re-bound write path wiped by denyRead tmpfs`) and every covered `allowWithinDeny` (`allowRead`) path re-binds ro (`Re-allowed read access within denied region`). The dependency-patch mechanism the issue prescribed was unnecessary — the durable fix the ADR deferred was delivered by the SDK bump itself.

That flipped the implementation from "patch argv ordering" to "revert to the structural config": `denyRead: [workspacesRoot(), c4StagingRoot, "/proc", ...denyReadExtra]` — a constant list. The parent tmpfs masks present AND future siblings, so enumeration (and its `readdirSync`, `degraded` fail-closed arm, symlink classification) was deleted entirely.

## Solution

- `buildAgentSandboxConfig` emits the constant parent deny; `allowWrite: [workspacePath]` is restored rw post-mask by the vendor; `readOnly` gains `allowRead: [workspacePath]` (inert today — support workspacePath is the plugin root outside the deny root — but forward-declared so a future root-resident read-only session isn't blanked).
- The committed canary fixture was re-captured in-image (`SANDBOX_CANARY_MODE=capture` on `node:22-slim`, then `--verify` → `verify_ok`): the delta is the covering `--tmpfs /tmp/soleur-sandbox-canary` + rw `--bind ${CANARY_WS}` restores + the literal root in `prepDirs`.
- A committed-fixture ordering pin (`denyBeforeRestoreViolations`) asserts: (1) at least one `--tmpfs` STRICT-ancestor of the ws destination exists (an exact-ws tmpfs masks the workspace but zero siblings); (2) the LAST mount op covering the ws dst is the rw `--bind ws ws` — covering ops include the whole mount vocabulary (`--bind`/`--ro-bind`/`--dev-bind*`/`--overlay*`/`--remount-ro`), not just `--tmpfs`; (3) a covering tmpfs precedes that final bind. A 10-row mutation matrix drives each violation class RED (deny-after-restore, missing restore, absent deny, second covering deny, post-restore covering bind, post-restore ro-bind shadowing, `--tmpfs /` and prefix-sibling edge cases, and the legal non-covering tmpfs PASS row).
- A live TOCTOU regression test: a long-running sandboxed shell waits on a flag file in its bind-mounted workspace; the host creates a sibling dir *after* the namespace exists; the sandbox re-lists the parent — sibling absent, `cat` denied.
- Telemetry restored where enumeration's deleted arm had carried it: `workspacesRootExists` + `workspaceUnderDenyRoot` per-dispatch log fields, prod missing-root `reportSilentFallback`, and a hard throw when `workspacePath` equals or contains the deny root (would unmask every tenant rw).

## Key Insight

**A dependency pin is a frozen claim about a moving target.** The ADR's "Option C: patch the SDK" was written against 0.2.85 semantics; the exit criterion fired not when we patched but when we *re-read the vendor at the pinned version*. Before designing around an upstream defect, re-derive the behavior at the pinned revision — the fix may already be in the binary.

**An ordering pin that names one op class misses the class that matters.** The first pin version asked "does a covering `--tmpfs` precede the rw `--bind`?" — but the property is positional at the mount-table level: ANY op whose destination covers the workspace and lands after the last restore breaks it (ancestor `--bind` re-exposes siblings; `--ro-bind ws ws` or `--remount-ro` strand it; `--tmpfs /` and trailing-slash spellings evade naive prefix checks). The structural-enumeration seat mapped 19 uncovered paths; the pin now quantifies the last covering op, not the first deny.

**"Not a regression" is an adjudication, not a dismissal.** The panel flagged the pre-restore `--ro-bind ${WS}/.claude` as shadowed by the covering tmpfs — alarming until checked: it was equally dead on main (the early `--bind ws ws` already covered it), and the real protection is the `/dev/null` masks that land post-restore. Every "new exposure" claim on an ordering change must be re-walked against the OLD argv — mount orderings shadow at every index, not just where the diff landed.

## Session Errors

1. **Quoted a vendor log string that isn't in the binary** (`"Skipping non-existent read deny path"` — real strings: `Skipping non-existent deny path not within allowed paths` / `mounts nothing this wrap can place (absent, …)`). Caught by the code-quality seat's binary grep. **Prevention:** before embedding a claimed-literal string from a binary/bundle in a comment, `grep -ao` it out of the artifact — paraphrase without quotes or quote verbatim.
2. **`spawnSandboxed` (new async spawn helper) ignored `timeoutMs` and had no `error` listener** — a hung or spawn-failed child would burn the vitest timeout with no diagnostic. Two seats flagged it. **Prevention:** every async `spawn` fixture helper must honor the shared opts contract (timeout kill deadline) and attach `child.on("error")` — the sync `spawnSync` path got both free; the async path needs them spelled out.
3. **New `lsSection` window lacked the `// window-assembly:` declaration** — `lint-window-closure-assertion-live` (affected gate) failed. **Prevention:** any `split(marker)`/regex window feeding an assertion needs the assembly declaration written with the window, not discovered by the lint.
4. **TOCTOU test first cut asserted `not.toContain("late-sibling")` on output that included the `cat` error line** — the error text embeds the path it failed on. **Prevention:** scope a listing assertion to the listing's own output window (delimited markers), not the whole process stdout.
5. **`git diff main...HEAD` against a stale local `main`** produced a 4000-file diff. Recovery: `origin/main` merge-base. **Prevention:** in worktrees always diff against `origin/main` (fetch first).
6. **git-history-analyzer seat errored mid-run (connection)** — retried. One-off.

## Prevention (workflow)

- Vendor-string verification could be a check in the ordering-pin family: a test that asserts the two quoted restore strings appear in the installed SDK binary would have caught error 1 at RED time. Candidate for the canary suite if a third vendor-string claim accrues — deferred as part of #9724.
- Deferred follow-ups filed: #9723 (vendored argv's trailing `--bind /proc /proc` undoes the `/proc` tmpfs deny — pre-existing exposure surfaced by this review), #9724 (capture-gate dark-launch; readOnly arm and shim surface uncaptured), #9725 (WORKSPACES_ROOT vs WORKTREE_ROOT divergence at the git-data cutover).
EOF
echo written