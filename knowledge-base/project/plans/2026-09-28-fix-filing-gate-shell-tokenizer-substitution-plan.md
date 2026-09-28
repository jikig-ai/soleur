---
title: "fix(hooks): filing gate classifies filings with a shell lexer (substitution, bash -c, quoted endpoints) and closes filingShape() spelling gaps"
date: 2026-09-28
slug: fix-filing-gate-shell-tokenizer-substitution
branch: feat-one-shot-9089-filing-gate-shell-tokenizer
issue: 9089
closes: 9089
type: bug
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(hooks): the filing gate sees filings inside substitutions, `bash -c` and quotes

## Enhancement Summary

**Deepened on:** 2026-09-28 (revision 4).

**Halt gates:**

- 4.6 User-Brand Impact: pass.
- 4.7 Observability: two proxy findings on the new block, both fixed or argued down in the plan.
- 4.8 PAT: no match.
- 4.9 UI wireframe: not a UI plan.
- 4.10 Encryption: no new store or connection.
- 4.11 Guard Contract: lint green, and the assembly is structural.

**Agents:** security-sentinel, test-design-reviewer, architecture-strategist and
performance-oracle, plus a verify-the-negative and attribution pass on the `standard` tier.

**Attribution check.** All 12 negative claims and every cited PR and issue were confirmed. The one
nuance is recorded: the cron allowlists grant two pinned `bash plugins/…/*.sh` invocations and no
open shell.

### Key improvements

1. **Closed an allow-where-main-denies regression.**
   - The failure path used to check the loose indicator before the floor. Now a floor-only hit
     always denies, and the floor compares **counts** per shape.
   - The indicator is computed with `grep -E` on continuation-joined text.
2. **Closed nine bypasses** that the security review found in the per-filing field parser and the
   lexer:
   - `bodyvar` reading another command's text;
   - a repeated `--body`, where gh keeps the last value;
   - `body=@file`;
   - a create-form `labels[]=`;
   - `find -exec` leaking a label from a later action;
   - `--repo` spellings: case, host, URL;
   - `repositories/<id>/issues`, `..` segments and `"$B/issues"`;
   - `bash -c -o posix`;
   - the `$'…'`/`$"…"` quote ends.

   A `..` segment also escapes the cron `gh api repos/jikig-ai/soleur/` allowlist prefix, so cron
   `decide()` now denies dot-segments.
3. **Performance.**
   - `_api_pl` (inherited from `main`) is quadratic: 8.6 s on 70 KB. It is made linear.
   - Bash `=~` was quadratic for the indicator, so the indicator uses `grep -E`.
   - Re-lexing is memoized, `ALRM` exits 3 (not 142), and the per-call cost is measured at
     +5-8 ms.
   - The quadratic `strip_command_bodies`, also inherited, gets its own issue.
4. **Test design.**
   - Five mutation rows could not go RED; each is fixed.
   - Floors now count executed rows.
   - `decision_of` fails any non-F row that routes through the failure path, which makes about 60
     existing deny rows into lexer witnesses.
   - Oracle vacuity is fixed with exported variables, a `doppler` shim, per-column truth and
     semantics aligned with the predicate.
   - Shims run in a sandbox copy of the hooks.
5. **Architecture.**
   - The parity vitest moves to the `repo-wide` project, so hook-only diffs still run it.
   - ADR-256 is reinstated as a scoped exception to ADR-157's "never denies".
   - The `model.c4` Hook Engine description gets one sentence.
   - The ADR-157 clauses are honored: a payload-free cause enum, and the kill switch downgrades the
     ask to an allow.
   - Phase 0 is split so Phase 1 can be cherry-picked.

### New considerations discovered

- Codex and Devin also run `guardrails.sh`. Whether they honor `ask` is unverified, and ADR-256
  records that.
- The union floor needs a removal criterion (3 consecutive clean oracle runs), recorded in ADR-256.

## Overview

The guardrails PreToolUse hook decides whether a Bash command files a GitHub issue by grepping
`$SCAN`. `$SCAN` is a copy of the command with every quoted span and heredoc body blanked out. The
blanking stops a commit message that *mentions* `gh issue create` from being denied (#5192), but it
also hides every filing whose text sits inside quotes, which bash still runs:

- `"$(gh issue create …)"`
- `bash -c "…"`
- `gh api "repos/o/r/issues" …`

This plan makes three changes:

- **A core-Perl shell lexer finds filings.** It runs alongside `main`'s existing detectors, which
  stay in place as a floor.
- **Each filing's exits are read from that filing's own arguments.** Another command on the same
  line can no longer supply them.
- **One predicate spec, enforced by one shared token corpus, binds the hook to the cron mirror's
  `filingShape()`.** The mirror's own POST-spelling and `#fragment` gaps are closed at the same
  time.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

This is revision 4. It folds in:

- the CTO domain review, the spec-flow analysis and the scoped advisor consult (revision 2);
- the plan-review panel (DHH, Kieran, code-simplicity, CTO devex lens) in revision 3;
- the deepen-plan panel (security-sentinel, test-design-reviewer, architecture-strategist,
  performance-oracle, verify-the-negative) in revision 4.

`### Plan-time review revisions` records what changed and why.

## Research Insights

### Premise Validation

- **#9089** is open (`gh issue view 9089`, 2026-09-28) with labels `type/security`,
  `meta/machinery` and `priority/p2-medium`. No PR closes it. Its five comments hold the scope from
  the resume note:
  - the cron mirror gaps;
  - the quoted-endpoint escape (DC-1 of the #9088 plan);
  - a long list of other residual shapes.
- **Commit `4170460eea`** (PR #9088, merged 2026-09-27) is the last change to
  `.claude/hooks/guardrails.sh`. It added per-segment CLASS 4 matching over `$SCAN` and left the
  quoted forms open on purpose. See the archived plan
  `knowledge-base/project/plans/archive/20260927-230014-2026-09-27-fix-guardrails-filing-gate-issue-subresource-plan.md`
  and DC-1 in the archived `decision-challenges.md`.
- **Measured on this branch (hook fed on stdin, from a non-git CWD), every named shape is still
  allowed:**
  - `URL=$(gh issue create …)`, `URL="$(gh issue create …)"` and `N="$(gh api …/issues -X POST …)"`
  - `bash -c "gh issue create …"` and `sh -c '…'`
  - `gh api "repos/…/issues" -X POST …` and `gh api repos/"$REPO"/issues -X POST …`
  - `printf x | gh issue create …`, `( … )`, `{ …; }`, `if …; then …` and `for …; do …`
  - `sudo …`, `env A=1 …`, `gh issue new …` and backticks
  - `gh issue list --repo cli/cli && gh issue create …`
  - `gh issue list --label meta/machinery && gh api …/issues -X POST -f title=x`

  The premise holds. The same session also measured `gh issue "cre"ate --help` passing the live
  hook, which is the quote-splitting form of the same escape.
- **`filingShape()` gaps, confirmed by reading**
  `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` (`export function filingShape`):
  - no branch matches `-ftitle=x`, `-Ftitle=x`, `-F=title=x`, `--input=f` or `-X=POST`;
  - the endpoint regex `issues\/?(\?[^/]*)?$` does not allow `#`;
  - `filingJustificationReason` has no `--input` refusal, which the hook gained in #9088.
- **gh behavior, verified with read-only calls (gh 2.101.0):**
  - `-X=GET`, attached `-fper_page=1`, `-F=per_page=1` and lowercase `--method=get` are all
    accepted.
  - A persistent `-R` works both before the subcommand (`gh issue -R cli/cli list`) and at the root
    (`gh --repo cli/cli issue list`).
  - `gh issue create --help` lists `ALIASES gh issue new` and `-m, --milestone`.
  - In `gh api --help`, `-i` (`--include`) is the only short boolean flag. The short flags that take
    a value are `-F -H -q -X -p -f -t`.
  - `repos/jikig-ai/soleur/ISSUES` and `REPOS/…/issues` both return 404, so API paths are
    case-sensitive.
  - Inside a git checkout, gh expands `repos/{owner}/{repo}/issues`.
- **`Text::ParseWords::shellwords` cannot be the tokenizer (measured).** Given
  `URL=$(gh issue create --title x);echo "a b" it'\''s x&&y`, it returns
  `[URL=$(gh] [issue] [create] [--title] [x);echo] [a b] [it\'s] [x&&y]`. It does not split
  operators or substitutions, and it gets the `'it'\''s'` idiom wrong.
- **Perl cost (measured):** walking a 64 KB input one character at a time takes 13 ms, so lexing
  every Bash command is affordable (Kieran: drop the prefilter).
- **ADR:** ADR-157 already rules that "a hook that cannot parse its input asks" and that it "never
  denies". This plan writes ADR-256 as a scoped exception with a pointer from ADR-157 (see
  `## Architecture Decision (ADR/C4)`). `origin/main`'s highest ADR is ADR-255 (fetched 2026-09-28).

### Property List (Phase 0.6b)

The properties use PR-numbers so they cannot be confused with the P-rows in Test Scenarios.

- **PR1. Every executed filing is seen.** Bash may execute a `gh issue create|new` or a `gh api`
  POST to the issues collection from any argv position. All of the following are classified as
  filings:
  - after a launcher (`sudo`, `setsid`, `flock f`, `doppler run --`, `xargs`, `find -exec`);
  - at top level, in pipeline stages, in subshells and `{ …; }` groups, and in
    `if`/`while`/`for`/`case` bodies;
  - inside `$(…)`, backticks or `<(…)`, whether quoted or not;
  - inside `${X:-$(…)}` defaults and unquoted-delimiter heredoc bodies;
  - inside `bash|sh|zsh|dash|ksh -c` strings and `eval` strings.
- **PR2. Quoting does not hide a filing.** A quoted or partly quoted spelling is classified the
  same as its unquoted form. Examples: `"repos/o/r/issues"`, `repos/"$R"/issues`, `-f "title=a b"`,
  `g"h"`, `g\h`.
- **PR3. Prose is not a filing.** Text that bash does not run as a command is not classified as a
  filing. That includes:
  - commit-message bodies and quoted-delimiter heredoc bodies;
  - quoted prose (`echo "gh issue create"`);
  - `--jq` programs;
  - `#` comments, including a `$(…)` inside one;
  - the text of `${…}` outside its substitutions.
- **PR4. Exits come from the filing's own arguments.** A filing's exits are its `--milestone`/`-m`,
  its `--repo`/`-R` external exemption, its label exit and its `--body-file`. They are read from
  that filing's own argv using gh's value-taking flags, so a flag value is never read as a flag.
  When the filing carries a literal inline body, that body is its exit-2/3 corpus.
- **PR5. The two predicates agree.** `filingShape()` and the hook's `filing_shape` give the same
  answer on every row of one shared corpus. The corpus covers `-ftitle=`, `-Ftitle=`, `-F=title=`,
  `--input=`, `-X=POST`, `-iXPOST`, `#fragment`, `{owner}`/`:owner` paths, root-level `--repo`, and
  `$`-valued methods, fields and endpoints. The cron mirror refuses an `--input` filing the same
  way the hook does.
- **PR6. One endpoint regex.** The deny marker heads the endpoint with the predicate's exported
  regex, not a hand copy.
- **PR7. Never weaker than `main`.** Nothing this change does, and no way it fails, lets through a
  filing that `main` would deny:
  - filings are the union of the lexer's findings and `main`'s detectors;
  - a lexer failure on a command that looks like a filing denies (the agent can fix it) or asks
    (our machinery failed), and never allows;
  - the lexer is bounded well inside the hook's non-blocking 10 s timeout.
- **PR8. Refusals are actionable.** A refusal names:
  - the filing it refused;
  - where the filing runs (`inside $(…)`, `inside bash -c`, `inside backticks`);
  - that the exit belongs inside that same command;
  - for backtick or unquoted-heredoc prose that bash executes, how to quote it.

### Cut List (Phase 0.6b and plan review)

- **`Text::ParseWords::shellwords` as the tokenizer** (PR1/PR2): cut. It was measured failing above.
- **One tokenizer implementation shared by both surfaces** (PR5): covered by one token-level
  corpus instead. The hook would otherwise shell out to node, or the lexer would be ported to JS.
- **A launcher table** (revision 1, PR1): replaced by detecting `gh` at any argv position. Every
  launcher table misses one, such as `setsid`, `flock`, `ionice` or `strace`.
- **Changing `$SCAN` / `strip_command_bodies`**: not needed. Other gates and 12 hooks consume
  them.
- **Cron-side `$(…)`/`bash -c` handling**: `decide()` already provides it by denying
  substitutions, pipes and `$VAR`, and no cron allowlist grants a shell. Vitest rows pin that
  behavior.
- **A `--help` exemption** (no property): cut. `--body --help` would be a bypass.
- **"Explicit `-X GET` wins over fields"** (no property): cut. It only removes over-gating.
- **Revision 2's same-script assignment map** (DHH, simplicity, Kieran #4): cut. Kieran found it
  unsound: `(R=cli/cli)`, `unset` and `read` are not modeled, so it could grant an exit bash would
  not. Its jobs are handled instead as follows:
  - A `$`-only endpoint with a POST signal is a filing, which errs toward gating.
  - A `$`-valued `--repo` is never external.
  - A body that references a variable falls back to a variable corpus: the command's heredoc bodies
    and literal assignment values. It never falls back to `$COMMAND` (revision 4, security #5).
- **Revision 2's stdin-completion rule for `xargs`/`parallel`** (DHH, simplicity): cut to
  Non-Goals. `main` does not gate that shape either, and Kieran found a gap in the rule.
- **The string-runner tail** (`trap`, `watch`, `su`/`runuser`, `script -c`, `env -S`, a shell fed a
  heredoc), from DHH and simplicity: moved to Non-Goals. Kept: `bash|sh|zsh|dash|ksh -c` and
  `eval`, which are the shapes the issue names.
- **`$'…'` decoding** (simplicity, and Kieran #3): moved to Non-Goals, together with brace
  expansion, under "computed command words". Partial decoding would be bypassable (`gh`), and
  full decoding pays for nothing an agent does.
- **The prefilter** (Kieran #3): cut. The lexer always runs (13 ms per 64 KB), which removes the
  `g''''h` bypass of the prefilter.
- **Five exit codes, and a separate floor-disagreement branch** (DHH, simplicity): collapsed into
  two exit codes. The floor is a plain union, and a floor-only hit takes the normal failure path.
- **A new ADR-256** (DHH, simplicity): cut in revision 3, then **reinstated in revision 4**. The
  architecture review found that the parity contract does not belong under ADR-157's title, and that
  the fail direction is an exception to ADR-157's "never denies", not an extension of it (DC-4).

### Relevant files

- `.claude/hooks/guardrails.sh`: the `guardrails:require-milestone` block, from the content anchor
  `_gh_create=0; _gh_api_issue=0; _gh_api_input=0` through the end of
  `guardrails:require-filing-justification`.
  - The CLASS 1 trigger is `grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create' <<<"$SCAN"`.
  - CLASS 4 is the `_api_pl` perl segmenter.
  - The exits read `_repo_toks`, built by `strip_heredocs "$COMMAND" | tr '\n' ' ' | xargs -n1` over
    the WHOLE command.
  - The body corpus is `_fj_body="$COMMAND"`.
- `.claude/hooks/lib/incidents.sh`: `strip_command_bodies`, `strip_heredocs` and
  `emit_incident`. `emit_incident` is fail-soft: it returns 0 on every write failure.
  `strip_heredocs` stays, because `pkill-self-match-guard.sh` uses it.
- `.claude/hooks/guardrails.test.sh`:
  - the helpers `decision_of`/`assert`/`assert_reason`, run from a non-git tmp CWD;
  - `MIN_ASSERTIONS=195`;
  - the no-perl shim row (anchor `_nopl="$CM/no-perl"`) and the `TOK_MSG` rows.

  The suite takes 22 s locally (measured) and runs as shard 2 of `scripts/suite-shard-legs.tsv`.
  `scripts/test-all.sh` discovers `.claude/hooks/lib/*.test.sh` by glob.
- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`: `filingShape`,
  `filingJustificationReason`, `labelTokenEquals`, `tokenize`, `splitSegments`,
  `dangerousMetacharReason`, `argumentInjectionReason` and `decide`. This file is in the Next.js
  server bundle, so it must never gain a `new URL(…, import.meta.url)` asset reference (#8074).
- `apps/web-platform/server/cron-filing-deny-marker.ts`: `const ENDPOINT_RE = …` is a hand copy of
  the `filingShape` endpoint regex.
- The vitest files are `apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts` and
  `apps/web-platform/test/server/cron-filing-deny-marker.test.ts`.
- `.claude/settings.json` registers guardrails.sh with `"timeout": 10`. The timeout is
  non-blocking, so a slow hook becomes an allow.
- `.claude/hooks/brand-hex-commit-gate.sh` is precedent for NUL-framed `mapfile -d ''` IPC.
- `knowledge-base/engineering/architecture/decisions/ADR-157-a-hook-that-cannot-parse-its-input-asks.md`
  is the ADR this plan amends.

### Institutional learnings applied

- `2026-09-27-my-segmenter-split-on-characters-the-shell-reads-as-one-command.md`:
  - Redirects carry `&`/`|` characters that do not separate commands.
  - `$(a | b)` must stay whole, and `#fragment` belongs to its word.
  - Run one process, never a fork per segment.
  - Fixture every character that has more than one meaning.
- `2026-09-25-line-linter-quote-state-needs-a-stack-not-flags.md`: tracking quote state needs a
  frame stack, not flags.
- `2026-09-10-i-graded-lines-when-the-unit-was-the-command.md`: the unit is the command. That is
  PR4.
- `2026-09-10-every-escape-my-mutations-could-not-reach.md`: only an escape corpus finds escapes.
  That is why this plan has the executed oracle and the differential corpus.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`: use
  non-canonical must-PASS rows and literal floors.
- `2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md`: every newly gated
  shape keeps its three honest exits, and the refusal says where the exit goes (PR8).
- `2026-05-29-command-detection-hook-self-interception-and-heredoc-fp.md`: test only through the
  committed suites. The live hook denied this session's own `gh issue create --help`.
- `workflow-patterns/2026-09-25-issue-filing-gate-body-file-needs-absolute-path-in-worktree.md`:
  a relative `--body-file` resolves against the hook's CWD.

### Related issues and prior art

- #9088 (merged) is the sub-resource narrowing, and #5192 is the commit-body false-positive class.
  #8074 and #8076 are the cron mirror and its deny marker.
- ADR-216 (machinery ledger), ADR-156 (untrusted hook input) and ADR-157 (a hook that cannot parse
  its input asks) set the constraints.
- Functional-discovery found no community artifact that gates `gh` filings with a lexer.
- No open `code-review` issue names a file in this plan (checked 2026-09-28).

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "a shell tokenizer shared with `filingShape()`" | The hook is bash plus perl. The mirror is an ESM module in the Next.js server bundle, and its `tokenize()` only ever sees metachar-free text | Share the **predicate spec and one token-level corpus**, not the code |
| `Text::ParseWords::shellwords` is the fix direction (#9089 CTO note) | Measured: it neither splits operators nor sees `$(` | A hand-written lexer with a frame stack |
| Cover `$(…)` and `bash -c` on the cron mirror too | `decide()` denies both before tokenizing | No cron code change for these shapes; two vitest rows pin the behavior |
| `-F=title=` and `-X=POST` are real gh spellings | Verified, and so are root-level `--repo` and `-iXPOST` clusters | In scope on both sides |
| `--input=` is only a shape gap in the mirror | The mirror also lacks the hook's `--input` refusal | Add the refusal (PR5) |

## Problem Statement

The filing gate answers "is this a filing?" with greps over `$SCAN`. That approach has three gaps:

- **Quoted text is invisible.** The greps cannot see anything inside quotes, even when bash
  executes it.
- **Anchors miss many positions.** The CLASS 1 trigger anchors on `(^|&&|\|\||;)`, so it misses
  `$(`, `|`, `(`, `{`, `then`, `do` and every launcher prefix.
- **Exits leak across commands.** Once a filing is detected, its exits are read from the whole
  command line, so a different command on the same line can satisfy them.

The cron mirror has the opposite shape. It tokenizes properly and refuses substitutions outright,
but `filingShape()` misses five POST spellings and the `#fragment` endpoint. Under the
`gh api repos/jikig-ai/soleur/` allowlist that `cron-roadmap-review` holds, those shapes are a live
bypass of the cron filing gate.

## Proposed Solution

### 1. The lexer: `.claude/hooks/lib/filing-shape.pl` (core Perl, no modules)

**Layout contract** (CTO devex, performance-oracle):

- `use strict;` with `$^W = 1`. `use warnings` alone costs 1.8 ms per fork, measured.
- A header that holds:
  - a grammar sketch;
  - the gh version the flag tables were taken from, and how to refresh them;
  - a pointer to ADR-256 (the parity contract);
  - the rule for removing the union floor.
- The flag tables and the string-runner list are data at the top of the file.
- One sub per construct.
- Regexes that contain `$`, `}` or `)` use `qr~…~` delimiters. `[$})]` breaks a `qr{…}` literal
  (measured).
- The suite runs `perl -c` on the file.

**Modes:**

| Invocation | Input | Output |
|---|---|---|
| `perl filing-shape.pl` (default) | The raw command on stdin | One NUL-framed record per filing: `F\0<shape>\0<ctx>\0<nfields>\0<key>=<value>\0…`. After the last record it prints `OK\0` and exits 0. Details below the table |
| `perl filing-shape.pl --classify tok…` | One token list | `create`, `api` or `none`. This is the corpus entry point, and it runs the same `filing_shape` sub |
| `perl filing-shape.pl --trace` | A command | Each simple command's argv, the full wrapper path (e.g. `shell-c>subst`) and the parsed fields, as plain text. The file header and every lexer-failure incident name this mode, so a false deny can be debugged |

In default mode:

- `<shape>` is `create` or `api`.
- `<ctx>` is the innermost wrapper: `top`, `subst`, `backtick`, `shell-c`, `eval` or `heredoc`.
- Consumers parse records **by count**. They never search for the `OK` or `F` sentinels.

**Failure exits.** Default mode can fail in two ways, and each prints `bound=<cause>` on stderr:

- **Exit 2** means an unbalanced quote, an unterminated substitution or heredoc delimiter word, or
  a NUL byte in the input. The agent can fix these. Unbalanced `(`/`)` are **never** an error, since
  they are separators, so `case` patterns and `[[ =~ (a|b) ]]` lex with exit 0.
- **Exit 3** means a bound tripped. There are three bounds:
  - recursion deeper than 16;
  - a character budget of 8 × input + 64 KiB, counted on ONE global counter that every frame
    charges, including re-lexed `bash -c`/`eval` strings and heredoc terminator scans;
  - `alarm 2`, with `$SIG{ALRM} = sub { print STDERR "bound=alarm\n"; exit 3 }` (without the
    handler perl exits 142).

  The cause is `depth`, `budget` or `alarm`. Our machinery failed, not the agent.

**Memoization.** Re-lexing is memoized on the substitution's source text. A `$(…)` seen at the word
level and again inside a `bash -c` string is lexed once, which turns 2^depth into depth.

**Lexing** is one recursive-descent pass with a frame stack. A substitution is lexed in place from
the same cursor, never by finding its closing `)` first. That is what lets a heredoc body inside
`$(cat <<'EOF' … EOF)` contain `)`, `(`, `it's` or `` ` ``.

- **Quoting:**
  - `'…'` is literal.
  - In `"…"`, `\` escapes only `$`, `` ` ``, `"`, `\` and newline. `$(`, backticks and `${` stay
    live.
  - In `$'…'`, the lexer honors `\\` and `\'` when finding where the string ends (security #3), so
    `echo $'\''; gh issue create …` splits as bash splits it. Other escape sequences are not
    decoded (Non-Goal).
  - `$"…"` is lexed exactly like `"…"`, so its substitutions are live.
  - Outside quotes, `\` makes the next character literal, and `\`-newline continues the line.
- **Separators:** an unquoted newline, `;`, `&`, `|`, `&&`, `||`, `|&`, `;;`, `;&`, `;;&`, `(` and
  `)` each end a simple command.
  - A redirection's `&` or `|` is not a separator: `2>&1`, `&>`, `>&2`, `>|`, `<&0`.
  - `{` and `}` are ordinary words.
- **Redirections:** an optional fd number, then one of `<`, `>`, `>>`, `>|`, `<>`, `>&`, `<&`, `&>`,
  `&>>` or **`<<<` (here-string)**. The redirection and its target word are dropped from argv, and
  substitutions inside the target are still recursed. `<<<` is matched before `<<` (security #4,
  test-design #7), and the existing "guard3: <<< here-string" row pins it.
- **Substitutions:** every `$(…)`, backtick span, `<(…)` and `>(…)` is lexed as a script wherever
  it appears.
  - Every substitution *inside* `${…}` and `$((…))` is lexed too, but the text of `${…}` itself
    never is.
  - A word keeps the raw source of its substitutions, so `repos/$(echo o)/r/issues` stays one token.
- **Comments:** `#` starts a comment only at the start of a word, and the comment runs to the end
  of the line. Nothing inside it is recursed.
- **Heredocs** are handled natively, not with `_incidents_heredoc_re`:
  - Several heredocs can be pending on one line.
  - Each body starts at the **next unquoted newline**, so the rest of the opening line is still code.
  - Any quoting of the delimiter makes the body data: `'EOF'`, `"EOF"`, `\EOF`, `E"OF"`.
  - An unquoted body is scanned for `$(`, backticks and `${`, and those are recursed.
  - `<<-` strips leading tabs before matching the terminator.
  - A missing terminator reads to EOF.
  - Heredoc bodies and literal `NAME=value` assignment values are collected, in text order, into a
    per-script **variable corpus**. That corpus is used only by the `bodyvar` fallback below.

**Finding filings.** In each simple command's argv, every index `i` whose word's basename is `gh`
starts a candidate. The candidate's argv is normalized so that `argv[i]` becomes `gh`, and then
`filing_shape` classifies it.

- This covers `sudo gh`, `setsid gh`, `flock f gh`, `doppler run -- gh`, `/usr/bin/time -v gh`,
  `find -exec gh …` and `then gh`, with no launcher table.
- **`find` actions (security #9):** when the candidate follows `-exec`, `-execdir`, `-ok` or
  `-okdir`, its argv is cut at the first bare `;` or `+` word. A later `-exec echo --label …` then
  cannot supply the filing's exit.
- **Deliberate over-fire (DC-2):** these commands are classified as filings, and each errs toward
  gating: an unquoted `echo gh issue create`, `bash -c 'echo gh issue create'`,
  `man gh issue create`, and `[[ $s =~ ^(gh issue create) ]]`.

**String runners** are the only list:

- `bash|sh|zsh|dash|ksh`, at any argv position, with an option cluster that contains `c`.
  - The script is the first word after the cluster that is not an option and not an option's value.
  - Options and their values can come before OR after the cluster: `--norc`, `-o posix`,
    `-O extglob`, `+x`, `--rcfile F`, `--` (security #13).
- `eval`, whose words are joined with spaces.

**Per-filing fields** are parsed with gh's value-taking flag tables. The tables are pinned in
Phase 0 from `gh issue create --help` and `gh api --help` (gh 2.101.0). A token is read as a flag
only when it is not the value of a preceding value-taking flag. For single-valued flags gh keeps the
**last** value, and so does the parser.

| Field | Meaning |
|---|---|
| `head=…` | `gh issue create` or `gh api <path>`, with the path cut at `?` or `#` and capped at 64 characters |
| `repo=…` | The last `-R`, `--repo`, `-R=`, `--repo=` or `-Rx`, at the root or group level. Normalized before the owner test (security #10): scheme and host are stripped (`https://github.com/`, `github.com/`) and the owner is lowercased, so `JIKIG-AI/soleur` and `https://github.com/jikig-ai/soleur` count as ours. A value that contains `$` or a backtick is **never external** |
| `milestone=1` | Set when `-m`, `--milestone`, `--milestone=` or `-mX` is present |
| `label=…` | Repeatable, because `--label` is a slice. It comes from `--label`/`-l` and their `=`/attached forms. On **api filings only**, it also comes from the value of `-f`/`-F`/`--field`/`--raw-field`, or attached `-flabels[]=…`, when that value starts with `labels[]=` (security #8). A bare `labels[]=` token or a create-form `--title 'labels[]=…'` does not count |
| `bodyfile=…` | The last `--body-file` or `-F` value (create only), including `=` forms. Also set by an api `body=@<path>` field (security #7). `@-` or `-` is unreadable |
| `body=…` | The **last** literal inline body (security #6): `--body`/`-b`, or an api `body=` field in any spelling that is not an `@` value. If that value contains an unquoted `$` expansion, the record carries `bodyvar=1` plus `varcorpus=<the variable corpus>`, and bash uses that corpus, never `$COMMAND` (security #5) |
| `input=1` | Set when an api filing carries `--input` or `--input=` |

### 2. `guardrails.sh` wiring

- **The lexer always runs** (Kieran: no prefilter). Its records are read with a
  `while IFS= read -r -d ''` loop (bash 3.2-safe) from a process substitution. The substitution
  appends the producer's exit code as a final `RC\0<n>\0` record.
- **Filings are the union** of the lexer's records and `main`'s detectors (PR7):
  - The CLASS 1 `$SCAN` grep and `_api_pl` stay, commented as the floor.
  - **`_api_pl` is made linear** (performance-oracle). It finds `gh\s+api\b` once and then searches
    for the endpoint from that position. Measured on `main`, the current pattern takes 8.6 s on a
    70 KB padded input, and that alone outruns the non-blocking timeout.
  - The floor reports a **count per shape**: the number of CLASS 1 matches, and `_api_pl`'s number
    of hit segments. A shape where the floor count exceeds the lexer's count is a floor-only hit
    (security #2).
- **Each lexer record goes through `_gate_one_filing`.** It keeps the existing milestone,
  external-repo and three-exit logic, reading the record's fields instead of `_repo_toks` or
  `$COMMAND`. The `xargs -n1` tokenizer and its three token loops are deleted.
- **A deny names the filing's head and context,** and adds "add the exit inside the same `<ctx>`
  command as `gh`" (CTO devex). Two hints are added:
  - the prose hint, for `ctx=backtick` or an unquoted `heredoc`;
  - "pass an absolute path", for a relative `bodyfile` that cannot be read.
- **Failure path** (security #1, test-design #6). The indicator is computed with `grep -E`, never
  bash `[[ =~ ]]`, which is quadratic on a miss (36 KB takes 3.3 s, measured). It runs on the raw
  command with `\`-newline continuations joined, and matches `\bgh\b.*(issue[^A-Za-z0-9_]+(create|new)|issues)`.
  The rules apply in this order:
  1. **A floor-only hit denies, whatever the indicator says.** Message: "the filing gate could not
     parse this command (`<cause>`); run the filing as a plain top-level command with an absolute
     `--body-file` path." This covers every case `main` gates, including the no-perl row and a
     tripped bound in front of a top-level filing.
  2. **Lexer exit 2 with the indicator matching denies** with `TOK_MSG`.
  3. **Any other failure with the indicator matching asks,** per ADR-157 and scoped by ADR-256.
     Other failures are exit 3, a missing `OK`, a malformed stream, or no perl. Message: "the filing
     gate could not parse this command (`<cause>`). Approve only if it does not file an issue." The
     ADR-157 kill switch `SOLEUR_DISABLE_HOOK_INPUT_ASK=1` turns this ask into an allow and still
     writes the incident.
  4. Otherwise the hook allows. That is `main`'s behavior for a non-filing.

  **Incident.** One code, `guardrails-filing-lexer-failure`, whose cause is an **enum**: `exit2`,
  `depth`, `budget`, `alarm`, `noperl`, `trunc` or `floor-only`. It carries no payload content,
  per ADR-157's telemetry clause.
- **Unchanged:** `$SCAN`, `strip_command_bodies` and every other gate. The quadratic
  `strip_command_bodies` is pre-existing, and it is re-homed (see Non-Goals).

### 3. The shared predicate (one spec, two implementations)

```text
filing_shape(tokens):
  tokens[0] != "gh"                                  -> none   # the hook normalizes the basename first
  pos = tokens after index 0 that are not flags, skipping the value of a bare -R / --repo
        (root- or group-level; not -R=x, --repo=x, -Rx)
  pos[0] == "issue" and pos[1] in {create, new}      -> create
  pos[0] == "api":
      endpoint = SOME token matches ISSUES_COLLECTION_RE
                 or is a bare $VAR / ${VAR}                       (leans toward gating)
                 or contains an expansion and ends in issues[/][?…|#…]   (security #12: "$B/issues")
                 or is a repos/… or repositories/… path with a `.`, `..` or %2e segment (security #11)
      post     = SOME token i satisfies POST_SIGNAL
      endpoint && post                               -> api
  otherwise                                          -> none

ISSUES_COLLECTION_RE (case-sensitive; Perl uses \z where JS uses $):
  /(?<![A-Za-z0-9_])(?:repos\/[^\/?#\s]+(?:\/[^\/?#\s]+)?|repositories\/[0-9]+)\/issues(?:\/?(?:[?#].*)?|[$})][^\/]*)$/

POST_SIGNAL(tokens, i). C = an optional run of -i, the only boolean short flag gh api has.
V = an optional leading $NAME or ${…} (test-design #6: `$E-X POST` reaches gh as `-X POST`).
  t matches /^V-C?X$/ or t == "--method", and the next token matches /^post$/i or starts with $ or `
  or t matches /^V(-C?X=?|--method=)(post$|\$|`)/i          # -XPOST, -X=POST, -iXPOST, -X$M
  or t matches /^V--input(=|$)/
  or t matches /^V-C?[fF]$/ or t is --field / --raw-field, and the next token starts with title=, $ or `
  or t matches /^V(-C?[fF]=?|--field=|--raw-field=)?title=/   # -ftitle=, -F=title=, -iftitle=, bare title=
  or t matches /^V(-C?[fF]=?|--field=|--raw-field=)[$`]/     # -f$T (prefix required: --jq "$Q" is not a signal)
```

**The corpus.** The new file `.claude/hooks/lib/filing-shape-corpus.json` is a JSON array.

- **Entries:** `{"id": "C<n>", "tokens": [...], "shape": "create"|"api"|"none", "why": "..."}`.
- **Documentation:** a first element `{"_doc": "…schema, ownership, where new rows go…"}`. The
  loaders skip it.
- **Consumers:** two suites load the file.
  - `filing-shape.test.sh` runs every row through `--classify`.
  - A new vitest file, `apps/web-platform/test/server/inngest/filing-shape-corpus-parity.test.ts`,
    runs every row through `filingShape(tokens) ?? "none"`. It reads the file with `readFileSync`,
    resolved from `import.meta.url`, and it is registered in
    `apps/web-platform/test/repo-wide-suites.ts`. Without that registration, a diff touching only
    `.claude/hooks/lib/` would never run the JS half (architecture #1).
- **Floors (test-design #4):**
  - The row floor counts **executed** rows. The shell suite increments a counter inside its loop,
    and the vitest increments `ran++` in each case and checks it in `afterAll`. Both compare
    against a literal.
  - The three-shape-class check runs over the asserted rows, not over the file.

### 4. The cron mirror

- **`filingShape()`:** export `ISSUES_COLLECTION_RE`, and implement the predicate above.
- **`filingJustificationReason()`:** an `api` shape carrying an `--input`/`--input=` token returns
  the hook's `--input` refusal. This check runs **before** exits 0 and 1.
- **`decide()` (security #11, cron containment):** deny any `gh api` token that is a
  `repos/…`/`repositories/…` path with a `.`, `..` or `%2e` segment. A measured GET of
  `repos/jikig-ai/soleur/labels/../issues` returned the issues collection. So without this check a
  `..` segment escapes the `gh api repos/jikig-ai/soleur/` allowlist prefix, for filings and for
  any other endpoint.
- **`cron-filing-deny-marker.ts`:** import the regex, delete the local `ENDPOINT_RE`, and cut the
  head at `?` or `#`.
- **PR6 scope.** The deny marker shares the regex by import. The Perl side keeps its own copy,
  bound to the JS copy only through the corpus (architecture #7).

### 5. The executed oracle and the differential corpus (opt-in, not CI)

`filing-shape.test.sh --differential <base-hooks-dir>` is committed so the result can be reproduced
(CTO devex). It does not run in CI.

**How each command runs:**

- **Shims, first in `PATH`, then `/usr/bin:/bin`:**
  - `gh` logs its argv.
  - `sudo` execs the rest of its argv.
  - `doppler` execs the argv after `--` (test-design #8).
  - `git` does nothing.
- **Guards:**
  - `GH_TOKEN=invalid`, `GH_HOST=invalid.invalid`, a tmp `GH_CONFIG_DIR` and a tmp working
    directory;
  - `timeout 5` on each command;
  - no absolute `gh` path in any generated command.
- **Exported variables:** `REPO=jikig-ai/soleur`, `M=POST`, `EP=repos/jikig-ai/soleur/issues` and
  `QS='?x=1'`. Without them, variable rows expand to empty and could never report a miss
  (test-design #8).

**Ground truth comes from gh semantics in the shim, not from `--classify`** (Kieran #10). A logged
argv counts as a filing when either condition holds:

- it is `issue create` or `issue new`, after skipping `-R`/`--repo`;
- it is `api` to an issues-collection path (the first positional argument), where the method is the
  last `-X`, or POST by default, AND a title field or `--input` is present (test-design #8, aligned
  with the predicate).

**Checks:**

- **Misses:** every truth filing is reported by the lexer.
- **Prose:** every row tagged `prose` produces no filing.
- **Wrapper coverage:** every wrapper column produces at least one truth filing. A column with none
  cannot fail, so it is itself a failure.
- **Flip table:** base-hook and patched-hook verdicts are compared, and every flip must be explained
  (AC5). This runs only once the hook is wired (Phase 5), not in Phase 3 (architecture #6).

## Implementation Phases

Contract before consumer: each phase consumes only what an earlier phase produced. The phases are
split so that Phase 0a plus Phase 1 can be cherry-picked on their own (architecture #6).

**Phase 0a: corpus and cron tests first.**

- Add `filing-shape-corpus.json`, with its `_doc` element.
- Add `filing-shape-corpus-parity.test.ts`, registered in `repo-wide-suites.ts`.
- Add the vitest rows: the `--input` refusal, the dot-segment deny, the two `decide()` pins, and the
  deny-marker `#fragment` row.
- These rows start RED.

**Phase 0b: hook tests first.**

- Add the `filing-shape.test.sh` rows and the `guardrails.test.sh` rows. Put each row ID in its
  assert label (CTO devex).
- The suite header says where a new row goes:
  - a spelling → the corpus;
  - lexing → `filing-shape.test.sh`;
  - a verdict or refusal text → `guardrails.test.sh`.
- Write the heredoc-inside-`$(…)` rows first, so the tests force the frame-stack design (advisor).
- Pin gh's flag tables and version from `--help`.
- Add the table-staleness row. It is **intentionally RED** until Phase 2 or 3 creates the tables.
- Make `decision_of` fail any non-F row that writes a `guardrails-filing-lexer-failure` incident
  (test-design #6). This turns the ~60 existing deny rows into lexer witnesses once Phase 4 wires
  the lexer.

**Phase 1: the cron mirror and shared predicate.**

- Implement `ISSUES_COLLECTION_RE`, `filingShape`, the `--input` refusal, the dot-segment deny in
  `decide()`, and the deny-marker import.
- Vitest (`--project repo-wide` plus the unit files) must be green.
- These are the first code commits, so the live cron bypass can ship on its own if needed (DC-1).

**Phase 2: `filing-shape.pl --classify`.** The corpus must pass on both sides.

**Phase 3: the lexer, per-filing fields, `--trace`, memoization and bounds.**

- Implement the lexer and its record rows.
- Run `--differential` in miss-and-prose mode. It must report 0 misses, 0 prose filings, and every
  wrapper column with at least one truth filing. The flip table waits for Phase 5.

**Phase 4: wire `guardrails.sh`.**

- Add `_gate_one_filing`, the counted union floor, the linear `_api_pl` and the failure path.
- Delete `xargs -n1`.
- Put the failure-path decision table in a comment next to the code.
- Update every comment that describes `$SCAN`-based detection.
- Run `guardrails.test.sh` and `hook-input-contract.test.sh`.

**Phase 5: record and verify.**

- Write ADR-256, and add the one-line pointer to ADR-157.
- Add the sentence about the Hook Engine's second implementation to `model.c4`.
- Run the C4 tests:
  - `apps/web-platform/test/c4-code-syntax.test.ts`;
  - `apps/web-platform/test/c4-render.test.ts`;
  - `plugins/soleur/test/c4-count-parity.test.sh`.
- Run the full `--differential`, including the flip table (AC5).

**Phase 6 (at ship).**

- File one residual follow-up issue that lists the Non-Goals, labeled `meta/machinery` with the
  milestone `Post-MVP / Later`. Both were verified to exist.
- File a second issue for the pre-existing quadratic `strip_command_bodies`. It is a
  hook-wide timeout bypass: 12 s on 87 KB, measured. Label it `type/security`, `domain/engineering`
  and `priority/p2-medium`.
- Close #9089 from the PR body.

## Files to Create

- **`.claude/hooks/lib/filing-shape.pl`:** the lexer, string runners, field parser, variable
  corpus, predicate, memoization and bounds. Modes: default, `--classify` and `--trace`.
- **`.claude/hooks/lib/filing-shape-corpus.json`:** the shared corpus, with a `_doc` element and a
  floor of 80 executed rows.
- **`.claude/hooks/lib/filing-shape.test.sh`:** runs the following.
  - corpus parity, with an executed-row counter;
  - lexer-record rows;
  - bounds rows that assert `bound=<cause>`;
  - `perl -c`;
  - flag-table staleness;
  - `--probe`;
  - `--differential` (opt-in).

  Shim rows copy the hook tree into a sandbox, as the existing `TAXO_SANDBOX` row does, and replace
  `lib/filing-shape.pl` there. They never shim `perl` on `PATH`, which would also blind `$SCAN` and
  the floor (test-design #9). Each shim touches a marker file that the row asserts.
- **`apps/web-platform/test/server/inngest/filing-shape-corpus-parity.test.ts`:** the JS half of the
  corpus.
- **`knowledge-base/engineering/architecture/decisions/ADR-256-filing-gate-lexer-and-corpus-bound-predicate-parity.md`:**
  the ordinal is provisional, and ship re-verifies it. Its latest base on `origin/main` is ADR-255,
  checked 2026-09-28.

## Files to Edit

- **`.claude/hooks/guardrails.sh`, in the filing-gate block:**
  - the lexer call and the record reader;
  - `_gate_one_filing`;
  - the counted union floor, including the linear `_api_pl`;
  - the failure path and its decision-table comment;
  - the refusal texts;
  - deleting `xargs -n1` and the three token loops;
  - the header comments.
- **`.claude/hooks/guardrails.test.sh`:**
  - the new rows, with the `MIN_ASSERTIONS` bump in the same commit;
  - the `decision_of` incident check;
  - the "quoted endpoints on both sides of &&" comment;
  - the `TOK_MSG` rows are kept.
- **`apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`:** `ISSUES_COLLECTION_RE`,
  `filingShape`, `filingJustificationReason`, and the `decide()` dot-segment deny.
- **`apps/web-platform/server/cron-filing-deny-marker.ts`:** import the regex, and cut at `[?#]`.
- **`apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts`:**
  - the `--input` refusal and its reorder row;
  - the dot-segment deny rows;
  - the two `decide()` pins, for `$(…)` and for `bash -c`.
- **`apps/web-platform/test/repo-wide-suites.ts`:** register the parity test.
- **`apps/web-platform/test/server/cron-filing-deny-marker.test.ts`:** the `#fragment` head row.
- **`knowledge-base/engineering/architecture/decisions/ADR-157-a-hook-that-cannot-parse-its-input-asks.md`:**
  a dated one-line pointer to ADR-256's scoped exception.
- **`knowledge-base/engineering/architecture/diagrams/model.c4`:** one sentence in the
  `hooks = container "Hook Engine"` description. It names the filing predicate's second
  implementation (`filingShape()` in the cron containment hook) and the shared corpus that binds
  the two.

## Open Code-Review Overlap

None. No open `code-review` issue names any of the files above (queried 2026-09-28, 200-issue
window).

## Non-Goals (re-homed to the follow-up issue at ship)

- **Other filing routes:**
  - GraphQL `createIssue`;
  - `curl -X POST …/repos/o/r/issues`;
  - variables not assigned as a literal in view;
  - `gh alias set ic 'issue create'` followed by `gh ic …`;
  - function wrappers (`f(){ gh "$@"; }; f issue create …`);
  - `source <(echo 'gh …')`;
  - `python3 -c`/`node -e` running `gh` (security #14).
- **Computed or escaped command words:** decoding `$'…'` escapes (`$'\x67h'`), brace expansion,
  globs in `argv[1..2]`, and `$(printf gh)`.
- **String runners beyond shells and `eval`:** `trap`, `watch`, `su`/`runuser -c`, `script -c`,
  `env -S`, a shell fed a heredoc or here-string, `ssh host STR`, `bash script.sh`,
  `printf … | bash`, and `parallel ::: "…"`.
- **`xargs`/`parallel` completed from stdin.**
- **Other gates and lints:**
  - `.claude/hooks/follow-through-directive-gate.sh`;
  - the `MUTATING_METHOD` spellings in `scripts/lint-workflow-issue-write-scope.py`.
- **Cron mirror exits:** `labelTokenEquals` and the body loop are not value-position-aware.
  `argumentInjectionReason` does not refuse `--input <file>` to non-issue endpoints.
- **The endpoint owner is not read:** an api-form POST to another owner's repo is not exempt.
- **The pre-existing quadratic `strip_command_bodies`** (`_incidents_heredoc_re`, used by 13
  hooks). It gets its own issue at ship.
- **Over-gating that errs toward gating:**
  - `-X GET` with fields or `--input`, and a repeated `-X POST -X GET`;
  - `gh issue create --help`;
  - an unquoted `echo gh issue create`, `bash -c 'echo gh issue create'`, `man gh issue create` and
    `[[ … =~ (gh issue create) ]]`;
  - `a=(gh issue create)`, and a function body that is never called;
  - a `$`-only endpoint that is not an issues collection;
  - a comment POST whose body ends in `repos/o/r/issues` (DC-3).

## Technical Considerations

- **Performance** (performance-oracle, measured on this host):
  - The hook takes 69-76 ms per call today. The lexer fork adds about 5-8 ms, or 8-10%.
  - A bare perl start costs 3.5-4 ms.
  - The bounds are:
    - one global character budget, charged in every frame;
    - memoized re-lexing, which turns 2^depth into depth;
    - `alarm 2` with an exit-3 handler.
  - The quadratic `_api_pl` is made linear. The indicator runs in `grep -E`, which takes 5-17 ms
    on the inputs where bash `=~` takes 3-72 s.
  - Not adopted: merging the strip, `_api_pl` and the lexer into one perl process under one alarm
    (DC-5).
- **Fail direction:**
  - Detection is the lexer **plus** `main`'s counted detectors.
  - A floor-only hit always denies.
  - A lexer failure on a command that looks like a filing denies (exit 2) or asks (our machinery),
    and never allows. This is ADR-256's scoped exception to ADR-157's "never denies".
- **Over-fire.** Recursing into every substitution is correct, because bash runs them. The risk is
  prose misread as code. Four things pin it:
  - the PR3 must-PASS rows, each also asserting that the lexer exits 0 and prints `OK`;
  - the oracle's `prose` rows;
  - the every-commit shape with hostile heredoc bodies;
  - `decision_of`'s check that no non-F row writes an incident.
- **Portability:**
  - Perl uses core modules only, and the NUL framing needs no JSON module.
  - The record reader is safe on bash 3.2.
  - Test code reads the corpus with `jq` (shell) and `readFileSync` (vitest).
  - Other harnesses: `guardrails.sh` also runs under Codex (`.codex/config.toml`) and Devin
    (`.devin/config.json`). Whether they honor `ask` is **unverified**, and the ADR records that
    (architecture #5).
- **Attack surface enumeration:**
  - **Covered (PR1/PR2):** `gh issue create|new` and REST `gh api` POSTs, in any executed position
    this lexer models, including `repositories/<id>/issues` and dot-segment paths.
  - **Re-homed:** the Non-Goals.
  - **Cron:** `decide()` stops every substitution and non-allowlisted verb before `filingShape`
    runs, and it now also stops dot-segment escapes from the allowlist prefix.
  - **Cron allowlists:** apart from `gh`/`git` prefixes, the cron allowlists grant only two pinned
    `bash plugins/soleur/skills/…/*.sh` invocations (`_cron-claude-eval-substrate.ts`
    `CRON_BASH_ALLOWLISTS`). No allowlist grants an open shell.
- **Bundle safety.** The mirror gets no new asset reference. Only the new test file reads the
  corpus.

## Architecture Decision (ADR/C4)

### ADR

The plan creates **ADR-256**, "Filing-gate classification via a shell lexer, with a corpus-bound
predicate shared with the cron mirror". The ordinal is provisional. ADR-157 gets a dated one-line
pointer to it. ADR-256 records three decisions:

1. **Lexing replaces blanked-text grepping.** `main`'s detectors stay as a counted union floor. The
   floor may be removed only after the `--differential` oracle has run clean on 3 consecutive
   filing-gate changes, and the ADR records that criterion.
2. **Parity is a corpus-bound predicate spec, not shared code.** The ADR names the three consumers:
   the Perl `filing_shape`, the JS `filingShape` and the deny marker's import.
3. **A scoped exception to ADR-157's "never denies"** (architecture #2).
   - The exception covers only commands that match the filing indicator, or that `main`'s floor
     detects. There, an agent-fixable failure (exit 2) or a floor-only hit denies, because the
     repair is never a filing and ADR-157's bricking concern does not apply.
   - Every other machinery failure asks, per ADR-157. The kill switch still applies, and the
     telemetry is a cause enum with no payload.
   - ADR-157 covered parsing the tool-call envelope. It now also covers lexing the command.
   - Whether Codex and Devin honor `ask` is recorded as unverified.

The ADR's Alternatives section lists these rejected options:

- `shfmt --to-json`: not on operator hosts, and `-c` strings would still need re-parsing;
- tree-sitter-bash: heredocs inside `$(…)`;
- `bashlex`: unmaintained;
- `bash -n`: gives no argv;
- `Text::ParseWords`: measured failing;
- shelling out to node: couples the hook to the web-platform module graph;
- amending ADR-157 alone: DHH and simplicity preferred it, but architecture found the parity
  contract does not belong under ADR-157's title (DC-4).

A CI-only shfmt cross-check is noted as a follow-up option.

### C4 views

The C4 model gets **one edit**, in `model.c4`. The `hooks = container "Hook Engine"` description
says `.claude/hooks/` is "the only tree of hook CODE" since the PreToolUse mirrors were retired. This
plan names a second implementation of one hook predicate (`filingShape()` in the cron containment
hook), bound by a corpus that lives in the Hook Engine tree. The description gets one sentence that
says so (architecture #4).

The rest of the enumeration was checked against all three files and needs no change:

- **External human actors:** none new. `claude -> hooks` already models the untrusted envelope.
- **External systems:** none new. The hook calls no service.
- **Data stores:** none touched.
- **Access relationships:** none changed.

Phase 5 runs `c4-code-syntax.test.ts`, `c4-render.test.ts` and `c4-count-parity.test.sh`.

### Sequencing

ADR-256 and the C4 sentence are true at merge. There is no soak.

## User-Brand Impact

- **If this lands broken, the user experiences:** one of two failures in their own agent sessions.
  - **Over-fire:** a routine command is refused as a filing. The most exposed command is the
    `git commit -m "$(cat <<'EOF' … EOF)"` form this repo uses for every commit. A refusal there
    stalls every agent pipeline at commit time.
  - **Under-fire:** an unjustified issue lands on the operator's backlog through a
    `$(…)`/`bash -c`/quoted-endpoint filing. For cron agents, it lands through a `-ftitle=` or
    `-X=POST` spelling.
- **If this leaks, the user's workflow is exposed via:** nothing new. The hook reads the command
  string and writes local incident rows. The cron change only adds refusals after the allowlist
  match, and it reads no new file or secret.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: a local PreToolUse lexer plus a narrowing of the cron mirror's filing predicate; it handles no user data or credential, and the worst outcome is a mis-gated agent command, which the must-PASS commit rows pin.`

## Observability

The interactive gate is a local PreToolUse hook with no server runtime. On the cron side,
`SOLEUR_CRON_FILING_DENY` (Better Stack) already reports every filing-shaped denial, and this change
feeds it the predicate's own regex.

```yaml
liveness_signal:
  what: "filing-shape.test.sh verdict line (corpus parity, lexer records, bounds, flag-table staleness) and guardrails.test.sh verdict line, each under a literal executed-row floor, plus filing-shape-corpus-parity.test.ts in the repo-wide vitest project"
  cadence: "every scripts/test-all.sh run and every CI run (both .test.sh suites are glob-discovered; the vitest runs in the web-platform test job)"
  alert_target: "a RED suite fails its CI leg and blocks the PR"
  configured_in: "scripts/test-all.sh SUITE_GLOBS (.claude/hooks/*.test.sh, .claude/hooks/lib/*.test.sh), scripts/suite-shard-legs.tsv, apps/web-platform/test/repo-wide-suites.ts"

error_reporting:
  destination: "hook: permissionDecisionReason plus emit_incident rows in .claude/.rule-incidents.jsonl (guardrails-require-milestone, wg-defer-only-after-inline-triage, and the new guardrails-filing-lexer-failure code with its cause); cron: the SOLEUR_CRON_FILING_DENY pino WARN marker shipped to Better Stack by the Vector app_container_warn_filter"
  fail_loud: "a lexer failure on a filing-indicated command denies (unbalanced quoting, or a shape main gates) or asks (our machinery), with the cause and a pointer to --trace in the incident row"

failure_modes:
  - mode: "a filing inside $(...), backticks, bash -c, eval, a pipeline, a group or at any argv position is allowed"
    detection: "Guard 1 deny rows and the --differential oracle's no-miss check go RED"
    alert_route: "PR-blocking suite failure; oracle run at Phase 3 and Phase 5"
  - mode: "prose is read as code and a routine command, including the every-commit form, is denied"
    detection: "PR3 must-PASS rows (each also asserting lexer exit 0 plus OK) go RED"
    alert_route: "PR-blocking suite failure"
  - mode: "the lexer crashes, hangs, trips a bound or is absent and a filing is allowed"
    detection: "failure-path rows (no-perl, truncated stream, exit 2 and exit 3 shims, floor-only hit) and the bounds rows"
    alert_route: "PR-blocking suite failure"
  - mode: "the hook and the cron mirror classify the same tokens differently"
    detection: "the shared corpus fails in one suite and not the other (Guard 3)"
    alert_route: "PR-blocking suite failure in whichever leg diverged"
  - mode: "a gh upgrade adds a value-taking flag and the field parser misreads its value as a flag"
    detection: "the flag-table staleness row in filing-shape.test.sh (skips when gh is absent)"
    alert_route: "PR-blocking suite failure on the next run with the new gh"

logs:
  where: "session output (the refusal text), the repo-local .claude/.rule-incidents.jsonl, and Better Stack for the cron marker"
  retention: "repo-local, rotated by rotate_if_needed (.claude/hooks/lib/log-rotation.sh); Better Stack per the source's plan retention"

discoverability_test:
  command: "bash .claude/hooks/lib/filing-shape.test.sh --probe"
  expected_output: "PROBE=create"
```

`--probe` runs exactly one lexer call, on `URL=$(gh issue create --title x)`, and prints
`PROBE=<shape>`. It takes well under a second. Check 10's allowlist does not include `perl`, which
is why the probe goes through `bash`.

**Deepen-plan Phase 4.7 disposition.** Two proxy checks flagged this block:

- **The "suite-shaped command" check.** `filing-shape.test.sh` matches `[-.]test\.`, but the check
  is a false hit. `--probe` is parsed first and exits before any row, corpus load or oracle runs,
  so it makes one perl fork. The suite file is just the place to put a Check-10-legal `bash` entry
  point without adding a sixth file.
- **The "prose `expected_output`" check.** The original value `PROBE create` contained whitespace,
  which the check reads as prose. The fix is `PROBE=create`, a single token with no whitespace.

AC11 is updated to match.

## Guard Contract

### Guard 1 — the hook's filing detection sees every executed filing and no prose

**Property.** A `gh issue create|new` or `gh api` issues-collection POST that bash would execute
from the Bash tool's command string is classified as a filing. Text that bash would not execute as a
command is not.

**Assembly.** Filings are the union of two chokepoints plus a failure path.

- **(a) `filing-shape.pl` in default mode**, called once from `guardrails.sh`. It has four members:
  1. the simple-command split;
  2. substitution recursion (`$(`, backticks, `<(`, `>(`, and substitutions inside
     `${…}`/`$((…))`, in bare words, double quotes and redirection targets);
  3. the heredoc reader (quoted = data, unquoted = scanned);
  4. any-position `gh` detection plus shell `-c` and `eval` recursion.
- **(b) The floor:** `main`'s CLASS 1 grep and `_api_pl`.
- **The failure path** handles exit codes 2 and 3, a malformed stream, no perl, and a floor-only
  hit.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| G1-1 | Substitution recursion removed for `$(` | RED: D1-D3, D20, D23 |
| G1-2 | Double-quote context treats `$(` as literal | RED: D2, D3 |
| G1-3 | Backtick recursion removed | RED: D7 |
| G1-4 | Shell `-c` recursion removed | RED: D4-D6, D20, D31 |
| G1-5 | Only an exact `-c` recognized (no clusters, no `--`) | RED: D6, D31 |
| G1-6 | Heredoc body starts at `<<` instead of the next newline | RED: D21 |
| G1-7 | Unquoted-delimiter heredoc bodies not scanned | RED: D27 |
| G1-8 | Detection limited to `argv[0]` | RED: the D16 launcher rows (except `/usr/bin/gh`, which is `argv[0]`) |
| G1-9 | `\|` not a separator | RED: D43, `gh issue create --title x --body y --milestone M \| tee --label meta/machinery` (base allows; must deny). `tee`'s `--label` would otherwise read as the filing's exit |
| G1-10 | Quoted-delimiter heredoc bodies lexed as code | RED: P5, P6, whose body lines START with `gh issue create --title x --body y` |
| G1-11 | Single-quoted spans lexed as code | RED: P7 |
| G1-12 | `${…}` text lexed as a script | RED: P8 |
| G1-13 | Comments not skipped before substitution recursion | RED: P9 |
| G1-14 | Own dispatch: a lexer exit ≠ 0 read as "no filings" | RED: F-exit2 and F-exit3 run on `URL=$(gh issue create …)`, which the floor cannot see |
| G1-15 | Own dispatch: `OK`/`RC` check removed, so a truncated stream reads as complete | RED: F-empty, a sandbox shim printing NOTHING on `URL=$(gh issue create …)` and exiting 0 (ask expected). F-trunc alone is masked by the count parser (test-design #5) |
| G1-16 | Floor removed from the union | RED: F-floor, a lexer shim printing only `OK` on a bare top-level create |
| G1-17 | Second member: only the first record is gated | RED: D29 |
| G1-18 | Reorder: records parsed by searching for `OK` instead of by count | RED: F-count, a shim record whose field value contains `OK\0` and whose `nfields` is correct. A search-based parser stops early and drops the second filing |
| G1-19 | The floor compares yes/no instead of a per-shape count | RED: F-count2, a sandbox shim reporting ONE justified create on a command with two top-level creates (the second unjustified). The floor counts 2, which is more than 1, so the hook must deny (security #2) |
| G1-20 | The failure path checks the indicator before the floor | RED: D53 (the depth bound trips; the indicator misses across a `\`-newline; the floor must still deny) |

**Harness rows.**

- **H1-a.** Delete any 3 new rows in either suite, and that suite's literal floor trips.
- **H1-b (must-PASS, non-canonical).** P14: justified filings inside `$(…)` and inside `bash -c`
  stay `<none>`.
- **H1-c (must-PASS).** P18, P19 and P20: the list-then-label and GET shapes.
- **H1-d.** Every P-row also asserts, in `filing-shape.test.sh`, that the lexer exits 0 and prints
  `OK`, so a crashed lexer cannot pass a must-PASS row.

**Anchor.** Two checks sit outside the committed rows:

- the `--differential` oracle (real bash, with ground truth taken independently from gh semantics);
- the base-vs-patched flip check against `git show 4170460eea:.claude/hooks/` (AC5).

### Guard 2 — a filing's exits come from its own arguments, parsed by gh's flag tables

**Property.** A filing is credited with a milestone, an external repo, a label exit, a body file or
a literal body claim only when that value is the argument of the matching gh flag in the filing's
own argv.

**Assembly.** The producer is the field parser in `filing-shape.pl`; its flag tables are pinned to
a gh version, and a staleness row checks them. The consumer is `_gate_one_filing`, which reads the
fields `repo`, `milestone`, `label`, `bodyfile`, `body`/`bodyvar` and `input`. No other reader of
`_repo_toks` remains in the filing path. No reader of `$COMMAND` remains either, since the `bodyvar`
fallback reads the lexer's `varcorpus`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| G2-1 | Fields computed over the whole command | RED: D24, D25, D26, D45 (`find -exec` cut) |
| G2-2 | Value-taking flags not skipped | RED: D36, D37 |
| G2-3 | `$`-valued `--repo` treated as external | RED: D38 |
| G2-4 | Own dispatch: `_gate_one_filing` returns before its checks | RED: every filing deny row |
| G2-5 | Second member: only the first `label` field read | RED: P21 (`--label type/bug --label meta/machinery` must ALLOW) |
| G2-6 | The `bodyvar` fallback removed | RED: P10 (`BODY=$(cat <<'EOF' …); … --body "$BODY"`, allowed on `main` and still allowed) |
| G2-7 | The literal body is ignored and `$COMMAND` is always used | RED: D35 |

**Harness rows.**

- **H2-a (must-PASS).** P16, the `-m` short form.
- **H2-b (must-PASS).** P15, an external create with a literal `--repo cli/cli`.

**Anchor.** The `&&`-chained arm of the differential corpus.

### Guard 3 — one predicate, two implementations

**Property.** For every row of `filing-shape-corpus.json`, both `--classify` and `filingShape()`
return the row's `shape`. The deny marker heads endpoints with the exported `ISSUES_COLLECTION_RE`.

**Assembly.** The predicate spec has three consumers:

- `filing_shape` (Perl);
- `filingShape` (JS);
- `filingHead`, by import.

The corpus file is the one fixture source.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| G3-1 | JS drops the `-X=`/`--method=` arm | RED in vitest only |
| G3-2 | Perl drops the attached `-ftitle=` arm | RED in `filing-shape.test.sh` only |
| G3-3 | Either side drops `#` from the endpoint regex | RED in that suite |
| G3-4 | Own dispatch: the corpus loader returns `[]` | RED: the literal floor, in both suites |
| G3-5 | Second member: only the first corpus row asserted | RED: the EXECUTED-row counter (shell loop counter, vitest `ran++` in `afterAll`) falls short of its literal floor |
| G3-6 | The deny marker keeps a local `ENDPOINT_RE` without `#` | RED: the deny-marker fragment row |
| G3-7 | Reorder: the cron `--input` refusal moved after exit 1 | RED: "`--input` with `-f labels[]=meta/machinery` still denies" |
| G3-8 | POST_SIGNAL's `$` arm loses its required prefix | RED: C-row `gh api repos/o/r/issues --jq "$Q"` → `none` |
| G3-9 | The cron `decide()` dot-segment deny is removed | RED: vitest `gh api repos/jikig-ai/soleur/labels/../issues …` must deny under the `gh api repos/jikig-ai/soleur/` allowlist |

**Harness rows.**

- **H3-a.** Each suite requires all three shape classes to be present.
- **H3-b (must-PASS, non-canonical).** Sub-resources, `issues.json`, `ISSUES` and `pulls` classify
  as `none` on both sides.

**Anchor.** The oracle's ground truth comes from gh semantics, independent of `--classify`. A
predicate weakened in step with the corpus therefore shows up as an oracle miss.

## Acceptance Criteria

- [ ] **AC1.** Both suites pass under a literal floor equal to their row count, and each floor is
  bumped in the same commit as its rows:
  - `bash .claude/hooks/guardrails.test.sh` prints `Total: N  Pass: N  Fail: 0` with
    `MIN_ASSERTIONS=N`;
  - `bash .claude/hooks/lib/filing-shape.test.sh` prints `Total: M  Pass: M  Fail: 0` with its own
    literal floor.
- [ ] **AC2.** Run `guardrails.test.sh` against a scratch copy of the **whole**
  `git show 4170460eea:.claude/hooks/` tree (never the worktree).
  - Every D-row not tagged `[base-deny]` FAILs.
  - Every P-row not tagged `[base-deny]` passes.
  - `[base-deny]` marks rows the base already denies (D28's `-X=POST`, `-ftitle=` and `--input=` rows, D34) or must-PASS
    rows the base denies (P16, the `-m` form). D36 is base-denied too. Those rows pin the patched
    behavior and are
    excluded from the RED check.
- [ ] **AC3.** Run `cd apps/web-platform && ./node_modules/.bin/vitest run --project repo-wide test/server/inngest/filing-shape-corpus-parity.test.ts`
  and `./node_modules/.bin/vitest run test/server/inngest/cron-bash-allowlist-hook.test.ts test/server/cron-filing-deny-marker.test.ts`.
  Both pass. The parity test counts executed rows (`ran >= 80` in `afterAll`, a literal) and asserts all three classes over the asserted rows.
- [ ] **AC4.** The corpus holds at least 80 rows, covering:
  - `$E-X POST`, `${E}-X POST`, `repositories/<id>/issues`, a `..` segment, `"$B/issues"`;
  - every POST_SIGNAL spelling against the base endpoint, including `-iXPOST`, `-iftitle=x`,
    `-X$M`, `-f "$T"` and lowercase `post`;
  - every endpoint form with `-X POST`: `/`, `?q`, `#f`, leading `/`, a full URL, `$REPO`,
    `{owner}/{repo}`, `:owner/:repo`, `issues$QS`, `${EP:-…}`, `$(…)` and a bare `$EP`;
  - every `create` spelling: `create`, `new`, `-R x create`, `--repo x create`, `--repo=x create`
    and root `--repo x issue create`;
  - at least 15 `none` rows: sub-resources, `issues.json`, `ISSUES`, `pulls`, a GET with no signal,
    `--jq "$Q"`, `gh issue list`, `gh pr create`, `git` and `echo`.
- [ ] **AC5.** Run `bash .claude/hooks/lib/filing-shape.test.sh --differential <scratch-base-hooks>`
  over at least 300 generated commands:
  - 12 wrappers (bare, `$(…)`, `"$(…)"`, backticks, `bash -c "…"`, `sh -c '…'`, `eval`, `sudo`,
    `setsid`, `doppler run --`, pipeline stage, unquoted heredoc) × (the corpus's `create`/`api`
    rows + 10 `none` rows);
  - plus 30 prose shapes.

  It must report 0 oracle misses and 0 prose filings. Its base-vs-patched flip table goes in the PR
  body:
  - every allow→deny flip is an oracle-truth filing;
  - every deny→allow flip is a justified filing, a `-m` filing or a sub-resource.
- [ ] **AC6 (bounds, asserted by exit code and `bound=<cause>`, not wall clock).** Test-design #10
  and performance-oracle drive these rows:
  - A 20-deep `$(…)` nesting (which grows linearly and cannot hit the budget) gives exit 3 with
    `bound=depth`.
  - A budget row, sized from the formula at Phase 3 and never from a guess, gives exit 3 with
    `bound=budget`. With memoization on, a nested `bash -c "$(…)"` stays well under the budget; a
    row pins that too (exit 0).
  - A 300 KiB padded command ending in a bare create gets a hook decision of `deny`, through the
    floor.
  - One wall-clock tripwire, the 12-deep hook call under 8 s, stays a suite row and is not an AC.
- [ ] **AC7.** `bash .claude/hooks/hook-input-contract.test.sh` passes, and
  `python3 scripts/lint-shell-capture-exit.py .claude/hooks/guardrails.sh` reports no new finding.
- [ ] **AC8.** In `.claude/hooks/guardrails.sh`:
  - `grep -c 'xargs -n1'` returns 0;
  - `_api_pl` and the CLASS 1 grep are still present, each commented as the floor.
- [ ] **AC9.** `grep -c 'const ENDPOINT_RE' apps/web-platform/server/cron-filing-deny-marker.ts`
  returns 0, and the file imports `ISSUES_COLLECTION_RE`.
- [ ] **AC10.** All of these hold:
  - `python3 scripts/lint-guard-contract.py` passes on this plan;
  - `bash plugins/soleur/test/c4-count-parity.test.sh` passes;
  - ADR-256 exists (ordinal re-verified at ship), and ADR-157 carries the dated pointer to it;
  - the C4 tests pass after the `model.c4` sentence: `c4-code-syntax.test.ts` and `c4-render.test.ts`;
  - the PR body carries `Closes #9089` and links the residual follow-up issue.
- [ ] **AC11.** `bash .claude/hooks/lib/filing-shape.test.sh --probe` prints `PROBE=create`.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed (structural review for revision 2, devex lens for revision 3)

**Assessment:** The direction is sound, and the risk is medium: the lexer sees every agent command.
Every structural recommendation was adopted except the PR split (DC-1) and the new ADR (DC-4):
any-position detection, lexer bounds, per-filing exits, value-position gaps, hardened commit rows,
separated failure causes, and `{owner}` rows. The `ISSUES` casing was probed and returns 404, so
the regex stays case-sensitive. The devex findings were all adopted: `--trace`, the in-command
clause in refusals, row IDs in labels plus a header guide, a committed `--differential` mode, a
flag-table staleness row, a Perl layout contract, and build-vs-buy alternatives in ADR-256.

### Product/UX Gate

Not applicable. No file matches the UI-surface list, and the mechanical override did not fire.

### Plan-time review revisions

| Finding | Source | Change |
|---|---|---|
| The fallback grepped `$SCAN`, so deep nesting slipped through | spec-flow #16, advisor | A raw-text indicator decides deny or ask, and `main`'s detectors are a union floor |
| No net for a lexer misparse | spec-flow #18, advisor | The union floor, plus an executed oracle with independent ground truth (Kieran #10) |
| Launcher gaps (`setsid`, `flock`, `doppler run --`, `time -v`, `strace`, `sudo --`, …) | spec-flow #3-#4, CTO | Any-position `gh` detection |
| Heredoc delimiter spellings, multiple heredocs per line, and heredocs inside `$(…)` | spec-flow #5, CTO, advisor | Native heredoc queue with in-place recursive descent (P1-P6, D21, D27) |
| `${…}` text and `$(…)` inside a comment | spec-flow #6-#7 | Only substitutions inside `${…}` are recursed, and comments are skipped (P8, P9) |
| Unactionable refusals | spec-flow #8, CTO devex | The `ctx`, the in-command clause, the prose hint and the absolute-path hint (PR8) |
| Must-PASS rows that could not catch their mutants | spec-flow #9-#11 | New body lines, single-quoted `;` rows, and a lexer exit-0 plus `OK` assertion |
| Hand-graded AC5, a tautological AC3 count, and a post-deploy anchor | spec-flow #12-#14 | Oracle-generated expectations and literal floors |
| Value-position flags, `$`-repo, relative body-file, record parsing | spec-flow #19 | Flag-table fields, no exemption for `$` values, an absolute-path hint, and F-count |
| Wall-clock AC6 | plan-review standing check | Bounds asserted by exit code |
| Assignment map unsound and over-built | Kieran #4, DHH #5, simplicity | Cut. `$`-only endpoints gate, a `$` repo is never external, and a `$` body falls back to the variable corpus (revision 4) |
| Stdin completion, string-runner tail, `$'…'` decoding | DHH #7-#8, simplicity, Kieran #3/#9 | Moved to Non-Goals |
| Prefilter bypassable (`g''''h`) | Kieran #3 | Cut; the lexer always runs |
| Five exit codes and a separate disagreement branch | DHH #3-#4, simplicity | Two exit codes and a plain union floor |
| `$J` breaks rows inside `bash -c "…"`; P13 contradicted the over-fire; AC2 inconsistent with base-denied rows; D39 double-defined | Kieran #1, #2, #5 | `$K` for double-quoted runners, `bash -c 'echo …'` moved to D32, `[base-deny]` tags, D39 renamed P21 |
| Mutations that could not go RED (G1-8, G1-9, G1-18) and failure rows the floor masked | Kieran #6-#7 | New witnesses (D43, F-count), and failure rows run on floor-invisible commands |
| Predicate: basename vs `tokens[0]`, `$` arm too broad, `-i` clusters, Perl `$` vs `\z`, root `--repo` | Kieran #8, #11 | Normalize before classify, prefix-required `$` arm, `-i` clusters, `\z`, and root `--repo` (verified) |
| Property IDs collided with row IDs | Kieran #12 | Properties renamed PR1-PR8 |
| New ADR vs. amend | DHH #10, simplicity vs. CTO, then architecture #2-#3 | Revision 3 amended ADR-157; revision 4 reinstates ADR-256 as a scoped exception (DC-4) |
| `--probe` ceremony | simplicity, DHH #11 | Kept: Check 10's allowlist excludes `perl`, so the probe needs `bash` |
| Floor gated behind the indicator (allow where `main` denies); floor yes/no | security #1, #2 | Floor-only hit denies first; floor counts per shape (G1-19, G1-20, D53) |
| `$'…'` end and `$"…"` desync; `<<<`; NUL | security #3, #4, test-design #7 | `\\`/`\'`-aware `$'…'` end; `$"…"` lexed as `"…"`; `<<<` redirection; NUL → exit 2 (D52) |
| `bodyvar` read other commands' text; repeated `--body`; `body=@file`; `labels[]=` on create | security #5-#8 | Variable corpus (heredocs + assignments only); last value wins; `@` → bodyfile; api-only label field (D44, D46-D48) |
| `find -exec` label leak; `--repo` spellings; `repositories/<id>`, `..`, `"$B/issues"`; `bash -c -o posix` | security #9-#13 | argv cut at `;`/`+`; repo normalization; regex + dot-segment + partial-expansion endpoints; cron `decide()` dot-segment deny (D45, D49-D51, G3-9) |
| Mutation rows that could not go RED (D43, D28 tags, G2-1/D35, G3-5, G1-15) | test-design #1-#5 | `--milestone M` in D43, per-spelling tags, D45 for G2-1, executed-row floors, F-empty |
| Existing `$E-X POST` row silently routed through the floor | test-design #6 | V-prefix POST_SIGNAL arms; `decision_of` fails any non-F row that writes a lexer-failure incident |
| Oracle vacuity (unset vars, no doppler shim, truth ≠ predicate); shim blinding the floor | test-design #8-#9 | Exported vars, doppler shim, per-column truth ≥ 1, aligned truth; sandbox-copy shims with markers |
| Bounds rows did not show which bound fired | test-design #10, performance | `bound=<cause>` on stderr; linear depth row; formula-sized budget row |
| Quadratic `_api_pl` and `=~` indicator; re-lex doubling; alarm exit 142 | performance-oracle | Linear `_api_pl`; `grep -E` indicator; memoized re-lexing; `$SIG{ALRM}` → exit 3; `$^W` over `use warnings` |
| Vitest corpus read skipped on hook-only diffs; ADR-157 "never denies" contradicted; parity under wrong ADR; C4 Hook Engine sentence false | architecture #1-#4 | `repo-wide` parity test; ADR-256 as a scoped exception; model.c4 sentence |
| ADR-157 clauses (payload-free telemetry, kill switch, other harnesses); phase ordering; PR6 half-true | architecture #5-#7 | Cause enum; kill switch → allow + incident; Codex/Devin `ask` recorded unverified; Phase 0a/0b; PR6 scoped |

## Test Scenarios

Row IDs are referenced by the Guard Contract. Two justification suffixes are used:

- `$J` stands for `--milestone "Post-MVP / Later" --label meta/machinery`, with a leading space.
- `$K` stands for `--milestone M --label meta/machinery`, with a leading space. `$K` is used inside
  double-quoted runner strings, where `$J`'s quotes would break the string.

A ⏎ marks a newline. `[base-deny]` marks a row the base hook already denies.

**Deny rows (`guardrails.test.sh`):**

- **Substitutions and runners:**
  - D1 `URL=$(gh issue create --title x --body y)`
  - D2 `URL="$(gh issue create --title x --body y)"`
  - D3 `N="$(gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y)"`
  - D4 `bash -c "gh issue create --title x --body y"`
  - D5 `sh -c 'gh issue create --title x --body y'`
  - D6 `bash -lc 'gh issue create --title x --body y'`
  - D7 `` echo `gh issue create --title x --body y` ``
  - D19 `eval "gh issue create --title x --body y"`
  - D20 `bash -c "URL=\$(gh issue create --title x --body y)"`
  - D23 `X="${Y:-$(gh issue create --title x --body y)}"`
  - D31 Three rows: `bash -c -- '…'`, `bash --norc -c '…'` and `sudo sh -c '…'`
- **Quoted spellings and deliberate over-fire:**
  - D8 `gh api "repos/jikig-ai/soleur/issues" -X POST -f title=x -f body=y`
  - D9 `gh api repos/"$REPO"/issues -X POST -f title=x`
  - D10 `gh api 'repos/jikig-ai/soleur/issues' -f "title=a b"`
  - D32 Four rows: `g\h issue create --title x --body y`, `g''h issue create …`, and the
    deliberate over-fire rows `echo gh issue create --title x` and `bash -c 'echo gh issue create'`
- **Command positions:**
  - D11 `printf x | gh issue create --title x --body-file -`
  - D12 `( gh issue create --title x --body y )`
  - D13 `{ gh issue create --title x --body y; }`
  - D14 `if true; then gh issue create --title x --body y; fi`
  - D15 `for i in 1; do gh issue create --title x --body y; done`
  - D16 One row each: `sudo gh …`, `sudo -- gh …`, `env A=1 gh …`, `env -- gh …`, `command gh …`,
    `timeout -k 5 10 gh …`, `nohup gh …`, `nice -5 gh …`, `setsid gh …`, `flock /tmp/l gh …`,
    `doppler run -- gh …`, `/usr/bin/time -v gh …`, `strace -f gh …`, `xargs -r0 gh issue create …`,
    `find . -maxdepth 0 -exec gh issue create --title x --body y \;`, `/usr/bin/gh …`
- **Subcommand forms:**
  - D17 `gh issue new --title x --body y`
  - D18 `gh issue -R jikig-ai/soleur create --title x --body y`, and `gh --repo jikig-ai/soleur issue create --title x --body y`
- **Heredocs:**
  - D21 `cat <<'EOF' > b.md && gh issue create --title x --body-file b.md` ⏎ `body` ⏎ `EOF`
  - D27 `cat <<EOF` ⏎ `$(gh issue create --title x --body y)` ⏎ `EOF`, plus a two-heredocs-on-one-line variant
- **Exits scoped per filing:**
  - D24 `gh issue list --repo cli/cli && gh issue create --title x --body y`
  - D25 `gh issue list --milestone x && gh issue create --title x --body y --label meta/machinery`
    (the milestone gate fires)
  - D26 `gh issue list --label meta/machinery && gh api repos/jikig-ai/soleur/issues -X POST -f title=x`
  - D35 `echo "User-Impact: docs page Fix-Size: 200 lines / 5 files"; bash -c "gh issue create --title x --body y --milestone M"`
    (G2-7 witness only; its literal body `y` is the corpus)
    (the justification gate fires)
  - D36 `[base-deny]` `gh issue create --title -mx --body y --label meta/machinery` (the milestone gate fires)
  - D37 `gh issue create --title x --body --label=meta/machinery --milestone M`
  - D38 `gh issue create --repo "$OWNER/soleur" --title x --body y`
  - D40 `EP=repos/jikig-ai/soleur/issues; gh api "$EP" -X POST -f title=x`
- **POST spellings, multiple filings and parsing:**
  - D28 One row each (test-design #2): `[base-deny]` `… -X=POST -f title=x`, `[base-deny]` `… -ftitle=x`,
    `[base-deny]` `… --input=b.json`, and untagged `… -X "$M" -f body=y`, `… -iXPOST -f body=y`,
    `… -iftitle=x` (the `body=y` field keeps the `-X` arm the only POST signal under test)
  - D44 `echo "Mandated-By: wg-x" >/dev/null; gh issue create --title x --body "$B" -m M`
    (the `bodyvar` corpus is heredocs plus assignment values, never another command's arguments)
  - D45 `find . -maxdepth 0 -exec gh issue create --title x --body y -m M \; -exec echo --label meta/machinery \;`
  - D46 `gh issue create --title x --body "Mandated-By: wg-x" --body y -m M` (gh keeps the last body)
  - D47 `gh api repos/jikig-ai/soleur/issues -f title=x -F 'body=@/tmp/j Mandated-By: wg-x'`
    (`body=@…` is a body file)
  - D48 `gh issue create --title 'labels[]=meta/machinery' --body y -m M`, and
    `gh issue create --title x -F 'labels[]=meta/machinery' -m M` (`labels[]=` is credited only on api filings)
  - D49 `gh issue create -R JIKIG-AI/soleur --title x --body y`, `-R github.com/jikig-ai/soleur` and
    `-R https://github.com/jikig-ai/soleur` (all ours after normalization)
  - D50 `gh api repositories/1143547205/issues -X POST -f title=x`,
    `gh api repos/jikig-ai/soleur/labels/../issues -X POST -f title=x`, and
    `B=repos/jikig-ai/soleur; gh api "$B/issues" -X POST -f title=x`
  - D51 `bash -c -o posix 'gh issue create --title x --body y'`
  - D52 `echo $'\''; gh issue create --title x --body y -m M # '`, and
    `echo $"$(gh issue create --title x --body y)"`
  - D53 `: $(: $(: …17 levels…)); gh api \` ⏎ `repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y`
    (depth bound trips; the floor still denies, security #1)
  - D54 existing row 966's command wrapped in `$(…)` (`$E-X POST` inside a substitution; the corpus's V-prefix arm)
  - D29 `gh issue create --title a --body b$J; bash -c "gh issue create --title x --body y"`
  - D30 `gh issue create --title a --body b$J && gh api repos/jikig-ai/soleur/issues -X POST -f title=x`
  - D34 `[base-deny]` `gh issue create --title OK --body RC`
  - D43 `gh issue create --title x --body y --milestone M | tee --label meta/machinery` (base allows)

Every deny row that reaches the justification gate gets an `assert_reason` twin. The twin pins:

- the head and the `ctx`;
- the in-command clause;
- for api forms, the `-f labels[]=meta/machinery (the gh api spelling)` clause;
- for D7 and D27, the prose hint.

Multi-filing rows assert exactly one JSON object.

**Must-PASS rows (`<none>`).** Each P-row is also a lexer row in `filing-shape.test.sh` asserting
exit 0, `OK` and no filing (except P10, P14, P15, P16 and P21, which are filings that pass).

- **Commit messages:**
  - P1 `git commit -m "$(cat <<'EOF'` ⏎ *(body with `it's`, `1)`, an unclosed `(`, `` `code` ``, a
    literal `$(`, a `"`)* ⏎ `EOF` ⏎ `)"`
  - P2 the same as P1 with `<<"EOF"`
  - P3 the same as P1 with `<<\EOF`
  - P4 the same as P1 with `<<-'EOF'` and a tab-indented terminator
  - P5 `git commit -F - <<'EOF'` ⏎ `gh issue create --title x --body y` ⏎ `EOF`
  - P6 `git commit -m "$(cat <<'EOF'` ⏎ `gh issue create --title x --body y` ⏎ `$(gh issue create --title z)` ⏎ `EOF` ⏎ `)"`
  - P11 `git commit -m "fix(hooks): don't run gh issue create (#9089)"`
  - P12 this PR's own commit-message and `gh pr create --body-file` shapes, taken from the branch
    at Phase 4
- **Quoted prose, expansions and comments:**
  - P7 `echo 'done; gh issue create --title x --body y'`, and `echo "a; gh issue create --title x"`
  - P8 `echo "${M:-a; gh issue create --title x}"`
  - P9 `echo x # $(gh issue create --title x)`
  - P13 `echo "gh issue create --title x"`, `grep -n "gh issue create" notes.md`,
    `gh pr create --title "gh issue create" --body x`, and `printf '%s\n' 'gh issue create --title x' > notes.md`
- **Justified filings:**
  - P10 `BODY=$(cat <<'EOF'` ⏎ `User-Impact: the docs page` ⏎ `Fix-Size: 200 lines / 5 files` ⏎ `EOF` ⏎ `); gh issue create --title x --body "$BODY" --milestone "Post-MVP / Later"`
    (the `bodyvar` fallback)
  - P14 `URL=$(gh issue create --title x --body y$J)`, and `bash -c "gh issue create --title x --body y$K"`
  - P15 `gh issue create --repo cli/cli --title x --body y`
  - P16 `[base-deny]` `gh issue create -m "Post-MVP / Later" --title x --body y --label meta/machinery`
  - P21 `gh issue create --title x --body y --label type/bug$J`
- **Reads and sub-resources:**
  - P17 `gh issue list --json title --jq '.[] | "it'\''s"'`
  - P18 `gh api "repos/jikig-ai/soleur/issues?labels=x" --jq '.[].number' | xargs -I{} gh api -X POST repos/jikig-ai/soleur/issues/{}/labels -f 'labels[]=y'`
  - P19 `for n in $(gh api "repos/jikig-ai/soleur/issues?labels=x" --jq '.[].number'); do gh api -X POST repos/jikig-ai/soleur/issues/$n/labels -f 'labels[]=y'; done`
  - P20 `gh api repos/{owner}/{repo}/issues --jq length`

**Failure rows.** Shims replace the lexer, and each shim row runs on `URL=$(gh issue create …)`,
which the floor cannot see, unless noted:

| Row | Setup | Expected |
|---|---|---|
| F-noperl | No perl, bare create | deny (floor) |
| F-noperl-sub | No perl, `$(…)` create | ask |
| F-exit2 | The existing `TOK_MSG` rows, and a shim exiting 2 | deny with `TOK_MSG` |
| F-exit3 | A shim exiting 3 | ask, with the cause in the incident |
| F-exit3-bare | A shim exiting 3, bare create | deny (floor) |
| F-nonfiling | Any failure on a command without the indicator | `<none>` |
| F-trunc | A partial record, then exit 0 | ask |
| F-empty | No output at all, then exit 0 | ask (G1-15 witness) |
| F-count2 | One justified record on a command holding two bare top-level creates | deny (G1-19 witness) |
| F-count | The G1-18 witness | both filings gated |
| F-floor | A shim printing only `OK`, bare create | deny |
| F-bounds | The AC6 rows | exit 3 and exit 3 from the lexer; `deny` from the hook on the 300 KiB row |

**`filing-shape.test.sh` also runs:**

- the corpus rows through `--classify`;
- the lexer-record rows (exact fields for D24-D38 and P-rows);
- `perl -c`;
- the flag-table staleness row;
- `--probe`.

**Vitest:**

- `filing-shape-corpus-parity.test.ts` (in the repo-wide project), counting executed rows against a literal floor;
- `decide()` denies `URL=$(gh issue create …)` and `bash -c "gh issue create …"`;
- the `--input` refusal rows, including G3-7;
- the deny marker heads `repos/o/r/issues#x` as `gh api repos/o/r/issues`.

## Dependencies & Risks

- **Risk: the lexer disagrees with bash on rare syntax** (`case` inside `$(…)`, `[[ =~ (a|b) ]]`).
  Over-splitting only makes extra argv slices, and the union floor plus the oracle catch misses.
  Unbalanced results take the failure path.
- **Risk: over-fire on every commit.** P1-P6, P11, P12 and AC5's prose shapes pin it, alongside the
  existing #5192 rows.
- **Risk: `ask` in headless sessions.** In `claude --print`, an `ask` is treated as a refusal. It
  fires only on machinery failure for a filing-shaped command that `main` would not gate, and the
  incident row names the cause.
- **Dependency:** perl ≥ 5.10 with core modules only. This host has 5.42.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- **Never run a bare filing shape as an ad-hoc Bash call.** The live hook gates it, and once the
  patched hook is active, that includes `bash -c` and `$(…)` forms. Test only through the committed
  suites.
- **The `--differential` oracle must never reach a real `gh`.** That means:
  - no absolute `gh` paths in generated commands;
  - shims first in `PATH`;
  - an invalid `GH_TOKEN`/`GH_HOST`;
  - a tmp `GH_CONFIG_DIR` and a tmp CWD.
- **Never place a corpus read or `new URL(…, import.meta.url)` in `cron-bash-allowlist-hook.mjs`.**
  It is in the Next.js server bundle (#8074).
- **Use the `read -r -d ''` loop with the appended `RC` record, and parse records by count.**
  `mapfile -d ''` and `$(…)` lose the producer's exit code, and `$(…)` also drops NUL bytes.
- **Bump both literal floors in the same commit that adds rows.**
- **Keep `$J` out of double-quoted runner strings** and use `$K` there. `$J`'s inner quotes close
  the outer string.
