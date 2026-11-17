# Tasks: origin-TLS closing records (#10479, #12441)

Plan: `knowledge-base/project/plans/2026-11-17-docs-origin-tls-closing-records-10479-12441-plan.md`. Rulings: `decision-challenges.md` (same directory).

## 1. Part A: CLO closing addendum (due 2026-11-19)

- [ ] 1.1 Counsel-review frontmatter: add `addenda:` as the last key (plan Phase 1 step 1, exact string).
- [ ] 1.2 Q-1 string: append the `[Superseded 2026-11-17 (#10479), as to Q-1 being open: ...]` bracket, keeping the original text unchanged and adding no raw `"`.
- [ ] 1.3 Body blockquote under "Q-1 to Q-6 ...": Q-1 is discharged (6917496007, 6946870123), Q-2 to Q-6 stay open, and the #12742 replace is bounded as not yet requested per the CTO ruling of 2026-11-16.
- [ ] 1.4 Blockquote marker under line 143 ("GitHub will close ..."): give the cause (body edited to Ref at 2026-11-16T12:59:10Z), say both issues are OPEN, and never write "#10479 closed".
- [ ] 1.5 Inline bracket in the Artifact 5 Verdict cell (~line 103). No `|`.
- [ ] 1.6 Sub-bullet under R1 "New:" (~line 115). R1 text unchanged.
- [ ] 1.7 Append the `## Addendum — 2026-11-16 (post-merge, Q-1)` heading, the `Written 2026-11-17; ...` line and the verbatim paragraph.

## 2. Part A(b): A7 record

- [ ] 2.1 Blockquote marker under the "Owner's words" bullet (line 65), with the same cause. Say #10538 is OPEN.

## 3. Part B: runbook (#12441)

- [ ] 3.1 File issue (i), the SOLEUR_HEALTH_TIMING marker revival (labels `domain/engineering`, `observability`; quote the runbook shape sentence verbatim), and issue (ii), the site-split host-filtered query (label `domain/engineering`). Both: milestone `Post-MVP / Later`, Ref only, no priority label.
- [ ] 3.2 Insert `##### Addendum 2026-11-16: ...` after the 2026-11-11 addendum: source line, Table 1, consistency note, Table 2 (every day 11-07 to 11-16; days without a row read "no rows"), laptop samples, limitation, CTO 2026-11-16 and 2026-11-17 rulings, durable-path line.
- [ ] 3.3 Add the issue numbers to the decision-challenges rows "p90 step" and "Marker revive trigger (2)".

## 4. Verify

- [ ] 4.1 AC1-AC8 checks (YAML parse, verbatim count, marker counts, numstat deletions 2/0/0 plus span-removed equality; verbatim check via python `str.count`, legal lints, doc-SHA check, markdownlint).
- [ ] 4.2 `prepush-secret-scan.sh` before every push.

## 5. PR #12843

- [ ] 5.1 Body Ref-only; `closingIssuesReferences` == `[]`; never touch #12698.
- [ ] 5.2 CI green and review done, then stop. Ask the owner for a typed go naming PR #12843. Do not arm or enqueue.
