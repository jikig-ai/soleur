#!/usr/bin/env bash
# generate-kb-index-live.test.sh — run the KB index generator against the REAL tree.
#
# WHY (#8384 review). `generate-kb-index.sh --check` used to do two jobs: assert the committed
# index was fresh (moot once #8377 untracked it) AND execute the generator over the real
# ~9,500-file knowledge-base/ inside the required `test-scripts` context. #8377 retired the
# flag as if it did one job. Every surviving automated caller is `--soft` (WARN + exit 0), and
# every other suite drives the generator over a 2-5 file synthetic fixture — so a regression
# that only manifests on real corpus content (a frontmatter shape, a filename, a collation
# edge) would have been green in CI, silent at SessionStart, and reached the operator as
# "no prior art". This is the one row that runs the generator where the bytes actually are.
#
# WRITES TO A SCRATCH DIR, NEVER THE TREE: scripts/test-all.sh treats any repo write as FATAL.
# POSITIVE FLOORS, not `-s`: a generator that emitted a header and nothing else passes an
# emptiness check. The floors are ~15% of the 2026-09-20 measurement (6,698 rows / 4,450
# tags), so they catch a collapse without false-failing on ordinary corpus churn.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

d="$(mktemp -d)" || { echo "FAIL: mktemp" >&2; exit 1; }
trap 'rm -rf -- "$d"' EXIT

if ! bash scripts/generate-kb-index.sh --out "$d" >/dev/null 2>"$d/stderr"; then
  echo "FAIL: generate-kb-index.sh exited non-zero against the real tree:" >&2
  tail -20 "$d/stderr" >&2
  exit 1
fi

n_idx=$(grep -c '^- \[' "$d/INDEX.md" 2>/dev/null || echo 0)
n_tag=$(grep -c . "$d/kb-tags.txt" 2>/dev/null || echo 0)
n_cat=$(grep -c . "$d/kb-categories.txt" 2>/dev/null || echo 0)
fail=0
[[ "$n_idx" -ge 1000 ]] || { echo "FAIL: only $n_idx index rows from the real tree (floor 1000)" >&2; fail=1; }
[[ "$n_tag" -ge 100 ]]  || { echo "FAIL: only $n_tag tags from the real tree (floor 100)" >&2; fail=1; }
[[ "$n_cat" -ge 10 ]]   || { echo "FAIL: only $n_cat categories from the real tree (floor 10)" >&2; fail=1; }
[[ "$fail" -eq 0 ]] || exit 1
echo "generate-kb-index-live: $n_idx index rows, $n_tag tags, $n_cat categories from the real tree"
