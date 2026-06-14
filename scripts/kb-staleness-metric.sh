#!/usr/bin/env bash
# kb-staleness-metric.sh — deterministic, pure-local corpus-redundancy metric.
#
# Spec:  knowledge-base/project/specs/feat-compound-consolidate/spec.md (FR1)
# Plan:  knowledge-base/project/plans/2026-06-14-feat-kb-recall-quality-prereq-plan.md
# Issue: #5298 (gates deferred consolidation pass #5292)
#
# ONE gated signal: corpus-wide near-duplicate density over
# knowledge-base/project/learnings/ (excluding **/archive/**). All-pairs
# Jaccard(title-tokens ∪ tags) >= 0.6 — NO external API, NO blocking key,
# NO git calls. Title-less files (~15% of corpus) fall back to the
# date-stripped filename slug. CLO exempt classes (compliance/,
# security-issues/, incident/PIR, frontmatter category:compliance|security-issues
# or a regulation: key) are counted in the denominator but never proposed
# as merge candidates (never appear in top_pairs / redundant_pairs).
#
# Usage:
#   bash scripts/kb-staleness-metric.sh            # write dated JSON + print summary
#   bash scripts/kb-staleness-metric.sh --json     # print JSON to stdout only
#   bash scripts/kb-staleness-metric.sh --self-test # synthesized-fixture tests (cq-test-fixtures-synthesized-only)
#
# Env hooks (mirror learning-retrieval-bench.sh):
#   LEARNINGS_ROOT  override the scanned corpus dir
#   OUTPUT_DIR      override where the dated JSON lands
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEARNINGS_ROOT="${LEARNINGS_ROOT:-$REPO_ROOT/knowledge-base/project/learnings}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/knowledge-base/project}"
JACCARD_THRESHOLD="0.6"

PYBIN="$(command -v python3 || true)"
if [[ -z "$PYBIN" ]]; then
  echo "kb-staleness-metric: python3 not found on PATH" >&2
  exit 3
fi

# ── core: emit JSON for a given learnings root ──────────────────────────────
compute_json() {
  local root="$1"
  LEARNINGS_ROOT="$root" JACCARD_THRESHOLD="$JACCARD_THRESHOLD" "$PYBIN" - <<'PY'
import os, re, json, sys

root = os.environ["LEARNINGS_ROOT"]
thr = float(os.environ["JACCARD_THRESHOLD"])

STOP = {"the","a","an","and","or","of","to","in","for","on","with","is","are",
        "be","by","at","as","from","via","not","no","when","must","this","that"}

def slug_tokens(path):
    base = os.path.basename(path)
    base = re.sub(r"\.md$", "", base)
    base = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", base)  # strip date prefix
    return [t for t in re.split(r"[^a-z0-9]+", base.lower()) if t and t not in STOP]

def parse_frontmatter(text):
    # Return dict of simple top-level scalar/inline-list keys in the first --- block.
    fm = {}
    if not text.startswith("---"):
        return fm
    end = text.find("\n---", 3)
    if end == -1:
        return fm
    block = text[3:end]
    for line in block.splitlines():
        m = re.match(r"^([a-zA-Z_]+):\s*(.*)$", line)
        if m:
            fm[m.group(1).lower()] = m.group(2).strip()
    return fm

def title_tokens(title):
    return [t for t in re.split(r"[^a-z0-9]+", title.lower()) if t and t not in STOP]

def tag_tokens(raw):
    raw = raw.strip().strip("[]")
    return [t for t in re.split(r"[^a-z0-9]+", raw.lower()) if t and t not in STOP]

files = []
for dirpath, dirnames, filenames in os.walk(root):
    if os.sep + "archive" in (dirpath + os.sep):
        continue
    for fn in filenames:
        if not fn.endswith(".md"):
            continue
        if fn.upper() in ("MEMORY.MD", "INDEX.MD"):
            continue
        files.append(os.path.join(dirpath, fn))

records = []
for path in sorted(files):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        continue
    fm = parse_frontmatter(text)
    toks = set()
    if fm.get("title"):
        toks |= set(title_tokens(fm["title"]))
    if not toks:                       # title-less fallback → filename slug
        toks |= set(slug_tokens(path))
    if fm.get("tags"):
        toks |= set(tag_tokens(fm["tags"]))
    rel = os.path.relpath(path, root)
    cat = fm.get("category", "").lower()
    exempt = (
        re.search(r"(^|/)(compliance|security-issues|incidents?)/", "/" + rel) is not None
        or cat in ("compliance", "security-issues", "incident")
        or "regulation" in fm
    )
    records.append({"rel": rel, "toks": toks, "exempt": exempt})

n = len(records)
exempt_count = sum(1 for r in records if r["exempt"])

def jaccard(a, b):
    if not a or not b:
        return 0.0
    inter = len(a & b)
    if inter == 0:
        return 0.0
    return inter / len(a | b)

pairs = []
for i in range(n):
    ri = records[i]
    for j in range(i + 1, n):
        rj = records[j]
        if ri["exempt"] or rj["exempt"]:   # exempt never a merge candidate
            continue
        s = jaccard(ri["toks"], rj["toks"])
        if s >= thr:
            pairs.append((round(s, 4), ri["rel"], rj["rel"]))

pairs.sort(reverse=True)
redundant_pairs = len(pairs)
density = round(redundant_pairs / n, 6) if n else 0.0
top = [{"a": a, "b": b, "jaccard": s} for (s, a, b) in pairs[:10]]

out = {
    "metric": "kb-redundancy",
    "corpus_count": n,
    "exempt_count": exempt_count,
    "jaccard_threshold": thr,
    "redundant_pairs": redundant_pairs,
    "density": density,
    "top_pairs": top,
}
sys.stdout.write(json.dumps(out, indent=2, sort_keys=True))
PY
}

# ── self-test (synthesized fixtures only) ───────────────────────────────────
self_test() {
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/compliance"
  # 1 & 2: positive near-dup (shared title tokens)
  printf -- '---\ntitle: Foo Bar Baz Qux\n---\nbody\n'        > "$tmp/2026-01-01-foo-bar-baz-qux.md"
  printf -- '---\ntitle: Foo Bar Baz Qux Extra\n---\nbody\n'  > "$tmp/2026-01-02-foo-bar-baz-qux-extra.md"
  # 3 & 4: near-dup whose titles DIVERGE in the first token (proves no blocking key)
  printf -- '---\ntitle: Alpha Beta Gamma Delta Echo\n---\nbody\n' > "$tmp/2026-01-03-alpha-beta-gamma-delta-echo.md"
  printf -- '---\ntitle: Zeta Beta Gamma Delta Echo\n---\nbody\n'  > "$tmp/2026-01-04-zeta-beta-gamma-delta-echo.md"
  # 5: TITLE-LESS → slug fallback dups file 1
  printf -- 'no frontmatter here\n'                            > "$tmp/2026-01-05-foo-bar-baz-qux.md"
  # 6: EXEMPT (compliance/) duplicate of file 1 — must never appear in top_pairs
  printf -- '---\ntitle: Foo Bar Baz Qux\n---\nbody\n'         > "$tmp/compliance/2026-01-06-foo-bar-baz-qux.md"

  local json; json="$(compute_json "$tmp")"
  local fail=0
  assert() { # <desc> <python-bool-expr against `d`>
    local desc="$1" expr="$2"
    if printf '%s' "$json" | "$PYBIN" -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if ($expr) else 1)"; then
      echo "  ok   - $desc"
    else
      echo "  FAIL - $desc"; fail=1
    fi
  }

  echo "self-test: kb-staleness-metric"
  assert "corpus_count == 6"  "d['corpus_count'] == 6"
  assert "exempt_count == 1"  "d['exempt_count'] == 1"
  assert "density > 0"        "d['density'] > 0"
  assert "positive pair (foo-bar-baz-qux 1&2) detected" \
    "any('foo-bar-baz-qux.md' in (p['a'],) and 'foo-bar-baz-qux-extra.md' in (p['b'],) for p in d['top_pairs']) or any({'2026-01-01-foo-bar-baz-qux.md','2026-01-02-foo-bar-baz-qux-extra.md'} == {p['a'],p['b']} for p in d['top_pairs'])"
  assert "first-token-divergent pair (alpha vs zeta) detected — no blocking key" \
    "any({'2026-01-03-alpha-beta-gamma-delta-echo.md','2026-01-04-zeta-beta-gamma-delta-echo.md'} == {p['a'],p['b']} for p in d['top_pairs'])"
  assert "title-less file (file 5) appears in a redundant pair — slug fallback" \
    "any('2026-01-05-foo-bar-baz-qux.md' in (p['a'],p['b']) for p in d['top_pairs'])"
  assert "exempt compliance file NEVER in top_pairs" \
    "all('compliance/' not in p['a'] and 'compliance/' not in p['b'] for p in d['top_pairs'])"

  if [[ "$fail" -ne 0 ]]; then echo "self-test: FAILED" >&2; return 1; fi
  echo "self-test: PASSED"
}

# ── arg dispatch ────────────────────────────────────────────────────────────
case "${1:-}" in
  --self-test) self_test ;;
  --json)      compute_json "$LEARNINGS_ROOT"; echo ;;
  --help|-h)   sed -n '2,24p' "${BASH_SOURCE[0]}" ;;
  "")
    json="$(compute_json "$LEARNINGS_ROOT")"
    today="$(date -u +%F)"
    out_file="$OUTPUT_DIR/kb-redundancy-metrics-${today}.json"
    printf '%s\n' "$json" > "$out_file"
    echo "wrote $out_file"
    printf '%s\n' "$json" | "$PYBIN" -c 'import sys,json
d=json.load(sys.stdin)
print("corpus_count={} exempt={} redundant_pairs={} density={}".format(d["corpus_count"], d["exempt_count"], d["redundant_pairs"], d["density"]))'
    ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac
