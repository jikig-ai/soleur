# ADR-229: The workflow edge set is a bundled const, and classification is offline

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
decision 3). **[Amended 2026-09-19 (#8325): the view also carries `sub_steps`,
mirroring `DECLARED_SUB_STEPS` under the same parity block; it still has one
consumer.]** A `bun -e` read of the const from that script was weighed at
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

Declared back-edges: `review → work`, `ship → work`, `postmerge → work`,
`work → plan`. **[Amended 2026-09-19 (#8325): `postmerge → work` was originally
considered and rejected as redundant with `ship → work`; it is declared as of
this amendment on the seven-session reading in Consequences.]**
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
- **`postmerge → work` is declared (2026-09-19, #8325).** The seven sessions
  were read: five continue `postmerge → work → review → compound → ship →
  postmerge` (a full re-entry of the implementation tail after post-merge
  verification found something), two end the session at `work`; none skipped
  `ship`. The doc comment already described `ship → work` as "postmerge
  failed" — the recovery edge was recorded on the wrong node. `ship → work`
  stays declared as the pre-merge failure path (2 sessions in the same corpus).
- **Re-baselined 2026-09-19 (#8325, after the sub-step collapse and
  `postmerge → work`):** on the same machine, immediately before the change,
  `undeclared=622 sessions=1277 pairs=5026 nonnode=4019 read=10472 dropped=0`;
  immediately after, `undeclared=379 sessions=1264 pairs=4897 nonnode=4019
  substep=129 read=10472 dropped=0`. **Quote the DELTAS, not the absolutes:**
  the log is append-only and rotates under other sessions, so every absolute
  here is a snapshot that has already moved (a re-run hours later read 624→380,
  pairs 5041→4911, substep 130). The deltas reproduce. Undeclared −243: 127
  `brainstorm → compound` and 111 `compound → plan` rows collapse and 7
  `postmerge → work` rows become declared, while the collapse EXPOSES a few
  pairs that sat behind `compound` — measured `brainstorm → review` (3),
  `brainstorm → work` (2), `brainstorm → ship` (1). Pairs −243 + 114 = −129,
  i.e. exactly `substep`. `sessions` counts sessions forming at least one pair,
  so the 13 that were only `brainstorm compound` leave it. `ship → plan` (50),
  `postmerge → plan` (31), `review → ship` (51) and `plan → ship` (7) are
  unchanged.
- There is no follow-through probe. One was written, could not PASS where the
  sweeper runs (Alternatives table), and as an operator-run script was a
  wrapper around `classify --summary` restating this section's numbers — the
  simplification pass deleted it. The classifier itself warns on a null reading,
  on an unparseable log (rc 2), and on records that form zero pairs. The
  baseline lives here; re-baseline by editing this section.
- **The reading needs interpretation, not just counting.** Of the 604,
  `brainstorm → compound` (125) is `brainstorm/SKILL.md` invoking `compound` as
  a designed sub-step — a node skill used as a sub-skill, which the non-node
  filter cannot see. **Corrected 2026-09-19 (#8325):** `compound → plan` is the
  tail of that same handoff, `brainstorm → compound → plan` (live: 108 of 111;
  2 have no predecessor, 1 follows `ship`), not second-feature chaining; and
  `plan → compound` (31) is likewise `plan`'s own exit-gate compound
  (`plan/SKILL.md`, "Run `skill: soleur:compound` to capture learnings from the
  planning session"), followed by `work` in 13 of the 16 cases with a
  successor. `ship → plan` and `postmerge → plan` are the second-feature
  starts; 65 are self-loops. Over half the undeclared edges are not
  review-skips. Resolved 2026-09-19 (#8325): `brainstorm → compound` is not
  declared; it is collapsed as a classifier sub-step (`DECLARED_SUB_STEPS`,
  mirrored as `sub_steps`, counted as `substep=`), because declaring
  `compound → plan` as an edge would legitimise `review → compound → plan`, the
  ship-skip class the classifier exists to surface. `plan → compound` and
  `postmerge → compound` (11) have the same shape and were not added — the
  ruling named `brainstorm` only; recorded as a User-Challenge in the #8325
  spec's `decision-challenges.md`.
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
  tokens per run, where k is the number of turns before the pass.
  Measured on 2026-09-19 with `scripts/measure-plan-sharp-edges-turns.sh` over
  local transcripts 2026-09-17 → 2026-09-19 (Skill-tool and slash-typed
  invocations). Local retention is three days, so the corpus is a ROLLING
  WINDOW and a re-run does not reproduce a prior reading: two readings the same
  day gave n = 2 and n = 7. Post-extraction k over 7 runs:
  {31, 36, 38, 73, 81, 86, 125}, median 73 — every individual run clears the
  ~8-turn break-even by at least 3.9×, which is what carries the decision at
  this n, not the median alone. Pre-extraction proxies: k'_first median 7
  (n = 25; turns to the ADR-176 skeleton write, so an early bound) and k'_ac
  median 46 (n = 17; turns to the `## Acceptance Criteria` write, the faithful
  stand-in). Median per-run saving ≈ 58k × 73 ≈ **4.2M cache-READ tokens** —
  billed an order of magnitude below input rate, so price it before comparing
  against a run's billed total; the n = 17 k'_ac proxy independently implies
  ≈ 2.7M. Kept on measured evidence (#8325 §3 closed). Three caveats, each of
  which a later reader must re-take rather than quote: the ~8-turn break-even
  is asserted rather than measured and is the cost side of this comparison;
  `k` is right-CENSORED, because a run still in flight when the script runs has
  no catalogue Read yet and scores `post_skipped` — an earlier reading the same
  day scored 4 of 6 extracted runs `post_skipped` for exactly that reason and
  all four later scored `post` with k ∈ {38, 73, 81, 125}, so a genuine-skip
  count may only be taken over completed runs and says nothing against the
  ~95% figure above; and the whole reading is a rolling-window snapshot. The
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
  sub-skill) and the other sub-skills remain uncapped. That population is the
  first thing #8305's body-weight growth report must cover (recorded there);
  #8303 (heading-grammar normalisation) is the prerequisite for naming the
  sub-phases at all, not the tracker for capping them.
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

- `plugins/soleur/test/workflow-fidelity.test.ts` — edge set (four back-edges
  since #8325), the `plan → ship` absence, `mandatorySuccessors` forward-only
  **and a subset of the declared edges** (the wire between the two functions),
  derived-view parity in both directions for `transitions` **and `sub_steps`**,
  the three `DECLARED_SUB_STEPS` invariants (keys and values are nodes; a value
  is not a declared successor of its key), and budget-file keys equal to the
  lifecycle set. Runs
  in the required `grok-fidelity` CI check (and as a pre-push gate under the
  Grok harness only).
- `scripts/classify-workflow-transitions.test.sh` — 28 assertions including a
  present-but-unparseable log failing loudly, sub-skill hops not laundering the
  enclosing transition, rotated `.jsonl.gz` archives read, timestamp order
  over file order, and (#8325) the sub-step collapse: keyed on the previous
  KEPT node, after the non-node filter, per session, never on a session's
  first record, exposing rather than hiding `brainstorm → review` and the
  self-loop, and a view whose `sub_steps` is missing, `null` or `[]` failing
  closed (rc 2).
- `scripts/measure-plan-sharp-edges-turns.test.sh` — 21 assertions over
  synthesized transcripts: turns are requestId groups in file order, the
  invocation may sit in any record of its turn, the catalogue is matched by
  suffix (installed-plugin cache path counts, a `.bak` sibling does not),
  post/pre decided by the preamble block that starts `Base directory for this
  skill`, the slash-typed form starts a run while a tool_result or a mid-text
  quote does not, API-error records are not turns, windows end at the next
  run, `k = 0` is legal, percentiles, the exact null line, and a sentinel
  planted in every parsed string field never reaching stdout or stderr under an
  ARMED inherited xtrace (via `BASH_ENV`, with a positive control that the
  vector fired — the obvious `SHELLOPTS=xtrace` spelling is silently inert,
  because `SHELLOPTS` is readonly and the child runs untraced).
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
