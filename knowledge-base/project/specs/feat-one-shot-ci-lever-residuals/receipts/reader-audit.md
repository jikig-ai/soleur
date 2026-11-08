# Reader audit for the go/no-go re-ruling, criterion (d) (S4, Ref #9729)

Question (CTO R3 (d), unchanged): is every test file that mentions the documentation tree classified, and is none a REAL
reader inside a suite the proposed rule would skip?

Commands and counts (2026-11-07, this branch's tree at `4591c12e39`; the audit-pinned tree is `a2075a2e10`):

- `git grep -l "knowledge-base" -- 'apps/web-platform/**/*.test.*' 'apps/web-platform/test' | wc -l` returns **283** files
  in the web-platform tests (was 238 on 2026-10-16 — the tree grew; the census instrument is unchanged).
- The classification instrument is the dropped-consumer census `scripts/test-affected-kb-consumers.test.sh`:
  **31 of 31 cases pass, exit 0**, run 2026-11-07 on this worktree. It joins the enumerated registrations with the
  selector's per-suite edge sets and fails when a registered suite that reads a REAL documentation path is neither
  always-on nor covered by an edge for that path.
- `scripts/test-affected-kb-consumers.baseline.txt` holds **330 rows over 124 suites**: **322** are two-column rows (a
  read the census found covered by an edge or by the always-on set) and **8** carry a human-written `false-positive:`
  reason (a fixture write or a mention in a scratch repo, never a read of the real tree). Was: 274 rows over 104 suites
  (266 + 8) on 2026-10-16; the same 8 false-positive rows remain, the covered set grew with the suite set.
- The web-platform unit registration (`apps/web-platform [repo-wide+component]`) is still selected through an
  `edge:consumed` edge, not always-on: on a README-only diff
  (`env -u CI -u SOLEUR_TEST_FORCE_ALL bash scripts/test-all.sh --print-selection --paths=README.md`) its row is
  `sel=0` and the summary reads `selected=123 of=745 always_on=118 edge=5 fallback=none`. The 283 mentions are
  therefore covered or classified by the census, not by a per-file list.

Stated blind spots (from the census header, unchanged): only LITERAL `knowledge-base/` references are seen; one hop into
scripts a suite names; a variable assigned the bare literal and `${VAR:-knowledge-base/...}` defaults were measured on
2026-10-02 as false positives and are not implemented; no check can tell a real read from a false positive, which is why
the column carries a human reason.

**Status for criterion (d): `pass`**, with the blind spots above recorded. It is not a proof: the census checks the
documentation tree only; other root files (README.md, `.claude/settings.json`, AGENTS.md) are covered by criterion (b)'s
index audit, which this re-run reports strict-zero (`index-audit-fresh.out`).
