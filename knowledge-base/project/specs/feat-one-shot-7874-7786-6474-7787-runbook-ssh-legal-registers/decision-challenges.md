# Decision Challenges — feat-one-shot-7874-7786-6474-7787-runbook-ssh-legal-registers

Recorded per ADR-084. `/ship` renders these into the PR body and files an `action-required` issue.

Only genuine **scope** challenges appear here. The PR-granularity question raised by three domain
agents (CLO, CTO, CPO) was **resolved in the plan, not surfaced** — PR granularity is a technical
fork, and `hr-technical-fork-is-not-an-operator-question` reserves operator questions for
authorization, cost and scope. The reasoning is recorded in the plan's
`## Decisions taken, not deferred`.

---

## Challenge 1 — #7787 says "delete `--advisory`. No other change." The plan changes two more things.

**Class:** user-challenge (a deliberate, documented deviation — an *addition* to stated scope)
**Operator's stated direction:** "delete `--advisory` from its `run_suite` line, and nothing else."
**Status:** deviation taken, recorded here.

**(a) The comment block above the line becomes a false instruction.** `scripts/test-all.sh` carries:

```
# PROMOTION: delete the --advisory flag on the next line. Trigger: one green merge cycle with
# no unexplained finding. Tracked at #7787, which carries the full promotion checklist.
```

Once the flag is gone this tells the next reader to delete a flag that is not there, citing a
trigger already discharged. Phase 6.2 rewrites it in the same edit to record the promotion's date,
PR and evidence, and to keep the retained rc=2 asymmetry documented.

**(b) Two `NOT_TRANSCRIBED` waivers must land in the same PR.** This is not optional and is not
really a scope choice — it is what makes the promotion survivable. `/ship` Phase 5.5's
Counsel-Review CLO-Attestation Gate fires on this PR (`legal_touch` non-empty AND
`brand_survival_threshold: single-user incident`) and **mandates** producing
`knowledge-base/legal/audits/<YYYY-MM>-counsel-review-<issue>.md`; Phase 4.5 adds a CLO
attestation beside it. Both quote Art. 4(12) / Art. 33, both match
`scripts/lint-legal-registers.sh` predicate (c)'s producer, and after the promotion an unwaived
match is a red on the required `test` context — on the PR that did the promoting. Phase 4.6 and
Phase 5.4 pre-author the waiver rows and their `§Excluded records` parity rows.

**Nothing else in `scripts/test-all.sh` changes.** AC19 pins the diff to three non-comment lines:
the old and new `lint-legal-registers-live` lines, and the `probe-legal-corpus-truth-live`
registration Phase 5.3 adds.

---

## Challenge 2 — #6474's scope list contains three items that are already discharged

**Class:** user-challenge (a *reduction* of operator-stated scope)
**Operator's stated direction:** a seven-part scope for #6474.
**Status:** parts (3), (4) and (5) struck; recorded so the reduction is visible rather than silent.

- **(3) "fill the literal `__TBD_OBSERVED_VOLUME__` / `__TBD_BETTERSTACK_RETENTION__`
  placeholders."** Both were resolved by PR #7782. The only surviving occurrence in the register is
  a **backticked quotation inside the 2026-09-03 withdrawal marker**, deliberately backticked so
  the audit trail survives the register lint's inline-code strip. `__TBD_BETTERSTACK_RETENTION__`
  was discharged with a figure (90 days per source, measured 2026-09-04, #7772). Re-filling them
  would re-open a closed record.
- **(4) "repair the DSAR runbook step whose `docker inspect … .LogPath` returns EMPTY."** Commit
  `05e50c525` (#7872, 2026-09-06) already deleted that step and the false "expect zero shippers"
  check beside it. It was also never an Article 15 step: the flow is declared dormant and is an
  Art. 30(1)(f) *measurement method*; Art. 15 machinery is the `DSAR_TABLE_ALLOWLIST` worker path,
  untouched here. Describing it to the operator as an Article 15 gap would overstate it.
- **(5) "rebase the open PR that measures against the inapplicable 30 MB cap."** No such PR exists
  (`gh pr list --state open --limit 60` → 34, none measuring against the cap). The referent is
  **closed issue #3754**, CLOSED/COMPLETED 2026-09-04, superseded by PR #7782.

Parts (1), (2), (6) and (7) are live and are implemented in Phases 3–4 — and part (1) turned out
**worse** than filed: the 2026-09-03 correction rested the whole Art. 30(1)(f) discharge on the
misattributed mechanism, and the register carries a **third** assertion of it in PA8 §(b)(vi) that
the issue does not mention.
