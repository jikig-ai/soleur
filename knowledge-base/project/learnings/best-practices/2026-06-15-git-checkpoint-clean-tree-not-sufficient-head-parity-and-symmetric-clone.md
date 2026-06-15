# Learning: git checkpoint/restore over a shared clone — clean-tree is necessary but NOT sufficient

**Date:** 2026-06-15
**Context:** PR #5350 (#5275) — in-flight work durability: checkpoint a disconnected turn's uncommitted git working-tree to `refs/checkpoints/<conversationId>` and restore on resume.

## Problem

The plan + first implementation gated the restore on a single precondition: **clean working tree** (`git status --porcelain` empty) + a team-only sibling-slot probe. The reasoning was "if the tree is clean there is no uncommitted work to lose, so restoring the snapshot cannot clobber anything." Multi-agent review (data-integrity-guardian, reproduced empirically) falsified this. Three independent gaps:

1. **Moved-HEAD clobber.** The snapshot commit is parented at the HEAD it was taken over (HEAD=A). The shared workspace clone's HEAD **can advance** between checkpoint and resume — `git pull --no-rebase --autostash` runs on *every* `startAgentSession` via `gitWithInstallationAuth` (a raw `execFile` that bypasses `session-sync.ts`'s `ALLOWED_GIT_SUBCOMMANDS` allowlist), and `workspace-sync.ts` does `pull --ff-only` / `reset --hard`. A clean tree at HEAD=B does **not** make a HEAD=A snapshot safe: `git checkout-index -a -f` writes the *whole* snapshot tree, reverting every file changed between A and B. Newer committed work is silently clobbered.

2. **`checkout-index` never deletes.** A file the in-flight work *deleted* is correctly captured in the snapshot (absent from the tree), but `checkout-index -a -f` only *writes* index entries — the deleted file (present on the clean HEAD tree) is silently resurrected.

3. **Checkpoint/restore clone asymmetry.** The checkpoint resolved the *active* workspace (`resolveActiveWorkspacePath` → mutable `current_workspace_id`, solo-fallback); the restore resolved the *conversation's bound* `workspace_id`. Under active-claim drift they point at different clones → the ref is written where restore never looks → silent no-checkpoint + a stranded ref.

4. **"Solo" is not single-tenant.** The plan skipped the sibling-slot DB read for solo (`workspace_id === userId`) "because the solo clone is single-tenant-at-rest." False: per-user concurrency can be >1 (solo plan = 2). Two tabs share one tree; a checkpoint taken by tab A captures tab B's dirt, and restoring it over a now-clean tree clobbers B.

## Solution

- **HEAD-parity gate:** before materializing, require `git rev-parse <ref>^1 == git rev-parse HEAD`; else refuse-and-report (`reason: "stale-base"`). This converts the unconditional full-tree write into an "only-if-HEAD-unmoved" guarantee that actually matches the no-clobber claim.
- **Delete-aware restore:** after `checkout-index`, `rm` the paths in `git diff --name-only -z --diff-filter=D <ref>^1 <ref>` (deleted in the checkpoint vs its parent).
- **Symmetric clone resolution:** resolve the checkpoint clone from `conversations.workspace_id` (the same source restore uses), never the mutable active-claim resolver.
- **Always probe the sibling slot** (drop the solo skip) — a live sibling conversation on the same `workspace_id` forces refuse-and-report.

## Key Insight

A "**this can never happen**" safety premise (HEAD never moves, the tree is single-tenant, the path is stable) is a **hypothesis to falsify by grepping EVERY code path**, not just the one wrapper you happened to read. The original analysis checked `session-sync.ts`'s *command allowlist* and concluded "no pull moves HEAD" — but the HEAD-moving pulls run through a *different* function (`gitWithInstallationAuth`) that bypasses the allowlist entirely. When a correctness argument rests on "X never happens," the verification is `git grep` for **every** producer of X across the module's siblings, then encode the invariant as a runtime gate (HEAD-parity) rather than trusting the premise. For checkpoint/restore specifically: **clean-tree is necessary but not sufficient — also require HEAD-parity and clone-symmetry, and treat concurrency>1 as the default, not the exception.**

## Session Errors

1. **Logger import shape wrong** — `import { log } from "./logger"` but the module exports `createChildLogger(context)`. `log.info` threw, was swallowed as the restore-failed mirror, and surfaced as 2 confusing test failures (restore returned `restore-failed`). **Recovery:** `const log = createChildLogger("inflight-checkpoint")`. **Prevention:** before importing a shared util, grep an existing importer (`grep "from \"./logger\"" server/*.ts`) for the exact export shape — don't assume a `log` named export.
2. **`expect.anything()` does not match `null`** — the refuse-and-report path passes `null` as the err arg (it is not an error); the assertion `toHaveBeenCalledWith(expect.anything(), ...)` failed because `expect.anything()` deliberately rejects null/undefined. **Recovery:** match the options object arg directly. **Prevention:** for a known-null positional arg, assert the literal `null` (or `expect.objectContaining` on the next arg), never `expect.anything()`.
3. **Plan's `sessionTenant` scope claim was wrong** — the plan asserted `sessionTenant`/`userId` are "outer-scope" at the abort catch; `sessionTenant` is a `const` declared *inside* the try body, invisible in the catch (tsc TS2304). **Recovery:** re-mint via `getFreshTenantClient(userId)`. **Prevention:** plan code-level scope claims are hypotheses — verify the actual block scope (try-const vs param) before relying on a variable in a catch.
4. **resume-rebind test mock-chain gap** — the new ws-handler sibling-slot probe (`.from(...).neq().gte()`) wasn't covered by the existing tenant mock; the FR1 rebind test threw into its terminal catch and left the conversation unbound. Caught by the full suite, not the touched-file set. **Recovery:** recursive-by-default mock chain + stub `@/server/inflight-checkpoint`. **Prevention:** this is the documented wrapper-extension mock-chain sweep class — the full `vitest run` exit gate is the authoritative sweep.
5. **"HEAD never moves" premise was empirically false** — see Key Insight. **Recovery:** HEAD-parity gate + 4 more review-driven fixes. **Prevention:** the Key Insight above (falsify safety premises by grepping all producers, encode as a runtime gate).

## Tags
category: best-practices
module: server/inflight-checkpoint, session-resume, git-plumbing
related: [[2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates]], [[2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries]]
