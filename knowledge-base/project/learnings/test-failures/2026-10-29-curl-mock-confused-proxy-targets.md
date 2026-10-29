---
module: System
date: "2026-10-29"
problem_type: test_failure
component: testing_framework
symptoms:
  - "The curl mock counted a proxy URL as the request target"
  - "URL assertions missed --url= and non-HTTPS target operands"
  - "A passing URL log did not prove the expected transfer occurred"
root_cause: logic_error
resolution_type: test_fix
severity: medium
related_components: [cf-token-scope]
tags: [curl, test-mock, url-observer, proxy-arguments, mutation-testing]
synced_to: [work]
---

# Learning: Curl mocks must distinguish transfer targets from proxy operands

## Problem

A Cloudflare token-scope test used a stub curl that treated the last URL-looking
argument as the request destination. That conflated transfer targets with
configuration operands: `--proxy <url>`, `--preproxy <url>`, and `-x <url>`
configure a proxy but do not themselves issue a transfer. The observer also
missed `--url=<target>` and non-HTTPS targets, while line-count assertions could
hide multiple URLs on one dry-run recipe.

The resulting test could appear to prove an exact request even when the route
appeared only as a proxy value and curl had no transfer URL.

## Environment

- Module: System
- Affected component: shell test harness for `cf-token-scope`
- Date: 2026-10-29

## What Didn't Work

**Recording only the final argument:** A canonical URL left last could hide an
extra URL earlier in the argument vector.

- **Why it failed:** The mock observed the last argument rather than enumerating
  all transfer targets.

**Logging every argument that looked like a URL:** Proxy settings were then
  mistaken for request destinations.

- **Why it failed:** A URL-shaped option value is not necessarily a curl
  transfer target.

**Counting matching recipe lines:** An extra URL on the same line did not change
  the line count.

- **Why it failed:** The assertion measured lines, not the command's complete
  target set.

## Session Errors

**Cloudflare API search returned HTTP 404.**

- **Recovery:** Fetched the official Cloudflare API reference directly and
  verified the documented List Notification policies route.
- **Prevention:** When a search endpoint fails, verify the vendor reference
  directly before making an API-contract claim.

**A nonexistent `knowledge-base/project/project-nope.md` path was read twice.**

- **Recovery:** Confirmed the file was absent; no files changed.
- **Prevention:** Verify a target path with a repository-scoped glob before
  reading it.

**A test patch had out-of-order hunks, and a later patch context had become stale.**

- **Recovery:** Re-read the worktree and reapplied the patch in file order.
- **Prevention:** Re-read the current target before each retry and apply hunks in
  source order.

**Two `test-all.sh --print-selection` attempts timed out at 30 and 120 seconds.**

- **Recovery:** Recorded that neither run produced a selection or test verdict;
  CI remains the authoritative required gate.
- **Prevention:** Check runner capacity before retrying a full-gate operation and
  never interpret a timeout as a test result.

**Relative-path reads from a worktree returned stale content from another checkout.**

- **Recovery:** Re-read all affected files by absolute worktree path before
  editing.
- **Prevention:** Use worktree-absolute paths for MCP/tool reads and writes.

**Session-start cleanup warned that the separate root checkout could not fast-forward `main`.**

- **Recovery:** Inspected the cleanup script and root branch state; the target
  feature worktree was unaffected.
- **Prevention:** Distinguish a cleanup warning about another checkout from the
  active feature worktree, and inspect the named checkout before changing it.

**Default-severity ShellCheck returned nonzero for informational `SC2016` notices.**

- **Recovery:** Compared against the baseline (six notices versus four after the
  fix) and ran the warning-severity check successfully.
- **Prevention:** Use the repository's explicit ShellCheck severity for the
  gate; do not classify informational output as a new warning-level defect.

**The first URL-parser run failed D-conf because parsing shifted argv before it was logged.**

- **Recovery:** Captured the original argv before parsing and reran the focused
  suite successfully.
- **Prevention:** Preserve the original argument vector before a parser consumes
  positional parameters.

**Scratch-mutation setup omitted adjacent documentation, selected a mutated tree as a baseline, and used stale anchors.**

- **Recovery:** Rebuilt complete isolated copies from a pristine source tree and
  checked each mutation anchor before applying it.
- **Prevention:** Include every file the suite reads, construct a clean baseline
  separately from mutants, and assert each mutation anchor exists exactly where
  expected.

**Scratch mutation checks sometimes expected outdated failure labels.**

- **Recovery:** Inspected the test output, confirmed the mutant was killed, and
  corrected the expected diagnostic anchors, including on a later proxy-alias
  mutation.
- **Prevention:** Match the actual assertion-specific failure, not a remembered
  or stale output string.

**The single verification pass found a P3 mismatch between the mutation matrix and direct proxy-option fixtures.**

- **Recovery:** Added direct equals/separated tests for `--preproxy` and
  separated/attached tests for `-x`; the final focused suite passed 183/183.
- **Prevention:** Cross-check every written mutation claim against an assertion
  for that exact option spelling; keep the final test count tied to the latest
  run.

**The local affected gate returned budget-deferred under sibling-run contention.**

- **Recovery:** Checked capacity, stopped before starting another full run, and
  left CI's required `test` check as the authoritative result.
- **Prevention:** Treat capacity contention as no local verdict; rely on the
  tracked CI check rather than claiming a pass.

**Push output reported 80 open Dependabot alerts on the repository's default branch.**

- **Recovery:** Queried the alert API and verified the aggregate severity counts;
  the alerts were unrelated to this feature.
- **Prevention:** Investigate repository-wide security notices, but keep unrelated
  backlog work out of a focused feature PR.

**An initial `knowledge-base/INDEX.md` lookup returned not-found.**

- **Recovery:** A repository-scoped glob confirmed the index file is absent from
  this worktree.
- **Prevention:** Verify the index exists before prescribing or following its
  paths.

**The related-docs search first used the parent directory of a matching learning.**

- **Recovery:** The search was corrected to the learning's actual
  `integration-issues/` category path.
- **Prevention:** Read the exact path returned by the repository search instead
  of inferring a category directory from its basename.

**The first YAML check parsed an unquoted date scalar as a date object.**

- **Recovery:** Quoted the date so it remains a schema-conforming string.
- **Prevention:** Quote ISO dates in frontmatter when the schema requires a
  string; validate the parsed type, not only the visible format.

**The related-docs search first used the parent directory of a matching learning.**

- **Recovery:** The search was corrected to the learning's actual
  `integration-issues/` category path.
- **Prevention:** Read the exact path returned by the repository search instead
  of inferring a category directory from its basename.

## Solution

The mock now distinguishes actual transfer-target forms from proxy settings:

```bash
case "$1" in
  --url) shift; record_url "$1" ;;
  --url=*) record_url "${1#*=}" ;;
  --proxy|--preproxy|-x) shift ;;       # consume the setting; do not log it as a target
  --proxy=*|--preproxy=*|-x*) ;;        # likewise for attached/equal forms
  -H|-w|--max-time|--noproxy) shift ;;  # consume unrelated option values
  -*) [[ "$1" == *://* ]] && record_url "$1" ;;
  *) record_url "$1" ;;
esac
```

Capture the original argv before parsing. Pin the complete dry-run recipe, all
six live target URLs, exactly one Notifications URL, mock suffix fall-through,
and proxy-option absence in the SUT argv. Cover valid array responses and
fail-closed 404, degraded, object, and empty-object responses.

## Why This Works

The test's property is the set of actual transfer targets, not the set of
strings containing `://`. Curl options consume operands with different
semantics. A mock that ignores those boundaries can turn a proxy destination
into false evidence that the intended API request happened. Exact command and
target assertions, plus mutations of each option form, make the observer prove
the request rather than merely echoing a URL-shaped value.

## Prevention

- Model the command's option grammar in the test double; separate transfer
  targets from proxy and other option values.
- Test positional URLs, `--url`, and `--url=` across schemes, plus separated,
  equals, and attached proxy forms.
- Assert the full displayed command and the exact request count; a substring or
  line count is not proof of the target set.
- Mutation-test every claim using the spelling that could violate it, including
  extra targets, proxy-only values, and proxy overrides beside a real target.
- Keep the final focused-test count synchronized with the latest passing run.

## Related Issues

- Related route correction: [2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md](../2026-10-28-cf-token-retained-probe-used-nonexistent-notification-route.md) (included byte-identically; its source copy remains untouched).
- Related curl argv/mutation guidance: [2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md](../2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md).
- Implementation and regression tests: `plugins/soleur/test/cf-token-scope.test.sh`.
