---
title: "knowledge-base/INDEX.md is batch-regenerated, not per-PR — regen on a feature branch bundles pre-existing drift; surgically edit your own entries instead"
date: 2026-06-04
category: workflow-patterns
tags: [knowledge-base, index, generate-kb-index, pr-hygiene, scoped-diff, kb-tags, kb-categories]
branch: feat-one-shot-c4-single-page
pr: 4940
---

# Regenerating knowledge-base/INDEX.md on a feature branch bundles unrelated drift — prefer a surgical edit

## Problem

A plan said to run `bash scripts/generate-kb-index.sh` after adding/removing
knowledge-base `.md` files and commit the result. Running it produced a **+993
line** `INDEX.md` diff (committed header `Total files: 3773` → regenerated
`4759`), plus +388 `kb-tags.txt` and +12 `kb-categories.txt` — almost entirely
**unrelated to the actual change** (one file deleted-x3, one added). The PR was a
focused 3-page → 1-page docs consolidation; the regen would have dumped ~986
unrelated index entries into it.

## Key Insight

**`knowledge-base/INDEX.md` (and `kb-tags.txt` / `kb-categories.txt`) is
batch-regenerated sporadically, NOT on every PR.** Evidence: the last commits
touching `INDEX.md` were occasional KB-restructure PRs (e.g. #4887, #4182,
#4013), and there is **no CI workflow** that runs `generate-kb-index.sh` (grep
`.github/` → no reference) and **no CI gate** enforcing index freshness. So the
committed index is chronically behind `main` by hundreds of files at any time.

Running the generator on a feature branch therefore captures all that
accumulated drift into your PR — inflating the diff, creating a merge-conflict
magnet, and burying your actual one-line change in noise.

## How to apply

- When a plan says "regenerate INDEX.md", first check whether the committed index
  is stale: run the generator, then `git diff --numstat -- knowledge-base/INDEX.md`.
  If the delta is far larger than your change (hundreds of lines), the index is
  stale-committed.
- For a **scoped PR**, discard the bulk regen and surgically edit only your own
  entries: `git checkout HEAD -- knowledge-base/INDEX.md knowledge-base/kb-tags.txt
  knowledge-base/kb-categories.txt`, then hand-edit `INDEX.md` to remove the
  deleted files' entries and add the new file's entry in the generator's
  **path-sorted** position. (To find the right sorted slot, read the regenerated
  file's neighbors around your entry before discarding it — the sort key is the
  repo-relative path, e.g. `diagrams/README.md` < `diagrams/c4-model.md` <
  `nfr-register.md`.)
- Only touch `kb-tags.txt` / `kb-categories.txt` if your change actually adds new
  frontmatter `tags:`/`category:` values. A page with no frontmatter (or a plan
  file without tags) contributes nothing to them — leave them at HEAD.
- The "Do not edit manually" banner is about not authoring entries that drift
  from the generator's format. A surgical removal+insertion that matches the
  generator's exact output (path-sorted, same link format) is consistent with
  the generator, just without the unrelated drift. Bringing the whole index
  current is a separate, dedicated chore — not a rider on a feature PR.

## Session Errors

1. **Edit-before-Read on `nfr-register.md`** — the first `Edit` failed with "File
   has not been read yet"; the file had only been viewed via `sed -n`, which does
   not satisfy the Edit tool's in-conversation read requirement.
   — Recovery: `Read` the file, then `Edit`.
   — **Prevention:** already enforced by `hr-always-read-a-file-before-editing-it`
   and the Edit tool's own guard. `sed`/`cat`/`grep` viewing does NOT count as a
   Read — use the Read tool before Edit. No new enforcement warranted.
2. **`INDEX.md` regeneration bundled ~993 lines of pre-existing drift** (the
   committed index was ~986 files stale).
   — Recovery: `git checkout HEAD --` the three generated files, then surgically
   swapped the 3 deleted-page entries for the 1 new `c4-model.md` entry.
   — **Prevention:** this learning. Candidate plan-skill refinement: when a plan
   prescribes `generate-kb-index.sh`, note that the index is batch-maintained and
   a scoped PR should surgically edit only its own entries.
