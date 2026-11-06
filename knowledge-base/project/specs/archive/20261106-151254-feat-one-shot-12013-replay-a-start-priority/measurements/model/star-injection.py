# usage: python3 schedule-model-star-injection.py <dir-with-schedule-model-whatif.py,tokens.tsv,enum.txt> <measurements-dir>
# Injects extra `*` (drain-barrier) suites that other diffs would select, at their registration positions,
# and compares baseline vs the replay arms hoisted to the first registrations. Walls of the injected suites are ASSUMED.
import sys
S,A=sys.argv[1],sys.argv[2]
exec(open(f"{S}/whatif.py").read().split('for r in ["r1-backfill"')[0].replace("S,A=sys.argv[1],sys.argv[2]","S='%s';A='%s'"%(S,A)))
rows=[l.split("\t")[1] for l in open(S+"/enum.txt") if l.startswith("SUITE_COMMAND\t")]
pos={r:i for i,r in enumerate(rows)}
def inject(jobs,extra):
    allj=jobs+extra; allj.sort(key=lambda j: pos.get(j[0],10**6)); return allj
def hoist(names,jobs):
    return [j for j in jobs if j[0] in names]+[j for j in jobs if j[0] not in names]
for r in ["r1-backfill","r3-backfill"]:
    base=load(r)
    for name,extra in [("none",[]),("+orphan-process-reaper (60s)",[("scripts/orphan-process-reaper",60.0)]),("+orphan-reaper(60)+mutations(120)",[("scripts/orphan-process-reaper",60.0),("scripts/orphan-process-reaper-mutations",120.0)]),("+md-to-mrkdwn (30s)",[("scripts/md-to-mrkdwn",30.0)])]:
        j=inject(list(base),list(extra))
        b=sim(j)[0]; h=sim(hoist(REPL,j))[0]
        print(f"{r:12s} {name:36s} baseline={b:6.0f} hoistABC={h:6.0f} delta={h-b:+6.0f}")
