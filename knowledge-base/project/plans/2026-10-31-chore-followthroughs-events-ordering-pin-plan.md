---
title: "chore: pin ordering on statsPeriod-only Sentry /events/ follow-through probes (+ ordering-bound lint rule)"
type: chore
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
date: 2026-10-31
slug: chore-followthroughs-events-ordering-pin
branch: feat-one-shot-11553-sort-pin-census
issue: 11553
closes: 11553
---

## Overview

Seven follow-through probes under `scripts/followthroughs/` query the Sentry
`/api/0/organizations/<org>/events/` endpoint with a `statsPeriod`-only window and no
ordering pin. The endpoint's `sort` request parameter is optional: when absent there is
no `ORDER BY` guarantee and "newest-first" is observed behavior rather than contract, so
any coverage argument that assumes row order rests on an undocumented default. The probe
authoring convention (`followthrough-convention.md`) already requires every `/events/`
coverage argument to pin `sort=` or bound the window with `start=`/`end=`, and
`discord-blog-webhook-fallback.sh:184` is the shipped mirror (pin re-asserted by its own
suite). This chore brings the unbounded set onto the same contract — a `&sort=-timestamp`
pin per row-selecting probe, one documented exemption for the aggregate query — and adds a
new rule to the follow-through lint family so an unbounded `/events/` call fails CI rather
than surviving on convention alone. Deferred scope-out from PR #11543; tracked as #11553.

## Research Insights

### Premise Validation (Phase 0.6)

Every cited artifact was re-verified on this branch:

- Issue #11553 is OPEN; PR #11543 is MERGED (2026-10-30); issue #11532 CLOSED. The
  premise is live, not stale.
- `knowledge-base/project/learnings/2026-10-29-sentry-events-sort-optional-pin-it-for-coverage-arguments.md`
  and `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` both
  exist; the convention already carries the ordering rule in prose (§ probe-authoring
  rules, line ~60) — it has no mechanical enforcer.
- Mirror confirmed: `scripts/followthroughs/discord-blog-webhook-fallback.sh:184` pins
  `&sort=-timestamp`; `discord-blog-webhook-fallback.test.sh:255` re-asserts the pin.
- Capability claim verified: `grep -rn 'sort=\|/events/' scripts/lint-*` returns nothing —
  no repo check covers the unbounded-`/events/` class today (the issue's "candidate lint"
  rationale holds).
- ADR-corpus grep for the proposed mechanism (ordering/lint/followthrough keywords):
  no ADR rejected-alternative collides.
- Collision pre-check: `collision-precheck.sh 11553` flagged PR #11735 — it is THIS
  worktree's own auto-created draft on `feat-one-shot-11553-sort-pin-census`, benign.
  Foreign `test-all.sh` PIDs in a sibling worktree
  (`feat-one-shot-11594-11599-auth-mode-followups`) were reported and are non-blocking.

### Census reconciliation — spec claim vs codebase reality

The issue's census says 8 statsPeriod-only `/events/` probes. Measured census of every
`/events/` hit under `scripts/followthroughs/` (non-test, executable lines): **14 files**.

- **Unpinned, statsPeriod-only (the fix set — 7):**
  `ac10-workspace-reconcile-sentry-4246.sh` (`URL=...events/?query=...&statsPeriod=24h`, line ~55),
  `anthropic-admin-key-6297.sh` (`curl -G --data-urlencode 'statsPeriod=48h'`, line ~157 —
  **`field=count()` aggregate**, see per-probe dispositions),
  `cron-machinery-soak-9272.sh` (line ~87),
  `dashboard-cold-tiers-8978.sh` (line ~57),
  `egress-enforce-probe-11361.sh` (line ~44),
  `reconcile-ff-only-sentry-4977.sh` (line ~68),
  `workspaces-luks-soak-6604.sh` (line ~71).
- **Already bounded `start=`/`end=` (5):** `ac8-founder-ambiguous-soak-5673.sh:67`,
  `phase3-ga-soak-5274.sh:89`, `accounted-beacon-live-6462.sh:104`,
  `cwv-field-rum-9178.sh:111`, `dispatch-recovery-sweeper-11211.sh:101`.
- **Already `sort=`-pinned (1):** `discord-blog-webhook-fallback.sh:184` (the mirror).
- **Bounded AND aggregate (1):** `git-data-rehearsal-evidence.sh:398`
  (`start=`/`end=` + `field=count()`).
- **Census misclassification (1):** `sync-health-residual-5689.sh` — the issue counted it,
  but its call is `/api/0/projects/<org>/<project>/issues/` with `--data-urlencode
  statsPeriod=14d&limit=25` (line ~100–107), not `/events/`. Out of scope; recorded so the
  post-change lint hit-count does not read as a missed probe.

### Per-probe ordering dependence judgment

The issue asks for per-probe judgment on whether each verdict leans on ordering:

| Probe | Verdict shape | Leans on ordering? | Disposition |
|---|---|---|---|
| `ac10-workspace-reconcile-sentry-4246.sh` | `.data \| length == 0` → PASS | No — presence/absence is order-independent even under page truncation | Pin `&sort=-timestamp` (uniform contract, future-proof) |
| `anthropic-admin-key-6297.sh` | `.data[0]["count()"]` aggregate count | No — aggregate returns one row; ordering is meaningless, and `sort=-timestamp` on a `field=count()` select risks a 400 (sort field not selected) | **Exempt**: keep `statsPeriod=48h`; the lint exempts function-field (`field=<name>()`) aggregate calls structurally |
| `cron-machinery-soak-9272.sh` | `.data \| length` presence | No | Pin `&sort=-timestamp` |
| `dashboard-cold-tiers-8978.sh` | row-count presence | No | Pin `&sort=-timestamp` |
| `egress-enforce-probe-11361.sh` | `stage==` row count | No | Pin `&sort=-timestamp` |
| `reconcile-ff-only-sentry-4977.sh` | `.data \| length` presence | No | Pin `&sort=-timestamp` |
| `workspaces-luks-soak-6604.sh` | `.data \| length` DRIFT count | No | Pin `&sort=-timestamp` |
| `sync-health-residual-5689.sh` | `/issues/` endpoint, `issue_count == 0` | N/A — not an `/events/` call | Out of scope; no change |

No probe's verdict is strictly order-dependent today (all are presence/count checks), but
the convention states the rule unconditionally — "pin an ordering on every Sentry
`/events/` coverage argument" — and a lint cannot mechanically judge "does the verdict
lean on ordering", so the pin is applied uniformly. This mirrors the mirror's own
reasoning (the pin is what makes the coverage argument a contract).

### Property List (Phase 0.6b)

1. **P1** — Every credentialed `/events/` read under `scripts/followthroughs/` whose page
   could be argued to cover a window carries an explicit ordering contract (`sort=` or
   `start=`+`end=`); coverage arguments rest on contract, not observed default.
2. **P2** — The ordering contract is mechanically enforced: a new or edited probe missing
   the bound fails CI, not just convention review.

### Mechanism Minimality (Phase 0.6b) — Cut List

| Proposed mechanism | Property it buys | Already covered by? | Verdict |
|---|---|---|---|
| Per-probe `&sort=-timestamp` pin | P1 | No — the 7 probes verified unbounded | Keep |
| Lint rule requiring ordering bound on `/events/` URLs | P2 | No — `grep sort= scripts/lint-*` empty; convention doc is prose-only | Keep, as **rule 6 inside `lint-followthrough-varq-ban.sh`** (the family file already accreted rules 2–5 onto one probe-set walk with per-rule counters/floors; a new file would duplicate the probe-set machinery for zero property gain) |
| New `.test.sh` per probe to re-assert the pin | (none beyond P2) | The lint re-asserts the bound harness-wide — strictly stronger than per-probe greps; only 1 of 8 targets has a suite | **Cut** — except one assertion in the existing `anthropic-admin-key-6297.test.sh` pinning the aggregate (`field=count()`) exemption basis |

### Institutional learnings applied

- `2026-10-29-sentry-events-sort-optional-pin-it-for-coverage-arguments.md` — the source
  learning: `sort` optional, `get_orderby → None`, no ORDER BY guarantee; pin or bound.
- `2026-10-13-a-lint-anchored-on-the-verdict-word-stayed-green-over-the-marker-probes-that-had-the-same-defect.md` —
  **a lint's trigger must be the property, not the motivating consumer family**: rule 6
  anchors on "`/events/` call without a bound", not on "statsPeriod-only" — a future
  `start=`-less call of any spelling must still fire. Same source: each rule needs its
  OWN counter + floor + dispatch-mutation row (a `find|wc -l` counter byte-identical to a
  sibling's is not a floor).
- `best-practices/2026-07-22-a-guards-own-header-names-what-its-test-must-assert.md` —
  the lint header's rule-6 index entry must name exactly what the suite's mutation rows
  assert (rule 4's missing index entry is the recorded defect).
- `2026-09-24-followthrough-retirement-headers-underenumerate-touch-points.md` — when
  editing the lint family, enumerate its citation touch-points (followthrough-convention.md,
  ADR-031, Article 30 register) rather than trusting memory.
- `2026-05-19-sentry-url-routing-three-orthogonal-dimensions.md` + session errors in the
  source learning — region/host pinning (`de.sentry.io`, `jikigai-eu`) is orthogonal to
  the ordering pin; do not touch destination pins in this change.
- Sequential-fallback disclosure (from the source learning's session errors): on a Devin
  subagent, agent panels run in-process — findings here carry
  `Reviewed-Coverage: sequential-fallback`.

### External research

Skipped per Phase 1.6 — internal machinery with an in-repo mirror and documented
convention; Sentry-side semantics are already captured in the source learning.

## Problem Statement / Motivation

On the Sentry `/api/0/organizations/<org>/events/` endpoint, `sort` is an optional request
parameter; absent it, `get_orderby` returns `None` and there is no `ORDER BY` guarantee —
"newest-first" is observed behavior, not contract (CTO ruling on PR #11543). Seven probes
under `scripts/followthroughs/` issue credentialed `/events/` reads with `statsPeriod`-only
windows and no ordering pin. None of their current verdicts is strictly order-dependent
(all are presence/count checks — see the per-probe table in Research Insights), so the
exposure is *latent*: the next edit that argues "newest N covers the window" inherits an
unsound assumption, and convention review alone has already let seven probes ship unbound.
The convention doc states the rule in prose but nothing enforces it mechanically.

## Proposed Solution

Two deliverables, matching the issue's proposed fix:

1. **Pin the 6 row-selecting probes.** Append `&sort=-timestamp` to each `/events/` URL
   literal, mirroring `discord-blog-webhook-fallback.sh:184`. `&sort=-timestamp` is chosen
   over `start=`/`end=` because `statsPeriod` and `start`/`end` are mutually exclusive —
   bounding would mean replacing the rolling window with computed timestamps, strictly
   more machinery for the same property.
2. **Add rule 6 to `scripts/lint-followthrough-varq-ban.sh`** — "the ordering-bound rule":
   every executable-line `/events/` call in a probe file must carry `sort=`, or both
   `start=` and `end=`, on the same logical line (backslash-continuation folded, so the
   `curl -G --data-urlencode …` shape folds into one checkable unit). A `field=<name>()`
   function-field on the call marks an aggregate select and is exempt — ordering is
   meaningless on a one-row aggregate and pinning `sort` there risks a 400. Rule 6 gets
   its own counter (`scanned_rule6`, counting `/events/` logical lines examined including
   exempt ones), its own production floor (≥5 hits — 14 known today), its own exit-2
   diagnostic, and a header index entry naming what its suite asserts, per the family
   convention (rules 2–5 already accreted into this file; a standalone lint would
   duplicate the probe-set walk for zero property gain).

The one exempt probe is `anthropic-admin-key-6297.sh` (`field=count()` aggregate). It gets
a documenting comment, no param change. `sync-health-residual-5689.sh` is untouched — the
issue's census misclassified its `/issues/` call as `/events/`.

## Technical Considerations

- **Detection shape.** Two URL spellings exist in the tree: (A) a full URL literal
  (`URL="…/events/?query=…&statsPeriod=…"` — 6 of the fix set) and (B) `curl -G
  --data-urlencode 'statsPeriod=…' … "https://…/events/"` with params on separate
  continuation lines (`anthropic-admin-key-6297.sh`). Backslash-continuation folding
  handles both (the params precede the URL line in shape B, and folding merges them
  upward into the same logical line); the violation cites the physical line where
  `/events/` matched, not the fold's first line (the same line-number fidelity rule 1's
  header calls "the whole value of the guard").
- **Boundary-safe param matching.** The bound predicate matches `sort=`, `start=` and
  `end=` with a non-identifier left edge (`(^|[^A-Za-z_])sort=` etc.) so `resort=` or
  `append=`/`backend=` cannot satisfy or false-fire the bound check.
- **Spec-flow edge cases (sequential-fallback pass over the rule's decision paths).**
  (a) `cron-machinery-soak-9272.sh` gates its curl behind a `case "$URL" in
  https://…*)` destination-pin — a prefix glob, so appending `&sort=-timestamp` to the
  literal stays matched; the implementer must verify the glob is prefix-shaped before
  editing. (b) The `/events/` needle also matches the path literal inside a diagnostic
  string on an executable line (over-detection, cheap: the remedy is compliance or
  rewording — the same posture rule 4 takes). (c) Presence/count verdicts are unchanged
  by the pin (`.data|length` is order-independent); the `head`-printed forensic rows
  become deterministically newest-first — a strict improvement, not a behavior change.
- **Executable-line scoping.** Full-line comments are dropped before matching (rule 1's
  `grep -n` → `^[0-9]+:[[:space:]]*#` strip), so a doc comment describing an `/events/`
  call does not fire.
- **Probe set.** Rule 6 walks the same probe set as rules 1/3/4/5 (`is_probe_file`:
  `*.sh` OR executable OR `#!`, `*.test.sh` excluded) — the sweeper's executability
  chokepoint, structural rather than a member list.
- **Declared blind spots** (documented in the rule's header): an `/events/` URL and its
  params assembled across *non-continuation* statements (string concat, `printf -v`, a
  helper that appends `&sort=` later); a call whose endpoint is runtime-constructed; a
  `sort` passed through variable indirection. Same blind-spot class rule 3 already
  declares and accepts.
- **No new wiring.** `scripts/test-all.sh:5939-5940` already registers the lint's live
  run and its suite; extending the file adds the rule to the merge-blocking
  `test-scripts` shard with zero registration edits.
- **NFR impact:** none — CI-time bash only; no runtime surface changes.

## Implementation Phases

### Phase 1 — Probe pins (7 files)

- 1.1 `ac10-workspace-reconcile-sentry-4246.sh:55` — append `&sort=-timestamp` to the URL.
- 1.2 `cron-machinery-soak-9272.sh:87` — same.
- 1.3 `dashboard-cold-tiers-8978.sh:57` — same.
- 1.4 `egress-enforce-probe-11361.sh:44` — same (inline URL in the curl argv).
- 1.5 `reconcile-ff-only-sentry-4977.sh:68` — same.
- 1.6 `workspaces-luks-soak-6604.sh:71` — same.
- 1.7 `anthropic-admin-key-6297.sh` — add a comment above the `--data-urlencode
  'statsPeriod=48h'` block: aggregate `field=count()` select, ordering meaningless, exempt
  under rule 6's function-field exemption — no param change (pinning `sort` on an
  aggregate risks a 400).
- 1.8 `anthropic-admin-key-6297.test.sh` — add one assertion pinning that the `/events/`
  invocation still carries `field=count()` (the exemption basis; if the call is converted
  to a row select, the suite reddens *and* rule 6 fires on the missing bound).

### Phase 2 — Lint rule 6

- 2.1 `scripts/lint-followthrough-varq-ban.sh` — header index entry for rule 6 (naming the
  bound predicate, the aggregate exemption, the probe set, and the declared blind spots —
  the "guard's own header names what its test must assert" learning); RULE 6 body section:
  per-probe logical-line folding, executable-line `/events/` scan, bound predicate
  (`sort=` OR `start=` AND `end=` OR `field=<fn>()`), `scanned_rule6` counter, production
  floor ≥5 with its own `exit 2` diagnostic.
- 2.2 `scripts/lint-followthrough-varq-ban.test.sh` — R6-* rows implementing the Guard
  Contract matrix below (mutation + harness + characterization rows, mirroring the
  R2/R4/R5 row conventions).
- 2.3 `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — amend
  the "Pin an ordering" bullet: name rule 6 as the mechanical enforcer (same shape as the
  rule-2 bullet's "Enforced as **rule 2** of `lint-followthrough-varq-ban.sh`"), and drop
  the now-covered "census of unpinned sibling probes" tail note or re-point it at the
  post-change state.

### Phase 3 — Verification

- 3.1 `bash scripts/lint-followthrough-varq-ban.sh` (live run) → exit 0.
- 3.2 `bash scripts/lint-followthrough-varq-ban.test.sh` → all rows pass including R6-*.
- 3.3 Re-derived census: `grep` executable lines for `/events/` under
  `scripts/followthroughs/` → every hit carries `sort=`, `start=`+`end=`, or
  `field=<fn>()`.
- 3.4 `bash -n` on every touched probe; affected `test-all.sh` shard
  (`scripts/followthrough-varq-ban`, `scripts/followthrough-varq-ban-live`, plus any
  suite covering `anthropic-admin-key-6297.test.sh`).

## Files to Edit

- `scripts/followthroughs/ac10-workspace-reconcile-sentry-4246.sh` — `&sort=-timestamp` pin (line ~55)
- `scripts/followthroughs/cron-machinery-soak-9272.sh` — `&sort=-timestamp` pin (line ~87)
- `scripts/followthroughs/dashboard-cold-tiers-8978.sh` — `&sort=-timestamp` pin (line ~57)
- `scripts/followthroughs/egress-enforce-probe-11361.sh` — `&sort=-timestamp` pin (line ~44)
- `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh` — `&sort=-timestamp` pin (line ~68)
- `scripts/followthroughs/workspaces-luks-soak-6604.sh` — `&sort=-timestamp` pin (line ~71)
- `scripts/followthroughs/anthropic-admin-key-6297.sh` — comment documenting the aggregate exemption (no param change)
- `scripts/followthroughs/anthropic-admin-key-6297.test.sh` — one characterization assertion pinning `field=count()` on the `/events/` call
- `scripts/lint-followthrough-varq-ban.sh` — rule 6 (header index + body + counters/floor)
- `scripts/lint-followthrough-varq-ban.test.sh` — R6-* mutation/harness rows
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — ordering bullet names the mechanical enforcer

## Files to Create

None.

## Open Code-Review Overlap

None — 98 open `code-review` issues were fetched and every planned path was substring-matched
against their bodies (`jq --arg`); zero hits.

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct user-facing artifact — the
  worst case is an internal verification tracker mis-reporting (a false PASS auto-closing
  a tracker, or a false FAIL commenting daily) on a repo-ops issue the user never sees.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure
  vector — the diff adds a URL param and a CI lint rule; probes read the same operational
  event metadata through the same read-only token (`SENTRY_ACTIONS_RO_TOKEN`, ADR-031)
  over the same pinned destinations.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal tooling/CI change with no user-facing
  artifact and no new data egress; blast radius is a wrongly-reported internal tracker,
  which the lint exists to make *less* likely.

## Observability

Phase 2.9 evaluated — no Files-to-Edit entry under `apps/*/server|src|infra` or
`plugins/*/scripts/`, and no new infrastructure surface: section not required. (The
changed scripts *are* the observability surface; their signal contract — sweeper comments
and the 0/1/2 exit code — is pre-existing and unchanged by this diff.)

## Guard Contract

### Guard 1 — rule 6: ordering bound on `/events/` calls

**Property.** No executable-line `/events/` call in a probe under `scripts/followthroughs/`
reaches the tree without an explicit ordering contract on the same logical line: a
`sort=` parameter, or both `start=` and `end=`; a `field=<name>()` function-field select
is exempt because a one-row aggregate has no ordering to pin.

**Assembly.** Every logical line (backslash-continuation folded) of every file in the
probe set — `is_probe_file` over the target dir: `*.sh` OR executable OR `#!` shebang,
`*.test.sh` excluded — the same chokepoint rules 1/3/4/5 walk, so the rule inherits the
sweeper's executability boundary rather than enumerating today's members. Two spelling
surfaces are folded into the one assembly: full URL literals and `curl -G
--data-urlencode` continuation blocks. Declared blind spots (header-documented): endpoint
or params assembled across non-continuation statements or via runtime indirection.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `&sort=-timestamp` from the mirror `discord-blog-webhook-fallback.sh` URL | RED — cites file at true line |
| 2 | Remove `start=` from a bounded probe (e.g. `ac8-founder-ambiguous-soak-5673.sh`), leaving `end=` | RED — half-bound is unbound |
| 3 | Guard's own dispatch: neuter the `/events/` needle in a guard COPY → `scanned_rule6` = 0 < floor | exit 2, diagnostic names rule 6 |
| 4 | Add a SECOND unbounded `/events/` call in a file whose first call is compliant | RED — the walk does not stop at member one |
| 5 | Suite harness: must-PASS non-canonical — `start=`+`end=` bound with no `sort=` | GREEN — the bound, not the spelling, is the contract |
| 6 | Suite harness: must-PASS — `field=count()` aggregate with `statsPeriod` only (the live exemption shape) | GREEN — characterization row |
| 7 | Suite harness: `/events/` URL in a full-line `#` comment only | GREEN — executable-line scoping, not text-matching |
| 8 | Suite harness: `--data-urlencode 'sort=-timestamp'` on a continuation-folded `curl -G` call | GREEN — shape-B coverage is real, not accidental |

**Anchor.** Guard, suite, and probe files land in one commit — a weakening diff could move
both the matcher and a probe, so the external binding is the registered pair
`scripts/test-all.sh:5939-5940` (merge-blocking `test-scripts` shard): a PR that neuters
rule 6 must also edit the suite the shard runs, and rows 3–4 exist to redden exactly that
edit. No stored hit-count beyond the ≥5 floor; the census is re-derived from the tree on
every run.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Per probe, either pin `&sort=-timestamp` or bound with `start=`/`end=`, mirroring `discord-blog-webhook-fallback.sh:184`" | Phase 1 + 7 probe entries in Files to Edit | mapped |
| 2 | "(which also re-asserts the pin in its `.test.sh` so a dropped param reddens the harness)" | Rule 6 (harness-wide re-assertion, strictly stronger than per-probe greps) + item 1.8's suite assertion on the exemption basis | mapped |
| 3 | "Optionally add a lint to the followthrough lint family requiring an ordering bound (`sort=` or `start=`+`end=`) on `/events/` URLs" | Phase 2 — rule 6 in `lint-followthrough-varq-ban.sh` | mapped (the "optionally" is exercised — ruling: the lint buys P2 which no existing mechanism covers) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| 6 × `&sort=-timestamp` pin edits | "pin `&sort=-timestamp`" (ask 1) | asked |
| `anthropic-admin-key-6297.sh` exemption comment | "per-probe judgment needed on whether the verdict leans on ordering" (issue §What) | asked |
| `anthropic-admin-key-6297.test.sh` assertion | "re-asserts the pin in its `.test.sh` so a dropped param reddens the harness" (ask 2) | asked |
| Rule 6 in `lint-followthrough-varq-ban.sh` + header/floor | "a lint … requiring an ordering bound (`sort=` or `start=`+`end=`) on `/events/` URLs" (ask 3) | asked |
| `lint-followthrough-varq-ban.test.sh` R6-* rows | "no repo check currently covers this class" (issue §Proposed fix — the check must be shown non-vacuous) | inferred — justification: a lint without mutation rows can pass vacuously; the family convention requires per-rule mutation coverage |
| `followthrough-convention.md` bullet amendment | — | inferred — justification: the bullet states the rule in prose; naming its mechanical enforcer keeps doc and enforcement in step (the file already does this for rule 2) |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `knowledge-base/`
- Planned files: 11 | Estimated changed lines: ~250 (probe pins ≈ 15, lint rule ≈ 80, suite rows ≈ 120, comment/doc ≈ 15)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: Every executable-line `/events/` call under `scripts/followthroughs/` carries
  `sort=`, `start=`+`end=`, or a `field=<name>()` select; specifically the `/events/` call
  in each of the six pinned probes carries `sort=-timestamp` (re-derived census, not the
  issue's eight-name list — `egress-enforce-probe-11361.sh`'s is inline in the curl argv).
- [ ] AC2: `bash scripts/lint-followthrough-varq-ban.sh` (no arg, production run) exits 0
  and reports `scanned_rule6 >= 5`.
- [ ] AC3: `bash scripts/lint-followthrough-varq-ban.test.sh` exits 0 with all R6-* rows
  passing, including each Guard Contract matrix row.
- [ ] AC4: A guard copy with the `/events/` needle neutered exits 2 on the production tree
  with a diagnostic naming rule 6 (dispatch non-vacuity).
- [ ] AC5: `anthropic-admin-key-6297.sh` still sends `statsPeriod=48h` with no `sort` —
  documented exemption — and its `.test.sh` asserts the `field=count()` exemption basis.
- [ ] AC6: `sync-health-residual-5689.sh` is byte-untouched (out-of-scope `/issues/` call).
- [ ] AC7: `followthrough-convention.md`'s ordering bullet names rule 6 as the mechanical
  enforcer.
- [ ] AC8: `bash -n` clean on every touched probe; the `test-all.sh` affected shard
  (`scripts/followthrough-varq-ban`, `scripts/followthrough-varq-ban-live`,
  `anthropic-admin-key-6297` suite) is green.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The mechanical
UI-surface override did not fire (no `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx` in Files to Edit/Create); GDPR gate: no regulated-data surface and no
(a)–(d) trigger; IaC/ADR/Encryption/Task-Design gates: no infra, no architectural
decision, no store/connection, no new autonomous-task surface.

## Test Scenarios

- **unit** — Given a sandbox probe whose `/events/` URL has `statsPeriod` only, when the
  guard runs, then exit 1 citing the file at the true line (R6-M1).
- **unit** — Given a probe carrying `start=`+`end=` and no `sort=`, then exit 0 (R6-H1,
  non-canonical must-PASS).
- **unit** — Given a `field=count()` aggregate call with `statsPeriod` only, then exit 0
  (R6-H2, live exemption characterization).
- **unit** — Given an `/events/` URL inside a full-line comment, then exit 0 (R6-H3).
- **unit** — Given a `curl -G --data-urlencode 'sort=-timestamp'` continuation block, then
  exit 0 (R6-H4, shape-B folding).
- **unit** — Given a guard copy with a neutered needle on the production tree, then exit 2
  naming rule 6 (R6-M3, dispatch).
- **integration** — Given the real tree post-change, `bash
  scripts/lint-followthrough-varq-ban.sh` exits 0 and `scanned_rule6` ≥ 5.

## Context

Source learning: `knowledge-base/project/learnings/2026-10-29-sentry-events-sort-optional-pin-it-for-coverage-arguments.md`.
Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
Mirror: `scripts/followthroughs/discord-blog-webhook-fallback.sh:184` +
`discord-blog-webhook-fallback.test.sh:255`.

## References

- Issue: #11553 (deferred scope-out of PR #11543)
- Related: #11543 (merged), #11532 (closed)
- `scripts/lint-followthrough-varq-ban.sh` + `.test.sh` (rule-family conventions: per-rule
  counter, floor, dispatch mutation, header index entry)
- ADR-031 (Sentry token posture — the reads stay on `SENTRY_ACTIONS_RO_TOKEN`)
