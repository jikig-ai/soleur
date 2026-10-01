#!/usr/bin/env bash
# affected-prepass-bench.sh — selection-identity and CPU bench for the affected pre-pass (#9307).
#
# PURPOSE. The pre-pass (`test-all.sh --print-selection`) decides which suites a diff selects.
# Any change to its derive must leave that decision BYTE-IDENTICAL; a cheaper walk that changes
# selection is a regression, not an optimisation. This tool runs the same probe against a BASE
# revision and a HEAD (a revision or the working tree), compares the two AFFECTED_SELECTED streams
# row by row, and times both sides interleaved so they see the same load.
#
# OPERATOR-ONLY. It checks out trusted revisions of this repository into a scratch worktree and
# runs the runner found there; it is not a CI gate. A full run is about 35 CPU-minutes.
#
# Usage:
#   affected-prepass-bench.sh [--base <rev>] [--head <rev>] [--probe <a,b,...>] [--runs N]
#                             [--base-runner <path>] [--head-runner <path>] [--report-diff] [--json]
#   affected-prepass-bench.sh --compare-only <base-stream> <head-stream> [--added <label,label>]
#
#   --base <rev>        default: merge-base of HEAD and origin/main. After the change under test
#                       merges that equals HEAD and the run exits 3 asking for an explicit --base.
#   --head <rev>        default: the working tree.
#   --probe <paths>     comma-separated diff paths to select against; repeatable. Default: two
#                       probes, README.md and a multi-path probe that selects edge suites.
#   --runs N            timing repeats per side, interleaved base/head/base/head (head default 5,
#                       base default 2; N overrides the head count and caps base at N).
#   --base-runner / --head-runner <path>
#                       run that script instead of a worktree's scripts/test-all.sh (the suite
#                       drives fake runners through the full dispatch path with these).
#   --compare-only a b  pure compare of two saved streams; runs nothing.
#   --added <labels>    labels the head stream legitimately adds over the base (registrations the
#                       change under test introduces). Default in a full run: the difference of the
#                       two sides' `--enumerate-commands all` label sets.
#   --added-edges <paths>
#                       paths whose anchored edge (`^path`) the head rows may carry over the base rows,
#                       because the change under test ADDED those files (a suite whose closure reaches
#                       the runner sees the runner's text, which now names the new registration's file).
#                       Default in a full run: the files added between base and head (`git diff
#                       --diff-filter=A`). They are removed from the head row before the byte compare.
#   --report-diff       list differing rows (the first one is always printed).
#   --json              one machine-readable result line at the end.
#
# Exit: 0 identical, 1 differs (or a side failed), 2 usage, 3 base and head are the same tree.
#
# IDENTITY CONTRACT. Every row whose label exists in the base stream must appear byte-for-byte in
# the head stream, in the same order. Rows the head adds must equal the added-label list. The head
# AFFECTED_SUMMARY must equal the base summary adjusted by the added rows. Anti-vacuity: both sides
# exit 0, each stream ends in an AFFECTED_SUMMARY with fallback=none whose of= equals its row
# count, and the child runs under `env -u CI -u SOLEUR_TEST_FORCE_ALL` (either makes every
# selected bit 1, which would make two broken streams agree).

set -uo pipefail

BASE_REV=""
HEAD_REV=""
RUNS=""
BASE_RUNNER=""
HEAD_RUNNER=""
COMPARE_A=""
COMPARE_B=""
ADDED=""
ADDED_EDGES=""
ADDED_EDGES_SET=0
REPORT_DIFF=0
JSON=0
PROBES=()

die_usage() { echo "affected-prepass-bench: $*" >&2; exit 2; }

while (( $# > 0 )); do
  case "$1" in
    --base) [[ $# -ge 2 ]] || die_usage "--base needs a revision"; BASE_REV="$2"; shift 2 ;;
    --head) [[ $# -ge 2 ]] || die_usage "--head needs a revision"; HEAD_REV="$2"; shift 2 ;;
    --probe) [[ $# -ge 2 ]] || die_usage "--probe needs a path list"; PROBES+=("$2"); shift 2 ;;
    --runs) [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || die_usage "--runs needs a positive integer"; RUNS="$2"; shift 2 ;;
    --base-runner) [[ $# -ge 2 ]] || die_usage "--base-runner needs a path"; BASE_RUNNER="$2"; shift 2 ;;
    --head-runner) [[ $# -ge 2 ]] || die_usage "--head-runner needs a path"; HEAD_RUNNER="$2"; shift 2 ;;
    --compare-only) [[ $# -ge 3 ]] || die_usage "--compare-only needs two stream files"; COMPARE_A="$2"; COMPARE_B="$3"; shift 3 ;;
    --added) [[ $# -ge 2 ]] || die_usage "--added needs a label list"; ADDED="$2"; shift 2 ;;
    --added-edges) [[ $# -ge 2 ]] || die_usage "--added-edges needs a path list"; ADDED_EDGES="$2"; ADDED_EDGES_SET=1; shift 2 ;;
    --report-diff) REPORT_DIFF=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

# Pure compare of two saved streams. Prints a verdict (and differing rows with --report-diff) on
# stdout; exit 0 identical, 1 differs. Python, not awk: byte-exact line handling and a real set type.
compare_streams() {
  BENCH_ADDED="$3" BENCH_ADDED_EDGES="${4-}" BENCH_REPORT="$REPORT_DIFF" python3 - "$1" "$2" <<'PY'
import os, sys

def read(path):
    with open(path, "rb") as f:
        data = f.read()
    return data.decode("utf-8", "surrogateescape").split("\n")

def parse(lines):
    rows, summary, other = [], None, 0
    for ln in lines:
        if ln.startswith("AFFECTED_SELECTED\t"):
            rows.append(ln)
        elif ln.startswith("AFFECTED_SUMMARY"):
            summary = ln
        elif ln:
            other += 1
    return rows, summary, other

def fields(summary):
    out = {}
    for tok in summary.split()[1:]:
        k, _, v = tok.partition("=")
        out[k] = v
    return out

a_path, b_path = sys.argv[1], sys.argv[2]
added = [x for x in os.environ.get("BENCH_ADDED", "").split(",") if x]
allowed_edges = {"^" + x for x in os.environ.get("BENCH_ADDED_EDGES", "").split(",") if x}
report = os.environ.get("BENCH_REPORT") == "1"
a_rows, a_sum, _ = parse(read(a_path))
b_rows, b_sum, _ = parse(read(b_path))
problems = []

def need_summary(name, rows, summ):
    if summ is None:
        problems.append(f"{name}: no AFFECTED_SUMMARY (stream truncated or runner crashed)")
        return None
    f = fields(summ)
    if f.get("fallback") != "none":
        problems.append(f"{name}: degraded run ({summ})")
    if f.get("of") != str(len(rows)):
        problems.append(f"{name}: summary of={f.get('of')} but {len(rows)} AFFECTED_SELECTED rows")
    return f

fa = need_summary("base", a_rows, a_sum)
fb = need_summary("head", b_rows, b_sum)
if not a_rows or not b_rows:
    problems.append("an empty stream cannot be compared (zero rows)")

if not problems:
    label = lambda r: r.split("\t")[1]
    a_labels = [label(r) for r in a_rows]
    a_set = set(a_labels)
    b_extra = [r for r in b_rows if label(r) not in a_set]
    b_common = [r for r in b_rows if label(r) in a_set]
    if sorted(label(r) for r in b_extra) != sorted(added):
        problems.append("head adds labels %r, expected %r" % (sorted(label(r) for r in b_extra), sorted(added)))
    if len(b_common) != len(a_rows):
        gone = a_set - {label(r) for r in b_common}
        problems.append("head drops %d base row(s): %s" % (len(gone), ", ".join(sorted(gone)[:5])))
    def strip_allowed(row):
        # Remove the edges that exist only because the change added a file; nothing else is touched.
        if not allowed_edges:
            return row
        f = row.split("\t")
        if len(f) >= 5:
            f[4] = "|".join(e for e in f[4].split("|") if e not in allowed_edges)
        return "\t".join(f)
    diffs = [(x, y) for x, y in zip(a_rows, b_common) if x != strip_allowed(y)]
    if diffs:
        problems.append("%d row(s) differ byte-for-byte" % len(diffs))
        shown = diffs if report else diffs[:1]
        for x, y in shown:
            print("  base: " + x[:400].replace("\t", " | "))
            print("  head: " + y[:400].replace("\t", " | "))
            xe, ye = set(x.split("\t")[4].split("|")), set(strip_allowed(y).split("\t")[4].split("|"))
            print("  only in base: %s" % sorted(xe - ye)[:5])
            print("  only in head: %s" % sorted(ye - xe)[:5])
    # Summary arithmetic: head == base adjusted by the added rows.
    exp = dict(fa)
    exp["of"] = str(int(fa["of"]) + len(b_extra))
    sel = sum(1 for r in b_extra if r.split("\t")[2] == "1")
    exp["selected"] = str(int(fa["selected"]) + sel)
    for cls, key in (("always_on", "always_on"),):
        exp[key] = str(int(fa[key]) + sum(1 for r in b_extra if r.split("\t")[2] == "1" and r.split("\t")[3] == cls))
    exp["edge"] = str(int(fa["edge"]) + sum(1 for r in b_extra if r.split("\t")[2] == "1" and r.split("\t")[3].startswith("edge:")))
    if exp != fb:
        problems.append("head summary %r != base summary adjusted by the added rows %r" % (fb, exp))

if problems:
    for p in problems:
        print("DIFFERS: " + p)
    sys.exit(1)
print("IDENTICAL: %d base rows byte-for-byte, %d added row(s)" % (len(a_rows), len(b_extra)))
PY
}

if [[ -n "$COMPARE_A" ]]; then
  [[ -r "$COMPARE_A" && -r "$COMPARE_B" ]] || die_usage "--compare-only: both files must be readable"
  compare_streams "$COMPARE_A" "$COMPARE_B" "$ADDED" "$ADDED_EDGES"
  exit $?
fi

# ---- full run --------------------------------------------------------------------------------

# Never inherit lefthook's git environment: GIT_DIR beats cwd and beats `git -C`.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die_usage "not inside a git work tree"
if (( ${#PROBES[@]} == 0 )); then
  PROBES=("README.md" "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh,knowledge-base/legal/article-30-register.md")
fi
for p in "${PROBES[@]}"; do
  [[ "$p" =~ ^[^[:space:]]+$ ]] || die_usage "--probe must not contain whitespace other than commas: '$p'"
done
HEAD_RUNS="${RUNS:-5}"
BASE_RUNS="${RUNS:-2}"; (( BASE_RUNS > 2 )) && BASE_RUNS=2

SCRATCH="$(mktemp -d "${TMPDIR:-/var/tmp}/prepass-bench.XXXXXXXX")" || exit 2
WT_PATHS=()
cleanup() {
  local w
  for w in ${WT_PATHS[@]+"${WT_PATHS[@]}"}; do
    git -C "$REPO_ROOT" worktree remove --force "$w" >/dev/null 2>&1 || true
  done
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

resolve_rev() {
  git -C "$REPO_ROOT" rev-parse --verify --end-of-options "$1^{commit}" 2>/dev/null
}

# A side is a directory holding scripts/test-all.sh, or a runner path run from the repo root.
make_side() {
  local name="$1" rev="$2" runner="$3" dir
  if [[ -n "$runner" ]]; then
    [[ -f "$runner" ]] || die_usage "--${name}-runner: no such file: $runner"
    SIDE_DIR="$REPO_ROOT"; SIDE_RUNNER="$runner"; SIDE_ID="runner:$(cd "$(dirname "$runner")" && pwd)/$(basename "$runner")"
    return 0
  fi
  if [[ -z "$rev" ]]; then
    SIDE_DIR="$REPO_ROOT"; SIDE_RUNNER="scripts/test-all.sh"; SIDE_ID="tree:$(git -C "$REPO_ROOT" rev-parse HEAD)+worktree"
    return 0
  fi
  local sha; sha="$(resolve_rev "$rev")" || die_usage "cannot resolve revision: $rev"
  dir="$SCRATCH/$name"
  git -C "$REPO_ROOT" worktree add --detach "$dir" "$sha" >/dev/null 2>&1 || die_usage "git worktree add failed for $rev"
  WT_PATHS+=("$dir")
  SIDE_DIR="$dir"; SIDE_RUNNER="scripts/test-all.sh"; SIDE_ID="rev:$sha"
}

if [[ -z "$BASE_REV" && -z "$BASE_RUNNER" ]]; then
  BASE_REV="$(git -C "$REPO_ROOT" merge-base HEAD origin/main 2>/dev/null)" || die_usage "no merge-base with origin/main; pass --base"
fi
make_side base "$BASE_REV" "$BASE_RUNNER"; B_DIR="$SIDE_DIR"; B_RUNNER="$SIDE_RUNNER"; B_ID="$SIDE_ID"
make_side head "$HEAD_REV" "$HEAD_RUNNER"; H_DIR="$SIDE_DIR"; H_RUNNER="$SIDE_RUNNER"; H_ID="$SIDE_ID"

if [[ "$B_ID" == "$H_ID" ]]; then
  echo "affected-prepass-bench: base and head are the same tree ($B_ID); nothing to compare. Pass --base <rev>" >&2
  exit 3
fi
if [[ "$B_ID" == rev:* && "$H_ID" == tree:* ]]; then
  # The head is the working tree: if the base commit IS the current HEAD and the tree is clean the
  # two sides are the same code (the post-merge default). A dirty tree is a real comparison.
  if [[ "${B_ID#rev:}" == "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]] \
     && [[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    echo "affected-prepass-bench: base is the current HEAD and the tree is clean; pass --base <earlier rev>" >&2
    exit 3
  fi
fi

# run_timed <dir> <out> <err> <cmd...> -> "wall user sys rc" on stdout (rusage of the reaped tree).
run_timed() {
  python3 - "$@" <<'PY'
import os, resource, subprocess, sys, time
cwd, out, err = sys.argv[1:4]
cmd = sys.argv[4:]
env = {k: v for k, v in os.environ.items() if k not in ("CI", "SOLEUR_TEST_FORCE_ALL")}
r0 = resource.getrusage(resource.RUSAGE_CHILDREN); t0 = time.monotonic()
with open(out, "wb") as o, open(err, "wb") as e:
    rc = subprocess.run(cmd, cwd=cwd, stdout=o, stderr=e, stdin=subprocess.DEVNULL, env=env).returncode
t1 = time.monotonic(); r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
print("%.1f %.1f %.1f %d" % (t1 - t0, r1.ru_utime - r0.ru_utime, r1.ru_stime - r0.ru_stime, rc))
PY
}

load1() { cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "?"; }

stats() { # stats <list of numbers> -> "min median"
  printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END{ if(NR==0){print "? ?"; exit} m=(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2; printf "%.1f %.1f\n", a[1], m }'
}

enum_labels() { # enum_labels <dir> <runner> -> one label per SUITE_COMMAND record (duplicates kept)
  ( cd "$1" && env -u CI -u SOLEUR_TEST_FORCE_ALL bash "$2" --enumerate-commands all 2>/dev/null ) \
    | awk -F'\t' '$1=="SUITE_COMMAND"{print $2}'
}

if [[ -z "$ADDED" ]]; then
  b_lab="$SCRATCH/labels.base"; h_lab="$SCRATCH/labels.head"
  enum_labels "$B_DIR" "$B_RUNNER" > "$b_lab"
  enum_labels "$H_DIR" "$H_RUNNER" > "$h_lab"
  ADDED="$(sort -u "$h_lab" | comm -13 <(sort -u "$b_lab") - | paste -sd, -)"
  # of= counts registrations (records), not distinct labels: a label registered twice counts twice.
  ENUM_BASE_N="$(wc -l < "$b_lab" | tr -d ' ')"
else
  ENUM_BASE_N=""
fi
if (( ADDED_EDGES_SET == 0 )) && [[ "$B_ID" == rev:* ]]; then
  _h_rev="${H_ID#rev:}"; [[ "$H_ID" == rev:* ]] || _h_rev="HEAD"
  ADDED_EDGES="$(git -C "$REPO_ROOT" diff --diff-filter=A --name-only "${B_ID#rev:}" "$_h_rev" 2>/dev/null | paste -sd, -)"
fi

OVERALL=0
JSON_OUT=""
BASH_V="${BASH_VERSION}"
PATSUB="$(shopt patsub_replacement 2>/dev/null | awk '{print $2}')"; PATSUB="${PATSUB:-n/a}"
LOCALE="${LC_ALL:-${LANG:-unset}}"

probe_i=0
for probe in "${PROBES[@]}"; do
  probe_i=$((probe_i + 1))
  b_cpu=(); b_wall=(); h_cpu=(); h_wall=()
  load_start="$(load1)"
  n=$HEAD_RUNS; (( BASE_RUNS > n )) && n=$BASE_RUNS
  side_failed=""
  for (( i=1; i<=n; i++ )); do
    if (( i <= BASE_RUNS )); then
      read -r w u s rc < <(run_timed "$B_DIR" "$SCRATCH/b$probe_i.$i.out" "$SCRATCH/b$probe_i.$i.err" bash "$B_RUNNER" --print-selection "--paths=$probe")
      [[ "$rc" == "0" ]] || side_failed="base run $i exited rc=$rc"
      b_wall+=("$w"); b_cpu+=("$(awk -v u="$u" -v s="$s" 'BEGIN{printf "%.1f", u+s}')")
    fi
    if (( i <= HEAD_RUNS )); then
      read -r w u s rc < <(run_timed "$H_DIR" "$SCRATCH/h$probe_i.$i.out" "$SCRATCH/h$probe_i.$i.err" bash "$H_RUNNER" --print-selection "--paths=$probe")
      [[ "$rc" == "0" ]] || side_failed="head run $i exited rc=$rc"
      h_wall+=("$w"); h_cpu+=("$(awk -v u="$u" -v s="$s" 'BEGIN{printf "%.1f", u+s}')")
    fi
  done
  load_end="$(load1)"
  echo "== probe $probe_i: $probe"
  if [[ -n "$side_failed" ]]; then
    echo "DIFFERS: $side_failed (both sides must exit 0)"; OVERALL=1; continue
  fi
  verdict="$(compare_streams "$SCRATCH/b$probe_i.1.out" "$SCRATCH/h$probe_i.1.out" "$ADDED" "$ADDED_EDGES")"; vrc=$?
  printf '%s\n' "$verdict"
  (( vrc == 0 )) || OVERALL=1
  if [[ -n "$ENUM_BASE_N" ]]; then
    # Enumerate against the SAME paths as the probe: relevance-gated registrations are declined (or not) by
    # the named paths, so the count the summary's of= must equal depends on the probe.
    probe_n="$( ( cd "$B_DIR" && env -u CI -u SOLEUR_TEST_FORCE_ALL bash "$B_RUNNER" --enumerate-commands "--paths=$probe" all 2>/dev/null ) | awk -F'\t' '$1=="SUITE_COMMAND"' | wc -l | tr -d ' ')"
    base_of="$(sed -n 's/^AFFECTED_SUMMARY .*of=\([0-9][0-9]*\) .*/\1/p' "$SCRATCH/b$probe_i.1.out" | tail -1)"
    [[ "$base_of" == "$probe_n" ]] || { echo "DIFFERS: base summary of=$base_of but --enumerate-commands --paths=$probe lists $probe_n registrations"; OVERALL=1; }
  fi
  # Later repeats must equal the first of their own side (determinism), checked with cmp.
  for (( i=2; i<=BASE_RUNS; i++ )); do cmp -s "$SCRATCH/b$probe_i.1.out" "$SCRATCH/b$probe_i.$i.out" || { echo "DIFFERS: base run $i differs from base run 1 (non-deterministic)"; OVERALL=1; }; done
  for (( i=2; i<=HEAD_RUNS; i++ )); do cmp -s "$SCRATCH/h$probe_i.1.out" "$SCRATCH/h$probe_i.$i.out" || { echo "DIFFERS: head run $i differs from head run 1 (non-deterministic)"; OVERALL=1; }; done
  read -r bmin bmed < <(stats "${b_cpu[@]}"); read -r hmin hmed < <(stats "${h_cpu[@]}")
  read -r bwmin bwmed < <(stats "${b_wall[@]}"); read -r hwmin hwmed < <(stats "${h_wall[@]}")
  fmin="$(awk -v a="$bmin" -v b="$hmin" 'BEGIN{ if (b>0) printf "%.1f", a/b; else print "?" }')"
  fmed="$(awk -v a="$bmed" -v b="$hmed" 'BEGIN{ if (b>0) printf "%.1f", a/b; else print "?" }')"
  echo "  CPU user+sys  base min/median ${bmin}/${bmed} s   head min/median ${hmin}/${hmed} s   factor min ${fmin}x median ${fmed}x"
  echo "  wall          base min/median ${bwmin}/${bwmed} s   head min/median ${hwmin}/${hwmed} s"
  echo "  load1 ${load_start} -> ${load_end}; locale ${LOCALE}; bash ${BASH_V}; patsub_replacement ${PATSUB}; runs base=${#b_cpu[@]} head=${#h_cpu[@]}"
  vword="identical"; (( vrc == 0 )) || vword="DIFFERENT"
  echo "  plain: an affected run waited about ${bmed} s of CPU on selection and now waits about ${hmed} s (${fmed}x), selection ${vword}."
  JSON_OUT+="{\"probe\":\"$probe\",\"identical\":$([[ $vrc == 0 ]] && echo true || echo false),\"base_cpu_min\":$bmin,\"base_cpu_med\":$bmed,\"head_cpu_min\":$hmin,\"head_cpu_med\":$hmed,\"factor_med\":\"$fmed\",\"load\":\"${load_start}->${load_end}\"},"
done

# Class-only surface (--print-affected-set): it takes the print-mode early-out in classify, so it is
# a cheap surface check for the derive levers, not a derive surface. Rows for registrations the
# head adds are dropped from both before a byte compare.
( cd "$B_DIR" && env -u CI -u SOLEUR_TEST_FORCE_ALL bash "$B_RUNNER" --print-affected-set ) > "$SCRATCH/c.base" 2>/dev/null; brc=$?
( cd "$H_DIR" && env -u CI -u SOLEUR_TEST_FORCE_ALL bash "$H_RUNNER" --print-affected-set ) > "$SCRATCH/c.head" 2>/dev/null; hrc=$?
if [[ "$brc" != "0" || "$hrc" != "0" ]]; then
  echo "DIFFERS: --print-affected-set exited base=$brc head=$hrc"; OVERALL=1
else
  awk -F'\t' -v added="$ADDED" 'BEGIN{n=split(added,a,","); for(i=1;i<=n;i++) if(a[i]!="") skip[a[i]]=1} !($2 in skip)' "$SCRATCH/c.head" > "$SCRATCH/c.head.f"
  if [[ -s "$SCRATCH/c.base" ]] && cmp -s "$SCRATCH/c.base" "$SCRATCH/c.head.f"; then
    echo "== class-only stream (--print-affected-set): IDENTICAL ($(wc -l < "$SCRATCH/c.base" | tr -d ' ') lines)"
  else
    echo "DIFFERS: --print-affected-set stream (empty or differs after dropping added labels)"; OVERALL=1
  fi
fi

if (( JSON == 1 )); then
  printf '{"base":"%s","head":"%s","bash":"%s","locale":"%s","probes":[%s]}\n' "$B_ID" "$H_ID" "$BASH_V" "$LOCALE" "${JSON_OUT%,}"
fi
exit "$OVERALL"
