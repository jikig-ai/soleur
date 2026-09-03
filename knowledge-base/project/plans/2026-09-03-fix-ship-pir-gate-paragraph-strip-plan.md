---
title: "fix(ship): Incident-PIR gate fires on a precedent citation inside the hypothetical impact paragraph"
date: 2026-09-03
slug: fix-ship-pir-gate-paragraph-strip
branch: feat-one-shot-7801-pir-gate-paragraph-strip
issue: 7801
closes: 7801
type: fix
lane: cross-domain
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-09-03 · **Panel:** dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto, plus a scoped
strong-model advisor consult (ADR-083 Step 4.5).

Every reviewer rebuilt the prototype and re-ran the corpus independently; the `268 → 260` /
8-mover result reproduced exactly in four separate sweeps. The panel changed the **design**, not
just the prose:

1. **The hash boundary was defective and defeated the fix on its own target class.** A bare
   `/^[[:space:]]*#/` treats a `#6691` continuation line as a heading. Measured on a reflow of
   fixture F1 that differs only in where the line wraps: shipped `SIGNAL`, draft design **`SIGNAL`**
   — the fix did not fix it. Tightened to `#+([[:space:]]|$)`; fixture F9 now pins it.
2. **The thematic-break rule was dead machinery** (0 terminations in 1548 plans, two independent
   measurements) and its fixture modelled markdown incorrectly (`---` under a paragraph line is a
   setext underline). Cut, with the seam-rescue counter-hypothesis tested and disproved.
3. **The actuality vocabulary was fitted to N=1 with 8 unmeasured alternatives.** Trimmed to the
   two with corpus hits, and Property 3 was rewritten to stop overclaiming: at line scope,
   precedent-citation and self-report are undecidable. Fixture F10 now pins the residual as a
   characterization test instead of leaving the hole undocumented.
4. **Four acceptance criteria could not pass or could not fail.** AC2 contradicted AC3 (its glob
   would contain the new fixtures); AC8 was green on unmodified `main` (the phrase wraps a comment
   line break); AC9 was red on a correct edit (markdown emphasis breaks the anchor); AC6c's
   discriminator was false against 5 of the 8 measured movers *and* self-refuting.
5. **`git show origin/main:<script> | bash` is input-independent exit 0** — every "signals under
   both scripts" AC would have passed vacuously. Phase 4.0 now materializes and self-checks the
   baseline.
6. **The plan had no legal exit from its own gate.** `adjudicat`/`meta-case` return zero hits
   across ship, incident and AGENTS.rules.md, and the self-trip is certain. Phase 3.2 adds the
   disposition, two-conjunct-gated against a counter-example verified in git history.
7. **The mutation rows became executable.** The repo has 11 `*-mutation.test.sh` batteries; prose
   rows in an archived plan are performed once and never again, which is how this gate regressed
   four times with a green suite.

Deepen-plan gates: 4.6 (User-Brand Impact) **pass**; 4.7 (Observability) initially **failed** on a
missing `logs:` field — added; 4.11 (Guard Contract) **pass** via `lint-guard-contract.py`. Gates
4.5, 4.55, 4.8, 4.9 and 4.10 do not fire (no network symptom, no serving-surface downtime, no
PAT-shaped variable, no UI surface, no persistent store). All cited AGENTS rule IDs verified active
against `AGENTS.md`; the #7242/#7244 attribution verified against `git show d31d8a2c7`.

## Overview

The `/ship` Phase 5.5 Incident-PIR gate (`scripts/ship-incident-pir-gate.sh`) strips the
hypothetical framing LINE of a plan's `## User-Brand Impact` section before matching past-tense
outage vocabulary, but leaves the wrapped continuation sentences of that same paragraph in the
haystack. A plan that cites a past, closed incident as design precedent inside its own
hypothetical-impact paragraph therefore reads as an outage report and the gate fires.

This plan extends strip (3) from the label line to the paragraph the label opens — bounded by a
blank line, a markdown heading, or a new list item — and pairs the widening with three
counterweights that plan-time measurement proved it needs: an **actuality re-admit** so a sentence
claiming the event already happened survives the strip, a **fence boundary** so a code block
between the paragraph and a real claim cannot merge them, and a **fail-toward-PIR guard** so a
broken strip pipeline on a customer's unpinned `awk` fires rather than falls silent.

The signal scan is **trigger 3 of 3** in Phase 5.5. Triggers 1 (`/soleur:incident` ran this
session) and 2 (a `single-user incident`/`aggregate pattern` threshold **and** a production-incident
fix) are independent and untouched, so a miss here is not a single-point failure — it is the
deterministic layer of a three-trigger gate whose other two are model judgement.

Scope is the ship-gate subsystem only. No DNS/cutover code is touched.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited reference | Probe | Result |
| --- | --- | --- |
| Issue `#7801` | `gh issue view 7801 --json state,closedByPullRequestsReferences` | `OPEN`, no closing PR. Premise holds. |
| `scripts/ship-incident-pir-gate.sh` | read in full (105 lines) | Exists. Strip (3) is the `grep -vaiE` at the `haystack=` pipeline tail. |
| `plugins/soleur/test/ship-incident-pir-gate.test.ts` | read in full; `bun test` run | **16** tests over **15** fixtures — not "nine". See R1. |
| PR `#7793` linked plan | ran the shipped gate against it | `INCIDENT-SIGNAL: yes`. Reproduced. |
| ADR corpus for the mechanism | `grep -ril 'incident-pir\|pir gate\|ship-incident' knowledge-base/engineering/architecture/decisions/` | No ADR decides it. Not a rejected alternative. |
| "only ship/SKILL.md and the test call the gate" | `git grep -n ship-incident-pir-gate`; sweeps of `.claude/hooks/`, `.github/workflows/`, `scripts/`, `plugins/**` for the name, for `INCIDENT-SIGNAL`, and for glob-dispatch wrappers | Confirmed — exactly two callers, no hook, no workflow, no indirect form. |
| `awk` flavour | `awk --version` | `mawk 1.3.4 20260129`. Program also verified identical under `busybox awk` and `nawk`. No brace intervals used. |
| repo mutation-battery convention | `git ls-files \| grep -E 'mutation.*\.test\.sh$'` | **11** existing batteries registered in `scripts/test-all.sh`. Reverses a cut — see Cut List row 1. |

### Property List (Phase 0.6b)

1. A hypothetical-impact paragraph's continuation sentences do not contribute outage vocabulary to
   the Incident-PIR haystack.
2. A real, past-tense outage claim written **outside** that paragraph still contributes.
3. A sentence inside that paragraph that claims the event already happened **using one of the
   actuality idioms the re-admit enumerates** still contributes. A past-tense outage claim phrased
   *without* one of those idioms is **swallowed** — an accepted fail-open residual, pinned by
   fixture F10 so it is visible in the suite rather than discovered in an incident. Property 3 is
   deliberately **not** stated as "any actuality claim survives": at line scope that is undecidable
   (see Risks, row 2).
4. None of the gate's existing verdicts move.
5. The gate cannot go silent because a strip stage failed — a broken pipeline fires.
6. Each rule of the new stage is provably load-bearing by an **executable** mutation.

### Cut List (Phase 0.6b)

| Mechanism considered | Property | Disposition |
| --- | --- | --- |
| A colocated `scripts/ship-incident-pir-gate-mutation.test.sh` | 6 | **REVERSED — kept.** Initially cut on the reasoning that it "would split the fixture corpus". That conflated a second fixture corpus with a mutation *runner*: a battery mutates a sandbox copy and re-checks the **existing** fixtures, adding none. The repo has 11 such batteries wired into `scripts/test-all.sh`, and prose mutation rows in an archived plan are performed once and never again — which is how this gate regressed four times with a green suite. |
| Thematic-break boundary rule (`---`/`***`/`___`) | 2 | **Cut on two independent measurements.** Zero terminations across 1548 plans; deleting it moves zero verdicts. Its would-be fixture also models markdown incorrectly — `---` directly beneath a paragraph line is a CommonMark **setext H2 underline**, not a thematic break, so the rule cannot fire in the one position the fixture places it. The seam-rescue hypothesis (that it saves the PR_TEXT/PLAN_TEXT concatenation) was tested and **disproved**: the seam is rescued by the heading rule. |
| A modal-inversion re-admit (re-admit any in-window line *lacking* `would\|could\|might\|if this\|hypothetical`) | 3, vocabulary-free | **Cut on measurement: 0 verdicts move on 1548 plans.** Only 6 of the 37 silenced outage lines carry a conditional marker on their own line — the conditionality lives on the *label* line, which the trigger consumes. Recorded so it is not re-litigated. |
| A date/duration **actuality-anchor** re-admit (`20NN-NN-NN`, `NhNNm`, `began`, `never sent`) | 3, vocabulary-free | **Cut, though it measures clean** (same 8 movers, 0 `no -> yes`) and it *does* close the paraphrase hole. It re-admits any **dated** citation — including the `#6691`/`~8h15m` line-502 shape that motivated this issue. It would therefore un-fix the reported bug while appearing to strengthen the gate, and fixture F1 would have to model a shape the motivating case does not have. Rejected on that ground alone; recorded with its measurement so a future session does not re-derive it. |
| `[ -n "$haystack" ] \|\| { echo signal; exit 0; }` as the fail-open guard | 5 | **Cut.** An input that is *entirely* a fenced block legitimately yields an empty haystack, so this false-fires. The Phase 2.4 form keys on the pipeline's exit status instead, which fires only on real failure — verified: rc 2 for a bad `awk` flag, rc 127 for a missing binary, rc 0 for an empty-but-successful pipeline. |
| A new AGENTS.md rule about hypothetical framing | none | **Cut** — no behavioural gap a rule closes; `B_ALWAYS` budget not spent. |
| A follow-up issue for the six residual `outage` hits on the #7793 plan | none | **Cut** — already the accepted residual documented in the script header and in `knowledge-base/project/learnings/2026-07-22-incident-gate-meta-case-and-type-widening-must-sweep-injected-dep-signatures.md`. See R2. |

*(Section-scope stripping and the `OUTAGE_RE` negative lookahead were also considered and are
argued once, in `## Alternative Approaches Considered`, rather than twice.)*

### Value-Proposition Measurement (Phase 0.6c)

Correctness, not cost, is the justification, so 0.6c does not gate. Blast radius is measured anyway.
**Four independent sweeps** — the planning prototype and three reviewers rebuilding it from the
plan text — agree exactly:

| Measure | Value |
| --- | --- |
| Plans in `knowledge-base/project/plans/` | 1548 |
| Signal under the shipped gate | **268** (17.3%) |
| Signal after this change | **260** (16.8%) — 8 movers, identical file list every time |
| Plans that open a skip window | **989** (64%) |
| Lines the new stage silences | **4116** (≈2.7/plan), of which **37** carry `OUTAGE_RE` vocabulary |
| Plans whose verdict the actuality re-admit changes | **1** |
| Real PIRs in `knowledge-base/engineering/operations/post-mortems/` | 114 |

**Stop-condition instrument.** This fix removes 3.0% of signal volume while the gate fires on 17%
of plans against a ~7% real-PIR base rate. That ratio — not the next anecdote — is what should
decide whether a sixth corrective change is warranted, so Phase 2.6 records the post-change rate in
the PR body and the script header.

### Institutional learnings that change how this is built

| Learning | What it changes here |
| --- | --- |
| `.../2026-08-13-my-guard-passed-through-the-whole-regression-because-its-fixture-predated-the-widening.md` | "When a diff WIDENS a matcher… add a fixture in the **newly-admitted region**, and mutation-prove it." F1 lives in that region; the executable battery is the mutation-prove half. It also mandates F10: the residual needs a fixture even where the verdict is accepted. |
| `.../2026-07-22-incident-gate-meta-case-and-type-widening-must-sweep-injected-dep-signatures.md` | "Does the artifact that DOCUMENTS the gate trip it? If yes, that is inherent." Measured: this plan trips before **and** after. Phase 3.2 gives that adjudication a branch to land in — see R5. |
| `.../best-practices/2026-05-22-parity-tests-must-include-boundary-adjacent-fixtures.md` | Cover the boundaries you **have**. Read correctly, it is not a licence to declare boundaries in order to generate fixtures — which is why the thematic-break rule was cut rather than fixtured. |
| `.../best-practices/2026-06-12-source-scan-containment-gate-call-detection-and-fail-closed-lexing.md` | A naive regex stripper can swallow a section and fail OPEN. Motivates the actuality re-admit (R3) and the fence boundary (R6). |
| `.../bug-fixes/2026-04-28-awk-field-split-on-colon-truncates-multi-colon-yaml-values.md` | No `-F`/FS field extraction. Whole-record `$0` rules only. |

### Repo facts established (Phase 1)

- **Only invocation:** `plugins/soleur/skills/ship/SKILL.md` Phase 5.5, content anchor
  `bash "${CLAUDE_PLUGIN_ROOT:-.}/../../scripts/ship-incident-pir-gate.sh"`.
- **Gate is blocking.** On a signal, ship requires a `*-postmortem.md` on the branch and validates
  its `## Action Items & Follow-ups` shape. A false positive costs a fabricated PIR.
- **CI:** `.github/workflows/ci.yml` job `test-bun` runs `bash scripts/test-all.sh bun` →
  `bun test plugins/soleur/`. No path filter.
- **No shellcheck CI on repo-root scripts.** `actionlint` covers `.github/workflows/*.yml` only.
- **awk paragraph-scoping precedent** to adopt: `plugins/soleur/skills/ship/SKILL.md`, content
  anchor `awk '/^## Action Items & Follow-ups/{f=1;next} /^## /{f=0} f'`.
- **Test-runner form:** `bun test plugins/soleur/test/ship-incident-pir-gate.test.ts` (verified
  `16 pass, 0 fail`). Not vitest, not `npm run -w`.
- **`git show origin/main:<script>` is reachable** from this worktree; its *invocation* is the trap
  (R4).

### Skill-description budget (Phase 1.8)

No `description:` frontmatter edit is candidate or finalized. Skipped per the phase's own condition.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured) | Plan response |
| --- | --- | --- |
| **R1.** #7801: "moves NONE of the existing **nine** verdicts" | **16** tests over **15** fixtures. "Nine" is stale, inherited from the `#7242` header comment, and `grep -c 'nine existing fixtures'` returns **0 today** because the phrase wraps a comment line break. | ACs assert all 15 and all 16 hold. The stale sentence is **deleted**, not re-counted — the suite grows in this very PR, so a corrected number is wrong before it merges. AC8 anchors on `nine existing`, which does return 1 today, and asserts both directions. |
| **R2.** #7801: the precedent citation is "the matching text" | It is **a** match. The #7793 plan's haystack carries **7** `OUTAGE_RE` hits; the strip removes exactly **1**. The other 6 are planning prose about an outage the plan exists to *avoid*. **That plan still signals after this fix.** | No AC claims otherwise. The six residuals are the accepted residual the script header documents. |
| **R3.** #7801: extend the strip to the paragraph (naive form) | **Fail-open on a measured plan.** `2026-08-01-release-outcome-email-step-env-refs-plan.md` writes, inside its hypothetical paragraph, *"This already happened — the outage began ~2026-07-30 and no notification was ever sent."* A blank-line-bounded strip silences a plan reporting a real production outage — the #7242 class, re-entered through the fix for its opposite. | `ACTUALITY_RE` re-admit. Restores that plan; moves nothing else. F2 and mutation rows M2/M7 pin it. |
| **R4.** the draft's own "run the pre-change script (`git show origin/main:…`)" | **Silently vacuous.** Measured: `printf '…' \| git show origin/main:scripts/ship-incident-pir-gate.sh \| bash` returns exit 0 with no output **for every input, including empty** — `bash` consumes the script from stdin and the gate's `cat` eats the rest. Ship reads exit 0 as "signal", so every both-directions AC would have passed vacuously. | Phase 4.0 **materializes** the baseline and self-checks it against a known-negative fixture. Correct forms verified: `bash "$BASELINE" <<< text` and `bash <(git show …)`. |
| **R5.** the draft's own "adjudicate the meta-case, do not author a PIR" | **No branch exists to land it in.** `adjudicat`/`meta-case` return **zero hits** across `plugins/soleur/skills/ship/`, `plugins/soleur/skills/incident/`, `AGENTS.rules.md`. Ship's `No match` bullet has two arms; both end in *a PIR exists*. The trip is **certain**, measured on this plan under both gates. | **Phase 3.2** adds a third disposition, two-conjunct-gated so it cannot become an escape hatch. |
| **R6.** implied: fenced blocks are already neutralised | The fence strip deletes fence lines **without leaving a boundary**. Measured: paragraph, fence with no blank lines, then a real outage claim → the strip runs straight through and silences the claim. | The fence strip emits a blank line per fence marker. Verified behaviour-neutral. F7 pins it. |
| **R7.** implied: `/^[[:space:]]*#/` means "a markdown heading" | **It matches any `#`-prefixed line — including a `#6691` continuation.** Measured on a reflow of F1 that differs only in where the line wraps: shipped `SIGNAL`, loose-`#` **`SIGNAL`** (the fix walks past its own target class), tightened `#+([[:space:]]\|$)` `no`. 5 of the 6 corpus "heading boundaries" are `#NNNN` issue refs, not headings. | Regex tightened to `/^[[:space:]]*#+([[:space:]]|$)/`. Same 260 corpus verdicts. **F9 pins it** — without F9 a future loosening reddens nothing. |
| **R8.** the draft's AC6c: "8 movers, all conditional" | **False. 5 of the 8 removed lines contain no `would`/`could`** and are not line-locally conditional (e.g. *"OAuth outage goes unsurfaced because the probe's own auth is flaky."*). An implementer running the AC honestly declares 5 defects and blocks the ship. It is also self-refuting: the whole premise is that conditionality is a property of **paragraph membership**, not of a line's grammar. | AC6c rewritten to test paragraph membership + absence of actuality, which is the real discriminator — and which is the strongest available argument for why a state machine is warranted rather than a wider `would\|could`. |
| **R9.** the draft's AC11 (diff-path allowlist) | **Unsatisfiable with the pipeline.** Ship Phase 2 auto-invokes `soleur:compound --headless`, which writes under `knowledge-base/project/learnings/` on a routine run. | AC11 includes `learnings/` and is inverted into a real assertion: **no** file under `.../post-mortems/`, the observable proof that Phase 3.2 fired instead of a fabricated PIR. |
| **R10.** the draft's F8 (anchor fixture) as described in one sentence | **Vacuous on one physical line.** Measured: `T7-oneline old=no new=no` — the untouched `grep -vaiE 'if this lands'` deletes the whole line, taking the outage claim with it. Only the wrapped two-line form works (`old=yes new=yes`), and only then can M8 redden. | The two-line requirement is stated in `## Files to Create`, in the F8 scenario row, and as an HTML comment **inside the fixture**, because "reproduce verbatim" in an appendix does not survive into the file. |
| **R11.** the draft's F2 | **Would have been vacuous** if its only `PROD_RE` token sat inside the stripped paragraph: the fixture then reads `no` under both scripts and M2/M7 pass for the wrong reason. The draft body passed only by the luck of where `is live.` wrapped. | F2 carries a production token in `## Overview`, **outside** the stripped paragraph, and the requirement is stated in `## Files to Create`. Verified: `shipped=yes, merged=yes, re-admit-deleted=no`. |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (**63** open) and searched each
body for `scripts/ship-incident-pir-gate.sh`, `plugins/soleur/test/ship-incident-pir-gate.test.ts`,
and `plugins/soleur/skills/ship/SKILL.md`. **None.**

## Files to Edit

- `scripts/ship-incident-pir-gate.sh` — (a) declare `ACTUALITY_RE` beside `OUTAGE_RE`/`PROD_RE`
  with its measured-vocabulary rationale; (b) fence strip emits a blank-line boundary; (c) insert
  the paragraph-strip `awk` stage with its ordering contract as **inline `#` comments inside the
  awk program**; (d) wrap the `haystack=` assignment in the fail-toward-PIR guard; (e) extend the
  strip-(3) header comment; (f) **delete** the stale "nine existing fixtures" sentence;
  (g) record the post-change signal rate.
- `plugins/soleur/test/ship-incident-pir-gate.test.ts` — add `signalsText()` beside `signals()`
  (same status contract, in-memory input) and the new tests. `signals()` unchanged.
- `plugins/soleur/skills/ship/SKILL.md` — the Phase 5.5 prose sentence (content anchor
  **"hypothetical framing before matching"**, 1 hit), and the Phase 3.2 meta-case disposition in the
  Incident-PIR Gate's `- **No match:**` bullet.
- `scripts/test-all.sh` — register the mutation battery.

## Files to Create

- `scripts/ship-incident-pir-gate-mutation.test.sh` — the executable battery (M1-M9), following the
  repo's 11 existing `*-mutation.test.sh` precedents.

Under `plugins/soleur/test/fixtures/ship-incident-pir-gate/` — bodies and measured verdicts in the
Appendix:

- `precedent-citation-inside-hypothetical-paragraph.md` (F1) — must **not** signal.
- `real-outage-claimed-inside-hypothetical-paragraph.md` (F2) — must signal. **Its `PROD_RE` token
  MUST live outside the stripped paragraph** (in `## Overview`); `PROD_RE` matches the whole
  haystack, so a fixture whose only production token is inside the paragraph reads `no` under both
  scripts and makes M2/M7 pass vacuously (R11).
- `real-outage-after-hypothetical-paragraph.md` (F3) — must signal.
- `real-outage-in-sibling-bullet.md` (F4) — must signal.
- `real-outage-after-heading-boundary.md` (F5) — must signal.
- `real-outage-in-nested-sub-bullet.md` (F6) — must signal.
- `real-outage-after-fenced-block-abutting-paragraph.md` (F7) — must signal.
- `midsentence-conditional-does-not-open-a-paragraph.md` (F8) — must signal. **The outage claim MUST
  sit on the physical line AFTER the one carrying `if this lands`** (R10); carry that constraint as
  an HTML comment inside the file.
- `reflowed-citation-with-issue-ref-continuation.md` (F9) — must **not** signal. Pins the tightened
  hash rule (R7).
- `real-outage-inside-paragraph-without-actuality-idiom.md` (F10) — must **not** signal. The
  **documented residual**: a real past-tense outage report inside the paragraph, phrased without an
  actuality idiom, is swallowed. A characterization test, so the hole lives in the suite rather than
  only in this plan.

Per `cq-test-fixtures-synthesized-only` every fixture is written fresh; the two that mirror real
documents mirror their *shape*, not their text.

## Implementation Phases

### Phase 0 — Preconditions (re-verify, do not inherit)

0.1 `awk --version`. Introduce no `{n,m}` intervals regardless.
0.2 `bun test plugins/soleur/test/ship-incident-pir-gate.test.ts` — baseline `16 pass, 0 fail`.
0.3 `git grep -n 'haystack' scripts/ship-incident-pir-gate.sh` — confirm one producer, one consumer
    line. The Guard Contract's Assembly claim; verify, do not assume.
0.4 `command -v shellcheck` — AC7 has no CI backstop.
0.5 Confirm the pipefail premise the Phase 2.4 guard rests on: a failing stage inside
    `haystack="$( … )"` propagates a non-zero assignment status, while a legitimately-empty haystack
    does not.

### Phase 1 — RED: fixtures + tests, before the script edit

1.1 Write the 10 fixtures (Appendix bodies, verbatim, including the in-file constraint comments).
1.2 Add `signalsText(text: string): boolean` beside `signals()`, sharing the status-0-or-1 contract.
1.3 Add the tests, each commented with the rule it pins: one per fixture (10), plus three in-memory:
    - **template anti-rot** — read `plugins/soleur/skills/plan/references/plan-issue-templates.md`,
      extract the first two `- **If this (lands broken|leaks)` lines **verbatim**, append an indented
      continuation carrying an `OUTAGE_RE` and a `PROD_RE` hit, assert no signal. If the template's
      wording or its `- **` prefix drifts, the anchored trigger stops matching and this reddens —
      the only mechanism stopping a silent revert to fires-on-every-plan. Verified at plan time.
    - **fail-toward-PIR** — spawn the gate with `PATH` prefixed by a temp dir holding an `awk` stub
      that exits 2; assert status 0 with `INCIDENT-SIGNAL: yes`. (Do **not** probe by emptying
      `PATH`: `env PATH=/nonexistent bash` cannot find `bash` and fails for the wrong reason.)
    - **concatenation seam** — build `PR_TEXT` ending on a trigger line, join with a single `\n` as
      `ship` does, then a plan body carrying a real outage claim; assert signal. No file fixture can
      observe this: every fixture is one document, and the seam is a two-document property.
1.4 Run the suite. **Exactly two tests must fail on `main`**: F1 and the fail-toward-PIR case. Every
    other new test must already pass — they pin behaviour the current gate has, and exist to stop
    the Phase 2 edit widening past its contract. (F9 and F10 also fail on `main`, in the sense that
    `main` *signals* on them; they are authored as must-**not**-signal, so they fail RED too —
    expect **four** failures if F9/F10 are written before Phase 2. Author F9/F10 in Phase 1 and
    record their `main` verdicts; the RED count is 4, not 2.)

### Phase 2 — GREEN: the strip widening

2.1 Declare the third vocabulary beside the existing two. **Its alternatives are measured, matching
    the discipline `OUTAGE_RE`'s own header states one comment block above:**

```bash
# The ONLY discriminator between "a plan citing a closed incident as precedent" and "a plan
# reporting an unreported outage" inside a hypothetical paragraph — the two are otherwise
# textually identical, so this is a whitelist, not a decision procedure.
# Vocabulary is MEASURED, not imagined: across the 4116 lines that fall inside a stripped
# paragraph in all 1548 plans, `already happened` hits 4x and `not hypothetical` 1x; every other
# phrasing tried (`this happened`, `did happen`, `has happened`, `actually happened|occurred|
# fired`) hit ZERO. `already occurred` is kept as the one unmeasured near-miss of the measured
# winner. Adding an alternative requires a corpus hit or a fixture — the same bar as OUTAGE_RE.
# Every fail-open found in the wild adds a phrase HERE and a fixture; do NOT widen or narrow the
# paragraph rule instead. **Why:** #7801 R3.
ACTUALITY_RE='already (happened|occurred)|not hypothetical'
```

2.2 Fence strip leaves a block boundary — one word, closing R6's measured fail-open:

```bash
  | awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; print ""; next} !f{print}' \
```

2.3 Insert the paragraph-strip stage after the `[Nn]etwork-[Oo]utage` sed, before the `grep -vaiE`.
    **The ordering contract lives in the code**, because an awk program reads as a set of
    *independent* cases and gives no hint that it is ordered:

```bash
  | awk -v ACTUALITY_RE="$ACTUALITY_RE" 'BEGIN{skip=0}
       # --- ORDER IS THE DESIGN (#7801). Boundaries reset; the trigger opens; the re-admit closes.
       # A block boundary always prints and can never be eaten as paragraph body, so these come first.
       # The hash rule requires a space or EOL after the run of `#` — a bare /^[[:space:]]*#/ treats a
       # `#6691` continuation line as a heading and lets the outage claim after it through, which
       # defeats this fix on a reflow of its own target class (R7). Tables and blockquotes are NOT
       # boundaries: an accepted residual, listed here so the omission is deliberate, not forgotten.
       /^[[:space:]]*$/                                 {skip=0; print; next}
       /^[[:space:]]*#+([[:space:]]|$)/                 {skip=0; print; next}
       # The label line. ANCHORED, and ABOVE the list-item rule so a bulleted label is consumed
       # rather than read as a new block. The anchor bounds a STATEFUL rule: unanchored, one
       # subordinate clause silences a whole paragraph. This trigger list is a deliberate SUBSET of
       # the line-scoped `grep -vaiE` below (no `would break`/`could break`: those are mid-sentence
       # conditionals, and paragraph-scoping them would swallow arbitrary prose).
       tolower($0) ~ /^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)?[*_]*if this (lands|leaks)/ {skip=1; next}
       # A NEW list item is a NEW markdown block. (A nested sub-bullet also resets — deliberate,
       # and the fail-toward-fire direction.)
       /^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)/ {skip=0; print; next}
       # Once a paragraph says the event HAPPENED, the rest of it is an incident report.
       tolower($0) ~ ACTUALITY_RE                       {skip=0; print; next}
       # --- Rules below run only inside a skip window. Do NOT append past this line: it is dead code.
       skip                                             {next}
                                                        {print}' \
```

2.4 Wrap the assignment so a broken strip stage fires rather than falls silent. On a customer's
    unpinned `awk` a failed stage otherwise empties the haystack → exit 1 → indistinguishable from
    a clean no-signal, with no probe anywhere (the gate's surface is layer 7; CI is not present
    there):

```bash
if ! haystack="$(cat \
  … pipeline … )"; then
  echo "INCIDENT-SIGNAL: yes"
  echo "ship-incident-pir-gate: strip pipeline failed — failing toward PIR (#7801)" >&2
  exit 0
fi
```

2.5 Extend the strip-(3) header comment (paragraph scope, the three boundaries **and the two
    omitted ones**, the re-admit, the fence boundary, and the decision that the strip is lexical and
    cannot decide precedent-vs-self-report). Keep the `**Why:** #NNNN` style. **Delete** the stale
    "nine existing fixtures" sentence rather than re-numbering it.
2.6 **Phase 2 exit gate — run the corpus sweep here, not in Phase 4.** The prototype-to-script
    transfer (quoting inside `haystack="$(cat | awk '…')"`, stage position) is where divergence
    appears; finding it after ten fixtures are written is the rework path. Emit
    `"${TMPDIR:-/tmp}/pir-corpus-sweep.txt"` with one `path<TAB>before<TAB>after` row per plan plus
    the quoted removed line for each mover, and record the post-change signal rate.
2.7 Re-run the suite: all 16 pre-existing plus all 13 new tests green.

### Phase 3 — Consumer prose and the meta-case disposition

3.1 Update the Phase 5.5 sentence in `plugins/soleur/skills/ship/SKILL.md`.
3.2 **Add a third disposition to the Incident-PIR Gate's `- **No match:**` bullet**, available in
    **both** modes. Without it this PR has no legal exit (R5) — and note that under
    `/soleur:one-shot` step 7, ship is invoked with no `--headless`, so `HEADLESS_MODE=false` and
    the flow reaches an *interactive* prompt inside an unattended loop whose continuation gate
    forbids handing off to the operator.

    > **Meta-case — the PR's subject IS this gate.** When `git diff --name-only origin/main...HEAD`
    > includes `scripts/ship-incident-pir-gate.sh` **and** the PR body carries a line
    > `INCIDENT-PIR: meta-case — <one sentence naming why no production event occurred>`, record
    > that line and proceed **without** a PIR.

    **Why both conjuncts — verified against git history, not asserted.** A diff-only predicate is
    unsafe, and the repo contains the counter-example. Issue **#7242** ("Web Platform Release blocked
    at the zot mirror … prod is 3 releases behind") was a real production delivery outage; the PR
    that fixed it, **#7244** (commit `d31d8a2c7`), **edited `scripts/ship-incident-pir-gate.sh`**
    — adding the `releases? behind` alternation — *and* shipped
    `knowledge-base/engineering/operations/post-mortems/…-zot-mirror-blocked-releases-…-postmortem.md`
    in the same commit. A diff-only meta-case arm would have waved that PIR through. The
    declaration is the conjunct that separates the two cases: a PR editing the gate *because of* a
    production event omits the line and gets the normal requirement. A false declaration is a
    deliberate, recorded act — the same trust model as every `[ack]` in this repo.

### Phase 4 — Verification

4.0 **Materialize the baseline gate once**, before any AC that compares against it:
    `git show origin/main:scripts/ship-incident-pir-gate.sh > "${TMPDIR:-/tmp}/pir-gate-main.sh"`;
    assert non-empty; then **self-check** — `bash "$BASELINE" < <known-negative fixture>` must exit
    **1**. An all-`yes` baseline is the signature of the R4 stdin collision and is otherwise
    indistinguishable from a real result. Invoke only as `bash "$BASELINE" …`.
4.1 `shellcheck -S style` on the gate and the battery → rc 0.
4.2 Read the Phase 2.6 artifact; apply AC6c to every mover; carry the quoted lines and the signal
    rate into the PR body.
4.3 `bash scripts/ship-incident-pir-gate-mutation.test.sh` → every mutation RED.
4.4 `bash scripts/test-all.sh bun`.
4.5 `python3 scripts/lint-guard-contract.py` against this plan.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** ~~reports **29 pass, 0 fail** (16 pre-existing + 10 fixture + 3 in-memory)~~ —
  **AMENDED at /work: 36 pass, 0 fail.** The plan's arithmetic was wrong before review even ran
  (it omitted the template anti-rot, fail-toward-PIR and concatenation-seam tests and counted a
  3-case `test.each` as one), and review then added four more: the bulleted-label fixture, the
  `already occurred` inflection, the actuality-outranks-conditional case, and the residual
  stderr note. The number was a prediction; 36 is the measurement.
- **AC2** All **15** pre-existing fixtures keep their verdicts, with the input set enumerated from
  `origin/main` so the 10 new fixtures cannot enter it (a working-tree glob would contain them, and
  AC3 *requires* one of those to move):

  ```bash
  for b in $(git ls-tree --name-only origin/main plugins/soleur/test/fixtures/ship-incident-pir-gate/); do
    o=$(git show "origin/main:$b" | bash "$BASELINE" >/dev/null 2>&1 && echo yes || echo no)
    n=$(git show "origin/main:$b" | bash scripts/ship-incident-pir-gate.sh >/dev/null 2>&1 && echo yes || echo no)
    [ "$o" = "$n" ] || echo "MOVED: $b $o -> $n"
  done
  ```

  emits nothing.
- **AC3** F1 signals under `$BASELINE` and does **not** signal under the merged script. Both
  directions, so it cannot be vacuous.
- **AC4** F2-F8 each signal under **both** binaries.
- **AC5** F9 and F10 signal under `$BASELINE` and do **not** signal under the merged script. F9 is
  the tightened-hash pin (R7); F10 is the documented residual (Property 3).
- **AC6** Corpus sweep, asserted as **direction-and-identity** invariants rather than a count,
  because the corpus grows under sibling sessions (`cq-ac-must-not-depend-on-concurrent-sessions`):
  - **AC6a** No plan moves `no -> yes`. **Structural, not empirical:** the awk stage only ever drops
    whole records and both matchers are line-oriented, so removing lines cannot create a match.
    Recorded as an invariant; a violation would mean the stage is *rewriting* records rather than
    filtering them, which is the only defect this row can detect.
  - **AC6b** `knowledge-base/project/plans/2026-08-01-release-outcome-email-step-env-refs-plan.md`
    signals under **both** binaries — the corpus's own instance of F2.
  - **AC6c** Every `yes -> no` mover is inspected and its removed line quoted in the PR body. For
    each, both must hold: **(a)** the line sits inside a paragraph opened by an anchored
    `If this lands`/`If this leaks` label, and **(b)** the line asserts no actuality (matches none
    of `ACTUALITY_RE`). A move failing either is a defect. Observed at plan time: 8 movers — three
    conditional in their own grammar ("…would go unpaged"), five consequent clauses or precedent
    citations whose only hypothetical marker is the label two lines above. That five is precisely
    the class this change exists to strip, and precisely why a line-local `would|could` widening
    could not have fixed it. The count is evidence, never a threshold. **Do not test conditionality
    line-locally** — the premise of the whole change is that conditionality is a property of
    paragraph membership (R8).
- **AC7** `shellcheck -S style` exits 0 on `scripts/ship-incident-pir-gate.sh` and
  `scripts/ship-incident-pir-gate-mutation.test.sh`.
- **AC8** `grep -c 'nine existing' scripts/ship-incident-pir-gate.sh || true` prints **0**, and the
  same grep against `$BASELINE` prints **1**. Both directions, because the full-sentence anchor
  (`nine existing fixtures`) returns 0 on unmodified `main` and is therefore unfalsifiable (R1).
  `|| true` per `hr-when-a-command-exits-non-zero-or-prints` — `grep -c` exits 1 on zero matches.
- **AC9** `grep -cF 'hypothetical framing **paragraph**' plugins/soleur/skills/ship/SKILL.md || true`
  prints ≥ 1 — anchored on the literal bytes the edit writes, emphasis markers included, not on its
  reading (R8).
- **AC10** ~~`grep -c 'ORDER IS THE DESIGN'` >= 1~~ — **AMENDED at /work: the ordering contract
  is pinned by mutation rows M7 and M11, not by a prose literal.** Measurement falsified the
  prose: exactly ONE of the five orderings is load-bearing (re-admit above `skip{next}`, 2
  movers), plus the re-admit-above-DROP_RE precedence which a fixture pins. The original AC made
  a sentence a merge condition, so correcting the sentence would have failed the gate — an AC
  that pins prose is a standing veto on fixing the prose. Replaced with:
  `grep -cE '^run_row M(7|11) ' scripts/ship-incident-pir-gate-mutation.test.sh` = 2.
- **AC11** `git diff --name-only origin/main...HEAD | grep -vE '^(scripts/|plugins/soleur/test/|plugins/soleur/skills/ship/|knowledge-base/project/(plans|specs|learnings)/)' | grep .`
  emits nothing, **and** no path under `knowledge-base/engineering/operations/post-mortems/` appears
  in the diff. `learnings/` is allowed because ship Phase 2 auto-invokes `compound`; the
  post-mortems exclusion is the observable proof that Phase 3.2 fired instead of a fabricated PIR
  (R9).
- **AC12** ~~exits 0 and reports **9** mutations~~ — **AMENDED at /work: 11 mutation rows, 20
  assertions.** M10 (the fail-toward-PIR guard) and M11 (the re-admit precedence) were added
  after the plan. A run reporting `0 mutations` still fails. A run reporting `0 mutations` fails — a
  battery that dispatches nothing is the vacuity it exists to prevent.
- **AC13** The PR body carries the `INCIDENT-PIR: meta-case — …` declaration and the post-change
  signal rate.
- **AC14** `bash scripts/test-all.sh bun` is green and
  `grep -c 'ship-incident-pir-gate-mutation' scripts/test-all.sh || true` ≥ 1.
- **AC15** `python3 scripts/lint-guard-contract.py <this plan>` exits 0.

### Post-merge

- **AC-PM1** On the first `/ship` after merge, the Phase 5.5 line prints and the verdict matches the
  prediction recorded for that PR. The artifact has no deploy surface, but its *effect* is the
  merge-boundary gate for every subsequent PR here and on every customer's CLI; this is the only
  end-to-end observation of the thing that changed.

## Test Scenarios

| # | Fixture / test | Shape | Expected | Rule pinned |
| --- | --- | --- | --- | --- |
| F1 | `precedent-citation-inside-hypothetical-paragraph.md` | closed-incident citation on a wrapped continuation line, `(#6691)` mid-line | **no signal** | the widening itself |
| F2 | `real-outage-claimed-inside-hypothetical-paragraph.md` | "This already happened — the outage began…"; **prod token in `## Overview`** | **signal** | `ACTUALITY_RE` re-admit |
| F3 | `real-outage-after-hypothetical-paragraph.md` | claim in the next paragraph after a blank line | **signal** | blank-line boundary |
| F4 | `real-outage-in-sibling-bullet.md` | label and claim as sibling bullets, no blank line | **signal** | list-item boundary |
| F5 | `real-outage-after-heading-boundary.md` | label line, then `## Context` with no blank line, then the claim | **signal** | hash boundary |
| F6 | `real-outage-in-nested-sub-bullet.md` | claim as an indented sub-bullet under the label | **signal** | list-item rule reaches nested items (fail-toward-fire, deliberate) |
| F7 | `real-outage-after-fenced-block-abutting-paragraph.md` | label, fence with no blank lines, then the claim | **signal** | fence emits a boundary (R6) |
| F8 | `midsentence-conditional-does-not-open-a-paragraph.md` | `even if this lands out of order` on line A; the outage claim on **line B**. Line A is line-stripped under both scripts; line B survives only because the trigger is anchored | **signal** | trigger anchoring (R10) |
| F9 | `reflowed-citation-with-issue-ref-continuation.md` | F1 reflowed so the continuation line begins `#6691,` | **no signal** | tightened hash rule (R7) — under a bare `#` this signals and the fix fails |
| F10 | `real-outage-inside-paragraph-without-actuality-idiom.md` | "On 2026-07-30 the outage began and no notification was ever sent." inside the paragraph | **no signal** | **characterization test**: the accepted fail-open residual (Property 3) |
| F11 | template anti-rot (in-memory) | label lines extracted verbatim from `plan-issue-templates.md` + a continuation carrying outage & prod tokens | **no signal** | the anchor still matches the live template |
| F12 | fail-toward-PIR (in-memory) | gate spawned with an `awk` stub exiting 2 | **signal**, status 0 | the Phase 2.4 guard (Property 5) |
| F13 | concatenation seam (in-memory) | PR body ending on a trigger line, joined by a single `\n` to a plan carrying a real outage claim | **signal** | skip state must not survive the seam |
| — | (existing 15) | unchanged | unchanged | non-regression |

## User-Brand Impact

- **If this lands broken, the user experiences:** two failure directions, both on the Soleur CLI
  the customer runs themselves. Over-strip → `/ship` stays silent on a real production incident and
  the customer's outage ships with no post-incident report, so the learning is lost and the same
  outage recurs. Under-strip → `/ship` demands a PIR on an ordinary planning PR and authors a report
  for an event that never happened, filling the customer's post-mortem directory with fiction and
  training them to walk past a red gate.
- **If this leaks, the user's data / workflow / money is exposed via:** nothing. The gate reads text
  on stdin, writes one line to stdout, opens no socket, touches no credential, persists nothing.
- **Brand-survival threshold:** `aggregate pattern` — no single run is brand-fatal; the damage is
  erosion accumulated across many PRs, the shape #6813 named.

## Observability

```yaml
liveness_signal:
  what: "the /ship Phase 5.5 line `gate: incident signal — a PIR is required (see below).` or `gate: no incident signal.`"
  cadence: "once per /ship invocation"
  alert_target: "the operator's own session — a local CLI gate with no server surface"
  configured_in: "plugins/soleur/skills/ship/SKILL.md, Phase 5.5"
error_reporting:
  destination: "stderr of the calling shell; the bun suite treats any status other than 0 or 1 as a harness failure"
  fail_loud: true
failure_modes:
  - mode: "a strip stage errors on a customer's unpinned awk and emits nothing"
    detection: "IN-SURFACE. Without the guard this degrades to an empty haystack -> exit 1, indistinguishable from a clean no-signal on the customer's box with no probe. The Phase 2.4 guard makes it the loud arm: stdout `INCIDENT-SIGNAL: yes` plus a named stderr diagnostic. (Portability is NOT the concern - the program produces identical output under mawk 1.3.4, busybox awk and nawk - which is exactly why an untreated residual failure would be silent rather than loud.)"
    alert_route: "the operator's own terminal (layer 7); pinned in CI by test F12"
  - mode: "the strip widens past its contract and swallows a real outage claim"
    detection: "fixtures F2-F8 stop signalling"
    alert_route: "CI job test-bun; mutation rows M2-M7"
  - mode: "the strip silently stops firing and the false positive returns"
    detection: "fixture F1 starts signalling"
    alert_route: "CI job test-bun; mutation row M1"
  - mode: "the hash boundary is loosened back to a bare `#`, so a `#NNNN` continuation line becomes a false boundary and the fix walks past its own target class"
    detection: "fixture F9 starts signalling"
    alert_route: "CI job test-bun; mutation row M4"
  - mode: "the plan template's label wording drifts, the anchored trigger stops matching, and the gate silently reverts to fires-on-every-plan"
    detection: "test F11, which extracts the label lines from the live template rather than a copy"
    alert_route: "CI job test-bun"
logs:
  where: "the gate writes no log file. Its entire output is one stdout line consumed by /ship Phase 5.5, plus the Phase 2.4 stderr diagnostic; both land in the operator's terminal transcript. The durable record is the PR body, which carries the verdict, the corpus signal rate, and (on a meta-case) the INCIDENT-PIR declaration."
  retention: "the operator's terminal session; the PR body is permanent. No server-side sink exists or is warranted for a local CLI gate that persists nothing."
discoverability_test:
  command: "bun test plugins/soleur/test/ship-incident-pir-gate.test.ts"
  expected_output: "29 pass, 0 fail"
```

Observability layer **7** per `hr-observability-layer-citation` — code under `plugins/` and
`scripts/` executing on a customer's self-hosted CLI. The suite is the layer-7 probe **for the
merged gate's verdicts**; the pre-change/post-change comparisons in AC2-AC5 are one-time PR-time
checks with no CI backstop, as is AC7's shellcheck — a later regression in the *relative* property
would not be caught. The customer-side gap is closed **in the surface itself** by the Phase 2.4
guard rather than by more CI, since the customer never runs `bun test`.

## Guard Contract

### Guard 1 — the Incident-PIR hypothetical-paragraph strip

**Property.** No line of a plan's hypothetical impact paragraph — the paragraph opened by an
anchored `If this lands …` / `If this leaks …` label — contributes outage vocabulary to the
Incident-PIR haystack, **unless** it matches `ACTUALITY_RE`; every line outside that paragraph still
contributes; and the gate never falls silent because a strip stage failed.

**Assembly.** The chokepoint is the single `haystack="$( … )"` pipeline in
`scripts/ship-incident-pir-gate.sh`. `git grep -n 'haystack' <file>` returns four hits: two prose
comments, the sole producer, and the sole consumer line carrying both herestrings; `OUTAGE_RE` and
`PROD_RE` appear only at their definitions, in comments, and on that consumer line. There is no
other path by which text reaches either matcher. Stated structurally rather than as an enumeration
of today's stages, so a stage added later is inside the assembly by construction. On the harness
side the chokepoints are `signals()` and `signalsText()`, which share one status contract and spawn
the **shipped** script.

**Mutation matrix.** Every row is executed by `scripts/ship-incident-pir-gate-mutation.test.sh`,
which mutates a sandbox copy and requires at least one fixture verdict to flip. Rows that would only
re-assert `main`'s pre-existing harness (that `spawnSync` returns 127, that `readFileSync` throws)
are deliberately **absent**: this diff does not own them, and 16 existing tests already exercise
them.

| # | Mutation | Fixture that reddens | Why no other row covers it |
| --- | --- | --- | --- |
| M1 | Delete the paragraph-strip awk stage | F1 signals | the widening's own presence |
| M2 | Delete the `ACTUALITY_RE` re-admit rule | F2 stops signalling | the only fail-open guard on the widening; measured load-bearing on a real corpus plan |
| M3 | Delete the blank-line boundary rule | F3 stops signalling | a second member after M1's compliant first — the window would run to EOF |
| M4 | Loosen the hash rule to `/^[[:space:]]*#/` | F9 signals | measured: the loose form lets a reflow of F1 through, i.e. the fix fails on its own target class. Invisible to F5, which uses a real heading. |
| M5 | Delete the hash boundary rule entirely | F5 stops signalling | M4 tests the regex; this tests the rule's presence |
| M6 | Delete the list-item boundary rule | F4 **and** F6 stop signalling | sibling- and nested-block semantics; measured to save 2 real corpus plans |
| M7 | **Reorder** `skip {next}` above the `ACTUALITY_RE` rule | F2 stops signalling | a delete-only battery cannot see an ordering defect; this observes the property *inside* the window it is about |
| M8 | Un-anchor the trigger | F8 stops signalling | measured **identical** on all 1548 plans — only a constructed fixture can see it. The anchor bounds a *stateful* rule: unanchored, one subordinate clause silences a whole paragraph, a different risk class from the line-scoped `grep -vaiE` beside it. |
| M9 | Revert the fence strip's `print ""` | F7 stops signalling | measured fail-open (R6); invisible to every other fixture |

**Harness rows.** Edits to the SUITE (not the gate), plus a must-PASS non-canonical:

| # | Harness edit | Expected |
| --- | --- | --- |
| H1 | Make the battery's mutation loop a no-op | AC12's "9 mutations" assertion fails. Pins the battery's **own dispatch**: a battery reporting `0 mutations` and exiting 0 is exactly the vacuity it exists to prevent. |
| H2 | **must-PASS, non-canonical:** F3 is a permitted variation of the canonical F1 — the same sentence, one blank line down — and must pass with the **opposite** verdict. F11 is a second such input, generated at runtime from a file this PR does not edit. A suite whose only must-PASS input is the canonical cannot detect a strip that rejects everything. |

## Architecture Decision (ADR/C4)

**Not applicable — no ADR, no C4 change.** Verified independently: `model.c4` carries a `ship`
component but **no node for the gate script**; `views.c4` and `spec.c4` carry nothing;
`principles-register.md` ends at AP-024 and none of AP-001..024 bear on a lexical strip inside a
local CLI gate. The change adds no external human actor, no external system or vendor, no container
or store, and no actor↔surface relationship — the gate's single edge, `/ship` →
`scripts/ship-incident-pir-gate.sh`, predates this change and is unchanged. The decision the gate
embodies (fail-toward-PIR when uncertain) is **preserved and strengthened**, not reversed. The
repo's recorded pattern for this gate's narrowings (#6665, #7003, #7242) is a `**Why:**` header
comment in the script, which Phase 2.5 follows — including the decision that the strip is lexical,
cannot decide precedent-vs-self-report, and accepts a named residue.

## Domain Review

**Domains relevant:** none

Internal engineering tooling. `## Files to Create`/`## Files to Edit` contain no
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, and no path matching the shared
UI-surface term list, so the mechanical UI-surface override does not fire and the Product/UX gate is
`NONE`. No regulated-data surface (2.7 skips), no infrastructure (2.8 skips), no persistent store or
new cross-component connection (2.11 skips).

`lane:` is `cross-domain` because no
`knowledge-base/project/specs/feat-one-shot-7801-pir-gate-paragraph-strip/spec.md` exists to carry
one forward. Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). That is the
fail-closed default, not a judgement; the sweep above is the judgement.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A real outage claim inside the hypothetical paragraph is swallowed | **Measured: 1 of 1548 plans under the naive design** | fail-open — an incident ships with no PIR (#7242 class) | `ACTUALITY_RE`; F2; mutation rows M2/M7; AC6b names the plan by path |
| **The strip is lexical and cannot decide precedent-vs-self-report.** Both are past-tense outage claims inside the hypothetical paragraph; only an actuality idiom separates them, and widening the idiom list to catch more real reports necessarily re-admits F1 and undoes the fix | inherent | fail-open on any phrasing outside `ACTUALITY_RE` — demonstrated: dropping "This already happened" from the R3 plan's sentence silences it | Named openly rather than papered over: Property 3 is scoped to the enumerated idioms, F10 pins the residual as a characterization test, and the decision is recorded in the script header. The date/duration-anchor variant that would close it was measured and **rejected** because it un-fixes the motivating case (Cut List). If a future incident is missed here the answer is section restructuring — move precedent citations out of `## User-Brand Impact` — not a bigger whitelist. |
| A bare `#` hash rule treats a `#NNNN` continuation as a boundary, defeating the fix on a reflow of its own target class | **Measured: reproducible** | the fix silently does not fix | tightened to `#+([[:space:]]\|$)`; F9; mutation row M4 |
| A fenced block merges the paragraph with a following real claim | **Measured: reproducible** | fail-open | fence strip emits a boundary; F7; M9 |
| A broken strip stage on an unpinned `awk` silently empties the haystack | low, undetectable without the guard | fail-open with no probe | Phase 2.4 guard; F12; verified with an `awk` stub |
| An unanchored `if this lands` mid-sentence swallows an unrelated paragraph | low | fail-open | anchored trigger; F8; M8 |
| The paragraph skip state crosses the `PR_TEXT`/`PLAN_TEXT` seam — ship joins them with `printf '%s\n%s'`, one newline, not a blank line | low | fail-open across two documents | rescued by the heading rule (measured), and pinned by in-memory test F13, because no single-document fixture can observe a two-document property |
| Tables and blockquotes are not treated as block boundaries | low | fail-open | accepted residual, named in the header comment so the omission is deliberate |
| The inline-code `sed` turns a line into whitespace, faking a boundary | low | fail-toward-**fire** | accepted; the safe direction |
| **This plan trips its own gate at Phase 5.5** | **certain — measured `INCIDENT-SIGNAL: yes` under both the shipped and the fixed gate** (~17 residual hits, all Overview/Property-List/Reconciliation/Risks prose the widening cannot touch) | ship demands a PIR for an event that never happened | Phase 3.2's disposition, a **blocking phase**, not a note. AC13 asserts the declaration; AC11 asserts no post-mortem landed. |
| Under `/soleur:one-shot`, ship runs with `HEADLESS_MODE=false`, so the flow reaches an *interactive* prompt inside an unattended loop | certain on this dispatch path | the agent self-answers and authors fiction | Phase 3.2's disposition is **mode-independent**. The durable fix is out of subsystem — see Deferred Items. |
| Six residual `outage` hits keep the #7793 plan signalling and a reader concludes the fix failed | medium | confusion, not defect | R2 records it; the header's "Residual (accepted)" note names this instance |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold fails `deepen-plan` Phase 4.6.
- **Rule order inside the awk block is the design, not formatting** — and an awk program *looks*
  unordered, which is why the contract is inline comments plus AC10 rather than prose here. Three
  traps, in likelihood order: (1) grouping or alphabetising moves the list-item boundary above the
  anchored trigger and silently stops bulleted labels from stripping; (2) a rule appended after
  `skip {next}` — the natural place — is dead code; (3) a boundary rule copied from the shape of
  `skip {next}` instead of the blank-line rule omits `skip=0`.
- **The re-admit cannot distinguish a cited precedent from a reported incident.** Widening its
  vocabulary to catch more real reports necessarily re-admits F1 and undoes the fix.
- **Two trigger lists now live in one pipeline** — the awk owns `if this (lands|leaks)` at paragraph
  scope; the `grep -vaiE` owns a wider set at line scope. The awk list is a deliberate **subset**;
  the header comment says so, because otherwise a future edit to one silently diverges from the
  other.
- **`git show origin/main:<script> | bash` is silently vacuous.** `bash` consumes the script from
  stdin and the gate's own `cat` eats the rest, so it returns exit 0 for every input including
  empty — which the caller's contract reads as a signal. Materialize to a file, and self-check the
  baseline against a known-negative fixture.
- **CI does not shellcheck repo-root scripts.** A green CI does not mean the script is lint-clean.
- A full-sentence grep anchor can straddle a comment line break and be **vacuous** (`nine existing
  fixtures` returns 0 today). Anchor on the shortest token that survives wrapping, assert both
  directions, and `|| true` the `grep -c`.
- The gate is **blocking**: a false positive costs a fabricated post-mortem, not a warning.

## Alternative Approaches Considered

| Approach | Why rejected |
| --- | --- |
| Strip the entire `## User-Brand Impact` **section** | Destroys property 2, and contradicts strip (4)'s heading-line-only design, which has a both-directions test pinning it. It would also have silenced the 2026-08-01 plan outright. |
| Negative lookahead in `OUTAGE_RE` for precedent shapes | The script header records the repo's choice: labels and gate names are **stripped** so the token cannot reach `OUTAGE_RE`, "not added to a negative lookahead". Also unavailable in ERE under the host grep. |
| Modal-inversion re-admit | **Measured: 0 verdicts move on 1548 plans** — the conditionality lives on the label line the trigger consumes. |
| Date/duration actuality-anchor re-admit | Measures clean and closes the paraphrase hole, but re-admits any **dated** citation including the `#6691`/`~8h15m` shape that motivated the issue — it would un-fix the reported bug while appearing to strengthen the gate. |
| Sentence-scope instead of paragraph-scope | Sentence segmentation over prose with version numbers, ellipses and `e.g.` is not reliably regex-expressible; a paragraph is the natural cheaply-bounded unit. |
| Widen further to silence the six residual hits on the #7793 plan | A different, much larger class — planning prose about a hypothetical outage the plan exists to *prevent*. Silencing it guts the posture for a whole document class. |
| An mdast/remark parser | A Node/bun dependency on a self-hosted customer CLI adds a failure mode (missing runtime → gate silent → fail-open) worse than the false positives it fixes, and breaks the "the test invokes the shipped script" property that makes drift impossible. |
| A diff-only predicate for the Phase 3.2 meta-case arm | Unsafe: #7242 was a real delivery outage whose fix edited this very script and owed a PIR. |

## Deferred Items

- **`/soleur:one-shot` invokes `soleur:ship` without `--headless`**, so `HEADLESS_MODE=false` inside
  an unattended loop and every ship prompt lands on an interactive arm no one can answer. Confirmed
  at `plugins/soleur/skills/one-shot/SKILL.md` step 7 against `plugins/soleur/skills/ship/SKILL.md`
  ("If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true`"). Out of the ship-gate
  subsystem and far wider than this fix — it changes the mode of every ship phase. Phase 3.2's
  mode-independent disposition closes it for this PR. **File a `type/chore` issue**, re-evaluation
  criterion: *"every ship phase whose headless and interactive arms differ has been audited for
  one-shot's dispatch path."*

## Appendix — fixture bodies (measured, not sketched)

These are **synthesized fixtures**, not incident reports; no event described below occurred. Every
body was run through both the shipped script and the final prototype during planning, and the
recorded verdicts are measurements. Two carry in-file constraint comments because the constraint
does not survive a copy-paste otherwise (R10, R11).

**F1 `precedent-citation-inside-hypothetical-paragraph.md`** — old: signal, new: **no signal**

```markdown
---
title: "chore: migrate the docs site to Cloudflare Pages"
brand_survival_threshold: single-user incident
---

# chore: migrate the docs site

## User-Brand Impact

**If this lands broken, the user experiences:** the apex serving a Cloudflare
error page, a stale build, or NXDOMAIN — the only surface a prospective user
meets before signing up, dark or wrong. The 2026-08-16 precedent (#6691) was an
~8h15m apex outage from the same host, and it is the reason this plan exists.

**Brand-survival threshold:** `single-user incident`

## Rollout

The cutover is ordered so the new address exists before the old one is removed.
Deployed behind a two-call sequence with a rollback at every step.
```

**F2 `real-outage-claimed-inside-hypothetical-paragraph.md`** — old: signal, new: **signal**;
re-admit deleted: **no signal** (so M2/M7 redden non-vacuously)

```markdown
---
title: "fix: restore release-outcome notification"
brand_survival_threshold: single-user incident
---

<!-- The production token MUST stay in ## Overview, OUTSIDE the stripped paragraph.
     PROD_RE matches the whole haystack; a fixture whose only prod token is inside
     the paragraph reads `no` under both scripts and makes M2/M7 vacuous. -->

# fix: restore the release-outcome notification

## Overview

The release-outcome notification step lost its env refs and the production
pipeline stopped reporting.

## User-Brand Impact

**If this lands broken, the user experiences:** the pipeline silently stops taking
new builds while every surface reports healthy. The operator merges work for days
believing all is well. This already happened — the outage began ~2026-07-30 and no
notification was ever sent.
```

**F3 `real-outage-after-hypothetical-paragraph.md`** — old: signal, new: **signal**

```markdown
---
title: "fix: restore the apex"
brand_survival_threshold: single-user incident
---

# fix: restore the apex

## User-Brand Impact

**If this lands broken, the user experiences:** the apex serving an error page.

The 2026-08-16 apex outage took the production site down for ~8h15m and is the
event this PR reports.
```

**F4 `real-outage-in-sibling-bullet.md`** — old: signal, new: **signal**

```markdown
# fix: apex

## User-Brand Impact

- **If this lands broken, the user experiences:** an error page.
- The 2026-08-16 apex outage took the production site down for ~8h15m.
```

**F5 `real-outage-after-heading-boundary.md`** — old: signal, new: **signal** (no blank line before
the heading — that is the point)

```markdown
# fix: apex

## User-Brand Impact

**If this lands broken, the user experiences:** an error page at the apex.
## Context
The 2026-08-16 apex outage took the production site down for ~8h15m.
```

**F6 `real-outage-in-nested-sub-bullet.md`** — old: signal, new: **signal**

```markdown
# fix: apex

## User-Brand Impact

- **If this lands broken, the user experiences:**
  - the 2026-08-16 apex outage took the production site down for ~8h15m.
```

**F7 `real-outage-after-fenced-block-abutting-paragraph.md`** — old: signal, new: **signal**; without
the Phase 2.2 boundary this fixture goes dark. No blank lines around the fence — that is the point.

```markdown
# f

## User-Brand Impact

**If this lands broken, the user experiences:** an error page.
```
code
```
The 2026-08-16 apex outage took the production site down in production.
```

**F8 `midsentence-conditional-does-not-open-a-paragraph.md`** — old: signal, new: **signal**;
unanchored trigger: **no signal**

```markdown
<!-- The outage claim MUST stay on the line AFTER the one carrying `if this lands`.
     On one physical line the untouched `grep -vaiE` deletes the whole line, the
     fixture reads `no` under both scripts, and mutation M8 cannot redden. -->

# fix: apex ordering

## Rollout

The cutover is safe even if this lands out of order, because the 2026-08-16 apex
outage took the production site down for ~8h15m and we reordered the calls so it
cannot recur.
```

**F9 `reflowed-citation-with-issue-ref-continuation.md`** — old: signal, new: **no signal**; with a
bare `#` hash rule: **signal** (i.e. the fix fails)

```markdown
# c

## User-Brand Impact

**If this lands broken, the user experiences:** a stale build at the apex, the
only surface a prospective user meets before signing up. The precedent is
#6691, an ~8h15m apex outage on production from the same host, and it is the
reason this plan exists.
```

**F10 `real-outage-inside-paragraph-without-actuality-idiom.md`** — old: signal, new: **no signal**.
Characterization test for the accepted residual: a real past-tense outage report inside the
paragraph, phrased without an actuality idiom, is swallowed. If a future change closes this hole,
this fixture's expectation flips — deliberately, and visibly.

```markdown
---
title: "fix: restore release-outcome notification"
---

# fix: restore the release-outcome notification

## Overview

The release-outcome step lost its env refs and the production pipeline stopped reporting.

## User-Brand Impact

**If this lands broken, the user experiences:** the pipeline silently stops taking
new builds while every surface reports healthy.
On 2026-07-30 the outage began and no notification was ever sent.
```
