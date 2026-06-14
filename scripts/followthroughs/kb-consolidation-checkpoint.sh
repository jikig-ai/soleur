#!/usr/bin/env bash
# Follow-through verdict: KB consolidation gate checkpoint (#5298 gates #5292).
#
# Runs (on/after earliest=2026-08-13) under scripts/sweep-followthroughs.sh.
# Evaluates the AUTHORITATIVE decision rule's deterministic clause —
# corpus-wide redundancy density — from the pure-local kb-staleness-metric.sh,
# compared against the committed 2026-06-14 baseline. NO external API, NO
# secrets required (sweeper runs it under `env -i`).
#
# Spec (single source of truth):
#   knowledge-base/project/specs/feat-compound-consolidate/spec.md
#   §Re-Evaluation Criteria — clause 1 (redundancy material) is deterministic
#   and evaluated here; clause 2 (a named founder/agent outcome) is human
#   judgment and is escalated via the stay-open path below.
#
# Exit semantics (scripts/sweep-followthroughs.sh):
#   0 = PASS  → kill condition MET (redundancy NOT material): sweeper auto-closes
#               #5292 as wontfix-recommended. The corpus's problem was never bloat.
#   1 = FAIL  → redundancy IS material: build-candidate. Sweeper comments + leaves
#               #5292 OPEN for the founder to apply clause 2 (named_outcome) and
#               decide whether to build.
#   2 = *     → transient (metric/baseline unavailable): sweeper retries next sweep.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASELINE="$REPO_ROOT/knowledge-base/project/kb-redundancy-metrics-2026-06-14.json"
METRIC="$REPO_ROOT/scripts/kb-staleness-metric.sh"

ABS_THRESHOLD="0.15"   # absolute-density "clearly material" shortcut
DELTA_THRESHOLD="0.05" # +5 percentage-point growth vs baseline (trustworthy arm)

if [[ ! -f "$BASELINE" ]]; then
  echo "TRANSIENT: baseline $BASELINE missing — cannot evaluate gate."
  exit 2
fi
if [[ ! -x "$METRIC" ]]; then
  echo "TRANSIENT: metric $METRIC missing or not executable."
  exit 2
fi

current_json="$(bash "$METRIC" --json 2>/dev/null)" || { echo "TRANSIENT: metric run failed."; exit 2; }

# Pass JSON via env + quote the heredoc delimiter so adversarial learning
# filenames in the metric output cannot inject Python (the corpus is
# untrusted input to this automation). Mirrors kb-staleness-metric.sh's <<'PY'.
CURRENT_JSON="$current_json" python3 - "$BASELINE" "$ABS_THRESHOLD" "$DELTA_THRESHOLD" <<'PY'
import json, os, sys
baseline_path, abs_thr, delta_thr = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
cur = json.loads(os.environ["CURRENT_JSON"])
base = json.load(open(baseline_path))
cd, bd = cur["density"], base["density"]
delta = cd - bd
material_abs = cd >= abs_thr
material_delta = delta >= delta_thr
material = material_abs or material_delta

print("KB consolidation gate checkpoint (#5298 → #5292)")
print(f"  baseline density (2026-06-14): {bd:.4%}  ({base['redundant_pairs']} pairs / {base['corpus_count']} files)")
print(f"  current  density:              {cd:.4%}  ({cur['redundant_pairs']} pairs / {cur['corpus_count']} files)")
print(f"  delta: {delta:+.4%}   (clause-1 thresholds: abs >= {abs_thr:.0%} OR delta >= +{delta_thr:.0%})")
if cur["top_pairs"]:
    print("  top redundant pairs:")
    for p in cur["top_pairs"][:5]:
        print(f"    {p['jaccard']}  {p['a']}  <>  {p['b']}")
print()
if material:
    arm = "absolute >= 15%" if material_abs else "delta >= +5pp"
    print(f"VERDICT: BUILD-CANDIDATE — clause 1 (redundancy material) MET via {arm}.")
    print("Leaving #5292 OPEN. Founder must now apply clause 2 (set a dated named_outcome:")
    print("the concrete outcome consolidation unblocks this quarter) before building.")
    print("Both clauses must hold to build; see spec §Re-Evaluation Criteria.")
    sys.exit(1)
else:
    print("VERDICT: CLOSE-RECOMMENDED (wontfix) — clause 1 NOT met: corpus redundancy is")
    print("immaterial and did not grow past the threshold over the window. The corpus's")
    print("problem was never bloat; the consolidation pass is not justified. Auto-closing.")
    sys.exit(0)
PY
