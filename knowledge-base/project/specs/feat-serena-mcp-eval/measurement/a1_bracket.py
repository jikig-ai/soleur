#!/usr/bin/env python3
"""Bracket A1: LOWER = dominant-ext (v2). UPPER = count a nav result as 'code'
if ANY code-extension path appears anywhere in the command/input (deliberately
over-generous: a command touching both a .ts and 5 .md files counts as code)."""
import json,sys,re
from collections import defaultdict
# NOTE: this script matches extensions via CODE_TOKEN below, not a set membership
# test. Keep the two in sync -- an earlier revision omitted c|h here while listing
# them in a (dead) CODE_EXT set; measured impact of that gap was 309 bytes.
NAV_TOOLS={'Read','Grep','Glob','NotebookRead'}
READ_CMD=re.compile(r'\b(cat|head|tail|sed|less|bat|wc)\b')
SEARCH_CMD=re.compile(r'\b(grep|rg|ag|ack|find|fd)\b|\bgit\s+(grep|ls-files)\b')
CODE_TOKEN=re.compile(r'\.(ts|tsx|js|jsx|py|sql|go|rs|java|rb|cpp|c|h)\b')
def blocks(m):
    c=m.get('content') if isinstance(m,dict) else None
    return c if isinstance(c,list) else []
def clen(c):
    if isinstance(c,str): return len(c)
    if isinstance(c,list):
        n=0
        for b in c:
            if isinstance(b,dict):
                if isinstance(b.get('text'),str): n+=len(b['text'])
                elif b.get('type')=='image': n+=2000
            elif isinstance(b,str): n+=len(b)
        return n
    return 0
id2={};tot=0;upper=0;navtot=0
for fp in sys.argv[1:]:
    for line in open(fp,'r',errors='replace'):
        line=line.strip()
        if not line: continue
        try: r=json.loads(line)
        except: continue
        m=r.get('message')
        if not isinstance(m,dict): continue
        for b in blocks(m):
            if not isinstance(b,dict): continue
            if b.get('type')=='tool_use':
                if b.get('id'): id2[b['id']]=(b.get('name',''),b.get('input') if isinstance(b.get('input'),dict) else {})
            elif b.get('type')=='tool_result':
                sz=clen(b.get('content')); tot+=sz
                tid=b.get('tool_use_id')
                if tid not in id2: continue
                name,inp=id2[tid]
                blob=''
                isnav=False
                if name in NAV_TOOLS:
                    isnav=True; blob=' '.join(str(v) for v in inp.values())
                elif name=='Bash':
                    cmd=inp.get('command','')
                    if READ_CMD.search(cmd) or SEARCH_CMD.search(cmd):
                        isnav=True; blob=cmd
                if isnav:
                    navtot+=sz
                    if CODE_TOKEN.search(blob): upper+=sz
print(f"total_result_bytes={tot:,}")
print(f"all navigation traffic     = {100.0*navtot/tot:6.2f}%")
print(f"A1 UPPER BOUND (any code ext mentioned) = {100.0*upper/tot:6.2f}%   (threshold 15%)")
