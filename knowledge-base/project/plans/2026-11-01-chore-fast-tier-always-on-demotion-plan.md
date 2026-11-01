---
title: "chore: demote 8 always-on fast-tier labels exceeding the 10s committed cap to edge-selection (#11648)"
type: chore
date: 2026-11-01
slug: chore-fast-tier-always-on-demotion
branch: feat-one-shot-11648-fast-tier-demotion
issue: 11648
closes: 11648
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# chore: demote 8 always-on fast-tier labels exceeding the 10s committed cap to edge-selection (#11648)

## Overview

Eight labels in `ALWAYS_ON_SUITES` (`scripts/lib/test-affected-paths.sh`) carry committed weights below the `LOCAL_FAST_CAP_MS=10000` budget in `scripts/suite-durations.tsv`, but real CI timings — a `--timings-dir` re-price over five PR/merge_group runs (surfaced by the PR #11561 manifest regen, corroborated by the #11562 post-merge 8-run medians recorded in `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`) — put each above 10 s, so the next sanctioned durations regen (due by the issue's 2026-11-14 re-eval window) reds `scripts/test-all-fast-tier-budget.test.sh` unless the classification is decided first. Per the #9763 demotion doctrine, each crossed label leaves `ALWAYS_ON_SUITES` and becomes edge-selected: it keeps running on CI legs, merge_group, push and `--full`, and runs locally under `--affected` only when its declared/consumed/derived edge set matches the diff. Caps are not raised — the ratchet stands. The change removes the eight rows from `scripts/always-on-justifications.tsv`, re-pins the always-on census floor (`_MIN_ALWAYS_ON_DECLARED` in `scripts/test-all.sh` and its mirror literal in `scripts/test-all-affected.test.sh` f1), extends the `#9763 withdrawn-to-edge-selection` comment to name the resulting set, and reconciles the two audit surfaces that re-derive from classification (`scripts/test-affected-kb-consumers.baseline.txt`, and `scripts/ci-pr-affected-audit.accept.tsv` where a demoted suite's undeclared path mentions are citation-only — the committed ratchet baseline is shrink-only and cannot absorb new pairs).

`lane:` note — no `spec.md` exists for this branch at plan time, so `lane` defaults to `cross-domain` (TR2 fail-closed); the domain sweep below finds engineering-only implications.

## Problem Statement / Motivation

- `scripts/test-all-fast-tier-budget.test.sh` greens today only because the committed durations table under-prices the eight labels. The honest medians (ms, 8-run merge_group, per the runbook's #11562 post-merge re-price): `scripts/test-all-group-affected` 356,915; `tests/scripts/lint-ratchet` 26,575; `plugins/soleur/test/check-deps-adapter-drift.test.sh` 24,513; `plugins/soleur/test/token-drift-workflow-causes.test.sh` 19,777; `.claude/hooks/grep-q-pipe-guard.test.sh` 15,618; `scripts/lint-encryption-posture` 11,375; `plugins/soleur/test/gitleaks-merge-commit.test.sh` 11,791; `scripts/lint-gh-argv-arg-live` 13,212.
- A full `--timings-dir --write` re-price of `scripts/suite-durations.tsv` reds `test-all-fast-tier-budget` on both caps (per-suite >10 s AND summed ~464 s > 300 s total cap). The regen is due in the next sanctioned window; the classification must be decided before it lands or the regen itself is blocked.
- Keeping >10 s suites in the always-on local tier is also the drift the ratchet exists to prevent: every local `--affected` run pays them whether or not the diff can move their verdicts, and once PR affected-selection activates (ADR-276 S4), an honest edge set is what determines whether they may be skipped on a pull_request run.
- Epic context: this is the next child of #11556 (cut PR required-check time). It deliberately excludes the `--rows` arm-debt bundle (#11647, follow-on dispatch after this PR merges) and the ratchet-promotion watch issue (#11729).

## Research Insights

### Premise Validation (Phase 0.6)

- **#11648 OPEN** — the target issue. **#11556 OPEN** (epic). **#11562 CLOSED** via **PR #11561 MERGED 2026-10-30** (the manifest regen that surfaced the drift). **#9763 CLOSED** — the demotion doctrine origin, already applied once. **#11647 / #11729 OPEN** — both explicitly out of scope.
- Collision precheck (`scripts/collision-precheck.sh 11648`): PR #11779 names #11648 — it is THIS branch's own auto-created draft PR, not foreign work. Seven `test-all.sh` processes are running in the sibling worktree `feat-one-shot-11556-epic-ci-time-batch` — a parallel pipeline, disjoint files; local timing re-measurements taken during this work may be contended, so the plan re-prices from committed CI artifacts, not local wall-clock.
- Cited artifacts verified present: `scripts/lib/test-affected-paths.sh` (3,387 lines; `ALWAYS_ON_SUITES` holds 122 members), `scripts/test-all-fast-tier-budget.test.sh` (cap literals pinned 10,000 / 300,000), all 8 labels confirmed members of `ALWAYS_ON_SUITES`.
- ADR mechanism check (Phase 0.6 step 4): the proposed mechanism — demote to edge-selection with declared/consumed edges — is the same mechanism #9763 shipped (commit `01d2b5a0d8`), endorsed by ADR-262 (self-test mutation batteries withdrawn to consumed edges) and ADR-242 amendments (the always-on audit's hedge rule, decision 19/20). It is not an ADR-rejected alternative. One ADR-242 constraint does bind: a suite whose real reads cannot be bounded by declared edges stays hedged always-on — see the per-suite table; all 8 have boundable read sets.
- "Explicit classification row" in the issue's Proposed Fix resolves to the `edge:declared`/`edge:consumed` classification the selector prints per label — i.e., an entry the classifier can name rather than an `unclassified` leak-back (an unclassified suite selects anyway, defeating the demotion; `_affected_classify` rung 5, `scripts/test-all.sh:3986`).

### Property List (Phase 0.6b)

1. `test-all-fast-tier-budget` stays green when `scripts/suite-durations.tsv` is re-priced from real CI timings.
2. Each of the 8 labels still runs whenever a diff reaches its real subjects — honest `edge:*` classification, never `unclassified` leak-back and never silent under-selection (the kb-consumers and ci-pr-affected ratchets bound both directions).
3. The resulting classification set is documented where the withdrawal is recorded (the `#9763 withdrawn-to-edge-selection` index comment — pinned by the budget lint's drift arm).
4. Every always-on census ratchet stays green: `_MIN_ALWAYS_ON_DECLARED` (runner) + f1 literal (test-all-affected) re-pinned to count−5 in lockstep; justifications parity two-directional; non-live membership ceiling unaffected by removals.
5. No cap is raised, no committed durations row is hand-edited (generated table — `--durations` regen only), and the PR/CI full battery still runs all 8 suites.

### Cut List (Phase 0.6b)

No mechanism the ask did not already name was introduced. The "verify against a calm main-side run" alternative arm requires no new machinery — it is folded into Phase 0 as an evidence step using the existing `--timings-dir`/`--drift-report` path. No exemption mechanism was invented: `test-all-fast-tier-budget` has no overweight-always-on allowlist and creating one would be a new mechanism this ask does not need — all 8 suites have boundable edge scopes, so demotion is reachable for every label.

### Value-Proposition Measurement (Phase 0.6c)

The saving is measured, not asserted: the runbook's "2026-10-31 post-merge re-price" section records per-label 8-run merge_group medians (the `python3 scripts/regenerate-shard-manifest.py --drift-report --timings-dir <run-dirs>` path, artifacts `suite-timings-scripts-*`). Combined real weight of the 8 ≈ 464 s per selection vs. ~34 s committed — the local `--affected` fast tier stops paying the drifted cost on diffs that do not reach the suites' subjects, and the fast-tier committed total drops ~33 s (34.2 s → ~0.9 s attributable to the 8 rows leaving the capped set).

### Consolidated findings

- **Demotion precedent (commit `01d2b5a0d8`, #9804/#9763):** drop always-on entries → declare `AFFECTED_*_PATHS` scopes for corpus-walkers and self-only-derivation suites → re-pin `_MIN_ALWAYS_ON_DECLARED` to count−5 in `scripts/test-all.sh` AND the f1 literal in `scripts/test-all-affected.test.sh` (its fail text mandates moving both together) → update behavior arms → regenerate `scripts/test-affected-kb-consumers.baseline.txt` → doc sweep. This plan mirrors that shape.
- **Current census:** `ALWAYS_ON_SUITES` = 122 members, floor `_MIN_ALWAYS_ON_DECLARED=117` (`scripts/test-all.sh:4164`, count−5 convention with the re-pin ledger at :4157-4163), f1 literal `"117"` (`scripts/test-all-affected.test.sh:2944`). Removing 8 → 114 members → floor **109** at both sites.
- **Classifier mechanics:** `_affected_classify` (`scripts/test-all.sh:3934+`) — `always_on` > `edge:consumed` (AFFECTED_CONSUMED_EDGES label|ARRAY map) > `edge:declared` (`AFFECTED_<MAP(label)>_PATHS` in the index lib; map = label uppercased, non-alnum→`_`, leading `_` stripped) > `edge:derived` (argv literals + source closure) > `unclassified` (**selects anyway** — a demoted suite with no edges leaks back into every `--affected` run). Declared/consumed edges UNION with derived edges — a declaration can only widen.
- **Guards that re-derive from classification:** `scripts/always-on-ledger.test.sh` (P1: justifications.tsv parity two-directional — the 8 rows must be deleted or they read stale; P2: non-live cap 95, removals only help). `scripts/lint-orphan-test-suites.sh` (live-scanner census: a `-live` registration MUST be always-on or carry a **declared** edge — `scripts/lint-gh-argv-arg-live` requires a declared array; corpus-walker census: unscoped `git ls-files`/`rglob`/`grep -r` walkers need declared scope edges — binds `grep-q-pipe-guard`, `lint-gh-argv-arg`, `lint-encryption-posture`, `check-deps-adapter-drift` glob reads; unclassified-registration ERROR binds all 8). `scripts/test-affected-kb-consumers.test.sh` (every registered suite's REAL `knowledge-base/` read needs always-on or a covering edge; citation-only refs record as baseline rows). `scripts/ci-pr-affected-replay.py ratchet` — always-on suites are unaudited; once demoted they become `audited`, so every tracked path they name without edge coverage is a `new-pair` RED, and the baseline **cannot grow** — cover or accept-row each pair.
- **`grep-q-pipe-guard.test.sh` re-promotion history:** S4 PR5 (#10861) re-promoted it for being a whole-tree reader selected on >25% of merged PRs at ≤30 s. Its existing declared array `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` (index :1983) is deliberately PARTIAL (named tables only). Honest demotion needs root-anchored `glob:` edges over its PJ_EXTS scan set (see Technical Considerations).
- **Suite file registrations:** `scripts/test-all-group-affected` → `bash scripts/test-all-group-affected.test.sh` (test-all.sh:7224); `tests/scripts/lint-ratchet` → `python3 -m unittest tests.scripts.test_lint_ratchet` (:5525); `scripts/lint-gh-argv-arg-live` → `python3 scripts/lint-gh-argv-arg.py` (:5540); `scripts/lint-encryption-posture` → `bash scripts/lint-encryption-posture.test.sh` (:5638); the three `plugins/soleur/test/*.test.sh` and `.claude/hooks/grep-q-pipe-guard.test.sh` are SUITE_GLOB-registered.
- **Verification precedent:** the withdrawn set runs "on CI legs, merge_group, push and --full like every registered suite, and locally only when their subject paths change" — no shard-manifest or ci.yml change is needed; `scripts/suite-durations.tsv` rows stay (generated, never hand-edited) and stop counting toward the fast-tier caps once the labels leave `ALWAYS_ON_SUITES`.
- **Institutional learnings applied:** `2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md` (run the census, don't narrate it — every pin below was verified by reading the guard source); `always-on-audit.md` Rounds 1–3 (demote verdicts reversed when the recorder found reads the declaration could not bound — the per-suite read sets below are enumerated from source, not assumed); `2026-10-11-the-arm-i-made-live-was-pinned-only-from-the-ships-side.md` (the f1 literal is a second pin site — both move together).
- **Research substitution note:** the Phase 1 fan-out agents (`soleur:engineering:research:repo-research-analyst`, `soleur:engineering:research:learnings-researcher`) could not be spawned — this harness exposes no Task/subagent tool — so the equivalent reads were performed inline and are recorded above. External research skipped (Phase 1.6): the change is repo-internal tooling with an in-repo shipped precedent; nothing external applies. Functional-overlap (1.5b) and community-discovery (1.5) checks: not applicable — this changes classification data inside repo-private index files; no community artifact overlaps.
- **Plan-review substitution note:** the reviewer panel agents prescribed by the Plan Review section likewise cannot be spawned in this harness; a consolidated self-review was applied instead and is recorded at the end of this file. No independent review is claimed.

### Research Reconciliation — Spec vs. Codebase

| Claim (issue #11648) | Codebase reality | Plan response |
|---|---|---|
| 8 labels exceed the 10 s cap on real CI timings | Confirmed — committed weights 1,180–7,092 ms vs. 8-run merge_group medians 11,375–356,915 ms | Demote all 8; Phase 0 re-derives fresh medians as AC2 evidence |
| "each needs a declared/consumed edge or an explicit classification row" | `unclassified` suites select anyway — an edge is mandatory, not optional | Per-suite declared arrays in Files to Edit; grep-q-pipe keeps + extends its existing partial array |
| demotion comment must "name the resulting classification set" | The `#9763 withdrawn-to-edge-selection` block sits inside `ALWAYS_ON_SUITES` (:342-349) and currently names only the re-promoted `grep-q-pipe-guard` | Rewrite the block to enumerate the resulting demoted set |

## Proposed Solution

Move each of the 8 labels out of `ALWAYS_ON_SUITES` in `scripts/lib/test-affected-paths.sh` and give each an honest edge declaration — a new `AFFECTED_<LABEL>_PATHS` array (or extension of the existing `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS`) scoped to what the suite actually reads — so its classification becomes `edge:declared` (unioned with whatever derivation already reaches). Then reconcile every census that re-derives from the classification: delete the 8 `always-on-justifications.tsv` rows, re-pin the count−5 floors (117 → 109 at `scripts/test-all.sh:4164` and the f1 literal at `scripts/test-all-affected.test.sh:2944`), regenerate `scripts/test-affected-kb-consumers.baseline.txt`, and close out any `ci-pr-affected` ratchet pairs the demotions reveal with edge coverage or accept rows — never baseline growth. Finally, rewrite the `#9763 withdrawn-to-edge-selection` comment to name the resulting set per AC3.

## Technical Considerations

- **Demotion changes audit status.** Always-on suites are exempt from the `(suite, undeclared tracked path)` audit; edge-selected suites are audited. The implementation loop is: declare edges → run `python3 -I scripts/ci-pr-affected-replay.py ratchet` → for each `new-pair` either widen the declared array or add an anchor-keyed accept row to `scripts/ci-pr-affected-audit.accept.tsv` (mention-only paths: a message, a fixture written, never a read) → re-run until `live == baseline`.
- **kb-consumers dispositions differ per reference kind:** a REAL read gets a covering edge (`token-drift-workflow-causes` greps a real heading in `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md` → edge `knowledge-base/engineering/operations/runbooks/`); a synthetic `--paths` fixture member or doc comment is a `false-positive:` row in `scripts/test-affected-kb-consumers.baseline.txt` (regenerate with `bash scripts/test-affected-kb-consumers.test.sh --write-baseline`; the #9763 demotion recorded exactly these argv-code citation rows).
- **`glob:` declared edges:** root-anchored `glob:*.<ext>` entries (the GLOBROOT grammar, ADR-242 decision 28) mint real narrow edges over dir-less diff lines; dir-anchored `glob:<head>/...` covers whole trees. `*` crosses `/`. Malformed globs mint verbatim always-match edges — safe direction.
- **Observability gate (Phase 2.9): not triggered** — Files to Edit touch `scripts/`, `tests/`, `.claude/`, `plugins/soleur/test/` — none under the trigger set (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`); no new infrastructure surface. The verification surface is the gate suites' own output.
- **GDPR gate (2.7): not triggered** — no regulated-data surfaces; none of the (a)–(d) expansion triggers (no LLM processing of session data, threshold `none`, no new cron, no new distribution surface).
- **IaC gate (2.8): not triggered** — no new infrastructure.
- **Encryption posture (2.11): not triggered** — no persistent store, no new connection.
- **Task Design (2.9.3): not triggered** — no new autonomous-task surface.
- **Skill description budget (1.8): skipped** — no `SKILL.md` `description:` edits proposed.

### Per-suite demotion design

| Label | Registration argv | Real read set (enumerated from source) | Edge disposition |
|---|---|---|---|
| `scripts/test-all-group-affected` | `bash scripts/test-all-group-affected.test.sh` | `scripts/test-all.sh` (TARGET + sandbox copies), `scripts/lib/{test-affected-paths,test-relevance-paths,affected-glob,test-affected-derive-cache,repo-write-boundary}.sh`, self; `knowledge-base/support/community/2026-10-26-digest.md` is a synthetic `--paths` member, never read | New `AFFECTED_SCRIPTS_TEST_ALL_GROUP_AFFECTED_PATHS` = runner + five libs + self + index; kb citation → baseline `false-positive:` row if the oracle flags it |
| `tests/scripts/lint-ratchet` | `python3 -m unittest tests.scripts.test_lint_ratchet` | `plugins/soleur/scripts/lint-ratchet.py`, `plugins/soleur/scripts/ruff-requirements.txt`, `tests/scripts/fixtures/lint-ratchet/`, `tests/scripts/_git_fixture_env.py`, `ruff.toml`, `apps/web-platform/eslint.test-dirs.config.mjs`, self | New `AFFECTED_TESTS_SCRIPTS_LINT_RATCHET_PATHS`; fixture-side `knowledge-base/` strings are temp-repo writes — baseline rows only if the oracle flags them |
| `plugins/soleur/test/check-deps-adapter-drift.test.sh` | glob-registered | `plugins/soleur/skills/pencil-setup/scripts/` (check_deps.sh + pencil-mcp-adapter.mjs + pencil-save-gate.mjs + pencil-repl-surface.mjs), `plugins/soleur/test/test-helpers.sh`, self | New `AFFECTED_PLUGINS_SOLEUR_TEST_CHECK_DEPS_ADAPTER_DRIFT_TEST_SH_PATHS` (dir edge over the pencil-setup scripts dir) |
| `plugins/soleur/test/token-drift-workflow-causes.test.sh` | glob-registered | `.github/workflows/scheduled-terraform-drift.yml`, `scripts/check-cloudflare-token-drift.sh`, `apps/web-platform/infra/doppler-config-inventory.txt`, `apps/web-platform/infra/token-drift-read-tokens.tf`, `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md` (REAL read), `plugins/soleur/test/test-helpers.sh`, self | New `AFFECTED_PLUGINS_SOLEUR_TEST_TOKEN_DRIFT_WORKFLOW_CAUSES_TEST_SH_PATHS` including the runbooks dir edge (real read → covering edge, not a baseline row) |
| `.claude/hooks/grep-q-pipe-guard.test.sh` | glob-registered | Whole-tree PJ_EXTS read (sh bash yml yaml tf tftpl template service tmpl via `git ls-files`), plus the existing partial array's named tables, plus `knowledge-base/` non-archive code files | Extend existing `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` with root-anchored `glob:*.<ext>` for each PJ_EXTS extension — honest whole-tree scope; high selection rate is the truthful classification (its S4 PR5 `always_on` verdict was cost-based, not scope-based) |
| `scripts/lint-encryption-posture` | `bash scripts/lint-encryption-posture.test.sh` | `scripts/lint-encryption-posture.py`, `scripts/encryption-posture-ledger.json`, `scripts/encryption-posture-ledger.schema.json`, `apps/*/infra/` + `infra/` (rglob all files), `plugins/soleur/skills/plan/references/plan-issue-templates.md` (`--check-templates`), self | New `AFFECTED_SCRIPTS_LINT_ENCRYPTION_POSTURE_PATHS`; docstring's `knowledge-base/` plan-path mention is a comment → baseline row if flagged |
| `plugins/soleur/test/gitleaks-merge-commit.test.sh` | glob-registered | `.github/workflows/secret-scan.yml` (extracts `--log-opts`), `.gitleaks.toml`, `plugins/soleur/test/lib/gitleaks-probe.sh`, `plugins/soleur/test/test-helpers.sh`, self | New `AFFECTED_PLUGINS_SOLEUR_TEST_GITLEAKS_MERGE_COMMIT_TEST_SH_PATHS` |
| `scripts/lint-gh-argv-arg-live` | `python3 scripts/lint-gh-argv-arg.py` | `.github/workflows/*.{yml,yaml}` + every `**/*.sh` (the scan scope, per the linter docstring); SUT `scripts/lint-gh-argv-arg.py` | New `AFFECTED_SCRIPTS_LINT_GH_ARGV_ARG_LIVE_PATHS` = `glob:*.sh` + `.github/workflows/` + SUT + index — the lint-orphan live-scanner census requires a DECLARED edge for a `-live` registration |

### Census and ledger updates that move with the demotion

- `scripts/test-all.sh:4164` — `_MIN_ALWAYS_ON_DECLARED` 117 → 109, and extend the re-pin ledger comment (:4157-4163) with a `#11648: -8 always-on (the >10 s drifted set) — re-pinned at 114-5` line.
- `scripts/test-all-affected.test.sh:2941-2947` — f1 literal `117` → `109` and the pass/fail strings' `122-count` narrative updated (the fail text itself prescribes "move the floor to count - 5 here and in the runner together").
- `scripts/always-on-justifications.tsv` — delete the 8 stale rows (P1 parity is two-directional).
- `scripts/lib/test-affected-paths.sh` — the `#9763 withdrawn-to-edge-selection` comment block (:342-349) is rewritten to enumerate the resulting demoted set with per-suite disposition (declared edge array name); `grep-q-pipe-guard`'s S4 PR5 re-promotion note moves with it out of the member list.
- Behavior-arm sweep: `test-all-group-affected.test.sh` A6 asserts the floor machinery exists (value-agnostic — survives); `test-all-affected.test.sh` rows beyond f1 make no per-label always-on assertions (verified by grep). `scripts/test-all-weight-drift.test.sh` and `plugins/soleur/skills/work/SKILL.md` reference the mechanism generically — no label/count pins.

## Files to Edit

- `scripts/lib/test-affected-paths.sh` — remove 8 labels from `ALWAYS_ON_SUITES`; extend `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS`; add seven new `AFFECTED_*_PATHS` arrays; rewrite the withdrawn-to-edge-selection comment to name the resulting set.
- `scripts/test-all.sh` — `_MIN_ALWAYS_ON_DECLARED` 117 → 109 + re-pin ledger comment line.
- `scripts/test-all-affected.test.sh` — f1 literal pin 117 → 109 + narrative strings.
- `scripts/always-on-justifications.tsv` — delete the 8 demoted labels' rows.
- `scripts/test-affected-kb-consumers.baseline.txt` — regenerated via `--write-baseline` (only if the oracle flags new uncovered refs — expected: the `P_IRREL` citation in test-all-group-affected and doc-string mentions).
- `scripts/ci-pr-affected-audit.accept.tsv` — append anchor-keyed accept rows ONLY for mention-only paths the ratchet reports on the demoted suites (mention ≠ read); all real reads get edges instead.
- `knowledge-base/project/plans/2026-11-01-chore-fast-tier-always-on-demotion-plan.md`, `knowledge-base/project/specs/feat-one-shot-11648-fast-tier-demotion/{tasks.md,decision-challenges.md,session-state.md}` — this plan's own artifacts.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-11648-fast-tier-demotion/receipts/` — the AC2 evidence capture: per-label medians re-derived from the freshest `suite-timings-scripts-*` artifacts (a plain-text or TSV receipt, e.g. `medians-11648.txt`). No product code files are created.

## Open Code-Review Overlap

- **#8800** (test fixture: census sandbox `cp -al`/`ln -sfn` write-through hazard in `scripts/test-all-affected.test.sh`) — **Acknowledge**: different concern (fixture isolation, needs its own verification cycle); this plan edits only the f1 literal pin in that file and does not touch `build_census_sandbox()`. Scope-out stands.
- **#7942** (two `*.mutation.sh` batteries in `plugins/soleur/test/` run in no gate) — **Acknowledge**: unrelated registration/naming question; the demotion neither registers nor renames those batteries.

## User-Brand Impact

- **If this lands broken, the user experiences:** a misclassified suite either silently skipped on the diff that needed it (under-selection — a real regression class the ratchets exist to catch) or runs on every local `--affected` anyway (the demotion bought nothing). Worst case lands as a local-gate false-green, caught by CI's full battery — no user-facing artifact exists; this is repo-internal CI machinery.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — no user data, no credentials, no new surface; the diff touches test-selection metadata only.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** classification data inside a repo-private test index cannot reach a user artifact; the worst realistic defect is a skipped suite, bounded by the merge-gate full battery.

## Observability

```yaml
liveness_signal:
  what:            "test-all-fast-tier-budget + always-on-ledger + lint-orphan-test-suites verdicts — the classification guards themselves"
  cadence:         "per local --affected run / per CI leg"
  alert_target:    "CI job failure on the pr/merge_group run"
  configured_in:   "scripts/test-all-fast-tier-budget.test.sh, scripts/always-on-ledger.test.sh, scripts/lint-orphan-test-suites.sh (unchanged registrations)"

error_reporting:
  destination:     "suite FAIL lines on stderr (the guards' existing [FAIL]/[check] output)"
  fail_loud:       "non-zero exit of any of the three gate suites on a PR leg"

failure_modes:
  - mode:          "a demoted suite under-selects (edge set misses a real read)"
    detection:     "python3 -I scripts/ci-pr-affected-replay.py ratchet reports new-pair; test-affected-kb-consumers.test.sh reports an uncovered reference"
    alert_route:   "red CI leg (advisory affected-index-ratchet job + required gate suites)"
  - mode:          "a demoted suite leaks back into every run"
    detection:     "lint-orphan-test-suites.sh unclassified-registration ERROR; --print-selection shows no edge:declared row for the label"
    alert_route:   "red CI leg"
  - mode:          "floor/parity pins drifted (a label removed without its ledger row)"
    detection:     "always-on-ledger P1 stale-row RED; f1 literal-pin RED"
    alert_route:   "red CI leg"

logs:
  where:           "CI job logs for the test-scripts legs; local stdout of the three gate suites"
  retention:       "GitHub Actions retention (repo default)"

discoverability_test:
  command:         bash scripts/test-all-fast-tier-budget.test.sh
  expected_output: ALL PASS
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`bash scripts/test-all-fast-tier-budget.test.sh` green on a durations table priced from real CI timings (not stale committed prices)" [issue #11648] | AC1 / Test Scenarios §re-priced-fixture / Phase 0 evidence step | mapped |
| 2 | "Each of the 8 labels either demoted to edge-selection with declared edges, or its >10s price is shown to be a measurement artifact" [issue #11648] | Per-suite demotion design table + AC2 + Phase 0 median re-derivation | mapped |
| 3 | "The demotion comment in `test-affected-paths.sh` is updated to name the resulting classification set" [issue #11648] | Comment rewrite task (Phase 2) + AC3 | mapped |
| 4 | "do NOT raise the caps — that defeats the ratchet" [dispatch args + issue] | Proposed Solution + AC4 (cap literals unchanged) | mapped |
| 5 | "Out of scope for this PR: the ci/test-scripts arm-debt bundle … and the ratchet-promotion watch issue #11729" [dispatch args] | Dependencies & Risks non-goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Remove 8 labels from `ALWAYS_ON_SUITES` | "Demote each crossed label to edge-selection per the #9763 doctrine" | asked |
| Declared `AFFECTED_*_PATHS` arrays per suite | "each needs a declared/consumed edge or an explicit classification row" | asked |
| Demotion-comment rewrite naming the set | "The demotion comment in `test-affected-paths.sh` is updated to name the resulting classification set" | asked |
| `_MIN_ALWAYS_ON_DECLARED` + f1 re-pin | — | inferred — justification: the below-floor refusal and the f1 literal pin red the battery the moment the eighth label leaves; the f1 fail text itself mandates moving both sites together |
| `always-on-justifications.tsv` row deletions | — | inferred — justification: always-on-ledger P1 parity is two-directional; keeping the rows reads `stale` |
| kb-consumers baseline regen + ci-pr-affected accept rows | — | inferred — justification: demotion moves the 8 suites from unaudited to audited; uncovered refs/pairs red both ratchets and the baseline is shrink-only |
| Fresh-median evidence capture under `receipts/` | "or its >10s price is shown to be a measurement artifact" | inferred — justification: AC2's either/or needs recorded evidence for whichever arm each label lands on |
| `lane: cross-domain` frontmatter | — | inferred — justification: no spec.md exists to carry `lane:`; the fail-closed default applies |

### Split Assessment

- Subsystems touched: 3 — `scripts/`, `tests/`/`plugins/soleur/test/` (edge scopes only, no edits), `.claude/hooks/` (edge scopes only)
- Planned files: 6 repo files (+3 KB artifacts) | Estimated changed lines: ~180
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Guard Contract

The deliverable amends three existing guards' pinned inputs (the fast-tier budget's census, the runner's below-floor refusal, the f1 literal pin) and the classification index every guard censuses. The contract below is for the classification-change invariant this PR must preserve — the guards already carry their own mutation batteries.

### Guard 1 — always-on census coherence (the demotion cannot silently narrow the tier)

**Property.** Every label leaving `ALWAYS_ON_SUITES` leaves with (a) an edge declaration the classifier resolves to `edge:declared`/`edge:consumed`, (b) its justifications row deleted, and (c) both count−5 floor pins moved in lockstep — a partial demotion is red somewhere by construction.

**Assembly.** `ALWAYS_ON_SUITES` + the `AFFECTED_*_PATHS`/`AFFECTED_CONSUMED_EDGES` blocks in `scripts/lib/test-affected-paths.sh`; `_MIN_ALWAYS_ON_DECLARED` in `scripts/test-all.sh`; the f1 literal in `scripts/test-all-affected.test.sh`; `scripts/always-on-justifications.tsv`; the audit surfaces `scripts/test-affected-kb-consumers.baseline.txt` and `scripts/ci-pr-affected-audit.{baseline,accept}.tsv`. Chokepoints: `check_tier` (budget), `check_ledger` (ledger), the below-floor refusal, the ratchet's live-pair computation.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Remove a label from `ALWAYS_ON_SUITES` without re-pinning `_MIN_ALWAYS_ON_DECLARED` | RED — f1 literal-pin fails / below-floor refusal when the margin is exhausted |
| 2 | Remove a label without deleting its `always-on-justifications.tsv` row | RED — always-on-ledger P1 `stale` row |
| 3 | Demote `lint-gh-argv-arg-live` with no declared array (derived edges only) | RED — lint-orphan live-scanner census requires a declared edge for `-live` registrations |
| 4 | Demote `token-drift-workflow-causes` without a `knowledge-base/` covering edge | RED — test-affected-kb-consumers reports a real uncovered read |
| 5 | Demote any label and leave it `unclassified` (no edges anywhere) | RED — lint-orphan unclassified-registration ERROR; the suite leaks back into every `--affected` run |
| 6 | Declare a partial edge set for `grep-q-pipe-guard` covering only its named tables | RED — ci-pr-affected `new-pair` rows for the PJ_EXTS reads the declaration misses |
| 7 | Edit the index to add a 9th demotion but forget the f1 literal (runner floor moved alone) | RED — the two pin sites diverge; f1's own fail text names the lockstep rule |
| 8 | (must-PASS, non-canonical) A diff touching only `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md` selects `token-drift-workflow-causes` via `edge:declared` | PASS — permitted divergence: the real kb read is edge-covered |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — engineering-internal CI/test-selection machinery. The mechanical UI-surface override did not fire (no Files-to-Create/Edit match the UI-surface glob superset): Product tier is `none`, the Product/UX Gate is skipped.

## Architecture Decision (ADR/C4)

No architectural decision is made. The demotion applies an existing shipped doctrine (#9763, ADR-242 amendments, ADR-262) — no ownership/tenancy move, no new substrate, no trust-boundary change, no ADR divergence. C4 completeness check: `model.c4`/`views.c4`/`spec.c4` were read — the affected-gate machinery is repo tooling, not a modeled element; the change introduces no external actor, external system, container/data-store, or access-relationship (the one C4-adjacent mention, `lint-ratchet.py` in the `plugin` system's description, is unchanged in behavior). Conclusion: no C4 impact — verified against the element census, not a keyword grep.

## Acceptance Criteria

- [ ] **AC1** — `bash scripts/test-all-fast-tier-budget.test.sh` is green on a durations table priced from real CI timings: verified by driving `check_tier` (or the suite) against a copy of `scripts/suite-durations.tsv` with the 8 labels' rows re-priced to their recorded real medians — it stays green because the labels are no longer in `ALWAYS_ON_SUITES`. The committed table itself is not hand-edited (generated artifact).
- [ ] **AC2** — each of the 8 labels is demoted to edge-selection with a declared/consumed edge (verified `bash scripts/test-all.sh --print-selection --paths=<a real subject path>` prints `edge:declared`/`edge:consumed` for the label, not `always_on`/`unclassified`), OR its >10 s price is documented as a measurement artifact with fresh-median evidence under `knowledge-base/project/specs/feat-one-shot-11648-fast-tier-demotion/receipts/` and the label remains always-on (then the plan's floor/ledger arithmetic adjusts to the kept count).
- [ ] **AC3** — the `#9763 withdrawn-to-edge-selection` comment in `scripts/lib/test-affected-paths.sh` names the resulting demoted set (and `grep -q "withdrawn-to-edge-selection" scripts/lib/test-affected-paths.sh` still passes, per the budget lint's drift arm).
- [ ] **AC4** — `LOCAL_FAST_CAP_MS`/`LOCAL_FAST_TOTAL_CAP_MS` remain 10000/300000 and `_MIN_ALWAYS_ON_DECLARED` == resulting-count − 5 at both pin sites (`scripts/test-all.sh` and `scripts/test-all-affected.test.sh` f1).
- [ ] **AC5** — `bash scripts/always-on-ledger.test.sh` green (no stale/no missing justification rows), `bash scripts/lint-orphan-test-suites.sh` green (no unclassified registrations; `lint-gh-argv-arg-live` carries a declared edge), `bash scripts/test-affected-kb-consumers.test.sh` green (baseline regenerated iff the oracle flags new refs), and `python3 -I scripts/ci-pr-affected-replay.py ratchet` reports `live == baseline` (new pairs resolved by edges or accept rows only — the baseline file is not grown).
- [ ] **AC6** — `bash scripts/test-all.sh --print-selection --paths=<path in a demoted suite's scope>` selects the demoted suite; `--paths=<unrelated path>` declines it where the honest edge set permits decline (the two whole-tree globs — `grep-q-pipe-guard`, `lint-gh-argv-arg-live` — legitimately select on most diffs; that is the truthful classification, recorded in the comment).
- [ ] **AC7** — `bash scripts/test-all-affected.test.sh` and `bash scripts/test-all-group-affected.test.sh` green (f1 pin updated; A-arms unaffected).
- [ ] **AC8** — no cap raised, no `suite-durations*.tsv` row hand-edited, no suite removed from CI legs/merge_group/`--full` (the 8 remain registered; only their local `--affected` classification changes).

## Test Scenarios

- Given the committed index minus the 8 labels, when `check_tier` runs against a durations table whose 8 rows carry the real merge_group medians (≈ 11.4 s–356.9 s), then it reports within-caps — `unit` (the suite's own fixture-driven arms already exercise the synthetic direction; this scenario verifies the real-priced shape).
- Given a diff containing `scripts/test-all.sh`, when `--print-selection --paths=scripts/test-all.sh` runs, then `scripts/test-all-group-affected` prints `edge:declared` and selects — `integration`.
- Given a diff containing `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md`, when `--print-selection` runs, then `plugins/soleur/test/token-drift-workflow-causes.test.sh` selects via its declared edge — `integration`.
- Given a diff touching an unrelated path (e.g. `docs/some-page.md`), when `--print-selection` runs, then `scripts/test-all-group-affected`, `tests/scripts/lint-ratchet`, `check-deps-adapter-drift`, `token-drift-workflow-causes`, `lint-encryption-posture`, `gitleaks-merge-commit` all decline, while `grep-q-pipe-guard` (if the path is PJ_EXTS-typed it legitimately selects; markdown is outside PJ_EXTS) and `lint-gh-argv-arg-live` (non-.sh/non-workflow) decline — `integration`.
- Given the demoted set, when `python3 -I scripts/ci-pr-affected-replay.py ratchet` runs, then `SOLEUR_PR_AFFECTED_RATCHET exit=0` — new pairs are zero after edges/accepts — `integration`.
- Given a fuzz over each demoted label's first declared-edge member, when `--print-selection --paths=<member>` runs for each, then the label selects — `unit`-adjacent `integration` (property: every declared edge is live, not dead — catches a malformed `glob:` minting wrong).

## Success Metrics

- `test-all-fast-tier-budget` green before AND after a real re-price of `suite-durations.tsv` — the 2026-11-14 regen window lands without blocking.
- `ALWAYS_ON_SUITES` count 122 → 114 (or kept-label count if any label is proven artifact-only, with floor pins moved to match).
- Zero `unclassified` demoted labels; zero new ci-pr-affected ratchet pairs left uncovered.
- Local `--affected` selected-set committed weight reduced by ~33 s (the 8 rows' committed total) — real-time saving larger on diffs that don't reach the suites' subjects.

## Dependencies & Risks

- **Out of scope (named in the dispatch):** the `ci/test-scripts --rows` arm-debt bundle (#11647 — follow-on dispatch after this PR merges) and the ratchet-promotion watch issue (#11729). Neither is touched by this plan.
- **Contention risk:** a sibling worktree pipeline (`feat-one-shot-11556-epic-ci-time-batch`) is running `test-all.sh` processes on this host — any local timing measurement taken during this work is contended; the plan therefore prices from committed CI artifacts (`suite-timings-*` downloads), not local wall-clock.
- **Artifact freshness:** `suite-timings-*` artifacts live 14 days. The Phase 0 re-derivation uses the newest green `merge_group` runs available at implementation time; if none are fresh enough, the recorded 8-run medians in the runbook (2026-10-31) stand as the AC2 evidence and are quoted into the receipt.
- **Ratchet churn on land:** `affected-index-ratchet` is advisory today (`continue-on-error`) but is the promotion candidate in #11729 — this PR must leave `live == baseline` or it arms the next fire.
- **Merge-order sensitivity:** the floor pins are literal integers; a sibling PR that adds/removes an always-on label and merges first invalidates `109` — the re-pin arithmetic (count−5) is re-verified against `origin/main` at rebase.
- **Discovery:** `test-all-group-affected` may pick up additional subject reads during implementation (it copies `scripts/lib/*` into sandboxes) — the declared array is built from what the suite file actually names, iterated against the ratchet until clean.

## References & Research

- Doctrine precedent: commit `01d2b5a0d8` (#9804/#9763) — the prior always-on→edge-selection split.
- Mechanism: `scripts/test-all.sh` `_affected_classify` (:3184-3210, :3930-3998); `scripts/lib/test-affected-paths.sh` ALWAYS_ON + declared-edge blocks; `scripts/lib/test-relevance-paths.sh` consumed-edge arrays (`TEST_ALL_AFFECTED_BATTERY_PATHS` :207, `PR_GATE_MACHINERY_PATHS` :107).
- Guards: `scripts/test-all-fast-tier-budget.test.sh`, `scripts/always-on-ledger.test.sh`, `scripts/lint-orphan-test-suites.sh` (:1041-1143, :1309-1368), `scripts/test-affected-kb-consumers.test.sh`, `scripts/ci-pr-affected-replay.py` RATCHET section.
- Measurements: `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` (2026-10-30 baseline + 2026-10-31 post-merge re-price, incl. the 8-run medians and the "`--timings-dir` requires PR/merge_group artifact runs" caveat).
- Prior audit evidence: `knowledge-base/project/specs/archive/20261013-062704-feat-affected-parallel-test-gate/always-on-audit.md` (Rounds 1–3 — the demote/disqualified/uncovered/unreliable verdict vocabulary).
- ADRs: ADR-242 (local gate defaults to affected + always-on ratchets, decisions 19/20/22/27/28), ADR-262 (PR CI path-gates the self-test mutation batteries), ADR-276 (S4 PR affected-selection activation), ADR-140 (encryption-posture gate — the lint-encryption-posture subject).
- Issues: #11648 (this plan), #11556 (epic), #11562 (closed — surfaced the drift), #9763 (doctrine), #11647 & #11729 (out of scope).

## Implementation Phases

#### Phase 0: Evidence capture and pin arithmetic

- Re-derive per-label medians for the 8 labels from the newest green `merge_group` `suite-timings-scripts-*` artifacts (`gh run download <id> -p 'suite-timings-scripts-*' -D <dir>` then `python3 scripts/regenerate-shard-manifest.py --drift-report --timings-dir <dirs…>`; fall back to the runbook's recorded 2026-10-31 medians if artifact freshness fails). Write `knowledge-base/project/specs/feat-one-shot-11648-fast-tier-demotion/receipts/medians-11648.txt`.
- Compute resulting always-on count (122 − demoted count) and the floor value (count − 5). If any label's fresh median reads ≤10 s, disposition = measurement artifact (AC2 alternative arm) and the arithmetic adjusts.
- Deliverable: receipt file + the demotion set locked.

#### Phase 1: Index demotion

- In `scripts/lib/test-affected-paths.sh`: remove the 8 labels from `ALWAYS_ON_SUITES`; extend `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` with the PJ_EXTS `glob:` edges; add the seven new `AFFECTED_*_PATHS` arrays per the design table (each carrying self-inclusion + `scripts/lib/test-affected-paths.sh`); rewrite the `#9763 withdrawn-to-edge-selection` comment to name the resulting set.
- Delete the 8 rows in `scripts/always-on-justifications.tsv`.
- Deliverable: index + ledger coherent; `bash scripts/always-on-ledger.test.sh` green.

#### Phase 2: Pin re-ratchet and comment

- `scripts/test-all.sh`: `_MIN_ALWAYS_ON_DECLARED` → resulting-count − 5, plus the re-pin ledger comment line.
- `scripts/test-all-affected.test.sh`: f1 literal + narrative strings.
- Rewrite the withdrawn comment block (Phase 1 may interleave this — same file, keep atomic).
- Deliverable: `bash scripts/test-all-fast-tier-budget.test.sh` + `bash scripts/test-all-affected.test.sh` green.

#### Phase 3: Ratchet reconciliation loop

- `python3 -I scripts/ci-pr-affected-replay.py ratchet` → resolve every `new-pair` on the 8 demoted suites via edge widening or anchor-keyed accept rows (mention-only); never grow the baseline.
- `bash scripts/test-affected-kb-consumers.test.sh` → `--write-baseline` ONLY for citation/false-positive refs; real reads get edges (Phase 1).
- `bash scripts/lint-orphan-test-suites.sh` green; spot-check `--print-selection` rows for each label.
- Deliverable: all classification-deriving guards green.

#### Phase 4: Verification battery + docs

- Full guard battery: `bash scripts/test-all-fast-tier-budget.test.sh`, `bash scripts/always-on-ledger.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/test-affected-kb-consumers.test.sh`, `bash scripts/test-all-affected.test.sh`, `bash scripts/test-all-group-affected.test.sh`, `bash scripts/test-all-weight-drift.test.sh`, `bash scripts/test-all-corpus-weight-budget.test.sh`, `python3 -I scripts/ci-pr-affected-replay.py ratchet`, `bash scripts/test-all.sh --print-selection` spot checks per AC6.
- Re-priced-fixture check for AC1 (synthetic durations table at real medians).
- Confirm the 8 labels still appear in `scripts/suite-shard-legs.tsv` (registered for CI legs) and `scripts/suite-durations.tsv` (rows untouched).
- Deliverable: green battery + AC evidence in receipts.

## Consolidated self-review (Plan Review substitution)

Applied inline (no Task tool in this harness — independent reviewers could not be spawned; `Reviewed-Coverage: sequential-fallback`):

- **Simplicity (DHH/YAGNI lens):** the minimal diff is the classification change + the mechanical pin/ledger/baseline reconciliation it forces; no new machinery was added (0.6b cut list). A simpler "do nothing until the regen" alternative leaves the regen window broken — rejected.
- **Correctness lens:** the two silent-failure directions are bound by existing ratchets (under-selection → ci-pr-affected/kb-consumers; leak-back → lint-orphan unclassified census). The one structurally weak spot is `grep-q-pipe-guard`'s glob edges selecting on most diffs — accepted as the honest classification and documented in the comment rather than masked.
- **Riskiest phase:** Phase 3's ratchet loop is where unknown path-mentions surface; bounded by iterating edges/accepts until `live == baseline`, and the loop is mechanical.
- **Persisted challenges:** technical rulings recorded in `knowledge-base/project/specs/feat-one-shot-11648-fast-tier-demotion/decision-challenges.md`.
