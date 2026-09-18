# Tasks: revive the #7490 follow-through, qualify the `claude plugin update` docs, route the comparator residual upstream

Plan: `knowledge-base/project/plans/2026-09-18-fix-7490-followthrough-revive-and-plugin-update-form-plan.md`
Closes: #7490 · semver:patch · lane: cross-domain (no spec.md — fail-closed default)

## Phase 0: Preconditions (measure, do not assume)

- [ ] 0.1 Record `claude --version`, `claude plugin update --help | head -3`, `claude plugin marketplace update --help | head -3` for the PR body (CLI-verification gate)
- [ ] 0.2 `bash scripts/marketplace-manifest-validate.sh` — the standing assertion that the published manifest's `.name` is `soleur-marketplace` (no network dependency in the PR record)
- [ ] 0.3 Re-census fenced-only open `follow-through` trackers; confirm the set is still {7490, 7985, 6678, 6617, 6488, 5813}
- [ ] 0.4 Baseline green: `bash scripts/lint-followthrough-varq-ban.sh`, `bash scripts/sweep-followthroughs.test.sh`
- [ ] 0.5 Run the committed rule-3 regex once; set `MIN_REF_FILES` and `MIN_REFS` from THAT reading (three plan-time reconstructions gave 32, 24 and 46 — the regex is the artefact, not the number)
- [ ] 0.7 awk dialect reading: run the fence predicate under the runner's awk (mawk) against a 3-space-indented fence fixture; paste into the PR body
- [ ] 0.8 Capture the `guard-vacuity-floor.test.sh` derived-population baseline for AC9b
- [ ] 0.6 Census directive-less-but-fenced trackers (plan-time: 19) — the false-positive blast radius Guard 2 must keep at zero

## Phase 1: Stream A — docs (RED → GREEN)

- [ ] 1.1 RED: rewrite the sync-remedy assertions in `tests/commands/test-sync-producer-reachability.sh` to pin every command `sync.md` emits; run — must fail
- [ ] 1.2 GREEN: edit `plugins/soleur/commands/sync.md` to the generic runtime form (`claude plugin update soleur@<marketplace>` + `claude plugin list`); re-run — green
- [ ] 1.3 Edit `README.md` §Updating (both commands qualified, `soleur-marketplace`; one sentence for the direct-repository path)
- [ ] 1.4 Edit `plugins/soleur/README.md` §Known Issues marketplace-update section (same)
- [ ] 1.5 Edit `plugins/soleur/docs/pages/getting-started.njk` "Updating later?" callout (copy only — no structural tags added)
- [ ] 1.6 Edit `plugins/soleur/docs/pages/claude-code-plugins.njk` FAQ prose + JSON-LD `text` (keep both byte-identical)
- [ ] 1.7 Edit the three published blog posts (`2026-03-16-…`, `2026-03-17-…`, `2026-04-30-…`)
- [ ] 1.8 Edit `knowledge-base/project/README.md` and `ADR-178-shared-bash-primitives-ship-in-plugin.md` (one line each)
- [ ] 1.9 Edit the 14 echo lines across 10 SKILL.md files to the generic runtime form (literal strings; no `$VAR`)
- [ ] 1.10 Verify AC1, AC2, AC3, AC5; run the docs build and verify AC6

## Phase 2: Guard 1 — probe repo-path existence as rule 3 of the EXISTING lint (RED → GREEN)

- [ ] 2.1 Add every Guard 1 row as a named assertion to `scripts/lint-followthrough-varq-ban.test.sh`; they must fail (rule 3 absent)
- [ ] 2.2 Write rule 3 inside `scripts/lint-followthrough-varq-ban.sh` — literal regex with all six arms (bare `$VAR/`, braced, both `:-` forms, literal, `source`), `git ls-files` existence base, own counters and two floors, `REPO_PATHS_MIN_REFS` test-only override, per-LINE `# repo-path: runtime`, blind spots + shared-exit-code note in the header
- [ ] 2.3 Confirm the live tree is RED on the untouched `plugin-delivery-canary-7490.sh`
- [ ] 2.4 Repoint `REPORTS=` to the archive path AND annotate `inngest-cutover-flip-rollout-7761.sh`'s `AFTER_FILE` line — the tree's two misses, different in kind; live tree GREEN (AC7)
- [ ] 2.5 No new registration: rule 3 rides the existing suites in `scripts/test-all.sh`. Raise `MIN_ASSERTIONS` from 34
- [ ] 2.6 Run the repointed probe under the `env -i` form and record rc + last line (AC8)
- [ ] 2.7 `bash scripts/guard-vacuity-floor.test.sh` — compare against the Phase 0 baseline (AC9b)

## Phase 3: Guard 2 — sweeper LOUD fenced verdict (RED → GREEN)

- [ ] 3.1 Add a named test for EVERY Guard 2 row (1–21); build `mutate_sut` with placement assertions; add the missing harness capability (per-issue comments fixtures, `GITHUB_STEP_SUMMARY` export + assertions, 200-issue generator); run — RED
- [ ] 3.2 Edit `parse_directive`: dialect-safe `^[ ]?[ ]?[ ]?(```|~~~)` predicate with fence-length tracking, `fenced_seen` on a COLUMN-0 opener inside a fence, `END` emits `fenced_directive_count` and the unbalanced flag
- [ ] 3.3 Edit `run_one`: meta arm, loud branch gated on open mode, `FENCED_DIRECTIVE=1`, counted `::error::`, DRY_RUN short-circuit, comment-post failure arm, mode-gated `FENCED_FILE` with the `NO_DIRECTIVE_FILE` append moved into the non-fenced arm. No dedup readback (cut)
- [ ] 3.4 Edit `main`: collect all three run-level flags, print every annotation, then one `exit 1`
- [ ] 3.5 GREEN; re-run the G3 suite to confirm `MISSING_SECRET` is unchanged; raise `MIN_ASSERTIONS` from 118 (AC10, AC11)

## Phase 4: Guard 3 — producers agree with the consumer

- [ ] 4.1 `ship-soak-followthrough-gate.test.sh` rows 1–8 with the probe file PRESENT in the fixture and an unfenced positive control (RED) → gate edit (GREEN); raise `MIN_ASSERTIONS` from 19
- [ ] 4.2 Mirror the same strip into the ship SKILL.md enrollment-gate bash
- [ ] 4.3 `follow-through-directive-gate.test.sh`: add the ADR-193 accounting identity + a measured `MIN_ASSERTIONS` FIRST (it has neither), then the fenced row and the no-directive control (RED) → hook edit (GREEN)
- [ ] 4.4 Remove the ```` ```html ```` fence from the ship follow-through issue-body template; add the "unfenced, column 0" note (AC12)
- [ ] 4.5 `followthrough-convention.md`: unfenced sentence in §Author workflow step 4 + a Placement row in `## Directive fields` (AC12)
- [ ] 4.6 Run AC13

## Phase 4.5: Repair the two broken sibling probes before enrolling them

- [ ] 4.5.1 `inngest-doublefire-reading-6617.sh`: drop `--comments`, KEEP `--json`/`--jq` (dropping `--json` instead removes the author filter); measure before/after (rc 2 → rc 0 PASS); header note on the RESULT:PASS republication loop (AC21b)
- [ ] 4.5.2 `gh-pages-cert-reissue-6657.sh`: null/absent `https_certificate.state` gets its own arm at exit **3** (CANNOT ESTABLISH), not 2; record the measured API response in the header

## Phase 5: Unfence the six bodies (live mutation, measured first)

- [ ] 5.1 For each of 7985, 6678, 6617, 6488, 5813, 7490: run the probe under `env -i` and record rc + last line
- [ ] 5.2 Edit each body: remove only the two fence lines; add `secrets=GH_TOKEN` where the probe calls `gh` and the clause is absent (#7490, #7985, #6617, #5813); bump #7490's `earliest` to `2026-09-21T00:00:00Z`
- [ ] 5.3 `diff` each body before/after — no other line may change — then `gh issue edit N --body-file`
- [ ] 5.4 Verify AC14 and AC14b on the live bodies
- [ ] 5.5 Post the AC16 comment on #7985: measured FAIL (not NOT YET) semantics, plus the reopen behaviour and the un-enrol remedy
- [ ] 5.6 Record the `### Unfenced trackers` table for the PR body (AC15)
- [ ] 5.7 Dry run: `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`; read the log (AC17)

## Phase 6: Stream C — upstream

- [ ] 6.1 Scrub the POSTABLE SLICE `upstream-reports/93108-comment.md` (and the record as a second file) — AC18
- [ ] 6.2 Operator gate — interactive: present the composed body verbatim and ask for explicit approval before any post; headless: write `decision-challenges.md` in the 5-line informational frame (no `Operator`/`Post-merge`/`Follow-up` bullets) and leave the log `_pending_` (AC20)
- [ ] 6.3 If approved and posted: record the comment URL and the as-posted re-scrub result in the posting log (AC19)
- [ ] 6.4 Comment on #8253 recording the 4th upstream-ask recurrence (AC21)
- [ ] 6.5 File the tracking issue for the general per-verdict sweeper dedup and cite its number in the plan's Not-in-scope (AC26)

## Phase 7: Cross-cutting

- [ ] 7.1 `bash scripts/test-all.sh` full battery green (AC22)
- [ ] 7.2 Plan-path resolution check (AC23)
- [ ] 7.3 PR body: `Closes #7490`, `semver:patch`, diff-scope list, Phase 0 CLI output, `### Unfenced trackers` table (AC24)
