# Tasks: migrate the skills `${CLAUDE_PLUGIN_ROOT:-…}` and git-root anchors to the bare plugin-root anchor (#7453)

Plan: `knowledge-base/project/plans/2026-09-24-chore-migrate-skills-plugin-root-default-sites-to-bare-anchor-plan.md`.
Governing ADR: ADR-179 (not ADR-177).

## Phase 0: Preconditions

- [ ] 0.1 `git fetch origin main`. Re-derive the five Phase 0 counts (102 / 31 / 2 / 131 / the
  battery-tag-authorship closure count) and record them. If any count differs, re-derive the site
  list; never edit toward the plan's number.

## Phase 1: Guards RED first (`apps/web-platform/test/plugin-root-anchoring.test.ts`)

- [ ] 1.1 Guard 1 over the tracked `plugins/soleur/**/*.md` (`git ls-files --full-name`), zero
  tolerance:
  - [ ] 1.1.1 `readsRootUnsafely`, reused by reference.
  - [ ] 1.1.2 New `plantsRootUnsafely`: the `CLAUDE_PLUGIN_ROOT=` assignment check, the
    any-variable default arm toward `plugins/soleur`, and the `env` read. Covered by
    `PLANT_FIXTURES`.
  - [ ] 1.1.3 A live-scan dispatch control: the population plus one synthetic source gives exactly
    `[synthetic]`.
  - [ ] 1.1.4 A literal population floor of ≥ 550, and one aggregated check per predicate.
- [ ] 1.2 Guard 2: literal regexes 2a (dynamic prefix, quote-, `//`- and `/./`-tolerant), 2b
  (backtick `show-toplevel`) and 2c (`..` anywhere after the token). Add `DYNPREFIX_FIXTURES` with
  ≥ 10 entries, including the 7 security-review bypass forms and the `/plugins/soleur/…NOTICE`
  must-pass.
- [ ] 1.3 Guard 4 for the read-from-disk docs:
  - [ ] 1.3.1 (a) the notice plus the closed-rule sentence.
  - [ ] 1.3.2 (b) no CWD-relative path **or relative markdown link** points at a qualifying doc.
  - [ ] 1.3.3 (c) every `bash`/`sh` fence starts with the sentinel `export`.
  - [ ] 1.3.4 (d) the set equals the 5 named docs.
- [ ] 1.4 Ratchet:
  - [ ] 1.4.1 Drop form (a) and R5's `"a"`.
  - [ ] 1.4.2 Lower `RATCHET_MIN_ROWS` 120 → 85 **first**.
  - [ ] 1.4.3 Re-point `RATCHET_HEADER`, the THIRD AXIS comment, the R2 message and the describe
    title to #6222/#8729. Defer the regeneration to Phase 10.
- [ ] 1.5 Raise the anti-vacuity floors in the same edit. Add the one-screen guard index comment.
- [ ] 1.6 Run vitest and expect RED at these counts. Save the output as `phase1-red-run.txt`.
  - Guard 1: 31 files for (i) and 31 for (ii).
  - Guard 2: 3 + 2 + 0.
  - Guard 4: (a) 2, (b) 9, (c) 2, (d) set mismatch.

## Phase 2: Pattern C (`preflight/SKILL.md`)

- [ ] 2.1 Set `FORM_A_AWK=` and `PROBE_GATE=` to `"${CLAUDE_PLUGIN_ROOT}/skills/preflight/scripts/…"`,
  and replace the rationale comment.
- [ ] 2.2 `preflight-discoverability-test.test.ts`:
  - [ ] 2.2.1 Invert the git-rev-parse test.
  - [ ] 2.2.2 Add the unset-root decoy row: `env -u`, a pre-created empty `mktemp` ledger that
    must still be empty afterwards, and a twin positive control where the pre-migration block
    writes the decoy ledger.

## Phase 3: Prose (before the scripted replace)

- [ ] 3.1 Reword `community`, `work` (#7442 bullet) and `ship` (A13 comment), and the
  `commands/sync.md` double-prefix example.
- [ ] 3.2 Anchor four `plugins/soleur/scripts/admin-merge-ready.sh` prose mentions (`ship`,
  `merge-pr`, `drain-prs`, `one-shot`). In `schedule`, write the prose "the installed Soleur
  plugin's `scripts/admin-merge-ready.sh`" instead of the token.

## Phase 4: Executable `SKILL.md` sites (fixed-string replace, quoted, tail untouched)

- [ ] 4.0 Add the caller fail-safe lines:
  - in `skill-security-scan` and `skill-creator`: a missing verdict line means REVIEW;
  - in `review`: a non-zero trailer exit means not attested.
- [ ] 4.1 Tier 1 commits:
  - `ship`, `skill-security-scan`, `skill-creator`, `review`, `merge-pr`;
  - `work`, `one-shot`, `git-worktree`, `drain-prs`, `fix-issue`, `product-roadmap`.
- [ ] 4.2 Tier 2 commits:
  - `archive-kb`, `brainstorm`, `compound`, `compound-capture`;
  - `constraint-scaffold`, `deploy`, `drain-labeled-backlog`, `feature-video`;
  - `harvest-debt`, `kb-search`, `model-launch-review`, `pencil-setup`, `plan`, `seo-aeo`.
- [ ] 4.3 The four `git-worktree` `list` sites take exactly
  `bash "${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh" list`.

## Phase 5: schedule template

- [ ] 5.1 Remove the `SS_LIB`/`with_lock` branch from the one-time `prompt: |`, so it calls
  `gh pr merge --auto` directly. Update the rationale.
- [ ] 5.2 `concurrent-ship.test.sh`:
  - [ ] 5.2.1 Drop `schedule` from T1 and T1c.
  - [ ] 5.2.2 Move T1c's presence check to bare, and add its absence row.
  - [ ] 5.2.3 Add a template row. It first asserts the extracted block is non-empty and contains
    both `gh pr merge --auto` and `MERGE_ERR`, then asserts the block carries no
    `CLAUDE_PLUGIN_ROOT`.
- [ ] 5.3 Run `schedule-skill-once.test.sh` and `lint-scheduled-show-full-output.sh`.

## Phase 6: Read-surface docs (P7)

- [ ] 6.1 Migrate the 8 `:-` sites in the two brainstorm workshops and `settle-then-admin-merge.md`.
- [ ] 6.2 Every executable block in the five docs gets the first line
  `export CLAUDE_PLUGIN_ROOT="/__REPLACE_WITH_SOLEUR_PLUGIN_ROOT__"`, the absolute sentinel. The
  admin-merge blocks also get the exit-5 presence check.
- [ ] 6.3 Add the `**Plugin root in this file:**` notice to all five docs (≤ 100 words, with the
  closed-rule sentence and no `./plugins/soleur` spelling). SETUP.md gets the operator wording.
- [ ] 6.4 Loader-anchor every pointer:
  - `brainstorm/SKILL.md` ×2 and `review/SKILL.md` (currently CWD-relative);
  - the relative links to `settle-then-admin-merge.md` in `ship` (×3), `merge-pr`, `drain-prs`
    and `one-shot`.
- [ ] 6.5 `admin-merge-ready-wiring.test.sh`:
  - [ ] 6.5.1 Update `REF_GATE`.
  - [ ] 6.5.2 Positive row: the harness replaces the sentinel, the stub ran, and the `gh` ledger
    is non-empty.
  - [ ] 6.5.3 Unreplaced-sentinel row, under `env -u`: exit 5, the message printed, and the empty
    `mktemp` ledger still empty.
  - [ ] 6.5.4 Decoy twin row: the pre-migration block writes the decoy ledger.

## Phase 7: `safe-bash.ts` carve-out

- [ ] 7.1 Implement 4 exact literals: {bare, `SOLEUR_PLUGIN_PATH_DEFAULT`-substituted} ×
  {`list`, `ls`}. No `RegExp` change. Rewrite the comments.
- [ ] 7.2 `safe-bash.test.ts`:
  - [ ] 7.2.1 Add positives for both members.
  - [ ] 7.2.2 Add the full negative list (`-pwn`, `/tmp/x` root, unquoted bare, removed `:-`,
    `..`, `other.sh`, write verbs, `export … &&`, embedded newline). Add the positive control
    `pwd && <bare member> list`.
  - [ ] 7.2.3 Add the identity pin.
- [ ] 7.3 Coupling test:
  - [ ] 7.3.1 Widen `LIST_EMISSION`, and normalise each emission with the exported
    `TRAILING_SAFE_REDIRECT` (its value unchanged).
  - [ ] 7.3.2 Check raw and substituted membership.
  - [ ] 7.3.3 Pin `toBe(4)` and rewrite the docstring.

## Phase 8: Remaining consumers and docs

- [ ] 8.1 `lease-protects-active.test.sh` scenario 10: bare quoted hop, plus the unset-root decoy
  row (`env -u`, `mktemp` ledger). Add a twin positive control built from string pieces.
- [ ] 8.2 Server comments only: `agent-env.ts`, `agent-runner-query-options.ts` and the propagation
  probe.
- [ ] 8.3 Add the `CONTRIBUTING.md` line: `claude --plugin-dir "$PWD/plugins/soleur"` for testing
  edited payload scripts.
- [ ] 8.4 Leave the do-not-touch list untouched. Record the reasons for the PR body.

## Phase 9: ADRs

- [ ] 9.1 ADR-179: add `## Amendment — 2026-09-24 (#7453)` with A18 (including the Tier-1 exit-127
  table; verify the `run-scan.sh` and `emit-review-trailer.sh` caller handling and record the
  line), A19 (carve-out) and A20 (Read surface, Grok #8730, Devin cost). Add `amended_by:` and
  strike through the Consequences deferral bullet.
- [ ] 9.2 ADR-093: extend the "Amended by" line.

## Phase 10: Regenerate and verify

- [ ] 10.1 Create `scripts/plugin-root-anchor-debt.sh` (mode 100755, rc-branching,
  `BASH_SOURCE` root). Record `=31` before, `=0` after.
- [ ] 10.2 Regenerate the ratchet TSV with the guarded writer, as the last markdown step. Diff the
  data rows only: exactly 38 form-(a) removals.
- [ ] 10.3 Run the derived regression sweep (Test Scenarios, union of 3 sources), then
  lint-guard-contract, lint-skill-body-budget (CI form), markdownlint, lint-infra-no-human-steps
  and lint-shell-capture-exit.
- [ ] 10.4 C4: `c4-count-parity.test.sh`, `c4-code-syntax.test.ts`, `c4-render.test.ts`.
- [ ] 10.5 AC12 real-harness captures, with the plugin relocated: `cp -r` it to
  `$TMP/soleur-plugin`, then run `--plugin-dir` against that copy with canaries planted in the
  worktree copy. Capture the `list` step and the settle-then-admin-merge read path. Commit them
  verbatim.
- [ ] 10.6 Walk AC1–AC13 and record each output in the spec directory.
