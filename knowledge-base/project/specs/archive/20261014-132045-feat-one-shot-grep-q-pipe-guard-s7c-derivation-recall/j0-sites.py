#!/usr/bin/env python3
"""S7c J0 helper (read-only): for each pair print the non-test pipe sites (file:line: text).

Copied from the S7b tool (commit 6e320b391e) and widened to the S7c arms: it reads the producer files through the
same logical-line join (R1), annotation strip (R8), quote-parity bar scan (R3) and wrapper unwrap (R2) as j0-derive.py,
so a site is printed whenever any arm would read it as `... | VERB`. Run from the repo root:

    python3 -I <this file> <pairs-file>        # lines: test<TAB>verb<TAB>producer,producer
"""
import importlib.util
import os
import re
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
        raw = j0.read(f).split('\n')
        for ln, l in j0.logical_lines(raw, True):
            if re.match(r'^[ \t]*#', l):
                continue
            l = j0.ANNOT_STR.sub('', l)
            if '|' not in l:
                continue
            hit = False
            for m in re.finditer(r'(?<![|\\])\|(?!\|)&?', l):
                after = l[m.end():]
                if not j0.outside_quotes(l[:m.start()]) or j0.CASE_ALT.match(after):
                    continue
                if w in j0.unwrap(after):
                    hit = True
            if not hit:
                # the base text-pipe regex also reads a bar inside a command substitution or a quoted string (it has no quote parity)
                rest = l
                while True:
                    m = j0.PIPE.search(rest)
                    if not m:
                        break
                    rest = rest[m.end():]
                    if m.group(6) == w or w in j0.unwrap(m.group(6) + ' ' + rest.split('|')[0]):
                        hit = True
                        break
            if hit:
                print(f'   {f}:{ln}: {l.strip()[:200]}')
