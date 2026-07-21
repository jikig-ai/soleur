# Tasks — fix preflight Check 10 folded-scalar parser (#6772)

Derived from `knowledge-base/project/plans/2026-07-21-fix-preflight-check-10-folded-scalar-parser-plan.md`.

Phase order is load-bearing: contract (awk) → mirror (TS) → guard (parity harness).

## 1. Setup / preconditions

- [ ] 1.1 Re-derive the corpus census with regexes (do not trust the plan's approximate
      counts): count non-archive plans matching `^[[:space:]]*command:[[:space:]]*>[-+]?[[:space:]]*$`
      and `^[[:space:]]*command:[[:space:]]*\|[-+]?[[:space:]]*$`. Record actuals.
- [ ] 1.2 Re-read `plugins/soleur/skills/preflight/SKILL.md` Check 10 Steps 10.3–10.5 and
      `plugins/soleur/test/lib/discoverability-test-parser.ts` before editing either.
- [ ] 1.3 Confirm `plugins/soleur/skills/preflight/scripts/` exists or create it; confirm
      the `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` path pattern is used elsewhere in the plugin.

## 2. RED — fixtures before the fix

- [ ] 2.1 Add permissive fixtures: table-driven F1–F3 over `[">", ">-", ">+"]`, plus F4
      (single continuation line, no leading/trailing space).
- [ ] 2.2 Add restrictive fixtures: N1 (stops at sibling `expected_output:`), N2
      (continuation line starting `https://` not truncated), N5 (deeper-indented jq
      `key: value` inside the command not truncated), N3 (stops at the closing ``` of the
      YAML fence, and at column-0 prose).
- [ ] 2.3 Add non-shadowing fixtures: I1 (inline), B1 (block + sibling key), B2 (block
      joins with `\n`), B3 (`command: |-` enters block mode both surfaces), E1 (`>-` with
      no continuations returns empty, not `">-"`).
- [ ] 2.4 Run the suite. Confirm F1–F4, N1, N2, N5, B1 are RED against the unmodified
      parser, each for the right reason. **Capture the failure output verbatim** — this is
      the primary non-vacuity evidence for AC9.

## 3. Fix the production awk

- [ ] 3.1 Create `plugins/soleur/skills/preflight/scripts/parse-form-a.awk` with the
      program from plan §Phase 2: header comment (bash-wins contract, three scalar shapes,
      chomping not modelled), `indent()` helper, fold rule FIRST, block rule, inline rule,
      indent-aware shared terminator, fold/block continuation rules, column-0 exit, END.
- [ ] 3.2 Replace the inline awk in `SKILL.md` Step 10.4 with
      `awk -f "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/preflight/scripts/parse-form-a.awk" …`.
- [ ] 3.3 Update Step 10.4's Form A prose to name inline, block **and** folded shapes.
- [ ] 3.4 Verify: fold rule precedes inline rule (AC1, first-match capture); `>[-+]?`
      present (AC2). Do NOT strip indentation in block mode — explicitly rejected.

## 4. Mirror in TypeScript

- [ ] 4.1 `parseCommand()`: add the fold branch ahead of the inline match; widen the block
      header to `/^\s*command:\s*\|[-+]?\s*$/`; apply the indent-aware terminator to both
      multi-line modes; fold joins with `" "` and no trailing separator.
- [ ] 4.2 Align blank-line-inside-block to the awk (awk drops it; TS currently pushes `""`).
      bash wins per the file header.

## 5. Parity harness

- [ ] 5.1 Add the harness: for every Form-A fixture, run `parse-form-a.awk` via `Bun.spawn`
      and compare stdout (trailing newline trimmed) to `parseCommand(block)`.
- [ ] 5.2 Normalize block-mode leading indentation before comparison (awk preserves, TS strips).
- [ ] 5.3 Add P3: assert every harness fixture has a `command:` key and no competing fenced
      block — the harness runs Form A only, while `parseCommand()` falls back to Form B.
- [ ] 5.4 Assert the known inline-quote-stripping divergence **as a known difference**, so
      a change on either side reddens rather than silently passing.

## 6. GREEN + verification

- [ ] 6.1 Run `bash scripts/test-all.sh` from the worktree root. All green (AC10).
- [ ] 6.2 Sandbox mutation protocol for the six already-green pins (I1, N3, B2, B3, E1, P3):
      copy to sandbox + pristine backup, apply one mutation, `diff` to prove it landed, run,
      confirm the **named** test reddens, restore. Record the table (AC9).
- [ ] 6.3 AC11 corpus re-parse: run the fixed awk over the `## Observability` block of every
      non-archive plan matching `^[[:space:]]*command:[[:space:]]*[>|]`. Assert each parses
      non-empty, not a bare indicator, and free of `expected_output`. Report parsed count and
      changed-vs-pre-fix count. Derive counts from the regex, do not hardcode.

## 7. Follow-through

- [ ] 7.1 File tracking issue: flow-mapping shape `discoverability_test: { command: … }`
      (~7–13 plans currently FAIL state 3 honestly) (AC12).
- [ ] 7.2 File tracking issue: inline quote stripping divergence — TS strips, awk does not (AC12).
- [ ] 7.3 PR body: `Closes #6772`, Phase 1 RED output, mutation table, AC11 corpus report.
- [ ] 7.4 Confirm `decision-challenges.md` is rendered by `ship` into the PR body.
