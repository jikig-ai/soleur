# Tasks: argv-bearer sweep Tier 3, guard-first slice (S1) and review SKILL.md extraction

Plan: `knowledge-base/project/plans/2026-10-07-fix-argv-bearer-sweep-tier3-guard-first-slice-and-review-skill-extraction-plan.md`
Issue: Ref #9597, Ref #7797 (no `Closes` in S1). Branch: `feat-one-shot-argv-bearer-sweep-tier3`.

Rules for every task: never print, echo or grep for a credential value; no `git stash`; no
pattern-matching process kill; do not run `scripts/test-all.sh` locally (run owning suites directly);
one push at the end; run lints on a committed tree.

## Phase 0: Census and RED rows

- 0.1 Re-run `python3 scripts/lint-shell-trace-credential-refusal.py --census` and the widened-vocabulary prototype; write the per-file table (path, group, site count) to `knowledge-base/project/specs/feat-one-shot-argv-bearer-sweep-tier3/census-tier3.md`. Compare with the plan's numbers (35 Bearer argv sites in 16 files; 53 widened YAML sites; 86 widened sites in 34 files overall) and record any difference.
- 0.2 Add RED rows to `scripts/lint-shell-trace-credential-refusal.test.sh` for Guard 1 mutation rows 1 to 9 and the harness rows (YAML shapes: literal, folded, inline, inline-escaped, list-item continuation, `${{ }}`; must-PASS: echo-only, `printf | curl -H @-`, non-bash `shell:`).
- 0.3 Add RED rows to `tests/scripts/test-argv-bearer-sweep.sh` for each community-script call site (token absent from argv, exact stdin config, refusal row, must-PASS real token shape, bsky `--data-binary @file` body rows). Cross-check the shim against the real curl config parser with a local server and fake credentials.
- 0.4 Confirm no owning tests exist for the four community scripts (`git grep` over `*.test.*`); the battery hosts the rows.

## Phase 1: Lint arms and seeded baseline (guard first)

- 1.1 Replace `E_BEARER` by a named credential-header constant at its five read sites (held-name capture, array capture, `_e_scan`, `bearer_in_call`, wrapper-site `bearer_ctx`); keep `E_APIKEY` semantics; update finding text and remedy line.
- 1.2 Add `-u` / `--user` with a variable operand to `_e_scan`.
- 1.3 Add `rule_e_files()` with two feeders: PyYAML `run:` extractor for `.github/**` (skip non-bash `shell:`; report step name and best-effort line) and raw-line feeder for `cloud-init-*.yml` plus parse-failure fallback with a stderr note. Rules A to D and `--changed` stay `*.sh`-only. Verify each `git ls-files` pathspec matches at least one real file.
- 1.4 Fix the known miss: array-held `Authorization: Bot` in `discord-setup.sh` must be flagged (RED row first).
- 1.5 Re-time the repo-wide lint run after the arm lands (about 7 s before) and record it; confirm PyYAML is importable in the CI shard that runs it.
- 1.6 Update the lint docstring's Rule E block (members, YAML scope and the two feeders, vocabulary, `--changed` decision and reason, blind spots).

## Phase 2: Community scripts

- 2.1 `discord-community.sh` (line about 220) and `discord-setup.sh` (`curl_args` array, line about 74): Bot token through `--config -` with a process substitution, `--disable --noproxy '*'` first, token-shape guard before the call, refusal through the script's existing error path (read its exit and alert semantics first).
- 2.2 `bsky-setup.sh` (line about 268) and `bsky-community.sh` (line about 237): createSession body written by `jq -n --arg` to a 0600 `mktemp -t` file, sent with `--data-binary @file`, trap cleanup per `lint-trap-tempfile-ownership.py`, explicit JSON `Content-Type`.
- 2.3 `plugins/soleur/skills/flag-bootstrap/SETUP.md`: five `Api-Key` examples to the stdin-config form; add a `git grep` row to the battery.
- 2.4 Seed `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` with measured counts (minus the converted community scripts). Rebase onto current `origin/main` first; regenerate with `--write-baseline-e` only on the rebased tree; never hand-edit the nic-guard line (PR #9632).

## Phase 3: review SKILL.md extraction and Sharp Edge

- 3.1 Re-grep the pinned anchors (`lifecycle-handoff-protocol`, `run only the suites targeting the files they were given`, `TEST_GROUP=affected bash scripts/test-all.sh`, `SOLEUR_SUBAGENT`) and confirm none is inside lines 1183 to 1441.
- 3.2 Create `plugins/soleur/skills/review/references/defect-classes.md` with the Defect Classes lead-in and 150 bullets verbatim; prove byte identity (`wc -c` and a diff of the concatenation).
- 3.3 In SKILL.md keep the heading and replace the body with a `**Read [defect-classes.md](./references/defect-classes.md) now**` directive (markdown link, three Read pages stated) under the Findings Synthesis step; keep the `[workflow suites](./references/wfs.md)` bullet.
- 3.4 Add the stall Sharp Edge (last block a `tool_use` means not delivered; read last assistant text with `jq`, never `Read` or `tail` the JSONL; then `SendMessage` "make no further tool calls, reply now with the report"; evidence PR #9654) next to the existing "Parallel review batches can stall silently" bullet.
- 3.5 Record the byte delta; do not touch the `description:` frontmatter or `skill-body-budget.json`.
- 3.6 Run `lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"`, `bun test plugins/soleur/test/components.test.ts`, `bash plugins/soleur/test/fanout-suite-scope.test.sh`, `bun test plugins/soleur/test/workflow-fidelity.test.ts`.

## Phase 4: Verification (committed tree)

- 4.1 Run every item of plan Phase 4 (items 0 to 13), including the gates' own `--changed --base origin/main` invocations and `npx markdownlint-cli2` over the plan and this file.
- 4.2 Confirm `git diff --name-only "$(git merge-base HEAD origin/main)"..HEAD` has no `apps/web-platform/infra/` path, no `apply-web-platform-infra.yml`, no `destroy-guard-filter-web-platform.jq`.

## Phase 5: PR

- 5.1 PR body first line states that merging does not mutate production; then `Ref #9597`, `Ref #7797`, slice table, review coverage, #9632 sequencing note.

## Phase 6: Tracking

- 6.1 Verify labels exist (`gh label list --limit 200`), then file four slice issues (S2 ops and runner scripts with `Closes #8767` in its eventual PR; S3 workflow YAML without production effect plus the shared helper; S4 push-triggered production-class files; S5 apply workflow and cloud-init-registry, last) with milestones and `--add-blocked-by` edges (S4 after S3 helper; S5 after S3 and S4).
- 6.2 Restate the #9597 body (slice table, corrected measurements); comment on #7797, #7898 and #8767; leave all open.

## Out of scope (parent session, ops follow-ups)

- Why the push-triggered infra apply did not fire after the Tier 2 merge (operator-gated production apply).
- web-2 tracking: replaced 2026-10-06 19:28Z from main at `2efc8025ff`, before the Tier 2 merge; re-check at its next replacement.
