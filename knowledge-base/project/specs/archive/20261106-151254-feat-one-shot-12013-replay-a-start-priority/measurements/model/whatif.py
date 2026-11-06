import sys
S,A=sys.argv[1],sys.argv[2]
exec(open(f"{S}/sim.py").read().split('if __name__')[0].replace("S=sys.argv[1]; A=sys.argv[2]","S='%s';A='%s'"%(S,A)))
# committed weights
w={}
for f in ("scripts/suite-durations.tsv","scripts/suite-durations-heavy.tsv"):
    for l in open("/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-12013-replay-a-start-priority/"+f):
        if l.startswith("#") or not l.strip(): continue
        p=l.rstrip("\n").split("\t")
        if len(p)>=2 and p[1].isdigit(): w[p[0]]=int(p[1])/1000.0
REPL=["plugins/soleur/test/ci-pr-affected-replay-%s"%x for x in "abc"]
def run(name,jobs,width=4):
    T,st,en=sim(jobs,width); ri={l:i for i,(l,_) in enumerate(jobs)}
    print(f"  {name:44s} pool={T:6.0f}  replay-a start={st[ri[REPL[0]]]:6.0f}")
    return T
for r in ["r1-backfill","r3-backfill","r2-fifo-control"]:
    jobs=load(r); print(r,"sum",round(sum(x for _,x in jobs)),"sum/4",round(sum(x for _,x in jobs)/4))
    run("baseline (registration order)",jobs)
    def hoist(names,jobs): 
        h=[j for j in jobs if j[0] in names]; o=[j for j in jobs if j[0] not in names]; return h+o
    run("hoist replay-a",hoist([REPL[0]],jobs))
    run("hoist replay-a,b,c",hoist(REPL,jobs))
    heavy=REPL+["apps/web-platform/test/approval-guard1-mutation","scripts/lint-shell-trace-credential-refusal","tests/scripts/argv-bearer-sweep","apps/web-platform/test/destroy-ask-mutation"]
    run("hoist top-7 by measured wall",hoist(heavy,jobs))
    # LPT by committed weight (stable)
    lw=sorted(range(len(jobs)),key=lambda i:-w.get(jobs[i][0],0.0))
    run("LPT by committed weights (full reorder)",[jobs[i] for i in lw])
    lm=sorted(range(len(jobs)),key=lambda i:-jobs[i][1])
    run("LPT by measured wall (oracle, full reorder)",[jobs[i] for i in lm])
    # committed weights present for the replay arms?
    print("  committed weights a/b/c:",[w.get(x) for x in REPL])
    # width 8 oracle for reference
    run("baseline @ width 8 (reference only)",jobs,8)

print("---- timeline r1, hoist a,b,c")
jobs=load("r1-backfill")
h=[j for j in jobs if j[0] in REPL]; o=[j for j in jobs if j[0] not in REPL]; J=h+o
T,st,en=sim(J)
for i,(l,x) in enumerate(J):
    if x>150 or "*" in tok.get(l,[]): print(f"  {i:3d} {l[:60]:60s} wall={x:6.0f} start={st[i]:6.0f} end={en[i]:6.0f} tok={tok.get(l)}")
# idle slot-seconds
busy=sum(x for _,x in J); print("  busy",round(busy),"capacity",round(T*4),"idle slot-s",round(T*4-busy))
print("---- barrier-last variant (move * suites to end) + hoist")
star=[j for j in J if "*" in tok.get(j[0],[])]; non=[j for j in J if "*" not in tok.get(j[0],[])]
T2,st2,en2=sim(non+star); print("  pool",round(T2))
