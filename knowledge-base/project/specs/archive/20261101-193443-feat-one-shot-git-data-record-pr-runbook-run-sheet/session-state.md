# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-01-docs-git-data-record-pr-real-flip-run-sheet-plan.md
- Status: recovered from partial-artifact (subagent returned without a Session Summary; plan body with Acceptance Criteria and Research Insights was on disk).
- Plan artifact: recovered (selector=branch)

### Errors
Subagent ended without the Session Summary block.

### Decisions
See decision-challenges.md.

### Components Invoked
soleur:plan, soleur:deepen-plan (per subagent transcript)

## Review Phase (2026-11-01)

Panel SHA 275b51afda, tier single-user incident (source plan), 8 seats (history, pattern, security, quality, user-impact, architecture, simplicity) plus the coverage consult and one CTO ruling spawn. dedup: 78 raw -> 27 unique. Structural-cause roll-up: the sheet named abort, retry and rollback actions per row without one view of the flag, pause and exemption state at each step (fixed by the read-the-flag-first rule). Coverage consult: 2 of 5 leads verified real (host reboot, row age), 3 refuted or already covered.


Seats: history (H), pattern (PT), security (S), quality (Q), user-impact (U), architecture (A).

| id | canonical defect | seat(s) | sev | planned fix |
|---|---|---|---|---|
| L1 | RF5 hold-limit exit sends owner to the RF2 abort path, whose last step is pause OFF, after the flag write (RF4) | U, Q | P1 | RF5 exit = keep pause on, go to rollback; mark RF2 abort valid only while the flag is absent, first step read the flag |
| L2 | RF7 after-RF6 gate agent_sessions_live=0 cannot see trees of ended sessions whose replication failed (push failed / shed / pin-fault) | U | P1 | for those triggers count affected sessions from the failure rows; wait for forward fix or owner records acceptance against that count |
| L3 | hold limit has no owner, record or RF0 line; RF2/RF4/RF5/RF8 depend on it; no inputs to size it | PT, U, Q | P2 | RF0 line + sizing inputs (84 min budgets, 600 s settle, 89 min approval wait) |
| L4 | "owner acceptance comment under own login" cannot distinguish owner from agent (agent rulings are posted through the owner login) | S | P2 | require owner's own typed words naming the three credentials; agent-authored never counts; same for RF0 decision URLs and CLO acceptance |
| L5 | #8209 clearing condition understates open items (#9361, #9362, #9294, #9295, O13 items, D1/D2/G1/G1b) | S | P2 | O1 to O12 recorded, list the open ones, owner confirms on #8209 before RF4 |
| L6 | Preconditions heading/lead says workflow enforces all; new #8209 bullet says it does not | PT, S, Q | P2 | qualify the lead sentence (heading text unchanged) |
| L7 | RF4 "finalizer unwinds automatically" false for gc-timer-only failure (flag true, stamp written, no unwind); right move mode=unfreeze then RF5 | A | P2 | add the case |
| L8 | RF2 needs exemption absent but RF4 leaves it set; "restarts at RF2" contradicts; flag state unknown after RECOVERY_FAILED/STATE UNKNOWN | A, Q | P2 | retry path: exemption present and exemptConfigured=true expected, skip RF3; read flag first |
| L9 | RF6 runs pause off with the flag true; Quiet-window section says do not run off while flag true and go gate aborts on any =0 row; exception unmarked | A | P2 | mark RF6 as the deliberate exception, amend the Quiet-window sentence with a dated pointer |
| L10 | RF6 verifies unpause only via the Doppler mirror; running containers keep baked mirror 1 | A | P2 | require reporter row new_sessions_paused=0 on both hosts |
| L11 | op:git-data-bare-repo-erasure is a rollback trigger but a Delete Account during the freeze span produces it by design | A, Q | P2 | carve-out for events inside the freeze span; re-drive, not trigger |
| L12 | RF7 uses bare R5/R6/R8 colliding with RF numbers; "R6 is refs_assert only" edits a row | Q | P2 | write rehearsal R5 etc. with link |
| L13 | RF7 "before RF6 pause on, no real sessions" unmeasured; no re-read after approval wait; no pause-on requirement | Q, U | P2 | require the RF2 two-row read before approving |
| L14 | RF7 has no end state (canary repo stays in store; proof refuses store_not_empty) | Q | P2 | state end state and next attempt |
| L15 | RF7 cell too dense (~520 words) | Q | P2 | keep one row; move detail to a list under the table |
| L16 | RF5: go gate can pass on one host (other NO_SESSIONS); RF0 omits recorded owner+CTO decision on residuals #11716/#11717; overlay readings have no mapped action | U, Q | P2 | per-host requirement; RF0 line; overlay mapping |
| L17 | RF8: merge during soak cannot be done as re-pause/drain/deploy; no rule on who may merge for 7 days | U, Q | P2 | pre-merge ordering and a merge hold |
| L18 | RF4 "abort" has no action; stale/missing control line unhandled | U, Q | P2 | define the action |
| L19 | "every read is workflow annotation / Better Stack / Sentry" is false (Doppler name listing, /health, gh, DB count) | Q, S | P2 | reword |
| L20 | RF0 counts "two unchecked boxes", names one open one ticked | Q | P2 | fix text |
| L21 | RF0 gates the CLO disclosure on #10905 only; #10901 equally BLOCKED | H | P2 | name both |
| L22 | RF9 date 2026-12-29 vs runbook 2026-12-01 | H, A | P2 | state both, safe direction = the later |
| L23 | "deploy mid-canary drops the exemption" wrong mechanism (deploy re-bakes it; the real hazard is the restart killing the unreplicated session) | H, A | P2 | restate |
| L24 | "canary" alone is banned wording in the rehearsal section | PT | P2 | use synthetic account |
| L25 | sheet claims it restates nothing but carries none of the rehearsal's window bans (no rotate, no credential change, no apply dispatch, Art. 17 recording) | PT | P2 | pointer sentence |
| L26 | #9066 wording understated vs the issue (user told erasure complete; never unlinked; CLO date passed; not a breach) | S | P3 | tighten |
| L27 | P3 wording/consistency set: go gate undefined, Kind legend drift, re-pause/drain new words, label "exempt-account rule", CPO conditions uncredited, loose list from pointer blank line, E2 "for the deploy of" attribution, 121-minute wording, 75 s unsourced, RF3 both hosts, #8209 date range, #10216 vs #10175, release filter exclusions, plan session URL, re-pause leaves exempt account live, "any trigger means rollback" reads automatic, RF1 split, "R1 pause-off window" undefined, RF0 do-not-start-RF1 vs before-RF4 | all | P3 | batch |

structural-cause roll-up: L1, L8, L13, L18 are one gap, the sheet states abort/retry/rollback paths per row without a single table of flag/pause/exemption state per step, so each row can name an action valid only in a different state. Seat that should have enumerated it: architecture.

## Seat additions (simplicity seat + coverage consult), 2026-11-01
- S1..S8 (simplicity): delete the false closing line; cut RF4 false clauses and replace with a retry clause; "As R1 and R2" for RF4 Checks; trim RF2; merge RF7 triggers into two groups; point RF7 sequence at the rehearsal R5/R6/R8; shrink delta bullet 3 (drop the wrong-mechanism deploy sentence and the PR-meta); drop RF9 date and link D6 section. L5: do not copy the open-items list, say the open items live on #8209 and the owner confirms them there before RF4.
- Coverage consult leads verified real: host reboot/replace pointer (boot reopen section exists); maximum row age (2 minutes) on decision reads. Refuted: concurrency collision (git-data-cutover.yml has cancel-in-progress false and no schedule).

### Fix round 1 (2026-11-01, commit fb9eb5f3da reviewed by six seats)

Findings: 3 P1 (state rule keyed on the flag alone, re-pause reversal forbidden by the amendment, post-RF6 loss rule too narrow), about 12 P2, about 15 P3, all introduced by or left by the first fix commit. dedup: about 60 raw -> 20 unique. Structural cause: each new rule was written against the state the author was thinking about, not against every state the flag, pause, exemption and sentinel can be in. Resolved by CTO rulings R13 to R19 (decision-challenges.md) and one fix commit. Round 2 (targeted) and a verification pass follow.

### Fix round 2 (2026-11-01, commit bedf57cfb6 reviewed by four seats)

No P1 from user-impact, architecture or quality; one P1 from history (a routine deliberate deploy had no counted-loss gate) and about 12 P2 (state model gaps: the stamp, the sentinel read channel, unknown-N persistence, neighbouring Quiet-window sentences, a false #10914 claim). All applied in the third fix commit; rulings R20 to R22. Next: one verification pass and the affected gate.

### Verification pass (2026-11-01, HEAD 7fb1b04a19)

One fresh-eyes architecture seat: all six named P1s CLOSED, no new P1; 4 P2 and 7 P3 (scoping and contradiction gaps, none able to lose a tree by itself). Applied in the fourth fix commit without a further seat round (the targeted-round cap was reached): typed-N and unknown-N scoped to after RF6, the third Quiet-window blockquote extended to the abort-before-flag-write clause, RF2 retry wording, the deliberate-deploy end condition marked not a replication proof, the RF8 hold list extended to the apply paths, the pause-off channels listed, the flag-read channel named, the End-state rule for the pause after a rollback. Those edits are mechanically checked (linter, markdown lint, anchors, and the doc-pin suites; the cutover-access suite read 822 passed 0 skipped on two full runs and 795 passed 27 skipped on two others, where its docker runtime arm skipped on a transient apt failure inside the fixture container) and not seat-reviewed.

