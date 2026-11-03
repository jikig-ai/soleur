# Tasks: launch-check PR-B (severity-ranked epic with sub-issues)

Plan: `knowledge-base/project/plans/2026-11-03-feat-launch-check-severity-ranked-epic-sub-issues-plan.md`
Branch: `feat-one-shot-launch-check-pr-b-epic-issues` · Draft PR #11949 · Tracking issue #11910 (Refs, never Closes) · Live-check follow-up #11956
Lane: cross-domain (parent spec lane carried; this branch has no spec.md, so fail-closed default applies)

## Phase 0 — Failing tests and fixtures first (RED)

- [x] 0.1 Write `plugins/soleur/skills/launch-check/test/gh-stub.sh`: stateful fake `gh` with a stub-contract header (verified vs `UNVERIFIED-STUB-ONLY` shapes), a transport-error interruption mode, no basename of any real `gh` pipe producer named; real-flag whitelist, unknown flag exits 64; real `gh: ... (HTTP nnn)` stderr lines; records inside the matched dispatch branch only; read-without-`-X GET` logged as a violation; failure injection env (`GH_STUB_AUTH`, `FAIL_AFTER`, `KILL_AFTER_CREATE`, `SUBISSUE`, `PER_PAGE`, `EDIT_EPIC_BETWEEN`, `CRLF`)
- [x] 0.2 Write `test/issues.test.sh` (sources `lib.sh` unchanged): Test Scenarios, recorder canary, instrument self-test, exact assertion floor, small sandbox-copy mutation battery
- [x] 0.3 Commit `test/fixtures/plan-sample/` (`plan.tsv`, `epic.md`, `issues/CI-01.md`), synthesized
- [x] 0.4 Extend `test/wording.test.sh` (lint `issues.sh` and the template; no sentence-length prose literal; no `${...//...}` in `issues.sh` only) and add the autolink-shape lint over `checks.tsv`, `phrases.txt`, `issue-body.template` and rendered bodies
- [x] 0.5 Capture `render --dry-run` output for `fx_minimal`, `fx_healthy`, `fx_python` as the before-image for Phase 1

## Phase 1 — Refactors

- [x] 1.1 `common.sh`: `lc_is_headless`; `launch-check.sh` `is_headless()` delegates
- [x] 1.2 `render.sh`: add `lc_prepare_inputs` (catalog, `lc_clean_facts`, `lc_validate_judged`) used by `cmd_render` and `cmd_issues`
- [x] 1.3 `render.sh`: extract `lc_compute_gaps`; hand `prev`, `has_prev`, `judged_in`, `gaps.tsv`, `open.ids`, `accepted.ids` back to `lc_render`; bash 3.2 safe
- [x] 1.4 Diff the three fixtures' dry-run output against the before-image (byte-identical); run `render`, `identity`, `wording` suites

## Phase 2 — `issues.sh`: wrappers, preflight, live lookup, preview

- [x] 2.1 `lc__gh_exec` (stderr capture, `HTTP nnn` parse, rate-limit text first), `lc_gh_read` (inject `-X GET`), `lc_gh_write` (headless, dry-run, 4 shapes, field-key allowlist, `@file` realpath confinement, 1 s pause with a test seam)
- [x] 2.2 `lc_issues_preflight` (cd to target; gh present/auth; `gh repo view` slug + fork flag; REST repo read; report-only reasons)
- [x] 2.3 `lc_issues_live` (paginated REST listing; anchored `scan`; PR rows dropped; values used as set keys only)
- [x] 2.4 `references/issue-body.template`, `references/phrases.txt` additions; awk splice via `ENVIRON`/`index()`/`substr()`
- [x] 2.5 `lc_issues_preview` (report required, report/catalog hash, partition create/exists/closed/accepted/excluded/capped, cap 30 per run, excludes, plan directory mode 700, blob scan, summary lines, `SOLEUR_LAUNCH_CHECK_ISSUES_PLAN`)

## Phase 3 — `--create`

- [x] 3.1 Plan trust chain: `--confirm-repo`/`--confirm-count`; lstat owner/mode/symlink checks; `cp -R` into `$WORK`; closed-vocabulary validation; regenerate every body from catalog+facts+ids and `cmp` (`--create` takes `--target --facts --judged --plan`); repo binding; `--check-plan` stop; `plan-missing`
- [x] 3.2 Live visibility gate (PUBLIC, UNKNOWN, internal need `--confirm-public`); resolved slug vs `origin` (`--repo`); github.com-only host (`--host`); `gh` environment scrub and neutral cwd; report-hash and "create rows still open" re-check
- [x] 3.3 Scan the blob of exactly the sent bytes before the first write (the per-file rescan was dropped as redundant: a gitleaks run costs about 0.7 s)
- [x] 3.4 Re-list live (a failed or malformed listing aborts `issues-incomplete phase=lookup`); epic handling (`epic-closed`, `epic-ambiguous`, epic author check, second re-list after epic creation); absent labels only (422 `already_exists` is success)
- [x] 3.5 Item loop in severity order: REST create, link with `-F sub_issue_id`, whole-run task-list latch on first failed link, stop at first failed write, orphan re-link
- [x] 3.6 Epic section: GET just before splice, `lc_epic_splice` (CRLF tolerant, damaged markers stop the edit), section scan in a subshell, PATCH only if changed
- [x] 3.7 Summary marker `SOLEUR_LAUNCH_CHECK_ISSUES` with `plan=` and `phase=`, failed ids, rate-limit hint, resume command, `created.tsv`, `issues-incomplete`, exit codes; closed `detail=` tokens, no raw `gh` stderr printed

## Phase 4 — CLI wiring

- [x] 4.1 `cmd_issues` flags; abort-reason to exit-code table in the `launch-check.sh` header; headless/`--plan` refusals before `need_repo`; `--check-plan` before scanner preflight; no `echo "SOLEUR_..."` in `launch-check.sh`

## Phase 5 — Docs and architecture

- [x] 5.1 `SKILL.md`: replace "Planned" and the no-`gh` rule; preview/ask/create flow, decline path, lost-session recovery, public and fork questions, abort reasons; no `description:` edit
- [x] 5.2 ADR-314 dated amendment (decisions 6 and 7, Art. 28(3) posture note, markers unmirrored, one alternatives row); status stays `adopting`
- [x] 5.3 `model.c4`: second `plugin -> github` edge (customer's own `gh` token), rewrite `launchcheck` description; `bash scripts/regenerate-c4-model.sh`
- [x] 5.3b Comment-only block in `apps/web-platform/server/git-lock-marker-telemetry.ts` (unmirrored `ISSUES` markers, hosted run dark); `redact-gate.sh` runs its scans from the scratch directory (+ `.gitleaksignore` test; DONE with Phases 2-4, only the comment-only TS block remains)
- [x] 5.3c `SKILL.md` Undo paragraph; decline deletes the plan directory
- [x] 5.4 Suite assertion: no `skills/*/scripts/*.sh` emits `SOLEUR_LAUNCH_CHECK_ISSUES*` or `_PLAN_OK`

## Phase 6 — Ratchets and registry rows

- [x] 6.1 `components.test.ts` (no budget edit), `lint-skill-body-budget.py`
- 6.2 Accept rows via `ci-pr-affected-replay.py audit --all-refs`; re-run `ratchet`
- [x] 6.3 `.claude/hooks/grep-q-pipe-guard.test.sh` recount (`PJ_TRIPLES` 316)
- [x] 6.4 Telemetry drift test (`git-lock-marker-telemetry.test.ts`) unchanged and green
- [x] 6.5 `regenerate-shard-manifest.py --incremental --write`, then the measured duration row (suite split into `issues-guards` 95 s and `issues-resume` 211 s; `issues-common.sh` holds the shared harness)
- [x] 6.6 `fixture-relative-assert.test.sh --write-baseline`, then the plain check
- [x] 6.7 C4 set: `c4-code-syntax`, `c4-render`, `c4-count-parity`, `c4-model-freshness`
- [x] 6.8 `lint-orphan-test-suites.sh`, `lint-guard-contract.py` on the plan

## Phase 7 — Review and ship

- 7.1 Re-run the open code-review overlap filter; re-run `gdpr-gate` on the diff
- 7.2 `soleur:review` full panel (user-impact, observability-coverage included); fix round
- 7.3 PR body: `Refs #11910`, `## Changelog`, GDPR advisory, "live endpoint check: stub-only, tracked in #11956"; re-title draft PR #11949
- 7.4 CI is the full-suite gate; no run against any customer repo; content-strategy held row untouched
