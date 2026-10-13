---
title: "A red row backstopped by a later clause proves nothing about the clause it names"
date: 2026-10-12
category: workflow-patterns
issue: 10147
pr: 10162
tags: [mutation-testing, vacuity, probe-rows, guards, discrimination, spelling-census, infra-guard]
---

# A red row backstopped by a later clause proves nothing about the clause it names

## Problem

PR #10162 (`feat-one-shot-10147-10148-ext-residence-hardening`) hardened Guard 2's
`EXT_RESIDENCE` table: mandatory per-member `pin` fields bounded to repo-relative
`*.test.sh`/`*.test.ts` files, a fail-closed `unclassifiable` arm for non-literal
host expressions outside `server.tf`, and a `SOLEUR_PARITY_EXT_RESIDENCE_PROBE`
env var that feeds synthetic table entries through the same hygiene function so
the battery can exercise every branch.

The first probe battery (X1–X20) went green. Two independent fix-round seats then
found the same class: **the pin-bound probe rows X17/X18/X19 were red for the
wrong reason.** Each named a lexical conjunct (`startswith("/")`, `".."` in parts,
`endswith`) but supplied an input that *also* failed the trailing `is_file()`
clause — so deleting the named conjunct left the row red via the existence
backstop. The row claimed to prove a clause it never exercised.

## Root Cause

A conjunct chain `a or b or c or is_file()` has an implicit order: any input that
fails a *later* clause cannot discriminate an *earlier* one. My probe inputs were
written to be plausible violations, not to be **survivors**. The fix in every case
was the same shape — make the input satisfy every clause except the named one:

- Absolute pin → point it at a file that actually exists in the scratch repo
  (`"$TF_REPO/apps/.../luks-monitor-install.test.sh"` interpolated into the JSON).
- `..` traversal → `apps/../plugins/soleur/test/terraform-target-parity.test.ts`,
  which resolves onto an extant in-tree file.
- Wrong suffix → `touch` a real `.test.txt` first so only `endswith` rejects.
- Leaf symlink → target must exist (X20 already had this right — it was the
  counter-pattern the others missed).
- Intermediate-dir symlink → symlink a directory component, leaf a real file
  outside REPO (X24 exercises `resolve().is_relative_to(REPO)` — leaf
  `is_symlink()`/`is_file()` both pass).

The rule: **per row, simulate deleting the named clause.** If the row stays red,
it is vacuous for its stated purpose regardless of the anchor matching.

## Sibling findings worth carrying forward

- **A spelling census is a tripwire, not a closed sequence.** The reader-shape
  pin grew from 4 spellings to ~40 across two rounds (`read_bytes`, `iterdir`,
  `os.walk`, `statvfs`, from-import stat spellings, the write side
  `write_text`/`mkdir`/`symlink_to`, exec side `Popen`/`os.system`/`eval`,
  `subprocess.run` pinned at exactly 1, `symlink(` pinned at 1 since it is
  `is_symlink(`'s own substring). Every seat could name more — `group(`,
  `str.replace`, `from os import path` are unpinnable without colliding with
  legitimate code. Write the comment as "plausible natural spellings," not
  "every other file-touching spelling."
- **`grep -c` counts lines, not occurrences.** Two call sites on one line read
  as 1 and the exact-count bound passes vacuously. Use `grep -oE ... | wc -l`;
  add `[[:space:]]*\(` so legal `name ()` spellings cannot evade; append
  `| tr -d '[:space:]'` because BSD `wc -l` pads its output.
- **Reader pins count comments.** `read_text(` inside a `#` comment drifted the
  pinned count — the reader-shape check cannot distinguish code from prose.
  Comment text is inside the pin's universe.
- **Stat calls raise on hostile strings.** `Path.resolve()` throws `ValueError`
  on embedded NUL (reachable via probe JSON); symlink loops throw `RuntimeError`
  on old Pythons. Wrap the stat triple in `try/except` so the failure lands in
  the named `pin_bad` arm instead of a traceback — same class X1/X8/X22 exist
  to eliminate.
- **Scratch fixtures belong in trapped per-run dirs.** A fixed-name file in
  `dirname $TF_REPO` shared TMPDIR collides across concurrent runs and leaks
  outside the EXIT trap; `$PRISTINE_REPO` is per-run, trapped, and still
  outside the sandboxed repo.
- **`no()` never exits** — `rm -f`/`restore` after a failed row still run;
  fixture cleanup is reachable on every non-FATAL path.
- **Anchors need family prefixes.** `"stale EXT_RESIDENCE"` substring-matches
  both the real-table arm and the probe arm; `"stale EXT_RESIDENCE probe"`
  discriminates. `(malformed entry)` vs `(malformed entry,` are disjoint only
  because of the comma — lean on it deliberately.

## Verification

Full battery after all fixes: 143/143 green; per-conjunct deletion simulation
confirmed each X-row isolates exactly its named clause. Sibling corpus:
`2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md`,
`2026-09-23-a-mutation-anchor-can-match-inside-your-own-comment.md`,
`2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`.
