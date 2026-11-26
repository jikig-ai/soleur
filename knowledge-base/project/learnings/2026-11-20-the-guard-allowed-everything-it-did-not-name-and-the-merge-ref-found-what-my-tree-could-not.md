---
title: The guard allowed everything it did not name, and the merge ref found what my tree could not
date: 2026-11-20
category: integration-issues
module: apps/web-platform/infra (cf-account migration)
tags: [cloudflare, terraform, migration, deny-by-default, parallel-agents, semantic-conflict, review]
issue: 12931
pr: 12932
---

# Learning: the guard allowed everything it did not name, and the merge ref found what my tree could not

## Problem

PR1 of the #12931 Terraform move to the Soleur Cloudflare account added a completion predicate that holds
every web-platform infra apply while the migration is in progress. Review found it denied a **hand list of
three workflow files** and allowed every other caller. `key-rotate.yml` and `inngest-key-rotate.yml` load
the same credentials and plan the root through `scripts/key-rotate.sh` (`KR_INFRA_DIR`, then `terraform`),
so they passed the predicate. The scope suite missed them because it only matches Terraform written inline
in a workflow's `run:` text. Its structural map listed nine more bypass shapes (`if terraform apply`,
`exec terraform`, composite actions, renamed or reusable workflows).

Two other failures came from the fix process itself:

1. The review fixes went to three agents in isolated worktrees with **disjoint file ownership**. Each
   reported green. On the merged tree, 23 job-suite rows went red: the job suite's argv-exact `aws` fake
   expected `--endpoint-url` before `--only-show-errors`, and the state-migrate owner had moved it last. A
   layered-guard row also flipped. The trio census then refused a key one agent's new script named.
2. After the panel, a sibling PR (#12876) merged to main. It pinned the moved zone's config-ruleset id and
   asserted that `seo-config-rules.tf` imports it. This PR deletes that import. `git merge-tree` showed no
   conflict. Only CI on the merge ref ran the new test (B10), and two kb-consumers rows changed too.

## Solution

- **D1 (CTO ruling):** the predicate now gates every caller of `infra-credentials` unless it is named in
  `CFAM_EXEMPT_WORKFLOWS`. The job's in-flight check reads that one list, so it has no copy of its own. The
  scope suite follows `bash <repo-script>` one level and goes red when an exempt workflow's script plans
  the root.
- **Merged-tree contract breaks:** I aligned the fake with the real argv and asserted the R2 env prefix.
  The H3 row became a layered check: the gate library now ignores the override by itself, so a mutant of
  the job's `unset` must leave a clean run that shows the gate's ignore line. I removed the Access key from
  the PR1 inventory (it moves in PR2).
- **Semantic conflict:** B10 now pins the legacy ruleset id until PR2's re-pin. If an import ever returns,
  it must carry the pinned id, and the runbook has to own the re-pin step. The runbook gained that step
  after `redirects-dns` and an Expected-reds row: the preflight fails closed with `[ruleset-id]` between the
  flip and the re-pin.

## Key insight

A guard that names what it blocks is a guard that allows what it forgot to name. When the property is
"nothing applies against X until Y", the list must name the exceptions, and the default must be deny.
The static backstop cannot be complete either, so it must not be what decides.

For a parallel fix round, a green report from each owner says nothing about the contracts *between* owners.
Run the union of the suites on the merged tree before pushing. For a PR that deletes content, a clean
`merge-tree` says nothing about a sibling PR that asserts the deleted line. Merge main and run the suites
that read what you removed.

## Session Errors

1. **`dig` was absent; DNS was checked over DNS-over-HTTPS (forwarded).** Recovery: DoH. **Prevention:** one-off.
2. **A hook blocked a heredoc containing a Doppler write example (forwarded).** Recovery: rewrote it as silent
   stdin-only writes. **Prevention:** keep secret-write examples out of command text (hook-enforced).
3. **The first CTO ruling on the ssh/registry records (import, then replace) did not fit three A records per
   name (forwarded).** Recovery: re-ruled to a pinned pre-delete. **Prevention:** one-off. Count live records
   before asking for a ruling.
4. **The guard-contract lint failed once on Guard 4 (forwarded).** Recovery: fixed. **Prevention:** one-off.
5. **Review agents ended without a report (Terraform mechanics, structural enumeration). A hook blocked a
   seat's sandbox `rm -rf`.** Recovery: resumed each with SendMessage to write its report; removed the
   sandbox with `soleur-sandbox.sh rm`. **Prevention:** already in the brief (write the report incrementally,
   return it, never park). Covered.
6. **The scan gate refused when shellcheck was killed at load about 150.** Recovery: re-ran after the merge.
   **Prevention:** the gate refuses rather than passing, which is correct. Re-run it; never treat it as clean.
7. **A CONFLICTING PR suppressed every `pull_request` workflow.** Recovery: merged origin/main.
   **Prevention:** covered by the review checklist (`mergeable` before reading checks).
8. **A backgrounded poll loop was blocked by a hook.** Recovery: used Monitor. **Prevention:** hook-enforced.
9. **`gh issue create` was refused three times:** no milestone; a `$VAR` in `--body-file`; a `Mandated-By:`
   that was not a rule id. Recovery: a literal absolute body path, `--milestone`, and
   `Mandated-By: wg-when-deferring-a-capability-create-a`. **Prevention:** hook-enforced, and the messages
   name the fix.
10. **A Python edit wrote `\'` inside a single-quoted bash `printf`.** Recovery: `bash -n` caught it before
    any run. **Prevention:** run `bash -n` after every scripted shell edit (done).
11. **Merging the parallel fix branches turned 23 job rows red (argv order) and flipped a layered row.**
    Recovery: aligned the fake; made H3 layered. **Prevention:** covered by
    `review/references/risk-tier-and-fix-rounds.md` ("run the combined-tree gate").
12. **The trio census refused a key one agent's new script named.** Recovery: dropped the key from the PR1
    inventory. **Prevention:** same as 11; brief fix agents on the repo-global censuses by name.
13. **The shell-trace lint failed on `--noproxy "*"` inside a single-quoted inner script.** Recovery: a quoted
    heredoc spelling `'*'`. **Prevention:** same as 11. The fix brief must list the changed-file lints CI runs
    (`lint-shell-trace-credential-refusal.py --changed`).
14. **A semantic conflict with #12876 (B10) and two new kb-consumers rows showed up only on the merge ref.**
    Recovery: merged main, reconciled B10 and the runbook, re-baselined. **Prevention:** new bullet in
    `review/references/risk-tier-and-fix-rounds.md`: merge main and run the suites that read anything the
    PR deletes or rewrites.
15. **An exploratory command included `git checkout origin/main -- .`, which overwrites the working tree.**
    The stash hook blocked the whole line before it ran. Recovery: re-ran read-only with
    `git show`/`git grep origin/main`. **Prevention:** never put a tree-overwriting checkout in an exploratory
    command. Read another ref with `git show <ref>:<path>` and `git grep <ref>`.
16. **`sed -n "$((n-12)),…p"` ran with an empty `n` twice.** Recovery: grep by a unique string first.
    **Prevention:** one-off. Guard `[[ -n $n ]]` before arithmetic on a grep result.
17. **On resume the PR was `DIRTY`: main moved after the review pin and four files conflicted** (the pipe-guard
    test, the expense ledger and both shard TSVs). Recovery: merged main in ship and re-reviewed the merge commit
    before arming. **Prevention:** covered. Ship merges main, and a commit after the review pin needs a fresh
    Review-Evidence comment. Regenerate the shard TSVs rather than hand-merging them.

## Tags

category: integration-issues
module: apps/web-platform/infra
