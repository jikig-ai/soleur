#!/usr/bin/env bash
# ci-leg-balance-9232.sh — post-merge leg-balance soak probe for #9232.
#
# Measures the thing the issue actually demands: the per-LEG suite-time totals
# of the `test-scripts` matrix legs on green main-branch ci.yml runs after the
# duration-aware manifest landed. The metric is summed `suite-timings.tsv` per
# leg (the quantity the committed manifest controls), not job wall-clock —
# runner-acquisition wait and setup noise would mask the packing signal.
#
# A run is QUALIFYING only when every one of the expected light legs uploaded
# its `suite-timings-scripts-<k>` artifact (expected N is read from the
# committed manifest's `# n=` header, so the probe survives a K change). A run
# missing a leg contributes nothing to the sample — that asymmetry is
# fail-safe: it delays a PASS, never fabricates one.
#
# Balance verdict per qualifying run: every leg's suite-time total must be
# within ~2x of the run's mean leg total, EXCLUDING any leg whose largest
# single suite alone exceeds the mean — the issue's mega-suite carve-out
# (precedent: lint-orphan-test-suites-mutations at ~589s on a leg by itself
# cannot be split by any K).
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS              (>=3 qualifying post-cutoff runs, every leg within
#                          ~2x mean after the mega-suite carve-out; sweeper
#                          closes #9232)
#   1 = FAIL              (a qualifying run carried a breaching leg; sweeper
#                          comments, leaves open)
#   2 = NOT YET           (<3 qualifying runs; cutoff unset/unparseable;
#                          GH_TOKEN/gh/jq/python3 missing. NOT exit 0: an
#                          unmet precondition must not auto-close #9232)
#   3 = CANNOT ESTABLISH  (gh API failures or an unreadable committed
#                          manifest; sweeper comments, retries)
#   78 = xtrace refusal while GH_TOKEN is set (#7797)
#
# Required env: GH_TOKEN (needs actions:read — the sweeper forwards the
# repo's GITHUB_TOKEN under `secrets=GH_TOKEN`). Clock: SOLEUR_FT_EARLIEST
# (forwarded from the directive's `earliest=`) — required; pre-merge runs
# predate the new manifest and are stale data, not a small sample.
#
# `gh api` calls embed query params in the URL and never pass -f: -f flips
# the request to POST, and the runs-list endpoint 404s on POST. Measured
# 2026-09-29 on a fine-grained token.
#
# RETIREMENT: one-shot soak probe. When #9232 closes, delete this file, its
# .test.sh, and the `run_suite` line in scripts/test-all.sh.
set -uo pipefail

# XTRACE REFUSAL (#7797). This probe binds GH_TOKEN, and shell tracing echoes
# a command AFTER expansion -- under `bash -x` the credential reaches the
# transcript at the moment it is bound. Refuse to run traced while a
# credential is present.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
WORKFLOW="ci.yml"
MIN_RUNS=3      # #9232's ">=3 most recent qualifying post-merge green runs"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../suite-shard-legs.tsv"

[ -n "${GH_TOKEN:-}" ] || { echo "NOT YET: GH_TOKEN not set (secrets= clause)" >&2; exit 2; }
command -v gh      >/dev/null || { echo "NOT YET: gh not on PATH" >&2; exit 2; }
command -v jq      >/dev/null || { echo "NOT YET: jq not on PATH" >&2; exit 2; }
command -v python3 >/dev/null || { echo "NOT YET: python3 not on PATH" >&2; exit 2; }

# ISO-8601 -> epoch. GNU `date -d` first, BSD/macOS `date -j -f` fallback.
iso_epoch() {
  date -u -d "$1" +%s 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}

CUTOFF="${SOLEUR_FT_EARLIEST:-}"
if [ -z "$CUTOFF" ]; then
  echo "NOT YET: no cutoff clock — SOLEUR_FT_EARLIEST unset." >&2
  exit 2
fi
# `earliest=` is issue-body data — any member can edit it, and GNU `date -d`
# accepts natural-language single tokens (`now`, `today`, `@epoch`) that
# would silently widen the sample window toward stale pre-merge runs. The
# probe must not trust it at read.
if [[ ! "$CUTOFF" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "NOT YET: cutoff '$CUTOFF' is not canonical ISO-8601 UTC (YYYY-MM-DDTHH:MM:SSZ)." >&2
  exit 2
fi
CUTOFF_EPOCH="$(iso_epoch "$CUTOFF" || true)"
if [ -z "${CUTOFF_EPOCH:-}" ]; then
  echo "NOT YET: cutoff '$CUTOFF' is not a parseable ISO timestamp." >&2
  exit 2
fi

# The expected light-leg count is read from the committed manifest's `# n=`
# header — the same source the runner reads — never hardcoded, so a future
# K change does not silently redefine "qualifying".
EXPECTED="$(grep -m1 '^# n=' "$MANIFEST" 2>/dev/null | sed 's/^# n=//' || true)"
if [[ ! "$EXPECTED" =~ ^[0-9]+$ ]] || (( 10#$EXPECTED < 1 )); then
  echo "CANNOT ESTABLISH: cannot read '# n=<int>' from $MANIFEST — the committed manifest the probe balances against is missing or malformed." >&2
  exit 3
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Completed push runs on main, newest first. `created_at` is what the issue
# timestamps describe; compare epochs, not strings.
RUNS="$(gh api "repos/$REPO/actions/workflows/$WORKFLOW/runs?branch=main&event=push&status=completed&per_page=30" \
        --jq '.workflow_runs[] | select(.conclusion == "success") | [.id, .created_at] | @tsv')" \
  || { echo "CANNOT ESTABLISH: gh api runs list failed" >&2; exit 3; }

examined=0; qualifying=0; breached=0
while IFS=$'\t' read -r id created; do
  [ -n "$id" ] || continue
  created_epoch="$(iso_epoch "$created" || true)"
  [ -n "${created_epoch:-}" ] || continue
  [ "$created_epoch" -le "$CUTOFF_EPOCH" ] && continue
  examined=$((examined + 1))

  # This run's light-leg timing artifacts. Only runs where EVERY leg uploaded
  # qualify — a leg that died before its feed write leaves its suites
  # unmeasured, and summing a partial set manufactures a false lopsided read.
  ARTS="$(gh api "repos/$REPO/actions/runs/$id/artifacts?per_page=100" \
          --jq '[.artifacts[] | select(.name | test("^suite-timings-scripts-[0-9]+$")) | {id: .id, name: .name}]')" \
    || { echo "CANNOT ESTABLISH: artifacts list for run $id unreadable" >&2; exit 3; }
  narts="$(printf '%s' "$ARTS" | jq 'length')"
  [ "$narts" -eq "$EXPECTED" ] || continue

  mkdir -p "$WORK/$id" || { echo "CANNOT ESTABLISH: scratch dir" >&2; exit 3; }
  dl_ok=1
  while IFS= read -r aj; do
    [ -n "$aj" ] || continue
    aid="$(printf '%s' "$aj" | jq -r '.id')"
    aname="$(printf '%s' "$aj" | jq -r '.name')"
    # Binary payload — no --jq, straight to disk.
    gh api "repos/$REPO/actions/artifacts/$aid/zip" > "$WORK/$id/$aname.zip" 2>/dev/null \
      || { dl_ok=0; break; }
  done < <(printf '%s' "$ARTS" | jq -c '.[]')
  if [ "$dl_ok" != 1 ]; then
    echo "CANNOT ESTABLISH: artifact download failed for run $id" >&2
    exit 3
  fi

  # Sum per-leg suite ms (same exclusion rules as the generator: boundary
  # rows, skip=, and FAIL/KILLED/TRIPWIRE partials carry no weight) and grade
  # the balance. One python3 invocation per run — python3 is already the
  # regen prerequisite.
  verdict="$(python3 - "$WORK/$id" <<'PY'
import glob, sys, zipfile

d = sys.argv[1]
totals = {}   # leg -> summed suite ms
maxes = {}    # leg -> largest single-suite ms
for zp in sorted(glob.glob(d + "/*.zip")):
    # Artifact names are job-index (0-based); print 1-based leg numbers so the
    # report reads like the matrix names (`test-scripts (k/N)`).
    leg = zp.rsplit("-", 1)[-1].split(".")[0]
    leg = int(leg) + 1 if leg.isdigit() else None
    with zipfile.ZipFile(zp) as z:
        try:
            fh = z.open("suite-timings.tsv")
        except KeyError:
            print("CANNOT-READ")  # an artifact without the tsv is a shape break
            sys.exit(0)
        with fh:
            for raw in fh.read().decode("utf-8").splitlines():
                f = raw.split("\t")
                if len(f) < 2 or f[0].startswith("__run_boundary"):
                    continue
                verdict = f[2] if len(f) > 2 else ""
                if verdict.startswith("skip=") or verdict in ("FAIL", "KILLED", "TRIPWIRE"):
                    continue
                if not f[1].isdigit():
                    continue
                ms = int(f[1])
                totals[leg] = totals.get(leg, 0) + ms
                maxes[leg] = max(maxes.get(leg, 0), ms)
if not totals:
    print("EMPTY")
else:
    mean = sum(totals.values()) / len(totals)
    for leg in sorted(totals):
        print(f"leg {leg}: {totals[leg]}ms (max-suite {maxes[leg]}ms)")
    bad = [k for k, v in totals.items()
           if v > 2 * mean and maxes.get(k, 0) <= mean]
    print("BREACH " + ",".join(str(k) for k in bad) if bad else "OK")
PY
)" || { echo "CANNOT ESTABLISH: timing aggregation failed for run $id" >&2; exit 3; }

  case "$(printf '%s\n' "$verdict" | tail -1)" in
    CANNOT-READ|EMPTY)
      echo "CANNOT ESTABLISH: run $id's artifacts are not suite-timings shape" >&2
      exit 3 ;;
  esac

  qualifying=$((qualifying + 1))
  if [ "$(printf '%s\n' "$verdict" | tail -1)" != "OK" ]; then
    breached=$((breached + 1))
    printf 'run %s: BREACH — %s\n' "$id" "$(printf '%s\n' "$verdict" | tail -1)" >&2
    printf '%s\n' "$verdict" | sed 's/^/  /' >&2
  else
    printf 'run %s: balanced\n%s\n' "$id" "$(printf '%s\n' "$verdict" | sed 's/^/  /')"
  fi
  [ "$qualifying" -ge "$MIN_RUNS" ] && break
done <<< "$RUNS"

if [ "$qualifying" -lt "$MIN_RUNS" ]; then
  echo "NOT YET: only $qualifying qualifying post-cutoff green run(s) "
  echo "  (need $MIN_RUNS; examined $examined). A non-qualifying run is one"
  echo "  missing any of the $EXPECTED light-leg timing artifacts."
  exit 2
fi

if [ "$breached" -gt 0 ]; then
  echo "FAIL: $breached of $qualifying qualifying run(s) carried a leg over ~2x"
  echo "  the mean suite-time total (mega-suite carve-out applied)."
  exit 1
fi

echo "PASS: $qualifying qualifying post-cutoff run(s), every light leg within"
echo "  ~2x of the mean suite-time total (mega-suite carve-out applied)."
exit 0
