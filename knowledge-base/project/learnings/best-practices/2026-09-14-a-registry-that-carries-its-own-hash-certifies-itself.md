---
title: A registry that carries its own integrity hash certifies itself
date: 2026-09-14
category: best-practices
module: rule-corpus governance (scripts/lint-migrated-rule-ids.sh, scripts/lint-rule-bodies.py)
problem_type: guard assembly narrower than its property
issues: ["#8030"]
prs: ["#8175"]
tags: [guard-design, integrity-hash, registry, merge-base, mutation-testing, rule-corpus]
---

# Learning: a registry that carries its own integrity hash certifies itself

## Problem

PR #8175 migrated two `hr-*` rules out of `AGENTS.rules.md`, the only file
`scripts/lint-rule-bodies.py` hashes against a merge-base with WORM acks (ADR-092). To keep
the moved bodies protected, the PR added a body-sha256 column to
`scripts/migrated-rule-ids.txt` and a guard (`scripts/lint-migrated-rule-ids.sh`) that
recomputes each body at its new home and compares it to the row.

The guard was green, its 32-case suite was green, and a 17-row mutation battery reported
every row killed. A nine-seat review then measured all of these as green:

- **Weaken a body and re-hash its row in the same commit.** The guard compares two values
  that the same diff controls. The registry header even said "that update is the ack".
- **Drop a row and add one for an id that never migrated.** The `MIN_ROWS=7` floor is a
  count, so a substitution keeps it.
- **Add a second banner or a second `[id:]` copy** in the same section, or in another file.
  Only the first occurrence was hashed.
- **Put a banner outside `plugins/soleur/`.** The reverse scan never looked there.
- **Use an NBSP inside a body.** Python's `str.split()` collapses it and `tr` in the C locale
  does not, so the two normalisers disagree.

Seat-level test survivors on top of those:

- `expect_green`/`expect_red` could be rewritten to always pass with every counter still
  balanced;
- an intermediate-directory symlink escape was untested;
- `--print-hash` was untested;
- `LINT_MIGRATED_RULE_IDS_ROOT` inherited from the parent retargeted the live case.

## Solution

1. **Anchor the hash outside the commit that can change it.** `rule-body-lint --check`
   already runs on every PR against `git merge-base origin/main HEAD` and owns the ack file,
   so it now also reads the registry at the base and at HEAD
   (`check_migrated_rows` in `scripts/lint-rule-bodies.py`):
   - a changed hash on an existing row needs a NEW `<id>|<hash>` ack;
   - a new row must equal `sha256(normalize(base AGENTS.rules.md body minus "- "))`, i.e.
     a verbatim move, or be acked as a rewrite;
   - an id with no base body is refused;
   - a removed row needs a NEW `<id>|MIGRATED-ROW-DELETED` ack. The token is distinct because
     every migrated id already holds a historical `DELETED` ack, and acks are sets.

   Before relying on this, the lead measured that the registry hash equals the normalised
   base body hash for all 7 rows.
2. **Replace the count floor with set identity against an independent registry.** The
   registry's id set must equal the `NOT a retirement of the RULE` rows of
   `scripts/retired-rule-ids.txt`. Deleting a row or swapping in a fabricated id now needs a
   second, reviewed file to agree.
3. **Uniqueness per axis the property quantifies over:** one row per id, one banner per id
   in the whole scanned tree, the `[id:]` tag once in its home, and no non-ASCII whitespace.
4. **Scan the tree, not the window.** The scan reads every `*.md` except `.git`,
   `node_modules`, `.worktrees` and `knowledge-base/project/`. A banner outside
   `plugins/soleur/` is a finding, which is what makes the row-path rule and the scan agree.
5. **Drive verdict helpers in both directions.** The self-test calls `expect_green` and
   `expect_red` once each against a known-green and a known-red root, and requires +2 pass,
   +2 fail and +4 cases. It reports via `printf` + `exit`.

The sandbox battery after the fixes ran a green 45/45 control. 12/12 mutations were caught
by their named case, after tightening one needle (see Session Errors 13). The one path that
is not covered is written into the guard header: text adjacent to a callout but outside its
blockquote.

## Key Insight

**An integrity value stored beside the thing it protects, in a file the same commit can
edit, proves consistency and never integrity.** Ask of every hash, checksum, manifest row
or count floor: *what, other than this diff, must also move for a weakening to pass?* If the
answer is nothing, the check is a tautology against exactly the author it exists to stop.
The anchor has to live outside the commit: a merge-base diff, a second independently
reviewed registry, or a WORM ack.

`rule-body-lint` already embodied this for `AGENTS.rules.md`. The new guard reimplemented
only its present-tense half.

Two corollaries:

- **A count floor is not an identity check.** `rows >= N` survives any substitution that
  keeps N. Replace it with equality against a set enumerated by something else.
- **"Verified inert today" is not "consistent with the decision".** The plan recorded
  `cron-rule-prune` as an inert residual because its dry-run returned no candidates. Its PR
  body still called zero-event rules a "retirement proposal", which is the very framing
  #8030 retracted. Inertness is a fact about current data; the wording is a claim that fires
  the day the data changes.

## Session Errors

1. **The plan+deepen subagent hit the account's weekly Opus limit (HTTP 429), and a
   plan-review seat died unrecoverably.** Recovery: resumed the agent via SendMessage; the
   lead ran the dead seat's anchor sweep itself.
   **Prevention:** on a 429, check the on-disk artifact against the skill's completion
   predicate before re-invoking, and spawn later seats with a non-Opus `model` override.
2. **The planning agent reported the A11 line as 574 B; it measures 596 B.** The wrong budget
   (42618 / −725) propagated into 5 plan sites, tasks.md and session-state.md before being
   corrected to 42640 / −703. Recovery: re-measured, then swept every copy.
   **Prevention:** measure a byte count with `awk '{print length}'` on the committed line
   before writing it into more than one artifact.
3. **A python fold-in aborted on its exactly-once assertion (step-10 anchor text mismatch).**
   Recovery: re-matched the exact text.
   **Prevention:** keep the `count == 1` assertion pattern; it failed before writing, as
   designed.
4. **Guard case 15b's fixture doubled spaces inside the `[id:` token.** That broke the body
   locator, not the normaliser. Recovery: fixed the fixture, not the guard.
   **Prevention:** a whitespace-normalisation fixture must perturb prose only, never a
   structural token the locator keys on.
5. **The A1 anchor match failed on 5-space indentation.** Recovery: read the indent from the
   file.
   **Prevention:** derive indentation from the target line, never assume it.
6. **markdownlint MD038 failed on a nested code span in the compound A10 text.** Recovery:
   rewrote it without the outer span.
   **Prevention:** run `bash scripts/markdown-lint.sh <file>` after any edit that nests
   backticks.
7. **`components.test.ts` rejected backtick `scripts/` spans in plan and compound SKILL.md,
   and the first commit was rejected.** Recovery: converted them to markdown links.
   **Prevention:** in skill bodies, reference `scripts/`, `references/` and `assets/` paths
   as relative markdown links.
8. **`pytest` is not installed.** Recovery: used `python3 -m unittest`, as test-all.sh does.
   **Prevention:** read the `run_suite` line in test-all.sh for a suite's runner.
9. **Mutation G11 was killed by the positive control instead of the escape case.** That
   result is not attributable to the case. Recovery: added G11b, which isolates the case.
   **Prevention:** assert the named case failed, not just rc != 0.
10. **The guard reached review with its assembly narrower than its property** (the Problem
    section above). Recovery: merge-base anchor in `rule-body-lint`, set identity,
    uniqueness and a repo-wide scan.
    **Prevention:** for any integrity column, ask "what besides this diff must move?" before
    writing the guard. The new ship Sharp Edge below makes that question mechanical.
11. **The author's 17-row battery missed 5 test-design survivors** (verdict helpers,
    intermediate symlink, `--print-hash`, env inheritance, NBSP). Recovery: added the cases
    and a verdict-helper self-test.
    **Prevention:** enumerate the battery's axes — dispatch, population, env, oracle
    agreement — not its row count. This is already in review/SKILL.md; the gap was that it
    was not applied at /work.
12. **The pre-panel `git merge-tree` was clean, then #8149 merged during review** and
    conflicted on `MIN_FIRING_SUITES`. The naive resolution was 39; correct is 40, since both
    PRs added a firing suite. Recovery: resolved to 40 and ran the floor suite.
    **Prevention:** re-run the merge-tree probe immediately before applying review fixes. Add
    ratchet deltas arithmetically; never pick a side.
13. **Review mutation M2 survived: case 17b's needle `occurs 2 times` also matched the
    tag-count finding.** Recovery: pinned the banner-specific message.
    **Prevention:** a RED needle must carry the check's unique message prefix.
14. **`rule-prune.sh --propose-retirement` still framed zero-event rules as a retirement
    proposal.** The plan had classified the cron as a verified-inert residual. Recovery:
    reworded the PR body and pinned it with tp5b.
    **Prevention:** when a PR retracts a claim, sweep every producer of text that states it,
    whether or not that producer currently fires.

## Tags

category: best-practices
module: rule-corpus governance
