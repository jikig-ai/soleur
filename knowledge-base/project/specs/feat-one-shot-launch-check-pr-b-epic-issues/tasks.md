# Tasks: launch-check PR-B (severity-ranked epic with sub-issues)

Plan: `knowledge-base/project/plans/2026-11-03-feat-launch-check-severity-ranked-epic-sub-issues-plan.md`
Branch: `feat-one-shot-launch-check-pr-b-epic-issues` · Draft PR #11949 · Tracking issue #11910 (Refs, never Closes) · Live-check follow-up #11956
Lane: cross-domain (parent spec lane carried; this branch has no spec.md, so fail-closed default applies)

## Phase 0 — Failing tests and fixtures first (RED)

- 0.1 Write `plugins/soleur/skills/launch-check/test/gh-stub.sh`: stateful fake `gh`; real-flag whitelist, unknown flag exits 64; real `gh: ... (HTTP nnn)` stderr lines; records inside the matched dispatch branch only; read-without-`-X GET` logged as a violation; failure injection env (`GH_STUB_AUTH`, `FAIL_AFTER`, `KILL_AFTER_CREATE`, `SUBISSUE`, `PER_PAGE`, `EDIT_EPIC_BETWEEN`, `CRLF`)
- 0.2 Write `test/issues.test.sh` (sources `lib.sh` unchanged): Test Scenarios, recorder canary, instrument self-test, exact assertion floor, small sandbox-copy mutation battery
- 0.3 Commit `test/fixtures/plan-sample/` (`plan.tsv`, `epic.md`, `issues/CI-01.md`), synthesized
- 0.4 Extend `test/wording.test.sh` (lint `issues.sh` and the template; no sentence-length prose literal; no `${...//...}` in `issues.sh`)
- 0.5 Capture `render --dry-run` output for `fx_minimal`, `fx_healthy`, `fx_python` as the before-image for Phase 1

## Phase 1 — Refactors

- 1.1 `common.sh`: `lc_is_headless`; `launch-check.sh` `is_headless()` delegates
- 1.2 `render.sh`: add `lc_prepare_inputs` (catalog, `lc_clean_facts`, `lc_validate_judged`) used by `cmd_render` and `cmd_issues`
- 1.3 `render.sh`: extract `lc_compute_gaps`; hand `prev`, `has_prev`, `judged_in`, `gaps.tsv`, `open.ids`, `accepted.ids` back to `lc_render`; bash 3.2 safe
- 1.4 Diff the three fixtures' dry-run output against the before-image (byte-identical); run `render`, `identity`, `wording` suites

## Phase 2 — `issues.sh`: wrappers, preflight, live lookup, preview

- 2.1 `lc__gh_exec` (stderr capture, `HTTP nnn` parse, rate-limit text first), `lc_gh_read` (inject `-X GET`), `lc_gh_write` (headless, dry-run, 4 shapes, field-key allowlist, `@file` realpath confinement, 1 s pause with a test seam)
- 2.2 `lc_issues_preflight` (cd to target; gh present/auth; `gh repo view` slug + fork flag; REST repo read; report-only reasons)
- 2.3 `lc_issues_live` (paginated REST listing; anchored `scan`; PR rows dropped; values used as set keys only)
- 2.4 `references/issue-body.template`, `references/phrases.txt` additions; awk splice via `ENVIRON`/`index()`/`substr()`
- 2.5 `lc_issues_preview` (report required, report/catalog hash, partition create/exists/closed/accepted/excluded/capped, cap 30 per run, excludes, plan directory mode 700, blob scan, summary lines, `SOLEUR_LAUNCH_CHECK_ISSUES_PLAN`)

## Phase 3 — `--create`

- 3.1 Plan validation in place (closed vocabularies, symlink/size/file-set checks, one own marker per body, repo binding, `--check-plan` stop, `plan-missing`)
- 3.2 Live visibility gate with `--confirm-public`; report-hash and "create rows still open" re-check
- 3.3 Scan blob and each sent file before the first write
- 3.4 Re-list live; epic handling (`epic-closed`, `epic-ambiguous`, second re-list after epic creation); absent labels only (422 `already_exists` is success)
- 3.5 Item loop in severity order: REST create, link with `-F sub_issue_id`, whole-run task-list latch on first failed link, stop at first failed write, orphan re-link
- 3.6 Epic section: GET just before splice, `lc_epic_splice` (CRLF tolerant, damaged markers stop the edit), section scan in a subshell, PATCH only if changed
- 3.7 Summary marker `SOLEUR_LAUNCH_CHECK_ISSUES`, failed ids, rate-limit hint, `issues-incomplete`, exit codes

## Phase 4 — CLI wiring

- 4.1 `cmd_issues` flags; abort-reason to exit-code table in the `launch-check.sh` header; headless/`--plan` refusals before `need_repo`; `--check-plan` before scanner preflight; no `echo "SOLEUR_..."` in `launch-check.sh`

## Phase 5 — Docs and architecture

- 5.1 `SKILL.md`: replace "Planned" and the no-`gh` rule; preview/ask/create flow, decline path, lost-session recovery, public and fork questions, abort reasons; no `description:` edit
- 5.2 ADR-314 dated amendment (decisions 6 and 7, Art. 28(3) posture note, markers unmirrored, one alternatives row); status stays `adopting`
- 5.3 `model.c4`: second `plugin -> github` edge (customer's own `gh` token), rewrite `launchcheck` description; `bash scripts/regenerate-c4-model.sh`
- 5.4 Suite assertion: no `skills/*/scripts/*.sh` emits `SOLEUR_LAUNCH_CHECK_ISSUES*` or `_PLAN_OK`

## Phase 6 — Ratchets and registry rows

- 6.1 `components.test.ts` (no budget edit), `lint-skill-body-budget.py`
- 6.2 Accept rows via `ci-pr-affected-replay.py audit --all-refs`; re-run `ratchet`
- 6.3 `.claude/hooks/grep-q-pipe-guard.test.sh` recount (`PJ_TRIPLES` 316)
- 6.4 Telemetry drift test (`git-lock-marker-telemetry.test.ts`) unchanged and green
- 6.5 `regenerate-shard-manifest.py --incremental --write`, then the measured duration row
- 6.6 `fixture-relative-assert.test.sh --write-baseline`, then the plain check
- 6.7 C4 set: `c4-code-syntax`, `c4-render`, `c4-count-parity`, `c4-model-freshness`
- 6.8 `lint-orphan-test-suites.sh`, `lint-guard-contract.py` on the plan

## Phase 7 — Review and ship

- 7.1 Re-run the open code-review overlap filter; re-run `gdpr-gate` on the diff
- 7.2 `soleur:review` full panel (user-impact, observability-coverage included); fix round
- 7.3 PR body: `Refs #11910`, `## Changelog`, GDPR advisory, "live endpoint check: stub-only, tracked in #11956"; re-title draft PR #11949
- 7.4 CI is the full-suite gate; no run against any customer repo; content-strategy held row untouched
