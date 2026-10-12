# Tasks: Gate PR merge on unarchived KB artifacts (kb-archive-gate)

Plan: `knowledge-base/project/plans/2026-10-12-feat-kb-archive-gate-plan.md`
Decisions: `knowledge-base/project/specs/kb-archive-gate/decision-challenges.md`
Scope guard: this PR does NOT touch the existing backlog or any `*/archive/` path.

## Phase 1: The hook (deliverable a)

- [x] 1.1 Create `.claude/hooks/ship-kb-archive-gate.sh` per plan §(a):
  `hook_parse_input` input contract, fail-hard source of `lib/incidents.sh` +
  `lib/hook-input.sh`, `declare -f` guard, `strip_command_bodies` on $CMD.
- [x] 1.2 Verbatim-import the resolver helpers from `pre-merge-rebase.sh`
  (`_merge_args`, `--help` pass-through, `_repo_url_parts`,
  `_repo_flag_operands`, `_repo_env_operands`, `_repo_pointers_same_repo`,
  `_strip_repo_flags`, `MERGE_TARGET_WHY` ladder, in-command-cd scan,
  `timeout`→`gtimeout`→bare wrapper, `^[0-9a-f]{40}$` oid check) with a
  provenance comment naming the source line range.
- [x] 1.3 Trigger regex `(^|&&|\|\||\||;|\(|\s--\s)\s*((<assignment>|if|while|until|then|do|elif|else|!|time|env|command|builtin|exec|nohup|sudo)\s+)*gh\s+pr\s+merge(\s|$)`
  on `$SCAN`; `SOLEUR_SKIP_KB_ARCHIVE_GATE=1` pass-through. `gh pr merge`
  only — do NOT absorb the sibling's `ready` alternation; the `\s--\s`
  member goes in BOTH the fire-check and `_merge_args` extraction regexes.
- [x] 1.4 Head resolution: `--match-head-commit <40-hex>` > bare number N
  (`git fetch --no-tags origin refs/pull/<N>/head` → FETCH_HEAD) > HEAD
  (flag-first/arg-less). L-state → deny with `MERGE_TARGET_WHY`.
  Proven-foreign repo pointer → exit 0.
- [x] 1.5 Fail-open scope: `main`/`master`/detached/bare/non-git-dir exempt
  the HEAD path only; numbered and `--match-head-commit` merges always gate.
  `git fetch --no-tags origin main` failure → deny (fail-closed); empty
  merge-base → exit 0 WITH a `headless_or_stderr` warn naming the cause
  (never silent). L-deny applies only to invocations carrying an
  unprovable target token; flag-only (`--squash --auto`, no positional)
  takes the HEAD path.
- [x] 1.6 Census: `git diff --name-status -z --diff-filter=AM base...HEAD`
  over `knowledge-base/project/{specs,plans,brainstorms}`, `read -d ''`
  parsing; drop `*/archive/*`; `specs/` requires `specs/<dir>/<file>`,
  `<dir>` != `archive`. Non-empty remainder → deny.
- [x] 1.7 Deny: `emit_incident "wg-kb-artifacts-archived-in-pr" deny` + jq
  JSON (`permissionDecision`, `hookEventName: PreToolUse`, reason ≤10
  sanitized rows + `archive-kb.sh` remediation + manual `git mv …
  specs/archive/<ts>-<dir>` path for `M`-on-`specs/` denies + ordering
  caveat naming step 2.5 and Operator Holds + `SOLEUR_SKIP_KB_ARCHIVE_GATE`
  hatch name). `bash -n` clean.

## Phase 2: The test suite + registration (deliverable a)

- [x] 2.1 Create `.claude/hooks/ship-kb-archive-gate.test.sh` on the sibling
  fixture pattern (bare origin + clone work-tree, `make_payload`,
  `test-incident-sandbox` isolation, byte-equal `assert_fixture_dir` copy).
- [x] 2.2 Deny fixtures: live spec dir; topic-named plan; live brainstorm;
  `M` row on base-live spec file; `with_lock ... --` wrapped form;
  `FOO=1` env prefix; `time`/`if`/`sudo` keyword prefixes; `x |` pipe
  form; `$(…)` substitution; `gh pr merge <N>`
  against `refs/pull/<N>/head` on the fixture origin; `--match-head-commit`;
  `-R` same-repo proven; unprovable repo pointer; foreign `cd`; raw/scan
  disagreement; fetch failure; multi-leak after compliant first.
- [x] 2.3 Pass fixtures: archive-only diff; learnings-only; non-KB diff;
  `gh pr ready`; `--help`; quoted/commit-body mentions; `bash -c` quoted
  payload (documented residual); HEAD-path on main/detached/bare/non-git;
  `SOLEUR_SKIP_KB_ARCHIVE_GATE=1`; proven-foreign `-R`.
- [x] 2.4 Accounting: `MIN_ASSERTIONS` exact floor, `pass+fail == cases`,
  `UNRESOLVED` exit-3 arm on missing jq/git, fixture-nonempty vacuity
  control (assert the live-path file exists before asserting the deny).
- [x] 2.5 Registration checks in-suite: settings.json entry ordered after
  `ship-unpushed-commits-gate.sh`; `.devin/config.json` `^exec$` twin;
  `devin-dispositions.tsv` `bind` row; resolver-parity row diffing copied
  helper bodies against `pre-merge-rebase.sh`.
- [x] 2.6 Run `python3 scripts/regenerate-shard-manifest.py --incremental
  --write`; verify `suite-shard-legs.tsv` diff is exactly one row.
- [x] 2.7 `bash scripts/lint-orphan-test-suites.sh` — no orphan; suite green.

## Phase 3: ship SKILL.md restructure (deliverable b)

- [x] 3.1 Insert `## Phase 6.45: KB Artifact Archival` between the `gh pr
  create` block and `### Semver Label and Changelog`; move step 5.5's body
  verbatim; add `[skill-enforced: ship Phase 6.45 + hook
  ship-kb-archive-gate.sh]` marker and `SOLEUR_RULE_APPLIED` echo for
  `wg-kb-artifacts-archived-in-pr`.
- [x] 3.2 Exists-arm: delete step 5.5; move steps 6-7 (ready+arm,
  `wait-ready-run`, UNTRUSTED-CI announce, present-URL) into Phase 6.5's
  arming block with the `isDraft` preamble.
- [x] 3.3 Phase 5 Final Checklist: add `- [ ] KB artifacts archived (Phase
  6.45 gate)` before the Push row.
- [x] 3.4 Update cross-refs: `archive-kb/SKILL.md:30`,
  `compound/SKILL.md:517`, `ship/SKILL.md`'s Phase-7 archival passage,
  `ready-run-wait.md:5`, `settle-then-admin-merge.md:117`. Re-grep
  `Phase 6 step` across `plugins/soleur/skills/` — only unchanged-meaning
  hits remain (AC16).

## Phase 4: postmerge read-back (deliverable c)

- [x] 4.1 Insert `## Phase 5.8: KB archival read-back (REPORT-ONLY)` in
  `postmerge/SKILL.md` after Phase 5.7: `git diff --name-status
  --diff-filter=AM <merge-sha>^ <merge-sha>` over the three roots;
  non-`archive/` rows reported verbatim in Phase 6 comment + Phase 7
  summary; names `bash
  plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` on a new branch;
  never blocks "done".

## Phase 5: archive-kb discovery (deliverable d)

- [x] 5.1 Extend `archive-kb.sh` discovery to untracked paths:
  `git status --porcelain` `??` rows ONLY over the three roots (staged/
  modified already covered by branch-diff), same `*/archive/*` exclusion
  and spec-file→dir collapse — a lone untracked root-level file
  (`specs/.gitkeep`) does not fire; `|| true` under pipefail.
- [x] 5.2 Record the measured verification (feat-one-shot-9969-edge-roots
  dry-run lists spec dir + topic-named plan) in `archive-kb/SKILL.md`;
  comment on #7383 at ship (do not close from the plan).

## Phase 6: rule corpus + ledger

- [x] 6.1 `AGENTS.rules.md`: add `wg-kb-artifacts-archived-in-pr`
  Workflow-Gates entry (≤600 B body, why-single-line);
  `AGENTS.md`: add the index pointer. Re-run
  `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`.
- [ ] 6.2 Deferral for the sibling `\s--\s` gap (`ship-unpushed-commits-
  gate.sh`, `cla-signed-author-gate.sh`): run the
  `wg-defer-only-after-inline-triage` triple test at ship — pass → file
  the `type/chore` tracking issue; fail → durable in-place comments at
  each sibling's trigger line.
- [x] 6.3 AC pass: tick AC1–AC21 in the plan (self-application AC21 at
  ship: Phase 6.45 archives this spec dir + plan before arming).
