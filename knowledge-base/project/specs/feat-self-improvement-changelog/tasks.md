---
feature: feat-self-improvement-changelog
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-06-feat-self-improvement-changelog-operator-digest-plan.md
issue: "#6039"
---

# Tasks: enable self-improvement loop + operator-digest "got smarter" section

## Phase 0 — Verify preconditions (read-only)
- [x] 0.1 Confirm `promotion-config.yml` is currently `enabled: false` and #3594/#2720 are CLOSED (already verified 2026-07-06 — re-confirm at /work).
- [x] 0.2 Confirm the Anthropic DPA row is present at `compliance-posture.md:81`.

## Phase 1 — Stream A: enable the loop
- [x] 1.1 `promotion-config.yml`: `enabled: false` → `enabled: true`.
- [x] 1.2 `compliance-posture.md:120`: stale #3594 row `OPEN` → `CLOSED (#3596 — DPA row added; loop enable unblocked 2026-07-06)`.

## Phase 2 — Stream B: digest section (hardened v1, single source)
- [x] 2.1 `operator-digest/SKILL.md` intro (14-15): four→five sources/sections.
- [x] 2.2 Scope L1 (54): four→five named sources.
- [x] 2.3 Section heading (72): `## The four sections` → `## The five sections`.
- [x] 2.4 §1 data call: add `number,url` to `--json` (used only by §5 links; §1 prose rules unchanged).
- [x] 2.5 Insert `### 5. What got smarter this week` (reuse §1 data, client-side filter `labels[].name=="self-healing/auto" && mergedAt>=$SINCE`; render platform-level count + `details:` PR links; NO §5 gh call; NO `--search`; NEVER "your workspace").
- [x] 2.6 Deterministic fallback list (175-178): add Section 5 line.
- [x] 2.7 Output (205): four→five `##` sections.

## Phase 3 — Soak follow-through (Phase 2.9.1)
- [x] 3.1 Create `scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` (exit 0 before enable-commit+28d; non-zero after → surface DPIA re-eval).
- [x] 3.2 File `follow-through`-labelled tracker with `<!-- soleur:followthrough script=… earliest=<enable-commit-date+28d> -->`.
- [x] 3.3 Confirm `scheduled-followthrough-sweeper.yml` needs no new secrets (date-gated reminder).

## Phase 4 — Verify (pre-merge ACs)
- [x] 4.1 Run AC1–AC10 (see plan). Note AC5 asserts the guardrail line PRESENT (not absence of "your workspace"); AC4 asserts §5 has no `gh` call.
- [x] 4.2 `bun test plugins/soleur/test/components.test.ts` passes.

## Phase 5 — Post-merge (operator, automatable)
- [ ] 5.1 Trigger first run: `/soleur:trigger-cron cron/compound-promote.manual-trigger`; confirm `scheduled-compound-promote` Sentry monitor.
- [ ] 5.2 Read the next `Digest:` issue; confirm §5 renders honest-empty or ⚠️ (not blank).
