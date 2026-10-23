---
title: "fix(ci): skip data-read-only infra roots in the PR terraform-plan matrix; tolerate verified resolver arms in go-session-gates H3"
type: fix
date: 2026-10-23
slug: fix-ci-machinery-infra-plan-and-go-gates-h3
branch: feat-one-shot-10715-10714-ci-machinery
issue: 10715
closes: [10715, 10714]
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix(ci): skip data-read-only infra roots in the PR terraform-plan matrix; tolerate verified resolver arms in go-session-gates H3

## Enhancement Summary

**Deepened on:** 2026-10-23
**Sections enhanced:** gates verified + observability probe corrected + self-demonstration AC sharpened
**Research agents used:** none — this harness has no Task/spawn tool; repo research, learnings scan, ADR check, and all deepen halt-gates were run inline by the planning agent

### Key Improvements (deepen pass)

1. `discoverability_test.command` rewritten after the sharp-edges pass — the first draft used `bash -c '… && …'` which Check 10's shell-active byte reject (`&`) would have failed at ship; now `rg -l . <sentinel>` proving existence AND non-emptiness in one probe.
2. AC7/AC8 sharpened to note this PR's own run is the end-to-end proof: the sentinel lands under `apps/cla-evidence/infra/**`, so `validate` runs and the `plan` leg is absent by construction on this very PR.
3. Verified every cited issue/PR number live: #10715 + #10714 OPEN (no closing PRs), #10679 MERGED 2026-10-20, #8401/#7624/#4012/#7299/#6454 CLOSED, #8209 OPEN, #8919 MERGED. Rule-id citations verified against `AGENTS.md` (`wg-use-closes-n-in-pr-body-not-title-to` active).
4. Confirmed merge-blast-radius: no `apply-*.yml` workflow targets `apps/cla-evidence/infra` — merging mutates no production; the workflow's `paths:` filter does re-trigger Infra Validation on this diff (self-demonstrating).

### New Considerations Discovered

- `detect-changes`' `dirs` step output `has-doppler-token` vs `plan_directories` naming style differs (`kebab` output name vs `snake` step key) — the plan mirrors the existing `outputs:` indirection rather than inventing a new convention.
- The `plan` job's `if:` retains `github.event_name == 'pull_request'` and the `check-secrets` conjunct unchanged; only the directories conjunct is repointed — the push/dispatch arms still derive `plan_directories` but nothing consumes it there.
- H3's allowlist deliberately rejects a hypothetical `verified=true` on `none`/`devin-cache-nomatch` (structurally impossible today) so a future resolver bug surfaces as a test failure, not a silent pass.

### Deepen gate ledger

| Gate | Result |
|------|--------|
| 4.4 precedent-diff | pass — jq/sed/jq-aggregation pipeline is the repo's own precedent (`detect_infra_dirs`); no SQL/atomic-write/lock pattern |
| 4.45 verify-the-negative | pass — negative claims (`no consumer reads`, `fails identically on main`, `cannot ever succeed`) each grepped during research |
| 4.5 network-outage | n/a — no trigger tokens |
| 4.55 downtime & cutover | n/a — no serving surface touched |
| 4.6 User-Brand Impact | pass — `none` + scope-out reason for the two sensitive paths |
| 4.7 Observability | pass — 5 fields, `rg` allowlisted, literal `expected_output`, <15s |
| 4.8 PAT-shape | pass — grep clean after Sharp-Edge rewording |
| 4.9 UI-wireframe | n/a — no UI-surface paths |
| 4.10 Encryption posture | n/a — no `.tf`, store, or new connection |
| 4.11 Guard Contract | pass — `lint-guard-contract.py` green (2 entries, structural assemblies) |
| 4.12 Scope Check | pass — 1 unfenced section, all rows mapped/justified, `Recommendation: single PR` |

Two small CI/test-machinery defects in one PR — both `meta/machinery`,
`domain/engineering`, `type/bug`, both surfaced 2026-10-20, both
"Fix-Size: small" per their issues. Spec lacks valid `lane:` — defaulted to
cross-domain (TR2 fail-closed).

- **#10715** — `.github/workflows/infra-validation.yml`'s `plan` matrix leg for
  `apps/cla-evidence/infra` fails with Cloudflare error 9109 (`Unauthorized to
  access requested resource`) on `data.cloudflare_api_token_permission_groups.all`
  (`apps/cla-evidence/infra/iam.tf`). The step runs `doppler run … terraform plan
  -refresh=false`; `-refresh=false` skips managed-resource refresh but data
  sources are still read, so the permission-groups listing hits the real
  Cloudflare API with a credential that cannot list permission groups. The leg is
  not in the required-status contexts, but it reds every PR that touches that
  root.
- **#10714** — `plugins/soleur/test/go-session-gates.test.sh` row H3 fails 3 of
  241 assertions on Devin-CLI hosts: H3 expects
  `gate=<g> source=plugin-root-token verified=true`, but Devin-CLI sessions
  resolve the plugin via the `devin-cache` arm (no `CLAUDE_PLUGIN_ROOT` env), so
  the markers read `source=devin-cache`. Fails identically on `main` —
  environmental, not a regression.

## Research Insights

**Premise validation.** Both cited issues are `OPEN` with no
`closedByPullRequestsReferences` (`gh issue view 10715/10714`, 2026-10-23). PR
#10679 (the surfacing PR) is MERGED 2026-10-20. The cited artifacts all exist on
this branch: `.github/workflows/infra-validation.yml` `plan:` job (matrix
`directory: ${{ fromJSON(needs.detect-changes.outputs.directories) }}`, step
`doppler run --preserve-env=… --name-transformer tf-var -- terraform plan
-refresh=false`), `apps/cla-evidence/infra/iam.tf` carrying
`data "cloudflare_api_token_permission_groups" "all" {}`, and
`plugins/soleur/test/go-session-gates.test.sh` row H3 (three
`want_in … "gate=${g} source=plugin-root-token verified=true"` assertions over a
real `claude -p --plugin-dir` spawn). Nothing cited is stale.

**Property list (Phase 0.6b).**

- P1: a PR touching `apps/cla-evidence/infra/**` produces a green Infra
  Validation run — no plan leg that cannot succeed under the Tier-A credential
  set.
- P2: the exclusion is structural and self-declaring — a root opts out where it
  lives, travels on rename, and the exclusion is visible in the run log and the
  diff.
- P3: offline coverage is retained — `validate` (fmt / `terraform validate` /
  `*.tftest.hcl` / `main.test.sh`) keeps running for the excluded root.
- P4: `go-session-gates.test.sh` passes on Devin-CLI hosts that carry a `claude`
  binary (241 assertions, floor holds).
- P5: H3 still proves real-harness contact — a missing, unverified, or
  unrecognized-arm RESOLVE line still fails.

**Cut list (Phase 0.6b).** No proposed mechanism buys an already-covered
property: the workflow has no existing root-exclusion mechanism (`directories`
is consumed verbatim by `validate`, `plan`, `registry-userdata-budget`,
`inngest-userdata-budget`), so the `plan_directories` derivation is new but
minimal — one filter in the one job that already owns directory derivation.
Rejected heavier alternatives are in *Alternative Approaches Considered*.

**Relevant files.**

- `.github/workflows/infra-validation.yml` — `detect-changes` job derives
  `directories` from the PR/push/dispatch diff (three arms converging before
  `printf 'directories=%s\n'`); `plan` job (pull_request-only) consumes it.
- `plugins/soleur/test/infra-validation-detect.test.sh` — the committed
  byte-mirror test of the `detect_infra_dirs()` pipeline (#4012 heritage).
- `plugins/soleur/test/go-session-gates.test.sh` — H3 block; assertion floor
  `MIN_ASSERTIONS=239` skipped / 241 with H3 running.
- `plugins/soleur/commands/go.md` — the resolver fences H3 exercises; documents
  `source=devin-cache verified=true` as "the healthy Devin path" and
  `devin-cache-nomatch`/`none` as failure states.
- `apps/cla-evidence/infra/{main.tf,iam.tf,variables.tf}` — provider
  `cloudflare` uses `api_token = var`-supplied credential; `iam.tf` data source
  resolves R2 permission-group names at plan time.
- `apps/cla-evidence/infra/main.test.sh` — per-app lint hook the `validate` job
  already executes for this root.

**Applicable learnings.**

- `2026-07-02-self-validating-regression-when-runtime-capability-unverifiable-locally.md`
  — when a runtime value is environment-dependent, classify on the
  *environment-dependent* field and keep the deterministic property blocking:
  exactly the H3 shape (assert `verified=true`; the arm name is env data).
- `2026-03-21-ci-terraform-plan-workflow.md` — Doppler/`--name-transformer
  tf-var` and `$GITHUB_ENV` heredoc patterns this workflow already embodies.
- `2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md` — the
  detect pipeline is already grep-based per this learning; the filter extends
  it in kind.

**Conventions.** `detect-changes` is the single chokepoint for directory
derivation (three event arms converge before outputs); a second output is
additive and safe — no consumer reads `outputs` it does not name. Suite
`infra-validation-detect.test.sh` is the mirror-test contract for that
pipeline. `go-session-gates.test.sh` counts assertions via `ck`; keeping three
`ck` calls in H3 preserves the floor arithmetic (239 skipped / 241 running).

**ADR check (Phase 0.6 item 4).** ADR-241 (credential tiers) records Tier-A as
bounded substitutes and the PR plan as `-refresh=false`; nothing in it requires
every root to plan under Tier A — it *prescribes* least-privilege substitutes,
which favors excluding a root that needs a broader credential over widening
one. ADR-276/ADR-262's job-level `if:` + named-skip-tolerance mechanism is the
CI-gating precedent this plan follows (exclude at derivation, keep the
aggregator honest). No ADR-rejected alternative is being re-proposed. No new
architectural decision (no boundary/substrate/ownership change) → Phase 2.10
does not fire.

**External research:** skipped — both fixes are repo-internal machinery with
the mechanism already established by precedent (`detect-changes` derivation,
`ck`-counted suite rows). The Cloudflare 9109 semantics are stated in the issue
and the provider docs are not load-bearing for the chosen mechanism.

## Problem Statement

- `plan (apps/cla-evidence/infra)` cannot ever succeed on `pull_request`: the
  root's `data.cloudflare_api_token_permission_groups` read calls the
  Cloudflare permission-groups API, and the plan credential cannot list
  permission groups. `validate` already covers the root offline, so the leg
  buys nothing at its current credential scope — it only reds PRs.
- H3 asserts one arm (`plugin-root-token`) when the property it exists to prove
  is "the real harness resolved and verified a root"; the arm is
  environment-dependent by design (ADR-179 A16 added `devin-cache` precisely
  for Devin-CLI hosts).

## Proposed Solution

**Fix A (#10715) — sentinel-scoped plan matrix.**

1. `apps/cla-evidence/infra/.pr-plan-skip` (new, non-empty): a self-declaring
   sentinel whose content is the justification (the 9109 failure, why the
   credential scope is out of Tier-A reach, how to re-enable).
2. `detect-changes` gains a second output, `plan_directories`: the `DIRS`
   array filtered to roots **not** carrying `.pr-plan-skip`, computed once after
   the existing three-arm derivation. Each excluded root also emits an
   `::notice::` line so the exclusion is attributable in the run log.
3. `plan` job consumes `plan_directories` in both places it names
   `directories` today: the `if:` non-empty guard and `matrix.directory`.
   `validate`, `infra-validate-required`, `registry-userdata-budget`,
   `inngest-userdata-budget` and every other consumer keep `directories`
   unchanged.
4. `infra-validation-detect.test.sh` gains a `detect_plan_dirs()` mirror (the
   same sentinel filter over a JSON dir list read from stdin) plus cases:
   sentinel dir excluded, sentinel-free dir kept, all-sentinel input → `[]`,
   `directories` unaffected, and the committed sentinel exists and is non-empty.

**Fix B (#10714) — H3 verified-arm tolerance.**

Replace the three `want_in "$h3_out" "gate=${g} source=plugin-root-token
verified=true"` rows with a per-gate extract-then-classify:

- extract the `SOLEUR_PLUGIN_ROOT_RESOLVE` line for `gate=${g}` (trailing
  space in the grep) from `h3_out`;
- one `ck` per gate (3 total — floor arithmetic unchanged): PASS iff the line
  ends `verified=true` AND `source` is one of the healthy arms
  `{plugin-root-token, grok-env, devin-cache}`; FAIL on a missing line,
  `verified=false`, or an arm outside the set. The pass message carries the
  captured line for forensics.
- Update the H3 comment block: the arm is environment-dependent by design;
  `verified=true` is the invariant, `devin-cache` is the healthy Devin path
  (go.md's own vocabulary).

## Technical Considerations

- `detect-changes` runs after `actions/checkout`, so `[ -f "$d/.pr-plan-skip" ]`
  reads the checked-out tree — the same tree the diff measured, so a PR that
  *adds* the sentinel takes effect on its own run (self-demonstrating on this
  PR: `validate (apps/cla-evidence/infra)` runs, no `plan` leg appears).
- The filter is a shell loop over `jq -r '.[]'` + the `[ -f ]` test +
  `jq -R -s -c` re-aggregation — same toolset the surrounding pipeline already
  uses; no new dependency. `{ … || true; }` idiom preserved so a zero-match
  stays `[]` under any future `pipefail`.
- A skipped root produces no `plan` leg at all (matrix never materializes it) —
  deliberately **not** a per-leg early-exit, which would show a green check
  over a leg that did nothing (the anti-silent-skip class this workflow's
  `infra-validate-required` job exists to kill). Job-level skip on
  `plan_directories == '[]'` is the honest absence: no leg, no verdict claimed.
- Threat note: `.pr-plan-skip` is a visible self-declaration in the PR diff,
  and it cannot dodge `validate` — the worst a malicious root addition earns is
  losing its own live-plan preview. Recorded for the reviewer, not treated as a
  hole.
- H3's accepted-arm set is an allowlist, not "any `verified=true`": a future
  arm is unreviewed until added, and `verified=true` on `none` /
  `devin-cache-nomatch` is structurally impossible today but asserted anyway as
  the negative space.
- Sensitive-path note: `.github/workflows/infra-validation.yml` and
  `apps/cla-evidence/infra/` both match the preflight sensitive-path regex —
  the User-Brand Impact section carries the `threshold: none, reason:` scope-out.

## Files to Edit

- `.github/workflows/infra-validation.yml` — `detect-changes.outputs` +
  `dirs` step (emit `plan_directories` + `::notice::` per excluded root);
  `plan` job `if:` and `matrix.directory` consume `plan_directories`.
- `plugins/soleur/test/infra-validation-detect.test.sh` — `detect_plan_dirs()`
  mirror + sentinel cases + committed-sentinel existence/non-empty row.
- `plugins/soleur/test/go-session-gates.test.sh` — H3 block: extract line per
  gate, allowlist healthy arms, keep 3 `ck`; comment block updated.

## Files to Create

- `apps/cla-evidence/infra/.pr-plan-skip` — non-empty sentinel; content is the
  justification (why this root cannot plan under Tier-A PR credentials, what
  would re-enable it — granting the plan credential
  `API Token Permission Groups:Read`, i.e. the issue's alternative fix).

## Implementation Phases

- **Phase 1 (#10715):** create the sentinel; extend `detect-changes`; repoint
  `plan`; extend `infra-validation-detect.test.sh`; run it green.
- **Phase 2 (#10714):** rewrite the H3 assertion loop + comment; run
  `SOLEUR_GO_GATES_SKIP_H3=1 bash plugins/soleur/test/go-session-gates.test.sh`
  (floor path) green, and the unskipped suite on a `claude`-carrying host if
  available.
- **Phase 3:** full affected-suite run; verify both issues' failure signatures
  are gone (no 9109 leg, no H3 arm fails).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst
  case is a missed CI signal (an infra PR whose plan leg silently never ran) or
  a red suite on a contributor's Devin-CLI host.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — the change *narrows* a credential surface (a root stops
  needing a broader Cloudflare scope in a PR-reachable job); it grants nothing.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** both diffs are verification machinery
  (a workflow filter, a test assertion); no serving surface, credential value,
  or user data moves.
- `threshold: none, reason: the touched sensitive paths (infra-validation.yml,
  apps/cla-evidence/infra/) are CI verification surfaces — the change removes a
  credential-scope dependency rather than adding one, and no production system
  or user artifact is mutated.`

## Observability

```yaml
liveness_signal:
  what: "Infra Validation workflow outcome on PRs touching infra roots — check-run state plus the `::notice::` exclusion line in the detect-changes log"
  cadence: "per workflow run (pull_request / push to main / dispatch)"
  alert_target: "PR check UI (author) + ops email on red main runs"
  configured_in: ".github/workflows/infra-validation.yml — notify-main-failure job emails via notify-ops-email on push-to-main failure"
error_reporting:
  destination: "GitHub Actions check-run + run log; ops email via notify-ops-email (Resend) on main"
  fail_loud: "red `plan (…)` leg or `infra-validate-required` failure on the PR; '[ALERT] Infra Validation failed on main' on push"
failure_modes:
  - mode: "sentinel filter drops a non-sentinel root from plan_directories"
    detection: "plugins/soleur/test/infra-validation-detect.test.sh mirror rows run in the CI battery on every run of the suite"
    alert_route: "CI suite RED → PR author"
  - mode: "a second data-read-only root is added without a sentinel — plan leg reds 9109 again"
    detection: "red `plan (apps/<x>/infra)` leg on the next PR touching that root"
    alert_route: "PR check UI → author adds the sentinel (the mechanism, not a patch)"
  - mode: "H3 arm regression (new arm emits verified=true, or claude -p stops substituting)"
    detection: "go-session-gates.test.sh H3 row fails on the host where it runs"
    alert_route: "CI suite RED → PR author"
logs:
  where: "GitHub Actions run logs (detect-changes `::notice::` names each excluded root)"
  retention: "GitHub default (~90 days)"
discoverability_test:
  command: rg -l . apps/cla-evidence/infra/.pr-plan-skip
  expected_output: apps/cla-evidence/infra/.pr-plan-skip
```

## Guard Contract

### Guard 1 — `.pr-plan-skip` exclusion of the PR plan matrix

**Property.** Every infra root in `detect-changes.directories` fans out the
`validate` matrix, and exactly the subset **without** a `.pr-plan-skip` sentinel
fans out the `plan` matrix — a sentinel root produces no plan leg, and a
sentinel-free root is never filtered.

**Assembly.** The single chokepoint is the `dirs` step in
`.github/workflows/infra-validation.yml`'s `detect-changes` job: all three
derivation arms (pull_request diff, push diff, workflow_dispatch enumeration)
converge into `DIRS` before either output is emitted, and `plan_directories` is
derived from `DIRS` in that same step — no second site may re-derive it. The
only consumers of `plan_directories` are the `plan` job's `if:` guard and
`matrix.directory`; every other consumer (`validate`, `infra-validate-required`,
`registry-userdata-budget`, `inngest-userdata-budget`) keeps `directories`. The
sentinel itself is per-root state inside `apps/*/infra/` (and `infra/*/`), so
the member set is "any directory the derivation can emit", not today's roots.
The mirror rows live in `plugins/soleur/test/infra-validation-detect.test.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | `plan` job matrix reads `needs.detect-changes.outputs.directories` instead of `plan_directories` | RED — the consumer-pinning assertion (grep on the workflow text) fails; a sentinel root re-enters the matrix |
| 2 | The filter step emits `DIRS` unfiltered into `plan_directories` (sentinel check dropped) | RED — mirror case "sentinel dir excluded" fails |
| 3 | A second sentinel-bearing root is added and one is filtered out while another stays | RED — mirror case "mixed input keeps sentinel-free dirs, drops sentinel dirs" must observe BOTH arms in one run (a check that stops at the first member is the defect class) |
| 4 | The filter is applied to `directories` instead of a new output (validate loses sentinel roots) | RED — mirror case "`directories` still contains the sentinel root" fails; validate coverage is the property being preserved |
| 5 | `apps/cla-evidence/infra/.pr-plan-skip` is deleted or emptied | RED — the committed-sentinel existence/non-empty row fails, and the next PR on that root reds 9109 again |
| 6 | (harness) Sentinel-free input produces `plan_directories == directories` | must-PASS — a filter that rejects everything is certified only by must-PASS input |
| 7 | (harness) The mirror `detect_plan_dirs()` is weakened to echo stdin | RED — the suite's own rows fail because expected `[]`/subset values no longer match |

### Guard 2 — H3 verified-arm tolerance

**Property.** Row H3 passes iff the real `claude -p` run emitted, for each of
the three gates, a `SOLEUR_PLUGIN_ROOT_RESOLVE gate=<name>` line ending
`verified=true` on one of the allowlisted arms
`{plugin-root-token, grok-env, devin-cache}`; a missing line, `verified=false`,
or an unlisted arm fails.

**Assembly.** The per-gate loop in `plugins/soleur/test/go-session-gates.test.sh`'s
H3 block over `GATE_NAMES=(readiness cloud-detect session-start)` — the members
are the three delivered gate fences in `plugins/soleur/commands/go.md`, and the
extraction greps `SOLEUR_PLUGIN_ROOT_RESOLVE gate=<name>` with a trailing
space (exact prefix, not a partial gate name) per member. The allowlist is the resolver's own verified arm set; the guard's
dispatch is the `claude -p` spawn plus the extraction, which fails loudly (no
line → FAIL, never SKIP).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | One gate's captured line reads `verified=false` (any source) | RED |
| 2 | One gate's RESOLVE line is absent from `h3_out` entirely | RED — absent is a fail, not a skip |
| 3 | A captured line reads `source=devin-cache-nomatch verified=false` or `source=none verified=false` | RED |
| 4 | A captured line reads `source=<future-arm> verified=true` — an arm not in the allowlist | RED — a new arm is unreviewed until added to the set |
| 5 | The case pattern accepts `verified=` without `=true` (matches `verified=false` by prefix) | RED — the `=true` suffix is load-bearing |
| 6 | (harness) The spawned run emits mixed arms (one gate `plugin-root-token`, another `devin-cache`) all `verified=true` | must-PASS — the tolerance is the feature under test |
| 7 | (harness) `want_in`/`ck`/`pass` decision collapse | RED — covered by the suite's existing L2 decider self-tests |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "fix = grant the plan credential API Token Permission Groups:Read OR scope the matrix step to skip data-read-only roots" [issue #10715] | Phase 1 — `.pr-plan-skip` sentinel + `plan_directories` filter (the second disjunct; first is recorded as the operator-side alternative in the sentinel content) | mapped |
| 2 | "fix = H3 tolerates devin-cache arm or skips when CLAUDE_PLUGIN_ROOT unset" [issue #10714] | Phase 2 — H3 allowlist-of-verified-arms rewrite (the first disjunct) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/infra-validation.yml` edits (`plan_directories` output, `plan` rewiring) | "scope the matrix step to skip data-read-only roots" [issue #10715] | asked |
| `apps/cla-evidence/infra/.pr-plan-skip` create | "skip data-read-only roots" [issue #10715] — the sentinel is the scoping mechanism for that ask | asked |
| `plugins/soleur/test/go-session-gates.test.sh` H3 edit | "H3 tolerates devin-cache arm" [issue #10714] | asked |
| `plugins/soleur/test/infra-validation-detect.test.sh` edit | — | inferred — justification: the suite is the repo's committed mirror-test contract for this exact pipeline (#4012); a detect-changes derivation with no mirror row rots silently — the enforcement contract needs it |
| `::notice::` per excluded root in detect-changes | — | inferred — justification: an excluded root must be attributable in the run log, the same anti-silent-skip contract `infra-validate-required` enforces at job level |

### Split Assessment

- Subsystems touched: 3 — `.github` (workflow), `apps/cla-evidence` (sentinel), `plugins/soleur` (two suites)
- Planned files: 4 | Estimated changed lines: ~140
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/test-machinery change. Engineering
is the home domain (both issues carry `domain/engineering`); Marketing, Product,
Operations, Legal, Sales, Finance and Support assessment questions all answer
no: no content/brand surface, no user-facing UI (the mechanical UI-surface
override does not fire — no `Files to Create`/`Files to Edit` path matches the
ui-surface-terms glob set), no vendor/procurement, no legal docs, no pipeline,
no budget, no support workflow.

## Acceptance Criteria

1. `detect-changes` emits `plan_directories`: for a diff touching
   `apps/cla-evidence/infra/<file>.tf`, `directories ==
   ["apps/cla-evidence/infra"]` and `plan_directories == []`; for a diff
   touching `apps/web-platform/infra/<file>.tf`, both arrays equal
   `["apps/web-platform/infra"]`. (Verified by the new
   `infra-validation-detect.test.sh` cases.)
2. `grep -n 'plan_directories' .github/workflows/infra-validation.yml` shows
   the output declaration, the `plan` job `if:` guard, and the
   `matrix.directory` value — `plan` never names
   `needs.detect-changes.outputs.directories` again.
3. `test -s apps/cla-evidence/infra/.pr-plan-skip` exits 0 — sentinel present
   and non-empty, carrying its justification + re-enable condition.
4. `bash plugins/soleur/test/infra-validation-detect.test.sh` exits 0,
   including the new `detect_plan_dirs` cases.
5. `SOLEUR_GO_GATES_SKIP_H3=1 bash plugins/soleur/test/go-session-gates.test.sh`
   exits 0 with `assertion(s) executed` ≥ 239 (skip path), and on a host with
   `claude` on PATH ≥ 241 with zero H3 FAILs — including a Devin-CLI host where
   the markers read `source=devin-cache`.
6. The H3 block no longer asserts a single arm: `awk '/^echo "H3\./,/^else/'`
   over `plugins/soleur/test/go-session-gates.test.sh` contains no
   `source=plugin-root-token` requirement (section-scoped — R5b/R11b outside
   the block legitimately keep it).
7. On this PR's own Infra Validation run: `validate
   (apps/cla-evidence/infra)` runs and is green, and no
   `plan (apps/cla-evidence/infra)` leg exists (the `::notice::` in
   detect-changes names the exclusion). Self-demonstrating AC.
8. No 401/9109 appears in the `plan` job's step output on this run.

## Test Scenarios

- **TS-A1 (unit):** Given a dir list containing a sentinel-bearing root, when
  `detect_plan_dirs` runs, then that root is absent and sentinel-free roots are
  preserved — in `plugins/soleur/test/infra-validation-detect.test.sh`.
- **TS-A2 (unit):** Given all-sentinel input, when the filter runs, then
  `plan_directories` is `[]` and the `plan` job's `if:` evaluates false — mirror
  case + workflow `if:` grep.
- **TS-A3 (unit):** Given the real tree, when the committed-sentinel row runs,
  then `apps/cla-evidence/infra/.pr-plan-skip` exists and is non-empty.
- **TS-B1 (integration):** Given a `h3_out` capture whose gates resolve
  `source=devin-cache verified=true`, when H3 classifies, then all three rows
  pass; given `verified=false`, a missing line, or an unlisted arm, then the
  row fails — exercised by the Guard-2 mutation matrix during implementation
  review and by the live suite on the Devin-CLI host.
- **TS-B2 (integration):** Given `SOLEUR_GO_GATES_SKIP_H3=1`, when the suite
  runs, then `asserted` stays ≥ 239 — the floor comment's both-paths
  arithmetic is preserved (H3 contributes exactly 3 `ck` in both arms).
- **TS-E2E (e2e, pyramid-justified: this is the failure's actual surface — the
  GitHub Actions runner running the real workflow on the real root; no lower
  layer can reproduce a Cloudflare API rejection):** this PR's own
  `infra-validation.yml` run shows `validate (apps/cla-evidence/infra)` green,
  no `plan` leg for that root, and the `::notice::` exclusion line in the
  detect-changes step log.

## Open Code-Review Overlap

- #8735 (`notify-main-failure` misses cancelled jobs) — touches the same file
  but a different job (`notify-main-failure` vs `detect-changes`/`plan`).
  **Acknowledge:** different concern, needs its own cycle; our diff does not
  intersect the notify job's `needs:`/`if:` logic.
- #7942 (`*.mutation.sh` batteries run in no gate) — body references this
  workflow but concerns unregistered suites.
  **Acknowledge:** orthogonal registration concern.
- #8659 (33 suites replace test-helpers' composed EXIT trap) —
  `go-session-gates.test.sh` is plausibly one of the named suites; our edit is
  confined to the H3 block, not the `trap 'rm -rf "$TMP_ROOT"' EXIT` line.
  **Acknowledge:** folding a trap redesign into a two-issue machinery fix
  would inflate scope; the overlap is noted for the reviewer.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Merge mutates production | **No** — no apply workflow targets `apps/cla-evidence/infra` (its applies are operator-bootstrapped via `bootstrap.sh`); the workflow edit changes PR-time checks only; the sentinel is inert data |
| A future data-read-only root reds the plan leg again | The mechanism is the fix — the author adds `.pr-plan-skip` to the root (documented inside the sentinel file itself); `validate` never stops covering it |
| Filter silently drops a healthy root | Mirror cases pin both arms (sentinel out / non-sentinel in) and the committed-sentinel row pins the file itself; `::notice::` makes each exclusion visible in the run log |
| H3 tolerance hides a real resolution failure | The allowlist asserts `verified=true` — the invariant — and only names arms the resolver documents as healthy; `verified=false`, missing lines, and unlisted arms still fail |
| Accepting `devin-cache` on a substituting harness masks a broken token arm | Impossible in practice: `devin-cache` only resolves when a Devin cache dir exists; on a non-Devin host a broken arm-1 reports `none`/`verified=false`, which still fails |
| Sentinel travels with a root rename and keeps excluding | Intended behavior — the root's data-read property travels with it; deletion re-arms the leg (and re-reds it until the credential grant lands) |

## Alternative Approaches Considered

| Alternative | Verdict | Why |
|-------------|---------|-----|
| Grant the plan credential `API Token Permission Groups:Read` (issue's option A) | Deferred to operator | It is a mutation of a real production credential — outside the self-serve pipeline's authorization class — and widens a Tier-A-reachable token's scope against ADR-241's least-privilege direction. The sentinel content names it as the re-enable path: grant + delete the file restores full plan coverage |
| Hardcode `matrix.directory != 'apps/cla-evidence/infra'` in the `plan` `if:` | Rejected | One-line but non-structural: the second such root needs another hardcode, the exclusion lives far from the root it describes, and a rename silently re-arms the leg |
| `matrix.exclude` under `strategy` naming the root statically | Rejected | Cheapest in-workflow form (~4 lines and it works with `fromJSON`), but it is the same hand-maintained hardcode one level down: the exclusion lives in the workflow file, not at the root, does not travel on rename, and reintroduces the central-list pattern this repo has repeatedly replaced with filesystem-declared state |
| Per-leg early-exit inside `plan` (leg runs, detects sentinel, skips) | Rejected | A green check over a leg that did nothing is the anti-silent-skip class `infra-validate-required` exists to kill |
| Pin the Cloudflare permission-group IDs as literals, removing the data read | Rejected | IDs are account-scoped values not derivable in-repo; fetching them needs the very permission that's missing — circular — and pinned UUIDs drift invisibly |
| Replace the data source with `-target=` plan scoping | Rejected | Fragile: only plans the named subset, silently loses coverage for future resources added to the root |
| H3 skips when `CLAUDE_PLUGIN_ROOT` is unset (issue's option B) | Rejected | A skip disarms real-harness contact on exactly the hosts arm 3 (`devin-cache`, #8401) was built for; tolerance keeps the property under test (`verified=true`) blocking |

## Sharp Edges

- Do not write a `var`-prefixed Terraform reference to `cf_api_token` (or any
  `var`-prefixed `*_token`/`*_pat` variable name) in plan, PR, or code prose —
  deepen-plan Phase 4.8's PAT-shape regex halts on that spelling (write
  `variable "cf_api_token"` or the bare name).
- `grep`-based AC6 must stay section-scoped to the H3 block: `plugin-root-token`
  legitimately survives in R5b/R11b rows elsewhere in the file — a whole-file
  grep contradicts the AC by construction.
- The `plan_directories` derivation must live in `detect-changes`' `dirs` step,
  not in a second step reading the output — one chokepoint computes both arrays
  or the two can disagree.
- Keep exactly 3 `ck` assertions in H3; the suite's `MIN_ASSERTIONS=239` floor
  is pinned to "H3 skipped" and the +2 delta to "H3 running" — changing the
  count breaks the floor arithmetic measured on the skipped path.
- Empty `.pr-plan-skip` sentinel would work for `-f` but carries no
  justification — keep it non-empty; the test row asserts `test -s`.

## Context

- Issue #10715 body: "Step 'Terraform plan' fails: `Error: error listing API
  Token Permission Groups … Unauthorized to access requested resource (9109)`";
  "Pre-existing: the job has no prior runs in the recent window (path-gated)";
  "Job is not in the required-status contexts."
- Issue #10714 body: "H3 expects `gate=* source=plugin-root-token verified=true`
  markers, but Devin CLI sessions resolve the plugin via the devin-cache arm
  (no CLAUDE_PLUGIN_ROOT env), so markers read source=devin-cache. Fails
  identically on main — environmental, not a regression."
- go.md's resolver documentation (lines ~119-120): `source=devin-cache
  verified=true` is "the healthy Devin path"; `devin-cache-nomatch` is a
  distinct unverified state with its own remedy.

## References

- Closes #10715, Closes #10714 (PR body lines, never the title —
  `wg-use-closes-n-in-pr-body-not-title-to`)
- Surfacing PR: #10679 (MERGED 2026-10-20)
- ADR-241 (Tier-A bounded substitutes), ADR-179 A16 (devin-cache arm),
  ADR-262/ADR-276 (job-level CI gating precedent)
- `apps/cla-evidence/infra/variables.tf` `cf_admin_token` description —
  documents the precedent that this root's plan matrix "had never run to
  completion … the breakage was latent until #7624 touched this directory"
