# ADR-256 — The filing gate classifies filings with a shell lexer, bound to the cron mirror by a shared corpus

- **Status:** Accepted
- **Date:** 2026-09-28
- **Issue:** #9089
- **Related:** [ADR-157](./ADR-157-a-hook-that-cannot-parse-its-input-asks.md) (this ADR is a
  scoped exception to its "never denies"), [ADR-156](./ADR-156-hook-stdin-is-model-controlled-and-untrusted.md)
  (the command string is untrusted input), [ADR-216](./ADR-216-machinery-ledger-and-filing-time-lever.md) (the exits the
  gate enforces), `.claude/hooks/lib/filing-shape.pl`, `.claude/hooks/lib/filing-shape-corpus.json`,
  `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` (`filingShape`)

> **Ordinal.** Provisional; `origin/main`'s highest was ADR-255 on 2026-09-28. Re-verified at ship.

## Context

The interactive filing gate (`guardrails:require-milestone` and
`guardrails:require-filing-justification` in `.claude/hooks/guardrails.sh`) decided "is this a
filing?" by grepping `$SCAN`, a copy of the command with every quoted span and heredoc body blanked.
The blanking exists so a commit message that *mentions* `gh issue create` is not denied (#5192). It
also hid every filing bash still runs from quoted text: `URL="$(gh issue create …)"`,
`bash -c "gh issue create …"`, `gh api "repos/o/r/issues" -X POST …`. The anchored CLASS 1 grep
missed `$(`, `|`, `(`, `then`, `do` and every launcher prefix. Once a filing was detected, its exits
were read from the WHOLE command line, so `gh issue list --label meta/machinery && gh api …/issues`
was credited with a label no filing carried.

The cron containment hook's mirror, `filingShape()`, had the opposite problem: it tokenizes
properly and refuses substitutions outright, but missed five POST spellings (`-ftitle=`,
`-Ftitle=`, `-F=title=`, `--input=`, `-X=POST`) and the `#fragment` endpoint — a live bypass under
the `gh api repos/jikig-ai/soleur/` allowlist one cron holds.

## Decision

### 1. Lex, do not grep — with main's detectors kept as a counted floor

`.claude/hooks/lib/filing-shape.pl` (core Perl, no modules) is a recursive-descent lexer with a
frame stack. It models quoting, separators, redirections (including `<<<`), in-place substitution
recursion (`$(…)`, `<(…)`, backticks; substitutions inside `${…}` and `$((…))`), comments, a native
heredoc queue, `bash|sh|zsh|dash|ksh -c` and `eval` strings, and `gh` at any argv position. It emits
one NUL-framed record per filing with that filing's own fields, parsed with gh's value-taking flag
tables. Its grammar sketch, the gh version the tables came from, and the `--trace` debugging mode
are in the file header.

`guardrails.sh` unions the lexer's findings with main's CLASS 1 grep and `_api_pl` (made linear),
each counted per shape. The floor reads `$SCAN`, which blanks quotes and heredoc bodies, so it is
compared only with the lexer records marked `vis=1` (outside quotes, heredoc bodies and runner
strings) — otherwise a quoted decoy filing would offset a real top-level one. A shape whose floor
count exceeds that visible count denies. **The floor may
be removed only after `bash .claude/hooks/lib/filing-shape.test.sh --differential <base>` has run
clean — zero oracle misses, zero prose filings — on three consecutive filing-gate changes.**

### 2. Parity is a corpus-bound predicate spec, not shared code

The predicate ("create" / "api" / none over a dequoted token list) has three consumers:

- `filing_shape` in `filing-shape.pl` (the hook);
- `filingShape` in `cron-bash-allowlist-hook.mjs` (the cron mirror);
- the cron deny marker, which imports the mirror's `issuesEndpointToken` instead of copying it.

The Perl and JS copies are bound only by `.claude/hooks/lib/filing-shape-corpus.json`, which BOTH
`filing-shape.test.sh` and `apps/web-platform/test/server/inngest/filing-shape-corpus-parity.test.ts`
run under an executed-row floor. The vitest file is in the `repo-wide` project, so a diff touching
only `.claude/hooks/lib/` still runs the JS half. A new spelling goes into the corpus first.

### 3. A scoped exception to ADR-157's "never denies"

ADR-157 rules that a hook which cannot parse its input asks and never denies, because denying bricks
a session whose repair is itself a Bash call. This ADR carries that rule from the tool-call envelope
to the lexing of the command, with one exception:

| Lexer outcome | Decision |
|---|---|
| main's floor sees more filings than the lexer | **deny** — `TOK_MSG` when the cause is the agent's own unbalanced quoting, else "run the filing as a plain top-level command" |
| exit 2 (unbalanced quote, unterminated substitution, NUL) on a command matching the filing indicator | **deny** with `TOK_MSG` |
| | *The indicator is computed on the command with quotes and backslashes removed and continuations joined, so `gh issue c''reate` cannot split the word past it.* |
| a tripped bound, a crash or a truncated stream, on ANY command | **ask**, as ADR-157 prescribes. Not indicator-gated: a defeated lexer's text fallback cannot see a computed word (`$'\x69ssue'`, `is$(:)sue`) that only the lexer decodes, and only pathological input trips a bound |
| no perl on a filing-indicated command | **ask** |
| no filing indicator | allow |

The deny arms cover only commands that are filing-shaped, and their repair is never a filing — so
ADR-157's bricking concern does not apply to them. The ADR-157 clauses still hold on the ask arm:
the kill switch `SOLEUR_DISABLE_HOOK_INPUT_ASK=1` turns the ask into an allow, and the incident
`guardrails-filing-lexer-failure` carries only a cause enum (`exit2`, `depth`, `budget`, `alarm`,
`records`, `crash`, `noperl`, `trunc`, `floor-only`), never payload content. `records` is the
32-record cap; `crash` is any die inside the lexer, which is reported on stdout as `E\0crash\0`.

**Unverified:** `guardrails.sh` also runs under Codex (`.codex/config.toml`) and Devin
(`.devin/config.json`). Whether those harnesses honor `ask` has not been measured; see
[ADR-165](./ADR-165-what-ask-means-on-a-harness-with-no-ask-state.md) for what `ask` becomes where
there is no ask state.

## Consequences

- Every Bash command pays one more perl fork (measured +5-8 ms on a 69-76 ms hook). The lexer is
  bounded well inside the non-blocking 10 s hook timeout: depth 16, one global character budget of
  8 × input + 64 KiB charged by every frame (output bytes included), memoized re-lexing, at most
  32 records, and `alarm 2`.
- Deliberate over-fire: an unquoted `echo gh issue create`, `bash -c 'echo gh issue create'`,
  `man gh issue create` and `a=(gh issue create)` are classified as filings. Each errs toward gating.
- The Non-Goals (other filing routes such as GraphQL and `curl`, computed command words and
  aliases, expansion-time evaluation such as `${x@P}`, string runners beyond shells and `eval`
  including a pipe into a shell, stdin-completed `xargs`, and the `--body-file` read-time gap) are tracked in the residual follow-up
  issue filed at ship.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| `shfmt --to-json` | Rejected: not installed on operator hosts, and `-c` strings would still need re-parsing. A CI-only shfmt cross-check remains a follow-up option. |
| tree-sitter-bash | Rejected: mishandles heredocs inside `$(…)`, the every-commit shape. |
| `bashlex` | Rejected: unmaintained. |
| `bash -n` | Rejected: validates syntax, gives no argv. |
| `Text::ParseWords::shellwords` | Rejected — measured: splits neither `;` nor `$(`, and mangles `'it'\''s'`. |
| One shared implementation (the hook shells out to node) | Rejected: couples every Bash call to the web-platform module graph. |
| Amend ADR-157 alone | Rejected: the parity contract does not belong under ADR-157's title, and the fail direction is an exception to it, not an extension. |
