# Tasks: argv-bearer sweep Tier 3, guard-first slice (S1) and review SKILL.md extraction

Plan: `knowledge-base/project/plans/2026-10-07-fix-argv-bearer-sweep-tier3-guard-first-slice-and-review-skill-extraction-plan.md`
Issue: Ref #9597, Ref #7797 (no `Closes` in S1). Branch: `feat-one-shot-argv-bearer-sweep-tier3`.

Rules for every task: never print, echo or grep for a credential value; no `git stash`; no
pattern-matching process kill; do not run `scripts/test-all.sh` locally (run owning suites directly);
one push at the end; run lints on a committed tree.

## Phase 0: Census and RED rows

- 0.1 Re-run `python3 scripts/lint-shell-trace-credential-refusal.py --census` and the widened-vocabulary prototype; record the per-file table (path, group, site count) once, in the PR body and the #9597 restatement. Compare with the plan's numbers (35 Bearer argv sites in 16 files; 53 widened YAML sites; 86 widened sites in 34 files overall) and record any difference.
- 0.2 Add RED rows to `scripts/lint-shell-trace-credential-refusal.test.sh` for Guard 1 mutation rows 1 to 9 and the harness rows (YAML shapes: literal, folded, inline, inline-escaped, list-item continuation, `${{ }}`; must-PASS: echo-only, `printf | curl -H @-`, non-bash `shell:`).
- 0.3 Add RED rows to `tests/scripts/test-argv-bearer-sweep.sh` for each community-script call site (token absent from argv, exact stdin config, refusal row, must-PASS real token shape, bsky `--data-binary @file` body rows). Cross-check the shim against the real curl config parser with a local server and fake credentials.
- 0.4 Extend `plugins/soleur/skills/community/test/community-argv.test.sh` (sibling PATH-shim suite) for the four scripts; census the indirect suites that must stay green (`plugins/soleur/skills/incident/test/redact-sentinel.test.sh`, `apps/web-platform/test/server/inngest/cron-community-monitor-allowlist.test.ts`, `test/content-publisher.test.ts`).
- 0.5 Shim and suite extensions, each its own commit: parameterise the battery's `evaluate` and shim by scheme (`Bot`) with a `Bot`-to-`Bearer` mutation; make the shim record `--data-binary @file` content and `stat` mode at curl time, add a `fail7` mode, calibrate with `--libcurl`; add a `jq` shim; relax the battery's followthrough-in-baseline-E population row to the S2-owned list.
- 0.6 Lint-suite mechanics: drive repo-wide rows through `sbx_repo`; add the YAML fixture set under `scripts/fixtures/shell-trace-refusal/` (dispatch by suffix and content); give `fx_mut_row` a suffix parameter; pin the finding grammar and update `E_MSG_RE` with a self-check row; raise `MIN_ASSERTIONS`, make `E_ROWS` exact, add `Y_ROWS`.
- 0.7 Diff the Rule D census before and after the `_array_body` declaration fix (expect 14 to 15, adding `discord-setup.sh`).
- 0.8 Check `git status --short` shows only intended files before running `--changed`; check `gh pr view 9632 --json state,mergedAt` and rebase first if it merged.

## Phase 1: Lint arms and seeded baseline (guard first)

- 1.1 Replace `E_BEARER` by a named credential-header constant (any `Authorization:` scheme, `CF-Access-Client-(Id|Secret)`, `X-Signature-256`, `X-API-Key`) at its five read sites (held-name capture, array capture, `_e_scan`, `bearer_in_call`, wrapper-site `bearer_ctx`); keep `E_APIKEY` semantics; update finding text and remedy line.
- 1.2 (Deferred to S2: `-u` / `--user` detection, added with the `betterstack-query.sh` conversion.)
- 1.3 Add `rule_e_files()` with two feeders: PyYAML `run:` extractor for `.github/**` (skip non-bash `shell:`; report step name and best-effort line; an unparseable file exits 2; import `yaml` lazily) and a raw-line feeder for `cloud-init-*.yml` only. Rules A to D and `--changed` stay `*.sh`-only. Verify each `git ls-files` pathspec matches at least one real file.
- 1.4 Fix the known miss: array-held `Authorization: Bot` in `discord-setup.sh` must be flagged (RED row first).
- 1.5 Re-time the repo-wide lint run after the arm lands (about 7 s before) and record it; confirm `import yaml` works in the runner that executes `scripts/lint-shell-trace-credential-refusal-repo`.
- 1.6 Update the lint docstring's Rule E block (members, YAML scope and the two feeders, vocabulary, `--changed` decision and reason, blind spots).

## Phase 2: Community scripts (shipped by the plugin release on merge)

- 2.1 `discord-community.sh` (line about 220) and `discord-setup.sh` (`curl_args` array, line about 74): Bot token through `--config -` with a process substitution, `--disable --noproxy '*'` first; reuse `discord-community.sh`'s existing token-shape check as the guard and add the same check on `DISCORD_BOT_TOKEN_INPUT` in `discord-setup.sh`; a refusal prints `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=token_shape` (value-free) and exits 1, never through `report_transport_failure`; changelog line for the `--noproxy` behaviour change.
- 2.2 `discord-setup.sh`: add the xtrace-refusal preamble (neighbour form) and delete its line from `scripts/lint-shell-trace-credential-refusal.baseline.txt` (deletion only), so the explicit-path run is clean.
- 2.3 `bsky-setup.sh` (line about 268) and `bsky-community.sh` (line about 237): body written to a 0600 file created with `mktemp "${TMPDIR:-/tmp}/bsky-body.XXXXXXXX"`, sent with `--data-binary @file`; the password and handle reach `jq` through its environment as an inline assignment prefix (`jq -n '{identifier:$ENV.X, password:$ENV.Y}'`), never `jq --arg`, never `export`; one owning EXIT trap; not inside a `$(...)`; refusals exit non-zero (never 0 or 3) because `bsky-community.sh post` also runs hosted from `scripts/content-publisher.sh`. Add a `jq` shim row asserting no credential value on `jq`'s argv.
- 2.4 `plugins/soleur/skills/flag-bootstrap/SETUP.md`: five `Api-Key` examples to the stdin-config form; add a `git grep` row to the battery.
- 2.5 Seed `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` with measured counts (minus the converted community scripts). Rebase onto current `origin/main` first; regenerate with `--write-baseline-e` only on the rebased tree; never hand-edit the nic-guard line (PR #9632).

## Phase 3: review SKILL.md extraction and Sharp Edge

- 3.1 Re-measure `wc -c` of SKILL.md and locate the three migration/RLS bullets by bold lead ("Legal-disclosure prose hallucinated against the actual migration body", "Stale plan-time RLS-policy enumeration drift", "RLS-policy-expression edit breaks exact-string verify/ sentinels"); confirm the pinned anchors (`lifecycle-handoff-protocol`, `run only the suites targeting the files they were given`, `TEST_GROUP=affected bash scripts/test-all.sh`, `SOLEUR_SUBAGENT`) are outside them.
- 3.2 Create `plugins/soleur/skills/review/references/defect-classes-migrations.md` (header line in the `wfs.md` style stating the load condition) with the three bullets verbatim; prove byte identity (`wc -c` and a diff).
- 3.3 In SKILL.md replace the three bullets with one markdown-link bullet `[migration and RLS classes](./references/defect-classes-migrations.md)` beside the `wfs.md` link; never a backtick path.
- 3.4 Add the stall Sharp Edge (last block a `tool_use` means not delivered; read last assistant text with `jq`, never `Read` or `tail` the JSONL; then `SendMessage` "make no further tool calls, reply now with the report"; evidence PR #9654) next to the existing "Parallel review batches can stall silently" bullet.
- 3.5 Record the byte delta (expected headroom about 3 KB); do not touch the `description:` frontmatter or `skill-body-budget.json`.
- 3.6 Run `lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"`, `bun test plugins/soleur/test/components.test.ts`, `bash plugins/soleur/test/fanout-suite-scope.test.sh`, `bun test plugins/soleur/test/workflow-fidelity.test.ts`.

## Phase 4: Verification (committed tree)

- 4.1 Run every item of plan Phase 4 (items 0 to 13), including the gates' own `--changed --base origin/main` invocations and `npx markdownlint-cli2` over the plan and this file.
- 4.2 Confirm `git diff --name-only "$(git merge-base HEAD origin/main)"..HEAD` has no `apps/web-platform/infra/` path, no `apply-web-platform-infra.yml`, no `destroy-guard-filter-web-platform.jq`.

## Phase 5: PR

- 5.1 PR body first line states that merging fires the web-platform release (plugins/soleur edits) and no infra apply; then `Ref #9597`, `Ref #7797`, slice table, review coverage, #9632 sequencing note.

## Phase 6: Tracking

- 6.1 Verify labels exist (`gh label list --limit 200`), then file four slice issues (S2 ops and runner scripts with `Closes #8767` in its eventual PR; S3 workflow YAML without production effect plus the shared helper; S4 push-triggered production-class files; S5 apply workflow and cloud-init-registry, last) with milestones and `--add-blocked-by` edges (S4 after S3 helper; S5 after S3 and S4).
- 6.2 Restate the #9597 body (slice table, corrected measurements); comment on #7797, #7898 and #8767; leave all open.

## Out of scope (parent session, ops follow-ups)

- Why the push-triggered infra apply did not fire after the Tier 2 merge (operator-gated production apply).
- web-2 tracking: replaced 2026-10-06 19:28Z from main at `2efc8025ff`, before the Tier 2 merge; re-check at its next replacement.
