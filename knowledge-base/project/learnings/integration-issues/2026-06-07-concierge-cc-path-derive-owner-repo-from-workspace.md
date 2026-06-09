---
module: cc-dispatcher
date: 2026-06-07
problem_type: integration_issue
component: server
symptoms:
  - "Concierge replies 'no connected git repository' on a workspace whose header shows the repo"
  - "Agent asks the user to provide owner/repo even though the workspace is connected"
  - "gh issue/repo lookups fail because no -R owner/repo is passed"
root_cause: agent_inferred_context_from_fragile_filesystem_source_instead_of_server_resolved_value
severity: high
tags: [concierge, system-prompt, owner-repo, agent-native, context-parity, adr-044]
synced_to: []
---

# Concierge cc-path must derive owner/repo from the active workspace, not a git remote

## Problem

In the Dashboard "Soleur Concierge" chat, asking to "Fix Issue 4826" produced a reply
claiming there is **no connected git repository** — `gh` can't infer the repo and there's
no `.git` directory — and the agent prompted the user to type `owner/repo`. This happened
even though the workspace header plainly showed the connected repo (`jikig-ai/soleur`).

## Root Cause

The cc-path baseline directive `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE`
(`apps/web-platform/server/soleur-go-runner.ts`) instructed the agent to "discover your
owner/repo from the origin remote with `git config --get remote.origin.url`". On a
`.git`-less workspace (cold workspace, or `ensureWorkspaceRepoCloned` self-heal not yet
run) that command returns empty, so the agent concluded "no repo connected".

Meanwhile the server **already** resolves and validates the owner/repo for every dispatch:
`cc-dispatcher.ts` parses `connectedOwner`/`connectedRepo` from the membership-scoped
`getCurrentRepoUrl(userId)` (active-workspace `repo_url`, ADR-044) and validates each
against `CC_GITHUB_NAME_RE`. Those values were in scope (already used for the GH_TOKEN mint
and the C4 write-tool gate) but were never surfaced into the Concierge's system prompt. The
sibling **leader path** (`agent-runner.ts:1429-1441`) already did the right thing —
appending `The connected repository is ${owner}/${repo}` — but the cc-path had no equivalent.

## Solution

1. Added `buildConnectedRepoContext(owner, repo)` to `cc-dispatcher.ts` and appended its
   output to `effectiveSystemPrompt` inside an `if (connectedOwner && connectedRepo)` guard
   — lock-stepping the lead phrase with the leader path so the two surfaces stay greppable.
2. Rewrote `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE` to drop the `git config --get
   remote.origin.url` clause and instead point at "the connected repository named in your
   context" for the `-R owner/repo` value (keeping the `gh auth status` false-negative
   guidance + both paren-safe test anchors intact).

Prompt-text only — no new infra, schema, or data path. The owner/repo interpolation is
injection-safe because both bindings are `CC_GITHUB_NAME_RE`-validated before assignment
(carried the `agent-runner.ts:1425-1428` "if that regex relaxes, this becomes a
prompt-injection sink" warning forward).

## Key Insight

When two agent paths (Concierge cc-path vs. leader-path) each assemble a system prompt, and
one path tells the agent to **infer context from a fragile filesystem source** (a git
remote / `.git` directory) while the server **already holds the validated value**, surface
the server-resolved value into the prompt rather than having the agent probe the filesystem.
Guard the injection on the **resolved-value truthiness**, NOT on a `.git` presence check —
that filesystem dependency is the exact root cause. This is the system-prompt analogue of
agent-user context parity: anything the user can see (the connected repo in the workspace
header) the agent must see too, from the same server source of truth.

## Session Errors

1. **Bash CWD drift** — `./node_modules/.bin/vitest` / `tsc` / the full-suite run failed
   with `cd: apps/web-platform: No such file or directory` because the Bash tool does not
   persist CWD across calls. **Recovery:** chained `cd <worktree-abs-path> && <cmd>` in a
   single Bash invocation. **Prevention:** already covered by the work skill's "chain `cd
   <worktree-abs-path> && <cmd>` in one Bash call" rule — application lapse, not a missing
   rule.
2. **Edit `old_string` mid-comment mismatch** — the first attempt to add `export` + the
   parity comment failed (`String to replace not found`) because the `old_string` began
   mid-comment and did not match byte-for-byte. **Recovery:** re-read the exact lines, then
   matched a unique trailing slice. **Prevention:** already covered by
   `hr-always-read-a-file-before-editing-it` — read the exact bytes before constructing an
   Edit `old_string`.

## Tags
category: integration-issues
module: cc-dispatcher
