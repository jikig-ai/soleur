# Brainstorm: Pipeline cost tally + budget caps for autonomous loops (#9403)

**Date:** 2026-10-01
**Issue:** #9403 (OPEN, priority/p2-medium, type/chore, domain/engineering, meta/machinery, deferred-scope-out)
**Sibling set (cost reduction, all OPEN):** #9398 plan-scope check, #9399 risk-tiered review panel, #9400 affected-ratchets CI lane, #9401 merge-queue SHA policy, #9402 quarantine red checks
**Branch:** feat-one-shot-9403-cost-tally · **PR:** #9411 (draft)
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident (USER_BRAND_CRITICAL)

## What We're Building

A **running tally of activity units** — review seats spawned, fix rounds, CI cycles,
agent rounds — printed by every AUTONOMOUS_LOOP_SKILL at phase boundaries, plus
**per-dimension budget caps** with a warn-then-stop enforcement contract, plus a
`## Pipeline Tally` section and `Pipeline-Cost:` git trailer in the ship PR body.

No dollars anywhere on the local-loop path. Units only.

## Why This Approach

The issue asks for "cost visibility" and a "`--budget` pause". The prior-art sweep
refined both halves:

- **Units, never dollars.** The #5086 brainstorm (ADR-056) established that local
  autonomous loops run on the flat Max subscription at $0 marginal cost; per-loop
  dollar figures were rejected as manufacturing a false billing surprise. A unit
  tally surfaces *effort* honestly. CLO adds the legal edge: a rendered dollar
  estimate reads as metering and invites reliance claims the BSL "AS IS" clause
  would then carry; a unit tally cannot.
- **A blocking pause was rejected by the operator.** `one-shot`'s contract is
  explicitly "no per-phase approval gates"; a blocking AskUserQuestion at 2am
  strands a half-finished worktree with no notification channel. The shipped
  precedent is #8611's `--max-budget-usd` cron caps: a **classified hard stop**
  (`budget-capped`), never an operator question. Operator chose warn + hard stop.
- **Counters must be script invocations, not prose instructions.** Measured
  ~zero compliance on "emit a line" prose (emit-review-trailer.sh header). A
  `pipeline-tally.sh` helper on the `session-state.sh` root (git-common-dir —
  survives worktrees, resumes, sibling sessions) is the substrate; each skill
  calls `tally incr <counter>` at spawn/round boundaries.
- **Machine-readable trailer alongside human-readable PR section.** The
  `Reviewed-Coverage:` precedent (ADR-127 "record now, consume later") lets the
  cost-reduction program (#9398–#9402) measure whether it actually shrank spend.

## Key Decisions

| # | Decision | Rationale | Source |
|---|----------|-----------|--------|
| 1 | Tally denominated in units only: seats, fix rounds, CI cycles, agent rounds (+ tokens where the tee already captures them) | $0-marginal doctrine (#5086); CLO implied-billing guardrail | CPO, CLO, CFO |
| 2 | Budget = per-dimension caps: `--max-seats`, `--max-ci-cycles`, `--max-fix-rounds`, `--max-agent-rounds` | One scalar cannot compare unlike units; each limit checkable independently | Operator, CFO |
| 3 | Two thresholds: soft cap = flag-and-continue + PR annotation; hard cap = classified `budget-capped` stop at a phase boundary with session-state.md + resume prompt | Operator choice; #8611 classified-stop precedent; no stranded worktrees | Operator, COO |
| 4 | Scope = all AUTONOMOUS_LOOP_SKILLS (test-fix-loop, drain-labeled-backlog, resolve-todo-parallel, resolve-pr-parallel, work, one-shot, eval-harness) + workflow ports | The "nobody saw the cost" problem exists in every loop, not just one-shot | Operator |
| 5 | Counter substrate = new `pipeline-tally.sh` script writing per-run counters under `<git-common>/soleur-session-state/counters/` via `with_lock`/`_session_state_root` | Reuses shipped substrate; decisions.jsonl enum is a frozen 2-event contract (poor fit); hooks cover ~1.5/4 harnesses | Repo research |
| 6 | Surfaces: `tally:` line at phase boundaries; `## Pipeline Tally` in ship PR body (before `## Changelog`); `Pipeline-Cost:` git trailer | Trailer enables cross-PR aggregation for the cost-reduction program; template constraints on section placement | COO, repo research |
| 7 | Tally includes a plain-language verdict line (elapsed + "heavier than typical" comparison) | "11 seats, 8 CI cycles" is jargon to a non-technical operator | CPO |
| 8 | Never render dollar figures on the local-loop path; if a metered path ever shows $, label "estimate — your Anthropic bill governs" | CLO reliance-claim guardrail; #5086 honesty doctrine | CLO |
| 9 | Tally content is counts-only (no prompt text, args, paths) — same allowlist discipline as emit-decision.sh; note in spec that the PR-body section publicly discloses usage patterns | Public-repo disclosure is a choice, keep it metadata-only | CLO |
| 10 | Workflow ports keep their native `budget` object and report spawn counts into the shared counters; PostToolUse tee does not see `agent()` spawns | Workflow-runtime spawns are invisible to hooks (agent-token-tee.sh:107) | CTO, repo research |
| 11 | Visual design: N/A — no UI surface (CLI output + PR-body text only) | ui-surface-terms boundary | — |

## Non-Goals (deferred)

- **Dollar metering or dollar budgets on local loops** — rejected doctrine (#5086);
  CI `claude-code-action` dollars already capped at the `soleur-ci-eval` workspace
  level ($100/mo, #8505) — do not build a second dollar budget.
- **Blocking AskUserQuestion pause** — operator rejected; warn + hard stop instead.
- **Extending `emit-decision.sh`'s event enum** — frozen contract (ADR-254);
  a per-run counter ledger is a different artifact than routing telemetry.
- **Hook-level enforcement** (PreToolUse deny over-budget spawns) — blast radius
  too large for v1; counters are advisory + script-checked, not hook-denied.
- **Cross-run aggregation surface / dashboard** — trailers make it possible;
  `operator-digest` fold-in is a candidate follow-up, not this PR.
- **Lead-session token capture** — unteed anywhere today (prose lead context);
  v1 counts what's instrumentable and marks the rest.

## Open Questions (for plan)

1. **Default cap values** — sizing rule: sum per-skill baselines first
   (`plan-sharp-edges.md` cost-cap sizing convention). Defaults must not fire on
   a normal run.
2. **Counter granularity for "agent rounds"** — one-shot step boundaries vs
   Task-spawn count; pick the semantic the operator recognizes.
3. **Workflow-to-counter bridge** — how `*.workflow.js` runs write back into the
   shared counter file (journal → `tally incr` on return vs direct write).
4. **Soft-cap warn channel** — printed line only, or also a PR comment (COO
   suggested both; PR comment may notify where stdout doesn't).
5. **Term disambiguation** — "seat" already means Max subscription seats in
   expenses.md; the tally's "review seat" is a spawned reviewer agent. Spec must
   define both.
6. **Resume semantics** — does a budget pause carry counters across `soleur:work`
   resume, or reset per invocation? (session-state root suggests persist.)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Substrate map confirms counters are derivable for seats (trailer +
tee), fix rounds (test-fix-loop `--max` counter), and CI cycles (gh run list /
ship Phase-7 counters); agent rounds and prose-path spawn counts need new
instrumentation. Workflow ports already carry a native `budget` object.
Recommends a separate `.soleur`-adjacent counter script over extending the frozen
decisions.jsonl enum; pause = interactive AskUserQuestion or classified stop —
never a workflow-script prompt (they can't ask; return early with journaled
state).

### Product (CPO)

**Summary:** Support with reframe — activity units escape the #5086 objection
cleanly. The pause is the dangerous half: headless budget trips must never hang;
always-on tally + opt-in gate; needs a plain-language verdict line for the
non-technical operator.

### Legal (CLO)

**Summary:** Green-light, low risk. Units-only keeps the BSL disclaimer posture;
the cap makes "operate against your own budget" an operative control. Never
market as a "spend cap". Counts-only content; note public-repo disclosure.
Extend AUTONOMOUS_LOOP_SKILLS sentinel test rather than adding new legal prose.

### Finance (CFO)

**Summary:** Units answer the wrong question but are the best available proxy —
the real exposure is Max-20x rolling quota burn (429 interruptions on record),
not dollars. Recommends disaggregated `--max-*` flags; CI dollars already capped
at workspace level; Actions minutes hosted-vs-self-hosted caveat for "CI cycle"
cost semantics.

### Operations (COO)

**Summary:** Right mechanism only if machine-readable — `Pipeline-Cost:` trailer
plus human-readable section; two thresholds (warn + hard-stop); persist counters
under the shared session-state root; workflow spawns need in-workflow counters
since PostToolUse never sees them.

## Session Errors

None.
