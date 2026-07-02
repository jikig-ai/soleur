---
feature: domain-model-register-gates
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-02-feat-domain-model-register-gates-plan.md
issue: 5871
---

# Tasks: Mechanical enforcement gates for the domain-model register (#5871)

Phase order is load-bearing (analyzer contract before its consumers). One PR (#5895); atomic.

## Phase 1 — Analyzer anchor fix (enforce ADR-076 item 3) — commit first
- [ ] 1.1 `scripts/lib/domain-model-lib.sh`: in `name_after()` bare-identifier branch (line 63), add
      `sub(/^public\./, "", tok)` before `return tok`. Strips the Postgres default schema only; keeps
      `storage.`/`auth.`; leaves the quoted branch (line 62) untouched. Fixes both the table token and
      the `t "_pkey"`/`t "_check"` derived object names, and function-guard tokens.
- [ ] 1.2 `scripts/domain-model-drift.test.sh`: add an additive test — a fixture with
      `CREATE POLICY p ON public.foo …` + `ALTER TABLE public.foo …` asserting the emitted anchor is
      `… › foo.<object>` (no `public.`, no double-dot); AND a `storage.objects` fixture asserting the
      `storage.` schema is preserved.
- [ ] 1.3 Run `bash scripts/domain-model-drift.test.sh` — all pass. (AC1)
- [ ] 1.4 Verify `… extract | jq -r '.facts[].anchor' | grep -c 'public\.'` == 0. (AC2)

## Phase 2 — Blocking ship gate: preflight `Check 11`
- [ ] 2.1 `plugins/soleur/skills/preflight/SKILL.md`: add `### Check 11: Domain-Model Register Drift`
      after Check 10.
  - [ ] 2.1a Fast-path SKIP predicate against `"$PREFLIGHT_TMP/preflight-diff-files.txt"`: SKIP unless
        the path-set matches (explicit literals) `apps/web-platform/supabase/migrations/.*\.sql$` OR
        `apps/web-platform/server/workspace-resolver\.ts$` OR
        `knowledge-base/engineering/architecture/domain-model\.md$`.
  - [ ] 2.1b Fail-safe: if the diff-cache file is missing/empty, recompute inline
        (`git diff --name-only origin/main...HEAD`); if still empty, **run** (never SKIP).
  - [ ] 2.1c Run `drift` → `"$PREFLIGHT_TMP/register-drift.txt"`, capture `rc`.
  - [ ] 2.1d Parse stale count line-anchored:
        `stale=$(grep -oE '^## Stale register citations \([0-9]+\)' … | head -1 | grep -oE '[0-9]+')`.
  - [ ] 2.1e Verdict (blocking-direct): rc==0→PASS; stale>0→FAIL (actionable message: fix cited row /
        run `/soleur:sync domain-model` / unbacktick filename citations per the parser-FP learning);
        rc==2→FAIL (gate-can't-run message); rc==3→FAIL (secret-refuse message naming newest migrations).
  - [ ] 2.1f Note in the body: "Undocumented source facts (M)" is intentionally NOT a FAIL input.
  - [ ] 2.1g Add the SKIP predicate row to the Fast-path SKIP overview table (line 44).
  - [ ] 2.1h Note: Check 11 RUNS pre-PR by design (diff-set is PR-independent) — do not SKIP-on-no-PR.
- [ ] 2.2 Confirm NO ship-skill edit needed (ship Phase 5.4 already halts on preflight FAIL).
- [ ] 2.3 Verify AC3 (SKIP on docs-only / RUN on business-rule surface / RUN on empty cache) and AC4
      (keys on stale, not exit code; exit-2/3 FAIL) against synthesized `preflight-diff-files.txt` +
      synthesized drift reports.

## Phase 3 — Advisory review note
- [ ] 3.1 `plugins/soleur/skills/review/SKILL.md` Conditional-Agents block (after gdpr-gate, ~line 267):
      add a conditional gate, same diff predicate as Check 11, that runs `drift` and emits ONE
      informational review-summary line: "domain-model register: N stale citation(s), M undocumented
      table(s) — see `/soleur:sync domain-model`". No blocking, no coordination logic.

## Phase 4 — Contract prose + ADR/C4
- [ ] 4.1 `knowledge-base/engineering/architecture/domain-model.md`: flip the maintenance-contract
      "Fast-follow (not yet mechanically gated)…" line to "Wired: … preflight Check 11 (stale-citation
      ship block, diff-scoped); advisory review note. (Plan-time flagging not built — no diff at plan
      time; #5871.)"
- [ ] 4.2 Amend `ADR-076` with a `## Enforcement gates (2026-07-02, #5871)` section: gate on
      stale-citation sub-count (not raw exit / undocumented-facts); single blocking chokepoint at
      preflight; review advisory; plan-flag not built; blocking-direct; the `public.` strip enforces
      item 3. C4: no impact (cite the external-actor/system/container/access-relationship enumeration
      from the plan).
- [ ] 4.3 AC5: prose no longer says "not yet mechanically gated"; ADR-076 amendment present.

## Exit
- [ ] Run the full test suite + preflight (Check 11 should PASS on this branch: stale=0; register
      touched by 4.1 introduces no staleness).
- [ ] Verify all ACs (AC1–AC5) pass.
