#!/usr/bin/env python3
"""S7b J0 reach probe, instrumentation step (SANDBOX COPY ONLY; never run against a live checkout).

    python3 -I j0-instrument.py <sandbox root> <stubs.txt from j0-stubs.py> <fallback log path>

For each stub definition site printed by j0-stubs.py it inserts ONE marker line at the top of the stub:

    [ -p /dev/stdin ] && echo "<file>:<line>|<verb>|$*" >> "${S7B_REACH_LOG:-<fallback>}"

(dash-safe: no [[ ]], no here-strings). The marker records only when stdin of the stub is a pipe.
Sites that are not stub definitions (real functions in non-test files, `rc` text, helper-call text) are skipped
and listed. Line numbers in the marker tag are the ORIGINAL line numbers.
"""
import re
import sys
import os

root, stubs_file, fallback = sys.argv[1:4]
SKIP_VERBS = {'rc'}
sites = {}  # path -> list of (lineno, kind, verb)
verb = None
for raw in open(stubs_file):
    if raw.startswith('## '):
        verb = raw.rstrip('\n').split(' :: ')[1]
        continue
    m = re.match(r'\s+(\S+?):(\d+) \[(\w+)\] (.*)', raw)
    if not m or verb in SKIP_VERBS:
        continue
    path, ln, kind, text = m.group(1), int(m.group(2)), m.group(3), m.group(4)
    sites.setdefault(path, set()).add((ln, kind, verb))

def marker(path, ln, verb, escape):
    s = '[ -p /dev/stdin ] && echo "%s:%d|%s|$*" >> "${S7B_REACH_LOG:-%s}"' % (os.path.basename(path), ln, verb, fallback)
    return s.replace('$', '\\$') if escape else s

done, skipped = [], []
for path, items in sorted(sites.items()):
    full = os.path.join(root, path)
    if not os.path.exists(full):
        skipped.append((path, 0, 'missing'))
        continue
    lines = open(full, errors='surrogateescape').read().split('\n')
    edits = {}  # index -> new text, or ('after', index, text)
    inserts = []  # (after_index, text)
    for ln, kind, verb in sorted(items):
        i = ln - 1
        l = lines[i]
        base = os.path.basename(path)
        is_test = base.endswith('.test.sh') or base.startswith('test-') or '/test/' in path or base.endswith('harness.sh') or 'stub-world' in base
        if kind == 'helper' and not re.search(r'\b(mkstub|make_stub|write_stub|stub_cmd)\b.*<<', l):
            skipped.append((path, ln, 'helper-text'))
            continue
        if kind == 'fn':
            if not is_test:
                skipped.append((path, ln, 'real-function'))
                continue
            m = re.search(r'\b%s\(\)\s*\{' % re.escape(verb), l)
            if not m:
                skipped.append((path, ln, 'fn-no-match'))
                continue
            lines[i] = l[:m.end()] + ' ' + marker(path, ln, verb, False) + ';' + l[m.end():]
            done.append((path, ln, verb, 'fn'))
            continue
        # kind path / helper
        if '<<' in l:
            unq = not re.search(r"<<-?\s*[\\]?['\"]", l)
            nxt = i + 1
            at = i
            if nxt < len(lines) and lines[nxt].startswith('#!'):
                at = nxt
            elif re.search(r'mkstub', l):
                at = i  # prelude supplies the shebang
            inserts.append((at, marker(path, ln, verb, unq)))
            done.append((path, ln, verb, 'heredoc' + ('-unquoted' if unq else '')))
        elif "'#!/usr/bin/env bash' " in l:
            lines[i] = l.replace("'#!/usr/bin/env bash' ", "'#!/usr/bin/env bash' '%s' " % marker(path, ln, verb, False), 1)
            done.append((path, ln, verb, 'printf-args'))
        elif re.search(r"printf '#!/(bin/sh|usr/bin/env bash)\\n", l):
            lines[i] = re.sub(r"(printf '#!/(?:bin/sh|usr/bin/env bash)\\n)", lambda mm: mm.group(1) + marker(path, ln, verb, False) + '\\n', l, count=1)
            done.append((path, ln, verb, 'printf-fmt'))
        else:
            skipped.append((path, ln, 'unrecognised'))
    for at, text in sorted(inserts, reverse=True):
        lines.insert(at + 1, text)
    open(full, 'w', errors='surrogateescape').write('\n'.join(lines))
for d in done:
    print('INSTR', *d)
for s in skipped:
    print('SKIP', *s)
