---
lane: "cross-domain"
issue: 9403
related_issues: ["#9398", "#9399", "#9400", "#9401", "#9402", "#5086", "#8611"]
brand_survival_threshold: "single-user incident"
---

# Feature: Pipeline cost tally + budget caps for autonomous loops (#9403)

Brainstorm: [`knowledge-base/project/brainstorms/2026-10-01-pipeline-cost-tally-brainstorm.md`](../../brainstorms/2026-10-01-pipeline-cost-tally-brainstorm.md).

## Problem Statement

Autonomous pipelines (one-shot, drain-*, resolve-*, test-fix-loop, work,
eval-harness) spend real work — review seats spawned, fix rounds, CI cycles,
agent rounds — but print no running tally. The operator only learns the cost
shape after the run ends (observed on PR #9339: a small fix cost an 11-seat
review and ~8 CI cycles). There is no mechanism to bound a runaway loop before
it burns the next expensive step.

## Goals

- Every AUTONOMOUS_LOOP_SKILL reports a running tally of activity units at phase
  boundaries.
- Per-dimension budget caps (`--max-seats`, `--max-ci-cycles`, `--max-fix-rounds`,
  `--max-agent-rounds`) with a two-threshold contract: soft cap flags and
  continues; hard cap produces a classified `budget-capped` stop at a phase
  boundary with `session-state.md` + resume prompt — never a blocking
  AskUserQuestion in an unattended run.
- The ship PR body carries a `## Pipeline Tally` section plus a machine-readable
  `Pipeline-Cost:` git trailer for cross-PR aggregation of the cost-reduction
  program (#9398–#9402).
- The tally includes a plain-language verdict line (elapsed time + "heavier than
  typical for this size") for the non-technical operator.

## Non-Goals

- Dollar figures or dollar budgets on local loops ($0-marginal Max-subscription
  doctrine, #5086; implied-billing risk per CLO). CI `claude-code-action` dollars
  stay capped at the `soleur-ci-eval` workspace level (#8505) — no second budget.
- Blocking pause gates of any kind.
- Extending `emit-decision.sh`'s frozen 2-event enum; hook-level (PreToolUse
  deny) enforcement — v1 counters are advisory + script-checked.
- Cross-run aggregation dashboard (trailers enable it; `operator-digest`
  fold-in is a candidate follow-up).
- Lead-session token capture (unteed today); v1 counts what's instrumentable.

## Functional Requirements

### FR1: Running tally

Each AUTONOMOUS_LOOP_SKILL prints a `tally: seats=N ci=N fix_rounds=N
agent_rounds=N` line at every phase boundary, sourced from a shared counter
file — a new `pipeline-tally.sh` script invoked as `tally incr <counter>` /
`tally show` writing under `<git-common>/soleur-session-state/counters/` via the
existing `with_lock`/`_session_state_root` substrate. Prose-only "emit a line"
instructions are NOT acceptable (measured ~zero compliance precedent:
emit-review-trailer.sh header) — increments are script invocations.

### FR2: Per-dimension budget caps

Flags `--max-seats N --max-ci-cycles N --max-fix-rounds N --max-agent-rounds N`
on each autonomous-loop skill, each carrying a non-firing-on-normal-runs
default (sized by summing per-skill baselines per the plan-sharp-edges cost-cap
rule). Each dimension has a soft threshold (warn + continue + flag in tally) and
a hard threshold (classified stop).

### FR3: Classified hard stop

On hard-cap breach the pipeline stops at the next phase boundary: writes/updates
the branch `session-state.md`, emits a resume prompt, and marks the run
`budget-capped` — the #8611 `--max-budget-usd` classified-stop shape. In
interactive sessions the soft cap MAY surface via AskUserQuestion; in headless
runs it NEVER blocks.

### FR4: PR-body + trailer reporting

`soleur:ship` Phase 6 PR body gains a `## Pipeline Tally` section placed before
`## Changelog` (respecting the ship-operator-step-gate / auto-close-scan /
release-extractor section constraints), plus a `Pipeline-Cost:` git trailer via
the `emit-review-trailer.sh` precedent for cross-PR aggregation.

### FR5: Workflow-port parity

`skills/*/workflows/*.workflow.js` report spawn counts and the native `budget`
object state back into the shared counters on return (PostToolUse hooks do not
see Workflow-runtime `agent()` spawns — counters must live in-workflow).

## Technical Requirements

### TR1: Counter substrate

New `plugins/soleur/scripts/pipeline-tally.sh` — bash 3.2-safe, fail-open
(counters must never red a pipeline), field-allowlisted counts-only payload (no
prompt text, args, or paths — emit-decision.sh NO-ECHO discipline), atomic
append or locked write via session-state.sh primitives. Persist across resumes
within a run; keyed per run/worktree branch.

### TR2: Cross-harness coverage

Counters are incremented by script invocation from skill prose (model-disciplined
on all harnesses) AND read/writable from workflow scripts; no dependence on
Claude-only hooks (agent-token-tee.sh is repo-local and misses workflow spawns).

### TR3: Term disambiguation

"Seat" in tally output = a spawned reviewer agent; MUST NOT read as Max
subscription seats (expenses.md usage). Spec/plan wording and output labels must
distinguish.

### TR4: Sentinel test extension

Extend `components.test.ts` AUTONOMOUS_LOOP_SKILLS coverage to assert the tally
invocation contract (script call presence at phase boundaries) — reuse the
existing sentinel pattern; no new legal prose (CLO).

### TR5: Observability

Per `hr-observability-layer-citation`: counter-write failure mode covered by the
fail-open contract + a `SOLEUR_TALLY_ABSENT`-style sentinel the ship summary
prints when no counter file exists (distinguishes "zero counted" from
"instrumentation never ran" — the quiesced-emitter trap).
