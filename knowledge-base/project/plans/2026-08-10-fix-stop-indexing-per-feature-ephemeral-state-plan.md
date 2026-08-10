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
---

# Stop indexing per-feature ephemeral state (Tier 1)

## Overview

`knowledge-base/INDEX.md` is the discovery surface `kb-search` (Tier 1),
`learnings-researcher` (Step 0), and `learning-retrieval-bench.sh` read to find prior
art. Regenerated from the current tree it enumerates **7,475 files**; **2,515 of them
(34%) are per-feature working state** inside `knowledge-base/project/specs/*/` —
`tasks.md`, `session-state.md`, and ~90 other one-off working filenames.

Change `scripts/generate-kb-index.sh` so a spec directory contributes only its
`spec.md` (plus anything the author deliberately organised into a subdirectory).
Nothing moves on disk. No archival, no gate, no backlog migration.

Decision record: the brainstorm. In short — archival's only real benefit was INDEX.md
exclusion, and the `git mv` that delivered it is what collides with ADR-084 §5. Take
the benefit directly; retire the move (Tier 2, #7400).

## Research Reconciliation — Spec vs. Codebase

| Spec / inherited claim | Codebase reality | Plan response |
|---|---|---|
| FR1: omit three named classes (`session-state.md`, `tasks.md`, `decision-challenges.md`) | The census finds **~90 distinct basenames** in live spec dirs, **~76 occurring exactly once** (`phase0-evidence.md`, `sentinel-sweep.md`, `ac-walk.md`, `mutation-evidence.md`…). A 3-name denylist leaves ~113 ephemeral rows indexed and cannot catch the next invented name. | **Mechanism changed to an allowlist**, operator-confirmed 2026-08-10: under `project/specs/`, index only `*/spec.md` plus anything at depth ≥3. Removes 2,515 rather than 2,408, and is structurally immune to new filenames. Spec FR1 is superseded by this plan; FR2/FR3/FR5 hold unchanged. |
| TR2: single-source constant — "the script has TWO `find` invocations, do not duplicate literals" | Verified by reading both. The second walk (`:136`) is rooted at `$LEARNINGS_DIR` = `project/learnings/` and **can never see `project/specs/`**. | **Only one `find` needs the change.** TR2's shared-constant requirement is dropped as unnecessary — a single edit site is simpler than a constant threaded through two. Asserted, not assumed. |
| TR6: "`scripts/*.test.sh` is NOT auto-discovered — registration is a task" | Correct, and worse than stated: **`plugins/soleur/test/generate-kb-index.test.sh` already exists and is registered nowhere.** Zero hits across 135 `run_suite` lines in `scripts/test-all.sh`. | Pre-existing orphan suite. Register it — this is a **bug fix in its own right**, independent of the feature, and it is what makes every test below actually gate. |
| Tests are net-new | The suite exists (`KB_DIR` env override + synthetic KB roots under `mktemp -d`). | **Extend**, don't author. Reuse the existing `setup_kb`/`run_generator` harness. |
| ADR-084 §5 needs `specs/<branch>/decision-challenges.md` readable | `ship/SKILL.md:1458` reads it **by filesystem path**, not via INDEX.md. Confirmed safe. | No conflict. Excluding it from the index cannot affect ship Phase 6. |
| The archival↔ADR-084 collision is an edge case | `ship/SKILL.md:2361` documents it as **sanctioned**: *"compound is the last point at which archival can happen. If compound's consolidation is skipped or deferred — a legitimate choice when Phase 6 still needs `specs/<branch>/decision-challenges.md` at its live path — then archival does not happen at all."* | Strengthens the brainstorm's conclusion; cite in ADR-172. The repo already documents that ADR-084 makes archival silently not run. |
| Nested plan `plans/feat-one-shot-reconcile-no-workspace-match/plan.md` exists (broke the reverted gate's `-maxdepth 1`) | **Verified present**, 4,763 bytes. It is the only nested plan. | Keep as a fixture shape (TR4) so the same blind spot cannot recur. |

**Premise Validation.** #7399/#7400/#7401 open, PR #7398 open — all created today by the
predecessor brainstorm; no stale premises. ADR-084 read in full (`## Decision` §5 +
`## Alternatives Considered`); it decides *where headless decision challenges are
recorded and rendered*, and does not decide anything about KB indexing — no rejected
alternative covers this mechanism. `archive-kb.sh` read in full; its `specs/feat-${slug}`
exact-path probe and `derive_slug()`'s `fix-` strip confirmed by direct read.

## Implementation Phases

### Phase 0 — Preconditions (no writes)

0.1 Re-run the baseline so the delta is measured, not inherited:

```bash
KB=knowledge-base
find "$KB" -type f -not -type l -name '*.md' -not -path '*/archive/*' -not -name 'INDEX.md' | wc -l
```

Expected **7475**. If it differs, re-derive every count in this plan before proceeding —
do not carry these numbers forward on faith.

0.2 Confirm the faceting walk is learnings-only (TR2 reconciliation above):
`grep -n 'find "\$LEARNINGS_DIR"' scripts/generate-kb-index.sh` returns exactly one line.

0.3 Confirm the orphan suite: `grep -c 'generate-kb-index' scripts/test-all.sh` returns **0**.

### Phase 1 — Register the orphan suite (RED-capable before any behaviour change)

Add to `scripts/test-all.sh`, adjacent to the other `plugins/soleur/test` registrations:

```bash
run_suite "plugins/generate-kb-index" bash plugins/soleur/test/generate-kb-index.test.sh
```

Run `bash scripts/test-all.sh` and confirm the suite now appears and passes against
current behaviour. **This must land before Phase 3** — otherwise the new tests are
written into a suite that still gates nothing, and a green run proves nothing.

### Phase 2 — Failing tests first (`cq-write-failing-tests-before`)

Extend `plugins/soleur/test/generate-kb-index.test.sh`. The existing `setup_kb` builds
only `project/learnings/`; add a sibling that builds `project/specs/` shapes.

Fixtures derived from **the repository's real shapes** (TR4), not from the code:

| Fixture | Path shape | Expected |
|---|---|---|
| F1 canonical spec | `specs/feat-x/spec.md` | **indexed** |
| F2 flat ephemeral | `specs/feat-x/tasks.md`, `session-state.md` | dropped |
| F3 long-tail ephemeral | `specs/feat-x/phase0-evidence.md`, `ac-walk.md` | dropped — **the case a denylist misses** |
| F4 `fix-` prefix | `specs/fix-y/spec.md` + `specs/fix-y/tasks.md` | spec indexed, tasks dropped — **prefix-independence, FR2** |
| F5 bare-named dir | `specs/review-workflow-hardening/spec.md` | indexed (real shape, exists on main) |
| F6 deliberate subdir | `specs/feat-z/case-studies/01-a.md` | **indexed** (depth ≥3) |
| F7 nested plan | `plans/feat-q/plan.md` | **indexed** — the shape that broke the reverted gate's `-maxdepth 1` |
| F8 flat plan | `plans/2026-01-01-feat-r-plan.md` | indexed (FR3) |
| F9 archive | `specs/archive/…/spec.md` | dropped (pre-existing behaviour, must not regress) |
| F10 `decision-challenges.md` | `specs/feat-x/decision-challenges.md` | dropped from index; **file still present on disk** (assert both) |

F10's disk assertion is load-bearing: it is the mechanical proof that ADR-084 §5's
read path is untouched.

### Phase 3 — The predicate (GREEN)

One edit, in the existing `find` at `scripts/generate-kb-index.sh:36-41` — the same
predicate that already carries `-not -path '*/archive/*'` (TR1):

```bash
find "$KB_DIR" -type f -not -type l -name '*.md' \
  -not -path '*/archive/*' \
  -not -name 'INDEX.md' \
  \( -not -path "$KB_DIR/project/specs/*" \
     -o -name 'spec.md' \
     -o -path "$KB_DIR/project/specs/*/*/*" \) \
  | LC_ALL=C sort
```

Read as: *include a file unless it is a flat file inside a spec directory that is not
`spec.md`.*

**Sharp edge — `find -path`'s `*` matches `/`.** This is the trap that would ship green.
It does not bite here, but only because each arm was checked against real paths:

- `specs/*/*/*` requires **two** literal `/` after `specs/`. `feat-x/tasks.md` has one,
  so it does not match; `feat-z/case-studies/01-a.md` has two, so it does.
- `specs/*/spec.md` is deliberately **not** used — `*` spanning `/` would make it match
  at any depth. `-name 'spec.md'` is used instead, which is depth-agnostic by design and
  simpler.

Phase 2's F3/F6/F7 are what pin this. Do not "simplify" the third arm to `specs/*/*`
without re-running them.

Verified empirically against the live corpus on 2026-08-10: **7,475 → 4,960 (−2,515)**;
survivors under `specs/` are exactly 321 `spec.md` + the 7 deliberate nested files.

### Phase 4 — Mutation battery (TR3)

Assert against the **call form and extracted block**, never a comment naming the
behaviour — the reverted gate passed 21/0 while an arm pointed at a different script
because a comment named the audited one (`2026-08-09-my-suites-were-hermetic…`).

Each mutation applied to a scratch copy MUST turn the suite RED. Enumerated, not hoped for:

| # | Mutation | Must fail via |
|---|---|---|
| M1 | Delete the whole `\( … \)` group | F2, F3 |
| M2 | Delete `-o -name 'spec.md'` | F1, F4, F5 |
| M3 | Delete `-o -path ".../specs/*/*/*"` | F6 |
| M4 | Change `-not -path "$KB_DIR/project/specs/*"` → `-path` | F8, and most of the corpus |
| M5 | Widen third arm to `specs/*/*` | F2, F3 (flat ephemera return) |
| M6 | Drop `-not -path '*/archive/*'` | F9 (pre-existing behaviour) |
| M7 | Narrow first arm to `specs/feat-*` | F4, F5 (the `archive-kb.sh` defect, reintroduced) |

M7 is the important one: it is the exact bug this plan exists to avoid repeating.

### Phase 5 — Real-corpus assertion (TR5)

Point the script at a **copy** so the committed `INDEX.md` is never written (NG4):

```bash
tmp=$(mktemp -d); cp -r knowledge-base "$tmp/kb"
KB_DIR="$tmp/kb" bash scripts/generate-kb-index.sh >/dev/null
grep -c 'project/plans'  "$tmp/kb/INDEX.md"   # unchanged vs baseline
grep -o 'project/specs[^)]*' "$tmp/kb/INDEX.md" | xargs -n1 basename | sort | uniq -c
rm -rf "$tmp"
```

This runs **the script**, not a re-typed copy of its predicate — an AC that re-types the
`find` would pass even if the script diverged (`cq-assert-anchor-not-bare-token`, input
side). Expected: spec-dir basenames are `spec.md` ×321 plus the 7 nested files, and
nothing else; plan row count unchanged.

`git status --short` must be clean afterwards — no `INDEX.md`, `kb-tags.txt`, or
`kb-categories.txt` in the diff (FR4).

### Phase 6 — ADR-172

Author `ADR-172-kb-index-exclusion-supersedes-per-feature-archival.md`, `status: adopting`.

The brainstorm's central finding is that per-feature archival had **no ADR and no rule
anywhere** — shipping its replacement undocumented would reproduce that exact defect.
Per `wg-architecture-decision-is-a-plan-deliverable` §Sequencing, the decision is only
fully true after Tier 2, so it is authored now describing the target state.

Content: the decision (index-exclusion, not `git mv`); the measurement; the ADR-084 §5
collision with `ship/SKILL.md:2361` cited as the repo's own record that archival
sanctionedly does not run; Tier 1 vs Tier 2 (#7400) sequencing; and
`## Alternatives Considered` covering keep-archival-and-fix-its-holes, delete-the-
convention-outright, and denylist-by-basename — each with the reason it lost.

**The ordinal is provisional.** ADR-171 is the highest on `origin/main` as of
2026-08-10; `/ship` re-verifies against a freshly-fetched `origin/main` before merge. If
it moves, sweep this plan, `tasks.md`, and every AC naming the ordinal in the same edit.

## Files to Edit

- `scripts/generate-kb-index.sh` — the `find` predicate at `:36-41` (Phase 3). One `\( … \)` group.
- `plugins/soleur/test/generate-kb-index.test.sh` — F1–F10 + M1–M7 (Phases 2, 4).
- `scripts/test-all.sh` — register the orphan suite (Phase 1).

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-172-kb-index-exclusion-supersedes-per-feature-archival.md`

## Files explicitly NOT touched

`plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` (NG2 — must be byte-identical),
`knowledge-base/INDEX.md` / `kb-tags.txt` / `kb-categories.txt` (NG4, #7401), and every
existing spec dir and plan (NG3, NG5 — no `git mv`, no gate).

## Open Code-Review Overlap

- **#2231** — *perf(kb-search): skip past frontmatter with nextfile in facet extraction*.
  Touches `scripts/generate-kb-index.sh`. **Acknowledge, do not fold in.** It targets the
  awk in the **faceting** walk (`$LEARNINGS_DIR`, `:136`); this plan edits only the
  **index** walk's path predicate (`:36-41`). Different function, no textual overlap,
  independent concerns. #2231 remains open.

## User-Brand Impact

Inherited verbatim from the brainstorm and spec — not re-authored.

- **If this lands broken, the user experiences:** KB search and prior-art sweeps
  returning wrong results — either missing real specs (over-exclusion) or still buried
  under per-feature scratch (under-exclusion). Both are silent.
- **If this leaks, the user's workflow is exposed via:** no new exposure vector; nothing
  moves, nothing is deleted, no new data surface. The risk is availability of correct
  discovery, not confidentiality.
- **Brand-survival threshold:** `single-user incident`. A discovery surface that is 34%
  per-feature scratch degrades the sweeps that stop an agent acting on a false greenfield
  premise in a customer's repo — the failure mode `2026-07-26-prior-art-sweep-by-function-and-scoped-agent-negatives.md`
  records.

CPO sign-off: carried forward from the brainstorm's `## Domain Assessments`, where the
operator elected to skip the leader triad on the grounds that this is internal KB tooling
with no user-facing, legal, sub-processor, or recurring-cost surface. Recorded as a
decision, not a gap. `user-impact-reviewer` fires at review time.

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-172** (provisional ordinal), `status: adopting` — see Phase 6.

### C4 views

**No C4 impact.** All three models read in full
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), not
grepped for the feature's own noun. Enumerated per the completeness mandate:

- **External human actors:** none added. The change adds no correspondent, reviewer, or recipient.
- **External systems / vendors:** none. `generate-kb-index.sh` is a local script — no webhook, no outbound API, no third-party store.
- **Containers / data stores touched:** `kb = database "Knowledge Base"` (`model.c4:85`) only, and its description enumerates *what the KB holds on disk* — unchanged, because nothing moves. Not falsified.
- **Actor↔surface access relationships:** unchanged. `skills -> kb`, `agents -> kb`, `hooks -> kb`, `api -> kb` all still read/write the same paths; only which rows `INDEX.md` lists changes. No element gains or loses reach.

There is no C4 element for index generation or `kb-search` today, and this change does
not create one — INDEX.md is an artifact *inside* the existing `kb` database, below C4
component granularity.

## Gates assessed and skipped, with reasons

- **2.5 Product/UX** — NONE. Mechanical UI-surface override scanned against Files to Edit/Create: `scripts/*.sh`, a `.test.sh`, and an ADR markdown. No path matches the UI-surface glob superset. No `.pen` required.
- **2.7 GDPR** — skipped. No schema, migration, auth flow, API route, or `.sql`. Triggers (a)–(d) checked individually: no LLM/external-API processing, no new artifact distribution surface, and the script that reads `project/specs/` is pre-existing and unchanged in *what it reads* (only what it emits) — not a new cron or workflow.
- **2.8 IaC** — skipped. No server, service, cron job, secret, DNS record, vendor account, or firewall rule is introduced. The detection scan over this plan body found no remote-shell invocation, no systemd unit install, no secret-store write, and no vendor-console wording.
- **2.9 Observability** — skipped. Files to Edit contain no code-class file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no new infrastructure surface. `scripts/generate-kb-index.sh` is a local/CI generator with no runtime error path and no execution surface to instrument. Stated rather than skipped silently, since it is a judgment call.
- **2.11 Encryption Posture** — skipped. No persistent store and no new cross-component connection. No `.tf`, no migration, no cloud-init, no compose file.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** Baseline reproduced: the Phase 0.1 command returns `7475` before any edit.
- [ ] **AC2** After Phase 3, the same command with the new predicate returns `4960` (delta −2515).
- [ ] **AC3** Phase 5 runs **the script** against a `cp -r` copy; spec-dir basenames in the produced INDEX.md are `spec.md` ×321 plus exactly the 7 nested files, and nothing else.
- [ ] **AC4** `grep -c 'project/plans'` on that produced INDEX.md is unchanged from baseline (FR3).
- [ ] **AC5** F1–F10 all present and passing in `plugins/soleur/test/generate-kb-index.test.sh`.
- [ ] **AC6** Every mutation M1–M7 turns the suite RED. Record the actual per-mutation failure in the PR body — a mutation list with no recorded RED is a hope, not a battery.
- [ ] **AC7** `grep -c 'generate-kb-index' scripts/test-all.sh` ≥ 1 (was 0), and `bash scripts/test-all.sh` shows the suite running and green.
- [ ] **AC8** `git diff --stat plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` is empty (NG2).
- [ ] **AC9** `git status --short` shows no `INDEX.md`, `kb-tags.txt`, or `kb-categories.txt` (NG4, FR4).
- [ ] **AC10** No file under `knowledge-base/project/{specs,plans}/` is added, deleted, or renamed: `git diff --name-status origin/main -- knowledge-base/project/specs knowledge-base/project/plans` shows only this feature's own new artifacts, and zero `R`/`D` status lines (NG3).
- [ ] **AC11** `ship` Phase 6's read path is intact: `specs/feat-kb-archival-convention/decision-challenges.md`, if written, exists on disk after generation (F10's disk half).
- [ ] **AC12** `ADR-172-*.md` exists with `status: adopting`, cites `ship/SKILL.md:2361` and ADR-084 §5, and its `## Alternatives Considered` names all three losing options. If the ordinal moved at ship, this AC names the final one.
- [ ] **AC13** `bash -n scripts/generate-kb-index.sh` clean; full `bash scripts/test-all.sh` green.

### Post-merge (operator)

None. Every step above is automatable in-session and runs inline. No operator action,
no dashboard, no vendor console.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `-path`'s `*` matches `/`, so an arm silently over/under-matches | Each arm hand-checked against real paths (Phase 3); F3/F6/F7 pin the boundaries; M5 catches the tempting `specs/*/*` simplification |
| The 7 nested survivors include 2 ephemeral evidence files (`feat-6538-web2-fsn1-orphan/measurements/*`) | Accepted. 2 rows against 2,515 removed; the depth-≥3 rule buys immunity to the ~76 one-off flat filenames, which is the dominant term |
| INDEX.md stays 3,711 rows stale after this ships | Out of scope by design (NG4). #7401 owns it. Phase 5 measures against a copy so this PR neither fixes nor worsens it |
| A future ephemeral file lands at depth ≥3 and gets indexed | Acceptable and self-limiting — a deliberate subdirectory is a deliberate act. Revisit only if observed |
| Tier 2 never lands, leaving `archive-kb.sh` in place unenforced | Status quo, not a regression — it is already unenforced. #7400 tracks; ADR-172 `status: adopting` records the half-done state honestly |

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Denylist the 3 named classes (spec FR1 as written) | Leaves ~113 long-tail ephemeral rows and cannot catch the next invented filename; ~76 basenames occur exactly once, so invention is the norm |
| Denylist all ~90 observed basenames | A snapshot of today's corpus requiring maintenance forever; same failure mode, deferred |
| Allowlist `spec.md` only, no subdir carve-out | Simpler by one clause, but drops 5 genuine `feat-product-strategy/case-studies/*` content rows |
| Move the case studies out of `specs/` and use the simple allowlist | A `git mv` — the exact mechanism this decision retires; also widens scope past Tier 1 |
| Fix `archive-kb.sh`'s holes and keep the `git mv` | Inherits the ADR-084 §5 collision that `ship/SKILL.md:2361` documents as sanctioned; costs a 3,054-path rename; does not fix half-archival |
| Build the reverted gate again, reworked | Any gate on the move inherits the same collision. `wip-kb-archival-gate-rework` should not be reworked |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains `TBD`/`TODO`, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled and carried forward verbatim.
- The ADR-172 ordinal is provisional. Re-derive against freshly-fetched `origin/main` immediately before merge, and when it moves, sweep this plan + `tasks.md` + AC12 in the same edit (`2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md`).
- Do not run `bash scripts/generate-kb-index.sh` in the worktree without restoring afterwards — it rewrites `INDEX.md`, `kb-tags.txt`, and `kb-categories.txt` in place. Phase 5's `cp -r` form exists to avoid this; it was hit once during brainstorm measurement and required `git checkout --` on three files.
- **Documenting a guard's trigger token trips the guard.** The first write of this plan was blocked by the IaC routing hook because the §Gates-skipped bullet quoted the literal token it had scanned for. Rephrased rather than opting out via `iac-routing-ack`, since there is no manual step to justify — the ack would have been a false attestation. Same shape as the AC self-reference grep trap already in this skill's Sharp Edges. Worth a hook refinement: exclude bullets that assert a *negative* finding.
