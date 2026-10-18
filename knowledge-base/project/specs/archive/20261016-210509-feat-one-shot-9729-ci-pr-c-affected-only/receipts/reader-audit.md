# Reader audit for the go/no-go, criterion (d) (S4 PR C, Ref #9729)

Question (CTO R3 (d)): is every test file that mentions the documentation tree classified, and is none a REAL reader inside a suite the
proposed rule would skip?

Commands and counts (2026-10-16, tree `origin/main` at `ee8644bded` plus this branch's tooling (the two new suites name no documentation-tree path: the census passes with them)):

- `git grep -l "knowledge-base" -- 'apps/web-platform/**/*.test.*' 'apps/web-platform/test' | wc -l` returns **238** files in the
  web-platform tests (the plan-time count was 238; the CTO figure of 207 used a different grep shape).
- The classification instrument is the dropped-consumer census `scripts/test-affected-kb-consumers.test.sh` (30 of 30 cases pass on this
  branch; `bash scripts/test-affected-kb-consumers.test.sh` exits 0). It joins the enumerated registrations with the selector's per-suite edge
  sets and fails when a registered suite that reads a REAL documentation path is neither always-on nor covered by an edge for that path.
- `scripts/test-affected-kb-consumers.baseline.txt` holds **274 rows over 104 suites**: **266** are two-column rows (a read the census found
  covered by an edge or by the always-on set) and **8** carry a human-written `false-positive:` reason (a fixture write or a mention in a
  scratch repo, never a read of the real tree).
- The web-platform unit registration (`apps/web-platform [repo-wide+component]`) is selected through an `edge:consumed` edge, not always-on
  (its README-only row is `sel=0`); the 238 mentions are therefore covered or classified by the census, not by a per-file list.

Stated blind spots (from the census header, unchanged): only LITERAL `knowledge-base/` references are seen; one hop into scripts a suite
names; a variable assigned the bare literal and `${VAR:-knowledge-base/...}` defaults were measured on 2026-10-02 as false positives and are not
implemented; no check can tell a real read from a false positive, which is why the column carries a human reason.

**Status for criterion (d): `pass`**, with the blind spots above recorded. It is not a proof: the census checks the documentation tree only, and
the index audit (`index-audit.md`) shows the same class of gap for other root files (README.md, `.claude/settings.json`, AGENTS.md).
