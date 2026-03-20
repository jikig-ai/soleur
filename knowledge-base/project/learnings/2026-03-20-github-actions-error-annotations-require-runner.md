# Learning: GitHub Actions ::error:: annotations only work on the runner

## Problem
When adding error handling to deploy scripts that execute via `appleboy/ssh-action`, the initial instinct is to use `::error::Invalid version` workflow command annotations for clear CI feedback. These annotations are processed by the GitHub Actions runner's stdout parser and render as error annotations in the Actions UI.

## Solution
Use plain `echo "ERROR: ..."` instead of `::error::` inside `appleboy/ssh-action` `script:` blocks. The script executes on the remote server via SSH, not on the Actions runner. The runner's workflow command parser only intercepts stdout from `run:` blocks executed locally on the runner. Inside ssh-action, `echo "::error::..."` prints the literal string to remote stdout, which may or may not be forwarded to the runner log — and even if forwarded, is not guaranteed to be parsed as a workflow command.

## Key Insight
GitHub Actions workflow commands (`::error::`, `::warning::`, `::set-output::`, etc.) are a runner-side feature, not a shell feature. Any action that executes commands in a different context (SSH, Docker exec, remote API) bypasses the runner's stdout parser. Always use plain output in remote execution contexts.

## Tags
category: integration-issues
module: ci-cd
