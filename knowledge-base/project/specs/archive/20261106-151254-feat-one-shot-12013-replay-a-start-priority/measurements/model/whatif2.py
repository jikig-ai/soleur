import sys
S,A=sys.argv[1],sys.argv[2]
exec(open(f"{S}/whatif.py").read().split('for r in ["r1-backfill"')[0].replace("S,A=sys.argv[1],sys.argv[2]","S='%s';A='%s'"%(S,A)))
def hoist(names,jobs):
    return [j for j in jobs if j[0] in names]+[j for j in jobs if j[0] not in names]
def starlast(jobs):
    return [j for j in jobs if "*" not in tok.get(j[0],[])]+[j for j in jobs if "*" in tok.get(j[0],[])]
print("reading  base  hoistA  hoistABC  starlast  hoistABC+starlast  hoistA+starlast  | floor(sum/4)")
for r in ["r1-backfill","r3-backfill","r2-fifo-control"]:
    jobs=load(r); f=lambda j: sim(j)[0]
    print(r, *[f"{f(x):5.0f}" for x in [jobs,hoist(REPL[:1],jobs),hoist(REPL,jobs),starlast(jobs),starlast(hoist(REPL,jobs)),starlast(hoist(REPL[:1],jobs))]], "|", round(sum(x for _,x in jobs)/4))
    print("   stars in selection:",[l for l,_ in jobs if "*" in tok.get(l,[])])
