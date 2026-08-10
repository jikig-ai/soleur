---
title: "PIPE_BUF atomicity did not apply, because the thing I redirected into was a file"
date: 2026-08-10
module: scripts/generate-kb-index.sh
problem_type: logic_error
component: tooling
severity: high
tags: [xargs, parallel-write, pipe-buf, data-race, generated-artifacts, false-comment, macos-portability]
related_files: scripts/generate-kb-index.sh, plugins/soleur/test/generate-kb-index.test.sh
---

# PIPE_BUF atomicity did not apply, because the thing I redirected into was a file

## Problem

`generate-kb-index.sh` produced `kb-tags.txt` and `kb-categories.txt`
nondeterministically. Five runs over one unchanged corpus produced five distinct
outputs. The committed artifacts carried ~14 fabricated values —
`agent-worcat`, `blast-radcat`, `cloudflacat`, `mutation-testincat` — and a
`grep -c` for the real value the first of those was torn from returned **0**.

`kb-search` validates `--tag`/`--category` against those files and rejects a
miss with *"No matches. Valid values: …"*. So a real, in-corpus category was
being reported as invalid, because the corruption had destroyed it.

## Root cause

```bash
find "$LEARNINGS_DIR" … -print0 \
  | xargs -0 -P4 -n100 awk '…' > "$facets_tmp"
```

The redirect is on the **whole pipeline**, so `$facets_tmp` is a regular file
and all four `awk` children inherit the same open file description on it.

`PIPE_BUF` atomicity is a property of **pipes**. It does not apply to regular
files at all. And `awk` block-buffers stdout, so it flushes in ~4096-byte
blocks whose boundaries land mid-line; another child's flush lands in the gap.

The downstream stage is what makes it destructive rather than merely noisy:

```bash
{ grep $'^tag\t' "$facets_tmp" || true; } | cut -f2 | LC_ALL=C sort -u > "$TAGS_FILE"
```

`cut -f2` keeps the spliced prefix **and discards the remainder**. One tear
therefore fabricates a key *and* deletes a true one. A validation gate built on
that file then rejects a legitimate value.

## The comment was inverted in every clause

The block above it asserted safety:

> Parallel-safe because each batch writes independent lines to its own stdout
> stream, **which xargs concatenates into the downstream pipe**. Lines are
> always smaller than PIPE_BUF (4 KB), so atomic writes hold. … **(TR9 — no
> shared append target).**

There is no downstream pipe — there is a redirect to a file. And the file *is*
the shared append target the comment says does not exist. Both halves of the
justification named the exact property that was false.

This is why it survived: a reader checking the code against the comment finds
them consistent in vocabulary. Only asking *what is on the other side of the
`>`* separates them.

## Fix

Drop `-P` on that walk.

Measured on the real corpus: `-P4` → 5 distinct outputs over 5 runs; serial → 1;
`stdbuf -oL` → 1, **byte-identical to serial**. So both fixes are correct.

Serial was chosen over `stdbuf -oL` for a portability reason, not a correctness
one: `stdbuf` is GNU coreutils and is absent from stock macOS, and this script
ships inside a plugin that runs on customers' machines. It is also not slower
here (2,119 files; whole-script time measured within noise of `-P4`).

Piping into `sort` instead of redirecting is a **partial** fix and was rejected:
it gives the children a real pipe, but `awk` remains fully buffered there, so a
flush still splits a line across two atomic 4096-byte writes and another child
can land between them.

## Key insight

**Ask what is on the other side of the redirect before trusting any
concurrency argument about it.** `xargs -P … | consumer` and
`xargs -P … > file` look almost identical and have different safety models.
The first can be sound; the second is a shared append target with no atomicity
guarantee at all.

And when a comment justifies concurrency safety, check its *nouns*. A comment
that says "pipe" about a file is not approximately right — it is asserting the
one property that makes the code wrong.

**Detection:** `git grep -nE "xargs .*-P[0-9]* .*> *\"?\\\$"` — any `xargs -P`
whose pipeline ends in a redirect rather than a consumer.

**Second-order:** the corruption was invisible to the suite because the
determinism test used a 1–3 file fixture. One `awk` batch emitting far under
4096 bytes can never reach a flush boundary, so the test could not fail for the
bug it appeared to cover. A contention test needs a corpus that provably spans
multiple flush boundaries *and* multiple `xargs` batches — and should assert
that it does (`tag_bytes >= 4096`), or it silently degrades back into the
vacuous version the next time someone trims the fixture.

## Session Errors

- **Committed the corrupted artifacts.** The regeneration commit landed a fresh random draw of the race. The race pre-dated the PR; committing its output did not. **Prevention:** treat a generated artifact as reviewable output — regenerate twice and diff before committing.
- **The B-arm of my own fix comparison was invalid.** A `perl` invocation failed to create the mutant file; the arm then ran a nonexistent script and reported the *previous* arm's leftover md5 as its result. It read as a clean pass. **Prevention:** assert the mutation landed (`diff -q` against a pristine backup) before reading any battery row; a mutation that did not land reports the baseline, which is indistinguishable from a kill.

## See also

- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] — the fixture could not reach the defect; same shape, different axis.
- [[2026-08-10-my-verification-was-narrower-than-the-claim-it-certified]] — the sibling from this session.
