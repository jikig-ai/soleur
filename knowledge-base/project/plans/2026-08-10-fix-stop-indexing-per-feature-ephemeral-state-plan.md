---
title: "Stop indexing per-feature ephemeral state (Tier 1)"
date: 2026-08-10
type: fix
issue: "#7399"
branch: feat-kb-archival-convention
pr: 7398
worktree: .worktrees/feat-kb-archival-convention
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-kb-archival-convention/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-08-10-kb-archival-convention-brainstorm.md
plan_review: 6-agent panel 2026-08-10 (dhh, kieran, code-simplicity, architecture-strategist, spec-flow, cto)
---

# Stop indexing per-feature ephemeral state (Tier 1)

> **v2, post-plan-review.** A 6-agent panel found three P0 factual errors in v1 and four
> mutations that survived its battery green. Everything below is the corrected form; the
> `## Plan Review Revisions` section at the end records what changed and why, so the
> corrections are auditable rather than silently absorbed.

## Overview

`knowledge-base/INDEX.md` is a discovery surface agents grep for prior art. Regenerated
from the current tree it enumerates **7,482 files**, of which **1,275 are per-feature
working state** under `knowledge-base/project/specs/*/`.

Change `scripts/generate-kb-index.sh` so a spec directory contributes its `spec.md` and
its `tasks.md` — the two files that name a feature — and nothing else. Then regenerate
INDEX.md in this PR. Nothing moves on disk; no archival, no gate, no backlog migration.

**Who actually benefits — corrected.** v1 claimed three consumers. Two do not read spec
rows at all:

| Consumer | Reads spec/plan rows? |
|---|---|
| `learnings-researcher.md:15` Step 0 — *"reveals relevant files across ALL domains"* | **Yes — the only one** |
| `.openhands/skills/learnings-researcher/SKILL.md:15` — verbatim duplicate | **Yes** |
| `kb-search/SKILL.md:146` Tier 1 | No — *"restrict to lines whose link target is rooted under `knowledge-base/project/learnings/`"* |
| `learning-retrieval-bench.sh` | No — learnings-anchored (`:35`) |

So the benefit is scoped to `learnings-researcher` Step 0 and to any agent that greps
INDEX.md raw. That is still worth doing — Step 0 is the cross-domain prior-art sweep — but
the v1 framing overstated it and would not have survived `user-impact-reviewer`.

Decision record: the brainstorm. Archival's only real benefit was INDEX.md exclusion, and
the `git mv` that delivered it collides with ADR-084 §5. Take the benefit directly; retire
the move at Tier 2 (#7400).

## Why `spec.md` **and** `tasks.md`, not `spec.md` alone

**79% of live spec dirs have no `spec.md`** — 1,209 of 1,530. A `spec.md`-only allowlist
therefore de-indexes ~1,209 whole features, not just their scratch. Those `tasks.md` rows
carry real labels (`# Tasks: fix(ci) tenant-integration mig 062 schema-vs-ledger drift
(#4338)`), and ≥677 of those dirs have no indexed plan carrying the slug either.

Operator-confirmed 2026-08-10 after the panel surfaced this: index `spec.md` + `tasks.md`.

| Mechanism | Indexed | Removed | Features losing their only row |
|---|---|---|---|
| Today | 7,482 | — | — |
| `spec.md` only | 4,961 | 2,516 | **1,209** |
| **`spec.md` + `tasks.md`, flat-scoped (chosen)** | **6,207** | **1,275** | **261, of which 250 held only `session-state.md`** |

The 250 are dirs whose entire content is session scratch — no spec, no tasks. Dropping
them is correct. The genuine residual is **11 dirs** holding a long-tail file plus
`session-state.md`. Two of those are not feature dirs at all — `specs/external/`
(vendor interface reference) and `specs/openhands-portability/` — and are named
explicitly in ADR-173's Consequences rather than folded into the scratch count.

## Research Reconciliation — Spec vs. Codebase

| Spec / v1 claim | Reality | Response |
|---|---|---|
| Spec FR1: denylist 3 named classes | 69 distinct basenames in live spec dirs, 58 occurring exactly once (the ~90/~76 in earlier drafts came from the superseded denylist analysis and were never re-measured) | Superseded by the allowlist. Spec amended in this PR (see Files to Edit) — a spec left contradicting its plan reproduces the "no authoritative record" defect the brainstorm found |
| Spec G1: "with no predicate and no judgment call" | The mechanism **is** a predicate | Spec amended: "a single mechanical predicate, no per-file judgment" |
| Spec TR2: single-source constant across two `find`s | Second walk is rooted at `$LEARNINGS_DIR` (`:22`) and cannot reach `project/specs/`. Verified by reading both | Dropped as unnecessary — one edit site |
| **v1: "the test suite is an orphan, registered nowhere"** | **FALSE.** `scripts/test-all.sh` (the `for f in plugins/soleur/test/*.test.sh` glob loop) registers it via a glob loop (`for f in plugins/soleur/test/*.test.sh …; do run_suite "$f" bash "$f"; done`). It is item 18 of 60, runs under `want_scripts` (true for the default `TEST_GROUP=all`), and passes 24/0 today | **v1's Phase 1 deleted.** The `grep -c 'generate-kb-index' scripts/test-all.sh` that returned 0 is a false negative by construction — glob registrations never name their files. Adding a `run_suite` line would have made the suite run **twice**. `2026-04-14-plan-prescribed-test-framework-not-available.md:41` already recorded "picked up automatically by `scripts/test-all.sh`"; v1 contradicted it without citation |
| **v1: "ADR-171 is the highest on origin/main"** | **FALSE.** `ADR-172-ci-side-observability-emission-and-read-only-registry-inventory.md` merged to main today. v1's check read a stale local ref — no `git fetch` preceded it | Rebased onto `origin/main`; next free ordinal re-derived after fetch: **ADR-173** |
| **v1 predicate interpolated `$KB_DIR` into `-path`** | **Silently no-ops on a trailing slash.** `KB_DIR=knowledge-base/` → patterns become `…//project/specs/*`, which `find` never emits, so `-not -path` is always true and the exclusion vanishes: 7,477 indexed, exit 0, green suite. The pre-existing `rel="${f#"$KB_DIR/"}"` (`:62`) breaks identically, emitting absolute paths | Non-interpolated `'*/project/specs/*'` (immune, measured identical both forms) **plus** `KB_DIR="${KB_DIR%/}"` normalization at `:20`, which also fixes the pre-existing `rel=` bug |
| v1: `-name 'spec.md'` vs `specs/*/spec.md` is a checked trap | **Inert.** The two forms are empirically indistinguishable across the whole corpus, because arm 1 already admits everything outside `specs/`. Only a depth-1 `specs/spec.md` discriminates; zero exist | Claim and its task deleted. `-name` is kept on the honest grounds that it is simpler and depth-agnostic |
| Nested plan `plans/feat-one-shot-reconcile-no-workspace-match/plan.md` | Verified present, only nested plan | Kept as fixture F7 |
| ADR-084 §5 needs `decision-challenges.md` readable | `ship` Phase 6 step 2.5 reads it by filesystem path, not via INDEX.md | No conflict, independently confirmed by architecture-strategist |

**Premise Validation.** #7399/#7400/#7401 open; PR #7398 open. ADR-084 read in full — it
decides where headless decision challenges are recorded, and no rejected alternative covers
KB indexing. C4 "no impact" independently confirmed against all three `.c4` files.

## Implementation Phases

### Phase 0 — Preconditions (no writes)

0.1 Record the baseline **as a value, not an assertion**. Absolute literals decay on every
KB merge and on this PR's own artifacts — v1 asserted `7475` and measured `7477`, tripping
its own stop-the-line on turn one:

```bash
KB=knowledge-base
before=$(find "$KB" -type f -name '*.md' -not -path '*/archive/*' -not -name 'INDEX.md' | wc -l)
echo "baseline=$before"   # informational; no literal comparison
```

0.2 Confirm the faceting walk cannot reach `project/specs/`:
`grep -n 'find "\$LEARNINGS_DIR"' scripts/generate-kb-index.sh` → exactly one line.

0.3 Confirm the suite is **already registered** (glob-aware — a filename grep against
`test-all.sh` is a false negative):

```bash
for f in plugins/soleur/test/*.test.sh; do echo "$f"; done | grep -c 'generate-kb-index'  # expect 1
```

0.4 Read `scripts/generate-kb-index.sh:15-45` before editing.

### Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

Extend `plugins/soleur/test/generate-kb-index.test.sh`. Two prerequisites the suite lacks:

- **`GEN_SCRIPT` override.** `:12` hardcodes the path, so the mutation battery cannot point
  at a scratch copy. Change to `GEN_SCRIPT="${GEN_SCRIPT:-$REPO_ROOT/scripts/generate-kb-index.sh}"`.
  Without this, Phase 3 is unexecutable except by mutating the real script in the working
  tree — the fragile pattern `cf-tunnel-liveness-gate-mutations.test.sh` exists to avoid.
- **A `setup_kb_specs` sibling** to the existing `setup_kb` (which builds only `project/learnings/`).

Fixtures, derived from the repository's real shapes:

| # | Shape | Expected | Pins |
|---|---|---|---|
| F1 | `specs/feat-x/spec.md` | indexed | arm 2 |
| F2 | `specs/feat-x/session-state.md` | dropped | the change itself |
| F3 | `specs/feat-x/phase0-evidence.md`, `ac-walk.md` | dropped | long tail |
| F4 | `specs/fix-y/spec.md` + `tasks.md` indexed, `session-state.md` dropped | mixed | prefix-independence |
| F5 | `specs/review-workflow-hardening/spec.md` indexed **+ `session-state.md` dropped** | mixed | bare-named dir. **The sibling is load-bearing** — without it F5 is indexed before and after and discriminates nothing |
| F7 | `plans/feat-q/plan.md` | indexed | the `-maxdepth 1` shape that broke the reverted gate |
| F8 | `plans/2026-01-01-feat-r-plan.md` | indexed | plans untouched |
| F9 | `specs/archive/…/spec.md` | dropped | pre-existing archive arm |
| F10 | `specs/feat-x/decision-challenges.md` | dropped from index | ADR-084 read path is by filesystem, proven separately |
| **F11** | `INDEX.md` in the fixture root | never a row | `-not -name 'INDEX.md'` |
| **F12** | `specs/feat-x/diagram.png` | dropped | `-name '*.md'` — 356 `.png` + 93 `.pen` would enter without it |
| **F13** | `product/specs/feat-w/session-state.md` | **indexed** | only `project/specs/` is special. No such dir exists today, which is exactly why nothing pinned it |
| **F14** | `specs/feat-x/tasks.md` | **indexed** | the allowlist's second arm |
| **F15** | generator run with `KB_DIR="$kb/"` | byte-identical output to `KB_DIR="$kb"` | trailing-slash normalization |

F6 is gone with the depth-≥3 arm. v1's F10 disk-presence half is dropped — it asserted
that `find` is not `rm`, and no mutation can turn it red.

### Phase 2 — The predicate (GREEN)

Two edits to `scripts/generate-kb-index.sh`:

```bash
# :20 — normalize before any interpolation
KB_DIR="${KB_DIR:-$REPO_ROOT/knowledge-base}"
KB_DIR="${KB_DIR%/}"   # -path patterns and the rel= strip at :62 both break on a trailing slash

# :36-41 — one group added to the existing find
find "$KB_DIR" -type f -not -type l -name '*.md' \
  -not -path '*/archive/*' \
  -not -name 'INDEX.md' \
  \( -not -path '*/project/specs/*' -o -name 'spec.md' -o -name 'tasks.md' \) \
  | LC_ALL=C sort
```

Read as: *a spec directory contributes `spec.md` and `tasks.md`; everything else in it is
branch-lifetime working state.* Patterns are single-quoted and non-interpolated, so the
predicate cannot be disabled by the form of `KB_DIR`.

Measured on the live corpus: **7,477 → 6,196 (−1,281)**; survivors under `specs/` are
exactly 321 `spec.md` + 1,242 `tasks.md`.

Add a ~10-line WHY block above the group — the house style for sharp edges
(`test-all.sh:378`, `lefthook.yml:262`). It is the only place a future editor will read.
Also update `:10` (`# Excludes archive/ directories and INDEX.md itself.`), which is
`--help` output via the `sed` at `:27` and becomes incomplete.

### Phase 3 — Mutation battery

`GEN_SCRIPT=<mutant> bash <suite>` against a `cp`+`sed` mutant under `mktemp -d`. Each must
turn the suite RED; record the actual failure per row.

| # | Mutation | Caught by |
|---|---|---|
| M1 | delete the whole `\( … \)` group | F2, F3, F4, F5 |
| M2 | delete `-o -name 'spec.md'` | F1, F4, F5 |
| M4 | flip `-not -path` → `-path` | F2, F3, F7, F8 |
| M6 | drop `-not -path '*/archive/*'` | F9 |
| M7 | narrow arm 1 to `*/project/specs/feat-*` | F4, **F5's new sibling** — v1 attributed this to bare F5, which cannot discriminate it |
| **M9** | drop `-not -name 'INDEX.md'` | F11 |
| **M13** | loosen arm 1 to `*specs/*` | F13 |
| **M14** | delete `-o -name 'tasks.md'` | F14 |
| **M15** | drop `-name '*.md'` | F12 |
| **M16** | delete the `KB_DIR%/` normalization | F15 |

M3/M5 are gone with the depth-≥3 arm. Do **not** add a row for `-not -type l`: `-type f`
already excludes symlinks, so deleting it is semantically null and no fixture can go red.

### Phase 4 — Differential real-corpus assertion

Generate twice on **one** copy — pre-edit script, then edited script — so the comparison is
internal and no literal can decay:

```bash
tmp=$(mktemp -d); cp -r knowledge-base "$tmp/kb"
git show HEAD:scripts/generate-kb-index.sh > "$tmp/pre.sh"
KB_DIR="$tmp/kb" bash "$tmp/pre.sh" >/dev/null; before_plans=$(grep -c 'project/plans' "$tmp/kb/INDEX.md")
KB_DIR="$tmp/kb" bash scripts/generate-kb-index.sh >/dev/null; after_plans=$(grep -c 'project/plans' "$tmp/kb/INDEX.md")
[ "$before_plans" = "$after_plans" ] || echo "FAIL: plan rows changed"
sed -n 's|^- \[.*\](\(project/specs/[^)]*\))$|\1|p' "$tmp/kb/INDEX.md" | xargs -n1 basename | sort -u
rm -rf "$tmp"
```

The last line is the load-bearing invariant and must print exactly `spec.md` and
`tasks.md`. It runs **the script**, extracts **link targets** (not any line containing the
literal `project/specs`, which this plan's own title would match), and asserts a **set**,
not a count.

### Phase 5 — Regenerate INDEX.md

Operator decision 2026-08-10, reversing v1's NG4. `lefthook.yml:257-260` already
regenerates and `git add`s INDEX.md on any commit touching `knowledge-base/**/*.md`, so
deferral was never real — it only relocated the diff into some future unrelated PR, at
~6,200 lines. v1's NG4 held solely because lefthook is not installed on this machine, and
its AC checked the working tree while the hook stages to the index.

Regenerate as the **final commit**, alone, with the diff explained in the PR body. It is a
generated artifact and this is the one PR where a full regeneration is legible.
`kb-tags.txt` and `kb-categories.txt` are written by the same script — commit all three.

Comment on #7401 that its remaining scope is the CI freshness gate only, and name
`plugins/soleur/test/c4-model-freshness.test.sh` as the precedent to copy.

### Phase 6 — ADR-173

`ADR-173-kb-index-exclusion-supersedes-per-feature-archival.md`, `status: adopting`
(established vocabulary — 7 existing ADRs use it).

Must record: the decision; the measurement; the ADR-084 §5 collision with
`ship/SKILL.md` (sentence beginning "The practical consequence: compound is the last point") as the repo's own record that archival sanctionedly does not run; the
79%-no-`spec.md` finding that drove `spec.md` + `tasks.md`; Tier 2 (#7400) sequencing; and
`## Alternatives Considered` covering keep-archival-and-fix-its-holes,
delete-the-convention-outright, denylist-by-basename, and `spec.md`-only.

**Ordinal re-derived after `git fetch` on 2026-08-10; ADR-172 is taken.** `/ship`
re-verifies; if it moves, sweep plan + tasks + AC in one edit.

## Files to Edit

- `scripts/generate-kb-index.sh` — `KB_DIR` normalization (`:20`), the predicate group (`:36-41`), the WHY block, the `:10` header/`--help` line
- `plugins/soleur/test/generate-kb-index.test.sh` — `GEN_SCRIPT` override, `setup_kb_specs`, F1–F15
- `knowledge-base/project/specs/feat-kb-archival-convention/spec.md` — amend G1, FR1; drop TR2; strike absolute counts
- `plugins/soleur/agents/engineering/research/learnings-researcher.md:15` — *"INDEX.md lists every non-archived KB file with its title"* is falsified by this change
- `.openhands/skills/learnings-researcher/SKILL.md:15` — verbatim duplicate of the same claim
- `plugins/soleur/skills/brainstorm/SKILL.md:232` — reasons from one exclusion class (`/archive/`); there are now two
- `plugins/soleur/skills/spec-templates/SKILL.md:73-78` — state the rule where spec dirs are created; this is the only discoverability fix that reaches authors
- `plugins/soleur/skills/archive-kb/SKILL.md` — superseded-in-part pointer to ADR-173 + #7400, so nobody rebuilds the reverted gate. NG2 covers only the *script*
- `knowledge-base/INDEX.md`, `kb-tags.txt`, `kb-categories.txt` — Phase 5 regeneration

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-173-kb-index-exclusion-supersedes-per-feature-archival.md`

## Files explicitly NOT touched

`plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` (NG2 — byte-identical; its
retirement is #7400's exit criterion). No spec dir or plan is added, deleted, or renamed
(NG3). No archival gate (NG5).

## Open Code-Review Overlap

- **#2231** — *perf(kb-search): skip past frontmatter with nextfile in facet extraction*.
  Same file, different function: it targets the awk in the **faceting** walk
  (`$LEARNINGS_DIR`, `:135`); this plan edits the **index** walk (`:36-41`) and `:20`.
  **Acknowledge, do not fold in.** Remains open.

## User-Brand Impact

- **If this lands broken, the user experiences:** prior-art sweeps returning wrong results — missing real specs, or still buried under scratch. Both silent.
- **If this leaks:** no new exposure vector. Nothing moves, nothing is deleted, no new data surface.
- **Brand-survival threshold:** `single-user incident`. The risk concentrates in the three prose files above, not in the predicate: they assert an INDEX.md completeness invariant this change falsifies, and an agent trusting it reads an empty grep as "no prior art" — the #6962 shape this work cites as its own justification.

CPO sign-off carried forward from the brainstorm. `user-impact-reviewer` fires at review.

## Architecture Decision (ADR/C4)

### ADR
Create **ADR-173**, `status: adopting` — Phase 6.

### C4 views
**No C4 impact**, independently confirmed by architecture-strategist against all three
models. No external human actor added; no external system or vendor; the only container
touched is `kb = database "Knowledge Base"` (`model.c4:85`), whose description enumerates
on-disk contents — unchanged, because nothing moves. All inbound edges (`hooks -> kb` :438,
`api -> kb` :439/:456, `skills -> kb` :457, `agents -> kb` :458, and the L3
`brainstorm/plan/work/compound/architecture -> kb` edges :640-644) are unchanged in reach.
No element exists for index generation; INDEX.md is an artifact inside `kb`, below C4
component granularity.

## Gates assessed and skipped

- **Product/UX** — NONE. No path in Files to Edit/Create matches the UI-surface glob superset.
- **GDPR** — skipped. No schema, migration, auth flow, API route, or `.sql`; triggers (a)–(d) checked individually.
- **IaC** — skipped. No server, service, cron job, secret, DNS record, vendor account, or firewall rule.
- **Observability** — skipped. No code-class file under `apps/*/server|src|infra` or `plugins/*/scripts`; a local/CI generator with no runtime error path.
- **Encryption Posture** — skipped. No persistent store, no new cross-component connection.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** Phase 4's differential runs on one `cp -r` copy: `project/plans` row count identical pre-edit vs post-edit.
- [ ] **AC2** Phase 4's set assertion prints exactly `spec.md` and `tasks.md` — no third basename, extracted from link targets.
- [ ] **AC3** `before − after` equals the count of dropped files computed in the same session; no absolute literal appears in any AC.
- [ ] **AC4** F1–F15 present and passing.
- [ ] **AC5** Every mutation M1–M16 turns the suite RED, with the actual failure recorded per row in the PR body.
- [ ] **AC6** `GEN_SCRIPT` override present, so the battery runs against mutants without touching the working tree; `git status` clean after the battery.
- [ ] **AC7** `git diff --stat plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` empty (NG2).
- [ ] **AC8** `git diff --name-status origin/main...HEAD -- knowledge-base/project/specs knowledge-base/project/plans` shows only this feature's own artifacts, zero `R`/`D` lines. **Three-dot** — two-dot compares tips and reports main's movement as this branch's deletions.
- [ ] **AC9** Every site asserting INDEX.md completeness is amended. The literal-phrase
      grep that was used here (`"lists every non-archived KB file"` over `plugins/ .openhands/`)
      is the DEFECT, not the check: it cannot see the same claim phrased as
      "excludes `**/archive/`" or "lists all KB files", and it does not look in
      `knowledge-base/`. Sweep semantically across all three roots and classify every hit:
      `grep -rn "0\*\* .\/archive\/. rows\|excludes .\*\*\/archive\/\|lists all KB files\|every KB file\|all KB files\|lists every non-archived" knowledge-base/ plugins/ .openhands/`
- [ ] **AC10** `ADR-173-*.md` exists, `status: adopting`, cites ADR-084 §5 + `ship/SKILL.md` (sentence beginning "The practical consequence: compound is the last point"), and its Alternatives table names all four losing options. Ordinal re-verified against fetched `origin/main` at ship.
- [ ] **AC11** INDEX.md, `kb-tags.txt`, `kb-categories.txt` regenerated in a final standalone commit; the generated INDEX.md matches a fresh run of the merged script.
- [ ] **AC12** `bash -n scripts/generate-kb-index.sh` clean; full `bash scripts/test-all.sh` green, with the suite appearing exactly **once** in the runner output.

### Post-merge (operator)

None. Every step is automatable in-session.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| 264 spec dirs lose their only row | 250 contain nothing but `session-state.md` — correct to drop. The genuine residual is 14 dirs with a long-tail file; named here, accepted |
| 107 flat long-tail files dropped, incl. `migration-checklist.md` ×21, `dpa-verification-memo.md` ×2 | Real content misfiled as flat scratch. Remedy is self-service and one sentence in `spec-templates/SKILL.md`: put real content in a subdirectory or name it `spec.md` |
| The rule is discoverable from nowhere authors work | `spec-templates/SKILL.md:73-78` + the `--help`/header line + the WHY block above the code |
| Regenerating INDEX.md makes this PR large | Deliberate, isolated to its own final commit, explained in the PR body. The alternative was a ~6,200-line diff landing in someone else's PR |
| Tier 2 never lands | Status quo, not a regression. The `archive-kb/SKILL.md` pointer stops the reverted gate being rebuilt |

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| `spec.md`-only allowlist | De-indexes 1,209 whole features (79% of spec dirs have no `spec.md`); their `tasks.md` row was their only presence |
| Denylist 3 named classes (spec FR1) | Leaves ~113 long-tail rows; ~76 basenames occur exactly once, so invention outpaces the list |
| Denylist all ~90 observed basenames | A snapshot needing maintenance forever — the same failure mode |
| Depth-≥3 subdirectory carve-out | Buys 7 rows, 2 of which the plan itself classifies as ephemeral; costs a third arm, 2 fixtures, 2 mutations, and forces a frozen-census AC. Cut on dhh + code-simplicity recommendation |
| Keep `git mv` archival, fix its holes | Inherits the ADR-084 §5 collision; costs a 3,054-path rename; does not fix half-archival |
| Rebuild the reverted gate | Any gate on the move inherits the collision |

## Plan Review Revisions

6-agent panel, 2026-08-10. All findings below were independently re-verified before applying.

- **R1 (P0, 4 agents)** — v1's "orphan suite" premise was false; `test-all.sh`'s glob loop registers it by glob. v1's Phase 1, AC7, and a standalone commit deleted. v1 asserted a bare token against one enumeration form **two sections after prohibiting exactly that** — the defect it opened by warning about.
- **R2 (P0, architecture-strategist)** — ADR-172 was already taken on `origin/main`; v1's ordinal came from a stale ref with no `git fetch`. Rebased; renumbered to ADR-173.
- **R3 (P0, dhh + kieran)** — `$KB_DIR` interpolated into `-path` made the predicate form-dependent; a trailing slash silently disabled it (7,477 indexed, exit 0, green). Non-interpolated patterns + `KB_DIR%/` normalization, which also fixes the pre-existing `rel=` bug at `:62`.
- **R4 (cto)** — 79% of spec dirs have no `spec.md`; the approved mechanism would have de-indexed ~1,209 features. Re-confirmed with the operator; mechanism changed to `spec.md` + `tasks.md`.
- **R5 (kieran)** — 4 mutations survived v1's battery (M9, M13, M15, and the arm-2 form change); M7's F5 attribution was wrong (F5 had no sibling and could not discriminate it). F5 given a sibling; F11–F15 and M9/M13/M14/M15/M16 added.
- **R6 (kieran)** — v1's headline `*`-spans-`/` sharp edge is inert: `-name 'spec.md'` and `specs/*/spec.md` are indistinguishable across the corpus. Claim and its task deleted rather than left asserted-but-unpinned.
- **R7 (all)** — every absolute count was stale and mixed two trees (baseline from `origin/main`, `spec.md` count from the worktree). All ACs converted to same-session differentials.
- **R8 (dhh + arch + spec-flow)** — `lefthook.yml:257-260` regenerates and auto-stages INDEX.md; v1's NG4 held only by accident of local setup, and its AC checked the working tree while the hook stages to the index. Operator reversed NG4: regenerate here.
- **R9 (arch + spec-flow)** — `kb-search` Tier 1 and the bench are learnings-anchored and read no spec rows. Overview corrected; only `learnings-researcher` Step 0 benefits.
- **R10 (arch + spec-flow)** — three prose files assert an INDEX.md completeness invariant this change falsifies, including `.openhands/skills/learnings-researcher/SKILL.md`, absent from v1 entirely. Added to Files to Edit. This is where the single-user-incident risk actually lives.
- **R11 (spec-flow)** — the suite hardcodes `GEN_SCRIPT`, making v1's battery unexecutable as specified. Override added as a Phase 1 prerequisite.
- **R12 (spec-flow + kieran)** — v1's task "confirm F1–F10 are RED against the unmodified script" was impossible; most fixtures are regression guards, GREEN before and after. Rewritten to name only the genuinely-RED set.
- **R13 (dhh + code-simplicity)** — depth-≥3 arm cut; F6, M3, M5 and the slash-arithmetic block go with it.
- **R14 (cto)** — 7 of 316 test suites are genuine orphans (not systemic), 4 of them `linear-fetch/scripts/` including a secret-redaction gate. Two glob blind spots in `test-all.sh`'s glob loop. **Filed separately — deliberately out of scope here.**

## Sharp Edges

- `lefthook.yml:257-260` regenerates and `git add`s INDEX.md on any KB-markdown commit. Post-merge, the first contributor who commits KB markdown gets the full regeneration in their diff. Phase 5 defuses this for the exclusion delta; the CI freshness gate (#7401) is what stops it recurring.
- Running `bash scripts/generate-kb-index.sh` in the worktree rewrites three files in place. Phase 4's `cp -r` form exists to avoid it.
- Documenting a guard's trigger token trips the guard: v1's first write was blocked by the IaC routing hook because a bullet quoted the literal token it had scanned for. Rephrased rather than opting out via `iac-routing-ack`, which would have been a false attestation.
- The ADR ordinal is provisional until merge. Re-derive against **fetched** `origin/main` — v1 got this wrong by reading a stale local ref, which is the failure the rule exists to prevent.
