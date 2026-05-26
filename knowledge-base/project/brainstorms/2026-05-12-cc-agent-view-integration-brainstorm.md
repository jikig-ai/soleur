---
title: CC Agent View Integration — Reframed as Concurrency Hardening + Cloud-UX Audit
date: 2026-05-12
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
source: https://claude.com/blog/agent-view-in-claude-code
---

# CC Agent View "Integration" Brainstorm

## What We're Building

**TL;DR: We are NOT integrating Agent View.** The blog post describes a Claude Code CLI-internal feature (`claude agents`, `/bg`, `claude --bg`) with zero third-party integration surface. After 4-leader assessment (CPO/CLO/CTO/CMO) the original framing was rejected and the brainstorm was reframed into two independent work streams:

1. **Concurrency hardening (THIS spec, full /bg-readiness scope)** — make Soleur's worktree + SessionStart hooks safe under N-parallel CC sessions. Pays the 2026-04-21 unpaid bill and makes `/bg`-driven Agent View sessions safe as a free side-effect.
2. **Cloud-UX audit (deferred tracking issue)** — does Agent View's row-per-session UX vocabulary inform the design of Phase 3.3 conversation inbox / Phase 3.21 agent work visualization on app.soleur.ai?

Rejected: marketing/competitive-intel blog (CMO option), Kill option. User selected hardening + cloud-UX audit only.

## Why This Approach

Anthropic shipping Agent View is a **competitive-intelligence signal, not a build prompt**. CPO: investing cycles in CLI-plugin polish conflicts with the cloud-first roadmap pivot (roadmap.md:16 — "no one wants to install a Claude Code plugin"). CTO: there is no integration surface — no API, no hook, no MCP server, no documented status file. CMO: Anthropic shipped the CLI primitive; app.soleur.ai captures the 90% who won't `brew install`. The only useful response is to (a) make our own concurrency model safe so `/bg`-driven sessions don't break Soleur workflows, and (b) audit our own cloud-side multi-session UX surfaces against the vocabulary Anthropic just defined.

## User-Brand Impact

**Artifact:** Soleur operator's in-flight work — feature worktrees, draft PRs, branch state.
**Vector:** A second CC session (`/bg` or otherwise) running SessionStart's `cleanup-merged` reaps a sibling session's worktree mid-flight, wiping local commits and orphaning the draft PR.
**Threshold:** `single-user incident`. The 2026-04-21 incident already happened once; making `/bg` a recommended workflow without hardening would convert "occasional collision" into a default failure mode.

This is operator-data loss, not end-user PII loss, but the rule applies (per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`): a single operator losing committed-but-unpushed work is a brand-survival event for a dev-tools product.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Kill literal "Agent View integration" framing | No integration surface exists. Blog post confirms feature is CLI-internal. |
| 2 | Scope this worktree to **full /bg-readiness** concurrency hardening | User-selected. Closes 2026-04-21 incident class + makes `/bg` officially supportable. Splits into 3-4 sub-issues per CTO. |
| 3 | Defer cloud-UX audit to separate tracking issue, aligned with Phase 3.21 | Different domain (product/design vs engineering). Should run when Phase 3.21 "agent work visualization" is active, not before. |
| 4 | Reject CMO marketing thread (competitive-intel row + blog post) | Not user-selected. Can be filed independently if marketing chooses. Not blocking. |
| 5 | Apply 2026-03-17 PPID session-scoping pattern as the lock primitive | Proven precedent in same bare-repo+worktree topology. Avoids cross-session lock contention. |
| 6 | Marketing/positioning surfaces must NOT reference Agent View | Per CMO read: re-tethering messaging to the CLI deepens the cloud-first contradiction. Silent-and-compatible is correct. |

## Open Questions

- Should the SessionStart hook detect headless `/bg` invocations and skip the full cleanup pass entirely? (vs. running cleanup with a session-claim file check.) Plan-time decision.
- Does Anthropic's `claude --bg [task]` write any local state file that Soleur could *read* (not as integration but as a "do not reap" hint)? Worth a 5-min check at plan time — `find ~/.claude -name '*bg*' -newer /tmp/$(date +%s)` after a `/bg` launch.
- For the cloud-UX audit: does Phase 3.21's existing design (if any) already match Agent View's vocabulary, or does it diverge? Out-of-scope here.

## Approaches Considered

**Approach 1 — Concurrency hardening (CTO) (chosen).** Pay the unpaid bill: flock + grace window + push-on-create + PPID claims + hook TTY restructure + sidecar-loader locks + concurrent-merge guard. ~12 hook files touched. /bg works as side effect.

**Approach 2 — Marketing-only response (CMO) (rejected).** Add competitive-intel row + write validation blog post. No code. User did not select.

**Approach 3 — Cloud-UX audit (CPO) (deferred).** Design audit of Phase 3.3 + 3.21 against Agent View vocabulary. User selected but defers to a separate worktree aligned with Phase 3.21 active work.

**Approach 4 — Kill the brainstorm (rejected).** Do nothing. User did not select.

**Approach 5 — Wrap Agent View (rejected pre-question).** Build a Soleur skill that proxies `claude agents` output. Killed by CTO at Phase 0.5 — no API to wrap.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Zero integration surface. Real risk is existing concurrency bugs (4 named: fetch race, cleanup-merged sibling-wipe, sidecar-loader contention, concurrent gh-pr-merge). Verdict: REFRAME to concurrency hardening. /bg/Agent View safety falls out for free once primitives land.

### Product (CPO)

**Summary:** Cloud-first roadmap pivot (roadmap.md:16) means CLI-plugin polish is unfunded effort attracting the wrong cohort (CMO's recruitment-mix cap: ≤7/10 founders are CC users). Phase 3.21 agent work visualization IS Soleur's answer. Anthropic shipping Agent View is CI signal, not build prompt. Verdict: REFRAME to cloud-UX audit (deferred).

### Legal (CLO)

**Summary:** GREEN. No blockers. One YELLOW on marketing-copy trademark footer ("Claude Code and Agent View are products of Anthropic; Soleur is not affiliated") IF marketing thread were chosen — moot since user rejected CMO thread.

### Marketing (CMO)

**Summary:** Agent View is a tailwind, not a threat — validates parallel-agent thesis without contradicting cloud pivot. Two zero-code deliverables proposed (CI row, validation blog). Operator-facing Soleur surfaces should remain silent-and-compatible (do NOT add Agent View references to /soleur:go or /soleur:one-shot). Verdict: PARK on integration. (User rejected the marketing deliverables; CMO findings retained for future reference.)

## Capability Gaps

- **Cross-session lock primitive in worktree-manager.sh.** Currently no `flock`-wrapped section. Verified by `grep -n flock plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` → 0 matches. Needed to prevent concurrent `cleanup-merged` reaping an active worktree.
- **Session-claim/lease pattern.** No `*.lock` or `*.lease` files written by `/soleur:one-shot`, `/soleur:drain-labeled-backlog`, or `/soleur:brainstorm`. Verified by `find .worktrees -name '*.lock' -o -name '*.lease' 2>/dev/null` → 0 matches. Needed for the grace-window heuristic to know which worktrees are actively in use.
- **Structured-log fallback for hooks.** Multiple hooks gate verbose output on `[[ -t 1 ]]`. Confirmed in `worktree-manager.sh:737`. Backgrounded sessions have no TTY → verbose paths suppressed silently → failure modes invisible to operator. Needed: hooks log to a structured file when no TTY, with a path the Agent-View attach session can tail.
- **`/bg` detection heuristic.** No code path distinguishes a foreground operator session from a `claude --bg`-spawned session. Needed if we want SessionStart to behave differently in headless mode (e.g., skip prompt-required gates).

## Reference Material

- Blog post (read 2026-05-12): https://claude.com/blog/agent-view-in-claude-code
- Seed incident: `knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`
- Lock-primitive pattern: `knowledge-base/project/learnings/2026-03-17-session-scoped-state-files-via-ppid.md`
- TOCTOU guards: `knowledge-base/project/learnings/2026-03-18-stop-hook-toctou-race-fix.md`
- Stale-worktree precedent: `knowledge-base/project/learnings/2026-02-21-stale-worktrees-accumulate-across-sessions.md`
- Orphan recovery: `knowledge-base/project/learnings/2026-03-09-ralph-loop-crash-orphan-recovery.md`
- Branch-wipe class: `knowledge-base/project/learnings/2026-02-19-never-use-delete-branch-with-parallel-worktrees.md`
- Bare-repo config bleed: `knowledge-base/project/learnings/2026-04-02-bare-repo-config-bleed-worktrees.md`
- SessionStart matcher contract: `knowledge-base/project/learnings/2026-03-04-sessionstart-hook-api-contract.md`
- Resume architecture (cloud-side, adjacent): `knowledge-base/project/learnings/2026-03-27-agent-sdk-session-resume-architecture.md`
- Strategic context: `knowledge-base/product/roadmap.md` (last_updated 2026-05-11)

## Lane

Lane: cross-domain (USER_BRAND_CRITICAL=true override; no operator override applied).
