---
title: "Tasks — fix(preflight): Check 10 decodes YAML quoted-scalar escapes"
branch: feat-one-shot-8102-check10-yaml-quote-escapes
plan: knowledge-base/project/plans/2026-09-25-fix-check10-yaml-quoted-command-escapes-plan.md
lane: cross-domain
closes: [8102, 7548]
---

# Tasks

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## 1. Setup

- 1.1 Re-read the plan's §Decode contract and §Files to Edit.
- 1.2 Confirm mawk is available for AC1: an installed `mawk` or a container.

## 2. RED (tests first, `cq-write-failing-tests-before`)

- 2.1 Create `plugins/soleur/test/fixtures/preflight-check-10/11-quoted-inline-scalars.md`: 13
  unfenced `## Observability` sections, each with a `# case: <ID>` line, per the plan's fixture
  table. Check the backslashes with `od -c`.
- 2.2 Create `plugins/soleur/test/fixtures/preflight-check-10/12-empty-quoted-command-with-fence.md`:
  `command: ""` followed by a fenced `printf LAUNDERED`.
- 2.3 In `plugins/soleur/test/preflight-discoverability-test.test.ts`:
  - 2.3.1 Add a module-level, ID-keyed fixture loader that registers each section through `reg(id, "both", …)`.
  - 2.3.2 Hoist the #7453 slicer to module scope and add the normalize-fence slicer (anchors resolved through `uniqueIndex`).
  - 2.3.3 Add the "#8102 quoted inline scalars" describe:
    - Q template rows (expected value from `Bun.YAML`, or from `DEVIATIONS` for NEG-LF, NEG-MISMATCH and NEG-EMPTY). The failure message names `.bun-version`.
    - The Q-ids set row.
    - E template rows, asserting both the decoded value and parity with the mirror.
    - The E-fence row.
    - The `parseExpected` scope row for DQ2.
  - 2.3.4 Replace F1d with the no-`CMD=`-reassignment scan (from the normalize anchor to `DT_OUT=`).
  - 2.3.5 Use test names with no quote or backslash characters.
- 2.4 Run the suite and confirm the RED set matches the plan's Implementation Phase 1.

## 3. GREEN

- 3.1 `plugins/soleur/skills/preflight/scripts/parse-form-a.awk`:
  - Add `yaml_inline_scalar()` (POSIX only; minimum length 3) and call it from the inline rule.
  - Update the header comment. Keep the rule order unchanged.
- 3.2 `plugins/soleur/test/lib/discoverability-test-parser.ts`:
  - Add `decodeQuotedScalar()` (ASCII trim; single-pass regex per quote style) and wire it into `parseCommand`'s inline path.
  - Correct the `stripQuotes` comment. Leave its behaviour unchanged.
- 3.3 `plugins/soleur/skills/preflight/SKILL.md` (Check 10 Step 10.4 only):
  - Add the "inline quoted" Form A table row stating the contract.
  - Delete the #8149 normalize-block strip and its comment.
  - Add the 3-line "decoded in the parser; executed verbatim by tests" comment.
  - Update the "parity harness only compares the GATE" lead-in.
- 3.4 Delete the "P2 known divergence — inline quote stripping" test. Keep the CRLF P2 row.
- 3.5 Run under gawk and mawk. Every fixture row must be byte-exact (AC1, AC2).

## 4. Verification

- 4.1 Mutation: re-add the #8149 strip. E `NEST` must go RED. Record the line.
- 4.2 Mutation: set the awk minimum length back to 2. Q `NEG-EMPTY` and E-fence must go RED. Record the line.
- 4.3 RED-first on `origin/main`'s awk and SKILL.md (scratch copy): E fails on DQ1 (AC5).
- 4.4 Regenerate `plugins/soleur/test/fixtures/check10-test-manifest.txt` with `LC_ALL=C sort -u`.
- 4.5 Ratchet `MIN_TESTS`, `MIN_ASSERTIONS` and `MIN_MANIFEST_LINES` in `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` to the measured values, then run it (AC7).
- 4.6 `bun test plugins/soleur/test/preflight-discoverability-test.test.ts plugins/soleur/test/observability-schema-parity.test.ts` (AC8).
- 4.7 `git diff origin/main...HEAD -- plugins/soleur/skills/preflight/SKILL.md`: hunks only in Step 10.4 (AC9).

## 5. Ship

- 5.1 The PR body carries `Closes #8102` and `Closes #7548`, the two recorded mutation lines, and DC-1 from `decision-challenges.md`.
- 5.2 Comment on #7403: its trigger (b) fired with #8102 and #7548; request re-triage (AC10).
