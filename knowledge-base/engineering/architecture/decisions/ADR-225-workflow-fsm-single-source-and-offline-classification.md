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
of truth. `.claude/workflow-transitions.json` is a *derived view*, generated from
it and pinned by a parity block that fails in both directions — a view carrying
an edge the const lacks is exactly as wrong as one missing an edge.

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

**4. The SKILL.md byte ratchet is anchored to the merge base, in a
`fetch-depth: 0` job.** Anchoring to the working tree would let one diff raise
both a file and its own ceiling. Placing it in the `bun` job — beside the
existing `SKILL_DESCRIPTION_WORD_BUDGET` — would put the base read in a job with
no fetch depth, where it fails on every run and any fallback is permanently
fail-open.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Record-mode `PreToolUse(Skill)` gate | Output dead-ends in `non_corpus_counts`; the data it would record already exists in `.skill-invocations.jsonl` |
| Blocking transition gate | ADR-070 permits deny-by-default only on re-fetching layers; `Skill` does not re-fetch, and at 16/98 phase coverage it would false-deny `/go` itself |
| `mandatorySuccessors()` reads the canonical JSON | The plugin does not ship `.claude/`; returns `[]` on a customer install |
| One function for both concepts | A back-edge in the successors collection renders as an instruction to re-enter that phase |
| `transitions` key inside `phase-surface-map.json` | Forces FSM edges through the web bundle via that file's deep-equal parity test |
| Ratchet beside the existing word budget | That job has no `fetch-depth`; the base read fails every run |
| Restore a CI schedule for the rule-metrics aggregator | Removed deliberately under #6042: fresh checkouts committed all-zero snapshots that clobbered the real local aggregate |
| Raise emission coverage via SKILL.md prose | Zero `emit_incident` call sites appeared in any SKILL.md in five months; the mechanism does not stick |

## Consequences

- The edge set can be read from bash (the derived view) and from TypeScript (the
  const) without either being a runtime dependency of the other.
- Two copies exist, so drift is possible; the parity block is what makes it
  detectable rather than latent.
- Classification is on-demand rather than continuous. Nothing pages on an
  undeclared transition — by design, since ADR-131's open question is precisely
  whether another always-on gate earns its keep.
- Measured at adoption: **427 undeclared node→node transitions of 8,800** across
  ~16 months of sessions (1,334 sessions, 10,260 invocation records). The largest
  are `brainstorm → compound` (123), `compound → plan` (97) and `review → ship`
  (46). `plan → ship` occurs twice. `postmerge → work` — the edge rejected as
  redundant — occurs 7 times, which is recorded here rather than acted on.
- A gate remains buildable on top of this without rework: the edge set is
  declarative and the classifier already resolves state per session. Whether one
  is warranted is deferred to the measurement this ADR makes possible, not to a
  date.

## Verification

- `plugins/soleur/test/workflow-fidelity.test.ts` — edge set, the `plan → ship`
  absence, `mandatorySuccessors` forward-only, derived-view parity in both
  directions. Runs under `grok-fidelity-gate.sh` as a mandatory pre-push gate.
- `scripts/classify-workflow-transitions.test.sh` — 11 assertions including a
  present-but-unparseable log failing loudly rather than reporting zero.
- `scripts/lint-skill-body-budget.test.sh` — 10 assertions including the
  same-diff ceiling raise, the unavailable base, and the empty node set.
- `scripts/lib/incidents-roots.test.sh` — inode dedupe and first-seen ordering.
- `scripts/rule-metrics-aggregate.test.sh` T26 — the shared checkout counted
  exactly once and a sibling worktree counted at all.
