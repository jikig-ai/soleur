---
title: "fix: CI enforcement-gap audit + battery-gate follow-ups + security-scan flake"
type: fix
date: 2026-11-12
slug: ci-battery-gate-enforcement-followups
branch: feat-one-shot-12666-12583-9340-batch
issue: 12666
closes: [12666, 12583, 9340]
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: CI enforcement-gap audit + battery-gate follow-ups + security-scan flake

## Enhancement Summary

**Deepened on:** 2026-11-12
**Sections enhanced:** 9 (Research Insights, Hypotheses, Proposed Solution, Technical
Considerations, Observability, Guard Contract, Scope Check, Acceptance Criteria,
Dependencies & Risks) plus three sections added outright (Implementation Phases,
Alternative Approaches Considered, Network-Outage Deep-Dive).
**Research agents used:** none — depth-1 harness; all prescribed fan-outs ran sequentially
inline (`Reviewed-Coverage: sequential-fallback`).

### Key Improvements

1. Corrected two load-bearing factual claims caught by the verify-the-negative pass: the
   oracle lane's data-path allowlist is EMPTY (`_never_a_member_`), strengthening the audit
   Q3 disjointness argument; and `admin-merge-ready.sh` lives under `plugins/soleur/scripts/`,
   not `scripts/`.
2. Pinned the probe's alert route to a verified-existing label (`compliance/critical`,
   matching the sibling ruleset-drift audit) — `ci/enforcement-gap` does not exist.
3. Confirmed the lint-orphan completeness arm's placement is sound: the linter is registered
   UNGATED (`test-all.sh:6071`), only its mutation battery is `--pr-gated`.
4. Added the Guard-2 mechanics the implementation must satisfy: `expected >= 6` closure-floor
   literal bump, one-array-one-call-site invariant, glob-loop `--pr-gated` special-case shape.
5. Recorded the GHA-vs-Inngest substrate ruling and the probe's novel-shape scrutiny note.

### New Considerations Discovered

- The probe's verdict contract is the plan's one novel pattern — flagged for reviewer scrutiny.
- `scripts/suite-*.tsv` weight manifests are `outside_surface` for the oracle lane — a
  weight-row-only diff cannot evade the weight-budget gate via the lane (supports Q3's
  "no leg move" answer).
- `workflow_dispatch` backfill on merge SHA `aae21955e6` is a live verification step for the
  probe (it must fire BYPASS on the incident merge).

## Overview

One PR, three open issues in the CI-machinery domain:

1. **#12666** — enforcement-gap audit: PR #12565 merged over a red required `test` check via
   ruleset bypass. Deliverable is a committed audit write-up answering the issue's four audit
   questions plus the one piece of machinery the audit motivates: a detective post-merge probe
   that flags any main merge whose PR head lacked a green full-battery CI signal and did not
   come through the merge queue.
2. **#12583** — flake fix: the skill-security-scan calibration test (~43 s baseline) exceeded
   its 180 s per-test timeout under box contention (load ~40). Deliverable is a surgical
   per-test timeout raise in the precedent shape the same file already uses.
3. **#9340** — PR battery gate follow-ups whose re-evaluation criterion (the #9323 soak probe)
   PASSED on 2026-11-09: per-suite admission rulings for six non-mutation next-tier suites, a
   per-suite CI-home review for the three already relevance-gated suites, narrowing the
   `.github/workflows` directory edge in `LINT_ORPHAN_BATTERY_PATHS`, and confirming the
   merge-queue residual (already live on ruleset 14145388).

## Research Insights

Reviewed-Coverage: sequential-fallback (depth-1 harness — the prescribed research
fan-out was executed sequentially inline by the planner rather than by subagents).

**Premise validation (Phase 0.6).** All three issues verified OPEN via `gh issue view`.
Collision precheck: PR #12699 names all three issues — it is this branch's own pipeline draft
(`head: feat-one-shot-12666-12583-9340-batch`), not a foreign duplicate. Verified facts:

- **#12666 incident is real and the timeline is pinned.** PR #12565 head `d46da3095c`: auto-merge
  armed 2026-11-10T12:03:58Z (mergeMethod MERGE, enabled by deruelle); `test-scripts (3/8)`
  FAILURE 2026-11-10T20:28Z (`[check] registration(s) with no committed weight row:
  plugins/soleur/scripts/run-health-emit.test.sh`); `test` aggregate FAILURE 20:43Z; merged
  2026-11-11T17:33:39Z by deruelle with NO `added_to_merge_queue`/`removed_from_merge_queue`
  timeline events and no `gh-readonly-queue` CI run on merge SHA `aae21955e6`. Native GitHub
  auto-merge cannot land over a failing required check — the merge was an explicit bypass action
  by a bypass-capable identity. Live ruleset 14145388 (`CI Required`, enforcement active)
  carries `required_status_checks` + `merge_queue` and bypass actors
  `OrganizationAdmin:pull_request` and `RepositoryRole(id=5):pull_request`.
- **#12583 flake site pinned.** `plugins/soleur/test/skill-security-scan.test.ts` calibration
  describe: test "0% of first-party SKILL.md emit HIGH-RISK" carries per-test timeout `180000`;
  `runCorpus()` scans every first-party SKILL.md once and both calibration tests share the
  cache, so the first test carries the whole corpus cost. File already uses surgical per-test
  timeout overrides (`30_000` elsewhere, citing #4096). The suite runs inside the
  `plugins/soleur` bun group (test-bun leg).
- **#9340 re-evaluation criterion is MET.** `scripts/followthroughs/pr-battery-gate-saving-9323.sh`
  reported `Sweeper run: PASS (2026-11-09T17:46:44Z)` — `qualifying_runs=40
  evidenced_runs=21 mean_runner_min=301.5 required_saving=20`, no escape. #9323 closed.
- **#9340 merge-queue bullet is STALE — already satisfied.** Ruleset 14145388 carries a live
  `merge_queue` rule (parameters: merge_method SQUASH, grouping ALLGREEN, max_entries_to_build 1);
  `gh-readonly-queue/main/pr-*` merge_group runs have been completing since at least
  2026-11-08 — predating the #12565 incident, which strengthens the audit's finding.
- **Mechanism minimality (0.6b).** Property List: (P1) a merge over a red required check becomes
  a loud attributed signal, not silent; (P2) an audit write-up answering the four audit
  questions; (P3) calibration test no longer flakes under contention; (P4) per-suite admission
  ruling for the six named next-tier suites; (P5) per-suite CI-home review for the three
  already-gated suites; (P6) `.github/workflows` edge narrowed to consumed files without losing
  coverage; (P7) merge-queue adoption confirmed. Cut List: new merge-queue machinery — cut,
  live already (P7 reduced to issue bookkeeping); bespoke "bypass event" GitHub webhook — cut,
  no such event reaches a self-hosted consumer at this scale, a polling probe covers P1;
  external research — cut, all machinery is in-repo.

**Relevant files (all on `origin/main`):**

- `scripts/test-all.sh` — `_diff_touches` (line ~3283, `--pr-gated` flag semantics, CI-bypass
  arms, fail-safe ordering), the in-runner `PR_GATE_CANARY_FAILED` canary (~3350), gated call
  sites at ~6036 (reaper), ~6099 (lint-orphan a/b), ~7493 (cf-tunnel), ~7557 (test-all-affected),
  ~7723 (registry), ~7733 (tag-authorship); relevance-gated (non-PR) sites ~7622 (c4 inside the
  glob loop), ~7364 (webplat unit arm), ~7756 (run-all.sh).
- `scripts/lib/test-relevance-paths.sh` — `PR_GATE_MACHINERY_PATHS` plus per-battery edge arrays
  (`REGISTRY_BATTERY_PATHS`, `CF_TUNNEL_BATTERY_PATHS`, `LINT_ORPHAN_BATTERY_PATHS`,
  `TAG_AUTHORSHIP_BATTERY_PATHS`, `TEST_ALL_AFFECTED_BATTERY_PATHS`,
  `AFFECTED_SCRIPTS_ORPHAN_PROCESS_REAPER_MUTATIONS_PATHS`, `C4_PRODUCER_PATHS`,
  `GITHUB_SCRIPTS_SUITE_PATHS`, `WEBPLAT_APP_PATHS`, `WEBPLAT_RELATED_META`). Every array ends
  with `PR_GATE_MACHINERY_PATHS`, SELF, and `scripts/lib/test-relevance-paths.sh` (the
  self-inclusion invariant the orphan linter enforces).
- `scripts/lint-orphan-test-suites.sh` — Guard 2: derives the `--pr-gated` array set from the
  runner's call sites, `RELEVANCE_ARRAYS` triples (`name|battery-file|element-count-floor`),
  `PR_GATE_CORPUS_ALLOWLIST` (whole-tree operand exemptions need written reasons). Surfaces 5/6
  grep `"$WORKFLOW_DIR"/*.yml` for `bash …test.sh` registrations — the whole directory IS the
  consumed set today.
- `scripts/test-all-pr-battery-gate.test.sh` — Guard 1: drives a COPY of the runner from a
  fixture repo, mutates each `--pr-gated` call site, grades CAUGHT only when the named arm fails.
  New `--pr-gated` call sites need new arms here.
- `scripts/ci-battery-gate-replay.sh` — replays each `--pr-gated` array against last-N
  first-parent commits; derives the gated set dynamically (no edit needed when adding sites).
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` — generated by
  `scripts/regenerate-shard-manifest.py` (`--incremental --write`); NOT hand-edited. The
  weight-row check that redded #12565 lives in `scripts/test-all-corpus-weight-budget` (leg 3).
- `scripts/probe-merge-group-coverage.sh` — Guard 1 of ADR-270; reads the canonical required-set
  JSONs (`scripts/ci-required-ruleset-canonical-required-status-checks.json`,
  `scripts/ci-cla-required-ruleset-canonical-required-status-checks.json`) — the same JSON the
  new probe should use as its required-set authority (kept in lockstep with the live ruleset by
  the daily `cron-ruleset-bypass-audit.ts` Inngest drift audit).
- `.github/workflows/ci.yml` — `test-scripts` matrix job is skippable by `push-dedupe` (push),
  `draft-light` (draft PRs, dark), and `oracle-selection` (oracle-only diffs); the `test`
  aggregator tolerates skips only for named reasons.
- `scripts/ci-oracle-lane.sh` — the oracle skip surface is narrower than it looks:
  `is_oracle_data_path` is an EMPTY allowlist today (`_never_a_member_`), so the only
  qualifying diffs are doc-path-only diffs and `ORACLE_INDEX`
  (`scripts/lib/test-affected-paths.sh`) edits confined to `AFFECTED_*_PATHS` extents
  (step-6 extent check). `scripts/suite-*.tsv` weight manifests are `outside_surface`
  → full battery. The exclusion list (`scripts/test-all.sh`, ci.yml, `scripts/lib/*`,
  the lane's own machinery) is a second net. So an oracle-only diff cannot touch suite
  registrations or weight rows.

**Suite facts (leg / measured weight / shape):**

| Suite | Leg | Weight | Shape |
|---|---|---|---|
| `plugins/soleur/test/monitor-pr-checks.test.sh` | 6 | 245 s | unit suite for `plugins/soleur/scripts/monitor-pr-checks.sh`; glob-registered |
| `tests/scripts/betterstack-roundtrip-latency` | 5 | 165 s | unit suite for `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh` |
| `tests/scripts/git-data-birth-readiness-gate` | 7 | 160 s | fixture-driven suite for `tests/scripts/lib/git-data-birth-readiness-gate.sh` |
| `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` | 6 | 154 s | guard-contract suite for `playwright-mcp-redact-proxy.py`; glob-registered |
| `scripts/test-contention` | 8 | 135 s | arms `scripts/lib/test-contention.sh`; explicit run_suite |
| `tests/scripts/sentry-alert-live-fidelity` | 6 | 103 s | drift-class suite for `scripts/sentry-alert-live-fidelity.sh` |
| `.github/scripts/test/run-all.sh` | (nested runner) | — | second REQUIRED home: `guard-script-fixture-tests` member in `quality-guards` (pr-quality-guards.yml, ungated, PR + merge_group) |
| `plugins/soleur/test/c4-from-components.test.sh` | glob loop | — | only test-all.sh-mediated homes (ci.yml leg + main-health-monitor 6-hourly) |
| `apps/web-platform [unit]` arm | test-webplat | — | `repo-wide+component` arm runs ungated beside it |

**Existing machinery checked for the bypass-alert property (P1) — none covers it:**

- `cron-ruleset-bypass-audit.ts` (Inngest, daily) audits ruleset CONFIG DRIFT (bypass_actors
  widened, required checks removed, enforcement suspended) — not per-merge bypass USE.
- `probe-merge-group-coverage.sh` — offline structural proof that required contexts have
  merge_group producers.
- `.github/workflows/post-merge-monitor.yml` — bot-fix pipeline only.
- `plugins/soleur/scripts/admin-merge-ready.sh` — PRE-merge gate for `--admin` merges
  (would have refused #12565's red `test`; it was not consulted).
- The `[full]` run-name marker ADR-276 planned as S4's full-battery marker does NOT exist in
  ci.yml (S4 is NO-GO/locked) — the probe cannot key on it.

**Institutional learnings applied:**

- `2026-03-19-github-ruleset-stale-bypass-actors.md` — bypass actors persist; audit the live set.
- `2026-03-19-github-actions-bypass-actor-not-feasible.md` — bot bypass via Integration actor
  impossible; synthetic-status pattern is the repo's existing answer.
- `2026-04-03-github-ruleset-put-replaces-entire-payload.md` — any ruleset edit goes through
  Terraform `infra/github/ruleset-ci-required.tf`, never ad-hoc PUT.
- `2026-09-22-the-admin-merge-gate-read-ready-from-an-empty-body.md` — readiness gates decide
  GREEN from positive counts, never empty-body absence.
- `2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md` — admin merges skip deploy-arm
  awaits; detection must not assume the normal path ran.
- ADR-262 Decision 4 (admission rule), Guard 2 closure contract; ADR-276 amendments (merge_group
  is the full-battery authority; S4 locked NO-GO); ADR-181 addendum §7/§8 (CI-home counting —
  run-all.sh's second home, c4's test-all.sh-mediated homes).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified 2026-11-12) | Plan response |
|---|---|---|
| #9340: "Merge queue adoption … The CI Required ruleset (14145388) carries only `required_status_checks` today" | Ruleset carries `merge_queue` (SQUASH, ALLGREEN); live merge_group runs since ≥2026-11-08 | Bullet dispositioned as already-done: verify + check off via issue comment, no code work |
| #12666: "Is there an alert path today when a required check is bypassed?" | No — drift audit covers config drift only; nothing detects per-merge bypass use | Build the detective probe (Phase B) |
| #9340: "the post-merge follow-through for #9323 reports the saving holds and no escape was found" | Soak PASSED 2026-11-09 (`mean_runner_min=301.5 ≥ 20`, no escape) | Re-evaluation unblocked; the unchecked bullets are the work |
| #12666 Q3 implies integrity gates may sit in a skippable leg | Integrity gates (weight-budget leg 3, lint-orphan leg 2, shard-manifest regen, always-on-ledger leg 3) are UNGATED inside test-scripts; the only whole-leg skip levers (oracle lane, draft-light) fire only on diffs that cannot touch registration/weight artifacts | Audit documents the disjointness argument; no leg move |

## Hypotheses

### Network-Outage Deep-Dive

The deepen-plan §4.5 trigger fired on the `timeout` token in #12583's title and Overview.
Layer-by-layer verification status, per the checklist contract:

- **L3 firewall allow-list:** not applicable — no SSH or host-connectivity hypothesis exists;
  the timeout is a bun-test per-test bound exceeded under host CPU contention (load ~40 on
  the shared runner), not a network stall. No egress path is exercised by the failing test.
- **L3 DNS/routing:** not applicable — same reason; the test reads local SKILL.md files.
- **L7 TLS/proxy:** not applicable — no HTTPS dependency in the calibration corpus.
- **L7 application:** verified in plan research — the timeout is the literal `180000` per-test
  argument in `plugins/soleur/test/skill-security-scan.test.ts`; the fix is a bound raise, not
  a service-layer change. No retry/backoff hypothesis is owed.

Verdict: the trigger fired on a lexical token; no network hypothesis survives inspection, so
no L3→L7 verification artifacts are owed in this plan.

## Problem Statement

Three independent but thematically-coupled CI-machinery defects:

1. **Enforcement gap (audit).** A required red `test` check was landed over via a ruleset
   bypass actor and nothing paged about it — the class recurs silently for any future bypass
   merge. Detection exists (the check redded on the PR) but enforcement and alerting did not.
2. **Flake.** The calibration test's 4× headroom over a 43 s baseline is insufficient on a
   contended box, producing false-red CI on unrelated PRs.
3. **Unfinished battery rollout.** The `--pr-gated` mechanism covers six mutation batteries;
   six more ~100-250 s suites are unevaluated, three already-gated suites lack the CI-home
   review needed to extend gating, and one directory-wide edge over-arms (~38% arm rate) — now
   that the soak has proven the gate safe.

## Proposed Solution

Four phases, ordered smallest-blast-radius first:

- **Phase A** — surgical timeout raise on the two calibration tests (`180000` → `600_000`,
  ~14× headroom over the 43 s baseline, same per-test override pattern the file uses at
  `30_000` citing #4096).
- **Phase B** — committed audit write-up (`knowledge-base/engineering/operations/post-mortems/`)
  answering #12666 Q1–Q4 with the evidence gathered here, plus `scripts/merge-bypass-audit.sh`
  + `.github/workflows/merge-bypass-audit.yml` (push-to-main + `workflow_dispatch`) that files
  a deduped issue when a merge lands without a green required set and without a merge_group
  run. The bypass-policy question (Q2) is recorded as an operator decision in
  decision-challenges — the ruleset is Terraform-managed and production-mutating.
- **Phase C** — #9340 follow-ups: amend ADR-262's admission rule (addendum) from "self-test of
  gate machinery" to "verdict is a property of a closed, declarable edge set"; admit the six
  named suites (all verified offline/unit suites over named SUT files) with per-suite
  `<NAME>_PATHS` arrays, RELEVANCE_ARRAYS entries, Guard-1 arms, and replay measurements;
  flip `.github/scripts/test/run-all.sh` to `--pr-gated` (its required `quality-guards` home
  still runs it on every PR); rule on c4-from-components and the webplat-unit arm (merge_group
  = full-battery authority per the ADR-276 amendment); narrow `.github/workflows` to a
  committed consumed-workflows enumeration with a completeness arm in the always-on linter.
- **Phase D** — bookkeeping: issue comments on #9340 (merge-queue bullet verified live; soak
  PASS recorded; per-suite rulings table) and #12666 (audit answers), weight-row regen for the
  new suite, ADR-262 addendum committed.

## Implementation Phases

### Phase A — #12583 flake fix (smallest blast radius, lands first)

1. Edit `plugins/soleur/test/skill-security-scan.test.ts`: raise the per-test timeout on both
   calibration tests from `180000` to `600_000` with a comment citing #12583, the ~43 s
   baseline, the observed >4× contention inflation, and the #4096 per-test-override precedent.
2. Verify locally: `bun test plugins/soleur/test/skill-security-scan.test.ts`.

### Phase B — #12666 audit + bypass detector

1. Write `knowledge-base/engineering/operations/post-mortems/2026-11-12-pr-12565-red-required-check-bypass-audit-postmortem.md` with the Q1–Q4 evidence (timeline pinned in Research Insights).
2. Write `scripts/merge-bypass-audit.sh` per the Guard-1 verdict contract + `--self-check` mode.
3. Write `scripts/merge-bypass-audit.test.sh` (fixture `gh` stub on PATH; every matrix row).
4. Write `.github/workflows/merge-bypass-audit.yml` (`on: push: branches: [main]` + `workflow_dispatch`).
5. Register the suite in `scripts/test-all.sh` (`run_suite "scripts/merge-bypass-audit" bash scripts/merge-bypass-audit.test.sh` — root `scripts/*.test.sh` is NOT in SUITE_GLOBS, explicit registration required).
6. Regenerate `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv` via `python3 scripts/regenerate-shard-manifest.py --incremental --write` — SAME diff (the #12565 defect class).
7. Backfill-verify: `workflow_dispatch` the probe against merge SHA `aae21955e6` during the PR and record that it fires BYPASS (the success metric).

### Phase C — #9340 battery follow-ups

1. `bash scripts/ci-battery-gate-replay.sh` — baseline arm rates for the lint-orphan battery (record ~38% claim) and per-candidate measurements for the new arrays.
2. ADR-262 addendum: admission-rule widening + per-suite ruling table + CI-home review.
3. `scripts/lib/test-relevance-paths.sh`: one `<NAME>_PATHS` array per admitted suite (PR_GATE_MACHINERY_PATHS + SUT + SELF + THIS FILE); narrow `LINT_ORPHAN_BATTERY_PATHS` (replace `.github/workflows` with enumerated members + the enumeration file).
4. `scripts/lint-orphan-consumed-workflows.txt`: sorted enumeration of `.github/workflows/*.yml` matching `grep -lE '\.test\.sh'`; completeness arm inside `lint-orphan-test-suites.sh` (the linter is registered UNGATED at test-all.sh:6071 — the arm cannot be declined).
5. `scripts/test-all.sh`: `--pr-gated` call sites for admitted suites (explicit `if/else` wraps for explicit registrations; `if [[ "$f" == "<path>" ]]` special-cases inside the SUITE_GLOBS loop for the two glob-registered admits — c4's shape at ~7621 with `--pr-gated` added); flip `run-all.sh` (line ~7756) to `--pr-gated`.
6. `scripts/lint-orphan-test-suites.sh`: `RELEVANCE_ARRAYS` rows + element floors per new array; raise the Guard-2 closure floor literal (`expected >= 6` — the error message itself instructs the bump); `PR_GATE_CORPUS_ALLOWLIST` reasons for any whole-tree operand.
7. `scripts/test-all-pr-battery-gate.test.sh`: one Guard-1 arm per new `--pr-gated` call site (including the glob-loop special-cases — arm diff = unrelated path, expect counted `[skip]`; mutation = delete the special-case).
8. Verify: `bash scripts/lint-orphan-test-suites.sh` exit 0; `bash scripts/test-all-pr-battery-gate.test.sh` exit 0; `bash scripts/ci-battery-gate-replay.sh` arm-rate delta recorded.

### Phase D — bookkeeping

1. `gh issue comment` #9340: merge-queue bullet verified live (ruleset 14145388 parameters + run history), soak PASS recorded, per-suite rulings table → check off bullets.
2. `gh issue comment` #12666: link the audit postmortem.
3. `gh issue comment` #12583: note the timeout fix.

## Alternative Approaches Considered

- **#12666 detector: extend `cron-ruleset-bypass-audit.ts` (Inngest, daily) instead of a new GHA workflow** — rejected as the primary shape: a daily sweep loses per-merge immediacy and the push event carries the merge SHA for free. The probe is purely git/repo-scoped (no app context, no app secrets, no Sentry dependency), which is exactly the carve-out where §4.4's Inngest preference does not bind — but the fork is recorded in decision-challenges.md (`pending - assumed: GHA push trigger`); if review prefers consolidation, the same verdict script is callable from the Inngest function.
- **Scheduled-poll workflow instead of push-triggered** — rejected: strictly worse latency and adds a second blind window for zero gain; the poll's own schedule can be skipped/renamed silently.
- **Webhook receiver (`ruleset`/audit-log event)** — rejected: no webhook consumer infrastructure exists for this repo's scale; a polling/push detector covers the same property with zero new service.
- **#12583: shrink the calibration corpus instead of raising the bound** — rejected: the corpus IS the security property (0% HIGH-RISK across all first-party skills); a sampled corpus weakens the guarantee the test exists to enforce. The file's own precedent (surgical per-test overrides) is the minimal-mechanism fix.
- **#12583: global runner/suite timeout raise** — rejected: it would mask future pathological regressions everywhere rather than headroom this one measured-outlier suite.
- **#9340: keep the `.github/workflows` directory edge** — rejected by the issue's own ask; the ~38% arm rate is measured over-broad.

## Technical Considerations

- **Probe semantics (fail-loud, never silent).** For each pushed merge commit on `main`:
  (a) a `merge_group` `success` run on the SHA → OK (the queue is the full-battery authority);
  (b) else resolve the source PR (squash-merge title `(#N)`, else merge-commit parents) and
  read the PR head's check runs for the required set in
  `scripts/ci-required-ruleset-canonical-required-status-checks.json` — every required context
  `success` → OK (a compliant direct merge); (c) else → file a `compliance/critical` issue
  (label verified via `gh label list`; matches the sibling ruleset-drift audit's route;
  a dedicated `ci/enforcement-gap` label may be created instead if reviewers prefer —
  it does not exist today) — deduped: skip when an open issue already names the SHA —
  plus `::error` annotation.
  Any `gh api` error exits 2 with an annotation — the probe must never exit 0 on an unread
  answer (the empty-body-verdict learning).
- **Probe permissions.** `contents: read`, `checks: read`, `actions: read`, `issues: write`.
  No checkout secrets beyond `GITHUB_TOKEN`; runs on `push` to `main` (per-merge, minutes-level
  detection) plus `workflow_dispatch` for backfill.
- **Admission-rule widening.** ADR-262 Decision 4 admits only machinery self-tests. The six
  named suites are unit/fixture suites over named SUT files — a strict superset class. The
  addendum keeps the machinery self-test clause and adds: "a suite whose verdict is a property
  of a closed, declarable edge set may carry `--pr-gated` when its declared edges cover its
  `$REPO_ROOT/`/`${ROOT}/` operands per Guard 2." Live-external suites (reading Better Stack /
  Sentry state) do NOT qualify — external drift is invisible to a diff predicate; none of the
  six named suites is live-external (verified: betterstack-roundtrip is the unit suite for the
  probe, not the live probe itself; sentry-alert-live-fidelity is a fixture-driven drift-class
  suite despite the "live" in its name).
- **Glob-registered suites** (`monitor-pr-checks.test.sh`, `playwright-mcp-redact-proxy.test.sh`)
  are gated by the c4 precedent at `scripts/test-all.sh:~7621`: an `if [[ "$f" == "<path>" ]]`
  special-case inside the SUITE_GLOBS loop, never a new lookup table. The c4 site uses a plain
  `_diff_touches` (relevance gate, not PR gate) — the new admits carry `--pr-gated` inside the
  same `if`-block shape. Guard 2's derivation greps `_diff_touches --pr-gated "${A-Z0-9_+"`
  literally, so the special-case call sites ARE visible to it; the one-array-one-call-site
  invariant (each RELEVANCE_ARRAYS row ↔ one call site, per the lint-orphan a/b comment) holds
  because each admit gets its own `if` block. The `expected >= 6` closure-floor literal in the
  linter must be raised to the new gated-array count — the linter's own error text instructs
  the bump.
- **Guard-2 closure.** Every new array must (a) appear in `RELEVANCE_ARRAYS` with an
  element-count floor, (b) contain `PR_GATE_MACHINERY_PATHS` + SELF + the relevance lib itself,
  (c) cover the battery file's literal `$REPO_ROOT/`/`${ROOT}/` operands or carry a
  `PR_GATE_CORPUS_ALLOWLIST` entry with a written reason, (d) be prefix-covered by
  `TEST_RELEVANCE_PREFIXES`.
- **Workflow-consumption narrowing (P6 design).** Introduce committed enumeration
  `scripts/lint-orphan-consumed-workflows.txt` = the sorted set of `.github/workflows/*.yml`
  that contain a `.test.sh` reference (the superset of what surfaces 5/6 can extract from).
  `LINT_ORPHAN_BATTERY_PATHS` replaces the bare `.github/workflows` directory entry with the
  enumerated files plus the enumeration file itself. A completeness arm inside
  `lint-orphan-test-suites.sh` diffs `grep -lE '\.test\.sh' .github/workflows/*.yml` against the
  committed list — a new workflow that registers suites but is not enumerated reds the
  always-on leg, forcing the enumeration update (which itself arms the battery via the
  enumeration file's edge membership). Measured arm-rate before/after via
  `scripts/ci-battery-gate-replay.sh` (issue cites ~38% today).
- **Weight-row contract.** The new `scripts/merge-bypass-audit.test.sh` is a NEW suite → it
  must land with a committed weight row via
  `python3 scripts/regenerate-shard-manifest.py --incremental --write` in the SAME diff —
  exactly the omission that redded #12565.
- **This PR arms every gated battery on itself** (it edits `scripts/test-all.sh`,
  `scripts/lib/test-relevance-paths.sh`, ci.yml-adjacent machinery) — full battery runs by
  design.

### Attack Surface Enumeration (detector coverage)

Ways a red required check can land on `main`: (a) `gh pr merge --admin` / REST
`PUT /pulls/{n}/merge` by a bypass-capable actor — covered by the probe's PR-head check-run
read; (b) GitHub UI "merge without waiting" — same actor class, same coverage; (c) auto-merge
fired before the check flipped — NOT a bypass (check was green/pending at evaluation) — the
probe reads the check's conclusion at audit time, and a later flip is recorded as
green-at-merge→red-later (different class: CI regression, not enforcement gap — the probe
reports it as `check_flipped_after_merge`, separate signal); (d) direct push to `main` with no
PR — flagged (`no_source_pr`); (e) a PR head whose required contexts posted `skipped`/`neutral`
conclusions that GitHub counts as green — counted as green by the probe (matches GitHub's own
semantics — a skip tolerated by the `test` aggregator is not a bypass).

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator sees either (a) silent
  enforcement gaps — a future bypass merge lands red required checks with no signal, the exact
  #12565 class recurring unobserved, or (b) false-red PR CI — a broken `--pr-gated` extension
  declines batteries on diffs that needed them, eroding trust in the `test` required check
  every PR depends on.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no regulated-data
  surface — the probe reads GitHub check-run/issue metadata only; the exposure is workflow:
  a mis-declared edge set lets a battery-breaking edit merge green (R1-class escape caught on
  the merge_group/push run, never on the PR).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** no single user-facing incident — the risk is a
  slow erosion of CI-signal integrity repo-wide (declined batteries, unflagged bypasses), an
  aggregate pattern rather than one catastrophic breach.

## Observability

```yaml
liveness_signal:
  what: "the merge-bypass-audit workflow runs on every push to main and exits 0; absence of runs is itself the anomaly (the workflow is on the push path, so a missing run means GitHub Actions is down — the same blind window every push-triggered audit shares)"
  cadence: "per push to main (~5-15/day); workflow_dispatch for backfill"
  alert_target: "compliance/critical GitHub issue on detection; ::error annotation on the run"
  configured_in: ".github/workflows/merge-bypass-audit.yml"

error_reporting:
  destination: "GitHub Actions run log + ::error annotation; filed issue carries the SHA evidence"
  fail_loud: "exit 2 + ::error::merge-bypass-audit annotation on any gh API error or unread answer — never exit 0 on an unread verdict"

failure_modes:
  - mode: "probe script exits 2 on gh API failure"
    detection: "red check run on the push; the workflow has no continue-on-error"
    alert_route: "red run visible on main commit; sweep by main-health-monitor hygiene"
  - mode: "probe files duplicate issues"
    detection: "dedupe arm — open issue naming the SHA suppresses refiling; test asserts it"
    alert_route: "the test suite, plus issue-volume eyeball on tracker"
  - mode: "required-set JSON drifts from live ruleset"
    detection: "existing daily cron-ruleset-bypass-audit (config-drift) — unchanged owner"
    alert_route: "compliance/critical drift issue (existing path)"

logs:
  where: "GitHub Actions run logs for the workflow"
  retention: "GitHub default (90 days)"

discoverability_test:
  command: "bash scripts/merge-bypass-audit.sh --self-check"
  expected_output: "self-check"
```

## Encryption Posture

```yaml
at_rest: []
in_transit:
  - connection: "GitHub Actions runner -> api.github.com (gh CLI)"
    enforced_at: "scripts/merge-bypass-audit.sh (gh api invocations)"
    tls: "HTTPS, TLS >= 1.2 (GitHub API minimum)"
    cert_verification: "on"
    does_not_defend: "a stolen GITHUB_TOKEN used from another caller — the token is Actions-scoped and expires with the job"
    disclosed_as: "not-publicly-claimed"
```

## Task Design

```yaml
tasks:
  - task: merge-bypass-audit
    trigger: "push to main (per-merge) + workflow_dispatch (backfill)"
    services: "reads GitHub check-runs/actions-runs/pulls/issues APIs + the committed required-set JSON; writes at most one GitHub issue per offending merge SHA"
    next: "nothing — terminal signal (issue + annotation)"
    human_reentry: "close the filed issue; re-run via workflow_dispatch for backfill; edit scripts/merge-bypass-audit.sh on main to change verdicts"
    dedupe: "before filing, open-issue search for an existing issue naming the merge SHA — a hit suppresses refiling (marker dedupe, not just concurrency)"
    source_dedupe: "not a ticket source — it consumes merge commits, one verdict per SHA"
```

## Guard Contract

### Guard 1 — merge-bypass-audit verdict integrity

**Property.** A merge on `main` is reported `BYPASS` if and only if it has no `merge_group`
success run AND its source PR's head lacked `success` on every required context — never green
by absence of evidence.

**Assembly.** The chokepoint is `scripts/merge-bypass-audit.sh`'s verdict function: every merge
commit on `main` flows through it (push trigger covers every landing path — queue merge,
direct merge, admin merge, direct push). The required set comes from
`scripts/ci-required-ruleset-canonical-required-status-checks.json` (single authority, drift-audited
daily), not a hand list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Merge commit with merge_group success run present | OK (queue authority ran) |
| 2 | Direct merge, PR head shows `test` conclusion `failure` | BYPASS + issue filed |
| 3 | Direct merge, PR head all-required `success` | OK |
| 4 | gh API returns empty/invalid check-runs body | exit 2 error — never OK |
| 5 | Dedupe: open issue already names the SHA | suppressed (no second issue) |
| 6 | Direct push, no source PR resolvable | BYPASS (`no_source_pr`) — never silently OK |
| 7 | Merge whose head check was green at merge but red at audit (post-merge re-run) | `check_flipped_after_merge` report, NOT bypass |
| 8 | Mutate the script's verdict function to return OK unconditionally | the suite's instrument control arms RED (vacuity direction) |

### Guard 2 — consumed-workflows enumeration completeness

**Property.** Every `.github/workflows/*.yml` whose content can feed surfaces 5/6 (i.e. names
`.test.sh`) is a member of `scripts/lint-orphan-consumed-workflows.txt`, and the battery's edge
set covers exactly that enumerated set.

**Assembly.** Two chokepoints: the enumeration file (committed, sorted) and the completeness
arm inside `lint-orphan-test-suites.sh` that recomputes `grep -lE '\.test\.sh'` and
set-diffs it against the file. The arm lives in the always-on linter (leg 2, ungated) so the
check itself cannot be --pr-gated away.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add a workflow containing a `bash x.test.sh` step without touching the enumeration | completeness arm RED |
| 2 | Drop one enumerated file from the .txt while it still contains `.test.sh` refs | completeness arm RED |
| 3 | Remove `.github/workflows` from LINT_ORPHAN_BATTERY_PATHS without adding enumerated members | battery declines on a workflow-registration diff — Guard-1 arm RED |
| 4 | Enumerate a file with NO `.test.sh` refs (over-inclusion) | allowed by design; the completeness check is one-directional (missing ⊆ listed), documented |
| 5 | Empty the enumeration file entirely | vacuity direction: the arm's own `grep -l` floor reds (0 enumerated vs >0 consumed) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#12666 (audit: PR #12565 merged over a red required 'test' check via ruleset bypass — enforcement gap audit)" | Phase B audit doc + FR-B1–B4 | mapped |
| 2 | "Which bypass actor/mode executed the merge" | Audit Q1 finding (Phase B deliverable) | mapped |
| 3 | "Should `pull_request` bypass remain enabled for `OrganizationAdmin`/`RepositoryRole`" | Operator decision row (decision-challenges); audit recommendation | mapped |
| 4 | "should suites that gate *artifact integrity* … also run in a leg that cannot be path-gated or skipped" | Audit Q3 finding (no move — disjointness argument) | mapped |
| 5 | "Is there an alert path today when a required check is bypassed? If not, add one" | `scripts/merge-bypass-audit.sh` + workflow (Phase B) | mapped |
| 6 | "#12583 ([flake] skill-security-scan calibration test exceeds 180s timeout under box contention, 43s baseline)" | Phase A timeout raise | mapped |
| 7 | "Non-mutation next-tier suites … each needs its own admission argument. Re-evaluate against the remaining top suites by runner-minute" | Phase C per-suite admission table + ADR-262 addendum | mapped |
| 8 | "Already relevance-gated suites … needs a per-suite CI-home review" | Phase C CI-home review (run-all.sh flip; c4/webplat-unit ruling) | mapped |
| 9 | "Narrow the `.github/workflows` directory entry in `LINT_ORPHAN_BATTERY_PATHS`" | Phase C enumeration + completeness arm | mapped |
| 10 | "Merge queue adoption would make the gate fully closed" | Verified already live → issue comment check-off (Phase D) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase A timeout edit | "raise the per-test timeout for this case or mark it slow-tier … or shrink the calibration corpus scope" | asked |
| Phase B audit postmortem doc | "audit: PR #12565 merged over a red required 'test' check via ruleset bypass — enforcement gap audit" | inferred — the audit needs a durable home; a postmortem-format doc in the established `post-mortems/` convention is the repo's shape for it (issue comment alone rots) |
| `scripts/merge-bypass-audit.sh` + `.test.sh` + workflow | "Is there an alert path today when a required check is bypassed? If not, add one (e.g., audit-log sweep or a `ruleset_bypass` event hook)" | asked |
| ADR-262 addendum | "They fail ADR-262's admission rule (not self-tests of gate machinery), so each needs its own admission argument" | asked — the admission argument cannot be written per-suite without widening the rule's class |
| per-suite arrays + RELEVANCE_ARRAYS + Guard-1 arms | "Gate `orphan-process-reaper-mutations` … fold it into the `--pr-gated` set by reusing that array" (the #12619 precedent the issue itself cites) | asked |
| consumed-workflows enumeration + completeness arm | "it needs linter-side enumeration of consumed workflow files" | asked |
| weight-row / shard-manifest regen step | — | inferred — the corpus-weight-budget gate refuses a registration with no committed weight row (the #12565 defect class); required for any new suite |
| issue comments on the three issues | — | inferred — the tracker's unchecked bullets are dispositions that live on the issue; #9340's own framing is a tracker |

### Split Assessment

- Subsystems touched: 3 — `scripts`, `.github`, `plugins/soleur`
- Planned files: ~14 | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the three issues share the gate-machinery surface; a split would
  order the same edits serially for no independence gain (operator instruction explicitly
  requests one PR).

## Acceptance Criteria

### Functional Requirements

- [ ] FR-A1: `plugins/soleur/test/skill-security-scan.test.ts` — both calibration tests carry a per-test timeout `>= 600_000` with a justification comment citing #12583, the ~43 s baseline, and the contention class (file: `plugins/soleur/test/skill-security-scan.test.ts`, calibration describe).
- [ ] FR-B1: `knowledge-base/engineering/operations/post-mortems/2026-11-12-pr-12565-red-required-check-bypass-audit-postmortem.md` (or date-adjacent name) answers all four audit questions with the verified evidence: Q1 explicit bypass merge by deruelle over a ~21h-red required `test`, no merge-queue involvement; Q2 recommendation recorded as pending operator decision; Q3 disjointness argument (integrity gates ungated + oracle surface cannot touch registration/weight artifacts); Q4 no prior alert path → probe built.
- [ ] FR-B2: `scripts/merge-bypass-audit.sh` implements the verdict contract in Guard 1 (merge_group success → OK; else required-set check on PR head; else BYPASS; `check_flipped_after_merge` distinguished; `no_source_pr` flagged; any API error → exit 2) AND a `--self-check` mode that verifies the required-set JSON parses and `gh` auth resolves, prints `merge-bypass-audit self-check ok` on success and exits 2 otherwise (the observability `discoverability_test.command` depends on this mode existing).
- [ ] FR-B3: `.github/workflows/merge-bypass-audit.yml` runs the probe on `push` to `main` and `workflow_dispatch`, least-privilege permissions, no `continue-on-error` on the audit job.
- [ ] FR-B4: `scripts/merge-bypass-audit.test.sh` drives the probe over fixture responses covering every Guard-1 matrix row; registered in `scripts/test-all.sh` and landed WITH its shard-leg + weight rows (`regenerate-shard-manifest.py --incremental --write`) in the same diff.
- [ ] FR-C1: ADR-262 carries an addendum widening the admission rule per Technical Considerations, and each admitted suite names its edge array + measured arm rate (from `bash scripts/ci-battery-gate-replay.sh`).
- [ ] FR-C2: The six named suites each receive a recorded ruling — admit (array + `--pr-gated` call site + RELEVANCE_ARRAYS entry + Guard-1 arm) or decline-with-reason — in the audit/issue table.
- [ ] FR-C3: `.github/scripts/test/run-all.sh`'s call site flips to `--pr-gated` (required `quality-guards` home documented as covering every PR); c4-from-components and the `apps/web-platform [unit]` arm each get a recorded ruling.
- [ ] FR-C4: `LINT_ORPHAN_BATTERY_PATHS` no longer contains the bare `.github/workflows` directory entry; `scripts/lint-orphan-consumed-workflows.txt` exists, is sorted, and the completeness arm in `lint-orphan-test-suites.sh` reds on an unenumerated workflow carrying `.test.sh` refs.
- [ ] FR-D1: `gh issue comment` on #9340 checks the merge-queue bullet (ruleset 14145388 `merge_queue` rule, live runs since 2026-11-08) and records the soak PASS + per-suite rulings table; `gh issue comment` on #12666 links the audit doc.

### Non-Functional Requirements

- [ ] NFR-1: `bash scripts/ci-battery-gate-replay.sh` output before/after recorded in the PR body or audit doc (arm-rate delta for the lint-orphan battery — target: materially below the ~38% the issue cites).
- [ ] NFR-2: `scripts/lint-orphan-test-suites.sh` exits 0 on the finished tree (Guard 2 closure, element floors, allowlist reasons all satisfied).
- [ ] NFR-3: `bash scripts/test-all-pr-battery-gate.test.sh` exits 0 — every new `--pr-gated` call site carries a Guard-1 arm.
- [ ] NFR-4: No decline on this PR's own run for the edited machinery — `PR_GATE_CANARY_FAILED` absent and every gated battery runs (self-proof).

### Quality Gates

- [ ] `bun test plugins/soleur/test/skill-security-scan.test.ts` passes.
- [ ] `bash scripts/merge-bypass-audit.test.sh` passes.
- [ ] CI `test` required check green on the PR head.

## Test Scenarios

- Given a pushed merge commit with a `merge_group` success run, when the probe audits it, then verdict OK and no issue filed (unit).
- Given a direct merge whose PR head `test` check-run concludes `failure`, when audited, then BYPASS + one deduped issue + `::error` (unit).
- Given a direct merge with all required contexts `success`, when audited, then OK (unit).
- Given a `gh api` error or empty body, when auditing, then exit 2 — never OK (unit).
- Given a second audit of an already-flagged SHA with the issue still open, when audited, then suppressed refiling (unit).
- Given a new `.github/workflows/x.yml` containing `bash foo.test.sh` and no enumeration update, when `lint-orphan-test-suites.sh` runs, then completeness arm RED (unit).
- Given an unrelated diff (`canary/unrelated-path.txt` class), when a PR CI run evaluates the new gated call sites, then each declines with a counted `[skip]` line (integration, Guard-1 driven).
- Regression for #12583: Given host contention, when the calibration corpus runs, then the test completes under 600 s (the raised bound — verified locally by a contended re-run; not a deterministic CI assertion).

## Success Metrics

- Zero `test`-timeout flakes attributable to the calibration tests in the 2 weeks post-merge.
- `merge-bypass-audit` produces `OK` on every compliant merge and would have fired on `aae21955e6` (assert via `workflow_dispatch` backfill on that SHA in the PR's verification log).
- Lint-orphan battery arm rate drops materially below 38% on the replay measure with zero coverage loss (Guard-2 closure stays green).
- Runner-minute saving from newly gated suites recorded (replay + suite-durations weights).

## Dependencies & Risks

**Precedent-diff record (§4.4).** Pattern-bound shapes in this plan all have in-repo
precedents: the timeout raise follows the same-file `30_000` per-test override (#4096); the
relevance arrays follow the `PR_GATE_MACHINERY_PATHS` + SELF + THIS-FILE block convention in
`scripts/lib/test-relevance-paths.sh`; the glob-loop gating follows the c4 special-case at
`test-all.sh:~7621` (delta: `--pr-gated` flag is new inside that shape); the probe workflow
follows the small push/dispatch workflow shape (e.g. `post-merge-monitor.yml`). The one novel
shape is the probe's verdict contract itself — **no precedent; pattern is novel** — reviewers
should scrutinize the merge_commit→source-PR→required-checks resolution chain against the
attack-surface enumeration above.

**Scheduled-work check (§4.4).** The Inngest canonical path (`apps/web-platform/server/inngest/functions/cron-*`, 60 live functions) was evaluated: the audit is **push-triggered, not scheduled** — GitHub push events have no Inngest ingress in this repo, the work is purely git/repo-scoped with no app context/secrets, and `step.run` memoization buys nothing for a per-merge verdict. GHA `on: push` is the correct substrate; the Inngest-extend fallback is recorded in decision-challenges.md.

- **Risk: admission-rule widening over-admits.** Mitigation: per-suite ruling table, Guard-2
  closure unchanged, replay measurement per array, declines stay counted verdicts; merge_group
  remains the full-battery authority per ADR-276.
- **Risk: probe false-positives spam issues.** Mitigation: dedupe by SHA; the
  `check_flipped_after_merge` class is reported separately (CI regression, not bypass);
  `workflow_dispatch` backfill validates the verdict matrix on known-good merges before the
  push trigger carries weight.
- **Risk: enumeration drift** (a new workflow registers suites un-enumerated). Mitigation:
  the completeness arm lives in the always-on linter leg and reds on the offending PR.
- **Dependency: operator ruling** on the bypass-actor question (Q2) — recorded in
  decision-challenges.md; not a merge blocker for the audit + probe.
- **Dependency: ADR-262 addendum** is a recorded-architecture change reviewed in this PR's
  diff (not a separate process).

## References & Research

- ADR-262 (`knowledge-base/engineering/architecture/decisions/ADR-262-pr-ci-path-gates-the-self-test-mutation-batteries.md`) — admission rule, Guard 1/2, residuals R1–R4.
- ADR-276 (`.../ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`) — merge_group authority; S4 locked NO-GO; `[full]` marker never shipped.
- ADR-270 (`.../ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`) — queue + stall probe + Guard 1 provenance.
- ADR-181 addendum §7–§8 — CI-home counting correction (run-all.sh second home; c4 homes all test-all.sh-mediated).
- `knowledge-base/project/brainstorms/2026-10-12-ci-path-aware-gating-brainstorm.md` — domain context (outside the 14-day carry-forward window; read as research, not as a decisions source).
- `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` + `plugins/soleur/scripts/admin-merge-ready.sh` — the documented bypass escape hatch the bypass actors exist for.
- Issues: #12666, #12583, #9340, #9323 (soak tracker, closed), #9729 (S4), #12478 (queue-merged PRs carry no push run).
- Learnings: `2026-03-19-github-ruleset-stale-bypass-actors.md`, `2026-03-19-github-actions-bypass-actor-not-feasible.md`, `2026-04-03-github-ruleset-put-replaces-entire-payload.md`, `2026-09-22-the-admin-merge-gate-read-ready-from-an-empty-body.md`, `2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md`.

## Open Code-Review Overlap

Two open `code-review` issues name files this plan touches:

- **#7942** "Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no
  gate" — **Acknowledge.** A different concern (glob-naming convention for `*.mutation.sh` in
  plugins/soleur/test/) already dispositioned in test-all.sh's own comment history; this plan
  adds `scripts/*.test.sh` (explicit registration convention), not a `*.mutation.sh`.
- **#8881** "review: #8854 test-scripts K=6→K=7 rebalance" — **Acknowledge.** A closed review
  record from a prior rebalance; this plan adds one suite via the same regenerate tooling —
  no fold-in needed.

## Domain Review

**Domains relevant:** engineering (CTO) — sequential-fallback assessment (depth-1 harness; the
domain-leader fan-out was assessed inline, not spawned).

### Engineering

**Status:** reviewed (self-assessed inline)
**Assessment:** All touched surfaces are CI/test machinery — the CTO domain's home turf:
`scripts/test-all.sh` gate call sites, relevance arrays, guard suites, a new probe script and
scheduled workflow, an ADR addendum, and a postmortem doc. No product code, no infra
provisioning (the ruleset-bypass question is deferred to an operator decision that would route
through Terraform `infra/github/` if taken). Product: NONE — no UI-surface file in
Files to Edit/Create (checked against the ui-surface term list: no component/page/route).
Marketing/Sales/Support/Finance/Legal/Product/Operations domains assessed: none relevant —
all changes are repo-internal test/CI machinery.

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-262-pr-ci-path-gates-the-self-test-mutation-batteries.md` with an addendum widening
Decision 4's admission rule (machinery self-tests → "verdict is a property of a closed,
declarable edge set"), recording the six-suite rulings, the three CI-home rulings, and the
`.github/workflows` narrowing rationale. In-scope plan task in Phase C — not deferred.

### C4 views

**No C4 impact** — checked against all three model files
(`diagrams/model.c4`, `views.c4`, `spec.c4`):
(a) external human actors — `founder` (issue reader/merger) and `publicReader` (public issue
surface) are already modeled; no new actor;
(b) external systems — GitHub is already `github = system "GitHub"` #external; the probe adds
a github-internal consumer (workflow → GitHub API + issue write), and the model deliberately
carries no `github -> github` edge (views.c4's own comment states the class does not render);
(c) containers/data-stores — none new (the workflow runs on GitHub-hosted runners inside the
GitHub boundary, matching how scheduled workflows are treated in existing edges);
(d) access relationships — unchanged (issues:write on own repo via GITHUB_TOKEN, an existing
shape in many workflows).
The ADR-262 addendum records an admission-rule widening — a policy decision, not a topology
change; a reader of ADR-262 without the addendum WOULD be misled, which is exactly why the
addendum is an in-plan deliverable.

## Files to Create

- `scripts/merge-bypass-audit.sh` — the probe (verdict contract per Guard 1)
- `scripts/merge-bypass-audit.test.sh` — fixture-driven suite for the probe
- `.github/workflows/merge-bypass-audit.yml` — push-to-main + dispatch trigger
- `scripts/lint-orphan-consumed-workflows.txt` — committed consumed-workflows enumeration
- `knowledge-base/engineering/operations/post-mortems/2026-11-12-pr-12565-red-required-check-bypass-audit-postmortem.md` — audit write-up

## Files to Edit

- `plugins/soleur/test/skill-security-scan.test.ts` — timeout raise on the two calibration tests
- `scripts/test-all.sh` — flip run-all.sh call site to `--pr-gated`; add `--pr-gated` gating for
  admitted next-tier suites (explicit `if _diff_touches --pr-gated … else skip_suite` wraps for
  explicit registrations; `if [[ "$f" == "<path>" ]]` special-cases inside the SUITE_GLOBS loop
  for the two glob-registered admits); register `scripts/merge-bypass-audit` explicitly
  (scripts/*.test.sh is not glob-registered)
- `scripts/lib/test-relevance-paths.sh` — one `<NAME>_PATHS` array per admitted suite
  (PR_GATE_MACHINERY_PATHS + SUT + SELF + THIS FILE per the block convention); narrow
  `LINT_ORPHAN_BATTERY_PATHS` (replace `.github/workflows` with the enumerated members + the
  enumeration file)
- `scripts/lint-orphan-test-suites.sh` — `RELEVANCE_ARRAYS` entries with element-count floors
  per new array; `PR_GATE_CORPUS_ALLOWLIST` updates if any whole-tree operand surfaces;
  new completeness arm for the consumed-workflows enumeration
- `scripts/test-all-pr-battery-gate.test.sh` — Guard-1 arms for each new `--pr-gated` call site
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` — regenerated (never hand-edited)
- `knowledge-base/engineering/architecture/decisions/ADR-262-pr-ci-path-gates-the-self-test-mutation-batteries.md` — addendum

## Skill Description Budget Check

No `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate or finalized — check
skipped per Phase 1.8.
