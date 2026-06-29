# Learning: "build a CI gate" was already in the test shard; and an empty-stdin `--body-file -` wiped an issue body

## Problem

Two distinct lessons from the #5703 brainstorm (CI backstop for gated classifier-skill edits):

1. **The CI gate the issue asked to "build" already ran on every PR.** #5703 asked
   for a required CI check that re-runs the eval-harness on PRs touching a gated
   classifier skill. The deterministic half (projection-freshness round-trip,
   `extract-block.test.sh`) was *already* running on every PR — discovered only by
   reading `scripts/test-all.sh`'s discovery globs. Without that check, the brainstorm
   would have proposed a redundant new workflow.

2. **An empty-stdin destructive write silently wiped a GitHub issue body.** Building an
   issue-update payload as `cat <fileA> <fileB> | gh issue edit 5703 --body-file -`
   wiped #5703's body to 1 char because the scratchpad dir didn't exist, so both `cat`
   targets errored and stdin was empty. `gh issue edit --body-file -` accepts empty
   stdin as "set body to empty" with no warning.

## Solution

1. **Before designing any CI gate, grep the test-runner's discovery globs** to check
   whether the deterministic check already runs per-PR. Here:
   `scripts/test-all.sh:186` globs `plugins/soleur/skills/*/test/*.test.sh`, which
   `ci.yml:375` (`bash scripts/test-all.sh scripts`) runs on every PR — so every
   `eval-harness/test/*.test.sh` already gates merges. The real residual gap was
   narrower: registry↔marker completeness drift + a hardcoded round-trip target loop
   (`for target in go-routing ticket-triage`, not registry-driven). Scope collapsed
   from "new workflow" to "two deterministic test additions in the existing shard."

2. **Never pipe `cat` of unverified files into a destructive `--body-file -` (or
   `--body`, `gh pr edit`, etc.).** Either (a) build the entire payload in a single
   heredoc to one file and verify it is non-empty (`[[ -s file ]]`) before piping, or
   (b) capture the original body first and guard: `test -s payload || { echo "empty
   payload, aborting"; exit 1; }`. Recovery here worked only because the original body
   was still in the session transcript from the session-start `gh issue view`.

## Key Insight

- A "build X" issue is a claim about desired end state, not about what already runs in
  CI — verify the deterministic layer against the test-runner's globs before designing.
- Destructive single-shot writes (`--body-file -`, `--body`, file overwrites) must
  validate their payload is non-empty *before* the write, because the failure of an
  upstream `cat`/redirect degrades silently to "empty input" rather than an abort.

## Session Errors

- **Empty-stdin issue-body wipe** — `cat <scratchpad files> | gh issue edit 5703
  --body-file -` set #5703's body to empty because the scratchpad dir was absent (both
  `cat`s errored, stdin empty). **Recovery:** restored the body from the session-start
  `gh issue view` capture + re-appended the reframe note via a verified heredoc file.
  **Prevention:** guard destructive `--body-file`/`--body` writes with a non-empty
  payload check (`[[ -s "$f" ]]`), or assemble the payload in one heredoc rather than
  cat-ing multiple unverified files; `mkdir -p` the scratchpad dir before writing to it.

## Tags
category: workflow-patterns
module: soleur:go, soleur:brainstorm, eval-harness, gh-cli
issue: 5703
