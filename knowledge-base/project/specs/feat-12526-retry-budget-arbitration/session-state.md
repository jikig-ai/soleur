# Session state — feat-12526-retry-budget-arbitration

PANEL_SHA: 69169594b3c3a144ebce36729975c821c85419c8
Review HEAD before this disposition: 50bcd4d14150c7f8a422e822e48d69acf3f24a6c
Tier: single-user incident (source: plan)
Class: code
Design-risk: yes
PR: 12815
Issue: 12526

status: review-in-progress

Checkout identity, when a ruling section is appended later, comes from `git rev-parse --show-toplevel` and `git rev-parse --path-format=absolute --git-common-dir`. Do not store a logical path.

## Dedup ledger

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| Continue wrote a ralph grant and the compact marker claimed grant=1 | continue-grant-keep-alive | code-quality-analyst, agent-native-reviewer | 50bcd4d141 |
| Spawn bit matched as a substring, including a prose mention | spawn-bit-substring | security-sentinel, pattern-recognition-specialist, data-integrity-guardian | 50bcd4d141 |
| Full-file replace dropped a concurrent append and could erase the spawn bit | ledger-replace-lost-update | data-integrity-guardian | 50bcd4d141 |
| Dot-dot, a symlink ledger, and control bytes could write outside the checkout or forge a second verb line | ledger-path-confinement | security-sentinel | 50bcd4d141 |
| A readable show with no selected marker line still spawned | not-capped-still-spawns | pattern-recognition-specialist | 50bcd4d141 |
| Awk could publish grant 0 without the consumed line | grant-prefix-publish | data-integrity-guardian | 50bcd4d141 |
| Continue has no legal in-process unit, and a Read during that unit took reason=spent while the verb field still said continue | continue-recorded-not-run | agent-native-reviewer, user-impact-reviewer | this review commit |
| The reference did not name a blank spawn, so a parent that does not improvise cannot call the ruling | blank-spawn-unnamed | agent-native-reviewer | this review commit |
| A failed append was reason=identity and could leave a partial section without the spawn bit | append-failure-labelled-identity | agent-native-reviewer, user-impact-reviewer | this review commit |
| Any nonempty history file, including a symlink or a path outside the toplevel, opened classification | history-path-unconfined | security-sentinel | this review commit |
| The 64-byte read blocked while stdin stayed open, and a nonempty dd error was still classified | stdin-read-unbounded | performance-oracle, security-sentinel | this review commit |
| A hard link or an in-tree spec-directory symlink wrote the spawn bit into another branch's ledger | ledger-inode-alias | data-integrity-guardian | this review commit |
| Non-goto phase and child-session were stored as free text | ledger-free-text-fields | user-impact-reviewer | this review commit |
| Absolute git toplevel and git common dir in the ledger | ledger-absolute-git-paths | user-impact-reviewer | CLO 2026-11-19 upheld; the paths stay |
| Grant read-back and the downgrade install gate treated grep rc 2 or more as a missing line | grant-grep-status-conflated | code-quality-analyst, pattern-recognition-specialist | this review commit |
| Phase 4 and the proposed-solution exit still told a later reader to add a consumed grant or to treat continue as exit 0 | plan-second-procedure-grant | agent-native-reviewer | this review commit |
| Pin tests locked one instance: a CR on the ledger leaf, a not-capped call that still passed history, and a denylist of one grant sentence | pin-locks-instance | test-design-reviewer, pattern-recognition-specialist | this review commit |

dedup: 17 unique. Each row is one defect. The first column names the raw reports that merged into it.

## Structural causes

1. Pin tests lock the instance, not the class. test-design-reviewer and pattern-recognition-specialist.
2. Leftover grant-reader error paths. code-quality-analyst and pattern-recognition-specialist.
3. A writer failure was labelled as a path mismatch. agent-native-reviewer and user-impact-reviewer. Ruled by R5.
4. The ledger inode alias is a different gap. data-integrity-guardian. It stays its own row.

## Residuals

- The stop hook can still replace the ralph file from an unlocked snapshot when downgrade is 0. A conforming parent does not write the grant line. Not redesigned in this commit.
- ftruncate uses the size captured immediately before the write. A concurrent unlocked append in that window can be truncated. O_APPEND stays so a concurrent budget-capped append is not dropped on the success path.
- A crash between a short write and ftruncate can leave a partial section. That residual is not an exit-path truncate.
- The parallel continue case has no barrier. A blocking flock is not added.
- The flood cases do not count unread bytes and do not pin a wall-clock duration.
- Ralph tests 56 through 62 do not lock the new hook abort branches. Those tests were not edited.
- A CR on the ledger leaf fails the leaf compare before the byte scan. The new CR case puts the byte in phase.
- The leading dot-dot case still passes both arms in one call.
- Attempt history is not named as a shared artifact. The ledger stores child-session and not the bundle.
- The one-shot cue stays a relative Read. The skill ceiling has no room to lengthen it, and the acceptance text pins that string.
- GNU realpath -e, dd status=none, and timeout are already the repo substrate. Not filed.
- Fail-only, deleting the four flood fixtures, deleting --probe, and deleting the identity refusal were not applied. The three parser tokens stay.

## Scan

Pre-panel: SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=4 rules=0 findings=18. Not SAST-clean.
Fix range 69169594b3..50bcd4d141: SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=3 rules=0 findings=3. Not SAST-clean.
Shell has no semgrep scan. The shellcheck seat has no agent file. Quote the receipt. Re-run the gate on the next fix range before the next seats.

## Rulings in force

R1 (2026-11-17) is amended by R1-r (2026-11-19): continue is recorded as applied not-run and the parent runs nothing. R2 stands. R4 names the blank spawn. R5 truncates a partial append and prints write-failed. The CLO field ruling (2026-11-19) keeps absolute git paths on this host and rejects free-text phase and child-session. Do not re-spawn the CTO for a row already ruled here.
