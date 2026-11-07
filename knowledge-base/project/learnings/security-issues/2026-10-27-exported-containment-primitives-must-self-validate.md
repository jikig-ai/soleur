---
date: 2026-10-27
category: security-issues
tags: [toctou, file-system-race, codeql, containment, exports]
---

# Exported containment primitives must enforce their own input validation

**Context.** Fixing CodeQL alert #248 (`js/file-system-race`) in
`writeDigestFileContained` (`apps/web-platform/server/inngest/functions/_cron-community-publication.ts`),
the lstat→mkdir→lstat ancestor walk was replaced with fd-pinned traversal:
`openContainedDir`/`createContainedFile` internals resolving children through
`/proc/self/fd/<fd>/` on Linux. The clean-relative-path check lived in the
exported wrapper only — the helpers were exported for the regression tests.

**Finding (5 review seats, empirically confirmed).** `/proc/self/fd/<fd>/..`
resolves to the pinned dir's real parent — `O_NOFOLLOW` guards only the final
component — so `openContainedDir(root, [".."])` escaped containment silently,
and a `/`-bearing `leaf` resolved a planted intermediate symlink under the
pin. Zero production callers were exploitable (the wrapper validated), but the
exports were the reusable containment API and enforcement sat one level up.

**Rules.** (1) A primitive exported as a containment boundary enforces the
invariant itself — basename checks (`""`, `.`, `..`, `/`, `\`) belong inside
`openContainedDir`/`createContainedFile`, not trusted to callers. (2) A pinned
path embedding an fd *number* (`/proc/self/fd/<n>/…`) goes stale if the handle
closes mid-flight (fd numbers recycle) — re-verify `fh.fd` before every use of
the path, `unlink` included, not only before `open`. (3) A check→use pair
CodeQL flags is only closed by fusing check into the syscall — realpath-verify,
mkdir -p + O_NOFOLLOW, and temp+rename all re-open the window.

**Also worth noting.** macOS `unlink(dir)` returns `EPERM` (not `EISDIR`) —
mapping only `EISDIR` to a "target is a directory" contract breaks the error
shape on darwin. And an eslint `no-unused-vars` destructure left behind by an
extraction is a ratchet breach (merge-blocking), not a warning.

Ref: PR #11334, issue #10368 (+ 9 duplicate machinery issues), decision rulings in
`knowledge-base/project/specs/feat-one-shot-10368-codeql-fs-race/decision-challenges.md`.
