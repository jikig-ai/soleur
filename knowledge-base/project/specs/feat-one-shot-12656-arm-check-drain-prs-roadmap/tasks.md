# Tasks: route drain-prs, product-roadmap and the dequeue re-arm through the Review-Evidence arm check

Plan: `knowledge-base/project/plans/2026-11-12-fix-arm-check-drain-prs-product-roadmap-plan.md`. Closes #12656.

## Phase 1: Setup

- [x] 1.1 Re-grep the arm spans in the five site files. Confirm they match the plan's Phase 4.1 list (ship :473 :1616 :1635 :2187 :2192, merge-pr :344 :349, drain-prs :84 :88 :89 :131, product-roadmap :325 :330, dequeue :30). Confirm no site file sets `H` today.
- [x] 1.2 Write `plugins/soleur/test/arm-check-sites.test.sh`. It needs:
  - the SITES array;
  - the joined-line span scanner with the Phase 0 terminators (next `gh pr merge`, `;`, `&&`, `||`, `|`, `)`, backtick);
  - assertions A1, A1-floor, the broadened A1-noH, A1-exempt, A2, A2b in statement form, A3, A4 with the `^`-anchored match, the 38-path MUST-MATCH list and 4 MUST-NOT, and A5 for sync-pr-behind.sh;
  - mutation rows M1, M2, M2b, M3, M5, M6, M7, M8 (M8b on merge-queue-dequeue), M10 (three spellings), M11, M14 (the paste plus the 28-alternative loop, split on top-level `|`) and M15;
  - harness rows H1, H3-H7 and the H8 control;
  - `bash "$0" --root` self-dispatch with an assertion-ID ledger: exit 1 on a caught failure or `ZERO-SPANS`, exit 2 on an instrument failure;
  - an exactly-one `edit()` helper.
- [x] 1.3 Run the suite against the unedited tree. Record the RED output (T1) in the commit message.

## Phase 2: Core Implementation

- [x] 2.1 drain-prs/SKILL.md §4:
  - [x] 2.1.1 Opening paragraph: "arm it through the arm check". The L2 `ready-count` chain stays byte-identical.
  - [x] 2.1.2 Checked arm: fetch `pull/<N>/head`, the check's first statement, then `--match-head-commit "${H:?run the arm check in this call}"`, all in one call. Add the route rule and refusal handling.
  - [x] 2.1.3 Exempt arm:
    - the read call, copied verbatim from plan Phase 1 item 4, with one named fail-closed statement per predicate:
      - (i) the `app/soleur-ai`/`app/soleur-infra` author plus `isCrossRepository=false`;
      - (iii) bot author and committer, or a clean sync via `git merge-tree --write-tree`, with at most 250 commits;
      - (v) `--no-renames`, `core.quotePath=false`, and quoted/symlink/submodule/binary refusal;
      - (vi) at most 1500 lines;
      - a head re-read, then the git-dir head file;
    - the arm call: read and remove the head file, a head-equality check, then `${EXEMPT_HEAD:?…}`;
    - the "never assign `H`/`EV`/`EXEMPT_HEAD` by hand" sentence;
    - the drain report line `exempt: first-party bot, bot-only or clean-sync commits, no domain surface, read at <sha>`.
  - [x] 2.1.4 Dequeue bullet: re-arm via merge-queue-dequeue step 3, or via the exempt calls for an exempt PR.
  - [x] 2.1.5 Reword the prose at :88 and :131 ("arming enqueues", "Arming auto-merge cannot bypass").
- [x] 2.2 drain-prs/SKILL.md §5:
  - add the bot scheduled-content bullet;
  - feature-PR bullet: "then arm through the arm check".
- [x] 2.3 product-roadmap/SKILL.md Phase 4 step 3:
  - the lead links `#arm-check`: the check's first statement, then the lock block, in one call;
  - a non-99 rc means read the state and report;
  - both lock arms pin `${H:?…}`;
  - the SS_LIB, with_lock, running-unlocked and rc=99 lines stay byte-identical.
- [x] 2.4 merge-queue-dequeue.md step 3: re-arm only when `null`, only through the arm check, with `PR_NUMBER="$N"`. Exempt PRs go back to drain-prs §4.
- [x] 2.5 ship/SKILL.md: reword the prose at :473, :1616 and :1635 only.
- [x] 2.5b sync-pr-behind.sh `kind=dequeued` message step (3): re-arm only through the arm check, naming `review-evidence-comment.md#arm-check`. Update the pins in ship-phase-7-poll-fixtures.test.sh scenario 18b and sync-pr-behind.test.sh dequeue tick 2 (Phase 3b).
- [x] 2.6 review-evidence-comment.md:
  - the header site list;
  - the `## The gate` single **column-0** `DOMAIN_SURFACE_RE='…'` line: the A-amend classes plus the deepen agent-instruction and CI-execution classes, 28 alternatives, with the floor-not-gate prose;
  - the `## Arm check` site list (sync-pr-behind included), the exemption sentence and the never-assign-by-hand sentence;
  - the fenced check block unchanged against 21202186df.

## Phase 3: Testing

- [x] 3.1 Run `arm-check-sites.test.sh`. It must be GREEN, every mutation row must exit 1 naming its assertion, H1 must give `ZERO-SPANS`, H3-H7 must stay GREEN, and the H8 control must exit 0 (T2, T3).
- [x] 3.2 Run the existing suites unedited:
  - concurrent-ship, drain-prs, ci-head-verdict, admin-merge-ready-wiring and monitor-lock, all unedited;
  - sync-pr-behind and ship-phase-7-poll-fixtures, with only the Phase 3b pin edits;
  - `bun test` over pr-merge-poll and components (T5).
- [x] 3.3 Registration:
  - `python3 scripts/regenerate-shard-manifest.py --incremental --write`, plus the measured row in `scripts/suite-durations.tsv`;
  - lint-orphan-test-suites, test-all-corpus-weight-budget, scripts-shard-manifest and regenerate-shard-manifest;
  - markdownlint on the edited `.md` files.
- [x] 3.4 Dry runs D1, D2, D3, D4, D6, D7, D7b, D9, D11, D13, D14 and D15 (T4):
  - Use the read-only allowlist `gh` shim: `pr merge` prints `WOULD-ARM`, and any other write is refused into `shim-refused.log`, which must end empty. `type -p gh` must name the shim.
  - Compose each block by anchor from the edited files with `compose.sh`, and record its sha256.
  - Expect full 40-hex SHAs, and no leftover `soleur-exempt-*.head` file.
  - Record the table in the PR body under `## Dry-run proof`.
- [ ] 3.5 PR body:
  - `Closes #12656` in the body;
  - links to #12711, #12712, #12715 and #12721;
  - `technical-ruling-gate.sh --branch` passes.
- [ ] 3.6 Post-merge: run `soleur:postmerge`, then check the release with `gh release list --limit 1`.
