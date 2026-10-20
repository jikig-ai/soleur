---
title: "fix: normalizeRepoUrl must be idempotent (dot-segment, opaque-path and peel-chain shapes)"
type: fix
date: 2026-10-20
slug: normalize-repo-url-idempotent-fixpoint
branch: feat-one-shot-normalize-repo-url-idempotent-fixpoint
issue: 10624
lane: cross-domain
---

# fix: normalizeRepoUrl must be idempotent (dot-segment, opaque-path and peel-chain shapes)

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Overview

`normalizeRepoUrl` (`apps/web-platform/lib/repo-url.ts`) documents itself as idempotent, and the fast-check suite added by PR #10624 (ADR-293) found an input where it is not. In the merge_group run 39400877769 on 2026-10-20 the counterexample `" http://a.aa/..git/"` (fast-check seed -1029694662, path `68:0:0:0:0:0:1:0:0`) ejected an unrelated PR (#10528) from the merge queue.

Mechanism: the single pass parses with `new URL()`, then strips `/+$` and `(\.git)+$`. For a last path segment `..git` the `.git` strip leaves a `.` dot segment (`http://a.aa/.`). The next call's `new URL()` resolves that dot segment away (`http://a.aa`). The output of pass 1 is therefore not a fixpoint of pass 1.

Fix: rename the existing body to an internal single pass and make the exported function re-run it until the output stops changing, bounded by a length-derived cap (CTO ruling below). Keep the documented canonical form unchanged. Add the reported counterexample as a permanent regression fixture, proven RED before the fix and GREEN after.

Constraints carried from the caller: PR #10692 is the only change; do not touch PR #10528 or any git-data/legal file; never dispatch a workflow; never comment on any issue; PR body uses `Ref #10624` and a Ref to the failing run only (never Closes/Fixes/Resolves).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured) | Plan response |
|---|---|---|
| Counterexample reproduces; a bounded loop "max 4 passes" fixes it | Seed + path replay reproduces on the first property (scratch replay against the worktree code: `Counterexample: [" http://a.aa/..git/"]`, `Shrunk 0 time(s)`). A **4-pass** cap is NOT enough: `"http://a.aa/" + "..git/"x6` needs 7 passes, `"x" + " /"x20` needs 20, and a dot-heavy fuzz needed up to 8 (1.3% of inputs needed >3). | Cap is length-derived (`raw.length + 3`), not 4. Ruled by CTO below. |
| "the dot-segment shape" is the defect | Same single-pass-not-a-fixpoint root cause also produces: opaque-path non-special scheme `"xx:B"` -> `"xx://B"` -> `"xx://b"`; string-only peel chains `"x / / / /"` (each pass peels one `/ ` pair); `"a#.git // // "`. | The same loop fixes all of them (no extra code). They are pinned as extra fixtures and listed in the PR body as additional counterexamples found. Property generator NOT widened (CTO). |
| Function header: coupled to SQL regex chain in `031_normalize_repo_url.sql` | 031 is a one-time backfill `UPDATE` using `regexp_replace`; it has no URL parsing, so it never resolved dot segments, `%2e` segments or opaque paths. TS<->SQL already diverges on those classes (e.g. `http://a.aa/x/../y`). | Finding: the dot-segment shape does NOT affect the SQL mirror and needs no migration. See `## SQL Mirror Finding`. |
| Stray `/* #9815 e2e probe — REVERTED BEFORE COMMIT */` | Present on `origin/main` as line 71 of `lib/repo-url.ts` (added by #10025). | Deleted in this PR (CTO), called out in PR body. |

## Research Insights

**Premise Validation.** Cited and checked: PR #10624 MERGED 2026-10-20T07:46:22Z; PR #10692 is this branch's draft PR (OPEN, draft); issue #10633 OPEN (SQL re-trim + stored-row backfill; read-only, will be cited with `Ref` only); `lib/repo-url.ts`, the property test, `test/repo-url.test.ts`, `test/repo-url-sql-parity.test.ts` and `supabase/migrations/031_normalize_repo_url.sql` all exist on `origin/main`. ADR corpus grep: ADR-293 (property-based testing adoption) is the only relevant ADR; its "First yield" section is where this second yield is recorded. No stale premise. The worktree HEAD (`42b9ca030b`) is one init commit ahead of `origin/main` at the time of planning; `lib/repo-url.ts` and the property test are identical on `origin/main`.

**Property List.**
1. `normalizeRepoUrl(normalizeRepoUrl(x)) === normalizeRepoUrl(x)` for every input (the documented contract).
2. The canonical form is unchanged for realistic repo URLs (`https://github.com/Owner/Repo[.git][/]` -> `https://github.com/Owner/Repo`; scheme+host lowercased, path case preserved).
3. The function always terminates and cannot loop unboundedly on adversarial input.
4. The reported counterexample (and the shapes the same mechanism produces) stay fixed (regression pinning).

**Cut List.**
- Fixed 4-pass cap -> property 1 (insufficient, measured) -> replaced by length-derived cap.
- Inline dot-segment resolution (hand-resolving `.`/`..`/`%2e` before the strips) -> property 1 -> `new URL()` already owns that grammar; re-running the pass reuses it; hand-rolling duplicates the WHATWG rules and misses opaque-path/peel shapes.
- A new SQL migration or edit to 031 -> none of the properties (SQL never resolved dot segments) -> covered by #10633 for its own defect; not needed here.
- Widening the property generator -> property 4 -> already covered by pinned fixtures; CTO ruled it a separate follow-up because it changes the merge_group flake profile.

**Institutional learning applied.** `knowledge-base/project/learnings/logic-errors/2026-10-20-repo-url-retrim-shielded-whitespace-sql-twin.md`: "Ordering-dependent normalizers have a re-normalization obligation at the end" — the same class one level up (a strip can expose material the *parse* step would resolve). Prevention item 1 ("end with the operation you started with") generalizes to "iterate to a fixpoint".

**Scratch measurements** (scratch copies under the session scratchpad, nothing committed): 400k-run fuzz over dot-segment, percent-dot, whitespace/slash/`.git` alphabets and `fc.string()`: 0 non-converging inputs; passes needed <= input length always (the `+3` slack is never used; re-measured on the final single-loop shape: 400k runs, 0 cap hits, 0 non-idempotent outputs); from the third pass on every change strictly shortens the string (0 violations), which is why a length-derived cap terminates. Pass 2 can be same-length (`xx:B` -> `xx://B` -> `xx://b` lowercases the host), so strict shortening is only argued from pass 3. A reviewer scratch run (300k) and a realistic-URL corpus (300k `scheme://host/owner/repo[suffix]` inputs, 0 single-pass-vs-loop differences) agree. Fixture expectations, computed with the final design: `" http://a.aa/..git/"` -> `http://a.aa`; `"http://a.aa/" + "..git/"x5` -> `http://a.aa`; `"xx:B"` -> `xx://b`; `"x" + " /"x8` -> `x`. A 4-pass cap leaves the 5-deep dot chain at `http://a.aa/.` and the 8-pair peel at `x / / /`, so these fixtures also catch a regression to a fixed cap.

**Behavior note (opaque-path inputs).** The loop changes output for non-`http(s)` scp-style inputs such as `github.com:Foo/Bar`: a single pass gave `github.com://Foo/Bar`, the loop gives `github.com://foo/Bar` (pass 2 reads `Foo` as a host and lowercases it). The only production gate on user input is the setup route's `^https:\/\/github\.com\/[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+$` check, which runs after normalization and rejects both forms, so no accepted input changes; the `xx:B` fixture pins the (now stable) value rather than endorsing it as a feature. Same-length second pass is why strict shortening is argued only from pass 3.

## Plan Review Outcome

Panel (threshold `none`, 3 agents; CTO already consulted twice, so the named panel was not re-run): DHH, Kieran, code-simplicity. Applied (mechanical): single-loop shape; `raw.length + 3` cap without `.trim()`; corrected importer list and caller-suite list (three setup-route suites fully mock the module); header comment to be reworded rather than appended; ADR note cut to the yield; test-runner equivalence noted. Re-ruled by CTO (technical, DHH P1 + simplicity P1 + Kieran): Sentry mirror dropped, silent return on the unreachable cap path. Not applied: dropping the 5-deep dot-chain fixture (CTO ruling 2 keeps it as a cap-regression catcher), collapsing the Guard Contract (the plan-gate requires it; kept compact), dropping the 300k realistic-URL corpus (kept as PR-body evidence, not a gate).

## Technical Rulings

Persisted in `knowledge-base/project/specs/feat-one-shot-normalize-repo-url-idempotent-fixpoint/decision-challenges.md`:

- Ruled by CTO agent, 2026-10-20: Convergence loop capped at `raw.length + 3` passes, last-pass output returned silently on cap exhaustion with no Sentry import (re-ruling after plan-review, option B over the first ruling's Sentry mirror) - a fixed 4 is provably insufficient (7 and 20 passes measured) while the length bound terminates the loop; the cap branch is unreachable by construction (0 hits in 400k+ fuzz runs), so a mirror there could never be tested and would add a dependency to a pure normalizer. Reversal trigger: any input that hits the cap flips this to a Sentry mirror. Throw and no-cap were rejected (a throw 500s a request path; an unbounded loop is the worst failure mode).
- Ruled by CTO agent, 2026-10-20: Pin the reported counterexample plus the extra examples, leave the generator unchanged and file the generator widening as a follow-up - the loop fix needs fixtures that would catch a cap regression, and generator changes risk queue flakes.
- Ruled by CTO agent, 2026-10-20: Delete line 71 of `lib/repo-url.ts` in this PR - it is a dead one-line leftover in the file already being changed.
- Ruled by CTO agent, 2026-10-20: Keep the ADR-293 note at the yield only (1-2 lines), SQL divergence in the lib header comment and the PR body - the ADR is the decision record and holds the yield itself, while the mirroring obligation belongs next to the code it constrains so it is read at edit time.

Planner refinement inside the CTO ruling (not a new decision): the string-only peel fixture uses `"x" + " /"x8` (8 pairs) rather than 5 pairs, because 5 pairs converge within a 4-pass cap and would not catch a regression to it.

## SQL Mirror Finding (item 3 of the brief)

Read `apps/web-platform/supabase/migrations/031_normalize_repo_url.sql`, `supabase/verify/031_normalize_repo_url.sql` (existence), the `sqlNormalize031` port in `test/repo-url-sql-parity.test.ts`, and issue #10633 (read-only).

- 031 is a one-time backfill `UPDATE` of `users.repo_url` and `conversations.repo_url`: `LOWER(substring(scheme+host)) || path`, then `regexp_replace` `/+$`, `(\.git)+$`, `/+$`. No `new URL()` equivalent: no dot-segment resolution, no percent-encoding, no opaque-path handling, no loop.
- Consequence: for `http://a.aa/..git/` SQL yields `http://a.aa/.` and stops; TS (after this fix) yields `http://a.aa`. That divergence class (inputs where `new URL()` rewrites the path) pre-dates this PR — it already exists for `http://a.aa/x/../y`, `%20`, default ports etc. The fixpoint loop does not widen it: the loop only re-applies the same TS pass; it adds no new equivalence the SQL had to honor.
- The parity gate only covers URL-parseable inputs without dot segments (its fixture table). Realistic stored values are GitHub repo URLs (`https://github.com/<owner>/<repo>[.git]`) which contain none of these shapes, so the stored-vs-write-boundary risk is nil for the dot-segment shape.
- **Conclusion: no migration, no change to 031, no change to the parity port.** Issue #10633 (missing SQL re-trim + stored-row re-normalization) is a separate defect in the same mirror. The PR body will cite it with `Ref #10633` as related, and the ADR-293 note points to it. It is not closed or commented on.

## Open Code-Review Overlap

None (queried open `code-review` issues for `apps/web-platform/lib/repo-url.ts`, `apps/web-platform/test/lib/repo-url.property.test.ts`, `apps/web-platform/test/repo-url.test.ts`: zero matches).

## User-Brand Impact

- **If this lands broken, the user experiences:** a workspace whose repo URL normalizes differently on write and read (the repo-setup, active-repo and webhook push-reconcile routes compare normalized URLs), so a connected repo appears missing or a push reconciles zero workspaces. For realistic GitHub URLs the output is byte-identical to today (measured: 300k generated `scheme://host/owner/repo[suffix]` inputs, 0 single-pass-vs-loop differences), so a regression here is visible in the existing fixtures (`test/repo-url.test.ts`, parity test) before it can ship.
- **If this leaks, the user's data is exposed via:** no new exposure vector. The change adds no logging, telemetry, network call or stored data; the normalizer stays a pure, dependency-free string function.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** a pure normalizer change that is output-identical for realistic inputs and adds no data surface; not `aggregate pattern` because no cross-user pattern or stored data changes.

`threshold: none, reason: lib/repo-url.ts is a stateless string normalizer; the change alters output only for pathological inputs (dot segments, opaque-path schemes, peel chains) and never touches stored rows, auth, or credentials.`

## Implementation Phases

Order is test-first (`cq-write-failing-tests-before`); `hr-never-git-stash-in-worktrees` applies — RED is shown by running the new fixture before editing the SUT, not by stashing.

### Phase 0 — Sync

- `git fetch origin main` and merge/rebase the branch onto `origin/main` so `lib/repo-url.ts` and the property test are the ones the merge queue will see. No other file in the PR is touched.

### Phase 1 — RED: regression fixtures (test file only)

Edit `apps/web-platform/test/lib/repo-url.property.test.ts`, inside the existing `describe("normalizeRepoUrl — regression fixtures", ...)` block, after the two existing fixtures (anchor: the `space before a stripped slash suffix` `it`):

1. Reported counterexample, in the existing comment style:
   - Comment: `// regression fixture: fast-check seed -1029694662 path 68:0:0:0:0:0:1:0:0` plus one line of explanation (trailing `.git` strip leaves a `.` dot segment the next `new URL()` resolves away).
   - Assert idempotence AND the pinned value: `const once = normalizeRepoUrl(" http://a.aa/..git/"); expect(once).toBe("http://a.aa"); expect(normalizeRepoUrl(once)).toBe(once);`
   - Never commit `{ seed }` params (ADR-293 / README convention).
2. Three extra example fixtures for the other shapes (label `// pinned example (scratch fuzz 2026-10-20, no fast-check seed)`), each asserting value + idempotence:
   - deep dot-segment chain `"http://a.aa/" + "..git/".repeat(5)` (written out literally or via `.repeat`) -> `http://a.aa`
   - opaque-path scheme `"xx:B"` -> `xx://b`
   - string-only peel chain `"x" + " /".repeat(8)` -> `x`
3. Run `cd apps/web-platform && bunx vitest run test/lib/repo-url.property.test.ts` (equivalent to the README's `./node_modules/.bin/vitest run <file>`). Expect **4 new fixtures RED** (the existing tests green; the property tests may be green or, on an unlucky seed, red — do not rely on them). Record the failing output (assertion lines) for the PR body ("fails before the fix").

### Phase 2 — GREEN: the fix (`lib/repo-url.ts`)

Shape (about 15 changed lines; numbers are not load-bearing):

```ts
/** One normalization pass — the documented canonical-form steps 1-5. Not idempotent on its own (a strip can expose a dot segment / opaque path the next parse rewrites). Trims, so it returns "" for empty/whitespace input. */
function normalizeRepoUrlPass(raw: string): string { /* existing body after the null guard, unchanged */ }

export function normalizeRepoUrl(raw: string | null | undefined): string {
  if (raw == null) return "";
  // Re-run the pass until the output stops changing. Pass 2 may be same-length (opaque-path scheme host
  // lowercase) but from pass 3 every change strictly shortens, so `raw.length + 3` iterations always reach
  // the fixpoint; the cap is a termination guard on an unreachable branch, not a behavior.
  let current = raw;
  const cap = raw.length + 3;
  for (let i = 0; i < cap; i++) {
    const next = normalizeRepoUrlPass(current);
    if (next === current) return current;
    current = next;
  }
  return current;
}
```

- Keep the exported signature and the `null/undefined/"" -> ""` contract: the `null` guard stays; `""`/whitespace-only inputs fall out of the first iteration as `""` because the pass trims (verified in scratch: `""` -> `""`, `"   "` -> `""`). Single-loop shape (no separate first pass before the loop).
- No new import and no telemetry (CTO re-ruling): `lib/repo-url.ts` stays dependency-free. The cap is the only termination guard on the unreachable branch; do not add a Sentry mirror or a throw.
- Update the header comment (reword, do not merely append): replace the "Idempotent." claim and the "any change here must be mirrored in the SQL regex chain" sentence so the paragraph does not contradict itself. State: (1) canonical-form step 6 "re-run the pass until the output stops changing", bounded by `raw.length + 3` iterations (the initial pass is the first iteration); (2) the termination argument (strict shortening from pass 3; pass 2 may be same-length for opaque-path schemes such as `xx:B` -> `xx://B` -> `xx://b`); (3) the SQL twin `031_normalize_repo_url.sql` mirrors steps 1-5 only for URLs where `new URL()` does not rewrite the path — it has no URL parse (dot segments, `%2e`, opaque paths) and no loop, and the realistic stored values (`https://github.com/<owner>/<repo>`) are unaffected; see #10633 for the separate SQL re-trim defect.
- Delete the stray `/* #9815 e2e probe — REVERTED BEFORE COMMIT */` line (CTO).
- Re-run `bunx vitest run test/lib/repo-url.property.test.ts` -> all green; record output ("passes after the fix").

### Phase 3 — Verification runs

- `cd apps/web-platform && bunx vitest run test/lib/repo-url.property.test.ts test/repo-url.test.ts test/repo-url-sql-parity.test.ts test/current-repo-url.test.ts`.
- Real importers of the module are `app/api/repo/setup/route.ts`, `app/api/workspace/active-repo/route.ts`, `app/api/webhooks/github/route.ts`, `server/current-repo-url.ts` and `server/inngest/functions/workspace-reconcile-on-push.ts`. The three setup-route suites fully `vi.mock("@/lib/repo-url")` and never load the real module, so they prove nothing here; run the suites that load it: `bunx vitest run test/current-repo-url.test.ts test/server/inngest/workspace-reconcile-on-push.test.ts` plus any webhook / active-repo suite found by `git grep -l "webhooks/github/route\|workspace/active-repo/route" -- 'apps/web-platform/test/**'`. With no new import this is a plain regression run, not a gate on a new dependency.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (the in-package form; the repo root declares no `workspaces`, so `npm run -w` aborts).
- Higher-run-count hunt, scratch only (a throwaway script in the session scratchpad, NOT committed, no env knob added to the test): a driver that imports the real `normalizeRepoUrl` and runs `fc.assert(..., { numRuns: 100000 })` several times with the property file's own `inputArb` plus a dot-segment alphabet (`.`, `..`, `..git`, `%2e`, `%2E`, `.%2e`, `.git`, `.GIT`, ` `, `/`) over 3+ different random seeds. Any counterexample found is reported in the PR body and NOT fixed in this PR unless the loop already fixes it; a counterexample that hits the `raw.length + 3` cap flips the CTO ruling to the Sentry-mirror option and reopens the termination argument (rework, not a bigger cap).

### Phase 4 — Docs (ADR-293)

- Append a short "Second yield" note (1-2 lines) after "First yield" in `knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md`: the second yield was non-idempotence on dot-segment / opaque-path / peel-chain inputs (reported counterexample `" http://a.aa/..git/"`, merge_group run 39400877769), fixed by a bounded convergence loop. Yield only — the SQL divergence lives in the `lib/repo-url.ts` header and the PR body (CTO ruling). Content-anchor reference only (`cq-cite-content-anchor-not-line-number`).

### Phase 5 — PR (via soleur:ship)

- PR #10692 body: root cause, RED output, GREEN output, the SQL mirror finding, other counterexamples found (list the extra shapes), the stray-line deletion, `Ref #10624`, `Ref https://github.com/jikig-ai/soleur/actions/runs/39400877769` (failing run), `Ref #10633` (related, not closed). No `Closes/Fixes/Resolves`. Follow-up to file (a normal issue, no comment on any existing issue): widen the property generator with a dot-segment/peel alphabet and decide its CI budget (CTO ruling 2). Queue rule in force: if the same suite flakes again in the merge queue after this PR is queued, file a flake issue (`## Flaky-test policy` in `test/README.md`) rather than re-enqueue a third time.

## Files to Edit

- `apps/web-platform/lib/repo-url.ts` — rename body to internal pass; single-loop exported fixpoint (no new import); reworded header; delete stray probe line.
- `apps/web-platform/test/lib/repo-url.property.test.ts` — four regression fixtures in the existing `regression fixtures` describe.
- `knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md` — "Second yield" note.

## Files to Create

- None in source. (Planning artifacts only: this plan, `knowledge-base/project/specs/feat-one-shot-normalize-repo-url-idempotent-fixpoint/tasks.md` and `decision-challenges.md`.)

Explicitly NOT touched: `supabase/migrations/**`, `supabase/verify/**`, `test/repo-url-sql-parity.test.ts`, PR #10528, any git-data/legal file, any workflow.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add the regression fixture to the property test in the file's existing pinned-seed style ... and make sure it FAILS before the fix and passes after (show both)" | Phase 1 (RED) + Phase 2 (GREEN) + Phase 5 PR body | mapped |
| 2 | "apply the minimal fix in lib/repo-url.ts, keeping the documented canonical form" | Phase 2 | mapped |
| 3 | "read it and state in the PR whether the dot-segment shape affects that mirror (do NOT add a migration unless the plan shows it is needed" | `## SQL Mirror Finding` + Phase 5 PR body | mapped (no migration needed) |
| 4 | "run the web-platform suite for that file ... and the sibling repo-url unit tests) and run the property test with a higher run count a few times to look for other dot-segment shapes (report any other counterexample you find in the PR" | Phase 3 + Phase 5 PR body | mapped |
| 5 | "the PR is the only change, small" | Files to Edit (3 files) | mapped |
| 6 | "if the same suite flakes again in the merge queue after your PR is queued, file a flake issue rather than re-enqueue a third time" | Phase 5 note | mapped |
| 7 | "`Ref #10624` / a Ref to the failing run only, never Closes/Fixes/Resolves" | Phase 5 | mapped |
| 8 | "read it (read-only), reference it with `Ref` only if relevant, do not close it" | `## SQL Mirror Finding`, Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `lib/repo-url.ts` fixpoint loop | "A bounded fixpoint loop (rename the existing body to an internal single pass; the exported function re-runs it until the output stops changing" | asked |
| Cap length-derived instead of 4 | "max 4 passes" (caller proposal) | inferred — justification: measured 7- and 20-pass inputs make a 4-cap non-idempotent; the CTO ruled the length bound. Caller's "bounded" requirement is kept. |
| Cap-exhausted path returns last output silently | — | inferred — justification: a termination guard is needed because pass 2 can be same-length; CTO re-ruled option B (no Sentry, no throw). |
| Property test fixtures (1 reported + 3 extra) | "add the regression fixture to the property test" | asked (reported one); extras inferred — justification: without them a regression to a fixed cap would pass the single reported case; CTO ruled them. |
| Delete stray `#9815` line | — | inferred — justification: dead leftover in the same file; CTO ruled. |
| ADR-293 "Second yield" note | "report any other counterexample you find in the PR" | inferred — justification: ADR-293 is the recorded home of the suite's yields and must not imply SQL parity; CTO ruled. |
| Scratch high-run-count hunt | "run the property test with a higher run count a few times" | asked |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 3 | Estimated changed lines: ~70 (fix ~15, fixtures ~35, ADR ~5, comment/header ~15)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `normalizeRepoUrl(" http://a.aa/..git/")` returns `http://a.aa` and `normalizeRepoUrl` of that output is identical (fixture pinned with comment `// regression fixture: fast-check seed -1029694662 path 68:0:0:0:0:0:1:0:0`; no `{ seed }` param committed).
- [ ] RED shown: the new fixtures fail against the unmodified `lib/repo-url.ts` (output captured for the PR body); GREEN shown after the fix.
- [ ] Extra fixtures (5-deep `..git/` chain, `xx:B`, 8-pair `" /"` peel) pass and each fails under a 4-pass-cap variant of the loop (mutation row below).
- [ ] Output byte-identical to the pre-fix single pass for realistic repo URLs (scratch 300k-run corpus of `scheme://host/owner/repo` with `.git`/`.GIT`/`/`/`.git.git`/whitespace variants, owner/repo segments excluding dot segments: 0 differences between single pass and loop; cited in the PR body). Documented canonical form unchanged for realistic inputs: `test/repo-url.test.ts` and `test/repo-url-sql-parity.test.ts` pass unmodified.
- [ ] `cd apps/web-platform && bunx vitest run test/lib/repo-url.property.test.ts test/repo-url.test.ts test/repo-url-sql-parity.test.ts test/current-repo-url.test.ts` all green; the importer-loading suites listed in Phase 3 green; typecheck green.
- [ ] Scratch high-run-count hunt (>= 3 seeds x 100k runs) reports zero non-idempotent outputs and zero inputs hitting the `raw.length + 3` cap; any other counterexample is listed in the PR body.
- [ ] `lib/repo-url.ts` gains no import (the diff shows no new `import` line) and no side effect on the cap path.
- [ ] `git diff --name-only origin/main...HEAD` is a subset of: the three Files-to-Edit paths, planning artifacts under `knowledge-base/project/{plans,specs}/feat-one-shot-normalize-repo-url-idempotent-fixpoint/` and the plan file, and the pipeline-written `knowledge-base/INDEX.md` / `specs/<branch>/session-state.md` if regenerated; no `supabase/`, no `.github/`, nothing git-data/legal.
- [ ] Stray `#9815 e2e probe` line removed; ADR-293 "Second yield" present and cites #10633 and the SQL divergence.
- [ ] PR #10692 body uses only `Ref #10624`, `Ref <failing run 39400877769>`, `Ref #10633`; contains none of `Closes`, `Fixes`, `Resolves`.

## Guard Contract

### Guard 1 — repo-url idempotence property suite and regression fixtures

**Property.** For every input `x`, `normalizeRepoUrl(normalizeRepoUrl(x)) === normalizeRepoUrl(x)`, and the loop that delivers it terminates within `raw.length + 3` iterations.

**Assembly.** The suite's population is whatever flows through the single chokepoint `normalizeRepoUrl`. Real importers (verified by `git grep`): `app/api/repo/setup/route.ts`, `app/api/workspace/active-repo/route.ts`, `app/api/webhooks/github/route.ts`, `server/current-repo-url.ts`, `server/inngest/functions/workspace-reconcile-on-push.ts`; other files that mention the name (detect-installation route, resolve-founder-for-installation, agent-runner, session-sync, cron-workspace-sync-health) only reference it in comments. There is no second exported entry point; internal `normalizeRepoUrlPass` is not exported, so no caller can bypass the loop. Property file: `test/lib/repo-url.property.test.ts` (arbitraries over `fc.string()`, `webUrl x suffix`, padded). Fixtures: the four pinned examples.

**Mutation matrix.**

| # | Edit | Expected |
|---|------|----------|
| 1 | Revert the SUT to the single pass (exported function = one pass) | reported-counterexample fixture RED |
| 2 | Change the cap to a fixed `4` | 5-deep `..git/` chain fixture RED and 8-pair peel fixture RED |
| 3 | Loop returns `current` after the first pass regardless of `next` | `xx:B` fixture RED (host lowercase only lands on pass 2) |
| 4 | Loop compares `next.length === current.length` instead of `next === current` | `xx:B` fixture RED / loop exits early (same-length change lowercases host) |
| 5 | Drop the `raw.length + 3` bound (`while (true)`) | not caught by the suite — covered by the scratch 400k-run convergence evidence and review of the diff; recorded as accepted gap (the cap-hit branch is unreachable by construction) |

**Harness rows.** (a) Edit the SUITE: drop the second `normalizeRepoUrl(once)` assertion from the reported-counterexample fixture — the fixture must still be RED on the unfixed SUT only because of the pinned `toBe("http://a.aa")` value (confirm the value assertion alone also fails: unfixed output is `http://a.aa/.`). (b) A must-PASS non-canonical input: `"  HTTPS://GitHub.com/Foo/Bar.git/  "` -> `https://github.com/Foo/Bar` (already in `test/repo-url.test.ts`; confirms the loop does not over-strip). The existing negative-control `it` in the property file (a deliberately false property throws) stays and keeps the anti-vacuity floor.

**Anchor.** Fixtures compare against literal expected strings, not a stored hash; the pinned `http://a.aa` etc. are the independent oracle. Weakening needs an edit to the test file itself, which the diff gate (`git diff --name-only`) and review see.

## Test Scenarios

- Reported counterexample: `" http://a.aa/..git/"` -> `http://a.aa`, second call identical.
- 5-deep `..git/` chain -> `http://a.aa` (needs 6 passes; fails under a 4-cap).
- `xx:B` -> `xx://b` (host lowercased on pass 2).
- `"x" + " /"x8` -> `x` (needs 8 passes; fails under a 4-cap).
- Regression guard: `https://github.com/Foo/Bar.git/` -> `https://github.com/Foo/Bar`; `""`/`"   "`/`null` -> `""` (existing tests).

## Observability

Skipped per Phase 2.9: `apps/web-platform/lib/` is outside the path set that triggers the section, and the change adds no server route, cron, infra or error path (the cap-exhausted branch returns silently by CTO ruling; it is unreachable by construction).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — a stateless TypeScript normalizer fix plus tests and an ADR note. No UI surface, no regulated-data surface (not a schema/auth/API-route/`.sql` change; no new data movement), no infrastructure, no new architectural decision (ADR-293 note only).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan sets `none` with the sensitive-path scope-out bullet.
- Do not "fix" the cap to a constant 4: the `x / / / /` and `..git/` chains need N passes (measured 7 and 20). If a future input hits `raw.length + 3`, rework the loop and reopen the CTO ruling (switch to the Sentry-mirror option) rather than raising the cap.
- The loop also lowercases the host on pass 2 for opaque-path schemes (`xx:B` -> `xx://b`): intended, now stable; it does not affect `http(s)` GitHub URLs.
- Keep `lib/repo-url.ts` dependency-free: do NOT import `@/server/observability` (pulls pino; violates the import-boundary gate) or `@/lib/client-observability` (CTO re-ruling: no telemetry on an unreachable branch).
- Do not add the scratch higher-run-count knob (e.g. `FC_NUM_RUNS`) to the committed test: README convention is default `numRuns`, and CTO ruling 2 keeps the CI flake profile unchanged.
- The worktree must not stash (`hr-never-git-stash-in-worktrees`): show RED by running the new fixtures before editing the SUT.
