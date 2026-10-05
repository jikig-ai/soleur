---
title: "fix: the AP-021 gate is a three-factor conjunction and its motivating message escaped all three"
date: 2026-08-19
slug: fix-ap021-gate-operator-line-and-claim-blind-spots
branch: feat-one-shot-7578-ap021-claim-blind-spot
issue: 7578
closes: [7578, 7318]
lane: cross-domain
type: fix
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

`scripts/lint-diagnosis-claims.sh` enforces AP-021 (ADR-166): *an operator-facing CI message
may only name a cause the job measured.* It flags a line only when **both** filters match:

```python
if not OPERATOR_LINE.search(line) or not CLAIM.search(line):
    continue
```

…and only when a third predicate, `MEASURED`, finds no evidence in a 16-line window.

A message that ran every 30 minutes for two days naming two causes the run had measured
**false** was never counted — and it was invisible to **all three** predicates, not the two
the issue names. This plan closes the gap by widening the two filters, narrowing the
exoneration for the newly-detected claim form, triaging the newly-visible lines, and holding
the ratchet at its current value rather than baselining the new hits.

`lane:` is recorded `cross-domain` per the fail-closed default — this branch has no `spec.md`
to carry a value forward from. The inline domain sweep (§Domain Review) found only
engineering relevant.

## Research Insights

### Premise Validation

Four premises were checked before any research was dispatched.

1. **The motivating instance is already fixed.** `scripts/zot-restart-loop-alarm.sh` no longer
   contains the `Better Stack unreachable / creds unset` DETAIL string; the merged
   observability work replaced it with measured wording and its in-file comment records
   *"Both are fixed here; the baseline ratchets to 0."* **The remaining work is the gate, not
   the instance** — which is what #7578 says it is about.
2. **The issue's title and body give different diagnoses.** Settled empirically below. Both
   are true, both are incomplete, and — the finding that reshapes this plan — **fixing both is
   still not sufficient.** A third predicate, which ADR-192 recorded and the issue dropped,
   exonerates the line regardless.
3. **`AP-021` is not a Linear issue reference.** It is an internal principle ID
   (`knowledge-base/engineering/architecture/principles-register.md`,
   `apps/web-platform/infra/infra-config-gate.sh`). The `[A-Z]{2,}-[0-9]+` preflight regex
   matches it as a false positive; no Linear fetch was spent.
4. **The collision probes clear.** The body-text probe surfaced one merged PR; its diff does
   not touch `scripts/lint-diagnosis-claims.sh`, and the issue names that file — empty
   intersection against a non-empty path set, so the link is a citation.

### The diagnosis, settled by measurement

The two historical offender lines, recovered from the commit that fixed them:

```
scripts/zot-restart-loop-alarm.sh:389   VERDICT="TRANSIENT"; DETAIL="recent ${WINDOW} empty AND control-marker query empty/errored (rc=${control_rc}) — Better Stack unreachable / creds unset"
scripts/zot-restart-loop-alarm.sh:186   NIC_DETAIL="recent ${WINDOW} empty for SOLEUR_PRIVATE_NIC AND the control-marker query is empty/errored (rc=${control_rc}) — Better Stack unreachable / creds unset"
```

Run against the live scanner, **all three predicates independently let both lines through**:

| Filter | Blocks the line? | Why |
|---|---|---|
| `OPERATOR_LINE` | **Yes (rejects)** | Its helper-call alternative is `^\s*[a-z_][a-z0-9_]*(\s+\S+)*\s+"` — it requires **whitespace immediately before the quote**. A shell assignment has `=` there. The uppercase shell-var convention is a second, independent barrier (`^\s*[a-z_]`). Measured: `NIC_DETAIL="x"` → False, `detail="x"` → False, `detail = "x"` → True. |
| `CLAIM` | **Yes (rejects)** | Its phrase list does not model the em-dash appendix `— <cause> / <cause>`. |
| `MEASURED` | **Yes (exonerates)** | Even with both filters above widened, the line is cleared: `VERDICT="TRANSIENT"` on line 389 matches `verdict=` (the regex is case-insensitive), and `NIC_VERDICT` in line 186's 16-line window matches `_VERDICT\b`. |

So there are **three** independent defects on the same line, not two — and the third is the
deepest. `MEASURED` tests for the *presence of a verdict-ish token near the message*, not for
the named cause having been measured. That is this repo's own `cq-assert-anchor-not-bare-token`
anti-pattern applied to the exoneration side, and it is exactly backwards for this incident:
the alarm's entire defect was that its measurement (`rc=0`) **contradicted** the causes the
appendix named, yet the presence of that very measurement is what cleared the line.

**This was already known and correctly recorded — in ADR-192, whose §Context carries the
identical three-row table, `MEASURED | True | would exempt the line anyway (VERDICT= matches)`
included.** The measurement above reproduces that finding independently; it does not discover
it. What went wrong is the restatement: **#7578's title carries only the `OPERATOR_LINE` row
and its body only the `CLAIM` row**, and neither carries the third. The prescribed fix follows
correctly from that partial reading and is inert.

That is the reusable lesson here, and it is worth more than the regex change: a follow-up
issue is a *lossy copy* of the analysis that produced it, and the factor it drops is invisible
precisely because the remaining factors still explain the symptom. The cheap gate is to read
the ADR the issue came from before planning against the issue — which is what
`plan` Phase 0.6 §4 already mandates, and what would have caught this before any measurement.

The issue body also cites **ADR-187 §Scope** as recording this deferral. That is a
mis-citation: ADR-187 has no §Scope section and never mentions this gate. The deferral is
recorded in **ADR-192**, which is where the closing note belongs.

### The measurement that reshapes the fix

Candidate configurations, scanned over the gate's real `DIRS` with its real evidence window
and `MEASURED` filter (the harness mirrors the scanner loop exactly; config A reproduces the
live gate's `1`, which is the harness's own fidelity check). The last column is measured by
running each config over the **pre-fix tree**, reconstructed from the commit that fixed the
alarm — not by reasoning about the regexes:

| Config | Widening | Hits (live) | Δ | Catches the historical offenders? |
|---|---|---|---|---|
| A | baseline (live gate) | 1 | — | **No** |
| B | `CLAIM` only — *the issue body's prescribed fix* | 18 | +17 | **No** |
| C | `OPERATOR_LINE` only — *the issue title's diagnosis* | 2 | +1 | **No** |
| D | both, broad predicate | 19 | +18 | **No** — `MEASURED` exonerates |
| E | both, **static-prose** predicate | 10 | +9 | **No** — `MEASURED` exonerates |
| F | E + #7318 continuation-line form | 11 | +10 | **No** — `MEASURED` exonerates |
| **G** | **F + appendix-class strict exoneration** | **12** | **+11** | **Yes — both lines** |

Four conclusions follow, and each contradicts something the issue assumes:

1. **No two-filter fix works.** Every configuration that widens only `OPERATOR_LINE` and
   `CLAIM` — including the strongest one — still misses both historical lines, because
   `MEASURED` clears them. Only config G, which narrows the exoneration for appendix-named
   causes, catches them. This is the plan's central finding; ADR-192 has it, the issue does not.
2. **The issue's own "Suggested shape" would not have fixed the bug it was filed for.**
   Config B is measured `False` against both historical lines.
3. **The issue's "30 hits" cost estimate priced only one third of the change.** It was taken
   with `OPERATOR_LINE` and `MEASURED` both unchanged.
4. **Tightening the predicate to static prose halves the triage cost at no loss of the target.**
   Requiring the appendix to contain no `$` (`[—–][^"$]{0,60}?\b(?:<predicate>)\b`) drops
   D→E (19→10). The dominant false-positive shape is an appendix that *interpolates the
   measured value it is explaining* (`http=$code — … (zot unreachable)`); the offender's
   appendix was static prose that the interpolated `rc=0` contradicted.

### The third widening, stated precisely

For a line whose `CLAIM` match came **only** from the new appendix alternative, the inferred
`MEASURED` token set no longer exonerates — only an explicit `# MEASURED-BY:` marker does.
Lines matching `CLAIM`'s pre-existing phrase list keep the current exoneration semantics
unchanged, so this narrows nothing that is green today for a reason unrelated to the appendix.

The justification is the AP-021 principle itself: a verdict variable in the neighbourhood
establishes that *the job measured something*, which is not the claim under test. The claim
under test is that **the cause this appendix names** was measured. For the phrase-list forms
the neighbourhood heuristic has held; for a static-prose appendix it demonstrably has not,
and the deliberate marker is the right evidence standard because a human had to write it.

### Fold-in: #7318

`#7318` (OPEN) is *the same regex, the same class* — `OPERATOR_LINE`'s helper-call alternative
is `^`-anchored, so a continuation-line call (`|| degraded sign "$?" "…"`) is invisible. The
gate's own source comment already documents the one live instance and its `+1` cost.

Measured: folding it in is E→F, **+1 hit**. Kept separate, it costs a second triage pass and a
second highwater negotiation over the same file. **Disposition: fold in, `Closes #7318`.**

### The ratchet decision — and why it diverges from the issue

The issue's §3 prescribes *"Set the highwater to the newly measured value."* The highwater
file argues against precisely this, in its own words, about an earlier `CLAIM` broadening:

> Baselining those would have parked two false positives in the ratchet forever, so that the
> count could never reach zero and every future reader would assume two real offenders
> remained.

That objection applies with 5× the force here (10 new hits, not 2). Triage of all 10 shows
**none is an unmeasured causal claim** — every one either interpolates a value the job
measured, hedges (`may be`), or states an explicit disjunction of possibilities. The correct
disposition is therefore `MEASURED-BY:` annotation (or rewording), **holding the highwater at
its current `1`** — not raising it to 11.

This preserves the property the ratchet exists to have: a non-zero count means a real
offender. The `SCOPE change` carve-out is *available* but is not needed and should not be used.

### Institutional learnings applied

- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — the
  mutation matrix must include a row targeting the guard's **own dispatch**, and a must-PASS
  row that is not the canonical fixture. Encoded in §Guard Contract.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` —
  the deliverable is a guard, so Test Scenarios must be shaped `mutation M → guard reddens`,
  not `command X → terminal Y`.
- `2026-08-11-every-guard-i-wrote-contained-an-instance-of-the-class-it-guarded.md` — this
  plan widens a detector; the widening itself must not carry an instance of the blindness
  class. Hence the fixture requirement that both historical lines be asserted verbatim.

### Property List / Cut List (mechanism minimality)

**Properties the ask must buy:**

- P1. A message assembled into a shell variable is reachable by the gate.
- P2. A cause named in a dash appendix is recognised as a causal claim.
- P3. Both historical offender lines would have been flagged before they shipped.
- P4. The ratchet still means "a real offender exists" after the widening.

**Cut List:**

| Mechanism proposed | Property it buys | Disposition |
|---|---|---|
| Widen the 16-line evidence window | reduces FPs whose `MEASURED-BY` sits out of range | **Cut.** Measured: only 1 of 10 hits (`zot-restart-loop-alarm.sh:387`) is out-of-window, and an explicit `MEASURED-BY:` fixes it for free. Widening the window changes exoneration semantics repo-wide for one line. |
| Raise the highwater to the measured value | P4 | **Cut.** Inverts P4 — see the ratchet decision above. Annotation holds it at 1. |
| A new `DIRS` entry / scope widening | none in this ask | **Cut.** Not proposed by the issue; orthogonal. |

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "the alarm's message was never counted at all" (body) | True | Confirmed by measurement |
| "`CLAIM`'s fixed phrase list … the pattern does not model [the appendix]" (body) | True, **but not the only reason** | Widen `CLAIM`; also widen `OPERATOR_LINE` |
| "`OPERATOR_LINE` rejects it before `CLAIM` is consulted" (title) | True | Widen `OPERATOR_LINE` (assignment form) |
| "A bounded widening … measures **30 hits**" (body) | Measured 18 for that config here; 10 for the tightened one | Adopt the tightened predicate; record measured deltas |
| "reusing the existing `OPERATOR_LINE` and `MEASURED` filters" (body §Measured cost) | **Insufficient** — measured `False` against both offenders | Reject; both filters must widen |
| "Set the highwater to the newly measured value" (body §3) | Contradicted by the highwater file's own stated rationale | Hold at 1; annotate instead |

## User-Brand Impact

**If this lands broken, the user experiences:** either every PR blocked by a red required
check (the gate is BLOCKING and feeds the `test` job in the CI Required ruleset), or — the
worse arm — a gate that reads green while remaining blind, so the next operator-facing CI
message naming an unmeasured cause ships and routes the operator to the wrong repair. That is
the ADR-154 failure shape this rule family exists to prevent.

**If this leaks, the user's workflow is exposed via:** no new data surface. The gate reads
tracked repo files and emits path/line/message excerpts to CI logs, exactly as today.

**Brand-survival threshold:** single-user incident.

The operator is non-technical. A CI message that confidently names a false cause is acted on,
not audited — #7242's misdiagnosis blocked three production releases, and the motivating
message here ran every 30 minutes for two days asserting two causes its own `rc=0` refuted.
One such message reaching one operator is the incident.

## Guard Contract

### Guard 1 — AP-021 detector reachability (`OPERATOR_LINE`)

**Property.** Every operator-facing message string in a scanned file is reachable by the
`CLAIM` filter, regardless of the syntactic form that carries it to the operator — a direct
`echo`/`printf`, a helper call at start-of-line, a helper call on a shell continuation, or a
variable assignment later interpolated into an emitted line.

**Assembly.** The chokepoint is the per-line decision in the `census()` heredoc of
`scripts/lint-diagnosis-claims.sh` — every scanned line of every file under `DIRS` flows
through it, and it is the only site that decides whether a line is reported. That decision is
a conjunction of **three** independent predicates, and the assembly is their *product*, not
any one of them:

```
report(line)  ⟺  OPERATOR_LINE(line) ∧ CLAIM(line) ∧ ¬MEASURED(window(line))
```

A line escapes if **any single factor** misses it, which is why a two-factor analysis of this
bug read as complete and was not. The property quantifies over: (a) the set of **carrier
syntaxes** — direct emit, start-of-line helper call, continuation-line helper call, variable
assignment — enumerated from shell/YAML grammar rather than from what the regex contains
today; (b) the set of **claim forms**; and (c) the set of **evidence standards** that count as
exoneration. An alternative list is a snapshot the next carrier form invalidates while the
suite stays green; the factorisation above is structural and does not drift.

**Mutation matrix.**

| # | Mutation | Must go |
|---|---|---|
| 1 | Restore the verbatim `VERDICT="TRANSIENT"; DETAIL="… — Better Stack unreachable / creds unset"` line into a fixture | RED |
| 2 | Restore the verbatim `NIC_DETAIL="…"` sibling (second carrier, after a compliant first) | RED |
| 3 | Delete the assignment alternative from `OPERATOR_LINE`, leaving the other two widenings | RED (fixture 1 no longer reported → suite fails) |
| 4 | Delete the appendix alternative from `CLAIM`, leaving the other two widenings | RED (fixture 1 no longer reported → suite fails) |
| 5 | Revert the appendix-class exoneration to the inferred `MEASURED` token set, leaving both regex widenings | RED (fixture 1 no longer reported → suite fails) |
| 6 | Make the scanner's dispatch vacuous — point `DIRS` at an empty dir / force `scanned_files` to 0 | RED (a gate reporting "0 checked" and exiting 0 is the vacuity case) |
| 7 | Add a continuation-line carrier (`\|\| degraded sign "$?" "… is the fix"`) to a fixture | RED |

Rows 3, 4 and 5 are the load-bearing set: each reverts exactly one factor of the conjunction
while leaving the other two in place, so together they prove no factor is decorative. Row 5 is
the one that would not exist if the fixture had been written after the fix instead of before
it — the two-filter version of this plan passed rows 3 and 4 and still shipped a gate blind to
its own motivating bug.

**Harness rows.**

| # | Edit to the SUITE (not the guard) | Must go |
|---|---|---|
| H1 | Remove the RED fixture file but leave the assertion count unchanged | RED — a suite that passes with its fixture deleted asserts nothing |
| H2 | Replace the must-PASS fixture with a byte-copy of the RED fixture | RED |
| H3 | **Must-PASS, non-canonical:** a *measured* dash-appendix line carrying an explicit `# MEASURED-BY:` marker — differs from the canonical fixture in a way the contract explicitly permits | GREEN |
| H4 | **Must-PASS, non-canonical:** an appendix that interpolates its measured value (`http=$code — (zot unreachable)`) under the static-prose predicate | GREEN |

H3 and H4 are load-bearing: rows 1–6 are all RED-direction, and a guard that rejects
*everything* satisfies every one of them. Only a must-PASS row that is not the canonical
fixture can detect over-rejection — the precise defect the tightened predicate exists to avoid.

## Implementation Phases

### Phase 1 — Fixtures first (RED)

The gate ships a test seam (`LINT_DIAGNOSIS_ROOT`) precisely so the scanner can be driven over
fixtures. Write the failing suite before touching the regexes.

1. Add fixtures carrying both historical offender lines **verbatim** (recovered above), plus
   the continuation-line carrier for #7318.
2. Add the two must-PASS fixtures (H3, H4).
3. Extend `scripts/lint-diagnosis-claims.test.sh` with the matrix rows. Confirm rows 1, 2, 6
   are RED and H3, H4 are GREEN **before** any change to the scanner.

### Phase 2 — Widen `OPERATOR_LINE` (closes #7578 title-half + #7318)

Add two alternatives:

- variable assignment: `^\s*(?:local\s+|export\s+|readonly\s+)?[A-Za-z_][A-Za-z0-9_]*="`
- continuation-line helper call (un-anchor the existing alternative for `||`/`&&`/`;`/`|`)

Comment both with the measured yield (`+1` and `+1` respectively) in the file's established
style — every existing alternative there carries its measured cost.

### Phase 3 — Widen `CLAIM` (closes #7578 body-half)

Add the **static-prose** appendix alternative:

```
[—–][^"$]{0,60}?\b(?:unreachable|creds unset|credentials unset|token expired|
not installed|misconfigured|permission denied|quota exhausted)\b
```

Document why the `$`-exclusion and the 60-char bound are load-bearing (measured D→E, 19→10)
and why the predicate list is CLOSED — the same reasoning the file already records for
`CLAIM`'s adjective list.

### Phase 3b — Narrow the exoneration for the appendix class (the fix that actually works)

Track which `CLAIM` alternative matched. For a line matched **only** by the new appendix
alternative, require an explicit `# MEASURED-BY:` marker in the evidence window; the inferred
token set (`verdict=`, `_VERDICT`, `steps.*.outputs.*`, …) no longer exonerates it. Lines
matched by `CLAIM`'s pre-existing phrase list are unaffected.

Comment this with the measurement that motivates it: both historical offenders pass
`OPERATOR_LINE` and `CLAIM` under the widening and were cleared by `VERDICT=` / `_VERDICT` —
so without this phase the whole change is inert against the bug it was filed for.

### Phase 4 — Triage the 11 newly-visible lines

Each gets `# MEASURED-BY: <what measured it>` or a reworded message. None is an unmeasured
causal claim; the annotation records *which* measurement exonerates it.

| File:line | Shape | Disposition |
|---|---|---|
| `.github/workflows/reusable-release.yml:1378` | `$?` measured, `is the fix` phrasing (#7318 line) | `MEASURED-BY: $?` |
| `apps/web-platform/infra/ci-deploy.sh:1673` | `http=$code` measured | `MEASURED-BY: $code` |
| `apps/web-platform/infra/ci-deploy.sh:2565` | non-acceptance measured; appendix is a disjunction | `MEASURED-BY:` |
| `apps/web-platform/infra/ci-deploy.sh:2614` | as above | `MEASURED-BY:` |
| `apps/web-platform/infra/git-data-bootstrap.sh:265` | names a *consequence*, not a cause | reword |
| `apps/web-platform/infra/inngest-bootstrap.sh:984` | deliberate diagnostic-boot log | `MEASURED-BY:` |
| `scripts/followthroughs/hostname-mislabel-web1-6616.sh:102` | `exit $bq_rc` measured; explicit 4-way disjunction | `MEASURED-BY:` + rationale |
| `scripts/sync-readme-counts.sh:50` | count measured; hedged `may be` | `MEASURED-BY:` |
| `scripts/sync-readme-counts.sh:52` | as above | `MEASURED-BY:` |
| `scripts/zot-restart-loop-alarm.sh:309` | `NIC_CAUSE` H1 arm; `imds_rc=${rc}` measured | `MEASURED-BY: imds_rc` |
| `scripts/zot-restart-loop-alarm.sh:387` | `NIC_CAUSE` attach arm; measured, formerly cleared by a bare `NIC_VERDICT` | `MEASURED-BY:` (do **not** widen the window) |

The last two are the appendix class in the very file the incident came from — they are
measured and will carry markers, but they are now *asserted* to be measured rather than
inferred to be, which is the point of Phase 3b.

`scripts/followthroughs/zot-soak-6122.sh:319` is the pre-existing baselined `1` and is **not**
touched — it is an unrelated subsystem and is what the highwater is for.

### Phase 5 — Hold the ratchet, record the provenance

Leave `scripts/lint-diagnosis-claims.highwater` at `1`. Extend its comment with the widening
and the measured deltas (A→F, and each alternative's individual yield), and state explicitly
that the `SCOPE change` carve-out was **available and deliberately not used**, with the reason
— so the next author does not read the unchanged number as "nothing widened."

### Phase 6 — ADR-166 amendment

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-166**, do not create a new one. The decision (*a CI message may only name a cause
the job measured*) is unchanged; what changes is its **enforcement reach**, and ADR-166 is the
document that records how AP-021 is enforced. Add to its `## Decision`:

- The detector is a **three-factor conjunction** — carrier ∧ claim ∧ ¬exoneration — so a blind
  spot in *any one* factor makes the whole class invisible. Diagnosing a miss requires testing
  all three; this incident's two-factor diagnosis was correct as far as it went and still
  produced an inert fix.
- The carrier filter enumerates carrier *syntaxes*, not an accumulated alternative list.
- **Proximity is not evidence.** For a cause named as free prose, a verdict variable in the
  neighbourhood shows the job measured *something*, not that it measured *this*. Where the two
  can diverge, exoneration requires the deliberate `MEASURED-BY:` marker.

Add to `## Alternatives Considered`: widening `CLAIM` alone (the originally-suggested shape),
and widening both regexes without touching the exoneration — with the measurement showing that
neither catches the motivating line.

Close the deferral in **ADR-192** (§"deliberately not in this change"), which is where it is
actually recorded — **not** ADR-187, which the issue cites but which has no §Scope section and
never mentions this gate. The closing note records that all three filters moved together, that
the two-filter fix is measured inert, and that the "30 hits" figure priced one factor of three.

### C4 views

**No C4 impact.** Checked against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) for the four
required categories: (a) **external human actors** — none added or changed; the only actor is
the existing operator, whose relationship to CI is unchanged. (b) **external systems/vendors** —
none; the gate reads tracked files in the repo and calls no service (Better Stack appears only
as *subject matter inside the scanned message strings*, not as a dependency of this change).
(c) **containers/data stores** — none; no new store, no new persisted artifact beyond the
existing `.highwater` file, which is unchanged in this plan. (d) **access relationships** —
unchanged; the gate runs in the existing CI container with the same read-only repo access.
A lint's detection regex is below the granularity any C4 view models.

### Sequencing

None — the amendment is true on merge.

## Observability

**Skipped — detection does not fire.** Files-to-Edit touch `scripts/` (repo root),
`.github/workflows/`, and `apps/web-platform/infra/` message strings only. The §2.9 trigger set
is `apps/*/server/`, `apps/*/src/`, `apps/*/infra/` **code**, `plugins/*/scripts/`, or new
infrastructure. This plan introduces no new runtime surface, no new failure mode, and no new
error path: the gate's sole output channel is its CI job's stdout plus its exit code, both of
which already exist and are already surfaced by the required `test` check. Recorded explicitly
rather than silently so the skip is reviewable.

## Encryption Posture

**Skipped.** No persistent store and no cross-component connection is introduced.

## Files to Edit

- `scripts/lint-diagnosis-claims.sh` — widen `OPERATOR_LINE` (×2 alternatives), widen `CLAIM`
  (×1), and narrow the exoneration for the appendix class (Phase 3b)
- `scripts/lint-diagnosis-claims.test.sh` — mutation matrix rows 1–6 + harness rows H1–H4
- `scripts/lint-diagnosis-claims.highwater` — provenance comment only; the number stays `1`
- `.github/workflows/reusable-release.yml` — `MEASURED-BY:` annotation
- `apps/web-platform/infra/ci-deploy.sh` — 3 annotations
- `apps/web-platform/infra/git-data-bootstrap.sh` — reword
- `apps/web-platform/infra/inngest-bootstrap.sh` — annotation
- `scripts/followthroughs/hostname-mislabel-web1-6616.sh` — annotation
- `scripts/sync-readme-counts.sh` — 2 annotations
- `scripts/zot-restart-loop-alarm.sh` — annotation
- `knowledge-base/engineering/architecture/decisions/ADR-166-*.md` — amend
- `knowledge-base/engineering/architecture/decisions/ADR-192-*.md` — close the recorded deferral

## Files to Create

- fixture files under the `LINT_DIAGNOSIS_ROOT` test-seam tree (paths follow the existing
  suite's fixture convention — read it at implementation time rather than guessing here)

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open`; no open issue body names any
path in Files to Edit.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (inline — see §Note on execution)
**Assessment:** The change is confined to a CI lint's detection regexes plus message-string
annotations. The one architecturally interesting decision — hold the ratchet vs. raise it — is
resolved in favour of holding, which preserves the gate's existing semantics rather than
weakening them. Risk concentrates in over-rejection (a too-broad predicate reddening a
blocking required check), which the H3/H4 must-PASS harness rows exist to bound.

No Product/UX surface: no file under `components/**`, `app/**/page.tsx`, or any UI-surface
glob. Product tier: **NONE**.

## Acceptance Criteria

### Pre-merge (PR)

1. Both historical offender lines, verbatim in fixtures **with their surrounding `VERDICT=` /
   `NIC_VERDICT` context**, are reported by the gate. The context is load-bearing: a fixture
   carrying the message string alone would pass under a two-filter fix and hide the defect.
2. Mutation matrix rows 1–7 each drive the suite RED when applied individually.
3. Harness rows H1, H2 drive the suite RED; H3, H4 stay GREEN.
4. `bash scripts/lint-diagnosis-claims.sh` exits 0 against the live tree with all Phase 4
   annotations applied.
5. `scripts/lint-diagnosis-claims.highwater` still reads `1`; its comment records the widening,
   the measured per-alternative deltas, and why the SCOPE carve-out was not used.
6. Reverting **any one** of the three factors — the `OPERATOR_LINE` assignment alternative,
   the `CLAIM` appendix alternative, or the Phase 3b exoneration narrowing — drives the suite
   RED. None is decorative.
7. `python3 scripts/lint-guard-contract.py` passes on this plan file.
8. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes over
   every changed doc — note the gate derives its own input set; run its own invocation, not a
   hand-enumerated path list.
9. ADR-166 carries the amendment; ADR-192's recorded deferral is closed (not ADR-187 — the issue mis-cites it).
10. The PR body uses `Closes #7578` and `Closes #7318`.

### Post-merge

None. No operator action, no deploy step, no external state change — the gate takes effect on
the next CI run.

## Test Scenarios

Every scenario is shaped *mutation → guard reddens*, not *command → terminal output*, because
the deliverable is a guard.

1. Fixture carrying `VERDICT="TRANSIENT"; DETAIL="… — Better Stack unreachable / creds unset"`
   — **including the `VERDICT=` context** → gate reports it.
2. Same, as `NIC_DETAIL=` after a compliant first assignment, with `NIC_VERDICT` in the window
   → gate reports it (second-member row **and** the exoneration row).
3. Continuation-line `|| degraded sign "$?" "… is the fix"` → gate reports it.
4. `OPERATOR_LINE` assignment alternative reverted → suite RED.
5. `CLAIM` appendix alternative reverted → suite RED.
6. Phase 3b exoneration narrowing reverted → suite RED.
7. `DIRS` pointed at an empty directory → suite RED (vacuity floor).
8. Measured dash-appendix line with `# MEASURED-BY:` → gate does **not** report (must-PASS).
9. Interpolating appendix `http=$code — (zot unreachable)` → gate does **not** report (must-PASS).
10. A phrase-list claim (`Most likely cause: …`) next to a `TOKEN_VERDICT` → gate does **not**
    report (must-PASS) — proves Phase 3b did not narrow the pre-existing class.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The predicate over-rejects and reds a blocking required check | H3/H4 must-PASS rows; the `$`-exclusion measured at 19→10; the predicate list is CLOSED |
| A future carrier syntax reopens the blind spot | The Assembly names carrier *syntaxes* structurally, and ADR-166's amendment records the AND-factor reasoning so the next author widens both factors |
| Annotating 10 lines with `MEASURED-BY:` becomes a suppression habit | Each annotation must name *what* measured it; Phase 4 records the specific variable per line, and one line is reworded rather than annotated |
| The unchanged `1` reads as "nothing happened" | Phase 5 requires the provenance comment to state the widening and the deliberate non-use of the carve-out |

## Note on execution

The domain sweep, research consolidation, and reviewer panel for this plan were run inline
rather than via spawned subagents, per a standing session constraint against delegating to
agents unrequested. The substance of each gate was executed; the delegation mechanism was not.
