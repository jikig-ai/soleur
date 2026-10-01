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

## Enhancement Summary

**Deepened on:** 2026-09-27. **Design revision 3** (v1 → v2 at plan review, v2 → v3 at deepen).

**Reviewers and agents used:**

- plan review: DHH, Kieran, code-simplicity, CTO (devex);
- the plan Step 4.5 advisor consult;
- deepen: security-sentinel (bypass hunt), test-design-reviewer, and a verify-the-negative sweep;
- learnings-researcher and functional-discovery during research.

### Key Improvements

1. **The design no longer parses quotes at all.** v1 (two quoted/bare arms) and v2 (a first-word
   rewrite of every quoted span) each closed the pre-existing quoted-path escape, and each was
   measured to add regressions:
   - v1: a nested-quote false positive;
   - v2: six regressions found by the security review, where main denies a create and v2 allows it
     (`"body=| a |"`, `--jq '.number|tostring'`, `"$BASE"repos/…`, `issues"$QS"`, `issues$QS`,
     `${EP:-…}`), plus new false positives on routine list-then-comment commands.

   v3 reads only `$SCAN`, the same quote-blanked text main reads, and adds one mechanism: **per-command
   segment scoping**. That is safe here because `$SCAN` has no quoted separators left.
2. **The reported use case is fixed in full, not just its simplest shape.** Per-segment scoping also
   fixes the list-then-label loop (`for n in $(gh api repos/R/issues …); do gh api -X POST
   repos/R/issues/$n/labels …; done`), which v1 and v2 left denied.
3. **The api-form refusal path is corrected** (CTO review):
   - `-F` is no longer read as `--body-file` on `gh api`;
   - the refusal names the api spelling of exit 1 and says that `--input` JSON is not read.

### New Considerations Discovered

- **The quoted-path escape is not closed by this PR.** This is a scope reduction relative to the
  brief's example. It is pre-existing on main, so the narrowing opens no bypass. Its closure needs
  the tokenizer recorded on #9089. See DC-1 in `decision-challenges.md`.
- **The first corpus runs in planning were silently invalid.** They copied the hook without its
  `lib/`, so every command read as an allow. Every AC now requires the whole `.claude/hooks/`
  directory.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The issue-filing gate in `.claude/hooks/guardrails.sh` has a trigger for the `gh api` form of
creating an issue (the in-code comment calls it "CLASS 4 of the filing surface"). It decides "this
is a filing" when two things hold:

1. **An endpoint match:** `gh\s+api\b[^|]*\brepos/[^[:space:]]+/issues\b`, run against `$SCAN`.
2. **A POST signal:** `(-X|--method)[[:space:]]+POST|-f[[:space:]]+title=|--field[[:space:]]+title=`,
   also run against `$SCAN` but **across the whole command**.

`[^[:space:]]+` spans `/`, and `\b` after `issues` is satisfied by the `/` that starts the next path
segment. So a POST to an existing issue's sub-resource is treated as a new filing. It then goes to
the filing-justification gate and is denied unless it carries `meta/machinery`, a `Mandated-By:`
claim, or a `User-Impact:` + `Fix-Size:` pair. That blocks routine agent work: adding a label,
posting a comment, assigning someone. Because the signal is read across the whole command, a
command that *lists* issues and then *labels* them is denied too, even with a correct endpoint
match.

This plan narrows the endpoint to the **collection** only (`repos/<o>/<r>/issues`, with an optional
trailing `/` and an optional `?query`, and nothing further in the path). It requires the endpoint
and the POST signal to sit in the **same command segment**, and it recognises the POST spellings gh
honours that the trigger never read.

**Measured on this branch's base (`b3d5652e7b`), with payloads fed to the hook on stdin from a non-git temporary working directory:**

| Command (owner/repo = `jikig-ai/soleur`) | Today | After this PR |
|---|---|---|
| `gh api -X POST repos/R/issues/123/labels -f 'labels[]=type/bug'` | **deny** | allow |
| `gh api -X POST repos/R/issues/123/comments -f body=hi` | **deny** | allow |
| `gh api --method POST repos/R/issues/123/assignees -f 'assignees[]=me'` | **deny** | allow |
| `gh api -X POST repos/$REPO/issues/$N/labels …` / `…/issues/{number}/labels …` | **deny** | allow |
| `for n in $(gh api repos/R/issues?labels=x --jq …); do gh api -X POST repos/R/issues/$n/labels …; done` | **deny** | allow |
| `gh api repos/R/issues -XPOST …` / `--method=POST` / `-X=POST` | **allow** | deny |
| `gh api repos/R/issues --input b.json` (gh defaults to POST) | **allow** | deny |
| `gh api repos/R/issues -F title=x …` / `--raw-field title=x …` / `-ftitle=x` | **allow** | deny |
| `gh api \⏎ repos/R/issues \⏎ -X POST …` (backslash continuation) | **allow** | deny |
| Unquoted `?x=1`, trailing `/`, `/repos/…`, full URL, `{owner}/{repo}`, `$REPO`, `issues$QS`, `${EP:-…}` | deny | deny |
| `gh api "repos/R/issues" -X POST …` (any **quoted** endpoint or quoted `-f "title=…"`) | allow | allow (**pre-existing; #9089**) |

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Matcher near "CLASS 4 of the filing surface", lines ~471-484 | Confirmed: comment at `guardrails.sh:471`, matcher at `:482-484` | Edit there |
| Second reference near line 649 (`… -X POST -f 'labels[]=meta/machinery'` was denied) | That line is **comment prose** in the exit-1 label reader. It is not a matcher, and it already describes the collection endpoint | No change. It stays accurate |
| "check any sibling copy of the same matcher elsewhere" | `git grep` finds exactly one other implementation: `filingShape()` in `cron-bash-allowlist-hook.mjs` (imported by `apps/web-platform/server/cron-filing-deny-marker.ts`). It **already** uses the collection-only regex `(^|\/)repos\/[^/?]+\/[^/?]+\/issues\/?(\?[^/]*)?$` plus `-XPOST`/`--method=POST`/`--input`/`-F title=`, and it has test rows for sub-resource allow (`cron-bash-allowlist-hook.test.ts`, the test titled "still allows a non-create endpoint under the same prefix") | No edit. The mirror is the reference shape. `scripts/lint-workflow-issue-write-scope.py` also matches `gh api` lines, but it is a workflow-scope lint and not a filing gate. Out of scope |
| "a quoted path must not become a bypass" | It is **already** a bypass on main: `$SCAN` blanks every quoted span, so `"repos/o/r/issues"` is invisible to the trigger. The narrowing does not open it | **Not closed here.** Two string-level designs that closed it were each measured to introduce new regressions (see Alternatives). Deferred to the tokenizer fix on #9089, with the exact shapes listed |
| Test suite ".claude/hooks/guardrails*.test.sh or similar" | `.claude/hooks/guardrails.test.sh` (127 assertions, `MIN_ASSERTIONS=127` floor, `assert <label> <want> <cmd>` helper, CLASS 4 block at `:809-824`). CI runs it as a shard leg (`scripts/suite-shard-legs.tsv:22`) | Add rows beside the CLASS 4 block and bump the floor |

## Proposed Solution

### 1. The trigger: one source, per-segment matching

Replace the three-line trigger at `guardrails.sh:482-484` with:

```bash
if grep -qE 'gh\s+api\b' <<<"$SCAN"; then
  _api_segs="$(printf '%s' "$SCAN" | perl -0777 -pe 's/\\\n/ /g; s/\\[;&|]/_/g; s/&&|\|\||[;&|]/\n/g' 2>/dev/null)" \
    || _api_segs="$SCAN"
  while IFS= read -r _api_seg; do
    grep -qE 'gh\s+api\b.*\brepos/[^[:space:]]+/issues(/?([?[:space:]()<>`\\]|$)|[$}])' <<<"$_api_seg" \
      && grep -qE '(^|[[:space:]])((-X|--method)[[:space:]=]*POST\b|--input([[:space:]=]|$)|(-f|-F)[[:space:]=]*title=|(--field|--raw-field)[[:space:]=]+title=)' <<<"$_api_seg" \
      && { _gh_api_issue=1; break; }
  done <<<"$_api_segs"
fi
```

**Source: `$SCAN`, unchanged.** `strip_command_bodies` has already blanked heredoc bodies and every
`"…"`/`'…'` span. Quoted prose, a quoted `--jq` program and a commit message therefore never reach
the matcher. That also means a quoted **endpoint** never reaches it, which is the pre-existing
escape deferred to #9089.

**Segments.** A small `perl` pass (perl is already required by `strip_command_bodies`) does three
things:

1. It joins backslash-newline continuations.
2. It neutralises *escaped* separators (`\;`, `\&`, `\|`) to `_`, so an escaped separator cannot
   split one command into two segments. An example is `gh api repos/R/issues -f x=\; -X POST …`
   (M25).
3. It splits on `&&`, `||`, `;`, `&`, `|` and newline.

Because `$SCAN` contains no quoted text, a separator character inside a quoted argument cannot
reach the split. That was the reason segment scoping had been rejected for a quote-preserving
source. If `perl` fails, the segments fall back to `$SCAN` itself, which is line-granular as on
main, so the fallback errs toward gating.

**Endpoint regex (per segment):** `gh\s+api\b.*\brepos/[^[:space:]]+/issues(/?([?[:space:]()<>`\\]|$)|[$}])`

- **Owner/repo stays one `[^[:space:]]+` word.** A two-segment `[^/]+/[^/]+` would stop matching
  `repos/$REPO/issues` and `repos/${GITHUB_REPOSITORY}/issues`, which are single shell words that
  expand to two segments. That would be a new bypass (M8).
- **Terminator.** After `issues`, an optional `/`, then one of `?`, whitespace, `()<>`, a backtick
  or `\`, or end of segment. `;&|` never reach this point because they are separators.
- **`$` or `}` is accepted directly after `issues`, with no `/`.** This keeps `issues$QS`,
  `issues"$QS"` (the quoted span is blanked in `$SCAN`, leaving `issues` followed by a space) and `${EP:-repos/R/issues}` gated, as on main
  (M23). A `$` after `issues/` is **not** accepted, so `issues/$N/labels` stays a sub-resource. The
  negated class `[^/[:alnum:]_-]` accepted it, and that re-denies templated sub-resources (M17).
- `\b` before `repos/` is unchanged from main.

**POST signal (the same segment):** the spellings match `filingShape()`:

- `-X POST`, `-XPOST`, `--method POST`, `--method=POST`, `-X=POST`;
- `--input` (gh switches to POST when an input body is given);
- a `title=` field under `-f`, `-F`, `--field` or `--raw-field`.

It also accepts the attached `-ftitle=x` form, which pflag accepts. **That form is a deliberate
divergence:** `filingShape()` does not match it.

**`set -euo pipefail`.** The loop's last `&&` list fails on every non-filing segment. That does not
trigger errexit, and the hook continues to the gates below it. A row pins it (the `git stash` gate
after a non-filing `gh api`), and mutation M27 shows that a stray failing status there takes down
25 rows.

### 2. The `-F` misread in the body reader (CTO review, same file)

The body-corpus reader treats `-F` as `--body-file` for every filing. On `gh api`, `-F` is a typed
field, so `gh api repos/R/issues -X POST -F title=x -f 'body=Mandated-By: wg-…'` is refused with
"--body-file names title=x …". That refusal is wrong, and here it hides a valid exit-3 justification
(measured: main denies, this change allows). The fix, matching the mirror, is to read `-F` as a body
file only when `_gh_create == 1`:

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
JSON body is not read: pass the body with -f instead.`

### 4. The CLASS 4 comment block

Rewrite the comment above the trigger (`guardrails.sh:471-479`) in five to eight lines:

- the endpoint is the collection only, and the endpoint and the signal must share a command
  segment;
- the source is `$SCAN`, so a quoted endpoint is invisible (#9089);
- why owner/repo stays one word;
- why the terminator is a closed list and why `$`/`}` are accepted only without a slash;
- `filingShape()` is the mirror that must agree.

Do **not** write the literal `_gh_api_issue=` in the comment, because the single-writer AC greps
for it.

### Alternatives considered and rejected

| Design | Why rejected (measured) |
|---|---|
| **v1: two endpoint arms.** A bare arm on `$SCAN` plus a "wholly-quoted endpoint" arm on quote-preserving text, and two matching signal arms | DHH and Kieran each measured a **new** false positive of the class being fixed. A quote nested in a body (`-f body="see 'repos/R/issues'"`) satisfies "the whole span is the endpoint" |
| **v2: first-word rewrite.** Each quoted span is reduced to its first word before matching (closes quoted, partially quoted and multi-word `title=` escapes) | The security review measured **six regressions where main denies a create and v2 allows it**. A kept word carrying `\|` cut the `[^\|]*` match (`"body=\| a \|"`, `--jq '.number\|tostring'`). A kept word glued to the path hid it (`"$BASE"repos/…`, `issues"$QS"`, `issues$QS`, `${EP:-…}`). It also measured **new false positives**: a quoted collection GET became visible and paired with a POST elsewhere in the command. String rewriting cannot pair quotes the way the shell does (`'it'\''s'`) |
| **Tokenize at trigger time with `xargs -n1`** (the mirror's approach) | GNU `xargs` rejects the standard bash apostrophe idiom `'it'\''s'` ("unmatched single quote", measured). That would add a deny or fail-open mode for **non-filings**. Core Perl `Text::ParseWords::shellwords` does not have this problem (per the CTO review), so it is the fix direction recorded on #9089 |
| **Global POST signal (main's behaviour)** | Denies list-then-label commands, the reported use case in loop form |

## Files to Edit

- `.claude/hooks/guardrails.sh`, four hunks and nothing else:
  - the CLASS 4 trigger at `:482-484` (§1);
  - its comment block at `:471-479` (§4);
  - the `-F` case in the body-corpus reader (the `--body-file|-F)` line, §2);
  - the exit-2/3 refusal string (the `names no user-visible consequence` reason, §3).
- `.claude/hooks/guardrails.test.sh`: 33 rows appended directly after the existing row
  `"filing-justification: gh api POST to another endpoint is untouched"` (CLASS 4 block), using the
  existing `assert` and `assert_reason` helpers. Bump `MIN_ASSERTIONS=127` to `160`, and extend the
  running-sum comment above it with `+ 33 CLASS 4 endpoint-scope rows = 160`.

<details>
<summary>The 33 rows as validated in deepen (a scratch copy of the whole <code>.claude/hooks/</code>: 160/160 green on the patched hook, 18 RED on main's hook)</summary>

```bash
# --- CLASS 4 endpoint scope: only the COLLECTION endpoint creates an issue.
# `repos/[^[:space:]]+/issues\b` spanned `/`, so a POST to an EXISTING issue's
# sub-resource (labels, comments, assignees) was denied as a new filing.
assert "filing-justification: POST to issues/<N>/labels is not a filing" "<none>" \
  "gh api -X POST repos/jikig-ai/soleur/issues/123/labels -f 'labels[]=type/bug'"
assert "filing-justification: POST to issues/<N>/comments is not a filing" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/issues/123/comments -f body=hi'
assert "filing-justification: --method POST to issues/<N>/assignees is not a filing" "<none>" \
  "gh api --method POST repos/jikig-ai/soleur/issues/123/assignees -f 'assignees[]=me'"
assert "filing-justification: templated \$REPO/\$N sub-resource POST is not a filing" "<none>" \
  "gh api -X POST repos/\$REPO/issues/\$N/labels -f 'labels[]=x'"
assert "filing-justification: {number} placeholder sub-resource POST is not a filing" "<none>" \
  "gh api -X POST repos/{owner}/{repo}/issues/{number}/labels --input l.json"
# The endpoint and the POST signal must sit in the SAME command segment, so
# listing issues and labelling them in one command is not a filing.
assert "filing-justification: list-then-label loop is not a filing" "<none>" \
  "for n in \$(gh api repos/jikig-ai/soleur/issues?labels=x --jq '.[].number'); do gh api -X POST repos/jikig-ai/soleur/issues/\$n/labels -f 'labels[]=y'; done"
assert "filing-justification: list piped into a labelling xargs is not a filing" "<none>" \
  "gh api repos/jikig-ai/soleur/issues --jq '.[].number' | xargs -I{} gh api -X POST repos/jikig-ai/soleur/issues/{}/labels -f 'labels[]=y'"
assert "filing-justification: a quoted collection GET beside a comment POST is not a filing" "<none>" \
  'gh api -X POST "repos/jikig-ai/soleur/issues/5/comments" -f body=x && gh api "repos/jikig-ai/soleur/issues?per_page=5"'
# The collection endpoint still gates in every unquoted spelling gh routes to it.
assert "filing-justification: collection ?query still gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues?x=1 -X POST -f title=x -f body=y'
assert "filing-justification: collection trailing slash still gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues/ -X POST -f title=x -f body=y'
assert "filing-justification: leading-slash /repos path still gates" "deny" \
  'gh api /repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y'
assert "filing-justification: full api.github.com URL still gates" "deny" \
  'gh api https://api.github.com/repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y'
assert "filing-justification: {owner}/{repo} placeholders still gate" "deny" \
  'gh api repos/{owner}/{repo}/issues -X POST -f title=x -f body=y'
assert "filing-justification: a single \$REPO word still gates" "deny" \
  'gh api repos/$REPO/issues -X POST -f title=x -f body=y'
assert "filing-justification: a variable glued after the collection still gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues$QS -X POST -f title=x -f body=y'
assert "filing-justification: \${EP:-…} default-expansion endpoint still gates" "deny" \
  'gh api ${EP:-repos/jikig-ai/soleur/issues} -X POST -f title=x -f body=y'
assert "filing-justification: collection path glued to a redirect still gates" "deny" \
  'gh api -X POST -f title=x -f body=y repos/jikig-ai/soleur/issues>out.json'
assert "filing-justification: a quoted pipe in --jq does not split the create" "deny" \
  "gh api -X POST --jq '.number|tostring' repos/jikig-ai/soleur/issues -f title=x -f body=y"
assert "filing-justification: an escaped separator does not split the create" "deny" \
  'gh api repos/jikig-ai/soleur/issues -f x=\; -X POST -f body=y'
assert "filing-justification: create after a sub-resource POST still gates" "deny" \
  "gh api -X POST repos/jikig-ai/soleur/issues/5/labels -f 'labels[]=x' && gh api repos/jikig-ai/soleur/issues -X POST -f title=x -f body=y"
assert "filing-justification: backslash-continued gh api gates" "deny" \
  $'gh api \\\n  repos/jikig-ai/soleur/issues \\\n  -X POST -f title=x -f body=y'
# POST spellings gh honours that the trigger did not read (measured on main: all ALLOWED).
assert "filing-justification: -XPOST gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -XPOST -f body=y'
assert "filing-justification: --method=POST gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --method=POST -f body=y'
assert "filing-justification: --input (gh defaults to POST) gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --input b.json'
assert_reason "filing-justification: an --input denial says the JSON is not read" \
  "an --input JSON body is not read" \
  'gh api repos/jikig-ai/soleur/issues -X POST --input b.json'
assert "filing-justification: -F title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -F title=x -f body=y'
assert_reason "filing-justification: -F title= is refused for the justification, not as a --body-file" \
  "names no user-visible consequence" \
  'gh api repos/jikig-ai/soleur/issues -X POST -F title=x -f body=y'
assert "filing-justification: api -F title= with a Mandated-By body reaches exit 3" "<none>" \
  "gh api repos/jikig-ai/soleur/issues -X POST -F title=x -f 'body=Mandated-By: wg-block-pr-ready-on-undeferred-operator-steps'"
assert "filing-justification: --raw-field title= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues --raw-field title=x -f body=y'
assert "filing-justification: attached short flag -ftitle= gates" "deny" \
  'gh api repos/jikig-ai/soleur/issues -ftitle=x -f body=y'
# Prose stays prose: quoted spans and heredoc bodies are blanked ($SCAN).
assert "filing-justification: sub-resource POST whose body names the collection path is not a filing" "<none>" \
  'gh api -X POST repos/jikig-ai/soleur/issues/5/comments -f body="use gh api repos/jikig-ai/soleur/issues -X POST to file"'
assert "filing-justification: an api create inside a heredoc body is prose" "<none>" \
  $'cat > /tmp/soleur-note.md <<\'EOF\'\nrun: gh api repos/jikig-ai/soleur/issues -X POST -f title=x\nEOF\ngh api repos/jikig-ai/soleur/labels --jq length'
# The segment loop must not end the hook: gates after CLASS 4 still run.
assert_reason "filing-justification: a later gate still runs after a non-filing gh api" \
  "git stash is not allowed" \
  'gh api repos/jikig-ai/soleur/labels --jq length; git stash'

```

</details>

## Files to Create

None.

## Open Code-Review Overlap

None. Checked `gh issue list --label code-review --state open` (200 max) against both file paths on
2026-09-27. There were no matches.

## Non-Goals

Every item below is recorded on **#9089** (`meta/machinery`, Post-MVP / Later), which carries the
fix direction (a `shellwords` tokenizer shared with the mirror) and a promotion trigger.

- **Quoted and partially quoted endpoints, and a quoted `title=`.** These pass on main and after
  this change:
  - `gh api "repos/R/issues" -X POST …`;
  - `gh api 'repos/R/issues?x=1&y=2' -X POST …`;
  - `gh api repos/"$REPO"/issues -X POST …`;
  - `gh api repos/R/issues -f "title=a b"` with no explicit method;
  - `EP=repos/R/issues; gh api "$EP" -X POST …`.

  `$SCAN` blanks quoted spans, and both string-level fixes tried here regressed (Alternatives).
- **Command substitution and `bash -c` filings.** `URL=$(gh issue create …)`,
  `URL="$(gh issue create …)"`, `N="$(gh api repos/R/issues -X POST …)"` and
  `bash -c "gh issue create …"` are all **allowed** on main (measured). The CLASS 1 anchor
  `(^|&&|\|\||;)` has no `$(`, and `$SCAN` blanks quoted `"$(…)"`.
- **GraphQL, curl and lowercase-method filings.** These pass on main and after this change:
  - `gh api graphql -f query='mutation { createIssue … }'`;
  - `curl -X POST … https://api.github.com/repos/R/issues`;
  - `-X post` (it is unverified whether GitHub routes a lowercase method).
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

## Observability

This is a local PreToolUse hook on the operator's own sessions, so it has no server-side runtime.
Its observable surfaces are the decision it returns, the local incident ledger, and the CI suite.

```yaml
liveness_signal:
  what: "guardrails.test.sh verdict line (Total/Pass/Fail) under the MIN_ASSERTIONS=160 floor, run as a test-all shard leg"
  cadence: "per local scripts/test-all.sh run and per CI invocation"
  alert_target: "suite RED fails the shard leg and blocks the PR"
  configured_in: "scripts/suite-shard-legs.tsv (.claude/hooks/guardrails.test.sh row) and the MIN_ASSERTIONS floor in the suite"

error_reporting:
  destination: "the hook's own permissionDecisionReason on deny, plus emit_incident rows in .claude/.rule-incidents.jsonl (rule ids guardrails-require-milestone / wg-defer-only-after-inline-triage)"
  fail_loud: "a deny carries a reason naming the exit to take; a perl failure in the segment split degrades to line-granular matching over $SCAN, which errs toward gating"

failure_modes:
  - mode: "sub-resource or list-then-label POST denied again (the original bug regresses)"
    detection: "the 8 allow rows for sub-resources and loops go RED (mutations M1, M17, M24, M26)"
    alert_route: "PR-blocking suite failure"
  - mode: "a collection-create spelling escapes the gate"
    detection: "the collection deny rows go RED (M2, M3, M4, M8, M10-M12, M19, M22, M23, M25), and the differential corpus shows a collection shape allowed"
    alert_route: "PR-blocking suite failure; corpus run during soleur:work"
  - mode: "the hook exits early under set -euo pipefail (no output reads as allow, and later gates are skipped)"
    detection: "the git-stash-after-gh-api reason row and every CLASS 4 deny row go RED (M27, M13)"
    alert_route: "PR-blocking suite failure"
  - mode: "a refusal names an exit the api form cannot take"
    detection: "assert_reason rows on the --input and -F title= shapes (M20, M21)"
    alert_route: "PR-blocking suite failure"

logs:
  where: "session output (the refusal text) and the repo-local .claude/.rule-incidents.jsonl written by emit_incident"
  retention: "repo-local; rotated by rotate_if_needed from .claude/hooks/lib/log-rotation.sh, which lib/incidents.sh sources"

discoverability_test:
  command: "grep -c -e _api_segs .claude/hooks/guardrails.sh"
  expected_output: "3"
```

## Guard Contract

### Guard 1 — CLASS 4 filing trigger (`_gh_api_issue` in `.claude/hooks/guardrails.sh`)

**Property.** A Bash command sets `_gh_api_issue=1` when, and only when, one of its command segments
(outside heredoc bodies and quoted spans) invokes `gh api` against the issues **collection** endpoint
of some repo (optionally with a trailing `/` and/or `?query`, and no further path segment), with a
POST signal that gh honours in the same segment.

**Assembly.** The property flows through one chokepoint: the single `_gh_api_issue=1` assignment
inside the `while … done <<<"$_api_segs"` loop, in the `if grep -qE 'gh\s+api\b' <<<"$SCAN"` block,
directly before `if [[ "$_gh_create" == 1 || "$_gh_api_issue" == 1 ]]`. It is the only writer of the
variable apart from its initializer. Its one input is `$_api_segs`, which is `$SCAN` passed through
the continuation join, the escaped-separator neutralisation and the separator split. **Every**
segment is examined until a match: M16 reads only the first segment and goes RED.

Two things sit downstream of the trigger and are in the assembly because the newly gated spellings
reach them: the `-F` arm of the body-corpus reader and the exit-2/3 refusal text. The behavioural
twin outside this file is `filingShape()` in
`apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`. It is not edited, but it is the
reference for which spellings count.

**Mutation matrix:**

Each row was applied to a scratch copy of the whole patched `.claude/hooks/` directory, and the
160-row suite was run against it. All 21 went RED. The unpatched hook fails 18 of the 33 new rows
(M0).

| # | Mutation | Expected |
|---|---|---|
| M1 | Endpoint terminator reverted to `/issues\b` (span `/` again, the original defect) | RED (8 rows: the sub-resource and loop allows) |
| M2 | Terminator loses `/?` | RED: "collection trailing slash still gates" |
| M22 | Terminator loses `?` | RED: "collection ?query still gates" |
| M3 | Terminator loses `<>` and the backtick | RED: "collection path glued to a redirect still gates" |
| M17 | Terminator made a negated class `[^/[:alnum:]_-]` | RED (4 rows: `$REPO/…/$N` and `{number}` sub-resources, among others) |
| M23 | The `$`/`}` alternative dropped | RED: `issues$QS` and `${EP:-…}` rows |
| M4 | No continuation join | RED: "backslash-continued gh api gates" |
| M24 | No segmentation (main's global signal) | RED: the list-then-label loop and the xargs rows |
| M26 | `\|` not a separator | RED: the xargs row |
| M25 | Escaped separators not neutralised | RED: "an escaped separator does not split the create" |
| M8 | Owner/repo tightened to two segments | RED: "a single $REPO word still gates" |
| M10 | `--input` alternative dropped | RED: the `--input` row |
| M11 | `(-X\|--method)[[:space:]=]*` narrowed to `[[:space:]]+` | RED: `-XPOST`, `--method=POST` |
| M12 | `-F`/`--raw-field` dropped from the title flags | RED: both rows |
| M19 | Short-flag title needs a separator | RED: `-ftitle=` |
| M13 | Own dispatch: the assignment sets `_gh_api_issue=0` | RED (24 rows: every CLASS 4 deny, including the 2 pre-existing ones) |
| M16 | Second member: only the first segment is read | RED: "create after a sub-resource POST still gates" |
| M15 | Source is raw `$COMMAND` (quoted prose visible) | RED (3 rows: the quoted `--jq` pipe, the body mention, the heredoc) |
| M27 | The loop leaves a failing status (a trailing `false`) | RED (25 rows, including "a later gate still runs after a non-filing gh api") |
| M20 | `-F` read as `--body-file` on the api form again | RED: the `-F title=` reason row and the `-F` exit-3 row |
| M21 | The api-form refusal clause dropped | RED: the `--input` reason row |
| H1 | Harness: delete any 3 of the 33 new rows | RED: the `MIN_ASSERTIONS=160` floor trips (`FLOOR: only 157 assertions ran`) |
| H2 | Must-PASS, not canonical: a quoted collection GET beside a comment POST (`gh api -X POST "…/issues/5/comments" -f body=x && gh api "…/issues?per_page=5"`) | PASS (`<none>`) |

**Anchor.** No stored value is compared. The rows compare live hook output with literal expected
decisions in the same commit, so one diff could weaken both. Two checks sit outside the commit:

- **The differential corpus:** 22 endpoint shapes × 10 signal spellings = 220 commands, each run
  through `origin/main`'s hook and the patched hook.
- **The security review's 29-command audit corpus**, which the same review had used to find v2's
  regressions, re-run against v3.

Measured:

- **Every deny → allow flip is intended.** The flips are sub-resource paths (`issues/123/labels`,
  `issues/123/comments`, `issues/comments`, `issues/$N/labels`, `issues/{number}/labels`), plus:
  - `issues.json`, which is not a GitHub route (`gh api 'repos/jikig-ai/soleur/issues.json?per_page=1'`
    returns `Not Found`, measured);
  - `issues;` followed by the flags. Bash runs the flags as a separate command, so this is not a
    create;
  - `-X PATCH …/issues/5` (an edit, not a create);
  - the `-F title=` + `Mandated-By:` exit-3 case (§2).
- **Every allow → deny flip** is a collection shape under a newly recognised spelling (`-XPOST`,
  `--method=POST`, `--input`, `-F title=`).
- **No quoted collection GET is newly denied, and no `-X GET` command is denied.**
- **All six v2 regressions** deny, as on main.

## Acceptance Criteria

- [x] `bash .claude/hooks/guardrails.test.sh` prints `Total: 160  Pass: 160  Fail: 0`, and
      `MIN_ASSERTIONS=160`.
- [x] The new rows are RED-before-GREEN against the **base** hook. Put
      `git show b3d5652e7b:.claude/hooks/guardrails.sh` and `git show b3d5652e7b:.claude/hooks/lib/…`
      into a scratch copy of the **whole** `.claude/hooks/` directory, never into the worktree.
      Pinning the SHA keeps the count stable if main moves. Every `FAIL:` line must be a new row,
      and there must be 18 of them. The other 15 already pass on main and pin non-regression. A hook
      copied without `lib/` emits nothing, and every row then reads as an allow.
- [x] The differential corpus (Test Scenarios step 2), run against the same base copy:
  - every deny → allow flip is a sub-resource path, `issues.json`, or `issues;`;
  - every allow → deny flip is a collection shape;
  - no `-X GET` command is denied.
- [x] `grep -cE '^[^#]*_gh_api_issue=' .claude/hooks/guardrails.sh` returns `2` (the initializer
      plus the single assignment).
- [x] `bash -n .claude/hooks/guardrails.sh` passes, and
      `python3 scripts/lint-shell-capture-exit.py .claude/hooks/guardrails.sh` reports 0 new
      findings.
- [x] `git diff --name-only origin/main...HEAD -- .claude/ apps/` lists exactly
      `.claude/hooks/guardrails.sh` and `.claude/hooks/guardrails.test.sh`.

## Test Scenarios

1. **The suite.** The rows are in the `<details>` block under Files to Edit. They use
   `R = jikig-ai/soleur` so the external-repo exemption stays off. Every deny row carries no exit-1,
   exit-2 or exit-3 justification, so a deny means the CLASS 4 trigger fired rather than some other
   gate. Write the rows first and confirm the 18 RED against the base hook
   (`cq-write-failing-tests-before`), then apply the four hook hunks.
2. **Differential corpus.** A throwaway loop in the scratchpad; do not commit it. Path set:
   - collection: `repos/R/issues`, `/repos/R/issues`, `repos/R/issues/`, `repos/R/issues?x=1`,
     `"repos/R/issues"`, `'repos/R/issues'`, `repos/$REPO/issues`, `repos/{owner}/{repo}/issues`,
     `repos/R/issues>out.json`, `` `echo repos/R/issues` ``, `repos/R/issues)`, `repos/R/issues;`,
     `repos/"$REPO"/issues`, `https://api.github.com/repos/R/issues`, `repos/R/issues$QS`;
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
- **Newly denied commands.** Some unquoted collection POST spellings that pass today will be denied:
  `-XPOST`, `--method=POST`, `-X=POST`, `--input`, `-F`/`--raw-field`/attached `title=`, and
  backslash-continued multi-line api filings against our repo that carry no justification. That is
  intended. In-repo call sites were checked (`git grep` over `plugins`, `.claude`, `.github`,
  `scripts`, `apps/web-platform/server`). The only `gh api … /issues` collection POST outside tests
  is `.github/workflows/dev-ledger-reconcile.yml:391`, which runs in CI and never passes through this
  local hook.
- **Scope relative to the brief.** The brief named `"repos/o/r/issues"` (quoted) as a shape that must
  not bypass. It already bypasses on main, and this PR does not change that. See DC-1 in
  `knowledge-base/project/specs/feat-one-shot-guardrails-filing-gate-subresource/decision-challenges.md`.

## References & Research

### Research Insights

- **Premise validation.** The brief cites no issue number. It cites #9028 (rename-guard flake),
  which `gh issue view 9028` shows is still OPEN, so the warning stands. The cited file and lines
  exist on this branch's base `b3d5652e7b`. The "second reference near line 649" is comment prose,
  not a matcher. No ADR is implicated: this is a bug fix to an existing gate.
- **Property list.**
  - P1: a POST to an existing issue's sub-resource, alone or beside a listing of issues, is never
    classified as a filing.
  - P2: every **unquoted** spelling of a POST to the issues collection that gh routes to "create
    issue" is classified as a filing. The quoted spellings are pre-existing and deferred to #9089.
  - P3: `gh api` text that appears only in quoted or heredoc prose is not a filing.
  - P4: a refusal on the api form names an exit the agent can actually take.
- **Cut list.**
  - A skill-level double-check in `ship/SKILL.md` or `compound/SKILL.md` buys P1 and P2, which the
    hook enforces at the single chokepoint. Cut.
  - Changing `pre-merge-rebase.sh` buys nothing. Cut.
  - Editing the cron mirror buys P1 and P2 for the cron substrate, which `filingShape()` already
    delivers. Cut.
  - Every quote-parsing mechanism (v1's two arms, v2's first-word rewrite) bought "quoted spellings"
    at a measured cost in regressions. Cut in favour of #9089.
- **Mirror (authority grepped).** `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`,
  `filingShape()` (`:132-147`): the collection regex plus the POST signals `-X POST`,
  `--method POST`, `-XPOST`, `--method=POST`, `--input`, and `title=` under `-f`, `-F`, `--field`
  and `--raw-field`. Its tests (`cron-bash-allowlist-hook.test.ts:771-772`) assert the sub-resource
  allow.
- **`$SCAN` semantics.** `strip_command_bodies` (`.claude/hooks/lib/incidents.sh`) blanks heredoc
  bodies **and** every `"…"`/`'…'` span, and returns its input when `perl` fails.
- **Learnings applied.**
  - `2026-02-24-guardrails-grep-false-positive-worktree-text.md`: bind command and argument in one
    pattern. Per-segment matching is exactly that binding.
  - `2026-02-24-guardrails-chained-commit-bypass.md`: guards must reason about `&&`/`||`/`;` chains.
  - `2026-06-12-command-detection-hook-fp-sweep-and-fixtures-as-latent-bug-detectors.md`: phrase
    gates read stripped text. The source stays `$SCAN`.
  - `2026-09-10-every-escape-my-mutations-could-not-reach.md`: measure the predicate with an escape
    corpus, not only mutations. The security review's audit corpus is what falsified v2.
- **Related issues.** #9089 was filed during this planning. Its comments record the residuals and
  the design history. No open `code-review` issue touches either file.
- **Community overlap:** none (functional-discovery queried 3 registries; there were 0 relevant
  results).

### Plan Review and Consult Record

- **Advisor consult (plan Step 4.5).**
  - Applied: reading the signal only from quote-blanked text, `-ftitle=`, and the GraphQL and
    lowercase-method residuals.
  - Cut: the shared bash/JS corpus.
  - Superseded: the two-commit order.
- **Plan review, round 1 (v1).**
  - DHH P0 and Kieran P1: the nested-quote false positive. This led to v2.
  - DHH P1: move the escape closures out. Adopted in v3 for the quoted class.
  - Kieran P2s: the bare `?` row, the table, the `grep -c` anchor, and running M16. All applied.
  - Simplicity: kept the core; cut the two-commit order and the duplicate prose.
  - CTO: §2 and §3 applied, plus the `assert_reason` rows.
- **Deepen.**
  - Security-sentinel: six v2 regressions, the quoted-GET false positives, and the list-then-label
    loop. This led to v3, and all are pinned by rows or covered by the audit corpus.
  - Test-design: the vacuous commit-message row was replaced (v3 has no such row, and the heredoc
    and body-mention rows carry P3). The M5/M6 attributions are moot in v3. The base SHA is now
    pinned in the RED AC. The full-URL row and the `--input` split were added.
  - Verify-the-negative: all ten factual claims confirmed. One stale "quoted-value signal" reference
    was removed.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- **Copy the hunk exactly.** The perl program sits inside a single-quoted bash string, and the
  regexes carry a backtick and `\\` inside bracket expressions. Run `bash -n` and the suite after
  pasting.
- **Portability.** The hook runs on operator hosts, macOS included. The hunk adds no new binary:
  `perl` is already required by `strip_command_bodies`, and `grep -E` is already used. It adds no
  regex construct beyond what the existing trigger uses (`\s`, `\b`, POSIX classes). The backtick and
  `\\` inside the bracket expression are literal in both GNU and BSD `grep -E`. `sed` was avoided
  deliberately, because BSD `sed` label and newline syntax differs.
- **Do not add a quote-parsing step to "close" the quoted escape.** Both attempts are recorded in
  Alternatives with their measured regressions. Any future attempt belongs to the #9089 tokenizer,
  and must be run against the security review's audit corpus (both directions) before merge.
- **The natural repair of a new refusal.** An agent denied on the api form will most likely add
  `-f 'labels[]=meta/machinery'` (honest, exit 1, and now named in the refusal) or switch to
  `gh issue create`, which is gated. The repairs that still pass are quoting the endpoint,
  `"$(…)"`, `bash -c "…"` and GraphQL. All are on #9089, and this PR does not claim to close them.
- **Text rather than invocation, in the over-fire direction.** `echo gh api repos/R/issues -X POST`
  and a `#` comment carrying that text in the same segment are gated. This is unchanged from main and
  fails toward gating.
- Do not "simplify" the terminator into a negated class (M17), or owner/repo into two segments (M8).
  The mirror uses two segments because it sees **expanded** tokens, while this hook sees the
  unexpanded `$REPO` word.

## Addendum — 2026-09-27 (PR #9088 review round)

A nine-seat review of `154f9a68dd` measured regressions the v3 design shipped
(main denied, v3 allowed), all fixed in the review commit:

- The segment split cut through **redirect operators** (`2>&1`, `&>`, `>&2`,
  `<&0`, `>|`) and through an unquoted **`$(a | b)` / backtick** argument,
  separating the endpoint from its POST flag. The split is now one perl pass
  that drops redirect operators and splits only at nesting depth 0.
- **`#`** was missing from the terminator list; gh strips the fragment and
  POSTs to the collection (measured against a local listener).
- The new **`(^|[[:space:]])` anchor** on the POST signal was dodged by `\-f`,
  `${E}-f` and `$E-f`. The signal is unanchored again, as on main.
- The bash loop forked `grep` **per segment** (a 64 KB, 10.9k-segment command
  took ~17.5 s; hook timeouts are non-blocking). The whole match now runs in
  the one perl process; a perl failure falls back to a whole-command match.
- `--input` moves `-f`/`-F` fields to the query string, so `-f
  'labels[]=meta/machinery'` beside `--input` credited exit 1 while filing an
  unlabelled issue. `--input` filings now get their own refusal, and the
  generic refusal names the exit-1 spelling for the form used.

Corrections to claims above, which describe the base commit `b3d5652e7b`:
the line numbers are base-commit references; `filingShape()` is the cron
**mirror**, not an equal — this hook is deliberately wider (unexpanded
`$VAR` endpoints, `-ftitle=`, `-X=POST`, `--input=`), and the mirror's own
gaps are recorded on #9089. The suite is 195 rows (floor 195); 15 of the
review-round rows are RED against `154f9a68dd`.
