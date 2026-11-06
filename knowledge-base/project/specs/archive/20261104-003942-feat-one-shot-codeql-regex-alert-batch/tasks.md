# Tasks — feat-one-shot-codeql-regex-alert-batch

Plan: `knowledge-base/project/plans/2026-11-03-fix-codeql-regex-alert-batch-plan.md`

## Phase 1: Alert fixes

- [ ] 1.1 `scripts/lint-anthropic-content-position.py` — reword the
  `POSITIONAL` literal's line-35 trailing comment so it carries no
  `[...]`-shaped text (removes the `h-1` empty-range surface CodeQL's
  non-VERBOSE parse reads). Pattern text unchanged.
- [ ] 1.2 `apps/web-platform/test/no-network-fonts.test.ts:475` — anchor
  `weakened`:
  `/^https?:\/\/fonts\.googleapis\.com$|^https?:\/\/fonts\.gstatic\.com$/`.
- [ ] 1.3 `scripts/ci-pr-affected-replay.py:1771` — replace `QUOTE_CTL`'s
  `[\x00-\x08\x0a-\x1f\x7f]` with a programmatically enumerated class
  (C0 minus 0x09 TAB, plus 0x7f DEL) — byte-identical match set.

## Phase 2: Verification

- [ ] 2.1 `bash scripts/lint-anthropic-content-position.test.sh` green.
- [ ] 2.2 `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/no-network-fonts.test.ts` green (33 tests).
- [ ] 2.3 `python3` probe: `QUOTE_CTL.search` match set over bytes
  0x00–0xFF identical to the old class.
- [ ] 2.4 `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` green
  (rows covering ctl-byte quoting).

## Phase 3: Ship

- [ ] 3.1 PR body contains `Closes #9550` on its own line.
- [ ] 3.2 All commits authored by `Jean Deruelle
  <jean.deruelle@jikigai.com>` — never `devin-ai-integration[bot]`.
- [ ] 3.3 Learning captured at compound: CodeQL parses `re.VERBOSE`
  comments as pattern text — `# [x.y.length-1]` reads as class `[x-1]`
  with empty range `h-1`.
