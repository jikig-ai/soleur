# Tasks: fix cloud sandbox gh auth missing for web-egress sessions

Plan: knowledge-base/project/plans/2026-11-09-fix-cloud-sandbox-gh-auth-missing-for-web-egress-sessions-plan.md
Issue: #12469 (Closes). Deferred: #12467, #12468, #12470.

## Phase 0: RED tests and behavioural probe
- 0.1 Add stub exports that throw (`buildGithubReadTools`, `listPullRequests`, `resolveCcGithubReadRegistration`) so new tests fail on assertions
- 0.2 Write T1 `github-read-tools-list.test.ts` (RED)
- 0.3 Write T2 characterization in `github-tools-untrusted.test.ts` (names/order snapshot, no redaction on legacy)
- 0.4 Write T3 `github-tools-read-builder.test.ts` (RED): six names, exclusions, schema keys, redact option, onError, 401/403 string, 404 hints
- 0.5 Write T4 `cc-github-read.test.ts` (RED), including T8 observability rows
- 0.6 Write T5/T6 in `cc-mcp-tier-allowlist.test.ts` and `cc-dispatcher-real-factory.test.ts` (new read-specific dark-path helper; entitled, degraded forwarder, no repo, support, not entitled)
- 0.7 Write T7 `cc-github-read-prompt.test.ts` (parsed-set equality, guardrail presence)
- 0.8 Write T9 deny-census characterization rows in `web-egress.test.ts`
- 0.9 Write T10 in `web-egress-toggle.test.tsx`; extend `runner-census.test.ts`; extend tool-tiers tests and `expected-tool-tiers.ts`
- 0.10 Behavioural probe (broker-mechanism-spike harness pattern): `printenv GH_TOKEN` entitled vs non-entitled; record result and SDK version in the plan Research Insights (settles H3)

## Phase 1: Readers
- 1.1 `listPullRequests` in `server/github-read-tools.ts` (metadata only, `has_more`, state closed set, SAFE_SEGMENT_RE, 0-results text, 64 KB cap)

## Phase 2: Builder, registrar, wiring
- 2.1 Export `buildGithubReadTools` from `server/github-tools.ts` (new tool, `onError`, `redact`, 401/403 string, 404 hints); compose `buildGithubTools` from it
- 2.2 Create `server/cc-github-read.ts` (registrar, reasons, FQN list constant, addendum, event)
- 2.3 Wire `cc-dispatcher.ts`: registrar outside the repo/installation block, tools merge, `platformToolNames`, `_ccRegisteredReadTools` cell (set/delete/clear beside the approval cell), advertise from the cell, addendum under `registered && webEgress`, connect-a-repository line
- 2.4 `server/tool-tiers.ts` entry for `github_list_pull_requests`

## Phase 3: Prompts
- 3.1 `ccGithubReadPromptAddendum()` text per plan Phase 3 (no edits to the exact-pinned directives)

## Phase 4: Disclosure copy
- 4.1 Toggle copy in `components/settings/web-egress-toggle.tsx` (two blocks) and the Scope Grants page paragraph

## Phase 5: Records
- 5.1 ADR-278 + ADR-311 amendment pair via `soleur:architecture` (include the ADR-309 push-gate residual sentence)
- 5.2 Read all three `.c4` files; extend the GitHub edge on the element that owns `cc-dispatcher`; run c4 tests incl. `c4-count-parity.test.sh`
- 5.3 DPIA screening addendum + Art. 30 PA-2 amendment with the CLO wording conditions

## Phase 6: Verify
- 6.1 `./node_modules/.bin/tsc --noEmit` and vitest for the named files (from `apps/web-platform`)
- 6.2 `technical-ruling-gate.sh --branch`; `git diff --quiet origin/main...HEAD -- docs/legal plugins/soleur/docs/pages/legal`
- 6.3 Open PR with `Closes #12469`, `## Changelog`, `semver:patch`
