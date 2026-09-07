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

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No `spec.md` exists for this
branch; the domain sweep in `## Domain Review` is the substantive assessment and it found no relevant
business domain.

## Overview

`net-issue-flow.sh` is a BLOCKING gate: a PR must close at least as many issues as it files. It
learns what a PR filed by matching the PR's number inside each issue body. A filing that names the
**originating issue** instead of the PR is therefore never counted, `Filing:` reads low, and a
net-positive PR passes — carrying the authority of a blocking check that succeeded. It fails OPEN,
which is the failure direction the script's own header calls "strictly worse than the advisory
surface it replaces."

This plan adds a second attribution path that reads the evidence already in hand: **the PR's own
body**. An issue created after the PR, named by number in the PR's (fence-stripped) body, and not one
of the PR's close targets, is a filing of that PR by the author's own account. That predicate is
first-party, needs no new API call, and leaves all four pinned call-shape properties of the FILED
query untouched.

The plan makes the design decision explicitly in `## Design Decision`, records the reasoning, and
records the two rejected alternatives — including the transitive widening the brief warned against —
in ADR-205.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited artifact | Check run | Verdict |
|---|---|---|
| Issue #7759 | `gh issue view 7759 --json state,title` | **OPEN**, title matches. Premise holds. |
| `plugins/soleur/skills/ship/scripts/net-issue-flow.sh` | read in full | Exists; the FILED `select` is exactly as quoted in the brief. |
| `plugins/soleur/test/net-issue-flow.test.sh` | read + executed | Exists, 951 lines. Baseline: `ALL PASS (84 assertions)`, `MIN_ASSERTIONS=84`. |
| `.claude/hooks/ship-net-issue-flow-gate.sh` | read in full | Exists; delegates via `bash "$GATE"` and re-implements **no** query logic. |
| `specs/<branch>/run-mutations.sh` | `find knowledge-base/project/specs -name run-mutations.sh` | Exists only at `specs/feat-one-shot-net-issue-flow-mandated-filing-exemption/run-mutations.sh` — a **different** branch. Confirms the brief: separate artifact, not evidence for the query properties. |
| `review-todo-structure.md` `**Source:** PR #<pr_number>` | read | Present, and governs **only** `code-review`-labelled review findings. Confirms the brief. |
| PR #7702 / PR #7841 | `gh pr view` | Both exist. **#7702's data has since been corrected** — the FILED query now returns `[7708,7709,7710,7759]` for it, so the original failing state is no longer reproducible live. Reproduction must be synthetic, in the suite. |
| **PRIOR PLAN (not cited by the brief)** | `grep -rln 7759 knowledge-base/project/plans/` | `2026-09-03-fix-fixture-operand-and-flow-gates-plan.md` carries a full `### PR 4 — the net-issue-flow FILED blind spot (#7759)` design. **PR 4 was never implemented** (`grep -c 'conservation' <gate>` = 0; #7759 still OPEN). See `## Research Reconciliation`. |

**Stale premise found and corrected:** the brief presents #7759 as undesigned. A prior plan designed it
in detail and chose a different predicate. This plan supersedes that PR 4 and says why.

### Property List (Phase 0.6b)

The ask proposes mechanisms; these are the observable properties underneath.

- **P1.** Every issue a PR filed is counted in `Filing:`, whichever number its body happens to cite.
- **P2.** The gate never omits a filing *silently* — an attribution it makes is named, with numbers,
  in the always-emitted block.
- **P3.** The four independently-measured call-shape properties of the FILED query survive: no
  `--search`, no `--label deferred-scope-out`, `--state all`, `--limit 500`.
- **P4.** A sibling PR's filings are never counted against this PR.
- **P5.** The gate's wall-clock stays inside the hook's 25 s ceiling (a timeout returns 124, which the
  hook translates to `exit 0` — a silent always-pass).

### Cut List (Phase 0.6b)

| Mechanism proposed | Property it would buy | Why it is cut |
|---|---|---|
| Sweep all filing producers to emit `Source: PR #<n>` (issue option 1, at scale) | P1 | Already covered — for the sites that matter — by the PR-body arm, which needs no producer to cooperate. Measured cost of doing it anyway: **16 filing sites, 11 emitting no PR number, 5 mutually incompatible citation shapes already in production, 10 consumers**. Its coverage claim is a universal negative that decays with every new filing site. |
| Widen FILED to match issues citing an issue this PR closes (issue option 2) | P1 | Buys P1 while **breaking P4**. Rejected — see `## Design Decision`. |
| A second `jq` invocation to isolate the new predicate | isolation | Breaks P5. The existing pass costs ~1 s over a ~2 MB payload; doubling it spends availability to buy isolation, in the one gate whose failure history is a silent `rc=124`. The arithmetic isolation that actually matters lives in the bash consumer, not in a separate process. |
| Promotion of the new arm to a *second* blocking signal beyond `NET > 0` | — | No second signal is added. The arm feeds the existing `NET` arithmetic; the threshold is unchanged. |

### Measured evidence

**1. The PR-body predicate reproduces the correct filing set on the motivating PR.** PR #7702,
`createdAt=2026-08-26T12:56:25Z`. Fence-stripping its body and extracting `#N` yields
`7553 7702 7708 7709 7710 7759`; subtracting close-keyword targets (`7652`) and the PR's own number
leaves `7553 7708 7709 7710 7759`. Filtering to issues with `createdAt >= 2026-08-26T12:56:25Z`
drops `#7553` (`createdAt=2026-08-13T21:53:53Z`) and leaves exactly **{7708, 7709, 7710, 7759}** —
the correct filing set, from data the gate already fetches.

**2. The defect is still live, today.** Issue **#7889** (`createdAt=2026-09-07T11:17:03Z`) is a
consolidated tracker filed by PR **#7879**. Its body cites `#4859 #7833 #7849 #7853 #7854` and
`grep -c '#7879'` on it returns **0**. Under the current query that PR's `Filing:` reads 0 while the
tracker's own text says "closing 3, filing 1". A third live instance, independent of #7702 and #7841.

**3. The `Mandated-By:` exemption (ADR-155) is currently inert.** Of the 500 most recent issues, **37**
carry a `Mandated-By:` line. Classifying every `#N` they cite in the recent range `[7155,7895]` as
issue-vs-PR (present in the issue list ⇒ issue; absent in that range ⇒ PR) gives **PR-refs = 0 for all
37**. The exemption is computed only over issues that already matched the FILED query, so none of them
is ever a candidate — the whole `[mandates-filing]` corpus derivation, the OPEN check and the
`Tracks|Refs` companion check have had no reachable producer. This is the **fail-closed twin** of the
reported fail-open defect, from the same root cause, and it is invisible because it manifests as a
false BLOCK that an agent resolves with the general override. The PR-body arm repairs it for free:
the `Tracks #<issue>` companion the exemption already demands lives **in the PR body**, which is
exactly what the new arm reads.

**4. The `--limit 500` window is now saturated but still has headroom.** The list returned exactly 500,
newest-first, spanning `#7895@2026-09-07` down to `#7155@2026-08-02` (~36 days). For PR #7702, 124 of
the 500 fell after the PR. The window is ~4× the current filing rate over a 12-day PR lifetime. Not a
defect today; recorded so the next person has the number rather than the adjective.

**5. Baseline timing and suite state.** `bash plugins/soleur/test/net-issue-flow.test.sh` →
`ALL PASS (84 assertions)`. `MIN_ASSERTIONS=84`, set **at** the running count with no slack.

### Applicable institutional learnings

- `knowledge-base/project/learnings/2026-09-04-every-defect-this-session-was-in-the-verification-not-the-fix.md`
  — **names #7759 by number, twice**, as a defect that fired live on that session's own PR: "`net-issue-flow`
  initially PASSED at +0 because a filed issue cited the originating issue rather than the PR… The
  under-count was the comfortable answer and it was wrong." Its prevention line governs this plan's own
  verification: *when a gate returns the comfortable answer, reproduce its selector by hand.* **This PR
  runs through the gate it is fixing** — see AC-D1.
- `.../learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — "A floor indexed to its own input is not a floor… Slack between a floor and the measured value is not
  padding — it is the budget an attacker spends." Governs the `MIN_ASSERTIONS` ratchet (Phase 4).
- `.../learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`
  — "a coverage guard whose oracle is derived from the artifact it guards must count a *second,
  independent* producer of the same fact." The PR body **is** that second, independent producer of
  "what this PR is about"; the filing's own text is the first.
- `.../learnings/2026-08-02-a-guard-that-derives-authority-must-use-the-authoritys-own-parser.md`
  — already honoured by the gate (`lint-rule-bodies.py --emit-mandating-ids`). This plan adds **no new
  corpus reader**, so the rule is satisfied by not introducing the hazard.

### Repo conventions that bind this change

- `cq-write-failing-tests-before` — the suite additions land RED before the gate change.
- `cq-assert-anchor-not-bare-token` / `cq-cite-content-anchor-not-line-number` — assertions and
  citations anchor on content, not line numbers.
- `hr-when-a-command-exits-non-zero-or-prints` — every new failure branch takes its **own** `_fail_open`
  rule id so "never fired" stays distinguishable from "fails open every run".
- `wg-use-closes-n-in-pr-body-not-title-to` — `Closes #7759` in the PR body.
- `rf-review-finding-default-fix-inline` — adjacent findings are fixed inline or acknowledged, not filed,
  so this PR stays net-negative.

## Research Reconciliation — Prior Plan and Brief vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Brief: "The issue lists options … but deliberately does not decide." | True of the issue. **Not** true of the repo: `2026-09-03-fix-fixture-operand-and-flow-gates-plan.md` §PR 4 decided it — option 2's predicate, made **report-only**, precision-conjoined on `Mandated-By:`/`deferred-scope-out`. | Treated as a design input, not a binding decision. This plan **supersedes** PR 4 and records the supersession in ADR-205. |
| Prior plan: the CLOSING-cite predicate must be report-only because "post-PR issues cite those numbers constantly for ordinary reasons — *regression of #500*". | Correct, and it is precisely why option 2 is rejected here. | The noise argument applies to the *transitive* predicate only. The PR-body predicate is first-party and does not carry it, which is why this plan can **count** rather than merely report. |
| Prior plan: "No producer is edited here… An instruction with no file behind it is prose." | Conclusion right, reason now falsified — there **are** named producers (`work/SKILL.md`, `ship/SKILL.md`) emitting `Mandated-By:` with no PR number. | Same conclusion, better reason: the producer sweep is **unnecessary**, not merely unsourced. See Cut List. |
| Prior plan: `FILED=$((FILED+1))` runs per row **before** any verdict is examined, so anything entering the row stream raises `NET`. | Verified in the gate's `while IFS=$'\t' read` loop. | Load-bearing and **intended** here: body-attributed rows are genuine filings and must raise `FILED`. The verdict ladder still applies to them, which is what revives the exemption. |
| Brief: "check whether the fix needs to reach [the hook] too." | The hook delegates and re-implements no query logic; its `REASON` embeds `${OUT}`, so any new report line reaches the operator automatically. Its 25 s budget is dominated by `gh issue list`; this change adds **no** API call. | **No hook change required.** Recorded as a verified finding, not an assumption. The suite's existing `hook remedy needle` assertions must still pass. |
| Issue: `deferred-scope-out` filings "inherit no such requirement". | Confirmed, and broader: 11 of 16 filing sites emit no PR number at all; 5 incompatible citation shapes exist. | Consumer-side fix; producer sweep cut. |

**Adjacent pre-existing finding (acknowledged, not filed).** `/review`'s own self-check probe searches
`gh issue list --label deferred-scope-out --state open -L 200 --search "Ref #<PR_NUMBER>"`, but its
producer (`review.workflow.js`) writes `From code review of PR #${prNum}` and never `Ref #N` — the probe
is dark against its own producer. Out of scope for a blocking-gate PR. Recorded in ADR-205 under
"Known adjacent gaps" with the evidence, so it is discoverable without a tracking issue that would make
this PR net-positive. Per `wg-defer-only-after-inline-triage`, the work phase triages it inline first:
if the fix is a single regex in `review/SKILL.md` and stays inside the cost-of-filing auto-flip
(≤100 lines AND ≤4 files **including** this plan's own file set), fold it in; otherwise leave the
acknowledgement.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (63 open) and matched each planned
path against every issue body with `jq --arg path … contains($path)`.

**None.** No open code-review issue names any of the seven files this plan edits.

## Design Decision

> **The required explicit decision.** Three candidate mechanisms; one adopted, two rejected, with the
> reasoning recorded here and in ADR-205.

### Adopted — a second attribution arm keyed on the PR's own body, which COUNTS

An issue is a filing of PR *N* when it was created after PR *N* **and** either

1. its body or title cites `#N` (existing behaviour, plus a bounded title extension), **or**
2. PR *N*'s fence-stripped body names `#M` where `M` is that issue's number, `M` is not one of the
   PR's close-keyword targets, and `M` is not *N* itself.

Arm 2 is the fix. Its evidence is **first-party**: the PR's author wrote the number into the PR's own
description. Rationale:

- **It changes the failure mode, not just the input data.** The defect class is a blocking gate that
  fails open *silently*. Arm 2 makes the gate unable to omit a filing that the PR itself names — the
  property, not a convention that happens to produce it.
- **It costs no new API call and cannot regress P3.** It reuses `PR_BODY_SCAN` (already fence-stripped
  once, near the top) and the same `ISSUES_JSON` payload. The `gh issue list` argv is unchanged except
  for one added `--json` field; `--search` is still absent, the label filter is still absent,
  `--state all` and `--limit 500` are untouched. P3 is preserved **structurally**, not by assertion.
- **It revives ADR-155's exemption at zero extra cost.** Measured: all 37 `Mandated-By:` issues cite
  zero PR numbers, so the exemption has never been reachable. Their `Tracks #<issue>` companion lives
  in the PR body — exactly what arm 2 reads. The exemption starts working as a side effect.
- **It preserves P4.** A sibling PR's filings are not named in *this* PR's body.
- **It reproduces the motivating case exactly.** Measured above: {7708, 7709, 7710, 7759} for #7702.

**Counting, not report-only.** The prior plan chose report-only because *its* predicate was noisy.
Removing the noise removes the reason. Report-only would still have printed `PASS` on #7702 — it would
have annotated a wrong verdict rather than corrected it, which is the shape the gate's own header
condemns. The residual false-positive (an author's prose naming an unrelated recently-created issue) is
**named in the report**, bounded by the `createdAt` filter and the fence-strip, and resolvable by the
documented override (c) — which exists for exactly this.

**Bounded title extension (separable).** Add `title` to the `--json` field list and match `#N` in title
or body. This closes the two sites that put the PR number in the issue **title** while every consumer
reads `.body` (`ship` Phase 6 decision-challenges; `postmerge` live-verify CANT-RUN). It is
**strictly monotone** — it can only increase `Filing:`, never decrease it — so it cannot introduce a new
always-pass path, which is the failure direction that matters here. Kept separable so review can cut it
without touching arm 2.

### Rejected — widen FILED to match issues citing an issue this PR closes (issue option 2)

Rejected outright.

- **Breaks P4 by construction.** Attribution is *transitive through a third party*. Any issue created
  after this PR that mentions a shared or foundational closed issue counts against this PR — including
  filings made by an entirely different sibling PR that also touches that issue.
- **Ordinary prose is indistinguishable from a filing.** "regression of #500", "see #500 for context".
  The prior plan reached the same conclusion and could only rescue the predicate by making it
  non-blocking and conjoining precision markers — i.e. by giving up the fix.
- **It fails in the closing direction.** A false BLOCK trains the override reflex, which the gate's own
  header warns is how a hatch stops being read.
- **Highest blast radius on the pinned query.** It changes the FILED *semantics*, in the one place where
  four prior defects each made the gate silently always-pass.

### Rejected as the load-bearing mechanism — emit `Source: PR #<n>` at the filing path (issue option 1)

Rejected as the fix; cut entirely rather than kept as a partial complement.

- **It re-instantiates the defect being fixed.** The bug is a consumer depending on a format no producer
  guarantees. Adding one more compliant producer leaves the gate exactly as fail-open for every producer
  not patched — and the failure stays silent.
- **The coverage claim is a universal negative.** "We patched them all" decays with the next filing site
  and with every improvised `gh issue create`. Measured surface: 16 sites, 11 non-compliant, 5
  incompatible shapes (`**Source:** PR #N`, `From code review of PR #N`, `**Source PR:** #N`, `Ref #N`
  expected by two consumers and produced by none, and nothing at all), 10 consumers.
- **It is unenforceable where it matters.** The gate runs at `gh pr ready` / `gh pr merge`, by which time
  the issues already exist. A missing line has nothing to detect it.
- **Arm 2 already covers the sites that matter**, including the two `Mandated-By:` producers, without any
  producer cooperating. Adding the line as well would be belt-and-braces on a strap that already holds.

## User-Brand Impact

**If this lands broken, the user experiences:** a `gh pr ready` / `gh pr merge` that is denied with a
`net-issue-flow: BLOCKED` message naming issue numbers the user does not recognise as their own filings
— a false block on a correct PR. The documented override (`<!-- gate-override: net-issue-flow -->` plus
a per-issue justification, or `SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1`) clears it in one line, and the gate
prints both remedies in the denial itself.

**If this leaks, the user's data/workflow is exposed via:** no new exposure. The change reads issue
numbers, titles, bodies and timestamps already fetched from the same repository the gate already
queries, and writes nothing outside stdout and the existing incident ledger. No credential, no new
network egress, no new persistence.

**Brand-survival threshold:** `aggregate pattern`.

Reasoning: the harm this defect causes is cumulative — an issue queue growing by roughly the
under-counted difference across many PRs — not a single-user incident. The worst *new* failure mode is
workflow friction with a one-line documented remedy printed at the point of failure, and no user data is
involved. No `requires_cpo_signoff`. `user-impact-reviewer` is therefore not mandatory at review; the
standard panel applies.

## Implementation Phases

### Phase 1 — RED: pin the defect before touching the gate

Per `cq-write-failing-tests-before`, every case below is added to
`plugins/soleur/test/net-issue-flow.test.sh` **first** and confirmed RED against the unmodified gate.
Each assertion call site carries its own `cases=$((cases + 1))` — never inside `pass()`/`fail()`, never
inside `$( )` (the suite's conservation check `passes + fails == cases` depends on that placement).

Fixtures follow the existing seam: a stub `gh` on `PATH` dispatching on argv, `run_gate` exporting
`PR_BODY_FILE` / `ISSUE_LIST_FILE`, PR number `999`, `PR_CREATED_AT_FIXTURE` as the boundary.

1. **R1 — the #7702 reproduction.** Issue `#7101` body cites `#8000` (the originating issue), never
   `#999`; PR body names `#7101` in prose. Expect `Filing: 1` and `exit 1`. RED today (`Filing: 0`,
   `exit 0`).
2. **R2 — the exemption revival.** Issue `#7102` body carries `Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps`
   on its own line, `state: "OPEN"`, and cites only `#8000`; PR body carries `Tracks #7102`. Expect the
   issue to appear in `Filing:` **and** be reported `exempt` via that rule id. RED today (never a
   candidate, so never exempt).
3. **R3 — title arm.** Issue `#7103` with `title` citing `#999` and a body citing nothing. Expect
   counted. RED today.
4. **R4 — report line.** The always-emitted block names the body-attributed numbers on their own
   labelled line. RED today (no such line).

### Phase 2 — GREEN: the gate change

Single file: `plugins/soleur/skills/ship/scripts/net-issue-flow.sh`.

**2a. Derive the PR-body-named set, next to the existing CLOSING extraction.** `PR_BODY_SCAN` is already
computed once near the top and is the fence-stripped body every consumer must see. Reuse it — do not
re-strip.

```bash
# Numbers the PR body NAMES, minus its close targets and its own number. This is
# first-party evidence of authorship: the PR's author wrote the number into the
# PR's own description. Derived from PR_BODY_SCAN so the fence-strip governs this
# arm too -- a number inside a quoted gate transcript must not become a filing.
ALL_REFS_JSON="$(printf '%s\n' "$PR_BODY_SCAN" \
  | grep -oE '(^|[^0-9A-Za-z])#[0-9]+' | grep -oE '[0-9]+' \
  | jq -R -s -c 'split("\n") | map(select(length > 0) | tonumber) | unique' 2>/dev/null)" \
  || _fail_open "could not encode the PR-body reference set"
CLOSING_JSON="$(printf '%s\n' "$CLOSING_NUMS" \
  | jq -R -s -c 'split("\n") | map(select(length > 0) | tonumber) | unique' 2>/dev/null)" \
  || _fail_open "could not encode the closing set"
NAMED_JSON="$(jq -n -c --argjson a "$ALL_REFS_JSON" --argjson c "$CLOSING_JSON" \
  --arg pr "$PR_NUMBER" '$a - $c - [($pr | tonumber)]' 2>/dev/null)" \
  || _fail_open "could not derive the PR-body-named set"
```

Each branch fails OPEN with its **own** message, and each takes a distinct rule id under
`net-issue-flow-body-attribution-*` (still `net-issue-flow*`-prefixed, so the aggregator's orphan
exemption covers it) — `hr-when-a-command-exits-non-zero-or-prints` and this gate's own timeout
post-mortem both require that "never fired" stays distinguishable from "fails open every run".

**2b. Add `title` to the `--json` field list.** `--json number,title,body,createdAt,state`. Verified
against the suite's Case 8 assertions: they test the `issue list` argv for `--limit 500` (present),
`--search` (absent), `--state all` (present) and `deferred-scope-out` (absent). None inspects the
`--json` field list, and the added field introduces none of those tokens. P3 is preserved.

**2c. Widen the `select` as a sibling disjunction, not a new pipeline stage.** Keeping it a sibling
filter over the same array bounds the shared-failure-domain risk — a malformed new predicate cannot take
down the FILED pipeline it sits beside.

```jq
| [ .[]
    | select((.createdAt // "") >= $since)
    | . as $i
    | select(
        (($i.body  // "") | test("(^|[^0-9A-Za-z])#" + $pr + "([^0-9]|$)"))
        or (($i.title // "") | test("(^|[^0-9A-Za-z])#" + $pr + "([^0-9]|$)"))
        or (($named | index($i.number)) != null)
      )
  ]
```

with `--argjson named "$NAMED_JSON"` added to the existing invocation. The `createdAt` guard stays
**first** and governs all three arms — a PR-body reference to an older issue is context, not a filing.

**2d. Carry provenance in the row, with the free-text field last.** The row becomes
`[number, verdict, attribution, detail]` and the consumer becomes
`while IFS=$'\t' read -r _num _verdict _attr _detail`. **Attribution goes before `detail`, not after:**
`read` assigns the remainder of the line to its final variable, and `detail` is the only field carrying
free text. `attribution` is one of `cites-pr` / `pr-body`, computed as
`(if (($i.body // "") | test(…)) or (($i.title // "") | test(…)) then "cites-pr" else "pr-body" end)`.

**2e. Report, then emit telemetry.** Add one line to the always-emitted block, printed only when the
set is non-empty, and keep `Filing:` as the true total:

```
  Attributed: 2  (#7708 #7709 — named in the PR body, citing the issue not the PR)
```

Then `_emit_as net-issue-flow-body-attributed applied "pr=${PR_NUMBER} attributed=<n>"`, so the rate at
which the narrow query under-counts becomes a measured number rather than an adjective. A clean run —
every filing citing the PR — must emit **no** such row; AC-G7 asserts that, because a telemetry row that
fires unconditionally measures nothing.

**Do not touch:** the `NET > 0` threshold, the override marker, the fence-strip, the merge-base corpus
read, the `lint-rule-bodies.py` derivation, or the `Filing:`-keeps-its-true-count contract.

### Phase 3 — the exemption path, verified rather than assumed

No code change. Confirm by test (R2) that a body-attributed row flows through the unchanged verdict
ladder — `Mandated-By:` claim → `[mandates-filing]` in the merge-base corpus → issue OPEN → `Tracks|Refs`
companion in the PR body — and is subtracted from `NET` while `Filing:` keeps its true count.

### Phase 4 — ratchet the anti-vacuity floor

Run the suite, read the reported assertion count, and set `MIN_ASSERTIONS` **at** that number. Not below
it, not rounded down: per ADR-193 and the four-rounds learning, "slack between a floor and the measured
value is not padding — it is the budget an attacker spends." The floor ratchets upward only.

### Phase 5 — documentation

- `plugins/soleur/skills/ship/SKILL.md` — the section documenting the four query properties gains the
  attribution arm: what it matches, that it adds no API call, and that `Filing:` still keeps its true
  count. The four properties stay stated verbatim.
- `plugins/soleur/skills/ship/scripts/net-issue-flow.sh` header — extend the "Why the FILED query looks
  the way it does" block with the fifth defect and its remedy, in the same measured-defect voice.
- ADR-205 (see below).

### Phase 6 — verification, including the dogfooding check

Run the full suite. Then run the gate against **this** PR and, per the 2026-09-04 learning, **hand-
reproduce the FILED selector rather than trusting the verdict**. This PR closes #7759 and is planned to
file nothing, so the expected reading is `Closing: 1 / Filing: 0 / Net: -1 / PASS`. If any issue is filed
after all, its body must cite this PR's number, and the hand-reproduction must confirm the gate sees it —
a fix PR that passed by exploiting its own defect is the one outcome this plan must not produce.

## Files to Edit

| Path | Change |
|---|---|
| `plugins/soleur/skills/ship/scripts/net-issue-flow.sh` | Phases 2a–2e: named-set derivation, `title` field, sibling disjunction, provenance field, report line, telemetry, header block. |
| `plugins/soleur/test/net-issue-flow.test.sh` | Phase 1 cases R1–R4 plus the bounding/control cases in `## Test Scenarios`; `MIN_ASSERTIONS` ratchet (Phase 4). |
| `plugins/soleur/skills/ship/SKILL.md` | Phase 5: document the attribution arm alongside the four properties. |

**Deliberately NOT edited**, each verified rather than assumed:

- `.claude/hooks/ship-net-issue-flow-gate.sh` — delegates via `bash "$GATE"`, re-implements no query
  logic, embeds `${OUT}` so the new report line reaches the operator unchanged, and its 25 s budget is
  dominated by `gh issue list`, which this change does not add to. The suite's existing
  `hook remedy needle` assertions must still pass unmodified — that is the check that this file was
  genuinely left alone.
- Every filing producer (`work/SKILL.md`, `review/workflows/review.workflow.js`, `compound/SKILL.md`,
  `brainstorm/SKILL.md`, `postmerge/SKILL.md`, …) — see Cut List.
- `plugins/soleur/skills/review/references/review-todo-structure.md` — its convention is unchanged and
  still correct for `code-review` findings.

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-205-attribute-a-prs-filings-by-the-prs-own-body.md` | The attribution-model decision and its rejected alternatives. |
| `knowledge-base/project/specs/feat-one-shot-7759-net-issue-flow-filing-cites-issue/tasks.md` | Task breakdown. |

## Architecture Decision (ADR/C4)

Detection fires: this changes a **resolver / trust-boundary rule** — who decides that an issue belongs
to a PR — and it **extends ADR-155**, whose exemption apparatus the measurement shows to be inert.

### ADR

**ADR-205 — attribute a PR's filings by the PR's own body, not only by what the filing cites.**
Provisional ordinal: verified free across all **74** `origin/*` refs
(`ADR-205: 0 ref-hits`; 201 and 204 are claimed on branches, 203 is the highest on `main`).
Per `/ship`'s ADR-Ordinal Collision Gate this number is **not final** — re-derive it against a freshly
fetched `origin/main` immediately before merge and after every Phase 7 sync, and when renumbering, sweep
`grep -rn 'ADR-205' knowledge-base/project/{plans,specs}/feat-one-shot-7759-*/` in the same edit so this
plan, `tasks.md` and any AC naming the ordinal move together.

Content: the two-arm attribution model; the first-party-evidence rationale; **Alternatives Considered**
carrying (a) the producer-convention sweep and (b) the transitive closed-issue widening, each with the
measurement that rejected it — so a future agent reaching for option 2 finds it already weighed; the
supersession of `2026-09-03-…-plan.md` §PR 4 and why the report-only choice does not survive a
less-noisy predicate; the measured inertness of ADR-155's exemption and its revival; and a **Known
adjacent gaps** section recording the `/review` `Ref #N` probe that is dark against its own producer.

### C4 views

**No C4 impact.** Enumerated against all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` (691 / 74 / 54 lines),
read rather than keyword-grepped:

- **External human actors:** none added. `contributor = actor "Contributor / PR Author" #external` and
  `founder = actor "Founder / Operator"` are already modelled; no actor gains or loses reach.
- **External systems:** none added. `github = system "GitHub" #external` is already modelled and the gate
  already calls `gh issue list` / `gh pr view` against it. No new vendor, no new endpoint family.
- **Containers / data stores:** none. The change is confined to one shell script inside
  `plugin = system "Soleur Plugin"`, whose L3 granularity is one component per skill
  (`ship = component "ship skill"`); a script inside a skill sits one level **below** any modelled
  element.
- **Actor↔surface access relationships:** none change. No element description is falsified — the `ship`
  component's description does not enumerate its gates.

### Sequencing

None. The decision is true the moment the change lands; nothing is soak-gated, so ADR-205 is authored as
`accepted`, not `adopting`.

## Guard Contract

### Guard 1 — the FILED attribution arm

**Property.** Every issue created after PR *N* that PR *N* filed is counted in `Filing:`, whether the
issue cites the PR or PR *N*'s own body names the issue — and no issue that PR *N* did not file is
counted.

**Assembly.** The property quantifies over the **two injection points into `FILED`**, and there are
exactly two — this is structural, not a snapshot of today's members:

1. the `select(...)` in the single `jq` pass over `ISSUES_JSON`, which decides *which issues become
   rows*; and
2. the `while IFS=$'\t' read` loop in `net-issue-flow.sh`, whose `FILED=$((FILED + 1))` executes once per
   row **before** any verdict is examined — so every row that reaches it raises `NET`.

A guard scoped to (1) alone is the defect, not a partial fix: a row emitted by the widened `select` that
the loop mis-parses (for example because a free-text field was placed before the provenance field)
either disappears from the count or corrupts the verdict, with the `select` still perfectly correct. The
chokepoint both arms must flow through is the TSV row contract between them; that contract — field
count, and free text last — is what the mutation matrix targets.

Inputs the property depends on: `PR_BODY_SCAN` (fence-stripped once, near the top — the only PR-body
form any consumer may read), `PR_CREATED_AT`, and `ISSUES_JSON`. No fourth input is introduced.

**Mutation matrix.** Each row is derived from the design, not from the implementation as it happens to
be shaped. Every row MUST drive the suite RED.

| # | Mutation | Why it must red |
|---|---|---|
| M1 | Delete the `or (($named \| index($i.number)) != null)` disjunct from the `select`. | The whole arm. R1 must fail. This is the defect restored. |
| M2 | Replace `NAMED_JSON` derivation with `NAMED_JSON='[]'` — the arm still dispatches, still runs, and attributes nothing. | **Targets the guard's own dispatch.** A gate that reports "0 attributed" and exits 0 is vacuous; without this row the suite could pass on an arm that never fires. |
| M3 | Add a **second** body-attributed issue to R1's fixture after a compliant first, and stop the derivation at the first match (`$a - $c - [...] | .[0:1]`). | A check that stops at the first member is itself an instance of the class this gate exists to catch. |
| M4 | Move the provenance field **after** `detail` in the row (`[number, verdict, detail, attribution]`) while leaving `read -r _num _verdict _attr _detail` unchanged. | A **reorder**, not a delete: the `select` stays correct and the row count stays right, so any assertion that only counts rows stays green. Only a case reading the *verdict and provenance of a specific issue* reds. This is the injection-point-2 row. |
| M5 | Drop the `select((.createdAt // "") >= $since)` guard, or move it *after* the disjunction. | A PR-body reference to a pre-existing issue becomes a filing. Bounds the arm against over-attribution (P4). Requires a case observing an older named issue. |
| M6 | Compute the named set from the **raw** `PR_BODY` instead of `PR_BODY_SCAN`. | A number inside a fenced gate transcript pasted into the PR description becomes a filing — the same self-override class the override marker is already guarded against, reached through the new arm. |
| M7 | Change `_emit_as net-issue-flow-body-attributed` to reuse the shared `net-issue-flow` rule id. | Collapses "the narrow query under-counted here" into "the gate ran", which is the exact distinction this gate's header condemns losing. |

**Harness rows.** At least one mutation of the **suite**, and at least one must-PASS non-canonical input.

| # | Row | Why it must red / pass |
|---|---|---|
| H1 | **RED.** Stub `fail()` to a no-op in the suite. | The conservation identity `passes + fails == cases` must break and report directly via `printf >&2` + `exit 1`, never through `fail()` — a check routed through the suspect cannot witness the suspect. |
| H2 | **RED.** Delete one new assertion's `cases=$((cases + 1))` while keeping its verdict. | The conservation check must fire on the over-count arm and name it a harness bug, not a product failure. |
| H3 | **RED.** Lower `MIN_ASSERTIONS` below the post-change count, then delete a case. | Proves the floor is set **at** the running count and that slack is what absorbs a deleted case. |
| H4 | **must-PASS, non-canonical.** A PR whose filings **all** cite the PR (the pre-change shape), with a PR body that names none of them. | `NET` must be **identical** to the pre-change gate's `NET` on the same fixture. Distinguishes "the arm is correct" from "the arm rejects nothing / accepts everything"; RED rows alone cannot see a guard that over-accepts. |
| H5 | **must-PASS, non-canonical.** A PR body naming `#M` where `#M` does not appear in `ISSUES_JSON` at all (a PR number, or an issue outside the 500-item window). | Must not crash, must not fail open, must simply not count. Bounds the arm against a missing-lookup panic. |

## Observability

```yaml
liveness_signal:
  what: "net-issue-flow gate rows in the incident ledger, keyed by rule_id. A run emits exactly one of
         applied|deny|bypass|warn under `net-issue-flow`, plus `net-issue-flow-body-attributed`
         (applied) only when the new arm attributed at least one issue."
  cadence: "once per `gh pr ready` / `gh pr merge` invocation, plus every explicit /ship Phase 5.5 run"
  alert_target: "rule-metrics-aggregate.sh weekly rollup (counts deny/bypass/applied/warn only)"
  configured_in: ".claude/hooks/lib/incidents.sh (sourced by the gate); rule ids are emitted from
                  plugins/soleur/skills/ship/scripts/net-issue-flow.sh"

error_reporting:
  destination: "the incident ledger via emit_incident, under net-issue-flow* rule ids"
  fail_loud: "Every fail-open path prints its reason to stdout AND emits a `warn` row -- never
              `transient`, which the aggregator does not count. Each new failure branch takes its own
              rule id (net-issue-flow-body-attribution-*), so `never fired` stays distinguishable from
              `fails open every run`."

failure_modes:
  - mode: "The PR-body reference set cannot be encoded (jq failure, malformed body)."
    detection: "stdout carries `could not encode the PR-body reference set`; a `warn` row under
                net-issue-flow-body-attribution-encode."
    alert_route: "weekly rule-metrics rollup; a non-zero count means the arm is dark on some PRs."
  - mode: "The arm dispatches but attributes nothing on every run (vacuous arm)."
    detection: "`net-issue-flow-body-attributed` count is 0 across a week in which `net-issue-flow`
                applied/deny rows are non-zero -- the arm ran and never fired."
    alert_route: "weekly rollup; mutation row M2 is the pre-ship proof the arm CAN fire."
  - mode: "The gate exceeds the hook's 25 s ceiling and the hook translates rc=124 to exit 0."
    detection: "`net-issue-flow-timeout` warn row, emitted by the hook ABOVE its `-eq 1` early exit."
    alert_route: "weekly rollup. This change adds no API call, so the dominant cost
                  (`gh issue list --limit 500`) is unchanged; AC-G8 measures wall clock."
  - mode: "The arm over-attributes -- an unrelated recently-created issue named in PR prose."
    detection: "the always-emitted `Attributed:` line names every such number, so the misattribution is
                visible in the denial text the hook surfaces via ${OUT}."
    alert_route: "self-reporting at the point of failure; remedy (c) is printed in the same output."

logs:
  where: "gate stdout (captured verbatim into the PreToolUse denial reason) + the incident ledger"
  retention: "ledger retention as configured by .claude/hooks/lib/log-rotation.sh; unchanged"

discoverability_test:
  command: "bash plugins/soleur/test/net-issue-flow.test.sh"
  expected_output: "net-issue-flow.test.sh: ALL PASS (<N> assertions)   # N == the ratcheted MIN_ASSERTIONS"
```

No `credentials_required`: the suite runs entirely against the stub `gh` and stub `git` seams and needs
no token. The first token is `bash`, on preflight Check 10's `PROBE_VERB_ALLOWLIST`, and the command
invokes no remote shell, so the Phase 2.9 reject condition on the `ssh` verb does not fire.

**Affected-surface note (Phase 2.9.2).** This is observability layer 7 — code that executes on a
customer's self-hosted CLI, where the operator cannot inspect the run. The `Attributed:` line is the
in-surface probe: it is emitted **from** the gate, names the discriminating numbers, and is carried into
the hook's denial text by `${OUT}`, so the two competing hypotheses ("the gate under-counted" vs "there
was nothing to count") are separable from a single run's output rather than by re-deriving the query.

## Acceptance Criteria

### Pre-merge (PR)

- **AC-G1.** `bash plugins/soleur/test/net-issue-flow.test.sh` exits 0 and prints
  `net-issue-flow.test.sh: ALL PASS (<N> assertions)`.
- **AC-G2.** `MIN_ASSERTIONS` equals the reported `<N>` exactly — no slack. Verify by reading the
  constant and the run's final line together.
- **AC-G3.** The four call-shape properties still hold. Re-run the suite's Case 8 assertions and confirm
  all four pass: `--limit 500` present, `--search` absent, `--state all` present, `deferred-scope-out`
  absent from the `issue list` argv.
- **AC-G4.** R1 (the #7702 shape) reds against the pre-change gate and greens after. Demonstrate both
  directions — `git stash` is forbidden in worktrees, so prove it by running the new suite against the
  gate at `origin/main` via `git show origin/main:plugins/soleur/skills/ship/scripts/net-issue-flow.sh`
  written to a temp path and invoked as `$GATE`.
- **AC-G5.** R2 passes: a body-attributed issue carrying `Mandated-By:` with a `Tracks #N` companion is
  reported `exempt`, and `Filing:` still shows its true (unreduced) count.
- **AC-G6.** Every mutation row M1–M7 drives the suite RED; every harness row H1–H3 drives it RED; H4 and
  H5 pass. Record the observed verdict per row.
- **AC-G7.** A fixture in which every filing cites the PR emits **no** `net-issue-flow-body-attributed`
  row — the telemetry is conditional, not unconditional.
- **AC-G8.** Wall clock for one gate invocation stays well inside the hook's 25 s ceiling. Measure with
  `bash -c 'time ...'` against the stub seam and record the number; the change adds no `gh` call, so the
  expected delta is within noise.
- **AC-G9.** The hook file is byte-unchanged: `git diff --stat origin/main -- .claude/hooks/ship-net-issue-flow-gate.sh`
  is empty, and the suite's four `hook remedy needle` assertions still pass.
- **AC-G10.** `ADR-205-*.md` exists, its ordinal is re-verified free across all `origin/*` refs at ship
  time, and its `## Alternatives Considered` names both rejected options with the measurement that
  rejected each.
- **AC-G11.** `ship/SKILL.md` still states all four query properties verbatim **and** documents the
  attribution arm.
- **AC-G12.** Every `knowledge-base/` path this plan cites resolves:
  `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'`
  prints nothing.

### Dogfooding

- **AC-D1.** Run the gate against this PR. Expected `Closing: 1 (#7759) / Filing: 0 / Net: -1 / PASS`.
  Then **hand-reproduce the FILED selector** against the live issue list rather than trusting the
  verdict, per the 2026-09-04 learning: a fix PR that passes by exploiting its own defect is the one
  outcome this plan must not produce. If any issue is filed after all, its body must cite this PR's
  number and the hand-reproduction must confirm the gate sees it.
- **AC-D2.** The PR body carries `Closes #7759` (body, not title).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Assessed against all eight
domains: the change is confined to a shell gate and its test suite inside `plugins/soleur/`, reads only
issue metadata the gate already fetches from the repository it is already querying, adds no user-facing
surface, no persistent store, no vendor, no cost, and no processing of personal data.

**Product/UX Gate:** not applicable. The mechanical UI-surface override was evaluated against both
`## Files to Edit` and `## Files to Create`: no path matches `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`, or any term on the shared UI-surface list. Product tier is **NONE** by both the
mechanical check and the semantic sweep, so no `.pen` wireframe is required
(`wg-ui-feature-requires-pen-wireframe` does not fire).

**GDPR / Compliance Gate (Phase 2.7):** skipped. No regulated-data surface — no schema, migration, auth
flow, API route or `.sql` file. The four expansion triggers were each checked and none fires: (a) no
LLM/external-API processing of operator-session data; (b) threshold is `aggregate pattern`, not
`single-user incident`; (c) no new cron reading `learnings/` or `specs/`; (d) no **new** artifact
distribution surface — this modifies a script inside an already-shipped plugin payload.

**Infrastructure-as-Code Gate (Phase 2.8):** skipped. No server, service, cron, secret, DNS record, cert,
firewall rule or vendor account is introduced. Detection scan over the plan draft and the feature
description found none of the trigger phrases.

**Encryption Posture Gate (Phase 2.11):** skipped. No persistent store and no new cross-component
connection. No `.tf`, migration, cloud-init or compose file in the edit set.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| **Over-attribution: a PR body names an unrelated recently-created issue in prose, and it is counted.** | Bounded by three conjuncts (`createdAt >= PR createdAt`, fence-stripped body, close-targets and self excluded), **named** in the `Attributed:` line so it is never silent, and resolvable by the documented override (c). Mutation M5/M6 pin the bounds; H5 pins the missing-lookup case. This is the accepted residual of the decision, recorded in ADR-205. |
| **The new arm raises `NET` on PRs that previously passed, so merges start blocking.** | That is the fix working — those PRs *were* net-positive. The gate prints all four remedies at the point of failure, and remedy (a) fix-inline plus the newly-revived remedy (d) mandated-filing exemption both widen the honest exits before anyone reaches for (c). |
| **A malformed new predicate takes down the whole `jq` pass, wedging the gate.** | The predicate is a **sibling disjunct over the same array**, not a stage inside the FILED pipeline, so its blast radius is bounded. Every failure branch fails OPEN with its own rule id, and the suite's fail-open cases already assert the announced-not-silent contract. |
| **Timeout regression pushes the hook past 25 s into a silent `exit 0`.** | No new API call; the dominant cost (`gh issue list --limit 500`) is unchanged, and the added work is one extra `jq -n` plus two small encodes. AC-G8 measures it rather than asserting it. |
| **The ADR ordinal collides before merge.** | 205 verified free across all 74 `origin/*` refs, but treated as provisional: re-derived at ship time and after every Phase 7 sync, with a same-edit sweep of this plan and `tasks.md` on any renumber. |
| **This PR passes its own gate by exploiting its own defect.** | AC-D1: hand-reproduce the selector rather than trusting the verdict. The plan files zero issues, so the expected reading is `Net: -1`. |
| **`--limit 500` is now saturated (500 returned, ~36-day window).** | Not a defect at current rates — 124 of 500 fell inside PR #7702's 12-day lifetime, ~4× headroom. Measured and recorded here so the next person has the number; no change made, since raising the limit would alter a pinned call-shape property. |

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| Widen FILED to match issues citing an issue this PR closes (issue option 2) | **Rejected** | Transitive third-party attribution breaks P4; ordinary cross-reference prose is indistinguishable from a filing; fails in the closing direction, training the override reflex; highest blast radius on the pinned query. |
| Sweep every filing producer to emit `Source: PR #<n>` (issue option 1) | **Rejected as the mechanism, cut entirely** | Re-instantiates the defect (consumer depends on an unguaranteed convention); coverage is a universal negative over 16 sites with 5 incompatible shapes; unenforceable at gate time; and arm 2 already covers the sites that matter. |
| Option 2's predicate, report-only and non-blocking (the prior plan's §PR 4) | **Superseded** | Its report-only choice was forced by its predicate's noise. A first-party predicate removes the noise and therefore the reason. Report-only would have printed `PASS` on #7702 — annotating a wrong verdict instead of correcting it. |
| A second `jq` invocation for isolation | **Rejected** | Doubles the pass over a ~2 MB payload to buy isolation, in the one gate whose failure history is a silent `rc=124`. The arithmetic isolation that matters lives in the bash consumer. |
| Raise `--limit` above 500 to widen the window | **Rejected (out of scope)** | Would alter a pinned call-shape property for a problem that is not yet real (~4× headroom measured). Recorded in Risks with the number. |
| Match the PR number in the issue **title** as well as the body | **Adopted, separable** | Strictly monotone — can only increase `Filing:`, never decrease — so it cannot create a new always-pass path. Closes the two sites that put the PR number in the title while every consumer reads `.body`. Kept separable so review can cut it independently of arm 2. |

## Test Scenarios

Beyond R1–R4 (Phase 1), the suite gains the bounding and control cases the mutation matrix requires.
Each carries its own `cases=$((cases + 1))` at the call site.

1. **Named in the PR body, created BEFORE the PR** → not counted. (Pins M5.)
2. **Named in the PR body only inside a fenced block** → not counted. (Pins M6.)
3. **Named in the PR body via a close keyword** → belongs to `CLOSING`, not `FILED`; assert the `NET`
   arithmetic explicitly so a double-count is visible.
4. **The PR's own number appearing in its body** → not self-counted.
5. **Two body-attributed issues, the first compliant** → both counted. (Pins M3.)
6. **Body-attributed row with a valid `Mandated-By:` + `Tracks #N`** → `exempt`, `Filing:` unreduced.
   (Pins the revived exemption; also pins M4, since it reads a specific issue's verdict *and*
   provenance.)
7. **Title cites the PR, body cites nothing** → counted. (Pins the separable title arm.)
8. **All filings cite the PR, PR body names none** → `NET` identical to the pre-change gate, and **no**
   `net-issue-flow-body-attributed` telemetry row. (H4 + AC-G7.)
9. **PR body names a number absent from `ISSUES_JSON`** → no crash, no fail-open, not counted. (H5.)
10. **`Attributed:` line present with the right numbers when the arm fires, absent when it does not.**
11. **Call-shape re-assertion** — the four Case 8 properties after the `--json` field addition.
