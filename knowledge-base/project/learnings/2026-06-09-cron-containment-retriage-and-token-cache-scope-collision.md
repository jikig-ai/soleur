# Learning: classify cron containment by the invoked skill's body, not its surface verbs — and key a memoized credential cache on scope, not identity alone

date: 2026-06-09
issue: "#5046"
branch: feat-tier2-cron-egress-firewall
category: security-issues

## Problem

PR-1 of #5046 (Tier-2 cron containment) was scoped to (a) **restore** 3 of 11 paused
claude-spawning crons by adding per-cron Bash allowlists under the #5018 deny-by-default hook, and
(b) **narrow** the cron GitHub-App installation token. A committed re-triage (AC1 evidence) had
classified `cron-bug-fixer`, `cron-agent-native-audit`, and `cron-legal-audit` as **allowlistable**
based on a surface read of their top-level `gh`/`git` verbs.

Tracing the actual skill bodies the crons invoke proved **all three were misclassified** — none can
run under the containment hook:

- **agent-native-audit / legal-audit** structurally require the **`Task` tool** (8 parallel
  sub-agents / the `legal-compliance-auditor` agent — `SKILL.md:37` / `:44`). The hook's `decide()`
  routes `Task` to its catch-all `deny` ("sub-agent classes are denied until the Tier-2 firewall
  lands; no Tier-1 cron needs these"). A perfect Bash allowlist is irrelevant when the skill's core
  mechanism is a denied tool class.
- **bug-fixer** → `/soleur:fix-issue`, whose Phase 2–6 bash (read from the SKILL.md, not inferred
  from the cron prompt) depends on `node -e "$(…)"` (command substitution), `eval "$TEST_CMD" | tail`
  (pipe), `bash …/worktree-manager.sh` (interpreter), `git worktree`/`git branch`, and
  `gh pr create --body "$(cat <<EOF)"` (substitution) — every one hook-denied. The **original**
  Tier-1 defer rationale ("bash that cannot be expressed as a finite allowlist") was correct.

Separately, the token-narrowing half had a latent **silent over-privilege bug**:
`generateInstallationToken`'s in-memory token cache was keyed on `installationId` **alone**. Every
cron resolves the SAME `jikig-ai/soleur` installation id, so a narrowed cron token and the broad
token the ~10 interactive/agent callers mint would cross-serve from one cache entry — whichever was
minted first wins, silently granting broad scope to a caller that asked for narrow (or 403-ing a
broad caller served a narrow token).

## Solution

**Restore half → dropped.** Re-verified AC1 against the skill bodies; reclassified all 3 →
needs-firewall. `TIER2_DEFERRED_CRONS` unchanged; no allowlist entries added. This realized the
plan's own risk **R3** ("if few of the 11 are cleanly allowlistable incl. bug-fixer = CPO #1, PR-1's
restore scope shrinks… AC1 surfaces this with evidence rather than discovering it mid-build"). The
operator confirmed **token-narrowing only** when surfaced. All 11 wait for PR-2 (the egress firewall
can relax the hook's `Task`/`Skill`/egress denials once exfil is contained at the network layer).

**Token narrowing → shipped, scope-keyed cache.**
- `generateInstallationToken(id, { permissions?, repositories? })` posts a scoped access_tokens body
  AND folds the scope into the cache key. Unscoped callers keep the bare-id key (zero behavior
  change); scoped callers get `${id}|${JSON.stringify({p:sortedEntries, r:sortedRepos})}` —
  JSON-serialized so a value containing a delimiter can never alias another scope's key.
- `mintInstallationToken` threads the scope; `DEFAULT_CRON_TOKEN_PERMISSIONS =
  {contents,issues,pull_requests}:write`. **Opt-in per cron, NOT a blanket default** — enumerating
  every live cron's GitHub API surface showed 6+ need scope outside that envelope (workflow-dispatch
  crons need `actions:write`, `gh-pages-cert-state`/`plausible-goals` need `pages`,
  `ruleset-bypass-audit` needs `administration:read`, content crons need `checks:write`). A blanket
  narrow default would have silently 403-ed all of them.
- Applied to `cron-daily-triage` + `cron-follow-through-monitor` (verified issue-bounded: allowlisted
  Bash is `gh issue …` only) + `repositories:["soleur"]`.

## Key Insight

1. **A cron's containment class is a property of the SKILL BODY it invokes, not the verbs in the
   cron prompt.** `/soleur:fix-issue` looks like "gh + git verbs" from the cron prompt; its actual
   Phase 2–6 bash is full of `$()`/pipes/`eval`/`node -e`/`bash <script>`. Classify by reading the
   invoked SKILL.md end to end, and use the one validated Tier-1 cron (`roadmap-review` — *invokes no
   skill and no `Task`*) as the template for "what the hook permits." A denied **tool class**
   (`Task`/`Skill`) defeats any Bash allowlist.
2. **A memoized credential factory keyed on identity alone silently cross-serves differently-scoped
   requests.** When narrowing ONE consumer's credential, the cache key must include the scope, or the
   narrow token leaks to broad callers (and vice versa). The fail mode is silent over-privilege —
   exactly the property the narrowing was meant to remove.
3. **Before changing a shared default to "secure by default," enumerate every consumer's real
   surface.** A blanket `{contents,issues,pull_requests}` default is *less* safe than full-grant when
   6+ siblings legitimately need `actions`/`pages`/`administration`/`checks` — it converts a
   security win into a silent multi-cron outage. Narrow opt-in; widen by enumeration.

## Session Errors

- **`git branch --show-current` exited 128** — run from the bare repo root, not the worktree.
  Recovery: `cd` into `.worktrees/<branch>`. Prevention: in a worktree task, `cd` to the worktree
  before any git op (one-off; adjacent to `hr-when-in-a-worktree-never-read-from-bare`).
- **Edit rejected "File has not been read yet"** — viewed `cron-daily-triage.ts` via `sed`/Bash, which
  does not satisfy the harness Read-before-Edit tracking. Recovery: Read tool, then Edit. Prevention:
  use the Read tool (not `sed`) before Edit (`hr-always-read-a-file-before-editing-it`). One-off slip.
- **Two cron test assertions failed after the mint-arg change** — expected: the change intentionally
  added `permissions`/`repositories` to the asserted `generateInstallationToken` call. Recovery:
  updated the assertions. Not a defect.
- **Full-suite surfaced 1 unrelated failure** (`live-repo-badge.test.tsx` — `purgeWorkspaceLogoObjects`
  missing on a leaked `@/server/workspace` mock). Recovery: confirmed pre-existing + isolation-only
  (passes standalone), filed **#5074**. Prevention: the recurring class is incomplete shared-module
  mock factories that leak across files in the same worker — tracked in #5074 (extract a lockstep
  `@/server/workspace` mock helper).

## Tags
category: security-issues
module: server/github-app, server/inngest/functions/_cron-shared, cron-containment
