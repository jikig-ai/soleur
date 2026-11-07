#!/usr/bin/env bash
# derive.sh <name> — figures from a reading's stamped log (/var/tmp/m12231/<name>/run.log). Also writes
# /var/tmp/m12231/<name>/suites.tsv (label, start_s, end_s, rc; no header). The committed <name>.suites.tsv, .timing.tsv and
# .notes.txt in this directory were copied from there by hand (suites.tsv with a header row added).
O=/var/tmp/m12231/${1:?usage: derive.sh <name>}; L=$O/run.log
wall=$(tail -1 "$L" | awk '{print int($1)}')
eng=$(grep -m1 '\[parallel\] mode engaged' "$L" | awk '{print int($1)}')
sel=$(grep -m1 AFFECTED_SUMMARY "$L" | awk '{print int($1)}')
echo "reading=$1 rc=$(cat $O/rc) head=$(sed -n 1p $O/start.txt | cut -c1-90)"
echo "wall_s=$wall cold_derive_s=${sel:-n/a} engaged_at_s=${eng:-n/a} pool_phase_s=$([ -n "$eng" ] && echo $((wall-eng)) || echo n/a)"
echo "loadavg_start: $(grep loadavg_start $O/start.txt) | $(grep loadavg_end $O/end.txt)"
echo "foreign_start: $(grep foreign_test_all_start $O/start.txt | cut -c1-120) | foreign_end: $(grep foreign_test_all_end $O/end.txt | cut -c1-120)"
grep -m1 AFFECTED_SUMMARY "$L" | cut -d' ' -f2-
for a in a b c; do
  s=$(grep -m1 "\[run\] plugins/soleur/test/ci-pr-affected-replay-$a started" "$L" | awk '{print int($1)}')
  e=$(grep -m1 "\[run\] plugins/soleur/test/ci-pr-affected-replay-$a done" "$L")
  en=$(echo "$e" | awk '{print int($1)}')
  echo "replay-$a: start=+${s}s (pool offset $((s-eng))s) end=+${en}s $(echo "$e" | sed 's/.*done (//; s/)//')"
done
# per-suite start/end offsets
awk 'match($0,/\[run\] .* started \(pid=/){lab=$0; sub(/^[0-9.]+ \[run\] /,"",lab); sub(/ started.*/,"",lab); s[lab]=int($1)}
     match($0,/\[run\] .* done \(rc=/){lab=$0; sub(/^[0-9.]+ \[run\] /,"",lab); sub(/ done.*/,"",lab); rc=$0; sub(/.*done \(rc=/,"",rc); sub(/[,)].*/,"",rc); print lab "\t" s[lab] "\t" int($1) "\t" rc}' "$L" >"$O/suites.tsv"
# seconds with at most one suite live inside the pool phase, and idle slot-seconds (width 4)
awk -v eng="$eng" 'match($0,/\[run\] .* started \(pid=/){n++; st[n]=$1; k[n]="s"} match($0,/\[run\] .* done \(rc=/){n++; st[n]=$1; k[n]="d"}
 END{live=0; prev=eng; low=0; idle=0; for(i=1;i<=n;i++){t=st[i]; if(t>eng){ if(live<=1) low+=t-prev; idle+=(4-live)*(t-prev); prev=t } if(k[i]=="s") live++; else live--; }
 print "seconds_with_at_most_one_suite_live=" int(low) " idle_slot_seconds=" int(idle) " (after engagement, to last event)"}' "$L"
# the star suites: when they started and what else was live. The label list is the six declared `*` overrides of
# scripts/lib/test-suite-lanes.sh at the measured trees; a derived `*` (unreadable source) is not listed here.
awk 'match($0,/\[run\] .* started \(pid=/){lab=$0; sub(/^[0-9.]+ \[run\] /,"",lab); sub(/ started.*/,"",lab); live[lab]=1; if(lab ~ /test-all-capacity-signal|orphan-process-reaper|md-to-mrkdwn|cf-tunnel-liveness|run-registered-suites/){n=0; for(x in live) if(x!=lab) n++; print "star " lab " started +" int($1) "s with " n " other suite(s) live"}}
     match($0,/\[run\] .* done \(rc=/){lab=$0; sub(/^[0-9.]+ \[run\] /,"",lab); sub(/ done.*/,"",lab); delete live[lab]}' "$L"
grep -E '^[0-9.]+ === [0-9]+ suites' "$L" | cut -d' ' -f2- | cut -c1-200
echo "failed:"; grep -E '^[0-9.]+ \[FAIL\]|^[0-9.]+ \[FAILED\]' "$L" | cut -d' ' -f2- | sort -u | cut -c1-120 | head -12
