---
title: "Auto-mint review: every P2 was one hazard, a tag created and never built"
date: 2026-09-28
category: integration-issues
module: inngest-bootstrap-auto-mint
tags: [ci, github-actions, adr-232, review, subagents]
issue: 4326
pr: 9079
---

# Learning: in the auto-mint review, every P2 was a tag created and never built

## Problem

#4326 adds `mint-inngest-bootstrap-tag.yml`. When a push to main changes the bootstrap image's inputs, it mints the next `vinngest-v*` tag with `GITHUB_TOKEN` and dispatches the build with an App token scoped to `actions:write`.

The first implementation passed 373/373 tests. The 8-seat review then returned about 12 P2s from five different seats, and nearly all of them were the same hazard: **a tag lands on the remote and no build ever runs.** Different seats reached that one state by different routes:

- **Credential ordering.** The Doppler install, the token check and the App mint all ran *after* the tag was created. At #8209 O10 the App key is evicted, so every carrier change would then strand a tag.
- **Tag name dropped.** `die` cleared the tag name. A verify failure, or a lost 2xx on the ref POST, therefore reported "no tag was created". A re-run then decided `noop` (`head-tagged`), and the tag was never built.
- **No timeout headroom.** The step timeouts summed to the job cap. A hang cancelled the job, and `if: failure()` never sent the Slack alert.
- **`ls-remote` exit codes discarded.** A network failure read as `tag-not-found`.
- **Substring wiring checks.** The tests checked workflow wiring with substrings, so six hollowed-step mutants (W1–W6) passed, each breaking the tag → token → dispatch chain.

## Solution

- Mint every credential after Decide and before the tag. The dispatch becomes the only step after the tag.
- Once the ref POST has been attempted, write `tag=<NEXT>` and `tag_state=unknown` whatever the outcome. Give the Slack step and the runbook a "tag MAY exist" branch.
- Add one `ls_remote` helper that fails as `ls-remote-failed` with the exit code.
- Keep the summed step timeouts below the job cap, and alert on `failure() || cancelled()`.
- Pin each step's `if`/`run`/`env` in the tests with exact equality, and check that every `steps.X.outputs.Y` reference resolves.
- Add fixture S1: a commit between the base tag and HEAD. Without it, "compare against the newest merged tag" was indistinguishable from "compare against the previous commit", which is the property the design exists for.

The suite went from 373 to 541 assertions.

## Key Insight

- **When several seats report different P2s, name the shared end state before fixing any of them.** Here it was "a tag with no build". The fixes then share one invariant: nothing irreversible happens until every credential and precondition is in hand. Fixing them one by one would have left the next route to the same state open.
- **A workflow test that checks substrings pins shape, never wiring.** `"would-mint" in if` passes when the operator is inverted. Use exact equality on the `if`, `run` and `env` of every step that carries the property.

## Session Errors

1. **I claimed in a PR body that no Terraform apply would fire (#9049) without grepping the `paths:` filter.** The AC6 test lives under `apps/web-platform/infra/**`, so merging fired `apply-web-platform-infra.yml`. It was a no-op. I appended a correction to the PR. **Prevention:** before writing any "no X fires" claim, `grep -n 'paths:' -A10` every workflow triggered by `push: main` and match it against the diff's file list.
2. **Several turns ended "waiting on the subagent" while the subagent had stalled.** Its test run had exited and nothing was running; the operator had to ask "why did you stop?". **Prevention:** when delegating a long task, arm a heartbeat monitor that reports commit/dirty/process counts, and check the worktree directly rather than trusting a pending notification.
3. **A queued local full gate (position 5 in the FIFO lock queue) held the pipeline despite the operator's "rely on CI" directive.** **Prevention:** put the operator's verification policy verbatim into every delegation brief, and forbid `test-all.sh` there when the policy is CI-plus-targeted.
4. **A PR that edited `.github/workflows/` (comment-only, #9049) could not be admin-merged by the agent (`untrusted-ci`) and livelocked BEHIND.** **Prevention:** split comment-only workflow edits into their own follow-up PR from the start, as #9076 was.
5. **`battery-tag-authorship` flagged `git tag --merged … --list` as tag-authoring and turned CI red.** Its set of read-only forms did not include `--merged`. **Prevention:** after adding a new `git tag` spelling to any battery-reachable file, run `bash scripts/battery-tag-authorship.test.sh` locally. That set now also covers `--merged`, `--no-merged` and `--no-contains`.
6. **I read a structural-review equivalence from a vacuous check.** A `json.dumps(sort_keys=True)` YAML comparison crashed on the `on:` boolean key; both sides errored, so they "compared equal". **Prevention:** give every comparison instrument a length or non-empty guard, and use `repr` when keys have mixed types.
7. **The fix subagent's first `fixture-relative-assert` read was a false rc 0** (it reported this itself). **Prevention:** capture `rc=$?` on the line immediately after the command, never inside an `echo` that expands a substitution.
8. **A deploy-arm canary flake (`canary_sandbox_failed`, rc 137 in 105 ms) blocked #9049's deploy.** This is the known #8016 class, and production stayed on the previous build until a later deploy carried the merge. **Prevention:** none locally. Record each occurrence on #8016, and treat a production re-run as a production write.

## Tags
category: integration-issues
module: inngest-bootstrap-auto-mint
