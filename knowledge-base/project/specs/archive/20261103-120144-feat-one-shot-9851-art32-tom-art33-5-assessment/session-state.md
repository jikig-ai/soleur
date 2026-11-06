# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-03-docs-art32-tom-residual-and-art33-5-assessment-9851-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Planner notes for the work phase:
- The plan and spec files sit outside markdownlint scope (`.markdownlintignore` excludes `knowledge-base/project/`); the markdownlint acceptance criterion applies to the two registers only.
- The sandbox-enabling merge date is cited as the UTC timestamp of the enabling PR (2026-04-05T22:01Z), not the local commit date.
- One engineering follow-up is routed per decision D13, outside the public repository.

### Decisions
- Conclusion class: a new breach-register row dated 2026-11-03, REACHABILITY-ONLY, PROVISIONAL, evidentiary limbs inconclusive, Art. 33 No, Art. 34 No; never "no exposure". Covers the inner Bash sandbox tier only.
- Art. 32 bullet: one `open residual` bullet after the arm-F bullet in named-gap form, plus an additive Superseded marker under the arm-F bullet.
- CLO review record lives in `decision-challenges.md` (`## CLO Review Record`); no audits file (it would need a waiver edit in a lint script, out of scope). The final CLO pass runs last on the final diff.
- Threshold `single-user incident`; user-impact reviewer plus the standard panel; gdpr-gate skipped by CLO and CTO ruling; no CMO or CPO; `Ref` keywords only.

### Components Invoked
soleur:plan, soleur:deepen-plan; CLO, CTO (two spawns), learnings-researcher, code-simplicity-reviewer, architecture-strategist, user-impact-reviewer.

- cto_spawns: 2 in planning

## Work Phase (2026-11-03)
- Status: registers drafted, checked and revised after two review rounds; final CLO review, QA and ship remain.
- Branch merged with origin/main once (one unrelated commit behind); no conflict.
- Phase 0 record: #9723 created 2026-10-07T19:14:00Z, closed 2026-10-09T01:58:31Z (PR 9768); #9860 and #9614 closed; #9773, #9842, #9543, #9851, #9601 open; PRs 9768, 10039, 9874, 1559, 5928, 9709 merged at the timestamps in the plan; deny entry PR 1282 merged 2026-03-29T18:19:42Z; ADR-075 has no addendum newer than 2026-10-31; `proc_mask` is the first entry of the canary's hardening probes.
- AC9(f) grep: one line in each of four public legal documents and their mirrors (agent web access, its audit records, the reader's own safeguards); S6 added to the Superseded marker. The bullet no longer carries the keyword-search sentence; it points to the ledger's Part 2 counts and the Publication Criterion.
- AC9(g) channel trace: loopback, delegated-egress, abstract unix sockets, in-process heap, procfs, server process and home-directory state each appear in ADR-075 or the arm-F bullet; no new channel. The bullet carries one sentence that the deploy canary is report-only, which the post-mortem already states publicly.
- Wording hits removed before commit: three words on the AC9(c) list were reworded out of the added lines.
- Checks re-run after the round-2 fixes (same results as the first run): register lint 15 rows, 0 failed; markdownlint clean on both registers; row has 11 awk fields; numstat deletions 0 and 0; scope grep 0; withheld-number check 0 on added lines, commit messages and PR text, negative control 1; check-pa-22, lint-art30-reverification, check-tom4-rls-posture and lint-infra-no-human-steps exit 0; legal-doc-consistency vitest 37 of 37.

## Review Phase (2026-11-03)
- Round 1 (panel at f2f0255505): five seats (user-impact, security, architecture, simplicity, pattern); one P1 (session-state repeated an item kept out of the public repo, D13), P2s on unscoped Art. 33 and Art. 34 cells, window dating, unsupported pointer clauses and stale canary evidence. Fixed in 11bfaa6cbb. Structural cause: statements broader or staler than their cited records.
- Round 2 (targeted fix round over f2f0255505..11bfaa6cbb): six seats (security, user-impact, pattern, architecture, simplicity, legal-wording auditor) plus the coverage consult; no P1; 11 P2 and about 22 P3 before dedup. Structural cause: prose added by the fix inherited the same over-claim class (an exclusive-control claim, a proxy-authentication bound and a supersession attribution stronger than their sources), and the tier vocabulary and rulings record were not propagated. Fixed in the following commit. Consult leads: ledger row I10 becomes stale on merge (PR-body note, not edited here); the CLO record location is not path-resolvable until archive (D8 limit).
