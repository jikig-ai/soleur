---
title: "Headless `claude --print` containment is deny-list / PreToolUse-hook-driven, NOT allow-list-driven"
date: 2026-06-08
category: integration-issues
tags: [claude-code, cron, sandbox, security, permissions, pretooluse-hook, headless, exfil]
issue: 5018
related: [5000, 5004]
cli_version_verified: "2.1.79 (Dockerfile pin) + 2.1.168"
---

# Headless `claude --print` is deny-list / hook-driven, not allow-list-driven

## Problem

The cron eval substrate spawns `claude --print` headless and relied on the OS bash
sandbox (bubblewrap) to auto-approve `Bash` tool calls. When the cloud runner's bwrap
cannot acquire unprivileged user namespaces (`kernel.apparmor_restrict_unprivileged_userns`
drift), every `Bash` call fails → the cron self-reports FAILED (#5000, #5004). The host
sysctl pin (#4932) recurred in 4 days, so the durable fix had to remove the cron's
dependency on userns: `sandbox.enabled:false`.

But disabling the sandbox removes the only thing containing headless bash. Two attempted
fixes were **falsified by live probes** before shipping (the third plan to reach probe
gating — the first two premises were wrong):

## What the probes proved (run against BOTH 2.1.168 and the prod-pinned 2.1.79)

1. **`--allowedTools` + `defaultMode` do NOT fail-close in headless `--print`.** With
   `sandbox.enabled:false`, `defaultMode` ∈ {`dontAsk`, `default`, `auto`} ALL **fail-OPEN**:
   a non-allowlisted Bash command (`uname -a`, `cat /proc/self/environ`) **runs**. Only an
   explicit `permissions.deny` rule OR a `PreToolUse` hook blocks. So `--allowedTools` is
   **not an enforced allowlist** headless — it is cosmetic.
2. **A `Read(/proc/**)` `permissions.deny` does NOT stop `cat /proc/self/environ`.** The
   `Read(...)` deny governs the **Read tool**, not a `cat` run through the **Bash** tool.
   (And the inverse: a `Bash`-only hook matcher does not cover the **Read** tool — `Read`,
   `Grep`, `Glob`, `WebFetch` are a parallel, unhooked path to the same secrets.)
3. **A `PreToolUse` hook CAN deny by content** — for Bash, AND for Read/Glob/Grep, AND
   (under a `*` catch-all matcher) for any tool class. A **deny-by-default** hook (allow
   only matched, deny everything else) is therefore the only fail-closed allowlist available.
4. **A crashed/missing hook, or any tool class with no matcher, FAILS OPEN.** Claude treats
   "no decision" as a fall-through to the (fail-open) permission layer. So: register the hook
   under a `*` catch-all (no unhooked class) AND run a **spawn-time self-test** that aborts
   the cron if the hook does not deny a canonical exfil payload.
5. **`ToolSearch`/`TodoWrite` are inert internal tools claude routes core tools through** —
   a deny-by-default catch-all must allow them or it breaks the agent's tool plumbing.
   (Discovery ≠ execution: a discovered `mcp__*`/`WebFetch` still hits the catch-all deny
   when CALLED.)

## Fix (hook-primary, the v3.1 design)

`cron-bash-allowlist-hook.mjs` (deny-by-default, tool-class-level) registered under a `*`
matcher by `buildCronEvalSettings`; per-cron allowlist file (`.claude/cron-allow.txt`);
`runHookSelfTest` spawn-time gate; `sandbox.enabled:false`. **The real safety property is
secret-out-of-context**: every env/secret-read path is denied (Bash `cat`/`env`/`printenv`
non-allowlisted; Read/Grep deny `.git/config` — where `buildAuthenticatedCloneUrl` writes
the GH_TOKEN — `/proc`, `.env`, gh/ssh/aws cred stores), so the *allowed* egress verbs
(`gh issue create --body`, `git push`) cannot leak a secret the model never read. Argument
injection (`--body-file /proc/self/environ`, `gh api -f body=@.git/config`, `git remote add
evil && git push evil`) is denied even on allowlisted verbs.

## Why it matters / how to apply

- **Never assume a permission flag fail-closes in headless `--print` — probe it.** v1
  (`bypassPermissions`) and v2 (`--allowedTools` fail-closed) both shipped to a draft PR on
  an unverified premise; both were exfil-class holes. The gating probe is cheap (a nested
  `claude --print --settings <tmp>` run) and catches it before review.
- **Re-probe against the version PROD runs**, not just your local CLI. The Dockerfile pins
  `claude-code@2.1.79`; the first probes ran on 2.1.168. Hook semantics are version-sensitive
  (architecture-strategist P0-D). Same "unverified premise" class the gate exists to prevent.
- **A PreToolUse hook is fail-OPEN on its own failure.** Treat hook reachability +
  non-crashing as load-bearing: register under `*`, resolve `node` by absolute path
  (PATH-drift fail-open), make the hook never `exit(non-zero)` (emit deny on any internal
  error), and assert it live with a spawn-time self-test.
- **The hook governs the claude-code tool layer ONLY.** Node-level `spawn("bash", …)` crons
  bypass it entirely — they need the Tier-2 network-egress firewall. The hook is an interim,
  parser-bounded control; the firewall is the durable boundary. See [[2026-06-08-fix-cron-sandbox-hook-primary-containment-plan]].

See ADR-033 **I7** and `knowledge-base/project/specs/feat-one-shot-5000-5004-cron-sandbox-bwrap-fix/phase0-probe-results-AC0.md` for the full probe matrix.
