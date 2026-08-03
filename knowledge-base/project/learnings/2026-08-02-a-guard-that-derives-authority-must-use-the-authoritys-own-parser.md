---
date: 2026-08-02
category: security-issues
module: ship/net-issue-flow
tags: [gates, fail-open, mutation-testing, fixture-shape, parser-parity, telemetry]
issues: [7161, 7172]
related_learnings:
  - 2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md
  - 2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md
  - 2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis.md
---

# A guard that derives authority from a corpus must use that corpus's OWN parser

## Problem

Two repo gates were in genuine conflict.
`wg-block-pr-ready-on-undeferred-operator-steps` REQUIRES a tracking issue for a
bare operator action; `net-issue-flow.sh` BLOCKS any PR filing more issues than
it closes. Neither documented exit applied — "fix inline" is a SIZE test and the
blocker was AUTHORITY; "close something" needs a superseded issue, which a
mandated tracker never is. The only exit was a blanket override whose help text
called itself an *"architectural-pivot deferral"*, so complying with one rule
required mis-describing the escape from the other.

The fix: an exemption whose qualifying rule-ids are DERIVED from a
`[mandates-filing]` marker in `AGENTS.rules.md`, gated by ADR-092's
human-reviewed ack. The whole design rests on one claim, stated in three places:
*"an agent can only ever name one of N already-blessed rules"* — a **closed
vocabulary**, which is what distinguishes it from a free-form reason string.

## Root cause

The derivation was a shell grep:

```bash
grep -F -- '[mandates-filing]' | grep -oE '\[id: (hr|wg)-[a-z0-9-]+\]'
```

ADR-092's own `parse_bodies` gates a line on **four** conjuncts: under a `## SECTION`
in `SECTIONS`, `line.startswith("- ")` at column 0, not pointer-shaped, and the
`^(hr|wg)-` prefix. The grep enforced **only the last one**.

So it was a strict SUPERSET along the line-shape axis. Measured on the shipped
corpus, appending two lines:

```
  - Note: [mandates-filing] for [id: hr-menu-option-ack-not-prod-write-auth].
Convention: [mandates-filing] for [id: wg-zero-agents-until-user-confirms].
```

→ the grep derived **4** ids; `parse_bodies` saw **2**. Neither added line is a
body line, so both are invisible to the ack gate, to `SECURITY_TAG_MARKERS`, to
the hash manifest and to `lint-rule-ids.py` — and fully visible to grep. No ack,
no manifest diff, no linter output. Delivered over two PRs (the corpus is read at
merge-base), it was a permanent repo-wide widening of a blocking gate.

The ADR's sentence *"the derived set is by construction a subset of the ADR-092
ack gate's coverage (`GATED_PREFIX_RE`)"* was the precise error: `GATED_PREFIX_RE`
is **one conjunct of four**. Restricting to it makes the set a subset along the
*prefix* axis and a superset along the *line-shape* axis.

## Solution

Stop re-implementing the predicate. `lint-rule-bodies.py` grew an
`--emit-mandating-ids` mode that reads a corpus on STDIN and reuses its own
`parse_bodies`; the gate pipes the merge-base corpus through it and fails CLOSED
on any error (missing python3, parse failure, non-zero exit).

```bash
MANDATING_IDS="$(printf '%s\n' "$CORPUS_TEXT" \
  | python3 "$REPO_ROOT/scripts/lint-rule-bodies.py" --emit-mandating-ids 2>/dev/null \
  || true)"
```

One parser, one predicate — which is the same argument the ADR already made for
not hardcoding the id list in the gate. Both exploit shapes now derive nothing;
the legitimate set is unchanged.

## Key insight

**When a gate reads a file to decide who has authority, the ONLY safe reader is
the parser that file's own gate uses.** Any re-implementation is a second
predicate, and the two will differ — not necessarily in the direction you check.
The seductive part is that the re-implementation looks *stricter*: `^(hr|wg)-`
reads like a tightening, and it is, on the axis you were thinking about. The
conjuncts you did not think about are where the authority leaks.

Ask, of any derived-authority check: *what does the authoritative gate require
that my reader does not?* Enumerate its conjuncts and diff them, rather than
confirming the one you deliberately added.

## The battery could not have found it — and what it did find

37 mutations, all eventually killed. But the first battery reported **29/29
killed** while this P1 was live, because every mutation perturbed the
*implementation* and the defect was in the *fixture space*. Four of the defects
review found were fixture-shape, not assertion-shape:

| Defect | Why no mutation could see it |
|---|---|
| Corpus line shape (the P1) | No fixture had a marker on a non-body line |
| `merge-base HEAD HEAD` (same-PR self-grant) | Stub prefix-matched `merge-base*`, so it could not reject a wrong ref |
| Gated-`SECTION` conjunct | Every fixture line sat under a gated heading |
| `NET=0 if EXEMPT>0` | Every exemption fixture had exactly one issue — 1-of-1 is all-of-1 |

Three of these SURVIVED a battery that was itself written to be adversarial.
The generalization, which this repo keeps re-learning: **a battery measures the
mutations its author imagined; the axis authors systematically miss is the shape
of the fixtures, not the content of the assertions.** Before trusting a green
battery, sweep the fixture set and ask what shapes the producer can emit that no
fixture instantiates.

Corollary that did work: the battery earned its keep only because one mutation
targeted the **parser** rather than the gate. Mutating across the module boundary
is what surfaced the untested conjunct.

## Session errors

- **The exemption's own attribution was unreadable by construction.** `_emit`
  hardcodes `rule_id="net-issue-flow"`, so `_emit_as "net-issue-flow-mandated-filing--<rule>"`
  put the rule in the free-text `rule_text_prefix`, which the aggregator never
  parses. The `summary.gate_exemptions` readout — the feature's sole surviving
  justification once unforgeability is conceded — would have returned `[]`
  forever. **Prevention:** when adding a telemetry field whose purpose is to let
  a consumer make a distinction, `git grep` the field across CONSUMER paths
  before claiming it; a count of 0 means the gap is still fully open.
- **Two new warn ids reached `rule-metrics.json` nowhere.** The single-dash
  `…-corpus-unreadable` / `…-zero-tagged` ids that correctly keep them out of
  `gate_exemptions` (double-dash prefix) also kept them out of every other key,
  while `orphan_rule_ids` filters the whole `net-issue-flow` prefix. The same
  defect the PR diagnosed, reproduced one level down inside its own fix.
  **Prevention:** same grep-the-consumer rule; a new rule_id needs a reader.
- **Fence-strip applied to three of four inputs.** The marker, claim and
  companion matches all read the stripped PR body; `CLOSING` read the raw one, so
  a fenced `Closes #4242` — a quoted commit message, routine here — bought free
  NET credit on a blocking gate. **Prevention:** when a normalization exists,
  enumerate every consumer of the un-normalized value; strip once, before any
  reader.
- **The remedy was pinned where I read it, not where the agent reads it.**
  Deleting the entire `(d)` block from the hook's deny payload left both suites
  green. The gate's stdout reaches an agent only as embedded `${OUT}`; the
  payload is the surface. **Prevention:** ask which artifact the consumer
  actually receives, and pin that one.
- **The test suite wrote ~116 fake rows into the operator's REAL telemetry** in
  one afternoon (against 11 genuine rows in the prior 12 days), feeding the
  aggregator and soak probe this same PR edits — the suite was poisoning the
  metrics the feature adds. `INCIDENTS_REPO_ROOT` was scoped to two cases instead
  of the suite. **Prevention:** redirect side-effecting sinks at suite scope,
  never per-case; assert the delta is 0 after a run.
- **Cases 1–14 ran against an EMPTY corpus.** The fixture heredocs were written
  200 lines BELOW the cases whose comment claimed they used them. **Prevention:**
  when a comment claims a fixture is in effect, instrument one case and read the
  actual value rather than trusting declaration order.
- **The cause ladder lied when the exemption was inactive** — with an empty set
  every claim reported "names a rule that does not carry `[mandates-filing]`",
  including for rules that do, sending an agent to guess another id. **Prevention:**
  a cause ladder needs a rung for "the mechanism is off", evaluated first.
- **A NEW rule carrying the marker was a CI warning, not an error.** AP-017's
  additive lane takes no ack, so the widest door into the exemption was the one
  an author reaches for *because* adding a rule is the sanctioned safe primitive.
  **Prevention:** when a marker GRANTS rather than DESCRIBES, the additive lane
  needs its own gate.
- **Harness failures that produced false verdicts, not missing ones.** Nested
  bash→python quoting yielded 6 spurious `BROKEN`; a per-mutation `cp -a` copied
  2.3 GB of `node_modules` 26 times and timed out twice; a PATH-mirror loop forked
  `basename` 7,045 times and hung a suite for 2 minutes. **Prevention:** put
  mutation patterns in the target language, not through shell quoting; exclude
  `node_modules` from any sandbox copy; use `${f##*/}` not `basename` in loops.
- **Three of four ADR cross-links were invented filenames** that happened to have
  real ordinals. **Prevention:** resolve every relative doc link against `ls`
  before committing — an ordinal existing does not mean the slug does.
- **A background task's completion notification reports the wrapper's exit**, not
  the command's; the suite's rc had to be read from an explicit rc file.
  **Prevention:** already `hr-`-covered; the failure is reflexively trusting the
  notification.
- **`lint-agents-enforcement-tags.py` has linted ZERO tags since ADR-151** — it
  defaults to `AGENTS.md`, which that ADR made pointer-only, so all 42
  enforcement tags in `AGENTS.rules.md` are unvalidated and it reports
  `OK: all 0 hook + 0 skill … resolve`. This also falsified a plan premise (FR10
  claimed it validates the ship anchor). Filed as **#7172** — 12 pre-existing
  unresolved anchors, two needing retire-the-rule decisions. **Prevention:** a
  gate reporting "0 checks passed" is reporting nothing; assert a non-zero
  cardinality floor on any all-members linter.
- Plan-phase forwarded errors (see `session-state.md`): the gate already exceeded
  its `timeout 8` in production (1 of 3 runs `rc=124` → silent always-pass); nine
  P0s in plan v1, four asserted from documents rather than measured; three ACs
  structurally unsatisfiable; one AC vacuously green; one proposed test seam was
  itself a self-grant vector.

## Prevention (generalized)

1. **Derived-authority readers must call the authority's parser.** If that is
   impractical, enumerate the authority's conjuncts and assert your reader
   enforces each — then mutate ACROSS the module boundary to prove it.
2. **Sweep fixture SHAPE, not just assertion coverage.** For each property, name
   the set it quantifies over and count distinct shapes the fixtures instantiate.
   One shape is a sample, not a proof, and no code mutation detects it.
3. **A new telemetry field needs a consumer in the same PR.** `git grep` it; a
   zero means the gap the field was added to close is still open.
4. **Normalize once, above every reader.** A normalization applied to N-1 of N
   consumers is a fail-open on the one you forgot.
