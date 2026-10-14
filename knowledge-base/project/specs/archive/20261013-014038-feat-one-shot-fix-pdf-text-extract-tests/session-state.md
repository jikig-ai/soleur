# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-pdf-text-extract-tests/knowledge-base/project/plans/2026-05-06-fix-pdf-text-extract-tests-fail-on-node-lt-22-plan.md
- Status: complete

### Errors
- GraphQL API rate limit exhausted at planning start (resets ~22:51 UTC). Worked around by using REST `gh api repos/...` and direct shell probes. Recorded in plan as a sharp edge for the Open Code-Review Overlap step (re-run at PR-review time).

### Decisions
- Root cause is Node version, not #3353 regression. `pdfjs-dist@5.4.296`'s legacy build calls `process.getBuiltinModule` at `pdf.mjs:14339` (and 5 other lines). That API was added in Node 22.0.0 and back-ported to Node 20.16.0 (PR `nodejs/node#52762`, 2024-07-24). Node 21 (LTS-skip line, EOL) never received it. Local Node 21.7.3 fails; CI ubuntu-latest's pre-installed Node 20.20.2 passes.
- Engines field must use the disjunction `>=20.16.0 || >=22.3.0` (mirroring pdfjs-dist verbatim), not a single floor — the disjunction precisely captures the back-port boundary and avoids spurious warnings on ubuntu-latest's Node 20.20.2.
- Three-layer fix: (1) `engines` in `apps/web-platform/package.json`, (2) `.nvmrc` at repo root containing `22`, (3) `Setup Node.js` step on the CI `test:` job using the literal pinned SHA `49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0`. Issue body claimed 4 failures; local repro shows 8 of 9 — plan AC asserts 9/9 and the count explicitly to guard drift.
- No domain leaders, no review/research subagents spawned. Pure infra/test-tooling change. Threshold = `none` with documented scope-out.
- Phase 4.5 (network-outage) skipped — no SSH/handshake/timeout keywords. Phase 4.6 (User-Brand Impact halt) PASS — section present, threshold valid, scope-out present for sensitive-path coverage.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Direct shell verification (no Task subagents): gh api (REST), git log/show, find/grep, direct probe of node_modules/pdfjs-dist@5.4.296, WebSearch (Node 20.16.0 release notes, mozilla/pdf.js#19857), local vitest run, ubuntu-latest runner-image readme via gh api.
