---
title: Tasks — harness-parity census (allowlist over the name index)
feature: feat-harness-parity-gate-8299
date: 2026-09-18
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-09-18-feat-harness-parity-census-plan.md
closes: 8299
---

# Tasks

Derived from **plan v3 (revised after the 7-agent panel)** — the section headed
`# PLAN v3 — allowlist predicate over the name index (plan of record; revised …)`. v1 and v2
in the same file are refuted record; the earlier BLOCKED banner on this file is lifted.

No commit may be RED: `lefthook.yml:311` runs the full battery on any staged `.ts`, and
`lefthook.yml:333` runs `bun test plugins/soleur/test/` (including `workflow-fidelity.test.ts`'s
doc pins) on any staged `.md`.

## Phase 1 — Classifier, fixtures, fidelity fold, preambles (commit 1, GREEN)

- [x] 1.1 Write the Phase 2 expected-verdict table from the plan **before** any classifier code
      (Guard Contract ordering).
- [x] 1.2 `plugins/soleur/lib/harness-parity.ts` (W1): `INDEX_GLOBS` / `POPULATION_GLOBS` as
      separate constants with `:(glob)` magic; `readIndex()` reading the registry via
      `discoverAgentPaths()` (67); `readPopulation()` with `cwd: PLUGIN_ROOT` + `--full-name`,
      `regionPolicy` from the matching glob, `EXCLUDED_BY_PATH` for `commands/help.md`;
      `classifyDoc` implementing R1–R9 (R6b gates bare agent leaves; R9 has the explicit path
      exclusion), BOUNDARY (incl. `#`), the path class, the token class, the trailing `[:_-]+`
      strip, the strict marker grammar; `census`; `fixDoc` (R1/R4/R8 sigil shapes only).
  - [x] 1.2.1 Rationale comment beside every BOUNDARY member and every rule.
  - [x] 1.2.2 Message: `path:line: <c+raw> — <attribution>; write <resolved id>`; leaf→id and
        stem→id resolution; brace/rename tail on unrecognised-sigil and bare-leaf rows.
- [x] 1.3 Fixtures under `plugins/soleur/test/fixtures/harness-parity/{skills,commands}/` (synthesized,
      never copied) and `plugins/soleur/test/harness-parity.test.ts` (W2) — fixture suite only; the
      cross-file sentinel lands in Phase 4.
- [x] 1.4 `plugins/soleur/scripts/harness-parity-census.ts --report | --fix` (W4); `--fix` idempotent.
- [x] 1.5 W10 fold: `pipelineInvocationSuffix(skill, harness)`; harness-agnostic lines of
      `workflowFidelityInstructions` through `formatSkillList`; `workflow-fidelity.test.ts:235` →
      `soleur:work`; new codex assertion (`invokeSkill("ship")` contains `$soleur:postmerge`, not
      `/postmerge`). Grok arm unchanged.
- [x] 1.6 W8: go.md `:147` sentence widened; same sentence in `routingInstructions("grok")`
      (`harness.ts:436-446`) — eval-only, not claimed as delivery.
- [x] 1.7 The 12 `LOCKED_PIPELINE_SKILLS` preambles rewritten to the plan's template (no `/plan`
      clause; the general `soleur:<name>` rule); `one-shot` aligned; Guard 1
      (`workflow-fidelity.test.ts:402-415`) gains the `names a skill` regex — same commit.
- [x] 1.8 **Local RED checkpoint (not committed):** `--report` prints `1029 sites in 62 docs` with
      the attribution split in the plan's §Measurements and 20 UNKNOWN-NS sites; save the
      UNKNOWN-NS set. Any other number → reconcile against the plan appendix `census4.py` before
      touching a doc.
- [x] 1.9 Commit 1 (`.ts` + the 12 `.md`): full battery GREEN.

## Phase 2 — Remediation (commits 2…n, `.md`-only)

- [x] 2.1 Commit 2 = `--fix` on the base and nothing else (AC3 reproducibility).
- [x] 2.2 Hand edits per doc group, `--report` after each: 488 bare leaves → registry ids;
      `@agent-<leaf>` → ids; grok stem in prose → id; `/soleur:<metavar>` → `soleur:<metavar>`.
- [x] 2.3 go.md: three `harness-forms` regions (Step 2.0 `:128-157`; the Devin/Grok lines of Step
      2.1; Sharp Edge `:207`); `:124` → "route through `soleur:one-shot`"; `:122` dual voice **stays**.
- [x] 2.4 W9 emit-time rendering sentence (anchored phrase `operator-typed form`) at every site
      `git grep -nlE 'Resume prompt|paste this|copy-paste'` returns, plus `gdpr-gate/SKILL.md:270`.
- [x] 2.5 False positives: `work/SKILL.md:1359` `"${work}"`; `rclone/SKILL.md:33` glob braced or reworded.
- [x] 2.6 `description:` substitutions in `drain-labeled-backlog` and `product-roadmap` (token-for-token; budget stays 2442).
- [x] 2.7 `--report` prints `0 sites`. UNKNOWN-NS is NOT diff-empty against 1.8 and the earlier
      `[x]` on this line was wrong: the set went 20 → 78. Every added member is a
      `soleur:<name>` / `soleur:<skill>` metavariable inside the 12 preamble blocks and the 10
      `operator-typed-render` blocks this PR adds, plus the prescribed `soleur:foo` in
      compound-capture — which is the AC2 carve-out. But "diffs empty" as written is false, so
      the claim is restated rather than left ticked against a check that did not hold.

## Phase 3 — Tree census (commit n+1, GREEN)

- [x] 3.1 `plugins/soleur/test/harness-parity-tree.test.ts` (W3): index invariant from the test's
      own literal pathspecs (`|AGENTS| === EXPECTED_SOLEUR_AGENT_COUNT`, leaf uniqueness and
      disjointness, `|CANONICAL_IDS|`); `census` over `readPopulation()`;
      `expect(noncanonical).toEqual([])` per doc; UNKNOWN-NS reported.
- [x] 3.2 Cross-file sentinel added to `harness-parity.test.ts` (asserts the tree file contains the literal).
- [x] 3.3 Guard 3 matrix N1–N13 + H1–H5 run against a pristine copy; observed messages recorded in the PR body.

## Phase 4 — Authoring surfaces, ADR, spec (commit n+2)

- [x] 4.1 W6 bullet in `skill-creator`, `compound-capture` Step 8 (+ Step 8.1 skill row → `soleur:foo`), `heal-skill`.
- [x] 4.2 W11: nine slash-form examples in `AGENTS.rules.md` canonicalised (`/loop` stays);
      `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` → `[OK]`.
- [x] 4.3 ADR-226 via `soleur:architecture` (rich shape; §Decision 1–6 per the plan); ordinal
      re-derived across every `origin/*` ref before merge; no C4 edit; `c4-count-parity.test.sh` 10/10.
- [x] 4.4 spec.md FR/TR re-based on v3 (no FR describes a marker census or a token set).
- [ ] 4.5 PR body: `Closes #8299`; `Ref #8317`, `Ref #8318`, `Ref #7453`, `Ref #8306`, `Ref #8307`, `Ref #8308`.

## Phase 5 — Verification (AC1–AC17 in the plan)

- [x] 5.1 AC6 spot-check greps; AC7/AC8 sibling suites; AC9 no `PLUGIN_ROOT:-` added.
- [x] 5.2 AC12 preambles and go.md `:122/:124` shape; AC14 rule-budget lint.
- [x] 5.3 AC15 amended: CI's required `test` context is the merge gate (ADR-183), not a local
      battery. Operator decision, recorded in spec.md AC15 with what was discharged locally
      instead and the measurement that the one CI-uncovered shard (`apps/web-platform/infra/`)
      is touched by 0 files in this diff.
