# Decision Challenges — feat-one-shot-8623-likec4-tenant-config-rce

Headless-path record (no interactive operator gate). `/ship` should render these into the
PR body and file an `action-required` issue so the operator sees them.

## UC-1 — The render takes its bytes from the GitHub API, not from local git objects

**The operator's stated direction (#8623, pipeline arguments):** "render only tracked
.c4/.likec4/.like-c4 sources in a private staging dir (refuse symlinks, gitlinks, likec4 config
files — mirroring the ADR-235 amendment of 2026-09-23 local-resolver pattern)". The issue body
adds "copy only tracked … sources out of git objects".

**What the plan does instead:** keeps the private staging dir, the extension allowlist and all three
refusals, but fetches the committed blobs from the GitHub Contents/Trees/Blobs API at the commit
sha GitHub returned for the write, instead of reading the workspace's local `.git`.

**Why (evidence, not preference):** the agent sandbox has `allowWrite: [workspacePath]`
(`apps/web-platform/server/agent-runner-sandbox-config.ts`). The Agent SDK's built-in write-deny
list names `.git/hooks`, `.git/config`, `.git/config.worktree`, `.git/commondir`, `.git/worktrees`,
`.git/modules` and `.git/info/exclude` (`grep -aoE '/\.git/[a-zA-Z._/-]{1,40}'` over
`node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude`, SDK 0.3.197) — and not
`.git/objects`, `.git/refs`, `.git/HEAD` or `objects/info/alternates`. A local read would therefore
need per-object hash verification plus git env, alternates, gitfile and promisor-fetch hardening.
The CTO assessment and the scoped advisor consult both recommended the GitHub fetch independently;
it costs about three API calls per save. The resolver keeps the local pattern because there the
object store is the operator's own.

**Default if not challenged:** ship as planned. To revert to the local-objects design, see the
plan's "Alternative Approaches Considered" row and the v1 design in the plan history.

## T-1 — PR-body qualifier "assessment pending"

CMO asked to drop "assessment pending" from "not known to have been exploited; assessment
pending" (it hedges, on a public repo). CLO requires it until the L1/L2 exposure limbs have run,
because "not known" is otherwise an unverified claim. The plan keeps CLO's wording.

## T-2 — Diagnostic copy

CPO (sign-off approved-with-changes), CMO and spec-flow shaped the copy in the plan's
"Behaviour changes a tenant can see" table: one template for unsupported files with a
class-specific noun, a relative path plus "(and N more)", "in your GitHub repository", and
"Save again to retry" for transient failures. Applied as written; change the table if the voice
should differ.
