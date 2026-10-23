# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-23-fix-apply-restore-exit-annotations-plan.md
- Status: complete

### Errors
None. Two non-blocking snags: an issue filing refused by a hook (re-filed with the machinery label as #10932), and decision-challenges.md failing the ruling gate twice (both fixed, gate passes).

### Decisions
- Exits 2 and 5 now each have two causes (source or credential rejection, or a local login failure on the runner); exit 78 is the engine's refusal to run under xtrace with a credential set.
- Explicit 78 arms in the workflow restore step and in gate A2; rewritten 2 and 5 arms; net-zero bytes against the 490,000-byte workflow gate.
- Exit 1 is out of scope and tracked as #10932.
- The merge fires the production apply: an operator-class authorization row. Ship asks one plain question before the PR is marked ready or the merge is armed.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; CTO agent (forks F1-F4); learnings-researcher; dhh, kieran, simplicity, architecture, test-design reviewers.

## Review Phase (panel SHA c4131ddacb; tier none, source plan; class code)
Seats (7): git-history, pattern, architecture, security, code-quality, test-design, structural-enumeration. Shed (no path match): data-integrity, agent-native, performance. shellcheck run by lead (clean).
dedup: ~40 raw -> 20 unique. structural-cause roll-up: W9 asserts the PRESENCE of a labelled line in the step body, not the property rc -> case arm -> annotation -> exit; seats enumeration, testdesign, architecture each found a different instance.

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| W9 greps whole step body; case subject / exit rc / dead-branch copies stay green | W9 is presence-not-structure (P2) | enumeration, testdesign | review: rewrite W9 as a scoped function (P2) |
| W9 token checks over whole line incl. trailing comment; no negative control; population from header only; awk comment vs blank line | same root cause | testdesign, enumeration, architecture | same commit |
| A2 abort_line grep satisfied by stub chatter | A2 loop anchor (P2) | testdesign | review: anchor on gate's ::error:: prefix (P2) |
| gate A2 loop hand-written; arm 1, gate arms 2/5 `failed locally` unpinned | gate suite does not derive/pin | enumeration, architecture, pattern | same commit as A2 anchor |
| gate exit-2 text "restored nothing" false mid-loop; runbook row 2 "Nothing was written" | false claim on mid-loop exit 2 (P2) | codequality | review: reword (P2) |
| 78 arm "store unchanged" vs EMPTY (contradicts ruling F4); `set -x` not a cause; re-run advice | 78 arm wording | security, pattern, codequality, githistory | review: reword 78 arm |
| arms 2/5 rank causes ("not GHCR", "fix it") without measuring | ADR-166 unmeasured cause | githistory | review: reword arms |
| gate comment "wider set" not nested; "generated in this job"; "assume neither" | gate comment accuracy | security, githistory, codequality | review: reword |
| exit 1 gap not visible at `*)`; W9 comment | #10932 pointer | architecture | review: pointer |
| stubs name no subsection / preamble lacks ### contract / long lines | relocation pointer wording | architecture, codequality, githistory | review: stubs + preamble |
| battery floor 66 vs 67; G18b id | battery floor | pattern | review: floor 67, id G26 |
| runbook relocated block "here"; "names rotation" stale in gate header, ADR-169, recut runbook; "Six codes" count; restore-suite header count | stale prose siblings | pattern, githistory, codequality | review: sweep |

## Review fix round 1 (fix commit 017c22e838) and CTO amendment
Round 1 (7 targeted seats over the fix diff) closed the original P2s and found new defects in the W9 rewrite (nested arm, extra command inside an arm, exit-1 comment false, thin control coverage, text parse unable to prove the chain). The CTO agent amended F3 (see decision-challenges.md): W9 is now a behavioural run of the step body. Battery floor is 70 (G26-G29). Accepted/not fixed: engine line 657 "Nothing was copied" and workflow arm 3 "The store is EMPTY" are pre-existing wording about exits the engine/arm 3 own (engine unchanged by ruling); shell-level codes (126/127/137/143) reach `*)` which prints the number; computed `die "$x"` codes are invisible to the regex-read population (W9 comment states the limit).

## Review fix round 2 (fix commit a76fb37345) and verification
Round 2 (3 targeted seats: test-design, enumeration, security) found no bypass of the behavioural W9 check on its own terms. Hygiene and coverage fixes applied inline: recovery run (3 3 0), Doppler-failure run, exact first-engine-call argument pin plus not-traced check, step uniqueness and step-key refusal, PATH-only env with cwd/stdin/timeout/signal hygiene, five new controls (dopabort, sticky3, traced, args, stepkeys), `subject` control repaired, extra-code control now derived from the header/emit maximum. 39 assertions in the wiring suite. Mutation battery on 69dffdcc06: 66 caught, 0 survived, 4 documented-unreachable (rc 0); round-2 changes touch only the wiring suite and a lib comment.
Wontfix, recorded as a comment on #10932 (no new issue): credential-env values, job/`needs`/summary-step coverage, verdict swap on the W9 row, computed `die "$x"` codes, shell-level 126/127/137/143 reaching `*)`, pre-existing engine "Nothing was copied" and arm 3 "The store is EMPTY" wording.
