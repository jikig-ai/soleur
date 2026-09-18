# ADR-225: The workflow edge set is a bundled const, and classification is offline

- **Date:** 2026-09-18

## Status

Accepted.

## Context

Soleur declared a workflow state machine in two places that disagreed, and
nothing that could refuse an action read either one.

The state set lived in `.claude/phase-surface-map.json` (5 phases,
`skill_to_phase` mapping 16 of 98 skills). The transition graph lived in a
TypeScript `switch` in `plugins/soleur/lib/workflow-fidelity.ts` — a different
node set, forward-only, with zero back-edges. Enforcement was the word
"FORBIDDEN" rendered into a prompt, which is ADR-011 tier 3: the tier that
decays as context fills.

A `PreToolUse` hook on the `Skill` matcher already fired on every skill
invocation and returned no verdict, which made "give that hook a verdict" look
like the obvious remediation.

Three facts, each verified against the tree rather than inferred, made the
obvious remediation wrong.

**The plugin does not ship `.claude/`.** `.claude-plugin/marketplace.json`
declares `source: "./plugins/soleur"`; `plugins/soleur/.claude/` does not exist.
`apps/web-platform/server/phase-surface-map.ts` says so in its own header — the
bundled web copy exists *because* the container does not carry `.claude/`. So
any runtime read of the canonical JSON from plugin code returns nothing on a
customer install, and `mandatorySuccessors()` — reached from
`pipelineInvocationSuffix()` — then silently emits no next-step directive at
all. That is ADR-151's "appears enforced, is absent", on someone else's machine,
where no lint of ours runs.

**`mandatorySuccessors()` is prompt text, not a transition set.** Its result is
rendered as `When standalone, invoke next: /X, /Y`. A permitted transition is
legal-if-taken; a mandatory successor is a directive. Expressing the `work →
plan` back-edge by adding `plan` to `work`'s successors would instruct the model
to re-enter planning after every implementation run.

**A record-mode event would reach no consumer.** It carries no corpus rule-id
prefix, so `scripts/rule-metrics-aggregate.sh` files it under
`summary.non_corpus_counts` — a bare integer nothing reads — and compound's
Deviation Analyst ingests only `event_type ∈ {deny, bypass}` or
`kind == "hook_self_fault"`, none of which record-mode can emit. Meanwhile
`.claude/hooks/skill-invocation-logger.sh` had already been recording
`{ts, skill, session_id}` on every `Skill` call. The data existed; only the
classification was missing.

## Decision

**1. The canonical edge set is a bundled TypeScript const.**
`DECLARED_TRANSITIONS` in `plugins/soleur/lib/workflow-fidelity.ts` is the source
of truth. `.claude/workflow-transitions.json` is a *derived view*: **hand-mirrored
(there is no generator)** and pinned by a parity block that fails in both
directions — a view carrying an edge the const lacks is exactly as wrong as one
missing an edge. The view has one consumer: the offline classifier (bash,
decision 3). A `bun -e` read of the const from that script was weighed at
review (bun is present wherever the classifier runs) and not taken — see the
Alternatives table — so the mirror stays.

The view is a separate file rather than a `transitions` key inside
`.claude/phase-surface-map.json`, because that file is deep-equal'd against the
bundled web copy; a key added there would push FSM edges through the web bundle,
which has no consumer for them.

*This is the decision a future reader would otherwise undo.* The natural instinct
is "the JSON should be canonical and the TS should read it." It cannot be: the
JSON is not shipped.

**2. Permitted transitions and mandatory successors are separate functions.**
`declaredTransitions()` carries the edge set including back-edges;
`mandatorySuccessors()` stays forward-only and unchanged. The pre-existing
`toEqual` assertions on the latter enforce the separation rather than merely
documenting it.

Declared back-edges: `review → work`, `ship → work`, `work → plan`.
`postmerge → work` was considered and rejected as redundant with `ship → work`.
`plan → ship` is deliberately absent and asserted *as an absence* — it is the
path that skips `review`, which surfaces only after merge.

**3. Classification is offline, not a gate.**
`scripts/classify-workflow-transitions.sh` reads the invocation log that already
exists, groups by `session_id`, and reports transitions absent from the declared
set. No new `PreToolUse` surface, nothing that can wedge a session, and ADR-070's
two-tier rule — deny-by-default only on re-fetching layers — is not engaged at
all, because nothing denies.

**4. The SKILL.md byte ratchet is anchored to the merge base and runs as a step
in the required `rule-body-lint` job.** Anchoring to the working tree would let
one diff raise both a file and its own ceiling. Placing it in the `bun` job —
beside the existing `SKILL_DESCRIPTION_WORD_BUDGET` — would put the base read in
a job with no fetch depth, where it fails on every run and any fallback is
permanently fail-open. A *separate* job would have been advisory until someone
pinned it in `infra/github/ruleset-ci-required.tf`, and ADR-116 records that
advisory → blocking promotion has never happened here; `rule-body-lint` is
already required (ADR-092) and already fetches at depth 0, so the ratchet blocks
from its first run. Its row set is the ceiling file itself — base rows ∪
working-tree rows — so a row removed in the same diff is still measured against
its base ceiling; *which* rows exist (FSM keys ∪ destinations ∪
`ONE_SHOT_CHILD_SKILLS`, so `one-shot`, `qa` and `deepen-plan` are covered) is
pinned on the TypeScript side in the required `grok-fidelity` check. The lint
reads no view. A ceiling may rise, or a row be retired, only in a diff whose
sole change is the ceiling file (base..HEAD, staged and unstaged), so a raise
structurally cannot ride with the growth it would license. Bootstrap (no
ceiling file at the base) is legal only when the lint itself is also absent at
the base, which closes the rename escape.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Record-mode `PreToolUse(Skill)` gate | Output dead-ends in `non_corpus_counts`; the data it would record already exists in `.skill-invocations.jsonl` |
| Blocking transition gate | ADR-070 permits deny-by-default only on re-fetching layers; `Skill` does not re-fetch, and at 16/98 phase coverage it would false-deny `/go` itself |
| `mandatorySuccessors()` reads the canonical JSON | The plugin does not ship `.claude/`; returns `[]` on a customer install |
| One function for both concepts | A back-edge in the successors collection renders as an instruction to re-enter that phase |
| `transitions` key inside `phase-surface-map.json` | Forces FSM edges through the web bundle via that file's deep-equal parity test |
| Ratchet beside the existing word budget | That job has no `fetch-depth`; the base read fails every run |
| Ratchet as its own CI job | Not a required context; under auto-merge a red ratchet would not block, and ADR-116 records that advisory gates stay advisory |
| Read the const from bash via `bun -e` instead of keeping a mirrored view | Considered at review: bun is mandatory on the operator machine and in the CI scripts shard, so the premise "bash cannot read a TS const" is false where the classifier runs. Not taken in this PR: it trades one parity test for a runtime dependency on the plugin's TS module from repo tooling, and reverses a decision the plan carried through review. Either is defensible; the reason recorded here is that the mirror was the decision reviewed, not that the alternative cannot work |
| Enrol the transition probe in the follow-through sweeper | The sweeper runs on a hosted runner against a fresh checkout, where the gitignored invocation log cannot exist; measured: FAIL on every sweep — the #6042 locality error one row up, reproduced |
| Restore a CI schedule for the rule-metrics aggregator | Removed deliberately under #6042: fresh checkouts committed all-zero snapshots that clobbered the real local aggregate |
| Raise emission coverage via SKILL.md prose | Emission via SKILL.md is LIVE, not stalled: ADR-179 decision 9 (#7482, 2026-08-13) inverted the `source incidents.sh` form into `SOLEUR_RULE_APPLIED` markers captured hook-side — 21 sites across 7 lifecycle skills on `main`, 869 `applied` events in the live `.jsonl` logs across all roots on 2026-09-18 (excluding rotated archives). The audit's "4 of 10 skills" was a grep for the string `incidents.sh`, which the inverted transport no longer contains. Widening the remaining ~80 uncovered rules is a per-rule choice, not a mechanism gap, and out of scope here |

## Consequences

- The edge set can be read from bash (the derived view) and from TypeScript (the
  const) without either being a runtime dependency of the other.
- Two copies exist **in this repository only** (the view never ships), so drift
  is possible here; the parity block — a required check via `grok-fidelity` —
  is what makes it detectable rather than latent.
- Classification is on-demand rather than continuous. Nothing pages on an
  undeclared transition — by design, since ADR-131's open question is precisely
  whether another always-on gate earns its keep.
- Measured at adoption, under the node-only walk (records for non-node skills
  such as `deepen-plan`, `preflight`, `qa`, `one-shot` are removed *before*
  pairing, so a sub-skill hop collapses to the lifecycle transition it
  encloses): **604 undeclared transitions of 4,922 lifecycle pairs** across
  1,259 sessions and 10,268 invocation records spanning 2026-05-04 → 2026-09-18
  (~4.5 months; the invocation logger was added 2026-05-04). The largest are
  `brainstorm → compound` (125), `compound → plan` (109), `review → ship` (51)
  and `ship → plan` (50 — a session chaining a second pipeline, which the
  terminal-node graph correctly refuses to call declared). `plan → ship` occurs
  **7** times; a raw-adjacency walk saw 2, and review showed the other 5 were
  laundered through `plan → deepen-plan → ship`, which that walk classified as
  two unclassified pairs and zero violations. `postmerge → work` — the edge
  rejected as redundant — occurs 7 times, recorded here rather than acted on.
- There is no follow-through probe. One was written, could not PASS where the
  sweeper runs (Alternatives table), and as an operator-run script was a
  wrapper around `classify --summary` restating this section's numbers — the
  simplification pass deleted it. The classifier itself warns on a null reading,
  on an unparseable log (rc 2), and on records that form zero pairs. The
  baseline lives here; re-baseline by editing this section.
- **The reading needs interpretation, not just counting.** Of the 604,
  `brainstorm → compound` (125) is `brainstorm/SKILL.md` invoking `compound` as
  a designed sub-step — a node skill used as a sub-skill, which the non-node
  filter cannot see; `compound → plan`, `ship → plan`, `postmerge → plan/work`
  (~190) are sessions chaining a second feature; 65 are self-loops. Over half
  the undeclared edges are not review-skips. Whether to declare
  `brainstorm → compound` is the edge-set question recorded in
  decision-challenges §2.
- **The committed aggregate is now a function of which worktrees exist at
  regeneration time.** `cleanup-merged` deletes sibling worktrees and their
  logs, so hits and `last_hit` for rules exercised only there regress on the
  next regeneration; measured: `rules_unused_over_8w` 81 with the widened read
  vs 98 narrow. That is the local-producer model (ADR-091) made more visible,
  not a new class; archiving a worktree's log before deletion would be a new
  write site, which the CLO condition on this change forbids without its own
  review. Read the per-rule counters as a lower bound.
- **The ratchet is satisfied by its own remedy.** It bounds `SKILL.md` bytes;
  `references/` is unbounded, and appending 300 KB to
  `plan-sharp-edges.md` leaves the lint green (measured). That is by design —
  the ratchet exists to force each extraction to be argued — and #8305 (the
  body-weight growth report) is where total loaded weight, references included,
  gets tracked.
- **The extraction's economics, measured at review, are not what the plan
  claimed.** The ratchet bounds `SKILL.md` bytes — the load paid at turn 0.
  `plan/references/plan-sharp-edges.md` is 151,209 B and **~58k tokens** by the
  harness's own count (dense ~874 B lines, not bytes/4), it is read in three
  ~25k-token pages, and the load fires on ~95% of `plan` runs (the only
  pre-load exit is the "finished plan, return the path" arm). Per invocation
  the extraction is therefore **+~1 KB and three extra tool turns**, not
  "150 KB saved". What it does buy is per-turn: a block injected at turn 0 is
  re-sent on every turn of the run, a block injected at the end is re-sent on
  none of the earlier ones, so placing the load last avoids ~58k × k cache-read
  tokens per run, where k is the number of turns before the pass. That is
  plausibly large and **unmeasured** — no turn telemetry exists — but the
  break-even is ~8 turns before the pass and a `plan` run's research and
  drafting exceed that by an order of magnitude, so it is structural rather
  than speculative. The directive
  is therefore unconditional and placed as the final step before Plan Review,
  which is also where a verification pass belongs (Acceptance Criteria land
  last). A reachability guard in `components.test.ts` reds if a
  `references/*.md` stops being named from its skill, so an extraction cannot
  orphan its target silently. Two consequences to carry: (a) 151 KB of
  model-loaded prose left the `skill-security-scan` and `scratch-path-collision`
  scan surfaces, which walk `skills/*/SKILL.md` only — a pre-existing scope
  boundary (126 `references/*.md` already sit outside it) that this move
  crosses in size, recorded here rather than widened; (b) at measured growth
  (plan +8.5 KB, work +31 KB, review +47 KB per 14 days) the seeded ceilings
  bind in roughly two to three weeks — by design, since the ratchet exists to
  force the next extraction to be argued rather than absorbed.
- The ratchet's row set is the FSM's keys ∪ destinations ∪
  `ONE_SHOT_CHILD_SKILLS` (`deepen-plan`, `qa`), pinned on the TypeScript side;
  "lifecycle skill" is not only "FSM node". `preflight` (109 KB, a `ship`
  sub-skill) and the other sub-skills remain uncapped — the sub-phase
  normalisation deferred to #8303.
- No plugin runtime code calls `declaredTransitions()` or
  `isDeclaredTransition()`; they exist so the parity block and a future gate
  (below) have a typed source. `brainstorm → one-shot` is declared but unobservable by the
  classifier, because `one-shot` is not a node and its records are removed
  before pairing.
- A gate remains buildable on top of this without rework: the edge set is
  declarative and the classifier already resolves state per session. Whether one
  is warranted is deferred to the measurement this ADR makes possible, not to a
  date.

## Verification

- `plugins/soleur/test/workflow-fidelity.test.ts` — edge set, the `plan → ship`
  absence, `mandatorySuccessors` forward-only **and a subset of the declared
  edges** (the wire between the two functions), derived-view parity in both
  directions, and budget-file keys equal to the lifecycle set. Runs
  in the required `grok-fidelity` CI check (and as a pre-push gate under the
  Grok harness only).
- `scripts/classify-workflow-transitions.test.sh` — 16 assertions including a
  present-but-unparseable log failing loudly, sub-skill hops not laundering the
  enclosing transition, rotated `.jsonl.gz` archives read, and timestamp order
  over file order.
- `scripts/lint-skill-body-budget.test.sh` — 15 assertions including the
  same-diff ceiling raise, the unavailable base, the empty row set, a row for a
  sub-skill the FSM does not model, same-diff row removal, the rename escape
  from bootstrap, the legal raise-only diff, and a raise beside an uncommitted
  growth.
- `scripts/lib/incidents-roots.test.sh` — 12 assertions: NUL-framed
  `--porcelain -z` parsing (a newline-bearing path is one record, not a forged
  root, at both stages), inode dedupe, first-seen ordering, and the shared
  enumerate→dedupe composition both readers call.
- `scripts/rule-metrics-aggregate.test.sh` T30 — the shared checkout counted
  exactly once and a sibling worktree counted at all; T32 — a free-text or
  non-string `rule_id` from any root neither aborts the run nor reaches a
  committed key; a free-text `timestamp` is dropped before it can become `last_hit`.
- `plugins/soleur/test/components.test.ts` — every `references/*.md` is named
  from its skill (the extraction cannot orphan its target).
