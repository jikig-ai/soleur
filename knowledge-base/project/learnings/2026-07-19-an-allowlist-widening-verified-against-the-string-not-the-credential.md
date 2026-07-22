---
title: "A security allowlist was widened on a property of the string, not of the credential — and the doc explaining it tripped the rule"
date: 2026-07-19
category: security-issues
module: secret-scan
issue: 6706
pr: 6717
tags: [gitleaks, secret-scanning, ci, allowlist, vacuous-test, mutation-testing]
---

# Learning: a widening justified by a string property that was not a credential property

## Problem

#6706 reported `secret-scan` red on `main` for a commit that never merged, and proposed two
fixes: widen the `database-url-with-password` placeholder allowlist so a documentation comment
stops tripping it, and scope the `push:main` walk so an unmerged branch cannot redden the gate.

The plan implemented both. The widening added `pass|passwd|pw` to the password-side alternation,
justified — in the plan, in the commit message, in the runbook, and in a purpose-built
mutation-verified test — by this claim:

> every branch is terminated by `@`, so it matches only when the password is *exactly* the
> placeholder token.

That sentence is **true of the string and false of the credential**, and the difference is a
silenced production secret.

## Root cause

Two parser assumptions compose:

1. The rule's password class is `[^@/\s]+`, so the rule's own match **stops at the first `@`**.
2. The allowlist entry is an unanchored **search** against that match.

Every real URL parser takes userinfo to the **last** `@`. So for

```
postgres://user:pass@Xq7vNp2LmWd4@db.test/appdb
```

the true password is `pass@Xq7vNp2LmWd4`, but the rule matches only to the first `@`, and the
allowlist finds `postgres://user:pass@` inside that match → allowlisted → **silently not
reported**. Measured, against the pre-PR config vs the widened one:

| Fixture | pre-PR | widened |
| --- | --- | --- |
| `postgres://user:pass@<realsecret>@db.test/appdb` | rc=1 detected | **rc=0 silenced** |
| `postgres://user:pw@<realsecret>@rds.test` | rc=1 detected | **rc=0 silenced** |
| `postgres://postgres:pass@word2026@db.test` | rc=1 detected | **rc=0 silenced** |

Passwords containing `@` are common in generated credentials. The class pre-existed for
`password`/`secret` (filed as #6723) — the widening turned a narrow gap into a broad one, because
`pass`/`pw`/`passwd` are far likelier to *head* a real password.

## Solution

**Revert the widening entirely.** Two measurements showed it was unnecessary as well as harmful:

1. `vector.toml` already documents the shape as `postgres://<user>:<pw>@host`, which the
   pre-existing `<[^>]+>` branch covers. The current tree scans **rc=0 under `origin/main`'s own
   config** — no widening was ever required.
2. The flagged commit's branch had been **deleted from origin**; no remote ref contained it. The
   acute symptom self-resolved without the PR, exactly as the issue predicted it might.

The PR ships only the ref-scope fix, which is the durable half. The pre-existing multi-`@` gap is
filed as #6723 rather than bundled — changing the rule's match semantics has repo-wide blast
radius.

## Key insight

**Ask what the invariant is a property OF.** "Terminated by `@`" is a property of the matched
*string*. The security property needed is about the *credential*, and the two diverge exactly
where the rule's own tokenizer disagrees with a real parser. Whenever a guard is justified by a
regex-shaped argument, name the parser whose disagreement would break it — here, that `[^@/\s]+`
stops where `urlsplit` does not.

The corollary is about evidence: a plan, a commit message, a runbook paragraph and a
mutation-verified test all asserted this claim. **Four artifacts agreeing is one artifact, when
they all inherit the same sentence.** Only an adversarial attempt to *construct a bypass* falsified
it, and that attempt took one command.

## Session Errors

**A security allowlist widening silenced real credentials** — the `@`-anchor claim was true of the
string, not the credential. Recovery: reverted Phase 1 in full; `.gitleaks.toml` is byte-identical
to `origin/main`; filed #6723 for the pre-existing half. Prevention: for any allowlist/denylist
edit, require one adversarial construction attempt (*"produce an input that satisfies the allowlist
and is still a real secret"*) before the change is considered verified. Passing fixtures are not
that attempt.

**The runbook documenting the rule tripped the rule** — literal near-miss DSNs were written into
`knowledge-base/engineering/operations/secret-scanning.md`, which is not in the rule's `paths`
allowlist. This reddened `secret-scan` on the PR *and* on `main` (8 findings from my own branch).
Recovery: rewrote the examples to terminate in `@<host>` (`<` is outside the rule's host class
`[A-Za-z0-9.\-]`; note `@HOST` does NOT work — uppercase is in the class). Prevention: before
writing a credential-shaped example into any file, check whether that path is allowlisted; prefer
the angle-bracket placeholder form, which is allowlisted everywhere.

**Fixing the literals at the tip did not clear the gate** — `gitleaks git` scans the commit
**range**, so the introducing commits still fired even though the tip tree was clean. The plan's
own Sharp Edges documented this exact trap and I still hit it. Recovery: `git reset --soft` to the
last clean commit and rebuild the history (no `rebase -i` in this environment). Prevention: when a
secret-shaped string has ever been committed on a branch, the fix is always a history rewrite —
treat "I fixed it in a later commit" as a non-fix for anything gitleaks gates.

**A comment explaining the split-literal trap was itself a firing literal** — `postgresql://user:$VAR@host`
matches, because `$`, `{` and `}` all sit inside the rule's password class. Recovery: reworded to
describe the shape without completing it. Prevention: interpolating a shell variable into the
password position does not make a line safe; assemble the whole DSN at runtime or use the
angle-bracket form.

**Reported the full test suite as green from a background notification** — the harness reported
"exit code 0", which was my command's trailing `grep` pipeline, not the runner. The real exit was
**143 (SIGTERM)** and the run was truncated at `guardrails.test.sh` with 21 suites never executed.
I stated the gate had passed before checking. Recovery: read the captured `TESTALL_EXIT`, then ran
the unrun remainder (42 suites, 0 failures). Prevention: never end a backgrounded command with an
`echo`/`grep`/`tail` after the command whose status matters — and treat a completion notification's
exit code as reporting the *last* pipeline stage, never the runner. Capture `rc=$?` immediately and
grep the log for the runner's own summary line.

**Treated "no failures found" as "the exit gate passed"** on a run that was killed 60% of the way
through. Absence of failures in a truncated run is not evidence of a green suite. Prevention: check
the runner reached its own terminal summary before concluding anything from its output.

**Asserted that `apps/web-platform/scripts/*` contains the allowlist-diff and rename-guard suites**
— it does not; neither script has a unit test, they are exercised only by the workflow's own smoke
matrix. Recovery: listed the directory and corrected the claim in the same turn. Prevention: verify
a "the tests for X live at Y" claim with `git ls-files` before using it to justify a coverage
conclusion.

**Cited a vacuous fixture as evidence for the `@` anchor** — `svc:pass-but-longer` fires because
`svc` fails the USER-side alternation, not because of the anchor, and it passes identically with
the anchor deleted. Right verdict, wrong reason. Recovery: re-derived with `user:`-prefixed
fixtures and mutation-proved the difference. Prevention: for any fixture offered as evidence for
property P, mutate P out and confirm the fixture flips; if it does not, it is evidence for
something else.

**The first version of the test guard was vacuous across four dimensions** — it varied the password
token richly while holding user, host, scheme and password length constant, so pinning the rule's
host, dropping `postgresql://`, or adding a `{8,}` length floor each left it 16/16 green while real
credentials went undetected. Recovery: rewrote so each row varies exactly one dimension, plus T8
for allowlist arity; all four mutations now go RED. Prevention: for each property a guard claims,
ask *what set does this quantify over, and how many members does it sample* — one point per
dimension is vacuous for every dimension pinned by accident.

**Adding the advisory sweep late falsified three claims already written** — the ref-scope table, the
trade-off paragraph, and the workflow's own trigger header all still described a one-invocation
world. Recovery: re-derived all three. Prevention: after any late behavioural addition, re-read
every artifact that describes the behaviour — this is the same drift class the PR's own AC11
("stale wording removed") exists to catch.

**`tasks.md` continued asserting the reverted widening as verified** after the revert, including
ticked Phase 1 checkboxes and six passing ACs. Recovery: marked Phase 1 REVERTED and annotated
which ACs are superseded, retaining them as the record of what was measured. Prevention: a revert
is not complete until the artifacts that recorded the reverted work say so.

**Published plan-quoted numbers without re-measuring** — the plan's 3228/3094 commit counts were 13
commits stale (actual 3241/3097), and its "`git log -p` emits 0 bytes" for a merge commit is really
302 bytes total with 0 *patch* bytes. Both caught before merge. Prevention: already covered by the
existing rule that plan-quoted measurements are preconditions to verify; the addition here is to
prefer publishing the *command* over the number when the number tracks a moving target.

**Three hook denials, each correct** — `git stash list` (blocked even read-only), a backgrounded CI
poll loop (must use Monitor), and four `git-commit-secret-scan` denies. One compounding effect worth
noting: a PreToolUse denial rejects the **entire** Bash call, so a `git reset` that preceded a
blocked `git commit` never ran, and the next attempt failed against a stale index with stale line
numbers. Prevention: when a call is hook-denied, assume *nothing* in it executed, and re-establish
state in a separate call before retrying.

## Prevention (summary)

1. For allowlist/denylist edits, require an adversarial construction attempt, not passing fixtures.
2. Name the parser whose disagreement would break a regex-shaped safety claim.
3. Before writing a credential-shaped example anywhere, check the path's allowlist status.
4. A secret-shaped string ever committed on a branch requires a history rewrite, not a tip fix.
5. Never end a backgrounded command with a pipeline after the command whose exit status matters.
6. For each guard property, count the members of the set it quantifies over.

## Related

- #6706 — the originating issue (ref-scope defect)
- #6721 — merge-commit-exclusive content invisible to every gitleaks job
- #6723 — the pre-existing multi-`@` allowlist bypass
- #3888 — `allowlist-diff` parser is blind to `regexes` edits
- `knowledge-base/engineering/operations/secret-scanning.md` — ref scope per event, known gaps
