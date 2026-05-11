---
title: "Tasks: PDF chapter-chunking Phase 3.B + S1/S2 spikes bundle"
plan: knowledge-base/project/plans/2026-05-11-feat-pdf-chapter-chunking-bundle-plan.md
spec: knowledge-base/project/specs/feat-pdf-chapter-chunking-bundle/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-11-pdf-chapter-chunking-bundle-brainstorm.md
issues: [3472, 3473, 3474]
branch: feat-pdf-chapter-chunking-bundle
draft_pr: 3550
brand_survival_threshold: single-user incident
---

# Tasks: PDF Chapter-Chunking Bundle

Derived from the finalized plan (post plan-review fixes). Phases are sequential; tasks within a phase may parallelize where noted. Single-commit invariant (TR4 → AC #18) governs Phase 3 — directive revival and dispatch wiring land in the same commit per runner.

## Phase 0 — Worktree preflight

- [ ] **0.1** From `.worktrees/feat-pdf-chapter-chunking-bundle/`: `git fetch origin main` and confirm no drift.
- [ ] **0.2** `bun install` to refresh deps.
- [ ] **0.3** Run the test suite via `package.json scripts.test` (`./node_modules/.bin/vitest run`); record the baseline passing count.
- [ ] **0.4** `doppler secrets get ANTHROPIC_API_KEY -p soleur -c dev --plain | wc -c` returns non-zero. **Do NOT print the key.**

## Phase 1 — Spike S1: `cache_control` forwarding (#3473)

- [ ] **1.1** Run `doppler run -p soleur -c dev -- ./node_modules/.bin/tsx apps/web-platform/scripts/spike/cache-control-forwarding.ts`. Capture stdout to `/tmp/spike-s1-output.txt`.
- [ ] **1.2** Parse `cache_creation_input_tokens` (run 1) and `cache_read_input_tokens` (run 2). Determine verdict: GREEN-S1 (both > 0) or RED-S1.
- [ ] **1.3** Update PR #3550 body: prepend `## Spike S1 — cache_control forwarding` section with the verdict line and verbatim stdout.
- [ ] **1.4** Append `gh pr comment 3550 --body "## Spike S1 — cache_control forwarding\n\n**Verdict:** <GREEN-S1|RED-S1>\n\n**Run at:** $(date -u +%Y-%m-%dT%H:%M:%SZ)\n\n<verbatim output>"`. This is the immutable per-run audit trail for AC #17.
- [ ] **1.5** Record outcome in implementer scratchpad so Phase 3 picks the matching dispatch shape (GREEN: attach `cache_control: { type: "ephemeral" }`; RED: omit).

## Phase 2 — Spike S2: pdfjs `getOutline()` coverage (#3474)

### 2a — Fixture rework (KD-2 → AC #16)

- [ ] **2.1** Create `apps/web-platform/scripts/spike/generate-outline-fixture.ts` using `pdfkit`. Constraints: ≥10 top-level outline entries (depth ≥ 1) that resolve via `getDestination` → `getPageIndex`; total pages 200–500; output `.gitignore`d; script prints SHA-256 of generated file.
- [ ] **2.2** Run the generator; verify SHA-256 + page count are within the 200–500 band.
- [ ] **2.3** Source no-outline fixture: archive.org pre-1929 US public-domain scan OR CC0 source. Compute SHA-256. Prefer a Wayback Machine snapshot URL for immutability per Kieran P2-B.
- [ ] **2.4** Edit `apps/web-platform/scripts/spike/pdf-outline-fixtures.json`: remove all Manning/O'Reilly references; point outline-bearing entry at `generate-outline-fixture.ts`; point no-outline entry at the archive.org / Wayback URL + SHA-256.

### 2b — Spike execution

- [ ] **2.5** Run `doppler run -p soleur -c dev -- ./node_modules/.bin/tsx apps/web-platform/scripts/spike/pdf-outline-coverage.ts`. Capture the per-fixture table.
- [ ] **2.6** Update PR #3550 body: append `## Spike S2 — outline coverage` section with the verbatim table and per-fixture verdict (`usable` / `fall-through`).
- [ ] **2.7** **Gate:** if both fixtures match expectation, proceed to Phase 3. If either fixture diverges, **STOP**: file an issue referencing #3450 with the failed coverage data and defer the rest of the bundle.

## Phase 3 — Single-commit directive revival + dispatch wiring (TR4 → AC #18)

Implementation order matters within this phase: write RED tests before GREEN code per `cq-write-failing-tests-before`. Stage every edit and commit Concierge + Leader changes in the **same git commit** (Phase 3.10 verifies).

### 3.1 — Dependency + KD-6 reachability pre-flight

- [ ] **3.1** Re-add `@anthropic-ai/sdk@^0.92.0` to `apps/web-platform/devDependencies`. Regenerate `bun.lock` AND `package-lock.json` per `cq-before-pushing-package-json-changes`. Confirm import remains `import type { MessageParam }` only.
- [ ] **3.2** **KD-6 reachability pre-flight grep** (per §Risks): `rg "documentExtractMeta" apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/agent-runner.ts | head` — verify whether any path passes >1 `documentExtractMeta` per turn. Record result in implementer scratchpad: if confirmed unreachable, tests 10–11 are forward-looking guards + file a tracking issue for KD-6 reactivation when resolver multi-PDF support lands; if reachable, tests verify a live failure mode.

### 3.2 — RED tests (write before implementation)

- [ ] **3.3** Create `apps/web-platform/test/soleur-go-runner-chapter-chunked.test.ts` with cases 1–9 per plan §3.5 (case 8 has sub-parts 8a + 8b; case 2 covers system-prompt byte-stability across within-chapter turns).
- [ ] **3.4** Create `apps/web-platform/test/agent-runner-chapter-chunked.test.ts` — mirror of 1–9 + leader-specific NO-ASK assertion (assert SDK Read tool NOT invoked on the chapter-chunked PDF).
- [ ] **3.5** Create (or extend `pdf-chapter-router.test.ts` with) `apps/web-platform/test/pdf-chapter-router-cross-document.test.ts` — KD-6 cases 10 (ambiguous-which-document) + 11 (prefix carries document title).
- [ ] **3.6** Edit `apps/web-platform/test/soleur-go-runner-chapter-chunked-prompt.test.ts` — flip 4 cases from "directive REVERTED" to "directive PRESENT".
- [ ] **3.7** Edit `apps/web-platform/test/agent-runner-chapter-chunked-prompt.test.ts` — symmetric flip (2 cases).
- [ ] **3.8** Confirm new tests FAIL on current main (`./node_modules/.bin/vitest run <new-test-files>` should be RED at this checkpoint).

### 3.3 — Concierge implementation (`soleur-go-runner.ts`)

- [ ] **3.9** In `buildSoleurGoSystemPrompt` lines 1000–1016 (Phase 3.A revert site): replace `too_many_pages` fall-through with the chapter-chunked directive (inline template, no factory). Include: `the user is currently viewing: ${sanitizedPath}`, TOC list (sanitized titles + 1-based page ranges), content-block contract, NO-ASK clause, and the `[Answering from chapter <N>: "<title>"]` prefix instruction (multi-PDF variant: `[Answering from "<book title>", chapter <N>: "<title>"]`).
- [ ] **3.10** Extend `ActiveQuery` state with `chapterChunkedContext`, `activeChapter`, `multiPdfChapterChunked`, `chapterExtractionFailures`. `chapterChunkedContext.fullPath` and `documentTitle` are sourced from `args.contextPath` at session creation (NOT from `documentExtractMeta` — that field doesn't exist).
- [ ] **3.11** Add the dispatch-time chapter routing block in `dispatch()` before `pushUserMessage`: KD-5 stale-context check (path mismatch + chapters-empty branches; clear-and-proceed-same-turn semantics), `selectChapter` invocation, per-`kind` branches (selected | ambiguous | ambiguous-which-document | cost-cap-hit | router-error). Document the `kind: "ambiguous-which-document"` discriminator widening (per `cq-union-widening-grep-three-patterns`: grep for `_exhaustive: never` rails, `.kind ===` if-ladders, `?.kind ===` optional-chained; add `: never` rails at every consumer site).
- [ ] **3.12** `readFile` step: wrap in try/catch. On ENOENT, clear context + refund + emit deletion copy + mirror to Sentry via `reportSilentFallback({ feature: "soleur-go-runner", op: "chapter-readfile-enoent" })`.
- [ ] **3.13** Slice-failure path: emit copy + refund + Sentry mirror (`op: "chapter-slice-failure"`) + increment `chapterExtractionFailures`; on counter ≥ 3 surface cap and do NOT refund.
- [ ] **3.14** Implement `pushStructuredUserMessage(state, content)` as a local non-exported function in `soleur-go-runner.ts` accepting `MessageParam`-shaped content. S1-gated attachment: GREEN attaches `cache_control: { type: "ephemeral" }`; RED omits.
- [ ] **3.15** `handleAssistantMessage`: prepend chapter prefix when `activeChapter.prefixEmitted === false`; multi-PDF variant carries document title.
- [ ] **3.16** `handleResultMessage`: clear `activeChapter`; preserve `chapterChunkedContext`.

### 3.4 — Leader implementation (`agent-runner.ts`)

- [ ] **3.17** Symmetric directive revival at lines 1002–1014 (revert site) with leader-specific NO-ASK clause for the SDK Read tool.
- [ ] **3.18** Symmetric dispatch-time chapter routing using `pdf-chapter-router` and a local sibling of `pushStructuredUserMessage` (do NOT extract a shared helper per §3.4 of the plan).
- [ ] **3.19** Same KD-3 / KD-5 / KD-6 / KD-7 propagation as Concierge; same ENOENT + slice-failure + Sentry-mirror behavior.

### 3.5 — Single-commit invariant verification

- [ ] **3.20** Stage all changes from 3.1–3.19. Create ONE git commit per pairing wave: directive + dispatch in both runners must land together. Use `git add -p` to isolate paired hunks if needed.
- [ ] **3.21** Run the per-commit walking shell script from plan §3.6 (NOT `git log --oneline -- A B`). Exit code must be 0. If non-zero, `git rebase -i` or `git commit --amend` to fold.
- [ ] **3.22** Optionally wire the script as a `pre-push` hook on the worktree for the branch lifetime (delete on merge).

### 3.6 — Local verification

- [ ] **3.23** `./node_modules/.bin/vitest run` — full suite green; all new tests pass.
- [ ] **3.24** `./node_modules/.bin/tsc --noEmit` — green.

## Phase 4 — PR body composition + ready-for-review

- [ ] **4.1** Compose PR #3550 body with sections in this order: `## Spike S1`, `## Spike S2`, `## Implementation`, `## User-Brand Impact` (link to plan + brainstorm), `### Scope-outs acknowledged` (carry-forward + bundle disposition table), `## Closes` (one-per-line: `Closes #3472`, `Closes #3473`, `Closes #3474`), `Ref` (e.g., `Ref #3436 #3440 #3450 #3454 #3343`).
- [ ] **4.2** Confirm KD-6 reachability scratchpad note is reflected in the PR body's Implementation section (or §Risks).
- [ ] **4.3** Resolve Open Question 2 (cross-document + "Source PDF changed" copy): implementer proposes final wording in PR body; tag user for sign-off BEFORE marking ready.
- [ ] **4.4** Run `git push -u origin feat-pdf-chapter-chunking-bundle` per `rf-before-spawning-review-agents-push-the`.
- [ ] **4.5** Mark PR ready: `gh pr ready 3550`.
- [ ] **4.6** Invoke `/soleur:review` (5-agent panel per `single-user incident` threshold). `user-impact-reviewer` is included per `hr-weigh-every-decision-against-target-user-impact`.

## Phase 5 — Merge

- [ ] **5.1** After review-finding fix-inline (default per `rf-review-finding-default-fix-inline`) and any green CI: `gh pr merge 3550 --squash --auto` per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.
- [ ] **5.2** Poll `gh pr view 3550 --json state --jq .state` until `MERGED`.
- [ ] **5.3** Verify post-merge release/deploy workflows succeed per `wg-after-a-pr-merges-to-main-verify-all`.
- [ ] **5.4** `cleanup-merged` via worktree-manager.

## Phase 6 — Post-merge operator (parent + bundle ACs #19–#22)

- [ ] **6.1** Monitor `cost_ceiling` event rate for 1 week (AC #19); flag any single chapter-Q&A conversation that hits the cap.
- [ ] **6.2** Monitor outline-unusable rate (AC #20); file tuning issue if > 30%.
- [ ] **6.3** (GREEN-S1 only) Log `cache_creation` vs `cache_read` ratio (AC #21); file follow-up if hit rate < 50% over 1 week.
- [ ] **6.4** (KD-4) Log per-turn buffer re-read p95 latency (AC #22); file follow-up if p95 > 100ms over 1 week to reconsider threading `documentExtractBuffer` on resolver result.

## Acceptance Criteria Map

Verified across phases per plan §Acceptance Criteria:

| AC | Phase | Verification |
|---|---|---|
| #1–#3 (chapter Q&A baseline) | 3.3+3.4 + 4.6 | Integration tests 1–3 + manual PR-review verification |
| #4 (per-conv cost) | 3.3+3.6 | Integration test + S1 verdict gates 5 vs 10-turn bound |
| #5 (loaded-chapter prefix single-PDF) | 3.3+3.4 | Integration test 1 |
| #5-bis (KD-6 cross-doc) | 3.5 | Router tests 10–11 (forward-looking if §3.2 reachability grep confirms unreachable) |
| #6 (cap between turns) | 3.5 case 5 | Integration test |
| #7 (extraction failure refund) | 3.5 case 4 + Sentry mirror | Integration test |
| #8 (BYOK + Soleur-key) | 3.4 + carry-forward | Existing `cc-cost-caps.ts` |
| #9 (no runtime SDK dep) | 3.1 | `rg "from \"@anthropic-ai/sdk\"" apps/web-platform/server/` returns only `import type` |
| #10 (leader symmetry) | 3.4 | Mirror tests |
| #11 (PR body User-Brand Impact + CPO + user-impact-reviewer) | 4.1 + 4.6 | Manual + review-skill invocation |
| #12 (S1 verdict in body) | 1.3 | PR body inspection |
| #13 (KD-5 stale-context) | 3.5 case 8a + 8b | Integration test |
| #14 (KD-3 mid-stream regression guard) | 3.5 case 7 | Integration test |
| #15 (KD-1 spike sections) | 1.3 + 2.6 | PR body inspection |
| #16 (KD-2 fixture licensing) | 2.4 | Manifest diff |
| #17 (KD-7 S1 stability) | 1.4 + ship-time `gh api` jq | Comment count vs review-requested events |
| #18 (TR4 single-commit) | 3.21 | Per-commit walking script |
| #19–#22 | 6.1–6.4 | Post-merge telemetry |
