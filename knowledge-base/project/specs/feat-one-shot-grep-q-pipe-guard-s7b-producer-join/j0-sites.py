#!/usr/bin/env python3
"""S7b J0 helper (read-only): for each Funnel A pair print the non-test pipe sites (file:line: text).

Run from the repo root:  python3 -I <this file> <j0 output file>
Same PIPE/pipefail/observed rules as j0-derive.py (imported by path).
"""
import importlib.util
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('j0', os.path.join(here, 'j0-derive.py'))
j0 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j0)

for line in open(sys.argv[1]):
    p = line.rstrip('\n').split('\t')
    if len(p) < 3 or line.startswith(('J0', ' ', 'PAIRS')):
        continue
    t, w, fs = p[0], p[1], p[2].split(',')
    print(f'## {t} :: {w}')
    for f in fs:
        raw = open(f, errors='replace').read().split('\n')
        for i, l in enumerate(raw, 1):
            if l.lstrip().startswith('#'):
                continue
            for m in j0.PIPE.finditer(l):
                if m.group(1) == w:
                    print(f'   {f}:{i}: {l.strip()[:170]}')
