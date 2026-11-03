---
title: "fix: Repair codeql-to-issues dedupe (invalid gh search query empties EXISTING)"
type: fix
date: 2026-11-03
slug: fix-codeql-to-issues-dedupe
branch: feat-one-shot-codeql-dedupe-fix
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# fix: Repair codeql-to-issues dedupe (invalid gh search query empties EXISTING)

## Enhancement Summary

**Deepened on:** 2026-11-03 (plan-review standing checks + self-review applied inline — the
DHH/Kieran/code-simplicity panel could not be spawned in this subagent; deepen-plan gates
4.4–4.13 run below).

### Gate results (deepen-plan)

- **4.4 Precedent-diff:** sibling precedent `scripts/codeql-main-alert-gate.sh` cited and
  diffed in `## Alternative Approaches Considered` (author scope, jq form, failure semantics).
- **4.5 / 4.55:** no SSH/network or downtime/cutover trigger — skipped.
- **4.6 User-Brand Impact:** PASS — section present, `none` threshold, sensitive-path regex
  does not match `.github/workflows/codeql-to-issues.yml`.
- **4.7 Observability:** REQUIRED by this gate's pure-docs test (`.yml` Files-to-Edit) even
  though plan Phase 2.9's narrower trigger set skipped it — `## Observability` added with the
  5-field schema; `discoverability_test.command` is allowlist-verb `bash`, <15 s, literal
  `expected_output`.
- **4.8 PAT-shaped variable:** PASS — grep clean (no `var.*_token`/`TF_VAR_*_TOKEN`/literal
  token shapes).
- **4.9 / 4.10 / 4.13:** no UI surface, no persistent store/connection, no new autonomous
  task — skipped.
- **4.11 Guard Contract:** PASS — `lint-guard-contract.py` scanned clean (1 entry, 6-row
  matrix incl. own-dispatch, second-member, anchoring, suite-mutation and must-PASS rows).
- **4.12 Scope Check:** PASS — exactly one `## Scope Check`; all asks mapped, `inferred`
  items carry justifications.
- **Review agents (Phases 4, 5):** not spawned — no agent-spawn capability in this planning
  subagent. Deferred hardening A-vs-B items filed as issue #12004 for a CTO ruling.

### Key improvements from the deepen pass

- `## Observability` section added (4.7).
- Post-merge AC reworded to the invariant form (no ambient-count dependence).
- `--limit 200` cap residual documented (the open `type/security` list currently sits at the
  cap, mostly the duplicates this bug produced).
- MD038-lint-safe rendering of the trailing-space anchor literals.

## Overview

<!-- MD038 disabled on the anchor literals below: the trailing space inside the code span IS the dedupe anchor being specified, not stray whitespace. -->

The daily `check-alerts` job in `.github/workflows/codeql-to-issues.yml` dedupes by running
`gh search issues "sec: CodeQL alert #${ALERT_NUMBER} repo:${GH_REPO} is:issue is:open"`.
GitHub's search grammar reads the leading `sec:` as a qualifier token, so the query is invalid —
verified live, `gh` exits non-zero with `The search query contains invalid syntax.` The `|| true`
on that line then leaves `EXISTING` empty for every alert, the dedupe never fires, and the
workflow re-files an open tracker on every run. Live census of the open `type/security` list
(itself at the 200-row cap) shows ~185+ duplicates: 26 copies each of `sec: CodeQL alert`
#245/#246/#252/#258/#268, 25 of #272, 12 of #301, 9 of #248, 3 of #261.

The fix replaces the free-text search with a bounded
`gh issue list --label type/security --state open --limit 200 --json title` read plus an
anchored jq match on `^sec: CodeQL alert #${ALERT_NUMBER} ` (the trailing space anchors the <!-- markdownlint-disable-line MD038 -->
alert number so `#5` cannot match a tracker for `#50`). The same `sec: CodeQL alert #N — <desc>`
title shape is emitted by `scripts/codeql-main-alert-gate.sh` (`TRACKER_PREFIX`, line 76), so
one list dedupes trackers filed by both filers. Everything else in the workflow — alert fetch,
title/body format, `gh issue create --label type/security`, counters, the `close-orphans` job —
is unchanged.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed); no `spec.md` exists for
this branch.

## Research Insights

### Premise Validation (Phase 0.6)

- Cited file `.github/workflows/codeql-to-issues.yml` exists on this branch; the invalid query
  is at the `SEARCH_QUERY`/`EXISTING` lines of the `check-alerts` `run:` block.
- `gh search issues "sec: CodeQL alert #1 repo:jikig-ai/soleur is:issue is:open"` reproduced
  locally: `Invalid search query … The search query contains invalid syntax.` Premise holds.
- `scripts/codeql-main-alert-gate.sh` exists and already implements the prescribed mechanism:
  `list_issues()` (`gh issue list --label type/security --author app/github-actions --state open
  --limit 200 --json 'number,title'`) plus a `startswith($TRACKER_PREFIX + num)` jq match with a
  non-digit suffix check. Its tracker titles are `${TRACKER_PREFIX}${num} — ${rule}` — the same
  shape the workflow files (`sec: CodeQL alert #N — <desc>`), so the prescribed anchored match
  covers both filers.
- Label `type/security` exists (`gh label list`); repo is **public** (`isPrivate: false`).
- The broken form was introduced by the #8593 "existence-drill" rewrite (archived spec
  `20261101-135922-feat-one-shot-8593-8080-witness`, task 2.6 "codeql-to-issues.yml
  (existence-drill rewrite)") — the `--limit 1 --jq '.[0].number // empty'` shape it installed is
  exactly what the invalid query silently defeats.
- No external premises left to validate; no cited issue numbers.

### Property List (Phase 0.6b)

- P1: the `check-alerts` filing loop creates no second tracker for an alert number already named
  by an open `type/security` issue.
- P2: dedupe holds for trackers filed by BOTH filers (the workflow and
  `scripts/codeql-main-alert-gate.sh`), which share the `sec: CodeQL alert #N — <desc>` title.
- P3: a dedupe-read failure must not silently re-enable duplicate filing (the root cause:
  invalid query + `|| true` → empty `EXISTING`).

### Cut List (Phase 0.6b)

None. The ask proposes exactly one mechanism (list + anchored match); no mechanism already on
`origin/main` buys P1 for this job — the sibling gate's list lives in a different process and
cannot be "reused" across a workflow boundary.

### Repo findings

- `.github/workflows/codeql-to-issues.yml` — the file to edit. Its `close-orphans` job
  (lines ~93-108) already establishes the in-file convention for a `gh issue list` read:
  explicit `if !` exit check, `::warning` annotation, `jq -e` JSON validation.
- `plugins/soleur/test/components.test.ts` — `findUnboundedEnumerations` scans
  `.github/workflows/**/*.yml` for unbounded `gh issue list` / `gh search` / `gh api`
  enumerations and requires `-L N >= 100` or `--paginate`. The prescribed `--limit 200`
  satisfies it.
- `.github/workflows/auto-label-security.yml` — labels `^sec:` titles `type/security` on open;
  the workflow also files with `--label type/security` directly, so trackers carry the label
  regardless of which path lands first.
- `scripts/lint-workflow-run-body-syntax.py` (`bash -n` every `run:` body) and actionlint +
  shellcheck in `ci.yml` lint the edited block; `scripts/lint-workflow-issue-write-scope.py`
  needs `issues: write`, already present.
- No unit-test file covers workflow YAML in this repo; verification is synthesized-fixture jq
  runs plus a post-merge `workflow_dispatch` observation.

### Applicable learnings

- `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — `gh --jq` does NOT forward `--arg`; pipe to
  standalone `jq --arg`, never `gh issue list --jq '...' --arg p …`. The fix pipes `--json title`
  output into `jq --arg`.
- `2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md` — context for the untouched
  `close-orphans` job.
- `2026-04-13-codeql-to-issues-invalid-workflow-trigger.md`,
  `2026-04-13-codeql-alert-triage-and-issue-automation.md` — history of this workflow's
  trigger/label conventions.

### Functional overlap / community discovery

No uncovered stacks (GitHub Actions YAML + `gh`/jq — covered). Functional-overlap agent not
spawned (no agent-spawn capability in this planning subagent); a one-line dedupe-mechanism fix
has no plausible community-artifact substitute. External research skipped — the mechanism is
prescribed and already implemented once inside this repo.

## Open Code-Review Overlap

None. 96 open `code-review` issues queried; no body contains `codeql-to-issues.yml` or
`.github/workflows/codeql-to-issues.yml`.

## Files to Edit

- `.github/workflows/codeql-to-issues.yml` — `check-alerts` job `run:` block only: hoist one
  `gh issue list` read before the alert loop (fail-closed on fetch/parse failure), replace the
  per-alert `SEARCH_QUERY`/`gh search issues`/`EXISTING` lines and the now-stale
  "Existence drill (#8593)" comment with the anchored jq match.

## Files to Create

None.

## Proposed Change

In `check-alerts`, after the `ALERTS` non-empty check and before the `while` loop, fetch the
tracker list once (alert-independent — one API call replaces N searches):

```bash
# Dedupe reads the open type/security issue titles ONCE; the per-alert match is
# anchored on "sec: CodeQL alert #<N> " (trailing space) so #5 cannot match a
# tracker for #50. codeql-main-alert-gate.sh files the same title shape, so one
# list dedupes both filers. A fetch/parse failure skips the filing pass — a
# dedupe that silently reads empty is the duplicate-filing bug being replaced
# (fail-closed; mirrors the close-orphans job below).
if ! gh issue list --label type/security --state open --limit 200 --json title \
  > "${RUNNER_TEMP}/sec-issues.json" 2>"${RUNNER_TEMP}/sec-issues.err"; then
  echo "::warning title=check-alerts::gh issue list failed: $(cat "${RUNNER_TEMP}/sec-issues.err")"
  exit 0
fi
if ! jq -e . "${RUNNER_TEMP}/sec-issues.json" >/dev/null 2>&1; then
  echo "::warning title=check-alerts::Issue list returned non-JSON body — skipping filing pass."
  exit 0
fi
```

Inside the loop, replace the `SEARCH_QUERY`/`EXISTING` block with:

```bash
EXISTING=$(jq -r --arg p "sec: CodeQL alert #${ALERT_NUMBER} " \
  '[.[] | .title | select(type == "string") | select(startswith($p))] | .[0] // empty' \
  "${RUNNER_TEMP}/sec-issues.json")
```

`if [ -n "$EXISTING" ]` and everything downstream stay as-is.

## Alternative Approaches Considered

<!-- markdownlint-disable MD038 -->

| Approach | Verdict | Why |
|---|---|---|
| Fix the `gh search` query instead (e.g. `"sec: CodeQL alert #N" in:title`) | rejected | Still free-text search: index lag can miss a just-filed tracker; the `label:`-style qualifier trap generalizes; the prescribed fix is a bounded list read |
| `--author app/github-actions` on the list (sibling's anti-poison scope) | not adopted | Prescribed fix is verbatim `--label type/security`; the label already bounds the population — strangers on a public repo cannot self-apply labels. Recorded as a pending technical row in `decision-challenges.md` |
| Sibling's exact jq (`startswith` + next-char-not-digit) | not adopted | Catches bare `sec: CodeQL alert #N` titles with no suffix; prescribed form uses the trailing-space anchor — equivalent for the ` — <desc>` shape both filers always emit. Accepted residual: a human-filed bare-prefix title does not dedupe |
| Keep `|| true` around the new list read | rejected | Re-introduces the root cause: any transient API/jq failure silently empties the dedupe set and the run files duplicates. `::warning` + `exit 0` is fail-closed and mirrors `close-orphans` in the same file |
| Mass-close the ~185 existing duplicates in this PR | descoped | Bulk issue mutation is outside this fix's blast radius; the repaired dedupe prevents recurrence. Flagged to the operator via `decision-challenges.md` |

<!-- markdownlint-enable MD038 -->

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator's open-issues list — the security
  tracker backlog — either keeps accreting daily duplicate `sec: CodeQL alert #N` issues
  (fail-open direction, status quo) or, in the over-match direction, silently suppresses the
  tracker for a real critical/high CodeQL finding so it never pages anyone.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector —
  the change reads open issue titles with `GITHUB_TOKEN` and creates issues; no secrets, no
  user-data surface, no new network edge.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal triage tooling on this repo's own tracker;
  worst case is tracker noise or a suppressed internal tracker — no end-user artifact is
  produced or altered.

## Observability

```yaml
liveness_signal:
  what: "the daily `check-alerts` run completes and prints `Done. Created: <N>, Skipped (existing): <N>`"
  cadence: "daily at 06:00 UTC (schedule cron) + on-demand workflow_dispatch"
  alert_target: "Actions run state + `::warning`/`::error` annotations; the repo's scheduled-run conventions surface failures via the Actions UI and run-notify mail"
  configured_in: ".github/workflows/codeql-to-issues.yml `on.schedule` and `check-alerts` run block"

error_reporting:
  destination: "GitHub Actions run log (annotations render in the run summary); a failed run reds the Actions check surface"
  fail_loud: "`::warning title=check-alerts::` lines on dedupe-fetch/parse failure; a non-zero step exit fails the job"

failure_modes:
  - mode: "dedupe read fails or returns non-JSON (transient API/CLI fault)"
    detection: "`::warning` annotation in the run log; step exits 0 with zero filings"
    alert_route: "Actions run annotations (visible on the run page; daily cadence self-recovers next run)"
  - mode: "`gh issue create` fails mid-loop"
    detection: "non-zero step exit fails the job; run state red"
    alert_route: "failed Actions run notification"
  - mode: "dedupe silently over-matches and suppresses a real tracker"
    detection: "anchored-prefix fixture verification at PR time (ACs); `Skipped` count in run log vs open-alert count"
    alert_route: "PR-time assertion; post-merge run-log read"

logs:
  where: "Actions run logs for `CodeQL Alert to Issue` (per-step output incl. per-alert skip/create lines)"
  retention: "GitHub Actions default (~90 days)"

discoverability_test:
  command: "bash scripts/lint-workflow-run-body-syntax.py .github/workflows/codeql-to-issues.yml"
  expected_output: "clean"
```

## Guard Contract

### Guard 1 — codeql-to-issues dedupe

**Property.** The `check-alerts` filing loop creates no second tracker for an alert number
already named by an open `type/security` issue (and never suppresses an alert whose number is
not so named).

**Assembly.** The single per-alert dedupe read inside the `check-alerts` `while` loop of
`.github/workflows/codeql-to-issues.yml` — every `gh issue create` in that job flows through it;
it is the only chokepoint (the sibling `scripts/codeql-main-alert-gate.sh` chokepoint is
unchanged and out of this guard's window).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore a failing dedupe read (e.g. the invalid `gh search` query) under `|| true` — the guard's OWN dispatch fails and filing proceeds on an empty set | RED (a run with an open `#5` tracker must file 0 issues; it files 1) |
| 2 | Drop the `jq -e` / `if !` guards so a non-JSON or failed list read is treated as "no trackers" | RED (same observable as row 1 — guard reads empty and files) |
| 3 | Two distinct open alerts #A and #B each with an open tracker; hardcode the match to the first tracker or `break` after the first hit — a check that stops at the first member | RED (the second member's tracker must also suppress its filing) |
| 4 | Drop the trailing-space anchor so `sec: CodeQL alert #5` also matches `#50`'s tracker — order/lifetime row: the match observes INSIDE the number's character window | RED (alert #5 MUST file beside an existing `#50` tracker; over-dedupe suppresses it) |
| 5 | Suite edit: fixture titles carry `sec: CodeQL alert #5 — x` but the fixture omits the `type/security`-scoping shape (e.g. closed-issue titles injected into the list) — a closed tracker is not a dedupe signal | RED if the harness counted it; must-PASS input: closed `#5` tracker + open `#50` tracker, alert #5 files |
| 6 | Canonical must-PASS: open `sec: CodeQL alert #5 — x` tracker in the list, alert #5 in the alert set | PASS — 0 filed, `SKIPPED` increments |

## Scope Check

### Ask Mapping

<!-- markdownlint-disable MD038 -->

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix the broken dedupe in .github/workflows/codeql-to-issues.yml" | `.github/workflows/codeql-to-issues.yml` (Files to Edit) | mapped |
| 2 | "replace the search-based dedupe with `gh issue list --label type/security --state open --limit 200 --json title` plus an anchored jq match on `^sec: CodeQL alert #${ALERT_NUMBER} `" | Proposed Change (hoisted list read + `startswith($p)` anchored match) | mapped |
| 3 | "Keep everything else in the workflow unchanged" | Files to Edit scoped to the dedupe hunk + hoisted fetch; close-orphans job, alert fetch, issue title/body, labels, counters untouched | mapped |

<!-- markdownlint-enable MD038 -->

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/codeql-to-issues.yml` edit | "Fix the broken dedupe in .github/workflows/codeql-to-issues.yml" | asked |
| `gh issue list` + anchored jq mechanism | "replace the search-based dedupe with `gh issue list --label type/security --state open --limit 200 --json title` plus an anchored jq match" | asked |
| Hoisted-once fetch + `::warning`/`exit 0` failure arm | — | inferred — justification: the ask's own root cause is a fail-open dedupe read; carrying `|| true` into the replacement re-ships the bug, and the same file's `close-orphans` job already establishes the warn-and-exit convention |
| Comment replacement inside the edited hunk | — | inferred — justification: the "Existence drill (#8593)" comment documents the removed `gh search` mechanism; leaving it describes code that no longer exists |

### Split Assessment

- Subsystems touched: 1 — `.github/workflows/`
- Planned files: 1 | Estimated changed lines: ~20
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] `check-alerts` contains no `gh search` invocation; the dedupe read is exactly
      `gh issue list --label type/security --state open --limit 200 --json title`.
- [ ] The per-alert match anchors on `sec: CodeQL alert #${ALERT_NUMBER} ` with the trailing <!-- markdownlint-disable-line MD038 -->
      space (jq `startswith` on that prefix or an equivalent `^`-anchored test), so `#5` cannot
      match `#50`'s tracker and `#5` still matches `sec: CodeQL alert #5 — <desc>` — the title
      shape emitted by both `codeql-to-issues.yml` (`TITLE=` line) and
      `scripts/codeql-main-alert-gate.sh` (`TRACKER_PREFIX`).
- [ ] A list-fetch or non-JSON failure emits a `::warning` annotation and exits 0 before any
      `gh issue create`; no `|| true` path into the filing loop remains in the dedupe code.
- [ ] Diff is confined to the `check-alerts` `run:` block: alert fetch, loop counters, issue
      title/body creation, `gh issue create --label type/security`, and the `close-orphans` job
      are byte-identical.
- [ ] `python3 scripts/lint-workflow-run-body-syntax.py .github/workflows/codeql-to-issues.yml`
      exits 0 and the extracted `run:` body passes `bash -n`; the new lines stay
      shellcheck-clean under the repo's pinned actionlint (`ci.yml`).
- [ ] `bun test plugins/soleur/test/components.test.ts` stays green — `--limit 200` satisfies
      the `findUnboundedEnumerations` bound (`-L N >= 100`).
- [ ] Synthesized-fixture verification (run locally, fixture built per the Guard Contract
      matrix): fixture `[{"title":"sec: CodeQL alert #245 — Missing regular expression anchor"},{"title":"sec: CodeQL alert #2450 — x"}]`
      returns 1 hit for prefix `sec: CodeQL alert #245 ` and 1 hit for `sec: CodeQL alert #2450 `; <!-- markdownlint-disable-line MD038 -->
      empty fixture returns 0.
- [ ] Post-merge observation (next daily run or manual `workflow_dispatch`): for every open
      alert that already has a tracker, the run logs `Issue already exists for CodeQL alert #N —
      skipping`, and the run files no issue whose title duplicates an open
      `sec: CodeQL alert #N` tracker.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change to an internal triage
workflow. No UI-surface paths in Files to Edit/Create, so the mechanical Product/UX override
does not fire; Product tier is `NONE`.

## Test Scenarios

All scenarios exercise the jq match against synthesized title fixtures (unit layer — the dedupe
logic is a pure function of the titles JSON):

- Given fixture `[{"title":"sec: CodeQL alert #5 — a"},{"title":"sec: CodeQL alert #50 — b"}]`,
  when the match runs for alert #5, then exactly 1 hit and filing is skipped (unit).
- Given the same fixture, when the match runs for alert #500, then 0 hits and filing proceeds
  (unit).
- Given a fixture with a tracker for #5 marked CLOSED (state not in the open list), when the
  match runs for alert #5, then 0 hits — a closed tracker is not a dedupe signal (unit).
- Given a tracker filed by the gate (`sec: CodeQL alert #7 — js/ssrf` shape from
  `TRACKER_PREFIX`), when the match runs for alert #7, then filing is skipped — cross-filer
  dedupe (unit).
- Given `gh issue list` exits non-zero, when `check-alerts` runs, then it prints a `::warning`
  and exits 0 with zero `gh issue create` calls — no silent-empty dedupe (integration, asserted
  by the `if !`/`jq -e` guards in the run body).
- Property: for every alert number N, `filing(N)` is suppressed iff some list title starts with
  `sec: CodeQL alert #N ` — never by a prefix-sibling number, never by a non-matching title <!-- markdownlint-disable-line MD038 -->
  (property, unit layer).

## Context

- **Flagged follow-up (operator scope):** ~185+ duplicate `sec: CodeQL alert` trackers are
  already open. This fix stops new duplicates but does not mass-close the backlog — recorded as
  an `operator (scope)` row in `knowledge-base/project/specs/feat-one-shot-codeql-dedupe-fix/decision-challenges.md`.
- The workflow reads alerts across ALL refs (no `ref=` filter on the alerts query, unlike the
  gate script's `refs/heads/main` scope). Pre-existing behavior, untouched per "keep everything
  else unchanged".
- TOCTOU residual: the hoisted list is read once before filing; a tracker filed mid-run by the
  push-time gate is invisible to this run. Daily cadence makes the window ~24h worst case, and
  both issues self-resolve through `close-orphans` on dismissal.
- `--limit 200` bound: the open `type/security` list currently sits AT the 200-row cap (most
  rows are the duplicates this bug produced). A tracker evicted past the bound would read as
  absent and re-dup once — the same accepted bound the `close-orphans` job documents inline.
  The bound releases once the duplicate backlog is triaged (the flagged follow-up above).

## References

- Workflow: `.github/workflows/codeql-to-issues.yml` (`check-alerts`, `close-orphans`)
- Sibling filer: `scripts/codeql-main-alert-gate.sh` (`list_issues`, `TRACKER_PREFIX`)
- Enumeration lint: `plugins/soleur/test/components.test.ts` (`findUnboundedEnumerations`,
  `EXEC_SURFACE_GLOBS`)
- Learnings: `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`,
  `knowledge-base/project/learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md`,
  `knowledge-base/project/learnings/2026-04-13-codeql-to-issues-invalid-workflow-trigger.md`
- Origin spec (of the broken form): `knowledge-base/project/specs/archive/20261101-135922-feat-one-shot-8593-8080-witness/`
