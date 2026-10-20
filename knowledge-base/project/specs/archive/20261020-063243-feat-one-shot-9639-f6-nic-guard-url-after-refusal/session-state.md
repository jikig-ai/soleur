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

## Review Phase (2026-10-20, PANEL_SHA d2fa176f53, tier none, 9 seats + CTO + coverage consult)

structural-cause roll-up: (1) prose claims describing the pre-fix wrapper shape were never swept BY CLAIM (about 8 sites across scripts, units, a .tf comment, the scanner header and the ADR); (2) the new rows pin the spelling the author mutated and leave the neighbouring axis open (charset body clause, refusal disjuncts, limiter, second Exec line, not-exported for zot); (3) the scanner's assembly is narrower than the property it names.

dedup: ~85 raw -> 38 unique

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| zot refusal key disjunct makes traced --canary-only exit 78; contradicts plan/ruling | zot-refusal-predicate | observability, architecture, pattern, security, quality, testdesign, history | review: zot refusal exempts --canary-only (P2) |
| key name shape-bound not class-bound | key-class | security | declined by CTO (shape-only), recorded on #9639 |
| exported URL stays exported | unset-URL | security | review: unset URL (P3) |
| stale prose describing the old wrapper expansion (nic header, zot canary block, .service comments, scanner header, web-probe.tf, ADR heading and wording) | stale-claims-sweep | pattern, quality, history, architecture | review: sweep stale claims by claim (P2) |
| locale row / LC_ALL claim vacuous on bash 5 | locale-claim | quality, testdesign | review: reword claim, keep row as a pin (P2) |
| plan post-merge check 3 greps a conjunction that matches nothing; layer citation | plan-postmerge-3 | observability | review: rewrite check 3, cite layer (P2) |
| missing pins: zot not-exported, charset body clause, refusal disjuncts, nic limiter, all-Exec dollar-free, SCRIPT_KEY fixtures, comment-stripped body | neighbouring-axis-pins | testdesign, quality | review: add rows, mutation-proven (P2) |
| scanner: INDIRECT_RE spellings, ack keyed by unit only, MIN_WRAPPER tautology | scanner-assembly | enumeration, testdesign, simplicity, architecture, quality | review: widen regex, key ack to names, comment floor (P2) |
| scanner coverage: ExecStop*, other doppler spellings, drop-ins, direct $NAME | scanner-coverage-recorded | enumeration, security | recorded on #9639 (CTO) |
| _key_ok duplicated, no parity pin | key-ok-parity | pattern, history | review: byte-identity row (P3) |
| simplicity trims (about 22 rows, 60 plan lines) | trims | simplicity | declined by CTO |
| tasks.md ticks not backed | tasks-ticks | quality | review: relabel 1.6, tick 3.4 with the measurement (P3) |
