#!/usr/bin/env bash
# Item I measurement driver (#7432). Pulls the monitor run history and the infra-validation leg
# history with `gh`, extracts verdict fields, and prints the figures via analyze.py.
# Raw data stays under $ITEM_I_DIR (default /var/tmp/item-i, never /tmp); only a compact
# evidence file is committed. Re-run: bash run-all.sh   (needs gh auth, jq, python3; ~10 min)
# Usage: ITEM_I_DIR=/var/tmp/item-i-rerun bash run-all.sh
set -uo pipefail
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
export OUT="${ITEM_I_DIR:-/var/tmp/item-i}"
assert_fixture_dir "$OUT"
REPO="${ITEM_I_REPO:-jikig-ai/soleur}"; export REPO
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINDOW_START="${ITEM_I_LEG_START:-2026-09-25T00:00:00Z}"   # sharded deploy-script-tests legs landed (#8763)
rm -f "$OUT/leg-fetch-failures.txt" "$OUT"/ann/*.tsv "$OUT"/to/*.tsv   # a run that left the --limit window must not linger in the totals
mkdir -p "$OUT/ann" "$OUT/to" "$OUT/legs" "$OUT/legs-logs" "$OUT/mon-logs"

# ---- 1. monitor history (continue-on-error pins every job conclusion to success, so the
#         verdict is the SOLEUR_MAIN_HEALTH annotation, never the conclusion) ---------------
gh run list -R "$REPO" --workflow main-health-monitor.yml --branch main --limit 300 \
  --json databaseId,conclusion,status,createdAt,event,headSha,displayTitle > "$OUT/runs.json" || exit 1

one_outcome() {
  assert_fixture_dir "$OUT"
  rid="$1"
  meta=$(jq -r --argjson r "$rid" '.[]|select(.databaseId==$r)|"\(.createdAt)\t\(.conclusion)"' "$OUT/runs.json")
  job=$(gh api "repos/$REPO/actions/runs/$rid/jobs" --jq '[.jobs[]|select(.name=="health-check")][0]|"\(.id)\t\(.started_at)\t\(.completed_at)"' 2>/dev/null)
  jid=${job%%$'\t'*}; msg=""; a=""
  if [[ -n "$jid" && "$jid" != "null" ]]; then
    a=$(gh api "repos/$REPO/check-runs/$jid/annotations?per_page=100" --jq '[.[]|{t:.title,m:.message}]' 2>/dev/null)
    msg=$(jq -r '[.[]|select(.t=="main-health-outcomes")][0].m // ""' <<<"$a")
  fi
  t=$(sed -n 's/.*tests=\([a-z_]*\).*/\1/p' <<<"$msg"); i=$(sed -n 's/.* infra=\([a-z_]*\).*/\1/p' <<<"$msg")
  te=$(sed -n 's/.*tests_elapsed_s=\([0-9]*\).*/\1/p' <<<"$msg"); ie=$(sed -n 's/.*infra_elapsed_s=\([0-9]*\).*/\1/p' <<<"$msg")
  tt=$(jq -r '[.[]|select(.m|test("action .Run test suite. has timed out"))]|length' <<<"${a:-[]}")
  it=$(jq -r '[.[]|select(.m|test("action .Run infra suites. has timed out"))]|length' <<<"${a:-[]}")
  # columns: rid created conclusion jobid started completed tests infra tests_elapsed infra_elapsed
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rid" "$meta" "$job" "${t:-ABSENT}" "${i:-ABSENT}" "${te:-}" "${ie:-}" > "$OUT/ann/$rid.tsv"
  printf '%s\t%s\t%s\n' "$rid" "${tt:-0}" "${it:-0}" > "$OUT/to/$rid.tsv"
}
export -f assert_fixture_dir one_outcome
jq -r '.[].databaseId' "$OUT/runs.json" | xargs -P 6 -I{} bash -c 'one_outcome {}'
cat "$OUT"/ann/*.tsv | sort -t$'\t' -k2 > "$OUT/outcomes.tsv"
cat "$OUT"/to/*.tsv | sort > "$OUT/timeouts.tsv"

# ---- 2. per-run log facts (infra width/size/breakdown/REDs; tests-step nested runner) -------
awk -F'\t' '$4!="" && $4!="null"{print $1" "$4}' "$OUT/outcomes.tsv" \
  | xargs -P 6 -L1 bash -c "bash '$HERE/extract-monitor-facts.sh' \$0 \$1" > "$OUT/monitor-facts.tsv"

# ---- 3. infra-validation deploy-script-tests legs on push-to-main (-P 4, hosted 4-core) ----
gh run list -R "$REPO" --workflow infra-validation.yml --event push --branch main --limit 500 \
  --json databaseId,conclusion,createdAt,headSha > "$OUT/iv-push.json" || exit 1
one_legs() {
  assert_fixture_dir "$OUT"
  # Fetch raw JSON first and retry: a transient API error body must never reach legs.tsv as data
  # (a 2026-10-16 re-run parsed a 500 "Server Error" body into three bogus rows).
  rid="$1"; raw="$OUT/legs/$rid.json"; ok=0
  for _try in 1 2 3 4; do
    if gh api "repos/$REPO/actions/runs/$rid/jobs?per_page=100" > "$raw" 2>/dev/null && jq -e '.jobs|type=="array"' "$raw" >/dev/null 2>&1; then ok=1; break; fi
    sleep 3
  done
  if [[ $ok -ne 1 ]]; then echo "LEG FETCH FAILED run $rid" >> "$OUT/leg-fetch-failures.txt"; : > "$OUT/legs/$rid.tsv"; return 0; fi
  jq -r '.jobs[]|select(.name|test("^deploy-script-tests \\("))|"\(.id)\t\(.name)\t\(.conclusion)\t\(.started_at)\t\(.completed_at)"' "$raw" | sed "s/^/$rid\t/" > "$OUT/legs/$rid.tsv"
}
export -f one_legs
jq -r --arg s "$WINDOW_START" '.[]|select(.createdAt>=$s)|.databaseId' "$OUT/iv-push.json" | xargs -P 6 -I{} bash -c 'one_legs {}'
[[ -s "$OUT/leg-fetch-failures.txt" ]] && { echo "ABORT: leg fetch failures:"; cat "$OUT/leg-fetch-failures.txt"; exit 1; }
cat "$OUT"/legs/*.tsv > "$OUT/legs.tsv"
awk -F'\t' '$4=="failure"{print $1"\t"$2}' "$OUT/legs.tsv" > "$OUT/failed-legs.tsv"
one_log() { assert_fixture_dir "$OUT"; f="$OUT/legs-logs/$2.log"; [[ -s "$f" ]] || gh api --allow-escape-sequences "repos/$REPO/actions/jobs/$2/logs" > "$f" 2>/dev/null; }
export -f one_log
xargs -P 6 -L1 bash -c 'one_log $0 $1' < "$OUT/failed-legs.tsv"
: > "$OUT/red-headers.tsv"
while IFS=$'\t' read -r rid jid; do
  f="$OUT/legs-logs/$jid.log"; d=$(jq -r --argjson r "$rid" '.[]|select(.databaseId==$r)|.createdAt[0:13]' "$OUT/iv-push.json")
  grep -oE -- '--- RED: [^ ]+ \(rc=[0-9]+ elapsed=[0-9]+s' "$f" \
    | sed -E 's|--- RED: apps/web-platform/infra/||; s/ \(rc=/ rc=/; s/ elapsed=/ el=/' | sed "s/^/$d $rid /" >> "$OUT/red-headers.tsv"
done < "$OUT/failed-legs.tsv"

# ---- 4. figures + controls ---------------------------------------------------------------------
python3 -I "$HERE/analyze.py"
