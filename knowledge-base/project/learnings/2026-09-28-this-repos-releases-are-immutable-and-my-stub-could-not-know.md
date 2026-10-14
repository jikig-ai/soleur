---
title: This repo's GitHub releases are immutable, and a stubbed gh cannot know it
date: 2026-09-28
category: integration-issues
tags: [github-releases, immutable-releases, docker, cosign, test-stubs, oci]
issue: 8714
---

# Learning: this repo's releases are immutable, and a stubbed `gh` cannot know it

## Problem

PR 2a of #8714 step 5.3b-iii publishes the zot registry host's boot image as a GitHub release asset
through a new workflow. The design, the plan review panel and two self-run mutation batteries all
used `gh release create` followed by `gh release upload`. This repository has **immutable releases**
turned on (`gh api repos/jikig-ai/soleur/immutable-releases` → `{"enabled":true}`). An upload to a
published release returns HTTP 422. The first merge would therefore have produced a published
`zot-image-v2.1.20` with no asset. That state cannot be repaired, because the release cannot take
an upload and its tag cannot be reused. The security review seat found it by reading
`reusable-release.yml:383-394`, which had documented the same failure months earlier. The publish
test stubbed `gh`, so no test could have seen it.

Review found two sibling defects of the same shape, where the fixture was a story rather than a
measurement:

- The cosign classifier's test rows were invented one-liners. Docker's real pull error repeats the
  64-hex digest twice and runs about 420-450 bytes (measured, docker 29.7.2). The classifier's
  `tail -c 400` therefore never saw the `Error response from daemon` prefix, and every real DNS or
  429 failure stayed `verify_failed`.
- The stub `gh`/`curl` accepted any argument. Six mutations survived: create with the version
  instead of the tag, upload of the un-renamed file, a dropped `--target`, verify of the local
  build instead of the download, a digest read by position, and a dropped auth header.

## Solution

- **Publish through a draft:**
  1. delete any leftover draft for the tag;
  2. `gh release create --draft --prerelease --target <sha>`;
  3. `gh release upload`;
  4. `gh release edit --draft=false --latest=false`.

  A published release without an uploaded asset (`state == "uploaded"`) fails. The tag carries D's
  12-hex prefix, so a re-tagged upstream version gets a new tag instead of colliding with an
  immutable one.
- **Classifier:** grep the WHOLE stderr file, anchored at line start on
  `^docker: Error response from daemon:`. Cosign's own errors start with `Error:`, so a
  registry-quoted message cannot relabel them. The test rows use the measured shape, one keyword per
  case, plus two negatives.
- **Stubs:** route on argv POSITION, and refuse every argument the SUT must not send (wrong tag,
  wrong path, missing `--target`, missing `--draft`, unauthenticated reads) into a file each row
  checks.

## Key Insight

A stub encodes what its author believes the vendor does. The vendor's own constraints are exactly
what it cannot know: repo settings, rate limits, error byte-shapes, auth rules. Before writing a
stub for an external API, run the real command once against the real target. That means a dry
`gh api …/immutable-releases`, a real failed pull captured to a file, or a real 404 body. Derive the
fixture from that capture, never from memory. A green mutation battery over an invented fixture
measures the author's model of the vendor.

Two smaller facts from the same work:

- The **containerd image store does not normalize a short local image name**. After a successful
  `docker load`, `docker image inspect soleur-local/x:tag` fails, while
  `localhost/soleur-mirror/x:tag` works. Loaded image IDs also differ by store: the containerd store
  reports the manifest digest D, the classic store the config digest C. Accept both.
- **`--sort=name` sorts only WITHIN directories.** GNU tar keeps top-level operands in argument
  order. Also check 8 bytes at offset 257 to pin POSIX ustar: GNU format also starts with `ustar`.

## Session Errors

1. **Python batch-edit anchor had the wrong indentation, so the batch aborted.** Recovery: re-ran with
   the exact bytes (`cat -A`). **Prevention:** assert the anchor exists before editing (the
   `assert s.count(a)==1` pattern), and treat an unchanged suite count after a batch as UN-RUN.
2. **`sed` with a `|` delimiter failed on a pattern containing `|`.** Recovery: switched to Python
   string replace. **Prevention:** use Python for any edit whose pattern contains the delimiter.
3. **The commit's `bun-test` hook queued behind sibling worktrees' `test-all` runs.** Recovery: killed
   only this worktree's hook tree (verified via `/proc/<pid>/cwd`), ran the affected suites
   directly, then recommitted with `LEFTHOOK_EXCLUDE=bun-test`. **Prevention:** existing work-skill
   guidance (the narrower escape hatch).
4. **B2b fixture assumed `--sort=name` sorts top-level operands.** Recovery: asserted the fixed order
   (operands, then sorted `blobs/`). **Prevention:** see the Key Insight tar note.
5. **`drop-ustar` mutant survived a 5-byte magic check.** Recovery: compare 8 bytes to `ustar\0` +
   `00`. **Prevention:** when pinning a format, compare the bytes that DIFFER between the formats.
6. **Immutable releases missed at plan and implementation.** Recovery: draft-then-publish. Also
   routed to the plan sharp-edges catalogue. **Prevention:** that bullet.
7. **Invented classifier fixtures.** Recovery: measured the shape. **Prevention:** existing
   work-skill rule (the fake puts the seam above what the vendor validates).
8. **Permissive stubs.** Recovery: argv-position routing plus refusals. **Prevention:** existing
   work-skill rule (the stub must refuse a request it did not expect).
9. **Short local image name unresolvable in the containerd store.** Recovery: fully-qualified
   `localhost/…` name. **Prevention:** the Key Insight note.
10. **EXIT trap referenced a function-local variable.** Recovery: a top-level `W` bound before the
    trap. **Prevention:** bind every trap operand at top level.
11. **Anti-vacuity literal off by one.** Recovery: counted the rows. **Prevention:** derive the
    literal from a green run, never from expectation.
12. **PR 1's probe declared `credentials_required` although an unauthenticated API substitute
    existed**, which raised the corpus baseline. Recovery: an unauthenticated curl of the public
    Actions API. **Prevention:** existing plan 2.9 rule (the waiver is only for properties with no
    unauthenticated substitute).
13. **`rename-guard` flagged a new test as a 5% COPY of a sibling.** Recovery: a gitleaks scan with
    no allowlist, then a `Rename-Allowed-By` trailer. **Prevention:** none needed. The guard works
    as designed, and the trailer records the evidence.
14. **Armed a duplicate Monitor.** Recovery: `TaskStop`. **Prevention:** the supersede hook already
    warns.
15. **`fixture-relative-assert` flagged builder writes under roots it could not prove absolute.**
    Recovery: one top-level `mktemp` root plus the canonical `assert_fixture_dir`, and an absolute
    output path. **Prevention:** existing work-skill rule 6.6.
16. **`lint-shell-capture-exit` S1 on a `grep -o` capture.** Recovery: `|| die`.
    **Prevention:** existing lint.
