# Tasks — fix(compound-promote): split `diff-underivable` by emit site and carry `detail` into the outcome marker

Derived from
`knowledge-base/project/plans/2026-09-20-fix-compound-promote-diff-underivable-enum-split-plan.md`
**after the deepen pass**. Issue: #8427. Branch:
`feat-one-shot-8427-diff-underivable-enum-split`.

Rows in the suites are named by `it(` title or fixture literal, never line number —
this change moves every line in the files it edits.

## 1. Setup

- [ ] 1.1 Read `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
      in full (`hr-always-read-a-file-before-editing-it`): `DiffPathVerdict`,
      `checkDiffPaths()`, `safeDetail()`, `spawnGitCapture()`, `ClusterOutcome`, the
      `refusalDetail` accumulator and its single push site, and the two sibling sinks
      at the `diff-path-refused` branch.
- [ ] 1.2 Read `apps/web-platform/server/compound-promote-marker.ts` in full — note
      the spread order and the bare fail-open `catch`.
- [ ] 1.3 Read the three suites that pin this file's source text, plus
      `apps/web-platform/lib/safety/redaction-allowlist.ts` (marker strings and the
      `\b`-anchored `API_KEY_RE`).
- [ ] 1.4 Record the three pinned texts that must stay byte-identical: the step
      callback signature, the `await checkDiffPaths(cluster.proposed_diff_unified`
      call, and `'return { kind: "refused", reason: "diff-size-exceeded" };'`.

## 2. Tests first (RED)

### 2.1 Guard 2 — the empty arm

- [ ] 2.1.1 Re-base the `row 9 (dispatch)` row: its fixture is the empty string, so
      it asserts `empty`; amend the title. Do not delete it.
- [ ] 2.1.2 Add whitespace rows (spaces-only, two-newline, tab-space-CRLF). At least
      one non-empty whitespace fixture is required by Guard 2 matrix row 4.
- [ ] 2.1.3 Must-PASS row: two leading blank lines then a real `@@` hunk — asserts it
      is not refused as `empty` **and** that derivation proceeds (applies rc 0,
      yields a real `diff-index` record).
- [ ] 2.1.4 Harness row: the emptiness fixture set contains at least one non-empty
      whitespace-only string.

### 2.2 Guard 1 — emit-site attribution

- [ ] 2.2.1 Update the `row 2` row (fixture `"not a diff at all"`) to
      `underivable-apply`.
- [ ] 2.2.2 `underivable-read-tree` row using a `git init -q` fixture repo with **no
      commit** (measured: `read-tree HEAD` fails with `fatal: Not a valid object
      name HEAD`).
- [ ] 2.2.3 `underivable-empty-pathset` row using the **measured** edit-then-revert
      double patch in plan AC5a, with the positive control (first half alone yields
      `ok: true, paths: ["AGENTS.rules.md"]`) in the same row.
- [ ] 2.2.4 Build the PATH-shim helper: a temp dir prepended to `process.env.PATH`
      inside one `it()` and restored in `finally`; the shim `exec`s real git for
      `read-tree`/`apply` and fabricates only `diff-index` stdout.
- [ ] 2.2.5 Two `underivable-unparsable-record` rows via the shim — one for the
      `!meta.startsWith(":")` site, one for the five-field site. Separate rows,
      because the two sites share a literal.
- [ ] 2.2.6 Build the **AST** census in
      `cron-compound-promote-outcome-census.test.ts` using the installed `typescript`
      package: collect the union's declared literals and every `ok: false` return's
      `reason` initializer inside the `checkDiffPaths` declaration. **Compare by
      site-keyed multiset, not by set.**
- [ ] 2.2.7 Census mutation rows: declared-but-unemitted; zero `ok: false` returns
      found must throw; one of the two shared-literal sites changed alone; the
      three comment spellings (asterisk-continuation, single-line `/* */`, trailing
      `//`) leave the result unchanged; a `refuse()` hoist stays GREEN.
- [ ] 2.2.8 Harness rows: a hard-coded declared side reddens a harness-integrity row;
      a return split across three lines still PASSes.
- [ ] 2.2.9 Per-site mutation loop (rows 1a–1f), one mutant per site — not one row
      standing in for six.

### 2.3 `diffShape()`

- [ ] 2.3.1 Rows for `fenced` and `headerPair` separating the three inputs that can
      still reach the apply arm; `len` separating empty from whitespace-only.
- [ ] 2.3.2 A row asserting `diffShape()` returns no substring of its input.
- [ ] 2.3.3 A 1 MB input row asserting bounded completion.

### 2.4 Guard 3 — the marker boundary

- [ ] 2.4.1 Redaction row plus the companion asserting the unredacted fixture
      contained the shape.
- [ ] 2.4.2 Cap-after-redaction row with the **computed** fixture (twelve short
      addresses: assert 97 before / 203 after as their own expectations).
- [ ] 2.4.3 Producer-truncation straddle row: token preceded by a **non-word
      character**, starting at character 180, asserting 16 real token characters leak
      when a producer cut is restored.
- [ ] 2.4.4 C1 row (U+0085 must not reach the row raw).
- [ ] 2.4.5 Path-classification rows: unrecognised path emits `[unclassified-path]`;
      learnings path and SKILL.md path emit `<matched-prefix>/[elided]`.
- [ ] 2.4.6 Per-entry totality row (two entries, offending shape in the second).
- [ ] 2.4.7 Absent-detail row: an entry with no `detail` emits **no** `detail` key.
- [ ] 2.4.8 Unmodelled-extra-key row: the key does not reach the emitted row.
- [ ] 2.4.9 Fail-open row: one malformed entry degrades to `{cluster_hash, reason}`
      and the marker is still emitted.
- [ ] 2.4.10 Size row: 20-entry worst-case fixture asserts
      `JSON.stringify(row).length < 10000` and the degradation flag.
- [ ] 2.4.11 Must-PASS row: `error: corrupt patch at line 3` byte-identical.
- [ ] 2.4.12 Body-leak row (behavioural): 40-character marker line in the diff body;
      `verdict.detail` shares no 20-character substring with it.
- [ ] 2.4.13 Source row: `detail: pathVerdict.detail` (bare) occurs zero times.

## 3. Implementation

### 3.1 `checkDiffPaths` and the producer

- [ ] 3.1.1 Widen `DiffPathVerdict["reason"]` to the eight values.
- [ ] 3.1.2 Add the emptiness check as the **first** statement in the function body.
- [ ] 3.1.3 Replace the six `reason: "underivable"` literals with their site values.
- [ ] 3.1.4 Split `safeDetail` into `stripControl(s)` (strip only, **no** truncation)
      and `safeDetail = (s) => stripControl(s).slice(0, 200)`. Widen the strip class
      to include C1. `verdict.detail` carries the `stripControl` form.
- [ ] 3.1.5 Raise `spawnGitCapture`'s stderr accumulator to 64,000 and make it
      deterministic (`stderr = (stderr + chunk).slice(0, 64_000)`).
- [ ] 3.1.6 Fix the two sibling sinks: remove `detail` from the `diff-path-refused`
      ctx-logger line; pass `safeDetail(pathVerdict.detail)` to the Sentry `extra`.
- [ ] 3.1.7 Add the co-moving-artifact comment above `DiffPathVerdict`
      (`cq-cite-content-anchor-not-line-number`).

### 3.2 Shape and transport

- [ ] 3.2.1 Add and export `diffShape()`; `const head = diff.slice(0, MAX_DIFF_BYTES)`
      as the first statement; `len` from the untruncated diff; the three prescribed
      non-catastrophic predicate forms.
- [ ] 3.2.2 Widen `ClusterOutcome`'s refused variant with `detail?` and the four flat
      shape fields. Verify the step-callback signature text is byte-unchanged.
- [ ] 3.2.3 Return `detail` and the shape fields at the `!pathVerdict.ok` branch
      **without reformatting** the pinned call-site text; widen the
      `reportSilentFallback` `extra` with the four shape fields (second transport).
- [ ] 3.2.4 Extend `refusalDetail.push(...)`, keeping it outside the memoized
      callback.

### 3.3 Marker sink

- [ ] 3.3.1 Widen the `refusal_detail[]` element type (flat keys).
- [ ] 3.3.2 Rewrite the doc comment: new contract, transform order, cap asymmetry.
- [ ] 3.3.3 Build the transformed array **before** the `try`; rebuild each entry by
      **destructuring** the known fields (never spreading); omit `detail` when absent;
      degrade a bad entry to `{cluster_hash, reason}`.
- [ ] 3.3.4 Apply strip → redact → classify → surrogate-safe 200-char cap, using a
      **function replacement** for the path classification.
- [ ] 3.3.5 Move `SOLEUR_COMPOUND_PROMOTE_OUTCOME: true` and `fn:` to **after** the
      `...outcome` spread.
- [ ] 3.3.6 Add the serialized-size budget with deterministic degradation and a flag.

## 4. Probe, docs, register, verification

- [ ] 4.1 Write `scripts/checks/compound-promote-reason-sites.sh`: multi-line
      tolerant, exact set identity, prints only `COMPOUND_PROMOTE_REASON_SITES_OK`.
- [ ] 4.2 Runbook prose: rewrite the two now-false claims; list the five split values
      and `diff-empty`; state that `diff-empty` does not carry the
      `diff-underivable` prefix; document the shape fields.
- [ ] 4.3 Runbook jq recipe: add the **pinned** flatten expression as one `@tsv`
      column plus a worked sample line; add the docs-suite row asserting the fenced
      block contains `refusal_detail`.
- [ ] 4.4 Amend PA-8 `(c)` and its retention limb (journald as a third at-rest copy).
- [ ] 4.5 Run the targeted suites:
      `cd apps/web-platform && ./node_modules/.bin/vitest run --project repo-wide test/server/inngest/cron-compound-promote-allowlist.test.ts`
      plus the census and marker suites.
- [ ] 4.6 Ratchet half (a): every `run_suite` row with no path argument
      (`grep -nE 'run_suite "[^"]+" (bash|python3|bun|npx) [^ ]+$' scripts/test-all.sh`).
- [ ] 4.7 Ratchet half (b): `bash scripts/test-all.sh --print-suite-globs`, then
      `eval ls <glob>` and run the census-shaped suites.
- [ ] 4.8 Re-measure after any ratchet fix — satisfying one can move another.
- [ ] 4.9 Confirm `python3 scripts/lint-guard-contract.py` exits 0 with three guard
      entries from the plan file.
- [ ] 4.10 Run the probe and confirm it prints exactly the single token.

## 5. Ship

- [ ] 5.1 PR body uses `Closes #8427` (not the title).
- [ ] 5.2 PR body states the D1 compatibility choice, including that `diff-empty` is
      a deliberate reclassification a saved `diff-underivable` query stops matching.
- [ ] 5.3 PR body carries both ratchet-half verdicts as pasted terminal output.
- [ ] 5.4 PR body renders `decision-challenges.md` (UC-1, UC-2/UC-2a, T-1) and files
      the `action-required` issue.
