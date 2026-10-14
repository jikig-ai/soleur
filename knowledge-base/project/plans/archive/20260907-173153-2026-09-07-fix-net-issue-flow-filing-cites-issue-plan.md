---
title: "fix: attribute a PR's filings by the PR's own body, not only by what the filing cites"
date: 2026-09-07
slug: fix-net-issue-flow-filing-cites-issue
branch: feat-one-shot-7759-net-issue-flow-filing-cites-issue
issue: 7759
closes: [7759]
lane: cross-domain
type: bug
priority: priority/p2-medium
domain: domain/engineering
brand_survival_threshold: aggregate pattern
---

> **Superseded 2026-09-07 (#7896 review):** the "0 of 33" measurement below is FALSE. It classified cited numbers issue-vs-PR by range membership, which cannot work because GitHub issues and PRs share one number space here. Re-measured on `.pull_request`: **21 of 66 cited numbers are PRs and 20 of the 33 issues cite at least one**, over 29 pairs (one being #7710 -> #7702, the case #7759 was filed about). The exemption was under-reached, not inert. Likewise the "16 filing sites / 11 emit no PR number" figure: re-measured as **19 files / 48 invocations**, 14 files with no PR reference. And the `Possible unattributed filings:` mechanism described below was REMOVED in review — it reported numbers it had itself counted. See ADR-155 amendment and ADR-206.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No `spec.md` exists for this
branch; the domain sweep in `## Domain Review` is the substantive assessment and it found no relevant
business domain.

## Overview

`net-issue-flow.sh` is a BLOCKING gate: a PR must close at least as many issues as it files. It learns
what a PR filed by matching the PR's number inside each issue body. A filing that names the
**originating issue** instead of the PR is never counted, `Filing:` reads low, and a net-positive PR
passes — carrying the authority of a blocking check that succeeded. It fails OPEN, the direction the
script's own header calls "strictly worse than the advisory surface it replaces."

This plan adds one disjunct to the gate's existing `jq` pass: an issue created after the PR whose
number the PR's own fence-stripped body names — and which is not one of the PR's close targets — is a
filing of that PR. The evidence is first-party and already in the corpus the gate reads, so the change
adds no API call, no new subprocess, and no new failure branch, and the `gh issue list` argv is
untouched.

`## Design Decision` records the choice and the two rejected alternatives; ADR-206 records them durably.

## Enhancement Summary

**Deepened on:** 2026-09-07. Six review agents plus independent measurement.

### Corrections this pass made to the plan's own first draft

1. **A fail-open defect in the plan's prescribed code, of the exact family being fixed.** The draft
   built the named set in bash: `grep -oE … | jq …` with `|| _fail_open`. Under the gate's
   `set -uo pipefail`, `grep` exits 1 on no match, so **every PR whose body names no issue would have
   exited 0 before `gh issue list` ran** — and an author-controlled unbalanced fence would have turned a
   documented fail-**closed** path into a fail-open. Measured, not reasoned. Would have been a sixth
   member of the always-pass family.
2. **The fix dissolved the machinery rather than patching it.** Deriving the set inside the existing
   `jq` pass from `$pb` removes the bash pipeline entirely and takes nine findings with it: both
   fail-open paths above, three new `_fail_open` branches, three new rule ids the `_fail_open` helper
   could not have emitted anyway, a `failure_modes` entry, a fence-stripper divergence, and a
   misleading "TRANSIENT — API outage" message on a pure local string parse.
3. **The title-matching arm is cut.** It had no measured instance, no mutation row, and was the only
   change touching the pinned query — and its "strictly monotone" safety argument was inverted:
   monotone-increasing `Filing:` is monotone-increasing *false BLOCKs*, the exact ground on which this
   plan rejects option 2.
4. **Keyword-anchoring was proposed and is rejected on evidence.** Anchoring the arm on
   `Files|Filed|Tracks|Refs|Follow-up #N` would be a stronger claim of the filing *relationship* — but
   PR #7702 introduces its three filings as bare list items (`- #7708 — extend the operand rule`), so
   keyword-anchoring returns `Filing: 0` on the exact case the issue was filed for.
5. **Four mutation/harness rows were false-green** and are corrected; an escape row (conjoining
   `state == "OPEN"`) that satisfied every original row while violating the property is now closed.
6. **ADR-205 → ADR-206.** 205 is claimed by an unmerged branch, invisible to a tree-scan.
7. **Counts restated against the gate's own predicate:** 33 whole-line `Mandated-By:` issues (not 37),
   0 citing any PR.
8. **The largest revision: counting bare `#N` from the PR body was measured over 300 PRs and rejected.**
   It attributes 9 issues to two different PRs each, and flips 25 PRs (8.3%) from PASS to BLOCK with an
   unmeasured false-positive share. P4 is a stated guard property and bare-`#N` counting makes it
   *measurably false*. The design now counts only a **declared** `Filed:` line and *reports* everything
   else — which is what issue option 3 actually asked for.
9. **The producer question was answered, not dodged.** The first draft claimed the arm "needs no
   producer to cooperate". `/ship` Phase 6 **full-replaces** the PR body and carries forward only two
   markers, so free prose is not a durable input. But that same carry-forward table is the mechanism
   the fix needs: option 1 is rejected at the sixteen filing sites and adopted at **one** — the `/ship`
   body template — where the producer and the gate ship in the same skill.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited artifact | Check run | Verdict |
|---|---|---|
| Issue #7759 | `gh issue view 7759 --json state,title` | **OPEN**, title matches. Premise holds. |
| `net-issue-flow.sh` | read in full | The FILED `select` is exactly as the brief quotes it. |
| `plugins/soleur/test/net-issue-flow.test.sh` | read + executed | 951 lines. Baseline `ALL PASS (84 assertions)`, `MIN_ASSERTIONS=84`. |
| `.claude/hooks/ship-net-issue-flow-gate.sh` | read in full | Delegates via `bash "$GATE"`; re-implements **no** query logic. |
| `specs/<branch>/run-mutations.sh` | `find … -name run-mutations.sh` | Exists only under `specs/feat-one-shot-net-issue-flow-mandated-filing-exemption/` — a **different** branch. Confirms the brief. |
| `review-todo-structure.md` `**Source:** PR #<pr_number>` | read | Present; governs **only** `code-review` review findings. Confirms the brief. |
| PR #7702 / #7841 | `gh pr view` | Both exist. **#7702's data has since been corrected** — the FILED query now returns `[7708,7709,7710,7759]` for it, so the original failing state is not reproducible live. Reproduction must be synthetic. |
| **PRIOR PLAN (not cited by the brief)** | `grep -rln 7759 knowledge-base/project/plans/` | `2026-09-03-fix-fixture-operand-and-flow-gates-plan.md` carries a full `### PR 4 — the net-issue-flow FILED blind spot (#7759)`. **Never implemented** (`grep -c conservation <gate>` = 0; #7759 still OPEN). |

**Stale premise found and corrected:** the brief presents #7759 as undesigned. A prior plan designed it
and chose a different predicate. This plan supersedes that PR 4 and says why.

### Property List (Phase 0.6b)

- **P1.** Every issue a PR filed is counted in `Filing:`, whichever number its body cites.
- **P2.** The gate never omits a filing *silently* — an attribution it makes is named, with numbers, in
  the always-emitted block.
- **P3.** The four measured call-shape properties survive: no `--search`, no
  `--label deferred-scope-out`, `--state all`, `--limit 500`.
- **P4.** A sibling PR's filings are never counted against this PR.
- **P5.** Wall clock stays inside the hook's 25 s ceiling (rc=124 is translated to `exit 0` — a silent
  always-pass).

### Cut List (Phase 0.6b, plus this deepen pass)

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| Producer sweep emitting `Source: PR #<n>` (issue option 1) | P1 | Covered by the body arm without any producer cooperating. Measured surface: 16 filing sites, 11 emitting no PR number, 5 incompatible citation shapes, 10 consumers. Coverage is a universal negative that decays with each new site. Full reasoning in `## Design Decision`. |
| Widen FILED to match issues citing an issue this PR closes (issue option 2) | P1 | Buys P1 while breaking P4. Full reasoning in `## Design Decision`. |
| Title-matching arm + `--json title` | (no requirement with a measured instance) | No measured under-count; no mutation row; the only change touching the pinned argv; and its monotonicity argument is inverted (see Enhancement Summary #3). |
| Building the named set in bash (`grep … | jq …`) | supply `$named` | Introduced two fail-open paths and a fence-stripper divergence. The existing `jq` pass already receives the PR body and already strips fences. |
| Keyword-anchoring the arm (`Files|Filed|Tracks|Refs`) | precision | Would return `Filing: 0` on PR #7702, whose filings are bare list items. Evidence below. |
| A second `jq` invocation for isolation | isolation | Doubles a ~1 s pass over a ~2 MB payload in the one gate whose failure history is a silent rc=124. |

### Measured evidence

**1. The predicate reproduces the correct filing set on the motivating PR.** PR #7702,
`createdAt=2026-08-26T12:56:25Z`. Its fence-stripped body's `#N` set is
`7553 7702 7708 7709 7710 7759`; subtracting close targets (`7652`) and the PR's own number leaves
`7553 7708 7709 7710 7759`; the `createdAt` filter drops `#7553` (`2026-08-13T21:53:53Z`), leaving
exactly **{7708, 7709, 7710, 7759}** — the correct filing set, from data the gate already fetches.

**2. PR #7702 names its filings as bare list items — keyword-anchoring would break the fix.**

```text
- #7708 — extend the operand rule to P1b (relative operands; `rm -rf ""` no-ops …)
- #7709 — burn down the shrink-only baseline
- #7710 — `gdpr-gate` refuses before scanning (pre-existing, found during planning)
```

No `Files`/`Filed`/`Tracks`/`Refs`/`Follow-up` precedes any of them. This is why the arm matches bare
`#N` and accepts the residual named in `## Risks`, rather than conjoining a filing keyword.

**3. The defect is still live, today.** Issue **#7889** (`createdAt=2026-09-07T11:17:03Z`) is a
consolidated tracker filed by PR **#7879**. Its body cites `#4859 #7833 #7849 #7853 #7854`;
`grep -c '#7879'` returns **0**. A third live instance, independent of #7702 and #7841.

**4. ADR-155's `Mandated-By:` exemption is inert.** Applying the **gate's own whole-line predicate**
(`^[ \t\r]*[Mm]andated-[Bb]y:[ \t\r]*[A-Za-z0-9-]+[ \t\r]*$`) to the 500 most recent issues yields
**33** issues. Classifying every `#N` they cite in `[7155,7895]` as issue-vs-PR (present in the issue
list ⇒ issue; absent in range ⇒ PR) gives **0 of 33 citing any PR**. Since the exemption is computed
only over issues that already matched the FILED query, none has ever been a candidate — the
`[mandates-filing]` corpus derivation, the OPEN check and the `Tracks|Refs` companion check have had no
reachable producer. This is the **fail-closed twin** of the reported fail-open defect, invisible
because it manifests as a false BLOCK an agent clears with the general override.

> A substring count (`contains("Mandated-By:")`) returns 41 and a loose line-anchored count returns 37.
> **33** is the number under the predicate the gate actually applies, and is the one this plan uses.

**5. The `--limit 500` window is saturated but has headroom.** Exactly 500 returned, newest-first,
`#7895@2026-09-07` down to `#7155@2026-08-02` (~36 days). 124 of 500 fell after PR #7702. ~4× the
current filing rate over a 12-day PR lifetime.

**6. Baseline.** `ALL PASS (84 assertions)`; `MIN_ASSERTIONS=84`; full suite `real 0m9.388s`.

### Applicable institutional learnings

- `knowledge-base/project/learnings/2026-09-04-every-defect-this-session-was-in-the-verification-not-the-fix.md`
  — **names #7759 twice** as a defect that fired live on that session's own PR: "The under-count was the
  comfortable answer and it was wrong." Its prevention line governs this plan's own verification: *when
  a gate returns the comfortable answer, reproduce its selector by hand.* **This PR runs through the
  gate it is fixing** — AC-D1.
- `.../learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — "Slack between a floor and the measured value is not padding — it is the budget an attacker spends."
  Governs the `MIN_ASSERTIONS` ratchet, and is why redundant assertions are cut rather than counted.
- `.../learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`
  — "a coverage guard whose oracle is derived from the artifact it guards must count a *second,
  independent* producer of the same fact." The PR body is that second producer of "what this PR is
  about"; the filing's own text is the first.
- `.../learnings/2026-08-02-a-guard-that-derives-authority-must-use-the-authoritys-own-parser.md`
  — honoured by adding **no** new corpus reader and no second fence-stripper.

## Research Reconciliation — Prior Plan and Brief vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Brief: the issue "deliberately does not decide". | True of the issue; **not** of the repo — the 2026-09-03 plan §PR 4 decided it (option-2 predicate, report-only, precision-conjoined). | Treated as design input, not a binding decision. Superseded; recorded in ADR-206. |
| Prior plan: the CLOSING-cite predicate must be report-only because "post-PR issues cite those numbers constantly for ordinary reasons — *regression of #500*". | Correct, and exactly why option 2 is rejected here. | The noise argument attaches to the *transitive* predicate. It does not vanish for the body predicate, but it shrinks from third-party text to text the PR author wrote — see `## Risks`. |
| Prior plan: "No producer is edited here… An instruction with no file behind it is prose." | Conclusion right, reason falsified — there **are** named producers emitting `Mandated-By:` with no PR number. | Same conclusion, better reason: the sweep is **unnecessary**, not unsourced. |
| Prior plan: `FILED=$((FILED+1))` runs per row **before** any verdict is examined. | Verified. | Load-bearing and **intended**: body-attributed rows are filings and must raise `FILED`. The verdict ladder still applies, which is what revives the exemption. |
| Brief: "check whether the fix needs to reach [the hook] too." | The hook delegates, re-implements no query logic, and embeds `${OUT}` so any new report line reaches the operator. Its budget is dominated by `gh issue list`; this change adds no API call. | **No hook change.** Verified, not assumed. Its four `hook remedy needle` assertions must still pass. |
| Issue: `deferred-scope-out` filings "inherit no such requirement". | Confirmed, and broader: 11 of 16 filing sites emit no PR number; 5 incompatible shapes exist. | Consumer-side fix; producer sweep cut. |
| Review: `ship/SKILL.md` has a path where the operator cites an **existing OPEN issue** and the skill writes `Tracks #NNNN` into the PR body — an issue this PR did not file, which the arm would then count (a P4 break by repo-mandated workflow). | Confirmed. **But it self-neutralises:** that path's issues carry `Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps` and are OPEN, and the PR body carries the `Tracks` companion — the three conditions of the ADR-155 exemption. Such a row is counted in `Filing:` and then **subtracted from `NET`**. | No change needed; the interaction is documented in `## Risks` and ADR-206 so the next reader does not rediscover it as a bug. |
| Review: under the arm, `Tracks #N` both *causes* a row's inclusion and *satisfies* exemption condition 4, collapsing one of ADR-155's four independent conjuncts. | Correct. Condition 2 (the human-gated `[mandates-filing]` corpus edit) still bounds the blast radius. | Named explicitly in ADR-206 and in the gate header. Not priced at zero. |

**Adjacent pre-existing finding (acknowledged, not filed).** `/review`'s self-check probe searches
`--search "Ref #<PR_NUMBER>"` while its producer writes `From code review of PR #${prNum}` — dark
against its own producer. Out of scope for a blocking-gate PR. Recorded in ADR-206 under "Known
adjacent gaps". Per `wg-defer-only-after-inline-triage`, Phase 7 triages it inline first.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (63 open); matched every planned
path with `jq --arg path … contains($path)`. **None.**

## Design Decision

### Adopted — a DECLARED filing line, produced once by `/ship`, counted by the gate; everything else reported

Three roles, each mechanism doing the job it is actually good at.

**1. Counted — the declared filing list.** An issue is a filing of PR *N* when it was created after
PR *N* **and** either its body cites `#N` (existing behaviour, unchanged) **or** its number appears on
PR *N*'s **declared filing line** — a single `Filed: #A #B #C` line in the PR body, on the fence-stripped
body, excluding close targets and *N* itself.

**2. Produced — one line, in one place, in the skill that runs the gate.** `/ship` Phase 6 emits the
`Filed:` line into the PR body it generates, and the line is added to Phase 6's **existing
carry-forward table** — the table that already exists precisely because Phase 6 *full-replaces* the
body and two blocking gates read markers that live in it (`Tracks #N`/`Refs #N`, and the
`<!-- gate-override: net-issue-flow -->` marker). This is one producer, not sixteen, and the mechanism
that keeps it alive across the body rewrite is already built and already tested.

**3. Reported, never counted — the conservation check.** Any issue created after the PR whose number
appears **elsewhere** in the PR body is printed on its own line as a *possible unattributed filing*, and
contributes nothing to `Filing:`, `NET`, or the verdict. This is issue option 3 in its literal form: it
makes the blind spot self-reporting rather than silent, without making prose load-bearing.

Rationale:

- **It changes the failure mode, not the input data.** With the declared line, the gate cannot omit a
  filing that `/ship` itself recorded — a property, not a convention that happens to produce one. With
  the conservation line, a filing that escapes the declaration is *named* rather than dropped.
- **It cannot regress P3.** The `gh issue list` argv is byte-identical; both sets are derived inside the
  `jq` pass that already receives `--arg prbody`.
- **It preserves P4 — which bare-`#N` counting did not.** See the measurement below: prose citation is
  measurably not a filing claim. Counting only the declared line restores P4; the conservation line
  keeps the information without giving it authority.
- **It revives ADR-155's exemption.** Measured: 0 of 33 `Mandated-By:` issues cite a PR. Their
  `Tracks #<issue>` companion is already carried forward by Phase 6, and `Tracks`/`Refs` numbers join the
  declared set.
- **It reproduces the motivating case**: `/ship` on PR #7702 declares `Filed: #7708 #7709 #7710`,
  producing `Filing: 3 / Net: +2 / BLOCKED` — the verdict the issue reports as correct.
- **It fails CLOSED on a malformed body.** An unbalanced fence makes `$pb` empty, so both sets are empty
  and neither arm contributes — it cannot become an escape hatch.

**Why bare-`#N` counting was rejected after being drafted — measured, over 300 PRs.**

| Measurement | Result |
|---|---|
| PRs where a bare-`#N` arm would add attributions | 56 / 300 (122 attributions) |
| Issues attributed to **two different PRs** (so at least one is wrong) | **9** — e.g. #7228→{7203,7158}, #7310→{7303,7300}, #7652→{7618,7616} |
| Single-claim misattribution (invisible to the double-claim count) | PR #7546's body discusses `#7585`, which opens *"deferred-automation — surfaced by PR #7552"* |
| PRs flipping PASS → BLOCK | **25 / 300 (8.3%)**, with an unknown false-positive share |

P4 (*"a sibling PR's filings are never counted against this PR"*) is a stated guard property, and under
bare-`#N` counting it is **measurably false**. A gate that blocks 8.3% more PRs with an unmeasured
false-positive rate is the "cries wolf" failure the prior plan feared — reached by a different route.

**Why not keyword-anchoring (`Files|Filed|Tracks|Refs #N`) on free prose.** It is the right *shape* —
an assertion of the filing relationship rather than of relevance — but applied to an unproduced body it
returns `Filing: 0` on PR #7702, whose filings are bare list items (measurement 2). The declared line is
the same idea with a producer behind it, which is what makes it work.

**Counting, not report-only, for the declared set.** The prior plan's report-only choice would still
have printed `PASS` on #7702 — annotating a wrong verdict rather than correcting it, the shape the
gate's header condemns. Report-only is retained exactly where it belongs: on the undeclared residual.

### Rejected — widen FILED to match issues citing an issue this PR closes (issue option 2)

- **Breaks P4 by construction.** Attribution is transitive through a third party, so a sibling PR's
  filings count against this one whenever both touch a shared closed issue.
- **Ordinary prose is indistinguishable from a filing** ("regression of #500"). The prior plan reached
  the same conclusion and could only rescue the predicate by giving up the fix.
- **It fails in the closing direction.** A false BLOCK trains the override reflex.
- **Highest blast radius on the pinned query**, where four prior defects each made the gate always-pass.

### Rejected at the SIXTEEN filing sites; adopted at ONE — the `/ship` PR-body template (issue option 1)

The issue frames option 1 as "put it in the issue template used by `deferred-scope-out` filings". That
version is rejected. A single declared line in the PR body — the same idea moved to one producer — is
adopted, above.

Rejected at the filing sites because:

- **It re-instantiates the defect being fixed** at every site not patched — a consumer depending on a
  format no producer guarantees, failing silently when a producer forgets.
- **The coverage claim is a universal negative** that decays with the next filing site and every
  improvised `gh issue create`. Measured: 16 sites, 11 emitting no PR number, 5 mutually incompatible
  citation shapes (`**Source:** PR #N`, `From code review of PR #N`, `**Source PR:** #N`, `Ref #N`
  expected by two consumers and produced by none, and nothing at all).
- **It is unenforceable where it matters** — the gate runs at `gh pr ready`/`gh pr merge`, by which time
  the issues already exist and a missing line has nothing to detect it.

Adopted at the `/ship` body template because the objections above invert there:

- **One site, not sixteen**, and it is inside the skill that runs the gate — the producer and the
  consumer ship together and are tested together.
- **The persistence mechanism already exists.** Phase 6 full-replaces the body and already carries a
  documented table of markers that must survive it, for exactly this class of reason. The change is a
  third row in a table that has two.
- **It is enforceable at the right moment** — the line is written in the same phase that later runs the
  gate, so a missing declaration is a defect in one code path rather than a convention nobody owns.

The residual — a filing made outside `/ship`, or a body hand-edited afterwards — is what the
conservation line reports.

## User-Brand Impact

**If this lands broken, the user experiences:** a `gh pr ready` / `gh pr merge` denied with
`net-issue-flow: BLOCKED` naming issue numbers they do not recognise as their filings — a false block on
a correct PR. The documented override clears it in one line and the gate prints the remedy in the
denial itself.

**If this leaks, the user's data/workflow is exposed via:** no new exposure. The change reads issue
numbers, bodies and timestamps already fetched from the repository the gate already queries, and writes
nothing beyond stdout and the existing incident ledger.

**Brand-survival threshold:** `aggregate pattern`.

The harm the defect causes is cumulative — a queue growing by the under-counted difference across many
PRs — not a single-user incident. The worst new failure mode is workflow friction with a one-line
remedy printed at the point of failure, and no user data is involved. No `requires_cpo_signoff`.

## Implementation Phases

### Phase 1 — RED: pin the defect before touching the gate

Per `cq-write-failing-tests-before`, every case is added to `plugins/soleur/test/net-issue-flow.test.sh`
first and confirmed RED. Each assertion call site carries its own `cases=$((cases + 1))` — never inside
`pass()`/`fail()`, never inside `$( )`.

**1.0 — add the injection seam first.** The suite hardcodes
`GATE="$REPO_ROOT/plugins/soleur/skills/ship/scripts/net-issue-flow.sh"`, so the both-directions proof
in AC-G4 is not runnable. Change to `GATE="${NET_ISSUE_FLOW_GATE:-$REPO_ROOT/…}"` and add an assertion
that the **unset** default resolves to the shipped path — otherwise a stray env var could silently
redirect the suite, which would be a fail-open in the harness itself.

1. **R1 — the #7702 reproduction.** Issue `#7101` body cites `#8000`, never `#999`; PR body names
   `#7101`. Expect `Filing: 1`, `exit 1`. RED today.
2. **R2 — exemption revival.** Issue `#7102` carries `Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps`
   on its own line, `state: "OPEN"`, cites only `#8000`; PR body carries `Tracks #7102`. Expect counted
   in `Filing:` **and** reported `exempt` under that rule id. RED today.
3. **R3 — the report line.** The always-emitted block names the body-attributed numbers on their own
   labelled line, and **does not** name a named-but-uncounted issue. RED today.

### Phase 2 — GREEN: the gate change

Single file: `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`.

**2a. Derive the named set inside the existing `jq` pass.** The pass already receives
`--arg prbody "$PR_BODY"` and already computes `($prbody | sf) as $pb`. Add one argument,
`--arg closing "$CLOSING_NUMS"` (already a newline-separated integer list at that point), and three
lines:

```jq
  ($prbody | sf) as $pb
  # First-party evidence: numbers the PR's AUTHOR wrote into the PR's own description.
  # Derived from $pb, the SAME fence-stripped body the exemption's Tracks/Refs companion
  # check reads -- never from a second stripper. This file's awk stripper uses
  # [[:space:]] while `sf` uses [ \t]; deriving here makes that difference unreachable
  # instead of load-bearing.
  # `(?<![0-9A-Za-z])` is a LOOKBEHIND, not a consuming group: a consuming boundary eats
  # the separator and drops the second member of `#1#2`. Measured.
  # An unbalanced fence makes $pb "" -> $refs [] -> the arm contributes nothing. FAIL-CLOSED.
  | ($pb | [scan("(?<![0-9A-Za-z])#([0-9]+)")] | map(.[0] | tonumber) | unique) as $refs
  | ($closing | split("\n") | map(select(length > 0) | tonumber)) as $close
  # DECLARED: the `Filed:` line /ship Phase 6 emits, plus the Tracks/Refs companions.
  # This is the only set that COUNTS. It is produced, carried forward across Phase 6's
  # full-replace, and owned by one code path -- not scavenged from prose.
  | ($pb | split("\n")
      | map(select(test("^[ \t\r]*(Filed|Tracks|Refs):?[ \t]+#[0-9]")))
      | map([scan("(?<![0-9A-Za-z])#([0-9]+)")] | map(.[0] | tonumber)) | add // []
      | unique) as $declared_raw
  | (($declared_raw - $close - [($pr | tonumber)])) as $declared
  # CONSERVATION: named anywhere else in the body. REPORTED, never counted -- measured
  # over 300 PRs, prose citation attributes 9 issues to two PRs each and flips 8.3% of
  # PRs to BLOCK. Naming them is what makes the blind spot self-reporting; counting them
  # makes P4 false.
  | (($refs - $close - [($pr | tonumber)]) - $declared) as $unattributed
```

`Filed`/`Tracks`/`Refs` share one line matcher because all three are first-party declarations of a
filing relationship, all three are carried forward by Phase 6, and `Tracks`/`Refs` are already the
companion the ADR-155 exemption requires — so the exemption's population and the declared population are
the same set by construction rather than by coincidence.

> **Do NOT build this set in bash.** The first draft used
> `grep -oE … | jq … || _fail_open`. Under `set -uo pipefail` (in force; `-e` is not) `grep` exits 1 on
> no match, `pipefail` propagates it, and the gate `exit 0`s **before `gh issue list` runs** — for every
> PR whose body names no issue, which is the population the gate exists to catch. The same path turns
> the deliberately fail-**closed** unbalanced-fence handling into a fail-open. Both measured. The
> existing suite already contains the counterexamples: Cases 1 and 4 use bodies with zero `#`.

Measured behaviour of the block above, on a body carrying `Closes #7652`, `Filed: #7708 #7709 #7710`,
`Tracks #7801`, prose `#7708` and `Blocked on #7900`, a fenced `#9999`, and the self-reference `#999`:

| Set | Result | Note |
|---|---|---|
| `DECLARED` (**counted**) | `[7708,7709,7710,7801]` | `Filed:` line + `Tracks` companion; close target, self and fenced number all excluded |
| `UNATTRIBUTED` (**reported only**) | `[7900]` | prose citation — named on its own line, contributes nothing to `Filing:`/`NET` |
| unbalanced fence | both `[]` (`$pb` is `""`) | **fails closed**; neither arm can contribute |
| `CLOSING_NUMS` empty | no crash | a PR that closes nothing still declares correctly |

Note that the prose mention of `#7708` does not double-count it: `DECLARED` and `UNATTRIBUTED` are
disjoint by construction (`$unattributed` subtracts `$declared`).

**2b. Widen the `select` as a sibling disjunction over the same array** (not a stage inside the FILED
pipeline, so a malformed predicate cannot take the pass down):

```jq
| [ .[]
    | select((.createdAt // "") >= $since)
    | . as $i
    | select(
        (($i.body // "") | test("(^|[^0-9A-Za-z])#" + $pr + "([^0-9]|$)"))
        or (($named | index($i.number)) != null)
      )
  ]
```

The `createdAt` guard is a **separate conjunct**, so it governs all three arms regardless of position —
a PR-body reference to an older issue is context, not a filing.

**2c. Carry provenance in the row, free text last.** The row becomes
`[number, verdict, attribution, detail]`, consumed as
`while IFS=$'\t' read -r _num _verdict _attr _detail`. `attribution` is `cites-pr` or `pr-body`.

Ordering is load-bearing for a reason beyond `read`: the exempt branch does
`_emit_as "net-issue-flow-mandated-filing--${_detail}" bypass …`, justified by "on the exempt path
`$_detail` is a corpus-derived id". With `attribution` placed after `detail`, `_detail` becomes
`pr-body` and every exemption is silently re-grouped under
`net-issue-flow-mandated-filing--pr-body` — still `[a-z0-9-]`-shaped, still past the orphan filter.
Update that comment to say so.

**2d. Report and emit telemetry.** One conditional line in the always-emitted block; `Filing:` keeps its
true total:

```text
  Attributed: 2  (#7708 #7709 — named in the PR body, citing the issue not the PR)
```

The line MUST be derived from the rows actually counted, never from `$named` — otherwise the report and
the count desynchronise, and this line is the in-surface probe the Observability section rests on.

Then `_emit_as net-issue-flow-body-attributed applied "pr=${PR_NUMBER} attributed=<n>"`, emitted only
when the set is non-empty.

**2e. Surface the new id in the aggregator.** `scripts/rule-metrics-aggregate.sh` reads ids by **exact
key** (`$counts["net-issue-flow"].warn_count`) and its orphan gate does
`map(select(startswith("net-issue-flow") | not))` — so a `net-issue-flow-body-attributed` row is
filtered out of `orphan_rule_ids` **and** counted by no named field: write-only telemetry. That file
documents this exact mistake happening before, to the two mandated-filing ids, remedied with explicit
named fields. Add `gate_body_attributed_count` the same way.

**Do not touch:** the `gh issue list` argv, the `NET > 0` threshold, the override marker, the awk
fence-strip, the merge-base corpus read, `lint-rule-bodies.py`, or the `Filing:`-keeps-its-true-count
contract.

### Phase 3 — Exemption revival (verification only, no code)

Confirm via R2 that a body-attributed row flows through the unchanged verdict ladder and is subtracted
from `NET` while `Filing:` keeps its true count.

### Phase 4 — Pin the `--json` field list

Case 8 asserts four properties of the `issue list` argv and inspects the `--json` field list **not at
all**. Dropping `createdAt` makes `(.createdAt // "")` empty, `"" >= $since` false for every row,
`FILED=0`, `NET ≤ 0` — **PASS on every PR, silently**, a fifth always-pass with no assertion covering
it. Add a fifth Case 8 assertion that the argv contains `--json` and that the field list contains
`number`, `body`, `createdAt` and `state`. This is worth doing whether or not the query is edited.

### Phase 5 — Ratchet the anti-vacuity floor

Run the suite, read the reported count, set `MIN_ASSERTIONS` **at** it. No slack, no rounding; the floor
ratchets upward only (ADR-193). Redundant assertions are cut rather than counted, so the floor measures
discrimination and not padding.

### Phase 6 — Documentation

- `ship/SKILL.md` — document the attribution arm beside the four properties, which stay verbatim.
- Gate header — extend "Why the FILED query looks the way it does" with the fifth defect and its remedy,
  and record that `Tracks #N` now both admits a row and satisfies exemption condition 4.
- **ADR-155 amendment.** Measurement 4 falsifies its stated consequences: it is `Accepted` and describes
  a working four-condition exemption that has never fired. Add
  `## Amendment — 2026-09-07 (#7759)` recording the measured inertness, the revival, and the conjunct
  collapse, pointing forward to ADR-206. An ADR-only note in the new ADR would leave ADR-155 silently
  contradicted.
- **ADR-206** (see below).
- Verify every `knowledge-base/` citation in this plan resolves.

### Phase 7 — Adjacent finding triage

Triage the `/review` `Ref #N` probe inline first. If the fix stays inside the cost-of-filing auto-flip
(≤100 lines AND ≤4 files, counting this PR's set), fold it in; otherwise leave the ADR acknowledgement
and file nothing.

### Phase 8 — Verification, including dogfooding

Full suite, then the mutation battery, then run the gate against **this** PR and hand-reproduce the
FILED selector rather than trusting the verdict.

## Files to Edit

| Path | Change |
|---|---|
| `plugins/soleur/skills/ship/scripts/net-issue-flow.sh` | Phases 2a–2d: in-`jq` derivation of the declared set and the conservation set, sibling disjunction, provenance field, two report lines, telemetry, header. |
| `plugins/soleur/test/net-issue-flow.test.sh` | `$GATE` seam; R1–R3; the bounding, control and escape cases in `## Test Scenarios`; the Phase 4 `--json` assertion; `MIN_ASSERTIONS` ratchet. |
| `plugins/soleur/skills/ship/SKILL.md` | **Producer:** emit the `Filed: #A #B #C` line in the Phase 6 body template, and add it as a third row to Phase 6's existing carry-forward table (which today carries `Tracks #N`/`Refs #N` and the override marker, because Phase 6 full-replaces the body). **Docs:** document the declared arm and the conservation line beside the four query properties, which stay verbatim. |
| `scripts/rule-metrics-aggregate.sh` | Phase 2e: named fields for `net-issue-flow-body-attributed` and the conservation-report id. |
| `knowledge-base/engineering/architecture/decisions/ADR-155-cross-gate-exemption-markers-in-the-rule-corpus.md` | Amendment recording measured inertness, revival, and conjunct collapse. |

**Deliberately NOT edited**, verified rather than assumed:

- `.claude/hooks/ship-net-issue-flow-gate.sh` — delegates, re-implements no query logic, embeds `${OUT}`
  so the new line reaches the operator, and its budget is dominated by an API call this change does not
  add to. Its four `hook remedy needle` assertions must still pass unmodified — that is the check that
  the file was genuinely left alone.
- Every filing producer, and `review-todo-structure.md` — see Cut List.

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-206-attribute-a-prs-filings-by-the-prs-own-body.md` | The attribution-model decision and its rejected alternatives. |
| `knowledge-base/project/specs/feat-one-shot-7759-net-issue-flow-filing-cites-issue/tasks.md` | Task breakdown. |

## Architecture Decision (ADR/C4)

Detection fires: this changes a **resolver / trust-boundary rule** — who decides an issue belongs to a
PR — and it extends ADR-155.

### ADR

**ADR-206 — attribute a PR's filings by the PR's own body, not only by what the filing cites.**

Ordinal **206**, not 205: 205 is claimed by commit `e6d6ec8c5` on the unmerged branch
`feat-one-shot-7849-7853-7854-fixture-env-ledger-ancestry`. A `git ls-tree` scan of origin refs shows
no ADR-205 *file* and reports it free — the claim is visible only to `git log --all`. Use both probes.
206 is free under both. Still **provisional**: `/ship`'s ADR-Ordinal Collision Gate re-derives it before
merge and after every Phase 7 sync, and any renumber must sweep
`grep -rn 'ADR-206' knowledge-base/project/{plans,specs}/feat-one-shot-7759-*/` in the same edit.

Content: the two-arm attribution model; the first-party rationale **and its limit** (bare `#N` is
evidence of a mention, not of the filing relationship) with the #7702 measurement showing why
keyword-anchoring is unavailable; `## Alternatives Considered` carrying both rejected options plus
keyword-anchoring, each with the measurement that rejected it; the supersession of the 2026-09-03 plan
§PR 4; the ADR-155 conjunct collapse; the `Tracks #NNNN` cite-an-existing-issue interaction and why it
self-neutralises; and `Known adjacent gaps` for the `/review` `Ref #N` probe.

### C4 views

**No C4 impact.** Enumerated against all three model files
(`diagrams/{model.c4,views.c4,spec.c4}`, 691 / 74 / 54 lines), read rather than keyword-grepped:

- **External human actors:** none added. `contributor = actor "Contributor / PR Author" #external` and
  `founder = actor "Founder / Operator"` are modelled; no actor's reach changes.
- **External systems:** none added. `github = system "GitHub" #external` is modelled and the gate
  already calls it. No new vendor or endpoint family.
- **Containers / data stores:** none. The change is confined to one script inside
  `plugin = system "Soleur Plugin"`, whose L3 granularity is one component per skill
  (`ship = component "ship skill"`) — a script sits one level below any modelled element.
- **Actor↔surface access relationships:** none change; no element description is falsified.

### Sequencing

None. Nothing is soak-gated; ADR-206 is authored `accepted`.

## Guard Contract

### Guard 1 — the FILED attribution arm

**Property.** Every issue created after PR *N* that PR *N* filed is counted in `Filing:` — whether the
issue cites the PR or PR *N*'s own body names it — and no issue PR *N* did not file is counted.

**Assembly.** The property quantifies over the **two injection points into `FILED`**, and there are
exactly two: the `select(...)` in the single `jq` pass, which decides which issues become rows; and the
`while IFS=$'\t' read` loop, whose `FILED=$((FILED + 1))` runs once per row **before** any verdict is
examined. The chokepoint between them is the TSV row contract — four fields, free text last. A guard
scoped to the `select` alone is the defect, not a partial fix: a row the loop mis-parses corrupts the
verdict with the `select` still perfectly correct.

**Mutation matrix.** Derived from the design. Every row MUST drive the suite RED.

| # | Mutation | Why it must red |
|---|---|---|
| M1 | Delete the `or (($named \| index($i.number)) != null)` disjunct. | The arm itself. R1 reds. (The old "starve `$named` to `[]`" row is folded in here — with the derivation inside `jq`, an empty `$named` and a deleted disjunct are one axis, and `[]` is also the *legitimate* value for a body with no refs, so it could not discriminate.) |
| M2 | After a compliant first member, truncate the derivation (`… \| .[0:1]`). | A check that stops at the first member is an instance of the class this gate exists to catch. Needs the two-attributed fixture. |
| M3 | Move the provenance field **after** `detail` (`[number, verdict, detail, attribution]`) leaving `read` unchanged. | A **reorder**, not a delete: the `select` stays correct and the row count is unchanged, so any assertion that only counts rows stays green. Reds the per-row provenance case AND the `net-issue-flow-mandated-filing--<id>` ledger assertion, which silently becomes `--pr-body`. |
| M4 | Delete the `select((.createdAt // "") >= $since)` guard. | A PR-body reference to a pre-existing issue becomes a filing. (The first draft's "or move it after the disjunction" clause is **cut**: `select(A) \| select(B)` and `select(B) \| select(A)` are identical in jq, so it was a no-op mutation reporting the baseline.) |
| M5 | Derive `$refs` from `$prbody` instead of `$pb`. | A number inside a fenced gate transcript pasted into the PR description becomes a filing — the self-override class the override marker is already guarded against, reached through the new arm. |
| M6 | Replace the lookbehind `(?<![0-9A-Za-z])` with a consuming group `(^\|[^0-9A-Za-z])`. | Drops the second member of adjacent references (`#1#2` → `[1]`). Measured. |
| M7 | Reuse the shared `net-issue-flow` rule id for the body-attribution emit, **or** drop the aggregator's named field. | Collapses "the narrow query under-counted here" into "the gate ran". Requires a **positive** ledger assertion (`.rule_id == "net-issue-flow-body-attributed"` on a firing fixture), mirroring the suite's existing `attr`/`attr_neg` pair — the absence-only assertion in AC-G7 is green under this mutation because the emit is already conditional. |
| M8 | Conjoin `and (($i.state // "") == "OPEN")` onto the new disjunct. | **The escape row.** It satisfies every other row in this matrix while violating the property: a filed-then-closed issue is still a filing, which is precisely why `--state all` is a pinned property. Requires the CLOSED-state case. |

**Harness rows.** At least one suite mutation that reds, and must-PASS non-canonical inputs.

| # | Row | Why it must red / pass |
|---|---|---|
| H1 | **RED.** Neuter `fail()` to a no-op **while a product defect is induced** (point `$GATE` at the `origin/main` copy). | The conservation identity must fire with `An assertion was counted but its verdict was not recorded`. Neutering `fail()` on a *green* suite is a no-op — `fail()` is never called — so the original unpaired row reported the baseline. |
| H2 | **RED.** Delete one new assertion's `cases=$((cases + 1))` while keeping its verdict. | The conservation check fires on the over-count arm and names it a harness bug. |
| H3 | **RED.** **Keep** `MIN_ASSERTIONS` at the post-change count and delete one case. | Observe `anti-vacuity floor: only N-1 assertion(s) ran`. (The first draft lowered the floor *and* deleted a case — `N-1 < N-1` is false, so nothing fired and the row was green.) |
| H4 | **must-PASS.** All filings cite the PR; PR body names none of them. | `NET` identical to the `origin/main` gate on the same fixture, run through the `$GATE` seam as a real differential. Distinguishes "the arm is correct" from "the arm accepts everything"; RED rows alone cannot see over-acceptance. |
| H5 | **must-PASS.** PR body names a number absent from `ISSUES_JSON` (a PR number, or an issue outside the 500 window). | No crash, no fail-open, not counted. |
| H6 | **must-PASS.** PR body with **zero** `#` characters; `ISSUES_JSON` has 3 post-PR filings citing the PR. | Must print the `Filing: 3 / Net: +3` block and **exit 1**, emitting no `warn`. Bounds the fail-open direction — the shape the first draft broke. Assert on `CASE_RC` **and** the presence of the `Net:` line; a fail-open produces neither. |
| H7 | **must-PASS.** PR body with `Closes #7759` plus one unmatched fence. | Must reach a real verdict and emit no `warn`. The arm must contribute nothing (fail-closed), not abort the run. |

## Observability

```yaml
liveness_signal:
  what: "net-issue-flow rows in the incident ledger, keyed by rule_id. A run emits exactly one of
         applied|deny|bypass|warn under `net-issue-flow`, plus `net-issue-flow-body-attributed`
         (applied) only when the new arm attributed at least one issue."
  cadence: "once per `gh pr ready` / `gh pr merge`, plus every explicit /ship Phase 5.5 run"
  alert_target: "rule-metrics-aggregate.sh weekly rollup, via the NAMED field gate_body_attributed_count
                 added in Phase 2e -- the rollup reads ids by exact key, so a prefix alone surfaces
                 nothing"
  configured_in: ".claude/hooks/lib/incidents.sh (sourced by the gate); ids emitted from
                  plugins/soleur/skills/ship/scripts/net-issue-flow.sh; surfaced in
                  scripts/rule-metrics-aggregate.sh"

error_reporting:
  destination: "the incident ledger via emit_incident, under net-issue-flow* rule ids"
  fail_loud: "Every fail-open path prints its reason to stdout AND emits a `warn` row -- never
              `transient`, which the aggregator does not count. This change adds NO new fail-open
              branch: the named set is derived inside the existing jq pass, whose single failure mode
              (`could not parse issue list`) is already covered."

failure_modes:
  - mode: "The arm dispatches but attributes nothing on every run (vacuous arm)."
    detection: "gate_body_attributed_count is 0 across a week in which net-issue-flow applied/deny rows
                are non-zero -- the arm ran and never fired."
    alert_route: "weekly rollup. Mutation M1 plus the R1 fixture are the pre-ship proof it CAN fire."
  - mode: "The arm over-attributes -- an issue merely referenced in PR prose."
    detection: "the always-emitted `Attributed:` line names every such number, so the misattribution is
                visible in the denial text the hook surfaces via ${OUT}."
    alert_route: "self-reporting at the point of failure; remedy (c) is printed in the same output."
  - mode: "The `--json` field list loses `createdAt`, making every row fail the recency filter and the
           gate pass on every PR."
    detection: "the Phase 4 Case 8 assertion on the argv's --json field list."
    alert_route: "CI suite; this is the always-pass path with no prior coverage."
  - mode: "The gate exceeds the hook's 25 s ceiling and rc=124 is translated to exit 0."
    detection: "`net-issue-flow-timeout` warn row, emitted by the hook ABOVE its `-eq 1` early exit."
    alert_route: "weekly rollup. This change adds no API call and no subprocess; AC-G8 measures the
                  delta against the origin/main gate."

logs:
  where: "gate stdout (captured verbatim into the PreToolUse denial reason) + the incident ledger"
  retention: "as configured by .claude/hooks/lib/log-rotation.sh; unchanged"

discoverability_test:
  command: "bash plugins/soleur/test/net-issue-flow.test.sh"
  expected_output: "net-issue-flow.test.sh: ALL PASS (<N> assertions)   # N == the ratcheted MIN_ASSERTIONS"
```

No `credentials_required`: the suite runs against the stub `gh` and stub `git` seams and needs no token.
The first token is `bash`, on preflight Check 10's `PROBE_VERB_ALLOWLIST`, and the command invokes no
remote shell, so the Phase 2.9 reject condition on the `ssh` verb does not fire.

**Affected-surface note (Phase 2.9.2).** This is observability layer 7 — code executing on a customer's
self-hosted CLI, where the operator cannot inspect the run. The `Attributed:` line is the in-surface
probe: emitted **from** the gate, naming the discriminating numbers, carried into the hook's denial text
by `${OUT}`, so "the gate under-counted" and "there was nothing to count" are separable from a single
run's output. It must be derived from the counted rows, not from `$named` (Phase 2d), or the probe and
the count can disagree.

## Acceptance Criteria

### Pre-merge (PR)

- **AC-G1.** `bash plugins/soleur/test/net-issue-flow.test.sh` exits 0 and prints
  `net-issue-flow.test.sh: ALL PASS (<N> assertions)`.
- **AC-G2.** `MIN_ASSERTIONS` equals the reported `<N>` exactly — no slack.
- **AC-G3.** The `gh issue list` argv is **unchanged**: `git diff origin/main -- <gate>` shows no change
  to that line, and the Phase 4 assertion confirms the `--json` field list still contains `number`,
  `body`, `createdAt`, `state`. (The four Case 8 properties are then preserved by the argv not moving,
  which is a stronger statement than re-running assertions that were green before the change.)
- **AC-G4.** R1 reds against the pre-change gate and greens after, run through the `NET_ISSUE_FLOW_GATE`
  seam with `git show origin/main:<gate>` written to a temp path and `chmod +x`'d. The verdict keys on
  the named `FAIL <label>` lines for R1–R3, **not** on the suite's exit status — a missing `chmod` also
  exits non-zero, and at exit-status granularity that is indistinguishable from the defect being
  present.
- **AC-G5.** R2 passes: a body-attributed issue with `Mandated-By:` and a `Tracks #N` companion is
  reported `exempt`, and `Filing:` shows its true unreduced count.
- **AC-G6.** Every mutation row M1–M8 drives the suite RED; H1–H3 drive it RED; H4–H7 pass. Record the
  observed verdict per row, and confirm the battery is GREEN with **no** mutation applied before
  trusting any row.
- **AC-G7.** A fixture where every filing cites the PR emits **no** `net-issue-flow-body-attributed`
  row; a fixture where the arm fires emits exactly one, asserted by exact `.rule_id` match, and the
  weekly rollup renders `gate_body_attributed_count` for it.
- **AC-G8.** Stub-seam runtime delta versus the `origin/main` gate on the same fixture is **< 200 ms**
  (AC-G4 already stages that gate, so the comparison is free). Baseline for reference: the full suite
  runs `real 0m9.388s`. The absolute 25 s ceiling is argued structurally — the change adds no `gh` call
  and no subprocess — because the stub seam excludes the API cost that dominates it.
- **AC-G9.** The hook is byte-unchanged: `git diff --stat origin/main -- .claude/hooks/ship-net-issue-flow-gate.sh`
  is empty, and the four `hook remedy needle` assertions pass.
- **AC-G10.** `ADR-206-*.md` exists and its `## Alternatives Considered` names all three rejected
  options (producer sweep, transitive widening, keyword-anchoring) with the measurement that rejected
  each; ADR-155 carries the amendment. (Ordinal re-derivation is a Phase 6/ship **process step**, not an
  AC — an AC whose outcome depends on what other branches do violates
  `cq-ac-must-not-depend-on-concurrent-sessions`.)
- **AC-G11.** `ship/SKILL.md` states all four query properties verbatim **and** documents the arm.

### Dogfooding

- **AC-D1.** Run the gate against this PR. Expected `Closing: 1 (#7759) / Filing: 0 / Net: -1 / PASS`.
  Then **hand-reproduce the FILED selector** against the live issue list rather than trusting the
  verdict. A fix PR that passes by exploiting its own defect is the one outcome this plan must not
  produce. If any issue is filed after all, its body must cite this PR's number and the
  hand-reproduction must confirm the gate sees it.
- **AC-D2.** The PR body carries `Closes #7759` (body, not title).

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change. Assessed against all eight domains: confined to a shell gate, its test
suite and a metrics aggregator inside the repo, reading only issue metadata the gate already fetches
from the repository it already queries. No user-facing surface, no persistent store, no vendor, no cost,
no personal data.

**Product/UX Gate:** not applicable. The mechanical UI-surface override was evaluated against
`## Files to Edit` and `## Files to Create` — zero matches for `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx` or any shared UI-surface term. Tier **NONE** by both the mechanical check and the
semantic sweep, so `wg-ui-feature-requires-pen-wireframe` does not fire.

**GDPR / Compliance (2.7):** skipped. No schema, migration, auth flow, API route or `.sql`. The four
expansion triggers were each checked and none fires.

**Infrastructure-as-Code (2.8):** skipped. No server, service, cron, secret, DNS record, cert, firewall
rule or vendor account; no trigger phrase in the plan or feature description.

**Encryption Posture (2.11):** skipped. No persistent store, no new cross-component connection, no
`.tf`/migration/cloud-init/compose file.

**Network-Outage (4.5):** the keyword `timeout` appears, but only as the hook's **process** timeout
(`timeout 25`), not a network symptom. No SSH, host, firewall or provisioner is involved, so the L3→L7
checklist has no applicable layer. Recorded rather than silently skipped.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| **Over-attribution from PR prose** ("blocked on #7900", "rebased past #7888"). Measured: bare-`#N` counting attributes 9 issues to two PRs each and flips 8.3% of PRs to BLOCK. | **Designed out.** Prose citations land in the reported-only conservation set and contribute nothing to `Filing:`/`NET`. Only the declared `Filed:`/`Tracks`/`Refs` lines count. This is why the design changed during deepen-plan. |
| **A filing escapes the declaration** — made outside `/ship`, or the body hand-edited after Phase 6. | The conservation line names it as a *possible unattributed filing*, so the blind spot is self-reporting rather than silent. It does not block, so a false entry costs a line of output, not a wedged merge. Track the real rate via the aggregator field before considering promotion to counting. |
| **`/ship` Phase 6 full-replaces the body, so the declared line must survive it.** | The line is added to Phase 6's **existing** carry-forward table, which exists for exactly this reason and already protects `Tracks #N`/`Refs #N` and the override marker. AC asserts the line survives a Phase 6 regeneration. |
| **`ship/SKILL.md`'s "cite an existing OPEN issue" path writes `Tracks #NNNN` for an issue this PR did not file** — a P4 break by repo-mandated workflow. | **Self-neutralising:** those issues carry `Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps`, are OPEN, and have the `Tracks` companion — the three ADR-155 exemption conditions. The row is counted in `Filing:` and subtracted from `NET`. Documented so it is not rediscovered as a bug. |
| **The exemption's fourth conjunct loses independence** — `Tracks #N` now both admits the row and satisfies condition 4. | Condition 2 (the human-gated `[mandates-filing]` corpus edit, ADR-092) still bounds the blast radius: an agent can only name an already-blessed rule. Named in ADR-206 and the gate header rather than priced at zero. |
| **The new arm raises `NET` on PRs that previously passed.** | That is the fix working — those PRs *were* net-positive. The gate prints all four remedies at the point of failure, and the revived remedy (d) widens the honest exits before anyone reaches for (c). |
| **Over-attribution at scale blocks long-lived PRs monotonically** (reference accumulation grows with PR age) and `Rejected:` prints on one unbounded line. | Cap or wrap `REJECTED_DETAIL` so the denial stays readable; an unreadable denial destroys the `Attributed:` line's value as the in-surface probe. Track the real rate via `gate_body_attributed_count` before considering any tightening. |
| **`--limit 500` truncation now under-counts in a new way** — an issue the PR body names, created after the PR, that fell out of the window. | H5 pins it as not-counted-and-no-crash. The ~4× headroom was measured against the citation arm's hit rate, not the new arm's; recorded as a number to re-check rather than an adjective. Raising the limit would alter a pinned property and is out of scope. |
| **The ADR ordinal collides before merge.** | 206 verified free under **both** `git ls-tree` across 74 origin refs and `git log --all` (205 was free under the first probe and claimed under the second). Re-derived at ship time with a same-edit sweep on any renumber. |
| **This PR passes its own gate by exploiting its own defect.** | AC-D1: hand-reproduce the selector. The plan files zero issues; expected reading `Net: -1`. |

## Test Scenarios

Beyond R1–R3, each carrying its own `cases=$((cases + 1))` at the call site.

1. **Named in the PR body, created BEFORE the PR** → not counted, **and** the `Attributed:` line does
   not name it. (Pins M4 and closes the report-vs-count desynchronisation escape.)
2. **Named only inside a fenced block** → not counted. Assert the `Filing:`/`Net:` block is **present**
   and the number absent — asserting absence alone passes vacuously if the gate produced no output.
   (Pins M5.)
3. **Named via a close keyword** → belongs to `CLOSING`, not `FILED`; assert the `NET` arithmetic so a
   double-count is visible.
4. **The PR's own number in its own body** → not self-counted.
5. **A PR that closes nothing and body-attributes one issue** (`CLOSING_NUMS` empty) → counted, no
   crash.
6. **Two body-attributed issues, first compliant** → both counted. (Pins M2.)
7. **Adjacent references `#1#2` in the PR body** → both extracted. (Pins M6.)
8. **Body-attributed issue with `state: "CLOSED"`** → still counted in `Filing:`, and `rejected` rather
   than `exempt`. (Pins M8, the escape row; twin of the suite's existing `neg "CLOSED issue"`.)
9. **Per-row provenance.** One fixture, one run, two issues — one `cites-pr` and exempt, one `pr-body`
   and rejected — asserting each issue's provenance label **alongside** its verdict on its own line.
   (Pins M3 on the property it targets rather than on collateral detail corruption.)
10. **All filings cite the PR, PR body names none** → `NET` identical to the `origin/main` gate through
    the seam, and no `net-issue-flow-body-attributed` row. (H4 + AC-G7.)
11. **Arm fires** → exactly one `net-issue-flow-body-attributed` row by exact `.rule_id` match. (Pins
    M7; the absence-only assertion cannot.)
12. **PR body names a number absent from `ISSUES_JSON`** → no crash, no fail-open, not counted. (H5.)
13. **PR body with zero `#` characters** → full report block, `exit 1` on a net-positive fixture, no
    `warn`. (H6 — the shape the first draft's bash pipeline broke.)
14. **PR body with an unbalanced fence** → real verdict, no `warn`, arm contributes nothing. (H7.)
15. **`--json` field list** contains `number`, `body`, `createdAt`, `state`. (Phase 4 — the uncovered
    always-pass path.)
