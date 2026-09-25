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

- 2.1 Create `plugins/soleur/test/fixtures/preflight-check-10/11-quoted-inline-scalars.md`: 17
  unfenced `## Observability` sections, each with a `# case: <ID>` line, per the plan's fixture
  table. The file is ASCII only. Check the backslashes with `od -c`.
- 2.2 Create `plugins/soleur/test/fixtures/preflight-check-10/12-empty-quoted-command-with-fence.md`
  with the plan's exact bytes: the YAML is **unfenced**, and a fenced `printf LAUNDERED` follows
  (a fenced YAML block makes the row vacuous).
- 2.3 In `plugins/soleur/test/preflight-discoverability-test.test.ts`:
  - 2.3.1 Add a module-level, ID-keyed fixture loader that registers each section through `reg(id, "both", …)`.
  - 2.3.2 Hoist the #7453 slicer to module scope and add the normalize-fence slicer (anchors resolved through `uniqueIndex`).
  - 2.3.3 Add the "#8102 quoted inline scalars" describe:
    - Q template rows.
      - The expected value comes from `Bun.YAML`, parsed inside each test, with one clip-LF dropped for `|` only.
      - Otherwise it comes from the key-pinned, rule-derived `DEVIATIONS` map: NEG-LF, NEG-MISMATCH, NEG-EMPTY, NEG-UNTERMINATED.
      - The failure message names `.bun-version`.
    - The Q-ids set row.
    - E template rows.
      - Assert both the decoded value and parity with the mirror, `rc === 0`, and stderr exactly equal to `CHAIN_DONE`.
      - Build the environment with `gitCleanEnv({CLAUDE_PLUGIN_ROOT: <worktree>/plugins/soleur})`.
      - Use one `mkdtemp` directory per test, removed in `finally`.
    - The E-fence row, asserting the literal `$CMD === '""'` and no `LAUNDERED`.
    - Permanent twins:
      - (i) An awk copy with `cq < 2` makes fixture 12's `$CMD` contain `LAUNDERED`.
      - (ii) Injecting the #8149 `case` into the normalize slice turns NEST into `printf 200`.
    - A P2 known-divergence row for U+2028 after the closing quote (inline, not in the fixture).
    - The `parseExpected` scope row for DQ2.
  - 2.3.4 Replace F1d with the no-`CMD=`-reassignment scan, from the normalize anchor to `DT_OUT=`.
    - Use the unanchored `/(^|[^A-Za-z0-9_$])CMD\+?=/g` and count matches: exactly 3.
    - Also reject `read … CMD`, `printf -v CMD` and `declare`/`local`/`export CMD=`.
  - 2.3.5 Use test names with no quote or backslash characters.
- 2.4 Run the suite and confirm the RED set matches the plan's Implementation Phase 1. E NEST is GREEN on `main`, and that is expected.

## 3. GREEN

- 3.1 `plugins/soleur/skills/preflight/scripts/parse-form-a.awk`:
  - Add `yaml_inline_scalar()` and call it from the inline rule.
    - It uses a closing-quote scan. After the quote, only `[ \t\r]*` or `[ \t\r]+#…` may follow, and an empty body is left unchanged.
    - POSIX awk only, with no `[[:space:]]` inside the function.
    - **Never name a local `close`**: it is an awk builtin.
  - Update the header comment. Keep the rule order unchanged.
- 3.2 `plugins/soleur/test/lib/discoverability-test-parser.ts`:
  - Add `decodeQuotedScalar(): string | null`, built from the plan's anchored DQ and SQ regexes, each followed by a single-pass `replace`.
  - Wire it in as `decodeQuotedScalar(raw) ?? raw.trim()`, where `raw` is the **untrimmed** capture.
  - Correct the `stripQuotes` comment. Leave its behaviour unchanged.
- 3.3 `plugins/soleur/skills/preflight/SKILL.md` (Check 10 Step 10.4 only):
  - Add the "inline quoted" Form A table row stating the contract.
  - Delete the #8149 normalize-block strip and its comment.
  - Add the 3-line comment: decoding happens in the parser, the blocks are executed verbatim by tests, and SKILL.md and the awk must resolve from the same plugin root.
  - Update the "parity harness only compares the GATE" lead-in.
- 3.4 Delete the "P2 known divergence — inline quote stripping" test. Keep the CRLF P2 row.
- 3.5 Run under gawk and mawk (`docker run ubuntu:24.04` provides mawk 1.3.4). Every fixture row must be byte-exact (AC1, AC2).

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
- 5.2 Comment on #7403 (AC10).
  - Its trigger (b) fired with #8102 and #7548; request re-triage.
  - Name the deliberate YAML deviations: `\n` passes through, and `""` / `''` stay literal.
