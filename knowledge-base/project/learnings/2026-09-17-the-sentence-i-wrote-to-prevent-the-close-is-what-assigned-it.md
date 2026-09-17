---
title: "The sentence I wrote to prevent the close is what assigned it"
date: 2026-09-17
category: workflow-patterns
issue: 7535
pr: 8242
tags: [github-api, closing-keywords, proxy-vs-control-surface, prose-guards, measurement, review-catches]
synced_to: [ship, review]
---

# The sentence I wrote to prevent the close is what assigned it

## Problem

PR #8242 existed for exactly one reason: #7535's Phase 2 implementation had shipped in a parallel
session's PR (#8249), so the docs-only PR **must not** close #7535 ahead of it. Merging the wrong
one leaves the issue closed with the implementation unmerged.

I edited every artifact I could think of:

- plan frontmatter `closes: 7535` → `refs: 7535`
- a one-line pointer in `spec.md`
- a one-line pointer in `tasks.md`
- PR body prose reading **"`Refs #7535` — not `Closes`"**

Then measured:

```
gh pr view 8242 --json closingIssuesReferences  ->  [7535]     # the DOCS pr
gh pr view 8249 --json closingIssuesReferences  ->  []         # the IMPLEMENTATION pr
gh issue view 7535 --json closedByPullRequestsReferences -> [8242]
```

The docs PR held the close. The implementation PR held none. Every artifact I had edited was a
**proxy**.

## Root cause

The PR body contained this sentence, written to explain the disposition:

> …in frontmatter, so this branch cannot clo{}se #7535 ahead of the implementation.

(keyword deliberately broken here so this file cannot re-arm it)

GitHub's closing-keyword parser matches **keyword followed by reference** and **does not model the
negation**. "cannot close #7535" contains "close #7535". The sentence written to *prevent* the
close is what assigned it.

No commit message carried a keyword *at that moment*, and no manual sidebar link existed — I
checked both before concluding. The body prose was the cause of **that** close.

> **[Corrected post-merge]** The commit-message half of that sentence stopped being true later the
> same day, and it is the more useful half. See
> `## The third surface: commit messages reach the squash body` below — by merge time two commits
> on this branch DID carry keyword-then-ref adjacencies, both written while *documenting the trap*.
> A clean measurement of a mutable surface is a reading, not a property; this file originally
> recorded it as a property, which is how it came to assert something false about its own branch.

Two things made this hard to see:

1. **The control surface is not where the intent lives.** Issue closure is decided by (a) the PR
   body keyword and (b) GitHub's linked-issue association. Plan frontmatter is read by *no code at
   all* — measured: an anchored grep for field access on `closes:`, `refs:` and `implementation_pr:`
   across `plugins/soleur/lib`, `plugins/soleur/scripts`, `scripts` and `.claude/hooks` returns
   **zero** hits for all three. Editing frontmatter to prevent a close is editing the comment above
   a firewall rule.
2. **It survived three careful reads.** After fixing it I added an assertion over the body text
   before each push. It **rejected my first two fixes** — each had re-armed the trap inside the
   sentence explaining the trap ("would have closed #7535", then a verbatim quotation of the armed
   string). Only the mechanical check held.

## Solution

De-arm the body so no closing keyword is adjacent to the reference, then **re-assert the field**:

```python
hits = re.findall(r'(?i)\b(clos(?:e|es|ed)|fix(?:e[sd])?|resolve[sd]?)\s+#7535', body)
assert not hits, f"STILL ARMED: {hits}"
```

Chain the push behind the guard (`python3 … && gh pr edit …`) so a failed check cannot push. Then:

```
gh pr view 8242 --json closingIssuesReferences  ->  []
gh issue view 7535 --json closedByPullRequestsReferences -> []
```

And rewrite the acceptance criterion to assert the **field**, not the prose. The plan's AC30 read,
*at this point in the sequence* (it was inverted hours later — see the next section, and read the
plan for the live text):

> this PR's body uses `Refs #7535`, never a closing keyword, **and
> `gh pr view <this-PR> --json closingIssuesReferences` returns `[]` at merge.**
> Assert the API field, not the prose: a body that *says* `Refs` is not evidence.

A companion AC30b was added for the other side, because nothing asserted it: **#8249 must carry
`[7535]` before it merges**, or the issue stays open and the whole disposition silently fails.

### AC30b failed, and the failure is the better finding

It failed the same day it was written. Measured at 15:57Z:

```
gh pr view 8249 --json state,mergedAt,closingIssuesReferences
  -> MERGED 2026-09-17T13:47:30Z, closingIssuesReferences []
gh issue view 7535 --json state,closedByPullRequestsReferences
  -> OPEN, closedBy []
```

The implementation merged to `main` as `4dbd1affe` and #7535 was left open, closed by nothing —
the precise outcome AC30b existed to prevent. It named the right field, on the right PR, and was
raised as a comment there. None of that could make it true, because **its subject was another
session's PR body**, and a merged PR's body no longer closes anything.

So the criterion was not wrong; it was *unenforceable by its owner*. **An acceptance criterion
whose subject you cannot write to is a monitor, not a gate.** It can be measured, reported and
escalated, and it will still be sitting there unsatisfied at merge. The defect is structural: I
wrote a gate against a control surface outside my write scope and then treated raising it as
discharge.

The fallback has to be in your own power. Here it was: the docs PR could simply take back the
close, because by then the implementation was already on `main`, so closing the issue could no
longer run ahead of the work. AC30 was inverted to `Closes #7535` / `[7535]`, which is a criterion
this session can actually satisfy — and the inverse of the original trap applies with equal force,
because a body that *says* `Closes` is no more evidence than one that said `Refs`.

## Key insight

**A guard written in prose can be defeated by the parser that reads the prose.**

This repo already has `cq-assert-anchor-not-bare-token` — an assertion anchored on a bare token is
satisfied by the comment that explains it. This is the same defect with **GitHub's parser standing
in for the grep**, which means the class is broader than the rule states: it applies to *any*
consumer that pattern-matches prose it did not author. A changelog generator, a release-note
scraper, a Jira smart-commit parser, a bot that greps PR bodies for directives — each is a consumer
whose matcher your prose can trip while reading, to a human, as the opposite.

The second-order form is the one to internalise: **when a PR's purpose is to PREVENT an automated
effect, the acceptance criterion must assert the field that carries the effect.** Prose describing
the intent is not evidence of the outcome, and the more carefully the prose is written, the more
convincing the false evidence becomes.

## The third surface: commit messages reach the squash body

The body was fixed, the field measured `[]`, and a regex guarded every subsequent body edit. Then
`gh pr merge --auto --squash` was **refused by a hook** (`.claude/hooks/pre-merge-auto-close-scan.sh`):

```
BLOCKED: a commit/PR body has a prose-embedded auto-close keyword that will auto-close an issue on merge
  a commit message:   "#8043 F11 is a wrong attribution, use #8052" -- #8052 clo{}ses #8043 and #8043 has an
  a commit message: this, the docs PR would clo{}se #7535 ahead of the implementation that actually
```

(keywords broken here, as everywhere in this file, so the record cannot re-arm what it describes)

A **squash** merge concatenates commit messages into the squash commit's body, so a keyword in any
commit message is a keyword in the merge commit — and one of these named **#8043, an issue this PR
had nothing to do with**. It entered while writing the sentence that *reports* the refuted agent
finding about #8043/#8052; the other entered while writing the sentence that *explains* this very
trap. That is the third and fourth time in one session that documenting the trap re-armed it, after
the two body-edit attempts recorded above.

Measured afterwards: #8043 was already `CLOSED` (2026-09-13, by merged PR #8052), four days before
this session, so **no collateral close occurred**. The guard was still right to fire — the hazard
was real and its harmlessness was luck, not design.

Three things worth keeping:

1. **Enumerate the surfaces a matcher reads, not the one you edited.** For issue closure on a
   squash-merge repo those are: the PR body, every commit message on the branch, and the manual
   sidebar link. This file had already found the body; the commit messages were measured once, early,
   and then trusted for the rest of the session while I kept writing commits.
2. **A mutable surface measured clean is not a surface that stays clean.** The generalisation of
   AC30's rule: re-assert after every edit applies to *commit messages* as much as to the body, and
   `git rev-list origin/main..HEAD` + one anchored grep is the whole check.
3. **The hook was the only thing that caught it.** No self-review did, on a branch whose entire
   subject is this defect class. Mechanical enforcement is not a backstop to careful reading here;
   careful reading is what demonstrably fails.

Recovery, for the record: reworded both messages with `filter-branch --msg-filter` (it preserves
merge commits, and `rebase -i` is unavailable in this environment), then verified zero adjacencies
with a positive control, and verified the rewritten tree **byte-identical** to a backup branch so
the rewrite could not have changed content.

## When the base moves faster than one CI cycle

#8242 needed **seven** CI cycles to merge. Not one was caused by a defect in the diff: every check
that ever settled on every head passed. The cause was base churn — `main` landed a commit roughly
every 20–40 minutes while a full cycle took ~40, so the branch went `BEHIND` or `CONFLICTING`
before the last shard finished, and each resolution restarted the cycle that the next commit would
invalidate.

Resolving faster does not converge on this; it is a race whose step is shorter than its round trip.
What converged was **`gh pr merge --auto`**: arm it once and GitHub merges on the first moment
checks pass, with no need to occupy a quiet window by hand. Two details mattered:

- **Auto-merge does not update a stale branch.** It survives a sync, and it sat armed across four
  resyncs here, but `BEHIND` still had to be cleared explicitly (`sync-pr-behind.sh`). Arming it is
  not walking away.
- **Every conflict was `knowledge-base/INDEX.md` / `kb-tags.txt`**, which every KB-touching PR
  regenerates. The repo's `kb-index` merge driver resolved them locally each time with zero unmerged
  files, while GitHub reported `CONFLICTING` — because its merge ref cannot use a local driver. The
  conflict did not exist in any tree; committing the local resolution is what cleared it.

## Prevention

- For any PR that must **not** close an issue, assert `gh pr view <N> --json closingIssuesReferences`
  is `[]`. Do this after every body edit — the field is recomputed from the live body.
- **Sweep the commit messages too, not just the body.** On a squash-merge repo they land in the
  merge commit's body: `for sha in $(git rev-list origin/main..HEAD); do git log -1 --format=%B
  "$sha" | grep -nEi '\b(clos(e|es|ed|ing)|fix(es|ed)?|resolve[sd]?)\s+#[0-9]+'; done`, with a
  known-positive control. Re-run it before merge, not once at the start — the branch keeps growing
  commits, and the ones written to explain this defect are the ones that re-introduce it.
- Assert the **counterpart** too. AC30 covered only this PR's field; nothing covered the
  implementation PR's, which is the one that decides whether the issue ever closes.
- When writing prose *about* a keyword that has machine meaning, break it (`clo{}se`),
  HTML-escape it, or restructure so keyword and reference are never adjacent. Mentioning a
  construct and invoking it are indistinguishable to a matcher.
- Guard the edit mechanically and chain the push behind the guard. Three careful reads failed here;
  the regex did not.
- Generalise before filing: ask *which other consumer pattern-matches this prose?*
  `auto-close-scan.sh` scans body **text** and is blind to sidebar links by construction, so a
  body-text gate cannot detect a link the body does not declare.

## Session Errors

1. **Handoff claimed PR #7510 was "STILL DRAFT"; it merged 2026-08-19 (`45ea9f7e9`).** Recovery: a
   `gh pr view` at session start. **Prevention:** an inherited state claim is a claim — re-measure
   every blocker's state before acting on a handoff's scope decision.
   **Three of this handoff's factual claims were stale, not one** (see also #2, and its "an open P1
   (`/var/lib/zot` 100% full) may fail the post-merge deploy" — #7341 has been CLOSED since
   2026-08-14). Each was refuted in seconds by one `gh` call. The count is the finding: a handoff's
   *narrative* can be sound while its *state assertions* have all decayed, because prose is written
   once and the world keeps moving. Re-measure every one before use, not the ones that look
   suspicious — the third was caught only because it was checked on principle, having caused no
   visible trouble.
2. **Handoff said "update the `-lt 44` floor"; the floor on `main` is `-lt 92`.** Recovery: grepped
   the file. **Prevention:** re-derive every load-bearing number a handoff carries; ~15 seconds.
3. **My PR body's prose assigned the closing link** (this learning). **Prevention:** assert the API
   field, never the prose.
4. **My first two fixes for #3 re-armed the trap inside the sentence explaining it.** Recovery: the
   guard rejected both. **Prevention:** guard mechanically; do not trust a careful read of text
   whose subject is the thing being matched.
5. **A bare-token grep for `closes:` consumers matched English prose in shell comments** ("the
   asymmetry it closes:") and reported 5 consumers; anchored on field access, the true count is 0.
   **Prevention:** anchor on the emitter or the access form, never the bare token.
6. **`markdownlint` on an out-of-tree path crashed AND exited rc=0** — success reported having
   linted nothing. **Prevention:** an instrument's exit status is a claim; pair it with a known-bad
   input that must fail.
7. **Greps for `AC23** re-asserts` and `left **four** things` returned nothing** because the file
   has no `**` there; I nearly dismissed two *correct* agent findings as false positives.
   **Prevention:** when a grep contradicts a specific claim, search the plain substring before
   concluding the claim is wrong.
8. **A control-existence check reported `scripts/probe-verb-gate.sh` MISSING.** It exists at
   `plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh`; my regex anchored on `scripts/`
   mid-path and matched a substring. I nearly filed a phantom finding. **Prevention:** pair every
   existence sweep with a positive control (a path you know is absent) *and* anchor on a path start.
9. **"518 lint findings on both HEAD and main" was a matching COUNT** — the weakest possible
   evidence, as `qa/SKILL.md` states. The finding-**set** diff is 517/517 with zero new.
   **Prevention:** compare finding sets with `comm -23`, never totals.
10. **`ls -la F | cut … || echo ABSENT`** — a pipeline's status is its last command, so the
    absent-file branch could never fire. **Prevention:** test the file directly (`if [ -f F ]`),
    never a pipeline's status.
11. **Attributed the `markdown-lint` failure as PR-introduced** because four sibling PRs passed.
    Recovery: found the structural argument (the suite synthesizes its corpus; no diff file is an
    effective input). **Prevention:** prefer a structural independence argument over a statistical
    one — "it passed elsewhere" is weak where "this input cannot reach that code" is decisive.
12. **My `gc.auto` comment misattributed the mechanism**, claiming `git gc --auto` repacks.
    Measured: 1950 fixtures produce 1950 loose objects and `git gc --auto` creates **0** packs
    (`gc.auto`'s 6700 default is never reached). The real hazard is the detached
    `git maintenance run --auto` child. **Prevention:** a comment justifying a config line is a
    claim; a reader applying this repo's verification discipline would have deleted the line.
13. **I claimed the mutation suite was "hermetic".** It also reads `package-lock.json`,
    `pr-quality-guards.yml`, `lefthook.yml`, `required-checks.txt`, symlinks real `node_modules`,
    and executes the real SUT against the real repo. Retracted; the attribution survives on the
    narrower ground that no *diff* file is an effective input. **Prevention:** state the narrow
    claim you measured, not the broad one it suggests.
14. **The D9 number fix landed in one section and left its twins** in `AC28`, `tasks.md` and
    `spec.md` — third instance of the twin-copy class this session. **Prevention:** sweep by claim,
    repo-wide, before committing the first fix.
15. **The claim sweep by one spelling missed four more spellings** (see the addendum added to
    `2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md`). **Prevention:** enumerate
    a claim's spellings, not just its files.
16. **A stray `git stash list` was blocked by the guardrail** (`hr-never-git-stash-in-worktrees`).
    Hook fired correctly. **Prevention:** none needed — mechanical enforcement worked.
17. **Four turns ended on forward-looking commitments**; the unkept-promise stop hook fired each
    time. Hook fired correctly. **Prevention:** none needed — but note the hook is what surfaced it,
    not self-review.
18. **Environment:** `scripts/test-all.sh` refused `EXIT=4` (a sibling full-gate run was in flight,
    six peer sessions active); `bun` is installed at 1.3.14 but no mise version is pinned, so
    `test-all.sh` aborts at startup (worked around with `mise exec bun@1.3.14 --`); `lefthook` is
    absent from PATH, so **no pre-commit hook fired all session** and every gate had to be run
    explicitly; docker was reachable only via `newgrp docker`. **Prevention:** the `lefthook`
    absence is the load-bearing one — when hooks cannot fire, every gate they would have run becomes
    a manual step, and a session that does not notice ships unlinted.

19. **AC30b — I wrote an acceptance criterion against a control surface I had no write access to,
    and treated raising it on the other PR as discharge.** It failed within hours: #8249 merged
    `4dbd1affe` with `closingIssuesReferences: []` and #7535 stayed open, closed by nothing.
    Recovery: inverted AC30 so this PR takes the close, which is enforceable here because the
    implementation was already on `main`. **Prevention:** before writing a criterion, ask *can I
    write to the thing this asserts?* If not, it is a monitor — pair it with a fallback that is in
    your own power, and do not mark it satisfied by having escalated it.

20. **Two commit messages carried close-keyword adjacencies at merge time, one naming an unrelated
    issue (#8043).** Both were written while documenting this trap; a squash merge would have put
    them in the merge commit's body. Recovery: `.claude/hooks/pre-merge-auto-close-scan.sh` refused
    the merge, reworded via `filter-branch`, tree verified byte-identical. #8043 turned out already
    closed since 2026-09-13, so nothing collateral happened — luck, not design. **Prevention:** the
    commit-message sweep above; and treat "I measured that surface earlier" as expired the moment
    you write another commit. Hook fired correctly — no new rule needed.
21. **I asserted a docs-only merge would clean-skip the deploy arm; it deployed.** The
    `workflow_run` arm inherits neither path gate, and `resolve-target`/`deploy` both succeeded —
    production moved to the merge commit (`build_sha` matched, v0.276.9 → 0.276.10).
    **Prevention:** read the deploy job's conclusion for the merge SHA; do not infer it from the
    diff's shape.
22. **I predicted `battery-owed` would return `42 SKIPPABLE` after merge.** It cannot on a
    squash-merge repo: it requires `origin/main` to be an ancestor of `HEAD`, and a squashed feature
    branch never is. **Prevention:** read a gate's stated precondition before predicting its
    verdict — the script says so in its own output.
23. **Phase 3.7 nearly read another merge's deploy run as validating this one's gate change.** The
    only deploy-arm run available was on `267ff5807`; asserting the head SHA, not just the presence
    of a `deploy` job, is what prevented a false `GATE-VALIDATED`. **Prevention:** filter every run
    query by the merge SHA, and treat a run found without that filter as evidence about nothing.

## Related

- `knowledge-base/project/learnings/workflow-patterns/2026-09-17-the-collision-gate-is-point-in-time-a-cleared-ref-goes-stale-during-planning.md`
  — the same PR's other finding: why a sibling session was racing #7535 at all.
- `knowledge-base/project/learnings/2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`
  — amended with this session's six instrument failures.
- `knowledge-base/project/learnings/2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim.md`
  — amended with this session's spelling-multiplicity datum.
- `AGENTS.rules.md` `cq-assert-anchor-not-bare-token` — the grep-shaped form of this class.
- Two agent findings were **refuted** by measurement this session, and one would have introduced an
  error: a history seat rated "`#8043 F11` is a wrong attribution, use `#8052`" as P1, but PR #8052
  `closes: [8043]` and issue #8043 contains an `## F11` section, so the citation is a correct
  issue-plus-finding reference; applying the fix would have dropped the finding-level reference and
  made the plan disagree with the source file it quotes. A second seat reported a skip budget of 11;
  measured 13. Both are the modal false positive `review/SKILL.md` documents — a single agent at
  HIGH, no orthogonal corroboration, reasoning from one wrong model (`#N` must be a PR).

## Tags

category: workflow-patterns
module: github-integration
