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

This is revision 3. It folds in:

- the CTO domain review, the spec-flow analysis and the scoped advisor consult (revision 2);
- the plan-review panel (DHH, Kieran, code-simplicity, CTO devex lens) in revision 3.

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
- **ADR:** ADR-157 already rules that "a hook that cannot parse its input asks". This plan amends it
  rather than opening a new ordinal (see `## Architecture Decision (ADR/C4)`).

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
  - A body that references a variable falls back to `main`'s `$COMMAND` corpus.
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
- **A new ADR-256** (DHH, simplicity): cut. ADR-157 is amended instead.

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

**Layout contract (CTO devex).**

- `use strict; use warnings;`.
- A header with a grammar sketch, the gh version the flag tables were taken from, and the
  predicate and parity notes.
- The flag tables and the string-runner list are data at the top of the file.
- One sub per construct.
- The suite runs `perl -c` on the file.

**Modes.**

| Invocation | Input | Output |
|---|---|---|
| `perl filing-shape.pl` (default) | The raw command on stdin | One NUL-framed record per filing: `F\0<shape>\0<ctx>\0<nfields>\0<key>=<value>\0…`. After the last record it prints `OK\0` and exits 0. Details follow the table |
| `perl filing-shape.pl --classify tok…` | One token list | `create`, `api` or `none`. This is the corpus entry point, and it runs the same `filing_shape` sub |
| `perl filing-shape.pl --trace` | A command | Each simple command's argv, its full wrapper path (e.g. `shell-c>subst`) and the parsed fields, in plain text. Named in the file header and in every lexer-failure incident, for debugging a false deny |

In default mode:

- `<shape>` is `create` or `api`.
- `<ctx>` is the innermost wrapper, one of `top`, `subst`, `backtick`, `shell-c`, `eval` or
  `heredoc`.
- Consumers parse records **by count** and never search for the `OK` or `F` sentinels.

Default mode has two failure exits:

- **Exit 2:** an unbalanced quote or an unterminated construct. The agent can fix this.
- **Exit 3:** a bound tripped. That means recursion deeper than 16, a character budget of
  8 × input + 64 KiB lexed in total, or `alarm 2`. This is our machinery failing.

**Lexing** is one recursive-descent pass with a frame stack. A substitution is lexed in place from
the same cursor, never by finding the closing `)` first. That is what lets a heredoc body inside
`$(cat <<'EOF' … EOF)` contain `)`, `(`, `it's` or `` ` ``.

- **Quoting.**
  - `'…'` is literal.
  - In `"…"`, `\` escapes only `$`, `` ` ``, `"`, `\` and newline. `$(`, backticks and `${` stay
    live.
  - `$'…'` and `$"…"` are treated as quoted words. Their escapes are **not** decoded (Non-Goal).
  - Outside quotes, `\` makes the next character literal, and `\`-newline continues the line.
- **Separators.** These end a simple command: an unquoted newline, `;`, `&`, `|`, `&&`, `||`, `|&`,
  `;;`, `;&`, `;;&`, `(` and `)`.
  - A redirection's `&` or `|` is not a separator: `2>&1`, `&>`, `>&2`, `>|` and `<&0`.
  - `{` and `}` are ordinary words. Any-position detection makes them harmless.
- **Redirections.** A redirection is an optional fd number, then one of `<`, `>`, `>>`, `>|`, `<>`,
  `>&`, `<&`, `&>` or `&>>`. The redirection and its target word are dropped from argv, but
  substitutions inside the target are still recursed.
- **Substitutions.** Every `$(…)`, backtick span, `<(…)` and `>(…)` is lexed as a script, wherever
  it appears. The same holds for every substitution *inside* `${…}` and `$((…))`. The text of
  `${…}` itself is never lexed as a script. A word's value keeps the raw source of its
  substitutions, so `repos/$(echo o)/r/issues` stays one token.
- **Comments.** `#` starts a comment only at the start of a word, and the comment runs to the end
  of the line. Nothing in a comment is recursed.
- **Heredocs** are handled natively; the lexer does not use `_incidents_heredoc_re`.
  - Several heredocs may be pending on one line. Each body starts at the **next unquoted newline**,
    so the rest of the opening line is still code.
  - Quoting the delimiter in any way (`'EOF'`, `"EOF"`, `\EOF`, `E"OF"`) makes the body data.
  - An unquoted body is scanned for `$(`, backticks and `${`, and those are recursed.
  - `<<-` strips leading tabs before matching the terminator. A missing terminator reads to EOF.

**Finding filings.** In each simple command's argv, every index `i` whose word's basename is `gh`
starts a candidate. The candidate's argv is normalized so `argv[i]` becomes `gh`, and then
`filing_shape` classifies it.

- This covers `sudo gh`, `setsid gh`, `flock f gh`, `doppler run -- gh`, `/usr/bin/time -v gh`,
  `find -exec gh …` and `then gh`, with no launcher table.
- **Deliberate over-fire:** an unquoted `echo gh issue create` is classified as a filing, and so is
  `bash -c 'echo gh issue create'`. Both err toward gating (DC-2).

**String runners** are the only list.

- `bash|sh|zsh|dash|ksh` (any argv position) with an option cluster containing `c`, such as `-c`,
  `-lc` or `-ec`. Options like `--norc`, `-o opt` or `--` may come first. The script is the first
  non-option word after the cluster.
- `eval`, whose words are joined with spaces.

**Per-filing fields.** They are parsed with gh's value-taking flag tables, pinned in Phase 0 from
`gh issue create --help` and `gh api --help` (gh 2.101.0). A token counts as a flag only when it is
not the value of a preceding value-taking flag.

| Field | Meaning |
|---|---|
| `head=…` | `gh issue create`, or `gh api <path>`, with the path cut at `?`/`#` and capped at 64 characters |
| `repo=…` | From `-R`, `--repo`, `-R=`, `--repo=` or `-Rx`, at the root or group level. A value containing `$` or a backtick is **never external** |
| `milestone=1` | Present when the filing has `-m`, `--milestone`, `--milestone=` or `-mX` |
| `label=…` | From `--label`/`-l` and their `=`/attached forms, and from `-f`/`-F`/`--field`/`--raw-field`/attached `labels[]=…`. Repeatable |
| `bodyfile=…` | From `--body-file` or `-F` (create only), and their `=` forms |
| `body=…` | The literal inline body from `--body`/`-b`, or an api `body=` field in any spelling. Repeatable. If the value contains an unquoted `$` expansion, the record carries `bodyvar=1` instead, and bash falls back to `$COMMAND` (`main`'s corpus) |
| `input=1` | Present when an api filing has `--input` or `--input=` |

### 2. `guardrails.sh` wiring

- **The lexer always runs** (Kieran: no prefilter). Its records are read with a
  `while IFS= read -r -d ''` loop, which works on bash 3.2. The loop reads from a process
  substitution that appends the producer's exit code as `RC\0<n>\0`.
- **Filings are the union of the lexer's records and `main`'s detectors** (PR7). The CLASS 1 `$SCAN`
  grep and `_api_pl` stay, and they are commented as the floor.
- **Each lexer record goes through `_gate_one_filing`.** This function holds the existing
  milestone, external-repo and three-exit logic. It now reads the record's fields, not `_repo_toks`
  and not `$COMMAND`, except when `bodyvar` is set. The `xargs -n1` tokenizer and its three token
  loops are deleted.
- **A deny names the filing's head and context.** It adds the clause "add the exit inside the same
  `<ctx>` command as `gh`" (CTO devex). Two refusals get extra hints:
  - For `ctx=backtick`, or `heredoc` from an unquoted delimiter: "bash executes backticks and
    unquoted-heredoc text. If this was prose, use single quotes or `<<'EOF'`."
  - When a relative `bodyfile` cannot be read: "pass an absolute path".
- **Failure path.** This covers lexer exit 2 or 3, a missing `OK`, a malformed stream, no perl, and
  a floor hit that the lexer did not report. If the raw `$COMMAND` matches the loose indicator
  `gh.*(issue[^A-Za-z0-9_]+(create|new)|issues)`:
  1. **Exit 2 denies** with `TOK_MSG`.
  2. **Otherwise, if the floor fires, the hook denies**, since those are the cases `main` itself
     gates. The message: "the filing gate could not parse this command (`<cause>`); run the filing
     as a plain top-level command with an absolute `--body-file` path." The existing no-perl row
     keeps its `deny` this way.
  3. **Otherwise the hook asks** (ADR-157): "the filing gate could not parse this command
     (`<cause>`). Approve only if it does not file an issue."

  One incident code, `guardrails-filing-lexer-failure`, carries the cause. If the indicator does
  not match, the hook allows, which is what `main` does for a command that is not a filing.
- **Unchanged:** `$SCAN`, `strip_command_bodies` and every other gate.

### 3. The shared predicate (one spec, two implementations)

```text
filing_shape(tokens):
  tokens[0] != "gh"                                  -> none   # the hook normalizes the basename first
  pos = tokens after index 0 that are not flags, skipping the value of a bare -R / --repo
        (root- or group-level; not -R=x, --repo=x, -Rx)
  pos[0] == "issue" and pos[1] in {create, new}      -> create
  pos[0] == "api":
      endpoint = SOME token matches ISSUES_COLLECTION_RE, or is a bare $VAR / ${VAR}
                 (a $-only endpoint leans toward gating)
      post     = SOME token i satisfies POST_SIGNAL
      endpoint && post                               -> api
  otherwise                                          -> none

ISSUES_COLLECTION_RE (case-sensitive; Perl uses \z where JS uses $):
  /(?<![A-Za-z0-9_])repos\/[^\/?#\s]+(?:\/[^\/?#\s]+)?\/issues(?:\/?(?:[?#].*)?|[$})][^\/]*)$/

POST_SIGNAL(tokens, i), with C = an optional run of the boolean short flag -i (gh api's only one):
  t matches /^-C?X$/ or t == "--method", and the next token matches /^post$/i or starts with $ or `
  or t matches /^(-C?X=?|--method=)(post$|\$|`)/i       # -XPOST, -X=POST, -iXPOST, --method=POST, -X$M
  or t == "--input" or t starts with "--input="
  or t matches /^-C?[fF]$/ or t is --field / --raw-field, and the next token starts with title=, $ or `
  or t matches /^(-C?[fF]=?|--field=|--raw-field=)?title=/   # -ftitle=, -F=title=, -iftitle=, bare title=
  or t matches /^(-C?[fF]=?|--field=|--raw-field=)[$`]/     # -f$T (prefix required, so --jq "$Q" is not a signal)
```

**The corpus.** A new file, `.claude/hooks/lib/filing-shape-corpus.json`, is an array of entries of
the form `{"id": "C<n>", "tokens": [...], "shape": "create"|"api"|"none", "why": "..."}`. Two
suites load it:

- `filing-shape.test.sh` runs every row through `--classify`;
- the vitest runs every row through `filingShape(tokens) ?? "none"`.

Both assert a **literal** row floor and require all three shape classes to be present.

### 4. The cron mirror

- **`filingShape()`:** export `ISSUES_COLLECTION_RE`, and implement the predicate above (POST_SIGNAL,
  root-level `--repo`, the `gh issue new` alias, the `-R` skip, `$`-only endpoints).
- **`filingJustificationReason()`:** an `api` shape with an `--input`/`--input=` token returns the
  hook's `--input` refusal. The check runs **before** exits 0 and 1.
- **`cron-filing-deny-marker.ts`:** import the regex, delete the local `ENDPOINT_RE`, and cut the
  head at `?` or `#`.

### 5. The executed oracle and the differential corpus (opt-in, not CI)

`filing-shape.test.sh --differential <base-hooks-dir>` is committed, so the result can be
reproduced (CTO devex). It is not run in CI.

**How each command runs.**

- Each generated command runs through real bash with shims first in `PATH`, then `/usr/bin:/bin`.
  - The `gh` shim logs its argv.
  - The `sudo` shim execs the rest of the argv.
  - The `git` shim does nothing.
- Guards against reaching a real `gh`:
  - `GH_TOKEN=invalid`, `GH_HOST=invalid.invalid` and a tmp `GH_CONFIG_DIR`;
  - a tmp working directory, and each command wrapped in `timeout 5`;
  - no absolute `gh` path in any generated command.

**Ground truth comes from the logged argv, not from `--classify`** (Kieran #10). The shim decides
independently, using gh's own semantics:

- The path is the first positional argument after `api`.
- The method is the last `-X`. With no `-X`, it is POST if any field or `--input` is present.

**Checks.**

- Every truth filing must be reported by the lexer.
- Every row tagged `prose` must produce no filing.
- The patched hook's verdict is compared with the base hook's (`<base-hooks-dir>`, a scratch copy
  of `4170460eea:.claude/hooks/`). Every flip must be explained (AC5).

## Implementation Phases

Contract before consumer: each phase consumes only what an earlier phase produced.

**Phase 0: tests first.**

- Add the corpus, the `filing-shape.test.sh` rows and the `guardrails.test.sh` rows. Each row ID
  goes into its assert label (CTO devex).
- The suite header says where a new row belongs:
  - spelling → the corpus;
  - lexing → `filing-shape.test.sh`;
  - verdict and refusal text → `guardrails.test.sh`.
- Include the heredoc-inside-`$(…)` rows first, so the frame-stack design is forced by tests
  (advisor).
- Pin gh's flag tables and version from `--help`, and add a table-staleness row: when `gh` is on
  `PATH`, it compares the live `--help` value flags with the pinned tables; otherwise it skips.

**Phase 1: cron mirror + shared predicate.**

- Implement `ISSUES_COLLECTION_RE`, `filingShape`, the `--input` refusal and the deny-marker
  import.
- Vitest must be green. These are the first commits, so the live cron bypass can be cherry-picked
  on its own if needed (DC-1).

**Phase 2: `filing-shape.pl --classify`.** The corpus must pass on both sides.

**Phase 3: the lexer, per-filing fields, `--trace` and bounds.**

- Implement the lexer and the lexer-record rows.
- Run the `--differential` oracle pass once, before wiring (advisor). It must show no misses and no
  prose over-fire.

**Phase 4: wire `guardrails.sh`.**

- Add `_gate_one_filing`, the union floor and the failure path. Delete `xargs -n1`.
- Update every comment that still describes `$SCAN`-based detection.
- Run `guardrails.test.sh` and `hook-input-contract.test.sh`.

**Phase 5: record and verify.**

- Add the ADR-157 addendum.
- Run AC5 again against the final tree.
- Run `plugins/soleur/test/c4-count-parity.test.sh`.

**Phase 6 (at ship).**

- File ONE residual follow-up issue listing the Non-Goals, with the `meta/machinery` label and the
  `Post-MVP / Later` milestone. Both exist (verified).
- Close #9089 from the PR body.

## Files to Create

- `.claude/hooks/lib/filing-shape.pl`: the lexer, the string runners, the field parser, the
  predicate and the bounds, with the default, `--classify` and `--trace` modes.
- `.claude/hooks/lib/filing-shape-corpus.json`: the shared token-level corpus, with a floor of
  75 rows.
- `.claude/hooks/lib/filing-shape.test.sh` covers:
  - corpus parity (the Perl side);
  - lexer-record rows (exit 0, `OK` and exact fields);
  - the bounds rows and `perl -c`;
  - the flag-table staleness row;
  - `--probe`;
  - `--differential` (opt-in).

## Files to Edit

- `.claude/hooks/guardrails.sh`, in the filing-gate block:
  - the lexer call and the record reader;
  - `_gate_one_filing` and the union floor;
  - the failure path;
  - the refusal texts (head, ctx, the in-command clause, the prose hint, the absolute-path hint);
  - deletion of `xargs -n1` and the three token loops;
  - header comments rewritten.
- `.claude/hooks/guardrails.test.sh`:
  - the new rows (Test Scenarios), with `MIN_ASSERTIONS` bumped in the same commit;
  - the "quoted endpoints on both sides of && are blanked" comment rewritten (its verdict stays
    `<none>`, now for a different reason);
  - the `TOK_MSG` rows kept.
- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`: `ISSUES_COLLECTION_RE`,
  `filingShape` and `filingJustificationReason`.
- `apps/web-platform/server/cron-filing-deny-marker.ts`: import the regex and cut the head at
  `[?#]`.
- `apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts`:
  - the corpus `it.each`, with a literal floor;
  - the `--input` refusal and its reorder row;
  - two rows pinning that `decide()` denies `URL=$(gh issue create …)` and
    `bash -c "gh issue create …"`.
- `apps/web-platform/test/server/cron-filing-deny-marker.test.ts`: a `#fragment` head row.
- `knowledge-base/engineering/architecture/decisions/ADR-157-a-hook-that-cannot-parse-its-input-asks.md`:
  an addendum (see `## Architecture Decision (ADR/C4)`).

## Open Code-Review Overlap

None. No open `code-review` issue names any of the files above (queried 2026-09-28, a 200-issue
window).

## Non-Goals (re-homed to the follow-up issue at ship)

- **Other filing routes:**
  - GraphQL `createIssue` (labels there are ids, so exit 1 has no token to read);
  - `curl -X POST …/repos/o/r/issues`;
  - variables not assigned as a literal in view.
- **Computed or escaped command words:** `$'…'` escapes (`$'\x67h'`), brace expansion
  (`gh {issue,} {create,}`), globs in `argv[1..2]`, and `$(printf gh)`.
- **String runners beyond shells and `eval`:** `trap`, `watch`, `su`/`runuser -c`, `script -c`,
  `env -S`, a shell fed a heredoc or here-string, `ssh host STR`, `bash script.sh`,
  `printf … | bash`, and `parallel ::: "…"`.
- **`xargs`/`parallel` completed from stdin:** `printf 'issue create …' | xargs gh` and
  `echo -X POST … | xargs gh api …/issues`.
- `.claude/hooks/follow-through-directive-gate.sh`, and the spellings in
  `scripts/lint-workflow-issue-write-scope.py`'s `MUTATING_METHOD`.
- **Cron mirror exits:** `labelTokenEquals` and the body loop still ignore flag values, and
  `argumentInjectionReason` does not refuse `--input <file>` to non-issue endpoints.
- **The endpoint owner is not read**, so an api-form POST to another owner's repo is not exempt.
- **Over-gating that errs toward gating:**
  - `-X GET` with fields or with `--input`;
  - `gh issue create --help`;
  - an unquoted `echo gh issue create`, and `bash -c 'echo gh issue create'`;
  - `a=(gh issue create)`, and a function body defined but never called;
  - a `$`-only endpoint that is not an issues collection;
  - a comment POST whose body token ends in `repos/o/r/issues` (Kieran #14 proposes matching only
    the first positional argument instead; see DC-3).

## Technical Considerations

- **Performance.**
  - One extra perl fork runs on every Bash call. That is 13 ms per 64 KB of input, measured.
  - The depth limit, the character budget and `alarm 2` bound the pathological cases. Tripping any
    of them returns exit 3.
- **Fail direction.**
  - Detection is the lexer **plus** `main`'s detectors, so the hook is never weaker than `main`.
  - A lexer failure on a command that looks like a filing never allows it: it denies when `main`
    would gate the command or the agent can fix it, and asks otherwise (ADR-157).
- **Over-fire.** Recursing into every substitution is correct, because bash runs them. The risk is
  the lexer misreading prose as code, which three things pin:
  - the PR3 must-PASS rows, each also asserting that the lexer exits 0 and prints `OK`;
  - the oracle's `prose` rows;
  - the every-commit shape, run with hostile heredoc bodies.
- **Portability.**
  - Perl uses core modules only, with NUL-framed output, so no JSON module is needed.
  - The record reader works on bash 3.2.
  - Test code reads the corpus with `jq`.
- **Attack surface enumeration.**
  - **Covered (PR1/PR2):** `gh issue create|new` and REST `gh api` POSTs, in any executed position
    this lexer models.
  - **Re-homed:** the Non-Goals list.
  - **Cron:** `decide()` stops every substitution and non-allowlisted verb before `filingShape`
    runs, so for cron the predicate's spelling set is the whole surface (PR5).
- **Bundle safety.** The mirror gets no new import and no asset reference, and only tests read the
  corpus.

## Architecture Decision (ADR/C4)

### ADR

The plan amends **ADR-157** ("a hook that cannot parse its input asks") with a dated addendum. The
addendum records three decisions:

1. **Parse failures in the filing gate.** When the lexer fails, the hook denies if the agent can
   fix the command or `main` would gate it, and asks if our own machinery failed. The addendum
   records the loose indicator and the union floor.
2. **Lexing replaces blanked-text grepping.** Filings are classified by lexing the command, not by
   grepping text with quotes blanked. The hook and the cron mirror share a predicate spec that one
   corpus enforces; they do not share code.
3. **Build-vs-buy alternatives, each rejected (CTO devex):**
   - `shfmt --to-json`: a Go binary that is not on operator hosts, and `-c` strings would still
     need re-parsing.
   - tree-sitter-bash: heredocs inside `$(…)` are unreliable.
   - `bashlex`: unmaintained and not installed.
   - `bash -n`: produces no argv.
   - `Text::ParseWords`: measured failing.

   A CI-only shfmt cross-check is noted as a possible follow-up.

Why an addendum and not a new ADR: the fail direction extends ADR-157's own rule, and the parity
contract lives in `filing-shape.pl`'s header, next to the code it constrains (DHH, simplicity). The
CTO had asked for a new ADR (DC-4).

### C4 views

No C4 impact. All three model files were checked
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External human actors:** none new. The agent's envelope is already modeled as `claude -> hooks`
  ("Tool-call envelope on stdin — MODEL-CONTROLLED, UNTRUSTED (ADR-156)…").
- **External systems:** none new. The hook calls no service.
- **Containers and data stores:** the Hook Engine container is modeled, and its description
  ("Guards tool calls …") stays true. The new file is a library inside that container. No data
  store is touched.
- **Access relationships:** none change.

Phase 5 must also show `plugins/soleur/test/c4-count-parity.test.sh` green.

### Sequencing

The addendum is true at merge. There is no soak period.

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
  what: "filing-shape.test.sh verdict line (corpus parity, lexer records, bounds, flag-table staleness) and guardrails.test.sh verdict line, each under a literal MIN_ASSERTIONS floor, plus the corpus it.each in cron-bash-allowlist-hook.test.ts"
  cadence: "every scripts/test-all.sh run and every CI run (both .test.sh suites are glob-discovered; the vitest runs in the web-platform test job)"
  alert_target: "a RED suite fails its CI leg and blocks the PR"
  configured_in: "scripts/test-all.sh SUITE_GLOBS (.claude/hooks/*.test.sh, .claude/hooks/lib/*.test.sh), scripts/suite-shard-legs.tsv, apps/web-platform vitest config"

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
  expected_output: "PROBE create"
```

`--probe` runs exactly one lexer call, on `URL=$(gh issue create --title x)`, and prints
`PROBE <shape>`. It takes well under a second. Check 10's allowlist does not include `perl`, which
is why the probe goes through `bash`.

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
| G1-9 | `\|` not a separator | RED: D43, `gh issue create --title x --body y -m M \| tee --label meta/machinery`, which must deny. `tee`'s `--label` would otherwise read as the filing's exit |
| G1-10 | Quoted-delimiter heredoc bodies lexed as code | RED: P5, P6, whose body lines START with `gh issue create --title x --body y` |
| G1-11 | Single-quoted spans lexed as code | RED: P7 |
| G1-12 | `${…}` text lexed as a script | RED: P8 |
| G1-13 | Comments not skipped before substitution recursion | RED: P9 |
| G1-14 | Own dispatch: a lexer exit ≠ 0 read as "no filings" | RED: F-exit2 and F-exit3 run on `URL=$(gh issue create …)`, which the floor cannot see |
| G1-15 | Own dispatch: `OK`/`RC` check removed, so a truncated stream reads as complete | RED: F-trunc, a shim printing a partial record on `URL=$(gh issue create …)` and exiting 0 |
| G1-16 | Floor removed from the union | RED: F-floor, a lexer shim printing only `OK` on a bare top-level create |
| G1-17 | Second member: only the first record is gated | RED: D29 |
| G1-18 | Reorder: records parsed by searching for `OK` instead of by count | RED: F-count, a shim record whose field value contains `OK\0` and whose `nfields` is correct. A search-based parser stops early and drops the second filing |

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
`_repo_toks` remains in the filing path, and the only reader of `$COMMAND` is the `bodyvar`
fallback.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| G2-1 | Fields computed over the whole command | RED: D24, D25, D26, D35 |
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
| G3-5 | Second member: only the first corpus row asserted | RED: the literal floor |
| G3-6 | The deny marker keeps a local `ENDPOINT_RE` without `#` | RED: the deny-marker fragment row |
| G3-7 | Reorder: the cron `--input` refusal moved after exit 1 | RED: "`--input` with `-f labels[]=meta/machinery` still denies" |
| G3-8 | POST_SIGNAL's `$` arm loses its required prefix | RED: C-row `gh api repos/o/r/issues --jq "$Q"` → `none` |

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
  - `[base-deny]` marks rows the base already denies (D28's `_api_pl` spellings, D34) or must-PASS
    rows the base denies (P16, the `-m` form). D36 is base-denied too. Those rows pin the patched
    behavior and are
    excluded from the RED check.
- [ ] **AC3.** Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bash-allowlist-hook.test.ts test/server/cron-filing-deny-marker.test.ts`.
  It passes, and the corpus test asserts `corpus.length >= 75` as a literal.
- [ ] **AC4.** The corpus holds at least 75 rows, covering:
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
- [ ] **AC6 (bounds, asserted by exit code, not wall clock).**
  - A 20-deep nested `bash -c` gives lexer exit 3.
  - A 12-deep `bash -c "$(…)"` nesting gives exit 3 from the character budget.
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
  - ADR-157 carries the dated addendum;
  - the PR body carries `Closes #9089` and links the residual follow-up issue.
- [ ] **AC11.** `bash .claude/hooks/lib/filing-shape.test.sh --probe` prints `PROBE create`.

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
flag-table staleness row, a Perl layout contract, and build-vs-buy alternatives in the ADR
addendum.

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
| Assignment map unsound and over-built | Kieran #4, DHH #5, simplicity | Cut. `$`-only endpoints gate, a `$` repo is never external, and a `$` body falls back to `$COMMAND` |
| Stdin completion, string-runner tail, `$'…'` decoding | DHH #7-#8, simplicity, Kieran #3/#9 | Moved to Non-Goals |
| Prefilter bypassable (`g''''h`) | Kieran #3 | Cut; the lexer always runs |
| Five exit codes and a separate disagreement branch | DHH #3-#4, simplicity | Two exit codes and a plain union floor |
| `$J` breaks rows inside `bash -c "…"`; P13 contradicted the over-fire; AC2 inconsistent with base-denied rows; D39 double-defined | Kieran #1, #2, #5 | `$K` for double-quoted runners, `bash -c 'echo …'` moved to D32, `[base-deny]` tags, D39 renamed P21 |
| Mutations that could not go RED (G1-8, G1-9, G1-18) and failure rows the floor masked | Kieran #6-#7 | New witnesses (D43, F-count), and failure rows run on floor-invisible commands |
| Predicate: basename vs `tokens[0]`, `$` arm too broad, `-i` clusters, Perl `$` vs `\z`, root `--repo` | Kieran #8, #11 | Normalize before classify, prefix-required `$` arm, `-i` clusters, `\z`, and root `--repo` (verified) |
| Property IDs collided with row IDs | Kieran #12 | Properties renamed PR1-PR8 |
| New ADR vs. amend | DHH #10, simplicity vs. CTO | Amend ADR-157 (DC-4) |
| `--probe` ceremony | simplicity, DHH #11 | Kept: Check 10's allowlist excludes `perl`, so the probe needs `bash` |

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
    (the justification gate fires)
  - D36 `[base-deny]` `gh issue create --title -mx --body y --label meta/machinery` (the milestone gate fires)
  - D37 `gh issue create --title x --body --label=meta/machinery --milestone M`
  - D38 `gh issue create --repo "$OWNER/soleur" --title x --body y`
  - D40 `EP=repos/jikig-ai/soleur/issues; gh api "$EP" -X POST -f title=x`
- **POST spellings, multiple filings and parsing:**
  - D28 `[base-deny]` One row each: `… -X=POST -f title=x`, `… -ftitle=x`, `… --input=b.json`,
    `… -X "$M" -f title=x`, `… -iXPOST -f title=x`, `… -iftitle=x`
  - D29 `gh issue create --title a --body b$J; bash -c "gh issue create --title x --body y"`
  - D30 `gh issue create --title a --body b$J && gh api repos/jikig-ai/soleur/issues -X POST -f title=x`
  - D34 `[base-deny]` `gh issue create --title OK --body RC`
  - D43 `gh issue create --title x --body y -m M | tee --label meta/machinery`

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

- the corpus `it.each`, with its literal floor;
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
