---
title: My segmenter split on characters the shell reads as one command
date: 2026-09-27
category: security-issues
module: .claude/hooks/guardrails.sh
tags: [guardrails, hook, segmentation, shell-grammar, mutation-battery, review]
pr: 9088
issues: [9089]
---

# Learning: my segmenter split on characters the shell reads as one command

## Problem

PR #9088 narrowed the gh-api issue-filing trigger in `.claude/hooks/guardrails.sh`
so that a POST to an existing issue's sub-resource (`issues/<N>/labels`) is no
longer treated as a new filing. The design required the endpoint and its POST
signal to share one *command segment*. It split the quote-blanked `$SCAN` on
`&& || ; & |` and newline, and ran two `grep`s per segment.

That design went through three plan-review rounds, a deepen-phase security
review with a 29-command audit corpus, a 220-command differential corpus and a
21-row mutation battery. Every mutant was caught. The code still shipped five
regressions (commands main denied and the PR allowed) plus a cost regression:

- **Redirect operators** (`2>&1`, `>&2`, `&>`, `&>>`, `<&0`, `>|`) carry a `&`
  or `|` that is NOT a command separator, so the split cut one command in two.
  A redirect between the endpoint and `-X POST` let a create through.
- **An unquoted `$(a | b)` or backtick argument** was split the same way.
- **`#fragment`** was missing from the closed terminator list. gh strips the
  fragment, so the request is a real POST to the collection (measured against a
  local listener).
- **A new `(^|[[:space:]])` anchor on the POST signal** was dodged by `\-f`,
  `${E}-f` and `$E-f`, which all reach gh as `-f`. Main's signal was unanchored.
- **One `grep` fork per segment** made the hook O(segments). A padded 64 KB
  command took about 17 s, and a hook timeout is non-blocking, so padding
  becomes a way around the gate.

The review also found that the refusal text told `--input` filers to add
`-f labels[]=meta/machinery`. With `--input`, gh moves `-f` fields to the query
string, so that "exit" filed an unlabelled issue.

## Solution

- Do the whole match in **one perl pass**:
  1. Join `\`-newline continuations and neutralise escaped separators.
  2. Drop redirect operators. Remove a leading fd number only when it stands
     alone (`(?<!\S)\d+`), so `issues/123>&2` keeps `123`.
  3. Split on `;&|`/newline only at **nesting depth 0**, tracking `(` `)` and
     backticks, so a substitution stays inside the command that contains it.
  4. Match endpoint and signal per segment.

  It prints `2` for an `--input` filing, `1` for any other filing, `0` otherwise.
- **Fallback:** if perl fails, use a whole-command match, which errs toward
  gating.
- Add `#` to the terminator list and remove the POST-signal anchor.
- Give `--input` filings their own refusal. The generic refusal now names the
  exit-1 spelling for the form actually used.
- **Harness fix:** `decision_of`/`reason_of` now report a non-zero hook exit as
  `<rc=N>`. Before, an exit-2 block read as an empty-output allow, so every
  allow row could pass over a hook that blocked the call.
- **Tests:** 35 new rows, one per member of every alternation (terminator,
  POST signal, splitter escapes, each redirect form). 15 of them fail against
  the pre-review head. The floor went 160 → 195, and all 13 new mutants are
  caught.

## Key Insight

**A string-level segmenter is a claim about shell grammar, and the characters
it splits on are overloaded.** `&` is a separator, a redirect (`>&`, `&>`) and
part of `&&`. `|` is a pipe and part of `>|`. `;` inside `$(...)` belongs to the
substitution. Every overload is an input on which the segmenter disagrees with
bash, and each disagreement is a bypass in the direction that matters.

This class was already written down: review/SKILL.md carries it from #8354
("a guard that SEGMENTS text before it judges it fails in the segmenter"). It
recurred because plan and deepen never read that file. The rule lived only at
the phase that runs after the design is fixed. The mutation battery could not
catch it either, because every row perturbed the matcher and none added an
overloaded construct to the input.

The second insight is that **anchoring a signal to "whitespace or start" is a
narrowing**. The shell reaches the same argv through `\-f`, `${E}-f` and
`$E-f`, so an anchor added for tidiness opened three routes the unanchored
original had closed.

## Session Errors

1. **The first before/after corpus runs were invalid, because the hook was
   copied without its `lib/`**, so every command read as allow (forwarded from
   plan phase).
   - **Prevention:** run any hook experiment against a copy of the whole
     `.claude/hooks/` directory, never the single file. The plan's ACs now say
     so.
2. **Two designs (v1 two-arm, v2 first-word rewrite) were measured broken and
   discarded** (forwarded). Recovery: v3.
   - **Prevention:** run the security audit corpus in both directions before
     adopting a design (already practised).
3. **A background-polling guard fired a false positive and the command was
   re-run in the foreground** (forwarded).
   - **Prevention:** one-off; none needed.
4. **`spec.md` has no `lane:`, so the plan defaulted to cross-domain**
   (forwarded).
   - **Prevention:** one-off.
5. **The refusal-text edit embedded `'labels[]=…'` single quotes inside a
   single-quoted `jq` program.** `bash -n` passed, because the quotes still
   balanced, so the text was silently unquoted and glob-exposed. It was caught
   by reading the surrounding context before committing and switched to
   backticks.
   - **Prevention:** before editing a string literal, read which quoting
     context encloses it. `bash -n` does not detect a quote that closes and
     reopens.
6. **v3 shipped the five segmenter regressions and the per-segment fork cost
   past three review rounds, a 220-command corpus and a 21-row battery.**
   Recovery: a nine-seat review and the single-perl rewrite.
   - **Prevention:** a plan that adds a shell-text segmenter must fixture every
     overloaded construct: redirects with `&`/`|`, `$(...)`, backticks, escaped
     separators and `#`. It must also state the matcher's fork cost per
     segment. This is routed to plan-sharp-edges.md.
7. **The plan asserted that the new spellings "match `filingShape()`" and the
   comment said the mirror "must agree". Neither was measured, and both were
   false.** This hook gates `-ftitle=`, `-X=POST`, `--input=`, `$REPO` and
   `issues$QS`, all of which the mirror returns null for. Recovery: the comment
   now says this side is deliberately wider, and the mirror gaps are recorded
   on #9089.
   - **Prevention:** any "A matches B" claim needs a probe that runs both.
8. **The structural-enumeration review seat was stopped by a safety
   classifier.** Its prompt asked it to list every path by which a filing
   "reaches GitHub without the gate firing", which reads as bypass generation.
   Recovery: the other eight seats covered the ground.
   - **Prevention:** for a guard whose sink is a policy gate, phrase the seat
     as a coverage map of the guard's assembly and its test rows. This is
     routed to review/SKILL.md.
9. **A closing message promised a follow-up check ("I'll check that myself")
   without doing it, and the stop hook blocked the turn.** Recovery: the check
   was run in the same turn.
   - **Prevention:** already hook-enforced (`unkept-promise-hook.sh`).
10. **The `--input` refusal sentence pointed filers at an exit that `--input`
    makes a no-op, because gh sends `-f` fields to the query string.**
    Recovery: a dedicated `--input` refusal.
    - **Prevention:** when refusal text prescribes a recovery, run that
      recovery through the tool and confirm the result carries it, not just
      that the hook allows it.
11. **The suite's `decision_of` read a non-zero hook exit as an allow**
    (pre-existing). Recovery: it now reports `<rc=N>`.
    - **Prevention:** a harness that treats empty output as the success verdict
      must also check the exit code.
12. **The compound commit failed `lint-skill-body-budget`.** Routing a note to
    `review/SKILL.md` took the file 311 bytes over its ceiling, because it had
    about 19 bytes of headroom. Recovery: the note stays in this learning only.
    - **Prevention:** before routing an edit to a large skill, run
      `lint-skill-body-budget` on the target, or check its headroom.

## Tags
category: security-issues
module: .claude/hooks/guardrails.sh
