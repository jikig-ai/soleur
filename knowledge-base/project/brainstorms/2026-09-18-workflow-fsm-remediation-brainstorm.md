---
title: Workflow FSM remediation — instrument, reconcile, ratchet
date: 2026-09-18
branch: feat-workflow-fsm-remediation
pr: 8301
lane: cross-domain
brand_survival_threshold: single-user incident
status: ready-for-plan
source_artifact: "States Without Gates (claude.ai artifact 024daac0, 2026-08-13, derived at 63b80b78e)"
---

# Workflow FSM Remediation — Brainstorm

## What We're Building

Soleur declares a workflow state machine whose states and transitions are both
declared and neither executable, and nothing that can say *no* reads either one.
This brainstorm scopes the remediation into shippable increments, having first
**re-derived every count in the source audit against current `main`**.

The audit ("States Without Gates", 2026-08-13) was written in worktree
`feat-workflow-state-machine` at commit `63b80b78e` — five weeks stale by the
time of this session. Its structural findings hold. Several of its *numbers* do
not, and three of its framings are now wrong in ways that change the
recommendation.

## Re-Verification Against Current Main

Every row measured in this worktree on 2026-09-18. Command stated where the
method is not obvious.

| Claim | Audit (2026-08-13) | Current main | Verdict |
|---|---|---|---|
| `review/SKILL.md` size | 322 KB | **430 KB** | Worse (+34%) |
| `work/SKILL.md` size | 257 KB | **326 KB** | Worse (+27%) |
| `plan/SKILL.md` size | 248 KB | **258 KB** | Worse |
| `ship/SKILL.md` size | 187 KB | **248 KB** | Worse (+33%) |
| `review` lines >1,000 chars | 128 | **181** | Worse |
| `work` longest single line | 6,589 chars | **7,962 chars** | Worse |
| Inline learning citations in SKILL.md | 634 | **716** (593 distinct) | Worse |
| Learning files on disk | 2,151 | **2,311** | Grew |
| Headless predicate copies | "10+" | **11 skills** | Confirmed |
| Phase-surface coverage | 16 of 96 = 17% | **16 of 99 = 16%** | Confirmed |
| Rules with an emit call site | 20 of 103 = 19.4% | **19 of 98 = 19.4%** | Confirmed |
| Rule corpus size | 103 | **98** | Shrank by 5 |
| Prose-only rules | 65 of 103 = 63% | **55 of 98 = 56%** | Improved |
| Tier tags | 33 skill / 12 hook / 3 scanner | **26 skill / 15 hook / 3 scanner** | Shifted |
| `PreToolUse` hooks | 30 | **44** | Grew |
| Hooks on `Skill` matcher | 1, no verdict | **1, no verdict** | Confirmed |
| `mandatorySuccessors()` back-edges | 0 | **0** | Confirmed |
| Sub-phase id anomalies | 7 | 3 confirmed, 1 refuted | Partly refuted |

**The single most important row is the first four.** The waste is not static —
it compounds at roughly 30% per five weeks while the corpus that governs it
shrank by 5 rules. That is ADR-131's queue-growth thesis, measured.

## Three Corrections to the Audit

### Correction 1 — the measurement fix is not greenfield; it stalled

The audit recommends "the measurement fix" as the cheapest high-yield work. It
was already designed and partly shipped **five months ago**. Issue #2866
("fix rule-metrics emit_incident coverage") closed via PR #2876, and its
archived brainstorm (`20260424-164351-...-emit-incident-coverage-brainstorm.md`)
records eight decisions including the exact mechanism now proposed: skills
source `.claude/hooks/lib/incidents.sh` and call
`emit_incident <rule-id> applied <prefix>` at phase entry.

What shipped: `incidents.sh`, `scripts/rule-prune.sh`,
`scripts/rule-metrics-aggregate.sh`, and emission across the hook layer.
What stalled: **only 4 skills** source `incidents.sh` today (`compound`,
`git-worktree`, `incident`, `linear-fetch`) against Decision 8's plan for 10
skill-enforced rules.

The question for this cycle is therefore *why it stalled*, not *how to design
it*. Re-deriving the design would repeat work the institution already did.

### Correction 2 — cross-worktree fragmentation is half-fixed, and the residue is measurable

The audit says aggregation "reads a single per-checkout fragment." That was
fixed on **2026-09-11 by PR #8029** (`65d6a1584`, "aggregator read the incidents
log from a path where it cannot exist") — a month after the audit. The
aggregator now merges `$REPO_ROOT/.claude` **plus** the shared checkout beside
`git rev-parse --git-common-dir`.

But it collects exactly **two** roots. It does not enumerate sibling worktrees.
Measured live on this machine:

- Read by an aggregator run from here: **23,882 rows** (shared checkout +
  this worktree), cross-validated against the aggregator's own report of
  23,805 kept + 77 dropped = 23,882 — exact match.
- Stranded across **34 other sibling worktree roots**: **11,346 rows** —
  **32% of the 35,228-row corpus**.

So the blind spot is *refined*, not dismissed: the instrument went from reading
a sliver to reading roughly two-thirds, and still reports its two-thirds as the
whole.

**Measurement caveat, recorded because it bit this session.** A first pass
counted only live `.rule-incidents.jsonl` files and reported 6,372 / 5,672
(~47% stranded). That denominator was wrong: the aggregator also reads rotated
`.rule-incidents-*.jsonl.gz` archives, which hold the majority of the history.
Any future measurement of this residual must include the archives.

### Correction 3 — a blocking PreToolUse gate is ADR-070-noncompliant

The audit frames block-vs-record as an open operator preference. It is
constrained by a recorded decision. **ADR-070's two-tier rule permits
deny-by-default only on re-fetching layers (MCP / ToolSearch); every other
layer — including PreToolUse hooks — must be additive-hint only.** The `Skill`
tool does not re-fetch: a denied skill does not retry, so a hard deny there
strands the session.

The CTO assessment and the independent learnings sweep reached this conclusion
separately, from different sources. Record-mode is not the cautious option; it
is the compliant one.

## Correction Block — do NOT prune rules on rule-metrics.json

*Carried verbatim from the source audit at its author's explicit instruction.*

`rule-metrics.json` shows the large majority of rules never fired. **That is not
evidence those rules are dead.** The repo already investigated this:
`knowledge-base/project/learnings/2026-07-22-rule-metrics-denominator-investigation.md`
(issue #6794, closed via PR #6852) found the figure swings between 94 and 101
across successive runs *with no rule change*, because it is a per-checkout
fragment while sessions run in separate worktrees. **Its own conclusion is: do
not prune on this.** Any plan proposing rule deletion on this basis is wrong.

The honest statement is narrower and worse: **the corpus has no working
instrument for deciding what to remove.** 79 rules cannot emit; aggregation over
the 19 that can is fragmented; and — newly found this session — the aggregator
is not even scheduled.

### Correction 3b — the instrument is unscheduled, not merely fragmented

`.github/workflows/rule-metrics-aggregate.yml` is **`workflow_dispatch` only**.
The weekly schedule was *removed* under #6042 because fresh CI checkouts saw
zero incidents. So the failure has three independent layers, and fixing any one
alone leaves the instrument mute:

1. **Emission** — 79 of 98 rules have no call site.
2. **Collection** — 32% of emitted rows (11,346 of 35,228) sit in 34 unread sibling worktree roots.
3. **Cadence** — nothing runs the aggregator on a schedule.

Dogfooded live this session: an aggregator run from this worktree kept 23,805
events, dropped 77 malformed lines, and reported `rules_unused_over_8w: 81`.
Per the correction block above, that 81 is **not** a retirement shortlist.

## Why This Approach

The operator selected a **two-track first increment** (options 1 & 2 combined):
repair the instrument *and* bend the prompt-weight curve, in parallel, because
they share no files and answer two different failure modes.

**Track A (instrument)** is sequenced first-among-equals because CTO established
that fragmentation is a property of **root resolution**, not storage form: both
`.skill-invocations.jsonl` (one path, 10,246 records) and
`.rule-incidents.jsonl` (18 paths) resolve via the same
`dirname(hook)/../..`. Fixing root resolution to the git common dir repairs
incident aggregation **and** unblocks derived state-keying for any future gate —
one fix, two unlocks. A stored state file inherits the identical bug, which
settles Open Question 2 on mechanism rather than preference.

**Track B (weight)** exists because ordering violations are episodic while the
weight tax is paid on every invocation and is compounding at a measured ~30%/5
weeks. The intervention is mechanical body-extraction into `references/` plus a
**monotonically non-increasing** per-file byte ceiling.

The precedent here is a warning, not an encouragement:
`SKILL_DESCRIPTION_WORD_BUDGET` in `plugins/soleur/test/components.test.ts`
currently sits at 2,442 and **has been bumped 14 times**. A ceiling that can be
raised is not a ratchet; it is a changelog. Track B's ceiling must be
non-increasing by construction or it becomes the fifteenth bump.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | First increment = Track A (root resolution + node reconciliation) **and** Track B (weight ratchet), in parallel | Operator selection. Disjoint file sets; different failure modes |
| 2 | Gate ships in **record-mode**, with a **pinned calendar decision date** | ADR-070 forbids PreToolUse deny. ADR-116 line 96: advisory→blocking promotion has **never** happened here, so "revisit when data says so" means never |
| 3 | Merge the two node sets into one declarative source; `workflow-fidelity.ts` reads it | Split brain is the root defect. Bash cannot read a TS switch, so a hook gate needs the edges in JSON regardless |
| 4 | Legal back-edges: **review→work, ship→work, work→plan** | Operator selection. `postmerge→work` rejected as redundant with `ship→work` |
| 5 | Sub-phase normalization **deferred to its own track** | 4+ incompatible grammars; `plan` has zero `Phase` headings across 258 KB. Migration, not lint. Orthogonal: the gate cannot observe sub-phase progression anyway |
| 6 | Fix the 3 confirmed sub-phase anomalies **only** if free; otherwise defer with the track | Duplicate `Phase 0.4` (brainstorm), `6.4` before `6.` (ship), `0.5→1.5` gap (compound) |
| 7 | Rule **content** stays unconditionally loaded; only **transitions** are gated | ADR-151 split, validated by CTO: its failure mode was content silently absent; a denied transition is loud and synchronous — opposite signature |
| 8 | No rule pruning this cycle, on any signal | Correction block above |
| 9 | Do **not** put the verdict in `skill-invocation-logger.sh` | It is fail-soft (`exit 0` on every path) with a kill-switch; a deny there dies silently whenever telemetry does. Add a second entry to the same `Skill` array |
| 10 | Aggregator cadence must be restored as part of Track A | An instrument nothing runs is not an instrument (#6042 removed the schedule) |

## Open Questions

1. **Why did the April skill-emit arm stall at 4 skills?** Unresolved and
   load-bearing — if the cause was friction in the emission call itself,
   Track A repeats it. Plan-time investigation required before extending
   coverage.
2. **Where does the shared incident log live?** CTO recommends resolving to the
   git common dir. CLO constrains this: widen the **read** only; a shared-location
   **write** triggers `hr-write-boundary-sentinel-sweep-all-write-sites` and must
   carry the `0600` + gitignore guarantee to every new write site.
3. **What is the pinned gate decision date?** Decision 2 commits to having one;
   the date itself is an operator call at plan time.
4. **Does the web harness bind?** Partly answered — see Capability Gaps. A
   bundled-copy-plus-parity-test pattern already exists and is the cheapest path.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** The hook is ~100 lines; the real work is moving the edge set out of
the TS switch into declarative JSON so bash can read it, with a drift test.
Block-mode is ADR-070-noncompliant on the non-re-fetching `Skill` tool, and with
16/99 mapped it would false-deny `/go` itself. Derived state beats stored state
because fragmentation is a root-resolution bug that stored state inherits
identically. Sub-phase normalization is week+ and does not belong before the gate.
Recommends an ADR for the single source of truth.

### Product (CPO)

**Summary:** The operator loses twice — ~100k tokens of preamble before any
review reads a diff, and a plan→ship path with no `review` that surfaces only
post-merge. Weight is the higher-priority track because it is paid per
invocation and compounds. Warns that "decide later whether the gate is needed"
is unanswerable: a missing transition leaves no incident in a system that cannot
record incidents. Demands the ratchet be demonstrated failing red in CI before
merge, or it becomes another ADR-131 entry.

### Legal (CLO)

**Summary:** **Low exposure, no blocking legal work.** Corrected a premise:
rule-fire events are *not* a bare id + counter — `emit_incident()` writes
`command_snippet` (the triggering Bash command verbatim, 1024 chars), which
ADR-091 notes stores absolute paths, git/gh identity and PR-body text. Exposure
stays low only because the log is gitignored, mode `0600`, and has **no egress**
(no curl/wget anywhere in `incidents.sh`); only the redacted aggregate is
committed. Going 19→98 multiplies that content ~5×: a quantity change inside an
existing boundary, not a new category.

**The one condition that changes this:** if rule instrumentation is ever wired
into `plugins/` so it emits on a *customer's* machine, those snippets become
third-party personal data under our controllership — requiring an Article 30 row,
disclosure, and a CLO attestation. ADR-179 decision 4 already forbids it; the
plan must keep that boundary explicit.

## Capability Gaps

| Gap | Domain | Evidence | Why it matters |
|---|---|---|---|
| No sub-phase validator exists | Engineering | `grep -rn` across `scripts/` — `lint-rule-bodies.py` (507 lines) validates rule bodies, `lint-rule-ids.py` validates pointer↔body 1:1; neither parses ordered steps | A validator could live beside `lint-rule-bodies.py`, but has no home today |
| Aggregator has no schedule | Engineering | `.github/workflows/rule-metrics-aggregate.yml` is `workflow_dispatch` only; weekly schedule removed under #6042 | Layer 3 of the measurement failure |
| No per-file size budget for SKILL.md | Product | `plugins/soleur/test/components.test.ts:21` enforces `SKILL_DESCRIPTION_WORD_BUDGET=2442` (description words) and a 1024-char per-skill limit — **neither bounds SKILL.md body bytes** | Track B has no existing mechanism to extend; it is net-new |

**Not a gap — already exists (and the audit missed it):** the web harness is not
unbound. `apps/web-platform/server/phase-surface-map.ts` is a bundled copy of
the canonical `.claude/phase-surface-map.json`, with
`test/phase-surface-map-parity.test.ts` asserting `expect(bundled).toEqual(canonical)`.
Separately, `supabase/migrations/032_conversation_workflow_state.sql` already
stores per-conversation workflow state (`active_workflow`, `workflow_ended_at`)
with a CHECK constraint kept in lockstep with a TS union and a parity test. The
web arm's hook is `PostToolUse`, fail-open, per ADR-070.

## User-Brand Impact

- **Artifact:** the Soleur workflow FSM enforcement surface — the
  `PreToolUse(Skill)` transition gate, rule-fire instrumentation, and the
  SKILL.md prompt-weight ratchet.
- **Vector:** a governance mechanism that reports success across a fraction of
  its intended scope, so the operator believes a workflow rule is enforced when
  it is structurally incapable of firing. ADR-151 names this exact shape —
  "appears enforced, is absent" — the worst failure mode a governance system has.
  A wedging gate additionally strands a customer session on a self-hosted CLI
  (observability layer 7).
- **Threshold:** `single-user incident`.

## Session Errors

Recorded per `wg-every-session-error-must-produce-either`.

1. **False negative on `skill_to_phase` membership.** Probed with bare skill
   names; the keys are namespaced `soleur:<skill>`, so every lookup reported
   "NO PHASE" including correctly-mapped ones. Caught by dumping the keys before
   drawing a conclusion. Same class as the learnings the skill body warns about.
2. **Phantom duplicate `Phase 4` in `work`.** My heading regex stripped the `#`
   depth prefix, collapsing `### Phase 4: Handoff` and `#### Phase 4 Entry-Guard`
   into a false duplicate. Refuted by the CTO. Depth is load-bearing in Markdown.
3. **Undercounted sub-phases at 53.** My pattern matched only `## Phase N`, so
   `plan` scored 0 and `review` scored 2. The real finding is better than the
   count: there is **no single grammar** to count with.
4. **`emit_incident` co-occurrence error.** First probe counted rules whose id
   appeared in any file that *also* contained `emit_incident` anywhere, yielding
   82. Corrected to 19 by matching actual emit expressions.
5. **Accepted a subagent count without re-derivation (partially).** The CTO
   reported 12 emit sites vs my 19; re-derivation confirmed 19 (the 11
   SKILL.md-body emitters are a strict subset of the 19 executable ones). The
   CTO's other three disputes were all correct. Both directions of the
   "counts are claims" rule fired in one session.

## Lane

`cross-domain` (forced by `USER_BRAND_CRITICAL=true`, Phase 0.1, per #5175).
CPO + CLO + CTO triad spawned; `repo-research-analyst` and `learnings-researcher`
run in the same parallel batch.

**Phase 0.4 observation:** the Linear Context Preflight regex `[A-Z]{2,}-[0-9]+`
matches `ADR-151`, `ADR-070`, `ADR-131` — every ADR citation is a false-positive
Linear ID. It did not fire destructively here (no `linear-fetch` was warranted),
but a brainstorm whose description cites ADRs will route through Linear preflight
for no reason. Filed as a deferred item.

## Productize Candidate

`Productize Candidate: skill-body-weight-report` — a recurring measurement of
SKILL.md byte growth per file over time. This session had to hand-derive the
30%/5-week growth rate that turned out to be the strongest single finding;
nothing in the repo tracks it.
