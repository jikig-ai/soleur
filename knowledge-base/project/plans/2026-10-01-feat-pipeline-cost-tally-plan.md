---
title: "feat(one-shot): cost visibility — running tally of seats, fix rounds and CI cycles with a budget pause"
type: feat
date: 2026-10-01
slug: feat-pipeline-cost-tally
branch: feat-one-shot-9403-cost-tally
issue: 9403
closes: 9403
domain: engineering
priority: p2-medium
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: Pipeline cost tally + budget caps for autonomous loops

## Overview

Every autonomous-loop skill gains a running tally of activity units — review
seats spawned, fix rounds, CI cycles, agent rounds — printed at phase
boundaries, plus opt-in per-dimension budget caps with a warn-then-classified-stop
contract. `soleur:ship` renders the final tally into the PR body as a
`## Pipeline Tally` section carrying a machine-readable `Pipeline-Tally:` line.

No dollars are rendered anywhere on the local-loop path: the counters are units
of work, which is the honest currency for $0-marginal Max-subscription runs
(#5086 doctrine, brainstorm Decision 1).

## Problem Statement / Motivation

Observed on PR #9339 (disk-leak fix, merged 2026-10-01): a small fix consumed an
11-seat review panel, several fix rounds and ~8 CI cycles — and nobody saw the
shape until the end. Autonomous pipelines print no running tally, so runaway
cost shape is only ever discovered post-hoc. The issue asks for (a) a running
tally, (b) a pause at a configurable budget, (c) the tally in the PR summary.

## Proposed Solution

A shared counter script `plugins/soleur/scripts/pipeline-tally.sh` writing a
per-branch flat `key=value` counter file under
`<git-common-dir>/soleur-session-state/counters/` (the `session-state.sh`
lock/root substrate's own idiom — grep+cut, no jq), invoked by skill prose at
spawn/round/phase boundaries — script calls, not described prose (the
`emit-review-trailer.sh` precedent: described emits have measured ~zero
compliance). Budget caps are per-dimension flags
(`--max-seats`, `--max-ci-cycles`, `--max-fix-rounds`, `--max-agent-rounds`)
persisted into the counter file at `init` so they survive skill-to-skill
handoff; crossing the soft threshold flags-and-continues, crossing the hard cap
sets `capped=<dim>` and produces a classified `budget-capped` stop at the next
phase boundary — the #8611 `--max-budget-usd` shape, never a blocking prompt in
an unattended run. On Claude a second, mechanical floor lives in the shipped
`stop-hook.sh`: when the branch's counter file carries `capped`, the hook
declines to continue the loop (exits 0, prints the `budget-capped` reason to
stderr) — the cap is enforced even when prose bookkeeping never ran.

## Research Insights

**Premise validation (Phase 0.6).** #9403 OPEN; PR #9339 verified MERGED
2026-10-01; siblings #9398–#9402 all OPEN. Substrate claims verified against
the worktree: `session-state.sh` exports `with_lock`/`_session_state_root`/CLI
shim (`session-state.sh:619-635`) and `_safe_worktree_name`;
`emit-review-trailer.sh` lives at `plugins/soleur/skills/review/scripts/`;
`AUTONOMOUS_LOOP_SKILLS` = {test-fix-loop, drain-labeled-backlog,
resolve-todo-parallel, resolve-pr-parallel, work, one-shot, eval-harness}
(`components.test.ts:308-316`); workflow `budget`/`budgetOk()` globals exist in
5+ `*.workflow.js` (runtime globals — not returned fields);
`stop-hook.sh` is an unconditional plugin hook (`hooks.json`) carrying a
`{"decision":"block","reason":…}` channel; flag-scan convention confirmed
(`--max`, `--label`, `--dry-run`, `--headless`, `--full`). macOS lacks util-linux
`flock` (`_session_state_require_flock` rc=99, polyfill deferred,
`session-state.sh:57`) — counters degrade to `UNKNOWN` there, never STOP.

**Property List (Phase 0.6b).** P1 operator sees accumulated unit cost DURING
the run · P2 a configured cap produces a stop-for-decision · P3 the tally lands
durably in the PR · P4 tallies aggregate across PRs (program measurement).

**Cut List (Phase 0.6b).** Blocking prompt pause → rejected by operator; #8611
classified-stop covers P2. Dollar budget → cut (ADR-056 + CLO). Extending
`emit-decision.sh` enum → frozen 2-event contract. PreToolUse hook enforcement →
deferred (coverage ~1.5/4 harnesses; v1 blast radius). Git `Pipeline-Cost:`
trailer → cut at review: `gh pr merge --squash` derives main's commit from PR
title/body, so branch-commit trailers never reach `origin/main` — P4 reads PR
bodies instead.

**Value-proposition measurement (Phase 0.6c).** The saving claim is
observability/early-stop, denominated in units — the tally IS the measuring
instrument. Measurable stakes: the #9339 incident shape (11 seats / ~8 CI
cycles on a small fix) and ~35 min/CI-cycle (ship Phase-7 convention).

**Consolidated research (Phase 1).** Seven-agent brainstorm fan-out +
functional-discovery sweep (no community substitute — every tool denominates
tokens/dollars and depends on Claude-only hooks; borrow the counter-file
substrate idea from AWS `token_budget_guard.sh` and the warn→block ladder from
`Belkins/cost-guardian`).

## Technical Considerations

- **Counter file** — `<git-common>/soleur-session-state/counters/<slug>` where
  `<slug>` is `_safe_worktree_name($BRANCH)` (handles `feat/foo`); flat
  `key=value` lines, rewritten wholesale under `with_lock`:
  `seats=N`, `ci_cycles=N`, `fix_rounds=N`, `agent_rounds=N`,
  `cap_<dim>=N`, `warned_<dim>=<at-count>`, `capped=<dim>`, `run_id`, `started_at`.
  Branch-keyed: a one-shot→work→review→ship pipeline shares one ledger; a
  resume continues it (same branch → same file). Two worktrees cannot share a
  branch (git forbids it), so per-branch is collision-free; concurrent sessions
  on the same checkout aggregate — documented as intended (the branch's PR
  carries the aggregate). Detached HEAD writes `HEAD`; the
  `/tmp/soleur-session-state-orphan` fallback appends the repo basename to the
  counters dir so repos don't collide.
- **`init` semantics** — idempotent merge: preserves counters, merges new caps;
  auto-resets when the file carries `capped` or `started_at` older than 24h
  (stale-ledger continuation must not STOP a fresh run by accident); `--reset`
  forces a fresh ledger; opportunistically sweeps sibling counter files with
  mtime >30d.
- **`incr <dim> [n]`** — missing/unreadable file → `SOLEUR_TALLY_ERROR reason=missing-file`,
  prints `UNKNOWN`, exit 0 — never auto-creates (auto-create would make the
  init-after-incr ordering defect undetectable).
- **`gate <dim>`** — reads caps from the FILE (not argv — argv dies at skill
  boundaries); prints `OK` | `WARN` (≥80% of cap, records `warned_<dim>`) |
  `STOP` (≥cap or `capped` set); substrate failure → `UNKNOWN` +
  `SOLEUR_TALLY_ERROR` on stderr. `UNKNOWN` under any configured cap must be
  rendered by ship as `cap-unenforced`, never a clean tally.
- **STOP contract** — on `STOP` the skill writes `specs/<branch>/session-state.md`
  with a `budget-capped` marker + resume prompt and exits the phase cleanly;
  `capped=<dim>` persists so every subsequent `gate`/`init` returns `STOP`
  until caps are raised (`--reset` + new `--max-*`) — a budget-capped run
  cannot be accidentally resumed under the same caps. Parent skills
  (one-shot dispatching work/review/ship children) check the session-state
  marker before dispatching the next child — a child's stop halts the pipeline.
- **Flags** — `--max-<dim> N`: `10#` normalization (rejects `08`), rejects
  non-numeric/negative/`0` with a readable error (emit-review-trailer's
  validation shape). Each skill parses only the flags for dimensions it
  produces (`review`/`one-shot` → seats; `test-fix-loop` → its existing
  `--max` aliases `--max-fix-rounds`; `ship`/`work` → ci_cycles;
  drain/resolve-* → agent_rounds). Flags write `cap_<dim>` at `init`.
- **Workflow bridge** — `drain-labeled-backlog`, `resolve-todo-parallel`,
  `resolve-pr-parallel` workflow ports add a `counts:{…}` field to their
  report object; the invoking prose posts it via `incr`. One writer per
  dimension per invocation (prose site OR workflow-return — never both).
- **Fleet-skill attribution** — drain/resolve-* spawn work on per-item
  branches; their counters post to the dispatcher's ledger via
  `--branch <item-branch>` override on `incr`, so the item branch's PR carries
  its own tally; branch-isolation is intended (no cross-branch rollup in v1).
- **PR-body surface** — ship Phase 6 inserts `## Pipeline Tally` before
  `## Changelog` in BOTH templates (`gh pr edit` :1842 and `gh pr create`
  fallback :2037): counts + `warned`/`capped` events + a
  `Pipeline-Tally: seats=N; ci_cycles=N; fix_rounds=N; agent_rounds=N`
  machine line (the P4 aggregation surface — reads PR bodies, not commits).
  No comparative "typical" verdict in v1 — no baseline exists; counts +
  cap-fraction (`3 of 5 seat budget`) + a one-line glossary
  (`seats = reviewer agents spawned`) instead. Absent file →
  `SOLEUR_TALLY_ABSENT` sentinel; present-but-zeroed → `tally: 0` +
  "no counted operations" note (distinct from absent).
- **Soft-cap warn** — stdout line + `warned_<dim>` key + PR-body render.
  No AskUserQuestion anywhere (cut list).
- **Stop-hook floor (Claude)** — `plugins/soleur/hooks/stop-hook.sh` gains a
  read-only check before it decides to keep a loop alive: if the branch's
  counter file carries `capped=<dim>`, the hook exits 0 (declines to block,
  starving the loop) and prints `SOLEUR_TALLY_CAPPED dim=<d> cap=<n>` + the
  resume prompt to stderr. Negative enforcement — it removes the fuel, it does
  not deny a tool. `init --reset` clears `capped`, so a raised-cap resume
  unblocks cleanly. Non-Claude harnesses have no Stop hook: the prose `gate`
  remains the only layer there (documented, not silent).
- **Eval-harness** — carries `init`/`gate`/`incr agent_rounds` only where real
  boundaries exist; not force-fitted.
- **macOS caveat** — no `flock` → `with_lock` unavailable → counters go
  `UNKNOWN`; documented limitation until the session-state polyfill lands.

## User-Brand Impact

- **If this lands broken, the user experiences:** a pipeline that reports false
  unit counts, or a budget cap that silently never fires — the operator sees
  "bounded" while a runaway loop burns uncapped.
- **If this leaks, the user's [workflow] is exposed via:** a public PR-body
  tally disclosing automation scale under the operator's GitHub identity
  (counts-only, no content — accepted, disclosed in the plan).
- **Brand-survival threshold:** `single-user incident`

CPO sign-off: satisfied via brainstorm Phase 0.5 CPO assessment + plan-review
named-panel (approve-with-conditions, all conditions applied);
`soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: "pipeline-tally.sh selfcheck exit + counter-file presence under <git-common>/soleur-session-state/counters/"
  cadence: "per skill invocation (every AUTONOMOUS_LOOP_SKILL calls init/incr/gate)"
  alert_target: "ship summary line SOLEUR_TALLY_ABSENT when a run produced no counter file"
  configured_in: "plugins/soleur/scripts/pipeline-tally.sh; plugins/soleur/skills/ship/SKILL.md Phase 6"
error_reporting:
  destination: "stderr marker SOLEUR_TALLY_ERROR reason=<k> (fail-open — never reds a pipeline); PR body SOLEUR_TALLY_ABSENT / cap-unenforced sentinels"
  fail_loud: "SOLEUR_TALLY_ABSENT when zero increments recorded for a run that claims instrumentation; SOLEUR_TALLY_CAP_IGNORED when capped is set but the run shipped anyway"
failure_modes:
  - mode: "counter file never created (script missing, disabled, or call sites stripped)"
    detection: "ship emits SOLEUR_TALLY_ABSENT — distinguishes 'zero counted' from 'instrumentation never ran'"
    alert_route: "PR body + ship stdout"
  - mode: "hard cap breached but pipeline continued (gate verdict ignored)"
    detection: "components.test.ts sentinel asserts anchored call form per skill; ship checks capped key → SOLEUR_TALLY_CAP_IGNORED"
    alert_route: "CI red on components.test.ts; PR body sentinel"
  - mode: "concurrent increments lose updates"
    detection: "pipeline-tally.test.sh concurrent-incr arm under flock"
    alert_route: "test suite red"
  - mode: "caps configured but substrate unreadable (no flock, orphan root, corrupt file)"
    detection: "gate prints UNKNOWN; ship renders cap-unenforced"
    alert_route: "stderr marker + PR body"
logs:
  where: "counter file + stderr markers; counter files reaped opportunistically by init (mtime>30d)"
  retention: "per-branch; stale-file sweep inside init — no new housekeeping infrastructure"
discoverability_test:
  command: bash plugins/soleur/scripts/pipeline-tally.sh selfcheck
  expected_output: SOLEUR_TALLY_OK
```

## Guard Contract

### Guard 1 — `tally gate` classified stop

**Property.** When any dimension's counter reaches its persisted hard cap, the
pipeline cannot proceed to the next expensive step; every subsequent `gate`/`init`
returns `STOP` until caps are raised.

**Assembly.** The `capped` key in the counter file is the chokepoint — `gate`
reads it before every counted operation; `init` honors it on resume. Call-site
population: every expensive-step boundary in the instrumented skills (asserted
by Guard 2).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `--max-ci-cycles 1`, drive a second CI cycle, call `tally gate ci-cycles` | RED — prints `STOP`, sets `capped`, writes session-state marker |
| 2 | Resume (`init`, no `--reset`) on a file carrying `capped` | RED — immediate re-STOP; livelock impossible |
| 3 | Remove `tally gate` call form from one skill's SKILL.md | RED — Guard 2 sentinel loses the anchored form |
| 4 | `init` after first `incr` (ordering swap) | RED — incr on missing file prints UNKNOWN+SOLEUR_TALLY_ERROR, never auto-creates; the zero-window is detectable |
| 5 | must-PASS control: `init`→`incr seats 3`→`gate seats` under `--max-seats 5` | PASS |

### Guard 2 — components.test.ts tally-contract sentinel

**Property.** Every AUTONOMOUS_LOOP_SKILL's SKILL.md carries the tally contract
(init + gate call form) from the canonical block documented in
`pipeline-tally.sh`'s header.

**Assembly.** The `AUTONOMOUS_LOOP_SKILLS` array is the population; the sentinel
scans each SKILL.md for the anchored call form.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the tally block from `one-shot/SKILL.md` | RED |
| 2 | Add a ninth skill name to AUTONOMOUS_LOOP_SKILLS with no marker | RED — array membership drives the assertion |
| 3 | Comment-only mention of `pipeline-tally.sh` | RED — anchored call-form match, never bare token |
| 4 | must-PASS control: existing 7 skills carrying the contract | PASS |

### Guard 3 — absent/zero/ignored-cap tri-state in ship

**Property.** ship renders ABSENT (no file) ≠ ZERO (instrumented, nothing
counted) ≠ CAP_IGNORED (`capped` set, run continued) — three distinct outputs.

**Assembly.** ship Phase 6's tally read + the counter file's `capped` key.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the counter file before ship Phase 6 | RED — `SOLEUR_TALLY_ABSENT`, not `tally: 0` |
| 2 | File present, all counters 0 | RED — `tally: 0` + "no counted operations", not ABSENT |
| 3 | `capped=ci_cycles` set, ship runs without raised caps | RED — `SOLEUR_TALLY_CAP_IGNORED` in PR body |
| 4 | Dispatch row: remove the absent branch from the ship read | RED — no-file fixture must still print a sentinel |
| 5 | must-PASS control: populated file renders counts + cap-fraction | PASS |

### Guard 4 — stop-hook `capped` floor

**Property.** On Claude, a loop whose branch ledger carries `capped` cannot be
continued by `stop-hook.sh` — the hook exits 0 instead of emitting
`{"decision":"block"}`.

**Assembly.** `plugins/soleur/hooks/stop-hook.sh` — the chokepoint is the point
where the hook decides to block (before its `block` emit); input is the
branch-slugged counter file under the session-state root.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Counter file with `capped=ci_cycles` + active ralph-loop state → invoke hook | RED — must exit 0, must NOT emit `block` |
| 2 | Remove the capped-check from stop-hook.sh → same fixture | RED — fixture test asserts the uncapped→capped delta; an absent check emits block (the violation) |
| 3 | `capped` set, then `init --reset` (raised caps) → invoke hook | PASS — normal block behavior resumes; resume path not trapped |
| 4 | Corrupt/unreadable counter file + loop active | PASS — hook ignores the file entirely (fail-open; never blocks *for* the tally) |
| 5 | must-PASS control: no counter file + loop active | PASS — unchanged ralph-loop behavior |

## Implementation Phases

#### Phase 1: Counter script

- `plugins/soleur/scripts/pipeline-tally.sh` — `init`/`incr`/`show`/`gate`/
  `selfcheck` subcommands on `session-state.sh` (source the lib; `with_lock`
  writes; `_safe_worktree_name` slug; flat `key=value` counters). Header
  documents the canonical per-skill call-out block (the verbatim snippet every
  instrumented SKILL.md carries — the #3819 `<decision_gate>` pattern).
- `plugins/soleur/scripts/pipeline-tally.test.sh` — battery: init idempotent
  merge + auto-reset on capped/stale, incr correctness + missing-file UNKNOWN,
  concurrent-incr under flock, gate arms (OK/WARN/STOP/UNKNOWN, capped-flag
  persistence, UNKNOWN-under-caps), `10#` flag normalization + reject cases,
  selfcheck, stale-file sweep.
- `plugins/soleur/hooks/stop-hook.sh` — `capped` check before the block emit
  (Guard 4); hook test additions in the script's existing test surface.

#### Phase 2a: Pilot — `one-shot` only

- Flag parsing + `init` + `incr` call-outs + `gate` + STOP contract in
  `one-shot/SKILL.md`; `review/SKILL.md` gets `incr seats`; `ship/SKILL.md`
  gets the `## Pipeline Tally` render (both body templates + ABSENT/ZERO/
  CAP_IGNORED tri-state + `cap-unenforced`).
- **Live-run verification AC**: a real one-shot run leaves a non-empty counter
  file before the pattern stamps to the other skills (advisor's sequencing).

#### Phase 2b: Roll to remaining skills

- test-fix-loop (`--max` alias), drain-labeled-backlog, resolve-todo-parallel,
  resolve-pr-parallel (incl. `--branch` fleet attribution), work, eval-harness
  (minimal: init/gate/agent_rounds only).

#### Phase 3: Workflow bridge + sentinel + docs

- `counts:{…}` return field in the three loop workflow ports; invoking prose
  posts to the counter.
- `components.test.ts`: Guard 2 sentinel rows.
- ADR-264 (provisional) + `model.c4` plugin-system description edit (counters
  write-surface).
- README component counts if scripts are tabled.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| A — counter script on session-state (chosen) | ✅ | P1-P4; honest units; cross-harness |
| B — derive at report time | ❌ | No running tally, nothing to gate on |
| C — workflow-native `budget` only | ❌ | Covers opt-in workflow path only |
| D — emit-decision enum extension | ❌ | Frozen 2-event contract (ADR-254) |
| E — PreToolUse hook enforcement | ❌ deferred | ~1.5/4 harness coverage; v2 candidate |
| F — blocking prompt pause | ❌ | Strands unattended runs; classified-stop chosen |
| G — dollar budget | ❌ | ADR-056 doctrine + CLO guardrail |
| H — git `Pipeline-Cost:` trailer | ❌ | Squash-merge drops branch-commit trailers; PR-body line carries P4 |
| I — tee-derived mechanical agent counts (advisor) | ❌ deferred | Tee counts ALL spawns, can't isolate review seats; adds JSONL coupling for one dimension — prose + ABSENT/CAP_IGNORED sentinels bound the risk |
| J — stop-hook hard-cap floor (advisor) | ✅ applied | Operator-approved post-review: negative enforcement in shipped `stop-hook.sh` (declines to block when `capped` set); prose `gate` remains the cross-harness layer. Distinct from the deferred PreToolUse-deny design — it reuses the block channel, never denies a tool |

## Acceptance Criteria

- [ ] AC1: `bash plugins/soleur/scripts/pipeline-tally.sh selfcheck` prints `SOLEUR_TALLY_OK`, writes nothing, on a clean checkout.
- [ ] AC2: `init` → `incr seats 3` → `incr ci_cycles 2` → `show` prints `tally: seats=3 ci_cycles=2 fix_rounds=0 agent_rounds=0`.
- [ ] AC3: With `cap_ci_cycles=1` persisted, the second `tally gate ci-cycles` prints `STOP`, sets `capped`, and the honoring skill writes `session-state.md` + resume prompt and exits `budget-capped`; a subsequent `init` (no `--reset`) still returns `STOP`.
- [ ] AC4: ship Phase 6 renders `## Pipeline Tally` (both `gh pr edit` and `gh pr create` fallback templates) before `## Changelog` with counts + `Pipeline-Tally:` machine line; absent file → `SOLEUR_TALLY_ABSENT`; zeroed file → `tally: 0` + "no counted operations"; `capped` set + shipped → `SOLEUR_TALLY_CAP_IGNORED`.
- [ ] AC5: Each AUTONOMOUS_LOOP_SKILL SKILL.md carries the anchored tally call form; the extended components.test.ts sentinel goes red on Guard 2's matrix rows.
- [ ] AC6: No dollar figure on any tally/gate/PR-body output on the local-loop path.
- [ ] AC7: A mid-pipeline resume on the same branch continues the ledger (no clobber); a stale (>24h) or `capped` ledger auto-resets.
- [ ] AC8: `incr`/`gate` on a missing file prints `UNKNOWN` + `SOLEUR_TALLY_ERROR reason=missing-file`, exit 0 — never auto-creates; `UNKNOWN` under configured caps renders `cap-unenforced` in the ship output.
- [ ] AC9: Flag parse rejects `--max-seats 08`, `-1`, `0`, and `abc` with a readable error.
- [ ] AC10: One writer per counter dimension per invocation — prose `incr` and workflow `counts:` never both fire for the same dimension (asserted in the contract doc + a drift grep in the sentinel).
- [ ] AC11: With `capped=<dim>` in the branch ledger and an active ralph-loop state file, `stop-hook.sh` exits 0 without emitting `block` and prints `SOLEUR_TALLY_CAPPED`; after `init --reset` the same fixture blocks normally.

## Open Code-Review Overlap

- #8593 (`components.test.ts` — probe-gate window narrowing, unrelated #6793
  concern): **Acknowledge** — distinct defect in the same file; stays open.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Finance, Operations (carried
forward from brainstorm `## Domain Assessments`; Marketing, Sales, Support not
relevant).

### Engineering
**Status:** reviewed — substrate confirmed; separate counter file beats widening
the frozen decisions.jsonl enum.

### Product
**Status:** reviewed — units escape the #5086 objection; always-on tally,
opt-in gate; counts-only v1 verdict (no unmeasured "typical" claim).

### Legal
**Status:** reviewed — units only; "operative budget" strengthens the BSL
disclaimer posture; never a "spend cap"; counts-only PR content.

### Finance
**Status:** reviewed — units are the right Max-20x proxy; disaggregated flags;
CI dollars already workspace-capped.

### Operations
**Status:** reviewed — machine-readable `Pipeline-Tally:` PR-body line; warn +
hard-stop thresholds; counters persist under session-state root.

**Brainstorm-recommended specialists:** none.

## Test Scenarios

- Clean checkout + `selfcheck` → `SOLEUR_TALLY_OK`, zero files written.
- `init` + 2×`incr seats` + `incr ci_cycles` → `show` reports `seats=2 ci_cycles=1`.
- `cap_ci_cycles=1` + second `gate ci-cycles` → `STOP` + `capped` set + session-state marker; `init` without `--reset` still `STOP`; `init --reset` clears.
- 20 concurrent `incr` under flock → final count 20.
- No counter file at ship → `SOLEUR_TALLY_ABSENT`; zeroed file → `tally: 0`; `capped`+shipped → `SOLEUR_TALLY_CAP_IGNORED`.
- Comment-only `pipeline-tally.sh` mention in a SKILL.md → sentinel red.
- Workflow port returns `counts:{}` → invoking prose posts to shared file; drain child posts via `--branch <item>` to the item ledger.
- **Regression:** `guardrails.test.sh`, `components.test.ts`, `emit-review-trailer.test.sh` stay green.

## Success Metrics

- `## Pipeline Tally` appears in the final PR report on every instrumented run.
- A configured hard-cap crossing produces `budget-capped` instead of silent continuation.
- Zero prose-only emit instructions — every mutation is a script call.
- P4 enabled: `gh pr list --search "Pipeline-Tally:"` aggregates across merged PRs.

## Dependencies & Risks

- **Model-discipline risk** — prose call-outs depend on the executing model;
  sentinels assert call sites exist, SOLEUR_TALLY_ABSENT/CAP_IGNORED bound
  runtime non-compliance, and the stop-hook floor (if gated in) adds a
  mechanical backstop on Claude.
- **Counter vs. reality drift** — self-reported counts can undercount on a
  missed `incr`; mitigated by call-site sentinel + absent sentinel (not by a
  fixture-transcript harness — cut at review).
- **macOS** — no `flock`: counters `UNKNOWN`, caps unenforced; documented.
- **Non-goal drift** — dollar figures must never be added (ADR-056 + CLO).

## Architecture Decision (ADR/C4)

### ADR

New ADR (provisional ADR-264 — ship re-verifies): "Pipeline tally — per-branch
flat-key counters on the session-state root, script-invoked, fail-open;
per-dimension caps persisted in-file; classified `budget-capped` stop; PR-body
`Pipeline-Tally:` line is the aggregation surface (git trailers die at squash)."
Record alternatives D/E/H/I above.

### C4 views

Enumerate-and-check: **external actors** — none new (operator already modeled);
**external systems** — none (local file writes); **containers/stores** — the
`plugin` system description in `model.c4` names `emit-decision.sh` as the
shipped user-machine WRITE surface; this adds a second write surface
(`soleur-session-state/counters/`) under the same umbrella — **task:** amend
that description to name the counters directory. **Relationships** — none
change. Validation: `c4-code-syntax.test.ts` + `c4-render.test.ts` stay green.

## Sharp Edges

> `## User-Brand Impact` is filled. Deferred items — default caps, comparative
> "typical" verdict, tee-derived mechanical agent counts — are tracked in
> follow-up issue #9413.

## References & Research

- Issue #9403; inciting PR #9339; sibling set #9398–#9402
- Brainstorm + spec under `knowledge-base/project/{brainstorms,specs/feat-one-shot-9403-cost-tally}/`
- ADR-056 (units), ADR-108 (positive capture), ADR-127 (trailer precedent),
  ADR-254 (decisions.jsonl), #8611 (`--max-budget-usd` stop), #8505 (CI cap)
- Substrate: `scripts/lib/session-state.sh` (`with_lock`, `_safe_worktree_name`),
  `skills/review/scripts/emit-review-trailer.sh`, `test/components.test.ts:308`
- Review panel: spec-flow (11 findings), advisor (stop-hook floor + pilot),
  DHH/Kieran/simplicity/architecture (flat schema, trailer cut, tri-state,
  branch slug, fleet attribution), CPO/CTO (no-baseline verdict, contract doc,
  `--max` alias) — all applied except J (gated).
