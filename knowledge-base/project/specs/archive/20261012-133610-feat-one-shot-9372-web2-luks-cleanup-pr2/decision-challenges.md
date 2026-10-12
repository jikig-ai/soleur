# Decision challenges - feat-one-shot-9372-web2-luks-cleanup-pr2

Appended by plan on 2026-10-12 (headless pipeline: not asked, persisted for the ship phase to render in the PR body). Every technical
fork below was ruled by the CTO agent per `hr-technical-fork-is-not-an-operator-question`; nothing here is an operator question.

## Decision Classes

| # | Item | Class | Ruling | Where recorded |
|---|------|-------|--------|----------------|
| 1 | Retirement scope: the brief reads "the two workflows with their tests and registrations"; the plan deletes 24 files (7 scripts, 2 gates, 9 suites, fixtures, the two workflows and two workflow suites) | technical (ruled), disclosed as scope-adjacent | CTO agent, 2026-10-12: option B, the full runbook row-5 list. Dissent recorded by the CTO: (A) is the narrower reading of the brief. Flip condition: a live caller of a deleted script found by the post-deletion census | plan "CTO rulings", PR body |
| 2 | `web-host-reboot.md`: delete or banner | technical (ruled) | CTO agent, 2026-10-12: keep with a RETIRED banner; flip to delete only if the kb-consumers baseline generator keeps a stale row | plan R4 |
| 3 | G2 test control after `scripts/web2-rebirth.sh` is deleted | technical (ruled) | CTO agent, 2026-10-12: option A (drop the real-content control, keep the population and non-vacuity rows, add a scratch control) | plan Phase 3 T1, Guard Contract |
| 4 | `.tf` edits: comments only, no rename of `plaintext_workspaces_hosts` | technical (ruled) | CTO agent, 2026-10-12: comments only; adjacency pins named | plan Phase 4 |
| 5 | #9642 emptiness-evidence strictness | technical (ruled) | CTO agent, 2026-10-11 (carried from the brief): moot and retrospective for this cleanup; the three requirements become the learning | plan R8, PR body |
| 6 | ADR-263 `adopting` to `accepted` | mechanical (the ADR states its own criterion; the grader was run and passed) | no ruling needed | plan R2 |

## User-Challenge

None. The owner's stated direction is followed. The one place where the plan reads the brief wider than its wording (item 1) is a
consequence the brief's own phrase "with their tests" and the ADR-263 2026-10-08 addendum require (a tombstone row makes a half
retirement hard RED), so it is disclosed rather than challenged.

## Taste

1. **The CTO's grep missed `lb-weight-gate.sh`.** The CTO ruling 4 reported no stale wording in `lb-weight-gate.sh` (its pattern was
   rebirth/reborn). The brief names the file and two lines read "plaintext-but-empty until its live conversion" and "exists only
   after web-2's live LUKS conversion". The plan edits them (comments only). A reviewer who prefers the CTO's narrower reading can
   drop that file from the PR without affecting anything else.
2. **A second pre-existing red.** The push apply of `apply-web-platform-infra.yml` has failed on every infra-touching push since
   2026-10-11T22:20Z (`terraform_data.egress_gateway` and `egress_gateway_web2`, #10003). It is not in the brief's "known red" list.
   The plan reads the merge run's log against a named discriminator instead of treating a red run as either blessed or caused by this PR.
3. **`Closes #9372` closes at merge, before the postmerge comment.** The brief wants the final comment after postmerge verification.
   The plan comments on the already-closed issue; the comment is the graded-rows claim either way.
4. **Plan-review cuts not taken (2026-10-12).** The DHH, Kieran and simplicity reviewers asked to drop the Scope Check tables, the Guard
   Contract, the ADR-241 line and the Observability block. Kept: the Scope Check, Observability and Guard Contract sections are required
   by the plan skill's gates for this change class (and the lint validates them); the ADR-241 line is on the runbook's owner-approved
   literal deletion list. Taken: the credential-free `discoverability_test` (no `BASELINE_DECLARED_PROBES` bump), baseline-relative post-merge
   criteria, a single ADR addendum plus one Status note, the Guard Contract trimmed to three rows, the duplicate ratchet runs removed,
   and runbook marks limited to sentences that are false at read time.
