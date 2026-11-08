---
title: "docs(legal): land the 2026-11-08 CLO re-assessment record for #11294 and update the breach-register row"
date: 2026-11-08
slug: docs-11294-clo-reassessment-record-landing
branch: feat-one-shot-11294-clo-reassessment
issue: 11294
type: docs
domain: legal
brand_survival_threshold: none
lane: cross-domain
---

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch; the pipeline brief supplies the spec content.

# docs(legal): land the 2026-11-08 CLO re-assessment record for #11294 and update the breach-register row

## Enhancement Summary

**Deepened on:** 2026-11-08
**Sections enhanced:** Observability (skip → real 5-field block), Encryption Posture (skip
reworded off the literal trigger phrase), Acceptance Criteria (Pre-merge/Post-merge split),
Scope Check (ask provenance completed), Guard Contract (marker + matrix + anchor per
lint-guard-contract.py)
**Research agents used:** none — no Task/Agent tool in this subagent context; every deepen-plan
gate was executed inline against the repo (see gate ledger below)

### Key improvements

1. Observability converted from a skip to a real block — `scripts/lint-legal-registers.sh` is a
   non-docs path, so deepen-plan Phase 4.7's detection fires; the lint's own pass/fail output is
   its surface and `bash scripts/lint-legal-registers.sh` → `all assertions passed` is the
   discoverability probe (allowlisted verb, <15 s, literal match).
2. Premise validation surfaced the plan's one real fork: the CLO-prescribed composite
   canonical-source cell is unparseable by `lint-legal-registers.sh`'s single-path extraction —
   the plan carries the forced parser extension plus the Guard Contract it requires, recorded as
   a `pending - assumed:` technical ruling in `decision-challenges.md` for ship-time CTO
   conversion (no Agent tool here).
3. All issue/PR citations verified live (4 issues OPEN, PRs #12387/#8626 checked); no
   `Closes|Fixes|Resolves` anywhere.

### New considerations discovered

- PR #8626 touches `breach-register.md` at ~line 128 (2026-09-03 row) — disjoint from our edits;
  cell re-greps remain gated at work time anyway (AC-3).
- The new record matches `DETERMINATION_PATTERN` (produced=43 after landing) so it MUST be
  index-cited — the waiver alternative was semantically wrong, not merely heavier.
- `technical-ruling-gate.sh` fails a `technical` row carrying `pending - assumed` — that is the
  designed headless fallback: ship/work converts it via a CTO spawn (≤2 attempts) else drafts +
  files an issue. Mechanical choices were classified `taste` to keep the pending set minimal.

### Gate ledger (deepen-plan, run inline 2026-11-08)

- 4.6 User-Brand Impact — PASS (threshold `none`; zero sensitive-path hits on the diff)
- 4.7 Observability — PASS after the §Observability fill-in (5 fields, allowlisted verb, literal expected_output)
- 4.8 PAT-shaped variables — PASS (no hits)
- 4.9 UI wireframe — SKIP (no UI-surface file)
- 4.10 Encryption Posture — SKIP (no store/connection file or trigger prose)
- 4.11 Guard Contract — PASS (`lint-guard-contract.py`: 1 entry, matrix rows counted)
- 4.12 Scope Check — PASS (exactly 1 unfenced section; all asks mapped, inferred items justified)
- 4.13 Task Design — SKIP (no new autonomous surface)
- 4.4 Precedent-diff — the parser extension's precedent is the same file's existing single-path
  extraction block; contract diff is described inline under Technical Considerations
- 4.45/4.5/4.55 — SKIP (no negative-security claims to verify, no SSH/outage triggers, no
  downtime-inducing operation)

## Overview

The `soleur:legal:clo` agent ran its statutory re-assessment of the #11294 incident on 2026-11-08
(the trigger that fired: rotation not recorded complete in #11294). Its verdict: the 2026-10-29
determination STANDS, PROVISIONAL — a security incident, not a presumed notifiable personal-data
breach; no Art. 33/34 change; re-assessment re-armed for 2026-11-15. This plan lands the CLO's
finished record verbatim at its canonical path, applies the CLO-prescribed in-cell updates to the
2026-10-29 breach-register row, appends the dated Corrections section, and carries a verbatim
post-merge comment for #11294. The CLO's wording is the attestation: the pipeline lands it
verbatim and verifies conventions; it does not rewrite the record's prose.

## Research Insights

### Premise Validation (Phase 0.6)

- **Cited issues** — `gh issue view`: #11294 OPEN (`security: terraform prints random_id ids …`),
  #11711 OPEN (`security: rotation tracker …`), #9927 OPEN (`infra: Inngest LUKS key-loss
  residuals …`), #11922 OPEN (`feat(web-platform): accept a previous GitHub webhook secret …`).
  All four stay open; the brief's `Ref`-only constraint is honored.
- **Cited artifacts** — `/tmp/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` exists
  (13,895 bytes, valid legal frontmatter: `type: clo-attestation`, Tier-1 classification,
  `signed_off_at: 2026-11-08`). Target
  `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` does NOT
  yet exist. Every `related_records` path in the record's frontmatter resolves on disk
  (`2026-10-29-clo-determination-11294-…`, `2026-10-31-11294-run-log-evidence-preservation.md`,
  `2026-11-02-a6-no-known-access-record-inngest-keys.md`, plus
  `specs/archive/20261104-211526-feat-one-shot-11294-11711-rotation-audit/{audit-findings-11294.md,rotation-census-11711.md}`).
- **Register row** — the 2026-10-29 #11294 row is `knowledge-base/legal/breach-register.md:143`.
  All three cell texts the brief quotes as superseded match the file byte-for-byte (event-cell
  tail `Containment and rotation are owner-gated and not yet done`; the whole open-limbs cell;
  the canonical-source cell `` `knowledge-base/legal/audits/2026-10-29-clo-determination-…` ``).
- **STALE PREMISE FOUND — the prescribed canonical-cell append breaks `lint-legal-registers.sh`.**
  The lint parses the index's last column with `awk -F'|' … trim($(NF-1))` and treats the WHOLE
  trimmed cell as ONE repo-relative path (`scripts/lint-legal-registers.sh:263-303`). Appending
  `` `; 2026-11-08 re-assessment: `…` `` makes the cell a composite string that resolves to no file:
  assertion (b) fails (`cites a path that is not TRACKED`), and assertion (c) then sees NEITHER
  cited path line-equal to a produced file, failing for both the 2026-10-29 record and the new
  one. The lint is BLOCKING (`scripts/test-all.sh:6158`, no `--advisory`). The deliverable cannot
  merge as literally prescribed without a companion change — see `## Proposed Solution`.
- **Collision pre-check** — `collision-precheck.sh 11294`: the only open PR naming #11294 is our
  own draft #12387. Foreign `proc.sh` hits are unrelated `test-all.sh` runs in sibling worktrees.
- **PR #8626 conflict check** — open draft #8626 DOES touch `breach-register.md`, but its diff is
  a single line on the 2026-09-03 Sentry row (~line 128). Our edits land on line 143 and at file
  end — no text-level or hunk-level conflict.
- **Open code-review overlap (Phase 1.7.5)** — 94 open `code-review` issues; none name
  `breach-register.md`, `lint-legal-registers{,.test}.sh`, or `knowledge-base/legal/audits/`.
  Result: `None`.

### Property List (Phase 0.6b)

1. The CLO record exists durably in-repo at its canonical `audits/` path, verbatim.
2. The 2026-10-29 row's event / open-limbs / canonical-source cells carry the CLO's new text,
   in-cell, per the register's own corrections convention.
3. Superseded cell text is preserved verbatim in a dated `## Corrections` section (append-only).
4. `lint-legal-registers.sh` stays green with a multi-source canonical-source cell — every cited
   path validated on disk, no cited path silently dropped, a zero-citation row still fail-closed.
5. The verbatim CLO comment reaches #11294 after merge (tracked, not executed, by this plan).
6. No issue closes; no secret values land anywhere (counts/dates/ids only).

### Cut List (Phase 0.6b)

- **A new lint/guard for legal records** — property 4 is already bought by
  `lint-legal-registers.sh`; extending its parser is the minimal mechanism. No new guard.
- **A `NOT_TRANSCRIBED` waiver for the record** — the CLO prescribed citing the record in the
  canonical-source cell; indexing it while waiving it would violate the (c) disjointness
  invariant ("a file is either a determination in the register or an explained exclusion, never
  both"). Cut as a mechanism; retained only as the rejected alternative in the ruling row.
- **New register row for the re-assessment** — the index is of *determinations*; the record is a
  re-assessment that says the determination STANDS, and the register's in-cell corrections
  convention (per the 2026-09-14 section) is the designed vehicle. Cut.
- **External research (Phase 1.6/1.6b)** — skipped: strong local context; all conventions are
  repo-internal (register precedent commits, the lint itself). No external surface.
- **SpecFlow / community discovery / domain-leader spawns** — no Task/Agent tool exists in this
  subagent context; equivalents done inline (overlap check, semantic domain read). Product/UX
  gate: no UI-surface files → NONE.

## Problem Statement / Motivation

The CLO's 2026-11-08 re-assessment is an Art. 33(5) file document: it must exist durably, the
register row must reflect the reassessed state, and the superseded text must remain recoverable.
Two frictions shape the work:

1. **The prescribed canonical-cell append is a format the register's own integrity lint has never
   parsed.** Every one of the 15 current canonical-source cells carries exactly one backticked
   path. The CLO's prescription makes the #11294 cell the first composite cell; the lint as
   written reads the whole cell as one path and fails closed. Premise validation caught this
   before any edit.
2. **Every register edit is evidence-shaped.** The CLO Sharp Edge requires verifying each cell's
   current text before replacing; a drifted cell means STOP, not blind edit.

## Proposed Solution

Four deliverables, one fork resolved at plan time:

1. **Land the record verbatim.** `cp /tmp/2026-11-08-clo-reassessment-11294-rotation-incomplete.md
   knowledge-base/legal/audits/` and byte-verify (`cmp`). Conventions check only — frontmatter
   sanity and a no-secret-shaped-values scan; the CLO's prose is not edited.
2. **Extend the lint's cited-paths extraction (the ruling's assumed default).** In
   `scripts/lint-legal-registers.sh`, the `$(NF-1)` awk block emits ONE line per backtick-enclosed
   span in the canonical-source cell instead of the whole trimmed cell, with a new fail-closed
   arm for a row emitting zero candidates. Per-path resolution checks and the line-equality (c)
   joins are untouched. Fixture coverage lands in `scripts/lint-legal-registers.test.sh`. The
   lint change is proven GREEN against the unmodified register before the register edit — the
   parser change alone must not disturb the 15 single-path cells. Recorded as
   `pending - assumed:` in `decision-challenges.md` (no Agent tool in this context); the
   alternatives and their rejection are under `## Alternative Approaches Considered`.
3. **Apply the four register edits.** (a) event-cell sentence replacement; (b) whole open-limbs
   cell replacement; (c) canonical-source cell append — the text the CLO prescribed lands
   verbatim, composite cell now parseable; (d) append `## Corrections — 2026-11-08 (#11294
   re-assessment)` at file end with `> **Superseded 2026-11-08 (#11294) — applied in-cell:**`
   markers quoting each superseded clause, closing on a `**Determination unchanged.**` line. Plus
   one `inferred` edit: append the new record to the frontmatter `related:` list — convention
   measured at commit `45df1eef3f` (the 2026-10-29 determination landing added its record there).
4. **Post-merge runbook step.** Post the brief's verbatim comment on #11294 after merge —
   recorded in the plan/tasks and the PR body, executed post-merge (not a plan-phase action).

## Technical Considerations

- **The awk contract, precisely.** Current: `inblk && /^\|[ \t]*20[0-9][0-9]-/ { print
  trim($(NF-1)) }`. New: split `$(NF-1)` on `` ` ``, emit each enclosed (even-indexed) span
  trimmed, one per line; count rows emitting ≥1 span; `die2`-class failure if that count differs
  from the delegated `count-data-rows` row count (replaces the `resolved+broken == row_count`
  reconciliation, which becomes wrong at 16 paths / 15 rows). Every emitted line flows through
  the existing absolute/`..`/symlink/tracked/`-f` gauntlet unchanged, so a backticked non-path
  span in a canonical cell fails closed — the documented convention "canonical-source cells
  contain only backticked repo-relative paths" is load-bearing and already true of all 15 cells.
- **`## Index of determinations` section scoping is unchanged** — the `inblk` flag still bounds
  the parse to the index table; `related:` and `§Excluded records` paths stay invisible to the
  producer, exactly as the lint's header requires.
- **(c) stays line-exact** — `grep -qxF "$rel"` against emitted lines means a composite cell
  indexes BOTH records; disjointness (c) and the `OUT_OF_SCOPE_ROW` literal check need no edits.
- **Corrections-section precedent** — `## Corrections — 2026-09-14 (#7945, PR #8153)` establishes
  in-cell edits + verbatim blockquote markers; the 2026-09-08 section establishes the
  `> **Superseded …:**` marker shape. The CLO's marker text `— applied in-cell:` matches.
- **Token-lint safety** — no `TBD`/`TODO`/`XXX`/`FIXME` may land outside backticks in
  breach-register.md (assertion (a), standalone markers only).
- **Conventions on the record file** — filename/date/frontmatter verified at landing; the file
  joins `produced=43` under (c) and MUST be index-cited (it matches `DETERMINATION_PATTERN` —
  grep-verified: contains `Art. 4(12)`, `Art. 33(5)`, `Art. 33`).
- **Secrets** — the record is counts/dates/run-ids only per the brief; the landing step includes
  a verification scan anyway (defense in depth, not a rewrite license).
- **`test-affected-kb-consumers.baseline.txt:261`** maps `lint-orphan-test-suites` to
  breach-register.md — an unrelated consumer mapping, noted so a red there is not misread.

## Implementation Phases

### Phase 1 — Land the record verbatim

- `cp` the /tmp record to `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md`.
- `cmp` source vs. landed file (byte-identical — the verbatim AC).
- Conventions check: frontmatter block parses; `date:`/`signed_off_at:` = 2026-11-08; a
  secret-shaped-value scan (high-entropy base64url runs, Doppler-style tokens) returns nothing.
  A scan finding means STOP and flag — never scrub the CLO's text.

### Phase 2 — Extend `lint-legal-registers.sh` cited-paths extraction

- Rewrite the `cited_paths` awk block to emit every backtick-enclosed span in `$(NF-1)` per row.
- Add the zero-emission arm: a data row whose last cell yields no candidate fails with a named
  message (distinct from the unresolvable-path message).
- Replace the `resolved+broken == row_count` reconciliation with a `rows_emitting == row_count`
  reconciliation (fail-closed; emits the counts on mismatch).
- Extend `lint-legal-registers.test.sh` fixtures per the Guard Contract matrix below.
- **Prove the parser change in isolation:** run `bash scripts/lint-legal-registers.sh` GREEN on
  the register BEFORE the row edits, and `bash scripts/lint-legal-registers.test.sh` GREEN.

### Phase 3 — Register edits (all verified cell-by-cell before replacing)

- Re-grep the three cells' current text; any drift → STOP and flag (CLO Sharp Edge).
- (a) event cell: replace `Containment and rotation are owner-gated and not yet done` with the
  CLO's containment/rotation sentence (verbatim per brief deliverable 2a).
- (b) open-limbs cell: replace the whole cell with the CLO's new four-limb text (verbatim per 2b).
- (c) canonical-source cell: append `` `; 2026-11-08 re-assessment: ` `` followed by the record
  path in backticks (`` `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` ``).
- (d) append `## Corrections — 2026-11-08 (#11294 re-assessment)` at file end: one
  `> **Superseded 2026-11-08 (#11294) — applied in-cell:**` blockquote per superseded clause
  (the event-cell sentence and the whole prior open-limbs cell, quoted verbatim), then a
  `**Determination unchanged.**` line recording SECURITY INCIDENT/PROVISIONAL stands and the
  Art. 33 / Art. 34 cells stay `No`.
- `related:` frontmatter: append
  `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` after the
  2026-10-31 entry (inferred — convention of commit `45df1eef3f`).
- Run `bash scripts/lint-legal-registers.sh` GREEN (produced=43; both cited paths resolve and are
  indexed) and `bash scripts/lint-legal-registers.test.sh` GREEN.

### Phase 4 — Commit, PR, post-merge runbook

- Commit `docs(legal): land the 2026-11-08 CLO re-assessment record for #11294 (Ref #11294, Ref
  #11711, Ref #9927, Ref #11922)` — `Ref` only, never `Closes`/`Fixes`/`Resolves`.
- PR #12387 body: summary, `Ref` lines, the post-merge comment runbook verbatim (below).
- **Post-merge step (recorded here, executed after merge):** post the brief's verbatim comment on
  #11294 via `gh issue comment 11294 --body "<verbatim text>"`. The verbatim text lives in the
  brief and in tasks.md; it is not paraphrased.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Extend the lint parser to multi-source canonical cells (assumed default) | Chosen — preserves the CLO-prescribed cell text verbatim and keeps every produced file honestly indexed; the parser change is mechanical and tested first on the unmodified register |
| `NOT_TRANSCRIBED` waiver + `§Excluded records` row for the record | Rejected — citing the record as a canonical source while waiving it is exactly the indexed/waived contradiction assertion (c) exists to forbid; and a re-assessment of an indexed determination is not an exclusion |
| Keep the canonical cell single-path; cite the record in prose elsewhere | Rejected — deviates from the CLO's explicit prescription (canonical-source cell append); the "canonical source" column is where a regulator looks |
| New index row for the re-assessment | Rejected — the index is of determinations; a "determination STANDS" re-assessment is not a new determination, and the corrections convention is the designed vehicle |
| Land register edits without the lint change | Rejected — blocking lint red; the PR cannot merge |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the blast radius is an
  Art. 33(5) register row that misstates the controller's own breach posture to a supervisory
  authority, an evidentiary/integrity defect, not a user-visible one.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure vector —
  the change publishes counts, dates and record text about an incident already indexed publicly;
  the secrets-scan AC exists so no value-shaped string can ride along.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** Tier-1 internal record landing (docs + a lint parser
  fix); no user-facing artifact, no personal-data processing introduced — the record documents a
  past incident at counts-only granularity.

## Observability

The only non-docs file in the diff is `scripts/lint-legal-registers.sh` — a blocking CI guard,
whose own pass/fail output IS its observability surface. There is no daemon or endpoint to
probe; the smallest command that prints its health signal is the lint itself.

```yaml
liveness_signal:
  what:            "lint-legal-registers exits 0 with 'all assertions passed' (blocking suite, scripts/test-all.sh:6158)"
  cadence:         "every PR + merge CI run and local `test-all.sh` affected run"
  alert_target:    "red required check on the PR; ::error:: annotations in the job log"
  configured_in:   "scripts/test-all.sh:6158"

error_reporting:
  destination:     "CI job log / local stdout"
  fail_loud:       "::error::lint-legal-registers … lines plus a non-zero exit (1 = assertion failed, 2 = cannot decide)"

failure_modes:
  - mode:          "a canonical-source cell's cited path no longer resolves (composite cell parses as one string)"
    detection:     "assertion (b) 'breach-register cites a canonical source that does not resolve' / 'not TRACKED'"
    alert_route:   "CI red — lint-legal-registers-live suite"
  - mode:          "a determination-shaped audits/ file lands neither indexed nor waived"
    detection:     "assertion (c) 'determination-shaped file is neither indexed nor waived'"
    alert_route:   "CI red — lint-legal-registers-live suite"
  - mode:          "a row emits zero parseable citations and slips past a weakened parser"
    detection:     "row-emission reconciliation (rows_emitting vs delegated row count)"
    alert_route:   "CI red — lint-legal-registers-live suite"

logs:
  where:           "GitHub Actions job log; local stdout"
  retention:       "Actions run retention (90d)"

discoverability_test:
  command:         "bash scripts/lint-legal-registers.sh"
  expected_output: "all assertions passed"
```

## Encryption Posture

Skipped — the diff creates no `.tf`, `.sql`, `cloud-init.*` or `docker-compose.*` file and opens
nothing new between components (the lint parser edit stays inside one local script).

## Task Design

Skipped — no new autonomous-task surface (Phase 2.9.3 detection table: none matched).

## Architecture Decision (ADR/C4)

Skipped — the lint change is parser mechanics on an existing guard, not an
ownership/tenancy/trust-boundary move; ADR-200's register contract is preserved (every canonical
source still resolves and stays tracked). A competent engineer reading the ADRs learns nothing
new about system boundaries from this diff.

## Guard Contract

The deliverable modifies a guard (`scripts/lint-legal-registers.sh` cited-paths producer) — the
contract below is written against the DESIGN, before the guard edit.

### Guard 1 — multi-source canonical-source cell parsing

**Property.** Every repo-relative path a canonical-source cell cites is individually validated
(resolves, tracked, contained, non-symlink) and individually visible to assertion (c)'s
line-exact indexing join; a row citing zero parseable paths is a failure, never a skip.

**Assembly.** The single chokepoint is the `cited_paths` awk producer
(`scripts/lint-legal-registers.sh:263-303`) feeding the per-line resolution loop, the
`OUT_OF_SCOPE_ROW` literal check, and (c)'s `grep -qxF` joins — every index-row last cell flows
through it; consumers downstream of `cited_paths` are unchanged members.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Register fixture: a canonical cell carries two backticked paths where the second names a nonexistent file — composite path must surface individually | RED: (b) "does not resolve"/"not TRACKED" on the second path |
| 2 | Producer emits only the first backticked span (revert to single-path extraction) while the fixture cites two files, the second being a produced determination-shaped audits/ file | RED: (c) "neither indexed nor waived" — the second-member defect the composite cell creates |
| 3 | A data row's last cell contains prose with no backticked span (zero-emission row) | RED: row-emission reconciliation reports rows emitting < row_count, not a vacuous pass |
| 4 | Suite harness: the composite-cell fixture asserts rc≠0 only — a wrong-assertion red elsewhere would satisfy it | Harness row: fixture asserts the SPECIFIC `(b)`/`(c)` message text, so a red for another reason cannot green the case |
| 5 | Must-PASS non-canonical input: composite cell where BOTH paths resolve and both match produced files | GREEN: `lint-legal-registers.sh` exits 0 — certifies the guard is not reject-everything |

**Anchor.** The register and the guard sit in the same commit: a weakening that edits both the
producer and a register cell in one diff would pass. What must move OUTSIDE this diff for a
weakening to pass is the fixture set in `lint-legal-registers.test.sh` (committed tests asserting
the per-path semantics) plus this plan's AC requiring GREEN on the unmodified register — the
merge-base register rows are the independently-fixed reference.

## Domain Review

**Domains relevant:** Legal (the register is a Legal artifact; the CLO agent already performed
the substantive legal assessment — the pipeline lands its output, it does not re-litigate it).

**Domains not relevant:** Product/UX (no UI-surface file in Files to Create/Edit — mechanical
override does not fire → NONE), Engineering (a `scripts/` lint parser edit; no agent spawn
possible in this context — covered by the Guard Contract + unit fixtures), all others.

## Open Code-Review Overlap

None — 94 open `code-review`-labeled issues queried; zero bodies name any planned path.

## Files to Create

- `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` — verbatim `cp` of `/tmp/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` (byte-identical; `cmp` is the AC)
- `knowledge-base/project/specs/feat-one-shot-11294-clo-reassessment/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-11294-clo-reassessment/decision-challenges.md`

## Files to Edit

- `knowledge-base/legal/breach-register.md` — `related:` frontmatter line; event cell, open-limbs cell, canonical-source cell of the 2026-10-29 row (line ~143); `## Corrections — 2026-11-08 (#11294 re-assessment)` appended at file end
- `scripts/lint-legal-registers.sh` — cited-paths awk producer emits per-backtick-span lines + zero-emission arm + row-emission reconciliation
- `scripts/lint-legal-registers.test.sh` — composite-cell fixtures (both-resolve GREEN, second-unresolvable RED, zero-span RED, single-vs-composite mixed rows)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Copy /tmp/2026-11-08-clo-reassessment-11294-rotation-incomplete.md VERBATIM to knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md" | Phase 1; Files to Create #1; AC-1/AC-2 | mapped |
| 2 | "Event cell: replace `Containment and rotation are owner-gated and not yet done` with: `Containment executed 2026-10-31/11-01 …`" | Phase 3(a); Files to Edit #1 | mapped |
| 3 | "Open-limbs cell: replace the whole cell (`**Yes — all four, none closed.** … not yet contained`) with: `**Yes — all four, none certified clean.** …`" | Phase 3(b); Files to Edit #1 | mapped |
| 4 | "Canonical-source cell: append ; 2026-11-08 re-assessment: knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md" | Phase 3(c) + Phase 2 (the lint change the append forces); Files to Edit #1, #2, #3 | mapped |
| 5 | "Append at file end a `## Corrections — 2026-11-08 (#11294 re-assessment)` section: for each superseded clause a `> **Superseded 2026-11-08 (#11294) — applied in-cell:**` marker … then a `**Determination unchanged.**` line" | Phase 3(d); Files to Edit #1 | mapped |
| 6 | "AFTER the PR merges (post-merge step, runbook entry): post this comment verbatim on #11294: …" | Phase 4 post-merge runbook; AC-9 (tracking AC — comment lands post-merge) | mapped |
| 7 | "Ref/Tracks keywords only — never Closes/Fixes/Resolves for any issue" | Phase 4; AC-7 | mapped |
| 8 | "If a register cell's current text differs from the quoted superseded text, STOP and flag it rather than editing blind" | Phase 3 cell re-grep gate; AC-3 | mapped |
| 9 | "Open draft PR #8626 also touches breach-register.md — check for a text-level conflict before committing" | Premise Validation finding (done: no conflict — hunk at ~line 128 vs our line 143 + EOF) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Record file copy | "Copy … VERBATIM to knowledge-base/legal/audits/…" | asked |
| Register cell edits (a)–(c) | "Apply: a. Event cell: replace … b. Open-limbs cell: replace … c. Canonical-source cell: append …" | asked |
| Corrections section | "Append at file end a `## Corrections — 2026-11-08 (#11294 re-assessment)` section …" | asked |
| Post-merge comment | "AFTER the PR merges … post this comment verbatim on #11294" | asked |
| `lint-legal-registers.sh` parser change + test fixtures | — | inferred — justification: the prescribed canonical-cell append is unparseable by the guard's single-path `trim($(NF-1))` extraction; without this change the blocking lint fails on (b) and (c) and the deliverables cannot merge. Minimal in-scope repair, recorded `pending - assumed:` in decision-challenges.md |
| `related:` frontmatter append | — | inferred — justification: convention measured at commit 45df1eef3f — every index-cited audits/ record lands in `related:`; omitting it leaves the frontmatter list stale relative to the row it indexes |
| tasks.md / decision-challenges.md | — | inferred — justification: soleur pipeline artifacts (Save Tasks + ADR-084 headless ruling channel) |

### Split Assessment

- Subsystems touched: 2 — `knowledge-base` (legal records) + `scripts` (one lint + its test)
- Planned files: 5 | Estimated changed lines: ~140 (record ~369 lines verbatim + ~30 register + ~25 lint + ~50 test)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the record and the parser change are one logical landing (the lint
  red without it); splitting would put a knowingly-red register edit in one PR and its enabler in
  another.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1: `knowledge-base/legal/audits/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` exists and `cmp` against `/tmp/2026-11-08-clo-reassessment-11294-rotation-incomplete.md` reports byte-identical
- [ ] AC-2: the landed record's frontmatter parses (`type: clo-attestation`, `date: 2026-11-08`) and a secret-shaped-value scan finds nothing beyond counts/dates/ids
- [ ] AC-3: all three pre-edit cell greps match the brief's quoted superseded text byte-for-byte before any edit (drift → documented STOP, no blind edit)
- [ ] AC-4: `bash scripts/lint-legal-registers.sh` exits 0 on the register BEFORE the row edits (parser change proven in isolation) and exits 0 AFTER them
- [ ] AC-5: post-edit, the register index parses to 15 rows; the composite canonical cell emits BOTH cited paths, each `git ls-files --error-unmatch`-clean; `produced` includes the new record and it is index-cited (no waiver needed)
- [ ] AC-6: `bash scripts/lint-legal-registers.test.sh` exits 0 with the new composite-cell fixtures added (both-resolve GREEN, second-unresolvable RED, zero-span RED, mixed-row)
- [ ] AC-7: `## Corrections — 2026-11-08 (#11294 re-assessment)` exists at file end with a `> **Superseded 2026-11-08 (#11294) — applied in-cell:**` blockquote per superseded clause quoting the prior text verbatim, and a `**Determination unchanged.**` line; commit message and PR body use `Ref` only — `git log -1` and the PR body contain no `Closes|Fixes|Resolves` for #11294/#11711/#9927/#11922
- [ ] AC-8: `related:` frontmatter lists the new record path
- [ ] AC-9: the plan and tasks.md carry the verbatim post-merge comment for #11294 as a recorded post-merge step (execution happens after merge; the AC is that the step is recorded verbatim, not that the comment exists pre-merge)
- [ ] AC-10: no `docs/legal/` path is touched (`git diff --name-only origin/main...HEAD | grep -c '^docs/legal/'` = 0 — Tier-1, mirror/SHA/heading gates not engaged)

### Post-merge (operator)

- [ ] AC-11: the verbatim comment is posted on #11294 via `gh issue comment 11294 --body "<verbatim text>"`; #11294 remains open after it lands. Automation: not feasible at plan-merge time — the step is explicitly conditioned on the merge event itself; the `gh` CLI is the mechanism and the verbatim text is already prepared in tasks.md §5.

## Domain Review placement note

`## Domain Review` is placed here per the heading contract (after Acceptance Criteria would put
it mid-file; keeping it adjacent to Scope Check preserves the template order — see §Domain
Review above).

## Test Scenarios

- **Unit (lint fixtures):** Given a register fixture whose canonical cell carries two resolving
  backticked paths, when `lint-legal-registers.sh` runs, then it exits 0 and (b) reports both
  resolved — `unit`.
- **Unit (lint fixtures):** Given the second cited path is absent, when the lint runs, then (b)
  fails naming that path — `unit`.
- **Unit (lint fixtures):** Given a canonical cell with no backticked span, when the lint runs,
  then the row-emission reconciliation fails — `unit`.
- **Unit (lint fixtures):** Given a produced determination-shaped audits/ file cited only as the
  SECOND span of a composite cell, when the lint runs, then (c) counts it indexed — `unit`.
- **Integration:** `bash scripts/lint-legal-registers.sh` on the real tree exits 0 pre- and
  post-edit; `bash scripts/lint-legal-registers.test.sh` exits 0 — `integration`.
- **Integration (negative):** `git diff --name-only origin/main...HEAD | grep -E 'Closes|Fixes|Resolves'` on commit message/PR body returns nothing for the four cited issues — `integration`.

## Success Metrics

- Record on `main` at its canonical path, byte-identical to the CLO's file.
- Register row carries the reassessed state; superseded text preserved in the Corrections section.
- `lint-legal-registers` green in CI; no waiver added; produced count 43 all indexed-or-waived.
- #11294 comment posted verbatim post-merge; all four cited issues remain open.

## Dependencies & Risks

- **Lint design risk (managed):** the per-span producer must not emit non-path backticked spans
  as candidates silently — the plan pins "every emitted candidate runs the existing resolution
  gauntlet" so a junk span reds rather than skips. If a future cell needs backticked non-path
  text, the resolution fails closed and a fix is forced — acceptable and documented.
- **Concurrent register writers:** PR #8626 touches a different row (~line 128); if it merges
  first, rebase and re-verify the three target cells (drift → STOP per AC-3).
- **Post-merge step rot:** the verbatim comment is duplicated into tasks.md so merge-time
  execution needs no pipeline context.
- **Subagent context limits:** no Task/Agent tool — domain leaders, SpecFlow and research agents
  were substituted with inline checks; the technical ruling on the lint fork is recorded
  `pending - assumed:` in `decision-challenges.md` for the ship-time render.

## References & Research

- Register row: `knowledge-base/legal/breach-register.md:143` (2026-10-29 #11294 row)
- Corrections precedent: `knowledge-base/legal/breach-register.md` `## Corrections — 2026-09-14`
  (in-cell) and `## Corrections — 2026-09-08` (marker shape)
- Lint producer: `scripts/lint-legal-registers.sh:263-303` (extraction), `:386-443` (producer +
  disjointness), test suite `scripts/lint-legal-registers.test.sh`
- Convention precedent: commit `45df1eef3f` (2026-10-29 determination landing: record + row +
  `related:` line); record landing pattern commits `0c064ead`, `3fd8ba5e`, `824725160`
- Record source: `/tmp/2026-11-08-clo-reassessment-11294-rotation-incomplete.md`
- Issues: Ref #11294, Ref #11711, Ref #9927, Ref #11922 | PRs: #12387 (this pipeline), #8626
  (conflict-checked), #11502 (determination-landing precedent)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6 — filled above.
- The three cell greps MUST run in the work phase immediately before each edit, not reused from
  this plan session (PR #8626 or a sibling could land between plan and work).
- The lint parser change touches a legal-integrity guard: land it proven-GREEN on the unmodified
  register before the composite cell exists (AC-4), so a bisect can separate parser defect from
  register content.
- The verbatim-copy AC uses `cmp`, not "looks right" — any diff is a defect, not a summary task.
- `produced=43` after landing: if the lint's produced count does not rise by exactly 1, the
  record did not match `DETERMINATION_PATTERN` and something else is being counted — investigate,
  do not adjust.
