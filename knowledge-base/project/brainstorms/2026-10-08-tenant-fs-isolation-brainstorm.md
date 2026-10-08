---
date: 2026-10-08
topic: tenant-fs-isolation
lane: cross-domain
issue: 5863
---

# True per-tenant filesystem isolation for the Concierge — ADR-075 Option B (#5863)

## What We're Building

The end-state for agent-sandbox tenant isolation: **no sibling workspace is ever
present on an agent's filesystem surface** — not as readable content, not as a
mount-table entry, not as a stat-able path. Chosen mechanism: a per-session
**outer bwrap wrap of the whole `claude` CLI process** via
`Options.pathToClaudeCodeExecutable` (`sdk.d.ts`), so the boundary covers *both*
agent tool tiers (sandboxed Bash AND the in-CLI file tools that today sit outside
bwrap under only the realpath hook).

## Baseline this designs against (verified 2026-10-08)

- #5862 closed via PR #9709 (merged 2026-10-07, deployed): vendored CLI 2.1.284
  builder emits deny-then-restore — `--tmpfs <denyRead landing>` then rw
  `--bind` restores. `buildAgentSandboxConfig` now emits constant
  `denyRead: [workspacesRoot(), c4StagingRoot, "/proc", ...denyReadExtra]`.
- Residuals at this baseline (the reason #5863 exists): sibling mount-table/stat
  existence is observable; the argv tail `--bind /proc /proc` re-exposes the real
  procfs over the `/proc` tmpfs deny (#9723 — cross-tenant `/proc/<pid>/environ`
  credential channel); deny root diverges from `getWorkspaceWorktreeRoot()`
  after the `GIT_DATA_STORE_ENABLED` cutover (#9725); capture/canary gaps
  (#9724 — stays a separate issue).
- Process model: one node process, uid 1001, `-v /mnt/data/workspaces:/workspaces`;
  the `claude` CLI child per session is **unsandboxed** (file tools inside it);
  per-Bash bwrap argv is built inside the vendored binary and transported
  opaquely via `--args <fd>` — the `bwrap-shim` sees only the outer argv.
- Container capability envelope (soleur-bwrap.json seccomp + apparmor): no
  `--cap-add`, no CAP_SYS_ADMIN; `unshare(NEWUSER)`, post-userns `NEWNS`/`NEWPID`,
  `mount`/`umount`/`pivot_root` allowed; `clone3`→ENOSYS; `open_tree`/
  `move_mount`/`setns`/`fsopen`/`fsmount`/`bpf` EPERM (compile-time cap-gated —
  idmapped-mount designs are out without a profile change + redeploy cycle).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Driver | **Arms-length tenants are coming** — this gates onboarding | Full end-state bar on day one: content, existence, mount table, `/proc` must all close in v1. Sharpened re-eval trigger: "before the first hosted arms-length tenant session." |
| Mechanism appetite | Evaluate in-process and topology tiers; commit per comparison | Operator priced both. |
| Scope fold-in | **#9723 and #9725 fold into #5863** | The chosen design dissolves both structurally; #9724 (canary coverage on the current machinery) stays separate. |
| Tool-tier coverage | **Both tiers** | File tools (Read/Write/Edit/Glob/Grep/LS/Notebook*) run inside the CLI child; the outer wrap covers them because the boundary moves up one level around the whole CLI. |
| Approach | **Option 1 — outer per-session bwrap wrap; Option 3 (per-tenant executor) filed as deferred follow-up** | Only option satisfying both tiers without a topology change; we author the outer argv so the isolation property is immune to the #5849-class SDK argv drift. |

## Approaches Considered

### Option 1 — Outer per-session bwrap wrap of the whole CLI (chosen)

`pathToClaudeCodeExecutable` → wrapper script that `exec`s `/usr/bin/bwrap`
directly (bypassing the PATH shim — its `CLONE_NEWUSER`-deny filter would kill
the SDK's *inner* sandbox) with a self-authored minimal mount table: tmpfs/dir at
the workspaces parent + `--bind <own_ws>` at its real path, `--unshare-pid`
(scopes bound `/proc` to session processes — closes #9723), per-session
`/tmp`/`$HOME` scratch (dissolves shared `/tmp/claude-1001`, `~/.npm/_logs`,
`~/.claude` surfaces), no `--unshare-net` (inner SDK sandbox owns egress).
Fixes #9725 by construction (table built from the resolver root; the
`/workspaces` deny machinery can then simplify away per the issue's payoff).

- Pros: covers both tool tiers; immune to vendored-argv drift for the isolation
  property; per-session failure is loud via `sdk-startup` classifier; deploys as
  an image change.
- Cons: must enumerate the CLI's full fs footprint (plugin root, transcript
  dirs, MCP/proxy sockets); new surface needs its own faithful canary
  (dark-launched first per `wg-dark-launch-deploy-gates`); spike gates on
  `--version` probe compat, SIGTERM/`--die-with-parent`, graceful-drain (ADR-078).

### Option 2 — Shim payload rewrite (fallback)

Rewrite the `--args` fd payload to a minimal inner mount table. Bash-tier only —
fails the "both tiers" bar; NUL-stream + inner fd-renumbering surgery is fragile;
`/proc` still needs a separate decision. Retained as fallback if the Option 1
spike proves the wrapper unviable.

### Option 3 — Per-tenant subprocess/container executor (deferred follow-up)

The only kernel/credential boundary — subsumes #9543-class residuals (BYOK
leases, session state in the shared heap). Weeks-scale; per-tenant containers
already deferred twice on capacity grounds (#673, #4891); COGS step-change.
File as the tracked end-state; stage behind capacity work.

## Open Questions

- Does `pathToClaudeCodeExecutable` survive SDK `--version`/probe calls and
  stdio transport unchanged through bwrap? (Spike item.)
- Full CLI fs footprint outside the workspace: transcript dirs, plugin root,
  MCP socket paths, the socat proxy socket pair — complete enumeration required
  before the minimal table is correct (under-binding breaks sessions;
  over-binding re-leaks).
- Prod bwrap version needs re-measurement at plan time (0.8.0 vs 0.12.0
  evidence conflicts across issues) — the outer-wrap argv must be valid on the
  *deployed* version.
- Does the outer wrap change anything for `enableWeakerNestedSandbox` /
  the inner sandbox's `/proc` expectations? (Interaction to spike.)
- Git-data cutover: design keys on `workspacePathForWorkspaceId` /
  `getWorkspaceWorktreeRoot()` — whatever the resolver returns — and must also
  cover the `WORKTREE_ROOT` layout and any ci-deploy `-v` mount changes.

## User-Brand Impact

- **Artifact:** the per-tenant agent filesystem boundary (the thing a tenant's
  agent can or cannot see).
- **Vector:** worst case is one tenant's agent silently reading another
  tenant's workspace contents or credentials — a cross-tenant confidentiality
  breach, asymmetric toward operator→stranger at n=2 (operator workspaces carry
  KB/post-mortems/ADRs; the sensitive tenant is us). Symmetric treatment.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Option (b) outer-CLI bwrap wrap is the sweet spot — covers both
tool tiers, dissolves #9725 and narrows #9723 to session scope, authors our own
argv (immune to SDK drift), failure scoped to session startup. Shim payload
rewrite is Bash-only and fragile; per-tenant executor is the correct long-term
end-state but wrong vehicle here.

### Product (CPO)

**Summary:** Zero alpha-tester perception today (tester 1 is on the self-hosted
plugin); value is claim-enabling not experience-changing. Honest claim ceiling:
"process-level filesystem isolation for sandboxed agent commands" — never
"per-tenant isolation" unqualified (the in-process runner still shares a heap).
If tenants are coming, the ordering inverts: this gates the first hosted tenant.

### Legal (CLO)

**Summary:** No commitment breached — registered TOMs are DB-layer only and no
public doc claims FS isolation. #9723 converts a recorded *intra*-session
residual into an unrecorded *cross*-tenant channel — fold it in or sequence
before any claim. `/proc` reads leave no audit trail (weakens Art. 33
accountability) — the design must ship an observability probe. gdpr-gate at
plan 2.7/work exit; hold public claims until measured in prod (#9603 pattern);
register entry in honest tense, status `adopting`.

## Deferred / Follow-up Items

- **Per-tenant executor (Option 3)** — file as deferred issue (this brainstorm
  is its authority record).
- **#9724** — canary gaps on the existing capture machinery; stays separate,
  plus a NEW outer-wrap replay probe is required by this design.
- **Two-tenant runtime probe** — publishable isolation claim wants a realized-
  state proof (session A attempts sibling stat/`/proc` environ reads, all must
  fail); include in this spec's acceptance or track via #9603 claim discipline.
- **File-tool tier becomes residual-free**: the realpath hook downgrades to
  defense-in-depth — record the mechanism change in the Art. 30 register entry.
