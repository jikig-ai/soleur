---
module: web-platform agent sandbox (apps/web-platform/server/agent-runner-sandbox-config.ts)
date: 2026-10-08
problem_type: security_issue
component: service_object
symptoms:
  - "argv-level sandbox fixes cannot cover Read/Write/Edit/Glob/Grep/LS — they never run inside bwrap"
  - "sibling workspaces stay observable via /proc/self/mountinfo and shared /tmp|$HOME scratch even when tmpfs-masked"
root_cause: architecture
resolution_type: design_decision
severity: high
issue: 5863
pr: 9767
tags: [bwrap, sandbox, tenant-isolation, file-tools, pathToClaudeCodeExecutable, mount-namespace, adr-075]
---

# The file-tool tier lives outside bwrap — the isolation boundary is the `claude` CLI process, not the argv

## Problem

During the #5863 (ADR-075 Option B) brainstorm, the natural first instinct —
"make the bwrap argv mask siblings harder" — is structurally insufficient. The
vendored `claude` CLI child process is **unsandboxed**: Read/Write/Edit/Glob/
Grep/LS/Notebook* execute inside it with full container-FS visibility, contained
only by the in-process `createSandboxHook` realpath check. bwrap wraps only
Bash invocations, and its setup argv is built inside the vendored binary and
transported opaquely via `--args <fd>` — the `bwrap-shim` PATH interceptor
cannot read or rewrite that payload.

## Solution

Move the isolation boundary up one level: wrap the **whole CLI process** in our
own bwrap via `Options.pathToClaudeCodeExecutable` → wrapper →
`exec /usr/bin/bwrap <self-authored minimal argv> -- claude "$@"`. Because file
tools run inside the CLI process, one outer namespace covers Bash AND file
tools. Key constraints discovered:

- Exec bwrap by **absolute path** — the PATH shim injects a CLONE_NEWUSER-deny
  seccomp filter that would kill the SDK's *inner* sandbox.
- `--unshare-pid` scopes the bound `/proc` to session processes (closes the
  #9723 cross-tenant `/proc/<pid>/environ` channel).
- Build the table from `getWorkspaceWorktreeRoot()` — survives the git-data
  cutover (#9725 class).
- Container envelope: no CAP_SYS_ADMIN; `unshare(NEWUSER)`+post-userns
  NEWNS/NEWPID and `mount`/`pivot_root` are allowed; `open_tree`/`move_mount`/
  `setns`/`fsopen`/`clone3` are EPERM — idmapped-mount designs are dead.

## Key Insight

"Sandbox" in this stack means *Bash-only*. Any design claiming tenant isolation
that touches only the SDK `filesystem` config or the inner argv leaves the
file-tool tier — the tier most sessions actually use — on an in-process hook.

## Prevention

When evaluating sandbox-escape or isolation work, first ask which tier the
access path runs in (CLI-process file tools vs bwrap'd Bash) — argv surgery on
the wrong tier produces confident green tests against a leak that stays open.

## Session Errors

1. Operator prompt cited "the #5849 split-unshare discriminator" — #5849 is the
   Sonnet-5 toolchain PR; the discriminator lives in #5941/#5873. Resolved by
   `gh issue view` + repo grep before leader spawn (premise-validation did its
   job). **Prevention:** verify every cited issue number's title against the
   claim before threading it into subagent prompts.
2. `learnings-researcher` subagent reported `specs/feat-one-shot-5862-*/` and
   `specs/feat-one-shot-8752-*/` absent from the KB and "#5862 still unlanded" —
   both false in the worktree (dirs exist; #5862 merged via #9709 2026-10-07).
   Caught by orchestrator verification per the existing file-existence rule.
   **Prevention:** existing `brainstorm` Phase 1.1 guidance already covers this
   — independently `ls`/`gh` any subagent existence/state claim before it
   propagates into artifacts.

## Plan-review addendum (2026-10-08)

**Superseded bullets above (arm F, landed in the same spec):** the "Solution"
section's `--unshare-pid`/`no CAP_SYS_ADMIN` bullets were reversed by the
Phase-0 spike — the shipped arm is mountns-only via file-capability bwrap
(`cap_sys_admin,cap_setuid,cap_setgid+ep` + `--cap-add SYS_ADMIN` bounding
set), and `/proc` stays shared (#9723). Read the addendum + ADR-075, not the
pre-spike bullets.

Load-bearing corrections the review panel surfaced for the outer-wrap design:

- **`spawnClaudeCodeProcess` (sdk.d.ts:2431) is the supported interpose** — strictly better than `pathToClaudeCodeExecutable`+wrapper script; but `SpawnedProcess` carries NO stderr channel (capture into a ring buffer yourself) and spawn-ENOENT can hang `query()` (sdk-ts#255 → `accessSync` preflight + synthetic failed process).
- **`bwrap --clearenv` wipes the spawn env entirely** — secrets passed via `spawn(env)` never reach the child; the only way back is `--setenv KEY=val`, which lands on `/proc/<pid>/cmdline` (same-uid readable — worse than environ). Compose the child env server-side instead; never put secrets on argv.
- **A procfs superblock is pid-ns-keyed at mount time** — `--bind /proc /proc` under `--unshare-pid` does NOT scope `/proc`. Only a fresh `--proc` (or empty tmpfs) mounts scoped; and empty procfs starves the repo's own bwrap-shim fd sweep (`/proc/self/fd`), so masked-paths EPERM genuinely narrows the honest fallback space.
- **Detached pgid teardown**: `kill(-pgid)` needs `detached:true` or it hits the runner's own process group; bare-PID kill orphans the CLI inside the namespace.
- **Bind mounts pin inodes** — a reprovision that swaps the workspace dir under the same path leaves the session on a deleted inode; serialize reprovision before spawn.
