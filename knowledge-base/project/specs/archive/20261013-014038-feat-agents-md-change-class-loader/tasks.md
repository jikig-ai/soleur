# Tasks: change-class-aware AGENTS.md loader (#3493, v2)

> Derived from `knowledge-base/project/plans/2026-05-09-feat-agents-md-change-class-loader-plan.md` v2-post-plan-review.

## Phase 0: Pre-flight

- [ ] 0.1 Verify `gh issue view 3493 --json state` is OPEN; branch is `feat-agents-md-change-class-loader`; worktree path correct
- [ ] 0.2 Record CPO sign-off comment on PR #3496 explicitly acknowledging pivot-detector cut still meets `single-user incident` threshold via fail-closed default + stamp + operator-side `LOADER_FAIL_CLOSED=1`
- [ ] 0.3 Capture baseline `wc -c AGENTS.md` (currently 24,618) in PR description

## Phase 1: Tag, classify, and measure

- [ ] 1.1 Verify `[compliance-tier]` token doesn't already exist (`grep '\[compliance-tier\]' AGENTS*.md` returns 0 lines)
- [ ] 1.2 Find current line numbers via `grep -n '\[id: <slug>\]' AGENTS.md` for each of:
  - [ ] 1.2.1 `hr-never-paste-secrets-via-bang-prefix`
  - [ ] 1.2.2 `hr-menu-option-ack-not-prod-write-auth`
  - [ ] 1.2.3 `hr-never-git-add-a-in-user-repo-agents`
  - [ ] 1.2.4 `cq-pg-security-definer-search-path-pin-pg-temp`
  - [ ] 1.2.5 `hr-exhaust-all-automated-options-before`
- [ ] 1.3 Add `[compliance-tier]` tag (presence-only, no value) to each of the 5 rules above
- [ ] 1.4 Verify globs match real files per `hr-when-a-plan-specifies-relative-paths-e-g`:
  - [ ] 1.4.1 `git ls-files | grep -E '\.tf$' | head -3` returns ≥1
  - [ ] 1.4.2 `git ls-files | grep -E '^apps/[^/]+/infra/' | head -3` returns ≥1
  - [ ] 1.4.3 `git ls-files | grep -E '\.github/workflows/' | head -3` returns ≥1
- [ ] 1.5 Implement `tools/migration/classify-rules.sh` (embedded heuristics + 5-PR spot-check)
- [ ] 1.6 Run script; write `tools/migration/rule-classification.tsv` for reviewer audit
- [ ] 1.7 Self-consistency gate:
  - [ ] 1.7.1 Verify `sum(core_bytes) ≤ 18000`
  - [ ] 1.7.2 Verify `sum(docs_bytes) + sum(rest_bytes) ≤ 12000`
  - [ ] 1.7.3 Verify `sum(all_bytes) ∈ [22000, 28000]` (within 5% of 24,618)
  - [ ] 1.7.4 If `core > 18k`, demote `wg-when-a-test-runner-crashes-segfault-oom` and `wg-when-tests-fail-and-are-confirmed-pre` to `rest`
- [ ] 1.8 Embed per-class byte sums + 5-PR spot-check savings table in PR #3496 description

## Phase 2: Sidecar split + index rewrite

- [ ] 2.1 Run baseline plugin-loader test: `bun test plugins/soleur/test/components.test.ts` (must pass)
- [ ] 2.2 Create `AGENTS.core.md` with section headings `## Hard Rules`, `## Workflow Gates`, `## Compliance Tier`, `## Passive Domain Routing`, `## Communication`. Copy bodies from current `AGENTS.md`.
- [ ] 2.3 Create `AGENTS.docs.md` (eleventy + agents-md-meta rules)
- [ ] 2.4 Create `AGENTS.rest.md` (CQ runtime + Postgres + Review & Feedback)
- [ ] 2.5 Duplicate cross-cutting rule bodies (only if needed; budget: ≤500 bytes total duplication)
- [ ] 2.6 Rewrite `AGENTS.md` as thin pointer index:
  - [ ] 2.6.1 Each rule one line: `- <summary> [id: <slug>] [<enforcement-tag>] → AGENTS.<class>.md`
  - [ ] 2.6.2 Pointer ≤ 200 bytes per line
  - [ ] 2.6.3 Section headings preserved verbatim
  - [ ] 2.6.4 Top-of-file paragraph rewrite (≤ 500 bytes) explaining sidecar architecture
- [ ] 2.7 Re-run plugin-loader test: `bun test plugins/soleur/test/components.test.ts` (must still pass)
- [ ] 2.8 Verify `wc -c AGENTS.md ≤ 5000`

## Phase 3: Linter migration (TDD — tests first)

- [ ] 3.1 Locate or create `scripts/lint-rule-ids.test.sh` (run `find . -name 'lint-rule-ids.test.*'` first)
- [ ] 3.2 Write failing tests BEFORE editing the linter:
  - [ ] 3.2.1 Pointer in index without matching body → fail
  - [ ] 3.2.2 Body in sidecar without pointer in index → fail
  - [ ] 3.2.3 Removed-id false-positive: HEAD has rule in `AGENTS.md`, working copy moved to `AGENTS.core.md` → pass (no error)
  - [ ] 3.2.4 Legacy single-file mode: `python3 scripts/lint-rule-ids.py AGENTS.md` (no `--index-file`) still works
- [ ] 3.3 Implement linter changes:
  - [ ] 3.3.1 Add `--index-file <path>` argparse flag with realpath dedup against positional args
  - [ ] 3.3.2 Add `Compliance Tier` to `SECTIONS` set
  - [ ] 3.3.3 Refactor to `lint_union(paths, index_path, retired_ids)` with global ID set
  - [ ] 3.3.4 Pointer↔body 1:1 validation
  - [ ] 3.3.5 Removed-id diff aware of sibling sidecars
- [ ] 3.4 Run tests; iterate until all pass
- [ ] 3.5 Update `lefthook.yml`:
  - [ ] 3.5.1 Extend `glob:` array to include `AGENTS.*.md`
  - [ ] 3.5.2 Update command to pass `--index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md`
- [ ] 3.6 Verify lefthook fires on sidecar edit: modify a sidecar rule body, attempt commit, confirm linter runs

## Phase 4: SessionStart hook (TDD — tests first)

- [ ] 4.1 Write failing tests at `.claude/hooks/session-rules-loader.test.sh`:
  - [ ] 4.1.1 Classifier: pure-docs diff → `core docs-only`
  - [ ] 4.1.2 Classifier: pure-code diff → `core rest`
  - [ ] 4.1.3 Classifier: pure-infra diff → `core rest`
  - [ ] 4.1.4 Classifier: mixed/empty diff → `core docs-only rest` (fail-closed)
  - [ ] 4.1.5 Idempotency: 3 successive invocations with identical input produce identical `rule_ids_loaded` arrays in 3 manifest files
  - [ ] 4.1.6 Bare-repo path resolution: invoke with `cwd` field set + `git rev-parse --show-toplevel` failing → classifier still works (Kieran P0-1)
  - [ ] 4.1.7 Manifest schema: assert exactly 3 fields `{timestamp, change_class, rule_ids_loaded}`
  - [ ] 4.1.8 Fail-closed: if a sidecar file is missing → classifier loads all sidecars + sets class to `(fail-safe: sidecar missing)`
- [ ] 4.2 Implement `.claude/hooks/session-rules-loader.sh`:
  - [ ] 4.2.1 Worktree-aware path resolution: prefer envelope `cwd`, fall back to `git rev-parse --git-common-dir`, last-resort `pwd`
  - [ ] 4.2.2 Compute change set: `git diff --name-only origin/main...HEAD ∪ git status --porcelain` (with `--ignore-submodules=all`)
  - [ ] 4.2.3 Inline classifier regex (no shared library): `DOCS_RE`, `CODE_RE`, `INFRA_RE`
  - [ ] 4.2.4 Multi-class match → `mixed` → load all sidecars
  - [ ] 4.2.5 `LOADER_FAIL_CLOSED=1` env var override → load all sidecars
  - [ ] 4.2.6 Concatenate sidecar files with `---` separators
  - [ ] 4.2.7 Compose stamp: `[rules-loader] loaded: <classes> (N of M rules)`
  - [ ] 4.2.8 Compose hint line: `[rules-loader] If scope shifts mid-session, run: LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(echo '{"cwd":"<path>"}')`
  - [ ] 4.2.9 Inline 3-line jq manifest write to `.claude/.session-manifests/${session_id|timestamp}.json`
  - [ ] 4.2.10 Output `hookSpecificOutput.additionalContext` with stamp + hint + manifest path + content
  - [ ] 4.2.11 Make script executable (`chmod +x`)
- [ ] 4.3 Run tests; iterate until all pass
- [ ] 4.4 Register in `.claude/settings.json`:
  - [ ] 4.4.1 Add `SessionStart` key with matchers `startup|resume|clear|compact`
  - [ ] 4.4.2 Hook command: `"$CLAUDE_PROJECT_DIR"/.claude/hooks/session-rules-loader.sh`
- [ ] 4.5 Add `.claude/.session-manifests/` to `.gitignore`
- [ ] 4.6 Verify shellcheck-clean (or document any issues with rationale)
- [ ] 4.7 Stamp ≤ 200 bytes per line — assert in test 4.1.5 or separate test

## Phase 5: Compound bytes-cap migration (config-only — TDD-exempt)

- [ ] 5.1 Edit `plugins/soleur/skills/compound/SKILL.md` step 8 (lines 196-216):
  - [ ] 5.1.1 Replace `B = wc -c < AGENTS.md` with `B_INDEX`, `B_CORE`, `B_ALWAYS = B_INDEX + B_CORE`, `B_TOTAL`
  - [ ] 5.1.2 Fix shellcheck bug: `grep -h '^- ' AGENTS*.md | wc -l` (not `grep -h -c`)
  - [ ] 5.1.3 Update output lines to show `index`, `core`, `always-loaded total`, `registry total`, `constitution.md`
  - [ ] 5.1.4 Reframe thresholds to apply to `B_ALWAYS`: 18k warn, 22k critical
  - [ ] 5.1.5 Demote `B_TOTAL` thresholds to informational only
- [ ] 5.2 Update body of `cq-agents-md-why-single-line` rule (in `AGENTS.core.md`) to reference new architecture and thresholds

## Phase 6: Tests, docs, and validation

- [ ] 6.1 Confirm all `.test.sh` files added are picked up by `bash scripts/test-all.sh`
- [ ] 6.2 Run `bash scripts/test-all.sh` end-to-end; confirm all suites pass
- [ ] 6.3 Update `.claude/hooks/README.md`:
  - [ ] 6.3.1 Add Change-class loader section
  - [ ] 6.3.2 Document operator commands (view manifest, force re-load)
  - [ ] 6.3.3 Document default class rule (empty/multi-class → mixed)
- [ ] 6.4 Update `plugins/soleur/AGENTS.md` directory-structure section to note sidecar files at repo root are not plugin components
- [ ] 6.5 Re-run measurement spot-check from `tools/migration/classify-rules.sh` against shipped loader; confirm Phase 1.8 baseline holds (±5%)
- [ ] 6.6 Compaction re-entrancy live test: trigger 3 `/compact` events in this PR's review session; compare 3 manifest files' `rule_ids_loaded` arrays for identical sets
- [ ] 6.7 Add learning at `knowledge-base/project/learnings/<implementation-date>-agents-md-change-class-loader-measured-savings.md` (filename derived at write-time per AGENTS.md sharp edge):
  - [ ] 6.7.1 Per-class measured savings vs Phase 1 baseline
  - [ ] 6.7.2 Classifier accuracy on 5-PR spot-check
  - [ ] 6.7.3 Edge cases hit during implementation
  - [ ] 6.7.4 Telemetry blind-spot acknowledgment
  - [ ] 6.7.5 Pivot-detector-cut rationale + observed mid-session pivot frequency in this PR's own sessions
- [ ] 6.8 Update PR #3496 description final:
  - [ ] 6.8.1 Measured savings table (replacing any estimate)
  - [ ] 6.8.2 Manifest reference `<details>` block
  - [ ] 6.8.3 CPO sign-off comment recorded
  - [ ] 6.8.4 `Closes #3493` on its own body line
  - [ ] 6.8.5 Semver label `semver:minor`

## Phase 7: Multi-agent review + ship

- [ ] 7.1 Run `/soleur:review` (multi-agent: must include `user-impact-reviewer` per `requires_cpo_signoff: true`)
- [ ] 7.2 Resolve all P0 / P1 review findings inline per `rf-review-finding-default-fix-inline`
- [ ] 7.3 Run `/soleur:ship` to prepare for production:
  - [ ] 7.3.1 Phase 5.5 conditional gates (CMO/COO if triggered)
  - [ ] 7.3.2 Preflight Check 6 (User-Brand Impact section validation)
- [ ] 7.4 Mark PR ready, queue auto-merge: `gh pr merge 3496 --squash --auto`
- [ ] 7.5 Poll until merged: `gh pr view 3496 --json state --jq .state` until `MERGED`
- [ ] 7.6 Run `cleanup-merged` on the worktree

## Phase 8: Post-merge verification

- [ ] 8.1 Verify SessionStart hook fires in next fresh session: `ls -la .claude/.session-manifests/` shows new manifest within 30 seconds
- [ ] 8.2 Verify stamp visible in next session's console output (look for `[rules-loader] loaded:`)
- [ ] 8.3 Verify operator escape hatch: `LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(echo '{"cwd":"'"$PWD"'"}')` produces a manifest with `change_class` containing all classes
- [ ] 8.4 `gh issue view 3493 --json state` shows CLOSED
- [ ] 8.5 `gh issue view 3493 --json milestone` shows `Phase 4: Validate + Scale`
- [ ] 8.6 Update roadmap.md `Current State` Phase 4 row per `wg-when-moving-github-issues-between` (open count -1, count adjustment)
- [ ] 8.7 Verify lefthook still triggers linter on commits — modify any `AGENTS*.md` file, attempt commit, confirm linter fires
- [ ] 8.8 Verify release/deploy workflows succeed (per `wg-after-a-pr-merges-to-main-verify-all`)
