---
title: "A 'medium severity test failure' was a repo-destroying bug for five months"
date: 2026-09-04
category: workflow-issues
module: plugins/soleur/test
problem_type: data_loss
component: lefthook
root_cause: severity_misclassification
severity: high
tags: [lefthook, git, environment-variables, test-isolation, pre-commit, data-loss, measurement]
issue: 7772
pr: 7805
synced_to: []
---

# A "medium severity test failure" was a repo-destroying bug for five months

## What happened

Running `/one-shot` on #7772, a routine `git commit` in a worktree destroyed the
branch: 16 stray `base`/`change` commits landed on the feature branch and the index
was cut from ~14,000 entries to 2. I recovered with `git reset --mixed <real-tip>`,
retried with one lefthook step excluded, and **it happened again** from a different
step. Same day, main landed #7782 — where the same fixture did the same thing and the
stray commits were **pushed**.

## Root cause, reproduced rather than inferred

Git exports `GIT_DIR` and `GIT_INDEX_FILE` into hook environments. Lefthook runs the
test battery from `pre-commit`. Node/Bun fixtures shell out via `execFileSync`, which
inherits `process.env`. **`GIT_DIR` overrides `cwd`.** So a fixture that sandboxes
correctly — `mkdtemp`, `git init`, `cwd: dir` — still escapes:

```bash
git init -q victim && git -C victim commit -q --allow-empty -m victim-tip
export GIT_DIR=$PWD/victim/.git GIT_INDEX_FILE=$PWD/victim/.git/index
cd sandbox
git init -q                       # creates NO sandbox/.git
git commit -q --allow-empty -m base
mkdir -p apps/web-platform/app && echo hi > apps/web-platform/app/page.tsx
git add -A && git commit -q -m change
```

`sandbox/.git` does not exist; both commits land on the victim's branch; the victim's
index is rewritten to the sandbox's file list. Byte-for-byte the damage observed.

## The actual lesson: the diagnosis was right and the severity was wrong

**This was already a documented learning.**
`workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`, five months
earlier, names the identical mechanism. `welcome-hook.test.ts` already carried the
fix, and its comment already said "all GIT_* variables that lefthook injects".

It was filed as:

```yaml
problem_type: test_failure
severity: medium
symptoms:
  - "welcome-hook test passes individually but fails in lefthook pre-commit batch"
```

Every word is accurate **about the instance that was observed**. The observed symptom
was a flaky test, so it was recorded as a test-isolation problem and fixed in the one
file where it had surfaced. Nobody swept, because a medium-severity test nuisance does
not warrant a sweep.

But the mechanism is not "a test resolves the wrong repo". It is **"an arbitrary
process writes to the developer's live repository with the developer's index"**. The
same leak that makes an assertion read the wrong `git rev-parse` makes a `git commit`
land on the wrong branch. The symptom was medium; the capability was destructive.

**Classify by the CAPABILITY the mechanism grants, not by the symptom that surfaced
it.** An env leak into a process that runs `git commit` is a data-loss class even if
the day it was found it only reddened an assertion. Had the April entry read
`problem_type: data_loss`, the sweep would have been proportionate and #7782 and this
PR would not have lost their branch tips.

Measured cost of the mis-classification: **9** TS fixtures `mkdtemp` + `git init` a
sandbox; **1** scrubbed the env. Shell fixtures unaudited. Tracked at #7835 with a
lint, because a sweep without a gate decays exactly the way the first fix did.

## Three smaller things this session, same shape

**Kill the runaway before restoring the state.** After the first wipe I ran
`git reset --mixed` and moved on — but never killed the `git commit` whose hook caused
it. It kept running for **two hours**, held `.git/soleur-session-state/locks/test-all.lock`
(the lock that makes sibling worktrees refuse with rc=4, so I was blocking two other
live sessions), and was still executing the destructive path. Recovery order is:
stop the writer, then repair the damage. I did it backwards.

**A construct anchor is not enough while the corpus quotes the construct.**
`cq-assert-anchor-not-bare-token` says to anchor on a construct rather than a bare
token. I did — `indexOf('"$${STAGE}_warn" warning')` — and then wrote a template
comment that *quoted that exact literal*. `indexOf` found the prose ~400 lines above
the real emit and the arm failed against a correct template. The rule needs its second
half: **quantify over the corpus that ships.** Stripping whole-line `#` comments is
both immune to prose and more faithful, because ADR-152's render-time strip removes
exactly those lines.

**A tool that silently returns nothing reads exactly like absence.** For several turns
I concluded an assertion "is not in the tree" because `grep` found nothing — in main,
in the merge commit, everywhere. The shell's `grep` wrapper injects `-I`, the suite
trips binary detection, and matches were dropped **with no diagnostic**. The tell was
available and I ignored it: the failing suite printed a summary format that matched a
file my greps claimed was empty. When a search contradicts other evidence, suspect the
search before concluding absence — `command grep -a` settled it in one call.

## And one that is about numbers, not tools

Merging main surfaced a conflict on the Art. 30 retention cell. My side asserted
**3 days** for Better Stack source 2457081 (inherited from a runbook); main's #7717
asserted **NOT RECORDED**, reasoning that retention follows plan tier and the tier
cannot be pulled (`/usr/…/usage`, `/usage`, `/billing` all 404 — true).

Measured instead of adjudicated, twice, on two endpoint shapes: **both sources report
`logs_retention=90`**. The 3-day figure was a free-tier value predating a paid upgrade
— and it had already reached the Art. 30 register and **both published legal
documents**. #7717's inference was also wrong: `logs_retention` is a per-source
**attribute**, not a billing field, so the unknown tier never blocked reading it.

Two positions, confidently held, both false, and the check was one API call. When a
merge conflict is two parties disagreeing about a *measurable fact*, the resolution is
never to pick a side.

## Links

- Prior, same mechanism, under-classified: `workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`
- Sweep + lint: #7835 · markdownlint backlog: #7837 · Better Stack DPA/location: #7825
