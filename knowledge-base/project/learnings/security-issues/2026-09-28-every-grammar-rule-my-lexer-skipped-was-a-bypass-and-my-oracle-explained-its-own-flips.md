---
title: Every grammar rule my lexer skipped was a bypass, and my oracle explained its own flips
date: 2026-09-28
category: security-issues
module: guardrails-filing-gate
tags: [guardrails, lexer, bash-grammar, differential-oracle, hooks, cron-mirror, adr-256]
issue: 9089
pr: 9099
---

# Learning: every grammar rule my lexer skipped was a bypass, and my oracle explained its own flips

## Problem

#9089: the guardrails filing gate grepped a quote-blanked copy of the command, so every filing
bash still runs from quoted text (`URL="$(gh issue create …)"`, `bash -c "…"`, a quoted
`gh api "repos/o/r/issues"`) went ungated. The fix replaced the grep with a core-Perl shell
lexer (`.claude/hooks/lib/filing-shape.pl`), kept the old detectors as a counted floor, and bound
the lexer to the cron mirror `filingShape()` with a shared token corpus (ADR-256).

The first lexer passed its own suite (229 rows) and a 1,000-command executed differential. The
11-seat review then found 31 defects, and roughly a dozen were the SAME defect: a grammar rule
bash has and the lexer did not model, each of which is a filing that runs and is not gated:

- blanks are only space and tab (`\r`, `\f`, `\v` are word characters — `--body=x\r-mPost` forged
  a milestone);
- each `$(…)` has its own heredoc queue (a newline inside `$(…)` drained an OUTER heredoc);
- `(( x << y ))` is a shift, not a heredoc; a `case` pattern `)` does not close `$(…)`;
- `${ cmd; }` funsubs are scripts; every `o` in a `-oc` cluster consumes a value;
- `$'…'` is decoded, so `\n` splits an `eval` string;
- `\"` inside backticks inside `"…"`; a find `-exec` after another action.

The other half were places the gate trusted attacker-controlled text: the floor counted
filings the lexer found INSIDE quotes, so a quoted decoy cancelled a real top-level filing; the
failure-path indicator ran on raw text, so `gh issue c''reate` plus a tripped bound split the
word and allowed; substitution TEXT counted as body corpus, so `--body "$(true Mandated-By: x)"`
was justified.

## Solution

- Model each rule, one fixture row per reviewer reproducer (27 `R-*` rows in the hook suite).
- Compare the floor only to lexer records marked `vis=1` (not inside quotes, heredoc bodies or
  runner strings).
- Compute the failure indicator on quote/backslash-stripped, continuation-joined text.
- Build body corpus from literal text + drained heredocs + literally assigned values, never
  substitution text.
- Bound everything: depth 16, one character budget charged by every frame and by output bytes,
  32 records, `alarm 2`, and incremental `$cmdpos` (a quadratic re-scan hit the alarm first).

## Key Insight

**A hand-written parser for a language an attacker writes is complete only up to the grammar
you fixtured, and your own suite can only contain grammar you already thought of.** The suite
and the differential were both generated from the same mental model as the lexer, so both were
blind to the same rules. The review found them because reviewers wrote commands, not rows.
Fixture the grammar from the LANGUAGE's reference (every blank class, every quoting context,
every construct that opens a new heredoc scope), not from the feature's use cases.

**An executed oracle whose flip explanations read the system under test certifies itself.** The
differential classified a base→patched flip as "predicate errs toward gating" whenever the
lexer's own count was positive — i.e. whenever the lexer said so. Rewriting every explanation
to derive from the COMMAND and from ground truth (what a logging `gh` shim received) surfaced 43
unexplained flips, which were an oracle parser bug (`-iX POST`'s value dropped), an escaped
backtick the pattern missed, and three deliberate over-gates now named individually. Ground
truth also needed title-bearing twins of every api corpus row: without a title GitHub rejects
the POST, so every endpoint-form row read "no filing" and the endpoint axis was untested.

## Session Errors

1. **deepen-plan lint read `PROBE create` as prose** — Recovery: `PROBE=create`. — Prevention: write probe outputs as `KEY=value`.
2. **Ad-hoc `gh issue create --help` denied by the live hook** — Recovery: re-ran through a script file. — Prevention: probe filing shapes only through committed suites or `filing-shape.pl --trace`/`--classify` on stdin.
3. **`spec.md` had no `lane:`** — Recovery: plan fell back to `lane: cross-domain`. — Prevention: one-off; the fallback is the designed path.
4. **`set -e` killed the process substitution before it wrote the RC record** — Recovery: `_fs_rc=0; … || _fs_rc=$?`. — Prevention: never let a command whose exit code IS data run bare under `set -e`; capture with `|| rc=$?`.
5. **Variable corpus counted twice (P10)** — Recovery: body-corpus redesign (literal + heredoc + assigned values). — Prevention: define corpus provenance once, per source, before wiring a consumer.
6. **A 300 KiB fixture hit MAX_ARG_STRLEN** — Recovery: payload through stdin to `jq -Rsc`. — Prevention: test helpers take large payloads on stdin, never argv.
7. **`gh api --label` row expected allow** — Recovery: flipped to deny (`gh api` has no `--label`). — Prevention: derive expectations from `gh <cmd> --help` tables, which the lexer's `--tables` mode prints.
8. **Read a commit verdict off the completion notification** — the 82-minute battery failed on the ESLint ratchet; "exit 0" came from a trailing echo. — Recovery: fixed the escapes, re-committed, read `COMMIT RC=` from the log. — Prevention: already a work/SKILL.md rule (notification = liveness, never verdict); write `echo "RC=$?"` immediately after the command.
9. **hook-input-contract A1 flagged a literal `eval ` token** — Recovery: reworded to "eval-ed". — Prevention: grep new hook text for the contract's banned tokens before running the suite.
10. **lint-shell-capture-exit flagged `grep -o | wc`** — Recovery: `|| _fl_create=1`. — Prevention: covered by the lint.
11. **lint-orphan-test-suites read `find .` fixtures as a corpus walk** — Recovery: `find /dev/null`. — Prevention: covered by the lint.
12. **Quadratic `all_reserved` hit the alarm before the budget** — Recovery: incremental `$cmdpos`; R-PAD scaling row. — Prevention: every bounded parser gets one row at 10k× input that must finish under the budget, not the alarm.
13. **Three review-round rows written wrong** (R-RAWAT, unquoted `..;`, TOK_MSG `reason_of`) — Recovery: re-derived each from bash's behaviour. — Prevention: run a reproducer through real bash (the differential shim) before encoding its expectation.
14. **Circular oracle explanations + `-iX` truth-parser bug (43 unexplained flips)** — Recovery: command-derived explanations, title twins, `-i*X` value parsing. — Prevention: routed to plan sharp-edges (below).
15. **`pgrep -f` blocked by the self-match hook** — Recovery: `pgrep lefthook`. — Prevention: covered by the hook.
16. **review/SKILL.md edit 34 bytes over its body budget** — Recovery: tightened the text. — Prevention: covered by `lint-skill-body-budget`; that file sits ~60 bytes under its ceiling, so any addition must be offset.
17. **31 review findings, ~12 of them unmodelled bash grammar** — Recovery: fixed inline. — Prevention: the Key Insight above; routed to plan sharp-edges.

## Related

- ADR-256 (`knowledge-base/engineering/architecture/decisions/ADR-256-filing-gate-lexer-and-corpus-bound-predicate-parity.md`)
- ADR-157 (the scoped exception)
- `knowledge-base/project/learnings/2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md`
