# Learning: editing a PR body right after a push cancels the push-triggered CI

## Problem

During the G1 / git-data cutover PR series, a PR body was edited (`gh pr edit --body-file`) immediately after the branch was pushed. The edit fires `pull_request: edited` workflow runs, and those runs cancelled the in-flight push-triggered CI, so the PR showed cancelled checks and no verdict for the pushed commit. The cancellation mechanism (a shared concurrency group is the likely cause) was not measured.

## Solution

Write the PR body before the first push, or edit it only after the push-triggered CI has concluded. If the body must change while CI is running, wait for the checks to finish (use Monitor on the run, not chained sleeps), then edit, then confirm the checks that matter are green on the head SHA and re-dispatch only if the edit cancelled them.

## Key Insight

A PR body edit is a workflow trigger, not metadata. Treat `gh pr edit` after a push the way you treat a second push: it can cancel the first run's CI.

## Session Errors

1. A PR body was edited right after a push; the `edited` runs cancelled the push-triggered CI. **Prevention:** order the body write before the push, or after CI concludes.

## Tags

category: workflow-patterns
module: github-actions, pull-request-workflow
