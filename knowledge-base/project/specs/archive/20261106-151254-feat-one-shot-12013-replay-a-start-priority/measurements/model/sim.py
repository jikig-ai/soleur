import sys, csv, heapq
S=sys.argv[1]; A=sys.argv[2]
tok={}
for l in open(f"{S}/tokens.tsv"):
    p=l.rstrip("\n").split("\t"); tok[p[0]]=p[1].split() if len(p)>1 else []
def load(r):
    rows=[]
    for l in open(f"{A}/{r}.timing.tsv"):
        p=l.rstrip("\n").split("\t")
        if len(p)<3 or p[0].startswith("__"): continue
        if p[2].startswith("skip"): continue
        rows.append((p[0],int(p[1])/1000.0))
    return rows
def conflict(a,b):
    if not a and not b: return False
    if "*" in a or "*" in b: return True
    return bool(set(a)&set(b))
def sim(jobs,width=4,order=None):
    # jobs: list of (label,wall) in registration order. streaming registration w/ backfill (registration blocks only when saturated).
    # order: function giving priority ordering of the *queue* (None = registration order); here modelled as full-knowledge lookahead if 'buffer'.
    n=len(jobs); toks=[tok.get(l,["*"]) for l,_ in jobs]
    t=0.0; live=[] # (end, idx)
    queue=[]; nxt=0; start=[None]*n; end=[None]*n
    def fill():
        nonlocal live,queue
        live_tok=[x for _,i in live for x in toks[i]]
        rest=[]; skip=[]; anyq=False
        for i in queue:
            if len(live)>=width: rest.append(i); continue
            tk=toks[i]; ok=True
            if "*" in tk:
                ok = (len(live)==0 and not anyq)
            else:
                if conflict(tk,live_tok): ok=False
                if ok and anyq and conflict(tk,skip): ok=False
            if ok:
                start[i]=t; e=t+jobs[i][1]; end[i]=e; heapq.heappush(live,(e,i)); live_tok+=tk
            else:
                rest.append(i); anyq=True; skip+=tk
        queue=rest
    def reap():
        nonlocal t,live
        e,i=heapq.heappop(live); t=max(t,e)
    while nxt<n or queue or live:
        if nxt<n:
            queue.append(nxt); nxt+=1; fill()
            while len(live)>=width:
                reap(); fill()
        else:
            if not live: fill(); 
            if not live and queue: break
            reap(); fill()
    return t,start,end
def sim_buffered(jobs,key,width=4):
    # all registered first (instant), queue sorted by key but respecting registration order among conflicting suites
    n=len(jobs); toks=[tok.get(l,["*"]) for l,_ in jobs]
    t=0.0; live=[]; start=[None]*n; end=[None]*n
    pending=sorted(range(n),key=key)
    while pending or live:
        live_tok=[x for _,i in live for x in toks[i]]
        newp=[]; 
        for pos,i in enumerate(pending):
            if len(live)>=width: newp.append(i); continue
            tk=toks[i]; ok=True
            if "*" in tk: ok=(len(live)==0 and all(False for _ in []) )
            else:
                if conflict(tk,live_tok): ok=False
            # no overtaking of an earlier-registered conflicting suite still pending
            if ok:
                for j in pending[:pos]:
                    if j<i and j in set(pending) and j not in set(x for _,x in live) and start[j] is None:
                        if conflict(tk,toks[j]) or "*" in toks[j]: ok=False;break
            if "*" in tk and ok:
                ok = all(start[j] is not None for j in range(i))   # simplified barrier
            if ok:
                start[i]=t; e=t+jobs[i][1]; end[i]=e; heapq.heappush(live,(e,i)); live_tok+=tk
            else: newp.append(i)
        pending=newp
        if live:
            e,i=heapq.heappop(live); t=max(t,e)
        elif pending: break
    return t,start,end
if __name__=="__main__":
    r=sys.argv[3]; jobs=load(r)
    n=len(jobs)
    T,st,en=sim(jobs); 
    ri={l:i for i,(l,_) in enumerate(jobs)}
    print(r,"jobs",n,"sum",round(sum(w for _,w in jobs)),"model pool phase",round(T))
    for l in ["plugins/soleur/test/ci-pr-affected-replay-a"]:
        print(" replay-a model start",round(st[ri[l]]),"end",round(en[ri[l]]))
    # lock:test-all chain
    chain=sum(w for (l,w) in jobs if "lock:test-all" in tok.get(l,[]) or "*" in tok.get(l,[]))
    print(" lock:test-all/* chain sum",round(chain),"n",sum(1 for (l,w) in jobs if "lock:test-all" in tok.get(l,[]) or "*" in tok.get(l,[])))
