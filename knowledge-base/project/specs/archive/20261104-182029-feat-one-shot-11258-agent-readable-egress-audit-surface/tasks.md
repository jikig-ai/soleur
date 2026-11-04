# Tasks: agent-readable surface over the egress audit summary (scope narrowed to a record plus an absence pin)

Plan: `knowledge-base/project/plans/2026-11-04-feat-agent-readable-egress-audit-surface-plan.md`
Scope (binding CTO ruling B, 2026-11-04): ADR-288 amendment plus one default-suite absence-pin test. No agent tool, RPC, grant, migration, route or MCP/platform tool. `Ref #11258` / `Ref #9601` only.

## Phase 0: Re-verify at work start

- [x] 0.1 Merge `origin/main`; confirm #3722 and #11258 are still open (a fired trigger means STOP and re-rule via the CTO agent)
- [x] 0.2 On a clean tree, cross-check the test's planned file walk against `git ls-files` (973 `.ts`/`.tsx` files on 2026-11-04, plus `.mjs`) and re-measure: three name files, two loader importers, agent-surface population (47) with zero `egress[-_]?audit` matches
- [x] 0.3 Run the new matchers against the unmutated tree before writing any mutant

## Phase 1: The absence-pin test (written first; RED evidence comes from the mutation battery)

- [x] 1.1 Create `apps/web-platform/test/egress-audit-agent-surface-absence.test.ts` with the header (property, residuals, pointer to the ADR-288 amendment)
  - [x] 1.1.1 Arm (a): files containing the RPC names equal `EXPECTED_NAME_FILES` (set equality)
  - [x] 1.1.2 Arm (b): files matching one regex over quoted import specifiers ending in `egress-audit-read` (`from`, `import(`, `require(`) equal `EXPECTED_LOADER_IMPORTERS`
  - [x] 1.1.3 Arm (c): structurally derived agent-surface population (filename arm plus marker arm) has no `/egress[-_]?audit/i` match
  - [x] 1.1.4 Arm (d): `TOOL_TIER_MAP` keys and `CC_REGISTERED_PLATFORM_TOOL_NAMES` have no match (no assertion over `readCcMcpAllowlist`)
  - [x] 1.1.5 Arm (e): anti-vacuity (hard-coded root-to-anchor map independent of `SCAN_ROOTS`, count floor of at most 90% of the measured figure, both population arms non-empty, every expected member exists, synthetic must-match and must-not-match strings)
  - [x] 1.1.6 The test reads nothing outside `apps/web-platform` (no `knowledge-base/` read), so it stays in the `unit` project; scan `.ts`, `.tsx` and `.mjs`
- [x] 1.2 Do not name helpers `*Window`, `*Region` or `*Section`; run `python3 scripts/lint-window-closure-assertion.py --allowlist scripts/lint-window-closure-assertion.allowlist.txt`
- [x] 1.3 Run the test on the unmutated tree: arms (a)-(e) green; record the run before any mutant

## Phase 2: ADR-288 amendment

- [x] 2.1 Append the amendment from plan Appendix A to `knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md` (status stays `adopting`)
- [x] 2.2 Add the superseded marker under residual 5; leave its original text unchanged
- [x] 2.3 Scrub and wording greps on added lines (plan AC5 and AC11): no enablement reference, no banned wording

## Phase 3: Verification (targeted, not the full affected battery)

- [x] 3.1 Run the 9 mutation rows and 3 harness rows from the plan's Guard Contract against the committed tree, one at a time, restoring after each (no `git stash`); record results for the PR body
- [x] 3.2 `cd apps/web-platform && npx vitest run test/egress-audit-agent-surface-absence.test.ts test/cc-mcp-tier-allowlist.test.ts test/repo-wide-containment.test.ts`
- [x] 3.3 `bash scripts/markdown-lint.sh --repo-sweep`; `python3 scripts/lint-guard-contract.py <plan>`; `bash plugins/soleur/test/c4-count-parity.test.sh`
- [x] 3.4 `git diff --name-only origin/main...HEAD` is limited to the ADR, the new test and `knowledge-base/project/{plans,specs}/` (plus pipeline-written files, listed in the PR body); `server/dsar-export-allowlist.ts` untouched

## Phase 4: Ship

- [x] 4.1 Commit with trailers `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01GFjtgCLNJLuLXoUHkQcjhw`
- [ ] 4.2 PR body: `Ref #11258`, `Ref #9601`, rendered decision-challenges table, mutation record, `Net issue flow: 0 (no issue filed)`; no close keyword; ends with the generation line
- [ ] 4.3 After merge, one comment on #11258 restating the three triggers and linking the amendment (no held reference; body not edited); #11258 stays open
