# Plan Scope Check

The always-on scope check emitted into every plan by `soleur:plan` Phase 2.4 and
verified by `soleur:deepen-plan` §4.12. It answers two questions the pipeline
previously could not: *which user ask does this plan item serve?* and *does this
diff outgrow the brief?*

## Section schema (canonical copy)

Emit this block into the plan, immediately before `## Acceptance Criteria`:

```markdown
## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "<ask, quoted>"     | FR-2 / Phase 2 / Files-to-Edit entry | mapped |
| 2 | "<ask, quoted>"     | —        | descoped — justification: <reason> |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| <item>    | "<quote>"                         | asked   |
| <item>    | —                                 | inferred — justification: <reason> |

### Split Assessment

- Subsystems touched: <N> — <subsystem roots>
- Planned files: <N> | Estimated changed lines: <N>
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR | split — <proposed PR boundary>
```

## Extracting the asks

One row per ask, verbatim quote in the table — never a paraphrase.

- **`#N` invocations:** pull the asks from `gh issue view <N> --json body`. An ask
  is a discrete requested outcome: a task-list item (`tasks a–f`), a numbered or
  bulleted requirement, an acceptance bullet, or an imperative sentence
  ("the plan must …").
- **Freeform invocations:** extract the same shapes from the
  `<feature_description>` text.
- **Multi-signal briefs** (issue + prose + linked docs): enumerate asks from
  every source and mark the column with its origin.

## Mapping rules

Run the mapping in BOTH directions:

- **Ask → item:** every ask names the plan item that serves it (FR, phase, or
  `Files to Edit`/`Files to Create` entry). An ask with no item is `unmapped`
  unless the row is marked `descoped — justification: <reason>`.
- **Item → ask (Plan-Item Provenance):** every plan item, default, rung, or
  added step cites the verbatim user words it answers. "Per operator direction",
  "the user asked", "as requested", and similar phrases MUST embed the quote —
  the phrase alone is not a citation. An item with no quote is `inferred`, and
  `inferred` REQUIRES a justification naming the dependency, safety reason, or
  enforcement contract that needs it (e.g. "the drift pin or the contract rots").

## BLOCKED handling

An `unmapped` ask, or an `inferred`/`descoped` row with an empty justification,
blocks the plan.

- **Interactive:** resolve via AskUserQuestion — justify, descope (with reason),
  or rework the plan.
- **Headless / pipeline:** write `status: BLOCKED` as a line inside the
  `## Scope Check` section body (never the plan's frontmatter `status:` field),
  append the offending rows to
  `knowledge-base/project/specs/<branch>/decision-challenges.md`, and stop —
  do not emit the plan as finished. Resolving the rows removes the marker —
  deepen-plan §4.12 rejects a section still carrying it.

A plan may quote the schema for reference only inside a fenced code block —
unfenced `## Scope Check` headings are the live section, and more than one is
malformed. The LAST unfenced occurrence is authoritative at deepen-plan §4.12.

## Split assessment

Compute from `## Files to Edit` + `## Files to Create` once those lists are
drafted. Subsystem root = `apps/<x>` / `plugins/<x>` (two-segment roots), first
path segment otherwise. Thresholds (declared tunables — tune on observed false
positives): `>= 4` subsystem roots OR `> 25` planned files OR `> 800` estimated
changed lines. Over any threshold → `Recommendation: split — <proposed PR
boundary>` naming the seam; otherwise `single PR`. The recommendation is
advisory at emit time; a split offer ignored without a reason is exactly the
silent-growth class this gate exists to surface.

## Placement

Runs at plan Phase 2.4 — after `## Files to Edit`/`## Files to Create` are
stable and before the Phase 2.5 domain fan-out, so a BLOCKED verdict or split
recommendation fires before the expensive machinery (research, domain leaders,
deepen-plan).

**Why:** #9398 — on PR #9339 a small brief (tasks a–f) grew a destructive
`--attest` rung nobody asked for and a 101-file diff; 3 of 7 plan reviewers cut
it only after the plan was written and deepened, costing an 11-seat review and
~8 CI cycles. The ask↔item mapping makes invented scope visible at write time,
and the split assessment fires while a split is still cheap. See
`knowledge-base/project/learnings/2026-03-12-plan-review-scope-reduction.md` and
`2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`.
