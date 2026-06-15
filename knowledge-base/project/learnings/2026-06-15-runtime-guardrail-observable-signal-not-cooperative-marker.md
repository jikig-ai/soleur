---
title: "A runtime guardrail for agent-misbehavior must key on an OBSERVED side-effect, never the agent's own cooperative signal"
date: 2026-06-15
category: best-practices
tags: [guardrail, agent-runtime, detector-design, union-widening, regex, cwd, web-platform, soleur-go-runner]
module: apps/web-platform/server (soleur-go-runner)
issue: 5313
parent_epic: 5240
related_pr: 5311
---

# Learning: runtime guardrails key on observed side-effects, not cooperative markers

Four generalizable lessons from implementing the #5313 CWD-verify-loop guardrail (the runtime safety
net for the Concierge worktree-rebind loop). The mechanism learning (file-tools-in-process vs Bash-bwrap)
is in `2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`; this captures the
DESIGN+IMPLEMENTATION lessons.

## 1. A guardrail for behavior X must detect X by an OBSERVABLE side-effect, never by a signal X must cooperatively emit

The v1 plan keyed the runtime loop-breaker on a *structured marker the agent emits after 3 failed
verifications*. But the entire premise of the bug is that **the agent ignores prose contracts** — the
one-shot gate already said "abort on mismatch" and the live agent looped anyway. A marker the agent
must emit is exactly as ignorable as the "abort" it already ignored. Three plan-review agents
(Simplicity, SpecFlow, Kieran) independently converged on this as the load-bearing hole.

**Fix:** the detector keys on **observed Bash tool-results** (`extractBashToolResults` in
`soleur-go-runner.ts:handleUserMessage`) — it counts N=3 consecutive `cd <path> && pwd` commands whose
`pwd` output mismatches the target, with zero agent cooperation. **Generalizable rule:** when building a
runtime guard against an agent misbehaving, the trigger must be something the runtime *observes the
agent doing*, never something the agent must *choose to report*. The misbehaving agent is, by
definition, not a reliable reporter of its own misbehavior.

## 2. A union member's blast radius = whether each consumer REFERENCES or INLINES the source enum

Kieran (in plan-review, for the originally-considered `WSErrorCode` design) flagged that
`ws-zod-schemas.ts` hand-maintains a *duplicate* `z.enum([...18 literals...])` that a `grep WSErrorCode`
type-name search MISSES → a new variant passes `tsc` but throws at the wire-validation boundary at
runtime. That risk is REAL for `WSErrorCode`. But the chosen design used a `WorkflowEnd` *status*, and
`ws-zod-schemas.ts:501` does `z.enum(WORKFLOW_END_STATUSES)` — it REFERENCES the single-source tuple, so
adding one member to `lib/types.ts` auto-propagates and three `tsc`-enforced rails
(`_AssertWorkflowEndStatusMatches`, `WORKFLOW_END_USER_MESSAGES`, `_abortFlushExhaustive`) catch any
miss. **Lesson:** before sizing a union-widening sweep, grep whether each consumer *references* the
source symbol or *inlines* its literals. The design choice (which union to extend) can dissolve the
sweep entirely — choosing the referencing union turned a 4-consumer manual sweep into a one-line tuple
edit + compiler enforcement.

## 3. A detector whose match-predicate is broader than its reset-predicate false-positives on the HEALTHY case

`parseCwdVerifyTarget`'s regex initially tolerated a trailing `&& git branch …` continuation
(`…&& pwd\b`), but the success-reset compared the FULL trimmed output to `expectedPath`. A *successful*
`cd <wt> && pwd && git branch` prints `"<wt>\n<branch-output>"` — which never equals `<wt>` — so the
counter would falsely accumulate toward the threshold on a **healthy** worktree. Caught by
code-quality-analyst at review (P2). **Fix:** end-anchor the regex (`…&& pwd\s*$`) so the match-predicate
and the success/reset-predicate are symmetric. **Generalizable:** whenever a detector has a "this is the
pattern" predicate AND a "this is the success/reset" predicate, an asymmetry between them is a
false-positive on the good case, not the bad case — keep the two predicates exactly as wide as each
other.

## Key Insight

A guardrail's trust model is its design: it must observe, not ask; its detection and reset predicates
must be symmetric; and the cheapest union-widening is the one whose consumers reference a single source.

## Tags

category: best-practices
module: apps/web-platform/server (soleur-go-runner)

## Session Errors

1. **CWD-drift made semgrep + a diff-grep run against the bare root, not the branch** — a `cd` inside a
   prior `git commit` Bash command persisted, so `cd /home/jean/.../soleur && semgrep apps/...` and
   `git diff … -- apps/...` scanned MAIN's code (false "path.join findings", false "0 added lines").
   Ironic given the feature fixes a CWD-confusion loop. **Recovery:** re-ran both with an explicit
   `cd <worktree-abs> &&` prefix; semgrep on the branch was clean. **Prevention:** already covered — the
   work skill mandates chaining `cd <worktree-abs> && <cmd>` in a single Bash call (the Bash tool does
   not persist CWD reliably), and `test-all.sh` hard-refuses the bare root (that guard fired correctly).
   One-off; no new rule warranted.
