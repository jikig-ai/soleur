#!/usr/bin/env bash
# usage: extract-monitor-facts.sh <run_id> <job_id>   -> one TSV line of facts, raw log kept under /var/tmp/item-i/mon-logs
# Facts (tab-separated): run_id, nested_runner_in_tests_step(N|-), nested_P, nested_killed_ms, infra_N, infra_P, infra_breakdown, infra_RED_count, infra_RED_names
set -uo pipefail
OUT="${OUT:-/var/tmp/item-i}"; REPO="${REPO:-jikig-ai/soleur}"; rid="$1"; jid="$2"; f=$OUT/mon-logs/$jid.log
[[ -s $f ]] || gh api --allow-escape-sequences "repos/$REPO/actions/jobs/$jid/logs" > "$f" 2>/dev/null
[[ -s $f ]] || { printf '%s\tNOLOG\n' "$rid"; exit 0; }
# split at the infra step: its env dump contains the literal line "TEST_GROUP: infra"
split=$(grep -n -m1 'TEST_GROUP: infra$' "$f" | cut -d: -f1); [[ -n "$split" ]] || split=999999999
tests_part=$(sed -n "1,$((split-1))p" "$f"); infra_part=$(sed -n "$((split)),\$p" "$f")
tl=$(grep -m1 -oE 'Running [0-9]+ registered infra suite\(s\) (\(shard [^)]*\) )?with -P [0-9]+' <<<"$tests_part" || true)
tN=$(grep -oE '[0-9]+' <<<"$tl" | head -1); tP=$(grep -oE 'with -P [0-9]+' <<<"$tl" | grep -oE '[0-9]+')
tk=$(grep -m1 -oE '\[KILLED\] apps/web-platform/infra/run-registered-suites.sh \(exit=[0-9]+, [^,]*, [0-9]+ms' <<<"$tests_part" | grep -oE '[0-9]+ms' || true)
il=$(grep -m1 -oE 'Running [0-9]+ registered infra suite\(s\) (\(shard [^)]*\) )?with -P [0-9]+' <<<"$infra_part" || true)
iN=$(grep -oE '[0-9]+' <<<"$il" | head -1); iP=$(grep -oE 'with -P [0-9]+' <<<"$il" | grep -oE '[0-9]+')
ib=$(grep -m1 -oE 'registered infra suites: [0-9]+ passed, [0-9]+ failed, [0-9]+ unaccounted' <<<"$infra_part" | sed 's/registered infra suites: //' || true)
reds=$(grep -oE '^[0-9TZ:.-]+ +RED  apps/web-platform/infra/[^ ]+' <<<"$infra_part" | sed -E 's|.*RED  apps/web-platform/infra/||' | sort -u)
nr=$(grep -c . <<<"$reds" || true); [[ -z "$reds" ]] && nr=0
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rid" "${tN:--}" "${tP:--}" "${tk:--}" "${iN:--}" "${iP:--}" "${ib:--}" "$nr" "$(tr '\n' ',' <<<"$reds")"
