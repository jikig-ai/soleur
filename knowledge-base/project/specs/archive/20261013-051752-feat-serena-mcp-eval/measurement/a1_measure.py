#!/usr/bin/env python3
"""A1 criterion: share of tool_result bytes spent on code navigation Serena could replace.

Maps tool_use_id -> (tool_name, target_path), then attributes each tool_result's
size back to that call. Classifies by target extension.
"""
import json, os, sys, glob, re
from collections import defaultdict

CODE_EXT = {'.ts','.tsx','.js','.jsx','.py','.sql','.go','.rs','.java','.rb','.c','.h','.cpp'}
PROSE_EXT = {'.md','.txt','.mdx'}
CONF_EXT = {'.json','.yml','.yaml','.toml','.tf','.sh','.env','.example'}

NAV_TOOLS = {'Read','Grep','Glob','NotebookRead'}

def ext_of(p):
    if not p: return ''
    m = re.search(r'(\.[A-Za-z0-9]+)$', p.split('?')[0])
    return m.group(1).lower() if m else ''

def target_of(name, inp):
    if not isinstance(inp, dict): return ''
    for k in ('file_path','path','notebook_path','pattern','glob'):
        v = inp.get(k)
        if isinstance(v,str) and v: 
            if k in ('pattern','glob') and name=='Grep':
                # Grep: prefer its path/glob filter for classification
                g = inp.get('glob') or inp.get('path') or ''
                return g if isinstance(g,str) else ''
            return v
    return ''

def blocks(msg):
    if not isinstance(msg, dict): return []
    c = msg.get('content')
    if isinstance(c, list): return c
    return []

def content_len(c):
    if isinstance(c, str): return len(c)
    if isinstance(c, list):
        n = 0
        for b in c:
            if isinstance(b, dict):
                if isinstance(b.get('text'), str): n += len(b['text'])
                elif b.get('type')=='image': n += 2000
            elif isinstance(b, str): n += len(b)
        return n
    return 0

def main(paths):
    id2 = {}                      # tool_use_id -> (name, target)
    by_class = defaultdict(int)   # class -> bytes
    by_tool  = defaultdict(int)
    nav_by_ext = defaultdict(int)
    total_result_bytes = 0
    n_results = 0
    unmatched = 0

    for fp in paths:
        try:
            with open(fp, 'r', errors='replace') as f:
                for line in f:
                    line=line.strip()
                    if not line: continue
                    try: rec = json.loads(line)
                    except Exception: continue
                    msg = rec.get('message')
                    if not isinstance(msg, dict): continue
                    for b in blocks(msg):
                        if not isinstance(b, dict): continue
                        t = b.get('type')
                        if t == 'tool_use':
                            tid = b.get('id')
                            if tid: id2[tid] = (b.get('name',''), target_of(b.get('name',''), b.get('input')))
                        elif t == 'tool_result':
                            tid = b.get('tool_use_id')
                            n = content_len(b.get('content'))
                            total_result_bytes += n; n_results += 1
                            if tid not in id2:
                                unmatched += n; by_class['UNMATCHED'] += n; continue
                            name, tgt = id2[tid]
                            by_tool[name] += n
                            if name in NAV_TOOLS:
                                e = ext_of(tgt)
                                nav_by_ext[e or '(none)'] += n
                                if e in CODE_EXT: by_class['nav_code'] += n
                                elif e in PROSE_EXT: by_class['nav_prose'] += n
                                elif e in CONF_EXT: by_class['nav_config'] += n
                                else: by_class['nav_unknown'] += n
                            else:
                                by_class['other_tool'] += n
        except Exception as ex:
            print(f"ERR {fp}: {ex}", file=sys.stderr)

    print(f"tool_results={n_results}  total_result_bytes={total_result_bytes}")
    print()
    print("=== BY CLASS ===")
    for k,v in sorted(by_class.items(), key=lambda x:-x[1]):
        print(f"{k:16s} {v:>14,}  {100.0*v/max(total_result_bytes,1):6.2f}%")
    print()
    print("=== TOP TOOLS by result bytes ===")
    for k,v in sorted(by_tool.items(), key=lambda x:-x[1])[:12]:
        print(f"{k:22s} {v:>14,}  {100.0*v/max(total_result_bytes,1):6.2f}%")
    print()
    print("=== NAV tool results by target ext ===")
    for k,v in sorted(nav_by_ext.items(), key=lambda x:-x[1])[:15]:
        print(f"{k:14s} {v:>14,}  {100.0*v/max(total_result_bytes,1):6.2f}%")

if __name__ == '__main__':
    main(sys.argv[1:])
