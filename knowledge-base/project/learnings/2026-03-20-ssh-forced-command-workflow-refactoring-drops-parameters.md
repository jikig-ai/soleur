# Learning: Workflow refactoring silently drops SSH host fingerprint verification

## Problem

While implementing SSH forced commands (issue #747), both release workflows (`web-platform-release.yml`, `telegram-bridge-release.yml`) were simplified from multi-line inline SSH scripts to single-line `deploy <component> <image> <tag>` commands. The refactoring accidentally dropped the `ssh-known-hosts` parameter from the `webfactory/ssh-agent` setup step in both workflows. This parameter provides SSH host fingerprint verification — without it, the deploy step is vulnerable to man-in-the-middle attacks on the SSH connection between GitHub Actions runners and the production server.

The drop was not caught during implementation or self-review. It was caught by a security-sentinel review agent that diffed the before/after workflow files.

## Solution

Restored the `ssh-known-hosts` parameter to both workflow files' SSH agent setup steps. The fingerprint value was recovered from the pre-refactoring version of the files (it was still in git history / the base branch).

## Key Insight

When refactoring a YAML block to simplify its primary concern (e.g., replacing a complex SSH command with a shorter one), parameters that serve a *different* concern within the same block are easily dropped. The SSH agent step had two responsibilities: (1) load the private key, and (2) pin the host fingerprint. The refactoring targeted responsibility (1) but inadvertently destroyed responsibility (2) because the developer's attention was scoped to the command structure, not the full step configuration.

This is a general pattern: **simplification refactors are high-risk for silent parameter loss when a single YAML/config block serves multiple security concerns.** The mitigation is to diff every modified block field-by-field against the original, not just verify the new logic works. Review agents or `git diff` line-by-line review catch this; eyeballing the new version in isolation does not.

A secondary finding: the `echo` builtin interprets `-n` as a flag (suppress newline) rather than a string argument, which causes incorrect field counts when validating SSH commands. Use `printf '%s\n'` instead of `echo` in shell scripts that parse untrusted input.

## Session Errors

- Dropped `ssh-known-hosts` fingerprint parameter from both release workflows during simplification refactor (caught by review agent, not by self-review)
- Test mock for `curl` returned "OK" instead of "200" for HTTP status code, causing 1/15 test failure on first run (curl `-w '%{http_code}'` returns the numeric code, not a status string)

## Tags

category: security-issues
module: ci-deploy
