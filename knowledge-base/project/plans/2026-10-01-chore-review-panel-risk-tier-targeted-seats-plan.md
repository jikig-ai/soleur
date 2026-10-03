---
title: "chore(review): scale review panel to risk tier and review fix commits with targeted seats"
type: chore
date: 2026-10-01
slug: chore-review-panel-risk-tier-targeted-seats
branch: feat-one-shot-9399-review-panel-risk-tier
issue: 9399
closes: 9399
domain: engineering
priority: p2-medium
brand_survival_threshold: none
---

# chore(review): scale review panel to risk tier and review fix commits with targeted seats

## Enhancement Summary

**Deepened on:** 2026-10-01
**Gate results:** Phase 4.6 User-Brand Impact PASS (section + `none` threshold valid; no sensitive-path edits — the two `SENSITIVE_PATH_RE` matches in the body are fixture citations); Phase 4.7 Observability PASS (all 5 fields, `bash`-verb probe, literal expected output, <15 s); Phase 4.8 PAT PASS (no matches); Phase 4.9 UI-wireframe SKIP (no UI surface); Phase 4.10 Encryption Posture SKIP (no store/connection); Phase 4.55 Downtime SKIP (no infra/deploy/lock class); Phase 4.11 Guard Contract PASS (`lint-guard-contract.py` green — 3 guards; assemblies are structural: script-as-chokepoint, trailer validation block, three-way parity test).
**Agent passes:** inline/degraded — the planning harness exposes no Task/Workflow spawn surface, so the per-section research agents, skill-application sub-agents, and Phase-5 review panel were applied as inline lenses by the plan author and recorded as such (also noted in `## Plan Review Findings`).

### Key Improvements

1. **Tamper-resistant tier resolution (security-sentinel lens):** the PR body is author-editable text, so a declared `none` is not trusted unconditionally — the sensitive-path clamp now mirrors preflight Check 6's exact semantics (`none` honored only with an explicit `reason:` scope-out) and any `SENSITIVE_PATH_RE` diff always carries `security-sentinel` regardless of tier.
2. **Dedup ledger key corrected (data-integrity lens):** canonical defect key is `defect-class + rolled-up root cause`, not file-scoped — a cross-file structural finding must merge into one defect and one fix.
3. **`fix-round-seats.sh` input hygiene:** `--finding-seats` tokens are validated against the seat registry, dropped with `unknown-seat:` warnings, never echoed raw; empty `--files` is a distinct exit-0 contract from the non-empty-source floor.
4. **Trailer emits the resolved tier only:** `undeclared` is a classifier parse state, rejected by `--risk-tier` like any invalid value (3-token enum).
5. **Byte-ceiling ledger discovered and made binding:** measured merge-base headroom (plan +14 B / review +184 B / one-shot +856 B) moved all normative prose to unbudgeted `references/` files; SKILL.md edits are pointer lines.

### New Considerations Discovered

- ADR-264 was already claimed on `origin/feat-one-shot-agent-runnable-operator-bootstrap` (ordinal probed across all `origin/*` refs, not just `origin/main`) → provisional ordinal is **ADR-267**; re-probe before merge.
- `emit-review-trailer.sh`'s `--mode` enum-validation block is the precedent shape for the `--risk-tier` flag; `plan-review/lib/named-panel.mjs` + its parity test is the precedent for Guard 3.
- `--fix-round` trailer semantics pinned: a targeted round emits `Reviewed-Fix-Round:`/`Reviewed-Fix-Range:` keys over the fix-commit range only and NEVER `Reviewed-Coverage:` — a fix-range `full` would overclaim on ship's branch gate and the main trailer's idempotence skip would swallow it (ADR-267 §4, revised during review).
- Deferred resolve-pr-parallel wiring filed as **#9412** (labels/milestone verified live).

## Overview

Issue #9399 (part of the cost-reduction set observed on PR #9339): on 2026-10-01 a disk-leak fix whose core was small drew an 11-seat review panel because its plan declared `single-user incident`, then fix commits introduced new defects — a fix commit is the least-audited surface — costing further rounds and roughly eight CI cycles. The issue asks for four changes: (1) make the brand-survival threshold an explicit, challengeable decision at plan time, since it drives panel size; (2) scale review seats to the risk tier; (3) after the first full panel, review fix commits with targeted seats only, plus one verification pass at the end; (4) dedupe findings across seats before fixing. Acceptance: review reports seats spawned versus tier; a second round spawns only seats whose area a fix commit touched.

This plan introduces **one** new vocabulary carrier (the resolved *risk tier*, which reuses the existing `brand_survival_threshold` 3-value enum rather than inventing a second scale), a seat-scaling contract in `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` (byte-ceiling-driven: lifecycle SKILL.md files are at 14–856 B headroom against merge-base ceilings), a committed `fix-round-seats.sh` resolver that makes "targeted seats" mechanical instead of a prose convention, a `Reviewed-Risk-Tier:` trailer field, and a plan-time threshold-decision record routed through the existing ADR-084 `decision-challenges.md` channel.

## Problem Statement / Motivation

Current state (verified against the tree, not the issue's recollection):

- Panel composition is a **one-axis** decision: the Change Classification Gate (`plugins/soleur/skills/review/SKILL.md` §"Change Classification Gate") maps diff shape to seat count (`code` → 8, `non-code` → 4, `lockfile-only`/`deletion-dominated` → 2), and the `single-user incident` literal adds `soleur:engineering:review:user-impact-reviewer` as a conditional seat. There is no *risk* axis: an 11-seat panel on a 150-line tooling fix and an 11-seat panel on a credential-boundary rewrite differ only by which conditional triggers happened to fire.
- The plan's `brand_survival_threshold` is written silently by `plan` Phase 2.6 into frontmatter + `## User-Brand Impact`. It is never recorded as a *decision* — with a rationale, a cost consequence, or a challenge surface — even though it is the single largest lever on review cost (PR #9339: declared `single-user incident`, panel fixed at 11 seats; on main today a proportionate 2-seat review already exists only as an ad-hoc judgment call, e.g. `review: proportionate 2-seat review of a test-only mutation-battery speedup` on PR #9396's branch).
- Fix commits (`review: <summary> (P<N>)` produced by §5 fix-inline, and the resolver-agent commits produced by `one-shot` Step 5) get **no** seat-level re-review. `ship` Phase 1.5's evidence gate is a boolean (ADR-127), so a branch whose last three commits are unreviewed fixes passes identically to a fully-reviewed one. The repo's own learnings quantify the hole this leaves: `2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md` (the highest-severity findings were in the *fixes*), `2026-08-16-every-number-i-inherited-was-stale...` (the panel found the defect class inside the fix), `2026-08-10-the-fix-for-a-blind-spot-was-as-unpinned-as-the-blind-spot.md`.
- Dedup exists as one checklist line ("Remove duplicate or overlapping findings", review §5 Step 1) and a mechanical `file::title` key in `review.workflow.js`. Neither produces an auditable artifact mapping findings → canonical defects → fix commits, so duplicated findings become duplicated fix commits and duplicated CI cycles.

Measured baseline (Phase 0.6c): the #9339 review ran 11 seats (security, data-integrity, architecture, pattern, quality, agent-native, structural-enumeration, test-design, user-impact, history, semgrep — per the PR #9339 test-plan line). Per-seat cost is on the order of ~100k tokens (the #7418 12-agent review cost ~1.2M; `review/SKILL.md` §design-risk). Every full-panel re-round avoided is worth roughly that much; a targeted fix round is 1–3 seats.

## Proposed Solution

Five mechanisms, each mapped to a property in `## Research Insights`:

1. **Risk tier = the resolved `brand_survival_threshold`, resolved at review time through one chokepoint.** No new enum: `none` | `single-user incident` | `aggregate pattern` (the classifier may report `undeclared` internally; it is a parse state, never an emitted tier). Resolution order: PR body `**Brand-survival threshold:**` line → linked plan file (frontmatter `brand_survival_threshold:` or `## User-Brand Impact` line) → undeclared → `none`. **Tamper note (deepen):** the highest-precedence source (PR body) is also PR-author-editable, so "declared `none`" cannot be trusted unconditionally on a sensitive diff. **Fail-closed clamp, mirroring preflight Check 6's own semantics:** a diff matching `SENSITIVE_PATH_RE` (preflight Check 6 SSOT) resolves at minimum `single-user incident` UNLESS the declaration is an explicit `threshold: none, reason: <non-empty>` scope-out (the same exemption shape Check 6 honors); an undeclared sensitive diff, or a bare `none` with no scope-out reason, clamps to `single-user incident` and announces the clamp. Additionally, **any `SENSITIVE_PATH_RE`-matching diff always carries `security-sentinel`** regardless of tier (seats may exceed a tier's row; they may never fall below the *resolved* tier's row). Review never scales below the declared tier, and a `single-user incident` declaration on a docs-only diff gets its seats *and* a `mismatch` note (over-declaration is reported, not silently honored as a down-tier — the plan-time challenge is where inflation gets fixed).
2. **Seat scaling table `seats = f(class, tier)`** in a new `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`, mirrored in `review.workflow.js` and pointed to from `review/SKILL.md` (byte-ceiling constraint — see Technical Considerations). At `none`, three base seats become trigger-gated (see table below); at `single-user incident` the class baseline is a floor and `user-impact-reviewer` fires (existing) plus its lens extends into fix rounds on user-facing fix paths; at `aggregate pattern` the design-validity pass is mandatory, the structural-enumeration seat fires whenever the diff is guard-shaped (existing trigger), and the workflow raises `SKEPTICS` to 3. The `deep review`/`full review` override is unchanged — it always forces the full set.
3. **Fix-commit targeted round** — the contract lives in `references/risk-tier-and-fix-rounds.md` (review SKILL.md carries a pointer line under §5) plus a committed resolver `plugins/soleur/skills/review/scripts/fix-round-seats.sh`. Record `PANEL_SHA=$(git rev-parse HEAD)` at panel spawn. After each fix-commit batch, `git diff --name-only $PANEL_SHA..HEAD` yields fix-touched files; the seat set is `{seats that reported the findings these commits close} ∪ {path-mapped seats from the script} ∪ {security-sentinel if the fix diff touches SENSITIVE_PATH_RE or adds guard/deny-shaped lines}`. If a fix touches files no seat maps to, the script still emits `code-quality-analyst` as the generalist floor — a targeted round never returns zero seats on a source-touching fix. Seats spawn report-only against the fix diff. Cap: **two targeted rounds**; a third needed round escalates to the full class panel (an unbounded targeted loop is the treadmill this mechanism exists to prevent). Then **one verification pass**: a single fresh-eyes verifier seat (session model) answers "does each fix commit close its finding, and did any fix introduce a defect in its own area?" plus the lead's existing `TEST_GROUP=affected` run. `one-shot` Step 5 invokes the same round after its resolver-agent commits via `soleur:review <PR> --fix-round`.
4. **Dedup-before-fixing ledger.** review §5 Step 1's "Remove duplicate or overlapping findings" becomes a required emitted artifact — spec in the new references file (SKILL.md byte ceiling); §5 gets a pointer plus the `dedup: N raw → M unique` summary line. The ledger maps each raw finding → canonical defect key → reporting seat(s) → planned fix commit, emitted *before* any fix dispatch. **Deepen correction (data-integrity lens):** the canonical key is `defect-class + rolled-up root cause`, *not* file-scoped — a structural finding spanning N files ("same predicate copy at every call site") must merge across files into one defect and one fix, so the key is file-qualified only when the defect is genuinely file-local. The structural-cause roll-up rule already in §5 is unchanged — the ledger is what makes it visible. The workflow's mechanical `file::title` dedup stays as the cheap first pass; its report gains a `mergedGroups` count.
5. **Seats-vs-tier reporting.** Three surfaces: (a) the classification announce line gains `Tier: <value> (source: <pr-body|plan:<path>|sensitive-path clamp|undeclared>)`; (b) the `### Review Agents Used` summary gains `**Risk tier:** <value> — seats spawned: <N> (class <class> baseline <B> + escalation <E>)`; (c) `emit-review-trailer.sh` gains `--risk-tier <enum>` emitting a `Reviewed-Risk-Tier:` trailer — additive, validated against the enum, **no consumer** (same argument ADR-127 used for `Reviewed-Commit:`: adding the field once the key is in main's history is the expensive part). A `--fix-round` run emits `Reviewed-Fix-Round:`/​`Reviewed-Fix-Range:` trailers over the fix-commit range it actually reviewed (seat counts via `--agents-ran/--agents-expected`) — never `Reviewed-Coverage:` (revised during review: a fix-range `full` overclaims on ship's branch-level coverage gate).
6. **Challengeable threshold at plan time.** `plan` Phase 2.6's rendered `## User-Brand Impact` carries a fixed-format line `**Threshold decision (challengeable):** <value> — rationale: <one sentence> — review-panel effect: <tier → expected seat consequence>`. The line's full text and the routing rules live in `plan-issue-templates.md` (unbudgeted reference file — `plan/SKILL.md` has only **14 bytes** of headroom against its 120000 ceiling, so the SKILL.md edit must be a ≤14-byte-net surgical pointer inside an existing Phase 2.6 sentence, e.g. extending the `(full template: references/plan-issue-templates.md)` parenthetical). Classification: Taste(user-legible) — it drives money (seat spend) and coverage. Routing per ADR-084 (spelled out in the template reference, not SKILL.md): attached → surfaced at the existing post-plan-review apply gate (no new pause); headless → appended to `knowledge-base/project/specs/<branch>/decision-challenges.md` whenever the declared value is `single-user incident` or `aggregate pattern` (the cost-driving choices), which `ship` Phase 6 already renders. `plan-issue-templates.md` gains the line in all three `## User-Brand Impact` blocks. A `plan-review` finding that disputes the declared threshold classifies User-Challenge per `decision-principles.md`.

### Seat-scaling table (the normative contract)

| Tier | Base panel | Conditional/escalation seats | Fix-commit round |
|---|---|---|---|
| `none` (or undeclared, non-sensitive diff) | Class baseline, with {data-integrity, agent-native, performance} trigger-gated: each runs only when the diff touches its surface (persistence/migrations/queries; user-or-agent-visible surface; perf-sensitive paths). Floor: {git-history, pattern, architecture, security, code-quality} never shed. | Trigger-gated as today (test-design, semgrep/shellcheck, anti-slop, gdpr, rails, migration). | Targeted seats + one verification pass |
| `single-user incident` | Class baseline unconditional | + user-impact-reviewer; coverage consult unconditional at synthesis | Targeted seats; user-impact lens added when a fix touches user-facing paths |
| `aggregate pattern` | Class baseline unconditional + mandatory design-validity pass | + user-impact-reviewer; + structural-enumeration whenever guard-shaped; workflow `SKEPTICS=3` | Targeted seats + one verification pass; cap-2 escalation unchanged |

## Technical Considerations

- **SKILL.md byte ceilings — measured, binding.** `scripts/lint-skill-body-budget.py --base <merge-base>` enforces `plugins/soleur/test/skill-body-budget.json` ceilings read from the merge base, so this PR cannot raise them. Measured at merge base `c60dc74`: `review/SKILL.md` 476816/477000 → **184 B headroom**; `plan/SKILL.md` 119986/120000 → **14 B headroom**; `one-shot/SKILL.md` 51144/52000 → **856 B headroom**. Consequence: **all normative prose lives in unbudgeted reference files**, and SKILL.md edits are minimal pointers or in-sentence extensions whose net delta fits the ledger. `review/SKILL.md` gets ≤184 B: one pointer at the classification gate (`Tier: …` announce token + `references/risk-tier-and-fix-rounds.md` link) and one pointer under §5 (targeted round + dedup ledger). If 184 B is exceeded, reclaim by *relocating* equivalent existing detail into the reference file — never by dropping conditions (the 2026-09-23 compression sharp edge). `plan/SKILL.md` gets ≤14 B net: no new step or bullet — extend the existing `(full template: references/plan-issue-templates.md)` parenthetical in Phase 2.6 Step 3 only. `one-shot/SKILL.md` fits a normal 1–2 line Step 5 addition (~180 B used of 856 B).
- **SSOT reuse, not restatement.** The tier parse reuses the existing detection (`review/SKILL.md` conditional block + `review.workflow.js` `userImpactThreshold` trigger) — generalize the boolean to a 3(+undeclared)-value parse at the same read sites. The sensitive-path clamp reuses `SENSITIVE_PATH_RE` verbatim (byte-identical mirror rule applies to its three existing consumers; a *read* of the regex does not add a fourth copy — the plan reads it, the script or prompt embeds it only if the work phase decides to; if it does embed a copy, the Check-10-style `grep -cF` mirror pin must extend to it — flag for implementation).
- **Workflow port parity.** `review.workflow.js` changes: `CLASSIFY_SCHEMA.triggers.userImpactThreshold` (bool) → `brandThreshold` (enum `none|single-user incident|aggregate pattern|undeclared`); `conditionalDimensions` fires `user-impact` on `single-user incident` OR `aggregate pattern`; `SKEPTICS` becomes `deepReview || brandThreshold === 'aggregate pattern' ? 3 : 1`; the `log()` class line gains the tier + seat counts; `report` gains `riskTier` and `seatsSpawned`. A `plugins/soleur/test/review-tier-parity.test.ts` normalized parity test pins the SKILL.md table against the workflow's gating (precedent: `plan-review-named-panel.test.ts` + `plan-review/lib/named-panel.mjs`).
- **`fix-round-seats.sh` contract — one map, two consumers.** `bash fix-round-seats.sh --files <newline-or-comma file list> [--finding-seats <seat,...>]`: prints one seat registry-id per line, deduped, deterministic ordering (floor seats first). Exit 0 always on valid input; exit 2 on usage error; **empty `--files` prints nothing plus a `note: empty fix diff` stderr line and still exits 0** (a zero-change round legitimately spawns zero seats — the "never zero" floor applies only to non-empty diffs that touch source). Pure-function shape (path-regex → seat set) keeps it testable without a repo checkout. **Input hygiene (deepen — the `--finding-seats` input is model-emitted text):** every token is validated against the canonical seat registry; unknown tokens are dropped with a stderr `unknown-seat:` warning and **never echoed to stdout raw** — a forged token carrying whitespace/metacharacters cannot smuggle an extra output line. **The script's path→seat map is the single source for both consumers**: (a) the `none`-tier trigger-gating predicates in the seat-scaling table are *defined as* "the seat fires iff the diff touches a path its map arm covers" — no second prose predicate table to drift; (b) fix-round targeting runs the same map over the fix diff. The parity test (Guard 3) then pins three-way agreement: reference-file table ↔ `review.workflow.js` gating ↔ script map arms.
- **The fix→seat reverse mapping needs a carrier.** "Seats that reported the findings being fixed" is derivable only if findings carry their reporting seat — §5's synthesis already tags `reporting agent` for the coverage consult; the dedup ledger (mechanism 4) is where that lands durably. Fix commits already cite findings (`review: <summary> (P<N>)`); the round closes the loop by requiring the fix's seat set to include the finding's seat.
- **`--fix-round` invocation shape.** `soleur:review` args today are `PR|URL|file|empty` plus the `--parent ship` strip-prefix convention. `--fix-round` follows the same convention: stripped first, then runs ONLY the targeted round + verification pass against `PANEL_SHA..HEAD` (or a `--since <sha>` the caller supplies — one-shot Step 5 knows the panel SHA only indirectly, so the mode derives the base as the oldest `review(`/`review:` commit's parent on the branch... simpler: `git merge-base origin/main HEAD` plus filtering to `review*` subjects — implementation detail; the plan pins the contract: *round scope = commits since the last full-panel snapshot or since merge-base, whichever the caller attests*).
- **Skill-description budget.** No `description:` frontmatter edits are planned (Phase 1.8 gate not triggered).
- **NFR**: none beyond review-side token cost (the point of the change).

## User-Brand Impact

- **If this lands broken, the user experiences:** a `soleur:review` run whose reported seat count does not match the diff's declared risk — under-scaled: a sensitive diff gets a floor panel and a real finding reaches `main` that the skipped seat would have caught; over-scaled: the operator pays a full panel for a trivia PR and the pipeline's cost complaint this issue filed is not actually fixed. Both are legible in the review summary's seats-vs-tier line, which is the point of reporting it.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new data is persisted or egressed — `Reviewed-Risk-Tier:` records a 3-value enum in git trailers. The exposure is indirect: a tier mis-resolution (e.g. the sensitive-path clamp fail-open) lowers review coverage on a diff that needed it; mitigated by the fail-closed clamp (undeclared + sensitive-path → `single-user incident`) and by `ship` Phase 1.5/Check-6 gates, which are unchanged.
- **Brand-survival threshold:** `none` — plugin-internal review machinery; consistent with the corpus convention for chore plans (recent `chore-*` plans unanimously declare `none`). No sensitive-path files are touched (`plugins/soleur/**` is outside the canonical `SENSITIVE_PATH_RE`).

## Observability

The deliverable is itself a reporting surface; the block declares how a *mis-scaled review* is noticed.

```yaml
liveness_signal:
  what: "Per-review emission of `Reviewed-Risk-Tier:` + `Reviewed-Coverage:` trailers and the seats-vs-tier announce line; absence of the tier field on a post-change branch = the instrumentation did not land."
  cadence: "per soleur:review run"
  alert_target: "none — recorded forensic signal (ADR-127 pattern), no pager"
  configured_in: "plugins/soleur/skills/review/scripts/emit-review-trailer.sh"

error_reporting:
  destination: "stderr of emit-review-trailer.sh and fix-round-seats.sh"
  fail_loud: "invalid --risk-tier exits 2; a fix diff with unmatched source paths still emits the code-quality floor seat and an `unmapped-paths:` note on stderr"

failure_modes:
  - mode: "Tier mis-resolution (undeclared treated as low on a sensitive diff)"
    detection: "sensitive-path clamp forces `single-user incident`; the announce line prints the resolution source, so a wrong tier is legible in the review output"
    alert_route: "ship preflight Check 6 (unchanged) still fails a sensitive-path diff with no User-Brand Impact section"
  - mode: "fix-round-seats.sh returns zero seats on a source-touching fix diff"
    detection: "script's floor rule emits code-quality-analyst; test battery pins it"
    alert_route: "review summary's targeted-round line"
  - mode: "SKILL.md tier table and review.workflow.js drift apart"
    detection: "plugins/soleur/test/review-tier-parity.test.ts"
    alert_route: "CI red"

logs:
  where: "git trailers (`Reviewed-Risk-Tier:`) + review summary body"
  retention: "permanent (commit history)"

discoverability_test:
  command: "bash plugins/soleur/skills/review/scripts/fix-round-seats.sh --files 'apps/web-platform/supabase/migrations/20990101000000_x.sql'"
  expected_output: "data-integrity-guardian"
```

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-267 (provisional ordinal — sibling PRs may claim it; renumber sweeps all of `knowledge-base/project/{plans,specs}/feat-one-shot-9399-review-panel-risk-tier/`):** "Review panel composition is a function of declared risk tier; post-panel fix commits are reviewed by targeted seats plus one verification pass." Decision records: the tier enum reuses `brand_survival_threshold`; the never-scale-below-declared-tier rule; the cap-2-then-escalate bound; the `Reviewed-Risk-Tier:` trailer's no-consumer rationale (ADR-127 precedent). Alternatives Considered must carry: prose-only seat mapping (rejected — measured zero compliance on prose conventions; `emit-review-trailer.sh` exists for exactly this reason), full re-panel per fix round (rejected — the cost the issue cites), no fix review (rejected — fix commits are the least-audited surface), a new low/medium/high vocabulary (rejected — second vocabulary for one concept).

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`). External-actor/system enumeration for this change: (a) external human actors — none added (the `founder` actor and his `Invokes Soleur skills` edge are unchanged); (b) external systems/vendors — none added (seat agents are internal components, already modeled as a class via `archstrat`/the skills container); (c) containers/data stores — none added; (d) access relationships — unchanged. **One stale description must be corrected in this PR:** `platform.plugin.review` (`model.c4`) describes "Multi-agent code review with 8 parallel reviewers" — false once the panel is tier-scaled; update to describe the tier-scaled panel + targeted fix round. `views.c4` already includes `platform.plugin.review`; no view edits needed. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit.

### Sequencing

ADR-267 is authored in this PR with `status: accepted` (the decision is true when the code lands; no soak-gated slice).

## Guard Contract

### Guard 1 — `fix-round-seats.sh` seat-selection is floor-bounded and non-vacuous

**Property.** Every fix-commit diff resolves to exactly the union of {reporting seats of the findings it closes} ∪ {path-mapped seats} ∪ {conditional seats}, and a source-touching fix diff never resolves to an empty seat set.

**Assembly.** The script is the single chokepoint: `review/SKILL.md`'s targeted round and `one-shot` Step 5 both resolve seats through it — there is no second mapping site. The assembly it quantifies over: the path→seat pattern arms inside the script plus the `--finding-seats` input contract.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `*/migrations/*` pattern arm from the script | RED — fixture feeding a migration path expects `data-integrity-guardian` + `data-migration-expert` |
| 2 | Remove the code-quality floor emit so a source-touching unmatched path yields empty output | RED — anti-vacuity row: test asserts non-empty seat list on an unmatched `.ts` path |
| 3 | Feed two different-area files (a `*.test.ts` and a `.sql` migration) after a first matching file — assert both `test-design-reviewer` and `data-integrity-guardian` present | RED if the script stops at the first member |
| 4 | Corrupt the seat-registry spelling (e.g. `security-sentinel` → `security_sentinel`) in one emit line | RED — test asserts every emitted token resolves against the canonical seat registry derived from `DIMENSIONS`/the SKILL conditional list |
| 5 | Suite-side: fixture declares a finding→seat map naming `user-impact-reviewer`; remove the `--finding-seats` union step in the script | RED — the reporting seat must always re-spawn on its own finding's fix |
| 6 | Pass `--finding-seats` a forged token (`security-sentinel\nBUG-INJECTED` or an unknown seat name) | RED if the raw token reaches stdout; expected: dropped + `unknown-seat:` stderr warning |
| 7 | Pass `--files` with an empty list | exit 0, empty stdout, `note: empty fix diff` on stderr — distinct from the non-empty-source floor case |

### Guard 2 — `Reviewed-Risk-Tier` trailer validation

**Property.** Only the 3-token *resolved-tier* enum (`none|single-user incident|aggregate pattern`) can reach `main`'s history via the flag (`undeclared` is a classifier parse state and is rejected like any other invalid value); an invalid value exits 2 before any commit.

**Assembly.** `emit-review-trailer.sh` argument validation block (same shape as the existing `--mode` enum check) + the trailers-paragraph emit; consumed by `emit-review-trailer.test.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `aggregate pattern` from the enum regex | RED — battery row passes `--risk-tier "aggregate pattern"` and asserts the trailer parses |
| 2 | Remove the validation block entirely so any string reaches the trailer | RED — `--risk-tier bogus` must exit 2 |
| 3 | Emit the field *outside* the final trailers paragraph (e.g. mid-body) | RED — git trailers parse only the last contiguous `Key: value` block; the test asserts `%(trailers:key=Reviewed-Risk-Tier)` non-empty |
| 4 | Suite-side: assert the flag is optional — a run with no `--risk-tier` still emits a valid trailer with the field absent (not `unknown` text) | must-PASS row: absence is honest, a fabricated `unknown` literal would be a claim the caller never measured |

### Guard 3 — SKILL↔workflow tier-table parity

**Property.** The seat-scaling contract in `review/SKILL.md` and the gating in `review.workflow.js` (`CLASS_DIMENSIONS`/`conditionalDimensions`/`SKEPTICS`) cannot diverge silently — the copy that runs must match the copy that is specified.

**Assembly.** `plugins/soleur/test/review-tier-parity.test.ts` (normalized logic-parity guard, precedent `plan-review-named-panel.test.ts`): extracts the tier table rows from `references/risk-tier-and-fix-rounds.md` (the normative contract location — SKILL.md only points at it) and asserts the workflow's trigger shape agrees (e.g. `user-impact` fires iff tier ∈ {single-user incident, aggregate pattern}; `SKEPTICS` escalation keyed on `aggregate pattern`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Edit workflow so `user-impact` no longer fires on `aggregate pattern` | RED |
| 2 | Edit `references/risk-tier-and-fix-rounds.md` to add a fourth tier without touching the workflow | RED — the table's tier set is pinned |
| 3 | Change `SKEPTICS` so `aggregate pattern` no longer escalates | RED |
| 4 | Suite-side: add a must-PASS fixture where both sides agree on `none` (no forced seats) | PASS required — a guard that rejects everything is not caught by RED rows |

## Implementation Phases

### Phase 1 — Review-skill contract (the normative text)

- **Create `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`** (unbudgeted reference file; the `references/` convention already exists in this skill) carrying all normative text:
  - Tier resolution: parse order (PR body `**Brand-survival threshold:**` → linked plan frontmatter/`## User-Brand Impact` line → undeclared → `none`), the `SENSITIVE_PATH_RE` fail-closed clamp, the never-scale-below-declared rule, and the `mismatch` note contract.
  - The seat-scaling table (the normative contract above).
  - Announce-line and `### Review Agents Used` reporting formats (`Tier: <v> (source: …)`, `Risk tier / seats spawned`).
  - The `#### Fix-Commit Targeted Round` contract: `PANEL_SHA` snapshot, seat-set derivation via `fix-round-seats.sh`, report-only spawn on the fix diff, cap-2-then-escalate, one verification pass, `--fix-round` invocation.
  - The dedup ledger spec (mapping columns, `dedup: N→M` line, emitted before any fix dispatch).
  - The `aggregate pattern` escalation semantics and `none`-tier trigger-gating predicates.
- `plugins/soleur/skills/review/SKILL.md` — **byte-budgeted pointer edits only (≤ +184 B net):**
  - Classification announce line gains the `Tier:`/`source:` tokens (in-place extension).
  - One pointer line at the classification gate → `references/risk-tier-and-fix-rounds.md` (tier resolution + seat scaling).
  - §"Conditional Agents" `userImpactThreshold` bullet → `aggregate pattern` included (in-place edit).
  - One pointer line under §5 → fix-round contract + dedup ledger requirement.
  - `### Review Agents Used` template gains the `Risk tier` line.
  - If the delta exceeds 184 B, *relocate* equivalent existing detail into the reference file rather than compressing conditions away.
- `plugins/soleur/skills/review/workflows/review.workflow.js`: schema + gating + `SKEPTICS` + `log`/`report` fields per Technical Considerations (workflow scripts are not byte-capped).
- `plugins/soleur/skills/review/workflows/README.md`: note the tier divergence resolved (if it documents the class-only contract).

### Phase 2 — Machinery (script + trailer + tests)

- Create `plugins/soleur/skills/review/scripts/fix-round-seats.sh` + `plugins/soleur/skills/review/test/fix-round-seats.test.sh` (auto-registered via `plugins/soleur/skills/*/test/*.test.sh` glob in `scripts/test-all.sh`). Battery covers the Guard-1 matrix.
- Edit `plugins/soleur/skills/review/scripts/emit-review-trailer.sh`: `--risk-tier` flag, enum validation, `Reviewed-Risk-Tier:` trailer line in the trailers paragraph, usage text, header comment note.
- Edit `plugins/soleur/skills/review/test/emit-review-trailer.test.sh`: rows for Guard-2 matrix.
- Create `plugins/soleur/test/review-tier-parity.test.ts` (Guard 3).

### Phase 3 — Plan-side + pipeline wiring

- `plugins/soleur/skills/plan/references/plan-issue-templates.md` (unbudgeted): add the `**Threshold decision (challengeable):** <value> — rationale: … — review-panel effect: …` line to all three `## User-Brand Impact` blocks, plus a short comment block under the section explaining the ADR-084 routing (attached → post-plan-review gate; headless → `specs/<branch>/decision-challenges.md` when the declared value is `single-user incident` or `aggregate pattern`) and the plan-review User-Challenge classification.
- `plugins/soleur/skills/plan/SKILL.md` — **≤ +14 B net**: extend the existing parenthetical at Phase 2.6 Step 3 from `(full template: references/plan-issue-templates.md)` to name the challengeable-threshold line (e.g. `(full template incl. the challengeable threshold-decision line: references/plan-issue-templates.md)` — ~80 B; if it doesn't fit, trim whitespace-level prose elsewhere in the same phase, never a condition).
- `plugins/soleur/skills/one-shot/SKILL.md` Step 5 (~180 B of 856 B headroom): after resolver-agent commits land, run `soleur:review <PR> --fix-round` (the fix-commit targeted round + verification pass) before Step 5.5.

### Phase 4 — Decision record

- Create `knowledge-base/engineering/architecture/decisions/ADR-267-*.md` via `soleur:architecture` (provisional ordinal).
- Edit `knowledge-base/engineering/architecture/diagrams/model.c4`: `platform.plugin.review` description.
- Re-run C4 tests + `TEST_GROUP=affected bash scripts/test-all.sh`.

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Prose seat-mapping convention in SKILL.md only | The repo has measured zero compliance on prose-only conventions (`emit-review-trailer.sh` exists for exactly this); AC2's "spawns only seats whose area a fix commit touched" needs a deterministic resolver to be auditable. |
| Re-run the full class panel after every fix round | This is the cost the issue is filed to remove (#9339: several fix rounds, ~8 CI cycles). |
| No fix-commit review (status quo) | Fix commits are the least-audited surface; learnings 2026-09-23 / 2026-08-16 / 2026-08-10 all measure defects landing *in* fixes. |
| New `low/medium/high` tier vocabulary decoupled from `brand_survival_threshold` | Second vocabulary for one concept; the threshold is already the declaration every consumer parses, and decoupling invites the "two signals disagree" failure the corpus warns about. |
| Review silently down-tiers an over-declared plan | Fail-open on coverage: a misread diff gets under-reviewed. Over-declaration is *reported* (seats-vs-tier line + mismatch note); fixing it is the plan-time challenge's job, not review's. |
| Wire `resolve-pr-parallel` (bot/human comment fixes) into the fix round now | Same shape, but its fix surface is comment-driven, not finding-driven; deferred with tracking issue **#9412** (re-evaluation criteria recorded there) and named in the ADR's Alternatives, not silently dropped. |

## Acceptance Criteria

- [ ] AC1 — `soleur:review` output reports the resolved risk tier and seats spawned versus tier in two places: the classification announce (`Tier: <v> (source: …)`) and the `### Review Agents Used` summary line (`**Risk tier:** … seats spawned: N`).
- [ ] AC2 — Tier resolution: PR-body `**Brand-survival threshold:**` wins over the linked plan; undeclared resolves `none`; a `SENSITIVE_PATH_RE`-matching diff resolves at minimum `single-user incident` unless the declaration carries an explicit `threshold: none, reason: <non-empty>` scope-out (preflight Check 6 parity), and always carries `security-sentinel`. Review never spawns fewer seats than the resolved tier's row; an over-declared tier yields a `mismatch` note, never a silent down-tier.
- [ ] AC3 — Seat scaling: at `none`, {data-integrity, agent-native, performance} are trigger-gated on their surface predicates while {git-history, pattern, architecture, security, code-quality} are the never-shed floor; at `single-user incident`, `user-impact-reviewer` fires; at `aggregate pattern`, design-validity is mandatory and workflow `SKEPTICS` is 3.
- [ ] AC4 — `emit-review-trailer.sh --risk-tier <resolved enum>` (`none|single-user incident|aggregate pattern` only) emits a parseable `Reviewed-Risk-Tier:` trailer; `undeclared` and any other invalid value exit 2; the flag is optional (absent ≠ fabricated).
- [ ] AC5 — A second review round on fix commits spawns exactly the seats `fix-round-seats.sh` resolves (reporting-seat union + path mapping + conditional seats), never the full class panel, capped at two rounds before escalation; exactly one verification pass follows the last round.
- [ ] AC6 — The dedup ledger (`finding → canonical defect → reporting seats → fix commit`) is emitted before any fix dispatch, and the summary carries `dedup: N raw → M unique`.
- [ ] AC7 — `plan` Phase 2.6 writes the `**Threshold decision (challengeable):**` line into `## User-Brand Impact`; in headless mode a `single-user incident`/`aggregate pattern` declaration appends to `specs/<branch>/decision-challenges.md`.
- [ ] AC8 — `ADR-267-*.md` exists; `model.c4`'s `platform.plugin.review` description no longer claims a fixed 8-seat panel; `plugins/soleur/test/review-tier-parity.test.ts` passes.
- [ ] AC9 — `TEST_GROUP=affected bash scripts/test-all.sh` green, including `fix-round-seats.test.sh` and the updated `emit-review-trailer.test.sh`.

## Test Scenarios

- Given a PR whose plan declares `Brand-survival threshold: none` and whose diff adds a `.sh` plugin script (no persistence, agent, or perf surface), when `soleur:review` runs, then the announce prints `Tier: none (source: plan:<path>)` and the seat list omits data-integrity/agent-native/performance.
- Given a sensitive-path diff (`apps/web-platform/supabase/migrations/**`) and a PR body with **no** `## User-Brand Impact` section, when review runs, then the tier resolves `single-user incident` with `source: sensitive-path clamp` and `user-impact-reviewer` is in the seat list.
- Given a plan declaring `single-user incident` on a docs-only diff, when review runs, then the elevated seat set still spawns AND the summary carries the mismatch note (never silently down-tiered).
- Given fix commits closing findings reported by `security-sentinel` (touched `server/auth.ts`) and `test-design-reviewer` (touched `*.test.ts`), when the targeted round runs, then spawned seats ⊇ {security-sentinel, test-design-reviewer} and ⊆ that set plus path-mapped additions — not the 8-seat class panel.
- Given a fix commit touching only `README.md`, when `fix-round-seats.sh` resolves, then output is non-empty only if the path maps; a fix commit touching `src/foo.ts` with no mapped area still emits `code-quality-analyst` (floor).
- Given `--risk-tier bogus`, when `emit-review-trailer.sh` runs, then it exits 2 with no commit created.
- Given 14 raw findings across seats where two pairs share a canonical defect, when synthesis completes, then the ledger shows `dedup: 14 raw → 12 unique` and each merged group names its reporting seats.
- Given a second fix round that would spawn a third targeted round, when the cap fires, then review escalates to the full class panel for the cumulative fix diff.
- `emit-review-trailer.test.sh` rows: valid enum values produce parseable trailers; missing flag omits the field cleanly; invalid exits 2.
- `review-tier-parity.test.ts`: mutation of the workflow's `brandThreshold` gating reds the suite.

## Success Metrics

- On the next `none`-tier small fix PR, seats spawned < the 8-seat code baseline (expected ~5–7 incl. conditionals) while `single-user incident`+ panels keep every seat.
- Fix-commit rounds cost 1–3 seats + 1 verifier instead of a re-panel; the #9339-shaped incident's fix rounds each cost ≤ ~⅓ of a full panel.
- Every review run on a post-change branch carries `Reviewed-Risk-Tier:` — measurable via `git log --format='%(trailers:key=Reviewed-Risk-Tier,valueonly)'`.

## Dependencies & Risks

- **Risk:** shedding {data-integrity, agent-native, performance} at `none` under-covers a diff whose surface predicate mis-detects (e.g. a `.ts` file that IS a persistence path but not under `supabase/`). Mitigation: floor set never sheds security/pattern/architecture; the sensitive-path clamp; `deep review` override; and the mismatch note makes over/under-declaration legible.
- **Risk:** the findings→seat carrier breaks (a fix commit that doesn't cite its finding). Mitigation: the ledger (mechanism 4) is the durable carrier, and the path-mapping arm covers fixes that cite nothing.
- **Risk:** `--fix-round` on a branch with no `PANEL_SHA` — contract resolves base to the caller-attested snapshot or merge-base; recorded in the ADR.
- **Dependency:** `SENSITIVE_PATH_RE` (preflight Check 6 SSOT) — the clamp reads it; if implementation embeds a copy, the mirrored-literal pin must be extended.
- **Deferral watch:** nothing in this plan defers capability — the resolve-pr-parallel wiring is the one recorded follow-up (ADR Alternatives), not a hidden gap.

## Open Code-Review Overlap

Two open `code-review` issues match planned paths:

- **#8859** (`review: PR #8858 deferred Laya/Jev debt-ledger entry — zero findings`) — mentions `emit-review-trailer.sh` incidentally (a zero-findings review record). **Disposition: acknowledge** — unrelated to the `--risk-tier` flag.
- **#4133** (`follow-through(#4116): Schema parity test for ## Observability block`) — touches `plan/SKILL.md` §2.9 and `plan-issue-templates.md` but for the Observability schema, a different section than Phase 2.6 / `## User-Brand Impact`. **Disposition: acknowledge** — no rework collision; if #4133 lands first, the new parity test and ours are independent.

## Plan Review Findings

**Harness note:** this planning session ran inside a pipeline subagent with **no Task/agent spawn surface**, so the `soleur:plan-review` eng panel (code-simplicity, kieran-rails-reviewer, dhh-rails-reviewer + named-panel scan) could not be spawned as separate agents. The three lenses were applied inline by the plan author; threshold `none` prescribes the 3-seat panel, and this pass is recorded as *inline/degraded* — `deepen-plan` (next in the pipeline) carries the independent agent triad.

- **Kieran (correctness/convention):** folded — (a) `fix-round` attestation must cover only the fix range, not the branch — shipped as `Reviewed-Fix-Round:`/`Reviewed-Fix-Range:` keys rather than `Reviewed-Coverage:`; (b) unify the `none`-tier trigger predicates with the fix-round path map — one map in `fix-round-seats.sh`, two consumers, so no second prose predicate table can drift (three-way parity guard).
- **DHH (overengineering):** each mechanism maps to a named ask; `SKEPTICS=3` at `aggregate pattern` is the only discretionary addition — kept because tier scaling is the issue's point and it is bounded to the rarest tier. No consumer for the new trailer (ADR-127).
- **Code-simplicity:** the `--fix-round` base-resolution contract pinned to one rule (panel-snapshot SHA, else caller-attested `--since`, else merge-base) — no third path.
- **Named panel:** `soleur:engineering:cto` relevance (devex/cost of pipeline machinery) folded into Domain Review; no UI surface → Product/UX gate NONE.
- **Standing checks:** frontmatter `closes: 9399` against OPEN issue ✓; `## User-Brand Impact` three required lines + `## Acceptance Criteria` + `## Observability` (5-field schema) + `## Guard Contract` (3 guards, mutation matrices with RED/must-PASS rows) + `## Research Insights` (premise + property/cut lists) all present; all `knowledge-base/` and `plugins/` citations verified against the tree (only the four to-be-created files are absent); markdownlint clean.

## Domain Review

**Domains relevant:** Engineering

Lane resolution: the feature description contains `review` (a `cross-domain` trigger token in `brainstorm-domain-config.md` §Lane Inference) → `cross-domain`. Fresh assessment (no brainstorm document exists for this branch). **Sub-agent spawn note:** the Task/agent spawn surface is unavailable in this planning harness (planning runs inside a pipeline subagent); the sweep below is an inline single-pass assessment against each domain's Assessment Question — deepen-plan (which follows this skill in the pipeline) carries the agent triad.

### Engineering

**Status:** reviewed (inline)
**Assessment:** Direct hit — the plan re-architects the review pipeline's dispatch boundary (panel composition becomes a function of a declared risk tier; a new fix-commit round; a new shipped script). CTO-lens concerns: (a) the tier table adds a second axis to a gate that is already the densest convention surface in the skill — mitigated by making `fix-round-seats.sh` the single chokepoint so the *mechanism* is one file; (b) downward scaling trades coverage for cost — bounded by the never-shed floor, the sensitive-path clamp, and the `deep review` override; (c) `decision-challenges.md` reuse keeps the challenge surface in the channel `ship` already renders. No new substrate, no infra, no vendor.

Domains assessed and rejected: Marketing (no user-facing copy/brand surface), Product (no UI surface — mechanical scan of Files to Create/Edit hits no `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx`; Product/UX Gate tier = NONE), Legal (no regulated-data or legal-document surface), Operations (no vendor/procurement change — token-spend process change is engineering-internal), Sales (none), Support (none), Finance (token cost is pipeline-internal spend, not budgeting).

**Brainstorm-recommended specialists:** none (no brainstorm ran).

## Research Insights

**Relevant files (verified against the worktree):**

- `plugins/soleur/skills/review/SKILL.md` — Change Classification Gate (class→seat tree, `:117-189`), conditional seats incl. `userImpactThreshold` literal detection (`:358-370`), "Decide the agent set ONCE" (`:437`), §5 synthesis/dedup/provenance (`:919-1038`), summary template `### Review Agents Used` (`:1132`), exit gate + trailer call (`:1182-1269`).
- `plugins/soleur/skills/review/workflows/review.workflow.js` — `DIMENSIONS` registry, `CLASS_DIMENSIONS`, `conditionalDimensions` incl. `userImpactThreshold` (`:102-113`), `CLASSIFY_SCHEMA` (`:118-149`), `SKEPTICS` (`:345`), mechanical dedup (`:470-480`), report shape (`:523-546`).
- `plugins/soleur/skills/review/scripts/emit-review-trailer.sh` + `test/emit-review-trailer.test.sh` — trailer emit/validate/idempotence; additive field precedent (`Reviewed-Commit:`, `Reviewed-Coverage:`).
- `plugins/soleur/skills/plan/SKILL.md` Phase 2.6 (`:564-603`) — where `brand_survival_threshold` is authored today; `plan/references/plan-issue-templates.md` `## User-Brand Impact` blocks (×3).
- `plugins/soleur/skills/one-shot/SKILL.md` Step 5 (`:331-345`) — resolver-agent fix commits land outside review.
- `plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md` — ADR-084 taxonomy + `decision-challenges.md` channel (ship Phase 6 renders).
- `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1 — canonical `SENSITIVE_PATH_RE` (byte-identical mirror at deepen-plan Phase 4.6 Step 2).
- `plugins/soleur/test/plan-review-named-panel.test.ts` — parity-guard precedent for Guard 3.
- `scripts/test-all.sh` `:97-108` — `plugins/soleur/skills/*/test/*.test.sh` auto-registration glob.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `platform.plugin.review` description (stale "8 parallel reviewers" once this lands).

**Institutional learnings applied:**

- `2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md` — fixes carry the defect class they close; motivates the reporting-seat re-spawn arm.
- `2026-08-10-the-fix-for-a-blind-spot-was-as-unpinned-as-the-blind-spot.md` + `2026-09-18-every-defect-was-in-my-verification-not-the-feature.md` — fix verification needs its own pass (the "one verification pass" is the seat for it).
- `2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md` — panel-scale report-only spawn rule (applied to the targeted round).
- `2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md` (#7418/ADR-176) — machinery-minimality: the Cut List below is what this learning bought.
- `2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md` — cost-of-filing/panel economics; the measured ~1.2M-token 12-agent review is the per-panel cost basis.
- `2026-07-16-five-documented-traps-recurred-and-a-perturbing-instrument-is-not-evidence.md` — a converged panel finding on supplied premises is not independent evidence; the dedup ledger records *which seat* so independence is checkable.
- ADR-127 — trailer fields are recorded without consumers; `Reviewed-Risk-Tier:` follows.
- ADR-084 / `decision-principles.md` — the challengeable-decision channel mechanism 6 rides.
- ADR-053/ADR-110 — model-tier pins are orthogonal (no seat gets a model change); `workflow-model-pins.test.ts`'s allowlist is untouched by this plan (no new pin sites — noted so the work phase does not add one).

**Premise Validation (Phase 0.6).** Issue #9399: OPEN, `type/chore`, label `deferred-scope-out` — premise holds. Cited PR #9339: MERGED 2026-10-01, 29 commits; its test-plan line confirms "Review: 11 seats (security, data-integrity, architecture, pattern, quality, agent-native, structural-enumeration, test-design, user-impact, history, semgrep); all findings fixed inline" and its plan declared `Brand-survival threshold: single-user incident` — the "fixed the panel at 11 seats" claim is accurate. Cited mechanisms verified on `origin/main`: the classification gate (`review/SKILL.md:117`), the threshold→seat coupling (`:358`), the trailer (`emit-review-trailer.sh`). ADR corpus grep on the mechanism (seat scaling / tier / fix-round): no ADR decided or rejected this; ADR-127 governs the trailer axis (additive field is consistent), ADR-053/110 govern model tiering (orthogonal — no model pins added), ADR-084 governs the challenge channel (reused). `SENSITIVE_PATH_RE` and `decision-challenges.md` both exist as designed reuse points.

**Property List (Phase 0.6b).** (a) The plan's brand-survival threshold is a recorded decision with a rationale and a challenge surface, because it drives downstream spend. (b) Panel size is a declared function of risk, not only of diff shape. (c) Post-panel fix commits get audited by the seats whose area they touched — a bounded second round, plus one terminal verification. (d) Cross-seat duplicate findings merge before any fix work. (e) Every review run reports what it resolved and spawned (auditability of a cost lever).

**Cut List (Phase 0.6b).**

- "Second panel at full size after fixes" → property (c) → rejected outright by the issue's cost premise; targeted round is the mechanism.
- "New low/medium/high tier vocabulary" → property (b) → the `brand_survival_threshold` enum already carries the concept; a second scale is pure drift surface.
- "Dedup agent seat" → property (d) → the synthesis step already exists; it needs an emitted artifact, not another spawn.
- "Consumer for `Reviewed-Risk-Tier:` in ship/preflight" → property (e) → ADR-127's own answer: record now, gate later if ever; a consumer would be machinery beyond the ask.
- "Wire resolve-pr-parallel into the fix round" → property (c) extended → comment-driven fixes are a different carrier; recorded as ADR follow-up, not silent scope.

**External research (Phase 1.6):** skipped — internal machinery change with strong local conventions; all load-bearing mechanisms (classes, trailers, decision-challenges, parity tests) have in-repo precedents cited above. **Community discovery (1.5):** no uncovered stacks (markdown/.js/.sh, all covered). **Functional overlap (1.5b):** checked inline (agent spawn unavailable) — `grep` over `plugins/soleur/skills/` and `scripts/` finds no existing seat-scaling or fix-commit re-review mechanism; the classification gate is the only panel-composition mechanism.

**Spec-vs-codebase reconciliation:** no spec.md exists for this branch yet (brainstorm skipped on the one-shot path); nothing to reconcile. `spec.md` + `tasks.md` are produced by this plan's Save-Tasks step.

## Sharp Edges

- **Byte ceilings are the binding constraint of this PR** (`lint-skill-body-budget.py` measured ledger in Technical Considerations): plan=+14 B, review=+184 B, one-shot=+856 B. Normative prose goes to `references/`; never reclaim headroom by dropping a condition — relocate it. `plan-issue-templates.md`/`review/references/*` are unbudgeted.
- **ADR-267 is provisional** — probed across all `origin/*` refs on 2026-10-01: ADR-264 is claimed by `origin/feat-one-shot-agent-runnable-operator-bootstrap`; max on `origin/main` is ADR-263. Re-run the probe across `origin/*` immediately before merge (main moves under long sessions).
- `fix-round-seats.sh` runs on operator hosts too — keep it POSIX/bash-portable: no `timeout`, `sed -i`, `readlink -f`, `stat -c`, `date -d` (per the portability sharp edge; GNU-isms fail on stock macOS).
- The `discoverability_test` command intentionally contains no `|`, `;`, `&`, `<`, `>`, `$`, or backtick (preflight Check 10's byte-level shell-token reject applies even inside quotes).
- The fix-commit round reviews **the fix diff**, not the branch diff — `git diff $PANEL_SHA..HEAD`, report-only, against a known SHA; panel-scale concurrency rules from §Sharp Edges apply (no lead edits while seats read).
- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6; the new `Threshold decision` line is additional format, not a substitute for the three required lines.
- `git log ... %(trailers:key=Reviewed-Risk-Tier)` reads newest-first only where order matters; `ship` Phase 1.5's `head -1` lesson applies to any future consumer of the new field.
- The `--fix-round` path on a branch that rebased after the panel invalidates `PANEL_SHA`; the contract's merge-base fallback exists for exactly that.
- SKILL.md is prose surface priced per token — the seat table is normative once; do not restate it in the workflow comments (pointer, not copy), and keep the workflow's `resolveWorkflowModel`/`safeTitle`/`safeId` copies byte-shaped per the self-contained-script rule.

## References & Research

- Issue: #9399; incident-of-record: PR #9339 (merged 2026-10-01); cost-reduction set from #9339.
- `plugins/soleur/skills/review/SKILL.md` §Change Classification Gate, §Conditional Agents, §5.
- ADR-127 (trailer boolean), ADR-084 (decision-challenges), ADR-053/ADR-110 (model tiering — untouched), ADR-176 (checkpoint-first planning).
- `knowledge-base/project/learnings/2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md`, `2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix.md`, `2026-08-10-the-fix-for-a-blind-spot-was-as-unpinned-as-the-blind-spot.md`.

## Resume

Plan deepened 2026-10-01; all deepen-plan halts pass or are out-of-trigger. To implement:

`soleur:work knowledge-base/project/plans/2026-10-01-chore-review-panel-risk-tier-targeted-seats-plan.md` — tasks: `knowledge-base/project/specs/feat-one-shot-9399-review-panel-risk-tier/tasks.md`. Watch items: SKILL.md byte headroom (plan +14 B, review +184 B, one-shot +856 B — relocate, never drop conditions); ADR-267 is provisional (re-probe `origin/*` before merge); `fix-round-seats.sh` stays POSIX-portable; `undeclared` never reaches the trailer.
