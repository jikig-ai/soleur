---
title: "A gh stub that implements invented flags makes the SUT's dead code green"
created: 2026-09-25
source: feat-one-shot-ci-main-duplicate-skip / PR #8919
related: ["2026-03-04-gh-jq-does-not-support-arg-flag"]
---

# Stub fidelity: reject flags the real CLI doesn't have

The duplicate-skip proof shipped `gh api ... --arg p X` — `gh api` has no
`--arg` (cli/cli#10263; the repo's own learning names the gap). The test
stub parsed `--arg` anyway, so the mutation battery green-lit code that
errors on every real call — the whole feature was a silent no-op in the
fail-open direction (safe, but worthless).

Fix shape: (a) SUT uses `gh api URL | jq -r --arg p X` (two-stage); (b) the
stub WHITELISTS real `gh api` flags (`--jq`, `--paginate`, `-X`, `-f`, `-F`)
and exits 64 on anything else — an invented flag is a miss, not an answer.

Sibling trap found the same session: `pull_request` runs test the
merge-PREVIEW tree, not the head tree — a tree-equality proof of "the PR
already ran this" needs an ancestry check (head contains the merge-time
base) or it can green-light a tree the preview never saw.
