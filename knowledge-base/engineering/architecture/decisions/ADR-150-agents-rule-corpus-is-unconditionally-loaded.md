---
title: The AGENTS rule corpus is unconditionally loaded
status: active
date: 2026-07-28
---

# ADR-150: The AGENTS rule corpus is unconditionally loaded

## Context

PR #3493/#3496 split the agent rule registry into a slug-only pointer index
(`AGENTS.md`) plus three change-class sidecars. A SessionStart hook classified
each session's diff into `docs-only` / `code|infra` / `mixed` and injected only
the matching sidecar(s).

That change bundled **two independent mechanisms**, and the repo has been
attributing the benefit of the first to the second ever since:

| Mechanism | What it buys |
|---|---|
| **Index/body separation** — the index is re-rendered every turn; bodies are injected once at SessionStart | The large measured per-turn win recorded for #3496 |
| **Change-class conditionality** — *which* bodies get injected, chosen by a regex classifier over the diff | 8.2–8.9 % of session-start bytes |

Re-measured in this worktree (not quoted from the issue): **70.0 %** of the last
80 squashed PRs are multi-class (**72.0 %** of 200 commits). Multi-class loads
everything, so for roughly seven sessions in ten the classifier already selected
the whole corpus and saved nothing. The weighted-mean saving across all classes
is ~3.6–3.9 kB.

The conditionality was also never free at first turn. #3496's own measured table:

| Session class | Pre-split | Post-split | Δ |
|---|---|---|---|
| docs-only | 24,618 B | 23,842 B | **−3.2 %** |
| code/infra | 24,618 B | 26,773 B | **+8.8 %** |
| mixed (fail-closed) | 24,618 B | 28,767 B | **+16.9 %** |

Two of three classes were *worse* from day one. The mixed class was ~40 % then
and is 70–72 % now, so the mechanism has been a net first-turn cost for the
majority of sessions for its entire life.

The decisive cost is not bytes. A rule placed in a sidecar that does not load for
its own trigger is **absent from exactly the sessions it was written to govern**,
while every lint reports green — "appears enforced, is absent", the worst failure
mode a governance system has. That shipped twice:

- **#3681** — `wg-plan-prescribed-skills-must-run-inline` demoted core→rest.
  `/work` runs on docs-only PRs; `rest` does not load there.
- **#3808** — `cq-skill-description-budget-headroom` placed in `rest`; SKILL.md
  edits are docs-only, so the rule would have been a silent no-op on its own
  trigger.

Both passed `lint-rule-ids.py`, `lint-agents-rule-budget.py`, and CI. Neither was
caught by a gate; both were caught by a human reviewer.

The split also **blocked governance from being written**. ADR-140 records a hard
rule that could not land, and names loader-class infeasibility as the *decisive*
reason: its trigger surface spans `*.tf` (→ infra → core + rest) **and**
`plugins/*/skills/*/SKILL.md` (→ docs-only → core + docs-only). A rule that must
fire on both could only live in the always-loaded sidecar, which had no room.

Finally, the mechanism charged a permanent, shipped **class-fit verification
tax**: mirrored prose in `plan`, `deepen-plan`, and `compound` SKILL.md — including
a hand-maintained `<!-- mirror: … keep in sync -->` marker — existed for no purpose
but preventing the #3681 class.

## Considered Options

- **Option A: exclude `knowledge-base/**` from `DOCS_RE`.** Narrow the classifier
  so knowledge-base edits stop forcing the docs class.
  *Pros:* one-line change; targets the most common multi-class trigger.
  **Cons: UNSAFE, and confirmed so by reading the class-selection block.** With a
  KB-only changeset, `HAS_DOCS=HAS_CODE=HAS_INFRA=0`; `CHANGES` is non-empty so the
  empty-diff arm does not fire, the `>1` arm is false, and both single-class arms
  are false — `CLASSES` keeps its `core` default and the docs sidecar is **silently
  dropped**. That sidecar holds precisely the rules that fire on KB edits
  (`cq-rule-ids-are-immutable`, `cq-agents-md-tier-gate`,
  `cq-agents-md-why-single-line`, `cq-skill-description-budget-headroom`,
  `wg-ui-feature-requires-pen-wireframe`). This reproduces #3681. Making it safe
  requires per-rule trigger-class declarations linted against the classifier — i.e.
  **building more of the mechanism whose cost is the problem**.
- **Option B: relax the inflow rules that force a `.md` alongside code.** The
  structural reason most PRs are multi-class is that Soleur's own gates require a
  learning/spec `.md` with nearly every change.
  *Pros:* attacks the root cause of the multi-class rate.
  **Cons: REJECTED.** Those rules are the compounding-knowledge moat. Do not
  degrade the asset to rescue the optimizer.
- **Option C: collapse to one unconditionally-loaded corpus.** *(CHOSEN)*
  *Pros:* removes the silent-drop class structurally; retires the class-fit tax;
  unblocks rules with split trigger surfaces; makes the budget honest.
  *Cons:* +2.3 kB against the weighted-mean session; no per-class tailoring
  remains if a genuinely class-specific rule ever appears.
- **Option C-ii: collapse the index INTO the corpus** (one file, no pointer
  index). **REJECTED, and future readers must be warned explicitly:** this would
  destroy the index/body separation and put the whole corpus on EVERY turn —
  ~37 kB of bodies, or ~42 kB once the index is folded in, against the ~5 kB of
  pointers a turn costs today. It is the one variant of "collapse" that makes things dramatically worse,
  and it is the obvious next simplification for someone who reads only the title
  of this ADR.
- **Option C-iii: replace hook injection with an `@AGENTS.rules.md` @-import.**
  *Pros:* harness-native, zero injection code, no hook to maintain.
  **Cons: DEFERRED, not chosen.** ADR-094's frontmatter (`last_reviewed`,
  `review_cadence`, `owner`) would leak raw into context — an @-import cannot
  strip. It also drops the symlink-rejection and over-strip defenses. Revisit only
  after freshness metadata moves out of frontmatter.

## Decision

**Collapse the three change-class sidecars into a single `AGENTS.rules.md`,
injected in full on every session (Option C).**

What is retired is the **classifier** — not the loader hook, and not the
index/body separation. `AGENTS.md` remains a slug-only pointer index re-rendered
every turn; the corpus is injected once at SessionStart. The ` → <class>` arrow is
dropped from all 101 pointer lines because there is no class left to name.

The merge is a file move plus a section-wise heading union, nothing else. Rule
**ids** are untouched (`cq-rule-ids-are-immutable`) and no rule was added or
dropped: 101 in, 101 out.

Body text is **100 of 101 byte-identical**, not 101 of 101 — and stating it that
way matters, because the exception is what the control FOUND rather than
something it missed. `cq-agents-md-why-single-line` was rewritten because its own
text described the retired architecture and carries the threshold-mirror literals
the compound-sync gate anchors on. It is `cq-*`, so `GATED_PREFIX_RE` never sees
it: no ack was possible or required, and `.claude/rule-weakening-acks.txt` is
untouched.

Verified two independent ways — a full-corpus sha256 snapshot using
`lint-rule-bodies.py`'s own parse and normalization with the `^(hr|wg)-` gate
disabled (so it covers all **101**, not the 74 the committed manifest covers),
and a sorted raw-body-line diff. Both report exactly that one id.

**That proof is a committed command, not a number pasted into a PR.** Review
flagged the first version as session-perishable evidence, which this repo treats
as equivalent to uncommitted, so the ungated parse shipped as
`lint-rule-bodies.py --snapshot-all`. Anyone can re-derive the result from git
alone — the base side is reconstructed from the merge-base, including the
base-revision linter, so no artifact of the migration session is trusted:

```bash
BASE=$(git merge-base origin/main HEAD); D=$(mktemp -d); mkdir -p "$D/scripts"
git show "$BASE:scripts/lint-rule-bodies.py" > "$D/scripts/lint-rule-bodies.py"
cp scripts/_agents_md_sections.py "$D/scripts/"
for f in AGENTS.core.md AGENTS.docs.md AGENTS.rest.md; do git show "$BASE:$f" > "$D/$f"; done
# base side: 101 bodies · head side: 101 bodies · diff: cq-agents-md-why-single-line
python3 scripts/lint-rule-bodies.py --snapshot-all > /tmp/head.txt
```

The mode refuses to emit a snapshot that parsed zero bodies — a silent `0` would
read exactly like "nothing changed", which is the failure it exists to rule out.

**The decision rests on correctness, not bytes.** An earlier draft also credited
collapse with −939 B/turn from dropping the class arrow; that is **confounded**.
The arrow's captured class is never consumed semantically — residency is derived
from file membership — so the arrow could have been deleted with the split intact.
It is an orthogonal cleanup that collapse merely makes free.

## Consequences

**The measurement got honest; the budget did not get looser.** `B_ALWAYS` was
re-baselined 23000 → 46000. The old ceiling counted the index plus the one
always-loaded sidecar and ignored the other two, describing ~53 % of reality and
gating only the *minority* path. It now measures what every session actually
loads: **42,391 B** — about **1.3 kB smaller** than what the 70 % multi-class
majority was already carrying, and ~2.3 kB larger than the weighted mean. The
margin above the measured value is a ratchet against unreviewed growth, not a
derived quantity; its size is a judgment call and is documented as such.

Relatedly: **the "23,000-byte harness ceiling" was never a harness limit.** That
phrase existed only inside the lint's own WARN string and nowhere else in the
repo. 70 % of sessions were already running at 1.9× it with no recorded harness
failure.

**The hook survives with eight of its nine jobs.** Only the classifier dies. The
frontmatter strip (ADR-094), the over-strip guard, symlink rejection, the
missing-corpus fail-safe, the `(N of M rules)` stamp, the `[session-context]`
snapshot, the SOC 2 CC6.1/CC7.2 per-session manifest, and the tmpfs-guard alarm
block all remain. That last one matters disproportionately: the hook is the **only
SessionStart reader of the tmpfs alarm** (#6991 dead-channel class, pinned by
`scripts/tmpfs-guard.test.sh` Arm 20). Deleting the hook would have looked like a
two-sided edit and actually been a one-sided kill.

**Gates that became unfailable were deleted, not retargeted.** The repo's
anti-vacuity posture says a green gate that cannot fail is worse than no gate:

- `lint-rule-ids.py`'s `hr-*`-must-live-in-core and `[compliance-tier]`-must-live-in-core
  checks are gone. The invariant they enforced — "`hr-*` always loads" — is now
  **true by construction**: there is nowhere else for a body to be.
- `lint-rule-bodies.py`'s cross-sidecar collision detector is gone. Threat F1 (a
  same-id decoy in a *second* sidecar winning a last-file-wins merge) requires a
  second file to host the decoy. Duplicate ids *within* the corpus are still caught
  by `lint-rule-ids.py`'s per-file duplicate check.

**Two checks survive with their justification recorded, because vacuity was
measured rather than assumed.** Dropping the arrow widened the pointer shape to
"id + tags and nothing else", and it was not obvious which of the two
pointer-related checks stayed meaningful:

- The "pointer-shaped line inside the corpus" check in `lint-rule-ids.py` is
  **still reachable** — mutation-verified: appending a slug-only line to the corpus
  fires it. It now catches an index line pasted into the corpus, or a body
  truncated to its slug.
- The pointer filter in `lint-rule-bodies.py` is **not a security control**.
  Measured by gutting a real body to its bare slug: with the filter the id vanishes
  from the head map (74 → 73) and reads as a *deletion*; without it the id stays
  with a changed hash and reads as a *weakening*. Both block and demand an ack. The
  filter decides how the block is classified, not whether it fires. It is kept for
  parse symmetry and deliberately not described as a defense.

**The stamp now reads `N of N` on the happy path, and that is not vacuous.** The
numerator still detects a truncated, partially-written, or over-stripped corpus,
and the denominator comes from a **fixed expected set** (the `AGENTS.md` pointer
count), never from what actually loaded — a denominator derived from the loaded
set degrades in lockstep and renders a truncated corpus as 100 %.

**A missing corpus became a genuinely reachable state, which exposed a latent
bug.** Previously the fail-safe re-walked three sidecars, so at least one body was
always present and `CONTEXT` was never empty. With one corpus, a missing or
symlink-rejected file leaves it empty; `grep` exits 1, `pipefail` propagates, and
the ERR trap fired — replacing the honest `0 of N rules — fail-safe: corpus
missing` blackout stamp with a generic FALLBACK naming no cause. That is the
#7008 defect class (an instrument misreporting its own coverage) on the single
most important failure path, and it is now guarded.

**The ADR-092 weakening gate passes vacuously for exactly one commit.** `SIDECARS`
is head-side, so across the merge commit `git show <base>:AGENTS.rules.md`
resolves to nothing and the base map is empty. This is accepted and disclosed, not
overlooked: the compensating proof is the all-101 body-hash identity snapshot
above, which covers the 27 `cq-*`/`rf-*`/`pdr-*`/`cm-*` bodies the committed
74-entry manifest cannot speak to. Splitting the file move and the constant into
separate commits would be strictly worse — every gated body would read as DELETED
and demand ~74 WORM acks.

**A deployed cron was coupled to the retired filename and failed OPEN.**
`cron-compound-promote` runs from a deployed build, so between merge and redeploy
it would have read the absent file as `""` — collapsing the measured payload from
~40 kB to ~5 kB, inventing ~35 kB of phantom headroom for the proposer, and
disabling its own post-apply overflow guard, which compares against the same
falsely-low number. Worse, `TARGET_ALLOW_RE` would still have allowed it to open a
PR **resurrecting the retired file**, writing new rules into a file no loader
reads. Both it and `scripts/compound-promote.sh` now fail loud on a missing input,
and the allow-list no longer permits the retired target.

**Authoring gets simpler.** Placing a rule no longer requires reasoning about
which file classes fire on its trigger surface, so the mirrored class-fit prose in
`plan`/`deepen-plan` and the demote-to-a-sidecar rung of `compound`'s shrink ladder
are removed. The remaining shrink levers are trim-prose and retire-a-rule — and per
#6794 the retirement rung is not currently actionable, because the
`rules_unused_over_8w` metric is a per-worktree fragmentation under-count.

**Downstream issues whose premise is retired:** #7013 (B_FAILOPEN reporting —
`B_FAILOPEN` exists only because the loader can fail open across three sidecars),
#6138 (shrink `B_ALWAYS` below 22 k — unreachable by construction now that the
number measures the whole corpus), and #3792 (path-scoped `AGENTS.<lang>.md` —
explicitly premised on extending the classifier, and the measured ~8 % is evidence
against that ROI).

**Negative consequences, stated plainly:** every session now pays for every rule
at first turn, so corpus growth has no per-class escape valve; and if a genuinely
class-specific rule ever appears, the answer is to put it in the owning
skill/agent (per `cq-agents-md-tier-gate`), not to rebuild the classifier.

**This ADR supersedes a spec, not an ADR.** The split shipped under
`knowledge-base/project/specs/feat-agents-md-change-class-loader/` and never had an
ADR. It amends eight ADRs unevenly: substantively **092** (a named threat class
ceases to exist), **094** (decision intact — and it is now the decisive reason
hook injection beat an @-import), **140** (its decisive rejection rationale is
void; the blocked `hr-*` rule is writable again), and **116** (reach restated as
unconditional); a factual fix to **070** (its prior-art citation is now a
cautionary precedent); token swaps in **139** and the *active* **027** (two files
share that ordinal — only the `active` one is in scope); and a note on **086**.

**Residual references.** Within the swept scope — everything except
`knowledge-base/project/{plans,specs,brainstorms,learnings}` and `**/archive/**`,
which are point-in-time records that must keep the old paths — four remain, each
by decision: the **ack record** at `.claude/rule-weakening-acks.txt` line 22
(append-only WORM, CODEOWNERS-gated; rewriting a historical ack would alter a
signed audit record); `tests/scripts/fixtures/tfplan-real-ruleset-baseline.json`
(a captured Terraform plan, not a live assertion); and two self-references in this
ADR — the base-side reconstruction recipe, which must name the base-side files to
work, and the quotation of that ack's reasoning below.

That file's **header comment** was a fifth hit and was *not* left in place: it is
parser-ignored prose that instructed authors to ack changes to files that no longer
exist, which is prescriptive-not-narrative and therefore the "appears retired, still
advises" failure named above. It was corrected, along with a pre-existing typo
pointing at `rule-body-hashes.json` where the manifest is `.txt`. The append-only
property constrains ack *records*, not the header that explains them.

The sweep regex itself needed widening to find any of this. The plan's AC6
alternation matched `AGENTS.{core,docs,rest}.md` but not `AGENTS.{md,core.md,docs.md,rest.md}`
— a different brace spelling that hid two live residuals, one of them inside
`lint-agents-rule-budget.py`, the very script AC4 cites. A sweep is only as wide as
its worst-covered spelling, which is the same lesson as the rest of this change:
the check reported zero for a reason unrelated to the property being claimed.

Outside that scope the narrative corpus still names the retired files ~100 times,
which is correct for a historical record — with one caveat worth naming, because
it is this ADR's own thesis pointed at itself: a learning that *prescribes* a
demotion ladder is not inert narrative, it is live advice that `learnings-researcher`
will surface during `/plan`. "Appears retired, still advises" is the mirror of
"appears enforced, is absent". The prescriptive ones carry a superseded marker.

**Every new rule now costs always-loaded bytes — the zero-cost tier is gone.**
This is the consequence most likely to surprise the next author, because it was
never written down as a design property; it was simply the shape of the old
system. Under the split, a `rest`-class rule was excluded from `B_ALWAYS`
entirely, and authors reasoned that way explicitly — the WORM ack for
`wg-when-an-audit-identifies-pre-existing` records the trade in exactly those
terms ("AGENTS.rest.md is excluded from B_ALWAYS so this costs zero always-loaded
bytes"). That escape valve is now closed, and nothing replaced it: there is no
eviction, pruning, or demotion policy, while `/compound` proposes rules routinely.

The current margin, measured: `B_ALWAYS = 42,547 B` against `44,000` warn and
`46,000` reject — **1,453 B** and **3,453 B** of headroom. Mean rule body is
**366 B** and the per-rule cap is **600 B**, so the ratchet is roughly **four
average-sized rules to the warn tier and nine to hard reject** (three and six at
the cap). `AC4` proves today's state and says nothing about the trajectory.

The decision at the ratchet is deliberately **not** pre-authorized here, because
"raise the ceiling" is the move that would quietly undo this ADR's own reasoning:
the ceiling moved from 23,000 to 46,000 in this change because the *measurement*
became honest, not because the budget loosened, and a second raise justified by
citing the first would be a ratchet with no floor. When the warn tier is next
reached, the options are, in order: retire a rule via `retired-rule-ids.txt`
(rule IDs are immutable — retire, never reuse); route the insight to a skill or
agent where it is enforced closer to the action; tighten an existing body against
the 600 B cap. Re-baselining the ceiling is a last resort that requires its own
recorded rationale, not an inline bump.

## Cost Impacts

None. No vendor, subscription, or infrastructure change. The change is repo-local
files plus a SessionStart hook. Anthropic API token cost per session moves by
roughly +2.3 kB against the weighted mean and −1.3 kB against the majority path —
inside noise for any real session, and not the basis for this decision.

## NFR Impacts

None as tiered in `knowledge-base/engineering/architecture/nfr-register.md`. The
SOC 2 CC6.1/CC7.2 evidence path (`.claude/.session-manifests/`) is explicitly
preserved rather than changed: the manifest keeps its three-field schema, with
`change_class` pinned to the constant `"all"` rather than dropped, so any
historical-manifest reader still parses and the recorded value stays honest.

Observability is strengthened, not merely preserved: the governance-blackout path
(missing/symlinked/truncated corpus) now reports its own cause in the session stamp
instead of degrading to an unattributed fallback.

## Principle Alignment

| Principle | Title | Status | Note |
|---|---|---|---|
| AP-006 | All knowledge in committed repo files | Aligned | The corpus stays a committed repo file; nothing moves to local-only state. |
| AP-011 | ADRs for architecture decisions | Aligned | This ADR is the record; the split it retires never had one, which is part of why the mechanism outlived its evidence. |
| AP-017 | Additive-only auto-edit boundary | Aligned, with a disclosed one-commit gap | The WORM ack gate and its recursion invariant are preserved and retargeted. The single vacuous-pass commit is disclosed above with the all-101 hash snapshot as the compensating proof, and the auto-editable target list no longer permits resurrecting the retired file. |

No deviations requiring an exception.

## Diagram

No C4 impact — enumeration cited, not assumed. All three model files were read
(`model.c4`, `views.c4`, `spec.c4`):

- **External human actors:** none added or changed.
- **External systems / vendors:** none — this is a repo-local file plus hook change.
- **Containers / data stores:** the model's `Hook Engine` container description
  enumerates "phase-surface hints (ADR-070) and declarative skill context_queries
  (ADR-086)" and **never mentioned the rules loader**, so retiring the classifier
  falsifies no description. `AGENTS.*` are repo files, not modeled data stores.
- **Actor↔surface access relationships:** none change.

A grep for `rules-loader|AGENTS|SessionStart` across all three `.c4` files returns
zero hits. (Pre-existing and out of scope: the `Hook Engine` description is
*incomplete* — it omits the rules loader entirely.)
