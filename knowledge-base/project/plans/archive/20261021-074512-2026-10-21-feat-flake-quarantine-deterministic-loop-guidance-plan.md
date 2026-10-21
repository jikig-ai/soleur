---
title: "feat: flake-quarantine + deterministic-loop guidance for user repos (Epic #10397 child 6)"
type: feat
date: 2026-10-21
slug: feat-flake-quarantine-deterministic-loop-guidance
branch: feat-one-shot-10403-flake-quarantine-guidance
issue: 10403
closes: 10403
lane: cross-domain
---

## Overview

Ship flake-quarantine and test-determinism guidance to Soleur plugin users
(Epic #10397 child 6). Today `soleur:test-fix-loop` iterates on test failures
but has no flake-isolation protocol: a failure that passes on retry is
indistinguishable from a fixed one, so an agent learns to retry until green
instead of fixing the underlying nondeterminism. `soleur:engineering:review:test-design-reviewer`
scores Repeatable but nothing prescribes the determinism disciplines (seeded
randomness, frozen clocks, controlled networking, state isolation, terse
failure output) that make a test repeatable. Soleur's own corpus encodes this
internally (`wg-when-a-test-runner-crashes`, the scheduled-integration-suites
workflow, the `flaky` label) but ships none of it. This plan adds a
flake-detection → quarantine step to `test-fix-loop`, a determinism-checklist
reference consumed by `test-design-reviewer` and `soleur:qa`, and a `flaky`
label convention for user repos. Informed by live flake #10649
(`scripts/test-all-orphan-log-retention`: green locally and on branch CI, red
on merge-group runs — the exact pass-on-retry shape this guidance targets).

## Research Insights

### Premise Validation (Phase 0.6)

Checked every reference the issue cites:

- **#10403** OPEN; epic **#10397** OPEN (child 6 of the "Plugin shipped to
  users" group); siblings #10401 and #10402 already merged as PRs #10727 and
  #10735 — the shipped-guidance pattern this child follows is proven twice.
- **`plugins/soleur/skills/test-fix-loop/SKILL.md`** exists (150 lines, 14 207
  bytes). Its only `flak*` token is the API-budget paragraph's
  "perpetually-flaky test command" — **no flake-isolation semantics today**.
  The §2 termination table's `All tests pass` row treats `rc` 0 as success
  with no pass-on-retry discrimination. Premise holds.
- **`plugins/soleur/agents/engineering/review/test-design-reviewer.md`**
  exists (148 lines): scores Farley `Repeatable` and has flake-adjacent
  guidance (wall-clock equality, `happy-dom` blockade learnings) but **no
  prescribed determinism checklist**. Premise holds.
- **`plugins/soleur/skills/qa/SKILL.md`** exists (263 lines): has
  flake-*discrimination* prose in two places — Step 2.6's "Discriminate a
  real fail from an env flake" (#5009 discriminator) and the Notes bullet on
  the resource-starved local false-fail — but **no determinism hygiene
  reference**. Premise holds.
- **`wg-when-a-test-runner-crashes-segfault-oom`** exists at
  `AGENTS.rules.md:83` — repo-internal rule, unshipped. Premise holds.
- **`.github/workflows/scheduled-integration-suites.yml`** exists — the
  internal machinery: dedicated issue label, file-or-comment dedup, and an
  auto-close-stale arm on green ("a transient flake leaves a permanently
  open issue and trains the label to be ignored"). Premise holds; the
  patterns to ship are the label + the file/dedup/auto-close protocol.
- **`flaky` label** exists in this repo (`Intermittently-failing test`,
  #FBCA04) — the convention to mirror is real.
- **#10649** OPEN — the live flake informing this guidance: same suite green
  locally + on branch battery, red on three merge-group groups with
  unrelated diffs. Not fixed by this child (guidance-only scope), but its
  shape (timing-sensitive watchdog suite on shared runners) feeds the
  checklist's contention axis.
- **ADR-corpus check (proposed mechanism):** the mechanism — a new
  `references/*.md` under an existing skill plus pointer edits — is the
  exact shape #10401 (`plan/references/differential-migration-testing.md`)
  and #10402 (`test-browser/references/feature-map.md`) shipped this week.
  No ADR rejects it. ADR-177 (terminated = UNRESOLVED, not failed) and
  ADR-230 (probes are not fixes) are the two semantics the quarantine step
  must stay consistent with.

### Mechanism Minimality (Phase 0.6b)

**Property list** (what the ask actually requires):

1. A failure that passes on retry inside `soleur:test-fix-loop` is treated
   as a flake to isolate/track — never counted as resolved.
2. A determinism checklist exists (seeds, clocks, network, state isolation,
   output terseness) and is reachable by `test-design-reviewer` and `qa`.
3. (Optional in the ask) a `flaky` label convention for user repos.

**Mechanisms the ask names → coverage check:**

- test-fix-loop SKILL.md quarantine step → property 1; no existing coverage
  (verified: SKILL.md §2 has no pass-on-retry row).
- New reference doc → property 2; no existing coverage (`qa/references/`
  holds only `browser-preflight.md`; `test-fix-loop/` has no `references/`;
  test-design-reviewer's Repeatable scoring cites no checklist).
- `flaky` label convention paragraph → property 3; no shipped coverage.

**Cut list:** none. A new skill was pre-emptively cut by the issue itself
("No new skills unless the reference grows past reference-size") — the
reference stays in `references/`, not a new skill dir.

### Repo conventions that bind the implementation

- **Mirror trees propagate automatically.** `plugins/soleur/opencode/` and
  `plugins/soleur/cursor/` carry thin-pointer stubs (verified:
  `cursor/skills/soleur-test-fix-loop/SKILL.md` and both
  test-design-reviewer mirrors just say "Read the canonical file"). Edit the
  canonical files only; no mirror edits.
- **`references/` reachability gate** (`plugins/soleur/test/components.test.ts:260`):
  every `references/*.md` basename must be named from ≥1 other file in the
  same skill dir — the new file must be linked from
  `test-fix-loop/SKILL.md` (or a sibling file under `test-fix-loop/`).
- **No backtick refs** (`components.test.ts:235`): reference paths must be
  markdown links — `[name.md](./references/name.md)` inside the owning
  skill; `${CLAUDE_PLUGIN_ROOT}/skills/...` form for cross-skill links
  (learning: template-copied links use plugin-root form, #10401).
- **Byte ceiling — the sharpest constraint.** `qa` is a lifecycle SKILL.md
  under `scripts/lint-skill-body-budget.py` (merge-base-anchored, one-sided
  ratchet): ceiling **37 000 B**, current **36 940 B** → **60 B headroom**.
  A qa pointer must be woven into an existing line net-near-zero (the Step
  2.6 flake discriminator or the Notes #5009 bullet are the natural homes),
  or a swap that frees bytes in the same bullet. `test-fix-loop` is NOT in
  the ceiling set (row set = workflow-transitions keys ∪ destinations ∪
  ONE_SHOT_CHILD_SKILLS) — it may grow freely.
- **No `description:` edits planned** → skill-description budget check
  (Phase 1.8) does not apply; `test-fix-loop` is in
  `AUTONOMOUS_LOOP_SKILLS` already (budget paragraph present).
- **README component counts** count skills/agents/commands dirs only —
  a `references/` file changes nothing.

### Applicable institutional learnings

- `test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md`
  — contention flakes have *multiple* mechanisms (intra-test wait budgets
  vs cold-import cost); a quarantined flake needs mechanism-level triage,
  not a timeout bump. Feeds the checklist's contention/ordering axis.
- `2026-05-20-happy-dom-ws-fetch-blockade.md` — DOM emulators ship *real*
  network adapters; deterministic isolation needs a fail-loud network
  blockade. Feeds the network axis.
- `test-failures/2026-05-30-shared-live-db-integration-test-cross-service-clock-skew-flake.md`
  — cross-service clock skew; feeds the clocks axis.
- `2026-05-11-rename-fixture-beats-regex-for-rng-substring-flake.md` —
  unseeded RNG substring collisions; feeds the seeds axis.
- `2026-06-03-shared-hook-fetch-coalescing-and-e2e-flake-isolation.md` —
  e2e infra-flake vs regression discrimination (the #5009 shape qa already
  encodes).
- `2026-06-29-review-rate-limit-fallback-and-wallclock-exact-assertion-flake.md`
  — bound measured values, never exact-equality (already cited in
  test-design-reviewer).
- `2026-09-29-i-pinned-a-flake-class-with-a-weaker-fork-of-the-detector-we-already-had.md`
  — detector-drift caution: reuse the canonical detector (the
  `pass-on-retry` detection the loop adds should reuse its existing
  failure-set bookkeeping, not fork a new signal).
- `test-failures/2026-04-19-retry-once-early-return-masks-first-attempt-failures.md`
  — retry masks first-attempt failures: the core pathology this child
  names.
- `2026-10-11-a-fake-that-ignores-its-selectors-lets-every-selector-mutation-pass.md`
  — a fix-round itself introduced a pipefail flake; the checklist's
  "output terseness" axis (quiet flags, terse failure output) applies to
  the loop's own output handling too.

### Related issues / PRs

- #10397 (epic, open), #10403 (this, open), #10649 (live self-side flake,
  open — informs, not fixed here).
- Sibling shipped refs: `plugins/soleur/skills/plan/references/differential-migration-testing.md`
  (#10727) — carries the `Source:` footer convention for Osmani-derived
  guidance; `plugins/soleur/skills/test-browser/references/feature-map.md`
  (#10735).
- ADR-177 (KILLED ≠ failed taxonomy), ADR-230 (probes ≠ fixes), ADR-133
  (test-all tmpfs contention — merge-group load context for #10649).

### Community discovery (Phases 1.5 + 1.5b)

- Stack check: no uncovered stacks (TypeScript/bash repo; no flutter/rust/
  go/elixir/swift/kotlin/php signatures). Phase 1.5 skipped.
- Functional overlap: `flaky-test-triage` (pnakhat/qa-ai-repo) on
  claudepluginhub — real functional overlap (pass-on-retry detection,
  quarantine-with-owner+SLA, never-blanket-retries, N-green un-quarantine)
  but **Tier 3 / unverified (2 stars, 0 installs) → discarded per trust
  model, never suggested**. Its description independently validates the
  design vocabulary this plan uses. `e2e-testing-patterns` (@wshobson) and
  `playwright-expert` (@Jeffallan) are verified-tier but only tangent
  (debugging flaky *browser* tests, not loop quarantine semantics). No
  installs.

### Research decision (Phase 1.6)

**External research: skipped.** Strong local context — the issue names the
exact files, the sibling PRs demonstrate the shipped shape, and the Osmani
source article is already cited by the sibling reference. External research
adds nothing the corpus doesn't already carry.

## Problem Statement / Motivation

An agent that iterates on a flaky suite learns the wrong lesson: retry until
green. Inside `soleur:test-fix-loop` today, a failure that disappears on the
next run is indistinguishable from a fixed one — the `All tests pass` row at
`plugins/soleur/skills/test-fix-loop/SKILL.md` §2 declares success with no
discrimination between "the fix worked" and "the failure was nondeterministic
and will be back". The user's suite keeps its flake, the loop reports SUCCESS,
and the next run — or the next user — hits it again. That is the exact
anti-pattern the Osmani article's "fast and deterministic" section warns
against, and this repo already pays the tax: `wg-when-a-test-runner-crashes`,
the scheduled-integration-suites file/dedup/auto-close machinery, and the
`flaky` label all encode the quarantine discipline internally but ship none of
it to plugin users.

`test-design-reviewer` scores Farley's `Repeatable` property, and `soleur:qa`
carries two flake-discrimination passages (#5009 shape), but nothing tells
either one *which* disciplines make a test deterministic — seeded randomness,
frozen clocks, controlled networking, state isolation, terse failure output —
so the review signal "this test is flaky-shaped" has no prescribed remediation
to point at.

## Proposed Solution

Three deliverables, all inside the existing plugin tree (no new skills):

1. **A flake-quarantine step in `test-fix-loop`.** A new detection arm
   placed as the **final sub-step of §1 Parse Failures** — parse → screen →
   the failure set §2's termination table and §3's clustering both read is
   the *post-screen* set (the quarantined set persists for the run: a test
   quarantined in iteration N stays excluded from N+1's delta counts). The
   screen runs only after the `Suite terminated` row has had its say (a
   KILLED / `rc` 3 suite stays UNRESOLVED per ADR-177 and never enters flake
   screening; build/compile errors likewise route straight to the fix path —
   there is no single test to isolate). For each newly-failed test — keyed
   by **file + test name** (the same `it()` title in two files is two
   distinct entries, not one flake) — the
   loop re-runs *that test in isolation* — the same runner's filter flag
   (`vitest -t`, `pytest -k`, `go test -run`, `bun test -t` /
   `--test-name-pattern` — the bun flag verified locally 2026-10-21 against
   bun 1.4.3's `--help`; when the runner cannot filter, one suite-level
   re-run of unchanged code answers the same question by absence). **A pass
   on that retry — same code, no fix
   applied — is a flake signature.** An isolated re-run that itself errors
   or times out is NOT a pass: the failure stays on the fix path. Mixed
   sets compose per-test — passers quarantine, failers proceed to §3.
   The loop then, per quarantined test:
   (a) *quarantines* it — removes it from the failure set driving
   fix/cluster bookkeeping and from the delta counts (a quarantined flake
   can never count toward "fixed" nor falsely trip the `Circular fix` row);
   (b) *files* it — a GitHub issue via `gh` when a GitHub remote exists,
   titled `flake: <test> — <signature>`, deduped by an open-issue search on
   that title first (comment on the existing tracker instead of a duplicate,
   mirroring `scheduled-integration-suites.yml`), with the `flaky` label
   (create-then-add, mirroring this repo's `Intermittently-failing test` /
   #FBCA04 convention, never rewriting an existing label), body carrying the
   pass-on-retry signature, the runner command, and the
   determinism-checklist pointer; with no `gh`/remote, the quarantine is
   report-only and says so;
   (c) *reports* it — a `Quarantined flakes:` block in the Diagnostic Report
   naming each test + its issue, and a `Key Principles` line: "Pass-on-retry
   is a flake to quarantine, not a fix to report".
   Once quarantined, a test stays quarantined for the run (its issue tracks
   it) — a later re-failure is noted in the report and the filed issue, not
   re-entered for fixing; if the flaked test's path intersects files the
   loop's own commits touched, the report flags **possible
   diff-interaction** (quarantine must never launder a real regression this
   branch caused). Quarantine is bookkeeping + tracker + report — it never
   edits, skips, or deletes a test file, and it consumes no fix-round tally
   (no fix was attempted). If every failure quarantines and the suite then
   reads `rc` 0, the result is `SUCCESS (N quarantined — issues #…)` —
   never a silent green. A suite that surfaces a fresh flake signature on
   every re-run converges to the iteration cap and its report enumerates
   every quarantined name — the honest ceiling, not a hang. On
   NON_CONVERGENCE / MAX_ITERATIONS the report's
   Recommendation names remaining failures as load-only flake candidates to
   review against the checklist — the isolated re-run under-detects the
   contention class (#10649 shape: fails only under suite load), and the
   honest answer there is a determinism fix to the test, not retry.
2. **A determinism-checklist reference** at
   `plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md`
   (~150 lines): the five axes the issue names (seeded randomness, frozen
   clocks, controlled networking, state isolation, output terseness/quiet
   flags) plus a contention/ordering axis (the #10649 shape — shared-runner
   load boundaries, per the two-mechanism learning), the quarantine protocol
   (isolate → file → label → N-consecutive-green auto-close convention
   adapted from `scheduled-integration-suites.yml`), and the Source footer
   convention matching `differential-migration-testing.md`.
3. **Consumer wiring.** A pointer + Repeatable-side WARN rule in
   `test-design-reviewer.md` (a new test carrying flake-signal sources with
   no determinism control is WARN; cite the checklist), and a byte-budgeted
   pointer woven into `qa/SKILL.md`'s existing #5009 flake-discrimination
   prose (≤ 60 B net — the merge-base ceiling leaves no more; trim a
   redundant clause in the same bullet if the link needs the room).

## Technical Considerations

- **The quarantine step is prose-to-agent, not code.** The hard part is the
  semantics, not the mechanism: the pass-on-retry detector must reuse the
  loop's existing failure-name bookkeeping (the §2 comparison machinery)
  rather than fork a second signal — the detector-fork learning
  (`2026-09-29-…weaker-fork`) applies verbatim.
- **`NEVER modify test files` stays absolute.** Quarantine is bookkeeping +
  tracker + report — the step must not prescribe skip annotations, test
  deletion, or `@flaky` code tags as loop actions (a tag convention may be
  *described* in the reference as user-side hygiene, never as a loop edit).
- **Bounded cost:** one isolated re-run per *new* failure name, inside the
  existing iteration — not a retry loop; the `max iterations` cap and the
  pipeline tally are untouched.
- **qa/SKILL.md is at 36 940/37 000 B.** The pointer edit must measure
  net growth ≤ 60 B (`wc -c` against the merge-base file); prescribe the
  anchor line (Step 2.6 `#5009` discriminator or the Notes false-fail
  bullet) and the trim-in-place tactic.
- **No `description:` frontmatter edits** anywhere → the word-budget gate
  is untouched. No README component-count changes (a `references/` file is
  not a component). Mirror trees (`opencode/`, `cursor/`) propagate via
  their pointer stubs — no edits there.
- **NFR:** none — shipped markdown/prose only.

## User-Brand Impact

- **If this lands broken, the user experiences:** either the gap persists
  silently (same as today), or a misprescribed version — e.g. a quarantine
  step that teaches the user's loop to file *real* failures as flakes,
  producing false-green SUCCESS reports that hide regressions. The failure
  mode is degraded guidance quality, bounded by the Diagnostic Report still
  naming every quarantined test (the report is the visible artifact).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — docs-only change inside shipped skill/agent text; no
  credentials, no user data, no runtime behavior change to this repo's own
  CI.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is prose in the
  plugin distribution channel — a wrong instruction degrades a user's loop
  output quality; it cannot breach data or production, so `none` not
  `single-user incident`.

## Files to Create

- `plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md`
  — the determinism checklist + quarantine-protocol reference (~150 lines).

## Files to Edit

- `plugins/soleur/skills/test-fix-loop/SKILL.md` — new flake-detection →
  quarantine arm in the Phase-1 loop (before §3 clustering), a
  `Quarantined flakes:` block in the Diagnostic Report contract, a
  `flaky`-label convention note (create-then-add, mirror the repo's label),
  a Key Principles line, and the markdown-link naming the new reference
  (satisfies the reachability census). ~35 lines added.
- `plugins/soleur/agents/engineering/review/test-design-reviewer.md` — a
  Repeatable-side WARN rule for determinism-signal tests + the checklist
  pointer (~12 lines).
- `plugins/soleur/skills/qa/SKILL.md` — one pointer to the checklist woven
  into existing flake-discrimination prose, **net ≤ 60 B** growth (byte
  ceiling: 36 940 → ≤ 37 000).

## Implementation Phases

### Phase 1 — Author the reference

Write `plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md`:
flake signatures (pass-on-retry, order-dependence, environment-dependence),
the quarantine protocol (isolate → file → `flaky` label → auto-close on
N consecutive greens, adapted from `scheduled-integration-suites.yml`), and
the determinism checklist proper — seeded RNG, frozen clocks, controlled
networking (fail-loud blockades, per the happy-dom learning), state
isolation, terse failure output (quiet flags — feeds the loop's own
parse-failures step), contention/load boundaries (#10649). Source footer:
Osmani, *Agentic Verification*.

### Phase 2 — Wire the loop

Edit `test-fix-loop/SKILL.md`: the isolated-re-run detection arm, the
quarantine action (tracker filing + `flaky` create-then-add + report-only
fallback), failure-set exclusion semantics (no Circular-false-positive, no
counting-as-fixed), the Diagnostic Report `Quarantined flakes:` block, the
Key Principles line, and the `[determinism-checklist.md](./references/determinism-checklist.md)`
link.

### Phase 3 — Wire the consumers

`test-design-reviewer.md`: WARN rule + pointer. `qa/SKILL.md`: the ≤ 60 B
pointer edit.

### Phase 4 — Verify

Run the checks in Acceptance Criteria: components test (reachability +
no-backtick), body-budget lint against merge base, full-suite content pins
that read test-fix-loop (`fullsuite-merge-gate.test.ts` asserts the
`affected-tests.sh` token survives), and a read-through of the edited loop
for the two-path walk (fail-again → fix path; pass-on-retry → quarantine).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 cap) searched
against all four planned paths; zero bodies reference them.

## Observability

The shipped surface is agent-facing prose plus a reference doc;
"observability" is whether the landed convention stays mechanically wired —
the references-reachability census and the body-budget lint are the
enforcement layer and this block declares the probe.

```yaml
liveness_signal:
  what: "`test-fix-loop/references/determinism-checklist.md` exists and is named (markdown link) from `test-fix-loop/SKILL.md`; `test-design-reviewer.md` and `qa/SKILL.md` both cite it"
  cadence: "per-PR: components.test.ts references-reachability census + lint-skill-body-budget.py on plugin diffs"
  alert_target: "CI check failure (plugin test shard / lint)"
  configured_in: "plugins/soleur/test/components.test.ts + scripts/lint-skill-body-budget.py (pre-existing — no new guard added by this diff)"
error_reporting:
  destination: "CI job log — census failure names the orphaned reference path; budget lint names the over-ceiling file"
  fail_loud: "yes — orphan references and budget overruns are suite failures, not warnings"
failure_modes:
  - mode: "reference file orphaned (a later diff deletes the SKILL.md pointer)"
    detection: "components.test.ts references-reachability census"
    alert_route: "CI red on the next diff touching the plugin shard"
  - mode: "qa/SKILL.md edit pushes the body over its 37,000 B ceiling"
    detection: "scripts/lint-skill-body-budget.py --base <merge-base>"
    alert_route: "CI red"
  - mode: "a consumer pointer rots (skill path renamed)"
    detection: "AC4/AC5 battery — basename literal present in SKILL.md, test-design-reviewer.md, qa/SKILL.md"
    alert_route: "review-time AC check"
logs:
  where: "CI job log (suite assertion lines)"
  retention: "GitHub Actions retention"
discoverability_test:
  command: "grep -q 'determinism-checklist.md' plugins/soleur/skills/test-fix-loop/SKILL.md && grep -q 'determinism-checklist.md' plugins/soleur/agents/engineering/review/test-design-reviewer.md && grep -q 'determinism-checklist.md' plugins/soleur/skills/qa/SKILL.md && echo checklist-wired"
  expected_output: "checklist-wired"
```

## Guard Contract

This plan ships no new guard; its diff is made safe by two **pre-existing**
enforcement surfaces plus the AC battery. Each is recorded because the plan's
correctness claims stand on them.

### Guard 1 — References-reachability census (`plugins/soleur/test/components.test.ts`)

**Property.** Every `references/*.md` inside a skill directory is named (by
basename substring) from another file in the same skill directory — the new
`test-fix-loop/references/determinism-checklist.md` can never ship orphaned.

**Assembly.** The suite walks every skill directory's `references/` (depth
< 2) and asserts each basename appears in a same-skill sibling file — a
census over the live tree, not a pinned name list. `test-fix-loop/` gains
its first `references/` member via this diff; the
`[determinism-checklist.md](./references/determinism-checklist.md)` link in
SKILL.md is the naming surface.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Create `references/determinism-checklist.md` with no SKILL.md link | RED — census reports the orphan reference |
| 2 | Rename the file so the basename no longer matches the link text | RED — census reports the orphan |
| 3 | Add a second `references/*.md` later with no naming surface | RED — same census, second member |
| 4 | Point the link at `./references/determinism-checklist.md` using backticks instead of a markdown link | RED — no-backtick convention test (`components.test.ts`) |

### Guard 2 — SKILL body-budget lint (`scripts/lint-skill-body-budget.py` + `plugins/soleur/test/skill-body-budget.json`)

**Property.** `qa/SKILL.md` body stays ≤ 37,000 B — the pointer must fit
inside the ~60 B headroom or carry a same-bullet trim.

**Assembly.** The lint compares the working-tree byte count of every
ceiling-keyed lifecycle SKILL.md against the merge-base-anchored ceilings
table; `qa` is a ceiling key (36,940 B today). `test-fix-loop` is NOT keyed —
edits there are unbounded by this guard.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | `qa` pointer added as a new paragraph, net growth > 60 B | RED — body exceeds ceiling |
| 2 | Ceiling table hand-edited upward to fit the edit | RED at review — the table ratchets down only; a raise is a separate reviewed PR |
| 3 | Pointer lands in `test-design-reviewer.md` but `qa/SKILL.md` is skipped entirely | RED at review — AC4 unmet; consumer wiring incomplete |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "test-fix-loop treats a pass-on-retry as a flake to isolate/file, never as resolved." [issue #10403, Acceptance] | FR-1 / Phase 2 / Files-to-Edit `test-fix-loop/SKILL.md` | mapped |
| 2 | "Determinism checklist exists (seeds, clocks, network, state isolation, output terseness)." [issue #10403, Acceptance] | FR-2 / Phase 1 / Files-to-Create `determinism-checklist.md` | mapped |
| 3 | "No new skills unless the reference grows past reference-size." [issue #10403, Acceptance] | Constraint — no skill dir created; reference bounded ~150 lines | mapped |
| 4 | "a determinism checklist reference consumed by `test-design-reviewer`/`qa`" [issue #10403, Scope] | FR-3 / Phase 3 / Files-to-Edit `test-design-reviewer.md` + `qa/SKILL.md` | mapped |
| 5 | "Optionally a `flaky` label convention mirroring this repo's own label." [issue #10403, Scope] | FR-1(b) label step + reference convention section | mapped |
| 6 | "Edits to `test-fix-loop` (flake detection → quarantine step, not silent retry)" [issue #10403, Scope] | FR-1 / Phase 2 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `references/determinism-checklist.md` (create) | "a determinism checklist reference" | asked |
| `test-fix-loop/SKILL.md` quarantine step (edit) | "flake detection → quarantine step, not silent retry" | asked |
| `test-design-reviewer.md` pointer+WARN (edit) | "consumed by `test-design-reviewer`/`qa`" | asked |
| `qa/SKILL.md` pointer (edit) | "consumed by `test-design-reviewer`/`qa`" | asked |
| `flaky` label create-then-add step | "a `flaky` label convention mirroring this repo's own label" | asked |
| Isolated re-run detector inside the step | "pass-on-retry" | inferred — justification: pass-on-retry cannot be *observed* without a second run of the same code; one bounded isolated re-run is the detection mechanism the asked-for semantics require. |
| Report-only fallback when no `gh`/remote | — | inferred — justification: the loop runs on arbitrary user repos; a quarantine step that hard-requires a GitHub tracker would crash or silently skip on non-GitHub hosts (safety/robustness dependency). |
| Auto-close-on-green convention in the reference | — | inferred — justification: mirrors `scheduled-integration-suites.yml`'s stale-tracker arm the issue cites as existing internal encoding ("Internally … scheduled-integration-suites encode this"). |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 4 | Estimated changed lines: ~200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] **AC1 — quarantine step shipped.** `test-fix-loop/SKILL.md` contains a
  flake-detection arm prescribing: one isolated re-run per newly-failed
  test; pass-on-retry → quarantine (never counted as resolved/fixed); the
  step never prescribes modifying, skipping, or deleting test files.
- [ ] **AC2 — checklist exists with the five axes.**
  `plugins/soleur/skills/test-fix-loop/references/determinism-checklist.md`
  exists and covers: seeds, clocks, network, state isolation, output
  terseness — plus a contention axis and the quarantine protocol
  (file + `flaky` label + auto-close-on-green convention), and carries the
  `Source:` footer naming the Osmani article.
- [ ] **AC3 — test-design-reviewer consumes it.** The agent file links the
  checklist and adds a Repeatable-side WARN for determinism-signal tests
  (unseeded RNG / wall-clock reads / real network / shared mutable state /
  nondeterministic output with no control).
- [ ] **AC4 — qa consumes it within budget.** `qa/SKILL.md` names the
  reference inside existing flake-discrimination prose, and the file
  measures ≤ 37 000 bytes (`wc -c`; ceiling in
  `plugins/soleur/test/skill-body-budget.json`).
- [ ] **AC5 — reachability + lint gates green.**
  `bun test plugins/soleur/test/components.test.ts` passes (the new
  `references/*.md` is named by basename inside `test-fix-loop/` and no
  backtick `references/` refs were added), and
  `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0.
- [ ] **AC6 — report names quarantined flakes.** The Diagnostic Report
  contract gains a `Quarantined flakes:` enumeration — a `SUCCESS` result
  with quarantines must render them (never bare).
- [ ] **AC7 — no new components.** No new directories under
  `plugins/soleur/skills/` or `plugins/soleur/agents/`; README component
  tables unchanged (no skill/agent/command count moves).
- [ ] **AC8 — existing invariants preserved.** `test-fix-loop` still names
  `affected-tests.sh` (fullsuite-merge-gate pin), still requires a clean
  tree, still forbids test-file edits; the `AUTONOMOUS_LOOP_SKILLS` budget
  paragraph is intact.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** (CTO domain leader, executed in-process per harness note)
Complexity: small. The load-bearing risk is bookkeeping semantics, not
mechanism — the quarantined set must stay out of the §2 delta/Circular
comparisons without ever counting as "fixed", and must re-enter if a code
change plausibly intersects it (a pass-on-retry is weak evidence; the diff
may interact). Detector reuses the loop's own failure-name bookkeeping — no
forked signal (2026-09-29 learning). The `gh`-absent arm is report-only and
says so. No new substrate, trust boundary, or data model → no ADR. No
capability gaps; all consumers exist.

No Product/UX gate: zero UI-surface files in Files to Create/Edit (markdown
under `plugins/soleur/` only) — mechanical override does not fire; tier
NONE.

## Test Scenarios

All `unit` layer — the deliverable is plugin markdown verified by repo
gates, not runtime behavior.

- **S1 (AC1/AC6 trace).** Given the edited `test-fix-loop/SKILL.md`, when a
  reader traces a failure that fails the suite and passes an isolated
  re-run with no code change, then the text routes it to the quarantine arm
  (file + label + exclude + report), and no reading of the file counts it
  as fixed or silent.
- **S2 (AC1 negative).** Given the same file, when a failure re-fails the
  isolated re-run, then the text routes it to cluster→diagnose→fix
  unchanged.
- **S3 (AC2).** Given
  `grep -nE 'seed|clock|network|isolation|terse|quarantine|flaky'`
  on the new reference, when each axis is checked, then each has at least
  one prescriptive line (a test must fail absent coverage, not just absent
  words — deepen-plan verifies).
- **S4 (AC4).** Given `wc -c plugins/soleur/skills/qa/SKILL.md`, when the
  edit lands, then the count is ≤ 37 000 and the basename
  `determinism-checklist.md` appears in the file.
- **S5 (AC5).** Given `bun test plugins/soleur/test/components.test.ts`,
  when run post-edit, then the reachability census row for
  `test-fix-loop/references/determinism-checklist.md` is linked and the
  no-backtick rule stays green.
- **S6 (AC8).** Given `bun test plugins/soleur/test/fullsuite-merge-gate.test.ts`,
  when run post-edit, then the `affected-tests.sh` dispatch pin on
  `test-fix-loop/SKILL.md` still passes.
- **S7 (regression).** Given the §2 termination table, when `rc` is 3 or a
  `^[KILLED]` line is present, then the Suite-terminated row still fires
  before any quarantine logic (ADR-177 ordering preserved — a signal-killed
  suite is UNRESOLVED, never a "flake").

## Success Metrics

- A user-repo `test-fix-loop` run over a pass-on-retry failure produces a
  filed/labeled artifact + a named report line, not a silent green.
- `test-design-reviewer` and `soleur:qa` both have a prescribed checklist
  to cite when they detect flake-shaped tests.
- Zero new components; the diff is 4 files, ~200 lines.

## Dependencies & Risks

- **qa byte ceiling (60 B):** the pointer must be net-near-zero; if the
  trimmed phrasing cannot fit, the alternative is relocating the qa pointer
  into `qa/references/browser-preflight.md`… no — cross-file naming inside
  the skill dir satisfies *reachability* but not the consumer wire; keep
  the pointer in `SKILL.md` and free bytes in the same bullet.
- **`gh`-absent user repos:** handled by the report-only fallback; the risk
  is a user reading "quarantine" as "skip the test" — the reference must
  say explicitly the loop never edits test files.
- **Flake-definition drift:** the checklist lives next to the loop that
  uses it (co-location is the mitigation); the reachability census pins
  the link.
- **#10649 is not fixed here** — this child ships user-facing guidance; the
  self-side suite fix remains its own issue (see Non-Goals).

## Non-Goals

- Fixing `scripts/test-all-orphan-log-retention` / #10649 itself.
- Shipping a `flaky` CI *workflow* to user repos (the convention is
  documented in the reference; the workflow machinery stays Soleur-side).
- Auto-close machinery for user repos — described as a convention, not
  shipped code.
- Property-based testing / differential-migration / feature-map guidance —
  siblings #10400–#10402 own those.
- Any `description:` frontmatter change, new skill, or new agent.

## References & Research

- Issue: #10403; epic #10397; live flake #10649.
- Internal machinery mirrored: `AGENTS.rules.md:83`
  (`wg-when-a-test-runner-crashes`),
  `.github/workflows/scheduled-integration-suites.yml` (label + dedup +
  auto-close arms), repo label `flaky` (#FBCA04).
- Sibling shipped refs: `plugins/soleur/skills/plan/references/differential-migration-testing.md`,
  `plugins/soleur/skills/test-browser/references/feature-map.md`.
- Learnings: see `## Research Insights` §Applicable institutional learnings.
- Source: Addy Osmani, *Agentic Verification*
  (https://addyo.substack.com/p/agentic-verification).

## Enhancement Summary (deepen-plan, 2026-10-21)

### Gate results

- **§4.4 Precedent-diff:** pattern-bound behaviors are the `flaky`-label
  create-then-add (precedent: `reproduce-bug/SKILL.md` Phase 8's
  `action-required` label idiom — same `gh label create … || true` +
  `--add-label` shape) and the file/dedup/auto-close tracker protocol
  (precedent: `.github/workflows/scheduled-integration-suites.yml`). Both
  cited inline; no novel pattern introduced. No scheduled job added — the
  cron-pattern check is N/A.
- **§4.45 realism passes:** verify-the-negative — every `never`/`NOT` claim
  in the plan constrains the artifact being authored (the step must not
  prescribe test-file edits; the label step must not rewrite an existing
  label); none asserts a fact about existing code that a grep could
  contradict. Post-edit self-audit: no symbols dropped; no stale references.
- **§4.5 Network-outage:** trigger token `timeout` matched once — inside a
  learnings citation in Research Insights ("not a timeout bump"), not a
  connectivity symptom the plan addresses. Evaluated; not applicable.
- **§4.55 Downtime & Cutover:** no infra/DB/deploy operation → skip.
- **§4.6 User-Brand Impact:** PASS — section present, threshold `none`, no
  sensitive-path files touched (SENSITIVE_PATH_RE: zero matches on all four
  planned paths).
- **§4.7 Observability:** section added this pass — shipped `plugins/*/skills/`
  markdown does not meet the pure-docs exemption; 5-field block present,
  `discoverability_test.command` is a `grep`-led probe (<15 s, allowlisted
  verb), `expected_output` is the literal `checklist-wired`. PASS.
- **§4.8 PAT:** zero matches → PASS.
- **§4.9 UI-wireframe:** no UI-surface files → skip.
- **§4.10 Encryption Posture:** no persistent store / new connection → skip.
- **§4.11 Guard Contract:** section added this pass; `lint-guard-contract.py`
  scans it clean (2 guard entries, ≥3 matrix rows each). PASS.
- **§4.12 Scope Check:** verified mechanically — exactly one unfenced
  `## Scope Check`, zero unmapped asks, 3 `inferred` rows all carrying
  justifications, no `status: BLOCKED`. PASS.

### Deepen-pass agents/lenses (sequential in-process — Devin harness)

- **spec-flow-analyzer (Phase 3 of plan + deepen re-walk):** surfaced and
  folded eight edge cases into the quarantine step — unfilterable-runner
  fallback (suite-level re-run), errored re-run is not a pass, build-error
  carve-out, KILLED/rc-3 ordering ahead of screening, per-test partial
  quarantine, no fix-round tally consumption, load-only-flake
  under-detection honesty (NON_CONVERGENCE recommendation arm), open-issue
  dedup before filing.
- **code-simplicity:** every proposed mechanism maps to a Property-List
  entry or carries a written justification; recommended keeping the
  quarantine set run-scoped rather than inventing re-entry heuristics —
  applied (re-failure is noted, not re-entered).
- **kieran (correctness/convention):** flagged test-name keying — same
  `it()` title in two files must be distinct entries — applied
  (file + test name key).
- **dhh:** no overengineering findings — one reference, three pointer/logic
  edits, no new machinery beyond what the issue scoped.
- **cto (devex):** assessed in-process under plan Phase 2.5 — recorded in
  `## Domain Review`; no capability gaps, no architectural decision (no ADR).
- **plan-review panel (dhh/kieran/simplicity + cto named-panel):** ran at
  plan time with all findings mechanical → applied inline.

### Key improvements folded in

- Detection positioned as the final sub-step of §1 Parse Failures so §2's
  delta/Circular bookkeeping reads the post-screen set (advisor-pass
  finding — placement ambiguity closed).
- Pathological all-flake-suite ceiling stated: converges to the iteration
  cap with the quarantined set enumerated — an honest bound, not a hang.
- `bun test -t`/`--test-name-pattern` verified against bun 1.4.3 `--help`
  (CLI-verification gate) — `--filter` would have been fabricated.
- `## Observability` + `## Guard Contract` sections added for the
  deepen-plan halt gates, mirroring the sibling-plan shape (#10727/#10735).
- Flake screening keys on file + test name (kieran mechanical finding).
