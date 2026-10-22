---
module: web-platform
date: 2026-10-20
problem_type: logic_error
component: service_object
symptoms:
  - "normalizeRepoUrl(\"foo .git\") returned \"foo \" — a suffix strip exposed the whitespace it was shielding"
  - "Output with trailing whitespace is not a fixpoint: the next call's input trim() moves the value again, breaking the documented idempotence contract"
  - "SQL twin migration 031 carries the identical chain shape with no re-trim — non-idempotent on URL-parseable inputs like \"https://x/y .git\""
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [property-based-testing, idempotency, normalizer, sql-ts-parity, fast-check]
---

# Learning: a suffix strip can expose the whitespace it was shielding — the first property-suite yield was a real SUT defect, and the SQL twin has the same shape

## Problem

PR #10624 (issue #10398, epic #10397 child 1) adopted property-based testing in the soleur monorepo. The very first run of the new idempotency suite (`apps/web-platform/test/lib/repo-url.property.test.ts`, fast-check `fc.assert` over generated `urlish` + whitespace-padded inputs) found a real defect in `apps/web-platform/lib/repo-url.ts::normalizeRepoUrl`:

```text
normalizeRepoUrl("foo .git") → "foo "   (trailing space)
```

The canonical-form pipeline was `trim() → lowercase scheme+host → strip trailing .git → strip trailing /`. A strip can expose whitespace that was *shielded* by the suffix: `"foo .git"` loses `.git` and ends in a space; `"x /"` loses `/` and ends in a space. Because the leading `trim()` already ran, the output carries trailing whitespace — so `f(f(x)) ≠ f(x)` (the second call's input `trim()` moves the value one more step). The header documented idempotence; the implementation did not deliver it.

**The SQL twin has the same shape.** `apps/web-platform/supabase/migrations/031_normalize_repo_url.sql` chains `trim → strip /+$ → strip (\.git)+$ → strip /+$` with no re-trim, and its header claims "Second run is `UPDATE 0`". For a URL-parseable input like `"https://x/y .git"` the chain produces `"https://x/y "` — so the `WHERE repo_url <> <normalized-expr>` guard fires again on re-run (idempotence claim falsified), and rows already backfilled by 031 can carry the trailing-whitespace form while the now-fixed TS normalizer produces the trimmed form. That is stored-vs-write-boundary divergence — the exact contract the 2026-04-22 parity learning was written about.

The example-based parity gate (`test/repo-url-sql-parity.test.ts`, `sqlNormalize031`) did not catch any of this — its hand-picked fixture set contains no whitespace-shielded suffix shape. Third drift instance between the same two implementations (see References).

## Solution

Step 5 added to `normalizeRepoUrl` (`lib/repo-url.ts`), committed in `27d21ce3f6` / sanctioned by review commit `0aed0f9f8b`:

```ts
// Re-trim: a `/` or `.git` strip can expose whitespace it was shielding
// ("foo .git" -> "foo ", "x /" -> "x "), and an output with trailing
// whitespace is not a fixpoint — the next call's input trim() would
// move the value again, breaking the documented idempotence contract.
working = working.trim();
```

The shrunk fast-check counterexamples are pinned as named regression fixtures (never `{ seed }` params in committed code — ADR-293 seed policy). The plan's Overview, AC14 allowlist, and tasks.md were amended in the same review round to admit the sanctioned SUT fix — the plan had asserted "no SUT changes" and the ticked verification was falsified by the fix itself.

## Key Insight

**Ordering-dependent normalizers have a re-normalization obligation at the end, not just the beginning.** Any pipeline of the shape `trim → strip suffixes` must ask "can a strip expose what the trim removed?" — whitespace shielded by a `.git` or `/` suffix is the minimal counterexample class, and an example-based fixture table has no reason to enumerate it. A generator that composes `urlish × suffix × padding` finds it on the first run because the defect lives at the intersection of two generators, not inside either one's happy path.

**A fix on ONE side of a declared byte-parity pair re-opens the parity debt on the other side.** The TS re-trim landed in this PR; the SQL twin and the rows it already wrote were deliberately NOT touched (migration edits post-apply are a separate ship surface). The follow-up must include **stored-row re-normalization**, not just a regex-chain patch — rows 031 already backfilled can carry `"https://x/y "`.

**"Already covered by the parity gate" is a claim about the gate's fixture set, not the property.** The deferred-item ruling ("`repo-url-sql-parity.test.ts` already owns the parity property") predated the defect discovery; the parity gate's example set never exercised the shielded-whitespace shape. When a ruling's premise is coverage, verify which input classes the cited gate actually generates.

## Prevention

1. **Normalizer pipelines: end with the operation you started with.** If step 1 is `trim()`, audit whether any later strip can re-expose trimmed material; if so the pipeline's last step is `trim()` again. Same for lowercasing, unescaping, delimiter-stripping — the invariant is "output is a fixpoint of every stage's input normalization".
2. **Idempotence properties should compose generators at the strip boundary**, not just the raw string domain: `urlish × {"/", ".git", ".git.git", " ", "\t"} × padding` is what surfaced this — a flat `fc.string()` domain spends its budget elsewhere.
3. **TS↔SQL twins: when the TS side changes, sweep the SQL chain AND the stored data.** A migration that already ran has *two* consumers — future re-runs (idempotence) and rows written under the old shape (re-normalization). File the follow-up with both halves named explicitly.
4. **A ruling premised on "X already covers it" needs the coverage enumerated.** Name the input classes the cited test generates; a fixture set is a finite list and the class it misses is exactly the class a property suite exists to find.

## Session Errors

See the paired harness-defect learning (`../test-failures/2026-10-20-generated-input-oracle-extraction-window-and-bash-random-outvar.md`) for the instrument-side errors. The doc-fidelity drift specific to this fix:

1. **Plan Overview asserted "no SUT changes"; AC14's allowlist omitted `lib/repo-url.ts`; tasks.md 6.2 was ticked on a non-empty grep.** The sanctioned SUT fix falsified three plan-surface statements in one stroke; review (code-quality-analyst, git-history-analyzer) caught it as P2 doc-fidelity drift. Recovery: `0aed0f9f8b` admitted the fix in all three sites. **Prevention:** when an in-flight plan declares "no SUT edits", a discovered-defect fix must sweep the plan's Overview, allowlist ACs, and ticked checkboxes — the three surfaces that assert *delivery*, not intent.
2. **Pre-existing stray comment `/* #9815 e2e probe — REVERTED BEFORE COMMIT */` at repo-url.ts EOF** — review wontfix'd as pre-existing-on-main polish. Noted so it is not re-flagged next session.

## References

- PR #10624 (draft); issue #10398; epic #10397 child 1
- ADR-293 (`knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md`) §"First yield" — records the defect and the SQL-twin follow-up
- **Prior instance:** `knowledge-base/project/learnings/best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` — the same `normalizeRepoUrl` ↔ `031_normalize_repo_url.sql` pair drifted twice already (order-of-operations `.git` vs `/`; single-`\.git$` vs `(\.git)+$`). That learning's "two implementations of the same function WILL drift" claim is now measured three times.
- Parity gate: `apps/web-platform/test/repo-url-sql-parity.test.ts` (`sqlNormalize031` JS port of the 031 chain)
- Resolved by #10633 (migration `163_renormalize_repo_url.sql` + `verify/163`): the SQL twin re-trim and the stored-row re-normalization. Findings beyond this learning: 031 had two more divergences (D2 the strip was not interleaving-complete, D3 `trim()` removed only U+0020); the issue's own example `https://x/y .git` is `https://x/y%20` in TS, so path-position whitespace is out of the parity domain; and 031's immutability forced a new migration rather than an edit, with an eligibility guard so the backfill only writes values the TS normalizer agrees with.
