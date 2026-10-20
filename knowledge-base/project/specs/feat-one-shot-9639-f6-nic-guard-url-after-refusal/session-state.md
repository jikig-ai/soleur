# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-20-fix-nic-guard-url-lookup-after-xtrace-refusal-plan.md
- Status: complete

### Errors
- Plan write blocked once by the IaC-routing hook (reworded); lint-infra-no-human-steps flagged one line (reworded); decision-challenges.md table shape fixed by the parent (escaped pipes, date/colon, taste class for review dispositions).

### Decisions
- Scope (CTO): fix web-private-nic-guard and web-zot-consumer-probe; web-git-data-probe and inngest-consumer-probe recorded on #9639 as not fixed (no xtrace refusal to follow; the latter sources a file under open PR #10501).
- Script contract (CTO): unit becomes ExecStart bash -c doppler run -- script with no dollar sign; script reads the *_URL_KEY after the refusal, validates ^[A-Z][A-Z0-9_]*$, unexported result, no bare-variable fallback.
- Scanner coupling (CTO): doppler-injection-bound.test.sh gets a finding for unit-side indirect expansion plus a script-side *_KEY population reason; ACK_CARDINALITY stays 8.
- Tests first: static Exec* check, behavioral launch under xtrace with stub doppler, negative control restoring the old ExecStart, hoisted-lookup mutant, hostile-key loop. No shared ratchet file edited.
- Post-merge: count anchored "terraform_data.<install>: Creation complete" lines in the merge apply run, then Better Stack heartbeats and log rows (no SSH).

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan; CTO x2, DHH, Kieran, code-simplicity reviewers.
