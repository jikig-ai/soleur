---
module: System
date: 2026-04-05
problem_type: integration_issue
component: tooling
symptoms:
  - "Shell script mock using ${!@} indirect expansion failed silently"
  - "Terraform fmt check failed because Bash tool does not persist cd"
  - "replace_all on checkbox patterns over-marked unfinished tasks"
root_cause: incomplete_setup
resolution_type: tooling_addition
severity: medium
tags: [shell-testing, mock-architecture, terraform, disk-monitoring]
synced_to: []
---

# Learning: Shell Mock Testing Patterns and Disk Monitoring Provisioning

## Problem

When implementing disk-monitor.sh (#1409) with a test suite following the ci-deploy.test.sh mock architecture, the initial curl mock used `${!@}` indirect expansion to iterate positional parameter indices and capture the `-d` payload argument. This pattern silently produced no output — the mock appeared to run but never wrote to the capture file.

## Solution

Replace complex positional-parameter parsing with a simple `$*` dump approach. Instead of trying to extract individual arguments from curl calls, the mock writes ALL arguments as a single line to a capture file:

```bash
# Before (broken): tried to parse individual args
for i in "${!@}"; do
  if [[ "${!i}" == "-d" ]]; then ...

# After (working): dump all args, grep for expected content
echo "$*" >> "$mock_dir/curl_args"
```

The caller then uses `grep -qF "EXPECTED_TEXT" "$mock_dir/curl_args"` to verify the expected content was passed to curl. This is simpler, more robust, and avoids bash version-specific behavior.

## Key Insight

When mocking CLI tools in bash tests, capture the full invocation (`$*` or `$@` to a file) rather than trying to parse individual arguments. The test assertion can then grep for expected substrings. This avoids shell quoting and expansion edge cases while being easier to debug (the full invocation is visible in failure output).

## Session Errors

**Shell mock `${!@}` pattern failed silently** — Recovery: rewrote test architecture to use `$*` dump pattern. Prevention: always use `echo "$*" >> capture_file` for mock call recording; avoid indirect expansion for argument parsing in mock scripts.

**`cd` not persisted in Bash tool** — Recovery: used `terraform -chdir=` flag. Prevention: always use `-chdir=` or absolute paths with Terraform CLI; the Bash tool resets CWD between calls.

**`replace_all` on checkbox patterns over-marked tasks** — Recovery: manually reverted specific lines. Prevention: never use `replace_all` on `- [ ]` patterns when only some checkboxes should be checked; edit specific lines instead.

## Related

- `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` — established the mock trace pattern this test suite builds on
- `knowledge-base/project/learnings/integration-issues/2026-04-02-docker-image-accumulation-disk-full-deploy-failure.md` — the incident that motivated this monitoring feature

## Tags

category: integration-issues
module: System
