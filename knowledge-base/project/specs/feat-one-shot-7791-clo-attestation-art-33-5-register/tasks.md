---
title: "Tasks — CLO attestation for the Art. 33(5) breach register (#7791)"
date: 2026-09-04
branch: feat-one-shot-7791-clo-attestation-art-33-5-register
issue: 7791
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-09-04-compliance-clo-attestation-art-33-5-register-plan.md
---

# Tasks

Derived from the finalized (post-review) plan. **Task numbers follow the plan's stable section ids;
the execution order is the numbered list in the plan's `### Ordering` block, which is different.**

> **Execution order:** 1 → 3.3/3.5/3.6 → 3.8 → 3.1/3.2 → 4 → 3.7 → 2 → 5 → 6.
> The attestation file, the waiver swap and the deletion **land in one commit** — every intermediate
> state fails the register guard.

## Phase 0 — Preconditions

- [ ] 0.1 `bash scripts/lint-legal-registers.sh` → exit 0, `registers=4 rows=5 produced=12 waived=8 waiver-parity=ok`
- [ ] 0.2 `git fetch origin && git diff origin/main --stat -- knowledge-base/legal/` → no drift
      (work Phase 0.5 check 6 FAILs hard on `knowledge-base/legal/**` drift)
- [ ] 0.3 Capture the byte-exact `status:` line of `breach-register.md` from `origin/main` for AC7b

## Phase 1 — CLO pass 1: findings and drafted wording (writes nothing)

- [ ] 1.1 Assemble the brief as **allegations plus paths**, not pasted conclusions. The `clo` agent
      declares no `tools:` key and can read the corpus itself
- [ ] 1.1b Brief the **deliverables** too: drafted wording for the five stale sites; the C2+C3 cell
      text; the 2026-08-06 verdict scope; the pass-2 frontmatter (three `rulings_of_record`,
      `date:`/`attested:` split, AC20 carve-outs); the counsel-review re-issue text; the four
      carried items and the annex label; AC18's conditional-disposition rule
- [ ] 1.2 Enumerate disqualifying facts **as questions**, not findings
- [ ] 1.2b Require content anchors, never bare line numbers
- [ ] 1.2c Instruct: the only file it may create or modify is the attestation path
- [ ] 1.3 Instruct: drafted replacement wording, **no `AskUserQuestion`**, **does not sign on pass 1**
- [ ] 1.4 On 529 — remove any partial attestation file, then **resume via `SendMessage`**, never
      respawn; never downgrade the model tier
- [ ] 1.5 Fail-closed halt arm: final cleanup pass, assert the guard exits 0 on the halted tree,
      leave the PR in **draft**, comment on #7791 with the 529 request IDs, leave #7791 open
- [ ] 1.6 Returned-but-deficient arm: re-brief and resume; never hand-fill

## Phase 3.3 / 3.5 / 3.6 — Prose corrections (before the signature)

- [ ] 3.3 Correct the five stale sites using the CLO's drafted wording
  - [ ] (i) `§Excluded records` preamble — **correct in place**, prior text quoted in an appended marker
  - [ ] (ii) the stale supersession blockquote — **stack** a marker; never edit a supersession
  - [ ] (iii) 2026-05-17 waiver reason, register copy — **correct in place**
  - [ ] (iv) the false "this register is incomplete against its own stated predicate" — **stack** a
        marker. Highest-severity item in the plan
  - [ ] (v) guard copy of (iii) in `scripts/lint-legal-registers.sh` — **correct in place**
- [ ] 3.4 Scope note: `breach-register.md` has **no** `docs/legal/` mirror; the five `docs/legal/**`
      CI gates do not apply
- [ ] 3.5 Apply **C2 and C3** to the 2026-05-16 cell; leave both blockquotes standing
- [ ] 3.6 Re-issue `2026-09-counsel-review-7717.md`: frontmatter flip + appended
      `## Discharge on re-issue`. **Signed verdict rows A1–A9 and corrections C1–C5 untouched**

## Phase 3.8 — CLO pass 2: the signature

- [ ] 3.8 Resume the same agent; it **writes the attestation itself** at
      `knowledge-base/legal/audits/2026-09-03-clo-attestation-7717-art-33-5-register.md`, carrying
      `## 1. Findings at attestation`, the per-artifact verdict table (incl. the 2026-08-06 first
      verdict), the C2+C3 cell ratification, R1 as **DISCHARGED with the measurement**, the four
      carried items with the AC1–AC13 annex labelled as adopted evidence, `date:`/`attested:`, three
      `rulings_of_record`, and the AC20 carve-outs
- [ ] 3.8b Its Method section states the guard output it **certifies against** (`exit 0`,
      `produced=12 waived=8`) — the pipeline never writes into this file
- [ ] 3.9 **Pass-2 outage protocol.** Apply 1.4 (remove any partial file, resume, never respawn,
      never downgrade). If unreachable, stop **before** 3.1: leave the 3.3/3.5/3.6 corrections in
      place (they stand on their own and leave the guard green), leave the record and its waiver
      untouched, assert the guard exits 0, take the 1.5 terminal state

## Phase 3.1 / 3.2 — Waiver swap (only now that the attestation exists)

- [ ] 3.1 `scripts/lint-legal-registers.sh`: remove the implementation-record entry, add the
      attestation entry with a reason citing `#7791` (no `#NNNN` → fail-closed exit 2)
- [ ] 3.2 `breach-register.md` `§Excluded records`: the identical swap, same commit. The new row is
      the **tombstone** and names the supersession. **Do not create a stub file**

## Phase 4 — Retire the implementation record

- [ ] 4.1 Delete `knowledge-base/legal/audits/2026-09-03-implementation-record-7717-art-33-5-register.md`
- [ ] 4.2 Replace the `knowledge-base/INDEX.md` entry with the attestation, matching the
      `CLO attestation — …` shape used at the 2026-08-09 entry
- [ ] 4.3 Leave the six historical reference sites untouched — two are rows inside a **signed**
      counsel-review verdict table

## Phase 4b — BLOCKED arm (only if the CLO returns BLOCKED)

- [ ] 4b.1 The attestation is still written, by the CLO, with `disposition: BLOCKED`
- [ ] 4b.2 **Phase 4 does not run** — the implementation record stays
- [ ] 4b.3 The waiver swap still runs; net waivers **8 → 9**, not 8 → 8
- [ ] 4b.4 PR does not merge; #7791 stays open; blocker surfaced in the review trailer

## Phase 3.7 — Verification (first moment the guard can be green)

- [ ] 3.7 `bash scripts/lint-legal-registers.sh` **without `--advisory`** → exit 0,
      `produced=12 waived=8`. Record exit code + summary
- [ ] 3.7b State the honest R-g version: the blocking net is
      `lint-legal-registers.test.sh`'s `live corpus passes the guard` case, not the advisory arm

## Phase 2 — Verify the signed artifact

- [ ] 2.1 Build the checklist from the CLO's **obligation list** — one grep per obligation, hit/miss
      printed. Never from prohibitions
- [ ] 2.2 Confirm all four unique items are carried **inside** the attestation (F9), AC1–AC13 table
      labelled *"engineering verification, adopted by the CLO as evidence, not as legal finding"*
- [ ] 2.3 Assert `cells == header_cells` for every row added or edited (index table 9, excluded 2)
- [ ] 2.4 `rulings_of_record` enumerates **three** rulings
- [ ] 2.5 The 2026-08-06 verdict is present and its `status:` / `BLOCKED` are unchanged

## Phase 5 — Corpus sweep

- [ ] 5.1 Grep the **subject** of every changed claim corpus-wide; read every hit
- [ ] 5.2 **File the C1 deferral issue (F-4)** and record its number in the attestation's deferral
      sentence — AC26's deferred-branch is unsatisfiable without it
- [ ] 5.3 `bash scripts/lint-legal-registers.test.sh` — blocking unit suite

## Phase 6 — Ship Phase 5.5 handoff

- [ ] 6.1 Note the ship-gate audit's name is unknown until ship time; its waiver lands in a second commit
- [ ] 6.2 After the gate writes its audit, add its waiver to **both** copies in one commit
- [ ] 6.3 Re-run the guard without `--advisory` → exit 0 (AC15)
- [ ] 6.4 Instruct the ship-time CLO pass to attest the **delta only**, handing it the #7717 attestation

## Verification

- [ ] Run all 27 acceptance criteria from **one generated, uncommitted script**; emit one
      `[ok]`/`::error::` line per assertion plus a summary; paste the output into the review trailer
- [ ] CPO + `user-impact-reviewer` sign-off before ship (`compliance/critical`)
- [ ] PR body carries `Closes #7791`

## Follow-ups to file

- [ ] F-1 `scripts/add-legal-waiver.sh` — write both waiver copies atomically
- [ ] F-2 Lift the CLO invocation protocol into `plugins/soleur/agents/legal/clo.md` Sharp Edges
- [ ] F-3 `ship/SKILL.md` Counsel-Review gate: waive the audit it writes
- [ ] F-4 C1's corrected figures at the **three** stale sites — register §Inclusion predicate,
      ADR-200, guard header. **Art. 30 item 12 already reads `104`** (measured); do not "fix" it
