---
date: 2026-04-27
module: apps/web-platform/server/session-sync.ts
problem_type: integration_issue
component: connected_repo_writer
severity: high
tags:
  - autonomous-loop
  - git
  - ci-guards
  - workflow-injection
  - defense-in-depth
related:
  - "#2857"
  - "#2859"
  - "#2904"
  - "#2905"
  - "#2906"
synced_to: []
---

# Autonomous-loop PR-quality failure modes — three-layer fence

## Problem

The Command Center web app (`apps/web-platform/server/session-sync.ts`) runs an autonomous loop against connected user repos. At session start (`syncPull`) and end (`syncPush`), it ran:

```
git status --porcelain
git add -A           # the bug
git commit -m "Auto-commit before sync pull"
git pull --no-rebase --autostash
```

The blanket `git add -A` swept everything in the workspace tree — including:

1. **`.claude/settings.json` wipes** — the loop's workspace had drifted to a default settings file (`{"permissions":{"allow":[]}, "sandbox":{"enabled":true}}`), and the auto-commit landed that wipe in every PR. The wipe deleted 6 hooks, MCP allowlist, env vars, and Bash permissions. CI passed because no test depends on hooks running in CI; the wipe took effect only post-merge, when day-2 enforcement silently disappeared.
2. **Stray `.claude/worktrees/agent-*` markers** — Claude Code subagent runtime markers that were never in `.gitignore`. PR #2859 committed one as a gitlink (mode 160000) pointing at an unreachable commit.
3. **PR descriptions disconnected from diffs** — the LLM wrote bodies describing the loop's *intent* (e.g., "inlines critical CSS into `_includes/base.njk`"), while the diff contained zero changes to that file.

Two PRs (#2857, #2859) shipped this pattern; both were closed in favor of a clean human-authored replacement (#2904). The class warranted independent investigation.

## Solution

Three layers of defense in `apps/web-platform/server/session-sync.ts` + repo + CI:

### Layer 1 — Path-scoped auto-commit (root cause)

Replace `git add -A` with `getAllowlistedChanges()` filtering on `^knowledge-base/` and stage only matching paths via `git add -- <paths>`:

```typescript
const ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//];

export function getAllowlistedChanges(workspacePath: string): string[] {
  const output = runConnectedRepoGit(
    ["status", "--porcelain=v1", "-z"],
    { cwd: workspacePath, stdio: "pipe" },
  ).toString();
  const paths: string[] = [];
  const tokens = output.split("\0");
  for (let i = 0; i < tokens.length; i++) {
    const entry = tokens[i];
    if (entry.length < 4) continue;
    const status = entry.slice(0, 2);
    const path = entry.slice(3);
    if (ALLOWED_AUTOCOMMIT_PATHS.some((re) => re.test(path))) {
      paths.push(path);
    }
    if (status[0] === "R" || status[0] === "C") i++;
  }
  return paths;
}
```

Three sharp edges that cost rounds:

- **`--porcelain=v1 -z` not bare `--porcelain`.** Default porcelain C-quotes paths with tabs/quotes/non-ASCII; that quoted form fails at `git add --`. The `-z` form emits NUL-separated entries verbatim and round-trips cleanly.
- **Rename entries under `-z` emit destination first, source second.** Skip the source NUL token. Test fixture must rename across the allowlist boundary (`docs/old.md → knowledge-base/new.md`) — same-allowlist renames pass tautologically.
- **Bootstrap path is exempt.** `apps/web-platform/server/workspace.ts:provisionWorkspace` runs `git add .` to seed a fresh local-only repo before any remote is added. `hasRemote()` short-circuits both `syncPull`/`syncPush` so the seed and the sweep are temporally separated.

### Layer 1.5 — `runConnectedRepoGit` wrapper (full destructive-verb class)

Layer 1 fences `git add`. The same module can still call `git rm`, `git commit --amend`, `git push --force`, `git reset --hard` etc. Wrap every `execFileSync("git", ...)` in a guard:

```typescript
const ALLOWED_GIT_SUBCOMMANDS = new Set(["status", "add", "commit", "remote", "rev-list"]);
const FORBIDDEN_GIT_FLAGS = new Set(["--force", "-f", "--hard", "--amend", "--no-verify"]);

function runConnectedRepoGit(argv: string[], opts): Buffer {
  const subcmd = argv[0];
  if (!ALLOWED_GIT_SUBCOMMANDS.has(subcmd)) throw new Error(...);
  for (const arg of argv) {
    if (FORBIDDEN_GIT_FLAGS.has(arg)) throw new Error(...);
  }
  return execFileSync("git", argv, opts) as Buffer;
}
```

This was filed initially as scope-out (architectural-pivot). `code-simplicity-reviewer` correctly dissented — same directory, allowlist precedent already set, ~30 lines, fold inline. **Single-reviewer scope-out judgment is failure-prone; the second-reviewer concur gate caught it.**

### Layer 2 — `.gitignore`

`/.claude/worktrees/` (anchored leading slash). The existing `.worktrees` rule (no anchor) targets the soleur-internal worktree-manager directory and does NOT match `.claude/worktrees/agent-*`.

### Layer 3 — `pr-quality-guards.yml` (4 jobs + opt-out)

CI defense-in-depth that catches the failure modes even if Layer 1 regresses:

1. **`settings-json-integrity`** — flags deletion of valid top-level keys (`hooks`, `enabledMcpjsonServers`, `env`), introduction of unknown keys (`sandbox` is the smoking-gun for an LLM-rewritten file — Claude Code schema doesn't recognize it), and removal of `permissions.allow[*]` entries.
2. **`pr-body-vs-diff`** — extracts file paths from the PR body (excluding fenced blocks and URLs) and fails if <50% appear in the diff.
3. **`stray-worktree-marker-block`** — fails on any `.claude/worktrees/*` path in the diff.
4. **`auto-commit-message-density`** — fails if >50% of commit headlines match the exact strings emitted by session-sync.ts (`AUTO_COMMIT_MSG_PULL`/`PUSH`).

**Critical security finding (caught by security-sentinel):** the original opt-out — `confirm:claude-config-change` label honored unconditionally — is bypassable by the autoloop bot account. The bot opens the PR AND applies its own opt-out label. Fix: gate the opt-out on `labeler != PR author`, fetched via `/repos/$REPO/issues/$N/events`. Self-applied labels emit a warning and the gate still runs.

### Bash fixture tests for guard scripts

The 3 bash guard scripts had no local tests — high-leverage gap (test-design-reviewer caught it). Added `.github/scripts/test/` with 19 fixture cases (settings-integrity 6, density 6, body-vs-diff 7) plus a CI job that runs them on every PR. Each fixture replicates the SUT's regex/jq logic in a controlled bash test rather than calling `gh` against live GitHub state.

## Key Insights

1. **Path-allowlist beats subcommand-deny for auto-commit sweeps.** A denylist asks "what shouldn't be committed?" — the answer drifts (`.claude/`, `.github/`, `apps/`, `package.json`, `_data/`, ...). An allowlist asks "what's the product surface?" — for a knowledge-base writer the answer is `knowledge-base/`. One is exhaustive; the other is mechanical.

2. **Defense in depth requires INDEPENDENT layers.** L1 (allowlist), L2 (`.gitignore`), L3 (CI guard) each catch the canonical failure on their own. The `confirm:claude-config-change` opt-out disables all 4 L3 jobs (single-toggle escape hatch — correct), but L1+L2 remain in force at the agent process and the repo's ignore rules.

3. **CI opt-out labels are a bot-bypass surface unless the labeler is verified.** Any opt-out gate that says "label X disables the check" must verify `labeler != PR author` when the threat model includes bot-authored PRs. The bot can open PR + apply own label = silent bypass.

4. **Scope-out judgment is failure-prone for fresh hardening surfaces.** The instinct on F2 (other destructive git verbs) was scope-out as architectural-pivot. Code-simplicity-reviewer correctly identified it as a localized hardening pattern (~30 lines, same directory, precedent already set). The cost of fix-inline now ≪ cost of context-reload later. **The two-reviewer concur gate is the load-bearing safety net for scope-out decisions.**

5. **`git status --porcelain=v1 -z` is the only safe form for paths-as-data.** Default porcelain C-quotes; `-z` doesn't. This generalizes to any tooling that pipes `git status` output to another command.

## Session Errors

- **`Edit replace_all=true` was over-broad** — replaced the first opt-out block but each subsequent block had a unique skip message, so only 1 of 4 matched. **Recovery:** Manually replaced the remaining 3 individually. **Prevention:** When tempted to use `replace_all` on near-identical blocks that share a skeleton but differ in identifying fields (job name, slug), grep first to confirm match count. If the count exceeds 1, expect the diff to differ per-instance and use targeted edits.

- **Wrote opt-out logic to a separate script before realizing scripts run after `actions/checkout`** — created `.github/scripts/check-opt-out-label.sh`, then realized the opt-out step runs BEFORE `actions/checkout` so the script file isn't on the runner yet. **Recovery:** Deleted the script and inlined the logic in each of the 4 jobs. **Prevention:** When a CI job has a "skip" step before checkout, never reference repo-tracked scripts from that step. Either checkout first (cheap, ~3s) or inline. Capture this in the workflow design checklist.

- **PreToolUse `security_reminder_hook` reset shell CWD on workflow Write** — wrote `pr-quality-guards.yml`, the security reminder fired, and the next Bash call landed in `/home/jean/git-repositories/jikig-ai/soleur` (bare root) instead of the worktree. **Recovery:** Re-cd'd to the worktree before continuing. **Prevention:** After any tool call that triggers a hook with stderr output (security_reminder, lefthook, etc.), the next Bash call should re-establish CWD with `cd <worktree-abs-path> && <cmd>`. Already covered by `cq-for-local-verification-of-apps-doppler` for one case; this generalizes the pattern.

- **`vi.mock` hoisting clobbered top-level `const logInfo = vi.fn()`** — `vi.mock(...)` factory ran before the `const` declaration, producing "Cannot access 'logInfo' before initialization". **Recovery:** Used `const { logInfo } = vi.hoisted(() => ({ logInfo: vi.fn() }))`. **Prevention:** Already in the work-skill cookbook; the surprise here is that the same pattern applies to `vi.fn()`-only fixtures (no shared variable references), not just complex factories. The `cq-write-failing-tests-before` cookbook already mentions `vi.hoisted` — no new rule needed.

- **Initial test mock matched `args[1] === "--porcelain"`; SUT used `--porcelain=v1`** — first test pass after fixture refactor failed because string equality is brittle. **Recovery:** Switched to `args[1].startsWith("--porcelain")`. **Prevention:** When mocking command-line tools that take subcommand-prefix flags (porcelain=v1/v2, --format=...), match on prefix not equality.

- **Bash `$'...'` quoting collapsed multi-line headlines test fixture** — `$'merge\nfeat'` with embedded `'\''` for single quotes broke the line count under `<<<`. **Recovery:** Switched to plain `VAR="line1\nline2"` heredoc-style assignment. **Prevention:** For multi-line bash test fixtures with embedded quotes, prefer plain double-quoted variables over `$'...'` — readability wins, and the dollar-quote syntax is fragile around nested quoting.

- **Pre-existing kb-chat-sidebar happy-dom flakes (3 tests) on full vitest run** — passed in isolation. Tracked under #2594. **Recovery:** No action — confirmed pre-existing, isolation-passing. **Prevention:** No new prevention; #2594 already tracks the class. The constitution's `cq-vitest-cross-file-leaks-and-module-scope-stubs` rule is the upstream guidance.

- **(Forwarded from session-state.md) `deepen-plan` could not spawn `Task general-purpose:` subagents in pipeline mode** — the Task delegation tool wasn't available in the planning subagent context. **Recovery:** Plan agent loaded learnings inline, ran live SHA verification via `gh api`, and performed a guard-surface grep audit manually. **Prevention:** Already a known limitation of pipeline mode. The deepen-plan skill should detect this and gracefully degrade — already does, per the session-state record.

- **(Forwarded) Brainstorm/Domain Review subskills not invoked** — pipeline mode skipped Step 1 spawn. **Recovery:** Issue body explicitly cited CTO+COO domains, satisfying the gate. **Prevention:** Already covered by pipeline-mode design.

## Prevention

The new AGENTS.md rule (`hr-never-git-add-A-in-user-repo-agents`, 506 bytes, under the 600-byte cap) codifies the path-allowlist invariant for any future user-repo writer in `apps/web-platform/server/`. The 4 CI guards catch regressions of the broader failure class (settings wipe, body-vs-diff drift, stray markers, auto-commit message density) at PR time, even if Layer 1 is locally bypassed.

The `runConnectedRepoGit` wrapper covers the destructive-verb class (`rm`/`reset`/`amend`/`--force`) so future maintainers cannot regress the agent process to bare `execFileSync("git", ...)` calls without an explicit error.

For the second-reviewer concur gate: the failure mode where a single agent rationalizes a scope-out is real (`/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`). Today's session validated the gate on F2 — without the dissent, the destructive-verb class would have shipped to a follow-up issue and likely sat there indefinitely.

## See also

- `apps/web-platform/server/session-sync.ts` — the connected-repo writer
- `apps/web-platform/server/workspace.ts:provisionWorkspace` — the bootstrap-path scope-out
- `.github/scripts/check-{settings-integrity,pr-body-vs-diff,auto-commit-density}.sh` — guard scripts
- `.github/scripts/test/` — bash fixture tests (settings 6, density 6, body-vs-diff 7)
- `.github/workflows/pr-quality-guards.yml` — 4-job CI workflow
- AGENTS.md `hr-never-git-add-A-in-user-repo-agents` — the codified rule
- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — multi-reviewer gate justification
- `knowledge-base/project/learnings/2026-04-24-fake-git-author-bare-repo-bot-override.md` — sibling failure mode in the bare-repo identity surface
