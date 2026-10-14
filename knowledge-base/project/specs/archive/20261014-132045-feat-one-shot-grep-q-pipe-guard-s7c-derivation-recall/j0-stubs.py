#!/usr/bin/env python3
"""S7c J0 helper (read-only): for each (test file, verb) pair print where the verb is stubbed.

Copied from the S7b tool (commit 6e320b391e) and re-pointed at the S7c j0-derive.py names
(FNRE, PATHRE, HELPRE, FORRE, helper_defs, SRCRE). Run from the repo root:

    python3 -I <this file> <pairs-file>      # pairs-file lines: test<TAB>verb[<TAB>producers]

For each pair it prints every stub definition site: file:line, kind (fn | path | helper | helperarg | loop)
and the source line, in the suite itself and in the files it sources (one hop). The kinds feed
j0-instrument.py, which marks fn, path and heredoc-helper sites and skips the rest (helperarg, loop).
"""
import collections
import importlib.util
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('j0', os.path.join(here, 'j0-derive.py'))
j0 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(j0)


def code(path):
    try:
        return open(path, errors='replace').read().split('\n')
    except OSError:
        return []


def sites(path, verb):
    out = []
    raw = code(path)
    hd = j0.helper_defs(raw)
    for i, l in enumerate(raw, 1):
        if l.lstrip().startswith('#'):
            continue
        s = l.strip()[:110]
        m = j0.FNRE.match(l)
        if m and m.group(2) == verb:
            out.append((path, i, 'fn', s))
        if '>' in l and ('cat' in l or 'printf' in l):
            for m in j0.PATHRE.finditer(l):
                if m.group(2) == verb:
                    out.append((path, i, 'path', s))
        if 'stub' in l:
            for m in j0.HELPRE.finditer(l):
                if re.sub(r'^' + j0.HELPERS + r'[ \t]+"?', '', m.group(0)) == verb:
                    out.append((path, i, 'helper', s))
        toks = l.split()
        if toks and toks[0] in hd:
            for k in hd[toks[0]]:
                if k <= len(toks) - 1 and toks[k].strip('"\'') == verb:
                    out.append((path, i, 'helperarg', s))
        m = j0.FORRE.match(l)
        if m and verb in [w.strip('"\'') for w in m.group(2).split()]:
            body = '\n'.join(raw[i:i + 15])
            if re.search(r'(cat|printf)[^\n|]*>>?[ \t]*"?[^ "\n]*/(\$' + m.group(1) + r'|\$\{' + m.group(1) + r'\})', body) or re.search(r'stub', body):
                out.append((path, i, 'loop', s))
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
        refs = []
        for line in code(t):
            if re.match(r'^[ \t]*(\.|source)[ \t]', line) and not line.lstrip().startswith('#'):
                m = j0.SRCRE.match(line)
                if m:
                    refs.append(m.group(1))
        seen = set()
        for ref in refs:
            c = by_base.get(ref.rsplit('/', 1)[-1], [])
            if len(c) == 1 and c[0] != t and c[0].endswith('.sh') and c[0] not in seen:
                seen.add(c[0])
                found += sites(c[0], w)
        for s in found:
            print(f'   {s[0]}:{s[1]} [{s[2]}] {s[3]}')
        if not found:
            print('   (none found)')


main()
