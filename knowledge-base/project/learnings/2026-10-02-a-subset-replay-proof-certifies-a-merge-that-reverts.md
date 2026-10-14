---
title: "A subset replay proof certifies a merge that reverts main — and other #9401 review lessons"
date: 2026-10-02
category: workflow-patterns
tags: [admin-merge, carryover, security, bash, jq, git, hooks]
issue: 9401
---

## What happened (#9401 review)

A `--allow-local-merge` carryover arm proved "the merge added nothing but base-side
docs content" by checking `files(compare(G…HEAD)) ⊆ files(compare(G…parents[1]))`
on name+status+patch. The security review seat constructed the bypass the subset
direction cannot see: a merge commit with parents `[G, tip]` and **G's tree** (`git
merge -s ours`, or hand-built `commit-tree`) has an EMPTY added delta — vacuously
clean. `--match-head-commit` then lands `SHA` onto `main` with `main`'s tip already
an ancestor, so the result tree is `SHA`'s tree and every un-replayed main-side
file is silently **reverted** — code files the docs-only classifier never inspects,
because the deletion appears on neither side's `files` list.

## Fixes that followed

- **Bijection, not subset.** Compare the two deltas as EQUAL multisets of
  `(filename, status, previous_filename, patch)` tuples — a dropped file and a
  renamed-source asymmetry both fail now. ("Prove the replay, not the additions.")
- **`grep -Fxqf` over `comm -12` + `sort -u`.** `comm` collates by the ambient
  locale while the sorts were pinned `LC_ALL=C`; a collation disagreement drops a
  shared line → FALSE disjoint → a *skipped* sync — the unsafe direction. And bare
  `! grep` conflates error (rc≥2) with no-match (rc=1): capture `$?` and treat only
  `1` as disjoint.
- **`git diff --name-only --no-renames`** — default rename detection prints only
  the destination name, so a rename+modify reads disjoint; `--no-renames` lists the
  old name on both sides.
- **`git remote get-url` resolves `url.insteadOf`** — it returns the rewritten
  target, not the configured URL. For URL-identity proofs (same-repo `-R`
  normalization) read `git config --get remote.origin.url`. (The fixture bug that
  exposed this: `remote set-url` to a fake HTTPS URL + `insteadOf` to a local bare
  repo — get-url reported the local path, not the URL.)
- **Apostrophes inside a single-quoted jq program terminate it** — a `#` comment
  inside the program containing `PR's`/`rename's` produced `syntax error near
  unexpected token` at the NEXT `elif` — twice in one review round. Comments inside
  single-quoted jq must not contain `'`.
- **`${var,,}` is a parse error on stock macOS bash 3.2** — repo convention is
  `tr '[:upper:]' '[:lower:]'`; the folded forms fail closed but dead-code the
  feature on such hosts.
- **Ambient env is part of the proof.** `gh` honors exported `GH_HOST`/`GH_REPO`
  even with no flag in the command text — a same-repo proof that only scans the
  command string mis-grades (a foreign ambient `GH_HOST` + hostless `-R o/r` would
  have proven "same" while `gh` acted on another host). Seed the operand set with
  `"${GH_HOST:-}"`/`"${GH_REPO:-}"`.

## Key Insight

Any "the merge only added X" proof is incomplete — it must also prove "the merge
dropped nothing." Subset on the added delta certifies `-s ours`. The second lesson:
in a hook that intercepts command text, the *environment* is part of the command —
exported vars steer `gh` the same as in-line assignments, so proofs that read only
the text are incomplete in both directions.

## Tags
category: workflow-patterns
module: merge-machinery
