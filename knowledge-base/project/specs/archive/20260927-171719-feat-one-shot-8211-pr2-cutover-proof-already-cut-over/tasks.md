# Tasks: git-data cutover proof on the LUKS-served store (#8211 PR2, proof half)

Plan: `knowledge-base/project/plans/archive/20260927-171719-2026-09-27-feat-git-data-cutover-proof-on-luks-mapper-plan.md`.
Commit each phase with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`. Rely on CI for the full
suite.

## Phase 1: Setup — flip the canonical fixture (suite only)

- [ ] 1.1 `ssh` shim:
  - [ ] `findmnt -no SOURCE` defaults to `/dev/mapper/git-data`.
  - [ ] Add the `plain`, `mapperalt` and `mapperpre` modes.
  - [ ] `noeol` answers the mapper.
- [ ] 1.2 `findmnt` shim:
  - [ ] the `-T` default is the mapper;
  - [ ] `-no UUID` reads `SHIM_FINDMNT_UUID` (a value, `empty` or `fail`);
  - [ ] positional `-no SOURCE` reads `SHIM_FINDMNT_S`.
- [ ] 1.3 Add the `r=*` arm (`SHIM_VERIFY=ok|r<n>|line2|empty|notok|exec`) and
  `SHIM_VERIFY_STDERR`.
- [ ] 1.4 `VX-*` rows always set fixture `OLD_ROOT` and `STORE_VERIFIED` under `$T`.
- [ ] 1.5 Rename `store-not-cut-over`.
- [ ] 1.6 AC2: the timeline has 7 SSH calls and the annotation set has 9 notices.
- [ ] 1.7 `case_main_order`: update the list and its alternation together.
- [ ] 1.8 FSRC becomes MAP-ALT, `_fence_call` uses the mapper, and P2 moves in tandem with the
  `OLD_ROOT` comment.
- [ ] 1.9 Comment why `mutating()` forces positional `findmnt`.

## Phase 2: Core Implementation

- [ ] 2.1 Behaviour rows (RED), for every unit row in the plan's Test Scenarios:
  - [ ] 2.1.1 P3 parity, derived excluding `*.test.sh` and the script: `STORE_DEVICE` 5,
    `STORE_VERIFIED` 5, the `cutover_freeze` suffix 4, `MOUNT_ROOT` and `GIT_DATA_ROOT` 6.
  - [ ] 2.1.1a P3 is `case_parity <script> <dir>`, run over a copied directory, with 3 mutants.
  - [ ] 2.1.2 RB, in both directions:
    - producer 1 (script tokens) = producer 2 (observed `STORE` lines) = a pinned count;
    - the runbook side reads only the verdict-map section, with word boundaries;
    - the reverse check runs;
    - 3 RB mutants.
  - [ ] 2.1.3 VINJ (injected `::error::`/`::add-mask::` stderr), Vnotok, ARG-mapper, and the
    non-empty VX-dirmk.
- [ ] 2.2 Script (GREEN), `apps/web-platform/infra/git-data-cutover.sh`:
  - [ ] 2.2.1 `STORE_VERIFIED` config, and the `OLD_ROOT` and `LUKS_MAPPER` comments.
  - [ ] 2.2.2 `refuse_if_cut_over` becomes `refuse_if_not_on_mapper` (`store-on-mapper`,
    `store_not_on_mapper`). `LUKS_MAPPER` is validated first (`reason=arg_mapper`).
  - [ ] 2.2.3 `refuse_if_store_unverified`:
    - one `c=( … )` session. The prefix is only `"r=$qr; src=$qs; mk=$qm"`, where `src` is
      `STORE_SOURCE` re-checked against `^/dev/…` before `%q`. `fz="$r/.cutover-freeze"` is its own
      single-quoted element;
    - the `arg_root` and `arg_marker` checks;
    - rc 5, 6, 24, 21, 16, 22 and 23;
    - an explicit `*)` arm.
  - [ ] 2.2.4 `main` order, and the start and `clear` log text (no encryption claim).
  - [ ] 2.2.5 Header rewrite and the `refuse_real_modes` remedy line.
  - [ ] 2.2.6 `lint-shell-capture-exit.py`, `shellcheck`, `bash -n`.
- [ ] 2.3 Runtime arm:
  - [ ] 2.3.1 The fixture `findmnt` UUID branch, and the container writes the marker with
    `printf '%s\n'`.
  - [ ] 2.3.2 Every `/dev/sdb` reset becomes the mapper.
  - [ ] 2.3.3 Runtime rows:
    - R5b is the exact 7-line list, and R5c reads web 7 / gd 5.
    - R7 is inverted.
    - Add RVM: the marker is restored by a trap, and the output holds no UUID or marker bytes.
    - Add RVM2: a canonical run right after it.
    - Delete RFSRC.
  - [ ] 2.3.4 `RUNTIME_ROWS` is counted.
- [ ] 2.4 Docs, ADRs, workflow, C4:
  - [ ] 2.4.1 The workflow header comment.
  - [ ] 2.4.2 Runbook:
    - the Preconditions bullet;
    - step 7 and "Exit 0 means" (no encryption claim; #8634);
    - step 5 rewrite: the evidence chain (a)-(c), the #5914 template (with the scoped wording) and
      the 5.3 rule.
      - (b) binds to `boot_complete` plus the replace-run chain, and is fail-closed.
      - (c) pages every config back past the older volume's `created` time;
    - the verdict map grouped by action class.
  - [ ] 2.4.3 ADR-239 dated amendment. The status is unchanged.
  - [ ] 2.4.4 ADR-220 amendment-log entry restating D1b's flip condition.
  - [ ] 2.4.5 `model.c4` edge prose, then `bash scripts/regenerate-c4-model.sh`.

## Phase 3: Testing

- [ ] 3.1 Mutants, against the real text and scoped by function range:
  - re-anchor `g2-no-cut-over` (renamed `g2-no-on-mapper`), `g5-raw-capture` and `f-m17`;
  - scope `f-m2` and `f-m16`;
  - add the Guard 1 rows 1-5 and Guard 2 rows 1-10, plus the harness rows.
- [ ] 3.1a Guard 2 rows 5a/5b/11/12, Guard 1 row 6, and the two shim-dispatch harness rows.
- [ ] 3.2 Floors:
  - compute the expected `MUTANT_FLOOR` from the matrices first;
  - switch both checks to `-ne`;
  - do one `GDC_SKIP_RUNTIME=1` run after 2.3, where the measured value must equal the computed
    one;
  - restate the ledger comment;
  - re-measure after any `main` sync that touches the suite.
- [ ] 3.3 `c4-count-parity`, `c4-model-freshness`, `markdownlint-cli2` on the edited docs.
- [ ] 3.4 Push. The CI suite is green, including the runtime arm. Required checks are green on the
  head SHA.
- [ ] 3.5 PR body:
  - `Ref #8211` and `Ref #5914`;
  - a first line naming the production effect: a same-code redeploy;
  - the PR2 items that remain;
  - the CPO conditions word for word, also posted as a comment on #8211;
  - `decision-challenges.md` rendered.
- [ ] 3.6 Post-merge:
  - PM1:
    - wait for the release deploy, then dispatch, capture the run id and watch;
    - the operator approves. The session approves only with explicit in-session consent, after the
      path, event, branch, SHA and actor checks;
    - cancel the run if it is still unapproved;
  - PM2: read the nine notices;
  - PM3: the #5914 record;
  - PM4: the docs PR for the D1b and C4 TARGET flips and the ADR-239 status read, or a tracking
    issue.
