#!/usr/bin/env bash
# derive.sh <name> — figures from the stamped log
O=/var/tmp/m12013/$1; L=$O/run.log
wall=$(tail -1 "$L" | awk '{print int($1)}')
eng=$(grep -m1 '\[parallel\] mode engaged' "$L" | awk '{print int($1)}')
sel=$(grep -m1 AFFECTED_SUMMARY "$L" | awk '{print int($1)}')
echo "reading=$1 rc=$(cat $O/rc) head=$(sed -n 1p $O/start.txt | cut -c1-90)"
echo "wall_s=$wall cold_derive_s=$sel engaged_at_s=$eng suite_phase_s=$((wall-eng))"
echo "loadavg_start: $(grep loadavg_start $O/start.txt) | $(grep loadavg_end $O/end.txt)"
grep -m1 AFFECTED_SUMMARY "$L" | cut -d' ' -f2-
for a in a b c; do
  s=$(grep -m1 "\[run\] plugins/soleur/test/ci-pr-affected-replay-$a started" "$L" | awk '{print int($1)}')
  e=$(grep -m1 "\[run\] plugins/soleur/test/ci-pr-affected-replay-$a done" "$L")
  echo "replay-$a: start=+${s}s (pool offset $((s-eng))s) $(echo "$e" | sed 's/.*done (//; s/)//')"
done
# seconds with at most one suite live inside the pool phase
awk -v eng="$eng" '/\[run\] .* started \(pid=/{t=int($1); ev[t]++; n++; st[n]=$1; k[n]="s"} /\[run\] .* done \(rc=/{n++; st[n]=$1; k[n]="d"}
 END{live=0; prev=eng; low=0; for(i=1;i<=n;i++){t=st[i]; if(t>eng){ if(live<=1) low+=t-prev; prev=t } else prev=eng; if(k[i]=="s") live++; else live--; } print "seconds_with_at_most_one_suite_live=" int(low) " (after engagement, to last event)"}' "$L"
grep -E '^[0-9.]+ === [0-9]+ suites' "$L" | cut -d' ' -f2- | cut -c1-200
echo "failed:"; grep -E '^[0-9.]+ \[FAIL\]|^[0-9.]+ \[FAILED\]' "$L" | cut -d' ' -f2- | sort -u | cut -c1-120 | head -12
