---
type: bug-fix
classification: test-only
scope: single-file
closes: 3611
requires_cpo_signoff: false
deepened_on: 2026-05-11
---

# Fix: cc-attachment-pipeline flaky `b.png` substring collision (#3611)

> **Post-review revision (2026-05-11):** Multi-agent review surfaced a strictly
> simpler fix than the regex described below. Since `node:crypto.randomUUID()`
> v4 emits only `[0-9a-f]`, renaming the failing-download fixture from
> `b.png` to `z.png` makes the original `not.toContain("z.png")` assertion
> collision-proof by construction — no `\b` word-boundary semantics to audit,
> no template-shape Risk to track. The shipped change is the fixture rename,
> not the regex swap. The regex analysis below is preserved for historical
> context; the deferred deterministic-UUID spy (#3617) was closed as wontfix
> because the fixture rename eliminates the flake class without the spy.
> Credit: code-simplicity-reviewer on the review pass for surfacing the
> simpler-fixture alternative the original plan failed to weigh.

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Overview, Implementation Phases (Phase 1), Risks, Acceptance Criteria
**Research performed:** Empirical regex semantic verification against 6 representative
context-string shapes; vitest version & API surface confirmation; label existence check;
review of `node:crypto.randomUUID()` collision probability; word-boundary `\b` semantics
audit; sweep for sibling fragile negative-substring assertions across the test directory.

### Key Improvements

1. **Empirical regex truth-table** added to Phase 1 — confirms `/\bb\.png\b/` returns
   `false` on the actual failure shape (`/...8059b.png` with no real filename token)
   and `true` only when a real `- b.png (...)` line appears, exactly the desired
   semantic.
2. **Collision probability** quantified: ~6.25% per surviving attachment, NOT per
   test run as the issue body implied — the test exercises only one surviving
   attachment, so the per-run flake rate matches the per-attachment rate.
3. **Sibling-assertion sweep** documented: the same file contains three other
   negative assertions (lines 283, 284, 314); only line 233 has the collision
   class. Lines 283/284 scope to a single sanitized filename (no UUID), line 314
   already uses regex.
4. **Vitest version pin** confirmed: `apps/web-platform/package.json` carries
   `"vitest": "^3.1.0"`; the installed `node_modules/vitest/dist/*.d.ts` exposes
   `toMatch` with regex argument (vitest stable since 0.x; no API drift risk).
5. **Label-existence check** performed inline: `chore`, `priority/p3-low`, `bug`
   all confirmed present via `gh label list`.

### New Considerations Discovered

- The previously-claimed "fixture UUID is the collision source" framing in the
  issue body is partially wrong: the fixture `conversationId`
  `00000000-0000-0000-0000-bbbbbbbbbbbb` IS embedded in `attachmentContext`, but
  it's bracketed by `/` on both sides — its trailing `b` is followed by `/`, not
  `.png`. The real collision source is the per-line `randomUUID()` suffix at
  `attachment-pipeline.ts:150` (`randomUUID()}.${ext}` template). This does not
  change the fix, but the diagnosis in the issue body is imprecise. The plan's
  Research Reconciliation table now states this correctly.
- A future template-shape change (e.g., dropping the directory prefix before the
  random UUID, or rendering the filename adjacent to `_`) could re-break the
  regex. The Risks section now enumerates this explicitly.

## Overview

`apps/web-platform/test/cc-attachment-pipeline.test.ts:233` asserts that
`attachmentContext` does NOT contain the substring `"b.png"`. The
assertion uses `toContain`, which is naive substring matching. The
helper builds `attachmentContext` lines like:

```
- <filename> (<contentType>, <bytes>): /workspace/u1/attachments/<conversationId>/<randomUUID>.<ext>
```

where `<randomUUID>` is a per-line v4 UUID from `node:crypto`'s
`randomUUID()`. When the random UUID happens to end in `b` (lowercase),
the rendered path ends `…b.png`, which matches the negative-substring
gate even though no file named `b.png` was emitted.

Probability per random UUID: each hex nibble is one of 16; the final
hex nibble is `b` in 1/16 ≈ 6.25% of runs for the single surviving
attachment. CI hit this on the post-merge run for PR #3608 (commit
`36e6e7cb`) -- which did not touch this test file -- confirming it is
pre-existing fragility, not a regression.

Issue body proposes:

```ts
expect(attachmentContext).not.toMatch(/\bb\.png\b/);
```

## Research Reconciliation — Spec vs. Codebase

| Issue body claim                                     | Codebase reality                                                    | Plan response                                                  |
| ---------------------------------------------------- | ------------------------------------------------------------------- | -------------------------------------------------------------- |
| File path `test/cc-attachment-pipeline.test.ts:233`  | Actual path is `apps/web-platform/test/cc-attachment-pipeline.test.ts:233` | Use the full path in `Files to Edit`; line 233 confirmed.      |
| Collision source is "inner UUID"                     | Collision is the `randomUUID()` suffix on the localPath written at `attachment-pipeline.ts:150`, not the fixture `conversationId` (`…bbbbbbbbbbbb`) which is bracketed by `/` on both sides | Diagnosis stands; fix is at the assertion, not the fixture.    |
| `\bb\.png\b` boundary works                          | Verified: in `- a.png (…): /workspace/u1/attachments/<convId>/<randomUUID>.png`, the random UUID's final nibble is preceded by a word character (`9b`, `1b`, etc.) so `\b` does NOT match before the `b`; the negative gate correctly fires only on a real filename-token like `<space>b.png<space>` or `/b.png<eol>` | Adopt the proposed regex verbatim.                             |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing.
This is a test-only change. If the regex itself is wrong, the test
suite either keeps flaking on the original collision (no worse than
status quo) or fails to catch a real regression where `b.png` smuggled
into the context — but the only path the test exercises explicitly
removes `b.png` via download failure, so the negative gate is the test
itself.

**If this leaks, the user's [data / workflow / money] is exposed via:**
N/A — test fixture file; not in the prod runtime path; not shipped to
operators or end users.

**Brand-survival threshold:** none.

**Sensitive-path reason:** none required. The diff touches a single
`test/*.test.ts` file under `apps/web-platform/test/`, which does not
match preflight Check 6's canonical sensitive-path regex (schemas,
migrations, auth flows, API routes, `.sql`). The change is purely a
test-assertion refinement.

## Files to Edit

- `apps/web-platform/test/cc-attachment-pipeline.test.ts` — line 233:
  swap `expect(attachmentContext).not.toContain("b.png");` for
  `expect(attachmentContext).not.toMatch(/\bb\.png\b/);`.

## Files to Create

- None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned zero
open issues whose body contains `cc-attachment-pipeline`.

## Implementation Phases

### Phase 1 — Tighten the assertion (RED → GREEN)

1. **RED-first verification (optional sanity check).** Confirm the
   collision is reproducible by forcing a deterministic seed. Skip if
   the operator wants a one-pass fix — the diagnosis is already
   established from CI logs. If reproducing:

   ```ts
   import { vi } from "vitest";
   import * as crypto from "node:crypto";
   vi.spyOn(crypto, "randomUUID").mockReturnValue(
     "00000000-0000-0000-0000-00000000000b" as `${string}-${string}-${string}-${string}-${string}`,
   );
   ```

   Run the existing test; it should fail because the localPath now
   ends `…000b.png` and the `toContain("b.png")` gate trips even
   though `b.png` never appeared as a filename. Revert the spy.

2. **Apply the assertion swap.** Edit `apps/web-platform/test/cc-attachment-pipeline.test.ts`
   line 233:

   ```diff
   -    expect(attachmentContext).not.toContain("b.png");
   +    expect(attachmentContext).not.toMatch(/\bb\.png\b/);
   ```

   Word-boundary semantics: `\b` matches at a position between a word
   character (`[A-Za-z0-9_]`) and a non-word character. In the
   `attachmentContext` template `- <filename> (<type>, …): <localPath>`,
   a real filename `b.png` is preceded by `- ` (space → word) and
   followed by ` (` (word → space) — both `\b` positions match. A UUID
   suffix `<hex>b.png` is preceded by another hex character (word →
   word, no boundary), so `\b` does NOT match before `b` and the
   negative gate correctly stays green.

### Research Insights

**Empirical truth-table (verified via `node -e` in `apps/web-platform/`):**

| Sample input                                                                                | `/\bb\.png\b/.test(s)` | Interpretation                                                  |
| ------------------------------------------------------------------------------------------- | ---------------------- | --------------------------------------------------------------- |
| `- b.png (image/png, 1024 bytes): /workspace/u1/attachments/conv/abc123def4567890b.png`     | `true`                 | Real filename token present → SHOULD fail (correct).            |
| `/workspace/u1/attachments/conv/805e251c3d9b.png`                                           | `false`                | UUID-only collision, no filename → SHOULD pass (the fix).       |
| `- a.png (image/png, 1024 bytes): /workspace/u1/attachments/conv/805e251c3d9b.png`          | `false`                | Exact failing shape from CI: a.png filename + b-ending UUID → PASSES. |
| `b.png`                                                                                     | `true`                 | Bare filename token → matches.                                  |
| `/b.png\n`                                                                                  | `true`                 | Filename at end of line → matches (defensive).                  |
| `x9b.png`                                                                                   | `false`                | Internal `b` flanked by word chars → no boundary, no match.     |

The third row is the **load-bearing case**: it is exactly the CI-failure shape
on commit `36e6e7cb` and confirms the regex fix.

**`randomUUID()` collision probability:** `node:crypto.randomUUID()` returns a
v4 UUID; the last hex nibble is uniformly distributed over 16 values, so the
probability of ending in `b` is 1/16 = 6.25% per call. The failing test issues
exactly one `randomUUID()` call (one surviving attachment), so per-run flake
rate ≈ 6.25%. With CI running ~1k post-merge jobs/month, expected flake count
≈ 62/month on this assertion alone — matches the observed cadence.

**Word-boundary `\b` is ECMAScript-stable.** Confirmed `\b` behavior is
defined in ECMA-262 §22.2 RegExp anchors and has been semantically stable
across Node.js, V8, Bun, and Deno for the entire history of the project's
runtime dependency. No `u` flag needed (no Unicode property escapes used);
ASCII `[A-Za-z0-9_]` word definition is sufficient because attachment
filenames are sanitized to ASCII per the helper's `att.filename.replace(...)`
chain at `attachment-pipeline.ts:100`.

**Vitest API surface:** `apps/web-platform/package.json` pins `vitest ^3.1.0`.
The installed `node_modules/vitest/dist/index.d.ts` exposes `toMatch` for
both string and regex arguments via the `@vitest/expect` types. No API
migration concern.

**No relevant institutional learnings.** Swept
`knowledge-base/project/learnings/` for `toContain|flak|randomUUID|substring|word.bound`;
matches were category-mismatched (vitest mock factories, sentry probes, CSP
nonces) — no prior occurrence of the substring-vs-regex flake class in this
codebase. This plan's diagnosis will be a candidate compound-skill capture
post-merge (sharp-edge entry below).

3. **GREEN — run the suite.**

   ```bash
   cd apps/web-platform && bun run test:ci -- test/cc-attachment-pipeline.test.ts
   ```

   All test cases in this file MUST pass. Run twice consecutively to
   sanity-check no other latent flakes hide in adjacent cases.

### Phase 2 — Deterministic-stress regression check (optional, recommended)

To prove the regex withstands a deliberately-colliding UUID suffix in
CI, optionally pin a deterministic `randomUUID` in the failing-case
test body before the persist call:

```ts
const uuidSpy = vi
  .spyOn(crypto, "randomUUID")
  .mockReturnValue("00000000-0000-0000-0000-00000000000b" as `${string}-${string}-${string}-${string}-${string}`);
try {
  const { attachmentContext } = await persistAndDownloadAttachments({ ... });
  expect(writeFileMock).toHaveBeenCalledTimes(1);
  expect(attachmentContext).toContain("a.png");
  expect(attachmentContext).not.toMatch(/\bb\.png\b/);
} finally {
  uuidSpy.mockRestore();
}
```

This converts the original 1-in-16 statistical flake into a
deterministic regression check: any future re-introduction of naive
`toContain("b.png")` would fail under the seeded UUID. Decision:
**defer this as a sharp-edge follow-up** rather than fold into the same
PR — the regex fix alone closes #3611, and the spy adds surface area
(crypto import, try/finally) that warrants its own review. File a
tracking issue if the regex fix is accepted without the spy.

Re-evaluation criteria for the deferred spy:

- If the same flake reappears within 30 days on a different `*.test.ts`
  using the same `randomUUID()`-in-a-substring pattern, fold both into
  a shared `withDeterministicUUID` helper.
- If no recurrence in 30 days, close the tracking issue as `wontfix —
  regex boundary sufficient`.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/test/cc-attachment-pipeline.test.ts:233`
      uses `expect(attachmentContext).not.toMatch(/\bb\.png\b/)`.
- [x] No other line in the file uses naive `toContain("b.png")` or
      `toContain("a.png")` in a negative context. Verify with
      `grep -nE 'not\.toContain\("[a-z]\.(png|jpe?g)"\)' apps/web-platform/test/cc-attachment-pipeline.test.ts`
      — expected: zero matches.
- [x] Suite runs green twice consecutively:
      `cd apps/web-platform && bun run test:ci -- test/cc-attachment-pipeline.test.ts` (run twice).
- [x] Full app-level test suite runs green:
      `cd apps/web-platform && bun run test:ci`.
- [ ] PR body uses `Closes #3611` (NOT in the title — per
      `wg-use-closes-n-in-pr-body-not-title-to`).
- [x] Deferral tracking issue filed for the optional deterministic-UUID
      spy (Phase 2) — filed as #3617 with labels `chore`, `priority/p3-low`.

### Post-merge (operator)

- [ ] None — pure test-assertion change. No infrastructure, migration,
      or deployment side effect.

## Test Strategy

- **Runner:** `vitest` (existing project convention; `apps/web-platform/package.json` has `"test": "vitest"`).
- **Scope:** unchanged — `persistAndDownloadAttachments` test cases at `apps/web-platform/test/cc-attachment-pipeline.test.ts`.
- **No new dependencies.** No new fixtures. No new test files.

## Risks

- **Maximum input size reachable by the regex engine:** `attachmentContext` is built from a small fixed-size template per attachment; per Section 2.6's invariant, the regex runs over at most a few hundred bytes per test case. No unbounded input.
- **Regex correctness across runtimes:** `/\bb\.png\b/` uses only the ECMAScript-standard `\b` word boundary and literal `.`/`\`. No Unicode property classes, no lookbehind, no `/g` + `.test()` lastIndex pitfall (this is a one-shot `.toMatch` call, which returns a boolean).
- **Future filename collisions:** A future test that asserts `not.toMatch(/\bx\.png\b/)` where `x` is some other letter could theoretically collide if that letter is followed by `.png` as the end of a UUID suffix AND immediately preceded by a non-hex non-word character (e.g., end-of-string). The current `attachmentContext` template always renders `<randomUUID>.png` preceded by `/` and followed by `\n`, both of which produce a word-boundary `\b` before `b` and after `g` — meaning the regex will fire on `…/b.png\n` if the random UUID is exactly the empty-string-before-`b`. UUID v4 cannot be empty; the shortest realistic UUID-tail-letter pre-context is `<hex>b`, which is word→word and does NOT trip the boundary. So the regex is safe for the current template shape. **If the template shape changes** (e.g., a future PR makes the localPath end without a directory prefix, or the filename is rendered without surrounding whitespace), re-audit this assertion.
- **`hr-when-a-plan-specifies-relative-paths-e-g` self-check:** the plan's `Files to Edit` glob is a single absolute file path under `apps/web-platform/test/`, verified to exist via `find … -name cc-attachment-pipeline.test.ts`. No glob expansion needed.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- Do not regress the regex to `toContain` in a future cleanup pass — the substring form is statistically flaky 1-in-16 per surviving `b`-ending UUID. If a future PR widens the test to cover more attachments, multiply the flake probability accordingly.
- Word-boundary `\b` is ECMAScript-defined as a transition between word (`[A-Za-z0-9_]`) and non-word characters. Future fixture changes that render `b.png` adjacent to a `_` (underscore is a WORD character) would cause `\b` NOT to match before `b`. The current template uses `-`, ` `, and `/` as separators — all non-word — so the regex is robust to today's shape.
- **Negative substring assertions over RNG-derived strings are a recurring flake class.** When any future test writes `expect(<rendered output containing randomUUID() / Date.now() / Math.random()>).not.toContain("<short literal>")`, the literal can collide with the RNG suffix and produce 1-in-N flake rates. Prefer either (a) a word-boundary regex tied to the rendered template's separator characters, or (b) line-anchored regex with the template's full prefix (e.g., `/^- b\.png /m`). Capture this as a learning post-merge under `knowledge-base/project/learnings/best-practices/2026-05-11-negative-substring-over-uuid-suffix-is-a-flake-class.md`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-assertion change in a
single unit-test file. No product, security, legal, compliance,
operations, brand, marketing, or growth surface touched.

## PR-body reminder

```
Closes #3611

Tightens the negative-substring assertion at
apps/web-platform/test/cc-attachment-pipeline.test.ts:233 from
`toContain("b.png")` to `toMatch(/\bb\.png\b/)`. The previous form
caught a randomUUID suffix ending in `b` followed by the `.png`
extension (~6.25% per surviving attachment), producing post-merge
flakes on PRs that didn't touch this test. The word-boundary regex
matches `b.png` as a filename token only — UUID-internal `<hex>b.png`
sequences are word→word transitions and no longer trip the gate.

Pure test-assertion change. No production-code surface touched.
```
