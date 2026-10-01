#!/usr/bin/env python3
"""A1 v2: also classify Bash file-read/search commands, which carry 93% of
tool-result bytes in this repo (agents are instructed to use cat/sed/grep,
not the Read tool). v1 reported nav_code=0.00% purely as an artifact of that.
"""
import json, sys, re
from collections import defaultdict

CODE_EXT = {'.ts','.tsx','.js','.jsx','.py','.sql','.go','.rs','.java','.rb','.c','.h','.cpp'}
PROSE_EXT = {'.md','.txt','.mdx'}
CONF_EXT = {'.json','.yml','.yaml','.toml','.tf','.env','.example','.lock'}
SH_EXT   = {'.sh','.bash'}
NAV_TOOLS = {'Read','Grep','Glob','NotebookRead'}
# Bash commands that are file reads or code searches
READ_CMD = re.compile(r'\b(cat|head|tail|sed|less|bat|wc)\b')
SEARCH_CMD = re.compile(r'\b(grep|rg|ag|ack|find|fd|git\s+grep|git\s+ls-files)\b')
PATHLIKE = re.compile(r'[\w./~-]*\.[A-Za-z0-9]{1,6}\b')

def ext_of(p):
    m = re.search(r'(\.[A-Za-z0-9]+)$', (p or '').split('?')[0])
    return m.group(1).lower() if m else ''

def classify_ext(e):
    if e in CODE_EXT: return 'code'
    if e in PROSE_EXT: return 'prose'
    if e in CONF_EXT: return 'config'
    if e in SH_EXT: return 'shell'
    return 'unknown'

def bash_kind_and_ext(cmd):
    """Return (kind, dominant_ext) for a bash command, or (None,None) if not nav."""
    if not cmd: return (None, None)
    is_read = bool(READ_CMD.search(cmd))
    is_search = bool(SEARCH_CMD.search(cmd))
    if not (is_read or is_search): return (None, None)
    exts = defaultdict(int)
    for m in PATHLIKE.finditer(cmd):
        e = ext_of(m.group(0))
        if e: exts[e] += 1
    dom = max(exts.items(), key=lambda x: x[1])[0] if exts else ''
    return ('bash_read' if is_read else 'bash_search', dom)

def blocks(msg):
    c = msg.get('content') if isinstance(msg, dict) else None
    return c if isinstance(c, list) else []

def content_len(c):
    if isinstance(c, str): return len(c)
    if isinstance(c, list):
        n=0
        for b in c:
            if isinstance(b, dict):
                if isinstance(b.get('text'), str): n += len(b['text'])
                elif b.get('type')=='image': n += 2000
            elif isinstance(b,str): n += len(b)
        return n
    return 0

def main(paths):
    id2={}; total=0; n=0
    cls=defaultdict(int); navext=defaultdict(int); kindtot=defaultdict(int)
    for fp in paths:
        with open(fp,'r',errors='replace') as f:
            for line in f:
                line=line.strip()
                if not line: continue
                try: rec=json.loads(line)
                except Exception: continue
                msg=rec.get('message')
                if not isinstance(msg,dict): continue
                for b in blocks(msg):
                    if not isinstance(b,dict): continue
                    if b.get('type')=='tool_use':
                        tid=b.get('id')
                        if tid: id2[tid]=(b.get('name',''), b.get('input') if isinstance(b.get('input'),dict) else {})
                    elif b.get('type')=='tool_result':
                        sz=content_len(b.get('content')); total+=sz; n+=1
                        tid=b.get('tool_use_id')
                        if tid not in id2:
                            cls['UNMATCHED']+=sz; continue
                        name,inp=id2[tid]
                        if name in NAV_TOOLS:
                            e=ext_of(inp.get('file_path') or inp.get('path') or inp.get('glob') or '')
                            cls['nav_'+classify_ext(e)]+=sz; navext[e or '(none)']+=sz
                            kindtot['tool_nav']+=sz
                        elif name=='Bash':
                            kind,e=bash_kind_and_ext(inp.get('command',''))
                            if kind:
                                cls['nav_'+classify_ext(e)]+=sz; navext[e or '(none)']+=sz
                                kindtot[kind]+=sz
                            else:
                                cls['bash_other']+=sz; kindtot['bash_other']+=sz
                        else:
                            cls['other_tool']+=sz; kindtot['other_tool']+=sz
    print(f"tool_results={n}  total_result_bytes={total:,}")
    print("\n=== BY CLASS ===")
    for k,v in sorted(cls.items(),key=lambda x:-x[1]):
        print(f"{k:16s} {v:>14,}  {100.0*v/max(total,1):6.2f}%")
    print("\n=== NAV traffic by target ext ===")
    for k,v in sorted(navext.items(),key=lambda x:-x[1])[:14]:
        print(f"{k:14s} {v:>14,}  {100.0*v/max(total,1):6.2f}%")
    codeshare=cls['nav_code']
    print(f"\n>>> A1 REACHABLE SURFACE (nav on CODE files) = {100.0*codeshare/max(total,1):.2f}%  (threshold 15%)")

if __name__=='__main__': main(sys.argv[1:])
