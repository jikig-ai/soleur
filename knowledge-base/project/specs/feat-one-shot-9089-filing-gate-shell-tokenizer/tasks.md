# Tasks: fix(hooks): the filing gate sees filings inside substitutions, `bash -c` and quotes

Plan: `knowledge-base/project/plans/2026-09-28-fix-filing-gate-shell-tokenizer-substitution-plan.md`.
Issue: #9089. Row IDs (D*, P*, F*, C*) and guard rows (G*) refer to the plan.

## Phase 0a: Corpus and cron tests first (cherry-pickable with Phase 1)

- [x] 0a.1 Create `.claude/hooks/lib/filing-shape-corpus.json`:
  - at least 80 rows, plus a `_doc` element;
  - all three classes;
  - every AC4 spelling, including `$E-X POST`, `repositories/<id>`, a `..` segment and
    `"$B/issues"`.
- [x] 0a.2 Create `apps/web-platform/test/server/inngest/filing-shape-corpus-parity.test.ts`:
  - read the corpus with `readFileSync`, resolved from `import.meta.url`;
  - count executed rows with `ran++`, asserted in `afterAll` against a literal floor;
  - require all three classes among the asserted rows;
  - register the file in `apps/web-platform/test/repo-wide-suites.ts`.
- [x] 0a.3 Add vitest rows:
  - the `--input` refusal and its reorder row;
  - a `decide()` dot-segment deny (G3-9);
  - the two `decide()` pins for `$(…)` and `bash -c`;
  - a deny-marker `#fragment` row.

## Phase 0b: Hook tests first

- [x] 0b.1 Pin gh's version (2.101.0) and the value-taking flag tables from `--help`.
- [x] 0b.2 Create `.claude/hooks/lib/filing-shape.test.sh`:
  - a header saying where each kind of row belongs;
  - corpus parity, with an executed-row counter;
  - lexer-record rows, with an exit-0 and `OK` assertion for every P-row;
  - bounds rows that assert `bound=<cause>`;
  - `perl -c`;
  - a flag-table staleness row, intentionally RED until Phase 3;
  - the `--probe` mode (prints `PROBE=create`) and the `--differential` mode.

  Shim rows use a sandbox copy of the hook tree. Never shim `perl` on `PATH`, and give each shim a
  marker file.
- [x] 0b.3 Add D, P and F rows to `.claude/hooks/guardrails.test.sh`, including D43-D54, F-empty and
  F-count2:
  - put each row ID in its assert label;
  - add `assert_reason` twins;
  - use `[base-deny]` tags per the plan;
  - rewrite the "quoted endpoints on both sides of &&" comment.
- [x] 0b.4 Make `decision_of` fail any non-F row that writes a `guardrails-filing-lexer-failure`
  incident.
- [x] 0b.5 Confirm RED against a scratch copy of the whole `4170460eea:.claude/hooks/` tree (AC2).

## Phase 1: Cron mirror and shared predicate

- [x] 1.1 In `cron-bash-allowlist-hook.mjs`:
  - export `ISSUES_COLLECTION_RE`;
  - implement `filingShape` per the predicate spec: POST_SIGNAL with `-i` clusters and the
    prefix-required `$` arm, root and group `--repo`/`-R` skipping, `issue new`, and `$`-only
    endpoints.
- [x] 1.2 In `filingJustificationReason`, add the `--input` refusal before exits 0 and 1, using the
  hook's refusal text.
- [x] 1.3 In `cron-filing-deny-marker.ts`, import `ISSUES_COLLECTION_RE`, delete `ENDPOINT_RE`, and
  cut the head at `[?#]`.
- [x] 1.3b In `decide()`, deny any `gh api` token with a `.`, `..` or `%2e` path segment. This
  closes the allowlist-prefix escape.
- [x] 1.4 Get vitest green (AC3). Keep these as the first commits so they can be cherry-picked
  (DC-1).

## Phase 2: `filing-shape.pl --classify`

- [x] 2.1 Implement `filing_shape` in Perl, following the plan's predicate spec.
  - Use `\z` anchors and `qr~…~` delimiters.
  - Match the V-prefix (`$E-X`) arms, `repositories/<id>`, dot-segments and partial expansions.
  - Layout: `use strict;` + `$^W=1`, data tables at the top, one sub per construct.
- [x] 2.2 The corpus passes on both sides.

## Phase 3: Lexer

- [x] 3.1 Build the recursive-descent lexer with a frame stack:
  - Quoting: `$'…'` ends honor `\\`/`\'`, and `$"…"` is treated like `"…"`.
  - Separators, and redirections including `<<<`.
  - In-place substitution recursion, never recursing into `${…}` text.
  - Comments.
  - A native heredoc queue.
  - A variable corpus (heredoc bodies plus assignment values).
  - A NUL byte in the input exits 2.
  - Unbalanced parens are never an error.
- [x] 3.2 Detect `gh` at any argv position, with basename normalization and the `find -exec` cut at
  `;`/`+`.
  - String runners: `bash|sh|zsh|dash|ksh` with a `c` cluster (skipping option values before or
    after the cluster), and `eval`.
- [x] 3.3 Build the per-filing field parser:
  - last-value-wins for single-valued flags;
  - `repo` normalization (strip scheme and host, lowercase the owner; a `$` value is never external);
  - `labels[]=` counts only on api field values;
  - `body=@…` becomes `bodyfile`;
  - `bodyvar` plus `varcorpus`.
- [x] 3.4 Add the bounds, each printing `bound=<cause>` on stderr:
  - depth 16;
  - one global character budget of 8 × input + 64 KiB, charged by every frame;
  - `alarm 2` with a `$SIG{ALRM}` handler that exits 3;
  - memoized re-lexing keyed on substitution source.
- [x] 3.5 Add the output modes: NUL records followed by `OK`, `--trace`, and `--probe`
  (`PROBE=<shape>`).
- [x] 3.6 Run `--differential` in miss-and-prose mode:
  - export `REPO`, `M`, `EP` and `QS`, and shim `doppler`;
  - truth is taken from the shim using gh semantics;
  - require 0 misses, 0 prose filings, and at least one truth filing per wrapper column.

  The flip table waits for Phase 5.

## Phase 4: Wire `guardrails.sh`

- [x] 4.1 Read records with a `while IFS= read -r -d ''` loop plus an appended `RC` record,
  parsing records by count.
- [x] 4.2 Add `_gate_one_filing`, fed by the fields, and delete `xargs -n1` and the three token
  loops. When `bodyvar` is set, the corpus is `varcorpus`, never `$COMMAND`.
- [x] 4.3 Keep the CLASS 1 grep and `_api_pl` as a counted union floor:
  - make `_api_pl` linear (find `gh\s+api\b` once);
  - comment both as the floor (AC8).
- [x] 4.4 Add the failure path, in this order:
  1. a floor-only hit denies, whatever the indicator says;
  2. exit 2 with the indicator denies with `TOK_MSG`;
  3. any other failure with the indicator asks; the kill switch turns this into allow plus an
     incident;
  4. otherwise allow.

  Compute the indicator with `grep -E` on continuation-joined text using `\bgh\b`. Emit one
  incident code, `guardrails-filing-lexer-failure`, with a cause enum and no payload. Put the
  decision table in a comment.
- [x] 4.5 Refusal texts: include the head, the ctx and the in-command clause, plus the prose hint
  and the absolute-path hint.
- [x] 4.6 Update the header comments that describe `$SCAN`-based detection.
- [x] 4.7 Run `guardrails.test.sh`, `hook-input-contract.test.sh` and `lint-shell-capture-exit.py`
  (AC1, AC7). Bump `MIN_ASSERTIONS` in the same commit.

## Phase 5: Record and verify

- [x] 5.1 Write ADR-256 (the ordinal is provisional; the base is ADR-255), covering:
  - lex-not-grep, plus a floor-removal criterion;
  - corpus-bound parity;
  - the scoped exception to ADR-157;
  - Codex/Devin `ask` support recorded as unverified;
  - the alternatives.

  Add a dated one-line pointer in ADR-157.
- [x] 5.2 Add one sentence to the `model.c4` Hook Engine description about the second
  implementation plus the corpus. Run `apps/web-platform/test/c4-code-syntax.test.ts`,
  `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.
- [x] 5.3 Run the full `--differential` with the flip table and put it in the PR body (AC5).
- [x] 5.4 Run `python3 scripts/lint-guard-contract.py` on the plan (AC10), and check that
  `--probe` prints `PROBE=create` (AC11).

## Phase 6: Ship

- [ ] 6.1 File the residual follow-up issue listing the Non-Goals, with the `meta/machinery` label
  and the `Post-MVP / Later` milestone.
- [ ] 6.2 File the issue for the quadratic `strip_command_bodies`, a hook-wide timeout bypass (12 s
  on 87 KB), with labels `type/security`, `domain/engineering` and `priority/p2-medium`.
- [ ] 6.3 Put `Closes #9089` in the PR body, link both issues, and render DC-1 through DC-5 from
  `decision-challenges.md`.
