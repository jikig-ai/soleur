---
title: "chore(agents): trim AGENTS B_ALWAYS under 22k and wire budget linter into CI"
issue: 4599
branch: feat-one-shot-trim-b-always-agents-payload
type: chore
brand_survival_threshold: none
lane: procedural
---

# chore(agents): trim AGENTS B_ALWAYS under 22k and wire budget linter into CI

`Closes #4599`

## Enhancement Summary

**Deepened on:** 2026-05-29
**Always-on gates run:** 4.6 User-Brand Impact (PASS — threshold `none` + scope-out reason), 4.7 Observability (PASS — section present, declares skip with rationale), 4.8 PAT-shaped variable scan (PASS — no hits), 4.4 precedent-diff gate (demotion pattern — precedent found).

### Key Improvements
1. **Loader class-fit verified against the live hook** (`session-rules-loader.sh:99-126`, excerpt cited below). Confirms the demotion lever is constrained to ship/merge-phase `wg-*` gates only; all other `wg-*` and every `hr-*`/`[compliance-tier]` stay in core.
2. **Precedent-diff (gate 4.4):** the two demotion targets are the same architectural class as the 4 ship/merge `wg-*` gates already resident in `AGENTS.rest.md` (`wg-ship-push-before-merge`, `wg-after-merging-a-pr-that-adds-or-modifies`, `wg-after-a-pr-merges-to-main-verify-all`, `wg-end-of-work-emit-resume-prompt`). Demotion follows precedent — NOT a novel placement.
3. **Residual-gap honesty:** the demotion inherits an *existing accepted* residual (a pure-docs PR classified `docs-only` does not load `rest`), the same residual the already-resident `wg-after-a-pr-merges-to-main-verify-all` accepts today. It introduces no NEW silent-drop class.

### New Considerations Discovered
- The 988 B `wg-defer-only-after-inline-triage` is NOT demotable (fires on docs-only deferral triage); it is body-trimmed in core (L1). This was the deepen pass's key correction to the issue's generic "demote wg-*" framing.
- B_ALWAYS counts only `AGENTS.md + AGENTS.core.md` regardless of loader behavior — the plan must not "fix" the budget by always-loading `rest` (would game the metric).

### Loader class-fit evidence (gate-required citation)

`sed -n '99,126p' .claude/hooks/session-rules-loader.sh`:

```bash
DOCS_RE='\.(md|markdown|txt|njk|html)$|^\.github/.*\.md$'
CODE_RE='\.(ts|tsx|js|jsx|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|rb)$'
INFRA_RE='\.tf$|^apps/[^/]+/infra/|\.github/workflows/|/?Dockerfile|/migrations/.*\.sql$'
# Class selection:
#   LOADER_FAIL_CLOSED=1            -> core docs-only rest
#   empty change set               -> core docs-only rest
#   HAS_CODE+HAS_INFRA+HAS_DOCS > 1 -> core docs-only rest   (multi-class)
#   HAS_DOCS == 1 (only)           -> core docs-only          (REST NOT LOADED)
#   HAS_CODE == 1 || HAS_INFRA==1  -> core rest
```

**Class-fit determination per demotion candidate:**

- `wg-after-marking-a-pr-ready-run-gh-pr-merge` (314 B) — ship/merge phase. `/ship` runs against a feature branch whose `git diff origin/main...HEAD` spans the feature's code+docs → multi-class → full load (incl. `rest`). **Demotable.**
- `wg-block-pr-ready-on-undeferred-operator-steps` (353 B) — ship Phase 5.5 gate (PR-ready time). Same multi-class-at-ship reasoning. **Demotable.**
- `wg-defer-only-after-inline-triage` (988 B), `wg-when-deferring-a-capability-create-a` (450 B), `wg-at-session-start-*`, `wg-every-feature-listed-in-a-roadmap-phase`, etc. — fire on **single-class docs-only** sessions (planning/work on a docs PR). `rest` not loaded there. **NOT demotable — body-trim in core instead.**
- All `hr-*` and `[compliance-tier]` (`cq-pg-security-definer`) — pinned to core by `lint-rule-ids.py:collect_residency_metadata` (CPO sign-off PR #3496). **NOT demotable by rule.**

## Overview

The AGENTS always-loaded payload `B_ALWAYS = len(AGENTS.md) + len(AGENTS.core.md)` is **26814 bytes** (`AGENTS.md`=5471 + `AGENTS.core.md`=21343) against a **22000-byte reject ceiling** measured by `scripts/lint-agents-rule-budget.py`. The payload is injected into context on **every** turn via the SessionStart loader (`.claude/hooks/session-rules-loader.sh` always loads `AGENTS.core.md`), so the overage is a per-turn reasoning-token tax.

Two problems, one PR:

1. **Budget breach.** B_ALWAYS must drop **below 22000** (target **≤20000** to clear the 20000 WARN tier and leave headroom — need to shed ≥6814 B from the always-loaded pair to hit 20000, ≥4814 B to merely clear reject).
2. **No CI gate.** `scripts/lint-agents-rule-budget.py` is wired only into `lefthook.yml` (pre-commit, `AGENTS*.md` glob). It is **not** in `scripts/test-all.sh` nor `ci.yml`, so a contributor without lefthook installed (or any CI run) does not catch a regression. Wire it into the `scripts` shard of `scripts/test-all.sh`, which `ci.yml` already runs unconditionally (`test-scripts` job, line 360).

Also: **4 core rule bodies exceed the 600-byte per-rule cap** (`PER_RULE_CAP`) and must be tightened to ≤600 B — without weakening guidance, by relocating verbose `**Why:**/**How:**` prose to the already-cited learning files (issue-number breadcrumb stays, making the detail grep-discoverable).

**Decision: Path (a) attempted, path-b hybrid landed.** Path (a) (trim under 22000 + wire the gate) was executed in full — but the trim, after exhausting L1/L3/L2 without weakening guidance, landed at B_ALWAYS 22782 (−15%), not under 22000. The plan's modelled ~21212 over-estimated the prose fat actually available once every directive/command/threshold/tag is preserved. Going lower required either weakening always-loaded hard-rule directives or demoting `wg-*` gates that fire on single-class docs-only sessions (#3681 silent-drop). Per **operator AskUserQuestion decision** (and issue #4599's explicit path-b offer, "raise the limit if 22k is stale"), the REJECT ceiling was raised 22000→23000 (WARN stays 20000) and the linter wired into CI as a real gate. See AC1 below for the resolution detail.

### How the budget is reduced (lever selection)

Three candidate levers exist; the investigation below establishes which are actually usable:

| Lever | Usable? | Why |
|---|---|---|
| **L1 — Body-trim over-cap rules** (relocate verbose Why/How to learning files, keep imperative + id + tags + issue-# breadcrumb) | **Yes — primary** | Mandatory anyway (4 rules over 600 B). Relocation is not weakening: the detail moves to a grep-discoverable learning file. |
| **L2 — Condense verbose rule bodies in core** (collapse long `see knowledge-base/.../<file>.md` path citations to the issue-# breadcrumb; compress redundant restatement/parenthetical examples) | **Yes — primary** | Issue explicitly endorses condensing. Issue-# alone makes the learning grep-discoverable (the `wg-every-session-error` discoverability convention). |
| **L3 — Demote `wg-*` core→rest** | **Constrained — only ship/merge-phase gates** | `hr-*` and `[compliance-tier]` bodies are **pinned to core** by `lint-rule-ids.py:collect_residency_metadata` (CPO sign-off PR #3496 — demoting an `hr-*` is a single-user-incident regression; the linter rejects it). For `wg-*`, the loader gates `rest` to **code/infra** sessions only (`session-rules-loader.sh:124-125`); a `wg-*` rule that fires on a single-class **docs-only** session would go silently absent (the #3681 regression). Only ship/merge-phase gates are demotable, because `/ship` operates on a multi-file feature branch → loader sees multi-class → loads everything (`session-rules-loader.sh:120-121`). |

**Net plan:** L1 + L2 do the bulk of the reduction; L3 demotes exactly the two ship/merge-phase `wg-*` gates whose siblings already live in `AGENTS.rest.md` (precedent), removing their bodies (and one over-cap body) from core entirely. See the per-item byte table in **Acceptance Criteria** — the per-item deltas sum to the aggregate target, per the Sharp Edge on aggregate numeric targets.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "demote `wg-*` rules core→rest" (issue body, generic) | Loader (`session-rules-loader.sh:114-126`) loads `rest` only on **code/infra** single-class sessions; **docs-only** loads `core+docs-only` (NOT rest). Most `wg-*` gates fire on docs-only sessions too. | Demote ONLY ship/merge-phase `wg-*` gates (multi-class at ship → full load). All other `wg-*` stay in core, body-trimmed via L2. |
| "retire rules via `scripts/retired-rule-ids.txt`" (issue body, optional) | `retired-rule-ids.txt` exists; `lint-rule-ids.py` enforces an `HR_RETIREMENT_ALLOWLIST` and rejects reuse. No rule meets the discoverability-litmus retirement bar in this scope. | **No retirements.** Demotion is a MOVE (id stays in the index, no `retired-rule-ids.txt` entry). Reduction comes from L1+L2+L3-move only. |
| A rule body could be duplicated into both `rest` and `docs` to satisfy multiple trigger classes | `lint-rule-ids.py` enforces pointer↔body **1:1** (`:339-347`); pointer regex (`:156`) targets **exactly one** class. A body in two sidecars = duplicate-id error. | A demoted body lives in **exactly one** sidecar (`rest`). This is why only multi-class-at-ship gates are demotable. |
| `B_ALWAYS` "should drop under 22k" | Linter counts **only** `AGENTS.md + AGENTS.core.md` bytes regardless of loader behavior (`lint-agents-rule-budget.py:6,48,112-114`). | Demotion reduces B_ALWAYS because the body leaves `AGENTS.core.md`; `rest`/`docs` are not counted. We do NOT game this by also-always-loading rest. |
| Budget linter "not CI-wired" | Confirmed: present in `lefthook.yml:96` only; absent from `scripts/test-all.sh` and all `.github/workflows/`. `ci.yml` `test-scripts` job runs `bash scripts/test-all.sh scripts` unconditionally (`:360`). | Wire a `run_suite` for the live linter + its companion `.test.sh` into the `want_scripts` shard of `test-all.sh`; CI inherits the gate automatically. |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct user-facing artifact — this edits agent-instruction files and one test-harness shell line. The indirect failure mode is an over-trimmed rule body that drops load-bearing guidance, degrading future agent behavior on the affected workflow (e.g., a weakened ship gate). Mitigated by the no-weakening constraint (relocate, don't delete) + plan-review.
**If this leaks, the user's data is exposed via:** N/A — no data, credential, auth, or payment surface is touched.
**Brand-survival threshold:** none, reason: edits to `AGENTS*.md` rule prose + one `scripts/test-all.sh` line; no production code/infra/data surface, no sensitive path (per preflight Check 6 canonical regex).

## Implementation Phases

### Phase 0 — Preconditions (read-only verification)

0.1 Re-measure baseline (worktree may have drifted):
```bash
wc -c AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md; echo "exit=$?"
```
Confirm B_ALWAYS ≈ 26814 and exactly the 4 per-rule violations (lines 17, 43, 44, 56 of `AGENTS.core.md`). If counts differ, re-derive the per-item table before editing.

0.2 Confirm the residency invariant (so the plan never proposes an illegal move):
```bash
sed -n '206,238p' scripts/lint-rule-ids.py   # collect_residency_metadata: hr-* + [compliance-tier] pinned to core
sed -n '150,160p' scripts/lint-rule-ids.py   # pointer regex: exactly one class per pointer
```

0.3 Confirm loader class-fit for the two demotion candidates (per the two AGENTS sidecar-loader-class-fit Sharp Edges and `wg-when-fixing-a-workflow-gates-detection`):
```bash
sed -n '114,126p' .claude/hooks/session-rules-loader.sh
```
Verify: docs-only → `core docs-only` (NO rest); code/infra → `core rest`; multi-class/empty/fail-closed → `core docs-only rest`. Record in the plan body the class-fit determination for each demotion candidate: both `wg-after-marking-a-pr-ready-run-gh-pr-merge` and `wg-block-pr-ready-on-undeferred-operator-steps` are **ship/merge-phase**; `/ship` runs against a multi-file feature branch (`git diff origin/main...HEAD` spans the feature's code+docs) → `HAS_CODE+HAS_INFRA+HAS_DOCS > 1` → full load including rest. This matches the precedent of the ship-phase gates **already** in `AGENTS.rest.md` (`wg-ship-push-before-merge`, `wg-after-a-pr-merges-to-main-verify-all`, `wg-end-of-work-emit-resume-prompt`). If Phase 0.3 finds the loader has changed such that ship sessions can be single-class docs-only, **abort the demotion lever** and reclaim the equivalent bytes via additional L2 condensing in Phase 2.

0.4 Confirm the per-rule 600 B cap applies to `AGENTS.rest.md` too (so a demoted-but-untrimmed 988 B body would still trip): `scripts/lint-agents-rule-budget.py:per_rule_violations` runs over every path passed, including rest. The demoted `wg-defer-only-after-inline-triage` (988 B) MUST be trimmed to ≤600 B on its way into rest. **Update [Phase 0.3 decision]:** see Phase 1 — `wg-defer-only-after-inline-triage` fires on docs-only (deferral triage during any planning/work, incl. docs PRs), so it is NOT demotable; it stays in core and is body-trimmed via L1. Only the two ship/merge gates demote.

### Phase 1 — L1: body-trim the 4 over-cap rules to ≤600 B (in `AGENTS.core.md`)

For each, keep the imperative + `[id: ...]` + enforcement tags + `**Why:** #NNNN` issue breadcrumb; relocate the long `**Why:** … — see knowledge-base/.../<file>.md` narrative and any `**How to apply:**` paragraph into the cited learning file (append a short section if the detail is not already there). The learning file is grep-discoverable by issue number, satisfying the discoverability convention.

| line | rule id | current B | target B | trim approach (no guidance loss) |
|---|---|---|---|---|
| 17 | `hr-ship-message-no-operator-checklist` | 833 | ≤590 | Collapse the two-sentence `**Why:** PR-2 #4062 …` incident narrative + `**How to apply:**` paragraph to `**Why:** #4062 — ship checklists hide bugs; pull data via API or file an issue with the verify command embedded.` Move the full narrative to `knowledge-base/project/learnings/` (grep `#4062`). |
| 43 | `hr-no-ssh-fallback-in-runbooks` | 822 | ≤590 | Keep the primary-debug-step list + "Last-resort only after 3 no-SSH attempts" rule. Collapse the `**Why:** TR9 PR-5 …` Vector/Sentry/pino narrative to `**Why:** #4116 — SSH-as-primary is a regression of the no-SSH observability contract.` |
| 44 | `hr-observability-layer-citation` | 610 | ≤590 | Minor: trim the trailing `**Why:** same TR9 PR-5 — the layers are honor-system without this citation gate.` to `**Why:** #4116 — layers are honor-system without the citation gate.` |
| 56 | `wg-defer-only-after-inline-triage` | 988 | ≤590 | Keep the triple test (1 inline-first / 2 concrete-trigger / 3 plausibility) verbatim — it is the load-bearing guidance. Collapse the `**Why:** PR #4379 Phase 7 audit found 6 of 10 …` paragraph to `**Why:** #4379 — file an issue only when all three checks pass; document Non-Goals in-plan otherwise.` |

After Phase 1, re-run the budget linter — the 4 per-rule violations MUST be zero.

### Phase 2 — L2: condense verbose bodies in `AGENTS.core.md` (no relocation of imperative or Why)

Target the large rules whose bodies restate enforcement prose, embed long inline path citations, or duplicate examples already in a cited learning file. Safe transforms (apply only where guidance is preserved):

- **Collapse long learning-path citations to issue-#** (5 occurrences, ~537 B): `see knowledge-base/project/learnings/best-practices/2026-05-20-hr-fresh-host-iac.md` → drop the path, keep `**Why:** #4017/#4118.` (issue-# breadcrumb makes the learning grep-discoverable). Apply to the `hr-tagged-build-workflow-needs-initial-tag-push`, `hr-fresh-host-provisioning-reachable-from-terraform-apply`, `hr-observability-as-plan-quality-gate`, `hr-monitor-not-run-in-background-for-polling`, and any other rule carrying a full `see knowledge-base/...md` tail.
- **Compress redundant restatement** in the ≥400 B tier (17 rules, 9344 B): remove sentences that merely re-assert the imperative in different words; fold parenthetical examples that duplicate the enforcement tag's referenced spec. Conservative target ~15-20% per touched rule. Do NOT touch the imperative clause, the `[id]`/enforcement tags, or the one-line `**Why:**` issue breadcrumb.

This phase is iterative: re-run the budget linter after each batch and stop once B_ALWAYS ≤ 20000 with margin. Do NOT over-trim past the target (avoid weakening guidance for bytes you do not need).

### Phase 3 — L3: demote the 2 ship/merge-phase `wg-*` gates core→rest

For **`wg-after-marking-a-pr-ready-run-gh-pr-merge`** (314 B) and **`wg-block-pr-ready-on-undeferred-operator-steps`** (353 B):

3.1 **Move the body** bullet out of `AGENTS.core.md` `## Workflow Gates` and into `AGENTS.rest.md` `## Workflow Gates` (verbatim, preserving id + tags + Why). If either body exceeds 600 B after the move, trim per L1 first (neither does: both <360 B).

3.2 **Flip the pointer tier tag** in `AGENTS.md` from `→ core` to `→ rest` for both ids. (The index pointer line stays — demotion is a move, not a removal; no `retired-rule-ids.txt` entry.)

3.3 Verify residency invariant did not break: `lint-rule-ids.py` must still pass (these are `wg-*`, not `hr-*`/`[compliance-tier]`, so the move is legal).

### Phase 4 — Wire the budget linter into the CI gate

Edit `scripts/test-all.sh`, in the `if want_scripts; then` block, immediately after the existing `scripts/lint-rule-ids-live` line (currently line 118):

```bash
  run_suite "scripts/lint-agents-rule-budget-live" \
    python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
  run_suite "scripts/lint-agents-rule-budget-unit" \
    bash scripts/lint-agents-rule-budget.test.sh
```

(`run_suite` treats a non-zero exit as `[FAIL]`. The live linter exits 1 on reject / 0 on pass — exactly the gating semantic we want.) `ci.yml`'s `test-scripts` job (line 360) runs `bash scripts/test-all.sh scripts` unconditionally on every PR, so no `ci.yml` edit is required — the gate is inherited. Add a one-line comment above the new `run_suite` lines citing `#4599`.

### Phase 5 — Verification (all must pass)

```bash
# 1. Budget under ceiling, ideally no WARN, zero per-rule violations
python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md; echo "exit=$?"
wc -c AGENTS.md AGENTS.core.md   # B_ALWAYS = sum, expect <22000 (target <=20000)

# 2. Pointer<->body residency still 1:1 after demotions
python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt \
  --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md; echo "exit=$?"

# 3. Enforcement-tag linter unaffected
python3 scripts/lint-agents-enforcement-tags.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md; echo "exit=$?"

# 4. Newly-wired CI gate passes (and the new run_suite entries appear in output)
bash scripts/test-all.sh scripts 2>&1 | grep -E "lint-agents-rule-budget"

# 5. Demoted ids resolve to rest in the index, bodies are in rest, gone from core
grep -nE 'wg-after-marking-a-pr-ready-run-gh-pr-merge|wg-block-pr-ready-on-undeferred-operator-steps' AGENTS.md
grep -cE 'id: wg-after-marking-a-pr-ready-run-gh-pr-merge|id: wg-block-pr-ready-on-undeferred-operator-steps' AGENTS.core.md  # expect 0
grep -cE 'id: wg-after-marking-a-pr-ready-run-gh-pr-merge|id: wg-block-pr-ready-on-undeferred-operator-steps' AGENTS.rest.md  # expect 2
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Budget cleared.** `python3 scripts/lint-agents-rule-budget.py …` exits **0** with B_ALWAYS **< reject ceiling**. **Resolution (operator decision + issue #4599 path-b):** the original `< 22000` target proved unreachable without weakening always-loaded hard-rule guidance or demoting `wg-*` gates that fire on single-class docs-only sessions (silent-drop regression, #3681). After exhausting every safe lever (L1 + L3 + L2), B_ALWAYS landed at **22915** (core 17459), a **−13.7%** reduction from 26814. Per the operator's AskUserQuestion decision, the REJECT ceiling was raised **22000 → 23000** (WARN stays 20000); the linter exits 0 (WARN tier) and the CI gate is green. **L3 correction (post-CI):** only `wg-after-marking-a-pr-ready-run-gh-pr-merge` is demotable — `wg-block-pr-ready-on-undeferred-operator-steps` is pinned to core by `ship-undeferred-operator-step-gate.test.ts` (TC-6/TC-9), which the plan's loader-analysis missed; CI surfaced the broken test after auto-merge was queued, and the demotion was reverted. See the learning for the prevention (grep `plugins/soleur/test/` for gate-id pins before demoting).
- [x] **AC2 — Per-rule cap clean.** Zero `rule body exceeds 600 B` errors across all four files (the 4 violations at core lines 17/43/44/56 resolved; no new ones introduced).
- [x] **AC3 — Residency intact.** `lint-rule-ids.py …` exits **0** (pointer↔body 1:1; every `hr-*` and `[compliance-tier]` body still in core; demoted `wg-*` pointers resolve to their rest bodies).
- [x] **AC4 — Gate wired.** `scripts/test-all.sh` contains `run_suite "scripts/lint-agents-rule-budget-live"` + `-unit` inside the `want_scripts` block; `bash scripts/test-all.sh scripts` exits 0 (81/81 suites). `grep -c 'lint-agents-rule-budget-live' scripts/test-all.sh` = 1.
- [x] **AC5 — No guidance deletion.** id-set diff empty — 89 ids identical before/after (no `retired-rule-ids.txt` additions).
- [x] **AC6 — Demotion class-fit recorded.** Recorded in PR body + plan: ship/merge-phase gates run against multi-file feature branches → loader sees multi-class → full load incl. rest; matches existing rest.md ship-gate precedent.
- [x] **AC7 — Per-item byte ledger.** Per-lever ledger in PR body (L1 −893, L3 −557, L2 path-tails −562, L2 condensing remainder; core 21343 → 17326).

### Per-item byte ledger (target model — actuals filled at /work time)

Baseline B_ALWAYS = 26814 (AGENTS.md 5471 + core 21343). **AGENTS.md is irreducible** (5071 B of 5471 B is the 89 mandatory pointer lines, ~56 B each; one per rule, required by `lint-rule-ids.py`). So **all reduction must come from `AGENTS.core.md`**:

- To clear the hard gate (<22000): core must reach **≤ 16528** B ⇒ shed **≥ 4815** B from core.
- To hit the stretch target (≤20000, no WARN): core must reach **≤ 14528** B ⇒ shed **≥ 6815** B from core.

**Deepen-plan correction (numeric self-consistency, per the aggregate-target Sharp Edge):** the first-draft ledger contained an arithmetic error (claimed −6702 total; the itemised deltas actually sum to −4076 for L1+L2+L3 as first modelled, leaving B_ALWAYS at ~22738 — over the gate). The measured guidance-preserving surface was re-derived below. The fixed-delta levers (L1 + L3) yield only ~1450 B; **L2 condensing must do the heavy lifting (≥3365 B to clear the gate, ≥5365 B for the target)** and is therefore the load-bearing, iterative lever — not an afterthought.

| Lever | Item | Δ (measured / modelled) |
|---|---|---|
| L1 | 4 over-cap rules → ≤590 B (relocate Why/How narrative) | **−893** (398+243+232+20) |
| L3 | demote 2 ship/merge `wg-*` bodies core→rest (~56 B pointer stays in index, counted on AGENTS.md side which is fixed; body bytes leave core) | **−557** (314−0 +353−0, less ~55 B index pointers that were never in core) ≈ **−557** |
| L2 | collapse long `see knowledge-base/…md` path tails to issue-# breadcrumb (measured: 562 B across core) | **−562** |
| L2 | relocate `**Why:**` narrative-excess beyond a bare issue-# ref to the cited learning file, across the ~17 rules NOT already harvested by L1 (measured non-overlapping surface ≈ 1490 B) | **−1490** |
| L2 | tighten verbose **imperative** prose (redundant restatement, duplicated examples already in the enforcement-tag's referenced spec) across the 57 core rules — preserving every directive, id, tag, one-line Why. Modelled ~12% of the residual ~17 700 B core body | **−2100** (iterative; /work stops at target) |
| | **Total shed from core** | **≈ −5602** |

Modelled core after = 21343 − 5602 ≈ **15741** ⇒ B_ALWAYS ≈ 5471 + 15741 = **21212**. This clears the **hard gate (<22000)** with ~788 B margin but is **above the 20000 stretch**. To reach ≤20000, /work continues the L2 imperative-tightening lever (the only one with remaining headroom) until the linter reports ≤20000 with no WARN, then STOPS (do not over-trim).

**AC1 gate priority at /work time:** (1) clear <22000 (hard, blocks merge); (2) approach ≤20000 (stretch, no WARN). If the measured L2 imperative-tightening yields less than modelled and ≤20000 proves unreachable without weakening guidance, land at the lowest achievable value <22000 and record the achieved figure + a one-line note in the PR body explaining the residual — do NOT delete a rule or strip a load-bearing directive to force the stretch number. The 20000 is a headroom goal; the 22000 is the contract.

## Files to Edit

- `AGENTS.md` — flip pointer tier tags `→ core` to `→ rest` for the 2 demoted `wg-*` ids (Phase 3.2). No id removed.
- `AGENTS.core.md` — L1 trims (4 rules), L2 condensing (multiple bodies), remove the 2 demoted `wg-*` bodies (Phase 3.1).
- `AGENTS.rest.md` — add the 2 demoted `wg-*` bodies under `## Workflow Gates` (Phase 3.1).
- `scripts/test-all.sh` — add 2 `run_suite` lines (live linter + companion `.test.sh`) in the `want_scripts` block, after the `lint-rule-ids-live` line (Phase 4).
- `knowledge-base/project/learnings/…` (as needed) — receive the relocated `**Why:**/**How:**` narratives from the L1-trimmed rules, IF the detail is not already present in the cited file (append a short section keyed by issue #). Verify each cited learning path exists (`grep -rl "#4062"`, `#4116`, `#4379`) before relocating.

## Files to Create

- None expected. (Relocated narratives append to existing learning files cited by the rules' issue numbers.)

## Open Code-Review Overlap

None. (No open `code-review` issue touches `AGENTS*.md` or `scripts/test-all.sh` in this scope; the only related artifact is #4599 itself.)

## Domain Review

**Domains relevant:** Engineering (CTO) only.

This is an agent-tooling / CI-governance change. No Product/UX surface (no `components/**/*.tsx`, no `app/**/page.tsx`). No Marketing, Finance, Legal, Ops, Sales, or Security domain implications — it edits rule prose and one test-harness line. Product/UX Gate: **NONE**.

## Observability

Skipped — pure docs/tooling change. No Files-to-Edit under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`; no new infrastructure surface. The only executable change is a `run_suite` line in `scripts/test-all.sh`, whose "observability" is its own CI pass/fail (`[ok]`/`[FAIL]` in the `test-scripts` job log).

## Infrastructure (IaC)

Skipped — no server, service, cron, vendor account, DNS, secret, or firewall rule introduced.

## GDPR / Compliance Gate

Skipped — no regulated-data surface (no schema, migration, auth flow, API route, `.sql`); none of the (a)-(d) expansion triggers fire (no LLM-on-session-data processing, threshold is `none`, no new cron reading learnings/specs, no new distribution surface — the AGENTS files are existing committed artifacts).

## Precedent-Diff (gate 4.4 — demotion pattern)

The core→rest demotion is a pattern-bound behavior with sibling precedent. `grep -nE 'id: wg-(ship-push-before-merge|after-merging-a-pr-that-adds|after-a-pr-merges-to-main|end-of-work-emit-resume-prompt)' AGENTS.rest.md` returns 4 ship/merge-phase `wg-*` gates already resident in `AGENTS.rest.md` `## Workflow Gates`. The two candidates are the same class (PR-ready / merge-time gates) and follow the same placement. **No novel pattern.** The move mechanics (body bullet relocated verbatim, index pointer `→ core` flipped to `→ rest`) mirror how those four already sit in rest with `→ rest` pointers in `AGENTS.md`.

## Risks & Mitigations

- **Over-trimming weakens a rule.** Mitigation: L1/L2 relocate detail to grep-discoverable learning files and keep the imperative + Why-breadcrumb; never delete a rule or its core directive. Plan-review + the no-guidance-deletion AC5 (id-set diff empty) guard this. Stop L2 as soon as ≤20000 is reached — do not trim for bytes not needed.
- **Demotion silently drops a gate on a session class.** Mitigation: Phase 0.3 records the loader class-fit; only ship/merge-phase gates (multi-class at ship → full load) demote, matching the existing rest.md ship-gate precedent. If the loader's class logic has changed (Phase 0.3 finds ship can be single-class docs-only), abort L3 and reclaim via L2.
- **Per-rule cap trips on the demoted 988 B rule.** Resolved structurally: `wg-defer-only-after-inline-triage` is NOT demoted (it fires on docs-only); it is body-trimmed in core via L1. The two demoted gates are both <360 B, under cap.
- **Modelled L2 yield falls short.** Mitigation: AC1's hard gate is <22000, which L1+L3 nearly meet alone; any L2 condensing clears it. The ≤20000 stretch is achievable with marginal extra L2; do not block on it.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this plan fills it (threshold `none` with a one-sentence reason, required because the diff is a non-sensitive path).
- `lint-agents-rule-budget.py` applies the 600 B per-rule cap to **all four files** including `AGENTS.rest.md` — any rule demoted into rest that exceeds 600 B will trip; trim before moving. (Both demoted gates are under cap; the 988 B rule stays in core.)
- The pointer regex requires the tier tag to be the **last token** on the line (`… → rest$`); when flipping `→ core` to `→ rest`, preserve exact spacing (` → `) or `lint-rule-ids.py:is_pointer_line` will reclassify the line as a body and break the 1:1 check.
- B_ALWAYS counts **only** `AGENTS.md + AGENTS.core.md` regardless of how the loader behaves — do NOT "fix" the budget by making `rest` always-load (that games the metric while keeping the context always-injected, defeating the issue's purpose).
