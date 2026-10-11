#!/usr/bin/env python3
"""S7b J0 helper (read-only): for each Funnel A pair print where the verb is stubbed.

Run from the repo root:  python3 -I <this file> [pairs-file]
Reuses the definitions of j0-derive.py (imported by path) so the pair set is the same.
For each (test file, verb) it prints every stub definition site: file:line, kind
(fn | path | helper), and the source line, in the suite itself and in sourced files (one hop).
"""
import importlib.util
import os
import re
import sys
import collections

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('j0', os.path.join(here, 'j0-derive.py'))
j0 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j0)

def sites(path, verb):
    out = []
    try:
        lines = open(path, errors='replace').read().split('\n')
    except OSError:
        return out
    for i, l in enumerate(lines, 1):
        if l.lstrip().startswith('#'):
            continue
        for m in j0.FN.finditer(l):
            if m.group(1) == verb:
                out.append((path, i, 'fn', l.strip()[:110]))
        for m in j0.PATHFILE.finditer(l):
            if m.group(1) == verb:
                out.append((path, i, 'path', l.strip()[:110]))
        for m in j0.HELPER.finditer(l):
            if m.group(1) == verb:
                out.append((path, i, 'helper', l.strip()[:110]))
    return out

def main():
    pairs = []
    for line in open(sys.argv[1]):
        p = line.rstrip('\n').split('\t')
        if len(p) >= 2 and not line.startswith(('J0', ' ', 'PAIRS')):
            pairs.append((p[0], p[1]))
    files = j0.tracked()
    by_base = collections.defaultdict(list)
    for f in files:
        by_base[f.rsplit('/', 1)[-1]].append(f)
    for t, w in pairs:
        print(f'## {t} :: {w}')
        found = sites(t, w)
        code = '\n'.join(j0.code_lines(t))
        for ref in j0.SOURCED.findall(code):
            c = by_base.get(ref.rsplit('/', 1)[-1], [])
            if len(c) == 1 and c[0] != t and c[0].endswith('.sh'):
                found += sites(c[0], w)
        for s in found:
            print(f'   {s[0]}:{s[1]} [{s[2]}] {s[3]}')
        if not found:
            print('   (none found)')
main()
