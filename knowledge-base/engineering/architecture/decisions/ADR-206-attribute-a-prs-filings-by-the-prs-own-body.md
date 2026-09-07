# ADR-206 — Attribute a PR's filings by the PR's own body

- **Status:** Accepted
- **Date:** 2026-09-07
- **PR:** #7896
- **Issue:** #7759
- **Related:** [ADR-155](./ADR-155-cross-gate-exemption-markers-in-the-rule-corpus.md) (the
  mandated-filing exemption this revives, and whose conjuncts it collapses),
  [ADR-193](./ADR-193-anti-vacuity-floor-contract.md) (why the
  suite floor is reported outside `fail()`),
  [ADR-131](./ADR-131-gate-moratorium-and-meta-work-budget.md) (this adds no new gate — it
  corrects an existing one)

## Context

`net-issue-flow.sh` blocks a PR that files more issues than it closes. It answers "which issues
did this PR file?" from the ISSUE side only: an issue counts when its body cites `#<pr>`.

That question has no answer on the issue side when the filing cites the **originating issue**
instead of the PR — which is the common shape, because an agent filing a follow-up naturally
cites the issue it was working on. The gate then under-counts `Filing:` and **passes a
net-positive PR**, which is the fifth member of a defect family the gate's own header
enumerates: each one makes a blocking gate silently always-pass, "strictly worse than the
advisory surface it replaces, because it also carries the authority of having passed."

Measured live, twice:

| PR | Before | After the filings named the PR |
|---|---|---|
| #7702 | `Filing: 0 / Net: -1 / PASS` | `Filing: 3 / Net: +2 / BLOCKED` |
| #7841 | `Filing: 1 / PASS` | `Filing: 2 / Net: +1 / BLOCKED` |

Same PR, same filings, opposite verdict — the difference is only whether the filings happened to
name the PR rather than the issue.

## Decision

**Attribute from the PR's own body, and split counting from reporting.**

1. **COUNTED — the declared filing line.** An issue is a filing of PR *N* when it postdates *N*
   **and** either its body cites `#N` (the original arm, unchanged) **or** its number appears on
   *N*'s `Filed:` / `Tracks:` / `Refs:` line, minus close targets and *N* itself.
2. **PRODUCED — one line, one place.** `/ship` Phase 6 emits `Filed: #A #B #C` into the body it
   generates, and the line joins Phase 6's existing carry-forward table. That table exists because
   Phase 6 **full-replaces** the body and two blocking gates read markers living only there.
3. **REPORTED, never counted — the conservation line.** Every OTHER post-PR number the body
   mentions prints as `Possible unattributed filings:` and contributes to nothing — not
   `Filing:`, not `Exempt:`, not `NET`.

Both sets are derived inside the single existing `jq` pass, from the **fence-stripped** body.

### Why the split, rather than counting every mention

A declared line is an **assertion of the filing relationship**. A prose mention is an assertion of
relevance, and the two are measurably different. Over 300 PRs, counting bare `#N`:

| Measurement | Result |
|---|---|
| PRs where a bare-`#N` arm adds attributions | 56 / 300 (122 attributions) |
| Issues attributed to **two different PRs** (so at least one is wrong) | **9** |
| PRs flipping PASS → BLOCK | **25 / 300 (8.3%)**, unmeasured false-positive share |

**Independently replicated 2026-09-07 (#7896 review), 60 most-recent merged PRs against the
500-issue window.** The lens assigned to verify this table died on a quota, so it was re-run by
hand. The *conclusion* holds; the *rates* are sample-dependent and should not be quoted as
constants:

| Measurement | ADR (300 PRs) | Replication (60 PRs) |
|---|---|---|
| PRs where a bare-`#N` arm adds attributions | 56/300 (18.7%) | 20/60 (33%) |
| Attributions added | 122 | 65 |
| Issues attributed to two different PRs | 9 | 1 |

The replication is denser in cross-references (a more recent, more interlinked window), which is
why the per-PR rates are higher. What matters is that the failure mode reproduces with a named
instance: **issue #7869 is attributed to both PR #7838 and PR #7840**, so at least one attribution
is wrong. That is P4 violated under bare-`#N` counting, on live data, independent of the original
sample.

P4 — *"a sibling PR's filings are never counted against this PR"* — is a stated guard property,
and under bare-`#N` counting it is measurably false. The conservation line keeps the information
without giving prose authority: the blind spot becomes **self-reporting** rather than silent.

### Failure direction

It fails **CLOSED**. An unbalanced fence makes the stripped body empty, so both sets are empty and
neither arm contributes. It cannot become an escape hatch.

## Alternatives Considered

**Widen FILED to match issues citing an issue this PR closes (the issue's option 2).** Rejected.
Attribution becomes transitive through a third party, so a sibling PR's filings count against this
one whenever both touch a shared closed issue — breaking P4 by construction. Ordinary prose
("regression of #500") is also indistinguishable from a filing claim, and a false BLOCK trains the
override reflex.

**Sweep a `Source: PR #N` line into every filing site (the issue's option 1).** Rejected at the
producer sites, adopted at one. Two of the reasons first recorded here were wrong; the corrected
version is below.

*The count.* This said "**sixteen** filing sites … 11 of the 16 emit no PR number". Re-measured
2026-09-07 (`git grep -l 'gh issue create' -- 'plugins/soleur/skills/**/*.md'`): **19 files, 48
invocations**, of which 14 files carry no PR reference anywhere near the create. The direction of
the argument is if anything stronger than claimed, but the specific figure was not reproducible,
so it is replaced with the command that produces it.

*The "incompatible shapes" clause is struck.* It said the 5 sites that do cite a PR "use mutually
incompatible citation shapes", offered as a cost. It is not one. The pre-existing arm matches a
**bare `#N`** anywhere in the issue body — `test("(^|[^0-9A-Za-z])#" + $pr + "([^0-9]|$)")` — so
`**Source:** PR #N`, `From code review of PR #N`, `**Source PR:** #N` and `Ref #N` all already
satisfy it identically. Shape variation costs this consumer nothing, and citing it as evidence
against the alternative was an error.

*The decisive reason was never recorded, and it is this.* `/work` files follow-ups at a site the
skill itself documents as running **before** `/ship` (`work/SKILL.md`: "which is BEFORE `/ship`
Phase 5.5's Net-Issue-Flow Surfacing runs"), and `gh pr create` lives in `/ship` Phase 6.
`/brainstorm` and a standalone `/plan` file earlier still. **At those sites there is no PR number
in existence to cite.** Option 1 is not merely undisciplined there — it is impossible. PR-side
attribution is the only place the relationship is knowable at filing time. That argument carries
the decision on its own; the two struck clauses were never needed.

**Keyword-anchor on free prose (`Files|Filed|Tracks|Refs #N` anywhere).** Right *shape* — an
assertion rather than a mention — but applied to an unproduced body it returns `Filing: 0` on the
motivating case, because PR #7702 lists its filings as bare list items. The declared line is the
same idea with a producer behind it, which is what makes it work.

**Count bare `#N`.** Drafted, then rejected on the 300-PR measurement above.

**Report-only for the declared set too.** Rejected: it would still print `PASS` on #7702,
annotating a wrong verdict rather than correcting it — the shape the gate's own header condemns.

## Consequences

- **ADR-155's mandated-filing exemption is reached more often.** An earlier revision of this
  section said it was **inert** — "0 of 33 whole-line `Mandated-By:` issues cite a PR, so none had
  ever been a FILED candidate". **That measurement was wrong**, and it was wrong in the way its own
  stated method predicts: it classified cited numbers as issue-vs-PR by *range membership*, which
  cannot work here because GitHub issues and pull requests share one number space in this repo.
  Re-measured 2026-09-07 on `.pull_request` presence, which is the only sound discriminator:
  **21 of the 66 distinct cited numbers are pull requests, and 20 of the 33 issues cite at least
  one**, over 29 (issue, cited-PR) pairs — one of which is #7710 citing #7702, the case #7759 was
  filed about. The exemption had candidates. It was under-reached, not dead, and the stronger
  claims this section previously derived from the bad number ("never had a candidate", "never
  fires") are withdrawn. See the amendment on ADR-155.
- **One ADR-155 conjunct collapses, for one admission route.** A `Filed: #N` declaration now BOTH
  admits a row into FILED and satisfies exemption condition 4 (the companion), so for rows admitted
  that way the conjuncts are not independent. Rows admitted via the issue-cites-PR arm still need a
  separate companion, so the collapse is scoped. Condition 2 — the human-gated `[mandates-filing]`
  corpus edit — still bounds the blast radius either way. Priced explicitly, not at zero.
- **A `/ship` path that cites an EXISTING open issue self-neutralises.** Phase 5.5 writes
  `Tracks #NNNN` for an issue this PR did not file, which the declared arm would then count. Those
  issues carry `Mandated-By:` and are OPEN, and the PR body carries the companion — the three
  conditions of the exemption — so the row is counted in `Filing:` and then subtracted from `NET`.
- **The four pinned query properties are untouched.** The `gh issue list` argv is byte-identical.
  A fifth property is now pinned alongside them: the `--json` field list. Dropping `createdAt`
  makes every row fail the recency guard, so `FILED=0` and the gate passes on every PR — an
  always-pass path with no prior coverage.
- **Telemetry gains two ids**, both surfaced as named aggregator fields:
  `net-issue-flow-body-attributed` (how often the pre-#7759 gate would have under-counted — should
  be non-zero if this is load-bearing) and `net-issue-flow-unattributed-reported` (the residual
  blind spot — a rising value means producers are drifting off the declared line).
- **The PreToolUse hook is unchanged**, verified rather than assumed: it delegates and
  re-implements no query logic.

## Known adjacent gaps

**A filing that predates the PR is outside the window even when declared.** FILED is computed only
over issues with `createdAt >= <PR createdAt>`, and that conjunct is applied to BOTH arms — so a
number on the `Filed:` line whose issue was created before the PR row existed is not counted. This
is not hypothetical: `/brainstorm` files deferrals (`brainstorm/SKILL.md`, the
`Deferred from #<parent-issue>` shape) and a standalone `/plan` files trackers, and both routinely
run before any PR exists. Within `/one-shot` the draft PR is created at Step 0c, *before* Steps 1-2 planning, so
filings from that path are inside the window; the exposure is the pre-PR routes.

The recency conjunct is deliberate and should stay — without it any old issue number on the line
would count. What changed in the #7896 review is that such a declaration is no longer **silent**.
It used to be dropped from `Filing:` and simultaneously suppressed from the residual line (which
subtracted `$declared` unconditionally), so it appeared nowhere at all. It is now named on
`Undelivered declarations:` with the reason it could not be honoured. The gate still passes; the
operator can now see why.

**`Closes #<nonexistent>` still credits a close.** CLOSING is the one term in
`NET = FILED - EXEMPT - CLOSING` never validated against the fetched issue list. Word-boundary and
self-reference fail-opens were closed in the #7896 review, but existence is not checked, because
checking it against the 500-row window would false-block a legitimate close of an older issue or
one in another repo. The safe form is a report, not an arithmetic change.

**Enforcement is client-side.** The blocking surface is a PreToolUse hook on `gh pr ready` /
`gh pr merge`; the PR body is read at that instant and is editable afterwards, and merges that do
not go through a local Bash call (the web UI, a merge queue, `--auto` completing later) never
invoke it at all. The durable form is a required check re-running on `pull_request: [edited,
synchronize]`. That is a separate piece of work and is not claimed here.

- **`/review`'s `Ref #N` probe** uses a different, keyword-anchored predicate over issue bodies to
  find review-origin issues. It has the mirror-image exposure and is NOT fixed here — a different
  gate, a different corpus, and folding it in would put an unmeasured change inside a PR whose
  whole subject is that unmeasured changes to this query make it always-pass.
- **The declared line only helps PRs that carry one.** For a PR authored outside `/ship`, the
  conservation line reports the residual rather than counting it. That is the deliberate trade:
  fail-visible over fail-open.

## Supersedes

The 2026-09-03 plan §PR 4, which proposed report-only annotation for the whole set.
