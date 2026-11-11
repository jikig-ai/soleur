# Session state — feat-12531-spec-kit-ingestion

PANEL_SHA: 335e2ee6dbd1ce27eb63f3502bcc66b4a3f58eab
Tier: single-user incident (source: plan)
Class: code
Design-risk: yes (kept)
PR: #12653
Issue: #12531

dedup: 22 raw → 10 unique, plus 1 coverage-consult class verified in the diff. structural-cause roll-up: the projected channel is the same stdout stream as the receipt, so a mapped body or a line-break the strip misses can show a marker or a receipt label the script did not author (pattern P1, pattern line-break P2, security P2, code-quality P2, data-integrity marker P2). Pattern enumerated both halves. The other keys are separate defects.

Coverage consult (`receipt-list-unescaped`): verified. `emit` joins `unmapped` and `never-read` with `", "`. A heading or directory name that contains a comma is not one list entry. `moved` stays one line because its values are the closed set Goals, Non-Goals, and Functional Requirements.

## Dedup ledger

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| A mapped body can repeat `--- projected ---` or `--- side-evidence ---`, and U+0085 or a C0 break in a name or side-evidence line can put a receipt label at column 0. | receipt-frame-not-closed | pattern-recognition-specialist, code-quality-analyst, data-integrity-guardian, security-sentinel | review fix, same commit |
| Fence toggle closes on any backtick or tilde run. Frontmatter is recognized only when line 0 is `---`. | fence-and-frontmatter-segmenter | pattern-recognition-specialist, security-sentinel | review fix, same commit |
| ATX capture keeps a trailing ` #` sequence, so `## Success Criteria ##` is not the Goals heading. | atx-closing-hashes | pattern-recognition-specialist | review fix, same commit |
| `user story` has no token boundary, so `Superuser story` and `User storyboard` become functional requirements. | user-story-token-boundary | pattern-recognition-specialist | review fix, same commit |
| An exact mapped heading whose stripped body is empty is omitted from both the bucket and the appendix. | empty-mapped-heading-vanishes | data-integrity-guardian | review fix, same commit |
| `parts_of` refuses `.` as well as `..`, so `./specs/001-demo` and a `/./` component are `not-a-directory`. | dot-component-refused | code-simplicity-reviewer, code-quality-analyst | review fix, same commit |
| Identical P2/P3 return, unused `emit` dir_fd, and the dead trailing-newline write. | dead-code | code-simplicity-reviewer, code-quality-analyst | review fix, same commit |
| Invalid UTF-8 is replaced with U+FFFD, so a corrupt byte inside `NEEDS CLARIFICATION` still projects the story. | lossy-utf8 | code-quality-analyst | review fix, same commit |
| Ordinary-heading fallthrough, receipt slices, HTML-comment greps, and the existing run sentences are not pinned. | tests-dont-pin | test-design-reviewer, agent-native-reviewer, security-sentinel | review fix, same commit |
| Plan tells the agent to Read `references/spec-kit-intake.md`, which is not a worktree-root path. | plan-read-relative-path | agent-native-reviewer | review fix, same commit |
| `emit` joins `unmapped` and `never-read` on a comma, so a multi-clause heading is more than one list entry. Verified in the diff. Coverage consult lead. | receipt-list-unescaped | coverage-consult | review fix, same commit |

## Skipped

- User-impact P1 on `Success Criteria *(mandatory)*` and child `### Measurable Outcomes`. Data-integrity measured the same fixture and called it the written map: exact heading text, every other heading listed by name. Plan lines for exact `Success Criteria` and "every other heading is unmapped." Do not fold child headings. Do not strip `*(mandatory)*`.
- Security P3 asking the script to notice an existing branch spec. The script does not write. The stop stays in the skill sentences. The test pins those sentences.
- Setext text inside a previous P1 body. Setext is not a heading. Specified.

## Seats with no findings

architecture-strategist, git-history-analyzer, performance-oracle, semgrep-sast (receipt `SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=2 rules=0 findings=0`).

## Fix contract

One commit. Refuse `intake: unreadable` with no other stdout when a projected line is either marker, or a column-0 `moved:`, `unmapped:`, `never-read:`, or digest line. Strip U+0085 from accepted file bytes. Hostile names refuse C0 other than tab, DEL, U+0085, U+2028, U+2029, and the two markers. Fence: indent 0–3, same character, closer at least as long as the opener. Frontmatter: strip a leading BOM, skip leading blank lines, then the first `---` pair. Strip a trailing ATX hash sequence. User-story match uses token boundaries and does not match `User Stories`. An empty mapped body is listed unmapped. Refuse `..` only. Strict UTF-8. Tests pin the cases above, including comment-stripped greps of the run sentences that already exist. Plan Read path becomes `plugins/soleur/skills/plan/references/spec-kit-intake.md` only if the skill-body budget still fits. Do not edit the one-shot skill. Do not fold child headings.
