# Tasks: route drain-prs, product-roadmap and the dequeue re-arm through the Review-Evidence arm check

Plan: `knowledge-base/project/plans/2026-11-12-fix-arm-check-drain-prs-product-roadmap-plan.md`. Closes #12656.

## Phase 1: Setup

- [ ] 1.1 Re-grep the arm spans in the five site files. Confirm they match the plan's Phase 4.1 list (ship :473 :1616 :1635 :2187 :2192, merge-pr :344 :349, drain-prs :84 :88 :89 :131, product-roadmap :325 :330, dequeue :30). Confirm no site file sets `H` today.
- [ ] 1.2 Write `plugins/soleur/test/arm-check-sites.test.sh`. It needs:
  - the SITES array and the joined-line span scanner;
  - assertions A1, A1-floor, A1-noH, A1-exempt, A2, A2b, A3 and A4;
  - the mutation rows M1-M8, M10, M11 and M14;
  - the harness rows H1, H3, H4 and H5;
  - a self-dispatch exit on zero spans or zero assertions.
- [ ] 1.3 Run the suite against the unedited tree. Record the RED output (T1) in the commit message.

## Phase 2: Core Implementation

- [ ] 2.1 drain-prs/SKILL.md §4:
  - [ ] 2.1.1 Opening paragraph: "arm it through the arm check". The L2 `ready-count` chain stays byte-identical.
  - [ ] 2.1.2 Checked arm: fetch `pull/<N>/head`, the check's first statement, then `--match-head-commit "${H:?run the arm check in this call}"`, all in one call. Add the route rule and refusal handling.
  - [ ] 2.1.3 Exempt arm:
    - the read call: fail-closed captures, predicates (i)/(iii)/(v) with `// "?"`, `${DOMAIN_SURFACE_RE:?`, a head re-read, and a diff capped at 1500 lines;
    - the arm call: a head-equality check, then `${EXEMPT_HEAD:?…}`;
    - the drain report line.
  - [ ] 2.1.4 Dequeue bullet: re-arm via merge-queue-dequeue step 3, or via the exempt calls for an exempt PR.
  - [ ] 2.1.5 Reword the prose at :88 and :131 ("arming enqueues", "Arming auto-merge cannot bypass").
- [ ] 2.2 drain-prs/SKILL.md §5:
  - add the bot scheduled-content bullet;
  - feature-PR bullet: "then arm through the arm check".
- [ ] 2.3 product-roadmap/SKILL.md Phase 4 step 3:
  - the lead links `#arm-check`: the check's first statement, then the lock block, in one call;
  - a non-99 rc means read the state and report;
  - both lock arms pin `${H:?…}`;
  - the SS_LIB, with_lock, running-unlocked and rc=99 lines stay byte-identical.
- [ ] 2.4 merge-queue-dequeue.md step 3: re-arm only when `null`, only through the arm check, with `PR_NUMBER="$N"`. Exempt PRs go back to drain-prs §4.
- [ ] 2.5 ship/SKILL.md: reword the prose at :473, :1616 and :1635 only.
- [ ] 2.6 review-evidence-comment.md:
  - the header site list;
  - the `## The gate` single `DOMAIN_SURFACE_RE='…'` line (A-amend classes) with the floor-not-gate prose;
  - the `## Arm check` site list plus the exemption sentence;
  - the fenced check block unchanged against 21202186df.

## Phase 3: Testing

- [ ] 3.1 Run `arm-check-sites.test.sh`: GREEN, with every mutation row RED and H3/H4/H5 GREEN (T2, T3).
- [ ] 3.2 Run the existing suites unedited:
  - concurrent-ship, drain-prs, ci-head-verdict, admin-merge-ready-wiring, monitor-lock and sync-pr-behind;
  - `bun test` over pr-merge-poll and components (T5).
- [ ] 3.3 Registration:
  - `python3 scripts/regenerate-shard-manifest.py --incremental --write`, plus the measured row in `scripts/suite-durations.tsv`;
  - lint-orphan-test-suites, test-all-corpus-weight-budget, scripts-shard-manifest and regenerate-shard-manifest;
  - markdownlint on the edited `.md` files.
- [ ] 3.4 Dry runs D1, D2, D3, D4, D6, D7, D9, D11 and D13. Use the scratchpad `gh` shim (`pr merge` prints `WOULD-ARM`) and paste each block verbatim from the edited files. Record the table in the PR body under `## Dry-run proof` (T4).
- [ ] 3.5 PR body:
  - `Closes #12656` in the body;
  - links to #12711, #12712 and #12715;
  - `technical-ruling-gate.sh --branch` passes.
- [ ] 3.6 Post-merge: run `soleur:postmerge`, then check the release with `gh release list --limit 1`.
