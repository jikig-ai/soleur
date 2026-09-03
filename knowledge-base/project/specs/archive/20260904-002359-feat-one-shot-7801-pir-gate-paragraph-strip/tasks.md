# Tasks — fix(ship): Incident-PIR gate paragraph strip (#7801)

Plan: `knowledge-base/project/plans/2026-09-03-fix-ship-pir-gate-paragraph-strip-plan.md`
Branch: `feat-one-shot-7801-pir-gate-paragraph-strip`
Lane: `cross-domain` (spec lacked a valid `lane:` — fail-closed default)

Phase order is load-bearing: the script's contract changes (Phase 2) before any consumer prose
describes it (Phase 3).

## Phase 0 — Preconditions

- [x] **0.1** `awk --version`. Use no `{n,m}` interval expressions regardless of the answer.
- [x] **0.2** `bun test plugins/soleur/test/ship-incident-pir-gate.test.ts` — record the baseline
      (expect `16 pass, 0 fail`).
- [x] **0.3** `git grep -n 'haystack' scripts/ship-incident-pir-gate.sh` — confirm one producer and
      one consumer line. This is the Guard Contract's Assembly claim.
- [x] **0.4** `command -v shellcheck` — AC7 has no CI backstop.
- [x] **0.5** Confirm the pipefail premise: a failing stage inside `haystack="$( … )"` propagates a
      non-zero assignment status; a legitimately-empty haystack does not.

## Phase 1 — RED (fixtures and tests before the script edit)

- [x] **1.1** Create the 10 fixtures under
      `plugins/soleur/test/fixtures/ship-incident-pir-gate/`, copying the Appendix bodies verbatim
      **including the in-file HTML constraint comments** in F2 and F8:
  - [x] 1.1.1 `precedent-citation-inside-hypothetical-paragraph.md` (F1)
  - [x] 1.1.2 `real-outage-claimed-inside-hypothetical-paragraph.md` (F2) — prod token in
        `## Overview`, outside the stripped paragraph
  - [x] 1.1.3 `real-outage-after-hypothetical-paragraph.md` (F3)
  - [x] 1.1.4 `real-outage-in-sibling-bullet.md` (F4)
  - [x] 1.1.5 `real-outage-after-heading-boundary.md` (F5)
  - [x] 1.1.6 `real-outage-in-nested-sub-bullet.md` (F6)
  - [x] 1.1.7 `real-outage-after-fenced-block-abutting-paragraph.md` (F7)
  - [x] 1.1.8 `midsentence-conditional-does-not-open-a-paragraph.md` (F8) — outage claim on the
        line AFTER the `if this lands` line
  - [x] 1.1.9 `reflowed-citation-with-issue-ref-continuation.md` (F9)
  - [x] 1.1.10 `real-outage-inside-paragraph-without-actuality-idiom.md` (F10)
- [x] **1.2** Add `signalsText(text: string): boolean` beside `signals()` in
      `plugins/soleur/test/ship-incident-pir-gate.test.ts`, sharing the status-0-or-1 contract.
      Leave `signals()` unchanged.
- [x] **1.3** Add 13 tests, each with a comment naming the rule it pins:
  - [x] 1.3.1 one per fixture (10)
  - [x] 1.3.2 template anti-rot (F11) — extract the first two
        `- **If this (lands broken|leaks)` lines verbatim from
        `plugins/soleur/skills/plan/references/plan-issue-templates.md`, append an indented
        continuation carrying an `OUTAGE_RE` and a `PROD_RE` hit, assert no signal
  - [x] 1.3.3 fail-toward-PIR (F12) — spawn the gate with `PATH` prefixed by a temp dir holding an
        `awk` stub that exits 2; assert status 0 with `INCIDENT-SIGNAL: yes`. Do NOT probe by
        emptying `PATH`
  - [x] 1.3.4 concatenation seam (F13) — PR body ending on a trigger line joined by a single `\n`
        to a plan carrying a real outage claim; assert signal
- [x] **1.4** Run the suite and record the RED set. Expect **4** failures on `main`: F1, F9, F10
      (authored as must-NOT-signal; `main` signals on all three) and F12. Every other new test must
      already pass. More failures means a fixture is wrong, not that the gate is worse.
      **Measured: 5, not 4.** F1, F9, F10 and F12 as predicted, PLUS the template anti-rot test
      (F11): its appended continuation carries an outage claim INSIDE the hypothetical
      paragraph, which is precisely the class this change closes, so it cannot pass on `main`.
      The plan's "every other new test must already pass" was wrong for that one row.

> **Corrected at review: the corpus figures changed because the GLOB changed, not because the
> corpus grew.** Task 2.6 prescribes `knowledge-base/project/plans/*.md` (top-level, 1548 files);
> the implementation swept recursively (1878, including `archive/`). Both readings are internally
> correct and were measured on the same tree — at the plan-authoring commit the counts were
> already 1548 top-level / 1878 recursive. Top-level gives 268 -> 260 with 8 movers; recursive
> gives 315 -> 304 with 11. The PR quotes the recursive figures, so **AC6c must be verified with
> the recursive sweep** or a verifier reconciling against `*.md` will find 8 movers, not 11.

## Phase 2 — GREEN (the strip widening)

- [x] **2.1** ~~Declare `ACTUALITY_RE='already (happened|occurred)|not hypothetical'`~~ **AMENDED
      at review: shipped as `already (happened|occurred)`.** `not hypothetical` had a corpus hit but
      no fixture and zero verdict effect, so it failed the bar the comment above it sets. Beside
      `OUTAGE_RE`/`PROD_RE`, with the measured-vocabulary rationale comment from the plan.
- [x] **2.2** Change the fence strip to emit a block boundary:
      `awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; print ""; next} !f{print}'`.
- [x] **2.3** ~~Insert the stage before the `grep -vaiE`, with the `# ORDER IS THE DESIGN`
      comment.~~ **AMENDED at review: the `grep -vaiE` was MERGED into this awk (it ran after the
      paragraph strip and deleted lines the re-admit had restored), and the ORDER comment now
      names which orderings measurement showed are load-bearing rather than asserting all are.**
      Insert the paragraph-strip `awk -v ACTUALITY_RE=…` stage after the
      `[Nn]etwork-[Oo]utage` sed and before the `grep -vaiE`, with the inline `# ORDER IS THE
      DESIGN` comments. Rule order per the plan; the hash rule is
      `/^[[:space:]]*#+([[:space:]]|$)/`, NOT a bare `#`.
- [x] **2.4** Wrap the `haystack=` assignment in the fail-toward-PIR guard (`if ! haystack=… then`
      → print the signal line, a stderr diagnostic, `exit 0`).
- [x] **2.5** Extend the strip-(3) header comment (paragraph scope, the three boundaries plus the
      two deliberately omitted ones, the re-admit, the fence boundary, the lexical-limits
      decision). **Delete** the stale "nine existing fixtures" sentence — do not re-number it.
- [x] **2.6** **Exit gate — corpus sweep runs HERE, not in Phase 4.** Sweep every
      `knowledge-base/project/plans/*.md` under the baseline and the merged script; write
      `"${TMPDIR:-/tmp}/pir-corpus-sweep.txt"` with `path<TAB>before<TAB>after` plus the quoted
      removed line per mover; record the post-change signal rate.
- [x] **2.7** Re-run the suite: 16 pre-existing + 13 new all green.

## Phase 3 — Consumer prose and the meta-case disposition

- [x] **3.1** Update the Phase 5.5 sentence in `plugins/soleur/skills/ship/SKILL.md` (content anchor
      "hypothetical framing before matching") to say "hypothetical framing **paragraph** (a sentence
      in that paragraph that says the event already happened is re-admitted)".
- [x] **3.2** Add the third disposition to the Incident-PIR Gate's `- **No match:**` bullet,
      available in BOTH modes, gated on **both** conjuncts: the diff includes
      `scripts/ship-incident-pir-gate.sh` AND the PR body carries
      `INCIDENT-SIGNAL: meta-case — <reason>`. Include the #7242 counter-example explaining why a
      diff-only predicate is unsafe.

## Phase 4 — Verification

- [x] **4.0** Materialize the baseline:
      `git show origin/main:scripts/ship-incident-pir-gate.sh > "${TMPDIR:-/tmp}/pir-gate-main.sh"`;
      assert non-empty; **self-check** it exits 1 on a known-negative fixture. Invoke only as
      `bash "$BASELINE" …` — never `git show … | bash`, which is input-independent exit 0.
- [x] **4.1** Create `scripts/ship-incident-pir-gate-mutation.test.sh` implementing M1-M9 against a
      sandbox copy, following the repo's existing `*-mutation.test.sh` precedents. Each mutation
      must flip ≥1 fixture verdict; the script must report the mutation count.
- [x] **4.2** Register the battery in `scripts/test-all.sh`.
- [x] **4.3** `shellcheck -S style` on the gate and the battery → rc 0.
- [x] **4.4** Apply AC6c to every sweep mover: each removed line must sit inside an anchored
      hypothetical paragraph AND match none of `ACTUALITY_RE`. Do NOT test conditionality
      line-locally. Carry the quoted lines and the signal rate into the PR body.
- [x] **4.5** `bash scripts/ship-incident-pir-gate-mutation.test.sh` → all mutations RED.
- [ ] **4.6** `bash scripts/test-all.sh bun`.
- [x] **4.7** `python3 scripts/lint-guard-contract.py` against the plan.
- [ ] **4.8** Walk every AC (AC1-AC15, AC-PM1) and record its command output.

## Phase 5 — Ship prerequisites

- [ ] **5.1** File the deferred `type/chore` issue: `/soleur:one-shot` invokes `soleur:ship` without
      `--headless`, so every ship prompt lands on an interactive arm inside an unattended loop.
      Re-evaluation criterion: "every ship phase whose headless and interactive arms differ has been
      audited for one-shot's dispatch path."
- [ ] **5.2** Ensure the PR body carries the `INCIDENT-SIGNAL: meta-case — …` declaration (AC13). This
      plan trips its own gate with certainty; without the declaration Phase 5.5 has no legal exit
      and will author a post-mortem for an event that never happened.
- [ ] **5.3** Confirm `git diff --name-only origin/main...HEAD` satisfies AC11, including **no**
      file under `knowledge-base/engineering/operations/post-mortems/`.
