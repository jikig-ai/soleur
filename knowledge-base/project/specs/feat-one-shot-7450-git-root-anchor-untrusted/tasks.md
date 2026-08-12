# Tasks — #7450 git-root fallback is not a trusted anchor

Derived from
[`knowledge-base/project/plans/2026-08-12-fix-git-root-fallback-untrusted-anchor-plan.md`](../../plans/2026-08-12-fix-git-root-fallback-untrusted-anchor-plan.md).

Phase order is dependency-directed. Phase 1 is a **halt gate**: a negative measurement stops
the plan rather than degrading it.

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Re-read all 5 sites; confirm the git-root form is still present
      (`hr-always-read-a-file-before-editing-it`)
- [ ] 0.2 Re-run Pattern A / B / C sweeps; confirm counts (6 / 45 / 2)
- [ ] 0.3 Re-read `apps/web-platform/server/safe-bash.ts`; confirm none of the 3 scripts is in
      `EXACT_LITERAL_SAFE_COMMANDS`, and confirm `SAFE_BASH_PATTERNS` has no `bash <path>` regex
- [ ] 0.4 Read all three `.c4` files in full; re-confirm the no-C4-impact conclusion
- [ ] 0.5 Confirm `plugins/soleur/skills/*/scripts/redact-*.sh` discovery yields the expected set
- [ ] 0.6 Determine whether `redact-sentinel.test.sh` is path-gated in `scripts/test-all.sh`;
      if so, widen the predicate to the full gate-site set in this PR

## Phase 1 — MEASURE (halt gate; precedes the amendment text)

- [ ] 1.1 Build a throwaway skill with a bare `${CLAUDE_PLUGIN_ROOT}` inside a ```bash fence
      that prints its own expansion
- [ ] 1.2 Invoke it; capture artifact + invocation + raw output verbatim
- [ ] 1.3 Record the positive/negative verdict in the PR body
- [ ] 1.4 **On negative: STOP and re-plan.** Do not proceed to Phase 5

## Phase 2 — RED: decoy positive control

- [ ] 2.1 Synthetic contributor tree: `mktemp -d` + `git init`
- [ ] 2.2 Plant the decoy `redact-sentinel.sh` (`exit 0`, mode 0755) at the payload-shaped path
- [ ] 2.3 Assert the decoy is a live hazard — exits 0 on a synthesized-secret file
- [ ] 2.4 Extract the anchor from the **committed** `incident/SKILL.md` (independent producer;
      do not hardcode)
- [ ] 2.5 With `CLAUDE_PLUGIN_ROOT` unset and CWD in the tree, expand and assert the resolved
      path is NOT under the tree
- [ ] 2.6 Run; **capture the RED output for the PR body** (`cq-write-failing-tests-before`)

## Phase 3 — RED: extend the anchor guard

- [ ] 3.1 Extend `plugin-root-anchoring.test.ts` file axis to all `skills/**/SKILL.md`
- [ ] 3.2 Derive the script axis: discovered `skills/*/scripts/redact-*.sh` + closed extras
      `{ token-efficiency-report.sh }`
- [ ] 3.3 Add the `scanned >= 5` anti-vacuity floor
- [ ] 3.4 Update the docstring's out-of-scope block; keep naming the ~105 sites deferred to #7453
- [ ] 3.5 Run; capture RED

## Phase 4 — GREEN: migrate, with guards

- [ ] 4.1 `incident/SKILL.md` — bare payload-relative operand + identity preflight (keep `[[ -r ]]`)
- [ ] 4.2 `legal-generate/SKILL.md` — same; byte-identical to 4.1
- [ ] 4.3 `linear-fetch/SKILL.md` — operand + identity preflight + **the missing readability
      guard and exit-code dispatch**
- [ ] 4.4 `compound/SKILL.md` — operand only; **do not touch** `TE_REPORT_REPO_ROOT`
- [ ] 4.5 Correct the git-root-fallback prose in `incident` + `legal-generate`
- [ ] 4.6 Correct the falsified rationale comment in `preflight/SKILL.md`
      (**comment only — operands stay**, DC-1)
- [ ] 4.7 Retarget + strengthen Test 18 (coupling, identity preflight, corpus-wide negative)
- [ ] 4.8 Verify no `${CLAUDE_PLUGIN_ROOT}/plugins/soleur` doubled segment anywhere
- [ ] 4.9 Both suites green

## Phase 5 — ADRs

- [ ] 5.1 Amend ADR-179 as `## Amendment — 2026-08-12 (#7450): …`; keep `status: accepted`
- [ ] 5.2 Include: scope extension; no-`safe-bash`-change finding; fail-closed asymmetry;
      Phase 1 measurement; code-root vs data-root; Pattern C residual
- [ ] 5.3 Edit §R5 **in place** — record closure and correct its "all four are secret gates" wording
- [ ] 5.4 Correct ADR-093 `## Amendments` — the `git-root = the operator's own checkout`
      premise; keep the #6223 export-invariant reasoning intact
- [ ] 5.5 Confirm **no new ADR file** is added

## Phase 6 — Downstream comments (no code)

- [ ] 6.1 Comment on **#7453**: ratified anchor; **ordinal is ADR-179, not ADR-177**; this
      subset needed no `safe-bash.ts` change; the 2 Pattern C preflight sites with severity flag
- [ ] 6.2 Comment on **#6222**: remedy falsified; `${CLAUDE_PLUGIN_ROOT}` cannot anchor
      repo-root `scripts/` members; correct instruments are relocate-into-payload (ADR-179
      decision 3) or monorepo-sentinel gate (decisions 4-6); cite §R4's re-derived table; note
      the `domain-model-drift.sh` sites are already remediated
- [ ] 6.3 Verify both issues remain **OPEN**

## Phase 7 — Exit

- [ ] 7.1 `bash scripts/test-all.sh` green
- [ ] 7.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts`
- [ ] 7.3 Guard 1 mutation matrix M1-M6 executed; 6-row table in PR body
- [ ] 7.4 Guard 2 mutation matrix M7-M10 executed; 4-row table in PR body
- [ ] 7.5 PR body: `Closes #7450`; AC #3 disposition; DC-1/DC-2 rendered
- [ ] 7.6 `/soleur:review` (includes `user-impact-reviewer` at the single-user-incident threshold)
- [ ] 7.7 `/soleur:ship`
