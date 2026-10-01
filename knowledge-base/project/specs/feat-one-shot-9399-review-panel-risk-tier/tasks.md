---
feature: feat-one-shot-9399-review-panel-risk-tier
lane: cross-domain
plan: knowledge-base/project/plans/2026-10-01-chore-review-panel-risk-tier-targeted-seats-plan.md
created: 2026-10-01
---

# Tasks — Scale review panel to risk tier; targeted seats for fix commits

Derived from the plan's Implementation Phases. Byte-ceiling ledger (merge-base `c60dc74`):
`plan/SKILL.md` +14 B, `review/SKILL.md` +184 B, `one-shot/SKILL.md` +856 B — normative prose lives
in `references/` files; SKILL.md edits are pointers only.

## Phase 0 — Preconditions

- [ ] **0.1** Re-probe ADR-265 availability across all `origin/*` refs (sibling branches may claim
      it mid-session; renumber sweeps `knowledge-base/project/{plans,specs}/feat-one-shot-9399-*`).
- [ ] **0.2** Re-measure SKILL.md headroom: `python3 scripts/lint-skill-body-budget.py --base
      origin/main` and `wc -c` on the three edited skills; record deltas before writing prose.

## Phase 1 — Review-skill contract

- [ ] **1.1** Create `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` carrying:
      tier resolution order (PR body → linked plan → undeclared→`none`), `SENSITIVE_PATH_RE`
      fail-closed clamp, never-scale-below-declared + `mismatch` note, the seat-scaling table,
      announce/`### Review Agents Used` formats, fix-round contract (`PANEL_SHA`, cap-2-then-
      escalate, one verification pass, `--fix-round`), dedup ledger spec, `aggregate pattern`
      escalation semantics, `none`-tier trigger-gating predicates (defined as "seat fires iff the
      diff touches a path its script map arm covers").
- [ ] **1.2** Edit `plugins/soleur/skills/review/SKILL.md` within ≤ +184 B net: `Tier:`/`source:`
      announce tokens, pointer at classification gate, `userImpactThreshold` bullet extended to
      `aggregate pattern`, pointer under §5 (fix round + dedup ledger), `Risk tier` line in the
      `### Review Agents Used` template. Reclaim overage by relocating detail, never by dropping
      conditions.
- [ ] **1.3** Edit `plugins/soleur/skills/review/workflows/review.workflow.js`:
      `CLASSIFY_SCHEMA.triggers.userImpactThreshold` → `brandThreshold` enum; `conditionalDimensions`
      fires `user-impact` on `single-user incident`/`aggregate pattern`; `SKEPTICS` =
      `deepReview || brandThreshold === 'aggregate pattern' ? 3 : 1`; `log()` gains tier + seat
      counts; `report` gains `riskTier`, `seatsSpawned`, `mergedGroups`.
- [ ] **1.4** Update `plugins/soleur/skills/review/workflows/README.md` divergence note if it
      documents the class-only contract.

## Phase 2 — Machinery (RED first, `cq-write-failing-tests-before`)

- [ ] **2.1** Write `plugins/soleur/skills/review/test/fix-round-seats.test.sh` covering the
      Guard-1 mutation matrix (migrations→data-integrity+data-migration; `*.test.*`→test-design;
      floor emit on unmatched `.ts`; two-member union; seat-registry spelling; `--finding-seats`
      union). Auto-registers via `plugins/soleur/skills/*/test/*.test.sh` in `scripts/test-all.sh`.
- [ ] **2.2** Create `plugins/soleur/skills/review/scripts/fix-round-seats.sh` (POSIX-portable;
      `--files` + `--finding-seats`; deduped floor-ordered output; exit 2 on usage error).
- [ ] **2.3** Add rows to `plugins/soleur/skills/review/test/emit-review-trailer.test.sh` for the
      Guard-2 matrix (each enum value parses; `--risk-tier bogus` exits 2; field inside the trailers
      paragraph; flag absent → field absent).
- [ ] **2.4** Edit `plugins/soleur/skills/review/scripts/emit-review-trailer.sh`: `--risk-tier`
      flag, enum validation, `Reviewed-Risk-Tier:` trailer emit, usage text.
- [ ] **2.5** Create `plugins/soleur/test/review-tier-parity.test.ts` (Guard 3: reference table ↔
      workflow gating ↔ script map arms).

## Phase 3 — Plan-side + pipeline wiring

- [ ] **3.1** Edit `plugins/soleur/skills/plan/references/plan-issue-templates.md`: `**Threshold
      decision (challengeable):** <value> — rationale: … — review-panel effect: …` in all three
      `## User-Brand Impact` blocks + ADR-084 routing comment (attached → post-plan-review gate;
      headless → `specs/<branch>/decision-challenges.md` when declared value ≥ `single-user
      incident`; plan-review disputes classify User-Challenge).
- [ ] **3.2** `plugins/soleur/skills/plan/SKILL.md` Phase 2.6 Step 1, ≤ +14 B net: extend the
      `(template from ... plan-issue-templates.md)` reference to name the fourth required line; if
      no compliant trim exists, leave SKILL.md untouched (contract still binds via the mandated
      template read) and note the decision in the PR body.
- [ ] **3.3** `plugins/soleur/skills/one-shot/SKILL.md` Step 5: run `soleur:review <PR>
      --fix-round` after resolver-agent commits, before Step 5.5 (~180 B of 856 B).

## Phase 4 — Decision record + verification

- [ ] **4.1** Create `knowledge-base/engineering/architecture/decisions/ADR-265-*.md` via
      `soleur:architecture` — decision, alternatives (prose-mapping / full re-panel / no fix review
      / new vocabulary / resolve-pr-parallel → #9412), `status: accepted`.
- [ ] **4.2** Edit `knowledge-base/engineering/architecture/diagrams/model.c4`:
      `platform.plugin.review` description no longer claims a fixed 8-seat panel.
- [ ] **4.3** Run `bun test plugins/soleur/test/` (parity + pins suites), the C4 tests
      (`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`), then
      `TEST_GROUP=affected bash scripts/test-all.sh`.
- [ ] **4.4** Self-review this branch's diff with the new machinery where feasible; emit
      `emit-review-trailer.sh --risk-tier none` as the dogfood.

## Non-Goals reminder

No consumer for `Reviewed-Risk-Tier:` (ADR-127 pattern); no resolve-pr-parallel wiring (#9412); no
model-tier pins (ADR-053/110); `deep review`/`full review` override unchanged.
