---
title: "feat: Inngest execute-gate satisfiability witness + unbounded-gh-enumeration gate widening (epic #10390 PR 2)"
type: feat
date: 2026-11-01
slug: inngest-witness-gh-enum-gate
branch: feat-one-shot-8593-8080-witness
issue: 8593
closes: 8593
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# feat: Inngest execute-gate satisfiability witness + unbounded-gh-enumeration gate widening

Spec lacks valid `lane:` (no spec.md exists for this branch — brainstorm did not run on the one-shot path) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Epic #10390 batch PR 2 of the standing CTO batching ruling (recorded in
`knowledge-base/project/specs/archive/20261031-194207-feat-one-shot-11528-8841-9139-batch1/decision-challenges.md`:
"PR1 #11528+#8841+#9139, PR2 #8593+#8080-witness, PR3 #8595 gated on pr-merged 11653"). Two workstreams,
both centered on `.github/workflows/scheduled-inngest-health.yml`:

1. **#8593 — widen the #6793 unbounded-`gh`-enumeration gate** in `plugins/soleur/test/components.test.ts`
   so its assembly covers every enumeration-feeding `gh` capture (`gh issue|pr list` without `--search`,
   `gh search issues|prs`, `gh api …/issues` without `--paginate`), add the missing executable surfaces
   (`.github/scripts/`, `apps/web-platform/server/inngest/functions/*.ts`), and bound the six live
   uncovered members the issue's table names.
2. **#8080 item 1 only — a cron satisfiability witness** for the cutover pre-flight gate: the 15-minute
   watchdog calls `inngest_execute_registry_gate` **report-only**, emits the token, and files an
   `action-required` issue when the token is a refusal for N consecutive runs while no cutover is in
   flight. An unsatisfiable gate is then found by cron, not by a keyboard dispatch on cutover day
   (#8017 and #8054 were both found that way).

**Out of scope:** #8080 item 2 (the `RestartSec=5→300` unit-template quieting — deferred to the next
vinngest image bake / host-replace carrier batch per the same ruling); #8595 (PR 3, separate); #11720
(MUT_SKIP-idiom family remainder); the duplicate-issue audit half of #8594 (see Open Code-Review
Overlap). #8080 stays open — PR body carries `Refs #8080`, not `Closes`.

## Problem Statement / Motivation

- The #6793 gate names the property "no unbounded `gh` enumeration reaches automation" but its
  assembly sees only `gh pr|issue list … --search` captures on a subset of surfaces — the identical
  silent-30 truncation via `--label` probes, `gh search`, `gh api`, `.ts` agent-prompt surfaces, and
  `.github/scripts/` is invisible to every detector, and six live sites silently truncate today.
- The cutover pre-flight gate (`inngest_execute_registry_gate`,
  `tests/scripts/lib/inngest-host-dark-gate.sh`) can only be *proven* satisfiable by calling it — and
  today nothing calls it outside an operator-dispatched cutover run. A predicate that cannot be
  satisfied in the world the surrounding guards produced is discovered at the worst possible moment.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view`: **#8593 OPEN**, **#8080 OPEN**, **#8595 OPEN** (PR 3, untouched), epic **#10390 OPEN**.
  #11653 (former PR-3 gate) MERGED 2026-10-31. Batch-1 PR #11695 MERGED 2026-11-01 — its diff is the
  precedent for the landmines in this plan.
- **Stale mechanism text in #8080:** the issue says call `inngest_execute_registry_gate` "(and, when
  applicable, `inngest_host_dark_gate`)" — `inngest_host_dark_gate` was **retired 2026-10-14 under
  #8316** (lib header records it; `cutover-inngest-workflow.test.sh` census asserts it is never
  called). The witness calls `inngest_execute_registry_gate` **only**.
- **Drifted line numbers in #8593** (sites verified live): the two close-enumeration loops are now at
  `scheduled-inngest-health.yml:~1124` (`ci/inngest-dedicated-host`) and `~1221`
  (`ci/inngest-no-live-scheduler`); `review-reminder.yml:~117`; `strategy-review-check.sh:~107`;
  `cron-follow-through-monitor.ts:~117,124`; `codeql-to-issues.yml:~57`. Gate internals also moved:
  `GH_LIST_CMD` ~:879, `EXEC_SURFACE_GLOBS` ~:898-919, `extractSearchProbes` ~:972-1021,
  `HAS_LIMIT` ~:1045. Same artifacts, same defects — premise holds.
- **Collision pre-check:** `collision-precheck.sh` reported PR #11782 naming both issues — it is **this
  branch's own auto-draft** (headRefName `feat-one-shot-8593-8080-witness`, empty files list), not a
  duplicate. One foreign `test-all.sh` process (pid 2061005, worktree `chore-deadman-armed-record-11631`)
  is unrelated concurrent work — reported, proceeding.
- **ADR corpus check (mechanism nouns):** ADR-296 (streak state lives in a named workflow **artifact**,
  not the Actions cache — cache was evicted daily), ADR-252 (suite registration IS filesystem presence
  under `apps/web-platform/infra/**.test.sh`), ADR-199 + 2026-10-14 addendum (the dark-host gate and
  the #8316 retirement), ADR-100 (single dedicated host). No ADR rejects the proposed mechanisms.

### Property List (Phase 0.6b)

- P1: no `gh` enumeration feeding a post-narrowing consumer reaches an executable surface without an
  explicit, sufficient bound or a principled exemption (#8593).
- P2: every live site in the issue's table stops silently truncating (#8593 AC1).
- P3: an unsatisfiable execute-gate is discovered by the 15-minute cron and filed, not by a cutover-day
  dispatch (#8080-1).

### Cut List (Phase 0.6b)

- `op=registry-probe` (`scripts/cutover-inngest.sh`) already runs the gate read-only — but it is
  operator-dispatched, which is exactly the discovery channel P3 replaces. Not a substitute; keep
  witness in the cron workflow as the issue directs.
- Streak state: `scripts/monitor-streak-state.sh` (`fetch`/`seal`/`assert`, artifact carrier per
  ADR-296) already implements consecutive-run persistence parameterized by `STREAK_ARTIFACT_NAME` —
  **reuse, do not rebuild**.
- `inngest_luks_key_probe_dark` dead-man alert: **cut** — inert until #11266's signed-bundle work;
  barred by the operator brief.
- No other proposed mechanism buys a property an existing mechanism already covers; no cuts beyond
  the two above.

### Institutional learnings that apply

- `knowledge-base/project/learnings/2026-07-22-widening-a-lint-repo-wide-shipped-three-fail-opens-my-green-suite-missed.md`
  — the #6793 widening's own history: `dot:true` + per-surface non-empty guards; `&&`/`||`/`;`
  statement-split so a neighbor's flags can't launder; enumerate the *invariant*, not the examples
  (this plan adds `.[].`, `| grep`, `map(`, `sort_by`, `length` — and keeps `select(`).
- `knowledge-base/project/learnings/2026-07-20-the-lint-i-wrote-to-catch-a-fail-open-shipped-the-same-fail-open.md`
  — the extraction regex must not span delimiters that launder one probe's flags into another's.
- `knowledge-base/project/learnings/2026-10-06-total-count-is-a-snapshot-not-a-truncation-proof.md` —
  a `length` count is a completeness consumer; existence questions must use existence drills
  (`.[0]`/`// empty`), which is why `codeql-to-issues.yml` is rewritten to one.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — guards need own-dispatch RED rows + must-PASS rows; the Guard Contract below is written from the
  design, not the code.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — decision logic is extracted to a testable `scripts/` helper ("a verdict that cannot be driven RED
  is not a verdict" — same idiom as `inngest-dedicated-host-classify.sh`).
- `knowledge-base/project/learnings/best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`
  — the witness classifier's token set is derived from the lib at test time, not pinned in the suite.
- `knowledge-base/project/learnings/2026-09-22-one-monitor-four-red-gates-each-named-its-own-remedy.md`
  — refusal-token remedies name distinct remediations.

### Repo mechanisms reused (verified live)

- `tests/scripts/lib/inngest-host-dark-gate.sh` — `inngest_execute_registry_gate(--rows-file --query-rc
  --hb-file --hb-rc --emit-file --host --host-name)`. Exit 0 + `dark` = satisfied; exit 1 + one of
  {`unreadable`,`silent`,`wrong_host`,`stale_row`,`stale_schema`,`host_serving`,`flag_armed`,
  `flag_unreadable`,`fsm_unreadable`,`fsm_silent`} = refusal. `_erg_flag_class` partitions flags:
  `aborted|rolled-back` → preflip; `armed|flipping|flushed|done` → armed.
- `scripts/monitor-streak-state.sh` — `fetch`/`seal`/`assert` over a named artifact
  (`STREAK_ARTIFACT_NAME`/`STREAK_BRANCH`/`STREAK_FILE` env-parameterized; ADR-296).
- `scripts/betterstack-query.sh` + `scripts/lib/betterstack-read-classify.sh` — the read path the
  dedicated-host arm already uses (`--since --grep --limit`, rc-captured, stderr classified).
- `scripts/lib/inngest-probe-row.sh` — the ONE probe-row definition; the gate lib self-loads it (or
  honors `INNGEST_PROBE_ROW_LIB`).
- The workflow's own idioms: label dedupe via `--limit`-bounded `gh issue list`, `gh label create`
  idempotent, `action-required` for operator-digest harvest, consumer-crash arm keyed on
  `steps.*.outcome`, and `scripts/alarm-issue-filing-guard.test.sh` auto-discovers any new
  `gh issue create|comment|close` step (filing steps need a status-check `if:`).

### External research

Skipped — internal CI/tooling change with strong local precedent (batch-1, monitor-streak, the #6793
gate's own evolution). No new vendor surface.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on this branch | Plan response |
|---|---|---|
| #8080: call `inngest_execute_registry_gate` "and, when applicable, `inngest_host_dark_gate`" | `inngest_host_dark_gate` retired under #8316; census test asserts it is never called | Witness calls `inngest_execute_registry_gate` only; record the staleness |
| #8593 table: loops at `:975` / `:1063` | Now `~:1124` / `~:1221` | Fix sites by label name (`ci/inngest-dedicated-host`, `ci/inngest-no-live-scheduler`), not line number |
| #8593: six uncovered members | Six confirmed live; the widened corpus may flag *more* sites in the newly-scanned surfaces | Phase step: run the new detector over the corpus and bound or document-exempt every newly-flagged site in this PR |

## Proposed Solution

### Workstream A — gate widening (#8593)

1. **`plugins/soleur/test/components.test.ts`**
   - Broaden capture: keep `GH_LIST_CMD` for `gh (pr|issue) list`; add sibling patterns for
     `gh search (issues|prs)` and `gh api` calls whose path is an issue/PR/milestone **list** endpoint
     (plural path or query-string list params; NOT `…/issues/<N>` / `…/pulls/<N>` single-resource
     reads — `cancel-superseded-pr-runs.sh`'s `gh api repos/…/pulls/$PR_NUMBER --jq .created_at`
     must stay invisible).
   - New detector `findUnboundedEnumerations` (sibling to `findUnlimitedProbes`, which keeps the
     `--search` semantics unchanged): a capture is an offender when it feeds enumeration /
     post-narrowing — `.[].`, `| grep`, `select(`, `map(`, `length`, `sort_by`/`min_by`/`max_by`/`last`
     — and carries neither a sufficient bound nor an exemption. Sufficient bound: `-L N`/`--limit N`
     with **N ≥ 100**, or `--paginate` (gh api). Exemptions: existence drill with no
     post-search narrowing (`EXISTENCE_DRILL` + `POST_SEARCH_NARROWING`), `BOUNDED_LINKED_ISSUE`,
     and **new `BOUNDED_HEAD = /--head\b/`** (CTO ruling 2026-11-01: `--head <branch>` is
     domain-bounded by headRefName cardinality, same argument as `linked:issue #N` — covers
     `bump-inngest-bootstrap-pin.sh`'s two post-narrowing `--head` probes at :503/:556 which the
     widened detector would otherwise flag; coded as a pattern exemption, not a documented
     exclusion, so the judgment is enforced not narrated).
     `--limit` *presence* alone no longer greens an enumerating probe — the `-L 1` + `.[].number`
     shape the issue names must flag.
   - Extend `EXEC_SURFACE_GLOBS` with `.github/scripts/**/*.sh` **excluding `*/test/` fixtures**
     (mirrors the `.test.sh` exclusion — fixtures deliberately encode shapes) and
     `apps/web-platform/server/inngest/functions/*.ts`. Add a `"ts"` surface type in `surfaceOf`
     treating full-line `//` comments like `#` comments in sh/yaml (flush + skip) — otherwise
     comment prose like `_cron-shared.ts`'s `// gh issue list --search …` false-positives.
   - New synthesized negative/positive controls (fail RED on the issue's exact fixture
     `gh issue list --label x --jq '.[].number'` with no `-L`; RED on `-L 1` + `.[].number`;
     RED on `gh search issues … --jq 'length'`; RED on `gh api …/issues` without `--paginate`;
     PASS on `--paginate`, `-L 100`, `.[0]` drills, `linked:issue #N`, `//`-comment probes in a `.ts`
     fixture, single-resource `gh api …/pulls/123`, **must-PASS `gh pr list --head <branch>`**
     feeding a post-narrowing consumer — the BOUNDED_HEAD fixture).
   - Corpus offender assertion stays `toEqual([])` — every site the widened detector flags must be
     fixed or document-exempted **in this PR** (census step, Phase A3).
2. **Bound the six named sites:**
   - `scheduled-inngest-health.yml` `ci/inngest-dedicated-host` + `ci/inngest-no-live-scheduler`
     close-enumeration loops: add `--limit 100` to the `gh issue list --label … --jq '.[].number'`
     inside each `for n in $(…)` (matches the file's own `--limit 100` dedupe convention).
   - `review-reminder.yml` + `scripts/strategy-review-check.sh` (the `grep -cxF` exact-title dedupe):
     server-side narrow first — `--search "in:title \"$expected_title\""` — **and** `--limit 100`,
     keep the `grep -cxF` exact-match verify (substring-narrowed + explicitly bounded + exact-checked).
   - `codeql-to-issues.yml`: the `--jq 'length'` count exists only to answer "does an issue for this
     alert exist" — rewrite to an existence drill: `--limit 1 --json number --jq '.[0].number // empty'`
     and test non-empty (learning: total-count is a snapshot, not a truncation proof).
   - `cron-follow-through-monitor.ts` prompt lines ~117/124: add `--limit 200` plus a one-line
     instruction note that the listing is bounded (the T10 test asserts
     `toContain("gh issue list --label follow-through --state open")` — substring, unaffected).
   - `cron-roadmap-review.ts`: `gh api …/milestones` enumeration gets `--paginate`; the
     `gh pr list --search 'roadmap.md in:files'` probe gets an explicit `-L`.
3. **Census step (A3):** run the widened detector across the whole corpus; for every newly-flagged
   site beyond the six, either bound it (same PR) or record an explicit documented exclusion with
   rationale in the test file — never silently exempt.

### Workstream B — satisfiability witness (#8080 item 1)

New arm in `.github/workflows/scheduled-inngest-health.yml` (inside the existing `probe` job, after
the dedicated-host steps, reusing its secrets/env contract):

1. **Fetch streak:** `bash scripts/monitor-streak-state.sh fetch` with
   `STREAK_ARTIFACT_NAME=inngest-gate-witness-streak`, `STREAK_BRANCH=main`, artifact uploaded with
   `overwrite` + 90-day retention — the ADR-296 carrier, unchanged.
2. **Report-only gate call:** two `betterstack-query.sh` reads (probe rows `--since 24h --grep
   SOLEUR_INNGEST_SERVER_PROBE --limit 500`; flip heartbeat `--since 30m --grep inngest-cutover-flip
   --limit 200`), each rc-captured with stderr classified via `betterstack-read-classify.sh` (the
   dedicated arm's exact discipline — `lint-betterstack-emitter-read` scans this file). Source
   `tests/scripts/lib/inngest-host-dark-gate.sh`; call `inngest_execute_registry_gate` with a runner-temp
   emit file. **Report-only = the gate's exit code never kills the step and never dispatches an op.**
3. **Classify** via new extracted helper `scripts/inngest-gate-witness-classify.sh`:
   `dark` → `satisfy` (streak := 0); `flag_armed` **or** the newest probe row's `cutover_flag` in
   armed-class (`armed|flipping|flushed|done`, via the lib's `_erg_flag_class` partition) →
   `suppressed` (a cutover is in flight or done — the refusal is expected; streak held, no filing —
   this also self-retires the witness post-cutover); any other token (`unreadable`, `silent`,
   `wrong_host`, `stale_row`, `stale_schema`, `host_serving`, `flag_unreadable`, `fsm_unreadable`,
   `fsm_silent`, plus any token not in the lib's vocabulary — fail-closed) → `refusal` (streak += 1).
   Emit a greppable run-log line every run: `#8080 gate-witness token=<t> flag=<f> streak=<n>`.
4. **Seal + assert + upload** the streak (monitor-streak contract: a state-step failure reds the run
   AND files — a scheduled run has no watcher).
5. **File:** when `streak ≥ 8` (≈ 2 h at `*/15`, exceeding the gate's 5400 s row-age bound so an
   emit-cadence artifact cannot trip it): dedupe by `ci/inngest-gate-witness` label (bounded
   `--limit 100` `gh issue list`), create or comment an issue titled
   `[ci/inngest-gate-witness] execute-gate unsatisfiable by cron` carrying labels
   `ci/inngest-gate-witness`, `action-required`, `priority/p2-medium`, body naming the token, streak,
   and run URL. A subsequent `dark` verdict auto-closes the open witness issue with a comment —
   mirrors the file's stale-issue close arms. Filing/close steps carry `always() && …`-style `if:`
   conditions per `alarm-issue-filing-guard` (which auto-discovers them), and a witness-step crash is
   covered by a `steps.witness.outcome != 'success'` arm mirroring "Dedicated-host consumer crashed".

## Technical Considerations

- **Landmine constraints (encoded from the operator brief + batch-1 experience):**
  - NO `MUT_SKIP` / `*_GUARD_*` literals in `infra-validation.yml` executable text and NO `env -u`
    prefixes on `run: bash <path>` lines — env-axis muting is barred repo-wide by the
    registry-clientip IV seam check. This plan adds **no** `infra-validation.yml` edit at all:
    the new suite registers by filesystem presence under `apps/web-platform/infra/` (ADR-252).
  - grep-q-pipe-guard (#9217): no `grep | grep -q` predicates in new bash.
  - No `inngest_luks_key_probe_dark` dead-man alert (inert until #11266).
  - Guard-floor bumps are TWO write sites — if the new suite carries a `PRESENCE_ROWS`-style floor,
    its `mutate_floor_red` sed anchor is updated in the same edit.
  - `gh api` enum/query params use exact URL format (`?name=…&per_page=…` inside the path string —
    the monitor-streak fetch already does this; `-f` flips to POST).
  - Commit author: repo CLA-allowlisted identity via `git -c user.name=… -c user.email=…`, never a bot
    identity (cla.yml reads `commit.author.user.login`).
  - Advisory non-required reds to ignore at CI time: affected-index-ratchet ambient drift,
    deploy-script-tests shard timeouts, deploy-script-tests-fixed GuardA carrier reds.
- **`.ts` prompt files:** the widened glob scans agent-prompt text, not TS execution — the extractor
  works on raw text and the new `"ts"` surface strips `//` comments; `*.test.ts` fixtures stay out of
  the glob (it names `functions/*.ts` only — verify no `.test.ts` lives inside that dir at implement
  time; if one does, exclude `*.test.ts` beside the `*/test/` exclusion).
- **Suppression correctness:** `_erg_flag_class` is the lib's own partition — reuse it rather than
  re-listing flag values (a flag-vocabulary addition then lands in both places via the lib).
- **Post-cutover behavior:** flag `done` → `suppressed` permanently unless a rollback returns the flag
  to preflip class, which re-arms the witness automatically.

## User-Brand Impact

- **If this lands broken, the user experiences:** a cutover-day dispatch refused by a gate that cron
  had been watching fail for days, or a duplicated/missed `ci/*` issue from a silently-truncated
  enumeration — internal tooling degradation, not a product-surface defect.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the witness
  reads the same Better Stack log rows with the same read-only credentials and writes GitHub issues
  under the workflow's existing `issues: write` grant; the gate lint reads repo text only.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** no single-user-facing artifact or regulated data exposure;
  the failure mode is machinery noise/missed detection that aggregates over time.

## Observability

```yaml
liveness_signal:
  what: "witness verdict line `#8080 gate-witness token=<t> flag=<f> streak=<n>` in every scheduled-inngest-health run + the ci/inngest-gate-witness action-required issue when streak ≥ 8"
  cadence: "every 15 min (existing */15 trigger)"
  alert_target: "GitHub issue (ci/inngest-gate-witness + action-required labels — operator-digest harvests action-required only) + ::error:: annotation"
  configured_in: ".github/workflows/scheduled-inngest-health.yml (witness arm)"

error_reporting:
  destination: "GitHub issue via the filing arm; ::error::/::warning:: annotations in the run log; witness-step crash covered by the outcome-keyed arm (same shape as 'Dedicated-host consumer crashed')"
  fail_loud: "streak ≥ 8 consecutive refusals files/pages; streak-store unreadable reds the run AND files (monitor-streak contract); BS read failure → verdict unreadable → counts toward the streak"

failure_modes:
  - mode: "witness step crashes before writing outputs (selector/lib load failure, jq failure)"
    detection: "steps.witness.outcome != 'success' arm files with crash_reason (mirrors the dedicated-consumer-crashed arm)"
    alert_route: "ci/inngest-gate-witness issue + ::error::"
  - mode: "streak artifact store unreadable (listing/download fails)"
    detection: "monitor-streak-state.sh fetch exits 1; assert step reds the run"
    alert_route: "red run + filing arm (scheduled run has no watcher — red is the alert)"
  - mode: "Better Stack read fails (credential/transport/source)"
    detection: "rc captured into --query-rc/--hb-rc; gate emits unreadable → refusal streak; stderr classified via betterstack-read-classify.sh"
    alert_route: "verdict line + streak filing"

logs:
  where: "GitHub Actions run log (the verdict line is greppable); gate inputs are Better Stack source 2457081 rows (unchanged)"
  retention: "Actions logs ~90 days; streak artifact retention-days: 90 (above the 60-day scheduled auto-disable, per ADR-296)"

discoverability_test:
  command: "bash scripts/inngest-gate-witness-classify.sh --selftest"
  expected_output: "inngest-gate-witness-classify selftest: ok"
```

## Guard Contract

### Guard 1 — widened unbounded-`gh`-enumeration detector (`components.test.ts`)

**Property.** No `gh` capture whose output feeds enumeration or post-narrowing reaches an executable
surface without an explicit sufficient bound (`-L N ≥ 100` / `--paginate`) or a principled exemption.

**Assembly.** Every capture produced by the extractor over `EXEC_SURFACE_GLOBS` — the chokepoint is
`execSurfaceFiles()` + the capture regexes; all three command families (`gh pr|issue list`,
`gh search issues|prs`, `gh api …list endpoints`) and both new surface classes (`.github/scripts/`,
`functions/*.ts`) flow through it. Members drift; the corpus assertions quantify over the live tree.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture `gh issue list --label x --jq '.[].number'` (no `-L`, no `--search`) | RED |
| 2 | Capture regex neutered to match nothing → detector reports 0 probes over the live corpus | RED (representation/floor assertions fire) |
| 3 | Fixture with a compliant `-L 100` probe followed by a second unbounded `.[].` probe | RED on the second member only |
| 4 | `gh search issues "q" --jq 'length'` with no `--limit` | RED |
| 5 | `gh api 'repos/o/r/issues?state=open' --jq '.[].number'` without `--paginate` | RED |
| 6 | `gh issue list -L 1 --jq '.[].number'` (present-but-insufficient bound — the issue's named shape) | RED |
| 7 | Harness: drop `length` from the post-narrowing alternation → the length fixture above must flag | RED (control test fails, proving the alternative is load-bearing) |
| 8 | Must-PASS inputs differing from canonical: `--paginate` api enumeration; `-L 100` `.[].` probe; `.[0]` existence drill; `linked:issue #N`; a `//`-prefixed `.ts` comment containing a probe-shaped string | PASS |

**Anchor.** The exemptions and the detector share one diff; weakening both would pass only if the
synthesized control fixtures (committed, reviewed in the same diff) also agreed — the controls are
the outside-the-code reference. `gh api` list-vs-item discrimination is asserted by fixture pairs
(`…/pulls` list flags, `…/pulls/123` item passes).

### Guard 2 — witness verdict classifier (`scripts/inngest-gate-witness-classify.sh`)

**Property.** Every token the gate lib can emit maps to exactly one of `satisfy` / `refusal` /
`suppressed`, and no unknown token silently reads as `satisfy` (fail-closed default).

**Assembly.** The token vocabulary is `_ihdg_verdict "<literal>"` call sites inside
`inngest_execute_registry_gate` plus the suppression input (`cutover_flag` via `_erg_flag_class`) —
the suite's census derives the set from the lib at test time, so a new lib token lands unclassified
and RED, never silently mapped (same census idiom `cutover-inngest-workflow.test.sh` already enforces:
"every token the lib can emit has an arm in BOTH").

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one token arm from the classifier's table (e.g. `fsm_silent` falls through) | RED |
| 2 | Classifier reports `satisfy` for every input (vacuous-pass mutant) | RED on decision-table rows |
| 3 | Add a second refusal token after a compliant first mapping — table must classify both | RED if it early-exits |
| 4 | Feed a token absent from the lib's vocabulary → must classify `refusal`, never `satisfy` | RED on a `satisfy`/`suppressed` answer |
| 5 | `flag_armed` verdict OR armed-class `cutover_flag` → `suppressed`; preflip flag + refusal token → `refusal` | RED if either arm inverts |
| 6 | Harness: neuter the lib-derived census to see zero tokens → suite must report vacuity, not green | RED |

**Anchor.** The token set is read from `tests/scripts/lib/inngest-host-dark-gate.sh` at suite
run-time — outside the PR's own diff; a same-diff edit to both classifier and a hand-pinned token
list is exactly what the census defeats.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Extend `extractSearchProbes` (or add a sibling detector) to cover all `gh pr\|issue list` captures whose output feeds enumeration/post-narrowing (`.[].`, `for n in $(…)`, `\| grep`, `select(`, `map(`, `length`, `sort_by`), keeping the existing existence-drill and `linked:issue` exemptions." [#8593] | Workstream A item 1 (detector + matrix rows 1/3/6/8) | mapped |
| 2 | "Extend `GH_LIST_CMD` to `gh search issues\|prs` and `gh api` issue-list endpoints lacking `--paginate`." [#8593] | Workstream A item 1 (capture patterns + matrix rows 4/5) | mapped |
| 3 | "Extend `EXEC_SURFACE_GLOBS` to `apps/web-platform/server/inngest/functions/*.ts` and `.github/scripts/**/*.sh`." [#8593] | Workstream A item 1 (glob + `ts` surface + `*/test/` exclusion) | mapped |
| 4 | "Add bound-sufficiency guidance (presence of `-L` where the consumer enumerates should be sized against the population, or the enumeration shape should be required to assert completeness)." [#8593] | `-L N ≥ 100` / `--paginate` rule + matrix row 6 | mapped |
| 5 | "All six live uncovered members in the table above either carry explicit bounds or are asserted truncation-safe by the widened gate" [#8593 AC] | Workstream A item 2 (six site fixes) | mapped |
| 6 | "The widened detector fails RED on a fixture `gh issue list --label x --jq '.[].number'` enumeration with no `-L`" [#8593 AC] | Guard 1 matrix row 1 | mapped |
| 7 | "`.ts` cron-agent prompt files and `.github/scripts/` are inside `EXEC_SURFACE_GLOBS` or an explicitly documented exclusion with rationale" [#8593 AC] | Both globs included (no exclusion needed) | mapped |
| 8 | "`bun test plugins/soleur/test/components.test.ts` green" [#8593 AC] | AC-3 | mapped |
| 9 | "Have it call `inngest_execute_registry_gate` (and, when applicable, `inngest_host_dark_gate`) report-only, emit the token, and file an `action-required` issue when the token is a refusal for N consecutive runs while no cutover is in flight." [#8080-1] | Workstream B (witness arm); `inngest_host_dark_gate` retired → call the execute gate only | mapped — stale ask reconciled |
| 10 | "GitHub issue #8593 plus ONLY the satisfiability-witness half of #8080 — both edit `.github/workflows/scheduled-inngest-health.yml`. PR body contract: `Closes #8593` on its own body line, `Refs #8080`" [brief] | Scope: #8080 unit-template half + #8595 + #11720 descoped | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `components.test.ts` detector widening | asks 1–4, 6–8 | asked |
| Six site bounds (scheduled-inngest-health ×2, review-reminder, strategy-review-check, codeql-to-issues, cron-follow-through-monitor) | ask 5 | asked |
| `cron-roadmap-review.ts` bound (`--paginate` + `-L`) | ask 2 + "Extend `EXEC_SURFACE_GLOBS` to … `apps/web-platform/server/inngest/functions/*.ts`" | inferred — justification: the site enters the corpus via the asked-for glob and its enumeration would red the corpus assertion; #8593's own rule requires bounding flagged sites |
| `scripts/inngest-gate-witness-classify.sh` (new) | ask 9 | inferred — justification: "a verdict that cannot be driven RED is not a verdict" — extracted so Guard 2's decision table is executable |
| `apps/web-platform/infra/inngest-gate-witness-classify.test.sh` (new) | ask 9 + Guard Contract | inferred — justification: registers by filesystem presence (ADR-252); the classifier's decision table and lib-token census need a suite or the witness is unverifiable |
| `scripts/monitor-streak-state.sh` reuse (no edit) | ask 9 "refusal for N consecutive runs" | asked — streak persistence is the asked mechanism's state carrier |
| Corpus census step (A3) | ask 5 "All six live uncovered members … or are asserted truncation-safe by the widened gate" | inferred — justification: the widened detector may flag sites beyond the named six on the newly-scanned surfaces; the `toEqual([])` corpus assertion demands zero unhandled offenders |

### Split Assessment

- Subsystems touched: 3 — `.github`, `scripts`, `apps/web-platform`, `plugins` (4 roots at the
  first-segment count: `.github`, `scripts`, `apps`, `plugins`)
- Planned files: ~10 edited + 2 created | Estimated changed lines: ~500–650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — at the root-count threshold but under file/line thresholds, and the
  CTO batching ruling already fixed this batch boundary.

## Open Code-Review Overlap

- **#8594 — "review-reminder.yml uncapped enumeration files duplicate issues"** (open, code-review):
  touches `.github/workflows/review-reminder.yml`, which this plan edits. **Disposition: Acknowledge
  + partial fold-in.** The plan's dedupe bound satisfies #8594's first AC (`-L`/`--limit` on the
  enumeration) as a side effect; #8594's remaining ACs (close the #5819/#7742 duplicate pair, audit
  for other duplicate `Review Reminder:` titles) are live-data operations the issue itself scoped to
  "its own cycle" — #8594 **stays open**. PR body may carry `Refs #8594` (ship owns the body).
- **#8593** itself is a code-review issue naming the planned files — it is the work item, not an
  overlap.
- No other open code-review issue names a planned file.

## Implementation Phases

- **Phase A1 — detector widening (`components.test.ts`):** capture patterns for `gh search`/`gh api`
  list endpoints; `findUnboundedEnumerations` with the `-L N ≥ 100`/`--paginate` bound rule; `ts`
  surface + `//` comment handling; `EXEC_SURFACE_GLOBS` additions (`*/test/` + `*.test.ts`
  exclusions); new synthesized controls per Guard 1's matrix.
- **Phase A2 — site bounds:** the six named sites + `cron-roadmap-review.ts` per Proposed Solution.
- **Phase A3 — corpus census:** run the widened detector over the full corpus; bound or
  document-exempt every newly-flagged site; `bun test` green.
- **Phase B1 — witness classifier:** `scripts/inngest-gate-witness-classify.sh` (token→action table +
  `--selftest`) and `apps/web-platform/infra/inngest-gate-witness-classify.test.sh` (decision table,
  lib-token census, matrix rows).
- **Phase B2 — witness arm:** streak fetch → BS reads → gate call → classify → seal/assert/upload →
  filing/close/crash arms in `scheduled-inngest-health.yml`.
- **Phase C — plan/test green sweep:** `bun test plugins/soleur/test/components.test.ts`,
  `bash apps/web-platform/infra/inngest-gate-witness-classify.test.sh`,
  `vitest run test/server/inngest/cron-follow-through-monitor.test.ts` (prompt-pin check),
  alarm-issue-filing-guard suite (auto-discovers the new steps).

## Files to Edit

- `plugins/soleur/test/components.test.ts` — detector widening (Workstream A).
- `.github/workflows/scheduled-inngest-health.yml` — two enumeration bounds + witness arm.
- `.github/workflows/review-reminder.yml` — bounded+server-narrowed dedupe.
- `.github/workflows/codeql-to-issues.yml` — existence-drill rewrite.
- `scripts/strategy-review-check.sh` — bounded+server-narrowed dedupe.
- `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` — `--limit` in the two
  listing commands + instruction note.
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — `--paginate` + `-L`.
- Any additional file the A3 census flags (bound or documented-exempt in the same diff — the census
  output is appended to this list at work time).
- Pipeline artifacts: `knowledge-base/project/specs/feat-one-shot-8593-8080-witness/{tasks.md,decision-challenges.md,session-state.md}`.

## Files to Create

- `scripts/inngest-gate-witness-classify.sh` — extracted token→action classifier + `--selftest`.
- `apps/web-platform/infra/inngest-gate-witness-classify.test.sh` — decision table + lib census suite.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change: a CI lint widened, one
cron-workflow arm added, shell/test files only. No user-facing surface, no legal/compliance doc
wording, no ops procedure change. Mechanical UI-surface override scan: no `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx` in the file lists — Product tier NONE.

## Acceptance Criteria

- [ ] AC1 — `findUnboundedEnumerations` (or the widened detector set) returns RED on synthesized
  fixtures for each matrix row 1–7 shape, and PASS on the must-PASS inputs (row 8), inside
  `bun test plugins/soleur/test/components.test.ts`.
- [ ] AC2 — `EXEC_SURFACE_GLOBS` admits `.github/scripts/**/*.sh` (minus `*/test/`) and
  `apps/web-platform/server/inngest/functions/*.ts`; a `.ts` `//`-comment fixture produces zero
  probes.
- [ ] AC3 — `bun test plugins/soleur/test/components.test.ts` fully green, including the
  `toEqual([])` corpus offender assertions over the widened corpus.
- [ ] AC4 — Each of the six named sites carries an explicit bound (`--limit N ≥ 100`, `--paginate`,
  or existence-drill rewrite): the two `for n in $(gh issue list …)` loops, `review-reminder.yml`,
  `strategy-review-check.sh`, `codeql-to-issues.yml`, `cron-follow-through-monitor.ts`.
- [ ] AC5 — The A3 census ran; every newly-flagged site beyond the six is either bounded in this PR
  or carries a documented exclusion comment+test entry with rationale. The census output (site →
  disposition) is recorded in the PR body or a spec artifact.
- [ ] AC6 — `scheduled-inngest-health.yml` contains the witness arm: `monitor-streak-state.sh
  fetch/seal/assert` wired to artifact `inngest-gate-witness-streak` (90-day retention, overwrite),
  two `betterstack-query.sh` reads with rc-capture + stderr classification, the
  `inngest_execute_registry_gate` call (report-only — its exit code cannot fail the step or dispatch
  an op), the classify step, and the `#8080 gate-witness token=` log line.
- [ ] AC7 — Filing semantics: streak ≥ 8 consecutive `refusal` verdicts files/comments the
  `ci/inngest-gate-witness` + `action-required` + `priority/p2-medium` issue; `dark` resets the
  streak and auto-closes an open witness issue; armed-class flag (`flag_armed` or armed-class
  `cutover_flag`) suppresses both increment and filing. Filing/close steps carry status-check `if:`
  conditions (alarm-issue-filing-guard green) and a `steps.witness.outcome` crash arm exists.
- [ ] AC8 — `bash apps/web-platform/infra/inngest-gate-witness-classify.test.sh` green: decision
  table covers every `_ihdg_verdict` token in the lib (census-derived), Guard-2 matrix rows drive
  RED, unknown token → `refusal`.
- [ ] AC9 — `scripts/inngest-gate-witness-classify.sh --selftest` prints
  `inngest-gate-witness-classify selftest: ok` (the Observability discoverability probe).
- [ ] AC10 — PR body: `Closes #8593` on its own line and `Refs #8080` (#8080 stays open; its
  unit-template half is the carrier batch). `Refs #8594` optional.
- [ ] AC11 — No `MUT_SKIP`/`*_GUARD_*` literal in any workflow file's executable text; no `env -u`
  run-line prefixes; no `grep | grep -q` predicate; no `inngest_luks_key_probe_dark` text anywhere
  in the diff.
- [ ] AC12 — Diff scope: product-code changes confined to the Files to Edit/Create lists above plus
  census-appended sites; `infra-validation.yml` is NOT touched (filesystem registration covers the
  new suite).

## Test Scenarios

- **unit** — Given the synthesized fixture corpus, when `findUnboundedEnumerations` runs, then each
  matrix row's expected verdict is produced (red on rows 1–7, pass on row 8).
- **unit** — Given `inngest-gate-witness-classify.sh`, when fed each lib token + flag-class
  combination, then the decision-table mapping is produced (satisfy/refusal/suppressed; unknown →
  refusal).
- **unit** — Given the lib's `_ihdg_verdict` census, when the suite derives the token set, then a
  classifier missing an arm is RED (harness-vacuity row 6).
- **integration** — `vitest run test/server/inngest/cron-follow-through-monitor.test.ts` green after
  the prompt `--limit` additions (substring pins unaffected).
- **integration** — `bash scripts/alarm-issue-filing-guard.test.sh` green over the edited workflow
  (new filing/close steps satisfy the status-check + producer-liveness rules).
- **integration** — `bash scripts/lint-betterstack-emitter-read.test.sh` (or its IV-shard leg) sees
  the new BS reads carrying the same rc+stderr-classify discipline as the dedicated arm.

## Context

- Standing batching ruling:
  `knowledge-base/project/specs/archive/20261031-194207-feat-one-shot-11528-8841-9139-batch1/decision-challenges.md`
  (PR2 #8593+#8080-witness; PR3 #8595 gated on #11653 — now merged but still a separate PR).
- Gate lib: `tests/scripts/lib/inngest-host-dark-gate.sh` (`inngest_execute_registry_gate` ~:740;
  `_erg_flag_class` ~:658; `_ihdg_verdict` ~:570). Header documents the #8316 retirement.
- Registry-probe arm (`op=registry-probe`, `scripts/cutover-inngest.sh` ~:1449-1500): the manual
  read-only sibling whose plumbing the witness mirrors (BS reads → gate → emit-file fields → token
  case).
- Streak machinery: `scripts/monitor-streak-state.sh` + `scheduled-rehearsal-skip-monitor.yml` (the
  artifact carrier pattern and its accepted-residuals documentation to mirror).
- Stale citation check performed 2026-11-01: all `knowledge-base/` paths cited above verified to
  exist.

## References

- #8593 (gate widening), #8080 item 1 (witness), #10390 (epic), #8054/#8017 (the cutover-day
  discoveries the witness replaces), #8316 (`inngest_host_dark_gate` retired), #8594 (overlap),
  #11695 (batch-1 precedent), ADR-296, ADR-252, ADR-199, ADR-100.

## Deepen-Plan Run Record (2026-11-01)

`soleur:deepen-plan` halt-gate outcomes, verified mechanically against this file:

- **4.4 Precedent-diff:** precedent exists and is cited (dedicated-host arm, `op=registry-probe`
  plumbing, `monitor-streak-state.sh` + `scheduled-rehearsal-skip-monitor.yml`). Scheduled-work
  check: the witness attaches to an existing `*/15` workflow — no new scheduled job; the file's own
  header carries the standing `new-scheduled-cron-prefer-inngest` override (an external monitor
  cannot run on the thing it monitors).
- **4.5 Network-outage:** incidental `timeout` mention only (advisory CI shard reds) — plan does not
  address a connectivity symptom; gate not applicable.
- **4.55 Downtime & Cutover:** no host replace, migration DDL, or serving-surface swap — skipped.
- **4.6 User-Brand Impact:** section present, threshold `aggregate pattern` — pass.
- **4.7 Observability:** 5 fields present, `command` first token `bash` (allowlisted), no `ssh`,
  sub-15 s selftest, `expected_output` a literal — pass.
- **4.8 PAT sweep:** zero hits — pass.
- **4.9 UI wireframe:** no UI-surface files — skipped.
- **4.10 Encryption Posture:** no `.tf`/`.sql`/cloud-init/store-class file; witness reads an existing
  BS source over the existing transport — skipped.
- **4.11 Guard Contract:** `python3 scripts/lint-guard-contract.py` green (2 guard entries);
  assemblies are chokepoint-structural (extractor + corpus; lib-derived token census).
- **4.12 Scope Check:** exactly one unfenced section, all asks mapped or justified-inferred,
  `Recommendation: single PR` — pass.
- **4.13 Task Design:** detection is file-list+diff scoped — no new workflow file, no new
  `schedule:`/`on:` trigger, no new function file, no registry/pg_cron/timer/daemon — skipped.
- **Fan-outs (Phases 2–6 research/review agents) not executed:** the planning subagent has no
  nested-spawn tool; deferred to the parent pipeline per the batch-1 precedent — recorded in
  `specs/feat-one-shot-8593-8080-witness/decision-challenges.md`.
- **4.45 realism passes (run inline):** "report-only" claim verified — the gate lib is a pure
  file-grading function with no op dispatch; "filesystem registration" verified against ADR-252's
  own comment block in `infra-validation.yml` (`deploy-script-tests` job, `git ls-files` glob);
  `inngest_host_dark_gate` retirement verified at the lib header; no dropped symbols to sweep.
