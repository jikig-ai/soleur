# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-feat-founder-acceptance-record-followups-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Plan skill functional-overlap checks skipped; deepen ran a targeted gate set; Phase 4.0 Inbox wireframe is a first work task (AC16 gates Phase 4 code on it).

### Decisions
- Trio retention wording published now (CLO re-ruling 2026-11-08); no TC_VERSION bump; #12365 kept open for the human-lawyer review.
- CPO signed the deck but PROVISIONAL stays true while human lawyer review is owed (deviates from the brief; surfaced in PR body).
- #12396: parked-hold member step in secret-guards umbrella (CTO); no ruleset change.
- #12429: migration 186 RPC + sibling /counts route (CTO); no small-cell floor.
- Single PR with per-item commits (brief instruction), cto_spawns carried by planning subagent.

### Components Invoked
soleur:plan, soleur:gdpr-gate, soleur:plan-review, soleur:deepen-plan; agents CLO, CPO, CTO, plan-review panel, security-sentinel, observability-coverage-reviewer, user-impact-reviewer.

## Review fix-round ledger (PR panel base f787a5c680, fix-round range f787a5c680..977017b2c4)

Fix round 1 (panel of 16 seats, three fix batches, commits c4df905b30, 5503306d5c, 61b280c083, 620ec1c274, 7abd42ef4e, 977017b2c4) closed the first-panel findings. Fix-round review (10 seats: security, code-quality, architecture, pattern, data-integrity, user-impact, test-design, observability, deployment-verification, legal-auditor, structural-enumeration) dedup: ~60 raw -> 9 unique defects.

| raw finding | canonical defect key | reporting seat(s) | planned fix |
|---|---|---|---|
| quoted/list-item/flow `continue-on-error`, `shell:` key, constant member() verdict args, early exit before tail, `\|\| true` chain, `&& false` if, job-level if false | umbrella guards' text rules narrower than the YAML grammar and than the property "a member verdict cannot be neutralised" | security, structural, test-design, pattern, code-quality | parsed-YAML allow-list + pinned member() args + mutants (guards agent) |
| "each event carries the name of the text" false for 4 event kinds; imprecise "database error code"; record_invalid omitted | published monitoring sentence claims a union per event | user-impact, data-integrity, observability, legal-auditor | CLO re-ruling + 6 files + test pin |
| PP 4.15 / DPD 2.3(ah) notices attribute promises the section never made; undated "since November 2026"; Nov 8 paragraph rewritten in place vs Nov 8 entry annotated; ambiguous "further" marker; #12011 in new DRAFT markers; stale siblings (counsel-review-12011, ADR-309/319, claim ledger A1, Art. 30 item 15, README) | status correction not swept by claim across the repo; append-only rule applied unevenly | legal-auditor, security (F3), data-integrity (P3-c) | CLO re-ruling + append-only markers; ADR addenda by docs agent |
| RPC caller census blind to lib/supabase/ and any nested test/ segment | exclusion not root-anchored | security, architecture, test-design | root-anchor + self-test rows (TS agent) |
| "anon-denial probe" cannot fail on a broken REVOKE; verify/186 header says run-verify fails the deploy | compensating check named, not equivalent | deployment, data-integrity, architecture | real PostgREST anon probe in ADR/plan/verify header (docs agent) |
| plan 7.4 missing published-pages, counts 401, pre-merge verify read; total=0 stop rule; runbook rows/orphan paragraph; rollback in two scopes; model.c4 edge; ADR-319 stale bullets | plan/runbook/ADR prose not reconciled with the fix round | deployment, observability, architecture, code-quality, pattern | docs agent |
| ci-parked-hold affected-path edge set not widened | selection edge set narrower than the suite's reads | pattern | guards agent |
| counts helper hash length/anchors, undefined mutant name passes, crash counted as caught; queue-ref parity reads comments; two ci-parked-hold annotation/clause survivors | mutation battery gaps | test-design, structural | guards agent |
| flag decision tracked only in diff files; PR body still a stub | deviations and the global approval-queue flag decision not surfaced outside the diff | user-impact | plan item + ship step re-reads the flag; PR body at ship |

Accepted/unfixed: kindUndeclared and per-key pageReadFailed fire once per Inbox poll (volume only, gated founder); 503-vs-401 token-set disclosure (pre-existing, shared with the verify route); published-retention cannot guard other public surfaces (scope of that test).
