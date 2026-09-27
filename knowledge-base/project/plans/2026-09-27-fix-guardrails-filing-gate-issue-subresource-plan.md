---
title: "fix(hooks): guardrails filing gate treats POSTs to an existing issue's sub-resources as new filings"
date: 2026-09-27
slug: fix-guardrails-filing-gate-issue-subresource
branch: feat-one-shot-guardrails-filing-gate-subresource
issue: none
closes: none
type: bug
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(hooks): guardrails filing gate fires on `gh api -X POST .../issues/<N>/labels`

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The issue-filing gate in `.claude/hooks/guardrails.sh` has a trigger for the `gh api` form of
creating an issue (the in-code comment calls it "CLASS 4 of the filing surface"). It decides "this
is a filing" when two things hold:

1. **An endpoint match:** `gh\s+api\b[^|]*\brepos/[^[:space:]]+/issues\b`, run against `$SCAN`.
2. **A POST signal:** `(-X|--method)[[:space:]]+POST|-f[[:space:]]+title=|--field[[:space:]]+title=`.

`[^[:space:]]+` spans `/`, and `\b` after `issues` is satisfied by the `/` that starts the next path
segment. So a POST to an existing issue's sub-resource is treated as a new filing. It then goes to
the filing-justification gate and is denied unless it carries `meta/machinery`, a `Mandated-By:`
claim, or a `User-Impact:` + `Fix-Size:` pair. That blocks routine agent work: adding a label,
posting a comment, assigning someone.

This plan narrows the endpoint to the **collection** only (`repos/<o>/<r>/issues`, with an optional
trailing `/` and an optional `?query`, and nothing further in the path). The same hunk also closes
the collection-endpoint escapes measured below. Two things were measured before the design was
fixed: which commands the new predicate newly allows, and which it newly denies.

**Measured on this branch's base (`b3d5652e7b`), with payloads fed to the hook on stdin from a non-git temporary working directory:**

| Command (owner/repo = `jikig-ai/soleur`) | Today | Wanted |
|---|---|---|
| `gh api -X POST repos/R/issues/123/labels -f 'labels[]=type/bug'` | **deny** | allow |
| `gh api -X POST repos/R/issues/123/comments -f body=hi` | **deny** | allow |
| `gh api -X POST repos/R/issues/123/assignees -f 'assignees[]=me'` | **deny** | allow |
| `gh api "repos/R/issues" -X POST -f title=x -f body=y` (double-quoted path) | **allow** | deny |
| `gh api 'repos/R/issues' -X POST …` or `'repos/R/issues?x=1&y=2'` (single-quoted) | **allow** | deny |
| `gh api repos/"$REPO"/issues -X POST …` (partially quoted) | **allow** | deny |
| `gh api repos/R/issues -XPOST -f body=y` / `--method=POST` / `-X=POST` | **allow** | deny |
| `gh api repos/R/issues --input b.json` (gh defaults to POST) | **allow** | deny |
| `gh api repos/R/issues -F title=x …` / `--raw-field title=x …` / `-ftitle=x` | **allow** | deny |
| `gh api repos/R/issues -f "title=Fix the thing" -f body=y` (no explicit method) | **allow** | deny |
| `gh api \⏎ repos/R/issues \⏎ -X POST …` (backslash continuation) | **allow** | deny |
| Unquoted `repos/R/issues?x=1`, trailing `/`, `/repos/…`, `{owner}/{repo}`, `$REPO` forms | deny | deny (keep) |

The quoted-path escapes come from `strip_command_bodies` (`.claude/hooks/lib/incidents.sh`), which
builds `$SCAN` by blanking every quoted span. That is correct for keeping commit-message prose out of
detection, but it also removes a quoted endpoint or a quoted `title=` value. The cron-substrate
mirror of this gate, `filingShape()` in `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`,
already matches collection-only over dequoted tokens.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Matcher near "CLASS 4 of the filing surface", lines ~471-484 | Confirmed: comment at `guardrails.sh:471`, matcher at `:482-484` | Edit there |
| Second reference near line 649 (`… -X POST -f 'labels[]=meta/machinery'` was denied) | That line is **comment prose** in the exit-1 label reader. It is not a matcher, and it already describes the collection endpoint | No change. It stays accurate |
| "check any sibling copy of the same matcher elsewhere" | `git grep` finds exactly one other implementation: `filingShape()` in `cron-bash-allowlist-hook.mjs` (imported by `apps/web-platform/server/cron-filing-deny-marker.ts`). It **already** uses the collection-only regex `(^|\/)repos\/[^/?]+\/[^/?]+\/issues\/?(\?[^/]*)?$` plus `-XPOST`/`--method=POST`/`--input`/`-F title=`, and it has test rows for sub-resource allow (`cron-bash-allowlist-hook.test.ts`, the test titled "still allows a non-create endpoint under the same prefix") | No edit. The mirror is the reference shape. `scripts/lint-workflow-issue-write-scope.py` also matches `gh api` lines, but it is a workflow-scope lint and not a filing gate. Out of scope |
| "a quoted path must not become a bypass" | It is **already** a bypass on main (table above), as are partial quoting, `-XPOST`, `--method=POST`, `--input`, `-F`/`--raw-field title=` and a multi-word quoted `title=` | Closed in this hunk (see the first-word transform) |
| Test suite ".claude/hooks/guardrails*.test.sh or similar" | `.claude/hooks/guardrails.test.sh` (127 assertions, `MIN_ASSERTIONS=127` floor, `assert <label> <want> <cmd>` helper, CLASS 4 block at `:809-824`). CI runs it as a shard leg (`scripts/suite-shard-legs.tsv:22`) | Add rows beside the CLASS 4 block and bump the floor |

## Proposed Solution

### 1. The trigger: one source string, one endpoint regex, one signal regex

Replace the three-line trigger at `guardrails.sh:482-484` with:

```bash
_api_first_words() {
  local c; c="$(cat)"
  printf '%s' "$c" | perl -0777 -pe 's/"((?:[^"\\]|\\.)*)"|'\''([^'\'']*)'\''/my $w = defined $1 ? $1 : $2; $w =~ s{^\s*(\S*).*}{$1}s; $w/gse' 2>/dev/null \
    || printf '%s' "$c"
}
if grep -qE 'gh\s+api\b' <<<"$SCAN"; then
  _api_src="$(strip_heredocs "$COMMAND" | _api_first_words | tr '\n' ' ')"
  grep -qE 'gh\s+api\b[^|]*[[:space:]/"'\'']repos/[^[:space:]]+/issues/?([?[:space:];&|()<>`\\"'\'']|$)' <<<"$_api_src" \
    && grep -qE '(^|[[:space:]])((-X|--method)[[:space:]=]*POST\b|--input([[:space:]=]|$)|(-f|-F)[[:space:]=]*title=|(--field|--raw-field)[[:space:]=]+title=)' <<<"$_api_src" \
    && _gh_api_issue=1
fi
```

The presence check on `$SCAN` is unchanged. It is now a **cost pre-filter**: it keeps `perl` from
spawning on every Bash call that does not invoke `gh api`. It is not what keeps commit-message prose
out, because the transform below does that on its own (a mutation that moves it to `$COMMAND`
leaves every row green).

`_api_first_words` is the core of the design. It reduces every quoted span to its **first
whitespace-delimited word**, processing `"…"` and `'…'` spans in one left-to-right pass:

- **A quoted argument** loses only its quotes. `"repos/R/issues"` becomes `repos/R/issues`,
  `repos/"$REPO"/issues` becomes `repos/$REPO/issues`, `-f "title=Fix the thing"` becomes
  `-f title=Fix`, and `-f "title"=x` becomes `-f title=x`. These are exactly the escapes above.
- **Quoted prose** collapses to one word. `-f body="use gh api repos/R/issues to list"` becomes
  `-f body=use`. `-b "try -X POST"` becomes `-b try`. A quote **nested** inside a body
  (`-f body="the create endpoint is 'repos/R/issues'"`) is consumed with its outer span, because the
  outer span is matched first.
- **Failure mode.** On a `perl` error the helper returns its input unchanged, the same contract as
  `strip_command_bodies`. Quotes then survive, and the endpoint prefix class and the terminator list
  both admit `"`/`'`, so the bare and fully-quoted endpoint shapes are still caught. The helper
  never makes the `$(…)` capture fail under `set -euo pipefail`, because it ends in `|| printf`.

The endpoint regex, applied to the transformed and newline-folded text:

- **Prefix `[[:space:]/"']` before `repos/`,** not `\b`. With `\b`, a one-word quoted body equal to
  the collection path (`-f body='repos/R/issues'` becomes `body=repos/R/issues`) would match on a
  sub-resource POST (mutation M9). The `/` in the class keeps `/repos/…` and the full
  `https://api.github.com/repos/…` URL, and the latter is newly caught.
- **Owner/repo stays one `[^[:space:]]+` word.** A two-segment `[^/]+/[^/]+` would stop matching
  `repos/$REPO/issues` and `repos/${GITHUB_REPOSITORY}/issues`, which are single shell words that
  expand to two segments. That would be a new bypass (M8).
- **Terminator: a closed list of word-ending characters.** After `issues[/]`, the next character must
  be `?`, whitespace, `;&|()<>`, a backtick, `\`, a quote, or end of line. Two alternatives were
  prototyped and rejected, each for a measured hole:
  - The list `[?[:space:];&|)]` missed `…/issues>out.json` and `` `…/issues` `` (M3).
  - A negated class `[^/[:alnum:]_-]` accepts `$` and `{`. It then re-denies
    `repos/$REPO/issues/$N/labels` and `…/issues/{number}/labels`, which is the defect itself,
    reintroduced for templated sub-resources (M17).
- **Newline fold** (`tr '\n' ' '`) closes the backslash-continuation escape. It can only widen
  matching, and every widening fails toward gating (M4).

The POST signal uses the same spellings as `filingShape()`: `-X POST`, `-XPOST`, `--method POST`,
`--method=POST`, `-X=POST`, `--input` (gh switches to POST when an input body is given), and a
`title=` field under `-f`, `-F`, `--field` or `--raw-field`. It also accepts the attached `-ftitle=x`,
which pflag accepts. **That form is a deliberate divergence:** `filingShape()` does not match it.
The signal is only consulted after the endpoint has matched the collection.

### 2. The `-F` misread in the body reader (CTO review, same file)

The body-corpus reader treats `-F` as `--body-file` for every filing. On `gh api`, `-F` is a typed
field, so `gh api repos/R/issues -X POST -F title=x -f 'body=Mandated-By: wg-…'` is refused with
"--body-file names title=x …". That refusal is wrong, and here it hides a valid exit-3 justification.
Newly gating `-F title=` makes this reachable more often. The fix, matching the mirror, is to read
`-F` as a body file only when `_gh_create == 1`:

```bash
        --body-file) _fj_bf="${_repo_toks[$((_fj_bi + 1))]:-}" ;;
        # -F is --body-file only for `gh issue create`; for `gh api` it is a
        # typed field (`-F title=x`), and reading it as a path mis-refuses.
        -F) [[ "$_gh_create" == 1 ]] && _fj_bf="${_repo_toks[$((_fj_bi + 1))]:-}" ;;
```

### 3. The exit-1 refusal text names the api spelling (CTO review)

Every newly gated command is a `gh api` command, but the exit-2/3 refusal ("this filing names no
user-visible consequence …") names only `--label meta/machinery` for exit 1. Append one sentence to
that string: `On the gh api form, exit (1) is spelled -f 'labels[]=meta/machinery', and an --input
JSON body is not read: pass the body with -f instead.` The `--input` half matters because the gate
never reads the JSON file, so an agent that put its labels and body there has no working exit
unless it is told to move them.

### 4. The CLASS 4 comment block

Rewrite the comment above the trigger (`guardrails.sh:471-479`) in five to eight lines:

- the endpoint is the collection only;
- the `$SCAN` presence check is a cost pre-filter that keeps `perl` off non-`gh api` commands;
- why each quoted span is reduced to its first word (a quoted argument is a word, and prose is not);
- why owner/repo stays one word;
- why the terminator is a closed list, not a negated class;
- `filingShape()` is the mirror that must agree.

Do **not** write the literal `_gh_api_issue=` in the comment, because the single-writer AC greps
for it.

### Alternatives considered and rejected

| Design | Why rejected (measured) |
|---|---|
| **Two endpoint arms**: bare arm on `$SCAN` plus a "wholly-quoted endpoint" arm on quote-preserving text, and two matching signal arms. This was the plan's v1, before review | DHH and Kieran each measured a **new** false positive of the class being fixed. A quote nested in a body (`-f body="see 'repos/R/issues'"`) satisfies "the whole span is the endpoint". `-b "use -f 'title=x'"` does the same for the signal. The first-word transform removes both, halves the regex count, and also closes partial quoting |
| **Tokenize at trigger time with `xargs -n1`** (the mirror's approach) | GNU `xargs` rejects the standard bash apostrophe idiom `'it'\''s'` ("unmatched single quote", measured). That would add a deny or fail-open mode for **non-filings**. Core Perl `Text::ParseWords::shellwords` does not have this problem (per the CTO review), so it is the fix direction recorded on #9089 |
| **Scope the POST signal per command segment** (split on `;`, `&&`, `\|\|`, `\|`) | Fixes the list-then-label over-fire (Non-Goals), but in a string representation it opens a split-the-flags escape: `-f "body=x;y"` puts the endpoint and the signal in different segments. Deferred to the tokenizer fix on #9089 |
| **Closed-list vs negated-class terminator** | See M3 and M17 above |

## Files to Edit

- `.claude/hooks/guardrails.sh`, four hunks and nothing else:
  - the CLASS 4 trigger at `:482-484` (§1);
  - its comment block at `:471-479` (§4);
  - the `-F` case in the body-corpus reader (the `--body-file|-F)` line, §2);
  - the exit-2/3 refusal string (the `names no user-visible consequence` reason, §3).
- `.claude/hooks/guardrails.test.sh`: 32 rows appended directly after the existing row
  `"filing-justification: gh api POST to another endpoint is untouched"` (CLASS 4 block), using the
  existing `assert` and `assert_reason` helpers. Bump `MIN_ASSERTIONS=127` to `159`, and extend the
  running-sum comment above it with `+ 32 CLASS 4 endpoint-scope rows = 159`.

<details>
<summary>The 32 rows as validated in planning (a scratch copy of <code>.claude/hooks/</code>: 159/159 green on the patched hook, 21 RED on main's hook)</summary>

```bash
# --- CLASS 4 endpoint scope: only the COLLECTION endpoint creates an issue.
# `repos/[^[:space:]]+/issues\b` spanned `/`, so a POST to an EXISTING issue's
# sub-resource (labels, comments, assignees) was denied as a new filing.
assert "filing-justification: POST to issues/<N>/labels is not a filing" "<none>" \
  "gh api -X POST repos/jikig-ai/soleur/issues/123/labels -f 'labels[]=type/bug'"
assert "filing-justification: POST to issues/<N>/comments is not a filing" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/issues/123/comments -f body=hi'
assert "filing-justification: POST to issues/<N>/assignees is not a filing" "<none>" \
  "gh api --method POST repos/jikig-ai/soleur/issues/123/assignees -f 'assignees[]=me'"
assert "filing-justification: quoted \$REPO sub-resource POST is not a filing" "<none>" \
  'gh api -X POST "repos/$REPO/issues/$N/comments" --input c.json'
assert "filing-justification: unquoted \$REPO/\$N sub-resource POST is not a filing" "<none>" \
  "gh api -X POST repos/\$REPO/issues/\$N/labels -f 'labels[]=x'"
# The collection endpoint still gates in every spelling gh routes to it.
assert "filing-justification: bare collection ?query still gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues?x=1 -X POST -f title=x -f body=y'
assert "filing-justification: quoted collection ?query gates (escape closed)" "deny" \
  "gh api 'repos/jikig-ai/soleur/issues?x=1&y=2' -X POST -f title=x -f body=y"
assert "filing-justification: collection trailing slash still gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues/ -X POST -f title=x -f body=y'
assert "filing-justification: leading-slash /repos path still gates" "deny" \
  'gh api /repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y'
assert "filing-justification: {owner}/{repo} placeholders still gate" "deny" \
  'gh api repos/{owner}/{repo}/issues -X POST -f title=x -f body=y'
assert "filing-justification: a single \$REPO segment still gates" "deny" \
  'gh api repos/$REPO/issues -X POST -f title=x -f body=y'
# Pre-existing escapes closed in the same hunk (measured on main: all ALLOWED).
assert "filing-justification: double-quoted collection path gates" "deny" \
  'gh api "repos/jikig-ai/soleur/issues" -X POST -f title=x -f body=y'
assert "filing-justification: single-quoted collection path gates" "deny" \
  "gh api 'repos/jikig-ai/soleur/issues' -X POST -f title=x -f body=y"
assert "filing-justification: -XPOST gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -XPOST -f body=y'
assert "filing-justification: --method=POST gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --method=POST -f body=y'
assert_reason "filing-justification: --input (gh defaults to POST) gates, and says the JSON is not read" \
  "an --input JSON body is not read" \
  'gh api repos/jikig-ai/soleur/issues --input b.json'
assert_reason "filing-justification: -F title= gates for the justification, not as a --body-file" \
  "names no user-visible consequence" \
  'gh api repos/jikig-ai/soleur/issues -F title=x -f body=y'
assert "filing-justification: api -F title= with a Mandated-By body reaches exit 3" "<none>" \
  "gh api repos/jikig-ai/soleur/issues -X POST -F title=x -f 'body=Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps'"
assert "filing-justification: --raw-field title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --raw-field title=x -f body=y'
assert "filing-justification: quoted -f \"title=\" gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f "title=x" -f body=y'
assert "filing-justification: attached short flag -ftitle= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -ftitle=x -f body=y'
assert "filing-justification: quoted multi-word -f \"title=…\" gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f "title=Fix the thing" -f body=y'
assert "filing-justification: partially quoted repos/\"\$REPO\"/issues gates" "deny" \
  'gh api repos/"$REPO"/issues -X POST -f body=y'
assert "filing-justification: a one-word quoted body equal to the collection path is a value, not the endpoint" "<none>" \
  "gh api -X POST repos/jikig-ai/soleur/issues/5/comments -f body='repos/jikig-ai/soleur/issues'"
assert "filing-justification: an api create inside a heredoc body is prose" "<none>" \
  $'cat > /tmp/soleur-note.md <<\'EOF\'\nrun: gh api repos/jikig-ai/soleur/issues -X POST -f title=x\nEOF\ngh api repos/jikig-ai/soleur/labels --jq length'
assert "filing-justification: quoted endpoint nested inside a body is prose, not the endpoint" "<none>" \
  "gh api -X POST repos/jikig-ai/soleur/issues/5/comments -f body=\"the create endpoint is 'repos/jikig-ai/soleur/issues'\""
assert "filing-justification: POST flags inside another command's quoted text are not a signal" "<none>" \
  'gh api repos/jikig-ai/soleur/issues --jq length && gh pr comment 1 -b "try gh api -X POST with -f title=x"'
assert "filing-justification: backslash-continued gh api gates" "deny" \
  $'gh api \\\n  repos/jikig-ai/soleur/issues \\\n  -X POST -f title=x -f body=y'
# Second member after a compliant first: a sub-resource POST must not mask a
# collection create later in the same command.
assert "filing-justification: create after a sub-resource POST still gates" "deny" \
  "gh api -X POST repos/jikig-ai/soleur/issues/5/labels -f 'labels[]=x' && gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y"
# Commit prose naming the create form is still not a filing: the message is
# one multi-word quoted span, so only its first word survives.
assert "filing-justification: commit message naming the api create form is not a filing" "<none>" \
  "git commit -m \"docs: gh api 'repos/jikig-ai/soleur/issues' -X 'POST'\""
# The collection path followed directly by a shell metacharacter is still the
# collection. The terminator is a CLOSED list of word-ending characters: a
# negated class would accept `$`/`{` and re-deny `issues/$N/labels`.
assert "filing-justification: collection path glued to a redirect still gates" "deny" \
  'gh api -X POST -f title=x -f body=y repos/jikig-ai/soleur/issues>out.json'
# An inline body that MENTIONS the collection path is prose, not the endpoint:
# each quoted span is reduced to its FIRST word before matching, so a
# multi-word body contributes only its first word.
assert "filing-justification: sub-resource POST whose body names the collection path is not a filing" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/issues/5/comments -f body="use gh api repos/jikig-ai/soleur/issues to list"'

```

</details>

## Files to Create

None.

## Open Code-Review Overlap

None. Checked `gh issue list --label code-review --state open` (200 max) against both file paths on
2026-09-27. There were no matches.

## Non-Goals

Every item below is recorded on **#9089** (`meta/machinery`, Post-MVP / Later), which also carries a
promotion trigger and the recommended fix direction: a `shellwords` tokenizer shared with the mirror.

- **Command substitution and `bash -c` filings.** `URL=$(gh issue create …)`,
  `URL="$(gh issue create …)"`, `N="$(gh api repos/R/issues -X POST …)"` and
  `bash -c "gh issue create …"` are all **allowed** on main (measured). The CLASS 1 anchor
  `(^|&&|\|\||;)` has no `$(`, and `$SCAN` blanks quoted `"$(…)"`. This is a different trigger and
  the shared `$SCAN` contract.
- **The list-then-label over-fire.** This one matters most for agents. Examples:
  `for n in $(gh api "repos/R/issues?labels=x" --jq …); do gh api -X POST repos/R/issues/$n/labels …; done`,
  and the same through `| xargs`. Both are denied on main and after this change, because the signal
  is read across the whole command. Segment scoping is rejected above.
- **GraphQL and lowercase-method filings.** `gh api graphql -f query='mutation { createIssue … }'` is
  allowed on main and after this change (measured). So is `-X post` (unverified whether GitHub
  routes it).
- **`gh api repos/R/issues -X GET --input q.json` is gated.** `--input` implies POST only when no
  method is given. The mirror behaves the same way, and the error is in the gating direction.
- **The cron mirror (`filingShape()`).** It already has the target shape, so nothing changes there.
  A shared accept/deny corpus for both suites was proposed by the advisor consult and cut, because it
  is new cross-language test machinery for a mirror this PR does not edit.

## User-Brand Impact

- **If this lands broken, the user experiences:** one of two failures:
  - A Soleur agent session is refused when it adds a label to, comments on, or assigns an existing
    GitHub issue. This is the current bug, and it returns if the narrowing regresses.
  - An untriaged issue lands on the operator's backlog without the filing justification, if the
    narrowing opened a bypass.

  Either way the operator sees a stalled agent or an unexplained backlog item.
- **If this leaks, the user's workflow is exposed via:** nothing. The hook reads the command string
  and writes local incident telemetry. It handles no credentials or user data, and this change adds
  no new read or write surface.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: a local PreToolUse regex narrowing in .claude/hooks/ that touches no user data, credential or production surface; the worst outcome is a mis-gated agent command.`

## Guard Contract

### Guard 1 — CLASS 4 filing trigger (`_gh_api_issue` in `.claude/hooks/guardrails.sh`)

**Property.** A Bash command sets `_gh_api_issue=1` when, and only when, it invokes `gh api`, outside
heredoc bodies and multi-word quoted prose, against the issues **collection** endpoint of some repo
(optionally with a trailing `/` and/or `?query`, and no further path segment), with a POST signal
that gh honours.

**Assembly.** The property flows through one chokepoint: the single `_gh_api_issue=1` assignment
inside the `if grep -qE 'gh\s+api\b' <<<"$SCAN"` block, directly before
`if [[ "$_gh_create" == 1 || "$_gh_api_issue" == 1 ]]`. It is the only writer of the variable apart
from its initializer. Its one input is `$_api_src`, built as `strip_heredocs "$COMMAND"` →
`_api_first_words` → newline fold. Two things sit downstream of the trigger and are in the assembly
because the newly gated spellings reach them: the `-F` arm of the body-corpus reader and the
exit-2/3 refusal text. The behavioural twin outside this file is `filingShape()` in
`apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`. It is not edited, but it is the
reference for which spellings count.

**Mutation matrix:**

Each row was applied to a scratch copy of the patched hook (with `lib/` beside it), and the 159-row
suite was run against it. All 20 went RED. The unpatched hook fails 21 of the 32 new rows (M0).

| # | Mutation | Expected |
|---|---|---|
| M1 | Endpoint terminator reverted to `/issues\b` (span `/` again, the original defect) | RED (8 rows: the sub-resource allows) |
| M2 | Terminator loses `/?` | RED: "collection trailing slash still gates" |
| M22 | Terminator loses `?` | RED: both `?query` rows |
| M3 | Terminator loses `<>` and the backtick | RED: "collection path glued to a redirect still gates" |
| M17 | Terminator made a negated class `[^/[:alnum:]_-]` | RED: both `$REPO/…/$N` sub-resource rows |
| M4 | No newline fold | RED: "backslash-continued gh api gates" |
| M5 | `_api_first_words` made the identity (as on perl failure) | RED (6 rows: quoted and partially quoted paths, quoted titles) |
| M6 | Transform keeps the whole span, not its first word | RED (3 rows: nested-quote body, the prose signal, the one-word body) |
| M7 | Transform blanks every span (`$SCAN` semantics) | RED (6 rows: the quoted escapes stay open) |
| M8 | Owner/repo tightened to two segments | RED: `$REPO` and `"$REPO"` rows |
| M9 | Prefix `[[:space:]/"']` replaced by `\b` | RED: "a one-word quoted body equal to the collection path is a value" |
| M10 | `--input` alternative dropped | RED: the `--input` row |
| M11 | `(-X\|--method)[[:space:]=]*` narrowed to `[[:space:]]+` | RED: `-XPOST`, `--method=POST` |
| M12 | `-F`/`--raw-field` dropped from the title flags | RED: both rows |
| M19 | Short-flag title needs a separator | RED: `-ftitle=` |
| M13 | Own dispatch: the assignment sets `_gh_api_issue=0` | RED (23 rows: every CLASS 4 deny, including the 2 pre-existing ones) |
| M15 | Source is raw `$COMMAND` (no heredoc strip) | RED: "an api create inside a heredoc body is prose" |
| M16 | Second member: the endpoint regex anchored to the first command segment (`^[^&;\|]*gh\s+api\b[^&;\|]*…`) | RED: "create after a sub-resource POST still gates" |
| M20 | `-F` read as `--body-file` on the api form again | RED: the `-F title=` reason row and the `-F` exit-3 row |
| M21 | The api-form refusal clause dropped | RED: the `--input` reason row |
| H1 | Harness: delete any 3 of the 32 new rows | RED: the `MIN_ASSERTIONS=159` floor trips (`FLOOR: only 156 assertions ran`) |
| H2 | Must-PASS, not canonical: quoted `"repos/$REPO/issues/$N/comments"` with `--input` (quoted, variable, and a POST signal that *would* gate the collection) | PASS (`<none>`) |

The presence check (`$SCAN`) has no mutation row on purpose. Moving it to `$COMMAND` leaves the
suite green, because the transform already keeps prose out. It is a cost pre-filter that keeps
`perl` off the hot path, and the comment block says so (§4).

**Anchor.** No stored value is compared. The rows compare live hook output with literal expected
decisions in the same commit, so one diff could weaken both. The outside-the-commit check is the
**differential corpus**: 21 endpoint shapes × 10 signal spellings = 210 commands, each run through
`origin/main`'s hook and the patched hook. Measured on the final design:

- **No collection shape is allowed under any POST spelling, and no `-X GET` command is denied.**
- **The only deny → allow flips** are the sub-resource paths (`issues/123/labels`,
  `issues/123/comments`, `issues/comments`, `issues/$N/labels`, `issues/{number}/labels`), plus
  `issues.json`, which is not a GitHub route (`gh api 'repos/jikig-ai/soleur/issues.json?per_page=1'`
  returns `Not Found`, measured).
- **Every allow → deny flip** is a collection shape under a newly recognised spelling, or a newly
  recognised quoting or URL form (`"…"`, `'…'`, `repos/"$REPO"/issues`, `https://api.github.com/repos/…`).

## Acceptance Criteria

- [ ] `bash .claude/hooks/guardrails.test.sh` prints `Total: 159  Pass: 159  Fail: 0`, and
      `MIN_ASSERTIONS=159`.
- [ ] The new rows are RED-before-GREEN. Run them with `.claude/hooks/guardrails.sh` replaced by
      `git show origin/main:.claude/hooks/guardrails.sh`, in a scratch copy of the **whole**
      `.claude/hooks/` directory (with `lib/`), never in the worktree. Every `FAIL:` line must be a
      new row, and there must be 21 of them. The other 11 rows already pass on main and pin
      non-regression. A hook copied without `lib/` emits nothing, and every row then reads as an allow.
- [ ] The differential corpus (Test Scenarios step 2) shows no collection shape allowed under a POST
      spelling, no `-X GET` denied, and deny → allow flips only on sub-resource paths and
      `issues.json`.
- [ ] `grep -cE '^[^#]*_gh_api_issue=' .claude/hooks/guardrails.sh` returns `2` (the initializer
      plus the single assignment).
- [ ] `bash -n .claude/hooks/guardrails.sh` passes, and
      `python3 scripts/lint-shell-capture-exit.py .claude/hooks/guardrails.sh` reports 0 new
      findings.
- [ ] `git diff --name-only origin/main...HEAD -- .claude/ apps/` lists exactly
      `.claude/hooks/guardrails.sh` and `.claude/hooks/guardrails.test.sh`.

## Test Scenarios

1. **The suite.** The rows are in the `<details>` block under Files to Edit. They use
   `R = jikig-ai/soleur` so the external-repo exemption stays off. Every deny row carries no exit-1,
   exit-2 or exit-3 justification, so a deny means the CLASS 4 trigger fired rather than some other
   gate. Write the rows first and confirm the 21 RED against main's hook
   (`cq-write-failing-tests-before`), then apply the four hook hunks. One commit is fine, because the
   corpus separates the two directions by path class.
2. **Differential corpus.** A throwaway loop in the scratchpad; do not commit it. Path set:
   - collection: `repos/R/issues`, `/repos/R/issues`, `repos/R/issues/`, `repos/R/issues?x=1`,
     `"repos/R/issues"`, `'repos/R/issues'`, `repos/$REPO/issues`, `repos/{owner}/{repo}/issues`,
     `repos/R/issues>out.json`, `` `echo repos/R/issues` ``, `repos/R/issues)`, `repos/R/issues;`,
     `repos/"$REPO"/issues`, `https://api.github.com/repos/R/issues`;
   - sub-resource: `repos/R/issues/123/labels`, `repos/R/issues/123/comments`,
     `repos/R/issues/comments`, `"repos/R/issues/9/labels"`, `repos/R/issues.json`,
     `repos/$REPO/issues/$N/labels`, `repos/R/issues/{number}/labels`.

   Signal set: `-X POST`, `--method POST`, `-f title=x`, `--field title=x`, `-XPOST`, `--method=POST`,
   `--input b.json`, `-F title=x`, `-f "title=a b"`, `-X GET`.

   Run `gh api <path> <signal> -f body=y` through both hooks, each invoked **in place** inside a full
   copy of `.claude/hooks/`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an internal tooling change to a local agent-session
PreToolUse hook.

## Dependencies & Risks

- **Rename-guard flake (#9028, open).** On a main-sync merge, rename-guard can report main's own
  content as a laundering rename. If it fires on this PR, rebase onto `origin/main` with an identical
  tree. **Never** apply the override label.
- **Newly denied commands.** Closing the escapes means some commands that pass today will be denied:
  quoted, partially quoted and full-URL paths; `-XPOST`, `--method=POST`, `-X=POST`, `--input`;
  `-F`/`--raw-field`/attached `title=`; quoted multi-word `title=`; and multi-line api filings
  against our repo that carry no justification. That is intended. In-repo call sites were checked
  (`git grep` over `plugins`, `.claude`, `.github`, `scripts`, `apps/web-platform/server`). The only
  `gh api … /issues` POST outside tests is `.github/workflows/dev-ledger-reconcile.yml:391`, which
  runs in CI and never passes through this local hook.
- **Operator-scope note.** The DHH review recommended moving the escape closures to their own PR.
  They stay here because the brief asked for the quoted path not to be a bypass. The dissent is
  recorded in `knowledge-base/project/specs/feat-one-shot-guardrails-filing-gate-subresource/decision-challenges.md`.

## References & Research

### Research Insights

- **Premise validation.** The brief cites no issue number. It cites #9028 (rename-guard flake),
  which `gh issue view 9028` shows is still OPEN, so the warning stands. The cited file and lines
  exist on this branch's base `b3d5652e7b`. The "second reference near line 649" is comment prose,
  not a matcher. No ADR is implicated: this is a bug fix to an existing gate, and it adds no new
  mechanism class.
- **Property list.**
  - P1: a POST to an existing issue's sub-resource is never classified as a filing.
  - P2: every spelling of a POST to the issues collection that gh routes to "create issue" is
    classified as a filing.
  - P3: `gh api` text that appears only in quoted or heredoc prose is not a filing.
  - P4: a refusal on the api form names an exit the agent can actually take (added at review).
- **Cut list.**
  - A skill-level double-check in `ship/SKILL.md` or `compound/SKILL.md` (suggested by the learnings
    scan) buys P1 and P2, which this hook enforces at the single chokepoint. Cut.
  - Changing `pre-merge-rebase.sh` buys nothing, because `strip_command_bodies` is already shared.
    Cut.
  - Editing the cron mirror buys P1 and P2 for the cron substrate, which `filingShape()` already
    delivers. Cut.
  - The two-arm endpoint and signal design (v1) was cut at review, replaced by the first-word
    transform.
  - The quoted-value signal arm and the two-commit order were cut at review.
- **Mirror (authority grepped).** `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`,
  `filingShape()`: the collection regex plus the POST signals `-X POST`, `--method POST`, `-XPOST`,
  `--method=POST`, `--input`, and `title=` under `-f`, `-F`, `--field` and `--raw-field`. Its tests,
  `apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts`, assert the sub-resource
  allow and the `?x=1` and `/` escape rows.
- **`$SCAN` semantics.** `strip_command_bodies` (`.claude/hooks/lib/incidents.sh`) blanks heredoc
  bodies **and** every `"…"`/`'…'` span. `strip_heredocs` blanks only heredoc bodies. Both fall back
  to returning their input when `perl` fails, and `_api_first_words` copies that contract.
- **Learnings applied.**
  - `2026-02-24-guardrails-grep-false-positive-worktree-text.md`: bind command and argument in one
    pattern.
  - `2026-06-12-command-detection-hook-fp-sweep-and-fixtures-as-latent-bug-detectors.md`: phrase
    gates must read stripped text.
  - `2026-09-10-every-escape-my-mutations-could-not-reach.md`: measure the predicate with an escape
    corpus, not only mutations. Hence the differential corpus, which review then extended to the
    allow → deny direction.
  - `2026-06-12-restoring-a-contained-cron-literal-allowlist-forms-and-decide-paired-tests.md`:
    paired decide-style rows over the real hook.
- **Related issues.** #9089 was filed during this planning, with three follow-up comments. No open
  `code-review` issue touches either file.
- **Community overlap:** none (functional-discovery queried 3 registries; there were 0 relevant
  results).

### Plan Review and Consult Record

- **Advisor consult (plan Step 4.5).**
  - Applied: bare-only signal reading (the prose-flag FP), `-ftitle=`, and the GraphQL and
    lowercase-method residuals.
  - Cut: the shared bash/JS corpus.
  - Superseded: the two-commit order.
- **DHH.**
  - P0: the nested-quote false positive in the v1 quoted arm. Resolved by the redesign; pinned by a
    row and M6.
  - P1: split the escape closures out. Not applied; see decision-challenges.
  - Trims: floor rows kept, as the simplicity review judged them warranted.
- **Kieran.**
  - P1: the same nested-quote false positive. Resolved.
  - P1: a misleading "NEGATED class" test comment. Fixed.
  - P2: no row pinned the bare `?` terminator. Added; M22.
  - P2: the table disagreed with the rows on `?x=1`. Fixed.
  - P2: the list-then-label over-fire. Moved to Non-Goals and #9089.
  - P2: `-f "title"=x`. Now closed by the transform.
  - P2: a fragile `grep -c` AC. Anchored to non-comment lines.
  - P2: M16 was never run. It has been run.
- **Code simplicity.**
  - Kept: the core arms.
  - Cut: the two-commit order and the duplicate prose restatement of the rows.
  - Fixed: the misleading comment.
  - The `-X "POST"` quoted-signal alternation is gone with the redesign.
  - The `-ftitle=` divergence from the mirror is now stated.
- **CTO (devex).**
  - Applied: the `-F` body-file misread (§2), the api-form exit-1 and `--input` refusal text (§3),
    and `assert_reason` rows for both.
  - Recorded: the `-X GET --input` over-gate note, and the shellwords direction plus the promotion
    trigger on #9089.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- **Copy the hunk exactly.** The perl program sits inside a single-quoted bash string, so each of its
  single quotes is written `'\''`. A mis-closed quote turns the rest of the line into shell words.
  Run `bash -n` and the suite after pasting.
- **Portability.** The hook runs on operator hosts, macOS included. The hunk adds no new binary:
  `perl` is already required by `strip_heredocs`/`strip_command_bodies`, and `grep -E` and `tr` are
  already used. It adds no regex construct beyond what the existing trigger uses (`\s`, `\b`, POSIX
  classes). The backtick, `\\` and the quote characters inside the bracket expression are literal in
  both GNU and BSD `grep -E`. The perl uses only core regex features.
- **The natural repair of a new refusal.** An agent denied on the api form will most likely add
  `-f 'labels[]=meta/machinery'` (honest, exit 1, and now named in the refusal) or switch to
  `gh issue create`, which is gated. The repairs that still pass are `"$(…)"`, `bash -c "…"` and
  GraphQL. All are on #9089, and this PR does not claim to close them.
- **Text rather than invocation, in the over-fire direction.** `echo gh api repos/R/issues -X POST`,
  a `#` comment carrying that text, and the list-then-label loop are all gated. This is unchanged
  from main and fails toward gating.
- Do not "simplify" the terminator into a negated class (M17), or owner/repo into two segments
  (M8). The mirror uses two segments because it sees **expanded** tokens, while this hook sees the
  unexpanded `$REPO` word.
- GitHub returns `Not Found` for a GET on `repos/R/issues/?per_page=1` (measured), so a
  trailing-slash collection is probably not a working create route. It stays gated anyway, for
  parity with `filingShape()` and because an extra gate on an unroutable path costs nothing.
