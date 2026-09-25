---
title: "A second apply workflow could perform the credential rotation without its gate, and my guard pinned the hash, not the re-fire"
date: 2026-09-24
category: security-issues
module: apps/web-platform/infra
tags: [terraform, doppler, rotation, destroy-guard, target, workflow, guard-vacuity, review]
issue: 8705
pr: 8733
---

# Learning: a rotation has more than one workflow that can perform it

## Problem

#8705 rotated `doppler_service_token.web_probes` (a read token on the whole `soleur/prd` config,
very likely held by retained web-1 snapshot 411798619) by rename + `create_before_destroy`, merged
with `[ack-destroy]`. The plan routed the rotation through `apply-web-platform-infra.yml`: its main
plan targets the token behind the destroy guard, then its post-bridge SSH stage re-fires the four
web-1 installers whose `triggers_replace` hash the key.

The plan also made a comment-only edit to `server.tf` "required". The structural-enumeration review
seat found that `server.tf` is in `apply-deploy-pipeline-fix.yml`'s push `paths:`, and that
workflow's four `-target`s reference `hcloud_server.web["web-1"]` — whose `user_data` templatefile
reads the key. `-target` pulls in dependencies transitively, so on this merge that workflow's plan
would contain the token's replace. Its guard counted only `host_creates` (its own routine
`terraform_data` replaces count as deletes, so it never read `resource_deletes`). Both workflows share
one concurrency group, and which runs first is not deterministic. Had it won, it would have performed
the rotation with no `[ack-destroy]` gate and without re-firing the installers.

Separately, the Guard 1 predicate ("every consumer of the key re-fires") checked that the hash TEXT
sat in `triggers_replace`. Adding `lifecycle { ignore_changes = [triggers_replace] }` to an installer
keeps the text and suppresses the re-fire — green. So did an override file, a `*.tf.json`, the key
laundered through `input`, and the `hcloud_server.web` exception moved into a `local-exec`.

## Solution

- CTO ruling (c): revert the `server.tf` comment edit (so this merge does not trigger the second
  workflow) AND add a fail-closed gate to `apply-deploy-pipeline-fix.yml`: a new
  `non_terraform_data_deletes` counter in the shared destroy-guard filter (any managed resource that
  is not `terraform_data` with a `delete` or `forget` action) and a HALT with no bypass, plus the
  same HALT on the filter's existing `reboot_updates`. Tests T63a-f, T56e-j.
- Guard 1 now refuses `ignore_changes` on the trigger, key references outside the trigger and its
  provisioners, an exception outside the `user_data` templatefile, override files and `*.tf.json`
  naming the token. H2 proves each per-block row depends on the per-block check (rc=0 in the stubbed
  run, green inner control), and every verdict-owning helper has a negative control.

## Key Insight

A plan that changes a Terraform resource must enumerate EVERY workflow that can apply it, not only
the one it intends to use. The set is: every push-triggered workflow whose `paths:` include a file
the diff edits, times whether its `-target` graph reaches the resource (dependencies are pulled in
transitively), times whether its guard counts the change class. A path filter is not a security
boundary — the gate belongs in the workflow.

And a guard named for a behaviour ("re-fires on rotation") must reject every way the behaviour can
be suppressed while the pinned text stays present; a text pin is only the first predicate.

## Session Errors

1. **`gh issue create --body-file` blocked when the body file was written in the same command** (planning phase). Recovery: write the file in a separate step. **Prevention:** already documented in work/SKILL.md; one-off.
2. **terraform-architect subagent returned an empty report twice** (planning). Recovery: verified ForceNew and CBD semantics directly. **Prevention:** resume a silent agent with a request for its final report (as done for data-integrity in review) before re-deriving.
3. **Preflight ratchet red (24 vs 25) until the first work task.** Recovery: task 1.1 bumped it. **Prevention:** expected by design; the plan recorded it.
4. **`rm -rf /var/tmp/prs-8626-*` blocked by the protected-checkout hook.** Recovery: handed to the operator. **Prevention:** one-off; the hook is correct.
5. **The first commit's lefthook battery queued 2.7 h and then failed `lint-shell-trace-credential-refusal` on the new verifier** (no xtrace refusal, curl not confined). Recovery: added both, reran the lint. **Prevention:** a new script that reads a credential runs `python3 scripts/lint-shell-trace-credential-refusal.py` before its first commit (routed to work/SKILL.md).
6. **Verifier written before its guard rows** (TDD order inverted for Guard 3). Recovery: proved the rows RED by emptying the verifier. **Prevention:** one-off; the TDD gate already says test first.
7. **First RED run mute-aborted: `argv="$(cat missing)"` under `set -e`; a leak row failed open on a missing argv file.** Recovery: `|| true` in captures; require the file to exist. **Prevention:** known class (work/SKILL.md capture rules).
8. **`run-registered-suites.sh --help` ran the full 137-suite battery** (no help flag; unknown args fell through). Recovery: killed via SIGPIPE; checked for orphans. **Prevention:** fixed inline — the runner now exits 64 on any argument but `--list`.
9. **The Write tool refused after Bash-side edits left its read state stale.** Recovery: re-read, then write. **Prevention:** one-off.
10. **Two merge conflicts on shared ratchets** (preflight baseline, `PROMOTED_FILES`). Recovery: kept both entries, bumped the baseline. **Prevention:** known class; re-check at ship.
11. **P1: the plan's required `server.tf` edit would trigger `apply-deploy-pipeline-fix.yml`, which reaches the token transitively and had no delete gate.** Recovery: CTO ruling (c) above. **Prevention:** routed to plan-sharp-edges.md (enumerate every workflow that can apply the changed resource).
12. **P1: Guard 1 pinned hash presence, not re-fire; `ignore_changes` escaped it.** Recovery: class rules + rows R11-R16. **Prevention:** name the ways the behaviour can be suppressed with the text intact, and add a row per way.
13. **A new structural row mute-aborted the suite on a no-match grep under `set -e`** (found only by attributing a mutation's RED to a row). Recovery: `{ grep … || true; }`. **Prevention:** attribute every mutation to the named row, never to the exit code alone.
14. **A row label with `[...]` became a glob class in the copy-dir path (hash=0).** Recovery: `glob.escape(root)`. **Prevention:** one-off; escape paths passed to glob.
15. **Harness false leak and false miss: the L3 row's own `WPTR_DOPPLER_OUT` carried the sentinel into curl's env; a lookup by `id: plan` matched several jobs.** Recovery: exclude the harness's carriers; look up by step name. **Prevention:** one-off.
16. **`sed | head | grep -q` false-failed under `pipefail`.** Recovery: capture, then herestring. **Prevention:** known class.
17. **Data-integrity agent ended without a report.** Recovery: resumed it. **Prevention:** one-off.
18. **Stale claims ("three units", "adds no new exposure") survived inside a comment block the diff edited.** Recovery: rewrote the header. **Prevention:** when editing a comment block, re-verify every claim in the block, not only the lines changed.

## Tags

category: security-issues
module: apps/web-platform/infra

## Addendum: one more session error

19. **I ran `bash` on a `.ts` test file.** Bash executed its first line `import …` as ImageMagick's `import` screenshot command, which blocked for ~2 h waiting for a click inside a background task. Recovery: killed it and ran `bun test`. **Prevention:** run `plugins/soleur/test/*.ts` with `bun test`, never `bash`; `.ts` is not a shell script.

## Addendum: ship and post-merge errors (2026-09-25)

The rotation completed. Merge `96a87c89` came from PR #8733. Apply run 36063185028 printed `ROTATED`. The web-2 replace was run 36117021829. #8705 is closed with the evidence.

20. **Preflight Checks 6 and 10 ran against the draft PR's placeholder body.** With no plan link, `PLAN` was empty, and `awk … "$PLAN"` read stdin and hung until the tool timed out. Recovery: wrote the PR body first, then re-ran both checks. **Prevention:** write the PR body (with its plan link) before preflight. Guard every `awk … "$FILE"` with `[[ -f "$FILE" ]]`, since an empty path makes awk read stdin.
21. **The first PR body carried "Close #8705" in a numbered list.** The auto-close scanner caught it before the edit, and `closingIssuesReferences` stayed `[]`. **Prevention:** already covered by ship Phase 6; one-off.
22. **The plan's expected merge-apply counts were wrong: `1 added, 0 changed, 1 destroyed` against an actual `2 added, 1 changed, 1 destroyed`.** Every main apply re-applies `cloudflare_bot_management.soleur_ai` and a GitHub environment deployment policy (#8754). **Prevention:** before writing an AC that pins apply counts, read the last main apply's `Plan:` line and add the recurring drift to the expected numbers.
23. **The plan's web-2 log check (`FATAL` or `401` rows) would have passed a host whose token was revoked.** A revoked Doppler service token logs `Doppler Error: Invalid Auth token` and `Unable to download secrets`, with neither word present. **Prevention:** a negative log check for Doppler auth matches `Invalid Auth|Unable to download|401|FATAL`, and it runs once against a host that is known to be failing (here, web-2 before the replace) as its positive control.
24. **The first admin merge failed with `Head branch was modified`.** The pre-merge hook merged `origin/main` into the branch and pushed, so the head no longer matched `--match-head-commit`. Recovery: confirmed that the delta was main's own commit with no infra files, then merged the new head. **Prevention:** expect the pre-merge sync. Re-read `headRefOid` after the hook runs, and diff the pinned head against the new one before merging.
25. **One heartbeat read returned curl rc=22** (a transient Better Stack HTTP error). An immediate retry returned 200. **Prevention:** a timed read inside a Monitor retries a small bounded number of times and prints the HTTP code, never a bare rc.
