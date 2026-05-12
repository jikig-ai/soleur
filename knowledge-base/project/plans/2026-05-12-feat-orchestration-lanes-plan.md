---
feature: feat-orchestration-lanes
issue: 2721
parent_issue: 2718
parent_spec: knowledge-base/project/specs/feat-claude-skills-audit/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-12-orchestration-lanes-brainstorm.md
spec: knowledge-base/project/specs/feat-orchestration-lanes/spec.md
branch: feat-orchestration-lanes
draft_pr: 3625
brand_survival_threshold: none
lane: cross-domain
type: feature
classification: skill-prose-edit
---

# Plan — Named Orchestration Lanes (Single-Axis, 3 Lanes)

## Overview

Add a three-value `lane:` field that captures **brainstorm Phase 0.5 domain-leader breadth** for a session: `single-domain`, `cross-domain`, `procedural`. Auto-detected at a new Phase 0.4 (between Phase 0.1 and Phase 0.25), force-set to `cross-domain` when `USER_BRAND_CRITICAL=true`, fail-closed to `cross-domain` on ambiguity. Carried via YAML frontmatter through **spec.md → plan.md** (spec.md is canonical post-Phase-3.6); `work` reads it from spec.md frontmatter and announces it. `work` Tier 0/A/B/C is untouched and lane is non-binding in skill logic.

5 file edits, 1 new shell test, 1 parent-spec amendment. No new agent, no new skill, no AGENTS.md rule.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| FR3 says lane: appears in brainstorm-doc + spec.md + plan.md | brainstorm-doc currently uses prose (no frontmatter prescription); canonical brainstorm template lives in `brainstorm-techniques` skill, not in brainstorm SKILL.md | **Drop brainstorm-doc frontmatter prescription.** spec.md is the canonical post-3.6 source; brainstorm-doc carries frontmatter as my 2026-05-12 example shows but skill prose does NOT prescribe it. Per architecture review P2 + DHH cut: skipping brainstorm-doc-as-contract is viable; spec.md is authoritative |
| Plan needs awk frontmatter extraction | Robust precedent at `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:34`: `awk '/^lane:/ { gsub(/^lane:[[:space:]]*"?\|"?$/, ""); print; exit }'` (handles quoted values + trailing whitespace) | Adopt this pattern verbatim in plan + work + test. `awk '/^lane:/ {print $2}'` is brittle (Kieran P1.2) |
| Preflight Check 6.1 sensitive-path regex would catch missing User-Brand Impact | Regex anchors to `apps/web-platform/**`, `apps/*/infra/**`, `*/doppler*.{yml,yaml,sh}`, `.github/workflows/*.yml` — none match `plugins/soleur/skills/**/SKILL.md` | Preflight Check 6 SKIPs for this PR. User-Brand Impact section is single-sentence per DHH cut |
| Tests at `tests/scripts/` | Actual convention: `plugins/soleur/test/*.test.sh`. Direct precedents: `notice-frontmatter.test.sh`, `lint-distribution-content.test.sh` | New test at `plugins/soleur/test/lane-frontmatter.test.sh` |
| Open code-review backlog may overlap | `gh issue list --label code-review --state open` → 74 open, zero match against any of the 5 edited files | None — recorded |

## User-Brand Impact

Threshold: `none`. Skill prose edits only; preflight Check 6.1 canonical regex is non-matching against all 5 edited paths. Meta-observation: this feature *governs* whether the user-impact gate fires for downstream brainstorms — the fail-closed `cross-domain` default and `USER_BRAND_CRITICAL=true` force are the load-bearing defenses.

## Domain Review

**Domains relevant:** Product, Engineering, Marketing — carried forward verbatim from the 2026-05-12 brainstorm `## Domain Assessments`. CPO locks Soleur-idiom labels + fail-closed default. CTO confirms single-axis preserves work Tier system unchanged. CMO confirms renaming drops MIT per-file attribution obligation.

**Product/UX Gate:** none. Plan implements orchestration prose, not UI surface. No new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` — mechanical escalation does not fire.

## Open Code-Review Overlap

None. 74 open `code-review` issues queried; zero match against any of the 5 planned edit paths.

## Files to Edit

1. `plugins/soleur/skills/brainstorm/SKILL.md` — insert Phase 0.4 (lane selection + pipeline-mode fallback); prepend Phase 0.5 Processing Instructions step 0; modify Phase 3.6 step 4 to prescribe `lane:` in **spec.md** frontmatter (NOT brainstorm-doc — spec.md is canonical).
2. `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` — append `## Lane Inference` (compact: one table + carry-forward + USER_BRAND_CRITICAL composition order).
3. `plugins/soleur/skills/plan/SKILL.md` — modify `## Save Tasks to Knowledge Base` to extract `lane:` from spec.md via the canonical `gsub` awk pattern, validate against the 3-value enum, propagate to plan.md frontmatter, fail-closed to `cross-domain` + body note on missing/invalid.
4. `plugins/soleur/skills/work/SKILL.md` — Phase 0 step 4.5 reads `lane:` from spec.md (file-existence guarded), validates enum, includes in the existing announce string when present.
5. `knowledge-base/project/specs/feat-claude-skills-audit/spec.md` — minimal amendment: FR4 four-lane enumeration → three-lane single-axis (one-sentence + link); TR7 specify fail-closed default.

## Files to Create

1. `plugins/soleur/test/lane-frontmatter.test.sh` — content-gate test, 6 assertions (no synthetic round-trip; no keyword count; just marker-existence checks per DHH/simplicity cut). Honest test-shape limitation acknowledged inline.

## Implementation Phases

5 phases. Contract-before-consumer ordering preserved for review readability; per-file commits are atomic units of revert.

### Phase 1 — Test Scaffold (RED)

Create `plugins/soleur/test/lane-frontmatter.test.sh` with these failing assertions:

1. `brainstorm-domain-config.md` contains `^## Lane Inference$` AND mentions all three lane values (`single-domain`, `cross-domain`, `procedural`).
2. `brainstorm/SKILL.md` contains heading `Phase 0.4: Lane Auto-Detect and Selection`.
3. `brainstorm/SKILL.md` Phase 0.5 Processing Instructions list has a `0.` numbered step that reads `LANE`.
4. `brainstorm/SKILL.md` Phase 3.6 step 4 mentions `lane:` in spec.md frontmatter prescription.
5. `plan/SKILL.md` `## Save Tasks to Knowledge Base` section mentions `lane:` extraction from spec.md.
6. `work/SKILL.md` Phase 0 references `lane:` AND the announce string conditionally includes lane.
7. Parent audit spec `feat-claude-skills-audit/spec.md` FR4 contains literal "three named lanes"; TR7 contains literal "cross-domain" (fail-closed).

Test file header MUST carry a one-line comment: `# Marker-existence gate; does NOT prove semantic correctness — see plan §Risks R3.`

**Commit:** `test: scaffold lane-frontmatter content gate (RED)`

### Phase 2 — Lane Inference Vocabulary

Append to `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` (after the existing `## User-Brand-Critical Tag Processing` section):

```markdown
## Lane Inference

Lanes describe **Phase 0.5 domain-leader breadth** (single source of truth; downstream skills reference this section by heading).

| Lane | Phase 0.5 effect | Triggers (case-insensitive token scan) |
|---|---|---|
| `single-domain` | Spawn one leader (highest-relevance per Assessment Questions). On tie, fall back to **config declaration order** in this file's domain table (first match wins). | No `cross-domain` trigger AND no `procedural` trigger. |
| `cross-domain` | Spawn ≥2 leaders in parallel. If fewer than 2 match Assessment Questions, **fail-closed expand**: add the next-highest-relevance domain not yet in the set; tie-break by config declaration order. | `audit`, `review`, `security`, `compliance`, `migration`, `data`, `infra`, `regulated`, `payment`, `auth`, `cross-tenant`, `billing`, `gdpr`, `privacy`. |
| `procedural` | Spawn zero leaders. | `scaffold`, `lockfile`, `format-only`, `rename-only`, `dep-bump`, `version-bump`, `lint-fix` AND no `cross-domain` trigger. |

**Fail-closed default** when keyword inference returns no signal AND operator selects nothing resolvable: `cross-domain`. Cost asymmetry — false-positive fan-out is recoverable; missed user-impact gate is shipped breach.

**USER_BRAND_CRITICAL × lane composition.** When `USER_BRAND_CRITICAL=true` is set by Phase 0.1, the override at the top of this file (CPO + CLO + CTO mandatory triad) wins. Lane is then forced to `cross-domain`; the `cross-domain` fail-closed-expand clause is a no-op because the triad already provides ≥2 leaders. If relevance scoring would later drop one of the triad, the triad still fires (the override is unconditional); expansion only re-adds non-triad leaders.

**Carry-forward contract.** spec.md is the **canonical** lane source post-Phase-3.6; brainstorm-doc may carry `lane:` for provenance but is not load-bearing. `plan` reads from spec.md; `work` reads from spec.md. Operator-edited spec.md `lane:` between brainstorm and work is the operator's source of truth.

**Stability.** `lane:` is a frozen 3-value enum. Adding a fourth value requires parent-audit-spec amendment (`feat-claude-skills-audit/spec.md` FR4) and explicit follow-up brainstorm.
```

**Verification:** Test scaffold assertion #1 → GREEN.

**Commit:** `feat(brainstorm): canonical lane vocabulary in domain-config (GREEN: #1)`

### Phase 3 — brainstorm SKILL.md: Phase 0.4 + Phase 0.5 Step 0 + Phase 3.6 Prescription

All three edits in `plugins/soleur/skills/brainstorm/SKILL.md`, single commit (same-file atomic change).

**Edit A — Insert Phase 0.4** between Phase 0.1 (after its `**Why:**` paragraph) and Phase 0.25:

```markdown
### Phase 0.4: Lane Auto-Detect and Selection

Select an orchestration lane that describes the Phase 0.5 domain-leader breadth. Canonical vocabulary: `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` `## Lane Inference`. Written to spec.md frontmatter at Phase 3.6.

**Skip if** `USER_BRAND_CRITICAL=true` from Phase 0.1 — set `LANE=cross-domain` and proceed to Phase 0.25 without prompting. The framing question was already answered; avoid double-prompting.

**Otherwise:**

1. **Keyword scan** the feature description against the `## Lane Inference` table.

2. **Pipeline / headless mode detection.** If the parent invocation was `/soleur:one-shot`, `/soleur:go --headless`, or any non-interactive context (no TTY available, `HEADLESS_MODE=true`), set `LANE=<keyword-inference-result>` directly — fail-closed to `cross-domain` if no keyword matches. Skip the AskUserQuestion gate. Echo to the operator-facing terminal: `Phase 0.4: pipeline mode — lane=<value> (inferred)`. Continue.

3. **Interactive mode — AskUserQuestion.** Three presets (the runtime appends auto-Other automatically — do NOT include "Other" as a fourth preset per the 4-option cap):
   - Header: `"Lane"`
   - Question: `"Phase 0.5 domain-leader breadth. Inferred: <inferred-lane>."`
   - Options: the three lanes ordered with the inferred lane first labeled `(Recommended)`. Each option's `description` quotes the Phase 0.5 effect from the canonical table.

4. **Resolve response.** If the operator picks a preset, set `LANE=<picked>`. If the operator picks "Other" and the text resolves to a literal lane value, use it. **If "Other" does not resolve, fail-closed:** `LANE=cross-domain` AND echo to operator terminal: `Phase 0.4: free-text "<text>" did not resolve — fail-closed to cross-domain.` (Visible terminal echo, not just artifact note — per spec-flow G3.)

5. **Operator-override telemetry note (FR6).** When the chosen lane differs from the keyword-inferred default, add a one-line bullet to the brainstorm doc body's `## Lane` section: `Lane override: inferred=<inferred>, chosen=<chosen>.` Also echo to operator terminal so the override is visible immediately (not just on doc re-read).
```

**Edit B — Prepend Phase 0.5 Processing Instructions step 0.** Renumber existing 6 steps to 1–6; insert at head:

```markdown
0. **Lane-driven domain-set sizing (spec FR4).** Read `LANE` from Phase 0.4.
   - `LANE=procedural`: Skip Phase 0.5 entirely; echo `Phase 0.5: skipped (lane=procedural)` to the operator terminal so the bypass of 8 potential leaders is visible (per spec-flow G2); proceed to Phase 1.
   - `LANE=single-domain`: After step 1 selects the relevant-domain set, spawn only the single highest-relevance leader. On tie at highest score, fall back to **config declaration order** in `brainstorm-domain-config.md` domain table (first match wins). No AskUserQuestion at this point — tie-break is deterministic to support pipeline/headless mode.
   - `LANE=cross-domain`: After step 1, if fewer than 2 domains matched Assessment Questions, expand by adding the next-highest-relevance domain not yet in the set; tie-break by config declaration order; repeat until ≥2 leaders fire. Echo the expansion: `Phase 0.5: cross-domain expansion added <domain> (relevance tied; config-order tie-break)` to the operator terminal (per spec-flow G6).
   - The existing `USER_BRAND_CRITICAL=true` triad override (step 2) wins unconditionally — the triad is always mandatory when set; `LANE` shapes any additional leader inclusion only.
```

**Edit C — Phase 3.6 step 4 amendment.** In the existing step 4 (Generate spec.md using spec-templates), append:

```markdown
   - **spec.md frontmatter MUST include `lane: <value>`** where `<value>` is the resolved `LANE` from Phase 0.4. spec.md is the canonical post-Phase-3.6 lane source for downstream `plan` and `work` skills (per `## Lane Inference` carry-forward contract). spec.md frontmatter MUST also include `brand_survival_threshold:` matching the Phase 0.1 framing.
```

**Verification:** Test scaffold assertions #2, #3, #4 → GREEN.

**Commit:** `feat(brainstorm): Phase 0.4 + Phase 0.5 step 0 + Phase 3.6 lane prescription (GREEN: #2-#4)`

### Phase 4 — Downstream Consumers: plan SKILL.md + work SKILL.md

Two single-file edits committed together (same logical change — lane carry-forward propagation).

**Edit A — `plugins/soleur/skills/plan/SKILL.md` `## Save Tasks to Knowledge Base` section.** Before the "Save tasks.md to..." step, insert:

```markdown
**Carry forward `lane:` from spec.md.** Extract using the canonical gsub awk pattern (matches `skill-security-scan/scripts/run-scan.sh:34`):

```bash
LANE=$(awk '/^lane:/ { gsub(/^lane:[[:space:]]*"?|"?$/, ""); print; exit }' "knowledge-base/project/specs/feat-${branch_name}/spec.md")
```

Validate `LANE` against the 3-value enum (`single-domain`, `cross-domain`, `procedural`). If empty (legacy spec lacks `lane:`) or invalid (any other value), set `LANE=cross-domain` and echo to the operator terminal: `plan: spec lacks valid lane: — defaulted to cross-domain (fail-closed).` Add a one-line note to the plan body: `Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).` The plan file's YAML frontmatter MUST include `lane: <value>`.
```

**Edit B — `plugins/soleur/skills/work/SKILL.md` Phase 0.** After step 4 (Read tasks.md), insert step 4.5; modify step 5:

```markdown
4.5. Read `lane:` from spec.md if present. Guard file existence first:

```bash
spec_path="knowledge-base/project/specs/feat-${branch_name}/spec.md"
if [[ -f "$spec_path" ]]; then
  LANE=$(awk '/^lane:/ { gsub(/^lane:[[:space:]]*"?|"?$/, ""); print; exit }' "$spec_path")
  case "$LANE" in
    single-domain|cross-domain|procedural) ;;
    "") LANE="" ;;  # legacy spec; silent skip in announce
    *) echo "work: invalid lane value '$LANE' in spec; ignoring."; LANE="" ;;
  esac
fi
```

Lane is **non-binding in skill logic** — `work` code does not branch on `LANE`. Operators MAY use the announced lane as a heuristic when picking work Tier 0/A/B/C in Phase 2; binding behavior is deferred per Non-Goal #2.

5. Announce: `"Loaded constitution and tasks for \`feat-<name>\`"` — append `" (lane=<value>)"` when `LANE` is non-empty.
```

**Verification:** Test scaffold assertions #5, #6 → GREEN.

**Commit:** `feat(plan,work): propagate lane: from spec.md frontmatter (GREEN: #5, #6)`

### Phase 5 — Parent Audit Spec Amendment + Exit Gate

**Edit A — `knowledge-base/project/specs/feat-claude-skills-audit/spec.md` FR4.** Replace the four-lane block with:

```markdown
### FR4: Named orchestration lanes in brainstorm (single-axis)

Three lanes describe Phase 0.5 domain-leader breadth: `single-domain`, `cross-domain` (fail-closed default), `procedural`. Full vocabulary and carry-forward contract: `knowledge-base/project/specs/feat-orchestration-lanes/spec.md` and `knowledge-base/project/brainstorms/2026-05-12-orchestration-lanes-brainstorm.md`. (Amended 2026-05-12: collapsed from four lanes to three under single-axis lock.)
```

**Edit B — TR7 backwards-compatibility clause.** Append one sentence to the existing TR7 paragraph: `Named orchestration lanes auto-detect at brainstorm Phase 0.4 and fail closed to cross-domain on ambiguity; existing brainstorm invocations behave unchanged in shape (one new Phase 0.4 question prompt, skipped when USER_BRAND_CRITICAL=true).`

**Verification:** Test scaffold assertion #7 → GREEN. Then run the exit gate (no separate commit):

1. `bash plugins/soleur/test/lane-frontmatter.test.sh` exits 0.
2. `./node_modules/.bin/bun test plugins/soleur/test/components.test.ts` passes (baseline 1029/0; re-measure at /work start per learning `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`).
3. `bash scripts/test-all.sh` passes (orphan-suite discovery).
4. `./node_modules/.bin/bun test` (full suite) — no regression.

**Commit:** `feat(spec): amend feat-claude-skills-audit FR4/TR7 to single-axis (GREEN: #7)`

## Acceptance Criteria

- [ ] `brainstorm-domain-config.md` has `## Lane Inference` with the table, three lane tokens, USER_BRAND_CRITICAL composition order, carry-forward contract (spec.md canonical), and stability note.
- [ ] `brainstorm/SKILL.md` has Phase 0.4 with pipeline-mode fallback, interactive AskUserQuestion (3 presets + auto-Other), fail-closed "Other" resolution with **terminal echo**, override telemetry with **terminal echo**.
- [ ] `brainstorm/SKILL.md` Phase 0.5 Processing Instructions has step 0 with procedural-skip echo, single-domain config-order tie-break, cross-domain expansion echo.
- [ ] `brainstorm/SKILL.md` Phase 3.6 step 4 prescribes `lane:` in spec.md frontmatter.
- [ ] `plan/SKILL.md` extracts via the canonical gsub awk pattern, validates enum, fail-closes to `cross-domain` with terminal echo on missing/invalid.
- [ ] `work/SKILL.md` Phase 0 reads `lane:` (file-existence guarded), validates enum, includes ` (lane=<value>)` in announce when present.
- [ ] Parent audit spec FR4 amended to three-lane single-axis with link back; TR7 specifies fail-closed default.
- [ ] `plugins/soleur/test/lane-frontmatter.test.sh` exists; 7 assertions all GREEN; header comment acknowledges marker-existence limitation.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes.
- [ ] `bash scripts/test-all.sh` passes.
- [ ] PR body uses **`Closes #2721`** (no manual smoke run gating closure — the test scaffold + reviewer eyes + brainstorm self-test on the next brainstorm session are sufficient).

## Risks / Sharp Edges

**R1 — Phase order load-bearing.** Contract (Phase 2) before consumers (Phase 3+). Each phase is its own commit; the in-PR ordering is the implementation order for `/work`. Source: `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`.

**R2 — awk extraction robustness.** Use the canonical gsub pattern from `skill-security-scan/scripts/run-scan.sh:34`. Bare `awk '/^lane:/ {print $2}'` is brittle against quoted values and trailing whitespace (Kieran P1.2). Plan + work + test all use the gsub form.

**R3 — Marker tests do not prove semantic correctness.** Shell `grep -q` proves a string exists; it does not prove surrounding prose is correct. Multi-agent plan review (this skill) and per-session smoke runs on the next brainstorm are the load-bearing checks. The test file header comment acknowledges this honestly.

**R4 — State ownership.** spec.md is canonical post-Phase-3.6. brainstorm-doc may carry `lane:` for provenance but is not the source of truth; plan and work both read from spec.md. Operator-edited spec.md `lane:` between brainstorm and work is the operator's source of truth — by design.

**R5 — USER_BRAND_CRITICAL × lane composition order.** Triad first (unconditional CPO+CLO+CTO when tag set), then lane shapes any additional leader inclusion. Documented in `## Lane Inference` USER_BRAND_CRITICAL composition section. Architecture P1.

**R6 — "Non-binding in skill logic" honest framing.** Work code does NOT branch on `LANE`; operators MAY use the announced lane as a Tier 0/A/B/C heuristic. The architectural invariant is at the code level, not the operator-decision level — and that distinction is acceptable IF the plan stops pretending it protects against operator coupling. Reframed honestly in `work/SKILL.md` Phase 0 prose and Non-Goal #2.

**R7 — Plan-skill self-modification.** Phase 4 Edit A modifies `plan/SKILL.md` itself. Safe because the Skill tool reads SKILL.md fresh per invocation (no in-session cache across Skill calls), and the edit is additive — current `/work` execution path is unaffected.

**R8 — AskUserQuestion 4-option cap.** Three lane presets + runtime-appended auto-Other = 4. Do NOT include "Other" as a preset (Kieran P3.2 verified; precedent at `brainstorm/SKILL.md:70`).

**R9 — Schema-drift defenses.** Three-value stable enum + inline enum mention in each consumer SKILL.md + canonical section reference in `brainstorm-domain-config.md ## Lane Inference`. Future drift defense (CI hook) is intentionally deferred — see Non-Goals.

**R10 — Pipeline mode for Phase 0.4.** When `HEADLESS_MODE=true` or no TTY available, keyword inference runs verbatim with no AskUserQuestion gate; fail-closed to `cross-domain`. Echoed to operator terminal at run time so the silent default is visible (spec-flow G1).

## Non-Goals (Deferred — file ONE issue post-merge)

Two deferrals, both with concrete re-evaluation triggers. File one issue at PR-merge time labeled `deferred-scope-out`, milestone `Post-MVP / Later`:

1. **`--lane=X` shortcut on `/soleur:go` and `/soleur:brainstorm`** — pipeline-mode ergonomics; bypasses Phase 0.4 keyword inference entirely. Re-evaluate when keyword-inference miss rate (operator overrides at AskUserQuestion) is observed in ≥3 sessions or when one-shot operators report friction.
2. **`work` consuming `lane:` as a binding Tier 0/A/B/C hint** — experimental operator-loop coupling. Re-evaluate when operators report Tier-selection confusion under specific lane values; explicitly NOT a default to avoid coupling drift back to the two-axis preset rejected at brainstorm time.

**Explicitly dropped (no tracking issue, YAGNI):**

- Operator-override reason capture beyond `lane:` frontmatter — the inferred-vs-chosen note + git blame is sufficient.
- Expanded keyword-inference vocabulary beyond the minimum-viable set — expand when an actual miss is observed.
- Cross-skill lane-validation CI hook — solving an incident that hasn't happened.

## Telemetry

No new rule-fire telemetry. Brainstorm session already emitted `hr-new-skills-agents-or-user-facing applied` at brainstorm time. Compound Phase 1.5 step 8 emits its standard `cq-agents-md-why-single-line` byte-cap check. Threshold = `none`, no `hr-weigh-every-decision-against-target-user-impact` emit needed.

## Test Strategy

`plugins/soleur/test/*.test.sh` precedent (`notice-frontmatter.test.sh`, `lint-distribution-content.test.sh`). Bash + grep + the canonical gsub awk pattern. No new dependency. Test file header MUST acknowledge marker-existence limitation (R3).

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-12-feat-orchestration-lanes-plan.md

Context: branch feat-orchestration-lanes, worktree .worktrees/feat-orchestration-lanes/, PR #3625, issue #2721. Plan reviewed by 5 agents; cuts applied (9→5 phases, 10→7 assertions, 5→2 deferrals); brainstorm-doc frontmatter dropped (spec.md canonical); awk uses gsub precedent; pipeline-mode fallback + enum validation + terminal echoes for silent events added; Closes #2721 (no manual smoke gate). Implementation next.
```
