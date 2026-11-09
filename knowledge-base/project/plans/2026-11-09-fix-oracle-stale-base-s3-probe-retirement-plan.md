---
title: "fix(ci): oracle-selection pull_request diff base via merge-base (not HEAD^1) + retire S3 draft-light soak probes"
date: 2026-11-09
slug: oracle-stale-base-s3-probe-retirement
branch: feat-one-shot-12418-oracle-stale-base
issue: 12418
closes: 12418
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-11-09
**Sections enhanced:** Observability (emitted — deepen §4.7's non-pure-docs trigger is broader than plan §2.9's path list), Guard Contract (promoted to a top-level `##` section so `lint-guard-contract.py` resolves it — `###`-nested is invisible to the gate), Technical Considerations (merge-base repo precedents), retirement census dispositions (basename-dropping tombstones so the residual-zero AC is a clean universal).
**Research agents used:** none — sequential-fallback (no Task/Agent tool in this pipeline subagent context); all gates run inline.

### Key improvements

1. Observability section present and schema-compliant (allowlisted probe verb, literal `expected_output`, <15 s command).
2. Guard Contract lint-green (`python3 scripts/lint-guard-contract.py` → 1 entry, rc 0) with a design-derived 7-row mutation matrix including a guard-dispatch row and two must-PASS rows.
3. Residual-reference AC made unconditional: every live comment drops the basename for a `#9728` tombstone — no self-exempting grep.
4. Merge-base derivation grounded in sibling precedent (`check-backstop-revision.sh`, `legal-base-ref.sh`, `test-all.sh`), not a novel pattern.

### New considerations discovered

- `lint-guard-contract.py` keys on `^## Guard Contract` — a `###`-nested contract reads as absent at deepen §4.11.
- `pending - assumed` rows in `decision-challenges.md` are flagged `unruled-technical` by `technical-ruling-gate.sh` at ship time; the work/ship phase must spawn `soleur:engineering:cto` to convert the four pending rows before merge.

## Overview

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). There is no spec.md for this branch.

Two CI-lever items under epic #11556 land in one PR. First, the `oracle-selection` job's driver classifies a pull_request diff against the oracle surface using `diff_base="HEAD^1"` — the merge ref's first parent, a base tip captured when GitHub last rebuilt the merge ref — so a PR branch that itself carries a merge of `main` re-counts main-side churn and `oracle_only` misfires; the fix derives the diff base from the merge-base of the PR head against the live base ref instead, keeping the (2a) merge-ref shape guard and fail-closed semantics. Second, follow-through tracker #9728 closed on a PASS after the operator posted `S3-EXIT-CENSUS`, so the soak probe `scripts/followthroughs/ci-draft-light-soak-9728.sh` and the census instrument `scripts/ci-draft-push-census.sh` retire together with every registration their RETIREMENT clause and a live re-census enumerate — suite registrations, generated shard/duration rows, CODEOWNERS lines, ratchet accept rows, fixture baselines and stale comments — in one atomic deletion so no dead-path ratchet trips.

## Research Insights

**Research mode:** inline sequential fallback — this pipeline subagent context has no Task/Agent tool, so the Phase 1 fan-out (repo-research-analyst, learnings-researcher, functional-discovery, domain leaders, advisor) was executed inline by the orchestrator and each gate records `Reviewed-Coverage: sequential-fallback` implicitly via this note. No independent review agent ran.

### Premise Validation (Phase 0.6)

- **Issue #12418** — `gh issue view 12418` → `OPEN`, labels `priority/p2-medium`, `type/bug`, `domain/engineering`, `meta/machinery`. Premise holds; the issue prescribes the merge-base fix verbatim.
- **Tracker #9728** — `gh issue view 9728` → `CLOSED` 2026-11-08T21:36:05Z; per the brief, the sweeper auto-closed on a PASS and the operator posted `S3-EXIT-CENSUS` on 2026-11-08. The RETIREMENT preconditions in `scripts/followthroughs/ci-draft-light-soak-9728.sh:69-72` hold.
- **Cited files on `origin/main`:** `scripts/ci-oracle-lane.sh` (guard (2a) at ~262-277, `diff_base="HEAD^1"` at 275), `scripts/followthroughs/ci-draft-light-soak-9728{,.test}.sh`, `scripts/ci-draft-push-census{,.test}.sh` — all present.
- **`CI_ORACLE_LANE` is `on`** (`gh variable get CI_ORACLE_LANE` → `on`), so the misfire is live-cost, not dark telemetry.
- **Measured cost (Phase 0.6c):** `gh run view 42459010986` → `completed`/`cancelled`, 2026-11-08T07:29:42Z → 08:01:44Z (~32 min against the 30-min leg bound); issue #12418 records the same signature twice on PR #12376 and ~65 min serial for a full manifest run (#12393). Number source: the GitHub Actions run record, not an estimate.
- **ADR corpus (mechanism check):** ADR-276 §Scope-bound describes the pull_request guard as "the merge-ref two-parent shape (`HEAD^1` base, `HEAD^2` the PR head)" — the (2a) SHAPE stays; the defect is that diff-base derivation equated the shape's first parent with the intended diff base. No ADR decided `HEAD^1` *as* the semantic diff base; merge-base derivation is not a rejected alternative. The driver-sourcing precedent cuts the other way: `ci.yml` ~622-628 (#12329) deliberately sources the oracle-review driver from `git rev-parse HEAD^1`, not payload `base.sha`, because a payload SHA can go stale and a sourcing miss would run the PR-controlled HEAD copy — that rationale governs *which tree supplies the classifier*, not *which commit the diff runs against*, so the `base="HEAD^1"` driver-source line at `ci.yml` ~494 stays.
- **Collision precheck:** `bash plugins/soleur/scripts/collision-precheck.sh 12418` → exit 10: PR #12480 is **this branch's own draft PR** (head `feat-one-shot-12418-oracle-stale-base`, zero files), not a competing fix. Sibling worktrees running `test-all.sh` (`feat-one-shot-9729-s4-evidence-rerun`, `feat-one-shot-12375-oracle-lane-nits` → PR #12475, `feat-one-shot-cloud-sandbox-gh-auth-missing`) — expected fleet activity. Open racing PRs verified: #12434 (origin-tls, touches ci.yml), #12475 (oracle-lane nits, touches ci.yml), #7390 (suite TSV race) — operator-accepted per the brief.
- **`base_sha` output consumers:** none — `grep needs.oracle-selection.outputs.base_sha .github/workflows/` is empty; it is an audit-only output (`ci.yml` ~370 calls the pair "audit values").

### Property List (Phase 0.6b)

1. On `pull_request`, `oracle_only` reflects the PR's own delta when the branch carries a merge of `main`: `git diff` runs from the merge-base of the PR head against the live base ref, not the merge ref's first parent.
2. Every failure to resolve the merge-base stays fail-closed: any unresolvable ref emits the defaults (`oracle_only=false`) with a named `reason`, never a partial classification.
3. The retired probe and census leave zero live registrations: no orphan test suite (`lint-orphan-test-suites.sh`), no stale ratchet accept row (`census-degraded`), no dead CODEOWNERS path, no generated-manifest row for a deleted suite, no baseline row keyed to a deleted file.
4. Retirement edits are confined to the registration sites and their generated companions; historical records (ADR-276, archived plans/specs/learnings, the closed tracker) keep their references.

### Cut List (Phase 0.6b)

- ~~Also fix the oracle-review driver's `HEAD^1` sourcing (`ci.yml` ~625)~~ → property: correct base image for driver sourcing → already covered and deliberately HEAD^1 per #12329's stated rationale; a stale payload SHA *failing to resolve* is the hole it guards against.
- ~~Retire `scripts/ci-draft-light.test.sh` / `run_suite "scripts/ci-draft-light"`~~ → property: remove dead machinery → NOT dead: it is the S3 draft-light feature suite (the gated-jobs contract in ci.yml), live while `CI_DRAFT_LIGHT` is on; the RETIREMENT clause names only the soak probe and census instrument.
- ~~Hand-edit `scripts/suite-shard-legs.tsv` / `suite-durations.tsv`~~ → property: drop the two suite rows → covered by `scripts/regenerate-shard-manifest.py --incremental --write`, the sanctioned add/remove path the header documents; the `test-all.sh` comment says the generated TSVs are NOT hand-edited.
- ~~Hand-edit `plugins/soleur/test/fixture-relative-assert.baseline.txt`~~ → property: drop three rows keyed to deleted files → covered by `fixture-relative-assert.test.sh --write-baseline` (row-by-row equality baseline regenerated in the same commit).
- ~~New probe/guard to watch merge-base staleness~~ → property: regression visibility → the existing `ci-oracle-lane.test.sh` fixture suite is the regression vehicle; no new machinery needed.

### Relevant files

- `scripts/ci-oracle-lane.sh:256-330` — `run()` and the (2a) pull_request arm (`diff_base="HEAD^1"` at 275; `base_sha="$p1"` at 274; diff at 313; index extent diff at 356-359).
- `.github/workflows/ci.yml:454-510` — `oracle-selection` job: env block at 475-489 (add `PR_BASE_REF`/`PR_BASE_SHA`), driver-source `base="HEAD^1"` at ~494 (kept), `no_base_driver` fallback at ~503.
- `.github/workflows/ci.yml:2211-2320` — `oracle-index-check` (K=5 legs, the consumer that pays on a misfire; its "Fetch origin/main" step at ~2258 is precedent for an explicit base fetch: `git fetch --no-tags --quiet origin main`).
- `scripts/ci-oracle-lane.test.sh` — fixture-repo suite (~1594 lines); `drive()` at ~530 derives `base` from `HEAD^1` and injects `MERGE_GROUP_BASE_SHA`; a merge-carrying-branch fixture + `PR_BASE_*` env covers the fix.
- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md:139-146` — the manual replay recipe diffs `p1..p2`; must be updated to the merge-base recipe.
- RETIREMENT clause: `scripts/followthroughs/ci-draft-light-soak-9728.sh:69-72`.

### Live registration census (retirement footprint — re-censused 2026-11-09)

Repo-wide grep for `ci-draft-light-soak-9728|ci-draft-push-census` (excluding `.git`, `node_modules`):

| Site | Registration |
|---|---|
| `scripts/followthroughs/ci-draft-light-soak-9728.sh` + `.test.sh` | DELETE (`git rm`) |
| `scripts/ci-draft-push-census.sh` + `.test.sh` | DELETE (`git rm`) |
| `scripts/test-all.sh:7141-7144, 7149-7151` | two `run_suite` lines + their `#9728` comment blocks (the `run_suite "scripts/ci-draft-light"` block between them STAYS) |
| `scripts/suite-shard-legs.tsv:397, 432` + `scripts/suite-durations.tsv:396, 431` | two label rows each — via `regenerate-shard-manifest.py --incremental --write` |
| `.github/CODEOWNERS:26-27, 33-34` | four `@deruelle` rows |
| `scripts/ci-pr-affected-audit.accept.tsv:1806` | one accept row (`scripts/followthroughs/ci-draft-light-soak-9728` × `.github/workflows/ci.yml`) — prune per the audit, a stale row is `census-degraded` |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt:459-460, 477` | three count rows (8/5/18) — via `--write-baseline` regen |
| `.claude/hooks/grep-q-pipe-guard.test.sh:2205` | one exemption-table row keyed to the deleted `.test.sh` — delete the row |
| `scripts/sweep-followthroughs.sh:61` | comment names the probe among timed-out runs — REWORD to drop the basename (the tombstone names the issue, e.g. "the since-retired #9728 soak"), so the residual-reference grep is a clean zero; the measurement itself stays |
| `scripts/sweep-followthroughs.test.sh:1656, 1735` | comments cite the probe as the exit-3 example and a `/pulls` reader — re-attribute to a surviving probe (e.g. `ci-push-dedupe-soak-9512.sh`), dropping the basename |
| `.github/workflows/scheduled-followthrough-sweeper.yml:68` | comment names the probe among the four slow probes justifying `timeout-minutes: 30` — REWORD to drop the basename (keep the ceiling: surviving probes still need it) |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt:147` | dated history note naming the suite — REWORD the basename to an issue-number tombstone if `--write-baseline` preserves the note (the residual grep covers `plugins/`) |
| `knowledge-base/engineering/architecture/decisions/ADR-276-*.md`, `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md`, learnings, archived plans/specs | historical record — NO EDIT |

No `AFFECTED_*_PATHS` entry in `scripts/lib/test-affected-paths.sh` names either file (grep verified); no `scripts/ci-oracle-lane-suites.txt`/`ci-oracle-lane-legs.tsv` row names either; the sweeper discovers probes from tracker directives, and the tracker is closed — no registry edit needed there.

### Learnings applied

- `knowledge-base/project/plans/archive/20261107-124733-2026-11-07-chore-retire-ratchet-observation-window-probe-plan.md` — the direct retirement precedent: live re-census exceeds the RETIREMENT clause's named sites; stale accept rows are `census-degraded`; re-pin in the same commit; verify with a residual-reference grep.
- `knowledge-base/project/learnings/2026-10-13-a-lint-anchored-on-the-verdict-word-*.md` — marker/lint anchoring traps in this probe family.
- Issue #12418 body — the measured defect, the two-hit signature on #12376, and the #12329 same-class precedent.

## Problem Statement / Motivation

**Deliverable 1 — the stale diff base (#12418).** The `oracle-selection` job decides once per `pull_request`/`merge_group` run whether every changed path is oracle data, and on `oracle_only` it lets five heavy `test` legs skip while `oracle-index-check` runs the oracle-validation manifest instead. Its pull_request diff is `git diff HEAD^1 HEAD` — but `HEAD^1` on a merge ref is the base tip *at merge-ref computation time*, and GitHub does not rebuild the ref when `main` advances. A PR branch that merges `main` carries newer main-side commits; diffing from the stale first parent re-counts them as the PR's own changes. When the re-counted paths sit on the oracle surface the classifier reports `oracle_only=true` on a diff that is not an oracle repair — and since `CI_ORACLE_LANE=on` (re-activated by merged PR #12410), each misfire now pays the K=5 `oracle-index-check` manifest (~30-min legs, ~65 min serial measured) *and* can red-light the PR's `test` aggregate. Measured: run 42459010986 on docs-only PR #12376 classified `files=6 reason=oracle oracle_only=true`, cancelled at the bound; the same signature hit twice and only cleared on a rebase.

**Deliverable 2 — the prescribed retirement.** Tracker #9728 closed on a PASS (34 distinct light pushes over 28 days) and `S3-EXIT-CENSUS` is posted, so the RETIREMENT clause in `scripts/followthroughs/ci-draft-light-soak-9728.sh:69-72` fires for BOTH the probe and the census instrument it names. A retired suite that survives as dead registrations is worse than a live one: a stale accept row is `census-degraded` (exit 2) in the affected-index ratchet, generated shard/duration rows price a suite that cannot run, a CODEOWNERS line routes review on a nonexistent path, and the fixture baseline's row-by-row equality fails closed on a missing file. Every registration must retire in the same commit.

## Proposed Solution

**D1 — derive `diff_base` from the merge-base, keep everything else.** In `scripts/ci-oracle-lane.sh` guard (2a), after the two-parent shape validates (`h == GITHUB_SHA`, `p2 == PR_HEAD_SHA`), resolve the live base and compute `diff_base` as the merge-base of the PR head against it:

- New env inputs in the `oracle-selection` step (`ci.yml`): `PR_BASE_SHA: ${{ github.event.pull_request.base.sha }}` and `PR_BASE_REF: ${{ github.event.pull_request.base.ref }}` — all inputs through `env:` per the job's existing contract.
- Resolution order inside the driver: (i) if `PR_BASE_SHA` is 40-hex and `git rev-parse --verify --quiet "${PR_BASE_SHA}^{commit}"` resolves in the fetch-depth-0 checkout, use it as the base ref; (ii) else `git fetch --no-tags --quiet origin "$PR_BASE_REF"` (guarded: fetch failure is fail-closed — same precedent as `oracle-index-check`'s "Fetch origin/main" step) and use `FETCH_HEAD`; (iii) `diff_base="$(git merge-base HEAD^2 "$resolved")"` — an empty/failed merge-base is fail-closed (`reason=<named>` → `oracle_only=false`, full battery). A `git fetch` inside the driver must be reachable-or-nothing: the guard suite replays the step in a bare sandbox where fetch exits 128, which is exactly the fail-closed arm (the arm exists; the tests exercise it via fixtures with file:// origins or an injected failure).
- `diff_head="HEAD"` stays. `base_sha`/`head_sha` outputs keep their audit semantics: `head_sha` stays `$p2`; `base_sha` emits the resolved merge-base — the value the diff actually ran against (see Decisions; no workflow consumes it).
- The (2a) shape guard, fork guard, re-run guard, switch gate and every downstream consumer (`git diff` listing, `-U0` index extent diff, `git show $diff_base:$ORACLE_INDEX`) are untouched — the merge-base SHA is an ancestor of `p2`, always resolvable in the checkout.
- The driver-source line `base="HEAD^1"` in `ci.yml` (~494) stays — per #12329, first-parent sourcing guards the classifier tree, a different invariant.
- Header doc line 41 (`base_sha ... pull_request: HEAD^1`) and `scripts/ci-oracle-lane.test.sh` expectations update to the new derivation; runbook `ci-oracle-lane.md` §manual replay updated to `merge-base(p2, base)..HEAD`.

**D2 — atomic retirement of both instruments.** `git rm` the four files; excise the two `run_suite` blocks (comment + line) in `scripts/test-all.sh`; regenerate the two suite TSVs via `python3 scripts/regenerate-shard-manifest.py --incremental --write`; delete the four CODEOWNERS rows; prune the stale accept row via the audit's own stale-report; regenerate `fixture-relative-assert.baseline.txt` via `--write-baseline`; delete the `grep-q-pipe-guard.test.sh` exemption row; re-attribute the stale comments in `scripts/sweep-followthroughs{,.test}.sh`, `.github/workflows/scheduled-followthrough-sweeper.yml` and the baseline's history note by dropping the basename (issue-number tombstone `#9728`), so the residual-reference grep returns a clean zero on live surfaces. Sweeper permissions and the `timeout-minutes: 30` ceiling stay — surviving probes still need both (precedent from the #10865 retirement: re-attribute only comments that describe *live* consumers).

## Technical Considerations

- **Why merge-base of `HEAD^2` against the live base ref, not `HEAD^1`:** `HEAD^1` freezes at merge-ref computation; the merge-base recomputes against the base as it exists at run time — identical to GitHub's three-dot `base...head` semantics, so the diff covers exactly the PR's own delta. For a linear branch (no main merge), merge-base(`p2`, base) == `p1`'s descendant chain head the branch forked from — when the merge ref is fresh the results coincide, so the fix is a strict improvement, not a behavior swap.
- **Why not `pull_request.base.sha` directly as the diff base:** the payload SHA is the base tip at event time — fresher than `HEAD^1` but still capturable stale; `merge-base(p2, base.sha)` self-corrects (a stale base.sha that is already an ancestor of `p2` yields itself — still stale). The merge-base against the *live* base ref is the only derivation that cannot freeze. `base.sha` is used only as the zero-cost candidate the verify step tries first, never trusted as the diff base itself.
- **Fail-closed surface (ADR-276's design contract):** every new resolution step returns 0 with a named `reason` on failure — a mis-resolved base must never produce a partial classification. New reason tokens (e.g. `base_fetch`, `no_merge_base`) join the driver's reason grammar; the notice schema is unchanged.
- **Race discipline (operator-accepted):** #12434 and #12475 also edit `ci.yml`; #7390 races the suite TSVs. Edits stay tight and comment-anchored: the oracle env additions append to the existing env block, the TSV regen touches only the two removed labels (sticky-LPT keeps incumbents), and no refactors ride along.
- **Live-session warning honored:** nothing under `plugins/soleur/` is edited except the generated `fixture-relative-assert.baseline.txt` regen — required because the baseline pins deleted-file counts and would fail closed otherwise.
- **NFR:** no runtime/user-facing NFR affected; CI-cost NFR is the point of the fix (a false `oracle_only` pays ~30-min × K legs).
- **Retirement precedent:** footprint/disposition/verification shape follows the merged #10865 retirement plan (linked in References) — same census-first, atomic-deletion, dead-path-ratchet discipline.
- **Merge-base precedent (deepen §4.4):** the derivation is not novel — `scripts/check-backstop-revision.sh:64` resolves `git merge-base "origin/${BASE_REF}" HEAD`, `scripts/lib/legal-base-ref.sh:64-70` resolves `git merge-base HEAD "$base_sha"` with fail-closed error handling, and `scripts/test-all.sh:2941` diffs `origin/main...HEAD` for its affected set. The fix follows the same shape: resolve a live base ref, take the merge-base, fail closed on any step.

### Gates evaluated

- **Observability (2.9):** Files-to-Edit sit under `scripts/`, `.github/`, `.claude/hooks/`, `plugins/soleur/test/` (baseline regen) and `knowledge-base/` — none under plan 2.9's `apps/*/server|src|infra` or `plugins/*/scripts` path list, but deepen-plan Phase 4.7's trigger is the broader non-pure-docs test, so a compliant `## Observability` section is emitted above. The lane's own telemetry (`SOLEUR_ORACLE_LANE` notice, `reason=` grammar, step summary) is the observability surface and is preserved; new fail-closed reasons land in that existing grammar.
- **IaC (2.8):** skipped — no new infrastructure, service, secret, or host.
- **Encryption (2.11):** skipped — no persistent store or new connection.
- **Task Design (2.9.3):** skipped — no new autonomous-task surface; the sweeper keeps discovering probes from live tracker directives.
- **Soak enrollment (2.9.1):** skipped — this plan *closes* a soak; no new time-gated criterion is created.
- **GDPR (2.7):** skipped — no regulated-data surface; the deleted probes read GitHub Actions metadata only.
- **Architecture / ADR-C4 (2.10):** no new architectural decision — a bug fix on an existing surface plus a machinery lifecycle step its own RETIREMENT clause prescribes. ADR-276 stays append-only; a dated amendment note recording the diff-base correction (#12418) rides along so the recorded authority matches the shipped derivation.
- **Product/UX (2.5 Step 2):** NONE — no UI-surface file in the Files lists (mechanical override not fired).
- **Scoped advisor consult (4.5) + plan-review panel + domain leaders:** not spawned — no Task/Agent tool in this pipeline subagent context (sequential-fallback disclosure recorded in Research Insights).
- **Skill description budget (1.8):** skipped — no `SKILL.md` `description:` edit is a candidate.
- **Network-outage checklist (1.4):** no trigger pattern matched.
- **Community discovery (1.5):** skipped — bash/GitHub-Actions surface, no stack gap.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst case is a wrong `oracle_only` verdict (a PR pays the full battery it should have skipped, or an oracle-repair PR's `test` aggregate reds) or a red `test-scripts` shard on a missed retirement registration.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure — the lane reads only local git state and emits fixed-token outputs; the deleted probes are read-only GitHub metadata consumers.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches CI machinery and deletes read-only probes; no user-facing artifact, data store, or credential surface changes.
- `threshold: none, reason:` the diff touches `.github/workflows/ci.yml` and `scheduled-followthrough-sweeper.yml` (secrets-bearing paths under preflight's sensitive regex) but adds only env passthrough of already-public payload fields and leaves sweeper permissions untouched.

## Observability

The lane's own telemetry is the observability surface this fix must preserve and extend; the retirement half is deletion-only and creates no new surface.

```yaml
liveness_signal:
  what:            # SOLEUR_ORACLE_LANE ::notice line per pull_request/merge_group run (event/switch/locked/attempt/files/reason/oracle_only/would_skip/active) plus the job's step summary
  cadence:         # per CI run (only while vars.CI_ORACLE_LANE is non-empty)
  alert_target:    # GitHub Actions run annotations on the PR
  configured_in:   # .github/workflows/ci.yml oracle-selection job + scripts/ci-oracle-lane.sh notice emit
error_reporting:
  destination:     # GitHub Actions job conclusion + ::notice annotation stream
  fail_loud:       # fail-closed defaults (oracle_only=false) force the full battery; a red oracle-index-check or test aggregate is the loud failure
failure_modes:
  - mode:          # stale-base misfire (the defect this fixes)
    detection:     # reason=oracle with files=<N> on a diff the PR did not author — the measured signature on run 42459010986
    alert_route:   # PR author / operator reading the run
  - mode:          # unresolved live base (payload SHA missing AND fetch fails, or empty merge-base)
    detection:     # new named reason= tokens (base_fetch / no_merge_base) in the SOLEUR_ORACLE_LANE notice with oracle_only=false
    alert_route:   # PR author / operator reading the run
logs:
  where:           # GitHub Actions step output + GITHUB_STEP_SUMMARY for the oracle-selection job
  retention:       # Actions run log retention (repo default)
discoverability_test:
  command:         grep -q 'merge-base' scripts/ci-oracle-lane.sh && printf 'ok\n'
  expected_output: ok
```

## Guard Contract

The oracle-selection classifier is a gate whose diff window this fix redraws; the mutation matrix below is written against the design, exercised by the `ci-oracle-lane.test.sh` fixture suite.

### Guard 1 — pull_request diff base is the live merge-base

**Property.** On `pull_request`, the diff the classifier surfaces covers exactly the PR's own delta: `diff_base` resolves to `merge-base(HEAD^2, <live base ref>)`, never the merge ref's frozen first parent, and every failure to resolve emits fail-closed defaults.

**Assembly.** The single chokepoint is guard (2a) in `scripts/ci-oracle-lane.sh` `run()`: `diff_base`/`diff_head` are locals assigned only in the (2a) arm (pull_request) and the (2b) arm (merge_group, untouched), and every downstream read (`git diff` listing, `-U0` index diff, `git show $diff_base:`) consumes only those locals. The env injection point is the `oracle-selection` step's `env:` block in `ci.yml`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert `diff_base` to literal `HEAD^1` | RED — the merge-carrying-branch fixture classifies `oracle_only=true` on main-side churn |
| 2 | Compute `git merge-base HEAD^1 HEAD` (wrong operands — resolves the frozen parent) | RED — same fixture fails: the property is about the *live* base, not either parent |
| 3 | Drop the merge-base resolution entirely; `diff_base` empty while the diff still runs | RED — a suite row asserting `diff_base` resolves (non-empty, ancestor of `p2`) fails, and `git diff ""` rc fails closed |
| 4 | Swallow the `git fetch`/merge-base failure and continue with an unset base | RED — the injected-failure fixture must emit the named fail-closed reason, not classify |
| 5 | Emit `oracle_only=true` path that skips the (2a) shape guard (guard's own dispatch) | RED — existing bad-shape fixtures (octopus, non-merge, wrong head) already RED any dispatch that reaches classification without the shape |
| 6 | Fixture where the branch merges main AND adds a code file | must-PASS (non-canonical input): `oracle_only=false` — proves the gate is not a reject-everything stub |
| 7 | Fixture: fresh merge ref on a linear branch | must-PASS: merge-base result equals the old `HEAD^1` result — the fix is a strict improvement, no regression on the common case |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. (Sweep assessed all 8 domains inline; the mechanical UI-surface override did not fire — no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx` or UI-surface term in the Files lists.)

## Open Code-Review Overlap

2 open scope-outs touch planned files:

- **#7942** ("Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate") names `scripts/test-all.sh`. **Disposition: acknowledge** — this plan deletes `run_suite` blocks, not mutation-battery registration; different surface, remains open.
- **#3321** ("review: add CODEOWNERS coverage for knowledge-base/project/learnings/ subtree") names `.github/CODEOWNERS`. **Disposition: acknowledge** — this plan deletes four rows, doesn't restructure coverage; remains open.

## Implementation Phases

1. **Oracle fix + tests.** `ci.yml` env additions; `ci-oracle-lane.sh` merge-base resolution with fail-closed reasons; `ci-oracle-lane.test.sh` merge-carrying fixture + reason rows; header/runbook doc updates; ADR-276 dated amendment note.
2. **Retirement deletion.** `git rm` the four files; excise `run_suite` blocks; delete CODEOWNERS rows, the accept row, the guard-table row; re-attribute the two stale test comments.
3. **Regenerations.** `regenerate-shard-manifest.py --incremental --write`; `fixture-relative-assert.test.sh --write-baseline`; prune the accept row per the audit's stale report.
4. **Local verification** — the command battery in Acceptance Criteria.

## Files to Delete

- `scripts/followthroughs/ci-draft-light-soak-9728.sh`
- `scripts/followthroughs/ci-draft-light-soak-9728.test.sh`
- `scripts/ci-draft-push-census.sh`
- `scripts/ci-draft-push-census.test.sh`

## Files to Edit

- `scripts/ci-oracle-lane.sh` — (2a) arm: `diff_base` from merge-base; `base_sha` emits the merge-base; header line 41; new fail-closed reasons
- `scripts/ci-oracle-lane.test.sh` — `drive()` env + merge-carrying fixture + new assertion rows (mutation matrix above)
- `.github/workflows/ci.yml` — `oracle-selection` env: `PR_BASE_SHA`/`PR_BASE_REF` (+ anchored comment); no other job touched
- `scripts/test-all.sh` — remove two `run_suite` blocks (comment + line)
- `.github/CODEOWNERS` — remove four rows (26-27, 33-34)
- `scripts/ci-pr-affected-audit.accept.tsv` — remove the stale row at 1806 (per the audit's stale report)
- `.claude/hooks/grep-q-pipe-guard.test.sh` — remove the exemption row at 2205
- `scripts/sweep-followthroughs.test.sh` — re-attribute comments at 1656, 1735 to a surviving probe, dropping the basename
- `scripts/sweep-followthroughs.sh` — reword the ceiling-rationale comment at 61 to drop the basename (issue-number tombstone)
- `.github/workflows/scheduled-followthrough-sweeper.yml` — reword the slow-probes comment at 68 to drop the basename
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — reword the dated history note at ~147 if `--write-baseline` preserves it
- `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` — manual replay recipe → merge-base derivation; reason-table additions
- `knowledge-base/engineering/architecture/decisions/ADR-276-*.md` — dated amendment note recording the #12418 diff-base correction

## Files Regenerated (not hand-edited)

- `scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv` — `python3 scripts/regenerate-shard-manifest.py --incremental --write`
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "derive the base from the fetched base ref / merge-base (`git merge-base` of the merge ref's parents against `origin/main`, or `github.event.pull_request.base.sha` verified resolvable), not from HEAD^1 topology" [issue #12418] | D1: `ci-oracle-lane.sh` (2a) arm merge-base resolution; `ci.yml` env additions | mapped |
| 2 | "Keep the (2a) merge-ref shape guard; make `diff_base` the merge-base SHA and keep `base_sha`/`head_sha` semantics identical downstream" [issue #12418] | (2a) guard untouched; `diff_base` = merge-base; `base_sha`/`head_sha` audit semantics kept | mapped |
| 3 | "delete `scripts/followthroughs/ci-draft-light-soak-9728.sh`, its `.test.sh`, the run_suite line in `scripts/test-all.sh`, the rows in `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv`, and the CODEOWNERS lines" [brief, quoting RETIREMENT] | D2 deletion + regen phases | mapped |
| 4 | "apply the same retirement to `scripts/ci-draft-push-census.sh` + its `.test.sh` + the same registrations" [brief, quoting the census header] | D2 deletion + regen phases | mapped |
| 5 | "Enumerate ALL registrations before deleting (grep for both basenames across the repo including workflow YAML, docs, and knowledge-base references — update doc references or leave a tombstone note per repo convention)" [brief] | Live registration census table; per-site dispositions | mapped |
| 6 | "keep the edits tight and comment-anchored to reduce conflict surface" [brief] | Env-block-only ci.yml edit; regen-only TSV changes; no refactors | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `base_sha` emits the merge-base value | "keep `base_sha`/`head_sha` semantics identical downstream" | inferred — the output is audit-only (zero workflow consumers); emitting the SHA the diff actually ran against preserves "the base" semantics downstream readers use to replay |
| New env `PR_BASE_SHA`/`PR_BASE_REF` in `ci.yml` | "or `github.event.pull_request.base.sha` verified resolvable" / "the fetched base ref" | asked (both named sources need env wiring) |
| Runbook + ADR-276 doc updates | "update doc references or leave a tombstone note per repo convention" | asked |
| Re-attribute `sweep-followthroughs.test.sh` comments; keep sweeper-yml history | "update doc references or leave a tombstone note per repo convention" | inferred — repo convention (the #10865 retirement) re-attributes comments describing LIVE consumers and keeps dated measurements |
| ADR-276 amendment note | "update doc references" + `wg-architecture-decision-is-a-plan-deliverable` (recorded authority must not lag the shipped derivation) | inferred — justification: the ADR's scope-bound text names `HEAD^1` base; an append-only dated note keeps the record true |
| New fail-closed `reason=` tokens | "Every guard fails closed" (ADR-276 design contract the issue's fix must not weaken) | inferred — justification: a resolution failure without a named reason is an unclassifiable telemetry hole |

### Split Assessment

- Subsystems touched: 4 — `scripts/`, `.github/`, `.claude/`, `plugins/` (baseline only) + `knowledge-base/` docs
- Planned files: 13 edited + 4 deleted + 3 regenerated | Estimated changed lines: ~2,600 (dominated by the two deleted suites ~114K bytes ≈ 1,900 lines plus fixture/test additions)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines → over the file-count and line-count thresholds
- Recommendation: **single PR** — the brief prescribes one PR ("Two in-scope deliverables in ONE plan and ONE PR"); the line count is dominated by deletions of two self-contained suites and the coupling is administrative (one CI-lever arc, one commit-class operation). A split would leave the accept row / shard rows orphaned between PRs — the failure mode the atomic-retirement precedent exists to prevent.

## Acceptance Criteria

- [ ] `scripts/ci-oracle-lane.sh` (2a) arm computes `diff_base` as `git merge-base` of the PR head against the resolved live base (`PR_BASE_SHA` verified resolvable, else fetched `PR_BASE_REF`); the literal `diff_base="HEAD^1"` is gone; the two-parent shape guard, fork/re-run/switch guards and `diff_head="HEAD"` are unchanged.
- [ ] Every new resolution failure (unresolvable payload SHA AND failed fetch, or empty merge-base) emits the fail-closed defaults with a named `reason=` — verified by a suite row per arm.
- [ ] A merge-carrying-branch fixture in `scripts/ci-oracle-lane.test.sh` fails on the old `HEAD^1` derivation and passes on the merge-base derivation (the fixture's `git diff merge_base HEAD` names no main-side path).
- [ ] `base_sha` output emits the resolved merge-base SHA and `head_sha` stays `HEAD^2`; the driver header and the runbook's manual-replay recipe say so.
- [ ] `ci.yml` `oracle-selection` gains `PR_BASE_SHA`/`PR_BASE_REF` env lines and nothing else in the job changes; the `base="HEAD^1"` driver-source line is untouched.
- [ ] `git rm` removes all four files; `rg -n 'ci-draft-light-soak-9728|ci-draft-push-census' scripts/ .github/ .claude/ plugins/` returns zero hits (every live comment carries only the `#9728` issue tombstone; `knowledge-base/**` historical records are out of grep scope by convention).
- [ ] `scripts/test-all.sh` has no `run_suite` line for either label; `bash scripts/lint-orphan-test-suites.sh` exits 0.
- [ ] `git diff` on `suite-shard-legs.tsv`/`suite-durations.tsv` removes exactly the two label rows each (regen output reviewed — no unrelated rebalance).
- [ ] `CODEOWNERS` drops the four rows; `bash scripts/sweep-followthroughs.test.sh` passes after comment re-attribution.
- [ ] `scripts/ci-pr-affected-audit.accept.tsv` holds no row for either basename and the ratchet/audit reports no `stale` rows.
- [ ] `fixture-relative-assert.baseline.txt` regenerated in the same commit; `bash plugins/soleur/test/fixture-relative-assert.test.sh` green.
- [ ] `bash scripts/ci-oracle-lane.test.sh` green end-to-end (all pre-existing rows plus the new merge-base rows).

## Test Scenarios

- **Given** a fixture merge ref whose `HEAD^1` is a stale base tip and whose PR head merged a newer `main` carrying oracle-surface paths, **when** the driver runs with `PR_BASE_SHA`/`PR_BASE_REF` env, **then** `oracle_only=false` (or true only if the PR's own delta is in-surface) and `files=` counts the PR's own delta only — `unit` (fixture repo, hermetic `drive()`).
- **Given** the payload `PR_BASE_SHA` does not resolve in the checkout and `git fetch` fails (injected), **when** the driver runs, **then** fail-closed: `oracle_only=false`, named `reason`, defaults emitted — `unit`.
- **Given** a linear PR branch (no main merge) with a fresh merge ref, **when** the driver runs, **then** classification identical to the pre-fix run — `unit` (regression row).
- **Given** the deleted suites, **when** `bash scripts/test-all.sh --list` (or shard select) runs, **then** neither label appears and no `run_suite` references a missing file — `integration`.
- **Given** the regenerated baseline/TSVs, **when** `fixture-relative-assert.test.sh`, `lint-orphan-test-suites.sh`, the affected-index ratchet (`--print-baseline`/audit stale report) and `scripts-shard-totality` run, **then** all green — `integration`.
- Residual-reference sweep: `rg -n 'ci-draft-light-soak-9728|ci-draft-push-census' scripts/ .github/ .claude/ plugins/` → zero hits — `integration`.

## Context / Risks

- **Fetch inside a 2-minute step:** the `git fetch --no-tags origin "$PR_BASE_REF"` fallback adds one network op to a `timeout-minutes: 2` step — bounded by the step timeout; failure is fail-closed (full battery), the safe direction.
- **Fork PRs:** the fork guard (`HEAD_REPO == GH_REPO`) runs after (2a); on a fork the classification already returns before the merge-base fetch matters — but the fetch itself must still fail closed on a fork's base ref name (base ref is always the upstream's, resolvable).
- **merge_group untouched:** (2b) semantics (`MERGE_GROUP_BASE_SHA..HEAD_SHA`, batch fail-closed) are unchanged by design.
- **Degenerate merge-base shapes:** a criss-cross history can yield multiple merge bases — `git merge-base` prints one best common ancestor, which suffices for a two-dot diff; an empty result (unrelated histories) is the fail-closed arm, not a guessed base.
- **ADR-276 amendment is append-only:** one dated note naming #12418 and the derivation change; no Decision rewrite.

## References

- Issue: #12418 (this fix), #9728 (retired tracker), #11556 (epic), #9721 (stage series), #12410 (lane re-activation / K=5 legs), #12393 (manifest bound measurement), #12329 (`pull_request.base.sha` same-class precedent), #12274 (depth-1 base-resolution sibling), #12376 (measured misfire PR), run 42459010986
- ADR: ADR-276 (lane authority), ADR-240 (shard manifests), ADR-262 (path gating)
- Precedent plan: `knowledge-base/project/plans/archive/20261107-124733-2026-11-07-chore-retire-ratchet-observation-window-probe-plan.md`
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md`, `followthrough-convention.md`
