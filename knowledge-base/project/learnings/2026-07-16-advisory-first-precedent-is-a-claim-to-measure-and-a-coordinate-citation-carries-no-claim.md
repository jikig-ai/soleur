---
title: "A cited 'advisory-first, promote later' precedent is a claim to measure — and a coordinate citation carries no claim to validate"
date: 2026-07-16
category: test-failures
module: ci-gates / agents-md-rules / brainstorm
problem_type: logic_error
component: ci_tooling
severity: medium
symptoms:
  - "An issue specifies 'advisory-only initially, promotable to blocking per the <X> calibration precedent'"
  - "The cited precedent scanner appears in zero .github/workflows/"
  - "The calibration issue is open long past its stated window with zero organic findings"
  - "A proposed citation validator passes on the exact decoy that motivated it"
root_cause: unverified_precedent
tags: [advisory-vs-blocking, calibration-window, citation-rot, anchoring, born-blocking, write-mostly-artifact, precedent-verification]
related_prs: [6527, 6479, 6456, 4265, 4646]
related_issues: [6517, 6529, 6530, 4270]
related_adrs: [ADR-071, ADR-076]
related_learnings:
  - 2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again.md
  - 2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md
  - 2026-05-12-brainstorm-write-mostly-artifact-diagnosis-and-lifecycle-prereq.md
  - 2026-07-06-measure-data-production-rate-before-scoping-a-visibility-surface.md
  - 2026-07-02-enforce-gate-on-citation-resolvability-not-completeness-for-a-curated-register.md
synced_to: [brainstorm]
---

# Learning: an "advisory-first" precedent is a claim to measure, not a plan to copy

Source brainstorm (full decision record + domain assessments):
`knowledge-base/project/brainstorms/2026-07-16-citation-rot-bare-token-gates-brainstorm.md`

## Problem

Issue #6517 proposed two CI gates for recurring "the check certifies the wrong thing"
classes, and specified both ship **"advisory-only initially, promotable to blocking per
the frontend-anti-slop calibration precedent."**

That clause is load-bearing — it sets the gate's posture, its acceptance criteria, and its
cost. Three measurements refuted it:

- `grep -rl tier1-scan .github/workflows/` → **zero hits.** `tier1-scan.ts` is a skill
  script invoked from prose in `frontend-anti-slop/SKILL.md` and `review/SKILL.md`. It is
  not a CI gate. **There was no advisory stream to promote.**
- `gh issue view 4270` → the calibration window (opened 2026-05-21, stated window
  "2 weeks") is **OPEN at 56 days** — 4× over. Four comments: three on ship day, one
  triage bot (2026-05-24). **Zero findings logged organically.** Production rate = 0.
- What *did* ship blocking — the brand rules (#4646, 8 days later) — was **born blocking**
  and skipped calibration entirely.

**Advisory→blocking promotion has never happened once in this repo.**

## Root cause

"Advisory first, promote when calibrated" is a promise about **future follow-through**,
and follow-through is the thing that fails. A calibration window with no machine-enforced
expiry never closes; the issue tracking it becomes the artifact nobody reads.

The precedent was cited from memory of the **intent** ("we shipped anti-slop
advisory-then-blocking") rather than the **outcome** (the advisory arm produced nothing;
the blocking arm was born blocking). Intent is what an author remembers; outcome is what a
`gh issue view` returns.

## Solution — the three-check probe

Before accepting an "advisory-first" framing, run all three. Each is seconds:

```bash
# 1. Is the cited precedent even wired into CI, or is it a skill script?
#    No wiring = no advisory stream = nothing to promote.
grep -rl "<scanner>" .github/workflows/

# 2. Did the calibration window ever close?
#    Compare age vs stated window; count ORGANIC findings vs ship-day noise + triage bots.
gh issue view <calibration-issue> --json state,createdAt,comments

# 3. Was anything in this repo ever actually promoted advisory -> blocking?
#    Zero-for-N means born-blocking is the only mechanism with a track record.
```

Ties to `2026-05-12-brainstorm-write-mostly-artifact-diagnosis-and-lifecycle-prereq`
(zero closures ⇒ adding a producer compounds the backlog) and
`2026-07-06-measure-data-production-rate-before-scoping-a-visibility-surface` (an existence
check passes while the production rate is zero).

## Key insight

**Scope narrow enough to block from day one, or don't ship the gate.**

"Advisory now, blocking later" reads as the cautious option and is reliably the one that
ships nothing — it converts a gate into a warning stream with no reader and no expiry. If
a gate cannot be made precise enough to block, that is evidence **the detector is wrong**,
not evidence it needs a calibration window.

---

# Learning: a coordinate citation carries no claim, so no validator can check it

## Problem

#6517's Class A proposed a CI check that resolves `file:NNN` citations in changed files
against the post-diff tree. The motivating failure (PR #6479) was a citation at `:151`
that shifted 35 lines — landing on a **decoy** line that also echoed `TRANSIENT`, falsely
confirming the reviewer's read.

## Root cause

`foo.ts:151` asserts a **coordinate**, not a **claim**. Nothing records what it *meant* to
point at, so a resolver has no referent to check against. Walk the proposed gate over the
motivating failure: it resolves `:151`, finds a line, sees the token, and **PASSES**.

Measured on the live tree (2026-07-16, re-verified): **320 unique citations, 334 resolvable,
0 past-EOF.** Past-EOF is the only rot a resolver can detect — and intra-file drift is the
rot that actually happens. The detector finds nothing on the tree it would guard.

*(The `386 unique / 330 resolvable` figures first written here were unlabelled and
unreproducible; the `0 past-EOF` result — the only load-bearing one — re-verified exactly.
See Session Errors #3.)*

## Solution

Ban **new** `file:NNN` on added diff lines instead of validating old ones:

```bash
git diff -U0 | grep '^+'   # ~10-line regex over added lines only
# REJECT:  // see foo.ts:151
# ACCEPT:  // see foo.ts › emitBeacon()
```

Zero migration cost, no diff line-mapping, grandfathers the ~360, scoped to code comments
(markdown excluded — 6,529 sites, and an archived plan's citation is a historical record,
not a live claim). It enforces the content-anchor convention **ADR-076 item 3** already
mandates for the domain-model register — and that the violated file's own header already
stated: *"anchored on EMIT NAMES, not line numbers — line citations rot."*

## Key insight

**When a gate is proposed to VALIDATE a fragile convention, price BANNING the convention
instead.** A ban is a lexical check on added lines. A validator is a semantic check needing
intent the artifact never recorded. The ban is cheaper *and* strictly stronger.

Corollary (the rung check): the repo's escalation ladder is **learning → AGENTS.md rule →
hook/CI gate**. Before arguing for rung 3 because "prose failed", grep that rung 2 exists.
For this class it did not — see Session Errors #6.

## Session Errors

1. **A subagent overstated an ADR's scope.** learnings-researcher reported "ADR-076
   already decided: do not use line numbers at all." ADR-076 item 3's content-anchoring
   mandate is scoped to the domain-model **register's** facts/candidates — not a repo-wide
   ban on line numbers in code comments. — Recovery: read ADR-076's Context + Decision
   directly; corrected before it reached the brainstorm doc. — **Prevention:** an agent's
   ADR-scope claim is a claim to verify; read the ADR's Context + Decision, never just the
   Alternatives-Considered table a grep surfaces. Reinforces
   `2026-07-04-verify-adr-citation-numbers-before-threading-into-subagent-prompts`.
2. **`gh pr diff 6479 -- <path>` failed** (`accepts at most 1 arg(s), received 2`). —
   Recovery: dropped the pathspec. — **Prevention:** `gh pr diff` takes no pathspec; filter
   its output or use `git diff` instead.
3. **Three subagents returned irreconcilable counts for overlapping measures** — 52 vs 386
   vs ~6,336 citations; 586 vs 619 vs 2,715 bare-token sites — because each applied a
   different, unstated filter. — Recovery: cited only counts whose filter was stated, and
   surfaced the divergence rather than averaging. — **Prevention (v1, INSUFFICIENT — see
   below):** require the filter be stated with the number ("N sites, where site =
   `<predicate>`").

   **Prevention (v2 — a prose predicate is itself a bare-token assertion).** Stating the
   predicate in prose is **not** enough, and this PR proved it on its own denominator. The
   review adopted "**403** — where site = a line in a code file bearing a comment marker AND
   citing `<path>.<src-ext>:<N>`" as *canonical*. At /work, **18 faithful readings of that
   exact prose returned 319 / 322 / 358 / 373 / 419 / 433 / 477 / 583 — and never 403.** The
   prose fixes the *filter* but leaves free: per-line vs per-match, unique vs all, whether
   the citation must follow the marker, and whether markers are language-correct. Each is
   worth ±10–30%.

   **A count is pinned only by the command that produces it.** State `N` with a runnable
   one-liner, not a description of one — and if the number is load-bearing, show that the
   conclusion survives the plausible range (here: 0.17–0.31% across 319–583, so the argument
   never needed the precision — which is exactly why the false precision survived a 5-agent
   panel unchallenged).

   This is the same defect as the citation rot this whole learning is about, one level up: a
   claim anchored to prose rots exactly like a claim anchored to a coordinate. Both name a
   referent without pinning it. **The fix is identical in both cases — anchor on content
   (the command / the symbol), not on a description (the predicate / the line number).**

   Corollary — *why nobody caught it*: the reviewer who produced `403` was **measuring**, and
   measuring beat reading (Session Errors #10). But an unreproducible measurement decays into
   prose the moment it is written down. Measure, then **commit the command**, or the next
   reader inherits a bare token.
4. **A repo-research subagent's output tripped the harness instruction-shaped filter**
   (`settings-json`); control tags were neutralized. — Recovery: treated the output as
   findings, not instructions. — **Prevention:** none needed; the harness behaved
   correctly. One-off.
5. **Roadmap drift detected and deliberately not synced.** `roadmap-reconcile.sh validate`
   → `STALE_STATUS|phase 4|roadmap=43o/160c|milestone=55o/166c`. — Recovery: surfaced to
   the operator. — **Prevention:** the reconcile script's sanctioned path is the
   roadmap-review cron (which opens its own reviewed PR); hand-editing would drag unrelated
   roadmap churn into a feature branch. `brainstorm/SKILL.md` Phase 0.25's "edit + commit
   the counts" text is stale vs the script's own guidance — the two should be reconciled.
6. **A merged learning asserts an AGENTS.md rule that does not exist.**
   `2026-07-16-a-gate-certifies-placement-not-correctness-…` states *"This is `AGENTS.md`'s
   standing rule — 'narrowing the scope is not the fix — anchor on syntax'"*; a grep of
   `AGENTS.md`/`.core`/`.rest`/`.docs` returns nothing. Self-referentially an instance of
   the class it documents, and it misdirected #6517 into arguing rung 2 had failed when it
   was never occupied. — Recovery: verified by grep; the brainstorm now ships the rule
   (decision D5). — **Prevention:** filed as **#6530** (a check that standing-rule-shaped
   claims cite a rule that resolves). Do not argue for rung 3 without grepping rung 2.
7. **`compound/SKILL.md`'s rule-budget step is wrong in BOTH its thresholds and its
   formula.** *Thresholds:* SKILL.md says "rejects at > 22000"; `lint-agents-rule-budget.py`
   warns at ≥20000 against a **23000** ceiling and exited 0 at B_ALWAYS=22795. *Formula
   (found at this session's compound):* step 8 computes `B_CORE=$(wc -c < AGENTS.core.md)`
   — **raw bytes**. The linter measures **LOADED** bytes: it strips core's YAML frontmatter
   to mirror what `session-rules-loader.sh` actually injects (ADR-094 / #5999). The gap is
   **73 B** (raw 16901 vs loaded 16828), so step 8 reports `B_ALWAYS=22973` where the
   authoritative linter reports **22900** — and its own stale "critical > 22000" then fires a
   **spurious `[CRITICAL] shrink required before next rule`** against a payload that is
   genuinely 100 B *under* the real ceiling, with the linter exiting 0. An operator acting on
   it would retire a rule they did not need to. — Recovery: ran the authoritative linter and
   cited its figures (16828 / 22900); this learning's Rule-budget section uses the linter's
   numbers, not `wc -c`. — **Prevention:** ironically the exact class this PR gates — a check
   that certifies the wrong thing by measuring the wrong bytes, and a doc describing a gate
   behavior the code does not implement. Run the linter; never quote the doc's thresholds and
   never re-derive its formula by hand. Tracked for a real fix (different subsystem — not
   bundled into this branch).
8. **Auto-consolidation would have archived pre-plan artifacts.** `compound-capture`'s
   automatic consolidation archives brainstorm/spec artifacts on any `feat-*` branch, but
   this compound ran at the **brainstorm** phase — archiving would move the brainstorm and
   spec to `archive/` before `/plan` reads them. — Recovery: skipped Steps A–F with an
   explicit reason. — **Prevention:** consolidation/archival presumes a ship-phase
   compound; it should gate on the feature having shipped (merged PR), not merely on the
   branch prefix.
9. **I armed the wrong class for a whole plan cycle, on a recurrence count I never
   attributed.** #6517's body says "two failure classes have *each* recurred across multiple
   PRs"; I inherited that and wrote "10× in two days" into the brainstorm, spec, plan v1,
   this learning, and the #6517 issue-body addendum — as the justification for building
   Class A a hook + CI job + detector + two test suites + an ADR. **All ten are Class B**
   (#6456: 4 vacuous assertions; #6479: 4 grep + 2 placement). Class A recurred **once**
   against ~360 citations (~0.28%). DHH caught it at plan review by reading the counts I had
   quoted myself. — Recovery: plan v2 re-scoped; every artifact corrected. —
   **Prevention:** when a recurrence count justifies an investment, attribute each instance
   to a class **before** citing the total. A two-class issue body that says "each recurred"
   is a claim to verify per class, not a sum to inherit — and the sum is the number that
   sizes the build.
10. **The v1 detector was specified, reviewed, and would have shipped net-negative — nobody
    measured it until a reviewer did.** v1 passed my own authoring, a Research
    Reconciliation, and my Q1/Q2/Q3 resolutions. Then the CTO replayed it over 300 commits:
    **50/300 denied, 57% false hits** (`127.0.0.1:6379`, `4.5:1`), and `main`'s own HEAD —
    which *is* PR #6479, the motivating PR — would have been denied. Kieran found the root
    cause: `http://` **is** the TS comment marker, so a DSN string denies a line with no
    comment. Running my exact spec, Kieran counted **555 hits vs the 403 I claimed** — my
    measurement and my detector disagreed by 50% and I never noticed. — Recovery: gate held
    behind a replay AC (≤3/300, zero false). — **Prevention:** a detector spec is a claim to
    **replay against real history** before it is a plan. The replay is one shell loop; it
    belongs in the plan as an AC, not in review as a finding. Corollary: reviewers who
    *measure* find what reviewers who *read* cannot — the four agents who only read the plan
    all missed the 57%.
11. **The bare-token class recurred an 11th time — in the PR that bans it, in the AC that
    verifies the ban, written by the author of the rule.** Closing the review findings I
    added `AC10` ("no artifact states a moving reference in the present tense") and verified
    it with `grep -rn "current HEAD" knowledge-base/`. It **false-FAILED on four unrelated
    plans** — `git revert HEAD` guidance, a RED-state note, a `checkout -B` caveat, a
    tag-target note — because a bare token over prose matches prose. That is
    `cq-assert-anchor-not-bare-token`'s exact prohibition, committed inside its own
    acceptance criterion, minutes after I wrote the rule body.

    **Then it recurred a 12th time, in the fix.** Draft 2 anchored on the construct
    (`` `main`'s current HEAD ``) and scoped to the diff — and an earlier version of this
    very line claimed "both ACs then passed". **That claim was false**: draft 2 still returned
    **2 hits**, both this plan and this learning *quoting the construct while documenting the
    fix*. `pattern-recognition-specialist` and `user-impact-reviewer` independently caught it
    by RUNNING the AC I had asserted passed — the same defect as the denominator (a claim
    about a measurement, retyped rather than re-run), inside the Session Error about that
    defect.

    — Recovery (draft 3): **a self-documenting grep cannot anchor on its own pattern.**
    Anchoring harder cannot work — any pattern precise enough to match the assertion also
    matches the prose and the regex literal that describe it. Anchor instead on **structure
    the documentation cannot have**: the assertion is a markdown table row, so `^\|.*current
    HEAD` pins it while prose, code fences, and the AC's own regex all start otherwise.
    Mutation-tested both directions (injected table row → RED; real tree + both prose sites +
    the code block → GREEN).
    — **Prevention:** this is not a coda, it is the strongest evidence in the file for the
    rule's necessity: **knowing the rule, having just authored it, and actively working on
    the PR that ships it were jointly insufficient.** A rule that its own author violates
    within the hour is not a rule that "documentation a `grep` away" would have prevented —
    which is the whole argument for rung 2, and (when it measures clean) rung 3. Note also
    which clause caught it: *anchoring*, not scope. The rule's own line — *"narrowing the
    scope is not the fix; anchor on syntax"* — is right, but this instance needed **both**.
12. **I asserted two byte-counts into the plan without measuring them** (`559`/`597` for the
    as-shipped rule bodies; actual **558**/**595** — I reused a `wc -c` figure that counts
    the trailing newline). Self-caught by re-measuring before commit. — **Prevention:** the
    same rule as the denominator, at 1/100th the stakes: a number you did not just run the
    command for is a guess. The 595 body has **5 B** of headroom against the 600 B ceiling,
    so a retyped-not-measured count is the difference between green and a linter failure.
13. **The sweep that fixed the unlabelled-denominator class left four siblings of that exact
    class in artifacts it had already passed.** Re-review found: `534 B` for a rule body
    (actual **595**) — asserted *inside a sentence claiming the deliverables were "sound and
    verified"*; **`~6,529`** markdown sites — a bare count I could not reproduce from seven
    predicates (848–18,395), sitting **two bullets below** the paragraph declaring "a prose
    predicate does not pin a count"; **`1/403 = 0.248%`** — deriving the arithmetic-correction
    basis from the very number the same document declares unreproducible twenty lines above
    (against the adopted ~360 it is **1.80×**, not "~2×"); and **`111 B`** pointer cost
    (actual **105** = 55 + 48 + 2, which is also the file delta). — Recovery: all re-measured
    and fixed; the 6,529 was **dropped** rather than re-anchored, because nothing rests on its
    magnitude and a third command would have bloated the ADR. — **Prevention:** *fixing a
    defect class in the site that motivated it does not fix the class.* When a sweep is
    defined by a class (unlabelled counts), the work-list is **every instance of the class in
    every touched artifact**, enumerated by grep — not the sites the finding named. The
    tell-tale is proximity: three of these four sat within 40 lines of the prose that names
    the defect. Hardest-hitting variant: a bare figure **inside a sentence asserting
    verification** — the assertion of rigour is what stops the next reader checking.
14. **The sweep discovered two new findings mid-flight and never propagated them backwards
    into the artifacts it had already passed — including the durable ones.** While closing
    P2-3 I found the `gitleaks-staged` precedent is *two-surface* (its own files call the
    lefthook half "fast-feedback only" and CI "the enforcer"), and I added AC9/AC10. Both
    landed in the **plan** only. `spec.md` still read *"Resolved → the surface is lefthook"* —
    settling, in a docs PR, the architecture fork the plan explicitly reserved for the `cto`
    agent — and still dismissed the bypass surface as "`--no-verify`… a bypass no agent has
    been observed using" when there are **four** (cherry-pick, rebase, merge via
    `pre-merge-commit`, `--no-verify`), three of them ordinary agent operations. ADR-116
    §Consequences and the public **#6517 body** asserted the same settled surface. — Recovery:
    pushed the finding into all three; reopened the surface in each. — **Prevention:**
    **rank the propagation targets by durability, not by edit order.** The plan is ephemeral;
    the **ADR** (`status: accepted`, lives in the decision corpus) and the **issue body** (what
    a resuming author opens first) outlive it. A mid-sweep discovery must be pushed to every
    artifact the sweep already passed, durable ones first — otherwise the correction lives
    only in the artifact nobody reads next. Caught by `security-sentinel` +
    `pattern-recognition-specialist` cross-reading pairs of artifacts; no single-file lens
    could see it.
15. **A review prescription is a claim to verify, not an instruction to execute.** P1-1
    prescribed adopting `403` *with its stated predicate* — and the prescription was wrong: 18
    faithful readings of that prose never produced 403. The confirmation is the striking part:
    at re-review, `code-quality-analyst` — the same agent that filed P1-1 — independently
    re-measured, could not reproduce it either, and **retracted its own prescription**
    ("`/work` was right to refuse… the reasoning is better than the prescription it
    overrode"). — **Prevention:** treat a finding's *diagnosis* as high-signal and its
    *prescribed value* as a hypothesis. A reviewer who measures beats a reviewer who reads
    (Session Errors #10) — but a measurement written down without its command is prose by the
    time the next person reads it (Session Errors #3). Both halves are the same rule.
16. **A backgrounded `test-all.sh > log 2>&1` made the harness report `exit code 0` from the
    trailing command, not the runner** — the documented `hr`-adjacent trap, hit anyway. The
    background task's own `.output` was empty (the real output went to the redirect target),
    so the completion notification's "exit code 0" was the trailing `tail`/`echo`. — Recovery:
    captured `rc=$?` explicitly into the log and grepped the runner's own summary line
    (`178/178 suites passed`). — **Prevention:** for a backgrounded runner, either drop the
    redirect (let the task file capture stdout) or **always** grep the log for the runner's own
    verdict; never trust the notification's exit code. Knowing the trap was documented did not
    prevent it — the same finding as #11, in the harness layer.
17. **I created an `FR8` numbering collision** while sweeping spec.md (a new Class A FR8
    against Class B's existing FR8/FR9/FR10); self-caught within a minute and renamed to
    `FR2b`. One-off. — **Prevention:** none warranted; the immediate grep for duplicate ids is
    already the habit that caught it. (Its sibling *is* worth noting: the renumber left v1's
    `FR7` slot reused by a different requirement, so any external citation of "v1 FR7" now
    silently resolves to something else — the PR's own subject. Disclosed inline in spec.md
    rather than renumbered further; no live consumer cites it.)

## Rule budget

**Baseline, before the two rules landed:** `B_INDEX=5967`, `B_CORE=16828`,
**`B_ALWAYS=22795`** (linter WARN ≥20000; ceiling 23000; exit 0). Registry total 42253 bytes
/ 198 rules; longest rule 600 bytes.

**As-shipped:** **`B_ALWAYS=22900`** (`AGENTS.md=6072` + `AGENTS.core.md=16828`) — the two
tagless pointers cost 105 B, leaving **100 B** under the ceiling. Rule bodies **558 B** and
**595 B** (limit 600 each). Budget linter exits 0 with the standing `≥20000` WARN.

**Consequence for #6517's Class B (confirmed as-shipped):** the `cq-assert-anchor-not-bare-token`
**body** lives in `AGENTS.rest.md`, which is **class-gated, not always-loaded** — only
`AGENTS.md` + `AGENTS.core.md` count toward `B_ALWAYS`, so only the pointer hits it. Viable
but tight, as predicted: the 595 B body has **5 B** of headroom, and the P2-1 carve-out
clause overshot to 657 B before the linter caught it.

> **Re-measure, do not quote.** Every figure above is the output of
> `python3 scripts/lint-agents-rule-budget.py` at a moment in time, and `B_ALWAYS` moves
> whenever *any* rule changes. The next two rules hit the ceiling — a retirement pass on
> `AGENTS.core.md` is the standing recommendation.
